defmodule PaperForge.PDF.Syntax do
  @moduledoc false
  alias PaperForge.Reference

  @white [0, 9, 10, 12, 13, 32]
  @delimiters @white ++ [?(, ?), ?<, ?>, ?[, ?], ?/, ?%]

  def fail(reason), do: throw({:pdf_error, reason})

  def skip(<<c, rest::binary>>) when c in @white, do: skip(rest)

  def skip(<<"%", rest::binary>>) do
    case :binary.match(rest, ["\n", "\r"]) do
      {n, _} -> skip(binary_part(rest, n + 1, byte_size(rest) - n - 1))
      :nomatch -> ""
    end
  end

  def skip(source), do: source

  def word(source) do
    source = skip(source)
    take_word(source, [])
  end

  defp take_word(<<c, rest::binary>>, acc) when c not in @delimiters,
    do: take_word(rest, [c | acc])

  defp take_word(rest, acc), do: {acc |> Enum.reverse() |> :erlang.list_to_binary(), rest}

  def integer(source) do
    {token, rest} = word(source)

    case Integer.parse(token) do
      {n, ""} -> {n, rest}
      _ -> fail(:invalid_pdf_integer)
    end
  end

  def value(source, max_depth \\ 100), do: read(skip(source), 0, max_depth)

  defp read(_, depth, limit) when depth > limit, do: fail({:max_depth_exceeded, limit})

  defp read(<<"<<", rest::binary>>, depth, limit),
    do: dictionary(skip(rest), %{}, depth + 1, limit)

  defp read(<<"[", rest::binary>>, depth, limit), do: array(skip(rest), [], depth + 1, limit)
  defp read(<<"(", rest::binary>>, _, limit), do: literal(rest, 1, [], limit)

  defp read(<<"/", rest::binary>>, _, _) do
    {name, rest} = take_word(rest, [])

    name =
      Regex.replace(~r/#([0-9a-fA-F]{2})/, name, fn _, hex -> <<String.to_integer(hex, 16)>> end)

    {{:name, name}, rest}
  end

  defp read(<<"<", rest::binary>>, _, _) do
    case :binary.match(rest, ">") do
      {n, 1} ->
        hex =
          rest
          |> binary_part(0, n)
          |> :binary.bin_to_list()
          |> Enum.reject(&(&1 in @white))
          |> :erlang.list_to_binary()

        hex = if rem(byte_size(hex), 2) == 1, do: hex <> "0", else: hex

        case Base.decode16(hex, case: :mixed) do
          {:ok, data} -> {{:hex_string, data}, binary_part(rest, n + 1, byte_size(rest) - n - 1)}
          :error -> fail(:invalid_pdf_hex_string)
        end

      :nomatch ->
        fail(:unterminated_pdf_hex_string)
    end
  end

  defp read(source, _, _) do
    {token, rest} = word(source)

    case token do
      "true" -> {true, rest}
      "false" -> {false, rest}
      "null" -> {nil, rest}
      "" -> fail(:invalid_pdf_value)
      _ -> number_or_reference(token, rest)
    end
  end

  defp number_or_reference(token, rest) do
    cond do
      Regex.match?(~r/^[+-]?\d+$/, token) ->
        n = String.to_integer(token)
        {second, remaining} = word(rest)
        {third, tail} = word(remaining)

        if n >= 0 and Regex.match?(~r/^\d+$/, second) and third == "R" do
          generation = String.to_integer(second)
          if generation > 65535, do: fail(:invalid_object_generation)
          {Reference.new(n, generation), tail}
        else
          {n, rest}
        end

      Regex.match?(~r/^[+-]?(\d+\.\d*|\.\d+)$/, token) ->
        normalized =
          token |> String.replace(~r/^([+-]?)\./, "\\g{1}0.") |> String.replace(~r/\.$/, ".0")

        normalized = String.trim_leading(normalized, "+")
        {String.to_float(normalized), rest}

      true ->
        fail({:unsupported_pdf_token, token})
    end
  end

  defp dictionary(<<">>", rest::binary>>, acc, _, _), do: {acc, rest}

  defp dictionary(<<"/", _::binary>> = source, acc, depth, limit) do
    {{:name, key}, rest} = read(source, depth, limit)
    {value, rest} = read(skip(rest), depth, limit)
    dictionary(skip(rest), Map.put(acc, key, value), depth, limit)
  end

  defp dictionary(_, _, _, _), do: fail(:invalid_pdf_dictionary)

  defp array(<<"]", rest::binary>>, acc, _, _), do: {Enum.reverse(acc), rest}

  defp array(source, acc, depth, limit) do
    {value, rest} = read(source, depth, limit)
    array(skip(rest), [value | acc], depth, limit)
  end

  defp literal(_, depth, _, limit) when depth > limit, do: fail({:max_depth_exceeded, limit})
  defp literal(<<>>, _, _, _), do: fail(:unterminated_pdf_string)

  defp literal(<<"\\\r\n", rest::binary>>, depth, acc, limit),
    do: literal(rest, depth, acc, limit)

  defp literal(<<"\\", c, rest::binary>>, depth, acc, limit) when c in [10, 13],
    do: literal(rest, depth, acc, limit)

  defp literal(<<"\\", c, rest::binary>>, depth, acc, limit) when c in ?0..?7 do
    {digits, rest} = octal(rest, [c], 2)
    byte = Bitwise.band(String.to_integer(digits, 8), 255)
    literal(rest, depth, [<<byte>> | acc], limit)
  end

  defp literal(<<"\\", c, rest::binary>>, depth, acc, limit) do
    c = Map.get(%{?n => 10, ?r => 13, ?t => 9, ?b => 8, ?f => 12}, c, c)
    literal(rest, depth, [<<c>> | acc], limit)
  end

  defp literal(<<"(", rest::binary>>, depth, acc, limit),
    do: literal(rest, depth + 1, ["(" | acc], limit)

  defp literal(<<")", rest::binary>>, 1, acc, _),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp literal(<<")", rest::binary>>, depth, acc, limit),
    do: literal(rest, depth - 1, [")" | acc], limit)

  defp literal(<<"\r\n", rest::binary>>, depth, acc, limit),
    do: literal(rest, depth, ["\n" | acc], limit)

  defp literal(<<"\r", rest::binary>>, depth, acc, limit),
    do: literal(rest, depth, ["\n" | acc], limit)

  defp literal(<<c, rest::binary>>, depth, acc, limit),
    do: literal(rest, depth, [<<c>> | acc], limit)

  defp octal(<<c, rest::binary>>, acc, n) when c in ?0..?7 and n > 0,
    do: octal(rest, acc ++ [c], n - 1)

  defp octal(rest, acc, _), do: {:erlang.list_to_binary(acc), rest}
end

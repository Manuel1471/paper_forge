defmodule PaperForge.PDF.Filters do
  @moduledoc """
  Bounded decoding of structural PDF streams. Image codecs are preserved by the
  parser and reported as unsupported when explicitly decoded.
  """
  import Bitwise
  alias PaperForge.PDF.Syntax
  alias PaperForge.Stream

  def decode(%Stream{} = stream, limit \\ 50_000_000) do
    {:ok, decode!(stream, limit)}
  catch
    {:pdf_error, reason} -> {:error, reason}
  end

  @doc false
  def decode!(%Stream{data: data, dictionary: dictionary, filters: filters}, limit) do
    data = IO.iodata_to_binary(data)
    # Authoring streams have not yet been encoded by the serializer.
    if filters != [] do
      bounded(data, limit)
    else
      names = List.wrap(dictionary["Filter"])
      parameters = dictionary["DecodeParms"]

      params =
        if is_list(parameters), do: parameters, else: List.duplicate(parameters, length(names))

      if length(names) != length(params), do: Syntax.fail(:invalid_decode_parameters)

      Enum.zip(names, params)
      |> Enum.reduce(bounded(data, limit), fn {name, parameters}, bytes ->
        decode_filter(name, bytes, parameters || %{}, limit) |> bounded(limit)
      end)
    end
  end

  defp bounded(bytes, limit) when byte_size(bytes) <= limit, do: bytes
  defp bounded(_, limit), do: Syntax.fail({:max_stream_size_exceeded, limit})

  defp decode_filter({:name, name}, bytes, parameters, limit)
       when name in ["FlateDecode", "Fl"] do
    inflate(bytes, limit) |> predictor(parameters, limit)
  end

  defp decode_filter({:name, name}, bytes, _, limit) when name in ["ASCIIHexDecode", "AHx"] do
    {hex, _} =
      case :binary.split(bytes, ">") do
        [head, tail] -> {head, tail}
        [head] -> {head, ""}
      end

    hex = for <<c <- hex>>, c not in [0, 9, 10, 12, 13, 32], into: "", do: <<c>>
    hex = if rem(byte_size(hex), 2) == 1, do: hex <> "0", else: hex

    case Base.decode16(hex, case: :mixed) do
      {:ok, data} -> bounded(data, limit)
      :error -> Syntax.fail(:invalid_ascii_hex_stream)
    end
  end

  defp decode_filter({:name, name}, bytes, _, limit) when name in ["ASCII85Decode", "A85"] do
    bytes = for <<c <- bytes>>, c not in [0, 9, 10, 12, 13, 32], into: "", do: <<c>>
    ascii85(bytes, [], [], 0, limit)
  end

  defp decode_filter({:name, name}, bytes, _, limit) when name in ["RunLengthDecode", "RL"],
    do: run_length(bytes, [], 0, limit)

  defp decode_filter(name, _, _, _), do: Syntax.fail({:unsupported_stream_filter, name})

  defp inflate(bytes, limit) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z)
      inflate_chunks(z, bytes, [], 0, limit)
    rescue
      _ -> Syntax.fail(:invalid_flate_stream)
    after
      :zlib.close(z)
    end
  end

  defp inflate_chunks(z, input, acc, size, limit) do
    {status, output} = :zlib.safeInflate(z, input)
    size = size + IO.iodata_length(output)
    if size > limit, do: Syntax.fail({:max_stream_size_exceeded, limit})

    case status do
      :continue ->
        inflate_chunks(z, <<>>, [output | acc], size, limit)

      :finished ->
        :ok = :zlib.inflateEnd(z)
        IO.iodata_to_binary(Enum.reverse([output | acc]))
    end
  end

  defp run_length(<<128, _::binary>>, acc, _, _), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp run_length(<<n, rest::binary>>, acc, size, limit) do
    count = if n < 128, do: n + 1, else: 257 - n
    if size + count > limit, do: Syntax.fail({:max_stream_size_exceeded, limit})

    case {n, rest} do
      {n, <<chunk::binary-size(^count), tail::binary>>} when n < 128 ->
        run_length(tail, [chunk | acc], size + count, limit)

      {n, <<byte, tail::binary>>} when n > 128 ->
        run_length(tail, [:binary.copy(<<byte>>, count) | acc], size + count, limit)

      _ ->
        Syntax.fail(:invalid_run_length_stream)
    end
  end

  defp run_length(_, _, _, _), do: Syntax.fail(:invalid_run_length_stream)

  defp ascii85(<<"~>", _::binary>>, group, acc, size, limit) do
    case length(group) do
      0 ->
        IO.iodata_to_binary(Enum.reverse(acc))

      1 ->
        Syntax.fail(:invalid_ascii85_stream)

      n ->
        chunk = ascii85_group(group ++ List.duplicate(84, 5 - n)) |> binary_part(0, n - 1)
        if size + byte_size(chunk) > limit, do: Syntax.fail({:max_stream_size_exceeded, limit})
        IO.iodata_to_binary(Enum.reverse([chunk | acc]))
    end
  end

  defp ascii85(<<"z", rest::binary>>, [], acc, size, limit) do
    if size + 4 > limit, do: Syntax.fail({:max_stream_size_exceeded, limit})
    ascii85(rest, [], [<<0::32>> | acc], size + 4, limit)
  end

  defp ascii85(<<c, rest::binary>>, group, acc, size, limit) when c in 33..117 do
    group = group ++ [c - 33]

    if length(group) == 5 do
      if size + 4 > limit, do: Syntax.fail({:max_stream_size_exceeded, limit})
      ascii85(rest, [], [ascii85_group(group) | acc], size + 4, limit)
    else
      ascii85(rest, group, acc, size, limit)
    end
  end

  defp ascii85(_, _, _, _, _), do: Syntax.fail(:invalid_ascii85_stream)

  defp ascii85_group(group) do
    n = Enum.reduce(group, 0, &(&2 * 85 + &1))
    if n > 0xFFFFFFFF, do: Syntax.fail(:invalid_ascii85_stream)
    <<n::32>>
  end

  defp predictor(bytes, parameters, limit) when is_map(parameters) do
    case Map.get(parameters, "Predictor", 1) do
      1 -> bytes
      p when p in 10..15 -> png_predictor(bytes, parameters, limit)
      p -> Syntax.fail({:unsupported_predictor, p})
    end
  end

  defp predictor(_, _, _), do: Syntax.fail(:invalid_decode_parameters)

  defp png_predictor(bytes, parameters, limit) do
    colors = Map.get(parameters, "Colors", 1)
    bits = Map.get(parameters, "BitsPerComponent", 8)
    columns = Map.get(parameters, "Columns", 1)

    unless is_integer(colors) and colors > 0 and bits in [1, 2, 4, 8, 16] and is_integer(columns) and
             columns > 0,
           do: Syntax.fail(:invalid_predictor_parameters)

    row_size = div(colors * bits * columns + 7, 8)
    pixel_size = div(colors * bits + 7, 8)
    if row_size > limit, do: Syntax.fail({:max_stream_size_exceeded, limit})
    rows(bytes, row_size, pixel_size, :binary.copy(<<0>>, row_size), [])
  end

  defp rows(<<>>, _, _, _, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp rows(bytes, size, pixel, previous, acc) do
    case bytes do
      <<filter, row::binary-size(^size), rest::binary>> when filter in 0..4 ->
        decoded = decode_row(row, filter, pixel, previous)
        rows(rest, size, pixel, decoded, [decoded | acc])

      _ ->
        Syntax.fail(:invalid_predictor_stream)
    end
  end

  defp decode_row(row, filter, pixel, previous) do
    # A queue of the preceding pixel avoids quadratic binary appends.
    {decoded, _, _} =
      Enum.reduce(
        Enum.with_index(:binary.bin_to_list(row)),
        {[], :queue.from_list(List.duplicate(0, pixel)), 0},
        fn {byte, i}, {out, queue, _} ->
          {{:value, left}, queue} = :queue.out(queue)
          up = :binary.at(previous, i)
          upper_left = if i < pixel, do: 0, else: :binary.at(previous, i - pixel)

          prediction =
            case filter do
              0 -> 0
              1 -> left
              2 -> up
              3 -> div(left + up, 2)
              4 -> paeth(left, up, upper_left)
            end

          value = band(byte + prediction, 255)
          {[value | out], :queue.in(value, queue), 0}
        end
      )

    decoded |> Enum.reverse() |> :erlang.list_to_binary()
  end

  defp paeth(a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end
end

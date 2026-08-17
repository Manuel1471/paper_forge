defmodule PaperForge.PDF.Parser do
  @moduledoc false

  alias PaperForge.{Document, FontRegistry, ImageRegistry, Object, Reference, Stream}

  @default_max_file_size 100_000_000
  @default_max_objects 500_000
  @default_max_depth 100
  @default_max_stream_size 50_000_000

  @spec parse(binary(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def parse(pdf, options \\ [])

  def parse(pdf, options) when is_binary(pdf) and is_list(options) do
    max_file_size = Keyword.get(options, :max_file_size, @default_max_file_size)
    max_objects = Keyword.get(options, :max_objects, @default_max_objects)
    max_depth = Keyword.get(options, :max_depth, @default_max_depth)
    max_stream_size = Keyword.get(options, :max_stream_size, @default_max_stream_size)

    cond do
      not Enum.all?([max_file_size, max_objects, max_depth, max_stream_size], &valid_limit?/1) ->
        {:error, :invalid_parse_limits}

      byte_size(pdf) > max_file_size ->
        {:error, {:max_file_size_exceeded, max_file_size}}

      structure_depth(pdf) > max_depth ->
        {:error, {:max_depth_exceeded, max_depth}}

      largest_stream(pdf) > max_stream_size ->
        {:error, {:max_stream_size_exceeded, max_stream_size}}

      not String.starts_with?(pdf, "%PDF-") ->
        {:error, :invalid_pdf_header}

      Regex.match?(~r{/Encrypt\b}, pdf) ->
        {:error, :encrypted_pdf_not_supported}

      Regex.match?(~r{/Type\s*/ObjStm\b}, pdf) ->
        {:error, :object_streams_not_supported}

      true ->
        parse_objects(pdf, max_objects)
    end
  end

  def parse(_, _options), do: {:error, :invalid_pdf_header}

  defp parse_objects(pdf, max_objects) do
    matches =
      Regex.scan(~r/(?ms)(\d+)\s+(\d+)\s+obj\s*(.*?)\s*endobj/, pdf, capture: :all_but_first)

    if length(matches) > max_objects do
      {:error, {:max_objects_exceeded, max_objects}}
    else
      objects =
        matches
        |> Enum.reduce_while({:ok, %{}}, fn [id, generation, body], {:ok, objects} ->
          with {:ok, value} <- parse_object_body(body) do
            id = String.to_integer(id)
            object = %Object{id: id, generation: String.to_integer(generation), value: value}
            {:cont, {:ok, Map.put(objects, id, object)}}
          else
            error -> {:halt, error}
          end
        end)

      with {:ok, objects} <- objects,
           {:ok, root_reference, pages_reference} <- locate_catalog(objects) do
        version =
          Regex.run(~r/^%PDF-(1\.[4-7])/, pdf, capture: :all_but_first) |> List.first() || "1.7"

        {:ok,
         %Document{
           objects: objects,
           next_object_id: (objects |> Map.keys() |> Enum.max(fn -> 2 end)) + 1,
           root_reference: root_reference,
           pages_reference: pages_reference,
           info_reference: nil,
           pdf_version: version,
           font_registry: FontRegistry.new(),
           font_families: %{},
           font_fallbacks: %{},
           font_program_registry: %{},
           font_source_data: %{},
           default_font: :helvetica,
           page_templates: %{},
           styles: %{},
           components: %{},
           image_registry: ImageRegistry.new(),
           compress: true,
           named_destinations: %{},
           outlines_reference: nil,
           last_outline_reference: nil,
           outline_count: 0
         }}
      end
    end
  end

  defp valid_limit?(value), do: is_integer(value) and value > 0

  # The classic parser deliberately supports dictionaries and arrays only. This
  # inexpensive delimiter scan rejects pathological nesting before tokenization.
  defp structure_depth(pdf) do
    pdf
    |> :binary.bin_to_list()
    |> Enum.reduce({0, 0}, fn
      ?[, {current, maximum} -> {current + 1, max(maximum, current + 1)}
      ?], {current, maximum} -> {max(current - 1, 0), maximum}
      ?<, {current, maximum} -> {current + 1, max(maximum, current + 1)}
      ?>, {current, maximum} -> {max(current - 1, 0), maximum}
      _, state -> state
    end)
    |> elem(1)
  end

  defp largest_stream(pdf) do
    Regex.scan(~r/(?ms)\r?\nstream\r?\n(.*?)\r?\nendstream/, pdf, capture: :all_but_first)
    |> Enum.map(fn [data] -> byte_size(data) end)
    |> Enum.max(fn -> 0 end)
  end

  defp parse_object_body(body) do
    case :binary.match(body, ["\nstream\n", "\nstream\r\n", "\r\nstream\r\n"]) do
      {position, marker_length} ->
        dictionary_source = binary_part(body, 0, position)
        data_start = position + marker_length

        with {:ok, dictionary} <- parse_value(dictionary_source) do
          length = dictionary["Length"]

          data =
            if is_integer(length) and data_start + length <= byte_size(body),
              do: binary_part(body, data_start, length),
              else:
                body |> binary_part(data_start, byte_size(body) - data_start) |> trim_endstream()

          {:ok, Stream.new(data, dictionary: Map.delete(dictionary, "Length"))}
        end

      :nomatch ->
        parse_value(body)
    end
  end

  defp trim_endstream(data) do
    case :binary.match(data, "endstream") do
      {position, _} -> data |> binary_part(0, position) |> String.trim_trailing("\r\n")
      :nomatch -> data
    end
  end

  defp parse_value(source) do
    with {:ok, tokens} <- tokenize(source),
         {:ok, value, rest} <- value(tokens),
         [] <- rest do
      {:ok, value}
    else
      {:error, _} = error -> error
      rest when is_list(rest) -> {:error, {:trailing_pdf_tokens, Enum.take(rest, 5)}}
      _ -> {:error, :invalid_pdf_object}
    end
  end

  defp tokenize(source), do: scan(source, [])

  defp scan(<<>>, tokens), do: {:ok, Enum.reverse(tokens)}

  defp scan(<<char, rest::binary>>, tokens) when char in [0, 9, 10, 12, 13, 32],
    do: scan(rest, tokens)

  defp scan(<<"%", rest::binary>>, tokens), do: scan(skip_comment(rest), tokens)
  defp scan(<<"<<", rest::binary>>, tokens), do: scan(rest, [:dict_open | tokens])
  defp scan(<<">>", rest::binary>>, tokens), do: scan(rest, [:dict_close | tokens])
  defp scan(<<"[", rest::binary>>, tokens), do: scan(rest, [:array_open | tokens])
  defp scan(<<"]", rest::binary>>, tokens), do: scan(rest, [:array_close | tokens])

  defp scan(<<"(", rest::binary>>, tokens) do
    with {:ok, string, remaining} <- literal(rest, 1, []) do
      scan(remaining, [{:string, IO.iodata_to_binary(Enum.reverse(string))} | tokens])
    end
  end

  defp scan(<<"/", rest::binary>>, tokens) do
    {name, remaining} = take_while(rest, &(!delimiter?(&1)))
    scan(remaining, [{:name, decode_name(name)} | tokens])
  end

  defp scan(<<"<", rest::binary>>, tokens) do
    case :binary.match(rest, ">") do
      {position, 1} ->
        hex = rest |> binary_part(0, position) |> String.replace(~r/\s+/, "")
        hex = if rem(byte_size(hex), 2) == 1, do: hex <> "0", else: hex

        case Base.decode16(hex, case: :mixed) do
          {:ok, data} ->
            scan(binary_part(rest, position + 1, byte_size(rest) - position - 1), [
              {:hex, data} | tokens
            ])

          :error ->
            {:error, :invalid_pdf_hex_string}
        end

      :nomatch ->
        {:error, :unterminated_pdf_hex_string}
    end
  end

  defp scan(source, tokens) do
    {word, remaining} = take_while(source, &(!delimiter?(&1)))

    case classify(word) do
      {:ok, token} -> scan(remaining, [token | tokens])
      error -> error
    end
  end

  defp value([{:number, object_id}, {:number, generation}, :reference | rest])
       when is_integer(object_id) and is_integer(generation),
       do: {:ok, Reference.new(object_id, generation), rest}

  defp value([:dict_open | rest]), do: dictionary(rest, %{})
  defp value([:array_open | rest]), do: array(rest, [])
  defp value([{:name, name} | rest]), do: {:ok, {:name, name}, rest}
  defp value([{:string, string} | rest]), do: {:ok, string, rest}
  defp value([{:hex, data} | rest]), do: {:ok, {:hex_string, data}, rest}
  defp value([{:number, number} | rest]), do: {:ok, number, rest}
  defp value([{:boolean, boolean} | rest]), do: {:ok, boolean, rest}
  defp value([:null | rest]), do: {:ok, nil, rest}
  defp value(tokens), do: {:error, {:invalid_pdf_value, Enum.take(tokens, 5)}}

  defp dictionary([:dict_close | rest], dictionary), do: {:ok, dictionary, rest}

  defp dictionary([{:name, key} | rest], dictionary) do
    with {:ok, parsed, remaining} <- value(rest) do
      dictionary(remaining, Map.put(dictionary, key, parsed))
    end
  end

  defp dictionary(tokens, _dictionary),
    do: {:error, {:invalid_pdf_dictionary, Enum.take(tokens, 5)}}

  defp array([:array_close | rest], values), do: {:ok, Enum.reverse(values), rest}

  defp array(tokens, values) do
    with {:ok, parsed, remaining} <- value(tokens) do
      array(remaining, [parsed | values])
    end
  end

  defp classify("R"), do: {:ok, :reference}
  defp classify("true"), do: {:ok, {:boolean, true}}
  defp classify("false"), do: {:ok, {:boolean, false}}
  defp classify("null"), do: {:ok, :null}

  defp classify(word) do
    case Float.parse(word) do
      {number, ""} ->
        {:ok, {:number, if(number == trunc(number), do: trunc(number), else: number)}}

      _ ->
        {:error, {:unsupported_pdf_token, word}}
    end
  end

  defp literal(<<>>, _depth, _bytes), do: {:error, :unterminated_pdf_string}

  defp literal(<<"\\", char, rest::binary>>, depth, bytes),
    do: literal(rest, depth, [escaped(char) | bytes])

  defp literal(<<"(", rest::binary>>, depth, bytes), do: literal(rest, depth + 1, ["(" | bytes])
  defp literal(<<")", rest::binary>>, 1, bytes), do: {:ok, bytes, rest}
  defp literal(<<")", rest::binary>>, depth, bytes), do: literal(rest, depth - 1, [")" | bytes])
  defp literal(<<char, rest::binary>>, depth, bytes), do: literal(rest, depth, [<<char>> | bytes])

  defp escaped(?n), do: "\n"
  defp escaped(?r), do: "\r"
  defp escaped(?t), do: "\t"
  defp escaped(?b), do: <<8>>
  defp escaped(?f), do: <<12>>
  defp escaped(char), do: <<char>>

  defp skip_comment(source) do
    case :binary.match(source, ["\n", "\r"]) do
      {position, _} -> binary_part(source, position + 1, byte_size(source) - position - 1)
      :nomatch -> <<>>
    end
  end

  defp take_while(source, predicate), do: take_while(source, predicate, [])

  defp take_while(<<char, rest::binary>>, predicate, bytes) do
    if predicate.(char),
      do: take_while(rest, predicate, [char | bytes]),
      else: {bytes |> Enum.reverse() |> :erlang.list_to_binary(), <<char, rest::binary>>}
  end

  defp take_while(<<>>, _predicate, bytes),
    do: {bytes |> Enum.reverse() |> :erlang.list_to_binary(), <<>>}

  defp delimiter?(char), do: char in [0, 9, 10, 12, 13, 32, ?(, ?), ?<, ?>, ?[, ?], ?/, ?%]

  defp decode_name(name),
    do:
      Regex.replace(~r/#([0-9A-Fa-f]{2})/, name, fn _, hex -> <<String.to_integer(hex, 16)>> end)

  defp locate_catalog(objects) do
    Enum.find_value(objects, {:error, :pdf_catalog_not_found}, fn {id, %Object{value: value}} ->
      case value do
        %{"Type" => {:name, "Catalog"}, "Pages" => %Reference{} = pages} ->
          {:ok, Reference.new(id), pages}

        _ ->
          nil
      end
    end)
  end
end

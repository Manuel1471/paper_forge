defmodule PaperForge.PDF.Reader do
  @moduledoc false
  alias PaperForge.{Object, Reference, Stream}
  alias PaperForge.PDF.{Decryption, Filters, Syntax}

  def read(pdf, limits, options) do
    offset = startxref(pdf)
    {entries, trailer, revisions} = chain(pdf, offset, limits, MapSet.new(), %{}, %{}, [])

    state = %{
      pdf: pdf,
      entries: entries,
      objects: %{},
      streams: %{},
      loading: MapSet.new(),
      limits: limits,
      security: nil,
      encrypt_id: nil
    }

    state = encryption(state, trailer, options)

    state =
      Enum.reduce(Enum.sort(Map.keys(entries)), state, fn id, state ->
        case entries[id] do
          {:free, _, _} -> state
          _ -> elem(load(id, state), 1)
        end
      end)

    {state.objects, trailer,
     %{
       startxref: offset,
       revisions: Enum.reverse(revisions),
       cross_reference_type: xref_type(revisions),
       compressed_objects: Enum.count(entries, fn {_, e} -> match?({:compressed, _, _}, e) end),
       encryption:
         if(state.security,
           do:
             Map.take(state.security, [
               :revision,
               :permissions,
               :encrypt_metadata,
               :authentication
             ]),
           else: nil
         )
     }}
  end

  defp startxref(pdf) do
    case Regex.scan(~r/startxref[\x00\t\n\f\r ]+(\d+)[\x00\t\n\f\r ]+%%EOF/, pdf,
           capture: :all_but_first
         )
         |> List.last() do
      [offset] -> String.to_integer(offset)
      _ -> Syntax.fail(:missing_startxref)
    end
  end

  defp at(pdf, offset) when is_integer(offset) and offset >= 0 and offset < byte_size(pdf),
    do: binary_part(pdf, offset, byte_size(pdf) - offset)

  defp at(_, _), do: Syntax.fail(:invalid_pdf_offset)

  defp chain(pdf, offset, limits, seen, entries, trailer, revisions) do
    if MapSet.member?(seen, offset), do: Syntax.fail(:cyclic_xref_chain)

    if MapSet.size(seen) >= limits.max_depth,
      do: Syntax.fail({:max_depth_exceeded, limits.max_depth})

    {current, dictionary, type} = section(pdf, offset, limits)

    {current, type} =
      case dictionary["XRefStm"] do
        nil ->
          {current, type}

        hybrid when type == :table ->
          {extra, _, :stream} = stream_section(pdf, hybrid, limits)
          {Map.merge(current, extra), :hybrid}

        _ ->
          Syntax.fail(:invalid_hybrid_xref)
      end

    entries = Map.merge(current, entries)

    if map_size(entries) > limits.max_objects + 1,
      do: Syntax.fail({:max_objects_exceeded, limits.max_objects})

    trailer = Map.merge(dictionary, trailer)

    revisions = [
      %{offset: offset, type: type, entries: map_size(current), trailer: dictionary} | revisions
    ]

    case dictionary["Prev"] do
      nil ->
        {entries, trailer, revisions}

      previous ->
        chain(pdf, previous, limits, MapSet.put(seen, offset), entries, trailer, revisions)
    end
  end

  defp section(pdf, offset, limits) do
    case at(pdf, offset) do
      <<"xref", rest::binary>> -> table(rest, %{}, limits)
      _ -> stream_section(pdf, offset, limits)
    end
  end

  defp table(source, entries, limits) do
    case Syntax.skip(source) do
      <<"trailer", rest::binary>> ->
        {dictionary, _} = Syntax.value(rest, limits.max_depth)
        unless is_map(dictionary) and not is_struct(dictionary), do: Syntax.fail(:invalid_trailer)
        {entries, dictionary, :table}

      source ->
        {first, rest} = Syntax.integer(source)
        {count, rest} = Syntax.integer(rest)

        unless first >= 0 and count >= 0 and count <= limits.max_objects + 1 and
                 map_size(entries) + count <= limits.max_objects + 1,
               do: Syntax.fail({:max_objects_exceeded, limits.max_objects})

        {entries, rest} = table_entries(rest, first, count, entries)
        table(rest, entries, limits)
    end
  end

  defp table_entries(rest, _, 0, entries), do: {entries, rest}

  defp table_entries(source, id, count, entries) do
    {offset, rest} = Syntax.integer(source)
    {generation, rest} = Syntax.integer(rest)
    {flag, rest} = Syntax.word(rest)

    unless offset >= 0 and generation in 0..65_535 and flag in ["n", "f"],
      do: Syntax.fail(:invalid_xref_entry)

    entry = {if(flag == "n", do: :direct, else: :free), offset, generation}
    table_entries(rest, id + 1, count - 1, Map.put(entries, id, entry))
  end

  defp stream_section(pdf, offset, limits) do
    state = %{
      pdf: pdf,
      entries: %{},
      objects: %{},
      streams: %{},
      loading: MapSet.new(),
      limits: limits,
      security: nil,
      encrypt_id: nil
    }

    {object, _} = direct(offset, state)

    case object.value do
      %Stream{
        dictionary: %{"Type" => {:name, "XRef"}, "W" => widths, "Size" => size} = dictionary
      } = stream ->
        validate_widths(widths, size)
        indexes = validate_indexes(Map.get(dictionary, "Index", [0, size]), limits.max_objects)

        bytes = Filters.decode!(stream, limits.max_stream_size)

        {entries, remaining} =
          Enum.reduce(Enum.chunk_every(indexes, 2), {%{}, bytes}, fn [first, count],
                                                                     {entries, bytes} ->
            stream_entries(bytes, first, count, widths, entries)
          end)

        if remaining != "", do: Syntax.fail(:invalid_xref_stream_length)
        {entries, dictionary, :stream}

      _ ->
        Syntax.fail(:invalid_xref_stream)
    end
  end

  defp validate_widths(widths, size) do
    unless is_list(widths) and length(widths) == 3 and
             Enum.all?(widths, &(is_integer(&1) and &1 in 0..8)) and Enum.sum(widths) > 0 and
             is_integer(size) and size >= 0, do: Syntax.fail(:invalid_xref_stream)
  end

  defp validate_indexes(indexes, max_objects) do
    unless is_list(indexes) and rem(length(indexes), 2) == 0 and
             Enum.all?(indexes, &(is_integer(&1) and &1 >= 0)),
           do: Syntax.fail(:invalid_xref_index)

    count = indexes |> Enum.chunk_every(2) |> Enum.reduce(0, fn [_, n], acc -> acc + n end)
    if count > max_objects + 1, do: Syntax.fail({:max_objects_exceeded, max_objects})
    indexes
  end

  defp stream_entries(bytes, _, 0, _, entries), do: {entries, bytes}

  defp stream_entries(bytes, id, count, [w0, w1, w2] = widths, entries) do
    {type, bytes} = field(bytes, w0, 1)
    {a, bytes} = field(bytes, w1, 0)
    {b, bytes} = field(bytes, w2, 0)

    entry =
      case type do
        0 -> {:free, a, b}
        1 when b <= 65_535 -> {:direct, a, b}
        2 -> {:compressed, a, b}
        _ -> Syntax.fail(:invalid_xref_entry)
      end

    stream_entries(bytes, id + 1, count - 1, widths, Map.put(entries, id, entry))
  end

  defp field(bytes, 0, default), do: {default, bytes}

  defp field(bytes, width, _) do
    case bytes do
      <<value::unsigned-big-integer-size(^width)-unit(8), rest::binary>> -> {value, rest}
      _ -> Syntax.fail(:truncated_xref_stream)
    end
  end

  defp load(id, state) do
    case Map.fetch(state.objects, id) do
      {:ok, object} -> {object, state}
      :error -> load_uncached(id, state)
    end
  end

  defp load_uncached(id, state) do
    if MapSet.member?(state.loading, id), do: Syntax.fail({:cyclic_object_reference, id})

    if MapSet.size(state.loading) >= state.limits.max_depth,
      do: Syntax.fail({:max_depth_exceeded, state.limits.max_depth})

    state = %{state | loading: MapSet.put(state.loading, id)}
    {object, state} = load_entry(state.entries[id], id, state)

    state = %{
      state
      | objects: Map.put(state.objects, id, object),
        loading: MapSet.delete(state.loading, id)
    }

    {object, state}
  end

  defp load_entry({:direct, offset, generation}, id, state) do
    {object, state} = direct(offset, state)

    unless object.id == id and object.generation == generation,
      do: Syntax.fail({:xref_object_mismatch, id})

    {decrypt_object(object, state), state}
  end

  defp load_entry({:compressed, stream_id, index}, id, state),
    do: compressed(id, stream_id, index, state)

  defp load_entry(_, id, _), do: Syntax.fail({:missing_object, id})

  defp decrypt_object(object, %{security: nil}), do: object
  defp decrypt_object(%{id: id} = object, %{encrypt_id: id}), do: object

  defp decrypt_object(%{value: %Stream{dictionary: %{"Type" => {:name, "XRef"}}}} = object, _),
    do: object

  defp decrypt_object(object, state),
    do: %{object | value: Decryption.decrypt(object.value, state.security)}

  defp direct(offset, state) do
    {id, rest} = state.pdf |> at(offset) |> Syntax.integer()
    {generation, rest} = Syntax.integer(rest)
    {marker, rest} = Syntax.word(rest)

    unless id > 0 and generation in 0..65_535 and marker == "obj",
      do: Syntax.fail(:invalid_object_header)

    {value, rest} = Syntax.value(rest, state.limits.max_depth)

    {value, state} = object_body(value, Syntax.skip(rest), state)
    {%Object{id: id, generation: generation, value: value}, state}
  end

  defp object_body(dictionary, <<"stream", rest::binary>>, state)
       when is_map(dictionary) and not is_struct(dictionary) do
    rest = stream_separator(rest)
    {length, state} = stream_length(dictionary["Length"], state)

    if length > state.limits.max_stream_size,
      do: Syntax.fail({:max_stream_size_exceeded, state.limits.max_stream_size})

    data = stream_bytes(rest, length)
    {Stream.new(data, dictionary: Map.delete(dictionary, "Length")), state}
  end

  defp object_body(value, rest, state) do
    {marker, _} = Syntax.word(rest)
    if marker != "endobj", do: Syntax.fail(:missing_endobj)
    {value, state}
  end

  defp stream_separator(<<"\r\n", rest::binary>>), do: rest
  defp stream_separator(<<"\n", rest::binary>>), do: rest
  defp stream_separator(_), do: Syntax.fail(:invalid_stream_separator)

  defp stream_bytes(bytes, length) do
    case bytes do
      <<data::binary-size(^length), tail::binary>> ->
        {endstream, tail} = Syntax.word(tail)
        {endobj, _} = Syntax.word(tail)

        unless endstream == "endstream" and endobj == "endobj",
          do: Syntax.fail(:invalid_stream_length)

        data

      _ ->
        Syntax.fail(:truncated_pdf_stream)
    end
  end

  defp stream_length(n, state) when is_integer(n) and n >= 0, do: {n, state}

  defp stream_length(%Reference{object_id: id, generation: generation}, state) do
    {object, state} = load(id, state)
    unless object.generation == generation, do: Syntax.fail(:invalid_stream_length_reference)
    stream_length(object.value, state)
  end

  defp stream_length(_, _), do: Syntax.fail(:invalid_stream_length)

  defp compressed(id, stream_id, index, state) do
    {values, state} =
      case Map.fetch(state.streams, stream_id) do
        {:ok, values} ->
          {values, state}

        :error ->
          unless match?({:direct, _, 0}, state.entries[stream_id]),
            do: Syntax.fail(:invalid_object_stream_reference)

          {object, state} = load(stream_id, state)
          values = object_stream(object.value, state.limits)
          {values, %{state | streams: Map.put(state.streams, stream_id, values)}}
      end

    case Map.get(values, index) do
      {^id, value} -> {%Object{id: id, generation: 0, value: value}, state}
      _ -> Syntax.fail({:invalid_compressed_object_index, id})
    end
  end

  defp object_stream(
         %Stream{dictionary: %{"Type" => {:name, "ObjStm"}, "N" => count, "First" => first}} =
           stream,
         limits
       )
       when is_integer(count) and count >= 0 and is_integer(first) and first >= 0 do
    if count > limits.max_objects, do: Syntax.fail({:max_objects_exceeded, limits.max_objects})
    bytes = Filters.decode!(stream, limits.max_stream_size)
    if first > byte_size(bytes), do: Syntax.fail(:invalid_object_stream_header)
    {headers, rest} = object_headers(binary_part(bytes, 0, first), count, [])
    if Syntax.skip(rest) != "", do: Syntax.fail(:invalid_object_stream_header)
    body = binary_part(bytes, first, byte_size(bytes) - first)

    next_offsets = Enum.map(Enum.drop(headers, 1), &elem(&1, 1)) ++ [byte_size(body)]

    headers
    |> Enum.zip(next_offsets)
    |> Enum.with_index()
    |> Map.new(fn {{{id, offset}, next_offset}, index} ->
      {index, {id, compressed_value(body, offset, next_offset, limits.max_depth)}}
    end)
  end

  defp object_stream(_, _), do: Syntax.fail(:invalid_object_stream)

  defp compressed_value(body, offset, next_offset, depth) do
    unless offset >= 0 and offset < next_offset and next_offset <= byte_size(body),
      do: Syntax.fail(:invalid_object_stream_offset)

    {value, rest} = Syntax.value(binary_part(body, offset, next_offset - offset), depth)
    if Syntax.skip(rest) != "", do: Syntax.fail(:trailing_object_stream_tokens)
    value
  end

  defp object_headers(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp object_headers(source, count, acc) do
    {id, rest} = Syntax.integer(source)
    {offset, rest} = Syntax.integer(rest)
    if id <= 0, do: Syntax.fail(:invalid_object_stream_header)
    object_headers(rest, count - 1, [{id, offset} | acc])
  end

  defp encryption(
         state,
         %{"Encrypt" => %Reference{object_id: id, generation: generation}} = trailer,
         options
       ) do
    {object, state} = load(id, state)
    unless object.generation == generation, do: Syntax.fail(:invalid_encryption_reference)

    security =
      Decryption.authenticate(
        object.value,
        trailer,
        Keyword.get(options, :password)
      )

    %{state | security: security, encrypt_id: id}
  end

  defp encryption(state, trailer, _) do
    if trailer["Encrypt"], do: Syntax.fail(:invalid_encryption_dictionary)
    state
  end

  defp xref_type(revisions) do
    case Enum.uniq(Enum.map(revisions, & &1.type)) do
      [:table] -> :table
      [:stream] -> :stream
      types -> if(:hybrid in types, do: :hybrid, else: :mixed)
    end
  end
end

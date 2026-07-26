defmodule PaperForge.Serializer do
  @moduledoc """
  Serializes Elixir values into PDF syntax.

  Supported values include:

  - integers and floats;
  - booleans and `nil`;
  - PDF names;
  - literal strings;
  - hexadecimal strings;
  - arrays;
  - dictionaries;
  - indirect references;
  - PDF streams.
  """

  alias PaperForge.Compression
  alias PaperForge.Reference
  alias PaperForge.Stream

  @type pdf_name :: {:name, binary()}
  @type pdf_hex_string :: {:hex_string, binary()}

  @doc """
  Serializes a supported value as PDF iodata.

  ## Examples

      PaperForge.Serializer.encode(42)
      #=> "42"

      PaperForge.Serializer.encode({:name, "Helvetica"})
      #=> ["/", "Helvetica"]

      PaperForge.Serializer.encode("Hello")
      #=> ["(", "Hello", ")"]
  """
  @spec encode(term()) :: iodata()
  def encode(nil) do
    "null"
  end

  def encode(true) do
    "true"
  end

  def encode(false) do
    "false"
  end

  def encode(value)
      when is_integer(value) do
    Integer.to_string(value)
  end

  def encode(value)
      when is_float(value) do
    encode_float(value)
  end

  def encode({:name, value})
      when is_binary(value) do
    [
      "/",
      escape_name(value)
    ]
  end

  def encode({:hex_string, value})
      when is_binary(value) do
    [
      "<",
      Base.encode16(
        value,
        case: :upper
      ),
      ">"
    ]
  end

  def encode(%Reference{
        object_id: object_id,
        generation: generation
      }) do
    [
      Integer.to_string(object_id),
      " ",
      Integer.to_string(generation),
      " R"
    ]
  end

  def encode(%Stream{} = stream) do
    encode_stream(stream)
  end

  def encode(value)
      when is_binary(value) do
    encode_literal_string(value)
  end

  def encode(value)
      when is_list(value) do
    encode_array(value)
  end

  def encode(value)
      when is_map(value) do
    encode_dictionary(value)
  end

  def encode(value) do
    raise ArgumentError,
          "cannot serialize value as PDF: #{inspect(value)}"
  end

  defp encode_float(value) do
    value
    |> :erlang.float_to_binary(decimals: 6)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
    |> normalize_negative_zero()
  end

  defp normalize_negative_zero("-0") do
    "0"
  end

  defp normalize_negative_zero(value) do
    value
  end

  defp encode_literal_string(value) do
    [
      "(",
      escape_literal_string(value),
      ")"
    ]
  end

  defp encode_array(values) do
    encoded_values =
      values
      |> Enum.map(&encode/1)
      |> Enum.intersperse(" ")

    [
      "[",
      encoded_values,
      "]"
    ]
  end

  defp encode_dictionary(dictionary) do
    entries =
      dictionary
      |> Enum.sort_by(fn {key, _value} ->
        normalize_dictionary_key(key)
      end)
      |> Enum.map(fn {key, value} ->
        [
          "/",
          key
          |> normalize_dictionary_key()
          |> escape_name(),
          " ",
          encode(value)
        ]
      end)
      |> Enum.intersperse("\n")

    [
      "<<\n",
      entries,
      "\n>>"
    ]
  end

  defp encode_stream(%Stream{} = stream) do
    raw_data =
      Stream.raw_data(stream)

    {
      encoded_data,
      filter_names
    } =
      apply_filters(
        raw_data,
        stream.filters
      )

    dictionary =
      stream.dictionary
      |> Map.put(
        "Length",
        byte_size(encoded_data)
      )
      |> put_stream_filters(filter_names)

    [
      encode_dictionary(dictionary),
      "\n",
      "stream\n",
      encoded_data,
      "\n",
      "endstream"
    ]
  end

  defp apply_filters(
         data,
         filters
       ) do
    Enum.reduce(
      filters,
      {
        data,
        []
      },
      fn filter,
         {
           current_data,
           applied_filters
         } ->
        apply_filter(
          filter,
          current_data,
          applied_filters
        )
      end
    )
  end

  defp apply_filter(
         :flate,
         data,
         applied_filters
       ) do
    {
      Compression.flate(data),
      applied_filters ++
        [
          {:name, "FlateDecode"}
        ]
    }
  end

  defp apply_filter(
         filter,
         _data,
         _applied_filters
       ) do
    raise ArgumentError,
          "unsupported stream filter: #{inspect(filter)}"
  end

  defp put_stream_filters(
         dictionary,
         []
       ) do
    dictionary
  end

  defp put_stream_filters(
         dictionary,
         [filter]
       ) do
    case Map.has_key?(
           dictionary,
           "Filter"
         ) do
      true ->
        dictionary

      false ->
        Map.put(
          dictionary,
          "Filter",
          filter
        )
    end
  end

  defp put_stream_filters(
         dictionary,
         filters
       ) do
    case Map.has_key?(
           dictionary,
           "Filter"
         ) do
      true ->
        dictionary

      false ->
        Map.put(
          dictionary,
          "Filter",
          filters
        )
    end
  end

  defp normalize_dictionary_key(key)
       when is_binary(key) do
    key
  end

  defp normalize_dictionary_key(key)
       when is_atom(key) do
    Atom.to_string(key)
  end

  defp normalize_dictionary_key(key) do
    raise ArgumentError,
          "PDF dictionary keys must be strings or atoms, received: " <>
            inspect(key)
  end

  defp escape_literal_string(value) do
    value
    |> String.replace(
      "\\",
      "\\\\"
    )
    |> String.replace(
      "(",
      "\\("
    )
    |> String.replace(
      ")",
      "\\)"
    )
    |> String.replace(
      "\r",
      "\\r"
    )
    |> String.replace(
      "\n",
      "\\n"
    )
    |> String.replace(
      "\t",
      "\\t"
    )
    |> String.replace(
      "\b",
      "\\b"
    )
    |> String.replace(
      "\f",
      "\\f"
    )
  end

  defp escape_name(value) do
    for <<byte <- value>>,
      into: "" do
      if regular_name_byte?(byte) do
        <<byte>>
      else
        [
          "#",
          byte
          |> Integer.to_string(16)
          |> String.upcase()
          |> String.pad_leading(
            2,
            "0"
          )
        ]
        |> IO.iodata_to_binary()
      end
    end
  end

  defp regular_name_byte?(byte) do
    byte >= 33 and
      byte <= 126 and
      byte not in [
        ?#,
        ?%,
        ?(,
        ?),
        ?/,
        ?<,
        ?>,
        ?[,
        ?],
        ?{,
        ?}
      ]
  end
end

defmodule PaperForge.Serializer do
  @moduledoc """
  Converts Elixir values into valid PDF syntax.

  This module serializes the primitive values used by PDF:

  - null
  - booleans
  - integers and real numbers
  - names
  - literal strings
  - arrays
  - dictionaries
  - indirect references
  - streams
  """

  alias PaperForge.Reference
  alias PaperForge.Stream

  @type pdf_name :: {:name, binary()}

  @spec encode(term()) :: iodata()

  def encode(nil), do: "null"

  def encode(true), do: "true"
  def encode(false), do: "false"

  def encode(value) when is_integer(value) do
    Integer.to_string(value)
  end

  def encode(value) when is_float(value) do
    encode_float(value)
  end

  def encode({:name, value}) when is_binary(value) do
    ["/", escape_name(value)]
  end

  def encode(%Reference{} = reference) do
    [
      Integer.to_string(reference.object_id),
      " ",
      Integer.to_string(reference.generation),
      " R"
    ]
  end

  def encode(%Stream{} = stream) do
    encode_stream(stream)
  end

  def encode(value) when is_binary(value) do
    ["(", escape_literal_string(value), ")"]
  end

  def encode(value) when is_list(value) do
    encode_array(value)
  end

  def encode(value) when is_map(value) do
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
  end

  defp encode_array(values) do
    contents =
      values
      |> Enum.map(&encode/1)
      |> Enum.intersperse(" ")

    ["[", contents, "]"]
  end

  defp encode_dictionary(dictionary) do
    entries =
      dictionary
      |> Enum.sort_by(fn {key, _value} -> normalize_key(key) end)
      |> Enum.map(fn {key, value} ->
        [
          "/",
          key |> normalize_key() |> escape_name(),
          " ",
          encode(value)
        ]
      end)
      |> Enum.intersperse("\n")

    ["<<\n", entries, "\n>>"]
  end

  defp encode_stream(%Stream{} = stream) do
    data = IO.iodata_to_binary(stream.data)

    dictionary =
      stream.dictionary
      |> Map.put("Length", byte_size(data))

    [
      encode_dictionary(dictionary),
      "\nstream\n",
      data,
      "\nendstream"
    ]
  end

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)

  defp normalize_key(key) do
    raise ArgumentError,
          "PDF dictionary keys must be strings or atoms, got: #{inspect(key)}"
  end

  defp escape_literal_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace("\r", "\\r")
    |> String.replace("\n", "\\n")
  end

  defp escape_name(value) do
    for <<byte <- value>>, into: "" do
      if regular_name_byte?(byte) do
        <<byte>>
      else
        hex =
          byte
          |> Integer.to_string(16)
          |> String.upcase()
          |> String.pad_leading(2, "0")

        "#" <> hex
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

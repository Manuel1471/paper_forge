defmodule PaperForge.StringEncoding do
  @moduledoc """
  Encodes strings for use inside PDF objects.

  PaperForge currently supports:

  - PDF literal strings;
  - PDF hexadecimal strings;
  - UTF-16BE strings with a byte-order mark;
  - automatic selection between literal and UTF-16BE encoding.

  Standard Type 1 fonts still depend on their own font encoding for
  visible page content. This module is especially useful for metadata
  such as titles, authors, subjects, and keywords.
  """

  @utf16be_bom <<0xFE, 0xFF>>

  @type encoded_string ::
          binary()
          | {:hex_string, binary()}

  @doc """
  Encodes a string for a PDF literal string.

  The returned value is still a regular Elixir binary. Escaping of
  parentheses, backslashes, and control characters is handled later by
  `PaperForge.Serializer`.

  This function raises when the string contains characters outside the
  Latin-1 range.

  ## Examples

      PaperForge.StringEncoding.literal("PaperForge")
      #=> "PaperForge"

      PaperForge.StringEncoding.literal("Manuel García")
      #=> "Manuel García"
  """
  @spec literal(binary()) :: binary()
  def literal(value) when is_binary(value) do
    case to_latin1(value) do
      {:ok, encoded} ->
        encoded

      {:error, character} ->
        raise ArgumentError,
              "string contains a character that cannot be encoded as " <>
                "Latin-1: #{inspect(character)}"
    end
  end

  @doc """
  Attempts to encode a string as Latin-1.

  Returns:

      {:ok, encoded_binary}

  or:

      {:error, unsupported_character}
  """
  @spec to_latin1(binary()) ::
          {:ok, binary()}
          | {:error, binary()}
  def to_latin1(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reduce_while(
      {:ok, []},
      fn grapheme, {:ok, bytes} ->
        case encode_latin1_grapheme(grapheme) do
          {:ok, byte} ->
            {:cont, {:ok, [bytes, byte]}}

          :error ->
            {:halt, {:error, grapheme}}
        end
      end
    )
    |> case do
      {:ok, iodata} ->
        {:ok, IO.iodata_to_binary(iodata)}

      {:error, grapheme} ->
        {:error, grapheme}
    end
  end

  @doc """
  Encodes a string as UTF-16BE with a byte-order mark.

  The result is suitable for use as a PDF hexadecimal string.

  ## Example

      PaperForge.StringEncoding.utf16be("México")
      #=> <<254, 255, ...>>
  """
  @spec utf16be(binary()) :: binary()
  def utf16be(value) when is_binary(value) do
    encoded =
      value
      |> String.to_charlist()
      |> Enum.map(&encode_utf16_codepoint/1)
      |> IO.iodata_to_binary()

    @utf16be_bom <> encoded
  end

  @doc """
  Encodes a string as a PDF hexadecimal UTF-16BE string.

  ## Example

      PaperForge.StringEncoding.utf16be_hex("México")
      #=> {:hex_string, <<254, 255, ...>>}
  """
  @spec utf16be_hex(binary()) :: {:hex_string, binary()}
  def utf16be_hex(value) when is_binary(value) do
    {
      :hex_string,
      utf16be(value)
    }
  end

  @doc """
  Chooses the most appropriate PDF representation automatically.

  Strings that can be represented safely using Latin-1 are returned as
  ordinary binaries. Other strings are returned as UTF-16BE hexadecimal
  strings.

  ## Examples

      PaperForge.StringEncoding.auto("PaperForge")
      #=> "PaperForge"

      PaperForge.StringEncoding.auto("PDF con 漢字")
      #=> {:hex_string, <<254, 255, ...>>}
  """
  @spec auto(binary()) :: encoded_string()
  def auto(value) when is_binary(value) do
    case to_latin1(value) do
      {:ok, encoded} ->
        encoded

      {:error, _character} ->
        utf16be_hex(value)
    end
  end

  @doc """
  Returns whether a string can be encoded as Latin-1.
  """
  @spec latin1?(binary()) :: boolean()
  def latin1?(value) when is_binary(value) do
    match?(
      {:ok, _encoded},
      to_latin1(value)
    )
  end

  @doc """
  Returns whether a binary starts with the UTF-16BE byte-order mark.
  """
  @spec utf16be?(binary()) :: boolean()
  def utf16be?(<<@utf16be_bom, _rest::binary>>) do
    true
  end

  def utf16be?(_value) do
    false
  end

  defp encode_latin1_grapheme(grapheme) do
    case String.to_charlist(grapheme) do
      [codepoint]
      when codepoint >= 0 and
             codepoint <= 255 ->
        {:ok, <<codepoint>>}

      _ ->
        :error
    end
  end

  defp encode_utf16_codepoint(codepoint)
       when codepoint >= 0 and
              codepoint <= 0xFFFF and
              codepoint not in 0xD800..0xDFFF do
    <<codepoint::16-big>>
  end

  defp encode_utf16_codepoint(codepoint)
       when codepoint >= 0x10000 and
              codepoint <= 0x10FFFF do
    adjusted =
      codepoint - 0x10000

    high_surrogate =
      0xD800 +
        Bitwise.bsr(
          adjusted,
          10
        )

    low_surrogate =
      0xDC00 +
        Bitwise.band(
          adjusted,
          0x3FF
        )

    <<
      high_surrogate::16-big,
      low_surrogate::16-big
    >>
  end

  defp encode_utf16_codepoint(codepoint) do
    raise ArgumentError,
          "invalid Unicode codepoint: #{inspect(codepoint)}"
  end
end

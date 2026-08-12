defmodule PaperForge.FontError do
  defexception [:message, :reason]

  @impl true
  def exception(reason) do
    %__MODULE__{
      reason: reason,
      message: format_reason(reason)
    }
  end

  defp format_reason(:invalid_font) do
    "invalid TrueType font"
  end

  defp format_reason(:unsupported_font_format) do
    "unsupported font format"
  end

  defp format_reason(:invalid_cmap) do
    "invalid TrueType cmap table"
  end

  defp format_reason({:font_not_registered, font_key}) do
    "font #{inspect(font_key)} has not been registered"
  end

  defp format_reason({:missing_glyph, font_key, codepoint}) do
    "font #{inspect(font_key)} does not contain glyph U+#{hex_codepoint(codepoint)}"
  end

  defp format_reason(reason) do
    "font error: #{inspect(reason)}"
  end

  defp hex_codepoint(codepoint) do
    codepoint
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(4, "0")
  end
end

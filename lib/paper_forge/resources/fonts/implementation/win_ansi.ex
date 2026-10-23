defmodule PaperForge.Fonts.WinAnsi do
  @moduledoc false

  alias PaperForge.FontError

  @special %{
    8364 => 128,
    8218 => 130,
    402 => 131,
    8222 => 132,
    8230 => 133,
    8224 => 134,
    8225 => 135,
    710 => 136,
    8240 => 137,
    352 => 138,
    8249 => 139,
    338 => 140,
    381 => 142,
    8216 => 145,
    8217 => 146,
    8220 => 147,
    8221 => 148,
    8226 => 149,
    8211 => 150,
    8212 => 151,
    732 => 152,
    8482 => 153,
    353 => 154,
    8250 => 155,
    339 => 156,
    382 => 158,
    376 => 159
  }

  def encode!(text, font_key) do
    text
    |> String.to_charlist()
    |> Enum.map(fn
      codepoint when codepoint in 0..127 or codepoint in 160..255 ->
        codepoint

      codepoint ->
        case Map.fetch(@special, codepoint) do
          {:ok, byte} -> byte
          :error -> raise FontError, {:missing_glyph, font_key, codepoint}
        end
    end)
    |> :erlang.list_to_binary()
  end
end

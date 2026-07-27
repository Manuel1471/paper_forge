defmodule PaperForge.Fonts.TrueType.Subsetter do
  @moduledoc """
  Builds physical TrueType subsetting plans.

  This module does not yet rewrite the final `.ttf` program. It provides
  the deterministic planning pieces needed for that step: binary hashes,
  composite glyph dependency expansion, table selection, and TrueType
  checksum calculation.
  """

  alias PaperForge.Fonts.TrueType

  @tables_to_rebuild ["glyf", "loca", "hmtx", "maxp"]

  @type plan :: %{
          binary_hash: binary(),
          requested_glyphs: [non_neg_integer()],
          glyphs: [non_neg_integer()],
          composite_dependencies: [non_neg_integer()],
          rebuild_tables: [binary()],
          checksums: %{optional(binary()) => non_neg_integer()}
        }

  @spec plan(TrueType.t(), Enumerable.t()) :: plan()
  def plan(font, glyph_ids) do
    requested_glyphs =
      glyph_ids
      |> Enum.into(MapSet.new())
      |> MapSet.put(0)

    expanded_glyphs =
      TrueType.expand_glyph_dependencies(
        font,
        requested_glyphs
      )

    %{
      binary_hash: binary_hash(font.data),
      requested_glyphs: sorted(requested_glyphs),
      glyphs: sorted(expanded_glyphs),
      composite_dependencies: sorted(MapSet.difference(expanded_glyphs, requested_glyphs)),
      rebuild_tables: @tables_to_rebuild,
      checksums: checksums(font.raw_tables)
    }
  end

  @spec binary_hash(binary()) :: binary()
  def binary_hash(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  @spec checksums(%{optional(binary()) => binary()}) :: %{optional(binary()) => non_neg_integer()}
  def checksums(tables) when is_map(tables) do
    tables
    |> Enum.map(fn {tag, data} ->
      {
        tag,
        checksum(data)
      }
    end)
    |> Map.new()
  end

  @spec checksum(binary()) :: non_neg_integer()
  def checksum(data) when is_binary(data) do
    data
    |> pad4()
    |> checksum_words(0)
  end

  defp checksum_words(<<>>, total), do: rem(total, 0x1_0000_0000)

  defp checksum_words(<<word::32, rest::binary>>, total) do
    checksum_words(
      rest,
      rem(total + word, 0x1_0000_0000)
    )
  end

  defp pad4(data) do
    padding =
      rem(
        4 - rem(byte_size(data), 4),
        4
      )

    data <> :binary.copy(<<0>>, padding)
  end

  defp sorted(values) do
    values
    |> Enum.to_list()
    |> Enum.sort()
  end
end

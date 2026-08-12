defmodule PaperForge.Fonts.TrueType.Subsetter do
  @moduledoc """
  Builds physical TrueType subsetting plans.

  The subset preserves original glyph identifiers, so the PDF Type 0 font can
  continue to use its existing CID mapping. Unused glyph programs are removed
  while composite dependencies are retained. This trades the smallest possible
  font for a safe, deterministic physical subset that needs no CID remapping.
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

  @doc """
  Rebuilds a physical TrueType subset containing only requested glyph programs
  and their composite dependencies.

  The rebuilt font preserves the original glyph count and `hmtx` metrics. This
  makes it safe for a PDF that already addresses glyphs by their original CID.
  `glyf`, `loca`, `hmtx`, and `maxp` are included in the reconstructed table
  directory and every table checksum is recalculated.
  """
  @spec subset(TrueType.t(), Enumerable.t()) :: %{data: binary(), plan: plan(), checksums: map()}
  def subset(font, glyph_ids) do
    plan = plan(font, glyph_ids)
    glyphs = MapSet.new(plan.glyphs)
    glyf = rebuild_glyf(font, glyphs)
    loca = rebuild_loca(glyf.offsets, font.index_to_loc_format)

    tables =
      font.raw_tables
      |> Map.put("glyf", glyf.data)
      |> Map.put("loca", loca)
      |> Map.put("hmtx", Map.fetch!(font.raw_tables, "hmtx"))
      |> Map.put("maxp", rebuild_maxp(Map.fetch!(font.raw_tables, "maxp"), font.number_of_glyphs))

    data = build_font(tables)
    %{data: data, plan: plan, checksums: checksums(tables)}
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

  defp rebuild_glyf(font, glyphs) do
    {parts, offsets, _offset} =
      Enum.reduce(0..(font.number_of_glyphs - 1), {[], [0], 0}, fn glyph_id,
                                                                   {parts, offsets, offset} ->
        data =
          if MapSet.member?(glyphs, glyph_id) do
            glyph_data(font, glyph_id)
          else
            <<>>
          end

        padded = pad2(data)
        next_offset = offset + byte_size(padded)
        {[padded | parts], [next_offset | offsets], next_offset}
      end)

    %{data: parts |> Enum.reverse() |> IO.iodata_to_binary(), offsets: Enum.reverse(offsets)}
  end

  defp glyph_data(font, glyph_id) do
    start_offset = Enum.at(font.glyph_offsets, glyph_id)
    end_offset = Enum.at(font.glyph_offsets, glyph_id + 1)
    binary_part(Map.fetch!(font.raw_tables, "glyf"), start_offset, end_offset - start_offset)
  end

  defp rebuild_loca(offsets, 0) do
    Enum.map(offsets, fn offset ->
      if rem(offset, 2) != 0 or div(offset, 2) > 0xFFFF,
        do: raise(ArgumentError, "subset requires long loca")

      <<div(offset, 2)::16>>
    end)
    |> IO.iodata_to_binary()
  end

  defp rebuild_loca(offsets, 1) do
    offsets |> Enum.map(&<<&1::32>>) |> IO.iodata_to_binary()
  end

  defp rebuild_maxp(<<version::32, _glyphs::16, rest::binary>>, glyph_count),
    do: <<version::32, glyph_count::16, rest::binary>>

  defp build_font(tables) do
    tables = Map.put(tables, "head", zero_check_sum_adjustment(Map.fetch!(tables, "head")))
    directory = directory(tables)
    provisional = assemble_font(tables, directory)
    adjustment = rem(0xB1B0AFBA - checksum(provisional), 0x1_0000_0000)

    final_tables =
      Map.put(tables, "head", put_check_sum_adjustment(Map.fetch!(tables, "head"), adjustment))

    assemble_font(final_tables, directory)
  end

  defp directory(tables) do
    tags = tables |> Map.keys() |> Enum.sort()
    start = 12 + length(tags) * 16

    {records, _offset} =
      Enum.map_reduce(tags, start, fn tag, offset ->
        data = Map.fetch!(tables, tag)
        {{tag, checksum(data), offset, byte_size(data)}, offset + byte_size(pad4(data))}
      end)

    records
  end

  defp assemble_font(tables, records) do
    count = length(records)
    highest_power = highest_power_of_two(count)
    search_range = highest_power * 16
    entry_selector = trunc(:math.log2(highest_power))
    range_shift = count * 16 - search_range

    header = <<0x00010000::32, count::16, search_range::16, entry_selector::16, range_shift::16>>

    directory =
      Enum.map(records, fn {tag, table_checksum, offset, length} ->
        <<tag::binary-size(4), table_checksum::32, offset::32, length::32>>
      end)

    body =
      records
      |> Enum.map(fn {tag, _checksum, _offset, _length} -> pad4(Map.fetch!(tables, tag)) end)

    IO.iodata_to_binary([header, directory, body])
  end

  defp zero_check_sum_adjustment(<<prefix::binary-size(8), _::32, rest::binary>>),
    do: <<prefix::binary, 0::32, rest::binary>>

  defp put_check_sum_adjustment(<<prefix::binary-size(8), _::32, rest::binary>>, value),
    do: <<prefix::binary, value::32, rest::binary>>

  defp pad2(data), do: if(rem(byte_size(data), 2) == 0, do: data, else: data <> <<0>>)

  defp highest_power_of_two(value),
    do: value |> :math.log2() |> floor() |> then(&trunc(:math.pow(2, &1)))
end

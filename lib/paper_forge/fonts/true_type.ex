defmodule PaperForge.Fonts.TrueType do
  @moduledoc """
  Minimal TrueType parser for embedded PDF Type 0 fonts.
  """

  alias PaperForge.FontError

  @required_tables [
    "head",
    "hhea",
    "maxp",
    "hmtx",
    "cmap",
    "name",
    "OS/2",
    "post",
    "loca",
    "glyf"
  ]

  @type t :: %{
          data: binary(),
          units_per_em: pos_integer(),
          number_of_glyphs: non_neg_integer(),
          unicode_to_gid: %{optional(non_neg_integer()) => non_neg_integer()},
          widths: %{optional(non_neg_integer()) => non_neg_integer()},
          bbox: [integer()],
          ascent: integer(),
          descent: integer(),
          cap_height: integer(),
          italic_angle: number(),
          postscript_name: binary(),
          flags: pos_integer()
        }

  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(data) when is_binary(data) do
    with {:ok, tables} <- table_directory(data),
         :ok <- require_tables(tables),
         {:ok, head} <- parse_head(table(data, tables, "head")),
         {:ok, hhea} <- parse_hhea(table(data, tables, "hhea")),
         {:ok, maxp} <- parse_maxp(table(data, tables, "maxp")),
         {:ok, widths} <-
           parse_hmtx(
             table(data, tables, "hmtx"),
             hhea.number_of_hmetrics,
             maxp.number_of_glyphs
           ),
         {:ok, unicode_to_gid} <- parse_cmap(table(data, tables, "cmap")),
         {:ok, postscript_name} <- parse_name(table(data, tables, "name")),
         {:ok, os2} <- parse_os2(table(data, tables, "OS/2")),
         {:ok, post} <- parse_post(table(data, tables, "post")) do
      {:ok,
       %{
         data: data,
         units_per_em: head.units_per_em,
         number_of_glyphs: maxp.number_of_glyphs,
         unicode_to_gid: unicode_to_gid,
         widths: widths,
         bbox: head.bbox,
         ascent: hhea.ascent,
         descent: hhea.descent,
         cap_height: os2.cap_height || hhea.ascent,
         italic_angle: post.italic_angle,
         postscript_name: postscript_name,
         flags: font_flags(post.italic_angle)
       }}
    end
  rescue
    MatchError ->
      {:error, :invalid_font}
  end

  @spec parse!(binary()) :: t()
  def parse!(data) do
    case parse(data) do
      {:ok, font} ->
        font

      {:error, reason} ->
        raise FontError, reason
    end
  end

  @spec glyph_id(t(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  def glyph_id(%{unicode_to_gid: unicode_to_gid}, codepoint) do
    case Map.get(unicode_to_gid, codepoint, 0) do
      0 -> :error
      glyph_id -> {:ok, glyph_id}
    end
  end

  @spec glyph_width(t(), non_neg_integer()) :: non_neg_integer()
  def glyph_width(%{widths: widths}, glyph_id) do
    Map.get(widths, glyph_id, 0)
  end

  @spec pdf_width(t(), non_neg_integer()) :: integer()
  def pdf_width(%{units_per_em: units_per_em} = font, glyph_id) do
    font
    |> glyph_width(glyph_id)
    |> Kernel.*(1000)
    |> div(units_per_em)
  end

  defp table_directory(<<0x00010000::32, num_tables::16, _rest::binary>> = data) do
    records_offset = 12
    records_size = num_tables * 16

    if byte_size(data) < records_offset + records_size do
      {:error, :invalid_font}
    else
      records =
        data
        |> binary_part(records_offset, records_size)
        |> parse_table_records(%{})

      {:ok, records}
    end
  end

  defp table_directory(_data) do
    {:error, :unsupported_font_format}
  end

  defp parse_table_records(<<>>, tables), do: tables

  defp parse_table_records(
         <<tag::binary-size(4), _checksum::32, offset::32, length::32, rest::binary>>,
         tables
       ) do
    parse_table_records(
      rest,
      Map.put(tables, tag, {offset, length})
    )
  end

  defp require_tables(tables) do
    missing =
      Enum.reject(@required_tables, &Map.has_key?(tables, &1))

    case missing do
      [] -> :ok
      _ -> {:error, :invalid_font}
    end
  end

  defp table(data, tables, tag) do
    {offset, length} = Map.fetch!(tables, tag)
    binary_part(data, offset, length)
  end

  defp parse_head(<<
         _version::32,
         _revision::32,
         _checksum_adjustment::32,
         0x5F0F3CF5::32,
         _flags::16,
         units_per_em::16,
         _created::64,
         _modified::64,
         x_min::signed-16,
         y_min::signed-16,
         x_max::signed-16,
         y_max::signed-16,
         _mac_style::16,
         _lowest_rec_ppem::16,
         _font_direction_hint::signed-16,
         _index_to_loc_format::signed-16,
         _glyph_data_format::signed-16,
         _rest::binary
       >>) do
    {:ok,
     %{
       units_per_em: units_per_em,
       bbox: [x_min, y_min, x_max, y_max]
     }}
  end

  defp parse_head(_data), do: {:error, :invalid_font}

  defp parse_hhea(<<
         _version::32,
         ascent::signed-16,
         descent::signed-16,
         _line_gap::signed-16,
         _advance_width_max::16,
         _min_left_side_bearing::signed-16,
         _min_right_side_bearing::signed-16,
         _x_max_extent::signed-16,
         _caret_slope_rise::signed-16,
         _caret_slope_run::signed-16,
         _caret_offset::signed-16,
         _reserved::binary-size(8),
         _metric_data_format::signed-16,
         number_of_hmetrics::16,
         _rest::binary
       >>) do
    {:ok,
     %{
       ascent: ascent,
       descent: descent,
       number_of_hmetrics: number_of_hmetrics
     }}
  end

  defp parse_hhea(_data), do: {:error, :invalid_font}

  defp parse_maxp(<<_version::32, number_of_glyphs::16, _rest::binary>>) do
    {:ok, %{number_of_glyphs: number_of_glyphs}}
  end

  defp parse_maxp(_data), do: {:error, :invalid_font}

  defp parse_hmtx(data, number_of_hmetrics, number_of_glyphs) do
    metrics_size = number_of_hmetrics * 4

    if byte_size(data) < metrics_size do
      {:error, :invalid_font}
    else
      {widths, last_width} =
        data
        |> binary_part(0, metrics_size)
        |> parse_hmetrics(0, %{}, 0)

      remaining_glyphs =
        max(number_of_glyphs - number_of_hmetrics, 0)

      widths =
        if remaining_glyphs == 0 do
          widths
        else
          Enum.reduce(
            0..(remaining_glyphs - 1)//1,
            widths,
            fn index, current ->
              Map.put(current, number_of_hmetrics + index, last_width)
            end
          )
        end

      {:ok, widths}
    end
  end

  defp parse_hmetrics(<<>>, _glyph_id, widths, last_width) do
    {widths, last_width}
  end

  defp parse_hmetrics(
         <<advance_width::16, _left_side_bearing::signed-16, rest::binary>>,
         glyph_id,
         widths,
         _last_width
       ) do
    parse_hmetrics(
      rest,
      glyph_id + 1,
      Map.put(widths, glyph_id, advance_width),
      advance_width
    )
  end

  defp parse_cmap(<<_version::16, num_tables::16, records::binary>> = cmap_table) do
    records_size = num_tables * 8

    if byte_size(records) < records_size do
      {:error, :invalid_cmap}
    else
      subtables =
        records
        |> binary_part(0, records_size)
        |> parse_cmap_records([])

      parse_best_cmap(cmap_table, subtables)
    end
  end

  defp parse_cmap(_data), do: {:error, :invalid_cmap}

  defp parse_cmap_records(<<>>, records), do: Enum.reverse(records)

  defp parse_cmap_records(
         <<platform_id::16, encoding_id::16, offset::32, rest::binary>>,
         records
       ) do
    parse_cmap_records(rest, [
      {platform_id, encoding_id, offset}
      | records
    ])
  end

  defp parse_best_cmap(cmap_data, records) do
    records
    |> Enum.sort_by(&cmap_priority/1)
    |> Enum.find_value({:error, :invalid_cmap}, fn {_platform_id, _encoding_id, offset} ->
      if byte_size(cmap_data) > offset do
        subtable =
          binary_part(cmap_data, offset, byte_size(cmap_data) - offset)

        case parse_cmap_subtable(subtable) do
          {:ok, map} -> {:ok, map}
          {:error, _reason} -> nil
        end
      end
    end)
  end

  defp cmap_priority({3, 10, _offset}), do: 0
  defp cmap_priority({0, _encoding, _offset}), do: 1
  defp cmap_priority({3, 1, _offset}), do: 2
  defp cmap_priority(_record), do: 10

  defp parse_cmap_subtable(<<4::16, length::16, _language::16, rest::binary>>) do
    if byte_size(rest) < length - 6 do
      {:error, :invalid_cmap}
    else
      parse_format4(binary_part(rest, 0, length - 6))
    end
  end

  defp parse_cmap_subtable(<<12::16, _reserved::16, length::32, _language::32, rest::binary>>) do
    if byte_size(rest) < length - 12 do
      {:error, :invalid_cmap}
    else
      parse_format12(binary_part(rest, 0, length - 12))
    end
  end

  defp parse_cmap_subtable(_subtable), do: {:error, :invalid_cmap}

  defp parse_format4(
         <<seg_count_x2::16, _search_range::16, _entry_selector::16, _range_shift::16,
           data::binary>>
       ) do
    seg_count = div(seg_count_x2, 2)
    array_size = seg_count * 2

    with true <- byte_size(data) >= array_size * 4 + 2 do
      <<end_codes::binary-size(^array_size), _reserved_pad::16, rest::binary>> = data
      <<start_codes::binary-size(^array_size), rest::binary>> = rest
      <<id_deltas::binary-size(^array_size), rest::binary>> = rest
      <<id_range_offsets::binary-size(^array_size), glyph_id_array::binary>> = rest

      segments =
        for index <- 0..(seg_count - 1) do
          %{
            index: index,
            start_code: uint16_at(start_codes, index),
            end_code: uint16_at(end_codes, index),
            id_delta: int16_at(id_deltas, index),
            id_range_offset: uint16_at(id_range_offsets, index)
          }
        end

      {:ok, format4_map(segments, id_range_offsets, glyph_id_array)}
    else
      _ -> {:error, :invalid_cmap}
    end
  end

  defp parse_format12(<<num_groups::32, groups::binary>>) do
    if byte_size(groups) < num_groups * 12 do
      {:error, :invalid_cmap}
    else
      map =
        groups
        |> binary_part(0, num_groups * 12)
        |> parse_format12_groups(%{})

      {:ok, map}
    end
  end

  defp parse_format12_groups(<<>>, map), do: map

  defp parse_format12_groups(
         <<start_char::32, end_char::32, start_glyph::32, rest::binary>>,
         map
       ) do
    map =
      Enum.reduce(start_char..end_char, map, fn codepoint, current ->
        Map.put(current, codepoint, start_glyph + codepoint - start_char)
      end)

    parse_format12_groups(rest, map)
  end

  defp format4_map(segments, id_range_offsets, glyph_id_array) do
    Enum.reduce(segments, %{}, fn segment, map ->
      if segment.start_code == 0xFFFF and segment.end_code == 0xFFFF do
        map
      else
        Enum.reduce(segment.start_code..segment.end_code, map, fn codepoint, current ->
          glyph_id =
            format4_glyph_id(
              codepoint,
              segment,
              id_range_offsets,
              glyph_id_array
            )

          if glyph_id == 0 do
            current
          else
            Map.put(current, codepoint, glyph_id)
          end
        end)
      end
    end)
  end

  defp format4_glyph_id(
         codepoint,
         %{id_range_offset: 0, id_delta: id_delta},
         _id_range_offsets,
         _glyph_id_array
       ) do
    rem(codepoint + id_delta, 65_536)
  end

  defp format4_glyph_id(codepoint, segment, id_range_offsets, glyph_id_array) do
    offset_from_range_offset =
      segment.id_range_offset +
        2 * (codepoint - segment.start_code)

    range_offset_position =
      segment.index * 2

    glyph_index_position =
      range_offset_position +
        offset_from_range_offset -
        byte_size(id_range_offsets)

    if glyph_index_position < 0 or glyph_index_position + 2 > byte_size(glyph_id_array) do
      0
    else
      glyph_id =
        uint16_at_byte(
          glyph_id_array,
          glyph_index_position
        )

      if glyph_id == 0 do
        0
      else
        rem(glyph_id + segment.id_delta, 65_536)
      end
    end
  end

  defp parse_name(<<_format::16, count::16, string_offset::16, records::binary>>) do
    records_size = count * 12

    if byte_size(records) < records_size do
      {:error, :invalid_font}
    else
      string_data =
        binary_part(
          records,
          string_offset - 6,
          byte_size(records) - (string_offset - 6)
        )

      name =
        records
        |> binary_part(0, records_size)
        |> parse_name_records(string_data, nil)

      {:ok, sanitize_pdf_name(name || "EmbeddedFont")}
    end
  end

  defp parse_name(_data), do: {:error, :invalid_font}

  defp parse_name_records(<<>>, _string_data, name), do: name

  defp parse_name_records(
         <<
           platform_id::16,
           _encoding_id::16,
           _language_id::16,
           name_id::16,
           length::16,
           offset::16,
           rest::binary
         >>,
         string_data,
         name
       ) do
    value =
      if name_id == 6 and offset + length <= byte_size(string_data) do
        raw = binary_part(string_data, offset, length)
        decode_name(platform_id, raw)
      else
        nil
      end

    parse_name_records(rest, string_data, value || name)
  end

  defp decode_name(platform_id, raw)
       when platform_id in [0, 3] do
    for <<codepoint::16-big <- raw>>,
      into: "" do
      <<codepoint::utf8>>
    end
  end

  defp decode_name(_platform_id, raw), do: raw

  defp parse_os2(data) when byte_size(data) >= 90 do
    <<_prefix::binary-size(88), cap_height::signed-16, _rest::binary>> = data
    {:ok, %{cap_height: cap_height}}
  end

  defp parse_os2(_data), do: {:ok, %{cap_height: nil}}

  defp parse_post(<<_version::32, italic_angle_fixed::signed-32, _rest::binary>>) do
    {:ok, %{italic_angle: italic_angle_fixed / 65_536}}
  end

  defp parse_post(_data), do: {:ok, %{italic_angle: 0}}

  defp uint16_at(data, index), do: uint16_at_byte(data, index * 2)

  defp uint16_at_byte(data, offset) do
    <<value::16-big>> = binary_part(data, offset, 2)
    value
  end

  defp int16_at(data, index) do
    <<value::signed-16-big>> = binary_part(data, index * 2, 2)
    value
  end

  defp font_flags(italic_angle) do
    symbolic = 4
    nonsymbolic = 32
    italic = 64

    if italic_angle == 0 do
      symbolic + nonsymbolic
    else
      symbolic + nonsymbolic + italic
    end
  end

  defp sanitize_pdf_name(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_.-]/u, "")
    |> case do
      "" -> "EmbeddedFont"
      sanitized -> sanitized
    end
  end
end

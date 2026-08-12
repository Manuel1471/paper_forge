defmodule PaperForge.Images.PNG do
  @moduledoc """
  Reads PNG metadata and image data for embedding in PDF image XObjects.

  PNG image data is stored as zlib-compressed scanlines in `IDAT`
  chunks. PDF can consume non-alpha image data directly through
  `/FlateDecode` when paired with PNG predictor decode parameters.

  For alpha PNGs, this module decodes PNG scanline filters, separates
  color bytes from alpha bytes, and returns a separate soft-mask stream.

  This module supports non-interlaced 8-bit grayscale, RGB, grayscale
  with alpha, and RGBA PNG images. Adam7 interlacing and palette PNGs
  are intentionally unsupported.
  """

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @type color_space ::
          :device_gray
          | :device_rgb

  @type metadata :: %{
          width: pos_integer(),
          height: pos_integer(),
          color_type: non_neg_integer(),
          bits_per_component: pos_integer(),
          components: pos_integer(),
          color_space: color_space(),
          compressed_data: binary(),
          smask_compressed_data: binary() | nil
        }

  @type error_reason ::
          :invalid_png
          | :missing_ihdr
          | :missing_idat
          | :truncated_chunk
          | :invalid_ihdr
          | :unsupported_compression
          | :unsupported_filter
          | :unsupported_interlace
          | :invalid_image_data
          | {:unsupported_color_type, non_neg_integer()}
          | {:unsupported_bit_depth, non_neg_integer(), non_neg_integer()}

  @doc """
  Reads PNG metadata and concatenated compressed `IDAT` data.
  """
  @spec parse(binary()) ::
          {:ok, metadata()}
          | {:error, error_reason()}
  def parse(<<@signature, chunks::binary>>) do
    with {:ok, state} <- parse_chunks(chunks, %{metadata: nil, idat: []}),
         {:ok, metadata} <- fetch_metadata(state),
         {:ok, compressed_data} <- fetch_compressed_data(state),
         {:ok, image_data} <- build_image_data(metadata, compressed_data) do
      {:ok, Map.merge(metadata, image_data)}
    end
  end

  def parse(_data) do
    {:error, :invalid_png}
  end

  @doc """
  Reads PNG metadata and raises when the binary is invalid or unsupported.
  """
  @spec parse!(binary()) :: metadata()
  def parse!(data) when is_binary(data) do
    case parse(data) do
      {:ok, metadata} ->
        metadata

      {:error, reason} ->
        raise ArgumentError,
              "invalid PNG image: #{format_error(reason)}"
    end
  end

  @doc """
  Returns whether a binary begins with the PNG signature.
  """
  @spec png?(binary()) :: boolean()
  def png?(<<@signature, _remaining::binary>>) do
    true
  end

  def png?(_data), do: false

  defp parse_chunks(<<>>, state) do
    {:ok, state}
  end

  defp parse_chunks(data, _state)
       when byte_size(data) < 12 do
    {:error, :truncated_chunk}
  end

  defp parse_chunks(
         <<
           length::32-big,
           type::binary-size(4),
           remaining::binary
         >>,
         state
       ) do
    if byte_size(remaining) < length + 4 do
      {:error, :truncated_chunk}
    else
      <<
        chunk_data::binary-size(^length),
        _crc::32-big,
        rest::binary
      >> = remaining

      state =
        apply_chunk(
          type,
          chunk_data,
          state
        )

      case {type, state} do
        {"IEND", state} ->
          {:ok, state}

        {_type, {:error, reason}} ->
          {:error, reason}

        {_type, state} ->
          parse_chunks(rest, state)
      end
    end
  end

  defp apply_chunk("IHDR", chunk_data, state) do
    case parse_ihdr(chunk_data) do
      {:ok, metadata} ->
        %{state | metadata: metadata}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_chunk("IDAT", chunk_data, state) do
    %{state | idat: [state.idat, chunk_data]}
  end

  defp apply_chunk(_type, _chunk_data, state) do
    state
  end

  defp parse_ihdr(<<
         width::32-big,
         height::32-big,
         bit_depth,
         color_type,
         compression_method,
         filter_method,
         interlace_method
       >>)
       when width > 0 and height > 0 do
    with :ok <- validate_compression(compression_method),
         :ok <- validate_filter(filter_method),
         :ok <- validate_interlace(interlace_method),
         {:ok, color_space, components, source_components, alpha?} <- color_space(color_type),
         :ok <- validate_bit_depth(bit_depth, color_type) do
      {:ok,
       %{
         width: width,
         height: height,
         color_type: color_type,
         bits_per_component: bit_depth,
         components: components,
         source_components: source_components,
         color_space: color_space,
         alpha?: alpha?
       }}
    end
  end

  defp parse_ihdr(_chunk_data) do
    {:error, :invalid_ihdr}
  end

  defp validate_compression(0), do: :ok
  defp validate_compression(_method), do: {:error, :unsupported_compression}

  defp validate_filter(0), do: :ok
  defp validate_filter(_method), do: {:error, :unsupported_filter}

  defp validate_interlace(0), do: :ok
  defp validate_interlace(_method), do: {:error, :unsupported_interlace}

  defp color_space(0), do: {:ok, :device_gray, 1, 1, false}
  defp color_space(2), do: {:ok, :device_rgb, 3, 3, false}
  defp color_space(4), do: {:ok, :device_gray, 1, 2, true}
  defp color_space(6), do: {:ok, :device_rgb, 3, 4, true}

  defp color_space(color_type) do
    {:error, {:unsupported_color_type, color_type}}
  end

  defp validate_bit_depth(8, color_type)
       when color_type in [0, 2, 4, 6] do
    :ok
  end

  defp validate_bit_depth(bit_depth, color_type) do
    {:error, {:unsupported_bit_depth, bit_depth, color_type}}
  end

  defp fetch_metadata(%{metadata: nil}) do
    {:error, :missing_ihdr}
  end

  defp fetch_metadata(%{metadata: metadata}) do
    {:ok, metadata}
  end

  defp fetch_compressed_data(%{idat: []}) do
    {:error, :missing_idat}
  end

  defp fetch_compressed_data(%{idat: idat}) do
    {:ok, IO.iodata_to_binary(idat)}
  end

  defp build_image_data(%{alpha?: false}, compressed_data) do
    {:ok,
     %{
       compressed_data: compressed_data,
       smask_compressed_data: nil
     }}
  end

  defp build_image_data(%{alpha?: true} = metadata, compressed_data) do
    with {:ok, decoded_data} <- inflate(compressed_data),
         {:ok, color_data, alpha_data} <-
           decode_and_split_scanlines(
             metadata,
             decoded_data
           ) do
      {:ok,
       %{
         compressed_data: :zlib.compress(color_data),
         smask_compressed_data: :zlib.compress(alpha_data)
       }}
    end
  end

  defp inflate(compressed_data) do
    {:ok, :zlib.uncompress(compressed_data)}
  rescue
    ErlangError ->
      {:error, :invalid_image_data}
  end

  defp decode_and_split_scanlines(metadata, data) do
    row_length =
      metadata.width *
        metadata.source_components

    decode_and_split_rows(
      data,
      metadata.height,
      row_length,
      metadata.source_components,
      zero_row(row_length),
      [],
      []
    )
  end

  defp decode_and_split_rows(
         <<>>,
         0,
         _row_length,
         _bytes_per_pixel,
         _previous_row,
         color_rows,
         alpha_rows
       ) do
    {:ok,
     color_rows
     |> Enum.reverse()
     |> IO.iodata_to_binary(),
     alpha_rows
     |> Enum.reverse()
     |> IO.iodata_to_binary()}
  end

  defp decode_and_split_rows(
         <<
           filter_type,
           rest::binary
         >>,
         remaining_rows,
         row_length,
         bytes_per_pixel,
         previous_row,
         color_rows,
         alpha_rows
       )
       when remaining_rows > 0 do
    if byte_size(rest) < row_length do
      {:error, :invalid_image_data}
    else
      <<
        encoded_row::binary-size(^row_length),
        remaining_data::binary
      >> = rest

      with {:ok, row, color_row, alpha_row} <-
             decode_and_split_row(
               filter_type,
               encoded_row,
               previous_row,
               bytes_per_pixel
             ) do
        decode_and_split_rows(
          remaining_data,
          remaining_rows - 1,
          row_length,
          bytes_per_pixel,
          row,
          [[0, color_row] | color_rows],
          [[0, alpha_row] | alpha_rows]
        )
      end
    end
  end

  defp decode_and_split_rows(
         _data,
         _remaining_rows,
         _row_length,
         _bytes_per_pixel,
         _previous_row,
         _color_rows,
         _alpha_rows
       ) do
    {:error, :invalid_image_data}
  end

  defp decode_and_split_row(0, encoded_row, _previous_row, 2) do
    {color_row, alpha_row} =
      split_alpha_row_filter_zero(
        encoded_row,
        2,
        [],
        []
      )

    {:ok, encoded_row, color_row, alpha_row}
  end

  defp decode_and_split_row(0, encoded_row, _previous_row, 4) do
    {color_row, alpha_row} =
      split_alpha_row_filter_zero(
        encoded_row,
        4,
        [],
        []
      )

    {:ok, encoded_row, color_row, alpha_row}
  end

  defp decode_and_split_row(filter_type, encoded_row, previous_row, bytes_per_pixel)
       when filter_type in [1, 2, 3, 4] do
    decode_and_split_pixels(
      encoded_row,
      previous_row,
      filter_type,
      bytes_per_pixel,
      0,
      zero_pixel(bytes_per_pixel),
      [],
      [],
      []
    )
  end

  defp decode_and_split_row(_filter_type, _encoded_row, _previous_row, _bytes_per_pixel) do
    {:error, :invalid_image_data}
  end

  defp split_alpha_row_filter_zero(<<>>, _bytes_per_pixel, color, alpha) do
    {
      color
      |> Enum.reverse()
      |> IO.iodata_to_binary(),
      alpha
      |> Enum.reverse()
      |> IO.iodata_to_binary()
    }
  end

  defp split_alpha_row_filter_zero(
         <<gray, alpha, rest::binary>>,
         2,
         color,
         mask
       ) do
    split_alpha_row_filter_zero(
      rest,
      2,
      [<<gray>> | color],
      [<<alpha>> | mask]
    )
  end

  defp split_alpha_row_filter_zero(
         <<red, green, blue, alpha, rest::binary>>,
         4,
         color,
         mask
       ) do
    split_alpha_row_filter_zero(
      rest,
      4,
      [<<red, green, blue>> | color],
      [<<alpha>> | mask]
    )
  end

  defp decode_and_split_pixels(
         <<>>,
         _previous_row,
         _filter_type,
         _bytes_per_pixel,
         _index,
         _left_pixel,
         row,
         color,
         alpha
       ) do
    {:ok, row |> Enum.reverse() |> IO.iodata_to_binary(),
     color |> Enum.reverse() |> IO.iodata_to_binary(),
     alpha |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp decode_and_split_pixels(
         <<gray, alpha, rest::binary>>,
         previous_row,
         filter_type,
         2,
         index,
         {left_gray, left_alpha},
         row,
         color,
         mask
       ) do
    decoded_gray =
      decode_component(
        gray,
        filter_type,
        left_gray,
        previous_byte(previous_row, index),
        previous_byte(previous_row, index - 2)
      )

    decoded_alpha =
      decode_component(
        alpha,
        filter_type,
        left_alpha,
        previous_byte(previous_row, index + 1),
        previous_byte(previous_row, index - 1)
      )

    decode_and_split_pixels(
      rest,
      previous_row,
      filter_type,
      2,
      index + 2,
      {decoded_gray, decoded_alpha},
      [<<decoded_gray, decoded_alpha>> | row],
      [<<decoded_gray>> | color],
      [<<decoded_alpha>> | mask]
    )
  end

  defp decode_and_split_pixels(
         <<red, green, blue, alpha, rest::binary>>,
         previous_row,
         filter_type,
         4,
         index,
         {left_red, left_green, left_blue, left_alpha},
         row,
         color,
         mask
       ) do
    decoded_red =
      decode_component(
        red,
        filter_type,
        left_red,
        previous_byte(previous_row, index),
        previous_byte(previous_row, index - 4)
      )

    decoded_green =
      decode_component(
        green,
        filter_type,
        left_green,
        previous_byte(previous_row, index + 1),
        previous_byte(previous_row, index - 3)
      )

    decoded_blue =
      decode_component(
        blue,
        filter_type,
        left_blue,
        previous_byte(previous_row, index + 2),
        previous_byte(previous_row, index - 2)
      )

    decoded_alpha =
      decode_component(
        alpha,
        filter_type,
        left_alpha,
        previous_byte(previous_row, index + 3),
        previous_byte(previous_row, index - 1)
      )

    decode_and_split_pixels(
      rest,
      previous_row,
      filter_type,
      4,
      index + 4,
      {decoded_red, decoded_green, decoded_blue, decoded_alpha},
      [<<decoded_red, decoded_green, decoded_blue, decoded_alpha>> | row],
      [<<decoded_red, decoded_green, decoded_blue>> | color],
      [<<decoded_alpha>> | mask]
    )
  end

  defp decode_component(byte, filter_type, left, up, up_left) do
    byte
    |> Kernel.+(
      predictor(
        filter_type,
        left,
        up,
        up_left
      )
    )
    |> Bitwise.band(0xFF)
  end

  defp previous_byte(_previous_row, index)
       when index < 0 do
    0
  end

  defp previous_byte(previous_row, index) do
    :binary.at(
      previous_row,
      index
    )
  end

  defp predictor(1, left, _up, _up_left), do: left
  defp predictor(2, _left, up, _up_left), do: up
  defp predictor(3, left, up, _up_left), do: div(left + up, 2)
  defp predictor(4, left, up, up_left), do: paeth(left, up, up_left)

  defp paeth(left, up, up_left) do
    estimate =
      left + up - up_left

    left_distance =
      abs(estimate - left)

    up_distance =
      abs(estimate - up)

    up_left_distance =
      abs(estimate - up_left)

    cond do
      left_distance <= up_distance and left_distance <= up_left_distance -> left
      up_distance <= up_left_distance -> up
      true -> up_left
    end
  end

  defp zero_row(length) do
    :binary.copy(
      <<0>>,
      length
    )
  end

  defp zero_pixel(2), do: {0, 0}
  defp zero_pixel(4), do: {0, 0, 0, 0}

  defp format_error(:invalid_png) do
    "missing PNG signature"
  end

  defp format_error(:missing_ihdr) do
    "missing IHDR chunk"
  end

  defp format_error(:missing_idat) do
    "missing IDAT chunk"
  end

  defp format_error(:truncated_chunk) do
    "the PNG contains a truncated chunk"
  end

  defp format_error(:invalid_ihdr) do
    "the PNG contains an invalid IHDR chunk"
  end

  defp format_error(:unsupported_compression) do
    "unsupported PNG compression method"
  end

  defp format_error(:unsupported_filter) do
    "unsupported PNG filter method"
  end

  defp format_error(:unsupported_interlace) do
    "interlaced PNG images are not supported"
  end

  defp format_error(:invalid_image_data) do
    "the PNG contains invalid image data"
  end

  defp format_error({:unsupported_color_type, color_type}) do
    "unsupported PNG color type: #{color_type}"
  end

  defp format_error({:unsupported_bit_depth, bit_depth, color_type}) do
    "unsupported bit depth #{bit_depth} for PNG color type #{color_type}"
  end
end

defmodule PaperForge.Images.JPEG do
  @moduledoc """
  Reads JPEG metadata without decoding image pixels.

  The JPEG binary can be embedded directly in the PDF using
  `/DCTDecode`.
  """

  @start_of_image 0xD8
  @end_of_image 0xD9

  @start_of_frame_markers [
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF
  ]

  @standalone_markers [
    0x01,
    0xD0,
    0xD1,
    0xD2,
    0xD3,
    0xD4,
    0xD5,
    0xD6,
    0xD7,
    @start_of_image,
    @end_of_image
  ]

  @type color_space ::
          :device_gray
          | :device_rgb
          | :device_cmyk

  @type metadata :: %{
          width: pos_integer(),
          height: pos_integer(),
          bits_per_component: pos_integer(),
          components: pos_integer(),
          color_space: color_space()
        }

  @type error_reason ::
          :invalid_jpeg
          | :missing_start_of_frame
          | :truncated_marker
          | :truncated_segment
          | :invalid_segment_length
          | :invalid_start_of_frame
          | {:unsupported_components, non_neg_integer()}

  @doc """
  Reads JPEG metadata.
  """
  @spec parse(binary()) ::
          {:ok, metadata()}
          | {:error, error_reason()}
  def parse(<<
        0xFF,
        @start_of_image,
        remaining::binary
      >>) do
    parse_segments(remaining)
  end

  def parse(_data) do
    {:error, :invalid_jpeg}
  end

  @doc """
  Reads JPEG metadata and raises when the binary is invalid.
  """
  @spec parse!(binary()) :: metadata()
  def parse!(data) when is_binary(data) do
    case parse(data) do
      {:ok, metadata} ->
        metadata

      {:error, reason} ->
        raise ArgumentError,
              "invalid JPEG image: #{format_error(reason)}"
    end
  end

  @doc """
  Returns whether a binary begins with the JPEG start-of-image marker.
  """
  @spec jpeg?(binary()) :: boolean()
  def jpeg?(<<
        0xFF,
        @start_of_image,
        _remaining::binary
      >>) do
    true
  end

  def jpeg?(_data), do: false

  defp parse_segments(<<>>) do
    {:error, :missing_start_of_frame}
  end

  defp parse_segments(<<
         0xFF,
         0xFF,
         remaining::binary
       >>) do
    parse_segments(<<
      0xFF,
      remaining::binary
    >>)
  end

  defp parse_segments(<<
         0xFF,
         marker,
         remaining::binary
       >>)
       when marker in @standalone_markers do
    case marker do
      @end_of_image ->
        {:error, :missing_start_of_frame}

      _other ->
        parse_segments(remaining)
    end
  end

  defp parse_segments(<<
         0xFF,
         marker,
         remaining::binary
       >>) do
    parse_segment(marker, remaining)
  end

  defp parse_segments(<<
         _byte,
         remaining::binary
       >>) do
    parse_segments(remaining)
  end

  defp parse_segment(
         _marker,
         remaining
       )
       when byte_size(remaining) < 2 do
    {:error, :truncated_marker}
  end

  defp parse_segment(
         marker,
         <<
           segment_length::16-big,
           remaining::binary
         >>
       ) do
    cond do
      segment_length < 2 ->
        {:error, :invalid_segment_length}

      byte_size(remaining) < segment_length - 2 ->
        {:error, :truncated_segment}

      true ->
        payload_length = segment_length - 2

        <<
          segment::binary-size(^payload_length),
          rest::binary
        >> = remaining

        if marker in @start_of_frame_markers do
          parse_start_of_frame(segment)
        else
          parse_segments(rest)
        end
    end
  end

  defp parse_start_of_frame(<<
         bits_per_component,
         height::16-big,
         width::16-big,
         components,
         _component_data::binary
       >>)
       when bits_per_component > 0 and
              width > 0 and
              height > 0 and
              components > 0 do
    case color_space(components) do
      {:ok, color_space} ->
        {:ok,
         %{
           width: width,
           height: height,
           bits_per_component: bits_per_component,
           components: components,
           color_space: color_space
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_start_of_frame(_segment) do
    {:error, :invalid_start_of_frame}
  end

  defp color_space(1), do: {:ok, :device_gray}
  defp color_space(3), do: {:ok, :device_rgb}
  defp color_space(4), do: {:ok, :device_cmyk}

  defp color_space(components) do
    {:error, {:unsupported_components, components}}
  end

  defp format_error(:invalid_jpeg) do
    "missing JPEG start-of-image marker"
  end

  defp format_error(:missing_start_of_frame) do
    "no supported start-of-frame segment was found"
  end

  defp format_error(:truncated_marker) do
    "the JPEG ends inside a marker"
  end

  defp format_error(:truncated_segment) do
    "the JPEG contains a truncated segment"
  end

  defp format_error(:invalid_segment_length) do
    "the JPEG contains an invalid segment length"
  end

  defp format_error(:invalid_start_of_frame) do
    "the JPEG contains an invalid start-of-frame segment"
  end

  defp format_error({:unsupported_components, components}) do
    "unsupported number of color components: #{components}"
  end
end

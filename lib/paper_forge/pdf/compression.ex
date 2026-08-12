defmodule PaperForge.Compression do
  @moduledoc """
  Compression helpers used by PDF streams.

  PDF content streams commonly use the `/FlateDecode` filter, which
  corresponds to zlib-compatible DEFLATE compression.
  """

  alias PaperForge.PerformanceCache

  @doc """
  Compresses binary or iodata using zlib.

  ## Example

      compressed =
        PaperForge.Compression.flate(
          "BT /F1 12 Tf ET"
        )
  """
  @spec flate(iodata()) :: binary()
  def flate(data) do
    binary = IO.iodata_to_binary(data)

    PerformanceCache.fetch(:flate, binary, fn -> :zlib.compress(binary) end, 512)
  end

  @doc """
  Decompresses data previously compressed with `flate/1`.

  This function is mainly useful for tests and debugging.
  """
  @spec inflate(binary()) :: binary()
  def inflate(data) when is_binary(data) do
    :zlib.uncompress(data)
  rescue
    ErlangError ->
      raise ArgumentError,
            "data is not a valid zlib-compressed stream"
  end
end

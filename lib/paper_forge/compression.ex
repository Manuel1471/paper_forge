defmodule PaperForge.Compression do
  @moduledoc """
  Compression helpers used by PDF streams.

  PDF content streams commonly use the `/FlateDecode` filter, which
  corresponds to zlib-compatible DEFLATE compression.
  """

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
    data
    |> IO.iodata_to_binary()
    |> :zlib.compress()
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

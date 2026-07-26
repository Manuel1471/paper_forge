defmodule PaperForge.Writer do
  @moduledoc """
  Writes a PaperForge document as a complete PDF binary.
  """

  alias PaperForge.Document
  alias PaperForge.Object
  alias PaperForge.Serializer

  @pdf_header [
    "%PDF-1.7\n",
    "%\xE2\xE3\xCF\xD3\n"
  ]

  @spec to_binary(Document.t()) :: binary()
  def to_binary(%Document{} = document) do
    header =
      IO.iodata_to_binary(@pdf_header)

    objects =
      Document.objects(document)

    {body, offsets, next_offset} =
      encode_objects(
        objects,
        byte_size(header)
      )

    maximum_object_id =
      objects
      |> Enum.map(& &1.id)
      |> Enum.max(fn -> 0 end)

    xref_offset = next_offset

    xref =
      encode_xref(
        maximum_object_id,
        offsets
      )

    trailer =
      encode_trailer(
        maximum_object_id + 1,
        document,
        xref_offset
      )

    IO.iodata_to_binary([
      header,
      body,
      xref,
      trailer
    ])
  end

  defp encode_objects(objects, initial_offset) do
    Enum.reduce(
      objects,
      {[], %{}, initial_offset},
      fn object, {chunks, offsets, current_offset} ->
        encoded_object =
          object
          |> encode_object()
          |> IO.iodata_to_binary()

        updated_offsets =
          Map.put(
            offsets,
            object.id,
            current_offset
          )

        {
          [chunks, encoded_object],
          updated_offsets,
          current_offset + byte_size(encoded_object)
        }
      end
    )
  end

  defp encode_object(%Object{} = object) do
    [
      Integer.to_string(object.id),
      " ",
      Integer.to_string(object.generation),
      " obj\n",
      Serializer.encode(object.value),
      "\n",
      "endobj\n"
    ]
  end

  defp encode_xref(maximum_object_id, offsets) do
    entries =
      Enum.map(
        1..maximum_object_id,
        fn object_id ->
          case Map.fetch(offsets, object_id) do
            {:ok, offset} ->
              encode_xref_entry(
                offset,
                0,
                "n"
              )

            :error ->
              encode_xref_entry(
                0,
                0,
                "f"
              )
          end
        end
      )

    [
      "xref\n",
      "0 ",
      Integer.to_string(maximum_object_id + 1),
      "\n",
      "0000000000 65535 f \n",
      entries
    ]
  end

  defp encode_xref_entry(
         offset,
         generation,
         status
       ) do
    formatted_offset =
      offset
      |> Integer.to_string()
      |> String.pad_leading(10, "0")

    formatted_generation =
      generation
      |> Integer.to_string()
      |> String.pad_leading(5, "0")

    [
      formatted_offset,
      " ",
      formatted_generation,
      " ",
      status,
      " \n"
    ]
  end

  defp encode_trailer(
         size,
         %Document{} = document,
         xref_offset
       ) do
    trailer_dictionary =
      %{
        "Size" => size,
        "Root" => document.root
      }
      |> maybe_put_info(document.info)

    [
      "trailer\n",
      Serializer.encode(trailer_dictionary),
      "\n",
      "startxref\n",
      Integer.to_string(xref_offset),
      "\n",
      "%%EOF\n"
    ]
  end

  defp maybe_put_info(dictionary, nil) do
    dictionary
  end

  defp maybe_put_info(dictionary, info_reference) do
    Map.put(
      dictionary,
      "Info",
      info_reference
    )
  end
end

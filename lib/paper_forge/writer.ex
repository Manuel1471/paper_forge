defmodule PaperForge.Writer do
  @moduledoc """
  Serializes a `PaperForge.Document` into a valid PDF binary.

  The writer is responsible for:

  - writing the PDF header;
  - serializing indirect objects;
  - calculating byte offsets;
  - generating the cross-reference table;
  - generating the trailer;
  - writing `startxref` and the EOF marker.
  """

  alias PaperForge.Document
  alias PaperForge.Object
  alias PaperForge.Serializer
  alias PaperForge.Validation

  @doc """
  Converts a document into a complete PDF binary.

  ## Example

      binary =
        PaperForge.Writer.to_binary(document)

      File.write!(
        "document.pdf",
        binary
      )
  """
  @spec to_binary(Document.t()) :: binary()
  def to_binary(%Document{} = document) do
    Validation.validate!(document)

    header =
      pdf_header(document)

    objects =
      Document.objects(document)

    {
      object_section,
      offsets,
      next_offset
    } =
      encode_objects(
        objects,
        byte_size(header)
      )

    maximum_object_id =
      maximum_object_id(objects)

    cross_reference =
      encode_cross_reference(
        maximum_object_id,
        offsets
      )

    trailer =
      encode_trailer(
        document,
        maximum_object_id + 1,
        next_offset
      )

    [
      header,
      object_section,
      cross_reference,
      trailer
    ]
    |> IO.iodata_to_binary()
  end

  defp pdf_header(%Document{} = document) do
    IO.iodata_to_binary([
      "%PDF-",
      document.pdf_version,
      "\n",
      "%\xE2\xE3\xCF\xD3\n"
    ])
  end

  defp encode_objects(
         objects,
         initial_offset
       ) do
    Enum.reduce(
      objects,
      {
        [],
        %{},
        initial_offset
      },
      fn object,
         {
           encoded_objects,
           offsets,
           current_offset
         } ->
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

        updated_offset =
          current_offset +
            byte_size(encoded_object)

        {
          [
            encoded_objects,
            encoded_object
          ],
          updated_offsets,
          updated_offset
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
      "\nendobj\n"
    ]
  end

  defp encode_cross_reference(
         maximum_object_id,
         offsets
       ) do
    entries =
      if maximum_object_id > 0 do
        Enum.map(
          1..maximum_object_id,
          fn object_id ->
            encode_cross_reference_entry(
              object_id,
              offsets
            )
          end
        )
      else
        []
      end

    [
      "xref\n",
      "0 ",
      Integer.to_string(maximum_object_id + 1),
      "\n",
      "0000000000 65535 f \n",
      entries
    ]
  end

  defp encode_cross_reference_entry(
         object_id,
         offsets
       ) do
    case Map.fetch(
           offsets,
           object_id
         ) do
      {:ok, offset} ->
        [
          pad_offset(offset),
          " ",
          "00000",
          " n \n"
        ]

      :error ->
        [
          "0000000000",
          " ",
          "00000",
          " f \n"
        ]
    end
  end

  defp encode_trailer(
         %Document{} = document,
         size,
         cross_reference_offset
       ) do
    trailer_dictionary =
      %{
        "Size" => size,
        "Root" => document.root_reference
      }
      |> maybe_put_info(document.info_reference)

    [
      "trailer\n",
      Serializer.encode(trailer_dictionary),
      "\n",
      "startxref\n",
      Integer.to_string(cross_reference_offset),
      "\n",
      "%%EOF\n"
    ]
  end

  defp maybe_put_info(
         dictionary,
         nil
       ) do
    dictionary
  end

  defp maybe_put_info(
         dictionary,
         info_reference
       ) do
    Map.put(
      dictionary,
      "Info",
      info_reference
    )
  end

  defp maximum_object_id([]) do
    0
  end

  defp maximum_object_id(objects) do
    objects
    |> Enum.map(fn object ->
      object.id
    end)
    |> Enum.max()
  end

  defp pad_offset(offset)
       when is_integer(offset) and
              offset >= 0 do
    offset
    |> Integer.to_string()
    |> String.pad_leading(
      10,
      "0"
    )
  end
end

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
  alias PaperForge.Reference
  alias PaperForge.Security
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
  @spec to_binary(Document.t(), keyword()) :: binary()
  def to_binary(%Document{} = document, options \\ []) do
    Validation.validate!(document)

    header =
      pdf_header(document)

    {objects, security} = prepare_objects(Document.objects(document), options)

    {
      object_section,
      offsets,
      next_offset
    } =
      encode_objects(
        objects,
        byte_size(header),
        security
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
        next_offset,
        security
      )

    [
      header,
      object_section,
      cross_reference,
      trailer
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Writes a document incrementally and atomically to a filesystem path.

  PDF objects are serialized one at a time to a temporary file in the target
  directory. The completed file is renamed into place only after the xref and
  trailer have been written successfully.
  """
  @spec write_to_file(Document.t(), Path.t(), keyword()) :: :ok | {:error, File.posix() | term()}
  def write_to_file(%Document{} = document, path, options \\ []) when is_binary(path) do
    Validation.validate!(document)
    temporary_path = temporary_path(path)

    try do
      do_write_to_file(document, path, temporary_path, options)
    rescue
      exception ->
        File.rm(temporary_path)
        reraise exception, __STACKTRACE__
    end
  end

  defp do_write_to_file(document, path, temporary_path, options) do
    result =
      case File.open(temporary_path, [:write, :binary]) do
        {:ok, io} ->
          try do
            write_document(io, document, options)
          after
            File.close(io)
          end

        {:error, reason} ->
          {:error, reason}
      end

    case result do
      :ok ->
        case File.rename(temporary_path, path) do
          :ok -> :ok
          {:error, reason} -> cleanup_error(temporary_path, reason)
        end

      {:error, reason} ->
        cleanup_error(temporary_path, reason)
    end
  end

  defp write_document(io, document, options) do
    header = pdf_header(document)
    {objects, security} = prepare_objects(Document.objects(document), options)

    with :ok <- IO.binwrite(io, header),
         {:ok, offsets, next_offset} <-
           write_objects(io, objects, byte_size(header), security),
         maximum_object_id = maximum_object_id(objects),
         :ok <- IO.binwrite(io, encode_cross_reference(maximum_object_id, offsets)),
         :ok <-
           IO.binwrite(
             io,
             encode_trailer(document, maximum_object_id + 1, next_offset, security)
           ) do
      :ok
    end
  end

  defp write_objects(io, objects, initial_offset, security) do
    {offsets, next_offset} =
      Enum.reduce(objects, {%{}, initial_offset}, fn object, {offsets, current_offset} ->
        encoded_object = encode_object(object, security)
        object_size = IO.iodata_length(encoded_object)
        :ok = IO.binwrite(io, encoded_object)

        {Map.put(offsets, object.id, current_offset), current_offset + object_size}
      end)

    {:ok, offsets, next_offset}
  end

  defp temporary_path(path) do
    path <> ".paperforge-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp cleanup_error(path, reason) do
    File.rm(path)
    {:error, reason}
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
         initial_offset,
         security
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
          |> encode_object(security)
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

        {[encoded_object | encoded_objects], updated_offsets, updated_offset}
      end
    )
    |> then(fn {encoded_objects, offsets, next_offset} ->
      {Enum.reverse(encoded_objects), offsets, next_offset}
    end)
  end

  defp encode_object(%Object{} = object, security) do
    value =
      if security && object.id != security.object_id,
        do: Security.encrypt_object(object.value, security),
        else: object.value

    [
      Integer.to_string(object.id),
      " ",
      Integer.to_string(object.generation),
      " obj\n",
      Serializer.encode(value),
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
         cross_reference_offset,
         security
       ) do
    trailer_dictionary =
      %{
        "Size" => size,
        "Root" => document.root_reference
      }
      |> maybe_put_info(document.info_reference)
      |> maybe_put_security(security)

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

  defp maybe_put_security(dictionary, nil), do: dictionary

  defp maybe_put_security(dictionary, security) do
    dictionary
    |> Map.put("Encrypt", Reference.new(security.object_id))
    |> Map.put("ID", [{:hex_string, security.file_id}, {:hex_string, security.file_id}])
  end

  defp prepare_objects(objects, options) do
    case Keyword.get(options, :security) do
      nil ->
        {objects, nil}

      security_options when is_list(security_options) ->
        case Security.prepare(objects, security_options) do
          {:ok, security, encryption_object} ->
            {Enum.sort_by(objects ++ [encryption_object], & &1.id), security}

          {:error, reason} ->
            raise ArgumentError, "invalid PDF security options: #{inspect(reason)}"
        end

      other ->
        raise ArgumentError,
              "security options must be a keyword list, received: #{inspect(other)}"
    end
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

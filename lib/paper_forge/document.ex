defmodule PaperForge.Document do
  @moduledoc """
  Represents a PDF document and manages its indirect objects.

  The document maintains the page tree, catalog, fonts, images,
  metadata, compression configuration, and indirect-object numbering.
  """

  alias PaperForge.Font
  alias PaperForge.FontRegistry
  alias PaperForge.Fonts.Builtin
  alias PaperForge.Image
  alias PaperForge.ImageRegistry
  alias PaperForge.Images.JPEG
  alias PaperForge.Images.PNG
  alias PaperForge.Metadata
  alias PaperForge.Object
  alias PaperForge.Reference
  alias PaperForge.Stream

  @pages_object_id 1
  @catalog_object_id 2
  @first_dynamic_object_id 3
  @default_compression true
  @default_pdf_version "1.7"
  @supported_pdf_versions MapSet.new(["1.4", "1.5", "1.6", "1.7"])

  defstruct objects: %{},
            next_object_id: @first_dynamic_object_id,
            root_reference: nil,
            pages_reference: nil,
            info_reference: nil,
            pdf_version: @default_pdf_version,
            font_registry: nil,
            image_registry: nil,
            compress: @default_compression

  @type t :: %__MODULE__{
          objects: %{optional(pos_integer()) => Object.t()},
          next_object_id: pos_integer(),
          root_reference: Reference.t(),
          pages_reference: Reference.t(),
          info_reference: Reference.t() | nil,
          pdf_version: binary(),
          font_registry: FontRegistry.t(),
          image_registry: ImageRegistry.t(),
          compress: boolean()
        }

  @doc """
  Creates a new PDF document.

  The initial objects are the page tree and catalog. Fonts are
  registered on demand when pages are compiled.

  ## Options

  - `:compress` — enables Flate compression. Defaults to `true`.
  - `:pdf_version` — PDF header version. Defaults to `"1.7"`.
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) when is_list(options) do
    validate_options!(options)

    compress =
      options
      |> Keyword.get(:compress, @default_compression)
      |> validate_compression!()

    pdf_version =
      options
      |> Keyword.get(:pdf_version, @default_pdf_version)
      |> validate_pdf_version!()

    pages_reference = Reference.new(@pages_object_id)
    catalog_reference = Reference.new(@catalog_object_id)

    pages_object =
      Object.new(
        @pages_object_id,
        %{
          "Type" => {:name, "Pages"},
          "Kids" => [],
          "Count" => 0
        }
      )

    catalog_object =
      Object.new(
        @catalog_object_id,
        %{
          "Type" => {:name, "Catalog"},
          "Pages" => pages_reference
        }
      )

    %__MODULE__{
      objects: %{
        @pages_object_id => pages_object,
        @catalog_object_id => catalog_object
      },
      next_object_id: @first_dynamic_object_id,
      root_reference: catalog_reference,
      pages_reference: pages_reference,
      info_reference: nil,
      pdf_version: pdf_version,
      font_registry: FontRegistry.new(),
      image_registry: ImageRegistry.new(),
      compress: compress
    }
  end

  @doc """
  Adds a new indirect object.
  """
  @spec add_object(t(), term()) :: {t(), Reference.t()}
  def add_object(
        %__MODULE__{} = document,
        value
      ) do
    object_id = document.next_object_id
    object = Object.new(object_id, value)
    reference = Reference.new(object_id)

    updated_document = %{
      document
      | objects:
          Map.put(
            document.objects,
            object_id,
            object
          ),
        next_object_id: object_id + 1
    }

    {updated_document, reference}
  end

  @doc """
  Updates an existing indirect object.
  """
  @spec update_object(
          t(),
          Reference.t(),
          (term() -> term())
        ) :: t()
  def update_object(
        %__MODULE__{} = document,
        %Reference{object_id: object_id},
        update_function
      )
      when is_function(update_function, 1) do
    object = Map.fetch!(document.objects, object_id)

    updated_object = %{
      object
      | value: update_function.(object.value)
    }

    %{
      document
      | objects:
          Map.put(
            document.objects,
            object_id,
            updated_object
          )
    }
  end

  @doc """
  Adds a page reference to the page tree.
  """
  @spec append_page(t(), Reference.t()) :: t()
  def append_page(
        %__MODULE__{} = document,
        %Reference{} = page_reference
      ) do
    update_object(
      document,
      document.pages_reference,
      fn pages_dictionary ->
        pages_dictionary
        |> Map.update!(
          "Kids",
          &(&1 ++ [page_reference])
        )
        |> Map.update!(
          "Count",
          &(&1 + 1)
        )
      end
    )
  end

  @doc """
  Registers and reuses a standard PDF font.
  """
  @spec register_font(t(), atom()) :: {t(), Font.t()}
  def register_font(
        %__MODULE__{} = document,
        font_key
      )
      when is_atom(font_key) do
    case FontRegistry.fetch(document.font_registry, font_key) do
      {:ok, font} ->
        {document, font}

      :error ->
        create_and_register_font(document, font_key)
    end
  end

  @doc """
  Registers and deduplicates a JPEG image.
  """
  @spec register_jpeg(t(), binary()) :: {t(), Image.t()}
  def register_jpeg(
        %__MODULE__{} = document,
        jpeg_data
      )
      when is_binary(jpeg_data) do
    validate_jpeg_data!(jpeg_data)

    hash = Image.hash(jpeg_data)

    case ImageRegistry.fetch(document.image_registry, hash) do
      {:ok, image} ->
        {document, image}

      :error ->
        create_and_register_jpeg(
          document,
          hash,
          jpeg_data
        )
    end
  end

  @doc """
  Registers and deduplicates a supported image.

  JPEG and PNG binaries are currently supported.
  """
  @spec register_image(t(), binary()) :: {t(), Image.t()}
  def register_image(
        %__MODULE__{} = document,
        image_data
      )
      when is_binary(image_data) do
    cond do
      JPEG.jpeg?(image_data) ->
        register_jpeg(
          document,
          image_data
        )

      PNG.png?(image_data) ->
        register_png(
          document,
          image_data
        )

      true ->
        raise ArgumentError,
              "image data is not a valid JPEG or PNG binary"
    end
  end

  @doc """
  Adds a metadata information dictionary.
  """
  @spec put_metadata(t(), Metadata.t()) :: t()
  def put_metadata(
        %__MODULE__{} = document,
        %Metadata{} = metadata
      ) do
    {document, info_reference} =
      add_object(
        document,
        Metadata.to_dictionary(metadata)
      )

    %{document | info_reference: info_reference}
  end

  @doc """
  Returns indirect objects sorted by identifier.
  """
  @spec objects(t()) :: [Object.t()]
  def objects(%__MODULE__{} = document) do
    document.objects
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end

  @doc """
  Returns the number of indirect objects.
  """
  @spec object_count(t()) :: non_neg_integer()
  def object_count(%__MODULE__{} = document) do
    map_size(document.objects)
  end

  @doc """
  Fetches an object by reference.
  """
  @spec fetch_object(t(), Reference.t()) ::
          {:ok, Object.t()} | :error
  def fetch_object(
        %__MODULE__{} = document,
        %Reference{object_id: object_id}
      ) do
    Map.fetch(document.objects, object_id)
  end

  @doc """
  Fetches an object by reference and raises when missing.
  """
  @spec fetch_object!(t(), Reference.t()) :: Object.t()
  def fetch_object!(
        %__MODULE__{} = document,
        %Reference{object_id: object_id}
      ) do
    Map.fetch!(document.objects, object_id)
  end

  defp create_and_register_font(
         %__MODULE__{} = document,
         font_key
       ) do
    definition = Builtin.fetch!(font_key)

    {document, reference} =
      add_object(
        document,
        Font.definition_to_dictionary(definition)
      )

    {updated_registry, registered_font} =
      FontRegistry.register(
        document.font_registry,
        font_key,
        reference
      )

    updated_document = %{
      document
      | font_registry: updated_registry
    }

    {updated_document, registered_font}
  end

  defp create_and_register_jpeg(
         %__MODULE__{} = document,
         hash,
         jpeg_data
       ) do
    metadata = JPEG.parse!(jpeg_data)

    resource_name =
      ImageRegistry.next_resource_name(document.image_registry)

    image_dictionary =
      %{
        "Type" => {:name, "XObject"},
        "Subtype" => {:name, "Image"},
        "Width" => metadata.width,
        "Height" => metadata.height,
        "ColorSpace" => Image.pdf_color_space(metadata.color_space),
        "BitsPerComponent" => metadata.bits_per_component,
        "Filter" => {:name, "DCTDecode"}
      }
      |> maybe_put_cmyk_decode(metadata.color_space)

    image_stream =
      Stream.new(
        jpeg_data,
        dictionary: image_dictionary
      )

    {document, image_reference} =
      add_object(document, image_stream)

    image =
      Image.new(
        hash,
        :jpeg,
        metadata,
        jpeg_data,
        resource_name,
        image_reference
      )

    {updated_registry, registered_image} =
      ImageRegistry.register(
        document.image_registry,
        image
      )

    updated_document = %{
      document
      | image_registry: updated_registry
    }

    {updated_document, registered_image}
  end

  defp register_png(
         %__MODULE__{} = document,
         png_data
       ) do
    validate_png_data!(png_data)

    hash = Image.hash(png_data)

    case ImageRegistry.fetch(document.image_registry, hash) do
      {:ok, image} ->
        {document, image}

      :error ->
        create_and_register_png(
          document,
          hash,
          png_data
        )
    end
  end

  defp create_and_register_png(
         %__MODULE__{} = document,
         hash,
         png_data
       ) do
    metadata = PNG.parse!(png_data)

    resource_name =
      ImageRegistry.next_resource_name(document.image_registry)

    {document, smask_reference} =
      maybe_add_png_smask(
        document,
        metadata
      )

    image_dictionary =
      %{
        "Type" => {:name, "XObject"},
        "Subtype" => {:name, "Image"},
        "Width" => metadata.width,
        "Height" => metadata.height,
        "ColorSpace" => Image.pdf_color_space(metadata.color_space),
        "BitsPerComponent" => metadata.bits_per_component,
        "Filter" => {:name, "FlateDecode"},
        "DecodeParms" => png_decode_params(metadata)
      }
      |> maybe_put_smask(smask_reference)

    image_stream =
      Stream.new(
        metadata.compressed_data,
        dictionary: image_dictionary
      )

    {document, image_reference} =
      add_object(document, image_stream)

    image =
      Image.new(
        hash,
        :png,
        metadata,
        png_data,
        resource_name,
        image_reference
      )

    {updated_registry, registered_image} =
      ImageRegistry.register(
        document.image_registry,
        image
      )

    updated_document = %{
      document
      | image_registry: updated_registry
    }

    {updated_document, registered_image}
  end

  defp maybe_add_png_smask(
         %__MODULE__{} = document,
         %{smask_compressed_data: nil}
       ) do
    {document, nil}
  end

  defp maybe_add_png_smask(
         %__MODULE__{} = document,
         metadata
       ) do
    smask_dictionary = %{
      "Type" => {:name, "XObject"},
      "Subtype" => {:name, "Image"},
      "Width" => metadata.width,
      "Height" => metadata.height,
      "ColorSpace" => {:name, "DeviceGray"},
      "BitsPerComponent" => 8,
      "Filter" => {:name, "FlateDecode"},
      "DecodeParms" => %{
        "Predictor" => 15,
        "Colors" => 1,
        "BitsPerComponent" => 8,
        "Columns" => metadata.width
      }
    }

    smask_stream =
      Stream.new(
        metadata.smask_compressed_data,
        dictionary: smask_dictionary
      )

    add_object(
      document,
      smask_stream
    )
  end

  defp maybe_put_smask(dictionary, nil) do
    dictionary
  end

  defp maybe_put_smask(dictionary, smask_reference) do
    Map.put(
      dictionary,
      "SMask",
      smask_reference
    )
  end

  defp png_decode_params(metadata) do
    %{
      "Predictor" => 15,
      "Colors" => metadata.components,
      "BitsPerComponent" => metadata.bits_per_component,
      "Columns" => metadata.width
    }
  end

  defp maybe_put_cmyk_decode(
         dictionary,
         :device_cmyk
       ) do
    Map.put(
      dictionary,
      "Decode",
      [1, 0, 1, 0, 1, 0, 1, 0]
    )
  end

  defp maybe_put_cmyk_decode(
         dictionary,
         _color_space
       ) do
    dictionary
  end

  defp validate_options!(options) do
    supported_options = MapSet.new([:compress, :pdf_version])

    invalid_options =
      options
      |> Keyword.keys()
      |> Enum.reject(&MapSet.member?(supported_options, &1))

    case invalid_options do
      [] ->
        :ok

      values ->
        raise ArgumentError,
              "unsupported document options: " <>
                Enum.map_join(values, ", ", &inspect/1)
    end
  end

  defp validate_compression!(value)
       when is_boolean(value) do
    value
  end

  defp validate_compression!(value) do
    raise ArgumentError,
          "compress must be true or false, received: " <>
            inspect(value)
  end

  defp validate_pdf_version!(value)
       when is_binary(value) do
    if MapSet.member?(@supported_pdf_versions, value) do
      value
    else
      raise ArgumentError,
            "unsupported PDF version #{inspect(value)}. " <>
              "Supported versions: 1.4, 1.5, 1.6, 1.7"
    end
  end

  defp validate_pdf_version!(value) do
    raise ArgumentError,
          "pdf_version must be a string, received: " <>
            inspect(value)
  end

  defp validate_jpeg_data!(jpeg_data) do
    cond do
      byte_size(jpeg_data) == 0 ->
        raise ArgumentError, "JPEG data cannot be empty"

      JPEG.jpeg?(jpeg_data) ->
        :ok

      true ->
        raise ArgumentError,
              "image data is not a valid JPEG binary"
    end
  end

  defp validate_png_data!(png_data) do
    cond do
      byte_size(png_data) == 0 ->
        raise ArgumentError, "PNG data cannot be empty"

      PNG.png?(png_data) ->
        :ok

      true ->
        raise ArgumentError,
              "image data is not a valid PNG binary"
    end
  end
end

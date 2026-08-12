defmodule PaperForge.Document do
  @moduledoc """
  Represents a PDF document and manages its indirect objects.

  The document maintains the page tree, catalog, fonts, images,
  metadata, compression configuration, and indirect-object numbering.
  """

  alias PaperForge.Font
  alias PaperForge.Document.Objects, as: DocumentObjects
  alias PaperForge.FontError
  alias PaperForge.FontRegistry
  alias PaperForge.Fonts.Builtin
  alias PaperForge.Fonts.TrueType
  alias PaperForge.Fonts.TrueType.Subsetter
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
            font_families: %{},
            font_fallbacks: %{},
            font_program_registry: %{},
            font_source_data: %{},
            default_font: :helvetica,
            page_templates: %{},
            styles: %{},
            components: %{},
            image_registry: nil,
            compress: @default_compression,
            named_destinations: %{},
            outlines_reference: nil,
            last_outline_reference: nil,
            outline_count: 0

  @type t :: %__MODULE__{
          objects: %{optional(pos_integer()) => Object.t()},
          next_object_id: pos_integer(),
          root_reference: Reference.t(),
          pages_reference: Reference.t(),
          info_reference: Reference.t() | nil,
          pdf_version: binary(),
          font_registry: FontRegistry.t(),
          font_families: %{optional(atom()) => %{optional(atom()) => atom()}},
          font_fallbacks: %{optional(atom()) => [atom()]},
          font_program_registry: %{optional(binary()) => Reference.t()},
          font_source_data: %{optional(atom()) => binary()},
          default_font: atom(),
          page_templates: %{optional(atom()) => keyword()},
          styles: %{optional(atom()) => keyword()},
          components: %{optional(atom()) => function()},
          image_registry: ImageRegistry.t(),
          compress: boolean(),
          named_destinations: %{optional(binary()) => list()},
          outlines_reference: Reference.t() | nil,
          last_outline_reference: Reference.t() | nil,
          outline_count: non_neg_integer()
        }

  @doc """
  Creates a new PDF document.

  The initial objects are the page tree and catalog. Fonts are
  registered on demand when pages are compiled.

  ## Options

  - `:compress` — enables Flate compression. Defaults to `true`.
  - `:pdf_version` — PDF header version. Defaults to `"1.7"`.
  - `:default_font` — default font key for text operations. Defaults to
    `:helvetica`.
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

    default_font =
      options
      |> Keyword.get(:default_font, :helvetica)
      |> validate_font_key!(:default_font)

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
      font_families: %{},
      font_fallbacks: %{},
      font_program_registry: %{},
      font_source_data: %{},
      default_font: default_font,
      page_templates: %{},
      styles: %{},
      components: %{},
      image_registry: ImageRegistry.new(),
      compress: compress,
      named_destinations: %{},
      outlines_reference: nil,
      last_outline_reference: nil,
      outline_count: 0
    }
  end

  @doc """
  Sets the document default font key.
  """
  @spec default_font(t(), atom()) :: t()
  def default_font(%__MODULE__{} = document, font_key)
      when is_atom(font_key) do
    %{document | default_font: font_key}
  end

  @doc "Registers fallback font keys for text that a primary TrueType font cannot render."
  @spec font_fallback(t(), atom(), [atom()]) :: t()
  def font_fallback(%__MODULE__{} = document, primary_font, fallbacks)
      when is_atom(primary_font) and is_list(fallbacks) do
    unless Enum.all?(fallbacks, &is_atom/1) do
      raise ArgumentError, "font fallbacks must be font keys"
    end

    %{document | font_fallbacks: Map.put(document.font_fallbacks, primary_font, fallbacks)}
  end

  @doc """
  Registers a reusable page template.
  """
  @spec page_template(t(), atom(), keyword()) :: t()
  def page_template(%__MODULE__{} = document, template_name, options)
      when is_atom(template_name) and is_list(options) do
    %{document | page_templates: Map.put(document.page_templates, template_name, options)}
  end

  @doc "Registers a named document style used by `PaperForge.Flow` blocks."
  @spec style(t(), atom(), keyword()) :: t()
  def style(%__MODULE__{} = document, style_name, options)
      when is_atom(style_name) and is_list(options) do
    %{document | styles: Map.put(document.styles, style_name, options)}
  end

  @doc "Registers a reusable flow component receiving an assigns map."
  @spec component(t(), atom(), (map() -> PaperForge.Flow.t())) :: t()
  def component(%__MODULE__{} = document, component_name, renderer)
      when is_atom(component_name) and is_function(renderer, 1) do
    %{document | components: Map.put(document.components, component_name, renderer)}
  end

  @doc "Embeds a file in the PDF and associates it with the document catalog."
  @spec attach(t(), binary(), binary(), keyword()) :: t()
  def attach(%__MODULE__{} = document, filename, data, options \\ [])
      when is_binary(filename) and byte_size(filename) > 0 and is_binary(data) do
    stream =
      Stream.new(data,
        dictionary: %{
          "Type" => {:name, "EmbeddedFile"},
          "Subtype" => Keyword.get(options, :mime, "application/octet-stream")
        },
        filters: [:flate]
      )

    {document, stream_reference} = add_object(document, stream)

    file_spec = %{
      "Type" => {:name, "Filespec"},
      "F" => filename,
      "UF" => filename,
      "Desc" => Keyword.get(options, :description, filename),
      "AFRelationship" => {:name, Atom.to_string(Keyword.get(options, :relationship, :Data))},
      "EF" => %{"F" => stream_reference}
    }

    {document, file_reference} = add_object(document, file_spec)

    update_object(document, document.root_reference, fn catalog ->
      names = Map.get(catalog, "Names", %{})
      existing = get_in(names, ["EmbeddedFiles", "Names"]) || []

      catalog
      |> Map.put(
        "Names",
        Map.put(names, "EmbeddedFiles", %{"Names" => existing ++ [filename, file_reference]})
      )
      |> Map.update("AF", [file_reference], &(&1 ++ [file_reference]))
    end)
  end

  @doc """
  Fetches a page template.
  """
  @spec fetch_page_template(t(), atom()) :: {:ok, keyword()} | :error
  def fetch_page_template(%__MODULE__{} = document, template_name)
      when is_atom(template_name) do
    Map.fetch(document.page_templates, template_name)
  end

  @doc "Resolves a page template and all of its `:extends` ancestors."
  @spec resolve_page_template(t(), atom()) :: {:ok, keyword()} | :error | {:error, :cycle}
  def resolve_page_template(%__MODULE__{} = document, template_name)
      when is_atom(template_name) do
    resolve_page_template(document.page_templates, template_name, MapSet.new())
  end

  defp resolve_page_template(templates, name, seen) do
    cond do
      MapSet.member?(seen, name) ->
        {:error, :cycle}

      not Map.has_key?(templates, name) ->
        :error

      true ->
        options = Map.fetch!(templates, name)

        case Keyword.get(options, :extends) do
          nil ->
            {:ok, Keyword.delete(options, :extends)}

          parent ->
            case resolve_page_template(templates, parent, MapSet.put(seen, name)) do
              {:ok, inherited} ->
                {:ok, Keyword.merge(inherited, Keyword.delete(options, :extends))}

              error ->
                error
            end
        end
    end
  end

  @doc """
  Registers a TrueType font family.

  Supported variants are `:regular`, `:bold`, `:italic`, and
  `:bold_italic`. Each variant accepts the same options as
  `register_font/3`, usually `path: "Font.ttf"` or `data: binary`.
  """
  @spec register_font_family(t(), atom(), keyword()) :: t()
  def register_font_family(%__MODULE__{} = document, family_key, variants)
      when is_atom(family_key) and is_list(variants) do
    if variants == [] do
      raise FontError, :invalid_font
    end

    Enum.reduce(
      variants,
      document,
      fn {variant, font_options}, current_document ->
        validate_font_variant!(variant)

        font_key =
          family_font_key(family_key, variant)

        current_document
        |> register_font(font_key, List.wrap(font_options))
        |> put_font_family_variant(family_key, variant, font_key)
      end
    )
  end

  @doc """
  Resolves the font key for text options, including default fonts and
  registered font-family variants.
  """
  @spec resolve_font_key(t(), keyword()) :: atom()
  def resolve_font_key(%__MODULE__{} = document, options)
      when is_list(options) do
    font_key =
      Keyword.get(
        options,
        :font,
        document.default_font
      )

    case Map.fetch(document.font_families, font_key) do
      {:ok, variants} ->
        variant =
          font_variant(
            Keyword.get(options, :weight, :regular),
            Keyword.get(options, :style, :regular)
          )

        Map.get(
          variants,
          variant,
          Map.fetch!(variants, :regular)
        )

      :error ->
        builtin_font_variant(
          font_key,
          Keyword.get(options, :weight, :regular),
          Keyword.get(options, :style, :regular)
        )
    end
  end

  @doc "Resolves a font for an entire text run, applying registered fallbacks when needed."
  @spec resolve_text_font_key(t(), keyword(), binary()) :: atom()
  def resolve_text_font_key(%__MODULE__{} = document, options, text)
      when is_list(options) and is_binary(text) do
    primary = resolve_font_key(document, options)

    [primary | Map.get(document.font_fallbacks, primary, [])]
    |> Enum.find(primary, &font_supports_text?(document, &1, text))
  end

  defp font_supports_text?(document, font_key, text) do
    case FontRegistry.fetch(document.font_registry, font_key) do
      {:ok, %{kind: :truetype} = font} ->
        text
        |> String.to_charlist()
        |> Enum.all?(fn codepoint ->
          codepoint in [?\n, ?\r] or match?({:ok, _}, TrueType.glyph_id(font, codepoint))
        end)

      {:ok, %{kind: :builtin}} ->
        true

      :error ->
        false
    end
  end

  @doc """
  Adds a new indirect object.
  """
  @spec add_object(t(), term()) :: {t(), Reference.t()}
  def add_object(
        %__MODULE__{} = document,
        value
      ),
      do: DocumentObjects.add(document, value)

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
      when is_function(update_function, 1),
      do: DocumentObjects.update(document, Reference.new(object_id), update_function)

  @doc """
  Adds a page reference to the page tree.
  """
  @spec append_page(t(), Reference.t()) :: t()
  def append_page(
        %__MODULE__{} = document,
        %Reference{} = page_reference
      ),
      do: DocumentObjects.append_page(document, page_reference)

  @doc """
  Adds or replaces a named destination in the PDF catalog.
  """
  @spec add_named_destination(t(), binary() | atom(), Reference.t(), keyword()) :: t()
  def add_named_destination(
        %__MODULE__{} = document,
        name,
        %Reference{} = page_reference,
        options \\ []
      ) do
    name =
      normalize_destination_name(name)

    destination =
      [
        page_reference,
        {:name, "XYZ"},
        Keyword.get(options, :x),
        Keyword.get(options, :y),
        Keyword.get(options, :zoom)
      ]

    document = %{
      document
      | named_destinations:
          Map.put(
            document.named_destinations,
            name,
            destination
          )
    }

    update_catalog_names(document)
  end

  @doc """
  Adds a PDF outline/bookmark item that points to a page.
  """
  @spec add_outline(t(), binary(), Reference.t(), keyword()) :: t()
  def add_outline(%__MODULE__{} = document, title, %Reference{} = page_reference, options \\ [])
      when is_binary(title) do
    {document, outlines_reference} =
      ensure_outlines(document)

    destination = [
      page_reference,
      {:name, "XYZ"},
      Keyword.get(options, :x),
      Keyword.get(options, :y),
      Keyword.get(options, :zoom)
    ]

    item_dictionary =
      %{
        "Title" => title,
        "Parent" => outlines_reference,
        "Dest" => destination
      }
      |> maybe_put_previous_outline(document.last_outline_reference)

    {document, item_reference} =
      add_object(
        document,
        item_dictionary
      )

    document =
      case document.last_outline_reference do
        nil ->
          document

        previous_reference ->
          update_object(
            document,
            previous_reference,
            &Map.put(&1, "Next", item_reference)
          )
      end

    document =
      update_object(
        document,
        outlines_reference,
        fn outlines ->
          outlines
          |> Map.put_new("First", item_reference)
          |> Map.put("Last", item_reference)
          |> Map.put("Count", document.outline_count + 1)
        end
      )

    %{
      document
      | outlines_reference: outlines_reference,
        last_outline_reference: item_reference,
        outline_count: document.outline_count + 1
    }
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
        if Builtin.valid?(font_key) do
          create_and_register_font(document, font_key)
        else
          raise FontError, {:font_not_registered, font_key}
        end
    end
  end

  @doc """
  Records Unicode text used by an embedded TrueType font.

  PaperForge keeps the embedded font file intact, but subsets the PDF
  width array and `/ToUnicode` map to the glyphs that have actually
  been used so far.
  """
  @spec use_font_text(t(), atom(), binary()) :: {t(), Font.t()}
  def use_font_text(%__MODULE__{} = document, font_key, text)
      when is_atom(font_key) and is_binary(text) do
    font =
      FontRegistry.fetch!(
        document.font_registry,
        font_key
      )

    case font.kind do
      :truetype ->
        glyph_ids =
          text
          |> String.to_charlist()
          |> Enum.reject(&(&1 in [?\n, ?\r]))
          |> Enum.map(fn codepoint ->
            case TrueType.glyph_id(font, codepoint) do
              {:ok, glyph_id} ->
                glyph_id

              :error ->
                raise FontError, {:missing_glyph, font_key, codepoint}
            end
          end)

        used_glyphs =
          Enum.reduce(
            glyph_ids,
            font.used_glyphs,
            &MapSet.put(&2, &1)
          )

        font =
          %{font | used_glyphs: used_glyphs}

        document =
          document
          |> put_font(font)
          |> update_true_type_subset(font)

        {
          document,
          font
        }

      :builtin ->
        {
          document,
          font
        }
    end
  end

  @doc """
  Registers and reuses an embedded TrueType font.
  """
  @spec register_font(t(), atom(), keyword()) :: t()
  def register_font(
        %__MODULE__{} = document,
        font_key,
        options
      )
      when is_atom(font_key) and is_list(options) do
    case FontRegistry.fetch(document.font_registry, font_key) do
      {:ok, _font} ->
        document

      :error ->
        create_and_register_true_type_font(
          document,
          font_key,
          options
        )
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

  defp normalize_destination_name(name) when is_atom(name) do
    Atom.to_string(name)
  end

  defp normalize_destination_name(name)
       when is_binary(name) and byte_size(name) > 0 do
    name
  end

  defp normalize_destination_name(name) do
    raise ArgumentError,
          "destination name must be a non-empty string or atom, received: " <>
            inspect(name)
  end

  defp update_catalog_names(%__MODULE__{} = document) do
    names =
      document.named_destinations
      |> Enum.sort_by(fn {name, _destination} -> name end)
      |> Enum.flat_map(fn {name, destination} ->
        [
          name,
          destination
        ]
      end)

    update_object(
      document,
      document.root_reference,
      fn catalog ->
        existing_names = Map.get(catalog, "Names", %{})
        Map.put(catalog, "Names", Map.put(existing_names, "Dests", %{"Names" => names}))
      end
    )
  end

  defp ensure_outlines(%__MODULE__{outlines_reference: %Reference{} = reference} = document) do
    {
      document,
      reference
    }
  end

  defp ensure_outlines(%__MODULE__{} = document) do
    {document, outlines_reference} =
      add_object(
        document,
        %{
          "Type" => {:name, "Outlines"},
          "Count" => 0
        }
      )

    document =
      update_object(
        document,
        document.root_reference,
        &Map.put(&1, "Outlines", outlines_reference)
      )

    {
      %{document | outlines_reference: outlines_reference},
      outlines_reference
    }
  end

  defp maybe_put_previous_outline(dictionary, nil) do
    dictionary
  end

  defp maybe_put_previous_outline(dictionary, previous_reference) do
    Map.put(
      dictionary,
      "Prev",
      previous_reference
    )
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

  defp create_and_register_true_type_font(
         %__MODULE__{} = document,
         font_key,
         options
       ) do
    data =
      true_type_data!(options)

    true_type =
      TrueType.parse!(data)

    resource_name =
      FontRegistry.next_resource_name(document.font_registry)

    base_font =
      embedded_base_font_name(resource_name, true_type.postscript_name)

    font_file_stream =
      Stream.new(
        data,
        dictionary: %{
          "Length1" => byte_size(data)
        },
        filters: [:flate]
      )

    {document, font_file_reference} =
      register_font_program(
        document,
        data,
        font_file_stream
      )

    descriptor_dictionary = %{
      "Type" => {:name, "FontDescriptor"},
      "FontName" => {:name, base_font},
      "Flags" => true_type.flags,
      "FontBBox" => true_type.bbox,
      "ItalicAngle" => true_type.italic_angle,
      "Ascent" => true_type.ascent,
      "Descent" => true_type.descent,
      "CapHeight" => true_type.cap_height,
      "StemV" => 80,
      "FontFile2" => font_file_reference
    }

    {document, descriptor_reference} =
      add_object(
        document,
        descriptor_dictionary
      )

    cid_font_dictionary = %{
      "Type" => {:name, "Font"},
      "Subtype" => {:name, "CIDFontType2"},
      "BaseFont" => {:name, base_font},
      "CIDSystemInfo" => %{
        "Registry" => "Adobe",
        "Ordering" => "Identity",
        "Supplement" => 0
      },
      "FontDescriptor" => descriptor_reference,
      "DW" => 1000,
      "W" => true_type_widths(true_type, MapSet.new())
    }

    {document, cid_font_reference} =
      add_object(
        document,
        cid_font_dictionary
      )

    to_unicode_stream =
      Stream.new(
        to_unicode_cmap(true_type),
        filters: [:flate]
      )

    {document, to_unicode_reference} =
      add_object(
        document,
        to_unicode_stream
      )

    type0_dictionary = %{
      "Type" => {:name, "Font"},
      "Subtype" => {:name, "Type0"},
      "BaseFont" => {:name, base_font},
      "Encoding" => {:name, "Identity-H"},
      "DescendantFonts" => [cid_font_reference],
      "ToUnicode" => to_unicode_reference
    }

    {document, type0_reference} =
      add_object(
        document,
        type0_dictionary
      )

    font =
      true_type
      |> Map.put(:postscript_name, base_font)
      |> then(
        &Font.true_type(
          font_key,
          &1,
          resource_name,
          type0_reference,
          cid_font_reference: cid_font_reference,
          to_unicode_reference: to_unicode_reference
        )
      )

    {font_registry, _registered_font} =
      FontRegistry.put(
        document.font_registry,
        font
      )

    %{
      document
      | font_registry: font_registry,
        font_source_data: Map.put(document.font_source_data, font_key, data)
    }
  end

  defp register_font_program(%__MODULE__{} = document, data, %Stream{} = stream) do
    hash =
      :crypto.hash(:sha256, data)
      |> Base.encode16(case: :lower)

    case Map.fetch(document.font_program_registry, hash) do
      {:ok, reference} ->
        {
          document,
          reference
        }

      :error ->
        {document, reference} =
          add_object(
            document,
            stream
          )

        {
          %{
            document
            | font_program_registry:
                Map.put(
                  document.font_program_registry,
                  hash,
                  reference
                )
          },
          reference
        }
    end
  end

  defp true_type_data!(options) do
    case {Keyword.fetch(options, :path), Keyword.fetch(options, :data)} do
      {{:ok, path}, :error}
      when is_binary(path) and byte_size(path) > 0 ->
        File.read!(path)

      {:error, {:ok, data}}
      when is_binary(data) and byte_size(data) > 0 ->
        data

      {{:ok, _path}, {:ok, _data}} ->
        raise FontError, :invalid_font

      _other ->
        raise FontError, :invalid_font
    end
  end

  defp embedded_base_font_name(resource_name, postscript_name) do
    prefix =
      resource_name
      |> String.trim_leading("F")
      |> String.pad_leading(4, "0")
      |> then(&("PF" <> &1))

    prefix <> "+" <> postscript_name
  end

  defp put_font(%__MODULE__{} = document, %Font{} = font) do
    font_registry =
      FontRegistry.replace(
        document.font_registry,
        font
      )

    %{document | font_registry: font_registry}
  end

  defp update_true_type_subset(%__MODULE__{} = document, %Font{kind: :truetype} = font) do
    document =
      document
      |> update_embedded_font_program(font)
      |> update_object(
        font.cid_font_reference,
        fn dictionary ->
          Map.put(
            dictionary,
            "W",
            true_type_widths(font, font.used_glyphs)
          )
        end
      )
      |> update_object(
        font.to_unicode_reference,
        fn stream ->
          %{
            stream
            | data: to_unicode_cmap(font)
          }
        end
      )

    document
  end

  defp update_embedded_font_program(document, font) do
    program_reference = font_program_reference(document, font)
    parsed = document.font_source_data |> Map.fetch!(font.key) |> TrueType.parse!()
    subset = Subsetter.subset(parsed, font.used_glyphs)

    update_object(document, program_reference, fn stream ->
      %{
        stream
        | data: subset.data,
          dictionary: Map.put(stream.dictionary, "Length1", byte_size(subset.data))
      }
    end)
  end

  defp font_program_reference(document, font) do
    cid_font = document |> fetch_object!(font.cid_font_reference) |> Map.fetch!(:value)
    descriptor_reference = Map.fetch!(cid_font, "FontDescriptor")
    descriptor = document |> fetch_object!(descriptor_reference) |> Map.fetch!(:value)
    Map.fetch!(descriptor, "FontFile2")
  end

  defp true_type_widths(true_type, used_glyphs) do
    glyph_ids =
      if MapSet.size(used_glyphs) == 0 do
        []
      else
        used_glyphs
        |> MapSet.to_list()
        |> Enum.sort()
      end

    Enum.flat_map(glyph_ids, fn glyph_id ->
      [
        glyph_id,
        [
          TrueType.pdf_width(
            true_type,
            glyph_id
          )
        ]
      ]
    end)
  end

  defp to_unicode_cmap(true_type) do
    used_glyphs =
      Map.get(
        true_type,
        :used_glyphs,
        MapSet.new()
      )

    entries =
      true_type.unicode_to_gid
      |> Enum.filter(fn {_codepoint, glyph_id} ->
        MapSet.size(used_glyphs) == 0 or
          MapSet.member?(used_glyphs, glyph_id)
      end)
      |> Enum.reject(fn {_codepoint, glyph_id} ->
        glyph_id == 0
      end)
      |> Enum.sort_by(fn {_codepoint, glyph_id} ->
        glyph_id
      end)
      |> Enum.uniq_by(fn {_codepoint, glyph_id} ->
        glyph_id
      end)

    [
      "/CIDInit /ProcSet findresource begin\n",
      "12 dict begin\n",
      "begincmap\n",
      "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def\n",
      "/CMapName /PaperForge-ToUnicode def\n",
      "/CMapType 2 def\n",
      "1 begincodespacerange\n",
      "<0000> <FFFF>\n",
      "endcodespacerange\n",
      encode_bfchar_entries(entries),
      "endcmap\n",
      "CMapName currentdict /CMap defineresource pop\n",
      "end\n",
      "end\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp encode_bfchar_entries(entries) do
    entries
    |> Enum.chunk_every(100)
    |> Enum.map(fn chunk ->
      [
        Integer.to_string(length(chunk)),
        " beginbfchar\n",
        Enum.map(chunk, fn {codepoint, glyph_id} ->
          [
            "<",
            hex16(glyph_id),
            "> <",
            unicode_hex(codepoint),
            ">\n"
          ]
        end),
        "endbfchar\n"
      ]
    end)
  end

  defp hex16(value) do
    value
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(4, "0")
  end

  defp unicode_hex(codepoint)
       when codepoint <= 0xFFFF do
    hex16(codepoint)
  end

  defp unicode_hex(codepoint) do
    adjusted =
      codepoint - 0x10000

    high =
      0xD800 + Bitwise.bsr(adjusted, 10)

    low =
      0xDC00 + Bitwise.band(adjusted, 0x3FF)

    hex16(high) <> hex16(low)
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
    supported_options = MapSet.new([:compress, :pdf_version, :default_font])

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

  defp validate_font_key!(value, _option)
       when is_atom(value) do
    value
  end

  defp validate_font_key!(value, option) do
    raise ArgumentError,
          "#{option} must be an atom, received: " <> inspect(value)
  end

  defp validate_font_variant!(variant)
       when variant in [:regular, :bold, :italic, :bold_italic] do
    :ok
  end

  defp validate_font_variant!(variant) do
    raise ArgumentError,
          "unsupported font variant #{inspect(variant)}. " <>
            "Expected :regular, :bold, :italic, or :bold_italic"
  end

  defp put_font_family_variant(document, family_key, variant, font_key) do
    font_families =
      Map.update(
        document.font_families,
        family_key,
        %{variant => font_key},
        &Map.put(&1, variant, font_key)
      )

    %{document | font_families: font_families}
  end

  defp family_font_key(family_key, variant) do
    :"#{family_key}_#{variant}"
  end

  defp font_variant(:bold, :italic), do: :bold_italic
  defp font_variant(:bold, :oblique), do: :bold_italic
  defp font_variant(:bold, _style), do: :bold
  defp font_variant(_weight, :italic), do: :italic
  defp font_variant(_weight, :oblique), do: :italic
  defp font_variant(_weight, _style), do: :regular

  defp builtin_font_variant(:helvetica, :bold, style) when style in [:italic, :oblique],
    do: :helvetica_bold_oblique

  defp builtin_font_variant(:helvetica, :bold, _style), do: :helvetica_bold

  defp builtin_font_variant(:helvetica, _weight, style) when style in [:italic, :oblique],
    do: :helvetica_oblique

  defp builtin_font_variant(:times_roman, :bold, style) when style in [:italic, :oblique],
    do: :times_bold_italic

  defp builtin_font_variant(:times_roman, :bold, _style), do: :times_bold

  defp builtin_font_variant(:times_roman, _weight, style) when style in [:italic, :oblique],
    do: :times_italic

  defp builtin_font_variant(:courier, :bold, style) when style in [:italic, :oblique],
    do: :courier_bold_oblique

  defp builtin_font_variant(:courier, :bold, _style), do: :courier_bold

  defp builtin_font_variant(:courier, _weight, style) when style in [:italic, :oblique],
    do: :courier_oblique

  defp builtin_font_variant(font_key, _weight, _style), do: font_key

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

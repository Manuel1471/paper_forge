defmodule PaperForge do
  @moduledoc """
  Document engineering for the BEAM.

  PaperForge provides the public API for building, securing, validating, and
  transforming native PDF documents entirely in Elixir. It includes functional
  document construction, measured layout, exact page drawing, metadata,
  serialization, and production output workflows.

  ## Example

      alias PaperForge.Page

      document =
        PaperForge.new(compress: true)
        |> PaperForge.metadata(
          title: "PaperForge example",
          author: "Manuel García"
        )
        |> PaperForge.add_page(
          [
            size: :a4,
            origin: :top_left,
            margins: 72
          ],
          fn page ->
            page
            |> Page.text(
              "Hello PaperForge",
              y: 72,
              width: Page.content_width(page),
              align: :center,
              font: :helvetica_bold,
              size: 24
            )
            |> Page.text_box(
              "PaperForge generates PDF documents directly in Elixir.",
              y: 130,
              width: Page.content_width(page),
              font: :helvetica,
              size: 12,
              line_height: 16
            )
          end
        )

      PaperForge.write!(document, "example.pdf")
  """

  alias PaperForge.Document
  alias PaperForge.Flow
  alias PaperForge.Legacy.Flow, as: LegacyFlow
  alias PaperForge.Legacy.Table, as: LegacyTable
  alias PaperForge.Layout.Engine
  alias PaperForge.Metadata
  alias PaperForge.Page
  alias PaperForge.PageTemplateError
  alias PaperForge.Telemetry
  alias PaperForge.Writer
  alias PaperForge.Validation

  @doc """
  Creates a new empty PDF document.

  ## Options

  - `:compress` — enables Flate compression for page content streams.
    Defaults to `true`.
  - `:pdf_version` — PDF header version. Defaults to `"1.7"`.
  """
  @spec new(keyword()) :: Document.t()
  def new(options \\ []) when is_list(options) do
    Document.new(options)
  end

  @doc """
  Registers an embedded TrueType font.

  ## Options

  - `:path` — path to a `.ttf` file.
  - `:data` — TrueType font binary.
  """
  @spec register_font(Document.t(), atom(), keyword()) :: Document.t()
  def register_font(
        %Document{} = document,
        font_key,
        options
      )
      when is_atom(font_key) and is_list(options) do
    Document.register_font(
      document,
      font_key,
      options
    )
  end

  @doc """
  Registers a TrueType font family.

  Variants may include `:regular`, `:bold`, `:italic`, and `:bold_italic`.
  Each variant accepts the same options as `register_font/3`.
  """
  @spec register_font_family(Document.t(), atom(), keyword()) :: Document.t()
  def register_font_family(
        %Document{} = document,
        family_key,
        variants
      )
      when is_atom(family_key) and is_list(variants) do
    Document.register_font_family(
      document,
      family_key,
      variants
    )
  end

  @doc """
  Sets the default font key used by text operations that omit `:font`.
  """
  @spec default_font(Document.t(), atom()) :: Document.t()
  def default_font(
        %Document{} = document,
        font_key
      )
      when is_atom(font_key) do
    Document.default_font(
      document,
      font_key
    )
  end

  @doc "Registers fallback embedded fonts for a primary font."
  @spec font_fallback(Document.t(), atom(), [atom()]) :: Document.t()
  def font_fallback(%Document{} = document, primary_font, fallbacks)
      when is_atom(primary_font) and is_list(fallbacks) do
    Document.font_fallback(document, primary_font, fallbacks)
  end

  @doc """
  Registers a reusable page template.
  """
  @spec page_template(Document.t(), atom(), keyword()) :: Document.t()
  def page_template(%Document{} = document, template_name, options)
      when is_atom(template_name) and is_list(options) do
    Document.page_template(document, template_name, options)
  end

  @doc "Registers a named style for headings, paragraphs, tables, and other flow blocks."
  @spec style(Document.t(), atom(), keyword()) :: Document.t()
  def style(%Document{} = document, style_name, options)
      when is_atom(style_name) and is_list(options) do
    Document.style(document, style_name, options)
  end

  @doc "Registers a reusable `PaperForge.Flow` component."
  @spec component(Document.t(), atom(), (map() -> Flow.t())) :: Document.t()
  def component(%Document{} = document, component_name, renderer)
      when is_atom(component_name) and is_function(renderer, 1) do
    Document.component(document, component_name, renderer)
  end

  @doc """
  Renders a unified document flow.
  """
  @spec flow(Document.t(), (Flow.t() -> Flow.t()) | keyword()) :: Document.t()
  def flow(%Document{} = document, flow_function)
      when is_function(flow_function, 1) do
    {document, _report} =
      layout(
        document,
        flow_function,
        []
      )

    document
  end

  @doc """
  Renders a unified document flow and returns a layout report.
  """
  @spec layout(Document.t(), (Flow.t() -> Flow.t()), keyword()) :: {Document.t(), map()}
  def layout(%Document{} = document, flow_function, options \\ [])
      when is_function(flow_function, 1) and is_list(options) do
    flow =
      Flow.new()
      |> flow_function.()

    options =
      options
      |> resolve_template_options(document)

    Engine.render(
      document,
      flow,
      options
    )
  end

  @doc """
  Returns a structured debug report for a document.
  """
  @spec debug(Document.t(), keyword()) :: map()
  def debug(%Document{} = document, options \\ []) when is_list(options) do
    pages =
      document
      |> Document.fetch_object!(document.pages_reference)
      |> Map.fetch!(:value)

    %{
      pages: pages["Count"],
      objects: Document.object_count(document),
      fonts: map_size(document.font_registry.fonts),
      images: map_size(document.image_registry.images),
      show_margins: Keyword.get(options, :show_margins, false),
      show_blocks: Keyword.get(options, :show_blocks, false),
      show_baselines: Keyword.get(options, :show_baselines, false),
      show_page_breaks: Keyword.get(options, :show_page_breaks, false)
    }
  end

  @doc """
  Adds a page to a document.

  The second argument can be an existing `PaperForge.Page` or a function
  that receives and returns a page.
  """
  @spec add_page(
          Document.t(),
          Page.t() | (Page.t() -> Page.t())
        ) :: Document.t()
  def add_page(document, page_or_function)

  def add_page(
        %Document{} = document,
        %Page{} = page
      ) do
    Page.add_to_document(page, document)
  end

  def add_page(
        %Document{} = document,
        page_function
      )
      when is_function(page_function, 1) do
    add_page(document, [], page_function)
  end

  @doc """
  Creates a page with the provided options and adds it to the document.

  Supported page options include:

  - `:size`
  - `:orientation`
  - `:origin`
  - `:margins`
  """
  @spec add_page(
          Document.t(),
          keyword(),
          (Page.t() -> Page.t())
        ) :: Document.t()
  def add_page(
        %Document{} = document,
        page_options,
        page_function
      )
      when is_list(page_options) and
             is_function(page_function, 1) do
    page =
      page_options
      |> Page.new()
      |> page_function.()

    unless match?(%Page{}, page) do
      raise ArgumentError,
            "page callback must return a PaperForge.Page, received: " <>
              inspect(page)
    end

    add_page(document, page)
  end

  @doc """
  Adds vertically flowed text blocks across as many pages as needed.

  The flow uses top-left page coordinates so `:y` moves downward as
  content is added.
  """
  @spec add_flow(Document.t(), [iodata()], keyword(), keyword()) :: Document.t()
  def add_flow(
        %Document{} = document,
        blocks,
        page_options \\ [],
        options \\ []
      )
      when is_list(blocks) and is_list(page_options) and is_list(options) do
    {document, _report} =
      layout_flow(
        document,
        blocks,
        page_options,
        options
      )

    document
  end

  @doc """
  Adds vertically flowed text blocks and returns a layout report.
  """
  @spec layout_flow(Document.t(), [iodata()], keyword(), keyword()) ::
          {Document.t(), map()}
  def layout_flow(
        %Document{} = document,
        blocks,
        page_options \\ [],
        options \\ []
      )
      when is_list(blocks) and is_list(page_options) and is_list(options) do
    LegacyFlow.layout(document, blocks, page_options, options)
  end

  @doc """
  Adds a table across pages.

  When `:repeat_header` is true, the first `:header_rows` rows are
  repeated at the top of every generated page. Rows are currently kept
  together; pass `row_split: :keep`.
  """
  @spec add_table(Document.t(), [[term()]], keyword(), keyword()) :: Document.t()
  def add_table(
        %Document{} = document,
        rows,
        page_options \\ [],
        options \\ []
      )
      when is_list(rows) and is_list(page_options) and is_list(options) do
    LegacyTable.add(document, rows, page_options, options)
  end

  @doc """
  Adds metadata to the document.
  """
  @spec metadata(Document.t(), keyword()) :: Document.t()
  def metadata(
        %Document{} = document,
        options
      )
      when is_list(options) do
    metadata = Metadata.new(options)
    Document.put_metadata(document, metadata)
  end

  @doc "Embeds a document attachment."
  @spec attach(Document.t(), binary(), binary(), keyword()) :: Document.t()
  def attach(%Document{} = document, filename, data, options \\ []) do
    Document.attach(document, filename, data, options)
  end

  @doc "Applies watermarks, tamper-evident metadata, and resource policies."
  @spec protect(Document.t(), keyword()) :: Document.t()
  def protect(%Document{} = document, options \\ []) do
    PaperForge.Protection.apply(document, options)
  end

  @doc "Returns the stable SHA-256 fingerprint of a document."
  @spec fingerprint(Document.t()) :: binary()
  def fingerprint(%Document{} = document), do: PaperForge.Protection.fingerprint(document)

  @doc "Applies structural PDF/A and PDF/UA conformance profiles."
  @spec comply(Document.t(), keyword()) :: Document.t()
  def comply(%Document{} = document, options) do
    PaperForge.Compliance.apply(document, options)
  end

  @doc """
  Serializes a document into a complete PDF binary.
  """
  @spec to_binary(Document.t(), keyword()) :: binary()
  def to_binary(%Document{} = document, options \\ []) do
    Telemetry.render(document, :binary, fn -> Writer.to_binary(document, options) end)
  end

  @doc "Validates document structure and returns a deterministic validation report."
  @spec validate(Document.t()) :: {:ok, map()} | {:error, [map()]}
  def validate(%Document{} = document), do: Validation.validate(document)

  @doc "Validates document structure and raises `PaperForge.ValidationError` on failure."
  @spec validate!(Document.t()) :: map()
  def validate!(%Document{} = document), do: Validation.validate!(document)

  @doc """
  Writes a document to a file.
  """
  @spec write(Document.t(), Path.t(), keyword()) ::
          :ok | {:error, File.posix()}
  def write(
        %Document{} = document,
        path,
        options \\ []
      ) do
    path = validate_path!(path)

    Telemetry.render(document, {:file, path}, fn ->
      Writer.write_to_file(document, path, options)
    end)
  end

  @doc """
  Writes a document to a file and raises when writing fails.
  """
  @spec write!(Document.t(), Path.t(), keyword()) :: :ok
  def write!(
        %Document{} = document,
        path,
        options \\ []
      ) do
    path = validate_path!(path)

    Telemetry.render(document, {:file, path}, fn ->
      case Writer.write_to_file(document, path, options) do
        :ok -> :ok
        {:error, reason} -> raise File.Error, reason: reason, action: "write file", path: path
      end
    end)
  end

  defp resolve_template_options(options, document) do
    case Keyword.get(options, :template) do
      nil ->
        options

      template_name ->
        case Document.resolve_page_template(document, template_name) do
          {:ok, template_options} ->
            page_options =
              template_options
              |> Keyword.take([:size, :orientation, :margins])
              |> Keyword.put_new(:origin, :top_left)

            options
            |> Keyword.put(
              :page_options,
              Keyword.merge(page_options, Keyword.get(options, :page_options, []))
            )
            |> Keyword.put_new(:header, Keyword.get(template_options, :header))
            |> Keyword.put_new(:footer, Keyword.get(template_options, :footer))

          :error ->
            raise PageTemplateError,
              reason: :unknown_template,
              template: template_name

          {:error, :cycle} ->
            raise PageTemplateError,
              reason: :template_cycle,
              template: template_name
        end
    end
  end

  defp validate_path!(path)
       when is_binary(path) and byte_size(path) > 0 do
    path
  end

  defp validate_path!(path) do
    raise ArgumentError,
          "PDF output path must be a non-empty string, received: " <>
            inspect(path)
  end
end

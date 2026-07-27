defmodule PaperForge do
  @moduledoc """
  Public API for creating PDF documents with PaperForge.

  PaperForge provides a functional API for creating documents, adding
  pages, assigning metadata, serializing PDFs, and writing them to disk.

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
  alias PaperForge.Metadata
  alias PaperForge.Page
  alias PaperForge.TextWrapper
  alias PaperForge.Writer

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
    page_options =
      Keyword.put_new(
        page_options,
        :origin,
        :top_left
      )

    page = Page.new(page_options)
    page = decorate_flow_page(page, options)

    font_key =
      Document.resolve_font_key(
        document,
        options
      )

    {document, font} =
      Document.register_font(
        document,
        font_key
      )

    flow_state = %{
      document: document,
      page: page,
      page_options: page_options,
      cursor_y: Keyword.get(options, :y, Page.content_top(page)),
      bottom_y: Page.content_bottom(page),
      x: Keyword.get(options, :x, Page.content_left(page)),
      width: Keyword.get(options, :width, Page.content_width(page)),
      font_key: font_key,
      font: font,
      size: Keyword.get(options, :size, 12),
      line_height: Keyword.get(options, :line_height, Keyword.get(options, :size, 12) * 1.2),
      gap: Keyword.get(options, :gap, Keyword.get(options, :size, 12) * 0.5),
      options: options,
      has_content?: false,
      pages_added: 0,
      blocks_seen: 0,
      overflow?: false
    }

    state =
      blocks
      |> Enum.map(&IO.iodata_to_binary/1)
      |> Enum.reduce(flow_state, &flow_block/2)
      |> finish_flow()

    {
      state.document,
      %{
        pages_added: state.pages_added,
        blocks: state.blocks_seen,
        overflow?: state.overflow? or state.pages_added > 1
      }
    }
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
    validate_row_split!(Keyword.get(options, :row_split, :keep))

    page_options =
      Keyword.put_new(
        page_options,
        :origin,
        :top_left
      )

    page = Page.new(page_options)
    row_height = Keyword.get(options, :row_height, 24)
    y = Keyword.get(options, :y, Page.content_top(page))
    available_height = Page.content_bottom(page) - y
    rows_per_page = max(floor(available_height / row_height), 1)

    header_rows =
      if Keyword.get(options, :repeat_header, false),
        do: Keyword.get(options, :header_rows, 1),
        else: 0

    {headers, body_rows} = Enum.split(rows, header_rows)
    body_capacity = max(rows_per_page - header_rows, 1)

    body_rows
    |> Enum.chunk_every(body_capacity)
    |> Enum.reduce(document, fn chunk, current_document ->
      page_rows = headers ++ chunk

      add_page(
        current_document,
        page_options,
        fn current_page ->
          Page.table(
            current_page,
            page_rows,
            table_page_options(current_page, options, header_rows > 0)
          )
        end
      )
    end)
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

  @doc """
  Serializes a document into a complete PDF binary.
  """
  @spec to_binary(Document.t()) :: binary()
  def to_binary(%Document{} = document) do
    Writer.to_binary(document)
  end

  @doc """
  Writes a document to a file.
  """
  @spec write(Document.t(), Path.t()) ::
          :ok | {:error, File.posix()}
  def write(
        %Document{} = document,
        path
      ) do
    path = validate_path!(path)
    File.write(path, to_binary(document))
  end

  @doc """
  Writes a document to a file and raises when writing fails.
  """
  @spec write!(Document.t(), Path.t()) :: :ok
  def write!(
        %Document{} = document,
        path
      ) do
    path = validate_path!(path)
    File.write!(path, to_binary(document))
  end

  defp validate_row_split!(:keep), do: :ok

  defp validate_row_split!(row_split) do
    raise ArgumentError,
          "unsupported row split policy #{inspect(row_split)}. " <>
            "Expected :keep"
  end

  defp table_page_options(%Page{} = page, options, header?) do
    options
    |> Keyword.put_new(:x, Page.content_left(page))
    |> Keyword.put_new(:y, Page.content_top(page))
    |> Keyword.put_new(:width, Page.content_width(page))
    |> Keyword.put(:header, header?)
    |> Keyword.delete(:repeat_header)
    |> Keyword.delete(:header_rows)
    |> Keyword.delete(:row_split)
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

  defp flow_block("", state), do: state

  defp flow_block(block, state) do
    lines =
      TextWrapper.wrap(
        block,
        width: state.width,
        font: state.font_key,
        font_instance: state.font,
        size: state.size
      )

    state =
      %{state | blocks_seen: state.blocks_seen + 1}

    if Keyword.get(state.options, :keep_together, false) and
         state.has_content? and
         length(lines) * state.line_height > state.bottom_y - state.cursor_y do
      state
      |> next_flow_page()
      |> then(&flow_lines(lines, &1))
    else
      flow_lines(lines, state)
    end
  end

  defp flow_lines([], state), do: state

  defp flow_lines(lines, state) do
    state =
      if state.cursor_y >= state.bottom_y do
        next_flow_page(state)
      else
        state
      end

    available_height =
      state.bottom_y - state.cursor_y

    max_lines =
      max(
        floor(available_height / state.line_height),
        1
      )

    {visible_lines, remaining_lines} =
      Enum.split(
        lines,
        max_lines
      )

    text =
      Enum.join(
        visible_lines,
        "\n"
      )

    consumed_height =
      length(visible_lines) * state.line_height

    page =
      Page.text_box(
        state.page,
        text,
        flow_text_options(state, consumed_height)
      )

    state = %{
      state
      | page: page,
        cursor_y: state.cursor_y + consumed_height + state.gap,
        has_content?: true,
        overflow?: state.overflow? or remaining_lines != []
    }

    if remaining_lines == [] do
      state
    else
      state
      |> next_flow_page()
      |> then(&flow_lines(remaining_lines, &1))
    end
  end

  defp flow_text_options(state, height) do
    state.options
    |> Keyword.put(:x, state.x)
    |> Keyword.put(:y, state.cursor_y)
    |> Keyword.put(:width, state.width)
    |> Keyword.put(:height, height)
    |> Keyword.put(:font, state.font_key)
    |> Keyword.put(:size, state.size)
    |> Keyword.put(:line_height, state.line_height)
  end

  defp next_flow_page(%{has_content?: false} = state), do: state

  defp next_flow_page(state) do
    document =
      add_page(
        state.document,
        state.page
      )

    page =
      Page.new(state.page_options)
      |> decorate_flow_page(state.options)

    %{
      state
      | document: document,
        page: page,
        cursor_y: Page.content_top(page),
        bottom_y: Page.content_bottom(page),
        has_content?: false,
        pages_added: state.pages_added + 1
    }
  end

  defp finish_flow(%{has_content?: true} = state) do
    document =
      add_page(
        state.document,
        state.page
      )

    %{state | document: document, pages_added: state.pages_added + 1}
  end

  defp finish_flow(state) do
    state
  end

  defp decorate_flow_page(%Page{} = page, options) do
    page
    |> maybe_add_header(options)
    |> maybe_add_footer(options)
  end

  defp maybe_add_header(%Page{} = page, options) do
    case Keyword.get(options, :header) do
      nil ->
        page

      header when is_binary(header) ->
        Page.text(
          page,
          header,
          x: Page.content_left(page),
          y: Keyword.get(options, :header_y, max(Page.content_top(page) - 28, 12)),
          width: Page.content_width(page),
          align: Keyword.get(options, :header_align, :center),
          font: Keyword.get(options, :header_font, Keyword.get(options, :font, :helvetica)),
          size: Keyword.get(options, :header_size, 9)
        )

      header_function when is_function(header_function, 1) ->
        header_function.(page)
    end
  end

  defp maybe_add_footer(%Page{} = page, options) do
    case Keyword.get(options, :footer) do
      nil ->
        page

      footer when is_binary(footer) ->
        Page.text(
          page,
          footer,
          x: Page.content_left(page),
          y:
            Keyword.get(options, :footer_y, min(Page.content_bottom(page) + 22, page.height - 12)),
          width: Page.content_width(page),
          align: Keyword.get(options, :footer_align, :center),
          font: Keyword.get(options, :footer_font, Keyword.get(options, :font, :helvetica)),
          size: Keyword.get(options, :footer_size, 9)
        )

      footer_function when is_function(footer_function, 1) ->
        footer_function.(page)
    end
  end
end

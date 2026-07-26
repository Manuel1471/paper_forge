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

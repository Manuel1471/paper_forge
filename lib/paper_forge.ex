defmodule PaperForge do
  @moduledoc """
  A pure Elixir PDF generation library.

  PaperForge generates PDF documents directly without using
  browsers or external PDF rendering programs.
  """

  alias PaperForge.Document
  alias PaperForge.Metadata
  alias PaperForge.Page
  alias PaperForge.Writer

  @doc """
  Creates a new PDF document.
  """
  @spec new() :: Document.t()
  def new do
    Document.new()
  end

  @doc """
  Adds a previously created page to a document.
  """
  @spec add_page(Document.t(), Page.t()) :: Document.t()
  def add_page(
        %Document{} = document,
        %Page{} = page
      ) do
    Page.add_to_document(
      page,
      document
    )
  end

  @doc """
  Creates and configures a page using a function.

  ## Example

      PaperForge.add_page(document, fn page ->
        PaperForge.Page.text(page, "Hello", x: 72, y: 750)
      end)
  """
  @spec add_page(
          Document.t(),
          (Page.t() -> Page.t())
        ) :: Document.t()
  def add_page(
        %Document{} = document,
        function
      )
      when is_function(function, 1) do
    add_page(
      document,
      [],
      function
    )
  end

  @doc """
  Creates a page with options and configures it using a function.
  """
  @spec add_page(
          Document.t(),
          keyword(),
          (Page.t() -> Page.t())
        ) :: Document.t()
  def add_page(
        %Document{} = document,
        options,
        function
      )
      when is_list(options) and is_function(function, 1) do
    page =
      options
      |> Page.new()
      |> function.()

    add_page(
      document,
      page
    )
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
    metadata =
      Metadata.new(options)

    Document.put_metadata(
      document,
      metadata
    )
  end

  @doc """
  Converts the document to a PDF binary.
  """
  @spec to_binary(Document.t()) :: binary()
  def to_binary(%Document{} = document) do
    Writer.to_binary(document)
  end

  @doc """
  Writes the PDF to a file.
  """
  @spec write(Document.t(), Path.t()) ::
          :ok | {:error, File.posix()}
  def write(
        %Document{} = document,
        path
      ) do
    File.write(
      path,
      to_binary(document)
    )
  end

  @doc """
  Writes the PDF to a file and raises if the operation fails.
  """
  @spec write!(Document.t(), Path.t()) :: :ok
  def write!(
        %Document{} = document,
        path
      ) do
    File.write!(
      path,
      to_binary(document)
    )
  end
end

defmodule PaperForge.Page do
  @moduledoc """
  Represents a PDF page and its drawing operations.

  Pages store high-level operations until they are added to a document.
  """

  alias PaperForge.Coordinates
  alias PaperForge.Document
  alias PaperForge.Margins
  alias PaperForge.PageCompiler
  alias PaperForge.PageResources
  alias PaperForge.PageSize
  alias PaperForge.Stream

  @default_size :a4
  @default_orientation :portrait
  @default_origin :bottom_left

  defstruct [
    :width,
    :height,
    :margins,
    :origin,
    operations: []
  ]

  @type operation ::
          {:text, binary(), keyword()}
          | {:text_box, binary(), keyword()}
          | {:line, keyword()}
          | {:rectangle, keyword()}
          | {:circle, keyword()}
          | {:image, binary(), keyword()}

  @type t :: %__MODULE__{
          width: number(),
          height: number(),
          margins: Margins.t(),
          origin: Coordinates.origin(),
          operations: [operation()]
        }

  @doc """
  Creates a new page.
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) when is_list(options) do
    size = Keyword.get(options, :size, @default_size)

    orientation =
      Keyword.get(
        options,
        :orientation,
        @default_orientation
      )

    origin =
      options
      |> Keyword.get(:origin, @default_origin)
      |> Coordinates.validate_origin!()

    margins =
      options
      |> Keyword.get(:margins, 0)
      |> Margins.new()

    {width, height} =
      size
      |> PageSize.resolve()
      |> apply_orientation(orientation)

    Margins.validate_page!(
      margins,
      width,
      height
    )

    %__MODULE__{
      width: width,
      height: height,
      margins: margins,
      origin: origin,
      operations: []
    }
  end

  @doc """
  Adds a line of text.
  """
  @spec text(t(), binary(), keyword()) :: t()
  def text(
        %__MODULE__{} = page,
        text,
        options \\ []
      )
      when is_binary(text) and is_list(options) do
    options =
      Keyword.put_new(
        options,
        :font,
        :helvetica
      )

    add_operation(
      page,
      {:text, text, options}
    )
  end

  @doc """
  Adds wrapped multiline text.
  """
  @spec text_box(t(), binary(), keyword()) :: t()
  def text_box(
        %__MODULE__{} = page,
        text,
        options
      )
      when is_binary(text) and is_list(options) do
    options =
      Keyword.put_new(
        options,
        :font,
        :helvetica
      )

    add_operation(
      page,
      {:text_box, text, options}
    )
  end

  @doc """
  Adds a line operation.
  """
  @spec line(t(), keyword()) :: t()
  def line(%__MODULE__{} = page, options)
      when is_list(options) do
    add_operation(page, {:line, options})
  end

  @doc """
  Adds a rectangle operation.
  """
  @spec rectangle(t(), keyword()) :: t()
  def rectangle(%__MODULE__{} = page, options)
      when is_list(options) do
    add_operation(page, {:rectangle, options})
  end

  @doc """
  Adds a circle operation.
  """
  @spec circle(t(), keyword()) :: t()
  def circle(%__MODULE__{} = page, options)
      when is_list(options) do
    add_operation(page, {:circle, options})
  end

  @doc """
  Adds a JPEG or PNG image from a path or binary.
  """
  @spec image(t(), binary(), keyword()) :: t()
  def image(
        %__MODULE__{} = page,
        source,
        options
      )
      when is_binary(source) and is_list(options) do
    add_operation(
      page,
      {:image, source, options}
    )
  end

  @doc """
  Returns the usable page width after margins.
  """
  @spec content_width(t()) :: number()
  def content_width(%__MODULE__{} = page) do
    Margins.content_width(
      page.margins,
      page.width
    )
  end

  @doc """
  Returns the usable page height after margins.
  """
  @spec content_height(t()) :: number()
  def content_height(%__MODULE__{} = page) do
    Margins.content_height(
      page.margins,
      page.height
    )
  end

  @doc """
  Returns the left content boundary.
  """
  @spec content_left(t()) :: number()
  def content_left(%__MODULE__{} = page) do
    page.margins.left
  end

  @doc """
  Returns the top content boundary.
  """
  @spec content_top(t()) :: number()
  def content_top(%__MODULE__{origin: :top_left} = page) do
    page.margins.top
  end

  def content_top(%__MODULE__{origin: :bottom_left} = page) do
    page.height - page.margins.top
  end

  @doc """
  Returns the bottom content boundary.
  """
  @spec content_bottom(t()) :: number()
  def content_bottom(%__MODULE__{origin: :bottom_left} = page) do
    page.margins.bottom
  end

  def content_bottom(%__MODULE__{origin: :top_left} = page) do
    page.height - page.margins.bottom
  end

  @doc """
  Compiles the page operations into an uncompressed content-stream
  binary.

  This function is retained for compatibility with PaperForge v0.1.0.
  Image operations require a document and therefore cannot be compiled
  through this function.
  """
  @spec content(t()) :: binary()
  def content(%__MODULE__{} = page) do
    PageCompiler.compile_content(page)
  end

  @doc """
  Compiles the page and adds it to a document.
  """
  @spec add_to_document(t(), Document.t()) :: Document.t()
  def add_to_document(
        %__MODULE__{} = page,
        %Document{} = document
      ) do
    {document, content, resources} =
      PageCompiler.compile(page, document)

    content_stream =
      Stream.new(
        content,
        filters: content_stream_filters(document)
      )

    {document, content_reference} =
      Document.add_object(
        document,
        content_stream
      )

    page_dictionary = %{
      "Type" => {:name, "Page"},
      "Parent" => document.pages_reference,
      "MediaBox" => [
        0,
        0,
        page.width,
        page.height
      ],
      "Resources" => PageResources.to_dictionary(resources),
      "Contents" => content_reference
    }

    {document, page_reference} =
      Document.add_object(
        document,
        page_dictionary
      )

    Document.append_page(
      document,
      page_reference
    )
  end

  defp content_stream_filters(%Document{compress: true}) do
    [:flate]
  end

  defp content_stream_filters(%Document{compress: false}) do
    []
  end

  defp add_operation(
         %__MODULE__{} = page,
         operation
       ) do
    %{
      page
      | operations: [
          operation
          | page.operations
        ]
    }
  end

  defp apply_orientation(
         {width, height},
         :portrait
       ) do
    {
      min(width, height),
      max(width, height)
    }
  end

  defp apply_orientation(
         {width, height},
         :landscape
       ) do
    {
      max(width, height),
      min(width, height)
    }
  end

  defp apply_orientation(
         _size,
         orientation
       ) do
    raise ArgumentError,
          "unsupported page orientation #{inspect(orientation)}. " <>
            "Expected :portrait or :landscape"
  end
end

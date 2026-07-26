defmodule PaperForge.Page do
  @moduledoc """
  High-level representation of a PDF page.

  Coordinates currently use the native PDF coordinate system:

  - origin at the bottom-left corner;
  - X grows toward the right;
  - Y grows toward the top.
  """

  alias PaperForge.Document
  alias PaperForge.Graphics.Circle
  alias PaperForge.Graphics.Line
  alias PaperForge.Graphics.Rectangle
  alias PaperForge.Graphics.Text
  alias PaperForge.PageSize
  alias PaperForge.Stream

  defstruct width: 595.28,
            height: 841.89,
            operations: []

  @type operation :: iodata()

  @type t :: %__MODULE__{
          width: number(),
          height: number(),
          operations: [operation()]
        }

  @spec new(keyword()) :: t()
  def new(options \\ []) when is_list(options) do
    size =
      Keyword.get(
        options,
        :size,
        :a4
      )

    orientation =
      Keyword.get(
        options,
        :orientation,
        :portrait
      )

    {width, height} =
      PageSize.resolve(size)

    {width, height} =
      orient(
        width,
        height,
        orientation
      )

    %__MODULE__{
      width: width,
      height: height,
      operations: []
    }
  end

  @doc """
  Adds a text drawing operation.
  """
  @spec text(t(), binary(), keyword()) :: t()
  def text(
        %__MODULE__{} = page,
        text,
        options \\ []
      )
      when is_binary(text) and is_list(options) do
    add_operation(
      page,
      Text.command(text, options)
    )
  end

  @doc """
  Adds a line drawing operation.
  """
  @spec line(t(), keyword()) :: t()
  def line(
        %__MODULE__{} = page,
        options
      )
      when is_list(options) do
    add_operation(
      page,
      Line.command(options)
    )
  end

  @doc """
  Adds a rectangle drawing operation.
  """
  @spec rectangle(t(), keyword()) :: t()
  def rectangle(
        %__MODULE__{} = page,
        options
      )
      when is_list(options) do
    add_operation(
      page,
      Rectangle.command(options)
    )
  end

  @doc """
  Adds a circle drawing operation.
  """
  @spec circle(t(), keyword()) :: t()
  def circle(
        %__MODULE__{} = page,
        options
      )
      when is_list(options) do
    add_operation(
      page,
      Circle.command(options)
    )
  end

  @doc """
  Converts all page operations into one PDF content stream.
  """
  @spec content(t()) :: iodata()
  def content(%__MODULE__{} = page) do
    page.operations
    |> Enum.reverse()
    |> Enum.intersperse("\n")
  end

  @doc """
  Converts the high-level page into PDF indirect objects and
  adds them to the document.
  """
  @spec add_to_document(t(), Document.t()) :: Document.t()
  def add_to_document(
        %__MODULE__{} = page,
        %Document{} = document
      ) do
    content_stream =
      Stream.new(content(page))

    {document, content_reference} =
      Document.add_object(
        document,
        content_stream
      )

    page_dictionary = %{
      "Type" => {:name, "Page"},
      "Parent" => document.pages,
      "MediaBox" => [
        0,
        0,
        page.width,
        page.height
      ],
      "Resources" => %{
        "Font" => %{
          "F1" => document.default_font
        }
      },
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

  defp orient(width, height, :portrait) do
    {width, height}
  end

  defp orient(width, height, :landscape) do
    {height, width}
  end

  defp orient(_width, _height, orientation) do
    raise ArgumentError,
          "unsupported page orientation: #{inspect(orientation)}"
  end
end

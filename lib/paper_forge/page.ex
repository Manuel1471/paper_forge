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
          | {:link, binary(), keyword()}
          | {:link_to, binary() | atom(), keyword()}
          | {:destination, binary() | atom(), keyword()}
          | {:bookmark, binary(), keyword()}

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
    add_operation(
      page,
      {:text_box, text, options}
    )
  end

  @doc """
  Adds a paragraph using the multiline text-box layout engine.
  """
  @spec paragraph(t(), binary(), keyword()) :: t()
  def paragraph(
        %__MODULE__{} = page,
        text,
        options
      )
      when is_binary(text) and is_list(options) do
    text_box(
      page,
      text,
      options
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
  Adds a URI link annotation over a rectangular area.
  """
  @spec link(t(), binary(), keyword()) :: t()
  def link(
        %__MODULE__{} = page,
        uri,
        options
      )
      when is_binary(uri) and is_list(options) do
    add_operation(
      page,
      {:link, uri, options}
    )
  end

  @doc """
  Adds an internal link annotation to a named destination.
  """
  @spec link_to(t(), binary() | atom(), keyword()) :: t()
  def link_to(
        %__MODULE__{} = page,
        destination_name,
        options
      )
      when (is_binary(destination_name) or is_atom(destination_name)) and is_list(options) do
    add_operation(
      page,
      {:link_to, destination_name, options}
    )
  end

  @doc """
  Adds a named destination on this page.
  """
  @spec destination(t(), binary() | atom(), keyword()) :: t()
  def destination(
        %__MODULE__{} = page,
        name,
        options \\ []
      )
      when (is_binary(name) or is_atom(name)) and is_list(options) do
    add_operation(
      page,
      {:destination, name, options}
    )
  end

  @doc """
  Adds a PDF outline/bookmark pointing to this page.
  """
  @spec bookmark(t(), binary(), keyword()) :: t()
  def bookmark(
        %__MODULE__{} = page,
        title,
        options \\ []
      )
      when is_binary(title) and is_list(options) do
    add_operation(
      page,
      {:bookmark, title, options}
    )
  end

  @doc """
  Adds a basic table.

  Rows are lists of cell values. Table cells are drawn with rectangles
  and text operations so they work with the normal font pipeline.
  """
  @spec table(t(), [[term()]], keyword()) :: t()
  def table(
        %__MODULE__{} = page,
        rows,
        options
      )
      when is_list(rows) and is_list(options) do
    x = Keyword.get(options, :x, content_left(page))
    y = Keyword.fetch!(options, :y)
    width = Keyword.get(options, :width, content_width(page))
    row_height = Keyword.get(options, :row_height, 24)
    padding = Keyword.get(options, :padding, 6)
    font = Keyword.get(options, :font)
    size = Keyword.get(options, :size, 10)
    header? = Keyword.get(options, :header, false)

    column_count =
      rows
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 1 end)

    column_widths =
      Keyword.get(
        options,
        :column_widths,
        List.duplicate(width / column_count, column_count)
      )

    rows
    |> Enum.with_index()
    |> Enum.reduce(page, fn {row, row_index}, current_page ->
      row_y = y + row_index * row_height
      fill? = header? and row_index == 0

      row
      |> Enum.zip(column_widths)
      |> Enum.reduce({current_page, x}, fn {cell, cell_width}, {row_page, cell_x} ->
        cell_options =
          [
            x: cell_x,
            y: row_y,
            width: cell_width,
            height: row_height,
            stroke: true,
            fill: fill?,
            fill_color: Keyword.get(options, :header_fill_color, PaperForge.Color.gray(0.92)),
            stroke_color: Keyword.get(options, :stroke_color, PaperForge.Color.gray(0.65)),
            line_width: Keyword.get(options, :line_width, 0.5)
          ]

        text_options =
          [
            x: cell_x + padding,
            y: row_y + padding + size,
            width: max(cell_width - padding * 2, 1),
            font: font,
            size: size,
            color: Keyword.get(options, :color, PaperForge.Color.black())
          ]
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)

        row_page =
          row_page
          |> rectangle(cell_options)
          |> text(to_string(cell), text_options)

        {row_page, cell_x + cell_width}
      end)
      |> elem(0)
    end)
  end

  @doc """
  Adds an ordered or unordered list.
  """
  @spec list(t(), [term()], keyword()) :: t()
  def list(
        %__MODULE__{} = page,
        items,
        options
      )
      when is_list(items) and is_list(options) do
    x = Keyword.get(options, :x, content_left(page))
    y = Keyword.fetch!(options, :y)
    width = Keyword.get(options, :width, content_width(page))
    size = Keyword.get(options, :size, 10)
    line_height = Keyword.get(options, :line_height, size * 1.4)
    marker_width = Keyword.get(options, :marker_width, 24)
    type = Keyword.get(options, :type, :unordered)
    font = Keyword.get(options, :font)

    items
    |> Enum.with_index(1)
    |> Enum.reduce(page, fn {item, index}, current_page ->
      row_y = y + (index - 1) * line_height
      marker = list_marker(type, index)

      text_options =
        [
          y: row_y,
          font: font,
          size: size,
          color: Keyword.get(options, :color, PaperForge.Color.black())
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      current_page
      |> text(marker, Keyword.merge(text_options, x: x, width: marker_width))
      |> text(
        to_string(item),
        Keyword.merge(text_options,
          x: x + marker_width,
          width: max(width - marker_width, 1)
        )
      )
    end)
  end

  defp list_marker(:ordered, index), do: "#{index}."
  defp list_marker(:unordered, _index), do: "•"

  defp list_marker(type, _index) do
    raise ArgumentError,
          "unsupported list type #{inspect(type)}. Expected :ordered or :unordered"
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

    {document, annotations} =
      add_annotations(
        page,
        document
      )

    page_dictionary =
      %{
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
      |> maybe_put_annotations(annotations)

    {document, page_reference} =
      Document.add_object(
        document,
        page_dictionary
      )

    document =
      add_navigation(
        page,
        document,
        page_reference
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

  defp add_annotations(%__MODULE__{} = page, %Document{} = document) do
    page.operations
    |> Enum.reverse()
    |> Enum.reduce({document, []}, fn
      {:link, uri, options}, {current_document, annotations} ->
        {current_document, reference} =
          Document.add_object(
            current_document,
            link_annotation(page, uri, options)
          )

        {current_document, annotations ++ [reference]}

      {:link_to, destination_name, options}, {current_document, annotations} ->
        {current_document, reference} =
          Document.add_object(
            current_document,
            internal_link_annotation(page, destination_name, options)
          )

        {current_document, annotations ++ [reference]}

      _operation, state ->
        state
    end)
  end

  defp add_navigation(%__MODULE__{} = page, %Document{} = document, page_reference) do
    page.operations
    |> Enum.reverse()
    |> Enum.reduce(document, fn
      {:destination, name, options}, current_document ->
        Document.add_named_destination(
          current_document,
          name,
          page_reference,
          destination_options(page, options)
        )

      {:bookmark, title, options}, current_document ->
        Document.add_outline(
          current_document,
          title,
          page_reference,
          destination_options(page, options)
        )

      _operation, current_document ->
        current_document
    end)
  end

  defp link_annotation(page, uri, options) do
    x = Keyword.fetch!(options, :x)
    y = Keyword.fetch!(options, :y)
    width = Keyword.fetch!(options, :width)
    height = Keyword.fetch!(options, :height)
    origin = Keyword.get(options, :origin, page.origin)

    bottom_y =
      Coordinates.box_y(
        page.height,
        y,
        height,
        origin
      )

    %{
      "Type" => {:name, "Annot"},
      "Subtype" => {:name, "Link"},
      "Rect" => [x, bottom_y, x + width, bottom_y + height],
      "Border" => [0, 0, 0],
      "A" => %{
        "S" => {:name, "URI"},
        "URI" => uri
      }
    }
  end

  defp internal_link_annotation(page, destination_name, options) do
    x = Keyword.fetch!(options, :x)
    y = Keyword.fetch!(options, :y)
    width = Keyword.fetch!(options, :width)
    height = Keyword.fetch!(options, :height)
    origin = Keyword.get(options, :origin, page.origin)

    bottom_y =
      Coordinates.box_y(
        page.height,
        y,
        height,
        origin
      )

    %{
      "Type" => {:name, "Annot"},
      "Subtype" => {:name, "Link"},
      "Rect" => [x, bottom_y, x + width, bottom_y + height],
      "Border" => [0, 0, 0],
      "Dest" => normalize_destination_name(destination_name)
    }
  end

  defp destination_options(page, options) do
    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    y =
      options
      |> Keyword.get(:y, content_top(page))
      |> then(&Coordinates.point_y(page.height, &1, origin))

    [
      x: Keyword.get(options, :x),
      y: y,
      zoom: Keyword.get(options, :zoom)
    ]
  end

  defp normalize_destination_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_destination_name(name), do: name

  defp maybe_put_annotations(dictionary, []) do
    dictionary
  end

  defp maybe_put_annotations(dictionary, annotations) do
    Map.put(dictionary, "Annots", annotations)
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

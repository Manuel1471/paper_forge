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
          | {:note, binary(), keyword()}
          | {:highlight, binary(), keyword()}
          | {:annotation, atom(), keyword()}

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

  @doc "Adds a vector path made of move, line, cubic curve, and close segments."
  @spec path(t(), [PaperForge.Graphics.Path.segment()], keyword()) :: t()
  def path(%__MODULE__{} = page, segments, options \\ [])
      when is_list(segments) and is_list(options) do
    add_operation(page, {:path, segments, options})
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

  @doc "Adds a PDF text-note annotation."
  @spec note(t(), binary(), keyword()) :: t()
  def note(%__MODULE__{} = page, contents, options)
      when is_binary(contents) and is_list(options) do
    add_operation(page, {:note, contents, options})
  end

  @doc "Adds a highlight annotation over a rectangular text region."
  @spec highlight(t(), binary(), keyword()) :: t()
  def highlight(%__MODULE__{} = page, contents, options)
      when is_binary(contents) and is_list(options) do
    add_operation(page, {:highlight, contents, options})
  end

  @doc """
  Adds a standard PDF annotation.

  Supported types are `:underline`, `:strikeout`, `:stamp`, `:free_text`,
  `:square`, `:circle`, `:ink`, and `:file_attachment`. Common options include
  `:x`, `:y`, `:width`, `:height`, `:contents`, `:color`, `:author`,
  `:subject`, and `:reply_to`.
  """
  @spec annotation(t(), atom(), keyword()) :: t()
  def annotation(%__MODULE__{} = page, type, options)
      when type in [
             :underline,
             :strikeout,
             :stamp,
             :free_text,
             :square,
             :circle,
             :ink,
             :file_attachment
           ] and
             is_list(options) do
    add_operation(page, {:annotation, type, options})
  end

  @doc "Adds an underline annotation."
  @spec underline(t(), binary(), keyword()) :: t()
  def underline(%__MODULE__{} = page, contents, options),
    do: annotation(page, :underline, Keyword.put(options, :contents, contents))

  @doc "Adds a strikeout annotation."
  @spec strikeout(t(), binary(), keyword()) :: t()
  def strikeout(%__MODULE__{} = page, contents, options),
    do: annotation(page, :strikeout, Keyword.put(options, :contents, contents))

  @doc "Adds a named stamp annotation."
  @spec stamp(t(), binary(), keyword()) :: t()
  def stamp(%__MODULE__{} = page, contents, options),
    do: annotation(page, :stamp, Keyword.put(options, :contents, contents))

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
    row_heights = Keyword.get(options, :row_heights, List.duplicate(row_height, length(rows)))
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
      row_y = y + Enum.sum(Enum.take(row_heights, row_index))
      fill? = header? and row_index == 0

      stripe? =
        not fill? and rem(row_index, 2) == 1 and Keyword.has_key?(options, :stripe_fill_color)

      row
      |> Enum.reduce({current_page, 0}, fn raw_cell, {row_page, next_column} ->
        cell = normalize_page_table_cell(raw_cell)
        column = cell.column || next_column
        colspan = min(cell.colspan, max(length(column_widths) - column, 1))
        cell_x = x + Enum.sum(Enum.take(column_widths, column))
        cell_width = column_widths |> Enum.slice(column, colspan) |> Enum.sum()
        cell_height = row_heights |> Enum.slice(row_index, cell.rowspan) |> Enum.sum()
        fill_color = cell.fill_color || table_cell_fill(fill?, stripe?, options)

        cell_options =
          [
            x: cell_x,
            y: row_y,
            width: cell_width,
            height: cell_height,
            stroke: false,
            fill: fill? or stripe? or not is_nil(cell.fill_color),
            fill_color: fill_color,
            stroke_color: Keyword.get(options, :stroke_color, PaperForge.Color.gray(0.65)),
            line_width: Keyword.get(options, :line_width, 0.5)
          ]

        line_height = Keyword.get(options, :line_height, size * 1.3)
        cell_text = to_string(cell.content)
        line_count = max(length(String.split(cell_text, "\n")), 1)
        text_height = line_count * line_height

        text_y =
          case cell.valign || Keyword.get(options, :cell_valign, :top) do
            :middle -> row_y + max((cell_height - text_height) / 2, padding)
            :bottom -> row_y + max(cell_height - text_height - padding, padding)
            _top -> row_y + padding
          end

        text_options =
          [
            x: cell_x + padding,
            y: text_y,
            width: max(cell_width - padding * 2, 1),
            height: max(cell_height - (text_y - row_y) - padding, line_height),
            font: font,
            size: size,
            line_height: line_height,
            color:
              if(cell.color,
                do: cell.color,
                else:
                  if(fill?,
                    do:
                      Keyword.get(
                        options,
                        :header_color,
                        Keyword.get(options, :color, PaperForge.Color.black())
                      ),
                    else: Keyword.get(options, :color, PaperForge.Color.black())
                  )
              ),
            align: cell.align || Keyword.get(options, :cell_align, :left)
          ]
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)

        row_page =
          row_page
          |> rectangle(cell_options)
          |> draw_table_cell_borders(
            cell_x,
            row_y,
            cell_width,
            cell_height,
            cell.borders,
            options
          )
          |> text_box(cell_text, text_options)

        {row_page, column + colspan}
      end)
      |> elem(0)
    end)
  end

  defp table_cell_fill(true, _stripe?, options),
    do: Keyword.get(options, :header_fill_color, PaperForge.Color.gray(0.92))

  defp table_cell_fill(false, true, options),
    do: Keyword.get(options, :stripe_fill_color, PaperForge.Color.white())

  defp table_cell_fill(false, false, options),
    do: Keyword.get(options, :body_fill_color, PaperForge.Color.white())

  defp normalize_page_table_cell(%{content: _content} = cell) do
    %{
      content: cell.content,
      colspan: Map.get(cell, :colspan, 1),
      rowspan: Map.get(cell, :rowspan, 1),
      column: Map.get(cell, :column),
      align: Map.get(cell, :align),
      valign: Map.get(cell, :valign, :top),
      borders: Map.get(cell, :borders, :all),
      fill_color: Map.get(cell, :fill_color),
      color: Map.get(cell, :color)
    }
  end

  defp normalize_page_table_cell(content) do
    %{
      content: content,
      colspan: 1,
      rowspan: 1,
      column: nil,
      align: nil,
      valign: nil,
      borders: :all,
      fill_color: nil,
      color: nil
    }
  end

  defp draw_table_cell_borders(page, _x, _y, _width, _height, :none, _options), do: page

  defp draw_table_cell_borders(page, x, y, width, height, borders, options) do
    selected = if borders == :all, do: [:top, :right, :bottom, :left], else: List.wrap(borders)
    color = Keyword.get(options, :stroke_color, PaperForge.Color.gray(0.65))
    line_width = Keyword.get(options, :line_width, 0.5)

    Enum.reduce(selected, page, fn
      :top, current ->
        line(current, x1: x, y1: y, x2: x + width, y2: y, color: color, width: line_width)

      :right, current ->
        line(current,
          x1: x + width,
          y1: y,
          x2: x + width,
          y2: y + height,
          color: color,
          width: line_width
        )

      :bottom, current ->
        line(current,
          x1: x,
          y1: y + height,
          x2: x + width,
          y2: y + height,
          color: color,
          width: line_width
        )

      :left, current ->
        line(current, x1: x, y1: y, x2: x, y2: y + height, color: color, width: line_width)

      _unknown, current ->
        current
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

      {:note, contents, options}, {current_document, annotations} ->
        {current_document, reference} =
          Document.add_object(current_document, note_annotation(page, contents, options))

        {current_document, annotations ++ [reference]}

      {:highlight, contents, options}, {current_document, annotations} ->
        {current_document, reference} =
          Document.add_object(current_document, highlight_annotation(page, contents, options))

        {current_document, annotations ++ [reference]}

      {:annotation, type, options}, {current_document, annotations} ->
        {current_document, reference} =
          add_standard_annotation(page, current_document, type, options)

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

  defp note_annotation(page, contents, options) do
    {x, y, width, height} = annotation_box(page, options)

    %{
      "Type" => {:name, "Annot"},
      "Subtype" => {:name, "Text"},
      "Rect" => [x, y, x + width, y + height],
      "Contents" => contents,
      "Name" => {:name, Atom.to_string(Keyword.get(options, :icon, :Comment))},
      "Open" => Keyword.get(options, :open, false)
    }
  end

  defp highlight_annotation(page, contents, options) do
    {x, y, width, height} = annotation_box(page, options)

    %{
      "Type" => {:name, "Annot"},
      "Subtype" => {:name, "Highlight"},
      "Rect" => [x, y, x + width, y + height],
      "QuadPoints" => [x, y + height, x + width, y + height, x, y, x + width, y],
      "Contents" => contents,
      "C" => Keyword.get(options, :color, [1, 0.92, 0.23])
    }
  end

  defp add_standard_annotation(page, document, :file_attachment, options) do
    filename = Keyword.fetch!(options, :filename)
    data = Keyword.fetch!(options, :data)

    stream =
      Stream.new(data,
        dictionary: %{
          "Type" => {:name, "EmbeddedFile"},
          "Subtype" => Keyword.get(options, :mime, "application/octet-stream")
        },
        filters: [:flate]
      )

    {document, stream_reference} = Document.add_object(document, stream)

    file_spec = %{
      "Type" => {:name, "Filespec"},
      "F" => filename,
      "UF" => filename,
      "Desc" => Keyword.get(options, :description, filename),
      "EF" => %{"F" => stream_reference}
    }

    {document, file_reference} = Document.add_object(document, file_spec)

    dictionary =
      page
      |> standard_annotation(:file_attachment, options)
      |> Map.put("FS", file_reference)
      |> Map.put("Name", {:name, Atom.to_string(Keyword.get(options, :icon, :PushPin))})

    Document.add_object(document, dictionary)
  end

  defp add_standard_annotation(page, document, type, options),
    do: Document.add_object(document, standard_annotation(page, type, options))

  defp standard_annotation(page, type, options) do
    {x, y, width, height} = annotation_box(page, options)

    %{
      "Type" => {:name, "Annot"},
      "Subtype" => {:name, annotation_subtype(type)},
      "Rect" => [x, y, x + width, y + height],
      "Contents" => Keyword.get(options, :contents, ""),
      "C" => Keyword.get(options, :color, [0.95, 0.45, 0.2]),
      "F" => Keyword.get(options, :flags, 4)
    }
    |> maybe_annotation_value("T", Keyword.get(options, :author))
    |> maybe_annotation_value("Subj", Keyword.get(options, :subject))
    |> maybe_annotation_value("IRT", Keyword.get(options, :reply_to))
    |> maybe_annotation_value("RT", reply_type(options))
    |> add_annotation_geometry(type, x, y, width, height, options)
  end

  defp add_annotation_geometry(dictionary, type, x, y, width, height, _options)
       when type in [:underline, :strikeout] do
    Map.put(dictionary, "QuadPoints", [x, y + height, x + width, y + height, x, y, x + width, y])
  end

  defp add_annotation_geometry(dictionary, :stamp, _x, _y, _width, _height, options),
    do:
      Map.put(
        dictionary,
        "Name",
        {:name, annotation_name(Keyword.get(options, :name, :Approved))}
      )

  defp add_annotation_geometry(dictionary, :free_text, _x, _y, _width, _height, options),
    do: Map.put(dictionary, "DA", Keyword.get(options, :default_appearance, "/Helv 10 Tf 0 g"))

  defp add_annotation_geometry(dictionary, type, _x, _y, _width, _height, options)
       when type in [:square, :circle] do
    dictionary
    |> Map.put("BS", %{"W" => Keyword.get(options, :line_width, 1), "S" => {:name, "S"}})
    |> maybe_annotation_value("IC", Keyword.get(options, :fill_color))
  end

  defp add_annotation_geometry(dictionary, :ink, x, y, _width, _height, options) do
    strokes = Keyword.get(options, :points, [[{x, y}]])

    ink_list =
      Enum.map(strokes, fn
        stroke when is_list(stroke) and stroke != [] and is_number(hd(stroke)) -> stroke
        stroke -> Enum.flat_map(stroke, fn {px, py} -> [px, py] end)
      end)

    Map.put(dictionary, "InkList", ink_list)
  end

  defp add_annotation_geometry(dictionary, _type, _x, _y, _width, _height, _options),
    do: dictionary

  defp annotation_subtype(:underline), do: "Underline"
  defp annotation_subtype(:strikeout), do: "StrikeOut"
  defp annotation_subtype(:stamp), do: "Stamp"
  defp annotation_subtype(:free_text), do: "FreeText"
  defp annotation_subtype(:square), do: "Square"
  defp annotation_subtype(:circle), do: "Circle"
  defp annotation_subtype(:ink), do: "Ink"
  defp annotation_subtype(:file_attachment), do: "FileAttachment"

  defp annotation_name(value) when is_atom(value), do: Atom.to_string(value)
  defp annotation_name(value) when is_binary(value), do: value

  defp reply_type(options) do
    if Keyword.has_key?(options, :reply_to),
      do: {:name, Atom.to_string(Keyword.get(options, :reply_type, :R))},
      else: nil
  end

  defp maybe_annotation_value(dictionary, _key, nil), do: dictionary
  defp maybe_annotation_value(dictionary, key, value), do: Map.put(dictionary, key, value)

  defp annotation_box(page, options) do
    x = Keyword.fetch!(options, :x)
    top = Keyword.fetch!(options, :y)
    width = Keyword.get(options, :width, 18)
    height = Keyword.get(options, :height, 18)
    y = Coordinates.box_y(page.height, top, height, Keyword.get(options, :origin, page.origin))
    {x, y, width, height}
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

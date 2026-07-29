defmodule PaperForge.PageCompiler do
  @moduledoc """
  Compiles `PaperForge.Page` drawing operations into PDF page content.

  The compiler owns the transition from high-level page operations to
  low-level PDF commands, including coordinate transforms, font/image
  registration, and page resource collection.
  """

  alias PaperForge.Coordinates
  alias PaperForge.Document
  alias PaperForge.Fonts.Builtin
  alias PaperForge.Graphics.Circle
  alias PaperForge.Graphics.Image, as: ImageGraphics
  alias PaperForge.Graphics.Line
  alias PaperForge.Graphics.Path
  alias PaperForge.Graphics.Rectangle
  alias PaperForge.Graphics.Text
  alias PaperForge.Graphics.TextBox
  alias PaperForge.Image
  alias PaperForge.Page
  alias PaperForge.PageResources

  @doc """
  Compiles a page into `{document, content, resources}`.

  Fonts and images used by the page are registered in the returned
  document. Content is returned as an uncompressed binary so the caller
  can decide which stream filters to apply.
  """
  @spec compile(Page.t(), Document.t()) ::
          {Document.t(), binary(), PageResources.t()}
  def compile(%Page{} = page, %Document{} = document) do
    {document, commands, resources} =
      compile_operations(page, document)

    {
      document,
      IO.iodata_to_binary(commands),
      resources
    }
  end

  @doc """
  Compiles page content without document-backed resources.

  This is retained for compatibility with `PaperForge.Page.content/1`.
  Image operations are intentionally rejected because image XObjects
  must be registered in a document.
  """
  @spec compile_content(Page.t()) :: binary()
  def compile_content(%Page{} = page) do
    font_resources =
      page.operations
      |> Enum.reverse()
      |> Enum.reduce(
        %{},
        fn
          {:text, _text, options}, resources ->
            put_local_font_resource(
              resources,
              Keyword.get(options, :font, :helvetica)
            )

          {:text_box, _text, options}, resources ->
            put_local_font_resource(
              resources,
              Keyword.get(options, :font, :helvetica)
            )

          _operation, resources ->
            resources
        end
      )

    page.operations
    |> Enum.reverse()
    |> Enum.map(
      &compile_local_operation(
        page,
        &1,
        font_resources
      )
    )
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end

  defp compile_operations(%Page{} = page, %Document{} = document) do
    page.operations
    |> Enum.reverse()
    |> Enum.reduce(
      {
        document,
        [],
        PageResources.new()
      },
      fn operation, {current_document, commands, resources} ->
        {updated_document, command, updated_resources} =
          compile_operation(
            page,
            current_document,
            resources,
            operation
          )

        {
          updated_document,
          [commands, command, "\n"],
          updated_resources
        }
      end
    )
  end

  defp compile_operation(page, document, resources, {:text, text, options}) do
    font_key = Document.resolve_text_font_key(document, options, text)

    {document, _font} =
      Document.register_font(
        document,
        font_key
      )

    {document, font} =
      Document.use_font_text(
        document,
        font_key,
        text
      )

    command_options =
      options
      |> put_default_position(page)
      |> transform_text_coordinates(page)
      |> Keyword.put(:font, font_key)
      |> Keyword.put(:font_instance, font)
      |> Keyword.put(
        :resource_name,
        font.resource_name
      )

    command =
      Text.command(text, command_options)

    resources =
      PageResources.put_font(
        resources,
        font
      )

    {document, command, resources}
  end

  defp compile_operation(page, document, resources, {:text_box, text, options}) do
    font_key = Document.resolve_text_font_key(document, options, text)

    {document, _font} =
      Document.register_font(
        document,
        font_key
      )

    {document, font} =
      Document.use_font_text(
        document,
        font_key,
        text
      )

    command_options =
      options
      |> put_default_position(page)
      |> transform_text_box_coordinates(page)
      |> Keyword.put(:font, font_key)
      |> Keyword.put(:font_instance, font)
      |> Keyword.put(
        :resource_name,
        font.resource_name
      )

    result =
      TextBox.commands(
        text,
        command_options
      )

    resources =
      PageResources.put_font(
        resources,
        font
      )

    {document, result.commands, resources}
  end

  defp compile_operation(page, document, resources, {:line, options}) do
    command =
      compile_line_operation(
        page,
        options
      )

    {document, command, resources}
  end

  defp compile_operation(page, document, resources, {:rectangle, options}) do
    command =
      compile_rectangle_operation(
        page,
        options
      )

    {document, command, resources}
  end

  defp compile_operation(page, document, resources, {:circle, options}) do
    command =
      compile_circle_operation(page, options)

    {document, command, resources}
  end

  defp compile_operation(page, document, resources, {:path, segments, options}) do
    command = compile_path_operation(page, segments, options)
    {document, command, resources}
  end

  defp compile_operation(page, document, resources, {:image, source, options}) do
    image_data = read_image_source!(source)

    {document, image} =
      Document.register_image(
        document,
        image_data
      )

    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    geometry = image_geometry(image, options)
    x = geometry.x
    y = Coordinates.box_y(page.height, geometry.y, geometry.height, origin)

    clip =
      if geometry.clip do
        {clip_x, clip_y, clip_width, clip_height} = geometry.clip

        {
          clip_x,
          Coordinates.box_y(page.height, clip_y, clip_height, origin),
          clip_width,
          clip_height
        }
      end

    command =
      ImageGraphics.command(
        image.resource_name,
        x: x,
        y: y,
        width: geometry.width,
        height: geometry.height,
        clip: clip,
        matrix: image_matrix(image.orientation, x, y, geometry.width, geometry.height)
      )

    resources =
      PageResources.put_image(
        resources,
        image
      )

    {document, command, resources}
  end

  defp compile_operation(_page, document, resources, {:link, _uri, _options}) do
    {document, [], resources}
  end

  defp compile_operation(_page, document, resources, {:link_to, _destination, _options}) do
    {document, [], resources}
  end

  defp compile_operation(_page, document, resources, {:destination, _name, _options}) do
    {document, [], resources}
  end

  defp compile_operation(_page, document, resources, {:bookmark, _title, _options}) do
    {document, [], resources}
  end

  defp compile_operation(_page, document, resources, {type, _contents, _options})
       when type in [:note, :highlight] do
    {document, [], resources}
  end

  defp compile_local_operation(page, {:text, text, options}, font_resources) do
    font_key =
      Keyword.get(options, :font, :helvetica)

    command_options =
      options
      |> put_default_position(page)
      |> transform_text_coordinates(page)
      |> Keyword.put(:font, font_key)
      |> Keyword.put(
        :resource_name,
        Map.fetch!(font_resources, font_key)
      )

    Text.command(text, command_options)
  end

  defp compile_local_operation(page, {:text_box, text, options}, font_resources) do
    font_key =
      Keyword.get(options, :font, :helvetica)

    command_options =
      options
      |> put_default_position(page)
      |> transform_text_box_coordinates(page)
      |> Keyword.put(:font, font_key)
      |> Keyword.put(
        :resource_name,
        Map.fetch!(font_resources, font_key)
      )

    result =
      TextBox.commands(
        text,
        command_options
      )

    result.commands
  end

  defp compile_local_operation(page, {:line, options}, _font_resources) do
    compile_line_operation(page, options)
  end

  defp compile_local_operation(page, {:rectangle, options}, _font_resources) do
    compile_rectangle_operation(
      page,
      options
    )
  end

  defp compile_local_operation(page, {:circle, options}, _font_resources) do
    compile_circle_operation(page, options)
  end

  defp compile_local_operation(page, {:path, segments, options}, _font_resources) do
    compile_path_operation(page, segments, options)
  end

  defp compile_local_operation(_page, {:image, _source, _options}, _font_resources) do
    raise ArgumentError,
          "Page.content/1 cannot compile images because image XObjects " <>
            "must be registered in a document"
  end

  defp compile_local_operation(_page, {:link, _uri, _options}, _font_resources) do
    []
  end

  defp compile_local_operation(_page, {:link_to, _destination, _options}, _font_resources) do
    []
  end

  defp compile_local_operation(_page, {:destination, _name, _options}, _font_resources) do
    []
  end

  defp compile_local_operation(_page, {:bookmark, _title, _options}, _font_resources) do
    []
  end

  defp compile_line_operation(page, options) do
    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    {y1, y2} =
      Coordinates.line_y(
        page.height,
        Keyword.fetch!(options, :y1),
        Keyword.fetch!(options, :y2),
        origin
      )

    options
    |> Keyword.put(:y1, y1)
    |> Keyword.put(:y2, y2)
    |> Keyword.delete(:origin)
    |> Line.command()
  end

  defp compile_rectangle_operation(page, options) do
    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    height = Keyword.fetch!(options, :height)

    y =
      Coordinates.box_y(
        page.height,
        Keyword.fetch!(options, :y),
        height,
        origin
      )

    options
    |> Keyword.put(:y, y)
    |> Keyword.delete(:origin)
    |> Rectangle.command()
  end

  defp compile_circle_operation(page, options) do
    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    y =
      Coordinates.point_y(
        page.height,
        Keyword.fetch!(options, :y),
        origin
      )

    options
    |> Keyword.put(:y, y)
    |> Keyword.delete(:origin)
    |> Circle.command()
  end

  defp compile_path_operation(page, segments, options) do
    origin = Keyword.get(options, :origin, page.origin)

    transform = fn
      {:move_to, x, y} ->
        {:move_to, x, Coordinates.point_y(page.height, y, origin)}

      {:line_to, x, y} ->
        {:line_to, x, Coordinates.point_y(page.height, y, origin)}

      {:curve_to, x1, y1, x2, y2, x3, y3} ->
        {:curve_to, x1, Coordinates.point_y(page.height, y1, origin), x2,
         Coordinates.point_y(page.height, y2, origin), x3,
         Coordinates.point_y(page.height, y3, origin)}

      :close ->
        :close
    end

    clip_path =
      case Keyword.get(options, :clip_path) do
        nil -> nil
        path -> Enum.map(path, transform)
      end

    options
    |> Keyword.put(:clip_path, clip_path)
    |> Keyword.delete(:origin)
    |> then(&Path.command(Enum.map(segments, transform), &1))
  end

  defp image_geometry(image, options) do
    box_x = Keyword.fetch!(options, :x)
    box_y = Keyword.fetch!(options, :y)
    {box_width, box_height} = Image.display_size(image, options)

    case Keyword.get(options, :fit, :fill) do
      :fill ->
        %{x: box_x, y: box_y, width: box_width, height: box_height, clip: nil}

      fit when fit in [:contain, :cover] ->
        {natural_width, natural_height} = Image.oriented_dimensions(image)
        scale_fun = if fit == :contain, do: &min/2, else: &max/2
        scale = scale_fun.(box_width / natural_width, box_height / natural_height)
        width = natural_width * scale
        height = natural_height * scale
        {focus_x, focus_y} = image_focus(options)
        x = box_x + (box_width - width) * focus_x
        y = box_y + (box_height - height) * focus_y
        clip = if fit == :cover, do: {box_x, box_y, box_width, box_height}, else: nil
        %{x: x, y: y, width: width, height: height, clip: clip}

      fit ->
        raise ArgumentError,
              "image fit must be :fill, :contain, or :cover, received: #{inspect(fit)}"
    end
  end

  defp image_focus(options) do
    case Keyword.get(options, :focal_point) do
      {x, y} when is_number(x) and x >= 0 and x <= 1 and is_number(y) and y >= 0 and y <= 1 ->
        {x, y}

      nil ->
        {horizontal_focus(Keyword.get(options, :align, :center)),
         vertical_focus(Keyword.get(options, :valign, :middle))}

      focal_point ->
        raise ArgumentError,
              "image focal_point must be a {horizontal, vertical} tuple between 0 and 1, " <>
                "received: #{inspect(focal_point)}"
    end
  end

  defp horizontal_focus(:left), do: 0.0
  defp horizontal_focus(:center), do: 0.5
  defp horizontal_focus(:right), do: 1.0
  defp horizontal_focus(value) when is_number(value) and value >= 0 and value <= 1, do: value
  defp horizontal_focus(_value), do: 0.5

  defp vertical_focus(:top), do: 0.0
  defp vertical_focus(:middle), do: 0.5
  defp vertical_focus(:bottom), do: 1.0
  defp vertical_focus(value) when is_number(value) and value >= 0 and value <= 1, do: value
  defp vertical_focus(_value), do: 0.5

  defp image_matrix(2, x, y, width, height), do: {-width, 0, 0, height, x + width, y}

  defp image_matrix(3, x, y, width, height),
    do: {-width, 0, 0, -height, x + width, y + height}

  defp image_matrix(4, x, y, width, height), do: {width, 0, 0, -height, x, y + height}
  defp image_matrix(5, x, y, width, height), do: {0, height, width, 0, x, y}
  defp image_matrix(6, x, y, width, height), do: {0, height, -width, 0, x + width, y}

  defp image_matrix(7, x, y, width, height),
    do: {0, -height, -width, 0, x + width, y + height}

  defp image_matrix(8, x, y, width, height), do: {0, -height, width, 0, x, y + height}
  defp image_matrix(_orientation, x, y, width, height), do: {width, 0, 0, height, x, y}

  defp put_local_font_resource(resources, font_key) do
    Builtin.fetch!(font_key)

    if Map.has_key?(resources, font_key) do
      resources
    else
      Map.put(
        resources,
        font_key,
        "F#{map_size(resources) + 1}"
      )
    end
  end

  defp transform_text_coordinates(options, page) do
    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    y =
      Coordinates.point_y(
        page.height,
        Keyword.fetch!(options, :y),
        origin
      )

    options
    |> Keyword.put(:y, y)
    |> Keyword.delete(:origin)
  end

  defp transform_text_box_coordinates(options, page) do
    transform_text_coordinates(
      options,
      page
    )
  end

  defp put_default_position(options, page) do
    options
    |> Keyword.put_new(:x, Page.content_left(page))
    |> Keyword.put_new(:y, default_y(page))
  end

  defp default_y(%Page{origin: :top_left} = page) do
    page.margins.top
  end

  defp default_y(%Page{origin: :bottom_left} = page) do
    page.margins.bottom
  end

  defp read_image_source!(source) when is_binary(source) do
    cond do
      PaperForge.Images.JPEG.jpeg?(source) ->
        source

      PaperForge.Images.PNG.png?(source) ->
        source

      File.regular?(source) ->
        File.read!(source)

      true ->
        raise ArgumentError,
              "image source must be a valid JPEG or PNG binary, or an " <>
                "existing image file path"
    end
  end
end

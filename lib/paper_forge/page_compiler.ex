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
    font_key =
      Keyword.get(options, :font, :helvetica)

    {document, font} =
      Document.register_font(
        document,
        font_key
      )

    command_options =
      options
      |> put_default_position(page)
      |> transform_text_coordinates(page)
      |> Keyword.put(:font, font_key)
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
    font_key =
      Keyword.get(options, :font, :helvetica)

    {document, font} =
      Document.register_font(
        document,
        font_key
      )

    command_options =
      options
      |> put_default_position(page)
      |> transform_text_box_coordinates(page)
      |> Keyword.put(:font, font_key)
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

  defp compile_operation(page, document, resources, {:image, source, options}) do
    image_data = read_image_source!(source)

    {document, image} =
      Document.register_image(
        document,
        image_data
      )

    {width, height} =
      Image.display_size(image, options)

    origin =
      Keyword.get(
        options,
        :origin,
        page.origin
      )

    x = Keyword.fetch!(options, :x)

    y =
      Coordinates.box_y(
        page.height,
        Keyword.fetch!(options, :y),
        height,
        origin
      )

    command =
      ImageGraphics.command(
        image.resource_name,
        x: x,
        y: y,
        width: width,
        height: height
      )

    resources =
      PageResources.put_image(
        resources,
        image
      )

    {document, command, resources}
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

  defp compile_local_operation(_page, {:image, _source, _options}, _font_resources) do
    raise ArgumentError,
          "Page.content/1 cannot compile images because image XObjects " <>
            "must be registered in a document"
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

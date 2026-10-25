defmodule PaperForge.AcroForm do
  @moduledoc """
  Creates and edits standard PDF AcroForms.

  Supported fields are text, checkbox, push button, radio group, list,
  combobox, and signature widgets. The module also supports default values,
  generated appearances, restricted calculation actions, data import/export,
  and flattening. XFA is intentionally unsupported.

  Field appearances can be adapted to the surrounding design with
  `:background_color`, `:border_color`, `:border_width`, and `:border_radius`.
  Text fields also accept `:font`, `:font_size`, `:text_color`, `:text_align`,
  and `:padding`. Generated single-line appearances shrink text to fit the
  available width; the canonical field value is never truncated.
  Checkboxes additionally accept `:check_color` and `:check_width`.
  Radio groups use circular controls with a centered selection mark.
  """

  alias PaperForge.{
    Document,
    FontRegistry,
    Page,
    PageCompiler,
    PageResources,
    Reference,
    Stream,
    StringEncoding,
    TextMetrics
  }

  alias PaperForge.PDF.{Graph, Inspection}

  @field_types [:text, :checkbox, :button, :list, :combo, :signature]

  @doc "Adds one AcroForm field to a one-based page index."
  @spec add_field(Document.t(), pos_integer(), atom(), binary(), keyword()) :: Document.t()
  def add_field(%Document{} = document, page, type, name, options \\ [])
      when is_integer(page) and page > 0 and type in @field_types and is_binary(name) do
    ensure_unique_name!(document, name)
    {document, font_reference} = ensure_form(document)
    page_reference = page_reference!(document, page)
    rect = normalize_rect(document, page_reference, Keyword.fetch!(options, :rect), options)
    value = Keyword.get(options, :value, Keyword.get(options, :default))
    {document, appearance} = appearance(document, type, rect, value, options, font_reference)

    field =
      %{
        "Type" => {:name, "Annot"},
        "Subtype" => {:name, "Widget"},
        "FT" => {:name, field_type(type)},
        "T" => StringEncoding.auto(name),
        "Rect" => rect,
        "P" => page_reference,
        "F" => Keyword.get(options, :annotation_flags, 4),
        "Ff" => field_flags(type, options),
        "Q" => text_quadding(type, options),
        "DA" => Keyword.get(options, :default_appearance, "/Helv 10 Tf 0 g")
      }
      |> put_value(type, value)
      |> put_default(type, Keyword.get(options, :default))
      |> maybe_put("TU", Keyword.get(options, :tooltip))
      |> maybe_put("Opt", choice_options(type, options))
      |> maybe_put("AP", appearance)
      |> maybe_put("AA", calculation_action(Keyword.get(options, :calculation)))

    {document, field_reference} = Document.add_object(document, field)

    document = %{
      document
      | form_appearance_options:
          Map.put(document.form_appearance_options, field_reference.object_id, options)
    }

    document
    |> configure_field_font(field_reference, appearance, options)
    |> append_page_annotation(page_reference, field_reference)
    |> append_form_field(field_reference)
  end

  @doc "Adds a radio-button group and its widget children."
  @spec add_radio_group(Document.t(), binary(), [keyword()], keyword()) :: Document.t()
  def add_radio_group(%Document{} = document, name, choices, options \\ [])
      when is_binary(name) and is_list(choices) and choices != [] do
    ensure_unique_name!(document, name)
    {document, _font_reference} = ensure_form(document)

    selected =
      case Keyword.get(options, :value) do
        nil -> nil
        value -> to_string(value)
      end

    {document, widget_references} =
      Enum.reduce(choices, {document, []}, fn choice, {current, references} ->
        page_reference = page_reference!(current, Keyword.fetch!(choice, :page))
        appearance_options = Keyword.merge(options, Keyword.get(choice, :options, []))

        rect =
          normalize_rect(
            current,
            page_reference,
            Keyword.fetch!(choice, :rect),
            appearance_options
          )

        export = choice |> Keyword.fetch!(:value) |> to_string()

        {current, appearance} =
          checkbox_appearance(
            current,
            rect,
            export,
            Keyword.put(appearance_options, :radio, true)
          )

        widget = %{
          "Type" => {:name, "Annot"},
          "Subtype" => {:name, "Widget"},
          "Rect" => rect,
          "P" => page_reference,
          "F" => Keyword.get(appearance_options, :annotation_flags, 4),
          "AP" => appearance,
          "AS" => {:name, if(selected == export, do: export, else: "Off")}
        }

        {current, reference} = Document.add_object(current, widget)
        {append_page_annotation(current, page_reference, reference), references ++ [reference]}
      end)

    parent =
      %{
        "FT" => {:name, "Btn"},
        "T" => StringEncoding.auto(name),
        "Ff" => 32_768,
        "Kids" => widget_references,
        "V" => {:name, selected || "Off"}
      }
      |> maybe_put("TU", Keyword.get(options, :tooltip))

    {document, parent_reference} = Document.add_object(document, parent)

    document =
      Enum.reduce(widget_references, document, fn reference, current ->
        Document.update_object(current, reference, &Map.put(&1, "Parent", parent_reference))
      end)

    append_form_field(document, parent_reference)
  end

  @doc "Exports current form values as a map keyed by fully qualified field name."
  @spec export_data(Document.t()) :: map()
  def export_data(%Document{} = document) do
    document
    |> fields()
    |> Enum.reduce(%{}, fn {_reference, field}, data ->
      case field["T"] do
        nil -> data
        name -> Map.put(data, StringEncoding.decode(name), export_value(field["V"]))
      end
    end)
  end

  @doc "Imports values into existing fields and refreshes their basic appearance state."
  @spec import_data(Document.t(), map() | keyword()) :: Document.t()
  def import_data(%Document{} = document, values) when is_map(values) or is_list(values) do
    ensure_supported!(document)
    values = values |> Map.new() |> Map.new(fn {key, value} -> {to_string(key), value} end)

    Enum.reduce(fields(document), document, fn {reference, field}, current ->
      case Map.fetch(values, if(field["T"], do: StringEncoding.decode(field["T"]))) do
        {:ok, value} ->
          current
          |> Document.update_object(reference, fn existing ->
            existing
            |> put_value(field_kind(existing), value)
            |> maybe_update_state(value)
          end)
          |> update_radio_widgets(field, value)
          |> refresh_appearance(reference, field, value)

        :error ->
          current
      end
    end)
  end

  @doc "Flattens field values into page content and removes the interactive form."
  @spec flatten(Document.t(), keyword()) :: Document.t()
  def flatten(%Document{} = document, options \\ []) do
    ensure_supported!(document)

    if is_nil(acro_form(document)) do
      document
    else
      flattened = flatten_pages(document, Map.new(fields(document)), options)
      Document.update_object(flattened, flattened.root_reference, &Map.delete(&1, "AcroForm"))
    end
  end

  defp flatten_pages(document, fields, _options) do
    Enum.reduce(Graph.pages!(document), document, fn page, current ->
      annotations = Graph.resolve!(current, page.dictionary["Annots"]) || []
      {widgets, other} = Enum.split_with(annotations, &Map.has_key?(fields, &1))
      flatten_page(current, page, widgets, other, fields)
    end)
  end

  defp flatten_page(document, _page, [], _other, _fields), do: document

  defp flatten_page(document, page, widgets, other, fields) do
    resources = Graph.resolve!(document, page.dictionary["Resources"]) || %{}
    xobjects = Graph.resolve!(document, resources["XObject"]) || %{}

    {xobjects, commands} =
      Enum.reduce(widgets, {xobjects, []}, fn ref, {objects, commands} ->
        field = Map.fetch!(fields, ref)

        case normal_appearance(document, field) do
          nil ->
            ensure_empty_field!(field)

            {objects, commands}

          appearance ->
            name = unused_name(objects, "PFForm#{ref.object_id}")
            command = appearance_placement(document, appearance, field["Rect"], name)
            {Map.put(objects, name, appearance), [command | commands]}
        end
      end)

    {document, before_ref} = Document.add_object(document, Stream.new("q\n"))

    {document, after_ref} =
      Document.add_object(document, Stream.new(["Q\n", Enum.reverse(commands)]))

    contents = Graph.resolve!(document, page.dictionary["Contents"])
    # Keep references to streams; only resolve an indirect array of streams.
    original = if is_list(contents), do: contents, else: List.wrap(page.dictionary["Contents"])

    Document.update_object(document, page.reference, fn dictionary ->
      dictionary
      |> Map.put("Contents", [before_ref | original] ++ [after_ref])
      |> Map.put("Resources", Map.put(resources, "XObject", xobjects))
      |> Map.put("Annots", other)
    end)
  end

  defp ensure_empty_field!(field) do
    if field["V"] not in [nil, "", {:name, "Off"}],
      do: raise(ArgumentError, "cannot flatten a field without its appearance")
  end

  defp normal_appearance(document, field) do
    appearance = Graph.resolve!(document, field["AP"]) || %{}

    case appearance["N"] do
      %Reference{} = ref ->
        ref

      states when is_map(states) ->
        state = field["AS"] || field["V"] || {:name, "Off"}

        case state do
          {:name, name} -> states[name]
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp unused_name(objects, name) do
    if Map.has_key?(objects, name), do: unused_name(objects, name <> "_"), else: name
  end

  defp appearance_placement(document, reference, [x1, y1, x2, y2], name) do
    %Stream{dictionary: dictionary} = Graph.resolve!(document, reference)
    [bx1, by1, bx2, by2] = dictionary["BBox"]
    [a, b, c, d, e, f] = Map.get(dictionary, "Matrix", [1, 0, 0, 1, 0, 0])
    corners = for x <- [bx1, bx2], y <- [by1, by2], do: {a * x + c * y + e, b * x + d * y + f}
    {xs, ys} = Enum.unzip(corners)
    width = Enum.max(xs) - Enum.min(xs)
    height = Enum.max(ys) - Enum.min(ys)
    if width <= 0 or height <= 0, do: raise(ArgumentError, "invalid form appearance bounds")
    sx = (x2 - x1) / width
    sy = (y2 - y1) / height
    matrix = [sx, 0, 0, sy, x1 - sx * Enum.min(xs), y1 - sy * Enum.min(ys)]

    [
      "q ",
      Enum.map_intersperse(matrix, " ", &PaperForge.Serializer.encode/1),
      " cm /",
      name,
      " Do Q\n"
    ]
  end

  @doc "Returns true when the document catalog contains an XFA entry."
  @spec xfa?(Document.t()) :: boolean()
  def xfa?(%Document{} = document) do
    case acro_form(document) do
      {_reference, form} -> Map.has_key?(form, "XFA")
      nil -> false
    end
  end

  @doc "Rejects XFA forms with a stable error instead of partially editing them."
  @spec validate(Document.t()) :: :ok | {:error, :xfa_not_supported}
  def validate(%Document{} = document),
    do: if(xfa?(document), do: {:error, :xfa_not_supported}, else: :ok)

  defp ensure_form(document) do
    ensure_supported!(document)

    case acro_form(document) do
      {nil, form} ->
        {document, reference} = Document.add_object(document, form)

        document =
          Document.update_object(
            document,
            document.root_reference,
            &Map.put(&1, "AcroForm", reference)
          )

        ensure_form(document)

      {%Reference{} = form_reference, form} ->
        case get_in(form, ["DR", "Font", "Helv"]) do
          %Reference{} = font_reference -> {document, font_reference}
          nil -> add_form_font(document, form_reference)
        end

      nil ->
        font = %{
          "Type" => {:name, "Font"},
          "Subtype" => {:name, "Type1"},
          "BaseFont" => {:name, "Helvetica"},
          "Encoding" => {:name, "WinAnsiEncoding"}
        }

        {document, font_reference} = Document.add_object(document, font)

        form = %{
          "Fields" => [],
          "NeedAppearances" => false,
          "DA" => "/Helv 10 Tf 0 g",
          "DR" => %{"Font" => %{"Helv" => font_reference}},
          "SigFlags" => 3
        }

        {document, form_reference} = Document.add_object(document, form)

        document =
          Document.update_object(
            document,
            document.root_reference,
            &Map.put(&1, "AcroForm", form_reference)
          )

        {document, font_reference}
    end
  end

  defp add_form_font(document, form_reference) do
    font = %{
      "Type" => {:name, "Font"},
      "Subtype" => {:name, "Type1"},
      "BaseFont" => {:name, "Helvetica"},
      "Encoding" => {:name, "WinAnsiEncoding"}
    }

    {document, font_reference} = Document.add_object(document, font)

    document =
      Document.update_object(document, form_reference, fn form ->
        put_in(form, ["DR", "Font", "Helv"], font_reference)
      end)

    {document, font_reference}
  end

  defp acro_form(document) do
    catalog = document.objects[document.root_reference.object_id].value

    case catalog["AcroForm"] do
      %Reference{} = reference -> {reference, Graph.resolve!(document, reference)}
      form when is_map(form) -> {nil, form}
      _ -> nil
    end
  end

  defp fields(document) do
    for field <- Inspection.forms(document) do
      dictionary =
        if field.dictionary["T"],
          do: Map.put(field.dictionary, "T", StringEncoding.auto(field.name)),
          else: field.dictionary

      {field.reference, dictionary}
    end
  end

  defp ensure_supported!(document) do
    if xfa?(document), do: raise(ArgumentError, "XFA forms are not supported")
  end

  defp ensure_unique_name!(document, name) do
    if Enum.any?(fields(document), fn {_reference, field} ->
         field["T"] && StringEncoding.decode(field["T"]) == name
       end),
       do: raise(ArgumentError, "AcroForm field already exists: #{name}")
  end

  defp page_reference!(document, index) do
    case Enum.at(Graph.pages!(document), index - 1) do
      nil -> raise ArgumentError, "page index #{index} does not exist"
      page -> page.reference
    end
  end

  defp append_form_field(document, field_reference) do
    {form_reference, _form} = acro_form(document)

    Document.update_object(
      document,
      form_reference,
      &Map.update!(&1, "Fields", fn fields -> fields ++ [field_reference] end)
    )
  end

  defp append_page_annotation(document, page_reference, annotation_reference) do
    Document.update_object(document, page_reference, fn page ->
      Map.update(page, "Annots", [annotation_reference], &(&1 ++ [annotation_reference]))
    end)
  end

  defp appearance(document, :checkbox, rect, value, options, _font),
    do: checkbox_appearance(document, rect, value in [true, "Yes", :Yes], options)

  defp appearance(document, type, [x1, y1, x2, y2], value, options, _font_reference) do
    width = x2 - x1
    height = y2 - y1
    text = appearance_text(type, value, options)
    background = color_components(Keyword.get(options, :background_color, "1 1 1"))
    border = color_components(Keyword.get(options, :border_color, "0.25 0.3 0.4"))
    border_width = non_negative_option!(options, :border_width, 1)
    radius = radius_option!(options, width, height)
    shape = inset_shape(width, height, radius, border_width)

    font = Keyword.get(options, :font, :helvetica)

    metrics_font =
      case FontRegistry.fetch(document.font_registry, font) do
        {:ok, instance} -> instance
        :error -> font
      end

    padding = non_negative_option!(options, :padding, 6)
    requested_size = positive_option!(options, :font_size, 10)
    available = max(width - 2 * padding, 0.1)
    measured = TextMetrics.width(text, font: metrics_font, size: requested_size)

    size =
      min(
        requested_size,
        min(max(height - 4, 0.1), requested_size * available / max(measured, 0.1))
      )

    alignment = Keyword.get(options, :text_align, if(type == :button, do: :center, else: :left))

    unless alignment in [:left, :center, :right],
      do: raise(ArgumentError, "invalid form text_align")

    text_color = color_components(Keyword.get(options, :text_color, "0 0 0"))

    [red, green, blue] =
      text_color
      |> String.split()
      |> Enum.map(&String.to_float(if String.contains?(&1, "."), do: &1, else: &1 <> ".0"))

    page =
      Page.new(size: {width, height})
      |> Page.text(text,
        x: padding,
        y: (height - size) / 2 + size * 0.2,
        width: available,
        align: alignment,
        size: size,
        font: font,
        color: PaperForge.Color.rgb(red, green, blue)
      )

    {document, text_content, resources} = PageCompiler.compile(page, document)

    content =
      "q 0 0 #{width} #{height} re W n #{background} rg #{border} RG #{border_width} w #{shape} B #{text_color} rg " <>
        text_content <> " Q"

    stream =
      Stream.new(content,
        dictionary: %{
          "Type" => {:name, "XObject"},
          "Subtype" => {:name, "Form"},
          "BBox" => [0, 0, width, height],
          "Resources" => PageResources.to_dictionary(resources)
        },
        filters: [:flate]
      )

    {document, reference} = Document.add_object(document, stream)
    {document, %{"N" => reference}}
  end

  defp configure_field_font(document, reference, %{"N" => %Reference{} = appearance}, options) do
    if Keyword.has_key?(options, :default_appearance) do
      document
    else
      %Stream{dictionary: dictionary} = Graph.resolve!(document, appearance)

      case (dictionary["Resources"]["Font"] || %{}) |> Map.values() do
        [font | _] ->
          name = "PFField#{reference.object_id}"
          {form_ref, _} = acro_form(document)

          document
          |> put_form_font(form_ref, name, font)
          |> Document.update_object(
            reference,
            &Map.put(
              &1,
              "DA",
              "/#{name} #{Keyword.get(options, :font_size, 10)} Tf #{color_components(Keyword.get(options, :text_color, "0 0 0"))} rg"
            )
          )

        [] ->
          document
      end
    end
  end

  defp configure_field_font(document, _reference, _appearance, _options), do: document

  defp put_form_font(document, form_ref, name, font) do
    Document.update_object(document, form_ref, fn form ->
      update_in(form, ["DR", "Font"], &Map.put(&1 || %{}, name, font))
    end)
  end

  defp text_quadding(type, options) do
    case Keyword.get(options, :text_align, if(type == :button, do: :center, else: :left)) do
      :left -> 0
      :center -> 1
      :right -> 2
      _ -> raise ArgumentError, "invalid form text_align"
    end
  end

  defp appearance_text(_type, nil, _options), do: ""

  defp appearance_text(type, values, options) when is_list(values),
    do: Enum.map_join(values, ", ", &appearance_text(type, &1, options))

  defp appearance_text(type, value, options) when type in [:list, :combo] do
    Enum.find_value(Keyword.get(options, :options, []), to_string(value), fn
      [export, label] when export == value -> to_string(label)
      _ -> nil
    end)
  end

  defp appearance_text(_type, value, _options), do: to_string(value)

  defp checkbox_appearance(document, rect, checked?, options)
       when is_boolean(checked?),
       do: checkbox_appearance(document, rect, "Yes", options)

  defp checkbox_appearance(document, [x1, y1, x2, y2], export_value, options) do
    width = x2 - x1
    height = y2 - y1
    background = color_components(Keyword.get(options, :background_color, "1 1 1"))
    border = color_components(Keyword.get(options, :border_color, "0.25 0.3 0.4"))
    check = color_components(Keyword.get(options, :check_color, "0.04 0.56 0.48"))
    border_width = non_negative_option!(options, :border_width, 1)
    check_width = non_negative_option!(options, :check_width, 1.4)
    radius = radius_option!(options, width, height)
    radio? = Keyword.get(options, :radio, false)
    side = min(width, height)

    shape =
      if radio?,
        do: circle_shape(width / 2, height / 2, max((side - border_width) / 2, 0)),
        else: inset_shape(width, height, radius, border_width)

    mark =
      if radio? do
        "#{check} rg #{circle_shape(width / 2, height / 2, side * 0.23)} f"
      else
        left = (width - side) / 2
        bottom = (height - side) / 2

        "#{check} RG #{check_width} w 1 J 1 j #{left + side * 0.23} #{bottom + side * 0.51} m #{left + side * 0.43} #{bottom + side * 0.31} l #{left + side * 0.77} #{bottom + side * 0.71} l S"
      end

    off =
      Stream.new("q #{background} rg #{border} RG #{border_width} w #{shape} B Q",
        dictionary: %{
          "Type" => {:name, "XObject"},
          "Subtype" => {:name, "Form"},
          "BBox" => [0, 0, width, height]
        }
      )

    yes =
      Stream.new(
        "q #{background} rg #{border} RG #{border_width} w #{shape} B #{mark} Q",
        dictionary: %{
          "Type" => {:name, "XObject"},
          "Subtype" => {:name, "Form"},
          "BBox" => [0, 0, width, height]
        }
      )

    {document, off_reference} = Document.add_object(document, off)
    {document, yes_reference} = Document.add_object(document, yes)
    {document, %{"N" => %{"Off" => off_reference, export_value => yes_reference}}}
  end

  defp put_value(field, _type, nil), do: Map.delete(field, "V")

  defp put_value(field, :checkbox, value),
    do:
      field
      |> Map.put("V", {:name, if(value in [true, "Yes", :Yes], do: "Yes", else: "Off")})
      |> Map.put("AS", {:name, if(value in [true, "Yes", :Yes], do: "Yes", else: "Off")})

  defp put_value(field, :radio, value), do: Map.put(field, "V", {:name, to_string(value)})

  defp put_value(field, type, value) when type in [:text, :list, :combo, :button],
    do: Map.put(field, "V", encode_value(value))

  defp put_value(field, _type, value), do: Map.put(field, "V", value)

  defp put_default(field, _type, nil), do: field
  defp put_default(field, type, value), do: Map.put(field, "DV", put_value(%{}, type, value)["V"])
  defp encode_value(values) when is_list(values), do: Enum.map(values, &encode_value/1)
  defp encode_value(value), do: StringEncoding.auto(to_string(value))

  defp refresh_appearance(document, reference, field, value) do
    type = field_kind(field)

    if type in [:text, :list, :button] and is_list(field["Rect"]) do
      {_ref, form} = acro_form(document)
      options = Map.get(document.form_appearance_options, reference.object_id, [])

      {document, appearance} =
        appearance(
          document,
          type,
          field["Rect"],
          value,
          options,
          get_in(form, ["DR", "Font", "Helv"])
        )

      document
      |> Document.update_object(reference, &Map.put(&1, "AP", appearance))
      |> configure_field_font(reference, appearance, options)
    else
      document
    end
  end

  defp maybe_update_state(field, value) do
    if field_kind(field) == :checkbox,
      do: Map.put(field, "AS", {:name, if(value in [true, "Yes", :Yes], do: "Yes", else: "Off")}),
      else: field
  end

  defp radius_option!(options, width, height) do
    radius = non_negative_option!(options, :border_radius, 0)
    min(radius, min(width, height) / 2)
  end

  defp non_negative_option!(options, key, default) do
    value = Keyword.get(options, key, default)

    if is_number(value) and value >= 0,
      do: value,
      else: raise(ArgumentError, "#{key} must be a non-negative number")
  end

  defp color_components(%PaperForge.Color{components: components}),
    do: Enum.map_join(components, " ", &PaperForge.Serializer.encode/1)

  defp color_components("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    [r, g, b]
    |> Enum.map(&(String.to_integer(&1, 16) / 255))
    |> Enum.map_join(" ", &PaperForge.Serializer.encode/1)
  end

  defp color_components(value) when is_binary(value), do: value

  defp color_components(value),
    do:
      raise(
        ArgumentError,
        "form appearance color must be a PDF RGB string, hex color, or Color, got: #{inspect(value)}"
      )

  defp positive_option!(options, key, default) do
    value = non_negative_option!(options, key, default)
    if value > 0, do: value, else: raise(ArgumentError, "#{key} must be positive")
  end

  defp inset_shape(width, height, radius, stroke) do
    inset = min(stroke / 2, min(width, height) / 2)
    inner_width = max(width - 2 * inset, 0)
    inner_height = max(height - 2 * inset, 0)
    radius = min(radius, min(inner_width, inner_height) / 2)

    "1 0 0 1 #{inset} #{inset} cm " <>
      appearance_shape(inner_width, inner_height, radius) <>
      " 1 0 0 1 #{-inset} #{-inset} cm"
  end

  defp circle_shape(x, y, radius) do
    control = radius * 0.552_284_75

    "#{x + radius} #{y} m #{x + radius} #{y + control} #{x + control} #{y + radius} #{x} #{y + radius} c " <>
      "#{x - control} #{y + radius} #{x - radius} #{y + control} #{x - radius} #{y} c " <>
      "#{x - radius} #{y - control} #{x - control} #{y - radius} #{x} #{y - radius} c " <>
      "#{x + control} #{y - radius} #{x + radius} #{y - control} #{x + radius} #{y} c h"
  end

  defp appearance_shape(width, height, radius) when radius <= 0,
    do: "0 0 #{width} #{height} re"

  defp appearance_shape(width, height, radius) do
    control = radius * 0.552_284_75

    "#{radius} 0 m #{width - radius} 0 l #{width - radius + control} 0 #{width} #{radius - control} #{width} #{radius} c " <>
      "#{width} #{height - radius} l #{width} #{height - radius + control} #{width - radius + control} #{height} #{width - radius} #{height} c " <>
      "#{radius} #{height} l #{radius - control} #{height} 0 #{height - radius + control} 0 #{height - radius} c " <>
      "0 #{radius} l 0 #{radius - control} #{radius - control} 0 #{radius} 0 c h"
  end

  defp field_kind(%{"FT" => {:name, "Btn"}, "Ff" => flags})
       when is_integer(flags) and Bitwise.band(flags, 65_536) != 0, do: :button

  defp field_kind(%{"FT" => {:name, "Btn"}, "Ff" => flags})
       when is_integer(flags) and Bitwise.band(flags, 32_768) == 0, do: :checkbox

  defp field_kind(%{"FT" => {:name, "Btn"}, "Ff" => flags})
       when is_integer(flags) and Bitwise.band(flags, 32_768) != 0,
       do: :radio

  defp field_kind(%{"FT" => {:name, "Sig"}}), do: :signature
  defp field_kind(%{"FT" => {:name, "Tx"}}), do: :text
  defp field_kind(%{"FT" => {:name, "Ch"}}), do: :list
  defp field_kind(_), do: :text

  defp field_type(:text), do: "Tx"
  defp field_type(type) when type in [:checkbox, :button], do: "Btn"
  defp field_type(type) when type in [:list, :combo], do: "Ch"
  defp field_type(:signature), do: "Sig"

  defp field_flags(:button, _options), do: 65_536
  defp field_flags(:combo, _options), do: 131_072
  defp field_flags(_type, options), do: Keyword.get(options, :flags, 0)

  defp choice_options(type, options) when type in [:list, :combo],
    do: Enum.map(Keyword.get(options, :options, []), &encode_value/1)

  defp choice_options(_type, _options), do: nil

  defp calculation_action(nil), do: nil

  defp calculation_action({:sum, fields}),
    do: javascript_action("AFSimple_Calculate(\"SUM\", #{Jason.encode!(fields)});")

  defp calculation_action({:product, fields}),
    do: javascript_action("AFSimple_Calculate(\"PRD\", #{Jason.encode!(fields)});")

  defp calculation_action({:average, fields}),
    do: javascript_action("AFSimple_Calculate(\"AVG\", #{Jason.encode!(fields)});")

  defp calculation_action(other),
    do: raise(ArgumentError, "unsupported AcroForm calculation: #{inspect(other)}")

  defp javascript_action(script), do: %{"C" => %{"S" => {:name, "JavaScript"}, "JS" => script}}

  defp normalize_rect(document, page_reference, rect, options) do
    case {normalize_rect(rect), Keyword.get(options, :origin, :bottom_left)} do
      {[x1, y1, x2, y2], :bottom_left} ->
        [x1, y1, x2, y2]

      {[x1, y1, x2, y2], :top_left} ->
        [media_x, _media_y, _media_x2, media_y2] = page_media_box(document, page_reference)
        [media_x + x1, media_y2 - y2, media_x + x2, media_y2 - y1]

      {_rect, origin} ->
        raise ArgumentError,
              "field origin must be :bottom_left or :top_left, got: #{inspect(origin)}"
    end
  end

  defp normalize_rect([x1, y1, x2, y2]) when x2 > x1 and y2 > y1, do: [x1, y1, x2, y2]

  defp normalize_rect(other),
    do: raise(ArgumentError, "field rect must be [x1, y1, x2, y2], got: #{inspect(other)}")

  defp page_media_box(document, %Reference{object_id: object_id}) do
    resolve_media_box(document, document.objects[object_id].value)
  end

  defp resolve_media_box(_document, %{"MediaBox" => [x1, y1, x2, y2]} = _object)
       when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2),
       do: [x1, y1, x2, y2]

  defp resolve_media_box(document, %{"Parent" => %Reference{object_id: object_id}}) do
    resolve_media_box(document, document.objects[object_id].value)
  end

  defp resolve_media_box(_document, object),
    do: raise(ArgumentError, "page MediaBox is invalid or missing: #{inspect(object)}")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, "TU", value), do: Map.put(map, "TU", StringEncoding.auto(value))
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp export_value({:name, value}), do: value
  defp export_value(value) when is_binary(value), do: StringEncoding.decode(value)
  defp export_value({:hex_string, _} = value), do: StringEncoding.decode(value)
  defp export_value(value) when is_list(value), do: Enum.map(value, &export_value/1)
  defp export_value(value), do: value

  defp update_radio_widgets(document, %{"Kids" => kids}, value) when is_list(kids) do
    selected = to_string(value)

    Enum.reduce(kids, document, fn reference, current ->
      Document.update_object(current, reference, fn widget ->
        states = get_in(widget, ["AP", "N"]) || %{}
        state = if Map.has_key?(states, selected), do: selected, else: "Off"
        Map.put(widget, "AS", {:name, state})
      end)
    end)
  end

  defp update_radio_widgets(document, _field, _value), do: document
end

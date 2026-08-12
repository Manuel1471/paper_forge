defmodule PaperForge.AcroForm do
  @moduledoc """
  Creates and edits standard PDF AcroForms.

  Supported fields are text, checkbox, push button, radio group, list,
  combobox, and signature widgets. The module also supports default values,
  generated appearances, restricted calculation actions, data import/export,
  and flattening. XFA is intentionally unsupported.

  Field appearances can be adapted to the surrounding design with
  `:background_color`, `:border_color`, `:border_width`, and `:border_radius`.
  Checkboxes additionally accept `:check_color` and `:check_width`.
  """

  alias PaperForge.{Document, Reference, Stream}

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
        "T" => name,
        "Rect" => rect,
        "P" => page_reference,
        "F" => Keyword.get(options, :annotation_flags, 4),
        "Ff" => field_flags(type, options),
        "DA" => Keyword.get(options, :default_appearance, "/Helv 10 Tf 0 g")
      }
      |> put_value(type, value)
      |> maybe_put("DV", Keyword.get(options, :default))
      |> maybe_put("TU", Keyword.get(options, :tooltip))
      |> maybe_put("Opt", choice_options(type, options))
      |> maybe_put("AP", appearance)
      |> maybe_put("AA", calculation_action(Keyword.get(options, :calculation)))

    {document, field_reference} = Document.add_object(document, field)

    document
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
        {current, appearance} = checkbox_appearance(current, rect, export, appearance_options)

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
        "T" => name,
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
        name -> Map.put(data, name, export_value(field["V"]))
      end
    end)
  end

  @doc "Imports values into existing fields and refreshes their basic appearance state."
  @spec import_data(Document.t(), map() | keyword()) :: Document.t()
  def import_data(%Document{} = document, values) when is_map(values) or is_list(values) do
    values = values |> Map.new() |> Map.new(fn {key, value} -> {to_string(key), value} end)

    Enum.reduce(fields(document), document, fn {reference, field}, current ->
      case Map.fetch(values, field["T"]) do
        {:ok, value} ->
          current
          |> Document.update_object(reference, fn existing ->
            existing
            |> put_value(field_kind(existing), value)
            |> maybe_update_state(value)
          end)
          |> update_radio_widgets(field, value)

        :error ->
          current
      end
    end)
  end

  @doc "Flattens field values into page content and removes the interactive form."
  @spec flatten(Document.t(), keyword()) :: Document.t()
  def flatten(%Document{} = document, options \\ []) do
    field_refs =
      MapSet.new(Enum.map(fields(document), fn {reference, _} -> reference.object_id end))

    {_form_reference, form} = acro_form(document)
    font_reference = get_in(form, ["DR", "Font", "Helv"])

    document =
      Enum.reduce(flattenable_fields(document), document, fn {_reference, field}, current ->
        case {field["P"], field["Rect"], export_value(field["V"])} do
          {%Reference{} = page_reference, [x1, y1, x2, y2], value} when not is_nil(value) ->
            content = flattened_content(field, value, x1, y1, x2 - x1, y2 - y1, options)

            {current, stream_reference} =
              Document.add_object(current, Stream.new(content, filters: [:flate]))

            Document.update_object(current, page_reference, fn page ->
              page
              |> Map.update("Contents", stream_reference, &append_content(&1, stream_reference))
              |> Map.update("Resources", %{"Font" => %{"Helv" => font_reference}}, fn resources ->
                Map.update(
                  resources,
                  "Font",
                  %{"Helv" => font_reference},
                  &Map.put(&1, "Helv", font_reference)
                )
              end)
              |> Map.update("Annots", [], fn annotations ->
                Enum.reject(annotations, &MapSet.member?(field_refs, &1.object_id))
              end)
            end)

          _ ->
            current
        end
      end)

    Document.update_object(document, document.root_reference, &Map.delete(&1, "AcroForm"))
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
    case acro_form(document) do
      {%Reference{} = form_reference, form} ->
        case get_in(form, ["DR", "Font", "Helv"]) do
          %Reference{} = font_reference -> {document, font_reference}
          nil -> add_form_font(document, form_reference)
        end

      nil ->
        font = %{
          "Type" => {:name, "Font"},
          "Subtype" => {:name, "Type1"},
          "BaseFont" => {:name, "Helvetica"}
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
      "BaseFont" => {:name, "Helvetica"}
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
      %Reference{} = reference -> {reference, document.objects[reference.object_id].value}
      _ -> nil
    end
  end

  defp fields(document) do
    case acro_form(document) do
      {_reference, %{"Fields" => references}} ->
        Enum.flat_map(references, fn reference -> collect_field(document, reference) end)

      _ ->
        []
    end
  end

  defp collect_field(document, %Reference{} = reference) do
    field = document.objects[reference.object_id].value
    [{reference, field} | Enum.flat_map(Map.get(field, "Kids", []), &collect_field(document, &1))]
  end

  defp ensure_unique_name!(document, name) do
    if Enum.any?(fields(document), fn {_reference, field} -> field["T"] == name end),
      do: raise(ArgumentError, "AcroForm field already exists: #{name}")
  end

  defp page_reference!(document, index) do
    pages = document.objects[document.pages_reference.object_id].value["Kids"]
    Enum.at(pages, index - 1) || raise ArgumentError, "page index #{index} does not exist"
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

  defp appearance(document, _type, [x1, y1, x2, y2], value, options, font_reference) do
    width = x2 - x1
    height = y2 - y1
    text = if(is_nil(value), do: "", else: to_string(value))
    background = color_components(Keyword.get(options, :background_color, "1 1 1"))
    border = color_components(Keyword.get(options, :border_color, "0.25 0.3 0.4"))
    border_width = non_negative_option!(options, :border_width, 1)
    radius = radius_option!(options, width, height)
    shape = appearance_shape(width, height, radius)

    content =
      "q #{background} rg #{border} RG #{border_width} w #{shape} B BT /Helv 10 Tf 6 #{max(height / 2 - 4, 2)} Td (#{escape(text)}) Tj ET Q"

    stream =
      Stream.new(content,
        dictionary: %{
          "Type" => {:name, "XObject"},
          "Subtype" => {:name, "Form"},
          "BBox" => [0, 0, width, height],
          "Resources" => %{"Font" => %{"Helv" => font_reference}}
        },
        filters: [:flate]
      )

    {document, reference} = Document.add_object(document, stream)
    {document, %{"N" => reference}}
  end

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
    shape = appearance_shape(width, height, radius)

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
        "q #{background} rg #{border} RG #{border_width} w #{shape} B #{check} RG #{check_width} w 2 #{height / 2} m #{width / 2} 2 l #{width - 2} #{height - 2} l S Q",
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

  defp put_value(field, _type, nil), do: field

  defp put_value(field, :checkbox, value),
    do:
      field
      |> Map.put("V", {:name, if(value in [true, "Yes", :Yes], do: "Yes", else: "Off")})
      |> Map.put("AS", {:name, if(value in [true, "Yes", :Yes], do: "Yes", else: "Off")})

  defp put_value(field, :radio, value), do: Map.put(field, "V", {:name, to_string(value)})

  defp put_value(field, _type, value), do: Map.put(field, "V", value)

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
       when is_integer(flags) and flags < 32_768, do: :checkbox

  defp field_kind(%{"FT" => {:name, "Btn"}, "Ff" => flags})
       when is_integer(flags) and Bitwise.band(flags, 32_768) != 0,
       do: :radio

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
    do: Keyword.get(options, :options, [])

  defp choice_options(_type, _options), do: nil

  defp calculation_action(nil), do: nil

  defp calculation_action({:sum, fields}),
    do: javascript_action("AFSimple_Calculate(\"SUM\", #{inspect(fields)});")

  defp calculation_action({:product, fields}),
    do: javascript_action("AFSimple_Calculate(\"PRD\", #{inspect(fields)});")

  defp calculation_action({:average, fields}),
    do: javascript_action("AFSimple_Calculate(\"AVG\", #{inspect(fields)});")

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
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp export_value({:name, value}), do: value
  defp export_value(value), do: value
  defp append_content(contents, reference) when is_list(contents), do: contents ++ [reference]
  defp append_content(contents, reference), do: [contents, reference]

  defp flattened_content(field, value, x, y, width, height, options) do
    size = Keyword.get(options, :size, 10)

    if field_kind(field) in [:checkbox, :radio] and value != "Off" do
      "q 0 0 0 RG #{x + 2} #{y + height / 2} m #{x + width / 2} #{y + 2} l #{x + width - 2} #{y + height - 2} l S Q"
    else
      "BT /Helv #{size} Tf #{x + 3} #{y + max(height / 2 - size / 3, 2)} Td (#{escape(to_string(value))}) Tj ET"
    end
  end

  defp escape(value),
    do:
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("(", "\\(")
      |> String.replace(")", "\\)")

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

  defp flattenable_fields(document) do
    case acro_form(document) do
      {_reference, %{"Fields" => references}} ->
        Enum.flat_map(references, &flatten_field(document, &1, %{}))

      _ ->
        []
    end
  end

  defp flatten_field(document, %Reference{} = reference, inherited) do
    field = document.objects[reference.object_id].value
    effective = Map.merge(inherited, field)

    inherited =
      effective
      |> Map.take(["FT", "Ff", "T", "V", "DV"])
      |> Map.delete("Kids")

    children = Enum.flat_map(Map.get(field, "Kids", []), &flatten_field(document, &1, inherited))
    [{reference, effective} | children]
  end
end

defmodule PaperForge.Import.HTML do
  @moduledoc "Imports well-formed HTML fragments and a validated CSS subset."

  alias PaperForge.Import.{CSS, Markup, XML}

  @spec parse(binary(), keyword()) :: {:ok, PaperForge.Flow.t()} | {:error, term()}
  def parse(source, options \\ []) when is_binary(source) do
    wrapped = "<paperforge-root>#{source}</paperforge-root>"

    with {:ok, root} <- scan(wrapped),
         {:ok, rules} <- css_rules(root, options) do
      nodes = root |> element_content() |> Enum.map(&normalize/1)
      Markup.to_flow(nodes, Keyword.put(options, :css_rules, rules))
    end
  end

  defp scan(source) do
    {:ok, XML.parse!(source)}
  rescue
    _ -> {:error, :invalid_html}
  catch
    :exit, _ -> {:error, :invalid_html}
  end

  defp css_rules(root, options) do
    embedded =
      root
      |> element_content()
      |> collect_elements("style")
      |> Enum.map_join("\n", &element_text/1)

    external = Keyword.get(options, :css, "")
    CSS.parse(embedded <> "\n" <> external, strict: Keyword.get(options, :strict_css, true))
  end

  defp normalize({:xmlText, _parents, _pos, _language, value, _type}) do
    %{tag: "#text", attrs: %{}, children: [], text: to_string(value), raw: nil}
  end

  defp normalize({:xmlElement, name, _, _, _, _, _, _, _, _, _, _} = element) do
    tag = name |> to_string() |> String.downcase()

    %{
      tag: tag,
      attrs: attributes(element),
      children: element |> element_content() |> Enum.map(&normalize/1),
      text: nil,
      raw: if(tag == "svg", do: serialize_element(element), else: nil)
    }
  end

  defp normalize(_), do: %{tag: "#text", attrs: %{}, children: [], text: "", raw: nil}

  defp attributes({:xmlElement, _, _, _, _, _, _, attributes, _, _, _, _}) do
    Map.new(attributes, fn {:xmlAttribute, name, _, _, _, _, _, _, value, _} ->
      {name |> to_string() |> String.downcase(), to_string(value)}
    end)
  end

  defp element_content({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}), do: content
  defp element_content(_), do: []

  defp collect_elements(nodes, name) do
    Enum.flat_map(nodes, fn
      element = {:xmlElement, ^name, _, _, _, _, _, _, _, _, _, _} ->
        [element]

      element = {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} ->
        collect_elements(element_content(element), name)

      _ ->
        []
    end)
  end

  defp element_text(element) do
    element
    |> element_content()
    |> Enum.map_join("", fn
      {:xmlText, _, _, _, value, _} -> to_string(value)
      child -> element_text(child)
    end)
  end

  defp serialize_element(element), do: XML.serialize(element)
end

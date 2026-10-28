defmodule PaperForge.Import.XML do
  @moduledoc false

  # SAX keeps untrusted names as strings; the DOM scanner interns them as atoms.
  def parse!(source) when is_binary(source) do
    if byte_size(source) > 10_000_000, do: raise(ArgumentError, "XML input exceeds 10 MB")

    options = [
      :disallow_entities,
      :skip_external_dtd,
      event_fun: &event/3,
      event_state: %{stack: [], root: nil, count: 0, depth: 0, namespaces: []}
    ]

    case :xmerl_sax_parser.stream(source, options) do
      {:ok, %{root: root, stack: []}, rest} when not is_nil(root) ->
        if String.trim(to_string(rest)) != "", do: raise(ArgumentError, "trailing XML content")
        root

      _ ->
        raise ArgumentError, "invalid or unsupported XML"
    end
  end

  defp event({:startPrefixMapping, prefix, uri}, _, state) do
    name = if prefix == [], do: "xmlns", else: "xmlns:" <> to_string(prefix)
    %{state | namespaces: [attribute(name, to_string(uri)) | state.namespaces]}
  end

  defp event({:startElement, _, name, _, attributes}, _, state) do
    if state.depth >= 128 or state.count >= 100_000,
      do: throw({:xml_limit, ~c"XML structure limit exceeded"})

    attrs =
      Enum.map(attributes, fn {_, prefix, name, value} ->
        key =
          if prefix == [], do: to_string(name), else: to_string(prefix) <> ":" <> to_string(name)

        attribute(key, to_string(value))
      end)

    node = {to_string(name), attrs ++ state.namespaces, []}

    %{
      state
      | stack: [node | state.stack],
        depth: state.depth + 1,
        count: state.count + 1,
        namespaces: []
    }
  end

  defp event({:endElement, _, _, _}, _, %{stack: [{name, attrs, children} | rest]} = state) do
    node =
      {:xmlElement, name, nil, nil, nil, [], 0, attrs, Enum.reverse(children), [], [],
       :undeclared}

    append(%{state | stack: rest, depth: state.depth - 1}, node)
  end

  defp event({kind, text}, _, %{stack: [_ | _]} = state)
       when kind in [:characters, :ignorableWhitespace],
       do: append(state, {:xmlText, [], 0, [], to_string(text), :text})

  defp event(_, _, state), do: state

  defp append(%{stack: []} = state, node), do: %{state | root: node}

  defp append(%{stack: [{name, attrs, children} | rest]} = state, node),
    do: %{state | stack: [{name, attrs, [node | children]} | rest]}

  defp attribute(name, value), do: {:xmlAttribute, name, nil, nil, nil, [], 0, [], value, false}

  def serialize({:xmlElement, name, _, _, _, _, _, attrs, children, _, _, _}) do
    attrs =
      Enum.map(attrs, fn {:xmlAttribute, key, _, _, _, _, _, _, value, _} ->
        [" ", key, "=\"", escape(value), "\""]
      end)

    IO.iodata_to_binary([
      "<",
      name,
      attrs,
      ">",
      Enum.map(children, &serialize/1),
      "</",
      name,
      ">"
    ])
  end

  def serialize({:xmlText, _, _, _, value, _}), do: escape(value)

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end

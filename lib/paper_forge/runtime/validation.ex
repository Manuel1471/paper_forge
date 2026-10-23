defmodule PaperForge.Validation do
  @moduledoc """
  Performs deterministic structural validation before PDF serialization.

  Validation checks object identity, required catalog/page-tree objects,
  indirect-reference integrity, page counts, and supported PDF versions.
  """

  alias PaperForge.Document
  alias PaperForge.Fonts.Builtin
  alias PaperForge.Object
  alias PaperForge.PDF.Graph
  alias PaperForge.Reference
  alias PaperForge.Stream
  alias PaperForge.ValidationError
  alias PaperForge.ValidationResult

  @supported_versions MapSet.new(["1.0", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"])

  @type issue :: %{
          required(:code) => atom(),
          optional(:object_id) => pos_integer(),
          optional(:reference) => pos_integer(),
          optional(:expected) => term(),
          optional(:actual) => term()
        }

  @spec validate(Document.t()) :: {:ok, ValidationResult.t()} | {:error, [issue()]}
  def validate(%Document{} = document) do
    issues =
      []
      |> validate_version(document)
      |> validate_required_reference(document, :root_reference)
      |> validate_required_reference(document, :pages_reference)
      |> validate_object_identity(document)
      |> validate_references(document)
      |> validate_page_tree(document)

    case issues do
      [] ->
        {:ok,
         %ValidationResult{
           valid?: true,
           errors: [],
           warnings: warnings(document),
           objects: map_size(document.objects),
           pages: page_count(document),
           pdf_version: document.pdf_version,
           deterministic?: true
         }}

      issues ->
        {:error, Enum.reverse(issues)}
    end
  end

  @spec validate!(Document.t()) :: map()
  def validate!(%Document{} = document) do
    case validate(document) do
      {:ok, report} -> report
      {:error, issues} -> raise ValidationError, issues
    end
  end

  defp validate_version(issues, %{pdf_version: version}) do
    if MapSet.member?(@supported_versions, version),
      do: issues,
      else: [%{code: :unsupported_pdf_version, actual: version} | issues]
  end

  defp validate_required_reference(issues, document, field) do
    case Map.get(document, field) do
      %Reference{object_id: id, generation: generation} ->
        case document.objects[id] do
          nil -> [%{code: :missing_required_object, reference: id} | issues]
          %Object{generation: ^generation} -> issues
          _ -> [%{code: :generation_mismatch, reference: id, expected: generation} | issues]
        end

      value ->
        [%{code: :invalid_required_reference, actual: value} | issues]
    end
  end

  defp validate_object_identity(issues, document) do
    Enum.reduce(document.objects, issues, fn
      {id, %Object{id: actual}}, acc when id == actual ->
        acc

      {id, %Object{id: actual}}, acc ->
        [%{code: :object_id_mismatch, object_id: id, actual: actual} | acc]

      {id, value}, acc ->
        [%{code: :invalid_object, object_id: id, actual: value} | acc]
    end)
  end

  defp validate_references(issues, document) do
    Enum.reduce(document.objects, issues, fn
      {object_id, %Object{value: value}}, acc ->
        value
        |> references()
        |> Enum.reduce(acc, &validate_reference(&1, &2, object_id, document.objects))

      _entry, acc ->
        acc
    end)
  end

  defp validate_reference(
         %Reference{object_id: id, generation: generation},
         issues,
         object_id,
         objects
       ) do
    case objects[id] do
      %Object{generation: ^generation} ->
        issues

      nil ->
        [%{code: :dangling_reference, object_id: object_id, reference: id} | issues]

      _ ->
        [
          %{code: :generation_mismatch, object_id: object_id, reference: id, expected: generation}
          | issues
        ]
    end
  end

  defp validate_page_tree(issues, %{pages_reference: nil}),
    do: [%{code: :invalid_page_tree} | issues]

  defp validate_page_tree(issues, document) do
    case Graph.pages(document) do
      {:ok, pages} ->
        root = document.objects[document.pages_reference.object_id].value

        if root["Count"] == length(pages),
          do: issues,
          else: [
            %{code: :page_count_mismatch, expected: length(pages), actual: root["Count"]} | issues
          ]

      {:error, reason} ->
        [%{code: :invalid_page_tree, actual: reason} | issues]
    end
  end

  defp page_count(document) do
    case Map.get(document.objects, document.pages_reference.object_id) do
      %Object{value: %{"Count" => count}} -> count
      _ -> 0
    end
  end

  defp warnings(document) do
    []
    |> warn_empty_document(document)
    |> warn_unregistered_default_font(document)
    |> Enum.reverse()
  end

  defp warn_empty_document(warnings, document) do
    if page_count(document) == 0 do
      [issue(:empty_document, "document has no pages", ["pages"]) | warnings]
    else
      warnings
    end
  end

  defp warn_unregistered_default_font(warnings, document) do
    builtins = Builtin.keys()

    if document.default_font in builtins or
         Map.has_key?(document.font_registry.fonts, document.default_font) do
      warnings
    else
      [
        issue(
          :unknown_default_font,
          "default font #{inspect(document.default_font)} is not registered",
          ["default_font"]
        )
        | warnings
      ]
    end
  end

  defp issue(code, message, path) do
    %{code: code, code_id: code_id(code), message: message, path: path, severity: :warning}
  end

  defp code_id(:empty_document), do: "PF1201"
  defp code_id(:unknown_default_font), do: "PF3102"

  defp references(%Reference{} = reference), do: [reference]
  defp references(%Stream{dictionary: dictionary}), do: references(dictionary)
  defp references(%_struct{} = struct), do: struct |> Map.from_struct() |> references()

  defp references(value) when is_map(value),
    do: value |> Map.values() |> Enum.flat_map(&references/1)

  defp references(value) when is_list(value), do: Enum.flat_map(value, &references/1)
  defp references(_value), do: []
end

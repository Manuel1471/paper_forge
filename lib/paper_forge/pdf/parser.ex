defmodule PaperForge.PDF.Parser do
  @moduledoc false
  alias PaperForge.{Document, FontRegistry, ImageRegistry, Reference}
  alias PaperForge.PDF.{Filters, Reader, Syntax}
  alias PaperForge.Runtime.{CircuitBreaker, Guard}

  @spec parse(binary(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def parse(pdf, options \\ [])

  def parse(pdf, options) when is_binary(pdf) and is_list(options) do
    CircuitBreaker.protect(
      {:pdf_parser, :crypto.hash(:sha256, pdf)},
      fn -> guarded_parse(pdf, options) end,
      Keyword.take(options, [:failure_threshold, :reset_after_ms]) ++ [trip_on: :runtime]
    )
  end

  def parse(_, _), do: {:error, :invalid_pdf_header}

  defp guarded_parse(pdf, options) do
    case Guard.run(:import, fn -> parse_with_limits(pdf, options) end,
           timeout: Keyword.get(options, :timeout, :infinity)
         ) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_with_limits(pdf, options) do
    limits = parse_limits(pdf, options)
    version = header_version(pdf)
    {objects, trailer, structure} = Reader.read(pdf, limits, options)

    if map_size(objects) > limits.max_objects,
      do: Syntax.fail({:max_objects_exceeded, limits.max_objects})

    Enum.each(objects, fn {_, object} -> validate_stream(object.value, limits.max_stream_size) end)

    linearized =
      Enum.any?(objects, fn {_, object} ->
        is_map(object.value) and not is_struct(object.value) and
          is_number(object.value["Linearized"])
      end)

    structure = Map.put(structure, :linearized, linearized)
    root = trailer["Root"]
    {catalog, pages} = catalog_and_pages(objects, root)

    version =
      case catalog["Version"] do
        {:name, override}
        when override in ["1.0", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"] ->
          max(version, override)

        _ ->
          version
      end

    document = %Document{
      objects: objects,
      next_object_id: Enum.max(Map.keys(objects), fn -> 2 end) + 1,
      root_reference: root,
      pages_reference: pages,
      info_reference: trailer["Info"],
      pdf_version: version,
      font_registry: FontRegistry.new(),
      image_registry: ImageRegistry.new(),
      outlines_reference: catalog["Outlines"],
      source_info: Map.merge(structure, %{file_size: byte_size(pdf), trailer: trailer})
    }

    {:ok, document}
  catch
    {:pdf_error, reason} -> {:error, reason}
  end

  defp parse_limits(pdf, options) do
    limits = %{
      max_file_size: Keyword.get(options, :max_file_size, 100_000_000),
      max_objects: Keyword.get(options, :max_objects, 500_000),
      max_depth:
        Keyword.get(options, :max_recursion_depth, Keyword.get(options, :max_depth, 100)),
      max_stream_size:
        Keyword.get(
          options,
          :max_uncompressed_stream_bytes,
          Keyword.get(options, :max_stream_size, 50_000_000)
        )
    }

    unless Enum.all?(Map.values(limits), &(is_integer(&1) and &1 > 0)),
      do: Syntax.fail(:invalid_parse_limits)

    if byte_size(pdf) > limits.max_file_size,
      do: Syntax.fail({:max_file_size_exceeded, limits.max_file_size})

    limits
  end

  defp header_version(pdf) do
    case Regex.run(~r/^%PDF-(1\.[0-7]|2\.0)(?:[\r\n\x00\t ])/, pdf, capture: :all_but_first) do
      [version] -> version
      _ -> Syntax.fail(:invalid_pdf_header)
    end
  end

  defp validate_stream(%PaperForge.Stream{} = stream, limit) do
    case Filters.decode(stream, limit) do
      {:ok, _} -> :ok
      {:error, {:unsupported_stream_filter, _}} -> :ok
      {:error, {:unsupported_predictor, _}} -> :ok
      {:error, reason} -> Syntax.fail(reason)
    end
  end

  defp validate_stream(_, _), do: :ok

  defp catalog_and_pages(objects, root) do
    catalog = resolve(objects, root)

    unless is_map(catalog) and catalog["Type"] == {:name, "Catalog"},
      do: Syntax.fail(:pdf_catalog_not_found)

    pages = catalog["Pages"]
    unless match?(%Reference{}, pages), do: Syntax.fail(:invalid_page_tree)
    page_root = resolve(objects, pages)

    unless is_map(page_root) and page_root["Type"] == {:name, "Pages"},
      do: Syntax.fail(:invalid_page_tree)

    {catalog, pages}
  end

  defp resolve(objects, %Reference{object_id: id, generation: generation}) do
    case objects[id] do
      %{generation: ^generation, value: value} -> value
      _ -> Syntax.fail({:broken_reference, id, generation})
    end
  end

  defp resolve(_, _), do: Syntax.fail(:invalid_required_reference)
end

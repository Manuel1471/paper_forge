defmodule PaperForge.Declarative.Loader do
  @moduledoc false

  alias PaperForge.Declarative.Error
  alias PaperForge.Declarative.LocationMap
  alias PaperForge.Declarative.Migration

  @default_max_bytes 2_000_000
  @default_max_imports 32

  @spec load(Path.t(), keyword()) :: {:ok, map()} | {:error, [Error.t()]}
  def load(path, options \\ []) do
    absolute = Path.expand(path)
    root = options |> Keyword.get(:root, Path.dirname(absolute)) |> Path.expand()

    with :ok <- inside_root(absolute, root),
         {:ok, template} <- load_file(absolute, root, options, [], 0) do
      {:ok, Map.merge(template, %{"__source__" => absolute, "__root__" => root})}
    else
      {:error, %Error{} = issue} ->
        {:error, [issue]}

      {:error, reason} ->
        {:error, [error(:file_error, absolute, inspect(reason), reason, absolute)]}
    end
  end

  defp load_file(path, root, options, stack, count) do
    cond do
      path in stack ->
        {:error,
         error(
           :import_cycle,
           "$.imports",
           "import cycle detected",
           Enum.reverse([path | stack]),
           path
         )}

      count >= Keyword.get(options, :max_imports, @default_max_imports) ->
        {:error, error(:import_limit, "$.imports", "maximum import count exceeded", count, path)}

      true ->
        with :ok <- inside_root(path, root),
             :ok <- no_symlink(path, root),
             {:ok, stat} <- File.stat(path),
             :ok <-
               size_allowed(
                 stat.size,
                 Keyword.get(options, :max_template_bytes, @default_max_bytes)
               ),
             {:ok, source} <- File.read(path),
             {:ok, template} <- decode(source, path),
             {:ok, migrated} <- Migration.migrate(template),
             {:ok, imported} <- load_imports(migrated, path, root, options, [path | stack], count),
             {:ok, components} <-
               load_components(migrated, path, root, options, [path | stack], count),
             {:ok, included_blocks} <-
               load_includes(migrated, path, root, options, [path | stack], count) do
          own = Map.drop(migrated, ["imports", "includes", "libraries", "components"])
          own = merge_components(own, components)
          merged = deep_merge(imported, own)
          {:ok, Map.update(merged, "blocks", included_blocks, &(included_blocks ++ &1))}
        else
          {:error, %Error{} = issue} -> {:error, issue}
          {:error, reason} -> {:error, error(:file_error, path, inspect(reason), reason, path)}
        end
    end
  end

  defp load_imports(template, source, root, options, stack, count) do
    paths =
      List.wrap(Map.get(template, "imports", [])) ++ List.wrap(Map.get(template, "libraries", []))

    Enum.reduce_while(paths, {:ok, %{}}, fn relative, {:ok, acc} ->
      with {:ok, path} <- resolve_path(relative, source, root),
           {:ok, imported} <- load_file(path, root, options, stack, count + 1) do
        library = Map.drop(imported, ["blocks", "__source__", "__root__"])
        {:cont, {:ok, deep_merge(acc, library)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp load_includes(template, source, root, options, stack, count) do
    Enum.reduce_while(List.wrap(Map.get(template, "includes", [])), {:ok, []}, fn relative,
                                                                                  {:ok, acc} ->
      with {:ok, path} <- resolve_path(relative, source, root),
           {:ok, included} <- load_file(path, root, options, stack, count + 1) do
        {:cont, {:ok, acc ++ Map.get(included, "blocks", [])}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp load_components(template, source, root, options, stack, count) do
    Enum.reduce_while(List.wrap(Map.get(template, "components", [])), {:ok, %{}}, fn relative,
                                                                                     {:ok, acc} ->
      with {:ok, path} <- resolve_path(relative, source, root),
           {:ok, component_file} <- load_file(path, root, options, stack, count + 1),
           {:ok, name, definition} <- component_definition(component_file, path) do
        dependencies = get_in(component_file, ["design_system", "components"]) || %{}
        components = dependencies |> deep_merge(%{name => definition}) |> deep_merge(acc)
        {:cont, {:ok, components}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp component_definition(%{"kind" => "component", "name" => name} = file, _source)
       when is_binary(name) and name != "" do
    definition = Map.take(file, ["props", "defaults", "slots", "variants", "blocks"])
    {:ok, name, Map.put_new(definition, "blocks", [])}
  end

  defp component_definition(_file, source) do
    {:error,
     error(
       :invalid_component_file,
       "$",
       "component file must define kind=component and a non-empty name",
       nil,
       source
     )}
  end

  defp merge_components(template, components) when map_size(components) == 0, do: template

  defp merge_components(template, components) do
    design = Map.get(template, "design_system", %{})
    inline = Map.get(design, "components", %{})

    Map.put(
      template,
      "design_system",
      Map.put(design, "components", deep_merge(components, inline))
    )
  end

  defp resolve_path(relative, source, root) when is_binary(relative) do
    path = Path.expand(relative, Path.dirname(source))

    case inside_root(path, root) do
      :ok ->
        {:ok, path}

      {:error, reason} ->
        {:error,
         error(:forbidden_import, "$.imports", "import escapes template root", reason, source)}
    end
  end

  defp resolve_path(_relative, source, _root),
    do: {:error, error(:invalid_import, "$.imports", "import path must be a string", nil, source)}

  defp decode(source, path) do
    case Jason.decode(source) do
      {:ok, template} when is_map(template) ->
        {:ok, Map.put(template, "__locations__", LocationMap.build(source, path))}

      {:ok, _} ->
        {:error, error(:invalid_root, "$", "template root must be an object", nil, path)}

      {:error, reason} ->
        {:error,
         Error.new(:invalid_json, "$", Exception.message(reason), reason,
           source: path,
           line: Map.get(reason, :line),
           column: Map.get(reason, :column)
         )}
    end
  end

  defp inside_root(path, root) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)
    root_prefix = expanded_root <> "/"

    if expanded_path == expanded_root or String.starts_with?(expanded_path, root_prefix),
      do: :ok,
      else: {:error, :outside_root}
  end

  defp size_allowed(size, maximum) when size <= maximum, do: :ok
  defp size_allowed(size, maximum), do: {:error, {:template_too_large, size, maximum}}

  defp no_symlink(path, root) do
    path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce_while(root, fn segment, current ->
      candidate = Path.join(current, segment)

      case File.lstat(candidate) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :symlink_not_allowed}}
        {:ok, _stat} -> {:cont, candidate}
        {:error, :enoent} -> {:halt, {:error, :enoent}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _path -> :ok
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, a, b ->
      if is_map(a) and is_map(b), do: deep_merge(a, b), else: b
    end)
  end

  defp error(code, path, message, details, source),
    do: Error.new(code, path, message, details, source: source)
end

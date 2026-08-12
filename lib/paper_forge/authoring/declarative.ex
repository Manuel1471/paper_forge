defmodule PaperForge.Declarative do
  @moduledoc """
  Safe compiler for versioned `.paperforge` declarative documents.

  Templates are JSON documents containing data only. PaperForge never evaluates
  Elixir source from a template. Variables are validated before conditions,
  loops, and components are expanded into `PaperForge.Flow`, the public Layout
  IR used by the existing pagination engine.
  """

  alias PaperForge.Color
  alias PaperForge.AcroForm
  alias PaperForge.Declarative.Cache
  alias PaperForge.Declarative.Compiled
  alias PaperForge.Declarative.Error
  alias PaperForge.Declarative.Expression
  alias PaperForge.Declarative.Loader
  alias PaperForge.Declarative.LocationMap
  alias PaperForge.Declarative.Migration
  alias PaperForge.Declarative.Registry
  alias PaperForge.Declarative.Validator
  alias PaperForge.DesignSystem
  alias PaperForge.Flow
  alias PaperForge.Import
  alias PaperForge.Math

  @max_depth 64
  @default_limits %{
    max_blocks: 10_000,
    max_loop_iterations: 10_000,
    max_table_rows: 50_000,
    max_data_bytes: 10_000_000
  }
  @option_keys ~w(
    align background_color borders caption cell_height color colors column_gap column_widths
    compress count default_font destination even_footer even_header extends fill_color fit
    focal_point font footer gap header header_color
    header_fill_color height hyphenate id keep_together level line_height link marker
    margins numbered odd_footer odd_header orientation ordered padding page_break_after
    page_break_before pdf_version prefix repeat_header
    row_split row_height cell_line_height size space_after space_before spacer stroke_color stripe_fill_color style suffix template title
    type valign width widow_lines orphan_lines x y first_footer first_header last_footer
    last_header text author subject name filename data points reply_to reply_type
    default_appearance border_color line_width chart_type show_values show_legend
    point_radius inner_radius grid_color label_color chart_padding
    weight
  )a
  @enum_values ~w(
    left center right justify top middle bottom contain cover fill ordered unordered
    keep split error clip ellipsis continue portrait landscape all none a3 a4 a5 letter legal
    bar line area scatter pie donut regular bold
  )a
  @declarative_font_slots for index <- 1..64,
                              do: String.to_atom("paperforge_declarative_font_#{index}")
  @metadata_keys %{
    "title" => :title,
    "author" => :author,
    "subject" => :subject,
    "keywords" => :keywords,
    "creator" => :creator,
    "producer" => :producer,
    "creation_date" => :creation_date,
    "modification_date" => :modification_date
  }

  @type source :: binary() | map()

  @doc "Returns the packaged JSON Schema path for editor and CI integration."
  @spec schema_path() :: Path.t()
  def schema_path, do: Application.app_dir(:paper_forge, "priv/paperforge.schema.json")

  @doc "Migrates an older declarative map to the current format version."
  @spec migrate(map()) :: {:ok, map()} | {:error, term()}
  def migrate(template), do: template |> stringify() |> Migration.migrate()

  @doc "Clears the current process's bounded compiled-template cache."
  @spec clear_cache() :: :ok
  def clear_cache, do: Cache.clear()

  @doc "Parses JSON template content into a normalized map."
  @spec parse(source()) :: {:ok, map()} | {:error, [Error.t()]}
  def parse(source) when is_map(source), do: source |> stringify() |> Migration.migrate()

  def parse(source) when is_binary(source) do
    case Jason.decode(source) do
      {:ok, value} when is_map(value) ->
        value
        |> Map.put("__locations__", LocationMap.build(source))
        |> Migration.migrate()

      {:ok, _value} ->
        {:error, [error(:invalid_root, "$", "template root must be an object")]}

      {:error, reason} ->
        {:error, [error(:invalid_json, "$", Exception.message(reason), reason)]}
    end
  end

  @doc "Loads and parses a `.paperforge` file."
  @spec load(Path.t(), keyword()) :: {:ok, map()} | {:error, [Error.t()]}
  def load(path, options \\ []) when is_binary(path), do: Loader.load(path, options)

  @doc "Validates template structure, input data, design references, and blocks."
  @spec validate(source(), map() | keyword(), keyword()) :: :ok | {:error, [Error.t()]}
  def validate(source, data \\ %{}, options \\ []) do
    case compile(source, data, options) do
      {:ok, _compiled} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  @doc "Compiles a template and data into validated `PaperForge.Flow` Layout IR."
  @spec compile(source(), map() | keyword(), keyword()) ::
          {:ok, Compiled.t()} | {:error, [Error.t()]}
  def compile(source, data \\ %{}, options \\ []) do
    with {:ok, template} <- parse(source) do
      compile_template(template, data, options)
      |> locate_errors(template, options)
    end
  rescue
    exception ->
      {:error, [error(:compilation_error, "$", Exception.message(exception), exception)]}
  end

  defp compile_template(template, data, options) do
    with :ok <- data_size_allowed(data, options),
         registry <- registry(template, options),
         {:ok, variables} <-
           Validator.validate(template, stringify(Map.new(data)),
             registry: registry,
             reject_unknown_data: Keyword.get(options, :reject_unknown_data, false)
           ),
         {:ok, system} <- design_system(template, options),
         {:ok, definition} <- apply_layout(template, system),
         {:ok, font_keys} <- declarative_font_keys(definition),
         state <- %{
           design: system,
           registry: registry,
           limits: limits(options),
           blocks: 0,
           equation_count: 0,
           component_stack: [],
           font_keys: font_keys
         },
         {:ok, flow, _state} <-
           compile_blocks(Map.get(definition, "blocks", []), variables, state, 0) do
      template_hash =
        Cache.hash(Map.drop(template, ["__source__", "__root__", "__locations__"]))

      {:ok,
       %Compiled{
         flow: flow,
         template_id: to_string(Map.get(template, "id", binary_part(template_hash, 0, 16))),
         template_hash: template_hash,
         document_options:
           options_to_keyword(
             interpolate(Map.get(definition, "document", %{}), variables),
             system.tokens,
             font_keys
           ),
         layout_options:
           options_to_keyword(
             interpolate(Map.get(definition, "layout_options", %{}), variables),
             system.tokens,
             font_keys
           ),
         fonts: compile_fonts(definition, options, font_keys),
         font_fallbacks:
           compile_font_fallbacks(Map.get(definition, "font_fallbacks", %{}), font_keys),
         styles: compile_named_options(system.styles, system.tokens, variables),
         page_templates:
           compile_named_options(
             Map.get(definition, "page_templates", %{}),
             system.tokens,
             variables
           ),
         metadata: interpolate(Map.get(definition, "metadata", %{}), variables),
         forms: compile_forms(interpolate(Map.get(definition, "forms", []), variables)),
         security: compile_security(interpolate(Map.get(definition, "security", %{}), variables)),
         signature:
           compile_signature(interpolate(Map.get(definition, "signature", %{}), variables)),
         protection:
           compile_protection(interpolate(Map.get(definition, "protection", %{}), variables)),
         compliance:
           compile_compliance(interpolate(Map.get(definition, "compliance", %{}), variables))
       }}
    else
      {:error, %Error{} = issue} -> {:error, [issue]}
      {:error, issues} when is_list(issues) -> {:error, issues}
      issues when is_list(issues) -> {:error, issues}
    end
  end

  defp locate_errors({:error, errors}, template, options) when is_list(errors) do
    template_locations = Map.get(template, "__locations__", %{})
    data_locations = Keyword.get(options, :data_locations, %{})
    template_source = Map.get(template, "__source__")
    data_source = Keyword.get(options, :data_source)

    {:error,
     Enum.map(errors, fn issue ->
       locate_error(
         issue,
         template_locations,
         data_locations,
         template_source,
         data_source
       )
     end)}
  end

  defp locate_errors(result, _template, _options), do: result

  defp locate_error(%Error{line: line} = issue, _template, _data, _source, _data_source)
       when not is_nil(line),
       do: issue

  defp locate_error(issue, template_locations, data_locations, template_source, data_source) do
    {locations, lookup_path, fallback_source} =
      if String.starts_with?(issue.path, "$.data") do
        data_path = String.replace_prefix(issue.path, "$.data", "$")

        if map_size(data_locations) > 0 do
          {data_locations, data_path, data_source}
        else
          variable_path = String.replace_prefix(issue.path, "$.data", "$.variables")
          {template_locations, variable_path, template_source}
        end
      else
        {template_locations, issue.path, template_source}
      end

    case nearest_location(locations, lookup_path) do
      nil ->
        %{issue | source: issue.source || fallback_source}

      location ->
        %{
          issue
          | source:
              issue.source || Map.get(location, :source) || Map.get(location, "source") ||
                fallback_source,
            line: Map.get(location, :line) || Map.get(location, "line"),
            column: Map.get(location, :column) || Map.get(location, "column")
        }
    end
  end

  defp nearest_location(locations, path) do
    case Map.get(locations, path) do
      nil ->
        parent = path |> String.replace(~r/(?:\.[^.\[]+|\[\d+\])$/, "")
        if parent == path or parent == "", do: nil, else: nearest_location(locations, parent)

      location ->
        location
    end
  end

  @doc "Compiles with a bounded process-local cache keyed by template, data, and safe options."
  @spec compile_cached(source(), map() | keyword(), keyword()) ::
          {:ok, Compiled.t()} | {:error, [Error.t()]}
  def compile_cached(source, data \\ %{}, options \\ []) do
    registry = Keyword.get(options, :registry)

    if registry && map_size(registry.components) > 0 do
      compile(source, data, options)
    else
      cache_options = Keyword.drop(options, [:registry])
      key = Cache.hash({source, Map.new(data), cache_options})

      case Cache.fetch(key) do
        {:ok, compiled} ->
          {:ok, compiled}

        :error ->
          case compile(source, data, options) do
            {:ok, compiled} -> {:ok, Cache.put(key, compiled)}
            error -> error
          end
      end
    end
  end

  @doc "Compiles and renders a declarative template through the normal layout engine."
  @spec render(source(), map() | keyword(), keyword()) ::
          {:ok, PaperForge.Document.t(), map()} | {:error, [Error.t()]}
  def render(source, data \\ %{}, options \\ []) do
    compiler = if Keyword.get(options, :cache, false), do: &compile_cached/3, else: &compile/3

    with {:ok, compiled} <- compiler.(source, data, options),
         {:ok, document, report} <- render_compiled(compiled) do
      {:ok, document, Map.put(report, :template_hash, compiled.template_hash)}
    end
  end

  @doc "Renders and writes a declarative document, keeping passwords in write-time options only."
  @spec write(source(), map() | keyword(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, [Error.t()] | File.posix()}
  def write(source, data, path, options \\ []) when is_binary(path) do
    compile_options = Keyword.drop(options, [:security, :signature])
    compiler = if Keyword.get(options, :cache, false), do: &compile_cached/3, else: &compile/3

    with {:ok, compiled} <- compiler.(source, data, compile_options),
         {:ok, document, report} <- render_compiled(compiled),
         security <- merge_security(compiled.security, Keyword.get(options, :security, [])),
         signature <- merge_signature(compiled.signature, Keyword.get(options, :signature, [])),
         :ok <- write_document(document, path, security, signature) do
      {:ok, Map.put(report, :template_hash, compiled.template_hash)}
    end
  end

  defp render_compiled(compiled) do
    {default_font, document_options} =
      Keyword.pop(compiled.document_options, :default_font, :helvetica)

    document =
      document_options
      |> PaperForge.new()
      |> register_fonts(compiled.fonts)
      |> register_font_fallbacks(compiled.font_fallbacks)
      |> PaperForge.default_font(default_font)
      |> register_styles(compiled.styles)
      |> register_templates(compiled.page_templates)
      |> register_metadata(compiled.metadata)

    {document, report} =
      PaperForge.layout(document, fn _flow -> compiled.flow end, compiled.layout_options)

    document =
      document
      |> apply_forms(compiled.forms)
      |> maybe_comply(compiled.compliance)
      |> maybe_protect(compiled.protection)

    {:ok, document, report}
  rescue
    exception -> {:error, [error(:render_error, "$", Exception.message(exception), exception)]}
  end

  defp compile_fonts(definition, options, font_keys) do
    sources = options |> Keyword.get(:font_sources, %{}) |> Map.new()
    root = Map.get(definition, "__root__")

    definition
    |> Map.get("fonts", %{})
    |> Map.new(fn {name, font} ->
      data =
        cond do
          source = font["source"] ->
            Map.get(sources, source) || Map.get(sources, existing_atom(source)) ||
              raise(ArgumentError, "unknown declarative font source #{inspect(source)}")

          path = font["path"] ->
            load_declarative_font!(path, root)
        end

      {font_key(name, font_keys), [data: data, subset: Map.get(font, "subset", true)]}
    end)
  end

  defp compile_font_fallbacks(fallbacks, font_keys) do
    Map.new(fallbacks, fn {name, values} ->
      {font_key(name, font_keys), Enum.map(values, &font_key(&1, font_keys))}
    end)
  end

  defp load_declarative_font!(path, root) when is_binary(root) do
    absolute = Path.expand(path, root)
    prefix = root <> "/"

    if (absolute == root or String.starts_with?(absolute, prefix)) and
         not symlinked_path?(absolute, root) do
      File.read!(absolute)
    else
      raise ArgumentError, "font path escapes the template root"
    end
  end

  defp load_declarative_font!(_path, _root),
    do: raise(ArgumentError, "font paths require a template loaded from disk")

  defp symlinked_path?(path, root) do
    path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce_while(root, fn segment, current ->
      candidate = Path.join(current, segment)

      case File.lstat(candidate) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, true}
        {:ok, _stat} -> {:cont, candidate}
        {:error, _reason} -> {:halt, true}
      end
    end)
    |> Kernel.==(true)
  end

  defp register_fonts(document, fonts) do
    Enum.reduce(fonts, document, fn {name, options}, current ->
      PaperForge.register_font(current, name, options)
    end)
  end

  defp register_font_fallbacks(document, fallbacks) do
    Enum.reduce(fallbacks, document, fn {name, values}, current ->
      PaperForge.font_fallback(current, name, values)
    end)
  end

  defp design_system(template, options) do
    external = Keyword.get(options, :design_system, DesignSystem.new())
    inline = DesignSystem.new(Map.get(template, "design_system", %{}))
    system = DesignSystem.merge(external, inline)

    case DesignSystem.resolve(system, Map.get(template, "theme", Keyword.get(options, :theme))) do
      {:ok, resolved} ->
        {:ok, resolved}

      {:error, reason} ->
        {:error, error(:invalid_theme, "$.theme", "could not resolve theme", reason)}
    end
  end

  defp apply_layout(template, system) do
    case Map.get(template, "layout") do
      nil ->
        {:ok, template}

      name when is_binary(name) ->
        case Map.fetch(system.layouts, name) do
          {:ok, layout} ->
            {:ok, deep_merge(layout, Map.delete(template, "layout"))}

          :error ->
            {:error, error(:unknown_layout, "$.layout", "unknown layout #{inspect(name)}")}
        end

      _ ->
        {:error, error(:invalid_layout, "$.layout", "layout must be a design-system layout name")}
    end
  end

  defp compile_blocks(_blocks, _context, _state, depth) when depth > @max_depth,
    do: {:error, error(:maximum_depth, "$.blocks", "maximum expansion depth exceeded")}

  defp compile_blocks(blocks, context, state, depth) when is_list(blocks) do
    Enum.reduce_while(blocks, {:ok, Flow.new(), state}, fn block, {:ok, flow, current_state} ->
      next_count = current_state.blocks + 1

      if next_count > current_state.limits.max_blocks do
        {:halt, {:error, error(:block_limit, "$.blocks", "maximum block count exceeded")}}
      else
        current_state = %{current_state | blocks: next_count}

        case compile_node(flow, block, context, current_state, depth) do
          {:ok, next_flow, next_state} -> {:cont, {:ok, next_flow, next_state}}
          {:error, issue} -> {:halt, {:error, issue}}
        end
      end
    end)
  end

  defp compile_blocks(_blocks, _context, _state, _depth),
    do: {:error, error(:invalid_blocks, "$.blocks", "blocks must be a list")}

  defp compile_node(flow, %{"if" => condition} = node, context, state, depth) do
    with {:ok, result} <- Expression.evaluate(condition, context, &lookup/2) do
      selected = if result, do: Map.get(node, "then", []), else: Map.get(node, "else", [])
      append_compiled(flow, selected, context, state, depth + 1)
    else
      {:error, reason} ->
        {:error, error(:invalid_expression, "$.if", "invalid condition", reason)}
    end
  end

  defp compile_node(flow, %{"for" => loop} = node, context, state, depth) do
    with {:ok, path, binding} <- parse_loop(loop),
         values when is_list(values) <- lookup(context, path),
         true <- length(values) <= state.limits.max_loop_iterations do
      Enum.reduce_while(values, {:ok, flow, state}, fn value, {:ok, current, current_state} ->
        loop_context = Map.put(context, binding, value)

        case append_compiled(
               current,
               Map.get(node, "blocks", []),
               loop_context,
               current_state,
               depth + 1
             ) do
          {:ok, next, next_state} -> {:cont, {:ok, next, next_state}}
          {:error, issue} -> {:halt, {:error, issue}}
        end
      end)
    else
      nil ->
        {:error, error(:unknown_variable, "$.for", "loop collection was not found")}

      false ->
        {:error, error(:loop_limit, "$.for", "maximum loop iterations exceeded")}

      _ ->
        {:error,
         error(:invalid_loop, "$.for", "expected `item in collection` or an each/as object")}
    end
  end

  defp compile_node(flow, %{"slot" => name}, context, state, _depth) do
    case get_in(context, ["__slots__", to_string(name)]) do
      %Flow{} = slot_flow -> {:ok, %{flow | blocks: slot_flow.blocks ++ flow.blocks}, state}
      nil -> {:ok, flow, state}
    end
  end

  defp compile_node(flow, %{"component" => name} = node, context, state, depth) do
    name = to_string(name)

    if name in state.component_stack do
      {:error,
       error(
         :component_cycle,
         "$.component",
         "component cycle detected",
         Enum.reverse([name | state.component_stack])
       )}
    else
      compile_component(flow, name, node, context, state, depth)
    end
  end

  defp compile_node(flow, %{"type" => type} = node, context, state, _depth) do
    content = interpolate(Map.get(node, "content", Map.get(node, "text")), context)

    options =
      options_to_keyword(
        interpolate(Map.get(node, "options", %{}), context),
        state.design.tokens,
        state.font_keys
      )

    case apply_block(flow, type, content, node, context, options, state) do
      {:ok, next_flow} -> {:ok, next_flow, state}
      {:ok, next_flow, next_state} -> {:ok, next_flow, next_state}
      error -> error
    end
  rescue
    exception -> {:error, error(:invalid_block, "$.blocks", Exception.message(exception), node)}
  end

  defp compile_node(_flow, node, _context, _state, _depth),
    do:
      {:error,
       error(
         :invalid_block,
         "$.blocks",
         "block must define type, component, slot, if, or for",
         node
       )}

  defp compile_component(flow, name, node, context, state, depth) do
    case Registry.fetch_component(state.registry, name) do
      {:ok, _component} ->
        compile_trusted_component(flow, name, node, context, state, depth)

      :error ->
        case Map.fetch(state.design.components, name) do
          {:ok, definition} ->
            compile_declarative_component(flow, name, node, definition, context, state, depth)

          :error ->
            compile_trusted_component(flow, name, node, context, state, depth)
        end
    end
  end

  defp compile_declarative_component(flow, name, node, definition, context, state, depth) do
    variant = Map.get(node, "variant")
    definition = apply_variant(definition, variant)

    props =
      Map.merge(
        Map.get(definition, "defaults", %{}),
        interpolate(Map.get(node, "props", %{}), context)
      )

    with :ok <-
           validate_props(
             props,
             Map.get(definition, "props", %{}),
             "$.component.#{name}",
             state.registry
           ),
         :ok <- validate_slots(node, definition, name),
         {:ok, slots, state} <-
           compile_slots(Map.get(node, "slots", %{}), context, state, depth + 1) do
      component_context = context |> Map.merge(props) |> Map.put("__slots__", slots)
      blocks = Map.get(definition, "blocks", [])
      nested_state = %{state | component_stack: [name | state.component_stack]}

      case append_compiled(flow, blocks, component_context, nested_state, depth + 1) do
        {:ok, next, next_state} ->
          {:ok, next, %{next_state | component_stack: state.component_stack}}

        error ->
          error
      end
    end
  rescue
    exception ->
      {:error,
       error(:invalid_variant, "$.component.#{name}.variant", Exception.message(exception))}
  end

  defp compile_trusted_component(flow, name, node, context, state, depth) do
    case Registry.fetch_component(state.registry, name) do
      {:ok, component} ->
        props = interpolate(Map.get(node, "props", %{}), context)

        with :ok <- validate_props(props, component.props, "$.component.#{name}", state.registry),
             {:ok, slots, next_state} <-
               compile_slots(Map.get(node, "slots", %{}), context, state, depth + 1),
             {:ok, trusted_flow} <-
               Registry.render(component, props, slots, Map.get(node, "variant")) do
          {:ok, %{flow | blocks: trusted_flow.blocks ++ flow.blocks}, next_state}
        else
          {:error, %Error{} = issue} ->
            {:error, issue}

          {:error, reason} ->
            {:error,
             error(
               :trusted_component_error,
               "$.component.#{name}",
               "trusted component failed",
               reason
             )}
        end

      :error ->
        {:error, error(:unknown_component, "$.component", "unknown component #{inspect(name)}")}
    end
  end

  defp compile_slots(slots, context, state, depth) when is_map(slots) do
    Enum.reduce_while(slots, {:ok, %{}, state}, fn {name, blocks},
                                                   {:ok, compiled, current_state} ->
      case compile_blocks(blocks, context, current_state, depth) do
        {:ok, slot_flow, next_state} ->
          {:cont, {:ok, Map.put(compiled, name, slot_flow), next_state}}

        {:error, issue} ->
          {:halt, {:error, issue}}
      end
    end)
  end

  defp compile_slots(_slots, _context, _state, _depth),
    do: {:error, error(:invalid_slots, "$.slots", "slots must be an object")}

  defp append_compiled(flow, blocks, context, state, depth) do
    with {:ok, nested, next_state} <- compile_blocks(blocks, context, state, depth) do
      {:ok, %{flow | blocks: nested.blocks ++ flow.blocks}, next_state}
    end
  end

  defp apply_variant(definition, nil), do: definition

  defp apply_variant(definition, variant) do
    case get_in(definition, ["variants", to_string(variant)]) do
      nil -> raise ArgumentError, "unknown component variant #{inspect(variant)}"
      overrides -> deep_merge(Map.delete(definition, "variants"), overrides)
    end
  end

  defp validate_props(props, schemas, path, registry) when is_map(schemas) do
    errors =
      Enum.flat_map(schemas, fn {name, schema} ->
        schema = if is_map(schema), do: schema, else: %{"type" => schema}

        cond do
          Map.get(schema, "required", false) and not Map.has_key?(props, name) ->
            [error(:required_prop, "#{path}.props.#{name}", "required component prop is missing")]

          Map.has_key?(props, name) ->
            Validator.validate_value(
              Map.get(props, name),
              schema,
              "#{path}.props.#{name}",
              registry
            )

          true ->
            []
        end
      end)

    if errors == [], do: :ok, else: {:error, List.first(errors)}
  end

  defp validate_slots(node, definition, name) do
    supplied = Map.get(node, "slots", %{})
    schemas = Map.get(definition, "slots", %{})

    missing =
      schemas
      |> Enum.filter(fn {_slot, schema} -> Map.get(schema, "required", false) end)
      |> Enum.reject(fn {slot, _schema} -> Map.has_key?(supplied, slot) end)

    unknown = Map.keys(supplied) -- Map.keys(schemas)

    cond do
      missing != [] ->
        {slot, _schema} = List.first(missing)

        {:error,
         error(:required_slot, "$.component.#{name}.slots.#{slot}", "required slot is missing")}

      schemas != %{} and unknown != [] ->
        slot = List.first(unknown)

        {:error,
         error(:unknown_slot, "$.component.#{name}.slots.#{slot}", "slot is not declared")}

      true ->
        :ok
    end
  end

  defp registry(template, options) do
    case Keyword.get(options, :registry) do
      %Registry{} = registry -> registry
      nil -> Registry.new(resource_root: Map.get(template, "__root__"))
    end
  end

  defp limits(options) do
    supplied = options |> Keyword.get(:limits, %{}) |> Map.new()
    Map.merge(@default_limits, supplied)
  end

  defp data_size_allowed(data, options) do
    maximum = limits(options).max_data_bytes
    size = data |> :erlang.term_to_binary() |> byte_size()

    if size <= maximum,
      do: :ok,
      else:
        {:error,
         error(:data_limit, "$.data", "input data is too large", %{bytes: size, maximum: maximum})}
  end

  defp apply_block(flow, "heading", content, _node, _context, options, _state),
    do: {:ok, Flow.heading(flow, to_text(content), options)}

  defp apply_block(flow, "paragraph", content, _node, _context, options, _state),
    do: {:ok, Flow.paragraph(flow, to_text(content), options)}

  defp apply_block(flow, "rich_text", content, _node, _context, options, _state),
    do: {:ok, Flow.rich_text(flow, rich_runs(content), options)}

  defp apply_block(flow, "image", content, _node, _context, options, state) do
    case Registry.resolve_resource(state.registry, to_text(content)) do
      {:ok, source} ->
        {:ok, Flow.image(flow, source, options)}

      {:error, reason} ->
        {:error,
         error(:forbidden_resource, "$.blocks.image", "image resource is not allowed", reason)}
    end
  end

  defp apply_block(flow, "svg", content, _node, _context, options, _state),
    do: {:ok, Flow.svg(flow, to_text(content), options)}

  defp apply_block(flow, "html", content, _node, _context, options, _state) do
    with {:ok, imported} <- Import.html(to_text(content), options) do
      {:ok, append_flow(flow, imported)}
    end
  end

  defp apply_block(flow, "markdown", content, _node, _context, options, _state) do
    with {:ok, imported} <- Import.markdown(to_text(content), options) do
      {:ok, append_flow(flow, imported)}
    end
  end

  defp apply_block(flow, "math", content, node, context, options, _state) do
    ast = interpolate(Map.get(node, "ast", content), context)
    {:ok, Flow.math(flow, math_ast(ast), options)}
  end

  defp apply_block(flow, "equation", content, node, context, options, state) do
    number = state.equation_count + 1
    ast = interpolate(Map.get(node, "ast", content), context) |> math_ast()
    destination = Keyword.get(options, :destination, "equation-#{number}")
    title = Keyword.get(options, :title, "Equation #{number}")

    flow =
      flow
      |> Flow.heading(title,
        level: Keyword.get(options, :level, 4),
        destination: destination,
        bookmark: false
      )
      |> Flow.math(ast, options)

    {:ok, flow, %{state | equation_count: number}}
  end

  defp apply_block(flow, "equation_reference", content, node, _context, options, _state) do
    number = Map.get(node, "number", content)

    if is_integer(number) and number > 0 do
      text = Keyword.get(options, :text, "Equation #{number}, page {page}")
      {:ok, Flow.reference(flow, "equation-#{number}", Keyword.put(options, :text, text))}
    else
      {:error,
       error(
         :invalid_equation_reference,
         "$.blocks.number",
         "equation number must be a positive integer"
       )}
    end
  end

  defp apply_block(flow, "footnote", content, _node, _context, options, _state),
    do: {:ok, Flow.footnote(flow, to_text(content), options)}

  defp apply_block(flow, "endnotes", content, _node, _context, options, _state) do
    notes =
      List.wrap(content)
      |> Enum.with_index(1)
      |> Enum.map(fn
        {%{"number" => number, "text" => text}, _index} -> {number, to_text(text)}
        {text, index} -> {index, to_text(text)}
      end)

    {:ok, Flow.endnotes(flow, notes, options)}
  end

  defp apply_block(flow, "bibliography", content, node, context, options, _state) do
    entries = interpolate(Map.get(node, "entries", content || []), context)
    title = Keyword.get(options, :title, "References")

    flow = Flow.heading(flow, title, level: Keyword.get(options, :level, 2))

    flow =
      entries
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.reduce(flow, fn {entry, number}, current ->
        Flow.paragraph(current, "#{number}. #{bibliography_entry(entry)}", options)
      end)

    {:ok, flow}
  end

  defp apply_block(flow, "annotation", content, node, _context, options, _state) do
    type = annotation_type(Map.get(node, "annotation_type"))
    annotation_options = Keyword.put(options, :contents, to_text(content || ""))

    custom_options = [height: Keyword.get(options, :height, 0)]

    renderer = fn page, _context ->
      case type do
        :note -> PaperForge.Page.note(page, to_text(content || ""), options)
        :highlight -> PaperForge.Page.highlight(page, to_text(content || ""), options)
        _ -> PaperForge.Page.annotation(page, type, annotation_options)
      end
    end

    {:ok, Flow.custom(flow, renderer, custom_options)}
  end

  defp apply_block(flow, "chart", content, _node, _context, options, _state),
    do: {:ok, Flow.chart(flow, chart_series(content), options)}

  defp apply_block(flow, "qr_code", content, _node, _context, options, _state),
    do: {:ok, Flow.qr_code(flow, to_text(content), options)}

  defp apply_block(flow, "barcode", content, _node, _context, options, _state),
    do: {:ok, Flow.barcode(flow, to_text(content), options)}

  defp apply_block(flow, "list", content, _node, _context, options, _state),
    do: {:ok, Flow.list(flow, List.wrap(content), options)}

  defp apply_block(flow, "spacer", content, _node, _context, options, _state),
    do: {:ok, Flow.spacer(flow, content || 0, options)}

  defp apply_block(flow, "separator", _content, _node, _context, options, _state),
    do: {:ok, Flow.separator(flow, options)}

  defp apply_block(flow, "page_break", _content, _node, _context, _options, _state),
    do: {:ok, Flow.page_break(flow)}

  defp apply_block(flow, "table_of_contents", _content, _node, _context, options, _state),
    do: {:ok, Flow.table_of_contents(flow, options)}

  defp apply_block(flow, "reference", content, _node, _context, options, _state),
    do: {:ok, Flow.reference(flow, to_text(content), options)}

  defp apply_block(flow, "table", _content, node, context, options, state) do
    columns = interpolate(Map.get(node, "columns", []), context)
    rows = interpolate(Map.get(node, "rows", []), context)
    minimum = Map.get(node, "min_rows", 0)

    maximum =
      min(Map.get(node, "max_rows", state.limits.max_table_rows), state.limits.max_table_rows)

    cond do
      not is_list(rows) ->
        {:error, error(:invalid_table_rows, "$.blocks.rows", "table rows must resolve to a list")}

      length(rows) < minimum ->
        {:error, error(:table_row_minimum, "$.blocks.rows", "table has fewer than min_rows")}

      length(rows) > maximum ->
        {:error, error(:table_row_limit, "$.blocks.rows", "table row limit exceeded")}

      true ->
        {:ok, Flow.table(flow, columns, rows, options)}
    end
  end

  defp apply_block(flow, "grid", _content, node, context, options, _state) do
    columns = Map.get(node, "columns", 1)
    cells = interpolate(Map.get(node, "cells", []), context)
    {:ok, Flow.grid(flow, columns, cells, options)}
  end

  defp apply_block(flow, "columns", _content, node, context, options, _state) do
    count = Map.get(node, "count", 2)
    paragraphs = interpolate(Map.get(node, "paragraphs", []), context)
    {:ok, Flow.columns(flow, count, paragraphs, options)}
  end

  defp apply_block(_flow, type, _content, _node, _context, _options, _state),
    do:
      {:error,
       error(:unsupported_block, "$.blocks.type", "unsupported block type #{inspect(type)}")}

  defp append_flow(flow, imported), do: %{flow | blocks: imported.blocks ++ flow.blocks}

  defp math_ast(%{"symbol" => value}), do: Math.symbol(value)
  defp math_ast(%{"row" => items}) when is_list(items), do: Math.row(Enum.map(items, &math_ast/1))

  defp math_ast(%{"fraction" => %{"numerator" => numerator, "denominator" => denominator}}),
    do: Math.fraction(math_ast(numerator), math_ast(denominator))

  defp math_ast(%{"root" => value} = root),
    do: Math.root(math_ast(value), optional_math_ast(root["index"]))

  defp math_ast(%{"matrix" => rows}) when is_list(rows),
    do: Math.matrix(Enum.map(rows, fn row -> Enum.map(row, &math_ast/1) end))

  defp math_ast(%{"superscript" => %{"base" => base, "value" => value}}),
    do: Math.superscript(math_ast(base), math_ast(value))

  defp math_ast(%{"subscript" => %{"base" => base, "value" => value}}),
    do: Math.subscript(math_ast(base), math_ast(value))

  defp math_ast(%{"integral" => integral}) do
    Math.integral(
      optional_math_ast(integral["lower"]),
      optional_math_ast(integral["upper"]),
      math_ast(Map.fetch!(integral, "body")),
      Map.get(integral, "variable", "x")
    )
  end

  defp math_ast(value) when is_binary(value) or is_number(value), do: Math.symbol(value)

  defp math_ast(other),
    do: raise(ArgumentError, "invalid declarative math AST: #{inspect(other)}")

  defp optional_math_ast(nil), do: nil
  defp optional_math_ast(value), do: math_ast(value)

  defp bibliography_entry(entry) when is_binary(entry), do: entry

  defp bibliography_entry(entry) when is_map(entry) do
    [entry["author"], entry["title"], entry["publisher"], entry["year"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(". ", &to_text/1)
  end

  defp bibliography_entry(entry), do: to_text(entry)

  defp annotation_type(value) do
    case to_string(value) do
      "note" -> :note
      "highlight" -> :highlight
      "underline" -> :underline
      "strikeout" -> :strikeout
      "stamp" -> :stamp
      "free_text" -> :free_text
      "square" -> :square
      "circle" -> :circle
      "ink" -> :ink
      "file_attachment" -> :file_attachment
      other -> raise ArgumentError, "unsupported annotation type #{inspect(other)}"
    end
  end

  defp compile_forms(forms) when is_list(forms), do: Enum.map(forms, &compile_form/1)

  defp compile_form(%{"type" => "radio", "name" => name, "choices" => choices} = form) do
    %{
      type: :radio,
      name: name,
      value: form["value"],
      options: compile_form_options(form),
      choices:
        Enum.map(choices, fn choice ->
          [page: choice["page"], rect: choice["rect"], value: to_text(choice["value"])]
        end)
    }
  end

  defp compile_form(%{"type" => type, "name" => name, "page" => page, "rect" => rect} = form) do
    options = Keyword.put(compile_form_options(form), :rect, rect)

    %{type: form_type(type), name: name, page: page, options: options}
  end

  defp compile_form_options(form) do
    [
      value: form["value"],
      origin: form_origin(form["origin"]),
      default: form["default"],
      tooltip: form["tooltip"],
      options: form["options"],
      calculation: compile_calculation(form["calculation"]),
      background_color: form["background_color"],
      border_color: form["border_color"],
      border_width: form["border_width"],
      border_radius: form["border_radius"],
      check_color: form["check_color"],
      check_width: form["check_width"]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp compile_calculation(nil), do: nil

  defp compile_calculation(%{"operation" => operation, "fields" => fields})
       when operation in ["sum", "product", "average"] and is_list(fields),
       do: {String.to_existing_atom(operation), Enum.map(fields, &to_text/1)}

  defp compile_calculation(other),
    do: raise(ArgumentError, "invalid AcroForm calculation #{inspect(other)}")

  defp form_origin(nil), do: nil
  defp form_origin("bottom_left"), do: :bottom_left
  defp form_origin("top_left"), do: :top_left

  defp form_type("text"), do: :text
  defp form_type("checkbox"), do: :checkbox
  defp form_type("button"), do: :button
  defp form_type("list"), do: :list
  defp form_type("combo"), do: :combo
  defp form_type("signature"), do: :signature

  defp apply_forms(document, forms) do
    Enum.reduce(forms, document, fn
      %{type: :radio, name: name, choices: choices, value: value, options: options}, current ->
        AcroForm.add_radio_group(current, name, choices, Keyword.put(options, :value, value))

      %{type: type, name: name, page: page, options: options}, current ->
        AcroForm.add_field(current, page, type, name, options)
    end)
  end

  defp parse_loop(%{"each" => each, "as" => binding}) when is_binary(each) and is_binary(binding),
    do: {:ok, each, binding}

  defp parse_loop(expression) when is_binary(expression) do
    case Regex.run(~r/^([A-Za-z_][\w.]*)\s+in\s+([A-Za-z_][\w.]*)$/, expression) do
      [_, binding, path] -> {:ok, path, binding}
      _ -> :error
    end
  end

  defp parse_loop(_loop), do: :error

  defp interpolate(value, context) when is_binary(value) do
    case Regex.run(~r/^\{\{\s*([\w.]+)\s*\}\}$/, value) do
      [_, path] ->
        lookup(context, path)

      _ ->
        Regex.replace(~r/\{\{\s*([\w.]+)\s*\}\}/, value, fn _, path ->
          to_text(lookup(context, path))
        end)
    end
  end

  defp interpolate(value, context) when is_list(value),
    do: Enum.map(value, &interpolate(&1, context))

  defp interpolate(value, context) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, interpolate(item, context)} end)

  defp interpolate(value, _context), do: value

  defp lookup(context, path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(context, fn key, current ->
      if is_map(current) and Map.has_key?(current, key),
        do: {:cont, Map.get(current, key)},
        else: {:halt, nil}
    end)
  end

  defp options_to_keyword(options, tokens, font_keys \\ %{})

  defp options_to_keyword(options, tokens, font_keys) when is_map(options) do
    Enum.reduce(options, [], fn {key, value}, acc ->
      case option_key(key) do
        nil -> raise ArgumentError, "unknown declarative option #{inspect(key)}"
        atom -> [{atom, option_value(resolve_tokens(value, tokens), atom, font_keys)} | acc]
      end
    end)
  end

  defp options_to_keyword(_options, _tokens, _font_keys), do: []

  defp option_key(key) do
    key = to_string(key)
    Enum.find(@option_keys, &(Atom.to_string(&1) == key))
  end

  defp option_value(value, key, _font_keys)
       when key in [:style, :template, :extends] and is_binary(value),
       do: value

  defp option_value(value, key, font_keys)
       when key in [:font, :default_font] and is_binary(value),
       do: font_key(value, font_keys)

  defp option_value([width, height], :size, _font_keys)
       when is_number(width) and is_number(height),
       do: {width, height}

  defp option_value([x, y], :focal_point, _font_keys) when is_number(x) and is_number(y),
    do: {x, y}

  defp option_value(value, :margins, _font_keys) when is_map(value) do
    allowed = %{"top" => :top, "right" => :right, "bottom" => :bottom, "left" => :left}

    Enum.map(value, fn {key, margin} ->
      case Map.fetch(allowed, to_string(key)) do
        {:ok, side} when is_number(margin) and margin >= 0 -> {side, margin}
        {:ok, _side} -> raise ArgumentError, "margin #{key} must be a non-negative number"
        :error -> raise ArgumentError, "unknown margin side #{inspect(key)}"
      end
    end)
  end

  defp option_value("#" <> hex = color, _key, _font_keys) when byte_size(hex) in [3, 6],
    do: parse_color(color)

  defp option_value(value, _key, _font_keys) when is_binary(value) do
    Enum.find(@enum_values, value, &(Atom.to_string(&1) == value))
  end

  defp option_value(value, key, font_keys) when is_list(value),
    do: Enum.map(value, &option_value(&1, key, font_keys))

  defp option_value(value, _key, _font_keys) when is_map(value), do: stringify(value)

  defp option_value(value, _key, _font_keys), do: value

  defp parse_color("#" <> <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>>),
    do: parse_color("##{r}#{r}#{g}#{g}#{b}#{b}")

  defp parse_color("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    Color.rgb255(String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16))
  end

  defp resolve_tokens("$" <> path, tokens), do: lookup(tokens, path)

  defp resolve_tokens(value, tokens) when is_list(value),
    do: Enum.map(value, &resolve_tokens(&1, tokens))

  defp resolve_tokens(value, tokens) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, resolve_tokens(item, tokens)} end)

  defp resolve_tokens(value, _tokens), do: value

  defp compile_named_options(definitions, tokens, context) do
    Map.new(definitions, fn {name, options} ->
      {declarative_identifier(name), options_to_keyword(interpolate(options, context), tokens)}
    end)
  end

  defp declarative_font_keys(definition) do
    names = definition |> Map.get("fonts", %{}) |> Map.keys() |> Enum.sort()

    if length(names) <= length(@declarative_font_slots) do
      {:ok, Map.new(Enum.zip(names, @declarative_font_slots))}
    else
      {:error,
       error(
         :too_many_fonts,
         "$.fonts",
         "a template can register at most #{length(@declarative_font_slots)} fonts"
       )}
    end
  end

  defp font_key(name, _font_keys) when is_atom(name), do: name

  defp font_key(name, font_keys) when is_binary(name) do
    Map.get(font_keys, name) || existing_atom(name) ||
      raise(ArgumentError, "unknown declarative font #{inspect(name)}")
  end

  defp existing_atom(value) when is_atom(value), do: value

  defp existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp declarative_identifier(value) when is_atom(value), do: value

  defp declarative_identifier(value) when is_binary(value),
    do: existing_atom(value) || value

  defp register_styles(document, styles),
    do:
      Enum.reduce(styles, document, fn {name, opts}, doc -> PaperForge.style(doc, name, opts) end)

  defp register_templates(document, templates),
    do:
      Enum.reduce(templates, document, fn {name, opts}, doc ->
        PaperForge.page_template(doc, name, opts)
      end)

  defp register_metadata(document, metadata) when map_size(metadata) == 0, do: document

  defp register_metadata(document, metadata),
    do:
      PaperForge.metadata(
        document,
        Enum.map(metadata, fn {key, value} -> {metadata_key(key), value} end)
      )

  defp compile_security(options) when is_map(options) do
    allowed = ~w(algorithm encrypt_metadata permissions user_password owner_password)
    ensure_known_keys!(options, allowed, "security")

    permissions =
      options
      |> Map.get("permissions", %{})
      |> keyword_map(~w(print copy modify extract), "security.permissions")
      |> Enum.map(fn
        {:print, value} when value in ["none", "low_resolution", "high_resolution"] ->
          {:print,
           enum_atom(value, ~w(none low_resolution high_resolution), "security.permissions.print")}

        pair ->
          pair
      end)

    []
    |> maybe_put(:algorithm, enum_atom(options["algorithm"], ~w(aes_256), "security.algorithm"))
    |> maybe_put(:encrypt_metadata, options["encrypt_metadata"])
    |> maybe_put(:user_password, options["user_password"])
    |> maybe_put(:owner_password, options["owner_password"])
    |> maybe_put(:permissions, permissions, permissions != [])
  end

  defp compile_security(_), do: raise(ArgumentError, "security must be an object")

  defp compile_signature(options) when is_map(options) do
    allowed = ~w(algorithm reason location contact_info timestamp tsa_url visible multiple)
    ensure_known_keys!(options, allowed, "signature")

    []
    |> maybe_put(:alg, signature_algorithm(options["algorithm"]))
    |> maybe_put(:reason, options["reason"])
    |> maybe_put(:location, options["location"])
    |> maybe_put(:contact_info, options["contact_info"])
    |> maybe_put(:tsa_url, options["tsa_url"])
    |> maybe_put(:timestamp, options["timestamp"])
    |> maybe_put(:visible, options["visible"])
    |> maybe_put(:multiple, options["multiple"])
  end

  defp compile_signature(_), do: raise(ArgumentError, "signature must be an object")

  defp signature_algorithm(nil), do: nil
  defp signature_algorithm("ps256"), do: :PS256
  defp signature_algorithm("rs256"), do: :RS256

  defp signature_algorithm(value),
    do: raise(ArgumentError, "unsupported signature.algorithm value: #{inspect(value)}")

  defp compile_protection(options) when is_map(options) do
    allowed = ~w(identifier modified_at watermark policy)
    ensure_known_keys!(options, allowed, "protection")

    watermark =
      case options["watermark"] do
        nil ->
          nil

        text when is_binary(text) ->
          text

        map when is_map(map) ->
          ensure_known_keys!(map, ~w(text opacity size color angle), "protection.watermark")

          map
          |> keyword_map(~w(text opacity size color angle), "protection.watermark")
          |> Enum.map(fn
            {:color, "#" <> _ = color} -> {:color, parse_color_tuple(color)}
            pair -> pair
          end)

        _ ->
          raise ArgumentError, "protection.watermark must be text or an object"
      end

    policy =
      case options["policy"] do
        nil ->
          []

        map when is_map(map) ->
          keyword_map(
            map,
            ~w(allowed_uri_schemes allowed_hosts allow_attachments max_attachments max_attachment_bytes allowed_attachment_mimes),
            "protection.policy"
          )

        _ ->
          raise ArgumentError, "protection.policy must be an object"
      end

    []
    |> maybe_put(:identifier, options["identifier"])
    |> maybe_put(:modified_at, options["modified_at"])
    |> maybe_put(:watermark, watermark)
    |> maybe_put(:policy, policy, policy != [])
  end

  defp compile_protection(_), do: raise(ArgumentError, "protection must be an object")

  defp compile_compliance(options) when is_map(options) do
    allowed = ~w(profiles language title icc_profile output_condition)
    ensure_known_keys!(options, allowed, "compliance")

    profiles =
      Enum.map(Map.get(options, "profiles", []), fn profile ->
        enum_atom(profile, ~w(pdf_a_2b pdf_a_3b pdf_ua_1), "compliance.profiles")
      end)

    []
    |> maybe_put(:profiles, profiles, profiles != [])
    |> maybe_put(:language, options["language"])
    |> maybe_put(:title, options["title"])
    |> maybe_put(:icc_profile, options["icc_profile"])
    |> maybe_put(:output_condition, options["output_condition"])
  end

  defp compile_compliance(_), do: raise(ArgumentError, "compliance must be an object")

  defp maybe_comply(document, []), do: document
  defp maybe_comply(document, options), do: PaperForge.comply(document, options)
  defp maybe_protect(document, []), do: document
  defp maybe_protect(document, options), do: PaperForge.protect(document, options)

  defp merge_security([], []), do: []
  defp merge_security(policy, secrets) when is_list(secrets), do: Keyword.merge(policy, secrets)

  defp merge_security(_policy, other),
    do:
      raise(
        ArgumentError,
        "security write options must be a keyword list, got: #{inspect(other)}"
      )

  defp merge_signature([], []), do: []
  defp merge_signature(policy, runtime) when is_list(runtime), do: Keyword.merge(policy, runtime)

  defp merge_signature(_policy, other),
    do:
      raise(
        ArgumentError,
        "signature write options must be a keyword list, got: #{inspect(other)}"
      )

  defp write_document(document, path, security, []) do
    PaperForge.write(document, path, security_options(security))
  end

  defp write_document(document, path, security, signature) do
    with pdf <- PaperForge.to_binary(document, security_options(security)),
         {:ok, signed} <- PaperForge.Signature.sign(pdf, signature) do
      File.write(path, signed)
    end
  end

  defp security_options([]), do: []
  defp security_options(security), do: [security: security]

  defp keyword_map(map, allowed, path) when is_map(map) do
    ensure_known_keys!(map, allowed, path)
    Enum.map(map, fn {key, value} -> {existing_atom(to_string(key)), value} end)
  end

  defp ensure_known_keys!(map, allowed, path) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown #{path} properties: #{Enum.join(unknown, ", ")}"
    end
  end

  defp enum_atom(nil, _allowed, _path), do: nil

  defp enum_atom(value, allowed, path) do
    if value in allowed,
      # `value` is constrained by a small, compile-time allowlist. This is safe
      # while still allowing public enum atoms that are not otherwise loaded.
      do: String.to_atom(value),
      else: raise(ArgumentError, "unsupported #{path} value: #{inspect(value)}")
  end

  defp metadata_key(key) do
    case Map.fetch(@metadata_keys, to_string(key)) do
      {:ok, metadata_key} -> metadata_key
      :error -> raise ArgumentError, "unsupported metadata key #{inspect(key)}"
    end
  end

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
  defp maybe_put(options, key, value, true), do: Keyword.put(options, key, value)
  defp maybe_put(options, _key, _value, false), do: options

  defp parse_color_tuple("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    {String.to_integer(r, 16) / 255, String.to_integer(g, 16) / 255,
     String.to_integer(b, 16) / 255}
  end

  defp parse_color_tuple(value),
    do: raise(ArgumentError, "watermark color must be #RRGGBB, got: #{inspect(value)}")

  defp rich_runs(runs) when is_list(runs) do
    Enum.map(runs, fn
      %{"text" => text, "options" => options} ->
        {to_text(text), options_to_keyword(options, %{})}

      %{"text" => text} ->
        to_text(text)

      text ->
        to_text(text)
    end)
  end

  defp rich_runs(value), do: [to_text(value)]

  defp chart_series(series) when is_list(series) do
    Enum.map(series, fn
      [label, value] -> {to_text(label), value}
      %{"label" => label, "value" => value} -> {to_text(label), value}
    end)
  end

  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value), do: to_string(value)

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, a, b ->
      if is_map(a) and is_map(b), do: deep_merge(a, b), else: b
    end)
  end

  defp stringify(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify(item)} end)

  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value

  defp error(code, path, message, details \\ nil), do: Error.new(code, path, message, details)
end

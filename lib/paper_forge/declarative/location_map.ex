defmodule PaperForge.Declarative.LocationMap do
  @moduledoc false

  defstruct rest: "", line: 1, column: 1, locations: %{}, source: nil

  @spec build(binary(), binary() | nil) :: map()
  def build(json, source \\ nil) when is_binary(json) do
    state = %__MODULE__{rest: json, source: source}

    case value(skip_space(state), "$") do
      {:ok, parsed} -> parsed.locations
      :error -> %{}
    end
  end

  defp value(%{rest: ""}, _path), do: :error

  defp value(state, path) do
    state = put_location(state, path)

    case state.rest do
      <<"{", _::binary>> -> object(advance(state), path)
      <<"[", _::binary>> -> array(advance(state), path, 0)
      <<"\"", _::binary>> -> string(state) |> then_result()
      _ -> scalar(state)
    end
  end

  defp object(state, path) do
    state = skip_space(state)

    case state.rest do
      <<"}", _::binary>> -> {:ok, advance(state)}
      _ -> object_entry(state, path)
    end
  end

  defp object_entry(state, path) do
    key_line = state.line
    key_column = state.column

    with {:ok, key, state} <- string(state),
         state <- skip_space(state),
         <<":", _::binary>> <- state.rest,
         state <- state |> advance() |> skip_space(),
         child_path <- child_path(path, key),
         state <- put_location(state, child_path, key_line, key_column),
         {:ok, state} <- value(state, child_path) do
      state = skip_space(state)

      case state.rest do
        <<",", _::binary>> -> object_entry(state |> advance() |> skip_space(), path)
        <<"}", _::binary>> -> {:ok, advance(state)}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp array(state, path, index) do
    state = skip_space(state)

    case state.rest do
      <<"]", _::binary>> ->
        {:ok, advance(state)}

      _ ->
        child_path = "#{path}[#{index}]"

        with {:ok, state} <- value(state, child_path) do
          state = skip_space(state)

          case state.rest do
            <<",", _::binary>> -> array(state |> advance() |> skip_space(), path, index + 1)
            <<"]", _::binary>> -> {:ok, advance(state)}
            _ -> :error
          end
        end
    end
  end

  defp string(%{rest: <<"\"", _::binary>>} = state) do
    scan_string(advance(state), "")
  end

  defp string(_state), do: :error

  defp scan_string(%{rest: ""}, _raw), do: :error

  defp scan_string(%{rest: <<"\"", _::binary>>} = state, raw) do
    case Jason.decode("\"#{raw}\"") do
      {:ok, decoded} -> {:ok, decoded, advance(state)}
      _ -> :error
    end
  end

  defp scan_string(%{rest: <<"\\", _::binary>>} = state, raw) do
    escaped = advance(state)

    case String.next_codepoint(escaped.rest) do
      {codepoint, _rest} -> scan_string(advance(escaped), raw <> "\\" <> codepoint)
      nil -> :error
    end
  end

  defp scan_string(state, raw) do
    case String.next_codepoint(state.rest) do
      {codepoint, _rest} -> scan_string(advance(state), raw <> codepoint)
      nil -> :error
    end
  end

  defp scalar(state) do
    next =
      consume_while(state, fn codepoint ->
        codepoint not in [",", "]", "}", " ", "\t", "\r", "\n"]
      end)

    if next == state, do: :error, else: {:ok, next}
  end

  defp then_result({:ok, _decoded, state}), do: {:ok, state}
  defp then_result(_), do: :error

  defp skip_space(state), do: consume_while(state, &(&1 in [" ", "\t", "\r", "\n"]))

  defp consume_while(state, predicate) do
    case String.next_codepoint(state.rest) do
      {codepoint, _rest} ->
        if predicate.(codepoint), do: consume_while(advance(state), predicate), else: state

      nil ->
        state
    end
  end

  defp advance(state) do
    case String.next_codepoint(state.rest) do
      {"\n", rest} -> %{state | rest: rest, line: state.line + 1, column: 1}
      {_codepoint, rest} -> %{state | rest: rest, column: state.column + 1}
      nil -> state
    end
  end

  defp put_location(state, path),
    do: put_location(state, path, state.line, state.column)

  defp put_location(state, path, line, column) do
    location = %{source: state.source, line: line, column: column}
    %{state | locations: Map.put_new(state.locations, path, location)}
  end

  defp child_path("$", key), do: "$.#{key}"
  defp child_path(path, key), do: "#{path}.#{key}"
end

defmodule PaperForge.PageSize do
  @moduledoc """
  Standard PDF page dimensions expressed in points.
  """

  @sizes %{
    a4: {595.28, 841.89},
    a3: {841.89, 1190.55},
    a5: {419.53, 595.28},
    letter: {612, 792},
    legal: {612, 1008}
  }

  @type size_name :: :a3 | :a4 | :a5 | :letter | :legal

  @spec resolve(size_name() | {number(), number()}) :: {number(), number()}
  def resolve({width, height})
      when is_number(width) and width > 0 and
             is_number(height) and height > 0 do
    {width, height}
  end

  def resolve(name) when is_atom(name) do
    case Map.fetch(@sizes, name) do
      {:ok, dimensions} ->
        dimensions

      :error ->
        raise ArgumentError, "unsupported page size: #{inspect(name)}"
    end
  end

  def resolve(value) do
    raise ArgumentError, "invalid page size: #{inspect(value)}"
  end
end

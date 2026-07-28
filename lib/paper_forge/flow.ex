defmodule PaperForge.Flow do
  @moduledoc """
  Builder for unified document layout blocks.
  """

  alias PaperForge.Layout.Block

  defstruct blocks: []

  @type t :: %__MODULE__{blocks: [Block.t()]}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec heading(t(), binary(), keyword()) :: t()
  def heading(%__MODULE__{} = flow, text, options \\ []) when is_binary(text) do
    put_block(flow, Block.new(:heading, text, Keyword.put_new(options, :level, 1)))
  end

  @spec paragraph(t(), binary(), keyword()) :: t()
  def paragraph(%__MODULE__{} = flow, text, options \\ []) when is_binary(text) do
    put_block(flow, Block.new(:paragraph, text, options))
  end

  @spec image(t(), binary(), keyword()) :: t()
  def image(%__MODULE__{} = flow, source, options \\ []) when is_binary(source) do
    put_block(flow, Block.new(:image, source, options))
  end

  @spec table(t(), [term()], [[term()]], keyword()) :: t()
  def table(%__MODULE__{} = flow, columns, rows, options \\ [])
      when is_list(columns) and is_list(rows) do
    put_block(flow, Block.new(:table, %{columns: columns, rows: rows}, options))
  end

  @spec list(t(), [term()], keyword()) :: t()
  def list(%__MODULE__{} = flow, items, options \\ []) when is_list(items) do
    put_block(flow, Block.new(:list, items, options))
  end

  @spec spacer(t(), number(), keyword()) :: t()
  def spacer(%__MODULE__{} = flow, height, options \\ [])
      when is_number(height) and height >= 0 do
    put_block(flow, Block.new(:spacer, height, options))
  end

  @spec separator(t(), keyword()) :: t()
  def separator(%__MODULE__{} = flow, options \\ []) do
    put_block(flow, Block.new(:separator, nil, options))
  end

  @spec page_break(t()) :: t()
  def page_break(%__MODULE__{} = flow) do
    put_block(flow, Block.new(:page_break, nil, []))
  end

  @spec keep_together(t(), (t() -> t()) | Block.t()) :: t()
  def keep_together(%__MODULE__{} = flow, %Block{} = block) do
    put_block(flow, %{block | options: Keyword.put(block.options, :keep_together, true)})
  end

  def keep_together(%__MODULE__{} = flow, fun) when is_function(fun, 1) do
    nested_flow =
      __MODULE__.new()
      |> fun.()

    put_block(
      flow,
      Block.new(:container, nil,
        keep_together: true,
        children: Enum.reverse(nested_flow.blocks)
      )
    )
  end

  @spec custom(
          t(),
          (PaperForge.Page.t(), PaperForge.PageContext.t() -> PaperForge.Page.t()),
          keyword()
        ) :: t()
  def custom(%__MODULE__{} = flow, fun, options \\ []) when is_function(fun, 2) do
    put_block(flow, Block.new(:custom, fun, options))
  end

  @spec section(t(), atom(), keyword(), (t() -> t())) :: t()
  def section(%__MODULE__{} = flow, section_id, options, fun)
      when is_atom(section_id) and is_list(options) and is_function(fun, 1) do
    nested_flow =
      __MODULE__.new()
      |> fun.()

    block =
      Block.new(:section, section_id,
        children: Enum.reverse(nested_flow.blocks),
        title: Keyword.get(options, :title),
        page_break_before: Keyword.get(options, :page_break_before, false),
        page_break_after: Keyword.get(options, :page_break_after, false),
        page_options: Keyword.get(options, :page_options, []),
        template: Keyword.get(options, :template),
        header: Keyword.get(options, :header),
        footer: Keyword.get(options, :footer)
      )

    put_block(flow, block)
  end

  defp put_block(%__MODULE__{} = flow, %Block{} = block) do
    %{flow | blocks: [block | flow.blocks]}
  end
end

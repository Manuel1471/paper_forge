defmodule PaperForge.Declarative.Error do
  @moduledoc "Structured error returned while parsing, validating, or compiling a template."

  defexception [:message, :path, :code, :details, :source, :line, :column]

  @type t :: %__MODULE__{
          message: binary(),
          path: binary(),
          code: atom(),
          details: term(),
          source: binary() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil
        }

  @spec new(atom(), binary(), binary(), term()) :: t()
  def new(code, path, message, details \\ nil) do
    new(code, path, message, details, [])
  end

  @spec new(atom(), binary(), binary(), term(), keyword()) :: t()
  def new(code, path, message, details, options) do
    %__MODULE__{
      code: code,
      path: path,
      message: message,
      details: details,
      source: Keyword.get(options, :source),
      line: Keyword.get(options, :line),
      column: Keyword.get(options, :column)
    }
  end
end

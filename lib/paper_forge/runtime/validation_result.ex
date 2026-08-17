defmodule PaperForge.ValidationResult do
  @moduledoc """
  Structured outcome returned by `PaperForge.validate/1`.

  Errors prevent serialization. Warnings describe valid documents that may
  deserve attention before they are sent to production.
  """

  @enforce_keys [:valid?, :errors, :warnings]
  defstruct [:valid?, :errors, :warnings, :objects, :pages, :pdf_version, deterministic?: true]

  @type t :: %__MODULE__{
          valid?: boolean(),
          errors: [map()],
          warnings: [map()],
          objects: non_neg_integer(),
          pages: non_neg_integer(),
          pdf_version: binary(),
          deterministic?: boolean()
        }
end

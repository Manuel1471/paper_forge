defmodule PaperForge.Declarative.Compiled do
  @moduledoc "Validated Layout IR produced from a `.paperforge` template."

  alias PaperForge.Flow

  defstruct flow: nil,
            template_id: nil,
            template_hash: nil,
            document_options: [],
            layout_options: [],
            styles: %{},
            page_templates: %{},
            metadata: %{},
            forms: [],
            security: [],
            signature: [],
            protection: [],
            compliance: []

  @type t :: %__MODULE__{
          flow: Flow.t(),
          template_id: binary(),
          template_hash: binary(),
          document_options: keyword(),
          layout_options: keyword(),
          styles: %{optional(atom()) => keyword()},
          page_templates: %{optional(atom()) => keyword()},
          metadata: map(),
          forms: [map()],
          security: keyword(),
          signature: keyword(),
          protection: keyword(),
          compliance: keyword()
        }
end

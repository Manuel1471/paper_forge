defmodule PaperForge.RenderStats do
  @moduledoc """
  Stable render measurements returned by `PaperForge.render/2`.

  Timing fields are microseconds. Memory is the current render process memory
  at the beginning and end of serialization, not VM-wide peak memory.
  """

  @enforce_keys [:pages, :objects, :duration_us, :serialization_us, :output_bytes]
  defstruct [
    :pages,
    :objects,
    :fonts,
    :embedded_fonts,
    :images,
    :forms,
    :links,
    :bookmarks,
    :resources,
    :duration_us,
    :layout_us,
    :serialization_us,
    :write_us,
    :memory_before_bytes,
    :memory_after_bytes,
    :memory_delta_bytes,
    :reductions,
    :gc_count,
    :cache,
    :output_bytes,
    :fingerprint
  ]

  @type t :: %__MODULE__{
          pages: non_neg_integer(),
          objects: non_neg_integer(),
          fonts: non_neg_integer(),
          embedded_fonts: non_neg_integer(),
          images: non_neg_integer(),
          forms: non_neg_integer(),
          links: non_neg_integer(),
          bookmarks: non_neg_integer(),
          resources: map(),
          duration_us: non_neg_integer(),
          layout_us: non_neg_integer(),
          serialization_us: non_neg_integer(),
          write_us: non_neg_integer(),
          memory_before_bytes: non_neg_integer(),
          memory_after_bytes: non_neg_integer(),
          memory_delta_bytes: integer(),
          reductions: non_neg_integer(),
          gc_count: non_neg_integer(),
          cache: map(),
          output_bytes: non_neg_integer(),
          fingerprint: binary()
        }
end

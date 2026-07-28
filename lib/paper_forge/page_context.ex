defmodule PaperForge.PageContext do
  @moduledoc """
  Context passed to layout headers, footers, and custom flow blocks.
  """

  defstruct [
    :page_number,
    :total_pages,
    :page_width,
    :page_height,
    :content_left,
    :content_top,
    :content_right,
    :content_bottom,
    :content_width,
    :content_height,
    :section,
    :current_heading
  ]

  @type t :: %__MODULE__{
          page_number: pos_integer(),
          total_pages: pos_integer(),
          page_width: number(),
          page_height: number(),
          content_left: number(),
          content_top: number(),
          content_right: number(),
          content_bottom: number(),
          content_width: number(),
          content_height: number(),
          section: atom() | nil,
          current_heading: binary() | nil
        }
end

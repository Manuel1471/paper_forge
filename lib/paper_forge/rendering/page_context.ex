defmodule PaperForge.PageContext do
  @moduledoc """
  Context passed to layout headers, footers, and custom flow blocks.
  """

  defstruct [
    :page_number,
    :total_pages,
    :section_page_number,
    :section_total_pages,
    :page_width,
    :page_height,
    :content_left,
    :content_top,
    :content_right,
    :content_bottom,
    :content_width,
    :content_height,
    :section,
    :current_heading,
    :block_x,
    :block_y,
    :block_width,
    :block_height
  ]

  @type t :: %__MODULE__{
          page_number: pos_integer(),
          total_pages: pos_integer(),
          section_page_number: pos_integer(),
          section_total_pages: pos_integer(),
          page_width: number(),
          page_height: number(),
          content_left: number(),
          content_top: number(),
          content_right: number(),
          content_bottom: number(),
          content_width: number(),
          content_height: number(),
          section: atom() | nil,
          current_heading: binary() | nil,
          block_x: number() | nil,
          block_y: number() | nil,
          block_width: number() | nil,
          block_height: number() | nil
        }
end

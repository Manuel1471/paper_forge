defmodule PaperForge.Document do
  @moduledoc """
  Internal object graph of a PDF document.

  A new document automatically contains:

  - the root page tree;
  - the document catalog;
  - a default Helvetica font.
  """

  alias PaperForge.Metadata
  alias PaperForge.Object
  alias PaperForge.Reference

  @pages_object_id 1
  @catalog_object_id 2
  @default_font_object_id 3

  defstruct objects: %{},
            next_object_id: 4,
            root: nil,
            pages: nil,
            default_font: nil,
            info: nil

  @type t :: %__MODULE__{
          objects: %{optional(pos_integer()) => Object.t()},
          next_object_id: pos_integer(),
          root: Reference.t(),
          pages: Reference.t(),
          default_font: Reference.t(),
          info: Reference.t() | nil
        }

  @spec new() :: t()
  def new do
    pages_reference =
      Reference.new(@pages_object_id)

    catalog_reference =
      Reference.new(@catalog_object_id)

    font_reference =
      Reference.new(@default_font_object_id)

    pages_object =
      Object.new(
        @pages_object_id,
        %{
          "Type" => {:name, "Pages"},
          "Kids" => [],
          "Count" => 0
        }
      )

    catalog_object =
      Object.new(
        @catalog_object_id,
        %{
          "Type" => {:name, "Catalog"},
          "Pages" => pages_reference
        }
      )

    font_object =
      Object.new(
        @default_font_object_id,
        %{
          "Type" => {:name, "Font"},
          "Subtype" => {:name, "Type1"},
          "BaseFont" => {:name, "Helvetica"},
          "Encoding" => {:name, "WinAnsiEncoding"}
        }
      )

    %__MODULE__{
      objects: %{
        @pages_object_id => pages_object,
        @catalog_object_id => catalog_object,
        @default_font_object_id => font_object
      },
      next_object_id: 4,
      root: catalog_reference,
      pages: pages_reference,
      default_font: font_reference,
      info: nil
    }
  end

  @doc """
  Adds a new indirect object to the document.

  Returns the updated document and a reference to the object.
  """
  @spec add_object(t(), term()) ::
          {t(), Reference.t()}
  def add_object(%__MODULE__{} = document, value) do
    object_id = document.next_object_id

    object =
      Object.new(
        object_id,
        value
      )

    reference =
      Reference.new(object_id)

    updated_document = %{
      document
      | objects:
          Map.put(
            document.objects,
            object_id,
            object
          ),
        next_object_id: object_id + 1
    }

    {updated_document, reference}
  end

  @doc """
  Updates the value of an existing indirect object.
  """
  @spec update_object(
          t(),
          Reference.t(),
          (term() -> term())
        ) :: t()
  def update_object(
        %__MODULE__{} = document,
        %Reference{object_id: object_id},
        function
      )
      when is_function(function, 1) do
    object =
      Map.fetch!(
        document.objects,
        object_id
      )

    updated_object = %{
      object
      | value: function.(object.value)
    }

    updated_objects =
      Map.put(
        document.objects,
        object_id,
        updated_object
      )

    %{document | objects: updated_objects}
  end

  @doc """
  Adds a page reference to the document page tree.
  """
  @spec append_page(t(), Reference.t()) :: t()
  def append_page(
        %__MODULE__{} = document,
        %Reference{} = page_reference
      ) do
    update_object(
      document,
      document.pages,
      fn pages_dictionary ->
        kids =
          Map.fetch!(
            pages_dictionary,
            "Kids"
          )

        count =
          Map.fetch!(
            pages_dictionary,
            "Count"
          )

        pages_dictionary
        |> Map.put(
          "Kids",
          kids ++ [page_reference]
        )
        |> Map.put(
          "Count",
          count + 1
        )
      end
    )
  end

  @doc """
  Adds document metadata.

  Calling this function more than once replaces the active metadata
  reference, although previous objects remain in the object graph.
  """
  @spec put_metadata(t(), Metadata.t()) :: t()
  def put_metadata(
        %__MODULE__{} = document,
        %Metadata{} = metadata
      ) do
    dictionary =
      Metadata.to_dictionary(metadata)

    {document, info_reference} =
      add_object(
        document,
        dictionary
      )

    %{document | info: info_reference}
  end

  @doc """
  Returns all indirect objects sorted by their object ID.
  """
  @spec objects(t()) :: [Object.t()]
  def objects(%__MODULE__{} = document) do
    document.objects
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end
end

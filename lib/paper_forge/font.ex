defmodule PaperForge.Font do
  @moduledoc """
  Represents a standard PDF font registered inside a document.
  """

  alias PaperForge.Reference

  @enforce_keys [
    :key,
    :base_font,
    :family,
    :style,
    :encoding,
    :resource_name,
    :reference
  ]

  defstruct [
    :key,
    :base_font,
    :family,
    :style,
    :encoding,
    :resource_name,
    :reference
  ]

  @type family ::
          :helvetica
          | :times
          | :courier
          | :symbol
          | :zapf_dingbats

  @type style ::
          :regular
          | :bold
          | :italic
          | :bold_italic

  @type encoding ::
          :win_ansi
          | :builtin

  @type t :: %__MODULE__{
          key: atom(),
          base_font: binary(),
          family: family(),
          style: style(),
          encoding: encoding(),
          resource_name: binary(),
          reference: Reference.t()
        }

  @doc """
  Creates a registered font from a built-in font definition.
  """
  @spec new(map(), binary(), Reference.t()) :: t()
  def new(
        definition,
        resource_name,
        %Reference{} = reference
      )
      when is_map(definition) and
             is_binary(resource_name) and
             byte_size(resource_name) > 0 do
    %__MODULE__{
      key: Map.fetch!(definition, :key),
      base_font: Map.fetch!(definition, :base_font),
      family: Map.fetch!(definition, :family),
      style: Map.fetch!(definition, :style),
      encoding: Map.fetch!(definition, :encoding),
      resource_name: resource_name,
      reference: reference
    }
  end

  @doc """
  Builds the PDF dictionary for a registered font.
  """
  @spec to_dictionary(t()) :: map()
  def to_dictionary(%__MODULE__{} = font) do
    %{
      "Type" => {:name, "Font"},
      "Subtype" => {:name, "Type1"},
      "BaseFont" => {:name, font.base_font}
    }
    |> maybe_put_encoding(font.encoding)
  end

  @doc """
  Builds the PDF dictionary directly from a built-in font definition.

  This function can be used before the font receives its indirect object
  reference and resource name.
  """
  @spec definition_to_dictionary(map()) :: map()
  def definition_to_dictionary(definition)
      when is_map(definition) do
    %{
      "Type" => {:name, "Font"},
      "Subtype" => {:name, "Type1"},
      "BaseFont" => {
        :name,
        Map.fetch!(definition, :base_font)
      }
    }
    |> maybe_put_encoding(Map.fetch!(definition, :encoding))
  end

  defp maybe_put_encoding(
         dictionary,
         :win_ansi
       ) do
    Map.put(
      dictionary,
      "Encoding",
      {:name, "WinAnsiEncoding"}
    )
  end

  defp maybe_put_encoding(
         dictionary,
         :builtin
       ) do
    dictionary
  end
end

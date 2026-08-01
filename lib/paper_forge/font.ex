defmodule PaperForge.Font do
  @moduledoc """
  Represents a PDF font registered inside a document.
  """

  alias PaperForge.Reference

  @enforce_keys [
    :key,
    :base_font,
    :family,
    :style,
    :encoding,
    :kind,
    :resource_name,
    :reference,
    :unicode_to_gid,
    :widths,
    :units_per_em,
    :number_of_glyphs,
    :cid_font_reference,
    :to_unicode_reference,
    :used_glyphs,
    :metrics_id
  ]

  defstruct [
    :key,
    :base_font,
    :family,
    :style,
    :encoding,
    :kind,
    :resource_name,
    :reference,
    :unicode_to_gid,
    :widths,
    :units_per_em,
    :number_of_glyphs,
    :cid_font_reference,
    :to_unicode_reference,
    :used_glyphs,
    :metrics_id
  ]

  @type family ::
          :helvetica
          | :times
          | :courier
          | :symbol
          | :zapf_dingbats
          | :truetype

  @type style ::
          :regular
          | :bold
          | :italic
          | :bold_italic

  @type encoding ::
          :win_ansi
          | :builtin
          | :identity_h

  @type kind ::
          :builtin
          | :truetype

  @type t :: %__MODULE__{
          key: atom(),
          base_font: binary(),
          family: family(),
          style: style(),
          encoding: encoding(),
          kind: kind(),
          resource_name: binary(),
          reference: Reference.t(),
          unicode_to_gid: map() | nil,
          widths: map() | nil,
          units_per_em: pos_integer() | nil,
          number_of_glyphs: non_neg_integer() | nil,
          cid_font_reference: Reference.t() | nil,
          to_unicode_reference: Reference.t() | nil,
          used_glyphs: MapSet.t(non_neg_integer()) | nil,
          metrics_id: term()
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
      kind: :builtin,
      resource_name: resource_name,
      reference: reference,
      unicode_to_gid: nil,
      widths: nil,
      units_per_em: nil,
      number_of_glyphs: nil,
      cid_font_reference: nil,
      to_unicode_reference: nil,
      used_glyphs: nil,
      metrics_id: {:builtin, Map.fetch!(definition, :key)}
    }
  end

  @doc """
  Creates a registered TrueType font.
  """
  @spec true_type(atom(), map(), binary(), Reference.t()) :: t()
  def true_type(
        key,
        font,
        resource_name,
        %Reference{} = reference,
        options \\ []
      )
      when is_atom(key) and
             is_map(font) and
             is_binary(resource_name) and
             byte_size(resource_name) > 0 do
    %__MODULE__{
      key: key,
      base_font: Map.fetch!(font, :postscript_name),
      family: :truetype,
      style: :regular,
      encoding: :identity_h,
      kind: :truetype,
      resource_name: resource_name,
      reference: reference,
      unicode_to_gid: Map.fetch!(font, :unicode_to_gid),
      widths: Map.fetch!(font, :widths),
      units_per_em: Map.fetch!(font, :units_per_em),
      number_of_glyphs: Map.fetch!(font, :number_of_glyphs),
      cid_font_reference: Keyword.get(options, :cid_font_reference),
      to_unicode_reference: Keyword.get(options, :to_unicode_reference),
      used_glyphs: Keyword.get(options, :used_glyphs, MapSet.new()),
      metrics_id:
        {:truetype, key,
         :crypto.hash(
           :sha256,
           :erlang.term_to_binary({
             Map.fetch!(font, :unicode_to_gid),
             Map.fetch!(font, :widths),
             Map.fetch!(font, :units_per_em)
           })
         )}
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

  defp maybe_put_encoding(
         dictionary,
         :identity_h
       ) do
    Map.put(
      dictionary,
      "Encoding",
      {:name, "Identity-H"}
    )
  end
end

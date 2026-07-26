defmodule PaperForge.Fonts.Builtin do
  @moduledoc """
  Definitions for the 14 standard PDF fonts.

  These fonts can be used without embedding an external font file.
  """

  @fonts %{
    helvetica: %{
      key: :helvetica,
      base_font: "Helvetica",
      family: :helvetica,
      style: :regular,
      encoding: :win_ansi
    },
    helvetica_bold: %{
      key: :helvetica_bold,
      base_font: "Helvetica-Bold",
      family: :helvetica,
      style: :bold,
      encoding: :win_ansi
    },
    helvetica_oblique: %{
      key: :helvetica_oblique,
      base_font: "Helvetica-Oblique",
      family: :helvetica,
      style: :italic,
      encoding: :win_ansi
    },
    helvetica_bold_oblique: %{
      key: :helvetica_bold_oblique,
      base_font: "Helvetica-BoldOblique",
      family: :helvetica,
      style: :bold_italic,
      encoding: :win_ansi
    },
    times_roman: %{
      key: :times_roman,
      base_font: "Times-Roman",
      family: :times,
      style: :regular,
      encoding: :win_ansi
    },
    times_bold: %{
      key: :times_bold,
      base_font: "Times-Bold",
      family: :times,
      style: :bold,
      encoding: :win_ansi
    },
    times_italic: %{
      key: :times_italic,
      base_font: "Times-Italic",
      family: :times,
      style: :italic,
      encoding: :win_ansi
    },
    times_bold_italic: %{
      key: :times_bold_italic,
      base_font: "Times-BoldItalic",
      family: :times,
      style: :bold_italic,
      encoding: :win_ansi
    },
    courier: %{
      key: :courier,
      base_font: "Courier",
      family: :courier,
      style: :regular,
      encoding: :win_ansi
    },
    courier_bold: %{
      key: :courier_bold,
      base_font: "Courier-Bold",
      family: :courier,
      style: :bold,
      encoding: :win_ansi
    },
    courier_oblique: %{
      key: :courier_oblique,
      base_font: "Courier-Oblique",
      family: :courier,
      style: :italic,
      encoding: :win_ansi
    },
    courier_bold_oblique: %{
      key: :courier_bold_oblique,
      base_font: "Courier-BoldOblique",
      family: :courier,
      style: :bold_italic,
      encoding: :win_ansi
    },
    symbol: %{
      key: :symbol,
      base_font: "Symbol",
      family: :symbol,
      style: :regular,
      encoding: :builtin
    },
    zapf_dingbats: %{
      key: :zapf_dingbats,
      base_font: "ZapfDingbats",
      family: :zapf_dingbats,
      style: :regular,
      encoding: :builtin
    }
  }

  @type font_key ::
          :helvetica
          | :helvetica_bold
          | :helvetica_oblique
          | :helvetica_bold_oblique
          | :times_roman
          | :times_bold
          | :times_italic
          | :times_bold_italic
          | :courier
          | :courier_bold
          | :courier_oblique
          | :courier_bold_oblique
          | :symbol
          | :zapf_dingbats

  @doc """
  Returns all supported font keys.
  """
  @spec keys() :: [font_key()]
  def keys do
    @fonts
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Returns all built-in font definitions.
  """
  @spec all() :: [map()]
  def all do
    @fonts
    |> Map.values()
    |> Enum.sort_by(& &1.key)
  end

  @doc """
  Returns whether a font key is supported.
  """
  @spec valid?(term()) :: boolean()
  def valid?(font_key) do
    Map.has_key?(@fonts, font_key)
  end

  @doc """
  Fetches a built-in font definition.

  Returns `{:ok, definition}` or `:error`.
  """
  @spec fetch(term()) :: {:ok, map()} | :error
  def fetch(font_key) do
    Map.fetch(@fonts, font_key)
  end

  @doc """
  Fetches a built-in font definition and raises for unsupported fonts.
  """
  @spec fetch!(font_key()) :: map()
  def fetch!(font_key) do
    case fetch(font_key) do
      {:ok, definition} ->
        definition

      :error ->
        supported_fonts =
          keys()
          |> Enum.map_join(", ", &inspect/1)

        raise ArgumentError,
              "unsupported font #{inspect(font_key)}. " <>
                "Supported fonts: #{supported_fonts}"
    end
  end
end

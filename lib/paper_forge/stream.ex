defmodule PaperForge.Stream do
  @moduledoc """
  Represents a PDF stream object.

  A stream contains:

  - a PDF dictionary;
  - the raw stream data;
  - an optional list of filters.

  The serializer is responsible for applying the filters, calculating
  `/Length`, and adding the corresponding `/Filter` entry.

  ## Example

      %PaperForge.Stream{
        dictionary: %{},
        data: "BT /F1 12 Tf ET",
        filters: [:flate]
      }
  """

  @type filter ::
          :flate

  defstruct dictionary: %{},
            data: "",
            filters: []

  @type t :: %__MODULE__{
          dictionary: map(),
          data: iodata(),
          filters: [filter()]
        }

  @doc """
  Creates a new PDF stream.

  Supported options:

  - `:dictionary`
  - `:filters`

  ## Examples

      PaperForge.Stream.new(
        "Hello PDF"
      )

      PaperForge.Stream.new(
        "Compressed content",
        filters: [:flate]
      )

      PaperForge.Stream.new(
        jpeg_binary,
        dictionary: %{
          "Type" => {:name, "XObject"},
          "Subtype" => {:name, "Image"},
          "Filter" => {:name, "DCTDecode"}
        }
      )
  """
  @spec new(iodata(), keyword()) :: t()
  def new(
        data,
        options \\ []
      )
      when is_list(options) do
    dictionary =
      Keyword.get(
        options,
        :dictionary,
        %{}
      )

    filters =
      Keyword.get(
        options,
        :filters,
        []
      )

    validate_dictionary!(dictionary)

    validate_filters!(filters)

    %__MODULE__{
      dictionary: dictionary,
      data: data,
      filters: filters
    }
  end

  @doc """
  Adds a filter to a stream.

  Duplicate filters are not added.

  ## Example

      stream =
        stream
        |> PaperForge.Stream.add_filter(:flate)
  """
  @spec add_filter(t(), filter()) :: t()
  def add_filter(
        %__MODULE__{} = stream,
        filter
      ) do
    validate_filter!(filter)

    filters =
      if filter in stream.filters do
        stream.filters
      else
        stream.filters ++
          [filter]
      end

    %{
      stream
      | filters: filters
    }
  end

  @doc """
  Replaces the stream dictionary.
  """
  @spec put_dictionary(t(), map()) :: t()
  def put_dictionary(
        %__MODULE__{} = stream,
        dictionary
      ) do
    validate_dictionary!(dictionary)

    %{
      stream
      | dictionary: dictionary
    }
  end

  @doc """
  Adds or replaces a dictionary entry.
  """
  @spec put(t(), binary() | atom(), term()) :: t()
  def put(
        %__MODULE__{} = stream,
        key,
        value
      )
      when is_binary(key) or is_atom(key) do
    %{
      stream
      | dictionary:
          Map.put(
            stream.dictionary,
            key,
            value
          )
    }
  end

  @doc """
  Replaces the stream data.
  """
  @spec put_data(t(), iodata()) :: t()
  def put_data(
        %__MODULE__{} = stream,
        data
      ) do
    %{
      stream
      | data: data
    }
  end

  @doc """
  Returns the unfiltered stream data as a binary.
  """
  @spec raw_data(t()) :: binary()
  def raw_data(%__MODULE__{} = stream) do
    IO.iodata_to_binary(stream.data)
  end

  defp validate_dictionary!(dictionary)
       when is_map(dictionary) do
    :ok
  end

  defp validate_dictionary!(dictionary) do
    raise ArgumentError,
          "stream dictionary must be a map, received: " <>
            inspect(dictionary)
  end

  defp validate_filters!(filters)
       when is_list(filters) do
    Enum.each(
      filters,
      &validate_filter!/1
    )
  end

  defp validate_filters!(filters) do
    raise ArgumentError,
          "stream filters must be a list, received: " <>
            inspect(filters)
  end

  defp validate_filter!(:flate) do
    :ok
  end

  defp validate_filter!(filter) do
    raise ArgumentError,
          "unsupported stream filter #{inspect(filter)}. " <>
            "Expected :flate"
  end
end

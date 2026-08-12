defmodule PaperForge.Metadata do
  @moduledoc """
  Represents document metadata stored in the PDF information dictionary.

  Supported fields include:

  - title;
  - author;
  - subject;
  - keywords;
  - creator;
  - producer;
  - creation date;
  - modification date.

  Text values are encoded automatically using
  `PaperForge.StringEncoding`. Latin-1-compatible text is stored as a
  literal PDF string, while other Unicode text is stored as UTF-16BE.
  """

  alias PaperForge.StringEncoding

  defstruct [
    :title,
    :author,
    :subject,
    :creation_date,
    :modification_date,
    keywords: [],
    creator: "PaperForge",
    producer: "PaperForge"
  ]

  @type t :: %__MODULE__{
          title: binary() | nil,
          author: binary() | nil,
          subject: binary() | nil,
          keywords: [binary()],
          creator: binary() | nil,
          producer: binary() | nil,
          creation_date: DateTime.t() | NaiveDateTime.t() | nil,
          modification_date: DateTime.t() | NaiveDateTime.t() | nil
        }

  @doc """
  Creates document metadata from a keyword list.

  ## Supported options

  - `:title`
  - `:author`
  - `:subject`
  - `:keywords`
  - `:creator`
  - `:producer`
  - `:creation_date`
  - `:modification_date`

  ## Example

      PaperForge.Metadata.new(
        title: "Reporte de México",
        author: "Manuel García",
        keywords: ["PDF", "Elixir", "PaperForge"],
        creation_date: DateTime.utc_now()
      )
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) when is_list(options) do
    validate_options!(options)

    %__MODULE__{
      title:
        options
        |> Keyword.get(:title)
        |> validate_optional_string!(:title),
      author:
        options
        |> Keyword.get(:author)
        |> validate_optional_string!(:author),
      subject:
        options
        |> Keyword.get(:subject)
        |> validate_optional_string!(:subject),
      keywords:
        options
        |> Keyword.get(:keywords, [])
        |> validate_keywords!(),
      creator:
        options
        |> Keyword.get(:creator, "PaperForge")
        |> validate_optional_string!(:creator),
      producer:
        options
        |> Keyword.get(:producer, "PaperForge")
        |> validate_optional_string!(:producer),
      creation_date:
        options
        |> Keyword.get(:creation_date)
        |> validate_optional_date!(:creation_date),
      modification_date:
        options
        |> Keyword.get(:modification_date)
        |> validate_optional_date!(:modification_date)
    }
  end

  @doc """
  Converts metadata into a PDF information dictionary.

  Empty and `nil` values are omitted.
  """
  @spec to_dictionary(t()) :: map()
  def to_dictionary(%__MODULE__{} = metadata) do
    %{}
    |> put_encoded_string("Title", metadata.title)
    |> put_encoded_string("Author", metadata.author)
    |> put_encoded_string("Subject", metadata.subject)
    |> put_keywords(metadata.keywords)
    |> put_encoded_string("Creator", metadata.creator)
    |> put_encoded_string("Producer", metadata.producer)
    |> put_date("CreationDate", metadata.creation_date)
    |> put_date("ModDate", metadata.modification_date)
  end

  @doc """
  Returns whether the metadata contains no values that would be written
  to the PDF information dictionary.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = metadata) do
    map_size(to_dictionary(metadata)) == 0
  end

  defp put_encoded_string(
         dictionary,
         _key,
         nil
       ) do
    dictionary
  end

  defp put_encoded_string(
         dictionary,
         _key,
         ""
       ) do
    dictionary
  end

  defp put_encoded_string(
         dictionary,
         key,
         value
       )
       when is_binary(value) do
    Map.put(
      dictionary,
      key,
      StringEncoding.auto(value)
    )
  end

  defp put_keywords(
         dictionary,
         []
       ) do
    dictionary
  end

  defp put_keywords(
         dictionary,
         keywords
       ) do
    value =
      Enum.join(
        keywords,
        ", "
      )

    put_encoded_string(
      dictionary,
      "Keywords",
      value
    )
  end

  defp put_date(
         dictionary,
         _key,
         nil
       ) do
    dictionary
  end

  defp put_date(
         dictionary,
         key,
         %DateTime{} = datetime
       ) do
    Map.put(
      dictionary,
      key,
      encode_datetime(datetime)
    )
  end

  defp put_date(
         dictionary,
         key,
         %NaiveDateTime{} = datetime
       ) do
    Map.put(
      dictionary,
      key,
      encode_naive_datetime(datetime)
    )
  end

  defp encode_datetime(%DateTime{} = datetime) do
    offset_seconds =
      datetime.utc_offset +
        datetime.std_offset

    {
      offset_sign,
      absolute_offset
    } =
      if offset_seconds < 0 do
        {
          "-",
          abs(offset_seconds)
        }
      else
        {
          "+",
          offset_seconds
        }
      end

    offset_hours =
      div(
        absolute_offset,
        3600
      )

    offset_minutes =
      absolute_offset
      |> rem(3600)
      |> div(60)

    [
      "D:",
      pad(datetime.year, 4),
      pad(datetime.month, 2),
      pad(datetime.day, 2),
      pad(datetime.hour, 2),
      pad(datetime.minute, 2),
      pad(datetime.second, 2),
      offset_sign,
      pad(offset_hours, 2),
      "'",
      pad(offset_minutes, 2),
      "'"
    ]
    |> IO.iodata_to_binary()
  end

  defp encode_naive_datetime(%NaiveDateTime{} = datetime) do
    [
      "D:",
      pad(datetime.year, 4),
      pad(datetime.month, 2),
      pad(datetime.day, 2),
      pad(datetime.hour, 2),
      pad(datetime.minute, 2),
      pad(datetime.second, 2)
    ]
    |> IO.iodata_to_binary()
  end

  defp pad(
         value,
         width
       ) do
    value
    |> Integer.to_string()
    |> String.pad_leading(
      width,
      "0"
    )
  end

  defp validate_options!(options) do
    allowed_options =
      MapSet.new([
        :title,
        :author,
        :subject,
        :keywords,
        :creator,
        :producer,
        :creation_date,
        :modification_date
      ])

    invalid_options =
      options
      |> Keyword.keys()
      |> Enum.reject(
        &MapSet.member?(
          allowed_options,
          &1
        )
      )

    case invalid_options do
      [] ->
        :ok

      invalid_options ->
        raise ArgumentError,
              "unsupported metadata options: " <>
                Enum.map_join(
                  invalid_options,
                  ", ",
                  &inspect/1
                )
    end
  end

  defp validate_optional_string!(
         nil,
         _name
       ) do
    nil
  end

  defp validate_optional_string!(
         value,
         _name
       )
       when is_binary(value) do
    value
  end

  defp validate_optional_string!(
         value,
         name
       ) do
    raise ArgumentError,
          "#{name} must be a string or nil, received: " <>
            inspect(value)
  end

  defp validate_keywords!(keywords)
       when is_list(keywords) do
    unless Enum.all?(
             keywords,
             &is_binary/1
           ) do
      raise ArgumentError,
            "metadata keywords must be a list of strings"
    end

    keywords
  end

  defp validate_keywords!(keywords) do
    raise ArgumentError,
          "metadata keywords must be a list of strings, received: " <>
            inspect(keywords)
  end

  defp validate_optional_date!(
         nil,
         _name
       ) do
    nil
  end

  defp validate_optional_date!(
         %DateTime{} = datetime,
         _name
       ) do
    datetime
  end

  defp validate_optional_date!(
         %NaiveDateTime{} = datetime,
         _name
       ) do
    datetime
  end

  defp validate_optional_date!(
         value,
         name
       ) do
    raise ArgumentError,
          "#{name} must be a DateTime, NaiveDateTime, or nil, " <>
            "received: #{inspect(value)}"
  end
end

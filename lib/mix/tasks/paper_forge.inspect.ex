defmodule Mix.Tasks.PaperForge.Inspect do
  use Mix.Task
  @shortdoc "Inspects an existing PDF document"
  @moduledoc """
  Reports the structure and resources of an existing PDF.

      mix paper_forge.inspect document.pdf
      mix paper_forge.inspect document.pdf --json
      mix paper_forge.inspect document.pdf --password-env PDF_PASSWORD

  Passwords are read from the named environment variable and never printed.
  Signature inventory is not cryptographic signature verification.
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {options, paths, invalid} =
      OptionParser.parse(args, strict: [json: :boolean, password_env: :string])

    unless length(paths) == 1 and invalid == [],
      do: Mix.raise("Usage: mix paper_forge.inspect document.pdf [--json] [--password-env NAME]")

    password = password_option(options[:password_env])

    with {:ok, document} <- PaperForge.open(hd(paths), password),
         {:ok, report} <- PaperForge.analyze(document) do
      print_report(report, options[:json])
    else
      {:error, reason} -> Mix.raise("Cannot inspect PDF: #{inspect(reason)}")
    end
  end

  defp password_option(nil), do: []

  defp password_option(name) do
    case System.get_env(name) do
      nil -> Mix.raise("Password environment variable is not set")
      password -> [password: password]
    end
  end

  defp print_report(report, as_json) do
    if as_json do
      Mix.shell().info(Jason.encode!(json(report), pretty: true))
    else
      Mix.shell().info(
        "PDF #{report.pdf_version} | #{report.page_count || "unknown"} pages | #{report.object_count} objects"
      )

      Mix.shell().info(
        "Cross references: #{report.cross_reference_type}; compressed objects: #{report.compressed_objects}; incremental revisions: #{report.incremental_revisions}"
      )

      Enum.each(
        [
          :fonts,
          :images,
          :forms,
          :annotations,
          :attachments,
          :outlines,
          :signatures,
          :duplicate_resources,
          :broken_references,
          :orphaned_objects,
          :issues
        ],
        fn key ->
          Mix.shell().info("#{key}: #{length(report[key])}")
        end
      )

      Mix.shell().info(
        "Encryption: #{if report.encryption, do: "AES-256 (authenticated)", else: "none"}; signatures are not cryptographically verified"
      )
    end
  end

  defp json(%PaperForge.Reference{object_id: id, generation: generation}),
    do: %{object_id: id, generation: generation}

  defp json(%PaperForge.Stream{dictionary: dictionary, data: data}),
    do: %{dictionary: json(dictionary), encoded_bytes: IO.iodata_length(data)}

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, json(value)} end)

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_tuple(value), do: value |> Tuple.to_list() |> json()

  defp json(value) when is_binary(value) do
    if String.valid?(value), do: value, else: %{base64: Base.encode64(value)}
  end

  defp json(value), do: value
end

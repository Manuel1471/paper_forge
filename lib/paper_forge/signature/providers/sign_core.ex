defmodule PaperForge.Signature.Providers.SignCore do
  @moduledoc """
  Default PAdES provider backed by pure Elixir/OTP PKCS#8 signing.

  PKCS#8 PEM keys are the default and require no executable, NIF, or native
  compilation. PKCS#12/PFX loading is available as an explicit compatibility
  option and requires an `openssl` executable at runtime.
  """

  @behaviour PaperForge.Signature.Provider

  @impl true
  def capabilities, do: [:invisible, :incremental, :timestamp]

  @impl true
  def sign(pdf, options) do
    with :ok <- validate_requested_capabilities(options),
         {:ok, signer, chain} <- load_signer(options) do
      options =
        options
        |> Keyword.drop([:certificate, :provider, :visible, :multiple])
        |> Keyword.put(:signer, signer)
        |> Keyword.put(:x5c, chain)

      SignCore.PDF.sign(pdf, options)
    end
  end

  @impl true
  def verify(pdf, options), do: SignCore.PDF.verify(pdf, options)

  defp validate_requested_capabilities(options) do
    cond do
      Keyword.get(options, :visible, false) ->
        {:error, {:unsupported_capability, :visible}}

      Keyword.get(options, :multiple, false) ->
        {:error, {:unsupported_capability, :multiple}}

      true ->
        :ok
    end
  end

  defp load_signer(options) do
    case Keyword.get(options, :certificate) do
      {:pkcs8, signer_options} when is_list(signer_options) ->
        with {:ok, signer} <- SoftSigner.PKCS8.load(signer_options) do
          {:ok, signer, SoftSigner.PKCS8.cert_chain(signer)}
        end

      {:pkcs12, path, signer_options} when is_binary(path) and is_list(signer_options) ->
        with {:ok, signer} <- SoftSigner.PKCS12.load(path, signer_options) do
          {:ok, signer, SoftSigner.PKCS12.cert_chain(signer)}
        end

      {:signer, signer, chain} when is_list(chain) and chain != [] ->
        {:ok, signer, chain}

      nil ->
        {:error, :missing_certificate}

      other ->
        {:error, {:invalid_certificate_source, other}}
    end
  end
end

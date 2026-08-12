defmodule PaperForge.Signature do
  @moduledoc """
  Adds and verifies provider-backed digital signatures.

  The default provider signs incrementally with PAdES and PKCS#8 PEM material
  using Elixir/OTP only. Select another provider per call with `:provider` or
  configure one globally with `config :paper_forge, :signature_provider`.

      {:ok, signed_pdf} =
        PaperForge.Signature.sign(pdf,
          certificate: {:pkcs8, key_path: "key.pem", cert_path: "cert.pem"},
          reason: "Contract approval",
          location: "Monterrey, Mexico"
        )

  Passwords and private keys are call-time values and are never stored in a
  declarative template or compiled-template cache.
  """

  alias PaperForge.Signature.Providers.SignCore

  @type result :: {:ok, binary()} | {:error, term()}

  @doc "Returns the capabilities advertised by the selected provider."
  @spec capabilities(keyword()) :: [PaperForge.Signature.Provider.capability()]
  def capabilities(options \\ []) do
    provider = provider(options)
    Code.ensure_loaded?(provider)
    apply(provider, :capabilities, [])
  end

  @doc "Signs a PDF binary without rewriting its original revision."
  @spec sign(binary(), keyword()) :: result()
  def sign(pdf, options) when is_binary(pdf) and is_list(options) do
    provider = provider(options)
    Code.ensure_loaded?(provider)

    if function_exported?(provider, :sign, 2) do
      provider.sign(pdf, options)
    else
      {:error, {:invalid_provider, provider}}
    end
  end

  @doc "Signs a PDF binary and raises when the provider rejects the operation."
  @spec sign!(binary(), keyword()) :: binary()
  def sign!(pdf, options) do
    case sign(pdf, options) do
      {:ok, signed} -> signed
      {:error, reason} -> raise ArgumentError, "could not sign PDF: #{inspect(reason)}"
    end
  end

  @doc "Signs an existing PDF and writes the signed revision to `destination`."
  @spec sign_file(Path.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def sign_file(source, destination, options \\ []) do
    with {:ok, pdf} <- File.read(source),
         {:ok, signed} <- sign(pdf, options) do
      File.write(destination, signed)
    end
  end

  @doc "Verifies a signed PDF with the selected provider and trust policy."
  @spec verify(binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def verify(pdf, options \\ []) when is_binary(pdf) and is_list(options) do
    provider = provider(options)
    Code.ensure_loaded?(provider)

    if function_exported?(provider, :verify, 2) do
      provider.verify(pdf, options)
    else
      {:error, {:invalid_provider, provider}}
    end
  end

  defp provider(options) do
    Keyword.get(
      options,
      :provider,
      Application.get_env(:paper_forge, :signature_provider, SignCore)
    )
  end
end

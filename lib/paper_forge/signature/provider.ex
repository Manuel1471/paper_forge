defmodule PaperForge.Signature.Provider do
  @moduledoc """
  Contract for pluggable PDF signature providers.

  Providers isolate certificate storage and signing infrastructure from the
  stable PaperForge API. The built-in provider uses Elixir/OTP software keys;
  applications may replace it with an HSM, KMS, or another signing service.
  """

  @type capability :: :invisible | :visible | :incremental | :multiple | :timestamp
  @type result :: {:ok, binary()} | {:error, term()}

  @callback capabilities() :: [capability()]
  @callback sign(binary(), keyword()) :: result()
  @callback verify(binary(), keyword()) :: {:ok, term()} | {:error, term()}
end

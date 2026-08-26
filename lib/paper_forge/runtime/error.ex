defmodule PaperForge.Error do
  @moduledoc """
  Stable, structured failure returned by bounded production operations.

  `code` is intended for programmatic handling. The `PF8xxx` range covers
  runtime execution, timeouts, cancellation, and circuit-breaker decisions.
  """

  @enforce_keys [:code, :category, :message]
  defstruct [:code, :category, :message, :operation, :details, retryable?: false]

  @type t :: %__MODULE__{
          code: binary(),
          category: :timeout | :resource | :runtime | :cancelled,
          message: binary(),
          operation: atom() | nil,
          details: map() | nil,
          retryable?: boolean()
        }

  @spec timeout(atom(), timeout()) :: t()
  def timeout(operation, timeout) do
    %__MODULE__{
      code: "PF8101",
      category: :timeout,
      operation: operation,
      message: "#{operation} exceeded its #{inspect(timeout)} ms timeout",
      details: %{timeout: timeout},
      retryable?: true
    }
  end

  @spec circuit_open(term(), non_neg_integer()) :: t()
  def circuit_open(resource, retry_after_ms) do
    %__MODULE__{
      code: "PF8102",
      category: :resource,
      operation: :resource,
      message: "resource is temporarily unavailable after repeated failures",
      details: %{resource: resource, retry_after_ms: retry_after_ms},
      retryable?: true
    }
  end

  @spec resource_limit(atom(), non_neg_integer(), non_neg_integer()) :: t()
  def resource_limit(resource, value, limit) do
    %__MODULE__{
      code: "PF8103",
      category: :resource,
      operation: :render,
      message: "#{resource} limit exceeded",
      details: %{resource: resource, value: value, limit: limit},
      retryable?: false
    }
  end

  @spec cancelled(atom()) :: t()
  def cancelled(operation) do
    %__MODULE__{
      code: "PF8104",
      category: :cancelled,
      operation: operation,
      message: "#{operation} was cancelled",
      details: %{},
      retryable?: true
    }
  end
end

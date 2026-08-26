defmodule Mix.Tasks.Test.Fuzz do
  use Mix.Task

  @shortdoc "Runs opt-in parser fuzz tests"

  @moduledoc """
  Runs the bounded parser fuzz profile.

      MIX_ENV=test mix test.fuzz

  Additional arguments are passed to `mix test`, so callers can provide a
  deterministic ExUnit seed when reproducing a generated failure.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("test", ["--only", "fuzz" | args])
  end
end

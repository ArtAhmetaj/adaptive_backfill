defmodule AdaptiveBackfill.MixProject do
  use Mix.Project

  def project do
    [
      app: :adaptive_backfill,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AdaptiveBackfill.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.13.0"},
      {:ecto_sql, "~> 3.12.0"},
      {:postgrex, "~> 0.17"},
      {:mimic, "~> 1.7", only: :test}
    ]
  end
end

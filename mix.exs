defmodule AdaptiveBackfill.MixProject do
  use Mix.Project

  def project do
    [
      app: :adaptive_backfill,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: "https://github.com/ArtAhmetaj/adaptive_backfill"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.13.0"},
      {:ecto_sql, "~> 3.12.0"},
      {:postgrex, "~> 0.17"},
      {:telemetry, "~> 1.0"},
      {:mimic, "~> 1.7", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Adaptive backfill library with health checks for Elixir.
    Supports both single operations and batch processing with sync/async health monitoring.
    """
  end

  defp package do
    [
      name: "adaptive_backfill",
      files: ~w(lib examples .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/ArtAhmetaj/adaptive_backfill",
        "Changelog" => "https://github.com/ArtAhmetaj/adaptive_backfill/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "AdaptiveBackfill",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end

defmodule FeedbackATron.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/hyperpolymath/feedback-a-tron"

  def project do
    [
      app: :feedback_a_tron,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      releases: releases(),

      # Docs
      name: "FeedbackATron",
      description: "Automated multi-platform feedback submission with network verification",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :inets],
      mod: {FeedbackATron.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},

      # JSON
      {:jason, "~> 1.4"},

      # CLI argument parsing
      {:optimus, "~> 0.5"},

      # Terminal UI
      {:owl, "~> 0.11"},

      # Config file parsing
      {:toml, "~> 0.7"},

      # Fuzzy string matching for deduplication
      {:the_fuzz, "~> 0.6"},

      # For testing
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [
      main_module: FeedbackATron.CLI,
      name: "feedback-a-tron"
    ]
  end

  defp releases do
    [
      feedback_a_tron: [
        steps: [:assemble, :tar]
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "ARCHITECTURE.md"]
    ]
  end
end

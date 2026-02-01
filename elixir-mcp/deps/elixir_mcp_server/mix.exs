defmodule ElixirMcpServer.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hyperpolymath/elixir-mcp-server"

  def project do
    [
      app: :elixir_mcp_server,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description: "Model Context Protocol (MCP) server framework for Elixir/BEAM",
      package: package(),

      # Docs
      name: "ElixirMcpServer",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Testing
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: :test},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MPL-2.0"],
      metadata: %{"pmpl" => "PMPL-1.0-or-later obligations still apply; see LICENSE/README"},
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.adoc README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "ElixirMcpServer",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end

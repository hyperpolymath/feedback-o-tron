# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Application do
  @moduledoc """
  OTP Application for FeedbackATron.

  Supervises:
  - Submitter: Multi-platform issue submission
  - Deduplicator: Prevents duplicate submissions
  - AuditLog: Records all operations
  - Synthesis.TemplateCache: TTL cache for fetched issue-form templates
  - NetworkVerifier: Pre-flight network checks
  - MigrationObserver: ReScript migration session tracking (optional)
  - BatchReviewer: Issue review queue (optional, with migration observer)
  - Pipeline.Supervisor: GenStage pipeline (optional, with migration observer)
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core services
      FeedbackATron.RateLimiter,
      FeedbackATron.Submitter,
      FeedbackATron.Deduplicator,
      FeedbackATron.AuditLog,
      FeedbackATron.Synthesis.TemplateCache,

      # Network verification (optional, can be disabled)
      {FeedbackATron.NetworkVerifier, enabled: true}
    ]

    children = maybe_add_mcp_server(children)
    children = maybe_add_http_intake(children)
    children = maybe_add_migration_observer(children)

    opts = [strategy: :one_for_one, name: FeedbackATron.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Optional HTTP intake — the localhost wire the boj gateway/`bug-filing-mcp`
  # cartridge drives to reach the engine (docs/AUTONOMOUS-BUG-PIPELINE.adoc, C2/D0).
  # Off by default; bound to loopback only.
  defp maybe_add_http_intake(children) do
    if http_intake_enabled?() do
      children ++
        [
          {Bandit,
           plug: FeedbackATron.HTTPIntake.Router,
           scheme: :http,
           ip: http_intake_ip(),
           port: http_intake_port()}
        ]
    else
      children
    end
  end

  defp maybe_add_mcp_server(children) do
    if mcp_enabled?() do
      mcp_child = {
        FeedbackATron.MCP.Server,
        name: "feedback-a-tron",
        version: Application.spec(:feedback_a_tron, :vsn) |> to_string(),
        tools: [
          FeedbackATron.MCP.Tools.SubmitFeedback,
          FeedbackATron.MCP.Tools.ResearchFeedback,
          FeedbackATron.MCP.Tools.SynthesizeFeedback
        ]
      }

      children ++ [mcp_child]
    else
      children
    end
  end

  defp maybe_add_migration_observer(children) do
    if migration_observer_enabled?() do
      children ++
        [
          FeedbackATron.MigrationObserver,
          FeedbackATron.BatchReviewer,
          FeedbackATron.Pipeline.Supervisor
        ]
    else
      children
    end
  end

  defp mcp_enabled? do
    env_enabled? = System.get_env("FEEDBACK_A_TRON_MCP") || System.get_env("MCP_SERVER")

    env_on? =
      case env_enabled? do
        nil ->
          false

        value ->
          normalized =
            value
            |> String.trim()
            |> String.downcase()

          Enum.member?(["1", "true", "yes", "on"], normalized)
      end

    env_on? || Enum.any?(System.argv(), &(&1 == "--mcp-server"))
  end

  defp http_intake_enabled? do
    env_on?(System.get_env("FEEDBACK_A_TRON_HTTP")) ||
      Enum.any?(System.argv(), &(&1 == "--http-intake"))
  end

  defp http_intake_port do
    case System.get_env("FEEDBACK_A_TRON_HTTP_PORT") do
      nil ->
        7722

      value ->
        case Integer.parse(String.trim(value)) do
          {port, _} -> port
          :error -> 7722
        end
    end
  end

  # Loopback only by default; override with FEEDBACK_A_TRON_HTTP_BIND (e.g. "0.0.0.0").
  defp http_intake_ip do
    bind = System.get_env("FEEDBACK_A_TRON_HTTP_BIND") || "127.0.0.1"

    case :inet.parse_address(String.to_charlist(String.trim(bind))) do
      {:ok, ip} -> ip
      {:error, _} -> {127, 0, 0, 1}
    end
  end

  defp env_on?(nil), do: false

  defp env_on?(value) do
    normalized = value |> String.trim() |> String.downcase()
    Enum.member?(["1", "true", "yes", "on"], normalized)
  end

  defp migration_observer_enabled? do
    env_val = System.get_env("FEEDBACK_A_TRON_MIGRATION_MODE")

    env_on? =
      case env_val do
        nil ->
          false

        value ->
          normalized = value |> String.trim() |> String.downcase()
          Enum.member?(["1", "true", "yes", "on"], normalized)
      end

    env_on? || Enum.any?(System.argv(), &(&1 == "--migration-observer"))
  end
end

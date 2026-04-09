defmodule FeedbackATron.Application do
  @moduledoc """
  OTP Application for FeedbackATron.

  Supervises:
  - Submitter: Multi-platform issue submission
  - Deduplicator: Prevents duplicate submissions
  - AuditLog: Records all operations
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

      # Network verification (optional, can be disabled)
      {FeedbackATron.NetworkVerifier, enabled: true}
    ]

    children = maybe_add_mcp_server(children)
    children = maybe_add_migration_observer(children)

    opts = [strategy: :one_for_one, name: FeedbackATron.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_mcp_server(children) do
    if mcp_enabled?() do
      mcp_child = {
        FeedbackATron.MCP.Server,
        name: "feedback-a-tron",
        version: Application.spec(:feedback_a_tron, :vsn) |> to_string(),
        tools: [FeedbackATron.MCP.Tools.SubmitFeedback]
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
        nil -> false
        value ->
          normalized =
            value
            |> String.trim()
            |> String.downcase()

          Enum.member?(["1", "true", "yes", "on"], normalized)
      end

    env_on? || Enum.any?(System.argv(), &(&1 == "--mcp-server"))
  end

  defp migration_observer_enabled? do
    env_val = System.get_env("FEEDBACK_A_TRON_MIGRATION_MODE")

    env_on? =
      case env_val do
        nil -> false
        value ->
          normalized = value |> String.trim() |> String.downcase()
          Enum.member?(["1", "true", "yes", "on"], normalized)
      end

    env_on? || Enum.any?(System.argv(), &(&1 == "--migration-observer"))
  end
end

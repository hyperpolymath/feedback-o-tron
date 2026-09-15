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
  - Doors: MCP stdio server and HTTP intake, opened by `FeedbackATron.Doors`
    from the `:doors` application env or the `FEEDBACK_O_TRON_*` environment
  - MigrationObserver: ReScript migration session tracking (optional)
  - BatchReviewer: Issue review queue (optional, with migration observer)
  - Pipeline.Supervisor: GenStage pipeline (optional, with migration observer)
  """

  use Application

  @impl true
  def start(_type, _args) do
    doors =
      FeedbackATron.Doors.config(
        Application.get_env(:feedback_a_tron, :doors, []),
        System.get_env()
      )

    children =
      core_children() ++
        FeedbackATron.Doors.children(doors) ++
        migration_observer_children()

    opts = [strategy: :one_for_one, name: FeedbackATron.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp core_children do
    [
      FeedbackATron.RateLimiter,
      FeedbackATron.Submitter,
      FeedbackATron.Deduplicator,
      FeedbackATron.AuditLog,
      FeedbackATron.Synthesis.TemplateCache,
      # Network verification (optional, can be disabled)
      {FeedbackATron.NetworkVerifier, enabled: true}
    ]
  end

  defp migration_observer_children do
    if migration_observer_enabled?() do
      [
        FeedbackATron.MigrationObserver,
        FeedbackATron.BatchReviewer,
        FeedbackATron.Pipeline.Supervisor
      ]
    else
      []
    end
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

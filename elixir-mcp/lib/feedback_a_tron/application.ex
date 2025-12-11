defmodule FeedbackATron.Application do
  @moduledoc """
  OTP Application for FeedbackATron.

  Supervises:
  - Submitter: Multi-platform issue submission
  - Deduplicator: Prevents duplicate submissions
  - AuditLog: Records all operations
  - NetworkVerifier: Pre-flight network checks
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core services
      FeedbackATron.Submitter,
      FeedbackATron.Deduplicator,
      FeedbackATron.AuditLog,

      # Network verification (optional, can be disabled)
      {FeedbackATron.NetworkVerifier, enabled: true}
    ]

    opts = [strategy: :one_for_one, name: FeedbackATron.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

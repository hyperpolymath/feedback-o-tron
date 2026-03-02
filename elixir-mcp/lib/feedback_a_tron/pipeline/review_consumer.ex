# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.Pipeline.ReviewConsumer do
  @moduledoc """
  GenStage consumer that extracts issues from completed migration sessions
  and queues them for human review via BatchReviewer.

  Subscribes to the Pipeline.Producer alongside VeriSimConsumer.
  """

  use GenStage

  require Logger

  alias FeedbackATron.BatchReviewer

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[Pipeline.ReviewConsumer] Started")

    {:consumer, %{},
     subscribe_to: [{FeedbackATron.Pipeline.Producer, max_demand: 5, min_demand: 1}]}
  end

  @impl true
  def handle_events(sessions, _from, state) do
    for session <- sessions do
      issues =
        session.events
        |> Enum.filter(fn e -> e.type == :issue end)

      for event <- issues do
        issue = %{
          title: "[Migration] #{session.label}: #{event.description}",
          body: build_issue_body(session, event),
          repo: extract_repo_name(session.repo_path),
          source: :migration_pipeline,
          session_id: session.session_id,
          severity: event.severity
        }

        BatchReviewer.enqueue(issue)
      end

      if length(issues) > 0 do
        Logger.info(
          "[ReviewConsumer] Queued #{length(issues)} issues from session #{session.session_id}"
        )
      end
    end

    {:noreply, [], state}
  end

  defp build_issue_body(session, event) do
    """
    ## Migration Issue (Pipeline)

    **Session:** #{session.session_id}
    **Repo:** #{session.repo_path}
    **Label:** #{session.label}
    **Detected:** #{DateTime.to_iso8601(event.timestamp)}
    **Severity:** #{event.severity}

    ### Description

    #{event.description}

    ---
    _Queued by feedback-o-tron pipeline_
    """
  end

  defp extract_repo_name(path) do
    path |> String.split("/") |> List.last()
  end
end

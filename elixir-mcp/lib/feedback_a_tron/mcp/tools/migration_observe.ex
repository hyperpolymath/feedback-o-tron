# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.MCP.Tools.MigrationObserve do
  @moduledoc """
  MCP tool definitions for migration observation.

  Three tools following the pattern of `SubmitFeedback`:
  1. `begin_migration_observation` — start a session
  2. `log_migration_event` — log events during migration
  3. `end_migration_observation` — end session, generate diff + report
  4. `review_migration_queue` — list/approve/reject queued issues
  5. `submit_approved_migrations` — submit approved issues
  """

  alias FeedbackATron.{MigrationObserver, BatchReviewer, ReportGenerator}

  # --- Tool Definitions ---

  def tools do
    [
      begin_migration_observation_tool(),
      log_migration_event_tool(),
      end_migration_observation_tool(),
      review_migration_queue_tool(),
      submit_approved_migrations_tool()
    ]
  end

  # --- begin_migration_observation ---

  defp begin_migration_observation_tool do
    %{
      name: "begin_migration_observation",
      description: """
      Begin a ReScript migration observation session.

      Takes a before-snapshot of the target repo using panic-attack,
      capturing deprecated API counts, health score, version bracket,
      and other migration metrics. The session stays active until
      end_migration_observation is called.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          repo_path: %{
            type: "string",
            description: "Absolute path to the ReScript project directory"
          },
          label: %{
            type: "string",
            description: "Label for this session (e.g. 'v11-to-v12', 'belt-removal')"
          },
          build_time: %{
            type: "boolean",
            description: "Measure build time (runs rescript build)"
          },
          bundle_size: %{
            type: "boolean",
            description: "Measure bundle size (scans output directory)"
          }
        },
        required: ["repo_path", "label"]
      },
      handler: &handle_begin/1
    }
  end

  def handle_begin(params) do
    repo_path = params["repo_path"]
    label = params["label"]

    opts = [
      build_time: params["build_time"] || false,
      bundle_size: params["bundle_size"] || false
    ]

    case MigrationObserver.begin_observation(repo_path, label, opts) do
      {:ok, session_id} ->
        {:ok,
         [
           %{
             type: "text",
             text:
               "Migration observation started.\n" <>
                 "Session ID: #{session_id}\n" <>
                 "Repo: #{repo_path}\n" <>
                 "Label: #{label}\n\n" <>
                 "Before-snapshot captured. Proceed with migration work, " <>
                 "then call end_migration_observation when done.\n" <>
                 "Use log_migration_event to record issues, decisions, and notes."
           }
         ]}

      {:error, :session_active} ->
        {:error, "A migration session is already active. End it first."}

      {:error, reason} ->
        {:error, "Failed to start observation: #{inspect(reason)}"}
    end
  end

  # --- log_migration_event ---

  defp log_migration_event_tool do
    %{
      name: "log_migration_event",
      description: """
      Log a timestamped event during an active migration session.

      Events are captured for the migration report and may be queued
      for review (issues) or stored in VeriSimDB.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          event_type: %{
            type: "string",
            enum: ["issue", "complication", "note", "decision", "benchmark"],
            description: "Type of event to log"
          },
          description: %{
            type: "string",
            description: "Description of the event"
          },
          severity: %{
            type: "string",
            enum: ["info", "warning", "critical"],
            description: "Severity level (default: info)"
          }
        },
        required: ["event_type", "description"]
      },
      handler: &handle_log_event/1
    }
  end

  def handle_log_event(params) do
    event_type = String.to_existing_atom(params["event_type"])
    description = params["description"]

    severity =
      case params["severity"] do
        "critical" -> :critical
        "warning" -> :warning
        _ -> :info
      end

    case MigrationObserver.log_event(event_type, description, severity: severity) do
      :ok ->
        {:ok,
         [
           %{
             type: "text",
             text: "Event logged: [#{params["event_type"]}] #{description}"
           }
         ]}

      {:error, :no_active_session} ->
        {:error, "No active migration session. Call begin_migration_observation first."}

      {:error, reason} ->
        {:error, "Failed to log event: #{inspect(reason)}"}
    end
  end

  # --- end_migration_observation ---

  defp end_migration_observation_tool do
    %{
      name: "end_migration_observation",
      description: """
      End the current migration observation session.

      Takes an after-snapshot, computes the diff between before/after,
      generates a migration report, and queues discovered issues for review.
      Returns the full session summary with health score delta.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          notes: %{
            type: "string",
            description: "Optional session notes for the report"
          }
        },
        required: []
      },
      handler: &handle_end/1
    }
  end

  def handle_end(params) do
    notes = params["notes"]

    case MigrationObserver.end_observation(notes) do
      {:ok, session} ->
        report = ReportGenerator.per_repo_report(session)

        health_delta = session.diff[:health_delta] || 0.0
        deprecated_delta = session.diff[:deprecated_delta] || 0

        summary =
          "Migration observation completed.\n\n" <>
            "Session: #{session.session_id}\n" <>
            "Health delta: #{format_delta(health_delta)}\n" <>
            "Deprecated APIs delta: #{deprecated_delta}\n" <>
            "Events logged: #{length(session.events)}\n" <>
            "Issues queued for review: #{session.events |> Enum.count(&(&1.type == :issue))}\n\n" <>
            "---\n\n" <>
            report

        {:ok, [%{type: "text", text: summary}]}

      {:error, :no_active_session} ->
        {:error, "No active migration session."}

      {:error, reason} ->
        {:error, "Failed to end observation: #{inspect(reason)}"}
    end
  end

  # --- review_migration_queue ---

  defp review_migration_queue_tool do
    %{
      name: "review_migration_queue",
      description: """
      Review the migration issue queue. Lists pending items that were
      discovered during migration sessions. Items can be approved,
      rejected, or edited before submission.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          action: %{
            type: "string",
            enum: ["list", "approve", "reject", "stats"],
            description: "Action to perform (default: list)"
          },
          item_id: %{
            type: "string",
            description: "Item ID (required for approve/reject)"
          },
          reason: %{
            type: "string",
            description: "Rejection reason (for reject action)"
          },
          edits: %{
            type: "object",
            description: "Edits to apply before approval (title, body, repo)"
          }
        },
        required: []
      },
      handler: &handle_review/1
    }
  end

  def handle_review(params) do
    action = params["action"] || "list"

    case action do
      "list" ->
        pending = BatchReviewer.list_pending()

        if length(pending) == 0 do
          {:ok, [%{type: "text", text: "No pending items in the review queue."}]}
        else
          items =
            pending
            |> Enum.map(fn item ->
              "- **#{item.id}**: #{item.issue.title}\n  Severity: #{item.issue[:severity] || "info"}\n  Enqueued: #{DateTime.to_iso8601(item.enqueued_at)}"
            end)
            |> Enum.join("\n\n")

          {:ok,
           [
             %{
               type: "text",
               text: "## Pending Migration Issues (#{length(pending)})\n\n#{items}"
             }
           ]}
        end

      "approve" ->
        item_id = params["item_id"]

        if item_id do
          edits =
            (params["edits"] || %{})
            |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
            |> Map.new()

          case BatchReviewer.approve(item_id, edits) do
            :ok -> {:ok, [%{type: "text", text: "Approved: #{item_id}"}]}
            {:error, :not_found} -> {:error, "Item not found: #{item_id}"}
          end
        else
          {:error, "item_id required for approve action"}
        end

      "reject" ->
        item_id = params["item_id"]
        reason = params["reason"]

        if item_id do
          case BatchReviewer.reject(item_id, reason) do
            :ok -> {:ok, [%{type: "text", text: "Rejected: #{item_id}"}]}
            {:error, :not_found} -> {:error, "Item not found: #{item_id}"}
          end
        else
          {:error, "item_id required for reject action"}
        end

      "stats" ->
        stats = BatchReviewer.stats()

        {:ok,
         [
           %{
             type: "text",
             text:
               "## Review Queue Stats\n\n" <>
                 "Pending: #{stats.pending}\n" <>
                 "Approved: #{stats.approved}\n" <>
                 "Rejected: #{stats.rejected}\n" <>
                 "Submitted: #{stats.submitted}\n" <>
                 "Total: #{stats.total}"
           }
         ]}

      _ ->
        {:error, "Unknown action: #{action}"}
    end
  end

  # --- submit_approved_migrations ---

  defp submit_approved_migrations_tool do
    %{
      name: "submit_approved_migrations",
      description: """
      Submit all approved migration issues via the feedback-o-tron
      Submitter. Issues are sent to their configured platforms
      (typically GitHub issues on rescript-lang/rescript).
      """,
      input_schema: %{
        type: "object",
        properties: %{},
        required: []
      },
      handler: &handle_submit_approved/1
    }
  end

  def handle_submit_approved(_params) do
    case BatchReviewer.submit_approved() do
      {:ok, results} ->
        success_count = Enum.count(results, fn r -> match?({:ok, _}, r) end)
        error_count = Enum.count(results, fn r -> match?({:error, _}, r) end)

        summary =
          "Submitted #{success_count} issues (#{error_count} errors).\n\n" <>
            (results
             |> Enum.map(fn
               {:ok, %{item_id: id, submission_id: sid}} ->
                 "- #{id}: submitted (#{sid})"

               {:error, %{item_id: id, reason: reason}} ->
                 "- #{id}: FAILED (#{inspect(reason)})"
             end)
             |> Enum.join("\n"))

        {:ok, [%{type: "text", text: summary}]}

      {:error, reason} ->
        {:error, "Failed to submit: #{inspect(reason)}"}
    end
  end

  # --- Helpers ---

  defp format_delta(delta) when is_float(delta) do
    cond do
      delta > 0 -> "+#{Float.round(delta, 3)}"
      delta < 0 -> "#{Float.round(delta, 3)}"
      true -> "0"
    end
  end

  defp format_delta(_), do: "0"
end

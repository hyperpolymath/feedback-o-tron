# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.MigrationObserver do
  @moduledoc """
  GenServer that orchestrates ReScript migration observation sessions.

  A migration session has three phases:
  1. `begin_observation/2` — takes a before-snapshot via panic-attack
  2. `log_event/2` — captures timestamped events during migration
  3. `end_observation/1` — takes an after-snapshot, computes diff, creates report

  Each session produces a `MigrationSession` struct that can be stored
  as a VeriSimDB hexad and queued for review.
  """

  use GenServer

  require Logger

  alias FeedbackATron.{VeriSimWriter, BatchReviewer}

  defstruct [
    :current_session,
    :sessions
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Begin a migration observation session.

  Calls `panic-attack migration-snapshot` on the target repo to capture
  the before state.
  """
  def begin_observation(repo_path, label, opts \\ []) do
    GenServer.call(__MODULE__, {:begin_observation, repo_path, label, opts}, :timer.minutes(5))
  end

  @doc """
  Log a timestamped event during an active migration session.

  Event types: :issue, :complication, :note, :decision, :benchmark
  """
  def log_event(event_type, description, opts \\ []) do
    GenServer.call(__MODULE__, {:log_event, event_type, description, opts})
  end

  @doc """
  End the current migration observation session.

  Takes an after-snapshot, computes the diff, generates a report,
  and queues discovered issues for review.
  """
  def end_observation(notes \\ nil) do
    GenServer.call(__MODULE__, {:end_observation, notes}, :timer.minutes(5))
  end

  @doc "Get the current session state"
  def current_session do
    GenServer.call(__MODULE__, :current_session)
  end

  @doc "List all completed sessions"
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      current_session: nil,
      sessions: []
    }

    Logger.info("[MigrationObserver] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:begin_observation, repo_path, label, opts}, _from, state) do
    if state.current_session do
      {:reply, {:error, :session_active}, state}
    else
      build_time = Keyword.get(opts, :build_time, false)
      bundle_size = Keyword.get(opts, :bundle_size, false)

      case take_snapshot(repo_path, "before-#{label}", build_time, bundle_size) do
        {:ok, before_snapshot} ->
          session = %{
            session_id: generate_session_id(),
            repo_path: repo_path,
            label: label,
            started_at: DateTime.utc_now(),
            ended_at: nil,
            before_snapshot: before_snapshot,
            after_snapshot: nil,
            events: [],
            diff: nil,
            notes: nil,
            build_time: build_time,
            bundle_size: bundle_size
          }

          Logger.info("[MigrationObserver] Session #{session.session_id} started for #{repo_path}")
          {:reply, {:ok, session.session_id}, %{state | current_session: session}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:log_event, event_type, description, opts}, _from, state) do
    case state.current_session do
      nil ->
        {:reply, {:error, :no_active_session}, state}

      session ->
        event = %{
          timestamp: DateTime.utc_now(),
          type: event_type,
          description: description,
          severity: Keyword.get(opts, :severity, :info),
          metadata: Keyword.get(opts, :metadata, %{})
        }

        updated_session = %{session | events: session.events ++ [event]}
        Logger.debug("[MigrationObserver] Event logged: #{event_type} - #{description}")
        {:reply, :ok, %{state | current_session: updated_session}}
    end
  end

  def handle_call({:end_observation, notes}, _from, state) do
    case state.current_session do
      nil ->
        {:reply, {:error, :no_active_session}, state}

      session ->
        label = "after-#{session.label}"

        case take_snapshot(session.repo_path, label, session.build_time, session.bundle_size) do
          {:ok, after_snapshot} ->
            diff = compute_diff(session.before_snapshot, after_snapshot)

            completed_session = %{
              session
              | ended_at: DateTime.utc_now(),
                after_snapshot: after_snapshot,
                diff: diff,
                notes: notes
            }

            # Store in VeriSimDB (async, non-blocking)
            spawn(fn -> VeriSimWriter.write_migration_session(completed_session) end)

            # Queue issues for review
            queue_issues_for_review(completed_session)

            Logger.info(
              "[MigrationObserver] Session #{session.session_id} completed " <>
                "(health delta: #{format_delta(diff)})"
            )

            new_state = %{
              state
              | current_session: nil,
                sessions: [completed_session | state.sessions]
            }

            {:reply, {:ok, completed_session}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:current_session, _from, state) do
    {:reply, state.current_session, state}
  end

  def handle_call(:list_sessions, _from, state) do
    {:reply, state.sessions, state}
  end

  # --- Private Helpers ---

  defp take_snapshot(repo_path, label, build_time, bundle_size) do
    args =
      ["migration-snapshot", repo_path, "--label", label] ++
        if(build_time, do: ["--build-time"], else: []) ++
        if(bundle_size, do: ["--bundle-size"], else: [])

    case System.cmd("panic-attack", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, snapshot} -> {:ok, snapshot}
          {:error, _} -> {:error, {:parse_error, "failed to parse panic-attack output"}}
        end

      {output, code} ->
        {:error, {:panic_attack_failed, code, output}}
    end
  end

  defp compute_diff(before_snapshot, after_snapshot) do
    before_deprecated = get_in(before_snapshot, ["migration_metrics", "deprecated_api_count"]) || 0
    after_deprecated = get_in(after_snapshot, ["migration_metrics", "deprecated_api_count"]) || 0
    before_modern = get_in(before_snapshot, ["migration_metrics", "modern_api_count"]) || 0
    after_modern = get_in(after_snapshot, ["migration_metrics", "modern_api_count"]) || 0
    before_health = get_in(before_snapshot, ["migration_metrics", "health_score"]) || 0.0
    after_health = get_in(after_snapshot, ["migration_metrics", "health_score"]) || 0.0

    %{
      health_delta: after_health - before_health,
      deprecated_delta: after_deprecated - before_deprecated,
      modern_delta: after_modern - before_modern,
      version_before: get_in(before_snapshot, ["migration_metrics", "version_bracket"]),
      version_after: get_in(after_snapshot, ["migration_metrics", "version_bracket"]),
      config_before: get_in(before_snapshot, ["migration_metrics", "config_format"]),
      config_after: get_in(after_snapshot, ["migration_metrics", "config_format"])
    }
  end

  defp queue_issues_for_review(session) do
    issues =
      session.events
      |> Enum.filter(fn event -> event.type == :issue end)
      |> Enum.map(fn event ->
        %{
          title: "[Migration] #{session.label}: #{event.description}",
          body: build_issue_body(session, event),
          repo: extract_repo_name(session.repo_path),
          source: :migration_observer,
          session_id: session.session_id,
          severity: event.severity
        }
      end)

    Enum.each(issues, fn issue ->
      BatchReviewer.enqueue(issue)
    end)
  end

  defp build_issue_body(session, event) do
    """
    ## Migration Issue

    **Session:** #{session.session_id}
    **Repo:** #{session.repo_path}
    **Label:** #{session.label}
    **Detected:** #{DateTime.to_iso8601(event.timestamp)}
    **Severity:** #{event.severity}

    ### Description

    #{event.description}

    ### Context

    - Version bracket: #{get_in(session.before_snapshot, ["migration_metrics", "version_bracket"])}
    - Health score (before): #{get_in(session.before_snapshot, ["migration_metrics", "health_score"])}
    - Deprecated APIs (before): #{get_in(session.before_snapshot, ["migration_metrics", "deprecated_api_count"])}

    ---
    _Generated by feedback-o-tron migration observer_
    """
  end

  defp extract_repo_name(path) do
    path
    |> String.split("/")
    |> List.last()
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp format_delta(%{health_delta: delta}) do
    cond do
      delta > 0 -> "+#{Float.round(delta, 2)}"
      delta < 0 -> "#{Float.round(delta, 2)}"
      true -> "0"
    end
  end

  defp format_delta(_), do: "unknown"
end

# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.VeriSimWriter do
  @moduledoc """
  VeriSimDB hexad writer for migration sessions.

  Builds octad hexads from migration session data following the pattern
  from verisimdb/elixir-orchestration/lib/verisim/hypatia/scan_ingester.ex.

  Each migration session becomes a hexad with:
  - Document: full markdown report
  - Temporal: session timestamps
  - Provenance: source chain (feedback-o-tron -> panic-attack -> repo)
  - Semantic: tags [rescript-migration, repo_name, version_bracket]
  - Graph: triples linking repo -> session -> snapshots
  """

  require Logger

  @hexad_dir "verisimdb-data/migration-hexads"

  @doc """
  Write a completed migration session as a VeriSimDB hexad.

  Falls back to file-based storage when the VeriSimDB API is unavailable.
  """
  def write_migration_session(session) do
    hexad = build_hexad(session)

    case write_hexad_file(hexad) do
      {:ok, path} ->
        Logger.info("[VeriSimWriter] Migration hexad written: #{path}")
        {:ok, hexad["hexad_id"]}

      {:error, reason} ->
        Logger.error("[VeriSimWriter] Failed to write hexad: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Build a VeriSimDB hexad from a migration session.
  """
  def build_hexad(session) do
    hexad_id = "migration-#{session.session_id}"
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    repo_name = extract_repo_name(session.repo_path)
    before_health = get_in(session.before_snapshot, ["migration_metrics", "health_score"]) || 0.0
    after_health = get_in(session.after_snapshot, ["migration_metrics", "health_score"]) || 0.0
    version_bracket = get_in(session.after_snapshot, ["migration_metrics", "version_bracket"]) || "unknown"

    %{
      "schema" => "verisimdb.hexad.v1",
      "hexad_id" => hexad_id,
      "created_at" => now,

      "document" => %{
        "title" => "Migration session: #{session.label} (#{repo_name})",
        "body" => build_document_body(session),
        "content_type" => "text/markdown"
      },

      "temporal" => %{
        "started_at" => DateTime.to_iso8601(session.started_at),
        "ended_at" =>
          if(session.ended_at, do: DateTime.to_iso8601(session.ended_at), else: nil),
        "duration_seconds" => compute_duration(session),
        "event_type" => "rescript_migration_session"
      },

      "provenance" => %{
        "source" => "feedback-o-tron",
        "actor" => "migration-observer",
        "operation" => "migration-session",
        "input_path" => session.repo_path,
        "chain" => [
          %{"tool" => "feedback-o-tron", "version" => "1.0.0"},
          %{"tool" => "panic-attack", "version" => "2.0.0"}
        ]
      },

      "semantic" => %{
        "types" => ["rescript_migration", "migration_session", "observatory"],
        "tags" => [
          "rescript-migration",
          "repo:#{repo_name}",
          "version:#{version_bracket}",
          "label:#{session.label}"
        ],
        "health_before" => before_health,
        "health_after" => after_health,
        "health_delta" => after_health - before_health,
        "event_count" => length(session.events),
        "issue_count" =>
          session.events
          |> Enum.count(fn e -> e.type == :issue end)
      },

      "graph" => %{
        "triples" => build_graph_triples(hexad_id, session)
      },

      "vector" => %{
        "text_for_embedding" => build_embedding_text(session),
        "dimensions" => nil
      }
    }
  end

  # --- Private Helpers ---

  defp build_document_body(session) do
    repo_name = extract_repo_name(session.repo_path)
    before_metrics = session.before_snapshot["migration_metrics"] || %{}
    after_metrics = session.after_snapshot["migration_metrics"] || %{}

    events_md =
      session.events
      |> Enum.map(fn event ->
        "- **#{event.type}** (#{event.severity}): #{event.description}"
      end)
      |> Enum.join("\n")

    """
    # Migration Session: #{session.label}

    **Repo:** #{repo_name}
    **Session ID:** #{session.session_id}
    **Started:** #{DateTime.to_iso8601(session.started_at)}
    **Ended:** #{if session.ended_at, do: DateTime.to_iso8601(session.ended_at), else: "in progress"}

    ## Before

    | Metric | Value |
    |--------|-------|
    | Health Score | #{before_metrics["health_score"] || "N/A"} |
    | Deprecated APIs | #{before_metrics["deprecated_api_count"] || "N/A"} |
    | Modern APIs | #{before_metrics["modern_api_count"] || "N/A"} |
    | Version | #{before_metrics["version_bracket"] || "N/A"} |
    | Config | #{before_metrics["config_format"] || "N/A"} |
    | Files | #{before_metrics["file_count"] || "N/A"} |

    ## After

    | Metric | Value |
    |--------|-------|
    | Health Score | #{after_metrics["health_score"] || "N/A"} |
    | Deprecated APIs | #{after_metrics["deprecated_api_count"] || "N/A"} |
    | Modern APIs | #{after_metrics["modern_api_count"] || "N/A"} |
    | Version | #{after_metrics["version_bracket"] || "N/A"} |
    | Config | #{after_metrics["config_format"] || "N/A"} |
    | Files | #{after_metrics["file_count"] || "N/A"} |

    ## Events

    #{events_md}

    #{if session.notes, do: "## Notes\n\n#{session.notes}", else: ""}
    """
  end

  defp build_graph_triples(hexad_id, session) do
    repo_name = extract_repo_name(session.repo_path)
    session_uri = "session:#{session.session_id}"
    repo_uri = "repo:#{repo_name}"

    base = [
      [repo_uri, "has_migration_session", session_uri],
      [session_uri, "has_label", "label:#{session.label}"],
      [session_uri, "has_hexad", "hexad:#{hexad_id}"]
    ]

    event_triples =
      session.events
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} ->
        event_uri = "#{session_uri}:event:#{idx}"
        [session_uri, "has_event", event_uri]
      end)

    base ++ event_triples
  end

  defp build_embedding_text(session) do
    repo_name = extract_repo_name(session.repo_path)
    version = get_in(session.after_snapshot, ["migration_metrics", "version_bracket"]) || ""

    event_text =
      session.events
      |> Enum.map(fn e -> "#{e.type}: #{e.description}" end)
      |> Enum.join(". ")

    "ReScript migration session for #{repo_name}. " <>
      "Label: #{session.label}. Version: #{version}. " <>
      "Events: #{event_text}"
  end

  defp compute_duration(session) do
    case session.ended_at do
      nil -> 0
      ended -> DateTime.diff(ended, session.started_at, :second)
    end
  end

  defp write_hexad_file(hexad) do
    dir = @hexad_dir
    File.mkdir_p!(dir)

    path = Path.join(dir, "#{hexad["hexad_id"]}.json")
    content = Jason.encode!(hexad, pretty: true)

    case File.write(path, content) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_repo_name(path) do
    path
    |> String.split("/")
    |> List.last()
  end
end

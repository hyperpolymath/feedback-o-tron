# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.HTTPIntake.Router do
  @moduledoc """
  Optional HTTP intake for the autonomous bug-reporting pipeline.

  This is the wire the boj gateway → `bug-filing-mcp` cartridge drives to reach the
  real engine (see `docs/AUTONOMOUS-BUG-PIPELINE.adoc`, contract C2 / D0 = new wrapping
  cartridge). It is a thin, localhost-only JSON adapter over the *same* `Submitter.submit/2`
  path used by the MCP `submit_feedback` tool — no separate submission logic, so audit
  logging, dedup, rate-limiting and dry-run all behave identically.

  Off by default; enabled via `FEEDBACK_A_TRON_HTTP` (see `FeedbackATron.Application`).

  ## Routes

  - `GET  /health`                    → `{"status":"ok"}`
  - `POST /api/v1/submit_feedback`    → body `{title, body, repo, platforms?, labels?, dry_run?, skip_dedupe?}`

  The request/response shapes intentionally match the MCP tool's `input_schema` so a
  cartridge can forward the same arguments unchanged.
  """

  use Plug.Router
  require Logger

  alias FeedbackATron.Submitter

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  get "/health" do
    send_json(conn, 200, %{status: "ok", service: "feedback-a-tron", intake: "http"})
  end

  post "/api/v1/submit_feedback" do
    try do
      case validate(conn.body_params) do
        {:ok, issue, opts} ->
          case Submitter.submit(issue, opts) do
            {:ok, submission_id, results} ->
              send_json(conn, 200, format_results(submission_id, results))

            {:error, reason} ->
              Logger.error("HTTP submit_feedback failed: #{inspect(reason)}")
              send_json(conn, 502, %{error: "submission_failed", detail: inspect(reason)})
          end

        {:error, missing} ->
          send_json(conn, 400, %{error: "missing_required_fields", fields: missing})
      end
    rescue
      exception ->
        Logger.error("HTTP submit_feedback exception: #{Exception.message(exception)}")
        send_json(conn, 500, %{error: "internal_error", detail: Exception.message(exception)})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # --- helpers ---------------------------------------------------------------

  # Mirrors FeedbackATron.MCP.Tools.SubmitFeedback: required [title, body, repo].
  defp validate(params) when is_map(params) do
    missing =
      ["title", "body", "repo"]
      |> Enum.filter(fn k -> blank?(Map.get(params, k)) end)

    if missing == [] do
      issue = %{
        title: params["title"],
        body: params["body"],
        repo: params["repo"]
      }

      opts = [
        platforms: parse_platforms(params["platforms"]),
        labels: params["labels"] || [],
        dry_run: params["dry_run"] || false,
        dedupe: not (params["skip_dedupe"] || false)
      ]

      {:ok, issue, opts}
    else
      {:error, missing}
    end
  end

  defp validate(_), do: {:error, ["title", "body", "repo"]}

  defp blank?(nil), do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  defp parse_platforms(nil), do: [:github]

  defp parse_platforms(platforms) when is_list(platforms) do
    platforms
    |> Enum.map(&platform_atom/1)
    |> Enum.filter(& &1)
    |> case do
      [] -> [:github]
      list -> list
    end
  end

  defp parse_platforms(_), do: [:github]

  defp platform_atom("github"), do: :github
  defp platform_atom("gitlab"), do: :gitlab
  defp platform_atom("bitbucket"), do: :bitbucket
  defp platform_atom("codeberg"), do: :codeberg
  defp platform_atom("bugzilla"), do: :bugzilla
  defp platform_atom("email"), do: :email
  defp platform_atom(_), do: nil

  defp format_results(submission_id, results) do
    formatted =
      Enum.map(results, fn
        {:ok, %{platform: platform, url: url}} ->
          %{platform: platform, status: "success", url: url}

        {:ok, %{platform: platform, status: :dry_run, would_submit: issue}} ->
          %{platform: platform, status: "dry_run", title: issue.title}

        {:error, %{platform: platform, error: error}} ->
          %{platform: platform, status: "error", error: inspect(error)}

        {:error, {:duplicate_found, similar}} ->
          %{status: "skipped", reason: "duplicate", similar_issues: similar}

        {:error, {:similar_found, matches}} ->
          %{status: "skipped", reason: "similar_found", similar_issues: matches}

        {:error, other} ->
          %{status: "error", error: inspect(other)}
      end)

    %{submission_id: submission_id, results: formatted, summary: summarize(formatted)}
  end

  defp summarize(results) do
    count = fn status -> Enum.count(results, &(Map.get(&1, :status) == status)) end

    "Submitted: #{count.("success")}, Errors: #{count.("error")}, " <>
      "Skipped: #{count.("skipped")}, Dry run: #{count.("dry_run")}"
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end

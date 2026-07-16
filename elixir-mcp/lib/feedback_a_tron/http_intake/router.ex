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

  - `GET  /health`                     → `{"status":"ok"}`
  - `POST /api/v1/submit_feedback`     → body `{title, body, repo, platforms?, labels?, dry_run?, skip_dedupe?, template?, template_data?}`
  - `POST /api/v1/research_feedback`   → body `{repo, title, body?, limit?, include_templates?}`
  - `POST /api/v1/synthesize_feedback` → body `{raw_feedback, repo, context?, system_state?, template?, network_probe?}`

  The request/response shapes intentionally match the MCP tools' `input_schema` so a
  cartridge can forward the same arguments unchanged.
  """

  use Plug.Router
  require Logger

  alias FeedbackATron.{Params, Submitter}
  alias FeedbackATron.Synthesis.{Research, Synthesizer}

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

            {:error, {:schema_violation, violations}} ->
              send_json(conn, 422, %{error: "schema_violation", violations: violations})

            {:error, {:template_unavailable, why}} ->
              send_json(conn, 502, %{error: "template_unavailable", detail: inspect(why)})

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

  post "/api/v1/research_feedback" do
    try do
      params = conn.body_params

      case missing_fields(params, ["repo", "title"]) do
        [] ->
          request = %{
            repo: params["repo"],
            title: params["title"],
            body: params["body"]
          }

          opts =
            []
            |> put_opt(:limit, params["limit"])
            |> put_opt(:include_templates, params["include_templates"])

          case Research.research(request, opts) do
            {:ok, result} ->
              send_json(conn, 200, result)

            {:error, reason} ->
              Logger.error("HTTP research_feedback failed: #{inspect(reason)}")
              send_json(conn, 502, %{error: "research_failed", detail: inspect(reason)})
          end

        missing ->
          send_json(conn, 400, %{error: "missing_required_fields", fields: missing})
      end
    rescue
      exception ->
        Logger.error("HTTP research_feedback exception: #{Exception.message(exception)}")
        send_json(conn, 500, %{error: "internal_error", detail: Exception.message(exception)})
    end
  end

  post "/api/v1/synthesize_feedback" do
    try do
      params = conn.body_params

      case missing_fields(params, ["raw_feedback", "repo"]) do
        [] ->
          request = %{
            raw_feedback: params["raw_feedback"],
            repo: params["repo"],
            context: params["context"] || %{},
            system_state: params["system_state"] || %{}
          }

          opts =
            []
            |> put_opt(:template, params["template"])
            |> put_opt(:network_probe, params["network_probe"])

          case Synthesizer.synthesize(request, opts) do
            {:ok, result} ->
              send_json(conn, 200, result)

            # A rejection is a successful response: the caller must learn the
            # stated reason. Rejected feedback is audit-logged, never filed.
            {:reject, rejection} ->
              send_json(conn, 200, %{rejected: true, reason: rejection.reason})

            {:error, reason} ->
              Logger.error("HTTP synthesize_feedback failed: #{inspect(reason)}")
              send_json(conn, 502, %{error: "synthesis_failed", detail: inspect(reason)})
          end

        missing ->
          send_json(conn, 400, %{error: "missing_required_fields", fields: missing})
      end
    rescue
      exception ->
        Logger.error("HTTP synthesize_feedback exception: #{Exception.message(exception)}")
        send_json(conn, 500, %{error: "internal_error", detail: Exception.message(exception)})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # --- helpers ---------------------------------------------------------------

  # Mirrors FeedbackATron.MCP.Tools.SubmitFeedback: required [title, body, repo].
  defp validate(params) when is_map(params) do
    case missing_fields(params, ["title", "body", "repo"]) do
      [] ->
        issue = %{
          title: params["title"],
          body: params["body"],
          repo: params["repo"],
          template: params["template"],
          template_data: params["template_data"]
        }

        opts = [
          platforms: Params.parse_platforms(params["platforms"]),
          labels: params["labels"] || [],
          dry_run: params["dry_run"] || false,
          dedupe: not (params["skip_dedupe"] || false)
        ]

        {:ok, issue, opts}

      missing ->
        {:error, missing}
    end
  end

  defp validate(_), do: {:error, ["title", "body", "repo"]}

  defp missing_fields(params, required) when is_map(params) do
    Enum.filter(required, fn k -> blank?(Map.get(params, k)) end)
  end

  defp missing_fields(_params, required), do: required

  defp blank?(nil), do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

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

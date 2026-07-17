# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.MCP.Tools.SynthesizeFeedback do
  @moduledoc """
  MCP tool for shaping raw feedback into a receiver-ready report.

  The gate is usefulness, not tone: zero-signal abuse is rejected (with the
  reason stated and audit-logged, never filed); mixed content has its
  actionable core salvaged; genuine-but-thin feedback comes back with
  open_questions rather than being silently discarded.
  """

  use ElixirMcpServer.Tool

  alias FeedbackATron.Synthesis.Synthesizer
  require Logger

  @impl true
  def name, do: "synthesize_feedback"

  @impl true
  def description do
    """
    Shape raw feedback into a report that fits the target repo's issue template.

    Classifies intent (bug/feature/question/docs/praise), salvages the
    actionable core from mixed content, hydrates the repo's issue-form fields
    from the provided context and system state, and returns a draft plus
    open_questions for anything only the user can answer. Zero-signal abuse
    is rejected — the result carries {"rejected": true, "reason": ...}; it is
    audit-logged and never filed.

    Recommended interactive loop:
    1. research_feedback — check for duplicates and discover the repo's templates
    2. synthesize_feedback — shape the raw feedback into a template-fitting draft
    3. Resolve any open_questions with your user
    4. submit_feedback — file the report with template + template_data
    """
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        raw_feedback: %{
          type: "string",
          description: "The raw feedback/crash text to shape into a report"
        },
        repo: %{
          type: "string",
          description: "Target repository (owner/repo)"
        },
        context: %{
          type: "object",
          description: "Caller-provided context: title, version, expected, trajectory, logs"
        },
        system_state: %{
          type: "object",
          description: "Caller-provided environment facts (OS, runtime versions)"
        },
        template: %{
          type: "string",
          description: "Force a specific template file (e.g. bug.yml)"
        },
        network_probe: %{
          type: "boolean",
          description:
            "Run NetworkVerifier preflight when the report looks network-related (default false)"
        }
      },
      required: ["raw_feedback", "repo"]
    }
  end

  @impl true
  def execute(params, _context) do
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
        {:ok, [%{type: "text", text: Jason.encode!(result)}]}

      # A rejection is a successful tool result: the caller must learn the
      # stated reason. Rejected feedback is audit-logged and never filed.
      {:reject, rejection} ->
        {:ok, [%{type: "text", text: Jason.encode!(%{rejected: true, reason: rejection.reason})}]}

      {:error, reason} ->
        Logger.error("MCP synthesize_feedback failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    exception ->
      Logger.error("MCP synthesize_feedback exception: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end

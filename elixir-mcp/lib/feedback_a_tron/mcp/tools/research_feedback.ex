# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.MCP.Tools.ResearchFeedback do
  @moduledoc """
  MCP tool for researching feedback before it is filed.

  Checks the target forge for existing similar issues, consults the local
  submission history, and fetches the repo's issue-form templates so the
  eventual report can be shaped to fit the receiver.
  """

  use ElixirMcpServer.Tool

  alias FeedbackATron.Synthesis.Research
  require Logger

  @impl true
  def name, do: "research_feedback"

  @impl true
  def description do
    """
    Research a piece of feedback before filing it.

    Searches the target forge for existing similar issues, checks the local
    submission history for duplicates, and (by default) fetches the repo's
    issue-form templates so the eventual report can be shaped to fit.

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
        repo: %{
          type: "string",
          description: "Target repository (owner/repo)"
        },
        title: %{
          type: "string",
          description: "Working title / one-line summary of the feedback"
        },
        body: %{
          type: "string",
          description: "Optional draft body to improve similarity matching"
        },
        limit: %{
          type: "integer",
          description: "Max forge matches to return (default 5, max 20)"
        },
        include_templates: %{
          type: "boolean",
          description: "Also fetch the repo's issue-form templates (default true)"
        }
      },
      required: ["repo", "title"]
    }
  end

  @impl true
  def execute(params, _context) do
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
        {:ok, [%{type: "text", text: Jason.encode!(result)}]}

      {:error, reason} ->
        Logger.error("MCP research_feedback failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    exception ->
      Logger.error("MCP research_feedback exception: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end

defmodule FeedbackATron.MCP.Tools.SubmitFeedback do
  @moduledoc """
  MCP tool for submitting feedback/issues from Claude Code.

  This allows Claude to automatically submit issues, proposals,
  and feedback to configured platforms.
  """

  @behaviour FeedbackATron.MCP.Tool

  alias FeedbackATron.Submitter

  @impl true
  def name, do: "submit_feedback"

  @impl true
  def description do
    """
    Submit feedback, bug reports, or proposals to configured platforms.

    Supports GitHub, GitLab, Bitbucket, Codeberg, and email.
    Can submit to multiple platforms simultaneously.
    Includes deduplication to avoid creating duplicate issues.
    """
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        title: %{
          type: "string",
          description: "Issue/feedback title"
        },
        body: %{
          type: "string",
          description: "Issue/feedback body (markdown supported)"
        },
        repo: %{
          type: "string",
          description: "Target repository (owner/repo format)"
        },
        platforms: %{
          type: "array",
          items: %{
            type: "string",
            enum: ["github", "gitlab", "bitbucket", "codeberg", "email"]
          },
          description: "Platforms to submit to (default: github)"
        },
        labels: %{
          type: "array",
          items: %{type: "string"},
          description: "Labels to apply (platform-dependent)"
        },
        dry_run: %{
          type: "boolean",
          description: "If true, show what would be submitted without actually submitting"
        },
        skip_dedupe: %{
          type: "boolean",
          description: "If true, skip duplicate checking"
        }
      },
      required: ["title", "body", "repo"]
    }
  end

  @impl true
  def call(params) do
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

    case Submitter.submit(issue, opts) do
      {:ok, submission_id, results} ->
        format_results(submission_id, results)
      {:error, reason} ->
        %{error: inspect(reason)}
    end
  end

  defp parse_platforms(nil), do: [:github]
  defp parse_platforms(platforms) when is_list(platforms) do
    platforms
    |> Enum.map(&String.to_existing_atom/1)
    |> Enum.filter(&(&1 in [:github, :gitlab, :bitbucket, :codeberg, :email]))
  end

  defp format_results(submission_id, results) do
    formatted = Enum.map(results, fn
      {:ok, %{platform: platform, url: url}} ->
        %{platform: platform, status: "success", url: url}
      {:ok, %{platform: platform, status: :dry_run, would_submit: issue}} ->
        %{platform: platform, status: "dry_run", title: issue.title}
      {:error, %{platform: platform, error: error}} ->
        %{platform: platform, status: "error", error: inspect(error)}
      {:error, {:duplicate_found, similar}} ->
        %{status: "skipped", reason: "duplicate", similar_issues: similar}
    end)

    %{
      submission_id: submission_id,
      results: formatted,
      summary: summarize(formatted)
    }
  end

  defp summarize(results) do
    success = Enum.count(results, &(&1.status == "success"))
    errors = Enum.count(results, &(&1.status == "error"))
    skipped = Enum.count(results, &(&1.status == "skipped"))
    dry_run = Enum.count(results, &(&1.status == "dry_run"))

    "Submitted: #{success}, Errors: #{errors}, Skipped: #{skipped}, Dry run: #{dry_run}"
  end
end

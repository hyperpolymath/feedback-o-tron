# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.GitLab do
  @moduledoc """
  GitLab Issues channel — HTTPS only.
  Wraps existing Submitter.do_submit(:gitlab, ...) logic via Channel behaviour.
  """

  @behaviour FeedbackATron.Channel

  @impl true
  def platform, do: :gitlab

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    if cred[:token], do: :ok, else: {:error, "GitLab token required"}
  end

  @impl true
  def submit(issue, cred, opts) do
    repo = issue.repo || opts[:repo]
    labels = Keyword.get(opts, :labels, []) |> Enum.join(",")

    args = [
      "issue", "create",
      "--repo", repo,
      "--title", issue.title,
      "--description", issue.body,
      "--label", labels
    ]

    case System.cmd("glab", args, env: [{"GITLAB_TOKEN", cred.token}]) do
      {url, 0} -> {:ok, %{platform: :gitlab, url: String.trim(url)}}
      {error, _} -> {:error, %{platform: :gitlab, error: error}}
    end
  end
end

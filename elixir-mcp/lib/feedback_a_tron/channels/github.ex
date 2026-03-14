# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.GitHub do
  @moduledoc """
  GitHub Issues channel — HTTPS only.
  Wraps existing Submitter.do_submit(:github, ...) logic via Channel behaviour.
  """

  @behaviour FeedbackATron.Channel

  @impl true
  def platform, do: :github

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    if cred[:token], do: :ok, else: {:error, "GitHub token required"}
  end

  @impl true
  def submit(issue, cred, opts) do
    repo = issue.repo || opts[:repo]
    labels = Keyword.get(opts, :labels, [])
    label_args = Enum.flat_map(labels, &["--label", &1])

    args =
      ["issue", "create", "--repo", repo, "--title", issue.title, "--body", issue.body] ++
        label_args

    case System.cmd("gh", args, env: [{"GH_TOKEN", cred.token}]) do
      {url, 0} -> {:ok, %{platform: :github, url: String.trim(url)}}
      {error, _} -> {:error, %{platform: :github, error: error}}
    end
  end
end

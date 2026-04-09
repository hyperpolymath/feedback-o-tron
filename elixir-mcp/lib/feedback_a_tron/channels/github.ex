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
      {url, 0} ->
        {:ok, %{platform: :github, url: String.trim(url)}}

      {error, code} ->
        {:error, classify_gh_error(:github, error, code)}
    end
  end

  defp classify_gh_error(platform, output, _code) do
    cond do
      String.contains?(output, "401") or String.contains?(output, "auth") ->
        %FeedbackATron.Error.AuthenticationError{platform: platform, reason: "token rejected"}

      String.contains?(output, "403") or String.contains?(output, "rate limit") ->
        %FeedbackATron.Error.RateLimitError{platform: platform, resets_at: nil, remaining: 0}

      String.contains?(output, "422") or String.contains?(output, "validation") ->
        %FeedbackATron.Error.ValidationError{field: "issue", reason: String.trim(output)}

      true ->
        %FeedbackATron.Error.PlatformError{platform: platform, status: nil, body: String.trim(output)}
    end
  end
end

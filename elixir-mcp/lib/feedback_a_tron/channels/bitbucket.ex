# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Bitbucket do
  @moduledoc """
  Bitbucket Issues channel — HTTPS only.
  Wraps existing Submitter.do_submit(:bitbucket, ...) logic via Channel behaviour.
  """

  @behaviour FeedbackATron.Channel

  @impl true
  def platform, do: :bitbucket

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    if cred[:token], do: :ok, else: {:error, "Bitbucket token required"}
  end

  @impl true
  def submit(issue, cred, _opts) do
    url = "https://api.bitbucket.org/2.0/repositories/#{issue.repo}/issues"

    body = %{
      title: issue.title,
      content: %{raw: issue.body},
      priority: "major",
      kind: "enhancement"
    }

    headers = [
      {"Authorization", "Bearer #{cred.token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok, %{platform: :bitbucket, url: resp["links"]["html"]["href"]}}

      {:ok, %{status: 401, body: _error}} ->
        {:error, %FeedbackATron.Error.AuthenticationError{platform: :bitbucket, reason: "token rejected"}}

      {:ok, %{status: 429, body: _error}} ->
        {:error, %FeedbackATron.Error.RateLimitError{platform: :bitbucket, resets_at: nil, remaining: 0}}

      {:ok, %{status: status, body: error}} when status >= 400 and status < 500 ->
        {:error, %FeedbackATron.Error.ValidationError{field: "issue", reason: inspect(error)}}

      {:ok, %{status: status, body: error}} ->
        {:error, %FeedbackATron.Error.PlatformError{platform: :bitbucket, status: status, body: inspect(error)}}

      {:error, reason} ->
        {:error, %FeedbackATron.Error.NetworkError{platform: :bitbucket, reason: inspect(reason), url: url}}
    end
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Bugzilla do
  @moduledoc """
  Bugzilla channel — HTTPS only (REST API v1).
  """

  @behaviour FeedbackATron.Channel

  @impl true
  def platform, do: :bugzilla

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    if cred[:token] || (cred[:username] && cred[:password]),
      do: :ok,
      else: {:error, "Bugzilla API key or username/password required"}
  end

  @impl true
  def submit(issue, cred, opts) do
    base_url = opts[:bugzilla_url] || cred[:base_url] || "https://bugzilla.redhat.com"
    product = issue.repo
    component = opts[:component] || "distribution"
    version = opts[:version] || "rawhide"

    body = %{
      product: product,
      component: component,
      version: version,
      summary: issue.title,
      description: issue.body,
      op_sys: "Linux",
      platform: "x86_64",
      severity: opts[:severity] || "medium"
    }

    headers = [
      {"Authorization", "Bearer #{cred[:token]}"},
      {"Content-Type", "application/json"}
    ]

    url = "#{base_url}/rest/bug"

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: resp}} when is_map(resp) ->
        bug_id = resp["id"]
        {:ok, %{platform: :bugzilla, url: "#{base_url}/show_bug.cgi?id=#{bug_id}", bug_id: bug_id}}

      {:ok, %{status: 401, body: _error}} ->
        {:error, %FeedbackATron.Error.AuthenticationError{platform: :bugzilla, reason: "API key rejected"}}

      {:ok, %{status: 429, body: _error}} ->
        {:error, %FeedbackATron.Error.RateLimitError{platform: :bugzilla, resets_at: nil, remaining: 0}}

      {:ok, %{status: status, body: error}} when status >= 400 and status < 500 ->
        {:error, %FeedbackATron.Error.ValidationError{field: "bug", reason: inspect(error)}}

      {:ok, %{status: status, body: error}} ->
        {:error, %FeedbackATron.Error.PlatformError{platform: :bugzilla, status: status, body: inspect(error)}}

      {:error, reason} ->
        {:error, %FeedbackATron.Error.NetworkError{platform: :bugzilla, reason: inspect(reason), url: url}}
    end
  end
end

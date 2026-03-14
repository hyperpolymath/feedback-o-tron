# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Codeberg do
  @moduledoc """
  Codeberg Issues channel — HTTPS only (Gitea-compatible API).
  """

  @behaviour FeedbackATron.Channel

  @impl true
  def platform, do: :codeberg

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    if cred[:token], do: :ok, else: {:error, "Codeberg token required"}
  end

  @impl true
  def submit(issue, cred, _opts) do
    url = "https://codeberg.org/api/v1/repos/#{issue.repo}/issues"

    body = %{title: issue.title, body: issue.body}

    headers = [
      {"Authorization", "token #{cred.token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok, %{platform: :codeberg, url: resp["html_url"]}}

      {:ok, %{status: status, body: error}} ->
        {:error, %{platform: :codeberg, status: status, error: error}}

      {:error, reason} ->
        {:error, %{platform: :codeberg, error: reason}}
    end
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Discourse do
  @moduledoc """
  Discourse forum channel — HTTPS only.

  Creates topics in Discourse forums via the REST API.
  Supports API key and user API key authentication.

  DNS resolution via DoH/DoT exclusively (see SecureDNS).
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @impl true
  def platform, do: :discourse

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:base_url]) -> {:error, "Discourse base URL required (e.g. https://forum.example.com)"}
      not String.starts_with?(cred[:base_url] || "", "https://") -> {:error, "Discourse URL must be HTTPS"}
      is_nil(cred[:api_key]) -> {:error, "Discourse API key required"}
      is_nil(cred[:api_username]) -> {:error, "Discourse API username required"}
      true -> :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    base_url = String.trim_trailing(cred.base_url, "/")
    category_id = opts[:category_id] || cred[:default_category_id]
    tags = opts[:tags] || []

    # Extract hostname for secure DNS resolution
    %URI{host: hostname} = URI.parse(base_url)

    with {:ok, _ips} <- SecureDNS.resolve(hostname) do
      body = %{
        title: issue.title,
        raw: issue.body,
        category: category_id
      }

      body = if tags != [], do: Map.put(body, :tags, tags), else: body

      headers = [
        {"Api-Key", cred.api_key},
        {"Api-Username", cred.api_username},
        {"Content-Type", "application/json"}
      ]

      url = "#{base_url}/posts.json"

      case Req.post(url, json: body, headers: headers, receive_timeout: 15_000) do
        {:ok, %{status: 200, body: resp}} ->
          topic_id = resp["topic_id"]
          topic_slug = resp["topic_slug"] || "topic"
          {:ok, %{platform: :discourse, url: "#{base_url}/t/#{topic_slug}/#{topic_id}"}}

        {:ok, %{status: status, body: resp}} ->
          errors = extract_errors(resp)
          Logger.error("Discourse API error #{status}: #{inspect(errors)}")
          {:error, %{platform: :discourse, status: status, error: errors}}

        {:error, reason} ->
          {:error, %{platform: :discourse, error: reason}}
      end
    else
      {:error, reason} ->
        {:error, %{platform: :discourse, error: {:dns_failed, reason}}}
    end
  end

  defp extract_errors(%{"errors" => errors}) when is_list(errors), do: Enum.join(errors, "; ")
  defp extract_errors(%{"error_type" => type}), do: type
  defp extract_errors(other), do: inspect(other)
end

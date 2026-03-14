# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Jira do
  @moduledoc """
  Jira channel — HTTPS only.

  Creates issues in Jira Cloud or Server via REST API v2/v3.
  Supports API token (Cloud) and personal access token (Server) authentication.

  DNS resolution via DoH/DoT exclusively (see SecureDNS).
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @impl true
  def platform, do: :jira

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:base_url]) ->
        {:error, "Jira base URL required (e.g. https://yourorg.atlassian.net)"}

      not String.starts_with?(cred[:base_url] || "", "https://") ->
        {:error, "Jira URL must be HTTPS"}

      is_nil(cred[:token]) and is_nil(cred[:api_token]) ->
        {:error, "Jira API token required"}

      is_nil(cred[:project_key]) ->
        {:error, "Jira project key required (e.g. PROJ)"}

      true ->
        :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    base_url = String.trim_trailing(cred.base_url, "/")
    %URI{host: hostname} = URI.parse(base_url)

    with {:ok, _ips} <- SecureDNS.resolve(hostname) do
      project_key = cred.project_key
      issue_type = opts[:issue_type] || cred[:default_issue_type] || "Task"
      priority = opts[:priority] || cred[:default_priority]
      labels = opts[:labels] || []
      components = opts[:components] || []

      # Build Jira issue fields
      fields = %{
        project: %{key: project_key},
        summary: issue.title,
        description: format_description(issue.body, cred),
        issuetype: %{name: issue_type}
      }

      fields = if priority, do: Map.put(fields, :priority, %{name: priority}), else: fields
      fields = if labels != [], do: Map.put(fields, :labels, labels), else: fields

      fields =
        if components != [],
          do: Map.put(fields, :components, Enum.map(components, &%{name: &1})),
          else: fields

      body = %{fields: fields}

      headers = auth_headers(cred)

      url = "#{base_url}/rest/api/2/issue"

      case Req.post(url, json: body, headers: headers, receive_timeout: 15_000) do
        {:ok, %{status: 201, body: resp}} ->
          issue_key = resp["key"]
          {:ok, %{
            platform: :jira,
            url: "#{base_url}/browse/#{issue_key}",
            issue_key: issue_key
          }}

        {:ok, %{status: status, body: %{"errors" => errors}}} ->
          {:error, %{platform: :jira, status: status, error: errors}}

        {:ok, %{status: status, body: error}} ->
          {:error, %{platform: :jira, status: status, error: error}}

        {:error, reason} ->
          {:error, %{platform: :jira, error: reason}}
      end
    end
  end

  # Jira Cloud uses email:api_token Basic auth
  # Jira Server uses Bearer token
  defp auth_headers(cred) do
    base = [{"Content-Type", "application/json"}]

    if cred[:email] do
      # Jira Cloud: Basic auth with email:api_token
      token = cred[:api_token] || cred[:token]
      encoded = Base.encode64("#{cred.email}:#{token}")
      [{"Authorization", "Basic #{encoded}"} | base]
    else
      # Jira Server: Bearer token
      token = cred[:token] || cred[:api_token]
      [{"Authorization", "Bearer #{token}"} | base]
    end
  end

  # Jira v3 API uses Atlassian Document Format, v2 uses plaintext/wiki markup
  defp format_description(body, cred) do
    if cred[:api_version] == "3" do
      # ADF format for Jira Cloud v3
      %{
        type: "doc",
        version: 1,
        content: [
          %{
            type: "paragraph",
            content: [
              %{type: "text", text: body}
            ]
          }
        ]
      }
    else
      # Plaintext for v2
      body
    end
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.SourceHut do
  @moduledoc """
  SourceHut (sr.ht) channel — HTTPS only.

  Creates tickets on todo.sr.ht via the GraphQL API.
  Supports personal access token authentication.

  DNS resolution via DoH/DoT exclusively (see SecureDNS).
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @api_base "https://todo.sr.ht"

  @impl true
  def platform, do: :sourcehut

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:token]) -> {:error, "SourceHut personal access token required"}
      is_nil(cred[:tracker]) -> {:error, "SourceHut tracker name required (e.g. ~user/tracker-name)"}
      true -> :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    tracker = cred.tracker
    api_base = cred[:api_base] || @api_base
    %URI{host: hostname} = URI.parse(api_base)

    with {:ok, _ips} <- SecureDNS.resolve(hostname) do
      # SourceHut uses GraphQL for todo.sr.ht
      query = """
      mutation SubmitTicket($trackerId: Int!, $input: SubmitTicketInput!) {
        submitTicket(trackerId: $trackerId, input: $input) {
          id
          ref
          subject
        }
      }
      """

      # First, resolve tracker name to ID via REST API
      case resolve_tracker_id(api_base, tracker, cred.token) do
        {:ok, tracker_id} ->
          variables = %{
            trackerId: tracker_id,
            input: %{
              subject: issue.title,
              body: issue.body
            }
          }

          labels = opts[:labels] || cred[:default_labels] || []
          variables = if labels != [] do
            put_in(variables, [:input, :labels], labels)
          else
            variables
          end

          headers = [
            {"Authorization", "Bearer #{cred.token}"},
            {"Content-Type", "application/json"}
          ]

          gql_url = "#{api_base}/query"
          body = %{query: query, variables: variables}

          case Req.post(gql_url, json: body, headers: headers, receive_timeout: 15_000) do
            {:ok, %{status: 200, body: %{"data" => %{"submitTicket" => ticket}}}} ->
              ticket_ref = ticket["ref"]
              {:ok, %{
                platform: :sourcehut,
                url: "#{api_base}/#{tracker}/#{ticket_ref}",
                ticket_id: ticket["id"]
              }}

            {:ok, %{status: 200, body: %{"errors" => errors}}} ->
              {:error, %{platform: :sourcehut, error: errors}}

            {:ok, %{status: status, body: error}} ->
              {:error, %{platform: :sourcehut, status: status, error: error}}

            {:error, reason} ->
              {:error, %{platform: :sourcehut, error: reason}}
          end

        {:error, reason} ->
          {:error, %{platform: :sourcehut, error: reason}}
      end
    end
  end

  defp resolve_tracker_id(api_base, tracker, token) do
    # REST API to get tracker details
    url = "#{api_base}/api/trackers/#{URI.encode(tracker)}"

    headers = [
      {"Authorization", "Bearer #{token}"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"id" => id}}} ->
        {:ok, id}

      {:ok, %{status: status, body: error}} ->
        {:error, {:tracker_not_found, tracker, status, error}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

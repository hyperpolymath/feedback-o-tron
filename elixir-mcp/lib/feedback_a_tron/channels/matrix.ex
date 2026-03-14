# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Matrix do
  @moduledoc """
  Matrix channel — HTTPS (Matrix Client-Server API, encrypted transport).

  Sends feedback as messages to Matrix rooms.
  Supports access token authentication and .well-known server discovery.

  Matrix protocol enforces TLS at the transport layer.
  DNS resolution via DoH/DoT exclusively (see SecureDNS).

  Note: E2EE (end-to-end encryption) for individual messages requires
  libolm/vodozemac bindings — this module handles transport-layer encryption
  via HTTPS and can post to unencrypted rooms. For E2EE rooms, use a
  Matrix SDK with Olm session management.
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @impl true
  def platform, do: :matrix

  @impl true
  def transport, do: :matrix

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:homeserver]) ->
        {:error, "Matrix homeserver URL required (e.g. https://matrix.org)"}

      not String.starts_with?(cred[:homeserver] || "", "https://") ->
        {:error, "Matrix homeserver must be HTTPS"}

      is_nil(cred[:access_token]) ->
        {:error, "Matrix access token required"}

      is_nil(cred[:room_id]) ->
        {:error, "Matrix room ID required (e.g. !abc123:matrix.org)"}

      true ->
        :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    homeserver = String.trim_trailing(cred.homeserver, "/")
    room_id = cred.room_id
    %URI{host: hostname} = URI.parse(homeserver)

    with {:ok, _ips} <- SecureDNS.resolve(hostname) do
      txn_id = generate_txn_id()
      format = opts[:format] || :markdown

      body =
        case format do
          :markdown ->
            %{
              msgtype: "m.text",
              body: "**#{issue.title}**\n\n#{issue.body}",
              format: "org.matrix.custom.html",
              formatted_body: "<h3>#{html_escape(issue.title)}</h3>\n#{markdown_to_html(issue.body)}"
            }

          :plain ->
            %{
              msgtype: "m.text",
              body: "#{issue.title}\n\n#{issue.body}"
            }
        end

      # Matrix notice type for bot messages (less intrusive)
      body =
        if opts[:notice] do
          Map.put(body, :msgtype, "m.notice")
        else
          body
        end

      encoded_room = URI.encode(room_id)
      url = "#{homeserver}/_matrix/client/v3/rooms/#{encoded_room}/send/m.room.message/#{txn_id}"

      headers = [
        {"Authorization", "Bearer #{cred.access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.put(url, json: body, headers: headers, receive_timeout: 15_000) do
        {:ok, %{status: 200, body: %{"event_id" => event_id}}} ->
          {:ok, %{
            platform: :matrix,
            url: "https://matrix.to/#/#{room_id}/#{event_id}",
            event_id: event_id
          }}

        {:ok, %{status: status, body: error}} ->
          {:error, %{platform: :matrix, status: status, error: error}}

        {:error, reason} ->
          {:error, %{platform: :matrix, error: reason}}
      end
    end
  end

  defp generate_txn_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # Minimal markdown-to-HTML for Matrix formatted_body
  defp markdown_to_html(text) do
    text
    |> html_escape()
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/`(.+?)`/, "<code>\\1</code>")
    |> String.replace(~r/\n\n/, "<br/><br/>")
    |> String.replace(~r/\n/, "<br/>")
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.NNTP do
  @moduledoc """
  NNTP (Usenet) channel — NNTPS only (port 563, implicit TLS).

  Posts feedback as Usenet articles to configured newsgroups.
  Supports AUTHINFO USER/PASS authentication per RFC 4643.

  No plaintext NNTP (port 119) is ever used.
  DNS resolution via DoH/DoT exclusively (see SecureDNS).
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @nntps_port 563
  @connect_timeout 10_000
  @recv_timeout 15_000

  @impl true
  def platform, do: :nntp

  @impl true
  def transport, do: :nntps

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:server]) -> {:error, "NNTP server hostname required"}
      is_nil(cred[:newsgroup]) -> {:error, "NNTP newsgroup required"}
      true -> :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    server = cred.server
    newsgroup = cred[:newsgroup] || opts[:newsgroup]
    port = cred[:port] || @nntps_port
    from = cred[:from] || "feedback-a-tron@localhost"

    with {:ok, ips} <- SecureDNS.resolve(server),
         ip <- List.first(ips),
         {:ok, socket} <- connect_nntps(ip, port, server),
         :ok <- read_greeting(socket),
         :ok <- maybe_auth(socket, cred),
         :ok <- post_article(socket, newsgroup, from, issue) do
      :ssl.send(socket, "QUIT\r\n")
      :ssl.close(socket)
      {:ok, %{platform: :nntp, url: "nntp://#{server}/#{newsgroup}"}}
    else
      {:error, reason} ->
        Logger.error("NNTPS submission failed: #{inspect(reason)}")
        {:error, %{platform: :nntp, error: reason}}
    end
  end

  # Connect via implicit TLS (port 563)
  defp connect_nntps(ip, port, server_hostname) do
    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      server_name_indication: String.to_charlist(server_hostname),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    ip_charlist = :inet.ntoa(ip)
    :ssl.connect(ip_charlist, port, ssl_opts, @connect_timeout)
  end

  defp read_greeting(socket) do
    case :ssl.recv(socket, 0, @recv_timeout) do
      {:ok, data} ->
        line = IO.iodata_to_binary(data)

        if String.starts_with?(line, "200") or String.starts_with?(line, "201") do
          :ok
        else
          {:error, {:nntp_greeting_rejected, line}}
        end

      {:error, reason} ->
        {:error, {:nntp_recv_error, reason}}
    end
  end

  defp maybe_auth(socket, cred) do
    case {cred[:username], cred[:password]} do
      {nil, _} ->
        :ok

      {username, password} ->
        with :ok <- send_cmd(socket, "AUTHINFO USER #{username}"),
             {:ok, "381" <> _} <- recv_line(socket),
             :ok <- send_cmd(socket, "AUTHINFO PASS #{password}"),
             {:ok, "281" <> _} <- recv_line(socket) do
          :ok
        else
          {:ok, response} -> {:error, {:nntp_auth_failed, response}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp post_article(socket, newsgroup, from, issue) do
    with :ok <- send_cmd(socket, "POST"),
         {:ok, "340" <> _} <- recv_line(socket) do
      # Build RFC 5536 compliant Usenet article
      message_id = generate_message_id()
      date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S +0000")

      article = [
        "From: #{from}\r\n",
        "Newsgroups: #{newsgroup}\r\n",
        "Subject: #{issue.title}\r\n",
        "Date: #{date}\r\n",
        "Message-ID: #{message_id}\r\n",
        "User-Agent: FeedbackATron/1.0\r\n",
        "\r\n",
        escape_body(issue.body),
        "\r\n.\r\n"
      ]

      :ssl.send(socket, article)

      case recv_line(socket) do
        {:ok, "240" <> _} -> :ok
        {:ok, response} -> {:error, {:nntp_post_rejected, response}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, response} -> {:error, {:nntp_post_not_allowed, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_cmd(socket, cmd) do
    :ssl.send(socket, cmd <> "\r\n")
  end

  defp recv_line(socket) do
    case :ssl.recv(socket, 0, @recv_timeout) do
      {:ok, data} -> {:ok, String.trim(IO.iodata_to_binary(data))}
      {:error, reason} -> {:error, {:nntp_recv_error, reason}}
    end
  end

  # Dot-stuffing per RFC 3977 Section 3.1.1
  defp escape_body(body) do
    body
    |> String.replace("\r\n.", "\r\n..")
    |> String.replace(~r/\n\./, "\n..")
  end

  defp generate_message_id do
    rand = :crypto.strong_rand_bytes(12) |> Base.hex_encode32(case: :lower, padding: false)
    "<#{rand}@feedback-a-tron>"
  end
end

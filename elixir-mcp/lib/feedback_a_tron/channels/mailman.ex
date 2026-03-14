# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Mailman do
  @moduledoc """
  Mailman (GNU Mailman / HyperKitty) mailing list channel.

  Two submission modes:
  1. **SMTPS** (port 465, implicit TLS) — send email directly to list address
  2. **HTTPS** — HyperKitty REST API for Mailman 3 instances

  No plaintext SMTP (port 25) or STARTTLS (port 587) is used.
  DNS resolution via DoH/DoT exclusively (see SecureDNS).
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @smtps_port 465
  @connect_timeout 10_000

  @impl true
  def platform, do: :mailman

  @impl true
  def transport, do: :smtps

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:list_address]) and is_nil(cred[:hyperkitty_url]) ->
        {:error, "Either list_address (for SMTPS) or hyperkitty_url (for REST API) required"}

      not is_nil(cred[:list_address]) and is_nil(cred[:smtp_server]) ->
        {:error, "SMTP server required for email-based submission"}

      not is_nil(cred[:hyperkitty_url]) and
          not String.starts_with?(cred[:hyperkitty_url] || "", "https://") ->
        {:error, "HyperKitty URL must be HTTPS"}

      true ->
        :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    if cred[:hyperkitty_url] do
      submit_hyperkitty(issue, cred, opts)
    else
      submit_smtps(issue, cred, opts)
    end
  end

  # Submit via HyperKitty REST API (Mailman 3)
  defp submit_hyperkitty(issue, cred, _opts) do
    base_url = String.trim_trailing(cred.hyperkitty_url, "/")
    %URI{host: hostname} = URI.parse(base_url)

    with {:ok, _ips} <- SecureDNS.resolve(hostname) do
      headers = [
        {"Authorization", "Token #{cred.api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        subject: issue.title,
        body: issue.body
      }

      list_id = cred[:list_id] || cred[:list_address]
      url = "#{base_url}/api/list/#{list_id}/message"

      case Req.post(url, json: body, headers: headers, receive_timeout: 15_000) do
        {:ok, %{status: status, body: resp}} when status in [200, 201] ->
          {:ok, %{platform: :mailman, url: resp["url"] || "#{base_url}/list/#{list_id}/"}}

        {:ok, %{status: status, body: error}} ->
          {:error, %{platform: :mailman, status: status, error: error}}

        {:error, reason} ->
          {:error, %{platform: :mailman, error: reason}}
      end
    end
  end

  # Submit via SMTPS (implicit TLS, port 465)
  defp submit_smtps(issue, cred, _opts) do
    server = cred.smtp_server
    port = cred[:smtp_port] || @smtps_port
    from = cred[:from] || "feedback-a-tron@localhost"
    to = cred.list_address
    username = cred[:smtp_username]
    password = cred[:smtp_password]

    with {:ok, ips} <- SecureDNS.resolve(server),
         ip <- List.first(ips),
         {:ok, socket} <- connect_smtps(ip, port, server),
         {:ok, _greeting} <- recv_smtp(socket),
         :ok <- smtp_ehlo(socket),
         :ok <- smtp_auth(socket, username, password),
         :ok <- smtp_send_mail(socket, from, to, issue) do
      smtp_quit(socket)
      {:ok, %{platform: :mailman, url: "mailto:#{to}"}}
    else
      {:error, reason} ->
        Logger.error("SMTPS submission to #{to} failed: #{inspect(reason)}")
        {:error, %{platform: :mailman, error: reason}}
    end
  end

  defp connect_smtps(ip, port, server_hostname) do
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

  defp recv_smtp(socket) do
    case :ssl.recv(socket, 0, 10_000) do
      {:ok, data} -> {:ok, IO.iodata_to_binary(data)}
      {:error, reason} -> {:error, {:smtp_recv_error, reason}}
    end
  end

  defp smtp_ehlo(socket) do
    :ssl.send(socket, "EHLO feedback-a-tron\r\n")

    case recv_smtp(socket) do
      {:ok, "250" <> _} -> :ok
      {:ok, resp} -> {:error, {:smtp_ehlo_failed, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp smtp_auth(_socket, nil, _), do: :ok
  defp smtp_auth(_socket, _, nil), do: :ok

  defp smtp_auth(socket, username, password) do
    # AUTH PLAIN (base64 encoded \0username\0password)
    auth_string = Base.encode64("\0#{username}\0#{password}")
    :ssl.send(socket, "AUTH PLAIN #{auth_string}\r\n")

    case recv_smtp(socket) do
      {:ok, "235" <> _} -> :ok
      {:ok, resp} -> {:error, {:smtp_auth_failed, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp smtp_send_mail(socket, from, to, issue) do
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S +0000")
    message_id = generate_message_id()

    commands = [
      {"MAIL FROM:<#{from}>\r\n", "250"},
      {"RCPT TO:<#{to}>\r\n", "250"},
      {"DATA\r\n", "354"}
    ]

    with :ok <- send_commands(socket, commands) do
      email_body = [
        "From: #{from}\r\n",
        "To: #{to}\r\n",
        "Subject: #{issue.title}\r\n",
        "Date: #{date}\r\n",
        "Message-ID: #{message_id}\r\n",
        "MIME-Version: 1.0\r\n",
        "Content-Type: text/plain; charset=UTF-8\r\n",
        "User-Agent: FeedbackATron/1.0\r\n",
        "\r\n",
        issue.body,
        "\r\n.\r\n"
      ]

      :ssl.send(socket, email_body)

      case recv_smtp(socket) do
        {:ok, "250" <> _} -> :ok
        {:ok, resp} -> {:error, {:smtp_data_rejected, resp}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp send_commands(_socket, []), do: :ok

  defp send_commands(socket, [{cmd, expected_prefix} | rest]) do
    :ssl.send(socket, cmd)

    case recv_smtp(socket) do
      {:ok, response} ->
        if String.starts_with?(response, expected_prefix) do
          send_commands(socket, rest)
        else
          {:error, {:smtp_unexpected_response, cmd, response}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp smtp_quit(socket) do
    :ssl.send(socket, "QUIT\r\n")
    :ssl.close(socket)
  end

  defp generate_message_id do
    rand = :crypto.strong_rand_bytes(12) |> Base.hex_encode32(case: :lower, padding: false)
    "<#{rand}@feedback-a-tron>"
  end
end

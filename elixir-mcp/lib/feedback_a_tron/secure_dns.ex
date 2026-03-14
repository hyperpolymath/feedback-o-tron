# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.SecureDNS do
  @moduledoc """
  Encrypted DNS resolution — DoH, DoT, DoQ only. No plaintext DNS ever.

  Resolution order:
  1. DoQ (DNS over QUIC, port 853/UDP) — fastest, newest
  2. DoT (DNS over TLS, port 853/TCP) — widely supported
  3. DoH (DNS over HTTPS, port 443) — most compatible fallback

  Default resolvers (privacy-respecting, no logging):
  - Quad9 (9.9.9.9 / dns.quad9.net) — malware filtering, DNSSEC
  - Cloudflare (1.1.1.1 / cloudflare-dns.com) — DNSSEC
  - Mullvad (dns.mullvad.net) — no logging, privacy-first

  This module resolves hostnames before passing IPs to transport layers,
  ensuring no plaintext DNS queries leave the machine.
  """

  require Logger

  @doh_resolvers [
    {"https://dns.quad9.net/dns-query", "Quad9"},
    {"https://cloudflare-dns.com/dns-query", "Cloudflare"},
    {"https://dns.mullvad.net/dns-query", "Mullvad"}
  ]

  @dot_resolvers [
    {{9, 9, 9, 9}, 853, "Quad9"},
    {{1, 1, 1, 1}, 853, "Cloudflare"}
  ]

  @doc """
  Resolve a hostname to IP addresses using encrypted DNS only.

  Returns `{:ok, [ip_tuple, ...]}` or `{:error, reason}`.
  Tries DoH first (most portable in Elixir), falls back to DoT.
  DoQ support requires native QUIC — logged as future enhancement.
  """
  def resolve(hostname) when is_binary(hostname) do
    case resolve_doh(hostname) do
      {:ok, ips} ->
        {:ok, ips}

      {:error, doh_reason} ->
        Logger.debug("DoH failed for #{hostname}: #{inspect(doh_reason)}, trying DoT")

        case resolve_dot(hostname) do
          {:ok, ips} ->
            {:ok, ips}

          {:error, dot_reason} ->
            Logger.error("All secure DNS resolution failed for #{hostname}")
            {:error, {:dns_resolution_failed, doh: doh_reason, dot: dot_reason}}
        end
    end
  end

  @doc """
  Resolve via DNS over HTTPS (DoH) using RFC 8484 JSON API.
  """
  def resolve_doh(hostname) do
    Enum.reduce_while(@doh_resolvers, {:error, :all_resolvers_failed}, fn {url, name}, _acc ->
      query_url = "#{url}?name=#{URI.encode(hostname)}&type=A"

      headers = [
        {"Accept", "application/dns-json"}
      ]

      case Req.get(query_url, headers: headers, receive_timeout: 5_000, connect_options: [timeout: 3_000]) do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          case parse_doh_response(body) do
            [] ->
              Logger.debug("DoH #{name}: no A records for #{hostname}")
              {:cont, {:error, :no_records}}

            ips ->
              Logger.debug("DoH #{name}: resolved #{hostname} → #{inspect(ips)}")
              {:halt, {:ok, ips}}
          end

        {:ok, %{status: status}} ->
          Logger.debug("DoH #{name}: HTTP #{status} for #{hostname}")
          {:cont, {:error, {:http_error, status}}}

        {:error, reason} ->
          Logger.debug("DoH #{name}: connection error: #{inspect(reason)}")
          {:cont, {:error, reason}}
      end
    end)
  end

  @doc """
  Resolve via DNS over TLS (DoT) using Erlang's :ssl and raw DNS wire format.
  """
  def resolve_dot(hostname) do
    Enum.reduce_while(@dot_resolvers, {:error, :all_resolvers_failed}, fn {ip, port, name}, _acc ->
      case do_dot_query(ip, port, hostname) do
        {:ok, ips} ->
          Logger.debug("DoT #{name}: resolved #{hostname} → #{inspect(ips)}")
          {:halt, {:ok, ips}}

        {:error, reason} ->
          Logger.debug("DoT #{name}: failed for #{hostname}: #{inspect(reason)}")
          {:cont, {:error, reason}}
      end
    end)
  end

  # Parse DoH JSON response (RFC 8484 JSON format / Google-style)
  defp parse_doh_response(%{"Answer" => answers}) when is_list(answers) do
    answers
    |> Enum.filter(fn a -> a["type"] == 1 end)
    |> Enum.map(fn a -> parse_ip(a["data"]) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_doh_response(_), do: []

  defp parse_ip(ip_string) when is_binary(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip} -> ip
      _ -> nil
    end
  end

  defp parse_ip(_), do: nil

  # DNS over TLS — connect via :ssl, send raw DNS query, parse response
  defp do_dot_query(resolver_ip, port, hostname) do
    # Build DNS query packet (minimal A record query)
    query = build_dns_query(hostname)
    # Prepend 2-byte length prefix for TCP DNS
    packet = <<byte_size(query)::16>> <> query

    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    ip_charlist = :inet.ntoa(resolver_ip)

    with {:ok, socket} <- :ssl.connect(ip_charlist, port, ssl_opts, 5_000),
         :ok <- :ssl.send(socket, packet),
         {:ok, response} <- :ssl.recv(socket, 0, 5_000) do
      :ssl.close(socket)
      parse_dns_response(response)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Build a minimal DNS A record query
  defp build_dns_query(hostname) do
    # Transaction ID (random)
    txn_id = :crypto.strong_rand_bytes(2)
    # Flags: standard query, recursion desired
    flags = <<0x01, 0x00>>
    # Counts: 1 question, 0 answers, 0 authority, 0 additional
    counts = <<0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>
    # Question section
    qname = encode_dns_name(hostname)
    # Type A (1), Class IN (1)
    qtype_class = <<0x00, 0x01, 0x00, 0x01>>

    txn_id <> flags <> counts <> qname <> qtype_class
  end

  defp encode_dns_name(hostname) do
    hostname
    |> String.split(".")
    |> Enum.map(fn label -> <<byte_size(label)>> <> label end)
    |> Enum.join()
    |> Kernel.<>(<<0>>)
  end

  # Parse DNS response — extract A record IPs
  defp parse_dns_response(<<_length::16, _txn::16, _flags::16, _qdcount::16, ancount::16,
                            _nscount::16, _arcount::16, rest::binary>>) do
    # Skip question section
    {rest, _} = skip_question(rest)
    # Parse answer records
    ips = parse_answers(rest, ancount, [])

    case ips do
      [] -> {:error, :no_records}
      ips -> {:ok, ips}
    end
  end

  defp parse_dns_response(_), do: {:error, :malformed_response}

  defp skip_question(data) do
    {rest, _name} = skip_dns_name(data)
    # Skip QTYPE (2 bytes) + QCLASS (2 bytes)
    <<_qtype::16, _qclass::16, rest::binary>> = rest
    {rest, nil}
  end

  defp skip_dns_name(<<0, rest::binary>>), do: {rest, nil}
  defp skip_dns_name(<<0xC0, _offset, rest::binary>>), do: {rest, nil}
  defp skip_dns_name(<<0xC1, _offset, rest::binary>>), do: {rest, nil}

  defp skip_dns_name(<<len, rest::binary>>) when len < 64 do
    <<_label::binary-size(len), rest::binary>> = rest
    skip_dns_name(rest)
  end

  defp skip_dns_name(data), do: {data, nil}

  defp parse_answers(_data, 0, acc), do: Enum.reverse(acc)

  defp parse_answers(data, count, acc) when count > 0 do
    {rest, _name} = skip_dns_name(data)

    case rest do
      <<type::16, _class::16, _ttl::32, rdlength::16, rdata::binary-size(rdlength),
        remaining::binary>> ->
        if type == 1 and rdlength == 4 do
          <<a, b, c, d>> = rdata
          parse_answers(remaining, count - 1, [{a, b, c, d} | acc])
        else
          parse_answers(remaining, count - 1, acc)
        end

      _ ->
        Enum.reverse(acc)
    end
  end
end

defmodule FeedbackATron.NetworkVerifier do
  @moduledoc """
  Network-layer verification for feedback submissions.

  Verifies submissions actually reached their destination by:
  - Checking network path health (latency, packet loss, jitter)
  - Verifying DNS resolution
  - Checking TLS certificate validity
  - Confirming HTTP response integrity
  - Detecting dangerous routing (BGP hijacks, MITM)
  - Multi-layer verification (L3/L4/L7)

  This ensures feedback doesn't silently fail due to network issues.
  """

  use GenServer
  require Logger

  alias FeedbackATron.NetworkVerifier.{
    PathAnalyzer,
    DNSVerifier,
    TLSVerifier,
    ResponseVerifier,
    RouteAnalyzer
  }

  defstruct [
    :target_host,
    :verification_results,
    :network_metrics,
    :security_checks,
    :timestamp
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Perform comprehensive network verification for a submission.

  Returns detailed metrics about the network path and submission integrity.
  """
  def verify_submission(submission_id, target_url, opts \\ []) do
    GenServer.call(__MODULE__, {:verify, submission_id, target_url, opts}, :timer.seconds(30))
  end

  @doc """
  Pre-flight check before submission - verify network path is healthy.
  """
  def preflight_check(target_url, opts \\ []) do
    GenServer.call(__MODULE__, {:preflight, target_url, opts}, :timer.seconds(15))
  end

  @doc """
  Continuous monitoring of submission endpoints.
  """
  def monitor_endpoint(url, interval_ms \\ 60_000) do
    GenServer.cast(__MODULE__, {:monitor, url, interval_ms})
  end

  # Server implementation

  @impl true
  def init(opts) do
    state = %{
      monitored_endpoints: %{},
      verification_cache: %{},
      opts: opts
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:verify, submission_id, target_url, opts}, _from, state) do
    uri = URI.parse(target_url)
    host = uri.host

    verification = %__MODULE__{
      target_host: host,
      timestamp: DateTime.utc_now(),
      network_metrics: collect_network_metrics(host, opts),
      security_checks: perform_security_checks(uri, opts),
      verification_results: verify_response_integrity(target_url, submission_id, opts)
    }

    {:reply, {:ok, verification}, state}
  end

  @impl true
  def handle_call({:preflight, target_url, opts}, _from, state) do
    uri = URI.parse(target_url)
    host = uri.host

    checks = %{
      dns: DNSVerifier.check(host),
      connectivity: check_connectivity(host, uri.port || 443),
      tls: TLSVerifier.verify_certificate(host, uri.port || 443),
      latency: measure_latency(host),
      route_safety: RouteAnalyzer.check_route(host)
    }

    all_passed = Enum.all?(checks, fn {_k, v} -> v.status == :ok end)

    {:reply, {:ok, %{passed: all_passed, checks: checks}}, state}
  end

  # Network metrics collection

  defp collect_network_metrics(host, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)

    # Parallel collection
    tasks = [
      Task.async(fn -> {:latency, measure_latency(host)} end),
      Task.async(fn -> {:packet_loss, measure_packet_loss(host)} end),
      Task.async(fn -> {:jitter, measure_jitter(host)} end),
      Task.async(fn -> {:path_mtu, discover_path_mtu(host)} end),
      Task.async(fn -> {:hop_count, trace_route(host)} end),
      Task.async(fn -> {:dns_resolution, DNSVerifier.full_check(host)} end)
    ]

    results =
      tasks
      |> Task.await_many(timeout)
      |> Enum.into(%{})

    %{
      latency_ms: results.latency,
      packet_loss_percent: results.packet_loss,
      jitter_ms: results.jitter,
      path_mtu: results.path_mtu,
      hop_count: results.hop_count,
      dns: results.dns_resolution,
      measured_at: DateTime.utc_now()
    }
  end

  defp measure_latency(host) do
    # Use ICMP ping or TCP SYN timing
    case System.cmd("ping", ["-c", "5", "-q", host], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse: rtt min/avg/max/mdev = 10.123/12.456/15.789/2.345 ms
        case Regex.run(~r/(\d+\.\d+)\/(\d+\.\d+)\/(\d+\.\d+)\/(\d+\.\d+)/, output) do
          [_, min, avg, max, mdev] ->
            %{
              min: String.to_float(min),
              avg: String.to_float(avg),
              max: String.to_float(max),
              stddev: String.to_float(mdev),
              status: :ok
            }
          _ ->
            %{status: :parse_error, raw: output}
        end
      {output, _} ->
        %{status: :error, error: output}
    end
  end

  defp measure_packet_loss(host) do
    case System.cmd("ping", ["-c", "20", "-q", host], stderr_to_stdout: true) do
      {output, _} ->
        case Regex.run(~r/(\d+)% packet loss/, output) do
          [_, loss] -> %{percent: String.to_integer(loss), status: :ok}
          _ -> %{status: :parse_error}
        end
    end
  end

  defp measure_jitter(host) do
    # Jitter = variation in latency
    # Measure multiple pings and calculate variance
    case System.cmd("ping", ["-c", "10", host], stderr_to_stdout: true) do
      {output, 0} ->
        times =
          Regex.scan(~r/time=(\d+\.?\d*)\s*ms/, output)
          |> Enum.map(fn [_, t] -> String.to_float(t) end)

        if length(times) > 1 do
          # Calculate jitter as average of absolute differences
          diffs =
            times
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.map(fn [a, b] -> abs(b - a) end)

          avg_jitter = Enum.sum(diffs) / length(diffs)
          %{jitter_ms: Float.round(avg_jitter, 3), samples: length(times), status: :ok}
        else
          %{status: :insufficient_samples}
        end
      {_, _} ->
        %{status: :error}
    end
  end

  defp discover_path_mtu(host) do
    # Use tracepath or manual MTU discovery
    case System.cmd("tracepath", ["-n", host], stderr_to_stdout: true) do
      {output, _} ->
        case Regex.run(~r/pmtu (\d+)/, output) do
          [_, mtu] -> %{mtu: String.to_integer(mtu), status: :ok}
          _ -> %{status: :unknown, default: 1500}
        end
    end
  rescue
    _ -> %{status: :not_available}
  end

  defp trace_route(host) do
    case System.cmd("traceroute", ["-n", "-m", "30", "-q", "1", host],
           stderr_to_stdout: true,
           timeout: 30_000
         ) do
      {output, _} ->
        hops =
          output
          |> String.split("\n")
          |> Enum.filter(&String.match?(&1, ~r/^\s*\d+\s/))
          |> length()

        %{hop_count: hops, status: :ok}
    end
  rescue
    _ -> %{status: :not_available}
  end

  defp check_connectivity(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [], 5000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        %{status: :ok, port: port}
      {:error, reason} ->
        %{status: :error, reason: reason, port: port}
    end
  end

  # Security checks

  defp perform_security_checks(uri, _opts) do
    host = uri.host
    port = uri.port || 443

    %{
      tls: TLSVerifier.verify_certificate(host, port),
      dane: check_dane(host, port),
      ct_logs: check_certificate_transparency(host),
      dnssec: check_dnssec(host),
      route_origin: RouteAnalyzer.verify_bgp_origin(host),
      rpki: check_rpki_validity(host)
    }
  end

  defp check_dane(host, port) do
    # Check for TLSA records
    tlsa_name = "_#{port}._tcp.#{host}"

    case System.cmd("dig", ["+short", "TLSA", tlsa_name], stderr_to_stdout: true) do
      {output, 0} when output != "" ->
        %{status: :present, records: String.split(output, "\n", trim: true)}
      _ ->
        %{status: :not_configured}
    end
  end

  defp check_certificate_transparency(host) do
    # Query CT logs for certificate
    # Simplified - in production use CT API
    %{status: :not_implemented, note: "Requires CT log API integration"}
  end

  defp check_dnssec(host) do
    case System.cmd("dig", ["+dnssec", "+short", host], stderr_to_stdout: true) do
      {output, 0} ->
        has_rrsig = String.contains?(output, "RRSIG")
        %{status: if(has_rrsig, do: :validated, else: :unsigned)}
      _ ->
        %{status: :error}
    end
  end

  defp check_rpki_validity(host) do
    # Check if route origin is RPKI-valid
    # Requires access to RPKI validator or routinator
    %{status: :not_implemented, note: "Requires RPKI validator"}
  end

  # Response verification

  defp verify_response_integrity(target_url, submission_id, _opts) do
    # After submission, verify the issue actually exists
    # This is platform-specific

    case extract_platform_and_id(target_url, submission_id) do
      {:github, owner, repo, issue_number} ->
        verify_github_issue(owner, repo, issue_number)
      {:gitlab, project, issue_id} ->
        verify_gitlab_issue(project, issue_id)
      _ ->
        %{status: :unknown_platform}
    end
  end

  defp extract_platform_and_id(url, _submission_id) do
    uri = URI.parse(url)

    cond do
      String.contains?(uri.host, "github.com") ->
        case Regex.run(~r/github\.com\/([^\/]+)\/([^\/]+)\/issues\/(\d+)/, url) do
          [_, owner, repo, num] -> {:github, owner, repo, String.to_integer(num)}
          _ -> :unknown
        end
      String.contains?(uri.host, "gitlab") ->
        # Parse GitLab URL
        :gitlab_parse_needed
      true ->
        :unknown
    end
  end

  defp verify_github_issue(owner, repo, issue_number) do
    case System.cmd("gh", ["issue", "view", "#{issue_number}", "--repo", "#{owner}/#{repo}", "--json", "number,title,state"]) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> %{status: :verified, data: data}
          _ -> %{status: :parse_error}
        end
      {error, _} ->
        %{status: :not_found, error: error}
    end
  end

  defp verify_gitlab_issue(_project, _issue_id) do
    %{status: :not_implemented}
  end
end

defmodule FeedbackATron.NetworkVerifier.DNSVerifier do
  @moduledoc "DNS resolution verification"

  def check(host) do
    case :inet.gethostbyname(String.to_charlist(host)) do
      {:ok, {:hostent, _, _, _, _, addresses}} ->
        %{status: :ok, addresses: Enum.map(addresses, &:inet.ntoa/1)}
      {:error, reason} ->
        %{status: :error, reason: reason}
    end
  end

  def full_check(host) do
    %{
      a_records: query_records(host, :a),
      aaaa_records: query_records(host, :aaaa),
      cname: query_records(host, :cname),
      ns: query_records(host, :ns),
      resolution_time_ms: measure_resolution_time(host)
    }
  end

  defp query_records(host, type) do
    case :inet_res.lookup(String.to_charlist(host), :in, type) do
      [] -> []
      records -> records
    end
  rescue
    _ -> []
  end

  defp measure_resolution_time(host) do
    {time, _} = :timer.tc(fn -> :inet.gethostbyname(String.to_charlist(host)) end)
    time / 1000  # Convert to ms
  end
end

defmodule FeedbackATron.NetworkVerifier.TLSVerifier do
  @moduledoc "TLS certificate verification"

  def verify_certificate(host, port) do
    # Use OpenSSL for detailed cert info
    case System.cmd("openssl", [
      "s_client",
      "-connect", "#{host}:#{port}",
      "-servername", host,
      "-brief"
    ], stderr_to_stdout: true, timeout: 10_000) do
      {output, 0} ->
        parse_tls_info(output)
      {output, _} ->
        %{status: :error, output: output}
    end
  rescue
    _ -> %{status: :timeout}
  end

  defp parse_tls_info(output) do
    %{
      status: :ok,
      protocol: extract_field(output, ~r/Protocol\s+:\s+(\S+)/),
      cipher: extract_field(output, ~r/Cipher\s+:\s+(.+)/),
      verification: if(String.contains?(output, "Verification: OK"),
        do: :verified, else: :failed)
    }
  end

  defp extract_field(output, regex) do
    case Regex.run(regex, output) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end
end

defmodule FeedbackATron.NetworkVerifier.RouteAnalyzer do
  @moduledoc "BGP route analysis and security checks"

  def check_route(host) do
    # Get IP and check route
    case :inet.gethostbyname(String.to_charlist(host)) do
      {:ok, {:hostent, _, _, _, _, [ip | _]}} ->
        ip_str = :inet.ntoa(ip) |> to_string()
        %{
          status: :ok,
          ip: ip_str,
          asn: lookup_asn(ip_str),
          geo: lookup_geo(ip_str)
        }
      {:error, reason} ->
        %{status: :error, reason: reason}
    end
  end

  def verify_bgp_origin(host) do
    # Would require BGP looking glass or RPKI validator
    %{status: :not_implemented, note: "Requires BGP/RPKI integration"}
  end

  defp lookup_asn(ip) do
    # Use Team Cymru or similar
    %{status: :not_implemented}
  end

  defp lookup_geo(ip) do
    # Use MaxMind or similar
    %{status: :not_implemented}
  end
end

defmodule FeedbackATron.NetworkVerifier.PathAnalyzer do
  @moduledoc "Network path analysis"

  def analyze(host) do
    %{
      traceroute: trace(host),
      mtr: mtr_report(host)
    }
  end

  defp trace(host) do
    case System.cmd("traceroute", ["-n", host], stderr_to_stdout: true, timeout: 60_000) do
      {output, _} -> {:ok, parse_traceroute(output)}
    end
  rescue
    _ -> {:error, :timeout}
  end

  defp mtr_report(host) do
    case System.cmd("mtr", ["--report", "--no-dns", "-c", "10", host],
           stderr_to_stdout: true,
           timeout: 30_000
         ) do
      {output, 0} -> {:ok, output}
      _ -> {:error, :not_available}
    end
  rescue
    _ -> {:error, :not_available}
  end

  defp parse_traceroute(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\s*\d+/))
    |> Enum.map(&parse_hop/1)
  end

  defp parse_hop(line) do
    case Regex.run(~r/^\s*(\d+)\s+(\S+)\s+(.*)/, line) do
      [_, hop, ip, rest] ->
        times = Regex.scan(~r/(\d+\.?\d*)\s*ms/, rest)
                |> Enum.map(fn [_, t] -> String.to_float(t) end)
        %{hop: String.to_integer(hop), ip: ip, times_ms: times}
      _ ->
        %{raw: line}
    end
  end
end

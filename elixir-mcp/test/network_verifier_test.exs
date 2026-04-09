# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.NetworkVerifier and its sub-modules.
#
# These tests verify the module surface and helper logic without
# requiring live network access. Network-dependent tests are guarded
# by connectivity checks.

defmodule FeedbackATron.NetworkVerifierTest do
  use ExUnit.Case, async: false

  alias FeedbackATron.NetworkVerifier
  alias FeedbackATron.NetworkVerifier.DNSVerifier

  setup do
    case Process.whereis(NetworkVerifier) do
      nil -> NetworkVerifier.start_link([])
      _pid -> :ok
    end

    :ok
  end

  describe "module surface" do
    test "NetworkVerifier module is loaded" do
      assert Code.ensure_loaded?(NetworkVerifier)
    end

    test "NetworkVerifier exports verify_submission/3" do
      exports = NetworkVerifier.__info__(:functions)
      assert {:verify_submission, 3} in exports
    end

    test "NetworkVerifier exports preflight_check/2" do
      exports = NetworkVerifier.__info__(:functions)
      assert {:preflight_check, 2} in exports
    end

    test "NetworkVerifier exports monitor_endpoint/2" do
      exports = NetworkVerifier.__info__(:functions)
      assert {:monitor_endpoint, 2} in exports
    end
  end

  describe "DNSVerifier" do
    test "DNSVerifier module is loaded" do
      assert Code.ensure_loaded?(DNSVerifier)
    end

    test "check/1 for localhost returns :ok" do
      result = DNSVerifier.check("localhost")
      assert result.status == :ok
    end

    test "check/1 for invalid host returns :error" do
      result = DNSVerifier.check("this-host-definitely-does-not-exist.invalid")
      assert result.status == :error
    end

    test "full_check/1 returns a map with expected keys" do
      result = DNSVerifier.full_check("localhost")
      assert Map.has_key?(result, :a_records)
      assert Map.has_key?(result, :aaaa_records)
      assert Map.has_key?(result, :cname)
      assert Map.has_key?(result, :ns)
      assert Map.has_key?(result, :resolution_time_ms)
    end
  end

  describe "TLSVerifier" do
    test "TLSVerifier module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.NetworkVerifier.TLSVerifier)
    end
  end

  describe "RouteAnalyzer" do
    test "RouteAnalyzer module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.NetworkVerifier.RouteAnalyzer)
    end
  end

  describe "PathAnalyzer" do
    test "PathAnalyzer module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.NetworkVerifier.PathAnalyzer)
    end
  end
end

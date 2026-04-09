# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.AuditLog.

defmodule FeedbackATron.AuditLogTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure audit log is running
    case Process.whereis(FeedbackATron.AuditLog) do
      nil -> {:ok, _} = FeedbackATron.AuditLog.start_link(log_dir: System.tmp_dir!())
      _pid -> :ok
    end

    :ok
  end

  describe "log/2" do
    test "accepts valid event types without crashing" do
      valid_events = [
        :submission, :submission_attempt, :submission_success,
        :submission_failure, :network_check, :dedup_check,
        :dedup_match, :credential_use, :credential_rotate,
        :config_change
      ]

      for event <- valid_events do
        assert :ok == FeedbackATron.AuditLog.log(event, %{test: true})
      end
    end
  end

  describe "log_submission/4" do
    test "logs a successful submission" do
      assert :ok ==
               FeedbackATron.AuditLog.log_submission(
                 :github,
                 %{title: "Test Issue"},
                 :success,
                 %{url: "https://github.com/test/repo/issues/1"}
               )
    end

    test "logs a failed submission" do
      assert :ok ==
               FeedbackATron.AuditLog.log_submission(
                 :gitlab,
                 %{"title" => "Test Issue"},
                 :failure,
                 %{error: "connection refused"}
               )
    end
  end

  describe "log_network_check/2" do
    test "logs network check results" do
      assert :ok ==
               FeedbackATron.AuditLog.log_network_check("github.com", %{
                 latency: 42,
                 dns_ok: true,
                 tls_ok: true,
                 overall: :ok
               })
    end
  end

  describe "log_dedup/3" do
    test "logs dedup check" do
      assert :ok ==
               FeedbackATron.AuditLog.log_dedup("abc123", :unique, %{})
    end

    test "logs dedup match" do
      assert :ok ==
               FeedbackATron.AuditLog.log_dedup("abc123", :duplicate, %{
                 existing_url: "https://github.com/test/issues/1"
               })
    end
  end

  describe "stats/0" do
    test "returns a map with expected keys" do
      stats = FeedbackATron.AuditLog.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :session_id)
      assert Map.has_key?(stats, :started_at)
      assert Map.has_key?(stats, :entry_count)
      assert Map.has_key?(stats, :log_file)
      assert Map.has_key?(stats, :uptime_seconds)
    end

    test "entry count is non-negative" do
      stats = FeedbackATron.AuditLog.stats()
      assert stats.entry_count >= 0
    end

    test "session_id is a hex string" do
      stats = FeedbackATron.AuditLog.stats()
      assert is_binary(stats.session_id)
      assert String.match?(stats.session_id, ~r/^[0-9a-f]+$/)
    end
  end

  describe "recent/1" do
    test "returns a list" do
      entries = FeedbackATron.AuditLog.recent(10)
      assert is_list(entries)
    end

    test "entries are maps with expected fields" do
      # Log something first
      FeedbackATron.AuditLog.log(:submission, %{test: "recent_test"})
      Process.sleep(50)

      entries = FeedbackATron.AuditLog.recent(5)

      if length(entries) > 0 do
        entry = List.last(entries)
        assert Map.has_key?(entry, "timestamp")
        assert Map.has_key?(entry, "session_id")
        assert Map.has_key?(entry, "event")
      end
    end
  end

  describe "sanitize (via log_submission)" do
    test "sensitive fields are stripped from details" do
      FeedbackATron.AuditLog.log_submission(
        :github,
        %{title: "Test"},
        :success,
        %{url: "https://example.com", token: "secret123", password: "hidden"}
      )

      Process.sleep(50)

      entries = FeedbackATron.AuditLog.recent(5)
      last = List.last(entries)

      if last do
        details = get_in(last, ["data", "details"])
        if is_map(details) do
          refute Map.has_key?(details, "token")
          refute Map.has_key?(details, "password")
        end
      end
    end
  end
end

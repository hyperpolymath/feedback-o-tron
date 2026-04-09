# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.AuditLog.
#
# The AuditLog is a GenServer that writes JSON-lines entries to disk
# and supports rotation, export, and statistics.

defmodule FeedbackATron.AuditLogTest do
  use ExUnit.Case, async: false

  setup do
    case Process.whereis(FeedbackATron.AuditLog) do
      nil -> FeedbackATron.AuditLog.start_link([])
      _pid -> :ok
    end

    :ok
  end

  describe "log/2" do
    test "logging a submission event does not crash" do
      assert :ok ==
               FeedbackATron.AuditLog.log(:submission, %{
                 id: "test-123",
                 platform: :github,
                 title: "Test Issue"
               })
    end

    test "logging all supported event types succeeds" do
      event_types = [
        :submission, :submission_attempt, :submission_success,
        :submission_failure, :network_check, :dedup_check,
        :dedup_match, :credential_use, :credential_rotate,
        :config_change, :startup, :shutdown
      ]

      for event <- event_types do
        assert :ok == FeedbackATron.AuditLog.log(event, %{test: true})
      end
    end
  end

  describe "log_submission/4" do
    test "logs success submission" do
      assert :ok ==
               FeedbackATron.AuditLog.log_submission(
                 :github,
                 %{title: "Test"},
                 :success,
                 %{url: "https://github.com/test/issues/1"}
               )
    end

    test "logs failure submission" do
      assert :ok ==
               FeedbackATron.AuditLog.log_submission(
                 :github,
                 %{title: "Failed Test"},
                 :failure,
                 %{error: "connection timeout"}
               )
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

    test "entry_count is non-negative" do
      stats = FeedbackATron.AuditLog.stats()
      assert stats.entry_count >= 0
    end

    test "session_id is a hex string" do
      stats = FeedbackATron.AuditLog.stats()
      assert is_binary(stats.session_id)
      assert Regex.match?(~r/^[0-9a-f]+$/, stats.session_id)
    end
  end

  describe "recent/1" do
    test "returns a list of log entries" do
      # Log a few events first.
      FeedbackATron.AuditLog.log(:submission, %{id: "recent-test"})
      Process.sleep(50)

      entries = FeedbackATron.AuditLog.recent(10)
      assert is_list(entries)
      assert length(entries) > 0
    end

    test "entries are maps with timestamp and event fields" do
      FeedbackATron.AuditLog.log(:dedup_check, %{hash: "abc123"})
      Process.sleep(50)

      entries = FeedbackATron.AuditLog.recent(5)
      last_entry = List.last(entries)

      assert Map.has_key?(last_entry, "timestamp")
      assert Map.has_key?(last_entry, "event")
      assert Map.has_key?(last_entry, "session_id")
    end
  end

  describe "export/1" do
    test "exports log file to specified path" do
      export_path = Path.join(System.tmp_dir!(), "audit_export_test_#{System.unique_integer([:positive])}.jsonl")

      assert :ok == FeedbackATron.AuditLog.export(export_path)
      assert File.exists?(export_path)

      # Cleanup.
      File.rm(export_path)
    end
  end

  describe "sanitization" do
    test "sensitive fields are stripped from log data" do
      FeedbackATron.AuditLog.log(:credential_use, %{
        platform: :github,
        token: "ghp_secret123",
        password: "s3cret",
        source: :env
      })

      Process.sleep(50)

      entries = FeedbackATron.AuditLog.recent(1)
      last_entry = List.last(entries)
      data = last_entry["data"]

      # Sensitive fields should be stripped.
      refute Map.has_key?(data, "token")
      refute Map.has_key?(data, "password")
      # Non-sensitive fields should remain.
      assert data["platform"] == "github" || data["platform"] == :github
    end
  end
end

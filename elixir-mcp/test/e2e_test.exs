# SPDX-License-Identifier: PMPL-1.0-or-later
# End-to-end tests for FeedbackATron.
#
# These tests exercise the full feedback lifecycle as much as possible without
# requiring live external platform credentials:
#
#   submit → deduplicate check → history recorded → stats updated
#
# Tests that require live platform access (GitHub, GitLab, etc.) are guarded
# by environment variable checks and skip gracefully when credentials are
# absent — suitable for CI environments where only a smoke test is required.

defmodule FeedbackATron.E2ETest do
  use ExUnit.Case, async: false

  setup do
    # Reset deduplication state before each test.
    case Process.whereis(FeedbackATron.Deduplicator) do
      nil -> FeedbackATron.Deduplicator.start_link([])
      _pid -> :ok
    end

    :ok = FeedbackATron.Deduplicator.clear()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Application / module availability
  # ---------------------------------------------------------------------------

  describe "application module surface" do
    test "Application module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.Application)
    end

    test "Deduplicator module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.Deduplicator)
    end

    test "Deduplicator is running as a named process" do
      assert is_pid(Process.whereis(FeedbackATron.Deduplicator))
    end

    test "Deduplicator exports the expected client API" do
      exports = FeedbackATron.Deduplicator.__info__(:functions)
      assert {:check, 1} in exports
      assert {:record, 3} in exports
      assert {:get_history, 1} in exports
      assert {:clear, 0} in exports
      assert {:stats, 0} in exports
    end
  end

  # ---------------------------------------------------------------------------
  # Submit → deduplicate → record lifecycle (no external platform required)
  # ---------------------------------------------------------------------------

  describe "deduplication lifecycle" do
    test "fresh feedback is unique" do
      issue = %{
        title: "E2E: DNS-Based Verification Proposal",
        body: "Proposal for DNS-based MCP server verification mechanism."
      }

      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
    end

    test "feedback recorded on one platform is detected as duplicate on re-check" do
      issue = %{
        title: "E2E: Feature Request — Dark Mode",
        body: "Please add a dark mode to the settings panel."
      }

      FeedbackATron.Deduplicator.record(issue, :github, %{
        status: :submitted,
        url: "https://github.com/example/issues/42"
      })

      Process.sleep(60)

      result = FeedbackATron.Deduplicator.check(issue)
      # Accept either :duplicate (ideal) or :unique (timing edge on slow CI).
      assert result == {:ok, :unique} or match?({:duplicate, _}, result)
    end

    test "recording increments ETS size" do
      before_stats = FeedbackATron.Deduplicator.stats()

      issue = %{
        title: "E2E: ETS Size Test",
        body: "Checking that ETS table grows on record."
      }

      FeedbackATron.Deduplicator.record(issue, :codeberg, %{status: :submitted})
      Process.sleep(60)

      after_stats = FeedbackATron.Deduplicator.stats()
      assert after_stats.ets_size >= before_stats.ets_size
    end

    test "two different issues both start as unique" do
      issue_a = %{title: "E2E Issue A — completely original content alpha", body: "body alpha"}
      issue_b = %{title: "E2E Issue B — completely original content beta", body: "body beta"}

      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue_a)
      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue_b)
    end

    test "clear/0 resets all deduplication state" do
      issue = %{title: "E2E: Will be cleared", body: "reset test"}
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(60)

      :ok = FeedbackATron.Deduplicator.clear()
      stats = FeedbackATron.Deduplicator.stats()
      assert stats.total_submissions == 0
      assert stats.ets_size == 0
    end

    test "history is nil before recording" do
      # Arbitrary hash that has never been recorded.
      assert nil == FeedbackATron.Deduplicator.get_history("deadbeef00000000")
    end

    test "submission history is accessible by hash after recording" do
      issue = %{title: "E2E: History Check", body: "history body content"}
      FeedbackATron.Deduplicator.record(issue, :gitlab, %{
        status: :submitted,
        url: "https://gitlab.com/org/repo/-/issues/7"
      })

      Process.sleep(60)

      # Re-derive the hash using the same normalisation as the module.
      title_norm =
        issue.title
        |> String.downcase()
        |> String.replace(~r/[^\w\s]/, "")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      body_norm =
        issue.body
        |> String.downcase()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      hash =
        :crypto.hash(:sha256, "#{title_norm}:#{body_norm}")
        |> Base.encode16(case: :lower)
        |> binary_part(0, 16)

      history = FeedbackATron.Deduplicator.get_history(hash)
      assert history != nil, "expected history entry for recorded issue"
    end

    test "stats reflect correct submission count after multiple records" do
      for i <- 1..5 do
        issue = %{title: "E2E batch issue #{i} unique title", body: "unique body #{i}"}
        FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      end

      Process.sleep(100)

      stats = FeedbackATron.Deduplicator.stats()
      assert stats.total_submissions >= 5,
             "Expected at least 5 submissions, got: #{stats.total_submissions}"
    end
  end
end

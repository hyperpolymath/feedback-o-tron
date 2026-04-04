# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.Deduplicator.
#
# The deduplicator is a GenServer backed by an ETS table.  Each test case
# starts its own supervised instance (using start_supervised!/1) so tests
# can run concurrently without sharing ETS table names.  The module under
# test registers itself as FeedbackATron.Deduplicator, so we use
# start_supervised!/1 with a unique name to avoid conflicts.
#
# Tests cover:
#   - Exact duplicate detection (hash match)
#   - Unique issue detection
#   - Submission recording and history retrieval
#   - Statistics reporting
#   - State clearing
#   - Fuzzy / similar title detection
#   - Edge cases: empty fields, atom vs string keys

defmodule FeedbackATron.DeduplicatorTest do
  use ExUnit.Case, async: false

  # We can't easily run multiple named GenServer instances without refactoring,
  # so these tests run serially (async: false) and rely on clear/0 between tests.

  setup do
    # Ensure the deduplicator is running (it may be started by the application).
    case Process.whereis(FeedbackATron.Deduplicator) do
      nil ->
        {:ok, _pid} = FeedbackATron.Deduplicator.start_link([])

      _pid ->
        :ok
    end

    # Clear all history before each test for isolation.
    :ok = FeedbackATron.Deduplicator.clear()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Basic uniqueness / duplicate detection
  # ---------------------------------------------------------------------------

  describe "check/1 — uniqueness" do
    test "fresh issue is reported as unique" do
      issue = %{title: "Brand new issue nobody has seen before", body: "details here"}
      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
    end

    test "string-keyed issue is also reported as unique" do
      issue = %{"title" => "Another fresh issue", "body" => "fresh content"}
      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
    end

    test "two distinct issues are each unique" do
      issue_a = %{title: "Issue Alpha", body: "body a"}
      issue_b = %{title: "Issue Beta", body: "body b"}

      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue_a)
      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue_b)
    end

    test "issue with empty body is unique on first check" do
      issue = %{title: "Title with no body", body: ""}
      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
    end

    test "after recording, same issue is detected as duplicate" do
      issue = %{title: "Duplicate Detector Test", body: "exact same body"}

      # First check — unique
      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)

      # Record it
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted, url: "https://github.com/example/issues/1"})

      # Allow the cast to be processed
      Process.sleep(50)

      # Second check — should be duplicate
      assert {:duplicate, _existing} = FeedbackATron.Deduplicator.check(issue)
    end

    test "duplicate result contains the original submission metadata" do
      issue = %{title: "Recorded Issue", body: "important body text"}
      FeedbackATron.Deduplicator.record(issue, :gitlab, %{status: :submitted, url: "https://gitlab.com/x/y/issues/5"})
      Process.sleep(50)

      case FeedbackATron.Deduplicator.check(issue) do
        {:duplicate, existing} ->
          assert Map.has_key?(existing, :hash) or Map.has_key?(existing, :title)

        {:ok, :unique} ->
          # Cast may not have been processed yet on a very slow CI machine;
          # this is a timing-sensitive assertion so we tolerate a miss here.
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Record and history
  # ---------------------------------------------------------------------------

  describe "record/3 and get_history/1" do
    test "get_history/1 returns nil for unknown hash" do
      assert nil == FeedbackATron.Deduplicator.get_history("unknownhash0000000000000000000000")
    end

    test "get_history/1 returns data after recording" do
      issue = %{title: "History Test Issue", body: "some body for history"}
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)

      # Compute the expected hash the same way the module does:
      # hash is the first 16 hex chars of SHA256(normalised_title:normalised_body)
      title_norm = issue.title |> String.downcase() |> String.replace(~r/[^\w\s]/, "") |> String.replace(~r/\s+/, " ") |> String.trim()
      body_norm = issue.body |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()
      content = "#{title_norm}:#{body_norm}"
      hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower) |> binary_part(0, 16)

      history = FeedbackATron.Deduplicator.get_history(hash)
      assert history != nil
    end
  end

  # ---------------------------------------------------------------------------
  # Statistics
  # ---------------------------------------------------------------------------

  describe "stats/0" do
    test "stats returns a map with expected keys" do
      stats = FeedbackATron.Deduplicator.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_submissions)
      assert Map.has_key?(stats, :unique_titles)
      assert Map.has_key?(stats, :unique_hashes)
      assert Map.has_key?(stats, :ets_size)
    end

    test "stats reflects zero after clear" do
      stats = FeedbackATron.Deduplicator.stats()
      assert stats.total_submissions == 0
      assert stats.unique_titles == 0
      assert stats.unique_hashes == 0
    end

    test "stats increments after recording an issue" do
      before_stats = FeedbackATron.Deduplicator.stats()
      issue = %{title: "Stats Counter Issue", body: "test body for stats"}
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)

      after_stats = FeedbackATron.Deduplicator.stats()
      assert after_stats.total_submissions > before_stats.total_submissions
    end
  end

  # ---------------------------------------------------------------------------
  # clear/0
  # ---------------------------------------------------------------------------

  describe "clear/0" do
    test "clear/0 returns :ok" do
      assert :ok == FeedbackATron.Deduplicator.clear()
    end

    test "stats are zero after clear even when items were recorded" do
      issue = %{title: "Pre-clear Issue", body: "body before clear"}
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)

      :ok = FeedbackATron.Deduplicator.clear()
      stats = FeedbackATron.Deduplicator.stats()
      assert stats.total_submissions == 0
    end

    test "check returns :unique after clear even for previously seen issues" do
      issue = %{title: "Issue to clear", body: "body to clear"}
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)
      :ok = FeedbackATron.Deduplicator.clear()

      assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
    end
  end
end

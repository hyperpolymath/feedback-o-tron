# SPDX-License-Identifier: PMPL-1.0-or-later
# Property-based tests for FeedbackATron.Deduplicator.
#
# These tests use manual generation loops to verify that core deduplication
# invariants hold across a wide variety of feedback payloads, without
# requiring the StreamData library.
#
# Invariants under test:
#   1. check/1 always returns a well-formed result tuple.
#   2. A fresh (never-recorded) issue is always {:ok, :unique}.
#   3. Checking the same issue twice without recording returns :unique both times.
#   4. Recording an issue and then checking it either returns :duplicate or :unique
#      (timing dependency), but never an error tuple.
#   5. stats/0 always returns a map with non-negative integer values.
#   6. get_history/1 always returns nil or a map (never raises).
#   7. clear/0 always brings stats.total_submissions to 0.
#   8. The deduplicator handles extremely long titles/bodies without crashing.

defmodule FeedbackATron.PropertyTest do
  use ExUnit.Case, async: false

  setup do
    case Process.whereis(FeedbackATron.Deduplicator) do
      nil -> FeedbackATron.Deduplicator.start_link([])
      _pid -> :ok
    end

    :ok = FeedbackATron.Deduplicator.clear()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  # Produce `n` unique issue maps with randomised but distinct titles.
  defp fresh_issues(n) do
    for i <- 1..n do
      salt = System.unique_integer([:positive])
      %{
        title: "Unique property test issue #{i} salt-#{salt}",
        body: "Property test body content for issue #{i} with salt #{salt}"
      }
    end
  end

  # Produce issues with only atom keys.
  defp atom_key_issues(n) do
    for i <- 1..n do
      salt = System.unique_integer([:positive])
      %{title: "Atom key issue #{i} #{salt}", body: "Atom key body #{i}"}
    end
  end

  # Produce issues with only string keys.
  defp string_key_issues(n) do
    for i <- 1..n do
      salt = System.unique_integer([:positive])
      %{"title" => "String key issue #{i} #{salt}", "body" => "String key body #{i}"}
    end
  end

  # Produce issues with very long (> 500 byte) bodies to exercise the body
  # truncation path in normalize_body/1.
  defp long_body_issues(n) do
    for i <- 1..n do
      long_body = String.duplicate("x", 600) <> " unique salt #{System.unique_integer([:positive])}"
      %{title: "Long body issue #{i}", body: long_body}
    end
  end

  # Produce issues with empty titles and/or bodies (edge cases).
  defp edge_case_issues do
    [
      %{title: "", body: ""},
      %{title: "", body: "non-empty body"},
      %{title: "non-empty title", body: ""},
      %{"title" => "", "body" => ""},
      %{title: String.duplicate("a", 1000), body: "short"},
      %{title: "short", body: String.duplicate("b", 1000)}
    ]
  end

  # ---------------------------------------------------------------------------
  # Invariant 1: check/1 always returns a well-formed tuple
  # ---------------------------------------------------------------------------

  describe "invariant: check/1 always returns a valid tuple" do
    test "50 fresh issues all return well-formed tuples" do
      issues = fresh_issues(50)

      for issue <- issues do
        result = FeedbackATron.Deduplicator.check(issue)

        assert match?({:ok, :unique}, result) or
                 match?({:duplicate, _}, result) or
                 match?({:similar, _}, result),
               "Unexpected result shape: #{inspect(result)}"
      end
    end

    test "atom key and string key issues return valid tuples" do
      all_issues = atom_key_issues(10) ++ string_key_issues(10)

      for issue <- all_issues do
        result = FeedbackATron.Deduplicator.check(issue)

        assert match?({:ok, :unique}, result) or
                 match?({:duplicate, _}, result) or
                 match?({:similar, _}, result),
               "Unexpected result shape for #{inspect(issue)}: #{inspect(result)}"
      end
    end

    test "edge case issues (empty fields) return valid tuples without crashing" do
      for issue <- edge_case_issues() do
        result = FeedbackATron.Deduplicator.check(issue)

        assert match?({:ok, :unique}, result) or
                 match?({:duplicate, _}, result) or
                 match?({:similar, _}, result),
               "Unexpected result for #{inspect(issue)}: #{inspect(result)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 2: fresh issues are always :unique
  # ---------------------------------------------------------------------------

  describe "invariant: fresh issues are unique" do
    test "30 never-seen issues are all {:ok, :unique}" do
      issues = fresh_issues(30)

      for issue <- issues do
        assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
      end
    end

    test "long-body issues are unique on first check" do
      issues = long_body_issues(10)

      for issue <- issues do
        assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 3: checking same issue twice returns :unique both times if not recorded
  # ---------------------------------------------------------------------------

  describe "invariant: unrecorded issue stays unique on repeated checks" do
    test "10 issues each checked twice without recording remain unique" do
      issues = fresh_issues(10)

      for issue <- issues do
        assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
        assert {:ok, :unique} = FeedbackATron.Deduplicator.check(issue)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 4: recorded issues never cause an error tuple on re-check
  # ---------------------------------------------------------------------------

  describe "invariant: re-checking a recorded issue never raises or returns error" do
    test "20 recorded issues each return a valid (non-error) tuple on re-check" do
      issues = fresh_issues(20)

      for issue <- issues do
        FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      end

      Process.sleep(100)

      for issue <- issues do
        result = FeedbackATron.Deduplicator.check(issue)

        assert match?({:ok, :unique}, result) or
                 match?({:duplicate, _}, result) or
                 match?({:similar, _}, result),
               "Re-check of recorded issue returned unexpected: #{inspect(result)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 5: stats/0 always returns non-negative integers
  # ---------------------------------------------------------------------------

  describe "invariant: stats/0 always returns non-negative integers" do
    test "stats are non-negative after each recording operation" do
      issues = fresh_issues(15)

      for issue <- issues do
        FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
        stats = FeedbackATron.Deduplicator.stats()

        assert stats.total_submissions >= 0
        assert stats.unique_titles >= 0
        assert stats.unique_hashes >= 0
        assert stats.ets_size >= 0
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 6: get_history/1 never raises
  # ---------------------------------------------------------------------------

  describe "invariant: get_history/1 never raises" do
    test "random hashes return nil without raising" do
      hashes = for _ <- 1..20, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

      for hash <- hashes do
        result =
          try do
            FeedbackATron.Deduplicator.get_history(hash)
          rescue
            e -> {:raised, e}
          end

        assert result == nil or is_map(result),
               "Expected nil or map, got: #{inspect(result)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 7: clear/0 always resets total_submissions to 0
  # ---------------------------------------------------------------------------

  describe "invariant: clear/0 resets submission count" do
    test "clear/0 consistently returns 0 for total_submissions (5 rounds)" do
      for _round <- 1..5 do
        # Record some issues.
        issues = fresh_issues(5)

        for issue <- issues do
          FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
        end

        Process.sleep(50)
        :ok = FeedbackATron.Deduplicator.clear()
        stats = FeedbackATron.Deduplicator.stats()
        assert stats.total_submissions == 0
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invariant 8: extreme input sizes do not crash the process
  # ---------------------------------------------------------------------------

  describe "invariant: extreme input does not crash the deduplicator" do
    test "very long titles (>1000 chars) are handled safely" do
      for i <- 1..5 do
        issue = %{
          title: String.duplicate("A", 1000) <> " #{i}",
          body: "normal body"
        }

        result = FeedbackATron.Deduplicator.check(issue)

        assert match?({:ok, :unique}, result) or
                 match?({:duplicate, _}, result) or
                 match?({:similar, _}, result)
      end
    end

    test "very long bodies (>10_000 chars) are handled safely" do
      for i <- 1..5 do
        issue = %{
          title: "Long body test #{i} #{System.unique_integer([:positive])}",
          body: String.duplicate("B", 10_000)
        }

        result = FeedbackATron.Deduplicator.check(issue)

        assert match?({:ok, :unique}, result) or
                 match?({:duplicate, _}, result) or
                 match?({:similar, _}, result)
      end
    end
  end
end

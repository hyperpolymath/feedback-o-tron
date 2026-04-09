# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.Submitter.
#
# The Submitter is a GenServer that dispatches issue submissions to
# platform-specific Channel modules. These tests exercise the public
# API (submit/2, submit_batch/2, status/1) using dry-run mode to
# avoid live platform calls.

defmodule FeedbackATron.SubmitterTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure core services are running.
    case Process.whereis(FeedbackATron.Submitter) do
      nil -> FeedbackATron.Submitter.start_link([])
      _pid -> :ok
    end

    case Process.whereis(FeedbackATron.Deduplicator) do
      nil -> FeedbackATron.Deduplicator.start_link([])
      _pid -> :ok
    end

    case Process.whereis(FeedbackATron.AuditLog) do
      nil -> FeedbackATron.AuditLog.start_link([])
      _pid -> :ok
    end

    :ok = FeedbackATron.Deduplicator.clear()
    :ok
  end

  describe "submit/2 dry run" do
    test "dry run returns :dry_run status without actually submitting" do
      issue = %{title: "Test Issue", body: "Test body", repo: "owner/repo"}

      {:ok, submission_id, results} =
        FeedbackATron.Submitter.submit(issue, platforms: [:github], dry_run: true)

      assert is_binary(submission_id)
      assert length(results) == 1

      [result] = results
      assert {:ok, %{platform: :github, status: :dry_run}} = result
    end

    test "dry run with multiple platforms returns one result per platform" do
      issue = %{title: "Multi-platform test", body: "Test body", repo: "owner/repo"}

      {:ok, _id, results} =
        FeedbackATron.Submitter.submit(issue,
          platforms: [:github, :gitlab],
          dry_run: true
        )

      assert length(results) == 2
    end

    test "submission ID is unique across calls" do
      issue = %{title: "Unique ID test", body: "body", repo: "owner/repo"}

      {:ok, id1, _} = FeedbackATron.Submitter.submit(issue, dry_run: true)
      {:ok, id2, _} = FeedbackATron.Submitter.submit(issue, dry_run: true)

      assert id1 != id2
    end
  end

  describe "status/1" do
    test "status returns submission data for known ID" do
      issue = %{title: "Status test", body: "body", repo: "owner/repo"}
      {:ok, id, _} = FeedbackATron.Submitter.submit(issue, dry_run: true)

      result = FeedbackATron.Submitter.status(id)
      assert is_map(result)
      assert Map.has_key?(result, :issue)
      assert Map.has_key?(result, :results)
      assert Map.has_key?(result, :submitted_at)
    end

    test "status returns :not_found for unknown ID" do
      assert :not_found == FeedbackATron.Submitter.status("nonexistent_id")
    end
  end

  describe "deduplication integration" do
    test "submitting a duplicate issue after recording returns error" do
      issue = %{title: "Dedup integration test", body: "unique body content", repo: "owner/repo"}

      # Record the issue as already submitted.
      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)

      {:ok, _id, results} =
        FeedbackATron.Submitter.submit(issue, platforms: [:github], dedupe: true)

      # Should get a duplicate error.
      [result] = results
      assert {:error, {:duplicate_found, _}} = result
    end

    test "skipping deduplication allows submission of recorded issues" do
      issue = %{title: "Skip dedup test", body: "body for dedup skip", repo: "owner/repo"}

      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)

      {:ok, _id, results} =
        FeedbackATron.Submitter.submit(issue,
          platforms: [:github],
          dedupe: false,
          dry_run: true
        )

      [result] = results
      assert {:ok, %{status: :dry_run}} = result
    end
  end

  describe "submit_batch/2" do
    test "batch submission processes multiple issues" do
      issues = [
        %{title: "Batch issue 1", body: "body 1", repo: "owner/repo"},
        %{title: "Batch issue 2", body: "body 2", repo: "owner/repo"}
      ]

      {:ok, results} = FeedbackATron.Submitter.submit_batch(issues, dry_run: true)
      assert length(results) == 2
    end
  end
end

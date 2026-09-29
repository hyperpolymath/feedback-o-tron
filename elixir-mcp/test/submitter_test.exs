# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
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
    case Process.whereis(FeedbackATron.Consent) do
      nil -> FeedbackATron.Consent.start_link([])
      _pid -> :ok
    end

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

    case Process.whereis(FeedbackATron.RateLimiter) do
      nil -> FeedbackATron.RateLimiter.start_link([])
      _pid -> :ok
    end

    # The rate limiter is global state shared with rate_limiter_test.exs,
    # whose acquire/1 tests leave a 2 s GitHub cooldown behind them.
    for platform <- [:github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email] do
      FeedbackATron.RateLimiter.reset(platform)
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
    test "dry run does not record into the deduplicator" do
      before_stats = FeedbackATron.Deduplicator.stats()

      issue = %{title: "Dry run no-record test", body: "dry run body", repo: "owner/repo"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue, platforms: [:github], dry_run: true)

      assert {:ok, %{status: :dry_run}} = result

      # Recording is a cast; give it a moment so a regression would be caught.
      Process.sleep(50)
      after_stats = FeedbackATron.Deduplicator.stats()

      assert after_stats.total_submissions == before_stats.total_submissions
      assert after_stats.ets_size == before_stats.ets_size
    end

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

  # SP1b pre-ledger rule: nothing leaves this machine unless a person saw the
  # whole payload and typed y. Consent is a capability minted by
  # FeedbackATron.Consent at the terminal, not a claim a caller can make, so
  # every caller without one — including one that invents the value that used
  # to work — lands in the drafted clause.
  describe "consent gate" do
    test "no :consent with dry_run: false is drafted, never sent" do
      issue = %{title: "Consent gate: unconsented submit", body: "body", repo: "owner/repo"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue, platforms: [:github], dry_run: false)

      assert {:ok, %{platform: :github, status: :drafted_needs_human_consent}} = result

      {:ok, drafted} = result
      assert drafted.would_submit.title == issue.title
      assert drafted.would_submit.body == issue.body

      # Nothing was sent: the real-send branch is the only one that produces a
      # URL, and it is the only one that reads credentials.
      refute Map.has_key?(drafted, :url)
    end

    test "submit_batch with no consent drafts every issue" do
      issues = [
        %{title: "Consent gate: batch one", body: "b1", repo: "owner/repo"},
        %{title: "Consent gate: batch two", body: "b2", repo: "owner/repo"}
      ]

      {:ok, results} = FeedbackATron.Submitter.submit_batch(issues, platforms: [:github])

      assert length(results) == 2

      for {_id, platform_results} <- results do
        assert [{:ok, %{platform: :github, status: :drafted_needs_human_consent}}] =
                 platform_results
      end
    end

    test "dry_run: true is still :dry_run when consent is absent" do
      issue = %{title: "Consent gate: dry run wins", body: "body", repo: "owner/repo"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue, platforms: [:github], dry_run: true)

      assert {:ok, %{platform: :github, status: :dry_run}} = result
    end
  end

  # The forgeability tests. Every one of these fails against the tree that
  # read `Keyword.get(opts, :consent) == :human_confirmed`: there, naming the
  # atom was enough to reach the credentialed branch.
  #
  # How "reached the credentialed branch" is measured without touching the
  # network: the destination is a platform no credential can ever resolve, so
  # the send path dies at Credentials.get/2 and reports :no_credentials. That
  # is a different outcome from drafting, and it is the only one that proves
  # the gate opened. Drafting is the outcome every forgery must produce.
  describe "consent cannot be forged" do
    # A platform with no channel, no credential and no network: if the gate
    # opens, the attempt gets exactly this far and no further.
    @platform :no_such_platform

    test "the bare :human_confirmed atom is no longer consent" do
      issue = %{title: "Forged: the old atom", body: "body", repo: "owner/repo"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue,
          platforms: [@platform],
          consent: :human_confirmed
        )

      assert {:ok, %{status: :drafted_needs_human_consent}} = result
    end

    test "a fabricated token is not consent" do
      issue = %{title: "Forged: invented token", body: "body", repo: "owner/repo"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue,
          platforms: [@platform],
          consent: Base.url_encode64("not-minted-by-anyone", padding: false)
        )

      assert {:ok, %{status: :drafted_needs_human_consent}} = result
    end

    test "a real capability minted for a different payload is not consent for this one" do
      shown = %{title: "Forged: payload swap", body: "what the person saw", repo: "owner/repo"}
      {:ok, token} = FeedbackATron.Consent.issue(shown, platforms: [@platform])

      swapped = %{shown | body: "what actually gets sent"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(swapped, platforms: [@platform], consent: token)

      assert {:ok, %{status: :drafted_needs_human_consent}} = result
    end

    test "a real capability minted for other destinations is not consent for these" do
      issue = %{title: "Forged: destination swap", body: "body", repo: "owner/repo"}
      {:ok, token} = FeedbackATron.Consent.issue(issue, platforms: [:github])

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue, platforms: [:gitlab], consent: token)

      assert {:ok, %{status: :drafted_needs_human_consent}} = result
    end
  end

  describe "consent that was really given" do
    @platform :no_such_platform

    test "a capability minted at the terminal opens the send path once" do
      issue = %{title: "Consented send", body: "body", repo: "owner/repo"}
      opts = [platforms: [@platform]]

      {:ok, token} = FeedbackATron.Consent.issue(issue, opts)

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue, Keyword.put(opts, :consent, token))

      # Not drafted: the gate opened and the attempt reached the credentials.
      assert {:error, :no_credentials} = result

      # ...and the capability is spent, so the same yes cannot send twice.
      refute FeedbackATron.Consent.held_for?(issue, opts)

      {:ok, _id, [second]} =
        FeedbackATron.Submitter.submit(issue, Keyword.put(opts, :consent, token))

      assert {:ok, %{status: :drafted_needs_human_consent}} = second
    end

    test "one capability sends one report: the rest of a batch still drafts" do
      [first, second] = [
        %{title: "Batch: first", body: "b1", repo: "owner/repo"},
        %{title: "Batch: second", body: "b2", repo: "owner/repo"}
      ]

      opts = [platforms: [@platform]]
      {:ok, token} = FeedbackATron.Consent.issue(first, opts)

      {:ok, results} =
        FeedbackATron.Submitter.submit_batch([first, second], Keyword.put(opts, :consent, token))

      [{_id1, [first_result]}, {_id2, [second_result]}] = results

      assert {:error, :no_credentials} = first_result
      assert {:ok, %{status: :drafted_needs_human_consent}} = second_result
    end
  end
end

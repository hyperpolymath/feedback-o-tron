# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.ConsentTest do
  @moduledoc """
  Tests for the consent capability itself.

  The companion tests live in `submitter_test.exs`: they assert that a forged
  consent value does not reach the credentialed branch, which is the
  property the module exists to provide.
  """

  use ExUnit.Case, async: false

  alias FeedbackATron.Consent

  @issue %{title: "Consent capability test", body: "body", repo: "owner/repo"}
  @opts [platforms: [:github], labels: ["bug"]]

  setup do
    case Process.whereis(Consent) do
      nil -> Consent.start_link([])
      _pid -> :ok
    end

    :ok
  end

  describe "issue/2 + redeem/3" do
    test "a minted capability redeems exactly once" do
      assert {:ok, token} = Consent.issue(@issue, @opts)
      assert is_binary(token)
      assert byte_size(token) >= 43, "a 32-byte capability should not be short"

      assert Consent.held_for?(@issue, @opts)
      assert :ok = Consent.redeem(token, @issue, @opts)
      refute Consent.held_for?(@issue, @opts)
    end

    test "a capability is one-time: a second redeem finds nothing to spend" do
      {:ok, token} = Consent.issue(@issue, @opts)
      assert :ok = Consent.redeem(token, @issue, @opts)
      assert {:error, :unknown_capability} = Consent.redeem(token, @issue, @opts)
    end

    test "a capability is bound to the payload it was minted for" do
      {:ok, token} = Consent.issue(@issue, @opts)

      edited = %{@issue | body: @issue.body <> " and something you never saw"}

      assert {:error, :payload_mismatch} = Consent.redeem(token, edited, @opts)
    end

    test "a capability is bound to the destinations it was confirmed for" do
      {:ok, token} = Consent.issue(@issue, @opts)

      swapped = Consent.redeem(token, @issue, platforms: [:github, :gitlab], labels: ["bug"])
      assert swapped == {:error, :payload_mismatch}
    end

    test "a capability is bound to the labels it was confirmed for" do
      {:ok, token} = Consent.issue(@issue, @opts)

      swapped = Consent.redeem(token, @issue, platforms: [:github], labels: ["bug", "urgent"])
      assert swapped == {:error, :payload_mismatch}
    end
  end

  describe "redeem/3 refuses everything a caller could invent" do
    test "the bare atom that used to be enough is refused" do
      assert {:error, :no_consent} = Consent.redeem(:human_confirmed, @issue, @opts)
    end

    test "absence is refused" do
      assert {:error, :no_consent} = Consent.redeem(nil, @issue, @opts)
    end

    test "a guessed token is refused" do
      assert {:error, :unknown_capability} = Consent.redeem("let-me-in", @issue, @opts)
    end

    test "a token-shaped guess is refused" do
      guess = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :unknown_capability} = Consent.redeem(guess, @issue, @opts)
    end

    test "a truthy non-token is refused" do
      assert {:error, :no_consent} = Consent.redeem(true, @issue, @opts)
      assert {:error, :no_consent} = Consent.redeem(:yes, @issue, @opts)
      assert {:error, :no_consent} = Consent.redeem(%{consent: :human_confirmed}, @issue, @opts)
    end
  end

  describe "digest/2" do
    test "is stable for the same report regardless of option order" do
      a = Consent.digest(@issue, platforms: [:github, :gitlab], labels: ["b", "a"])
      b = Consent.digest(@issue, labels: ["a", "b"], platforms: [:gitlab, :github])

      assert a == b
    end

    test "changes when anything the person was shown changes" do
      base = Consent.digest(@issue, @opts)

      refute base == Consent.digest(%{@issue | body: "different"}, @opts)
      refute base == Consent.digest(%{@issue | title: "different"}, @opts)
      refute base == Consent.digest(%{@issue | repo: "other/repo"}, @opts)
    end
  end

  describe "expiry" do
    test "an unspent capability dies when its window passes" do
      {:ok, token} = Consent.issue(@issue, @opts)

      # Backdate the issue time rather than sleeping for five minutes.
      :sys.replace_state(Consent, fn state ->
        capabilities =
          Map.update!(state.capabilities, token, fn meta ->
            %{meta | issued_at: System.monotonic_time(:millisecond) - :timer.minutes(6)}
          end)

        %{state | capabilities: capabilities}
      end)

      assert {:error, :expired_capability} = Consent.redeem(token, @issue, @opts)
      refute Consent.held_for?(@issue, @opts)
    end
  end

  describe "failing closed" do
    test "an unreachable service is reported, never crashed through" do
      # Simulate the service being down by taking its registered name away.
      # The process stays alive, so the application supervisor has nothing to
      # restart underneath the test.
      pid = Process.whereis(Consent)
      Process.unregister(Consent)

      on_exit(fn ->
        case Process.whereis(Consent) do
          nil -> Process.register(pid, Consent)
          _registered -> :ok
        end
      end)

      assert Consent.issue(@issue, @opts) == {:error, :consent_service_unavailable}
      assert Consent.redeem("anything", @issue, @opts) == {:error, :consent_service_unavailable}
      refute Consent.held_for?(@issue, @opts)

      # And a consent service that cannot be reached must never look like
      # consent given: the Submitter's gate reads these same answers.
      issue = %{title: "Service down", body: "body", repo: "owner/repo"}

      {:ok, _id, [result]} =
        FeedbackATron.Submitter.submit(issue, platforms: [:no_such_platform])

      assert {:ok, %{status: :drafted_needs_human_consent}} = result
    end
  end
end

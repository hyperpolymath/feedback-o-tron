# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.Retry.

defmodule FeedbackATron.RetryTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Retry

  describe "with_backoff/2" do
    test "returns success on first try" do
      result = Retry.with_backoff(fn -> {:ok, "done"} end)
      assert {:ok, "done"} = result
    end

    test "retries transient errors and succeeds" do
      # Use Agent to track attempt count
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_backoff(
          fn ->
            attempt = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

            if attempt < 3 do
              {:error, :econnrefused}
            else
              {:ok, "recovered"}
            end
          end,
          max_attempts: 5,
          base_delay_ms: 10,
          jitter: false
        )

      assert {:ok, "recovered"} = result
      Agent.stop(agent)
    end

    test "gives up after max_attempts" do
      result =
        Retry.with_backoff(
          fn -> {:error, :timeout} end,
          max_attempts: 2,
          base_delay_ms: 10,
          jitter: false
        )

      assert {:error, :timeout} = result
    end

    test "does not retry non-retryable errors" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_backoff(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, %FeedbackATron.Error.AuthenticationError{platform: :github, reason: "bad token"}}
          end,
          max_attempts: 5,
          base_delay_ms: 10
        )

      assert {:error, %FeedbackATron.Error.AuthenticationError{}} = result
      # Should have only tried once
      assert Agent.get(agent, & &1) == 1
      Agent.stop(agent)
    end

    test "calls on_retry callback" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      Retry.with_backoff(
        fn -> {:error, :timeout} end,
        max_attempts: 3,
        base_delay_ms: 10,
        jitter: false,
        on_retry: fn attempt, delay, error ->
          Agent.update(agent, &[{attempt, delay, error} | &1])
        end
      )

      callbacks = Agent.get(agent, & &1)
      assert length(callbacks) == 2  # 2 retries before giving up on attempt 3
      Agent.stop(agent)
    end
  end

  describe "retryable?/1" do
    test "network errors are retryable" do
      assert Retry.retryable?(:timeout)
      assert Retry.retryable?(:econnrefused)
      assert Retry.retryable?(:econnreset)
      assert Retry.retryable?(:closed)
    end

    test "5xx status codes are retryable" do
      assert Retry.retryable?(%{status: 500})
      assert Retry.retryable?(%{status: 502})
      assert Retry.retryable?(%{status: 503})
    end

    test "auth errors are not retryable" do
      refute Retry.retryable?(%FeedbackATron.Error.AuthenticationError{
        platform: :github, reason: "bad"
      })
    end

    test "validation errors are not retryable" do
      refute Retry.retryable?(%FeedbackATron.Error.ValidationError{
        field: "title", reason: "too short"
      })
    end

    test "4xx status codes are not retryable" do
      refute Retry.retryable?(%{status: 400})
      refute Retry.retryable?(%{status: 404})
    end

    test "rate limit errors are retryable" do
      assert Retry.retryable?(%FeedbackATron.Error.RateLimitError{
        platform: :github, resets_at: nil, remaining: 0
      })
    end
  end
end

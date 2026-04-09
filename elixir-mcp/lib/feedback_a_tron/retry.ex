# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Retry do
  @moduledoc """
  Retry logic with exponential backoff for transient failures.

  Wraps any operation in a retry loop with configurable:
  - Maximum attempts
  - Base delay (doubles each retry)
  - Maximum delay cap
  - Jitter to prevent thundering herd
  - Retryable error classification
  """

  require Logger

  @default_opts [
    max_attempts: 3,
    base_delay_ms: 1_000,
    max_delay_ms: 30_000,
    jitter: true
  ]

  @doc """
  Execute a function with exponential backoff retry.

  ## Options
  - `:max_attempts` — total attempts including first try (default: 3)
  - `:base_delay_ms` — initial delay in ms, doubles each retry (default: 1000)
  - `:max_delay_ms` — cap on delay (default: 30000)
  - `:jitter` — add random jitter to delay (default: true)
  - `:on_retry` — callback `fn attempt, delay, error -> :ok end`

  ## Examples

      Retry.with_backoff(fn -> Req.post(url, json: body) end)

      Retry.with_backoff(
        fn -> some_network_call() end,
        max_attempts: 5,
        base_delay_ms: 500
      )
  """
  def with_backoff(fun, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    max = Keyword.fetch!(opts, :max_attempts)
    do_retry(fun, 1, max, opts)
  end

  defp do_retry(fun, attempt, max, opts) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, reason} = error ->
        if attempt >= max or not retryable?(reason) do
          Logger.warning(
            "[Retry] Giving up after #{attempt}/#{max} attempts: #{inspect(reason)}"
          )

          error
        else
          delay = compute_delay(attempt, opts)
          on_retry = Keyword.get(opts, :on_retry)

          if on_retry, do: on_retry.(attempt, delay, reason)

          Logger.info(
            "[Retry] Attempt #{attempt}/#{max} failed (#{inspect(reason)}), retrying in #{delay}ms"
          )

          Process.sleep(delay)
          do_retry(fun, attempt + 1, max, opts)
        end
    end
  end

  defp compute_delay(attempt, opts) do
    base = Keyword.fetch!(opts, :base_delay_ms)
    max_delay = Keyword.fetch!(opts, :max_delay_ms)
    jitter? = Keyword.fetch!(opts, :jitter)

    # Exponential: base * 2^(attempt-1)
    delay = base * Integer.pow(2, attempt - 1)
    delay = min(delay, max_delay)

    if jitter? do
      # Add up to 25% random jitter
      jitter_amount = div(delay, 4)
      delay + :rand.uniform(max(jitter_amount, 1))
    else
      delay
    end
  end

  @doc """
  Determine if an error is retryable (transient).
  Non-retryable errors are auth failures, validation errors, and 4xx responses.
  """
  def retryable?(reason) do
    case reason do
      # Network errors are retryable
      %{__exception__: true, __struct__: Req.TransportError} -> true
      %{__exception__: true, __struct__: Mint.TransportError} -> true
      :timeout -> true
      :econnrefused -> true
      :econnreset -> true
      :closed -> true
      :nxdomain -> true
      # HTTP 5xx are retryable
      %{status: status} when status >= 500 -> true
      # Rate limits are retryable (after wait)
      %FeedbackATron.Error.RateLimitError{} -> true
      %{status: 429} -> true
      # Auth and validation are NOT retryable
      %FeedbackATron.Error.AuthenticationError{} -> false
      %FeedbackATron.Error.ValidationError{} -> false
      %{status: status} when status >= 400 and status < 500 -> false
      # Default: retry unknown errors
      _ -> true
    end
  end
end

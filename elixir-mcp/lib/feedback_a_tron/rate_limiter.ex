# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.RateLimiter do
  @moduledoc """
  Per-platform rate limiting using a token bucket algorithm.

  Prevents AI agents from accidentally spamming platforms with
  too many submissions in a short time window.

  Each platform has configurable limits:
  - `max_requests`: Maximum requests per window
  - `window_ms`: Time window in milliseconds
  - `cooldown_ms`: Mandatory cooldown between requests

  Backed by ETS for fast concurrent access.
  """

  use GenServer
  require Logger

  @ets_table :feedback_rate_limits

  # Default limits per platform (requests per hour)
  @default_limits %{
    github: %{max_requests: 30, window_ms: 3_600_000, cooldown_ms: 2_000},
    gitlab: %{max_requests: 30, window_ms: 3_600_000, cooldown_ms: 2_000},
    bitbucket: %{max_requests: 20, window_ms: 3_600_000, cooldown_ms: 3_000},
    codeberg: %{max_requests: 20, window_ms: 3_600_000, cooldown_ms: 3_000},
    bugzilla: %{max_requests: 10, window_ms: 3_600_000, cooldown_ms: 5_000},
    email: %{max_requests: 10, window_ms: 3_600_000, cooldown_ms: 10_000},
    nntp: %{max_requests: 10, window_ms: 3_600_000, cooldown_ms: 10_000},
    discourse: %{max_requests: 15, window_ms: 3_600_000, cooldown_ms: 5_000},
    mailman: %{max_requests: 10, window_ms: 3_600_000, cooldown_ms: 10_000},
    sourcehut: %{max_requests: 15, window_ms: 3_600_000, cooldown_ms: 5_000},
    jira: %{max_requests: 20, window_ms: 3_600_000, cooldown_ms: 3_000},
    matrix: %{max_requests: 30, window_ms: 3_600_000, cooldown_ms: 1_000},
    discord: %{max_requests: 5, window_ms: 3_600_000, cooldown_ms: 10_000},
    reddit: %{max_requests: 5, window_ms: 3_600_000, cooldown_ms: 30_000}
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a request to the given platform is allowed.

  Returns:
  - `:ok` — request is allowed
  - `{:error, %FeedbackATron.Error.RateLimitError{}}` — rate limited
  """
  def check(platform) do
    GenServer.call(__MODULE__, {:check, platform})
  end

  @doc """
  Record that a request was made to a platform.
  Call this after a successful submission.
  """
  def record(platform) do
    GenServer.cast(__MODULE__, {:record, platform})
  end

  @doc """
  Check and record in one atomic operation.
  Returns `:ok` if allowed (and records the request), or error if rate limited.
  """
  def acquire(platform) do
    GenServer.call(__MODULE__, {:acquire, platform})
  end

  @doc """
  Get current rate limit status for a platform.
  """
  def status(platform) do
    GenServer.call(__MODULE__, {:status, platform})
  end

  @doc """
  Reset rate limit state for a platform (for testing).
  """
  def reset(platform) do
    GenServer.call(__MODULE__, {:reset, platform})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    custom_limits = Keyword.get(opts, :limits, %{})
    limits = Map.merge(@default_limits, custom_limits)
    {:ok, %{limits: limits}}
  end

  @impl true
  def handle_call({:check, platform}, _from, state) do
    result = do_check(platform, state.limits)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:acquire, platform}, _from, state) do
    case do_check(platform, state.limits) do
      :ok ->
        do_record(platform)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:status, platform}, _from, state) do
    limits = Map.get(state.limits, platform, default_limit())
    now = System.monotonic_time(:millisecond)
    requests = get_requests(platform)
    window_requests = prune_old(requests, now, limits.window_ms)

    status = %{
      platform: platform,
      used: length(window_requests),
      max: limits.max_requests,
      remaining: max(0, limits.max_requests - length(window_requests)),
      window_ms: limits.window_ms,
      cooldown_ms: limits.cooldown_ms
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:reset, platform}, _from, state) do
    :ets.delete(@ets_table, platform)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:record, platform}, state) do
    do_record(platform)
    {:noreply, state}
  end

  # Private

  defp do_check(platform, limits) do
    config = Map.get(limits, platform, default_limit())
    now = System.monotonic_time(:millisecond)
    requests = get_requests(platform)
    window_requests = prune_old(requests, now, config.window_ms)

    cond do
      # Check window limit
      length(window_requests) >= config.max_requests ->
        oldest = List.first(window_requests)
        resets_at = oldest + config.window_ms

        {:error,
         %FeedbackATron.Error.RateLimitError{
           platform: platform,
           resets_at: DateTime.add(DateTime.utc_now(), div(resets_at - now, 1000), :second),
           remaining: 0
         }}

      # Check cooldown
      length(window_requests) > 0 and now - List.last(window_requests) < config.cooldown_ms ->
        wait_ms = config.cooldown_ms - (now - List.last(window_requests))

        {:error,
         %FeedbackATron.Error.RateLimitError{
           platform: platform,
           resets_at: DateTime.add(DateTime.utc_now(), div(wait_ms, 1000) + 1, :second),
           remaining: config.max_requests - length(window_requests)
         }}

      true ->
        :ok
    end
  end

  defp do_record(platform) do
    now = System.monotonic_time(:millisecond)
    requests = get_requests(platform)
    :ets.insert(@ets_table, {platform, requests ++ [now]})
  end

  defp get_requests(platform) do
    case :ets.lookup(@ets_table, platform) do
      [{^platform, requests}] -> requests
      [] -> []
    end
  end

  defp prune_old(requests, now, window_ms) do
    Enum.filter(requests, fn ts -> now - ts < window_ms end)
  end

  defp default_limit do
    %{max_requests: 10, window_ms: 3_600_000, cooldown_ms: 5_000}
  end
end

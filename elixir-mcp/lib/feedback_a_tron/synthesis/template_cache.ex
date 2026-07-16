# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.TemplateCache do
  @moduledoc """
  ETS-backed cache for fetched issue templates with a 15-minute TTL.

  Keys are `{repo, :list}` for a repo's full template list and
  `{repo, file}` for individual parsed forms. Entries are stored as
  `{key, value, inserted_monotonic}` using `System.monotonic_time(:second)`
  so wall-clock adjustments cannot extend or shorten an entry's life.

  Reads go straight to the ETS table (`:protected` with
  `read_concurrency: true`) so cache hits never serialize through the
  GenServer; writes and evictions are owned by the server process.
  """

  use GenServer

  @ets_table :fat_template_cache
  @ttl_seconds 900

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Look up a cached value.

  Returns `{:ok, value}` for a live entry, `:miss` when the key is absent,
  expired, or the cache process is not running.
  """
  def get(key) do
    now = System.monotonic_time(:second)

    case :ets.lookup(@ets_table, key) do
      [{^key, value, inserted}] when now - inserted < @ttl_seconds ->
        {:ok, value}

      [{^key, _value, _inserted}] ->
        # Expired — evict lazily so the table doesn't accumulate dead rows.
        GenServer.cast(__MODULE__, {:evict, key})
        :miss

      [] ->
        :miss
    end
  rescue
    # Table doesn't exist (cache not started) — behave as a plain miss.
    ArgumentError -> :miss
  end

  @doc """
  Store a value under `key` with the current monotonic timestamp.

  A no-op (returns `:ok`) when the cache process is not running, so
  callers never crash just because caching is unavailable.
  """
  def put(key, value) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.call(pid, {:put, key, value})
    end
  end

  @doc """
  Drop every cached entry. Intended for tests.
  """
  def purge do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.call(pid, :purge)
    end
  end

  @doc false
  # Test hook: insert an entry with an explicit monotonic timestamp so TTL
  # expiry can be exercised without sleeping for 15 minutes.
  def put_at(key, value, inserted_monotonic) do
    GenServer.call(__MODULE__, {:put_at, key, value, inserted_monotonic})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    :ets.new(@ets_table, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    :ets.insert(@ets_table, {key, value, System.monotonic_time(:second)})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:put_at, key, value, inserted}, _from, state) do
    :ets.insert(@ets_table, {key, value, inserted})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:purge, _from, state) do
    :ets.delete_all_objects(@ets_table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:evict, key}, state) do
    :ets.delete(@ets_table, key)
    {:noreply, state}
  end
end

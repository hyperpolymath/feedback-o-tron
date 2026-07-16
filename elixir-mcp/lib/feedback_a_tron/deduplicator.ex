# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Deduplicator do
  @moduledoc """
  Prevents duplicate issue submissions across platforms.

  Uses multiple strategies:
  - Exact match: Same title and body hash
  - Fuzzy match: Similar titles (Levenshtein distance)
  - Semantic match: Key phrase extraction and comparison
  - Cross-platform tracking: Remembers what was submitted where

  Stores submission history in ETS for fast lookups.
  """

  use GenServer
  require Logger

  alias FeedbackATron.TextSimilarity

  @similarity_threshold 0.85
  @ets_table :feedback_submissions

  defstruct [
    :submissions,
    :title_index,
    :hash_index
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an issue is a duplicate.

  Returns:
  - `{:ok, :unique}` - No duplicates found
  - `{:duplicate, existing}` - Exact duplicate found
  - `{:similar, matches}` - Similar issues found (user should confirm)
  """
  def check(issue) do
    GenServer.call(__MODULE__, {:check, issue})
  end

  @doc """
  Record a successful submission.
  """
  def record(issue, platform, result) do
    GenServer.cast(__MODULE__, {:record, issue, platform, result})
  end

  @doc """
  Get submission history for an issue.
  """
  def get_history(issue_hash) do
    GenServer.call(__MODULE__, {:get_history, issue_hash})
  end

  @doc """
  Clear all submission history (for testing).
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Get statistics about submissions.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])

    state = %__MODULE__{
      submissions: %{},
      title_index: %{},
      hash_index: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check, issue}, _from, state) do
    title = issue[:title] || issue["title"] || ""
    body = issue[:body] || issue["body"] || ""
    hash = compute_hash(title, body)

    result =
      cond do
        # Check exact hash match
        Map.has_key?(state.hash_index, hash) ->
          existing = state.hash_index[hash]
          {:duplicate, existing}

        # Check fuzzy title match
        similar = find_similar_titles(title, state.title_index) ->
          if length(similar) > 0 do
            {:similar, similar}
          else
            {:ok, :unique}
          end

        true ->
          {:ok, :unique}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_history, issue_hash}, _from, state) do
    history =
      case :ets.lookup(@ets_table, issue_hash) do
        [{^issue_hash, data}] -> data
        [] -> nil
      end

    {:reply, history, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    :ets.delete_all_objects(@ets_table)

    {:reply, :ok,
     %__MODULE__{
       submissions: %{},
       title_index: %{},
       hash_index: %{}
     }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total_submissions: map_size(state.submissions),
      unique_titles: map_size(state.title_index),
      unique_hashes: map_size(state.hash_index),
      ets_size: :ets.info(@ets_table, :size)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record, issue, platform, result}, state) do
    title = issue[:title] || issue["title"] || ""
    body = issue[:body] || issue["body"] || ""
    hash = compute_hash(title, body)
    now = DateTime.utc_now()

    submission = %{
      hash: hash,
      title: title,
      platform: platform,
      result: result,
      submitted_at: now
    }

    # Store in ETS
    existing =
      case :ets.lookup(@ets_table, hash) do
        [{^hash, data}] -> data
        [] -> %{platforms: [], submissions: []}
      end

    updated = %{
      platforms: [platform | existing.platforms] |> Enum.uniq(),
      submissions: [submission | existing.submissions]
    }

    :ets.insert(@ets_table, {hash, updated})

    # Update indexes
    new_state = %{
      state
      | submissions: Map.put(state.submissions, hash, submission),
        title_index: Map.put(state.title_index, TextSimilarity.normalize_title(title), hash),
        hash_index: Map.put(state.hash_index, hash, submission)
    }

    Logger.info("Recorded submission: #{platform} - #{truncate(title, 50)}")

    {:noreply, new_state}
  end

  # Private functions

  defp compute_hash(title, body) do
    content = "#{TextSimilarity.normalize_title(title)}:#{TextSimilarity.normalize_body(body)}"
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  defp find_similar_titles(title, title_index) do
    normalized = TextSimilarity.normalize_title(title)

    title_index
    |> Enum.filter(fn {indexed_title, _hash} ->
      TextSimilarity.similarity(normalized, indexed_title) >= @similarity_threshold
    end)
    |> Enum.map(fn {indexed_title, hash} ->
      %{
        title: indexed_title,
        hash: hash,
        similarity: TextSimilarity.similarity(normalized, indexed_title)
      }
    end)
    |> Enum.sort_by(& &1.similarity, :desc)
    |> Enum.take(5)
  end

  defp truncate(string, max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length - 3) <> "..."
    else
      string
    end
  end
end

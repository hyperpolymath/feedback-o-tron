# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.BatchReviewer do
  @moduledoc """
  ETS-backed queue for migration issues awaiting human review.

  Issues discovered during migration observation are queued here before
  submission to rescript-lang/rescript or other targets. Follows the same
  ETS pattern as `FeedbackATron.Deduplicator`.

  MCP tools:
  - `review_migration_queue` — list pending items, approve/reject/edit
  - `submit_approved_migrations` — send approved items via Submitter
  """

  use GenServer

  require Logger

  @ets_table :migration_review_queue

  defstruct [
    :queue,
    :approved,
    :rejected,
    :submitted
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Enqueue an issue for review"
  def enqueue(issue) do
    GenServer.cast(__MODULE__, {:enqueue, issue})
  end

  @doc "List all pending items in the review queue"
  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  @doc "Approve an item by ID"
  def approve(item_id, edits \\ %{}) do
    GenServer.call(__MODULE__, {:approve, item_id, edits})
  end

  @doc "Reject an item by ID with an optional reason"
  def reject(item_id, reason \\ nil) do
    GenServer.call(__MODULE__, {:reject, item_id, reason})
  end

  @doc "Submit all approved items via the Submitter"
  def submit_approved do
    GenServer.call(__MODULE__, :submit_approved, :timer.minutes(5))
  end

  @doc "Get queue statistics"
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])

    state = %__MODULE__{
      queue: %{},
      approved: %{},
      rejected: %{},
      submitted: %{}
    }

    Logger.info("[BatchReviewer] Started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, issue}, state) do
    item_id = generate_item_id()

    item = %{
      id: item_id,
      issue: issue,
      enqueued_at: DateTime.utc_now(),
      status: :pending,
      edits: %{},
      rejection_reason: nil
    }

    :ets.insert(@ets_table, {item_id, item})

    Logger.debug("[BatchReviewer] Enqueued: #{item_id} - #{issue.title}")
    {:noreply, %{state | queue: Map.put(state.queue, item_id, item)}}
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    pending =
      state.queue
      |> Enum.filter(fn {_id, item} -> item.status == :pending end)
      |> Enum.map(fn {_id, item} -> item end)
      |> Enum.sort_by(& &1.enqueued_at, DateTime)

    {:reply, pending, state}
  end

  def handle_call({:approve, item_id, edits}, _from, state) do
    case Map.get(state.queue, item_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      item ->
        updated_item = %{item | status: :approved, edits: edits}
        :ets.insert(@ets_table, {item_id, updated_item})

        new_state = %{
          state
          | queue: Map.put(state.queue, item_id, updated_item),
            approved: Map.put(state.approved, item_id, updated_item)
        }

        Logger.info("[BatchReviewer] Approved: #{item_id}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:reject, item_id, reason}, _from, state) do
    case Map.get(state.queue, item_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      item ->
        updated_item = %{item | status: :rejected, rejection_reason: reason}
        :ets.insert(@ets_table, {item_id, updated_item})

        new_state = %{
          state
          | queue: Map.put(state.queue, item_id, updated_item),
            rejected: Map.put(state.rejected, item_id, updated_item)
        }

        Logger.info("[BatchReviewer] Rejected: #{item_id} - #{reason || "no reason"}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:submit_approved, _from, state) do
    approved_items =
      state.approved
      |> Enum.filter(fn {_id, item} -> item.status == :approved end)
      |> Enum.map(fn {_id, item} -> item end)

    results =
      Enum.map(approved_items, fn item ->
        issue = apply_edits(item.issue, item.edits)

        case FeedbackATron.Submitter.submit(issue, platforms: [:github]) do
          {:ok, submission_id, results} ->
            Logger.info("[BatchReviewer] Submitted: #{item.id} -> #{submission_id}")
            {:ok, %{item_id: item.id, submission_id: submission_id, results: results}}

          {:error, reason} ->
            Logger.error("[BatchReviewer] Submit failed: #{item.id} - #{inspect(reason)}")
            {:error, %{item_id: item.id, reason: reason}}
        end
      end)

    # Move submitted items
    submitted_ids = for {:ok, %{item_id: id}} <- results, do: id

    new_submitted =
      Enum.reduce(submitted_ids, state.submitted, fn id, acc ->
        case Map.get(state.approved, id) do
          nil -> acc
          item -> Map.put(acc, id, %{item | status: :submitted})
        end
      end)

    new_approved = Map.drop(state.approved, submitted_ids)

    new_state = %{state | approved: new_approved, submitted: new_submitted}
    {:reply, {:ok, results}, new_state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      pending: state.queue |> Enum.count(fn {_id, i} -> i.status == :pending end),
      approved: map_size(state.approved),
      rejected: map_size(state.rejected),
      submitted: map_size(state.submitted),
      total: map_size(state.queue)
    }

    {:reply, stats, state}
  end

  # --- Private Helpers ---

  defp apply_edits(issue, edits) when map_size(edits) == 0, do: issue

  defp apply_edits(issue, edits) do
    issue
    |> then(fn i ->
      if Map.has_key?(edits, :title), do: Map.put(i, :title, edits.title), else: i
    end)
    |> then(fn i ->
      if Map.has_key?(edits, :body), do: Map.put(i, :body, edits.body), else: i
    end)
    |> then(fn i ->
      if Map.has_key?(edits, :repo), do: Map.put(i, :repo, edits.repo), else: i
    end)
  end

  defp generate_item_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end
end

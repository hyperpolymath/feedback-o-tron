# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.Pipeline.Producer do
  @moduledoc """
  GenStage producer that emits completed migration sessions.

  The MigrationObserver pushes completed sessions into this producer,
  which then dispatches them to downstream consumers (VeriSimConsumer,
  ReviewConsumer).
  """

  use GenStage

  require Logger

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Push a completed migration session into the pipeline"
  def push_session(session) do
    GenStage.cast(__MODULE__, {:push, session})
  end

  # --- GenStage Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("[Pipeline.Producer] Started")
    {:producer, %{queue: :queue.new()}}
  end

  @impl true
  def handle_cast({:push, session}, %{queue: queue} = state) do
    new_queue = :queue.in(session, queue)
    {:noreply, [], %{state | queue: new_queue}}
  end

  @impl true
  def handle_demand(demand, %{queue: queue} = state) when demand > 0 do
    {events, remaining} = take_from_queue(queue, demand)
    {:noreply, events, %{state | queue: remaining}}
  end

  defp take_from_queue(queue, count) do
    take_from_queue(queue, count, [])
  end

  defp take_from_queue(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_from_queue(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, remaining} ->
        take_from_queue(remaining, count - 1, [item | acc])

      {:empty, _} ->
        {Enum.reverse(acc), queue}
    end
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.Pipeline.VeriSimConsumer do
  @moduledoc """
  GenStage consumer that writes completed migration sessions to VeriSimDB.

  Subscribes to the Pipeline.Producer and persists each session as a
  hexad via VeriSimWriter.
  """

  use GenStage

  require Logger

  alias FeedbackATron.VeriSimWriter

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[Pipeline.VeriSimConsumer] Started")

    {:consumer, %{},
     subscribe_to: [{FeedbackATron.Pipeline.Producer, max_demand: 5, min_demand: 1}]}
  end

  @impl true
  def handle_events(sessions, _from, state) do
    for session <- sessions do
      case VeriSimWriter.write_migration_session(session) do
        {:ok, hexad_id} ->
          Logger.info("[VeriSimConsumer] Wrote hexad: #{hexad_id}")

        {:error, reason} ->
          Logger.error("[VeriSimConsumer] Failed to write hexad: #{inspect(reason)}")
      end
    end

    {:noreply, [], state}
  end
end

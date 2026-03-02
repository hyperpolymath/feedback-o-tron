# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule FeedbackATron.Pipeline.Supervisor do
  @moduledoc """
  Supervisor for the migration observation GenStage pipeline.

  ```
  MigrationObserver (Producer) -> VeriSimConsumer (writes hexads)
                                -> ReviewConsumer (queues for review)
  ```

  Started conditionally when `--migration-observer` flag is set or
  `FEEDBACK_A_TRON_MIGRATION_MODE` environment variable is truthy.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {FeedbackATron.Pipeline.Producer, []},
      {FeedbackATron.Pipeline.VeriSimConsumer, []},
      {FeedbackATron.Pipeline.ReviewConsumer, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

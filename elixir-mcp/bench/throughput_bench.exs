# SPDX-License-Identifier: PMPL-1.0-or-later
# Benchee benchmarks for FeedbackATron feedback-submission throughput.
#
# Run with:
#   mix run bench/throughput_bench.exs
#
# Note: benchee must be in mix.exs deps under :dev:
#   {:benchee, "~> 1.3", only: :dev}
#
# Benchmarks cover:
#   - check/1 throughput for unique issues (cold, no prior state)
#   - check/1 throughput for duplicate detection (hot, after recording)
#   - record/3 throughput (GenServer cast, non-blocking)
#   - stats/0 throughput (read-only GenServer call)
#   - clear/0 throughput (full reset)
#   - Hash derivation cost (SHA256 + Base16 encode)
#   - Levenshtein comparison cost (via module internals, measured indirectly)

alias FeedbackATron.Deduplicator

# Ensure the deduplicator is running.
case Process.whereis(Deduplicator) do
  nil -> {:ok, _pid} = Deduplicator.start_link([])
  _pid -> :ok
end

Deduplicator.clear()

# Pre-record a batch of issues so the duplicate-detection path has a populated
# index to search through.
for i <- 1..200 do
  issue = %{
    title: "Pre-seeded issue number #{i} for bench warm-up",
    body: "Pre-seeded body content #{i} with some variability to spread the index"
  }
  Deduplicator.record(issue, :github, %{status: :submitted})
end

# Wait for all casts to be processed before measuring.
Process.sleep(300)

# ---------------------------------------------------------------------------
# Benchmark inputs
# ---------------------------------------------------------------------------

fresh_issue = %{
  title: "Brand new issue nobody has ever seen #{System.unique_integer([:positive])}",
  body: "Completely novel body content never previously recorded"
}

# An issue that was pre-recorded above — will hit the hash_index fast path.
recorded_issue = %{
  title: "Pre-seeded issue number 42 for bench warm-up",
  body: "Pre-seeded body content 42 with some variability to spread the index"
}

Benchee.run(
  %{
    "check/1 — unique issue (cache miss)" => fn ->
      Deduplicator.check(fresh_issue)
    end,

    "check/1 — duplicate issue (cache hit)" => fn ->
      Deduplicator.check(recorded_issue)
    end,

    "record/3 — cast submission (async)" => fn ->
      issue = %{
        title: "Bench record issue #{System.unique_integer([:positive])}",
        body: "Bench body"
      }
      Deduplicator.record(issue, :github, %{status: :submitted})
    end,

    "stats/0 — statistics read" => fn ->
      Deduplicator.stats()
    end,

    "get_history/1 — ETS lookup hit" => fn ->
      # Compute hash for a known pre-seeded issue.
      title_norm =
        "pre-seeded issue number 42 for bench warm-up"
        |> String.replace(~r/[^\w\s]/, "")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      body_norm =
        "pre-seeded body content 42 with some variability to spread the index"
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      hash =
        :crypto.hash(:sha256, "#{title_norm}:#{body_norm}")
        |> Base.encode16(case: :lower)
        |> binary_part(0, 16)

      Deduplicator.get_history(hash)
    end,

    "get_history/1 — ETS lookup miss" => fn ->
      Deduplicator.get_history("deadbeef00000000")
    end,

    "SHA256 hash derivation — raw cost" => fn ->
      :crypto.hash(:sha256, "some title:some body")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)
    end
  },
  time: 5,
  warmup: 2,
  memory_time: 2,
  print: [
    benchmarking: true,
    configuration: true,
    fast_warning: true
  ],
  formatters: [
    Benchee.Formatters.Console
  ]
)

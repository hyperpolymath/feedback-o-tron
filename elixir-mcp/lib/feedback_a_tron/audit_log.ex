defmodule FeedbackATron.AuditLog do
  @moduledoc """
  Comprehensive audit logging for all FeedbackATron operations.

  Records:
  - All submission attempts (success and failure)
  - Network verification results
  - Credential usage (no secrets logged)
  - Deduplication decisions
  - User actions

  Supports multiple output formats:
  - File (JSON lines)
  - Console (structured)
  - External (webhook)
  """

  use GenServer
  require Logger

  @log_file "feedback_a_tron_audit.jsonl"
  @max_log_size 10_000_000  # 10MB before rotation

  defstruct [
    :log_file,
    :log_handle,
    :entry_count,
    :session_id,
    :started_at
  ]

  # Event types
  @event_types [
    :submission_attempt,
    :submission_success,
    :submission_failure,
    :network_check,
    :dedup_check,
    :dedup_match,
    :credential_use,
    :credential_rotate,
    :config_change,
    :startup,
    :shutdown
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Log an audit event.
  """
  def log(event_type, data \\ %{}) when event_type in @event_types do
    GenServer.cast(__MODULE__, {:log, event_type, data})
  end

  @doc """
  Log a submission attempt.
  """
  def log_submission(platform, issue, status, details \\ %{}) do
    event_type = case status do
      :success -> :submission_success
      :failure -> :submission_failure
      _ -> :submission_attempt
    end

    log(event_type, %{
      platform: platform,
      title: issue[:title] || issue["title"],
      status: status,
      details: sanitize(details)
    })
  end

  @doc """
  Log network verification.
  """
  def log_network_check(host, results) do
    log(:network_check, %{
      host: host,
      latency_ms: results[:latency],
      dns_ok: results[:dns_ok],
      tls_ok: results[:tls_ok],
      overall: results[:overall]
    })
  end

  @doc """
  Log deduplication check.
  """
  def log_dedup(issue_hash, result, details \\ %{}) do
    event_type = case result do
      :duplicate -> :dedup_match
      :similar -> :dedup_match
      _ -> :dedup_check
    end

    log(event_type, %{
      hash: issue_hash,
      result: result,
      details: details
    })
  end

  @doc """
  Get recent log entries.
  """
  def recent(count \\ 100) do
    GenServer.call(__MODULE__, {:recent, count})
  end

  @doc """
  Get session statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Export logs to file.
  """
  def export(path) do
    GenServer.call(__MODULE__, {:export, path})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    log_dir = Keyword.get(opts, :log_dir, System.tmp_dir!())
    log_path = Path.join(log_dir, @log_file)

    # Open log file
    {:ok, handle} = File.open(log_path, [:append, :utf8])

    session_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    now = DateTime.utc_now()

    state = %__MODULE__{
      log_file: log_path,
      log_handle: handle,
      entry_count: 0,
      session_id: session_id,
      started_at: now
    }

    # Log startup
    write_entry(state, :startup, %{
      session_id: session_id,
      version: Application.spec(:feedback_a_tron, :vsn) |> to_string(),
      node: Node.self()
    })

    {:ok, state}
  end

  @impl true
  def handle_cast({:log, event_type, data}, state) do
    new_state = write_entry(state, event_type, data)

    # Check for rotation
    new_state = maybe_rotate(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:recent, count}, _from, state) do
    # Read last N lines from log file
    entries = read_recent_entries(state.log_file, count)
    {:reply, entries, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      session_id: state.session_id,
      started_at: state.started_at,
      entry_count: state.entry_count,
      log_file: state.log_file,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:export, path}, _from, state) do
    result = File.cp(state.log_file, path)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    write_entry(state, :shutdown, %{
      session_id: state.session_id,
      entry_count: state.entry_count
    })
    File.close(state.log_handle)
    :ok
  end

  # Private functions

  defp write_entry(state, event_type, data) do
    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      session_id: state.session_id,
      event: event_type,
      data: data
    }

    line = Jason.encode!(entry) <> "\n"
    IO.write(state.log_handle, line)

    # Also log to console in dev
    if Mix.env() == :dev do
      Logger.debug("[AUDIT] #{event_type}: #{inspect(data)}")
    end

    %{state | entry_count: state.entry_count + 1}
  end

  defp maybe_rotate(state) do
    case File.stat(state.log_file) do
      {:ok, %{size: size}} when size > @max_log_size ->
        rotate_log(state)
      _ ->
        state
    end
  end

  defp rotate_log(state) do
    File.close(state.log_handle)

    # Rename with timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:\.]/, "-")
    rotated_path = String.replace(state.log_file, ".jsonl", "_#{timestamp}.jsonl")
    File.rename(state.log_file, rotated_path)

    # Open new file
    {:ok, handle} = File.open(state.log_file, [:append, :utf8])

    Logger.info("Rotated audit log to #{rotated_path}")

    %{state | log_handle: handle}
  end

  defp read_recent_entries(log_file, count) do
    case File.read(log_file) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.take(-count)
        |> Enum.map(&Jason.decode!/1)

      {:error, _} ->
        []
    end
  end

  defp sanitize(data) when is_map(data) do
    # Remove sensitive fields
    sensitive_keys = ~w(password token secret key api_key access_token)a ++
                     ~w(password token secret key api_key access_token)

    data
    |> Enum.reject(fn {k, _v} ->
      key_str = to_string(k) |> String.downcase()
      Enum.any?(sensitive_keys, &(String.contains?(key_str, to_string(&1))))
    end)
    |> Enum.into(%{})
  end

  defp sanitize(data), do: data
end

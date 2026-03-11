defmodule FeedbackATron.Submitter do
  @moduledoc """
  Automated feedback/issue submission across multiple platforms.

  Supports:
  - GitHub Issues (via gh CLI or API)
  - GitLab Issues (via glab CLI or API)
  - Bitbucket Issues (via API)
  - Codeberg Issues (via API - Gitea compatible)
  - Email (for non-git platforms)
  - Discussion forums (via API where available)

  Features:
  - Credential rotation to avoid rate limits
  - Template-based issue formatting
  - Deduplication via semantic matching
  - Dry-run mode for verification
  - Audit logging
  """

  use GenServer
  require Logger

  alias FeedbackATron.{Channel, Credentials, Deduplicator, AuditLog}



  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Submit feedback/issue to specified platform(s).

  ## Options
  - `:platforms` - list of platforms to submit to (default: [:github])
  - `:dry_run` - if true, don't actually submit (default: false)
  - `:template` - template name for formatting
  - `:dedupe` - check for existing similar issues (default: true)
  - `:labels` - list of labels to apply

  ## Examples

      FeedbackATron.Submitter.submit(%{
        title: "SEP: DNS-Based MCP Server Verification",
        body: "...",
        repo: "modelcontextprotocol/modelcontextprotocol"
      }, platforms: [:github])
  """
  def submit(issue, opts \\ []) do
    GenServer.call(__MODULE__, {:submit, issue, opts}, :timer.minutes(2))
  end

  @doc """
  Submit to multiple repos/platforms in batch.
  """
  def submit_batch(issues, opts \\ []) do
    GenServer.call(__MODULE__, {:submit_batch, issues, opts}, :timer.minutes(10))
  end

  @doc """
  Check submission status.
  """
  def status(submission_id) do
    GenServer.call(__MODULE__, {:status, submission_id})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      submissions: %{},
      credentials: Credentials.load(),
      rate_limits: %{},
      opts: opts
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:submit, issue, opts}, _from, state) do
    platforms = Keyword.get(opts, :platforms, [:github])
    dry_run = Keyword.get(opts, :dry_run, false)
    dedupe = Keyword.get(opts, :dedupe, true)

    results =
      platforms
      |> Enum.map(fn platform ->
        with :ok <- check_rate_limit(state, platform),
             :ok <- maybe_dedupe(dedupe, platform, issue),
             {:ok, cred} <- Credentials.get(state.credentials, platform) do
          if dry_run do
            {:ok, %{platform: platform, status: :dry_run, would_submit: issue}}
          else
            do_submit(platform, issue, cred, opts)
          end
        end
      end)

    submission_id = generate_id()
    new_state = put_in(state.submissions[submission_id], %{
      issue: issue,
      results: results,
      submitted_at: DateTime.utc_now()
    })

    AuditLog.log(:submission, %{id: submission_id, issue: issue, results: results})

    {:reply, {:ok, submission_id, results}, new_state}
  end

  @impl true
  def handle_call({:submit_batch, issues, opts}, _from, state) do
    results = Enum.map(issues, fn issue ->
      {:ok, id, result} = handle_call({:submit, issue, opts}, nil, state)
      {id, result}
    end)
    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_call({:status, submission_id}, _from, state) do
    result = Map.get(state.submissions, submission_id, :not_found)
    {:reply, result, state}
  end

  # Platform-specific submission — delegates to Channel behaviour modules

  defp do_submit(platform, issue, cred, opts) do
    case Channel.get(platform) do
      {:ok, channel_mod} ->
        channel_mod.submit(issue, cred, opts)

      {:error, :unknown_platform} ->
        {:error, %{platform: platform, error: :unknown_platform}}
    end
  end

  # Helpers

  defp check_rate_limit(state, platform) do
    case Map.get(state.rate_limits, platform) do
      nil -> :ok
      %{remaining: 0, resets_at: reset} ->
        if DateTime.compare(reset, DateTime.utc_now()) == :gt do
          {:error, :rate_limited}
        else
          :ok
        end
      _ -> :ok
    end
  end

  defp maybe_dedupe(false, _platform, _issue), do: :ok
  defp maybe_dedupe(true, _platform, issue) do
    case Deduplicator.check(issue) do
      {:ok, :unique} -> :ok
      {:duplicate, existing} -> {:error, {:duplicate_found, existing}}
      {:similar, matches} -> {:error, {:similar_found, matches}}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end

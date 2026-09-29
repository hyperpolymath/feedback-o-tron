# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Consent do
  @moduledoc """
  The one place where a person's typed `y` becomes something the engine acts on.

  ## Why this module exists

  `Submitter` used to take the caller's word for it: an option reading
  `:human_confirmed` selected the credentialed branch, so any code already
  running in the VM could name the atom and send. A gate made of ordinary
  data is not a gate. The estate's own doctrine puts it as *a default is not
  a gate*; the equivalent here is that **a claim is not a proof** — and a
  bare atom that any term can equal is a claim.

  So consent is now a **capability**: an unguessable, one-time, payload-bound
  value that only this module can mint, and only the trusted submission
  boundary (`FeedbackATron.CLI`, after the person read the payload at a
  terminal and typed yes) asks it to mint one.

  ## The properties, and what they do and do not buy

  * **Unguessable** — 256 bits from `crypto.strong_rand_bytes/1`. A wire
    client cannot mint one, and cannot guess one: the MCP door and the HTTP
    door are structurally incapable of asserting consent, which is what the
    pre-ledger rule always claimed.
  * **One-time** — redeeming deletes the capability. It cannot be replayed
    by a second submit call, or by the batch path.
  * **Payload-bound** — a capability is issued over a digest of *exactly* the
    report, destinations and labels that were shown to the person. Change one
    character after the confirm and the capability no longer fits, so a
    leaked or replayed value cannot be used to send something else.
  * **Expiring** — a capability that is not spent within `@ttl_ms` dies. A
    confirmation is about a report read now, not a licence to send later.

  **The residual, stated plainly:** code that can already call
  `FeedbackATron.Consent.issue/2` inside this VM can mint its own
  capability, and such code can equally call `FeedbackATron.Channel`
  directly. This module removes *data* as a way to assert consent — the way
  that mattered, because it is the one a remote client could reach. It is
  not, and cannot be, a defence against arbitrary code execution in the VM.

  ## What is deliberately absent

  There is no `--yes` flag, and no way to mint a capability from a
  non-terminal. Non-tty still means no; an assistant must never type the `y`
  on the person's behalf.
  """

  use GenServer

  require Logger

  @name __MODULE__

  # A confirmation is about the report on the screen now. Five minutes is
  # generous for a person re-reading a long payload, short enough that a
  # capability cannot be hoarded for later use.
  @ttl_ms :timer.minutes(5)

  @typedoc """
  An opaque consent capability. Minted by `issue/2`, spent by `redeem/3`.
  """
  @type token :: String.t()

  # Client API

  @doc """
  Mint a consent capability for exactly this report, to exactly these destinations.

  Called only by `FeedbackATron.CLI`, only after the person has seen the whole
  payload and typed y. Everything else drafts.

  Returns `{:error, :consent_service_unavailable}` rather than raising when
  the service is not running: a consent system that crashes open would be
  worse than one that refuses.
  """
  @spec issue(map(), keyword()) :: {:ok, token()} | {:error, :consent_service_unavailable}
  def issue(issue, opts) when is_map(issue) and is_list(opts) do
    case Process.whereis(@name) do
      nil -> {:error, :consent_service_unavailable}
      pid -> GenServer.call(pid, {:issue, digest(issue, opts), self()})
    end
  end

  @doc """
  Spend a consent capability, if it is real, unspent, unexpired, and bound to
  this exact report.

  Returns `:ok` exactly once per capability. Every failure mode returns
  `{:error, reason}` so the caller can only ever fail closed.
  """
  @spec redeem(term(), map(), keyword()) ::
          :ok
          | {:error, :no_consent | :unknown_capability | :payload_mismatch | :expired_capability}
  def redeem(token, issue, opts) when is_binary(token) and is_map(issue) and is_list(opts) do
    case Process.whereis(@name) do
      nil -> {:error, :consent_service_unavailable}
      pid -> GenServer.call(pid, {:redeem, token, digest(issue, opts)})
    end
  end

  def redeem(_token, _issue, _opts), do: {:error, :no_consent}

  @doc """
  The digest a capability is bound to: the report as confirmed, plus where it
  was confirmed to go.

  Deliberately computed from the issue *as handed to the engine*, before any
  template hydration rewrites the body — the person confirmed what they were
  shown, and that is what the capability covers.
  """
  @spec digest(map(), keyword()) :: binary()
  def digest(issue, opts) when is_map(issue) do
    payload = %{
      title: Map.get(issue, :title),
      body: Map.get(issue, :body),
      repo: Map.get(issue, :repo),
      template: Map.get(issue, :template),
      template_data: Map.get(issue, :template_data),
      platforms: opts |> Keyword.get(:platforms, [:github]) |> List.wrap() |> Enum.sort(),
      labels: opts |> Keyword.get(:labels, []) |> List.wrap() |> Enum.sort()
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(payload))
  end

  @doc """
  True when a capability exists for this report right now, without spending it.

  For tests and diagnostics only. The send path uses `redeem/3`.
  """
  @spec held_for?(map(), keyword()) :: boolean()
  def held_for?(issue, opts) when is_map(issue) and is_list(opts) do
    case Process.whereis(@name) do
      nil -> false
      pid -> GenServer.call(pid, {:held_for, digest(issue, opts)})
    end
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{capabilities: %{}}}
  end

  @impl true
  def handle_call({:issue, digest, pid}, _from, state) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    now = System.monotonic_time(:millisecond)

    capabilities =
      state.capabilities
      |> Enum.reject(fn {_token, meta} -> expired?(meta, now) end)
      |> Map.new()
      |> Map.put(token, %{digest: digest, issued_at: now, issued_to: pid})

    {:reply, {:ok, token}, %{state | capabilities: capabilities}}
  end

  @impl true
  def handle_call({:redeem, token, digest}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.fetch(state.capabilities, token) do
      :error ->
        {:reply, {:error, :unknown_capability}, state}

      {:ok, %{digest: ^digest, issued_at: issued_at}} when now - issued_at <= @ttl_ms ->
        # One-time, spent or not: it leaves the table either way, so a
        # mismatch cannot be retried with the same value.
        capabilities = Map.delete(state.capabilities, token)
        {:reply, :ok, %{state | capabilities: capabilities}}

      {:ok, %{digest: ^digest}} ->
        capabilities = Map.delete(state.capabilities, token)
        {:reply, {:error, :expired_capability}, %{state | capabilities: capabilities}}

      {:ok, _meta} ->
        Logger.warning(
          "consent capability spent against a different payload; discarded. " <>
            "A capability covers exactly the report that was shown."
        )

        capabilities = Map.delete(state.capabilities, token)
        {:reply, {:error, :payload_mismatch}, %{state | capabilities: capabilities}}
    end
  end

  @impl true
  def handle_call({:held_for, digest}, _from, state) do
    now = System.monotonic_time(:millisecond)

    held? =
      Enum.any?(state.capabilities, fn {_token, meta} ->
        meta.digest == digest and not expired?(meta, now)
      end)

    {:reply, held?, state}
  end

  defp expired?(%{issued_at: issued_at}, now), do: now - issued_at > @ttl_ms
end

# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Email do
  @moduledoc """
  Email channel — SMTPS only (port 465, implicit TLS).

  Direct email submission for platforms without APIs.
  Uses the same SMTPS infrastructure as the Mailman channel.

  No plaintext SMTP ever.
  DNS resolution via DoH/DoT exclusively (see SecureDNS).
  """

  @behaviour FeedbackATron.Channel

  require Logger

  @impl true
  def platform, do: :email

  @impl true
  def transport, do: :smtps

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:smtp_server]) -> {:error, "SMTP server required"}
      is_nil(cred[:from_address]) -> {:error, "From address required"}
      true -> :ok
    end
  end

  @impl true
  def submit(_issue, _cred, _opts) do
    # Email submission delegates to Mailman's SMTPS transport.
    # Standalone email will be implemented when gen_smtp or swoosh is added.
    Logger.warning("Email channel: use Mailman channel for SMTPS email submission")
    {:error, %{platform: :email, error: :not_implemented, reason: "Use Mailman channel for SMTPS"}}
  end
end

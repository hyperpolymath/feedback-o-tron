# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Discord do
  @moduledoc """
  Discord channel — HTTPS only.

  Submits feedback as Discord embeds via two modes:
  - **Bot token**: POST to /channels/{channel_id}/messages (requires bot in server)
  - **Webhook URL**: POST to webhook endpoint (simpler, no bot needed)

  DNS resolution via DoH/DoT exclusively (see SecureDNS).

  ## Bot mode credentials

      %{token: "Bot ...", channel_id: "123456..."}

  ## Webhook mode credentials

      %{webhook_url: "https://discord.com/api/webhooks/..."}

  Author: Jonathan D.A. Jewell
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  @discord_api_base "https://discord.com/api/v10"

  # Embed colour: feedback-o-tron brand blue
  @embed_colour 0x5865F2

  @impl true
  def platform, do: :discord

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    cond do
      # Webhook mode — only need a valid HTTPS webhook URL
      not is_nil(cred[:webhook_url]) ->
        if String.starts_with?(cred[:webhook_url], "https://discord.com/api/webhooks/") do
          :ok
        else
          {:error, "Discord webhook URL must start with https://discord.com/api/webhooks/"}
        end

      # Bot mode — need token and channel_id
      not is_nil(cred[:token]) ->
        cond do
          not String.starts_with?(cred[:token] || "", "Bot ") ->
            {:error, "Discord bot token must start with 'Bot '"}
          is_nil(cred[:channel_id]) ->
            {:error, "Discord channel_id required for bot mode"}
          true ->
            :ok
        end

      true ->
        {:error, "Discord credentials require either :webhook_url or :token + :channel_id"}
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    if cred[:webhook_url] do
      submit_webhook(issue, cred, opts)
    else
      submit_bot(issue, cred, opts)
    end
  end

  # --- Bot mode: POST /channels/{channel_id}/messages ---

  defp submit_bot(issue, cred, _opts) do
    channel_id = cred.channel_id

    with {:ok, _ips} <- SecureDNS.resolve("discord.com") do
      embed = build_embed(issue)

      headers = [
        {"Authorization", cred.token},
        {"Content-Type", "application/json"}
      ]

      url = "#{@discord_api_base}/channels/#{channel_id}/messages"

      case Req.post(url, json: %{embeds: [embed]}, headers: headers, receive_timeout: 15_000) do
        {:ok, %{status: 200, body: resp}} ->
          message_id = resp["id"]
          guild_id = resp["guild_id"] || "unknown"
          msg_channel_id = resp["channel_id"] || channel_id
          {:ok, %{platform: :discord, url: "https://discord.com/channels/#{guild_id}/#{msg_channel_id}/#{message_id}"}}

        {:ok, %{status: status, body: resp}} ->
          error_msg = extract_error(resp)
          Logger.error("Discord bot API error #{status}: #{error_msg}")
          {:error, %{platform: :discord, status: status, error: error_msg}}

        {:error, reason} ->
          {:error, %{platform: :discord, error: reason}}
      end
    else
      {:error, reason} ->
        {:error, %{platform: :discord, error: {:dns_failed, reason}}}
    end
  end

  # --- Webhook mode: POST to webhook URL ---

  defp submit_webhook(issue, cred, _opts) do
    webhook_url = cred.webhook_url

    # Extract hostname from webhook URL for secure DNS
    %URI{host: hostname} = URI.parse(webhook_url)

    with {:ok, _ips} <- SecureDNS.resolve(hostname) do
      embed = build_embed(issue)

      # Append ?wait=true so Discord returns the message object
      post_url = "#{webhook_url}?wait=true"

      case Req.post(post_url, json: %{embeds: [embed]}, receive_timeout: 15_000) do
        {:ok, %{status: 200, body: _resp}} ->
          # Webhooks don't return enough info to construct a full message URL
          {:ok, %{platform: :discord, url: webhook_url}}

        {:ok, %{status: status, body: resp}} ->
          error_msg = extract_error(resp)
          Logger.error("Discord webhook error #{status}: #{error_msg}")
          {:error, %{platform: :discord, status: status, error: error_msg}}

        {:error, reason} ->
          {:error, %{platform: :discord, error: reason}}
      end
    else
      {:error, reason} ->
        {:error, %{platform: :discord, error: {:dns_failed, reason}}}
    end
  end

  # --- Helpers ---

  @doc false
  defp build_embed(issue) do
    embed = %{
      title: issue.title,
      description: issue.body,
      color: @embed_colour
    }

    # Include repo info as a footer if available
    if issue[:repo] do
      Map.put(embed, :footer, %{text: "Repository: #{issue.repo}"})
    else
      embed
    end
  end

  defp extract_error(%{"message" => msg}), do: msg
  defp extract_error(%{"code" => code, "message" => msg}), do: "#{code}: #{msg}"
  defp extract_error(other), do: inspect(other)
end

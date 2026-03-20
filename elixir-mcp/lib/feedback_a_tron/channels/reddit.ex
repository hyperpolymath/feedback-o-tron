# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channels.Reddit do
  @moduledoc """
  Reddit channel — HTTPS only.

  Submits feedback as self-posts to a subreddit via OAuth2.

  Authentication flow:
  1. POST to https://www.reddit.com/api/v1/access_token with Basic auth
     (client_id:client_secret) and grant_type=password
  2. Use the returned bearer token against https://oauth.reddit.com

  DNS resolution via DoH/DoT exclusively (see SecureDNS).

  ## Credentials

      %{client_id: "...", client_secret: "...", username: "...", password: "..."}

  ## Options

      [subreddit: "somesub"]

  Author: Jonathan D.A. Jewell
  """

  @behaviour FeedbackATron.Channel

  require Logger
  alias FeedbackATron.SecureDNS

  # Reddit API requirement: identify the app in User-Agent
  @user_agent "feedback-o-tron/1.0 (by /u/hyperpolymath)"

  @impl true
  def platform, do: :reddit

  @impl true
  def transport, do: :https

  @impl true
  def validate_creds(cred) do
    cond do
      is_nil(cred[:client_id]) -> {:error, "Reddit client_id required"}
      is_nil(cred[:client_secret]) -> {:error, "Reddit client_secret required"}
      is_nil(cred[:username]) -> {:error, "Reddit username required"}
      is_nil(cred[:password]) -> {:error, "Reddit password required"}
      true -> :ok
    end
  end

  @impl true
  def submit(issue, cred, opts) do
    subreddit = opts[:subreddit]

    if is_nil(subreddit) do
      {:error, %{platform: :reddit, error: "subreddit option is required (e.g. [subreddit: \"somesub\"])"}}
    else
      with {:ok, _ips} <- SecureDNS.resolve("www.reddit.com"),
           {:ok, _ips} <- SecureDNS.resolve("oauth.reddit.com"),
           {:ok, access_token} <- obtain_access_token(cred) do
        submit_post(issue, access_token, subreddit, cred)
      else
        {:error, %{platform: :reddit} = err} ->
          {:error, err}

        {:error, reason} ->
          {:error, %{platform: :reddit, error: {:dns_failed, reason}}}
      end
    end
  end

  # --- OAuth2 token exchange ---

  defp obtain_access_token(cred) do
    auth_url = "https://www.reddit.com/api/v1/access_token"

    # Basic auth header: base64(client_id:client_secret)
    basic_auth = Base.encode64("#{cred.client_id}:#{cred.client_secret}")

    headers = [
      {"Authorization", "Basic #{basic_auth}"},
      {"User-Agent", @user_agent},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    form_body = URI.encode_query(%{
      grant_type: "password",
      username: cred.username,
      password: cred.password
    })

    case Req.post(auth_url, body: form_body, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: resp}} ->
        error_msg = extract_error(resp)
        Logger.error("Reddit OAuth2 error #{status}: #{error_msg}")
        {:error, %{platform: :reddit, status: status, error: "OAuth2 failed: #{error_msg}"}}

      {:error, reason} ->
        {:error, %{platform: :reddit, error: reason}}
    end
  end

  # --- Submit self-post ---

  defp submit_post(issue, access_token, subreddit, cred) do
    submit_url = "https://oauth.reddit.com/api/submit"

    # Build the post body with repo context if available
    post_body = if issue[:repo] do
      "#{issue.body}\n\n---\n*Repository: #{issue.repo}*"
    else
      issue.body
    end

    headers = [
      {"Authorization", "bearer #{access_token}"},
      {"User-Agent", build_user_agent(cred)},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    form_body = URI.encode_query(%{
      api_type: "json",
      kind: "self",
      sr: subreddit,
      title: issue.title,
      text: post_body
    })

    case Req.post(submit_url, body: form_body, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"json" => %{"data" => %{"permalink" => permalink}}}}} ->
        {:ok, %{platform: :reddit, url: "https://reddit.com#{permalink}"}}

      {:ok, %{status: 200, body: %{"json" => %{"errors" => errors}}}} when errors != [] ->
        error_str = errors |> Enum.map(fn [_code, msg | _] -> msg end) |> Enum.join("; ")
        Logger.error("Reddit submit error: #{error_str}")
        {:error, %{platform: :reddit, error: error_str}}

      {:ok, %{status: status, body: resp}} ->
        error_msg = extract_error(resp)
        Logger.error("Reddit submit API error #{status}: #{error_msg}")
        {:error, %{platform: :reddit, status: status, error: error_msg}}

      {:error, reason} ->
        {:error, %{platform: :reddit, error: reason}}
    end
  end

  # --- Helpers ---

  defp build_user_agent(cred) do
    username = cred[:username] || "unknown"
    "feedback-o-tron/1.0 (by /u/#{username})"
  end

  defp extract_error(%{"error" => error}) when is_binary(error), do: error
  defp extract_error(%{"message" => msg}), do: msg
  defp extract_error(other), do: inspect(other)
end

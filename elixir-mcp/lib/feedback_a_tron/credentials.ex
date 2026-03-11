defmodule FeedbackATron.Credentials do
  @moduledoc """
  Credential management with rotation support.

  Credentials are loaded from:
  1. Environment variables (GITHUB_TOKEN, GITLAB_TOKEN, etc.)
  2. CLI configs (~/.config/gh/hosts.yml, ~/.config/glab-cli/config.yml)
  3. Secure credential store (system keyring)
  4. Encrypted config file (.feedback-a-tron/credentials.enc)

  Supports multiple credentials per platform for rotation.
  """

  require Logger



  defstruct [
    :github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email,
    :nntp, :discourse, :mailman, :sourcehut, :jira, :matrix
  ]

  @doc """
  Load credentials from all available sources.
  """
  def load do
    %__MODULE__{
      github: load_github_creds(),
      gitlab: load_gitlab_creds(),
      bitbucket: load_bitbucket_creds(),
      codeberg: load_codeberg_creds(),
      bugzilla: load_bugzilla_creds(),
      email: load_email_config(),
      nntp: load_nntp_creds(),
      discourse: load_discourse_creds(),
      mailman: load_mailman_creds(),
      sourcehut: load_sourcehut_creds(),
      jira: load_jira_creds(),
      matrix: load_matrix_creds()
    }
  end

  @doc """
  Get the best available credential for a platform.
  Implements rotation to distribute API load.
  """
  def get(creds, platform) do
    case Map.get(creds, platform) do
      nil -> {:error, :no_credentials}
      [] -> {:error, :no_credentials}
      [cred] -> {:ok, cred}
      creds when is_list(creds) -> {:ok, rotate(creds)}
    end
  end

  # GitHub: Check env, then gh CLI config
  defp load_github_creds do
    creds = []

    # Environment variable
    creds = case System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") do
      nil -> creds
      token -> [%{source: :env, token: token} | creds]
    end

    # gh CLI config
    creds = case load_gh_cli_token() do
      nil -> creds
      token -> [%{source: :gh_cli, token: token} | creds]
    end

    creds
  end

  defp load_gh_cli_token do
    config_path = Path.expand("~/.config/gh/hosts.yml")

    case File.read(config_path) do
      {:ok, content} ->
        # Parse YAML to get oauth_token for github.com
        case YamlElixir.read_from_string(content) do
          {:ok, %{"github.com" => %{"oauth_token" => token}}} -> token
          _ -> nil
        end
      {:error, _} -> nil
    end
  end

  # GitLab: Check env, then glab CLI config
  defp load_gitlab_creds do
    creds = []

    creds = case System.get_env("GITLAB_TOKEN") do
      nil -> creds
      token -> [%{source: :env, token: token, host: "gitlab.com"} | creds]
    end

    creds = case load_glab_cli_token() do
      nil -> creds
      {token, host} -> [%{source: :glab_cli, token: token, host: host} | creds]
    end

    creds
  end

  defp load_glab_cli_token do
    config_path = Path.expand("~/.config/glab-cli/config.yml")

    case File.read(config_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, %{"hosts" => %{"gitlab.com" => %{"token" => token}}}} ->
            {token, "gitlab.com"}
          _ -> nil
        end
      {:error, _} -> nil
    end
  end

  # Bitbucket: App password from env or config
  defp load_bitbucket_creds do
    case System.get_env("BITBUCKET_TOKEN") do
      nil -> []
      token ->
        username = System.get_env("BITBUCKET_USERNAME", "hyperpolymath")
        [%{source: :env, token: token, username: username}]
    end
  end

  # Codeberg: Token from env
  defp load_codeberg_creds do
    case System.get_env("CODEBERG_TOKEN") do
      nil -> []
      token -> [%{source: :env, token: token}]
    end
  end

  # Bugzilla: API key from env
  defp load_bugzilla_creds do
    creds = []

    creds = case System.get_env("BUGZILLA_API_KEY") do
      nil -> creds
      token -> [%{source: :env, token: token, base_url: System.get_env("BUGZILLA_URL", "https://bugzilla.redhat.com")} | creds]
    end

    # Also support username/password auth
    creds = case {System.get_env("BUGZILLA_USERNAME"), System.get_env("BUGZILLA_PASSWORD")} do
      {nil, _} -> creds
      {_, nil} -> creds
      {user, pass} -> [%{source: :env, username: user, password: pass, base_url: System.get_env("BUGZILLA_URL", "https://bugzilla.redhat.com")} | creds]
    end

    creds
  end

  # Email: SMTP config
  defp load_email_config do
    case System.get_env("SMTP_HOST") do
      nil -> nil
      host -> %{
        host: host,
        port: String.to_integer(System.get_env("SMTP_PORT", "587")),
        username: System.get_env("SMTP_USERNAME"),
        password: System.get_env("SMTP_PASSWORD"),
        from_address: System.get_env("SMTP_FROM", "feedback@localhost"),
        default_recipient: System.get_env("FEEDBACK_EMAIL_TO")
      }
    end
  end

  # NNTP: NNTPS server config
  defp load_nntp_creds do
    case System.get_env("NNTP_SERVER") do
      nil -> []
      server ->
        [%{
          source: :env,
          server: server,
          port: String.to_integer(System.get_env("NNTP_PORT", "563")),
          newsgroup: System.get_env("NNTP_NEWSGROUP"),
          username: System.get_env("NNTP_USERNAME"),
          password: System.get_env("NNTP_PASSWORD"),
          from: System.get_env("NNTP_FROM", "feedback-a-tron@localhost")
        }]
    end
  end

  # Discourse: HTTPS API
  defp load_discourse_creds do
    case System.get_env("DISCOURSE_URL") do
      nil -> []
      url ->
        if String.starts_with?(url, "https://") do
          [%{
            source: :env,
            base_url: url,
            api_key: System.get_env("DISCOURSE_API_KEY"),
            api_username: System.get_env("DISCOURSE_API_USERNAME", "system"),
            default_category_id: System.get_env("DISCOURSE_CATEGORY_ID")
          }]
        else
          Logger.warning("Discourse URL must be HTTPS, ignoring: #{url}")
          []
        end
    end
  end

  # Mailman: SMTPS or HyperKitty REST
  defp load_mailman_creds do
    creds = []

    # HyperKitty REST API
    creds = case System.get_env("HYPERKITTY_URL") do
      nil -> creds
      url ->
        if String.starts_with?(url, "https://") do
          [%{
            source: :env,
            hyperkitty_url: url,
            api_key: System.get_env("HYPERKITTY_API_KEY"),
            list_id: System.get_env("MAILMAN_LIST_ID")
          } | creds]
        else
          creds
        end
    end

    # Direct SMTPS to list address
    creds = case System.get_env("MAILMAN_LIST_ADDRESS") do
      nil -> creds
      list_addr ->
        [%{
          source: :env,
          list_address: list_addr,
          smtp_server: System.get_env("MAILMAN_SMTP_SERVER"),
          smtp_port: String.to_integer(System.get_env("MAILMAN_SMTP_PORT", "465")),
          smtp_username: System.get_env("MAILMAN_SMTP_USERNAME"),
          smtp_password: System.get_env("MAILMAN_SMTP_PASSWORD"),
          from: System.get_env("MAILMAN_FROM", "feedback-a-tron@localhost")
        } | creds]
    end

    creds
  end

  # SourceHut: personal access token
  defp load_sourcehut_creds do
    case System.get_env("SRHT_TOKEN") do
      nil -> []
      token ->
        [%{
          source: :env,
          token: token,
          tracker: System.get_env("SRHT_TRACKER"),
          api_base: System.get_env("SRHT_API_BASE", "https://todo.sr.ht")
        }]
    end
  end

  # Jira: Cloud (email + API token) or Server (PAT)
  defp load_jira_creds do
    case System.get_env("JIRA_URL") do
      nil -> []
      url ->
        if String.starts_with?(url, "https://") do
          [%{
            source: :env,
            base_url: url,
            email: System.get_env("JIRA_EMAIL"),
            api_token: System.get_env("JIRA_API_TOKEN"),
            token: System.get_env("JIRA_TOKEN"),
            project_key: System.get_env("JIRA_PROJECT_KEY"),
            default_issue_type: System.get_env("JIRA_ISSUE_TYPE", "Task"),
            api_version: System.get_env("JIRA_API_VERSION", "2")
          }]
        else
          Logger.warning("Jira URL must be HTTPS, ignoring: #{url}")
          []
        end
    end
  end

  # Matrix: homeserver + access token
  defp load_matrix_creds do
    case System.get_env("MATRIX_HOMESERVER") do
      nil -> []
      homeserver ->
        if String.starts_with?(homeserver, "https://") do
          [%{
            source: :env,
            homeserver: homeserver,
            access_token: System.get_env("MATRIX_ACCESS_TOKEN"),
            room_id: System.get_env("MATRIX_ROOM_ID")
          }]
        else
          Logger.warning("Matrix homeserver must be HTTPS, ignoring: #{homeserver}")
          []
        end
    end
  end

  # Simple round-robin rotation using process dictionary
  # In production, use ETS or Agent for shared state
  defp rotate(creds) do
    key = :credential_rotation_index
    current = Process.get(key, 0)
    next = rem(current + 1, length(creds))
    Process.put(key, next)
    Enum.at(creds, current)
  end
end

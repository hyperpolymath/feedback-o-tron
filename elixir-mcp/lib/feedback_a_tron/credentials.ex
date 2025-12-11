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

  @platforms [:github, :gitlab, :bitbucket, :codeberg]

  defstruct [:github, :gitlab, :bitbucket, :codeberg, :email]

  @doc """
  Load credentials from all available sources.
  """
  def load do
    %__MODULE__{
      github: load_github_creds(),
      gitlab: load_gitlab_creds(),
      bitbucket: load_bitbucket_creds(),
      codeberg: load_codeberg_creds(),
      email: load_email_config()
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

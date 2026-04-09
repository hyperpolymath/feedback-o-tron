# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Credentials.FileStore do
  @moduledoc """
  Persistent credential storage using an encrypted TOML file.

  Supports loading credentials from:
  - `~/.config/feedback-a-tron/credentials.toml` (plaintext, user-readable only)
  - `~/.netrc` (standard .netrc format for machine-token pairs)

  This supplements the primary environment variable loading in Credentials.

  ## .netrc Format Support

  Standard .netrc entries are mapped to platform credentials:

      machine github.com
        login oauth
        password ghp_your_token_here

      machine gitlab.com
        login oauth
        password glpat-your_token_here

      machine bugzilla.redhat.com
        login user@example.com
        password api_key_here

  ## TOML Config Format

      [github]
      token = "ghp_your_token_here"

      [gitlab]
      token = "glpat-your_token_here"
      host = "gitlab.com"

      [bugzilla]
      api_key = "your_api_key"
      base_url = "https://bugzilla.redhat.com"
  """

  require Logger

  @netrc_path "~/.netrc"
  @config_path "~/.config/feedback-a-tron/credentials.toml"

  # Machine → platform atom mapping for .netrc
  @netrc_machine_map %{
    "github.com" => :github,
    "gitlab.com" => :gitlab,
    "bitbucket.org" => :bitbucket,
    "codeberg.org" => :codeberg,
    "bugzilla.redhat.com" => :bugzilla,
    "todo.sr.ht" => :sourcehut
  }

  @doc """
  Load credentials from .netrc file.

  Returns a map of `%{platform_atom => [%{source: :netrc, ...}]}`.
  """
  def load_netrc do
    path = Path.expand(@netrc_path)

    case File.read(path) do
      {:ok, content} ->
        parse_netrc(content)

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.debug("Could not read #{path}: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Load credentials from TOML config file.

  Returns a map of `%{platform_atom => [%{source: :config_file, ...}]}`.
  """
  def load_toml_config do
    path = Path.expand(@config_path)

    case File.read(path) do
      {:ok, content} ->
        parse_toml_config(content)

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.debug("Could not read #{path}: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Load credentials from all file-based sources.

  Returns a merged map of `%{platform_atom => [cred_map, ...]}`.
  """
  def load_all do
    netrc_creds = load_netrc()
    toml_creds = load_toml_config()

    Map.merge(netrc_creds, toml_creds, fn _key, v1, v2 -> v1 ++ v2 end)
  end

  # --- .netrc parser ---

  defp parse_netrc(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> extract_netrc_entries()
    |> Enum.reduce(%{}, fn entry, acc ->
      case Map.get(@netrc_machine_map, entry.machine) do
        nil ->
          acc

        platform ->
          cred = %{
            source: :netrc,
            token: entry.password,
            username: entry.login,
            machine: entry.machine
          }

          Map.update(acc, platform, [cred], &[cred | &1])
      end
    end)
  end

  defp extract_netrc_entries(lines) do
    extract_netrc_entries(lines, [], nil)
  end

  defp extract_netrc_entries([], entries, current) do
    if current, do: [current | entries], else: entries
  end

  defp extract_netrc_entries(["machine " <> machine | rest], entries, current) do
    entries = if current, do: [current | entries], else: entries
    extract_netrc_entries(rest, entries, %{machine: String.trim(machine), login: nil, password: nil})
  end

  defp extract_netrc_entries(["login " <> login | rest], entries, current) when current != nil do
    extract_netrc_entries(rest, entries, %{current | login: String.trim(login)})
  end

  defp extract_netrc_entries(["password " <> password | rest], entries, current) when current != nil do
    extract_netrc_entries(rest, entries, %{current | password: String.trim(password)})
  end

  defp extract_netrc_entries([_ | rest], entries, current) do
    extract_netrc_entries(rest, entries, current)
  end

  # --- TOML config parser ---

  defp parse_toml_config(content) do
    case Toml.decode(content) do
      {:ok, config} ->
        config
        |> Enum.reduce(%{}, fn {platform_str, values}, acc ->
          platform = safe_to_atom(platform_str)

          if platform do
            cred = Map.put(values, "source", "config_file")
                   |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
                   |> Enum.into(%{})
                   |> Map.put(:source, :config_file)

            Map.update(acc, platform, [cred], &[cred | &1])
          else
            acc
          end
        end)

      {:error, reason} ->
        Logger.warning("Failed to parse TOML config: #{inspect(reason)}")
        %{}
    end
  end

  @known_platforms ~w(github gitlab bitbucket codeberg bugzilla email nntp discourse mailman sourcehut jira matrix discord reddit)

  defp safe_to_atom(str) do
    if str in @known_platforms do
      String.to_existing_atom(str)
    else
      nil
    end
  rescue
    ArgumentError -> nil
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.CLI do
  @moduledoc """
  Command-line interface for feedback-o-tron.

  Supports both direct CLI usage and MCP server mode for Claude integration.
  """

  alias FeedbackATron.{Submitter, MCP}
  require Logger

  def main(args) do
    case parse_args(args) do
      {:mcp_server, opts} ->
        Logger.info("Starting MCP server mode...")
        Application.ensure_all_started(:feedback_a_tron)
        MCP.Server.start_link(opts)
        :timer.sleep(:infinity)

      {:submit, issue, opts} ->
        Logger.info("Submitting issue: #{issue.title}")
        Application.ensure_all_started(:feedback_a_tron)

        case Submitter.submit(issue, opts) do
          {:ok, id, results} ->
            IO.puts("\n✅ Submission #{id} completed")
            print_results(results)
            System.halt(0)
          {:error, reason} ->
            IO.puts("\n❌ Submission failed: #{inspect(reason)}")
            System.halt(1)
        end

      {:version} ->
        IO.puts("feedback-o-tron v#{version()}")
        System.halt(0)

      {:help} ->
        print_help()
        System.halt(0)

      {:error, message} ->
        IO.puts("Error: #{message}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args(["--mcp-server" | _rest]) do
    {:mcp_server, []}
  end

  defp parse_args(["--version" | _]) do
    {:version}
  end

  defp parse_args(["--help" | _]) do
    {:help}
  end

  defp parse_args(["submit" | rest]) do
    case parse_submit_args(rest) do
      {:ok, issue, opts} -> {:submit, issue, opts}
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_args([]) do
    {:help}
  end

  defp parse_args(_) do
    {:error, "Unknown command"}
  end

  defp parse_submit_args(args) do
    with {:ok, opts} <- extract_options(args),
         {:ok, issue} <- build_issue(opts) do
      platforms = Keyword.get(opts, :platforms, [:github])
      submit_opts = [
        platforms: platforms,
        labels: Keyword.get(opts, :labels, []),
        dry_run: Keyword.get(opts, :dry_run, false),
        repo: Keyword.get(opts, :repo),
        component: Keyword.get(opts, :component),
        version: Keyword.get(opts, :bug_version)
      ]
      {:ok, issue, submit_opts}
    end
  end

  defp extract_options(args) do
    opts = parse_flags(args, [])
    {:ok, opts}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp parse_flags([], acc), do: Enum.reverse(acc)

  defp parse_flags(["--repo", repo | rest], acc) do
    parse_flags(rest, [{:repo, repo} | acc])
  end

  defp parse_flags(["--title", title | rest], acc) do
    parse_flags(rest, [{:title, title} | acc])
  end

  defp parse_flags(["--body", body | rest], acc) do
    parse_flags(rest, [{:body, body} | acc])
  end

  defp parse_flags(["--platform", platform | rest], acc) do
    platforms = Keyword.get(acc, :platforms, [])
    platform_atom = String.to_atom(platform)
    parse_flags(rest, Keyword.put(acc, :platforms, [platform_atom | platforms]))
  end

  defp parse_flags(["--label", label | rest], acc) do
    labels = Keyword.get(acc, :labels, [])
    parse_flags(rest, Keyword.put(acc, :labels, [label | labels]))
  end

  defp parse_flags(["--dry-run" | rest], acc) do
    parse_flags(rest, [{:dry_run, true} | acc])
  end

  defp parse_flags(["--component", component | rest], acc) do
    parse_flags(rest, [{:component, component} | acc])
  end

  defp parse_flags(["--version", version | rest], acc) do
    parse_flags(rest, [{:bug_version, version} | acc])
  end

  defp parse_flags([unknown | _], _acc) do
    raise "Unknown flag: #{unknown}"
  end

  defp build_issue(opts) do
    title = Keyword.get(opts, :title)
    body = Keyword.get(opts, :body)
    repo = Keyword.get(opts, :repo)

    cond do
      is_nil(title) -> {:error, "Missing required --title"}
      is_nil(body) -> {:error, "Missing required --body"}
      is_nil(repo) -> {:error, "Missing required --repo"}
      true -> {:ok, %{title: title, body: body, repo: repo}}
    end
  end

  defp print_results(results) do
    Enum.each(results, fn
      {:ok, %{platform: platform, url: url}} ->
        IO.puts("  ✓ #{platform}: #{url}")
      {:ok, %{platform: platform, status: :dry_run}} ->
        IO.puts("  [DRY RUN] #{platform}: Would submit")
      {:error, %{platform: platform, error: error}} ->
        IO.puts("  ✗ #{platform}: #{inspect(error)}")
      other ->
        IO.puts("  ? #{inspect(other)}")
    end)
  end

  defp print_help do
    IO.puts("""
    feedback-o-tron v#{version()} - Automated multi-platform feedback submission

    USAGE:
        feedback-o-tron [COMMAND] [OPTIONS]

    COMMANDS:
        --mcp-server        Start MCP server for Claude Code integration
        submit              Submit an issue/bug report
        --version           Show version
        --help              Show this help

    SUBMIT OPTIONS:
        --repo REPO         Target repository (owner/repo or product for Bugzilla)
        --title TITLE       Issue title
        --body BODY         Issue body (markdown supported)
        --platform NAME     Target platform (github, gitlab, bitbucket, codeberg, bugzilla, email)
                            Can be specified multiple times for multi-platform submission
        --label LABEL       Apply label (can specify multiple)
        --component NAME    Bugzilla component (e.g., "maliit-keyboard", "plasma-desktop")
        --version VER       Bugzilla version (e.g., "43", "rawhide")
        --dry-run           Show what would be submitted without actually submitting

    PLATFORMS:
        github              GitHub Issues (via gh CLI or API)
        gitlab              GitLab Issues (via glab CLI or API)
        bitbucket           Bitbucket Issues (via API)
        codeberg            Codeberg Issues (via Gitea API)
        bugzilla            Bugzilla (via XML-RPC or REST API)
        email               Email submission

    EXAMPLES:
        # Submit to GitHub
        feedback-o-tron submit --repo owner/repo --title "Bug title" --body "Description" --platform github

        # Submit to Bugzilla
        feedback-o-tron submit --repo fedora --title "maliit crashes" --body "Details..." --platform bugzilla

        # Multi-platform submission
        feedback-o-tron submit --repo owner/repo --title "SEP Proposal" --body "..." --platform github --platform gitlab

        # Dry run
        feedback-o-tron submit --repo owner/repo --title "Test" --body "Test" --dry-run

        # Start MCP server for Claude
        feedback-o-tron --mcp-server

    CREDENTIALS:
        Set via environment variables:
        - GITHUB_TOKEN
        - GITLAB_TOKEN
        - BITBUCKET_TOKEN
        - CODEBERG_TOKEN
        - BUGZILLA_API_KEY (or BUGZILLA_USERNAME + BUGZILLA_PASSWORD)

    MCP INTEGRATION:
        Add to ~/.config/claude/mcp_servers.json:
        {
          "feedback-o-tron": {
            "command": "/path/to/feedback-o-tron",
            "args": ["--mcp-server"]
          }
        }
    """)
  end

  defp version do
    case Application.spec(:feedback_a_tron, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "unknown"
    end
  end
end

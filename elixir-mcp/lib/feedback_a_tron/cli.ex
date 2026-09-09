# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.CLI do
  @moduledoc """
  Command-line interface for feedback-o-tron.

  Supports both direct CLI usage and MCP server mode for Claude integration.
  """

  alias FeedbackATron.Submitter

  def main(args) do
    case run(args) do
      {:halt, code} -> System.halt(code)
      :running -> Process.sleep(:infinity)
    end
  end

  @doc false
  @spec run([String.t()], keyword()) :: {:halt, non_neg_integer()} | :running
  def run(args, opts \\ []) do
    case parse_args(args) do
      {:serve, doors} ->
        if List.first(args) == "--mcp-server" do
          IO.puts(
            :stderr,
            "feedback-o-tron: --mcp-server is deprecated; use `feedback-o-tron serve`"
          )
        end

        Application.put_env(:feedback_a_tron, :doors, doors)
        {:ok, _} = Application.ensure_all_started(:feedback_a_tron)
        :running

      {:submit, issue, submit_opts} ->
        submit(issue, submit_opts, opts)

      {:version} ->
        IO.puts("feedback-o-tron v#{version()}")
        {:halt, 0}

      {:help} ->
        print_help(:stdio)
        {:halt, 0}

      {:error, message} ->
        IO.puts(:stderr, "Error: #{message}")
        print_help(:stderr)
        {:halt, 1}
    end
  end

  @doc false
  def parse_args(["serve" | rest]), do: parse_serve_flags(rest, mcp_stdio: true, http: true)

  def parse_args(["--mcp-server" | rest]),
    do: parse_serve_flags(rest, mcp_stdio: true, http: true)

  def parse_args(["--version" | _]), do: {:version}
  def parse_args(["--help" | _]), do: {:help}

  def parse_args(["submit" | rest]) do
    case parse_submit_args(rest) do
      {:ok, issue, opts} -> {:submit, issue, opts}
      {:error, msg} -> {:error, msg}
    end
  end

  def parse_args([]), do: {:help}
  def parse_args([other | _]), do: {:error, "Unknown command: #{other}"}

  defp parse_serve_flags([], doors) do
    if doors[:mcp_stdio] or doors[:http] do
      {:serve, doors}
    else
      {:error, "serve: both doors closed (--no-stdio and --no-http); nothing to serve"}
    end
  end

  defp parse_serve_flags(["--no-stdio" | rest], doors),
    do: parse_serve_flags(rest, Keyword.put(doors, :mcp_stdio, false))

  defp parse_serve_flags(["--no-http" | rest], doors),
    do: parse_serve_flags(rest, Keyword.put(doors, :http, false))

  defp parse_serve_flags(["--http-port", value | rest], doors) do
    case Integer.parse(value) do
      {port, ""} when port in 1..65535 ->
        parse_serve_flags(rest, Keyword.put(doors, :http_port, port))

      _ ->
        {:error, "Bad --http-port: #{value} (expected 1..65535)"}
    end
  end

  defp parse_serve_flags([flag | _], _doors), do: {:error, "Unknown serve flag: #{flag}"}

  defp submit(issue, submit_opts, run_opts) do
    {:ok, _} = Application.ensure_all_started(:feedback_a_tron)

    if submit_opts[:dry_run] or confirm_send(issue, submit_opts, run_opts) do
      do_submit(issue, submit_opts, run_opts)
    else
      IO.puts(:stderr, "Not sent.")
      {:halt, 3}
    end
  end

  # SP1b pre-ledger rule: nothing leaves the machine from the CLI until a
  # person has seen the whole payload and typed yes at a terminal. The privacy
  # ledger (SP3) replaces this with a per-report ledger and standing choices.
  # There is no --yes flag on purpose.
  defp confirm_send(issue, submit_opts, run_opts) do
    IO.puts(payload_preview(issue, submit_opts))
    confirm = Keyword.get(run_opts, :confirm, &tty_confirm/0)
    confirm.()
  end

  defp do_submit(issue, submit_opts, run_opts) do
    submit_fun = Keyword.get(run_opts, :submit, &Submitter.submit/2)

    case submit_fun.(issue, submit_opts) do
      {:ok, id, results} ->
        IO.puts("\n✅ Submission #{id} completed")
        print_results(results)
        {:halt, exit_code(results)}

      {:error, reason} ->
        IO.puts(:stderr, "\n❌ Submission failed: #{inspect(reason)}")
        {:halt, 1}
    end
  end

  @doc false
  def payload_preview(issue, submit_opts) do
    platforms =
      submit_opts |> Keyword.get(:platforms, [:github]) |> Enum.map_join(", ", &to_string/1)

    labels = submit_opts |> Keyword.get(:labels, []) |> Enum.join(", ")

    optional =
      for {label, key} <- [{"Component:   ", :component}, {"Version:     ", :version}],
          value = Keyword.get(submit_opts, key),
          not is_nil(value),
          do: "#{label} #{value}\n"

    """
    About to send this report. Everything below leaves this machine; nothing else does.

    Destinations: #{platforms}
    Repository:   #{issue.repo}
    Title:        #{issue.title}
    Labels:       #{if labels == "", do: "(none)", else: labels}
    #{Enum.join(optional)}Body:
    #{indent(issue.body)}
    """
  end

  defp indent(text) do
    text |> String.split("\n") |> Enum.map_join("\n", &("    " <> &1))
  end

  defp tty_confirm do
    if stdin_tty?() do
      answer = IO.gets("Send this report? [y/N] ")
      is_binary(answer) and String.downcase(String.trim(answer)) in ["y", "yes"]
    else
      IO.puts(
        :stderr,
        "feedback-o-tron: stdin is not a terminal; refusing to send without a person's yes. " <>
          "Use --dry-run to preview."
      )

      false
    end
  end

  # OTP 26+ exports :prim_tty.isatty/1 (it answers false for a pipe and for
  # a closed stdin); :io.columns/0 is the older proxy for the same question.
  defp stdin_tty? do
    if Code.ensure_loaded?(:prim_tty) and function_exported?(:prim_tty, :isatty, 1) do
      :prim_tty.isatty(:stdin) == true
    else
      match?({:ok, _}, :io.columns())
    end
  end

  defp exit_code(results) do
    if Enum.any?(results, &match?({:error, _}, &1)), do: 1, else: 0
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
    platform_atom = String.to_existing_atom(platform)
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

  defp print_help(device) do
    IO.puts(device, """
    feedback-o-tron v#{version()} - multi-platform feedback and bug-report submission

    USAGE:
        feedback-o-tron serve [--no-stdio] [--no-http] [--http-port N]
        feedback-o-tron submit --repo REPO --title TITLE --body BODY [OPTIONS]
        feedback-o-tron --version
        feedback-o-tron --help

    SERVE:
        Runs the engine in this process and opens its doors: the MCP server on
        stdin/stdout (for Claude Code and other MCP hosts) and the HTTP intake
        on 127.0.0.1:7722 (for boj and local tools). With the MCP door open
        the process exits when stdin closes; with --no-stdio it runs until
        stopped (Ctrl-C or SIGTERM). Environment: FEEDBACK_O_TRON_HTTP_PORT,
        FEEDBACK_O_TRON_HTTP_BIND.
        --no-stdio          Do not open the MCP door
        --no-http           Do not open the HTTP intake
        --http-port N       HTTP intake port (default 7722)

    SUBMIT OPTIONS:
        --repo REPO         Target repository (owner/repo, or product for Bugzilla)
        --title TITLE       Issue title
        --body BODY         Issue body (Markdown)
        --platform NAME     github (default), gitlab, bitbucket, codeberg, bugzilla, email; repeatable
        --label LABEL       Apply a label; repeatable
        --component NAME    Bugzilla component
        --version VER       Bugzilla version
        --dry-run           Print what would be sent and send nothing

        Without --dry-run the full payload is printed and you are asked
        "Send this report? [y/N]". Nothing is sent without a y typed at a
        terminal; there is no --yes flag.
        Exit codes: 0 sent (or dry run); 1 bad arguments or a destination
        failed; 3 not sent.

    CREDENTIALS:
        GitHub: `gh auth login` (the gh CLI's token is used), or GITHUB_TOKEN.
        Others: GITLAB_TOKEN, BITBUCKET_TOKEN, CODEBERG_TOKEN,
        BUGZILLA_API_KEY (or BUGZILLA_USERNAME + BUGZILLA_PASSWORD).

    MCP INTEGRATION (Claude Code):
        claude mcp add feedback-o-tron -- /full/path/to/feedback-o-tron serve
        or, in the MCP settings file:
        {
          "feedback-o-tron": {
            "command": "/full/path/to/feedback-o-tron",
            "args": ["serve"]
          }
        }
    """)
  end

  defp version do
    case Application.load(:feedback_a_tron) do
      :ok -> :ok
      {:error, {:already_loaded, _}} -> :ok
    end

    case Application.spec(:feedback_a_tron, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "unknown"
    end
  end
end

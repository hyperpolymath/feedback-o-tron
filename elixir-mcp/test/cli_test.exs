# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias FeedbackATron.CLI

  setup do
    for mod <- [
          FeedbackATron.RateLimiter,
          FeedbackATron.Submitter,
          FeedbackATron.Deduplicator,
          FeedbackATron.AuditLog
        ] do
      case Process.whereis(mod) do
        nil -> mod.start_link([])
        _pid -> :ok
      end
    end

    # Global state shared with rate_limiter_test.exs (see submitter_test.exs).
    for platform <- [:github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email] do
      FeedbackATron.RateLimiter.reset(platform)
    end

    :ok = FeedbackATron.Deduplicator.clear()
    :ok
  end

  describe "parse_args/1 serve" do
    test "serve opens both doors by default" do
      assert {:serve, doors} = CLI.parse_args(["serve"])
      assert doors[:mcp_stdio] == true
      assert doors[:http] == true
      refute Keyword.has_key?(doors, :http_port)
    end

    test "serve flags close doors and set the port" do
      assert {:serve, doors} = CLI.parse_args(["serve", "--no-http"])
      assert doors[:mcp_stdio] == true
      assert doors[:http] == false

      assert {:serve, doors} = CLI.parse_args(["serve", "--no-stdio", "--http-port", "8123"])
      assert doors[:mcp_stdio] == false
      assert doors[:http] == true
      assert doors[:http_port] == 8123
    end

    test "both doors closed is an error" do
      assert {:error, message} = CLI.parse_args(["serve", "--no-stdio", "--no-http"])
      assert message =~ "both doors closed"
    end

    test "a bad port is an error" do
      assert {:error, "Bad --http-port: 70000" <> _} =
               CLI.parse_args(["serve", "--http-port", "70000"])

      assert {:error, "Bad --http-port: x" <> _} = CLI.parse_args(["serve", "--http-port", "x"])
    end

    test "an unknown serve flag is an error" do
      assert {:error, "Unknown serve flag: --tcp"} = CLI.parse_args(["serve", "--tcp"])
    end

    test "--mcp-server is the deprecated spelling of serve" do
      assert CLI.parse_args(["--mcp-server"]) == CLI.parse_args(["serve"])
    end
  end

  describe "parse_args/1 submit" do
    test "parses a full submit" do
      args = [
        "submit",
        "--repo",
        "o/r",
        "--title",
        "T",
        "--body",
        "B",
        "--platform",
        "github",
        "--label",
        "bug",
        "--dry-run"
      ]

      assert {:submit, issue, opts} = CLI.parse_args(args)
      assert issue == %{title: "T", body: "B", repo: "o/r"}
      assert opts[:platforms] == [:github]
      assert opts[:labels] == ["bug"]
      assert opts[:dry_run] == true
      assert opts[:repo] == "o/r"
    end

    test "a missing --repo is an error" do
      assert {:error, "Missing required --repo"} =
               CLI.parse_args(["submit", "--title", "T", "--body", "B"])
    end

    test "an unknown flag is an error" do
      assert {:error, "Unknown flag: --bogus"} = CLI.parse_args(["submit", "--bogus"])
    end
  end

  describe "run/2" do
    test "--version prints the canonical version and halts 0" do
      {result, out} = with_io(fn -> CLI.run(["--version"]) end)
      assert result == {:halt, 0}
      assert out == "feedback-o-tron v1.0.0\n"
    end

    test "--help mentions serve and never the old spelling" do
      {result, out} = with_io(fn -> CLI.run(["--help"]) end)
      assert result == {:halt, 0}
      assert out =~ "feedback-o-tron serve"
      assert out =~ ~s("args": ["serve"])
      refute out =~ "a-tron"
    end

    test "no arguments prints help and halts 0" do
      {result, out} = with_io(fn -> CLI.run([]) end)
      assert result == {:halt, 0}
      assert out =~ "USAGE"
    end

    test "an unknown command halts 1 with the error on stderr" do
      {result, err} = with_io(:stderr, fn -> CLI.run(["frobnicate"]) end)
      assert result == {:halt, 1}
      assert err =~ "Error: Unknown command: frobnicate"
    end

    test "submit --dry-run halts 0 and prints the dry-run line" do
      args = ["submit", "--repo", "o/r", "--title", "T", "--body", "B", "--dry-run"]
      {result, out} = with_io(fn -> CLI.run(args) end)
      assert result == {:halt, 0}
      assert out =~ "[DRY RUN] github: Would submit"
    end

    test "a failed destination halts 1" do
      args = ["submit", "--repo", "o/r", "--title", "T", "--body", "B", "--dry-run"]

      submit = fn _issue, _opts ->
        {:ok, "sub-2", [{:error, %{platform: :github, error: :boom}}]}
      end

      {result, out} = with_io(fn -> CLI.run(args, submit: submit) end)
      assert result == {:halt, 1}
      assert out =~ "✗ github: :boom"
    end

    test "a submission error halts 1 with the reason on stderr" do
      args = ["submit", "--repo", "o/r", "--title", "T", "--body", "B", "--dry-run"]
      submit = fn _issue, _opts -> {:error, :no_credentials} end
      {result, err} = with_io(:stderr, fn -> CLI.run(args, submit: submit) end)
      assert result == {:halt, 1}
      assert err =~ "Submission failed: :no_credentials"
    end
  end

  describe "run/2 confirm gate" do
    @args [
      "submit",
      "--repo",
      "o/r",
      "--title",
      "T",
      "--body",
      "line one\nline two",
      "--label",
      "bug"
    ]

    test "prints the whole payload and refuses when the person says no" do
      submit = fn _issue, _opts -> flunk("nothing may be sent after a no") end

      {result, out} =
        with_io(fn -> CLI.run(@args, confirm: fn -> false end, submit: submit) end)

      assert result == {:halt, 3}
      assert out =~ "Everything below leaves this machine; nothing else does."
      assert out =~ "Destinations: github"
      assert out =~ "Repository:   o/r"
      assert out =~ "Title:        T"
      assert out =~ "Labels:       bug"
      assert out =~ "    line one\n    line two"
    end

    test "sends when the person says yes and halts 0 on success" do
      submit = fn issue, opts ->
        assert issue.title == "T"
        assert opts[:platforms] == [:github]
        {:ok, "sub-1", [{:ok, %{platform: :github, url: "https://github.com/o/r/issues/1"}}]}
      end

      {result, out} =
        with_io(fn -> CLI.run(@args, confirm: fn -> true end, submit: submit) end)

      assert result == {:halt, 0}
      assert out =~ "✓ github: https://github.com/o/r/issues/1"
    end

    test "--dry-run never asks" do
      confirm = fn -> flunk("a dry run must not prompt") end
      {result, out} = with_io(fn -> CLI.run(@args ++ ["--dry-run"], confirm: confirm) end)
      assert result == {:halt, 0}
      assert out =~ "[DRY RUN] github: Would submit"
    end

    test "payload_preview/2 lists Bugzilla component and version only when set" do
      issue = %{title: "T", body: "B", repo: "fedora"}
      opts = [platforms: [:bugzilla], labels: [], component: "maliit-keyboard", version: "43"]
      preview = CLI.payload_preview(issue, opts)
      assert preview =~ "Destinations: bugzilla"
      assert preview =~ "Component:    maliit-keyboard"
      assert preview =~ "Version:      43"
      assert preview =~ "Labels:       (none)"
      refute CLI.payload_preview(issue, platforms: [:github]) =~ "Component:"
    end
  end
end

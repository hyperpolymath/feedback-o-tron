# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.ResearchTest do
  # Uses the globally named Deduplicator (shared state, cleared per test),
  # so this module must run serially.
  use ExUnit.Case, async: false

  alias FeedbackATron.Deduplicator
  alias FeedbackATron.Synthesis.Research
  alias FeedbackATron.Synthesis.TemplateCache

  @bug_yaml """
  name: Bug Report
  description: File a bug report
  body:
    - type: markdown
      attributes:
        value: Thanks for reporting!
    - type: textarea
      id: what-happened
      attributes:
        label: What happened?
      validations:
        required: true
    - type: input
      id: version
      attributes:
        label: Version
  """

  setup do
    # Ensure the deduplicator is running (it may be started by the application).
    case Process.whereis(Deduplicator) do
      nil -> {:ok, _pid} = Deduplicator.start_link([])
      _pid -> :ok
    end

    :ok = Deduplicator.clear()

    # TemplateCache is started by the application; fall back to a
    # supervised instance when running without it.
    case Process.whereis(TemplateCache) do
      nil -> start_supervised!(TemplateCache)
      _pid -> :ok
    end

    :ok = TemplateCache.purge()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Forge section
  # ---------------------------------------------------------------------------

  describe "forge search" do
    test "reports gh as unavailable when executable lookup is forced off" do
      assert {:ok, result} =
               Research.research(
                 %{repo: "acme/widget", title: "Crash on save button", body: nil},
                 gh_disabled: true,
                 include_templates: false
               )

      assert result.forge == %{status: "unavailable", reason: "gh CLI not found on PATH"}
    end
  end

  # ---------------------------------------------------------------------------
  # Local section (Deduplicator)
  # ---------------------------------------------------------------------------

  describe "local dedup" do
    test "fresh issue is unique, with recurrence stats" do
      assert {:ok, result} =
               Research.research(
                 %{repo: "acme/widget", title: "Never seen before crash", body: "details"},
                 gh_disabled: true,
                 include_templates: false
               )

      assert result.local.status == "unique"
      assert result.local.stats == %{recorded_submissions: 0}
    end

    test "recorded submission is reported as duplicate with match summary" do
      issue = %{title: "Crash when saving file to disk", body: "it crashes"}
      Deduplicator.record(issue, :github, %{url: "https://github.com/acme/widget/issues/1"})

      assert {:ok, result} =
               Research.research(
                 %{repo: "acme/widget", title: issue.title, body: issue.body},
                 gh_disabled: true,
                 include_templates: false
               )

      assert result.local.status == "duplicate"
      assert result.local.match.platform == :github
      assert result.local.match.title == issue.title
      assert is_binary(result.local.match.hash)

      # Doctrine point 5: callers can judge pattern-vs-one-off.
      assert result.local.stats == %{recorded_submissions: 1}
    end

    test "near-identical title is reported as similar with scored matches" do
      Deduplicator.record(
        %{title: "Crash when saving file to disk", body: "abc"},
        :github,
        %{url: "https://github.com/acme/widget/issues/2"}
      )

      assert {:ok, result} =
               Research.research(
                 %{repo: "acme/widget", title: "Crash when saving files to disk", body: "xyz"},
                 gh_disabled: true,
                 include_templates: false
               )

      assert result.local.status == "similar"
      assert [match | _] = result.local.matches
      assert match.score >= 0.85
      assert is_binary(match.hash)
    end
  end

  # ---------------------------------------------------------------------------
  # Templates section
  # ---------------------------------------------------------------------------

  describe "templates" do
    setup do
      bypass = Bypass.open()
      base = "http://localhost:#{bypass.port}"
      {:ok, bypass: bypass, base: base}
    end

    test "summarizes each form to its non-markdown questions", %{bypass: bypass, base: base} do
      repo = "acme/templated"
      listing = [%{"name" => "bug.yml", "type" => "file"}]

      Bypass.stub(bypass, "GET", "/repos/#{repo}/contents/.github/ISSUE_TEMPLATE", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(listing))
      end)

      Bypass.stub(bypass, "GET", "/#{repo}/HEAD/.github/ISSUE_TEMPLATE/bug.yml", fn conn ->
        Plug.Conn.resp(conn, 200, @bug_yaml)
      end)

      assert {:ok, result} =
               Research.research(
                 %{repo: repo, title: "Crash on save", body: ""},
                 gh_disabled: true,
                 base_url: base,
                 raw_base_url: base
               )

      assert result.templates == [
               %{name: "Bug Report", file: "bug.yml", questions: ["What happened?", "Version"]}
             ]

      refute Map.has_key?(result, :templates_error)
    end

    test "fetch failure yields empty templates plus templates_error", %{
      bypass: bypass,
      base: base
    } do
      repo = "acme/bare"

      Bypass.stub(bypass, "GET", "/repos/#{repo}/contents/.github/ISSUE_TEMPLATE", fn conn ->
        Plug.Conn.resp(conn, 404, ~s({"message": "Not Found"}))
      end)

      assert {:ok, result} =
               Research.research(
                 %{repo: repo, title: "Crash on save", body: nil},
                 gh_disabled: true,
                 base_url: base,
                 raw_base_url: base
               )

      assert result.templates == []
      assert result.templates_error == "no_templates"
    end

    test "include_templates: false skips the fetch entirely" do
      # No Bypass routes are registered — a fetch attempt would fail loudly.
      assert {:ok, result} =
               Research.research(
                 %{repo: "acme/skipped", title: "Crash on save", body: nil},
                 gh_disabled: true,
                 include_templates: false
               )

      assert result.templates == []
      refute Map.has_key?(result, :templates_error)
    end
  end

  # ---------------------------------------------------------------------------
  # Robustness
  # ---------------------------------------------------------------------------

  describe "research/2 never raises" do
    test "garbage input degrades to stated-reason sections" do
      garbage_inputs = [
        %{},
        %{repo: nil, title: nil, body: nil},
        %{repo: 42, title: ["not", "a", "title"], body: %{nested: true}},
        %{"repo" => "string/keys", "title" => "atom-key contract ignored"},
        %{repo: "acme/widget", title: String.duplicate("a", 5_000), body: nil},
        %{repo: "acme/widget", title: "!!! ??? ...", body: nil},
        :not_even_a_map
      ]

      for input <- garbage_inputs do
        assert {:ok, %{forge: forge, local: local, templates: templates}} =
                 Research.research(input, gh_disabled: true, include_templates: false)

        assert is_map(forge)
        assert is_map(local)
        assert is_list(templates)
        assert %{recorded_submissions: n} = local.stats
        assert is_integer(n) and n >= 0
      end
    end

    test "garbage opts are tolerated" do
      assert {:ok, %{forge: _, local: _, templates: _}} =
               Research.research(
                 %{repo: "", title: "Crash on save", body: nil},
                 %{this: "is not a keyword list"}
               )
    end
  end
end

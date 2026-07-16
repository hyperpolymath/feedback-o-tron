# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.SynthesizerTest do
  # Uses the globally named AuditLog and TemplateCache, so run serially.
  use ExUnit.Case, async: false

  alias FeedbackATron.AuditLog
  alias FeedbackATron.Synthesis.Synthesizer
  alias FeedbackATron.Synthesis.TemplateCache

  @bug_yaml """
  name: Bug Report
  description: File a bug report
  labels:
    - bug
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
    - type: textarea
      id: repro
      attributes:
        label: Steps to reproduce
      validations:
        required: true
    - type: input
      id: version
      attributes:
        label: Version
      validations:
        required: true
    - type: dropdown
      id: severity
      attributes:
        label: Severity
        options:
          - low
          - high
      validations:
        required: true
  """

  @feature_yaml """
  name: Feature Request
  description: Suggest an idea
  body:
    - type: textarea
      id: idea
      attributes:
        label: Describe the feature
      validations:
        required: true
  """

  setup do
    # Ensure the audit log is running (it may be started by the application).
    case Process.whereis(AuditLog) do
      nil -> {:ok, _pid} = AuditLog.start_link(log_dir: System.tmp_dir!())
      _pid -> :ok
    end

    # TemplateCache is started by the application; fall back to a
    # supervised instance when running without it.
    case Process.whereis(TemplateCache) do
      nil -> start_supervised!(TemplateCache)
      _pid -> :ok
    end

    :ok = TemplateCache.purge()

    bypass = Bypass.open()
    base = "http://localhost:#{bypass.port}"
    {:ok, bypass: bypass, base: base}
  end

  defp serve_templates(bypass, repo) do
    listing = [
      %{"name" => "bug.yml", "type" => "file"},
      %{"name" => "feature.yml", "type" => "file"}
    ]

    Bypass.stub(bypass, "GET", "/repos/#{repo}/contents/.github/ISSUE_TEMPLATE", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(listing))
    end)

    Bypass.stub(bypass, "GET", "/#{repo}/HEAD/.github/ISSUE_TEMPLATE/bug.yml", fn conn ->
      Plug.Conn.resp(conn, 200, @bug_yaml)
    end)

    Bypass.stub(bypass, "GET", "/#{repo}/HEAD/.github/ISSUE_TEMPLATE/feature.yml", fn conn ->
      Plug.Conn.resp(conn, 200, @feature_yaml)
    end)
  end

  # ---------------------------------------------------------------------------
  # Template selection + hydration
  # ---------------------------------------------------------------------------

  describe "templated drafts" do
    test "bug text picks bug.yml and renders through the receiver's form", %{
      bypass: bypass,
      base: base
    } do
      repo = "acme/widget"
      serve_templates(bypass, repo)

      raw = """
      The editor crashes with an error every time I save.

      Steps to reproduce:
      1. Open a file
      2. Press save

      Seen on version 1.2.3
      """

      assert {:ok, result} =
               Synthesizer.synthesize(
                 %{raw_feedback: raw, repo: repo, context: %{}, system_state: %{}},
                 base_url: base,
                 raw_base_url: base
               )

      assert result.intent.intent == :bug
      assert result.intent.salvaged == false
      assert result.intent.stripped_reason == nil
      assert result.template == "bug.yml"

      # Title is the first sentence of the feedback.
      assert result.draft.title == "The editor crashes with an error every time I save."

      # Body is rendered in the receiver's form order and taxonomy.
      assert result.draft.body =~ "### What happened?"
      assert result.draft.body =~ "The editor crashes"
      assert result.draft.body =~ "### Steps to reproduce"
      assert result.draft.body =~ "1. Open a file"

      # template_data is the hydrated fields map.
      assert result.draft.template_data["version"] == "1.2.3"

      # The unfillable required dropdown comes back as an open question
      # with the receiver's own options — never guessed.
      assert [severity] = Enum.filter(result.open_questions, &(&1.field_id == "severity"))
      assert severity.options == ["low", "high"]
      assert severity.required == true
    end

    test "feature text picks feature.yml", %{bypass: bypass, base: base} do
      repo = "acme/gadget"
      serve_templates(bypass, repo)

      raw = "Please add support for dark mode. It would be great for late-night work."

      assert {:ok, result} =
               Synthesizer.synthesize(
                 %{raw_feedback: raw, repo: repo, context: %{}, system_state: %{}},
                 base_url: base,
                 raw_base_url: base
               )

      assert result.intent.intent == :feature
      assert result.template == "feature.yml"
    end

    test "explicit template option overrides intent-based selection", %{
      bypass: bypass,
      base: base
    } do
      repo = "acme/override"
      serve_templates(bypass, repo)

      raw = "The exporter crashes on empty projects."

      assert {:ok, result} =
               Synthesizer.synthesize(
                 %{raw_feedback: raw, repo: repo, context: %{}, system_state: %{}},
                 base_url: base,
                 raw_base_url: base,
                 template: "feature.yml"
               )

      assert result.template == "feature.yml"
    end

    test "context title wins over derived title", %{bypass: bypass, base: base} do
      repo = "acme/titled"
      serve_templates(bypass, repo)

      assert {:ok, result} =
               Synthesizer.synthesize(
                 %{
                   raw_feedback: "The sync job fails after upgrading past 3.1.0.",
                   repo: repo,
                   context: %{"title" => "Sync failure after 3.1.0 upgrade"},
                   system_state: %{}
                 },
                 base_url: base,
                 raw_base_url: base
               )

      assert result.draft.title == "Sync failure after 3.1.0 upgrade"
    end
  end

  # ---------------------------------------------------------------------------
  # Generic fallback (no templates)
  # ---------------------------------------------------------------------------

  describe "generic fallback" do
    test "no templates yields a generic draft with generic open questions", %{
      bypass: bypass,
      base: base
    } do
      repo = "acme/bare"

      Bypass.stub(bypass, "GET", "/repos/#{repo}/contents/.github/ISSUE_TEMPLATE", fn conn ->
        Plug.Conn.resp(conn, 404, ~s({"message": "Not Found"}))
      end)

      raw = "The importer fails on files larger than a gigabyte."

      assert {:ok, result} =
               Synthesizer.synthesize(
                 %{raw_feedback: raw, repo: repo, context: %{}, system_state: %{}},
                 base_url: base,
                 raw_base_url: base
               )

      assert result.template == nil
      assert result.draft.template_data == %{}

      # Core text plus the environment skeleton.
      assert result.draft.body =~ "The importer fails"
      assert result.draft.body =~ "## Environment"
      assert result.draft.body =~ "## Steps to Reproduce"

      # Doctrine point 4: thin feedback comes back with questions,
      # never silently discarded.
      assert Enum.map(result.open_questions, & &1.field_id) == ["repro-steps", "version"]
      assert Enum.all?(result.open_questions, & &1.required)
    end
  end

  # ---------------------------------------------------------------------------
  # Doctrine: rejection and salvage
  # ---------------------------------------------------------------------------

  describe "doctrine" do
    test "abusive-only input is rejected with a stated reason and audit-logged" do
      repo = "acme/reject-#{System.unique_integer([:positive])}"
      raw = "You suck. This is garbage. Total trash."

      assert {:reject, %{reason: reason}} =
               Synthesizer.synthesize(
                 %{raw_feedback: raw, repo: repo, context: %{}, system_state: %{}},
                 []
               )

      assert reason =~ "hostility"

      # Doctrine point 2: the rejection is audit-logged. AuditLog has no
      # :submission_rejected event type, so the Synthesizer logs the
      # closest allowed one (:submission_failure) with rejected: true.
      entries = AuditLog.recent(50)

      assert Enum.any?(entries, fn entry ->
               entry["event"] == "submission_failure" and
                 entry["data"]["rejected"] == true and
                 entry["data"]["repo"] == repo and
                 entry["data"]["reason"] == reason
             end)
    end

    test "salvaged input strips abuse and carries stripped_reason through", %{
      bypass: bypass,
      base: base
    } do
      repo = "acme/salvage"
      serve_templates(bypass, repo)

      raw = "This garbage editor crashes every time I press save. Version 2.0.1 on linux."

      assert {:ok, result} =
               Synthesizer.synthesize(
                 %{raw_feedback: raw, repo: repo, context: %{}, system_state: %{}},
                 base_url: base,
                 raw_base_url: base
               )

      # Doctrine point 3: actionable core kept, abuse stripped, and both
      # facts reported so the caller can tell the sender what was kept.
      assert result.intent.salvaged == true
      assert is_binary(result.intent.stripped_reason)
      assert result.intent.intent == :bug

      refute result.draft.body =~ "garbage"
      assert result.draft.body =~ "crashes every time I press save"
      assert result.draft.template_data["version"] == "2.0.1"
      assert result.template == "bug.yml"
    end
  end

  # ---------------------------------------------------------------------------
  # Robustness
  # ---------------------------------------------------------------------------

  describe "invalid input" do
    test "non-binary raw_feedback or repo is an error, not a crash" do
      assert {:error, :invalid_input} =
               Synthesizer.synthesize(%{raw_feedback: 42, repo: "acme/widget"}, [])

      assert {:error, :invalid_input} =
               Synthesizer.synthesize(%{raw_feedback: "text long enough", repo: nil}, [])

      assert {:error, :invalid_input} = Synthesizer.synthesize(%{}, [])
    end
  end
end

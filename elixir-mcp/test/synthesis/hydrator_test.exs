# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.HydratorTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Synthesis.Hydrator

  @caller_marker "(caller-supplied)"
  @engine_marker "(engine host — may differ from where the problem occurred)"

  defp field(overrides) do
    Map.merge(
      %{
        id: "field",
        type: :input,
        label: "",
        description: nil,
        placeholder: nil,
        options: [],
        render: nil,
        required: false
      },
      Map.new(overrides)
    )
  end

  defp form(fields) do
    %{
      name: "Bug Report",
      file: "bug.yml",
      description: nil,
      labels: [],
      title: nil,
      fields: fields
    }
  end

  defp input(raw, context \\ %{}, system_state \\ %{}) do
    %{raw_feedback: raw, context: context, system_state: system_state}
  end

  describe "version fields" do
    test "filled from context[\"version\"] when present" do
      form = form([field(id: "version", label: "Version", type: :input)])

      result = Hydrator.hydrate(form, input("it broke", %{"version" => "1.2.3"}))

      assert result.fields["version"] == "1.2.3"
    end

    test "extracted from the raw feedback when context has no version" do
      form = form([field(id: "version", label: "Version", type: :input)])

      result = Hydrator.hydrate(form, input("crashes since upgrading to v2.4.1 yesterday"))

      assert result.fields["version"] == "v2.4.1"
    end

    test "sha in the raw feedback counts as version info" do
      form = form([field(id: "version", label: "Version", type: :input)])

      result = Hydrator.hydrate(form, input("broken at commit deadbeef1234"))

      assert result.fields["version"] == "deadbeef1234"
    end
  end

  describe "log and repro fields" do
    test "stack trace lands in a logs field" do
      raw = """
      It crashed hard.
      ** (RuntimeError) boom
          MyApp.Worker.run/1
          MyApp.Server.handle_call/3
      """

      form = form([field(id: "logs", label: "Relevant log output", type: :textarea)])

      result = Hydrator.hydrate(form, input(raw))

      assert result.fields["logs"] =~ "** (RuntimeError) boom"
      assert result.fields["logs"] =~ "MyApp.Worker.run/1"
    end

    test "numbered steps land in a repro field" do
      raw = """
      The export dies.
      1. Open the app
      2. Click export
      3. Watch it crash
      """

      form = form([field(id: "repro", label: "Steps to reproduce", type: :textarea)])

      result = Hydrator.hydrate(form, input(raw))

      assert result.fields["repro"] =~ "1. Open the app"
      assert result.fields["repro"] =~ "3. Watch it crash"
    end
  end

  describe "description fields" do
    test "what-happened field gets the raw feedback trimmed" do
      form = form([field(id: "what-happened", label: "What happened?", type: :textarea)])

      result = Hydrator.hydrate(form, input("  the export button crashes the app  "))

      assert result.fields["what-happened"] == "the export button crashes the app"
    end

    test "opts[:core_text] wins over the raw feedback" do
      form = form([field(id: "description", label: "Description", type: :textarea)])

      result =
        Hydrator.hydrate(form, input("raw with hostility"), core_text: "just the core")

      assert result.fields["description"] == "just the core"
    end
  end

  describe "open questions" do
    test "unfilled required field becomes an open question with its options" do
      severity =
        field(
          id: "severity",
          label: "Severity",
          type: :dropdown,
          options: ["low", "high"],
          required: true,
          description: "How bad is it?"
        )

      result = Hydrator.hydrate(form([severity]), input("something is off"))

      refute Map.has_key?(result.fields, "severity")

      assert [question] = result.open_questions
      assert question.field_id == "severity"
      assert question.label == "Severity"
      assert question.description == "How bad is it?"
      assert question.required == true
      assert question.options == ["low", "high"]
    end

    test "unfilled optional field is omitted, not asked" do
      contact = field(id: "contact", label: "Contact Details", type: :input, required: false)

      result = Hydrator.hydrate(form([contact]), input("something is off"))

      refute Map.has_key?(result.fields, "contact")
      assert result.open_questions == []
    end

    test "opts[:ask_optional] surfaces unfilled optional fields too" do
      contact = field(id: "contact", label: "Contact Details", type: :input, required: false)

      result = Hydrator.hydrate(form([contact]), input("something is off"), ask_optional: true)

      assert [%{field_id: "contact", required: false}] = result.open_questions
    end
  end

  describe "dropdowns" do
    test "filled when a context value matches an option case-insensitively" do
      browser =
        field(
          id: "browser",
          label: "Browser",
          type: :dropdown,
          options: ["Firefox", "Chrome"],
          required: true
        )

      result = Hydrator.hydrate(form([browser]), input("it broke", %{"browser" => "firefox"}))

      # The option's exact spelling wins over the caller's casing.
      assert result.fields["browser"] == "Firefox"
      assert result.open_questions == []
    end

    test "near-match never fills; the field is asked instead" do
      version =
        field(
          id: "version",
          label: "Version",
          type: :dropdown,
          options: ["1.0.2", "1.0.3"],
          required: true
        )

      result = Hydrator.hydrate(form([version]), input("it broke", %{"version" => "1.0"}))

      refute Map.has_key?(result.fields, "version")
      assert [%{field_id: "version", options: ["1.0.2", "1.0.3"]}] = result.open_questions
    end
  end

  describe "environment fields" do
    test "carries caller system_state and engine facts with provenance markers" do
      env = field(id: "environment", label: "Environment", type: :textarea)

      result =
        Hydrator.hydrate(form([env]), input("it broke", %{}, %{"os" => "macOS 14.2"}))

      text = result.fields["environment"]

      assert text =~ "os: macOS 14.2 #{@caller_marker}"
      assert text =~ @engine_marker
      assert text =~ "otp_release: #{System.otp_release()}"
      assert text =~ "elixir: #{System.version()}"
    end

    test "expected field comes from context[\"expected\"]" do
      expected = field(id: "expected", label: "Expected behavior", type: :textarea)

      result =
        Hydrator.hydrate(form([expected]), input("it broke", %{"expected" => "a clean export"}))

      assert result.fields["expected"] == "a clean export"
    end
  end

  describe "probes" do
    test "probes are empty by default" do
      form = form([field(id: "environment", label: "Environment", type: :textarea)])

      result = Hydrator.hydrate(form, input("it broke"))

      assert result.probes == %{}
    end

    test "no probe runs when only one of the two flags is set" do
      form = form([field(id: "environment", label: "Environment", type: :textarea)])

      assert Hydrator.hydrate(form, input("timeout"), network_probe: true).probes == %{}
      assert Hydrator.hydrate(form, input("timeout"), network_related: true).probes == %{}
    end
  end

  describe "markdown fields" do
    test "markdown blocks are never filled and never asked" do
      md = field(id: "md-0", label: "", type: :markdown, required: false)
      what = field(id: "what-happened", label: "What happened?", type: :textarea, required: true)

      result = Hydrator.hydrate(form([md, what]), input("the export crashes"))

      refute Map.has_key?(result.fields, "md-0")
      assert result.open_questions == []
      assert Map.keys(result.fields) == ["what-happened"]
    end
  end
end

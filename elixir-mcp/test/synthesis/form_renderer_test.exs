# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.FormRendererTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Synthesis.FormRenderer

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

  test "renders fields in form order with ### headings" do
    form =
      form([
        field(id: "what", label: "What happened?", type: :textarea),
        field(id: "version", label: "Version", type: :input)
      ])

    rendered = FormRenderer.render(form, %{"what" => "it crashed", "version" => "1.2.3"})

    assert rendered == "### What happened?\n\nit crashed\n\n### Version\n\n1.2.3"
  end

  test "missing and blank values render as _No response_" do
    form =
      form([
        field(id: "contact", label: "Contact Details", type: :input),
        field(id: "extra", label: "Anything else?", type: :textarea)
      ])

    rendered = FormRenderer.render(form, %{"extra" => ""})

    assert rendered ==
             "### Contact Details\n\n_No response_\n\n### Anything else?\n\n_No response_"
  end

  test "render metadata wraps the value in a fenced code block" do
    form =
      form([field(id: "logs", label: "Relevant log output", type: :textarea, render: "shell")])

    rendered = FormRenderer.render(form, %{"logs" => "** (RuntimeError) boom"})

    assert rendered == "### Relevant log output\n\n```shell\n** (RuntimeError) boom\n```"
  end

  test "checkbox list values become - [x] lines" do
    form =
      form([
        field(
          id: "terms",
          label: "Code of Conduct",
          type: :checkboxes,
          options: ["I agree", "I have searched existing issues"]
        )
      ])

    rendered =
      FormRenderer.render(form, %{"terms" => ["I agree", "I have searched existing issues"]})

    assert rendered ==
             "### Code of Conduct\n\n- [x] I agree\n- [x] I have searched existing issues"
  end

  test "empty checkbox list renders as _No response_" do
    form = form([field(id: "terms", label: "Code of Conduct", type: :checkboxes)])

    assert FormRenderer.render(form, %{"terms" => []}) ==
             "### Code of Conduct\n\n_No response_"
  end

  test "markdown blocks are skipped entirely" do
    form =
      form([
        field(id: "md-0", label: "", type: :markdown),
        field(id: "what", label: "What happened?", type: :textarea)
      ])

    rendered = FormRenderer.render(form, %{"what" => "it crashed"})

    assert rendered == "### What happened?\n\nit crashed"
  end
end

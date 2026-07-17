# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.FormValidatorTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Synthesis.FormValidator

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

  defp form do
    %{
      name: "Bug Report",
      file: "bug.yml",
      description: nil,
      labels: [],
      title: nil,
      fields: [
        field(id: "md-0", type: :markdown),
        field(id: "what", label: "What happened?", type: :textarea, required: true),
        field(id: "version", label: "Version", type: :dropdown, options: ["1.0.2", "1.0.3"]),
        field(id: "terms", label: "Code of Conduct", type: :checkboxes, options: ["I agree"]),
        field(id: "contact", label: "Contact Details", type: :input)
      ]
    }
  end

  test "valid payload returns :ok" do
    answers = %{
      "what" => "it crashed",
      "version" => "1.0.2",
      "terms" => ["I agree"],
      "contact" => "me@example.com"
    }

    assert FormValidator.validate(form(), answers) == :ok
  end

  test "missing required field is :required_missing" do
    assert {:error, [error]} = FormValidator.validate(form(), %{})

    assert error.field == "what"
    assert error.error == :required_missing
    assert is_binary(error.detail)
  end

  test "blank string counts as missing" do
    assert {:error, [error]} = FormValidator.validate(form(), %{"what" => "   "})

    assert error.field == "what"
    assert error.error == :required_missing
  end

  test "unknown keys are :unknown_field, including markdown ids" do
    answers = %{"what" => "it crashed", "md-0" => "sneaky", "bogus" => "nope"}

    assert {:error, errors} = FormValidator.validate(form(), answers)

    assert Enum.map(errors, &{&1.field, &1.error}) == [
             {"bogus", :unknown_field},
             {"md-0", :unknown_field}
           ]
  end

  test "dropdown answer outside options is :invalid_option" do
    answers = %{"what" => "it crashed", "version" => "2.0.0"}

    assert {:error, [error]} = FormValidator.validate(form(), answers)

    assert error.field == "version"
    assert error.error == :invalid_option
    assert error.detail =~ "2.0.0"
  end

  test "non-string values are :not_a_string" do
    answers = %{"what" => "it crashed", "contact" => 42}

    assert {:error, [error]} = FormValidator.validate(form(), answers)

    assert error.field == "contact"
    assert error.error == :not_a_string
  end

  test "checkbox list with non-binary items is :not_a_string" do
    answers = %{"what" => "it crashed", "terms" => ["I agree", :yes]}

    assert {:error, [error]} = FormValidator.validate(form(), answers)

    assert error.field == "terms"
    assert error.error == :not_a_string
  end

  test "empty checkbox list on a required field is :required_missing" do
    required_terms =
      field(id: "terms", label: "Terms", type: :checkboxes, options: ["ok"], required: true)

    form = %{form() | fields: [required_terms]}

    assert {:error, [error]} = FormValidator.validate(form, %{"terms" => []})

    assert error.field == "terms"
    assert error.error == :required_missing
  end

  test "all violations are collected, not just the first" do
    answers = %{
      "version" => "9.9.9",
      "contact" => 42,
      "bogus" => "nope"
    }

    assert {:error, errors} = FormValidator.validate(form(), answers)

    assert Enum.map(errors, &{&1.field, &1.error}) == [
             {"what", :required_missing},
             {"version", :invalid_option},
             {"contact", :not_a_string},
             {"bogus", :unknown_field}
           ]
  end
end

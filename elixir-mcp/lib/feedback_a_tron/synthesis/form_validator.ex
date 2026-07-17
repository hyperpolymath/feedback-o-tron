# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.FormValidator do
  @moduledoc """
  Validates an answers map against a parsed issue-form
  (`FeedbackATron.Synthesis.TemplateFetcher` shape) before rendering and
  submission, so nothing hollow or malformed is filed in the receiver's
  name.

  Rules:

  * every required field must be present and non-blank
    (`String.trim/1 != ""`; for checkboxes, a non-empty list) —
    `:required_missing`
  * every provided key must be a known **non-markdown** field id —
    `:unknown_field` (markdown blocks are display-only and take no answer)
  * a dropdown answer must be one of the field's options —
    `:invalid_option`
  * values must be binaries; checkboxes may instead be a list of binaries —
    `:not_a_string`

  Checkbox selections are type-checked but not matched against options
  here; the renderer emits them verbatim as `- [x]` lines.

  All violations are collected, not just the first:

      :ok | {:error, [%{field: id, error: reason, detail: text}]}
  """

  @doc """
  Validate `answers` (`%{field_id => value}`) against `form`.

  Returns `:ok` or `{:error, errors}` with every violation found. Errors
  for the form's fields come first (in form order), then unknown keys
  (sorted).
  """
  def validate(form, answers) when is_map(answers) do
    known_fields = Enum.reject(form.fields, &(&1.type == :markdown))
    known_ids = MapSet.new(known_fields, & &1.id)

    field_errors = Enum.flat_map(known_fields, &check_field(&1, answers))

    unknown_errors =
      answers
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(known_ids, &1))
      |> Enum.sort_by(&key_to_string/1)
      |> Enum.map(fn key ->
        %{
          field: key_to_string(key),
          error: :unknown_field,
          detail: "#{inspect(key)} is not a field of #{form.file}"
        }
      end)

    case field_errors ++ unknown_errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp check_field(field, answers) do
    case Map.fetch(answers, field.id) do
      :error ->
        if field.required, do: [required_missing(field, "no answer provided")], else: []

      {:ok, value} ->
        check_value(field, value)
    end
  end

  defp check_value(field, value) when is_binary(value) do
    cond do
      String.trim(value) == "" ->
        if field.required, do: [required_missing(field, "answer is blank")], else: []

      field.type == :dropdown and value not in field.options ->
        [
          %{
            field: field.id,
            error: :invalid_option,
            detail: "#{inspect(value)} is not one of #{inspect(field.options)}"
          }
        ]

      true ->
        []
    end
  end

  defp check_value(%{type: :checkboxes} = field, value) when is_list(value) do
    cond do
      not Enum.all?(value, &is_binary/1) ->
        [
          %{
            field: field.id,
            error: :not_a_string,
            detail: "checkbox selections must be a list of strings, got: #{inspect(value)}"
          }
        ]

      value == [] and field.required ->
        [required_missing(field, "no boxes ticked")]

      true ->
        []
    end
  end

  defp check_value(field, value) do
    [
      %{
        field: field.id,
        error: :not_a_string,
        detail: "expected a string, got: #{inspect(value)}"
      }
    ]
  end

  defp required_missing(field, detail) do
    %{
      field: field.id,
      error: :required_missing,
      detail: "#{inspect(field.label)} is required: #{detail}"
    }
  end

  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: inspect(key)
end

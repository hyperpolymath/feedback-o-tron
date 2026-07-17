# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.FormRenderer do
  @moduledoc """
  Renders a filled issue-form into the Markdown body GitHub produces when
  a user submits the same form, so synthesized issues are indistinguishable
  from hand-filled ones (doctrine: shaped for the receiver).

  For each non-markdown field, in form order:

      ### <label>

      <value or _No response_>

  Sections are joined with blank lines. When a field carries `render`
  metadata (`FeedbackATron.Synthesis.TemplateFetcher` captures
  `attributes.render`, e.g. `"shell"`), the value is wrapped in a fenced
  code block with that language. Checkbox values given as a list become
  `- [x] item` lines. Markdown blocks are display-only and are skipped.
  """

  @no_response "_No response_"

  @doc """
  Render `form` with the answers in `fields` (`%{field_id => value}`).

  Missing, `nil`, empty-string, and empty-list values render as
  `#{@no_response}`.
  """
  def render(form, fields) when is_map(fields) do
    form.fields
    |> Enum.reject(&(&1.type == :markdown))
    |> Enum.map(fn field ->
      "### " <> field.label <> "\n\n" <> render_value(field, Map.get(fields, field.id))
    end)
    |> Enum.join("\n\n")
  end

  defp render_value(_field, nil), do: @no_response
  defp render_value(_field, ""), do: @no_response
  defp render_value(_field, []), do: @no_response

  defp render_value(field, value) when is_list(value) do
    value
    |> Enum.map(&("- [x] " <> to_string(&1)))
    |> Enum.join("\n")
    |> maybe_fence(field)
  end

  defp render_value(field, value) when is_binary(value), do: maybe_fence(value, field)

  # Defensive: validated payloads are strings or lists, but never crash
  # the renderer on anything else.
  defp render_value(field, value), do: maybe_fence(inspect(value), field)

  defp maybe_fence(text, field) do
    case Map.get(field, :render) do
      render when is_binary(render) and render != "" ->
        "```" <> render <> "\n" <> text <> "\n```"

      _no_render ->
        text
    end
  end
end

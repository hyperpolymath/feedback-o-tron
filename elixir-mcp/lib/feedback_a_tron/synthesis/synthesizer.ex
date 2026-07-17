# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.Synthesizer do
  @moduledoc """
  Orchestrates the synthesis pipeline: raw feedback in, receiver-shaped
  draft out.

      classify -> fetch receiver's templates -> pick form -> hydrate
               -> render -> draft + open questions

  Doctrine applied here:

  * **Usefulness gates, not tone** — classification is delegated to
    `FeedbackATron.Synthesis.IntentClassifier`, which strips hostility
    but keeps the actionable core.
  * **Zero-signal abuse** is rejected with the classifier's stated
    reason, audit-logged, and never filed. `AuditLog` has no
    `:submission_rejected` event type, so rejections are logged as the
    closest allowed type, `:submission_failure`, with `rejected: true`.
  * **Mixed content** — the returned `intent` map carries `salvaged` and
    `stripped_reason` through untouched so the caller can tell the
    sender what was kept and why.
  * **Useless-but-genuine** feedback comes back with `open_questions`
    (from the hydrator, or generic ones on the no-template path) — never
    silently discarded.
  * **Shaped for the receiver** — their template, their taxonomy: the
    form is fetched from the target repo, filled by the hydrator, and
    rendered exactly as GitHub renders a hand-filled form. When the repo
    has no templates, a generic draft is produced instead.

  ## Result shape

      {:ok, %{
        intent: map(),                 # classifier output, incl. salvaged/stripped_reason
        template: String.t() | nil,    # chosen template filename
        draft: %{title: _, body: _, template_data: %{field_id => value}},
        open_questions: [map()]
      }}
      | {:reject, %{reason: String.t()}}
      | {:error, term()}
  """

  alias FeedbackATron.AuditLog

  alias FeedbackATron.Synthesis.{
    FormRenderer,
    Hydrator,
    IntentClassifier,
    TemplateFetcher
  }

  @title_max 80

  @generic_open_questions [
    %{
      field_id: "repro-steps",
      label: "Steps to reproduce",
      description: "Numbered steps that reliably trigger the problem",
      required: true,
      options: []
    },
    %{
      field_id: "version",
      label: "Version",
      description: "Release version, commit, or build where this was observed",
      required: true,
      options: []
    }
  ]

  @generic_skeleton """
  ## Environment

  - Version: _please fill in_
  - OS / platform: _please fill in_

  ## Steps to Reproduce

  _please fill in_
  """

  @doc """
  Synthesize a receiver-shaped draft from raw feedback.

  `input` requires `:raw_feedback` and `:repo`; `:context` (sender-supplied
  metadata such as `"title"`, `"version"`, `"template"`) and
  `:system_state` (caller environment facts) default to `%{}`.

  Options:

  * `:template` — explicit template filename to use when the repo has it
  * `:network_probe` — set `true` to let the hydrator run a network
    preflight when the feedback looks network-related
  * `:base_url` / `:raw_base_url` — forwarded to `TemplateFetcher`
  """
  def synthesize(input, opts \\ [])

  def synthesize(%{raw_feedback: raw, repo: repo} = input, opts)
      when is_binary(raw) and is_binary(repo) do
    context = input |> Map.get(:context) |> stringify_keys()
    system_state = map_or_empty(Map.get(input, :system_state))

    case IntentClassifier.classify(raw, context) do
      {:reject, rejection} ->
        # Doctrine point 2: stated reason, audit-logged, never filed.
        # :submission_rejected is not an AuditLog event type; use the
        # closest allowed one and mark it as a rejection.
        AuditLog.log(:submission_failure, %{
          rejected: true,
          reason: rejection.reason,
          repo: repo
        })

        {:reject, rejection}

      {:ok, intent} ->
        build_draft(intent, repo, context, system_state, opts)
    end
  rescue
    error -> {:error, {:synthesis_failed, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:synthesis_failed, inspect(reason)}}
  end

  def synthesize(_input, _opts), do: {:error, :invalid_input}

  # ---------------------------------------------------------------------------
  # Draft building
  # ---------------------------------------------------------------------------

  defp build_draft(intent, repo, context, system_state, opts) do
    case fetch_forms(repo, opts) do
      [_ | _] = forms ->
        forms
        |> pick_form(intent.intent, wanted_template(opts, context))
        |> templated_draft(intent, context, system_state, opts)

      [] ->
        generic_draft(intent, context)
    end
  end

  defp templated_draft(form, intent, context, system_state, opts) do
    hydration =
      Hydrator.hydrate(
        form,
        %{raw_feedback: intent.core_text, context: context, system_state: system_state},
        network_probe: Keyword.get(opts, :network_probe),
        network_related: intent.signals.network_related,
        core_text: intent.core_text
      )

    {:ok,
     %{
       intent: intent,
       template: form.file,
       draft: %{
         title: derive_title(context, intent.core_text),
         body: FormRenderer.render(form, hydration.fields),
         template_data: hydration.fields
       },
       open_questions: hydration.open_questions
     }}
  end

  # No templates: still file something useful, and ask for what a bug
  # report always needs rather than silently discarding thin feedback.
  defp generic_draft(intent, context) do
    body = String.trim_trailing(intent.core_text) <> "\n\n" <> @generic_skeleton

    {:ok,
     %{
       intent: intent,
       template: nil,
       draft: %{
         title: derive_title(context, intent.core_text),
         body: body,
         template_data: %{}
       },
       open_questions: @generic_open_questions
     }}
  end

  # ---------------------------------------------------------------------------
  # Template selection
  # ---------------------------------------------------------------------------

  # Template fetch failures (no templates, network trouble, missing
  # cache) all degrade to the generic path — synthesis must not fail
  # just because the receiver's forms are unreachable.
  defp fetch_forms(repo, opts) do
    case TemplateFetcher.fetch(repo, opts) do
      {:ok, forms} when is_list(forms) -> forms
      _error -> []
    end
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # Explicit filename first, then the intent's conventional file, then
  # whatever the repo lists first.
  defp pick_form(forms, intent, wanted) do
    explicit_form(forms, wanted) || intent_form(forms, intent) || hd(forms)
  end

  defp explicit_form(_forms, nil), do: nil
  defp explicit_form(forms, wanted), do: Enum.find(forms, &(&1.file == wanted))

  defp intent_form(forms, :bug), do: Enum.find(forms, &(&1.file =~ ~r/bug/i))
  defp intent_form(forms, :feature), do: Enum.find(forms, &(&1.file =~ ~r/feat/i))
  defp intent_form(_forms, _intent), do: nil

  defp wanted_template(opts, context) do
    case Keyword.get(opts, :template) do
      wanted when is_binary(wanted) and wanted != "" -> wanted
      _ -> string_or_nil(context["template"])
    end
  end

  # ---------------------------------------------------------------------------
  # Title derivation
  # ---------------------------------------------------------------------------

  defp derive_title(context, core_text) do
    case string_or_nil(context["title"]) do
      nil -> core_text |> first_sentence() |> truncate(@title_max)
      title -> title |> String.trim() |> truncate(@title_max)
    end
  end

  defp first_sentence(text) do
    text
    |> String.trim()
    |> String.split(~r/(?<=[.!?])\s+|\n/, parts: 2)
    |> hd()
    |> String.trim()
    |> case do
      "" -> "Feedback"
      sentence -> sentence
    end
  end

  defp truncate(text, max) do
    if String.length(text) > max do
      String.slice(text, 0, max - 3) <> "..."
    else
      text
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp stringify_keys(context) when is_map(context) do
    Map.new(context, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(_context), do: %{}

  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_value), do: %{}

  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_value), do: nil
end

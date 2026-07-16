# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.Hydrator do
  @moduledoc """
  Fills a parsed issue-form (`FeedbackATron.Synthesis.TemplateFetcher` shape)
  from raw feedback, caller context, and system state.

  Doctrine applied here:

  * **Shaped for the receiver** — only the receiver's own fields are filled,
    in their taxonomy. Nothing is invented: a field is filled only when a
    matching value actually exists in the feedback or context.
  * **Never silently discard** — any required field that could not be filled
    comes back as an `open_questions` entry (with the field's options) so
    the sender can be asked, rather than filing a hollow report.

  ## Field matching

  Each non-markdown field is matched over
  `String.downcase(id <> " " <> label)`:

  * `version` — `context["version"]`, else the first semver/sha extracted
    from the raw feedback
  * `logs` / `stack` / `trace` / `output` —
    `IntentClassifier.extract_stack_trace/1`
  * `repro` / `steps` — `IntentClassifier.extract_repro_steps/1`
  * `environment` / `os` / `platform` / `system` — caller `system_state`
    (each line marked `(caller-supplied)`) merged with engine facts (marked
    `(engine host — may differ from where the problem occurred)`)
  * `expected` — `context["expected"]`
  * `what happened` / `description` / `describe` / `details` — the raw
    feedback trimmed (or `opts[:core_text]` when provided, e.g. the
    de-abused core from `IntentClassifier`); prose only goes into
    `:textarea` fields, so a one-line `:input` like "Contact Details"
    is never stuffed with the whole report

  Dropdowns are filled **only** when a context value equals one of the
  field's options case-insensitively — the option's exact spelling is used.
  Near-matches are never guessed. Checkboxes are never auto-filled.
  Markdown blocks are display-only: never filled, never asked.

  ## Network probes

  When `opts[:network_probe] == true` **and** `opts[:network_related] ==
  true`, `FeedbackATron.NetworkVerifier.preflight_check/1` is run against
  `opts[:probe_target]` (default #{inspect("https://api.github.com")})
  under a #{10_000}ms task guard. A pass/fail summary is appended to the
  environment field text and the raw result is returned under
  `probes.network`; any error becomes `probes.network = %{error: ...}`.
  By default `probes == %{}` and no probe runs.

  ## Result shape

      %{
        fields: %{field_id => value},          # only filled, non-blank values
        open_questions: [
          %{field_id: _, label: _, description: _, required: _, options: _}
        ],
        probes: %{} | %{network: map}
      }

  Unfilled optional fields are simply omitted from `fields` and are not
  asked unless `opts[:ask_optional] == true`.
  """

  alias FeedbackATron.Synthesis.IntentClassifier

  @probe_timeout_ms 10_000
  @default_probe_target "https://api.github.com"

  @caller_marker "(caller-supplied)"
  @engine_marker "(engine host — may differ from where the problem occurred)"

  # Semver-ish: 1.2.3 / v0.10.1
  @semver_re ~r/\bv?\d+\.\d+\.\d+\b/
  # Hex sha candidates; post-filtered to require both a digit and an a-f
  # letter so plain decimals and ordinary words don't count
  @sha_candidate_re ~r/\b[0-9a-f]{7,40}\b/

  # Match rules over the downcased "id label" haystack, most specific
  # first — the generic description bucket ("details", "describe") comes
  # last so "Environment details" still gets the environment treatment.
  @version_re ~r/version/
  @logs_re ~r/\blogs?\b|stack|trace|output/
  @repro_re ~r/repro|\bsteps?\b/
  @environment_re ~r/environment|\bos\b|platform|\bsystem\b/
  @expected_re ~r/expect/
  @description_re ~r/what[\s_-]*happened|description|describe|details/

  @doc """
  Hydrate `form` from `raw_feedback`, `context`, and `system_state`.

  Options:

  * `:core_text` — de-abused actionable core to use for description-like
    fields instead of the raw feedback
  * `:ask_optional` — also return unfilled optional fields as open questions
  * `:network_probe` / `:network_related` — both must be `true` to run the
    network preflight probe
  * `:probe_target` — URL for the preflight probe
  """
  def hydrate(form, input, opts \\ [])

  def hydrate(form, %{raw_feedback: raw, context: context, system_state: system_state}, opts)
      when is_binary(raw) do
    context = stringify_keys(context || %{})
    probes = maybe_probe(opts)
    env_text = environment_text(system_state || %{}, probes)
    description_text = String.trim(Keyword.get(opts, :core_text) || raw)
    ask_optional = Keyword.get(opts, :ask_optional, false) == true

    {fields, open_questions} =
      form.fields
      |> Enum.reject(&(&1.type == :markdown))
      |> Enum.reduce({%{}, []}, fn field, {fields, questions} ->
        case fill_field(field, raw, description_text, context, env_text) do
          value when is_binary(value) and value != "" ->
            {Map.put(fields, field.id, value), questions}

          _unfilled ->
            if field.required or ask_optional do
              {fields, [open_question(field) | questions]}
            else
              {fields, questions}
            end
        end
      end)

    %{fields: fields, open_questions: Enum.reverse(open_questions), probes: probes}
  end

  # ---------------------------------------------------------------------------
  # Field filling
  # ---------------------------------------------------------------------------

  defp fill_field(%{type: :dropdown} = field, _raw, _description, context, _env_text) do
    dropdown_value(field, context)
  end

  # Checkboxes are choices the sender must make; never auto-tick them.
  defp fill_field(%{type: :checkboxes}, _raw, _description, _context, _env_text), do: nil

  defp fill_field(field, raw, description_text, context, env_text) do
    haystack = haystack(field)

    cond do
      haystack =~ @version_re -> binary_or_nil(context["version"]) || extract_version(raw)
      haystack =~ @logs_re -> IntentClassifier.extract_stack_trace(raw)
      haystack =~ @repro_re -> IntentClassifier.extract_repro_steps(raw)
      haystack =~ @environment_re -> env_text
      haystack =~ @expected_re -> binary_or_nil(context["expected"])
      field.type == :textarea and haystack =~ @description_re -> description_text
      true -> nil
    end
  end

  defp haystack(field) do
    String.downcase(field.id <> " " <> field.label)
  end

  # Fill ONLY when a context value equals an option case-insensitively;
  # the option's exact spelling wins. Never guess a near-match.
  defp dropdown_value(field, context) do
    candidates =
      context
      |> Map.values()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)

    Enum.find(field.options, fn option ->
      String.downcase(option) in candidates
    end)
  end

  defp extract_version(raw) do
    case Regex.run(@semver_re, raw) do
      [version | _] -> version
      nil -> extract_sha(raw)
    end
  end

  defp extract_sha(raw) do
    @sha_candidate_re
    |> Regex.scan(raw)
    |> Enum.map(fn [candidate | _] -> candidate end)
    |> Enum.find(fn candidate ->
      String.match?(candidate, ~r/\d/) and String.match?(candidate, ~r/[a-f]/)
    end)
  end

  defp open_question(field) do
    %{
      field_id: field.id,
      label: field.label,
      description: field.description,
      required: field.required,
      options: field.options
    }
  end

  # ---------------------------------------------------------------------------
  # Environment text
  # ---------------------------------------------------------------------------

  defp environment_text(system_state, probes) do
    caller_lines =
      system_state
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, value} ->
        "#{key}: #{format_value(value)} #{@caller_marker}"
      end)

    engine_lines =
      [
        "os: #{engine_os()}",
        "otp_release: #{System.otp_release()}",
        "elixir: #{System.version()}"
      ]
      |> Enum.map(&(&1 <> " " <> @engine_marker))

    probe_lines =
      case probe_summary(probes[:network]) do
        nil -> []
        summary -> [summary]
      end

    Enum.join(caller_lines ++ engine_lines ++ probe_lines, "\n")
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp engine_os do
    {family, name} = :os.type()
    "#{family}/#{name} #{engine_os_version()}"
  end

  defp engine_os_version do
    case :os.version() do
      version when is_tuple(version) ->
        version |> Tuple.to_list() |> Enum.join(".")

      version ->
        to_string(version)
    end
  end

  # ---------------------------------------------------------------------------
  # Network probe (opt-in, guarded)
  # ---------------------------------------------------------------------------

  defp maybe_probe(opts) do
    if Keyword.get(opts, :network_probe) == true and
         Keyword.get(opts, :network_related) == true do
      target = Keyword.get(opts, :probe_target, @default_probe_target)
      %{network: run_probe(target)}
    else
      %{}
    end
  end

  # The preflight runs in its own task so a hung or missing NetworkVerifier
  # can never stall hydration; exits inside the task are caught so the
  # linked caller survives a dead GenServer.
  defp run_probe(target) do
    task =
      Task.async(fn ->
        try do
          FeedbackATron.NetworkVerifier.preflight_check(target)
        rescue
          e -> {:probe_error, inspect(e)}
        catch
          :exit, reason -> {:probe_error, inspect(reason)}
        end
      end)

    case Task.yield(task, @probe_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} -> result
      {:ok, {:probe_error, message}} -> %{error: message}
      {:ok, other} -> %{error: inspect(other)}
      {:exit, reason} -> %{error: inspect(reason)}
      nil -> %{error: "network preflight timed out after #{@probe_timeout_ms}ms"}
    end
  rescue
    e -> %{error: inspect(e)}
  end

  # preflight_check/2 returns {:ok, %{passed: boolean, checks: %{name => %{status: _}}}}
  defp probe_summary(nil), do: nil

  defp probe_summary(%{checks: checks}) when is_map(checks) do
    total = map_size(checks)
    passed = Enum.count(checks, fn {_name, result} -> check_passed?(result) end)

    failed =
      for {name, result} <- checks, not check_passed?(result), do: to_string(name)

    base = "network preflight: #{passed}/#{total} checks passed"

    case Enum.sort(failed) do
      [] -> base
      names -> base <> " (failed: #{Enum.join(names, ", ")})"
    end
  end

  defp probe_summary(%{error: error}), do: "network preflight: probe error (#{error})"
  defp probe_summary(_other), do: nil

  defp check_passed?(%{status: :ok}), do: true
  defp check_passed?(_result), do: false

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp stringify_keys(context) when is_map(context) do
    Map.new(context, fn {key, value} -> {to_string(key), value} end)
  end

  defp binary_or_nil(value) when is_binary(value) and value != "", do: value
  defp binary_or_nil(_value), do: nil
end

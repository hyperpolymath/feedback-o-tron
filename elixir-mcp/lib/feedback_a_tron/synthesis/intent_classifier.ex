# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.IntentClassifier do
  @moduledoc """
  Classifies raw feedback text into an intent (`:bug`, `:feature`, `:question`,
  `:docs`, `:praise`) with a confidence score and extracted signals, applying
  the feedback-handling doctrine:

  1. The gate is **usefulness, not tone**. Blunt or annoyed feedback with a
     real defect description passes through.
  2. Zero-signal abuse is rejected with a stated reason and never filed.
  3. Mixed content is salvaged: the actionable core is kept, the abuse is
     stripped, and both facts are reported (`salvaged: true` +
     `stripped_reason`).
  4. Praise is genuine feedback and classifies as `:praise` — it is never
     rejected just for containing no defect.

  All functions are pure — no processes, no side effects. Callers that need
  audit logging of rejections (doctrine point 2) do so at the call site.

  ## Result shape

      {:ok, %{
        intent: :bug | :feature | :question | :docs | :praise,
        confidence: float,            # 0.1..0.99
        signals: %{
          stack_trace: boolean,
          repro_steps: boolean,
          version_info: boolean,
          network_related: boolean
        },
        salvaged: boolean,            # true when hostility was stripped
        core_text: String.t(),        # raw when salvaged: false
        stripped_reason: String.t() | nil
      }}

      {:reject, %{reason: String.t()}}
  """

  # ---------------------------------------------------------------------
  # Signal detection patterns
  # ---------------------------------------------------------------------

  # Elixir: "** (RuntimeError)" / "** (Ecto.Query.CastError)" headers
  @elixir_error_re ~r/\*\* \([A-Z]\w+(\.\w+)*Error\)/
  # Elixir: indented Module.fun/arity stack frames
  @elixir_frame_re ~r/^\s+(\w+\.)+\w+\/\d+/m
  # JavaScript: "    at fn (file.js:10:5)" stack frames
  @js_frame_re ~r/^\s+at .+\(.+:\d+(:\d+)?\)/m
  # Python: traceback header
  @python_trace_re ~r/Traceback \(most recent call last\)/
  # Python: '  File "app.py", line 10' frames (used for block extraction)
  @python_frame_re ~r/^\s+File ".+", line \d+/m
  # Generic "SomeError: message" raise line (Python/JS final line)
  @error_line_re ~r/^\s*\w+(\.\w+)*Error: /m

  # Numbered list item: "1. do this" / "2) do that"
  @numbered_item_re ~r/^\s*\d+[.)]\s+/m
  @repro_phrase_re ~r/steps to reproduce/i

  # Semver-ish: 1.2.3 / v0.10.1
  @semver_re ~r/\bv?\d+\.\d+\.\d+\b/
  # "version" within a few characters of a digit ("version 4", "Version: 12")
  @version_word_re ~r/version\D{0,10}\d/i
  # Hex sha candidates; post-filtered to require both a digit and an a-f
  # letter so plain decimals and ordinary words don't count
  @sha_candidate_re ~r/\b[0-9a-f]{7,40}\b/

  @network_re ~r/\b(timeout|timed out|dns|tls|ssl|certificate|connection refused|ECONNREFUSED|EHOSTUNREACH|proxy|socket)\b/i

  # ---------------------------------------------------------------------
  # Intent keyword buckets
  # ---------------------------------------------------------------------

  @bug_patterns [
    ~r/\bcrash(es|ed|ing)?\b/i,
    ~r/\berrors?\b/i,
    ~r/\bexceptions?\b/i,
    ~r/\bbroken\b/i,
    ~r/\bbreaks?\b/i,
    ~r/\bfail(s|ed|ing|ure)?\b/i,
    ~r/\bregression\b/i,
    ~r/\btraceback\b/i,
    ~r/\bsegfault\b/i,
    ~r/\bbugs?\b/i,
    ~r/\bdoes(n't| not) work\b/i
  ]

  @feature_patterns [
    ~r/\badd support\b/i,
    ~r/\bwould be (nice|great)\b/i,
    ~r/\bfeature request\b/i,
    ~r/\bcould you\b/i,
    ~r/\benhancements?\b/i,
    ~r/\bplease add\b/i,
    ~r/\bsupport for\b/i
  ]

  @question_patterns [
    ~r/^\s*(how|why|what|where|can|does)\b/i,
    ~r/\bhow do i\b/i,
    ~r/\?\s*$/
  ]

  @docs_patterns [
    ~r/\breadme\b/i,
    ~r/\bdocumentation\b/i,
    ~r/\bdocs?\b/i,
    ~r/\btypos?\b/i,
    ~r/\bunclear\b/i,
    ~r/\bwording\b/i
  ]

  @praise_patterns [
    ~r/\bthanks?\b/i,
    ~r/\bthank you\b/i,
    ~r/\blove\b/i,
    ~r/\bgreat\b/i,
    ~r/\bawesome\b/i,
    ~r/\bbrilliant\b/i
  ]

  # A stack trace is near-conclusive evidence of a bug report
  @stack_trace_weight 3

  # ---------------------------------------------------------------------
  # Hostility detection (doctrine points 1-3)
  # ---------------------------------------------------------------------

  # Intentionally minimal and conservative: this list targets unambiguous
  # hostility directed at people or the project, not strong language about
  # a defect ("this is badly broken" passes untouched). False negatives
  # are acceptable — downstream humans still review; false positives that
  # eat genuine feedback are not. "garbage" excludes "garbage collection"
  # and friends via negative lookahead.
  @hostility_patterns [
    ~r/\byou\s+(guys\s+|all\s+)?suck\b/i,
    ~r/\bthis\s+sucks\b/i,
    ~r/\bgarbage\b(?!\s+collect)/i,
    ~r/\btrash\b/i,
    ~r/\bidiots?\b/i,
    ~r/\bmorons?\b/i,
    ~r/\bhate\s+(you|this)\b/i,
    ~r/\bworst\b.*\bever\b/i,
    ~r/\bkill\s+yourself\b/i,
    ~r/\bkys\b/i,
    ~r/\bdumpster\s+fire\b/i,
    ~r/\bf[u*]+ck(er|ers|ing|ed)?\b/i,
    ~r/\bsh[i*]t(ty|e)?\b/i,
    ~r/\bcrap(py)?\b/i
  ]

  # Words that don't count as substantive content when judging whether a
  # de-abused sentence still says anything
  @filler_words ~w(the this that with and but for you your are is was were
                   its it's a an of to in on at i we they he she it so such
                   very really just all what when who)

  @hostility_reject_reason "contains only hostility; no defect description, " <>
                             "reproduction, or request to act on — nothing to file"

  @too_short_reject_reason "empty or too short to contain actionable feedback"

  @stripped_reason "hostile/non-constructive wording removed; kept the actionable content"

  # Minimum trimmed length for feedback to be considered at all
  @min_length 8

  # De-abused text longer than this is presumed to carry enough substance
  # to be worth filing with open questions rather than rejecting
  @substantive_length 60

  # ---------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------

  @doc """
  Classify raw feedback text.

  Returns `{:ok, result}` with intent, confidence, signals, and salvage
  metadata, or `{:reject, %{reason: reason}}` when the text is empty, too
  short, or contains only hostility with nothing actionable.

  `context` is accepted for API compatibility (upstream callers pass page
  URL, app version, etc.) but classification is based on the text alone.
  """
  @spec classify(String.t(), map()) :: {:ok, map()} | {:reject, %{reason: String.t()}}
  def classify(raw, _context \\ %{}) when is_binary(raw) do
    trimmed = String.trim(raw)

    cond do
      String.length(trimmed) < @min_length ->
        {:reject, %{reason: @too_short_reject_reason}}

      hostile?(raw) ->
        classify_hostile(raw)

      true ->
        {:ok, build_result(raw, raw, false, nil)}
    end
  end

  @doc """
  Return the largest contiguous block of stack-trace lines (with one line
  of leading context when available), or `nil` when no trace is present.
  """
  @spec extract_stack_trace(String.t()) :: String.t() | nil
  def extract_stack_trace(raw) when is_binary(raw) do
    lines = String.split(raw, "\n")

    case largest_run(lines, &trace_line?/1, 1) do
      nil ->
        nil

      {start_idx, last_idx} ->
        context_start = max(start_idx - 1, 0)

        lines
        |> Enum.slice(context_start..last_idx)
        |> Enum.join("\n")
    end
  end

  @doc """
  Return the largest contiguous numbered-list block (two or more items),
  or `nil` when no such block is present.
  """
  @spec extract_repro_steps(String.t()) :: String.t() | nil
  def extract_repro_steps(raw) when is_binary(raw) do
    lines = String.split(raw, "\n")

    case largest_run(lines, &numbered_line?/1, 2) do
      nil ->
        nil

      {start_idx, last_idx} ->
        lines
        |> Enum.slice(start_idx..last_idx)
        |> Enum.join("\n")
    end
  end

  # ---------------------------------------------------------------------
  # Hostility handling
  # ---------------------------------------------------------------------

  defp classify_hostile(raw) do
    core = strip_hostility(raw)

    if salvageable?(core) do
      {:ok, build_result(core, core, true, @stripped_reason)}
    else
      {:reject, %{reason: @hostility_reject_reason}}
    end
  end

  defp hostile?(text) do
    Enum.any?(@hostility_patterns, &Regex.match?(&1, text))
  end

  # Strip hostility line by line so multi-line content (stack traces,
  # numbered steps) keeps its structure. Lines without hostility are kept
  # byte-for-byte; hostile lines are de-abused sentence by sentence and
  # whitespace-normalized. Lines reduced to nothing are dropped.
  defp strip_hostility(text) do
    text
    |> String.split("\n")
    |> Enum.map(&de_abuse_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp de_abuse_line(line) do
    if hostile?(line) do
      cleaned =
        line
        |> split_sentences()
        |> Enum.map(&de_abuse_sentence/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
        |> normalize_whitespace()

      if cleaned == "", do: nil, else: cleaned
    else
      line
    end
  end

  # A purely hostile sentence is dropped whole; a mixed sentence keeps its
  # residue with the hostile lexemes removed.
  defp de_abuse_sentence(sentence) do
    if hostile?(sentence) do
      residue =
        @hostility_patterns
        |> Enum.reduce(sentence, fn re, acc -> Regex.replace(re, acc, " ") end)
        |> normalize_whitespace()

      if substantive?(residue), do: residue, else: nil
    else
      sentence
    end
  end

  defp split_sentences(text) do
    Regex.split(~r/(?<=[.!?])\s+/, text)
  end

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
  end

  # Does the de-abused residue still say anything? At least one non-filler
  # word of three or more characters.
  defp substantive?(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9']+/, trim: true)
    |> Enum.any?(fn word ->
      String.length(word) >= 3 and word not in @filler_words
    end)
  end

  # Salvageable when the de-abused core carries any signal, scores in any
  # intent bucket, or is long enough to be substantive on its own.
  defp salvageable?(core) do
    signals = detect_signals(core)

    Enum.any?(Map.values(signals)) or
      any_bucket_scored?(core) or
      String.length(core) > @substantive_length
  end

  defp any_bucket_scored?(text) do
    [@bug_patterns, @feature_patterns, @question_patterns, @docs_patterns, @praise_patterns]
    |> Enum.any?(fn patterns -> count_matches(text, patterns) > 0 end)
  end

  # ---------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------

  defp build_result(analysis_text, core_text, salvaged, stripped_reason) do
    signals = detect_signals(analysis_text)
    {intent, confidence} = score_intent(analysis_text, signals)

    %{
      intent: intent,
      confidence: confidence,
      signals: signals,
      salvaged: salvaged,
      core_text: core_text,
      stripped_reason: stripped_reason
    }
  end

  defp detect_signals(text) do
    %{
      stack_trace: stack_trace?(text),
      repro_steps: repro_steps?(text),
      version_info: version_info?(text),
      network_related: Regex.match?(@network_re, text)
    }
  end

  defp stack_trace?(text) do
    Regex.match?(@elixir_error_re, text) or
      Regex.match?(@elixir_frame_re, text) or
      Regex.match?(@js_frame_re, text) or
      Regex.match?(@python_trace_re, text)
  end

  defp repro_steps?(text) do
    length(Regex.scan(@numbered_item_re, text)) >= 2 or
      Regex.match?(@repro_phrase_re, text)
  end

  defp version_info?(text) do
    Regex.match?(@semver_re, text) or
      Regex.match?(@version_word_re, text) or
      sha_present?(text)
  end

  defp sha_present?(text) do
    @sha_candidate_re
    |> Regex.scan(text)
    |> Enum.any?(fn [candidate | _] ->
      String.match?(candidate, ~r/\d/) and String.match?(candidate, ~r/[a-f]/)
    end)
  end

  defp score_intent(text, signals) do
    bug_keywords = count_matches(text, @bug_patterns)
    stack_bonus = if signals.stack_trace, do: @stack_trace_weight, else: 0
    feature = count_matches(text, @feature_patterns)
    question = count_matches(text, @question_patterns)
    docs = count_matches(text, @docs_patterns)

    # Praise only counts when there is no bug or feature evidence —
    # "would be great if you added X" is a feature request, not praise
    praise =
      if bug_keywords > 0 or feature > 0 do
        0
      else
        count_matches(text, @praise_patterns)
      end

    scores = [
      bug: bug_keywords + stack_bonus,
      feature: feature,
      question: question,
      docs: docs,
      praise: praise
    ]

    total = scores |> Keyword.values() |> Enum.sum()
    {intent, winning} = Enum.max_by(scores, fn {_intent, score} -> score end)

    cond do
      winning > 0 -> {intent, clamp_confidence(winning / max(total, 1))}
      signals.stack_trace -> {:bug, clamp_confidence(0.0)}
      true -> {:question, clamp_confidence(0.0)}
    end
  end

  defp count_matches(text, patterns) do
    Enum.count(patterns, &Regex.match?(&1, text))
  end

  defp clamp_confidence(value) do
    value |> max(0.1) |> min(0.99)
  end

  # ---------------------------------------------------------------------
  # Block extraction
  # ---------------------------------------------------------------------

  # Find the largest contiguous run of lines satisfying `matcher`, with at
  # least `min_len` lines. Returns {start_index, last_index} or nil.
  defp largest_run(lines, matcher, min_len) do
    lines
    |> Enum.with_index()
    |> Enum.chunk_by(fn {line, _idx} -> matcher.(line) end)
    |> Enum.filter(fn [{line, _idx} | _] -> matcher.(line) end)
    |> Enum.filter(fn chunk -> length(chunk) >= min_len end)
    |> Enum.max_by(&length/1, fn -> nil end)
    |> case do
      nil ->
        nil

      chunk ->
        {_line, start_idx} = List.first(chunk)
        {_line, last_idx} = List.last(chunk)
        {start_idx, last_idx}
    end
  end

  defp trace_line?(line) do
    Regex.match?(@elixir_error_re, line) or
      Regex.match?(@elixir_frame_re, line) or
      Regex.match?(@js_frame_re, line) or
      Regex.match?(@python_trace_re, line) or
      Regex.match?(@python_frame_re, line) or
      Regex.match?(@error_line_re, line)
  end

  defp numbered_line?(line) do
    Regex.match?(@numbered_item_re, line)
  end
end

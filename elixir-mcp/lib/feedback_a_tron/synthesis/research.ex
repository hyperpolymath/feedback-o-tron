# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.Research do
  @moduledoc """
  Research mode: before a draft is filed, gather what is already known
  about the feedback so recurring themes are recognized as recurring and
  one-offs are treated as one-offs (doctrine point 5).

  Three independent probes, each degraded gracefully — `research/2` never
  raises and always returns `{:ok, map}`:

  * **Forge** — searches the receiver's issue tracker via the `gh` CLI
    (mirroring `FeedbackATron.Channels.GitHub`'s token handling). Matches
    are scored against the input title with
    `FeedbackATron.TextSimilarity.similarity/2` and sorted best-first.
    When `gh` is missing (or `opts[:gh_disabled]` is set, the test escape
    hatch) the forge section reports `status: "unavailable"` with a
    stated reason rather than failing the research.
  * **Local** — `FeedbackATron.Deduplicator.check/1` against this
    engine's own submission history, plus `stats` with the count of
    recorded submissions so callers can judge pattern-vs-one-off.
  * **Templates** — the receiver's issue forms via
    `FeedbackATron.Synthesis.TemplateFetcher`, summarized to the
    questions each form asks (shaped for the receiver, doctrine point 6).
    Skipped when `opts[:include_templates] == false`; fetch failures
    yield `templates: []` plus a `templates_error` string.

  ## Result shape

      {:ok, %{
        forge: %{status: "ok", matches: [%{number, title, url, state, score}]}
             | %{status: "unavailable", reason: String.t()},
        local: %{status: "unique" | "duplicate" | "similar" | "unavailable",
                 ...,
                 stats: %{recorded_submissions: non_neg_integer()}},
        templates: [%{name: _, file: _, questions: [String.t()]}]
        # plus templates_error: String.t() when the fetch failed
      }}
  """

  alias FeedbackATron.Deduplicator
  alias FeedbackATron.TextSimilarity
  alias FeedbackATron.Synthesis.TemplateFetcher

  @default_limit 5
  @max_limit 20
  @max_query_words 6

  # Small stopword list: articles, copulas, pronouns, and glue words that
  # carry no search signal in an issue title.
  @stopwords ~w(a an and are as at be but by can do does for from has have
                how i if in into is it its my not of on or our so that the
                then this to was we were what when where which why will
                with you your)

  @doc """
  Research prior art for a draft issue.

  `input` is a map with `:repo` (`"owner/repo"`), `:title`, and optional
  `:body`. Options:

  * `:limit` — forge match cap, clamped to 1..#{@max_limit} (default #{@default_limit})
  * `:gh_disabled` — treat the `gh` CLI as absent (test escape hatch)
  * `:include_templates` — set `false` to skip the template fetch
  * `:base_url` / `:raw_base_url` — forwarded to `TemplateFetcher`

  Never raises: every sub-probe is rescue/catch-guarded, and malformed
  input degrades to empty strings. Always returns `{:ok, map}`.
  """
  def research(input, opts \\ []) do
    opts = if Keyword.keyword?(opts), do: opts, else: []
    repo = string_field(input, :repo)
    title = string_field(input, :title)
    body = string_field(input, :body)

    forge =
      safe(
        fn -> forge_search(repo, title, opts) end,
        fn message -> %{status: "unavailable", reason: message} end
      )

    local =
      safe(
        fn -> local_check(repo, title, body) end,
        fn message ->
          %{status: "unavailable", reason: message, stats: %{recorded_submissions: 0}}
        end
      )

    templates =
      safe(
        fn -> templates(repo, opts) end,
        fn message -> %{templates: [], templates_error: message} end
      )

    {:ok, Map.merge(%{forge: forge, local: local}, templates)}
  end

  # ---------------------------------------------------------------------------
  # Forge search (gh CLI)
  # ---------------------------------------------------------------------------

  defp forge_search(repo, title, opts) do
    query = significant_query(title)

    cond do
      Keyword.get(opts, :gh_disabled, false) or System.find_executable("gh") == nil ->
        %{status: "unavailable", reason: "gh CLI not found on PATH"}

      repo == "" ->
        %{status: "unavailable", reason: "no repo to search"}

      query == "" ->
        %{status: "unavailable", reason: "no significant words in title to search"}

      true ->
        run_gh_search(repo, query, title, normalize_limit(Keyword.get(opts, :limit)))
    end
  end

  defp run_gh_search(repo, query, title, limit) do
    args = [
      "search",
      "issues",
      "--repo",
      repo,
      query,
      "--json",
      "number,title,url,state",
      "--limit",
      to_string(limit)
    ]

    case System.cmd("gh", args, env: token_env(), stderr_to_stdout: true) do
      {output, 0} ->
        decode_matches(output, title)

      {output, code} ->
        %{status: "unavailable", reason: failure_reason(output, code)}
    end
  end

  defp decode_matches(output, title) do
    case Jason.decode(output) do
      {:ok, entries} when is_list(entries) ->
        matches =
          entries
          |> Enum.map(&annotate_match(&1, title))
          |> Enum.sort_by(& &1.score, :desc)

        %{status: "ok", matches: matches}

      _other ->
        %{status: "unavailable", reason: "unparsable gh search output"}
    end
  end

  defp annotate_match(entry, title) when is_map(entry) do
    match_title = if is_binary(entry["title"]), do: entry["title"], else: ""

    %{
      number: entry["number"],
      title: match_title,
      url: entry["url"],
      state: entry["state"],
      score: Float.round(TextSimilarity.similarity(match_title, title), 2)
    }
  end

  defp annotate_match(_entry, _title) do
    %{number: nil, title: "", url: nil, state: nil, score: 0.0}
  end

  # Strip punctuation, drop stopwords, keep the first significant words.
  # A title made entirely of stopwords falls back to its raw words so the
  # search still has something to chew on.
  defp significant_query(title) do
    words =
      title
      |> String.downcase()
      |> String.replace(~r/[^\w\s]/u, " ")
      |> String.split(~r/\s+/, trim: true)

    words
    |> Enum.reject(&(&1 in @stopwords))
    |> case do
      [] -> words
      significant -> significant
    end
    |> Enum.take(@max_query_words)
    |> Enum.join(" ")
  end

  defp normalize_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_limit)
  defp normalize_limit(_limit), do: @default_limit

  # Mirrors FeedbackATron.Channels.GitHub: gh authenticates via GH_TOKEN.
  # Anonymous searches still work for public repos, so any credential
  # failure degrades to an empty env rather than aborting the search.
  defp token_env do
    creds = FeedbackATron.Credentials.load()

    case FeedbackATron.Credentials.get(creds, :github) do
      {:ok, %{token: token}} when is_binary(token) -> [{"GH_TOKEN", token}]
      _ -> []
    end
  rescue
    _ -> []
  end

  defp failure_reason(output, code) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(&1 != ""))
    |> case do
      nil -> "gh exited with status #{code}"
      line -> line
    end
  end

  # ---------------------------------------------------------------------------
  # Local history (Deduplicator)
  # ---------------------------------------------------------------------------

  # Deduplicator.check/1 returns {:ok, :unique} | {:duplicate, submission}
  # | {:similar, [%{title, hash, similarity}]}; each is mapped to a
  # string-status section. Recurrence stats ride along so callers can
  # tell a recurring theme from a one-off (doctrine point 5).
  defp local_check(repo, title, body) do
    result =
      case Deduplicator.check(%{title: title, body: body, repo: repo}) do
        {:ok, :unique} ->
          %{status: "unique"}

        {:duplicate, existing} ->
          %{status: "duplicate", match: summarize_submission(existing)}

        {:similar, matches} ->
          %{status: "similar", matches: Enum.map(matches, &summarize_similar/1)}

        other ->
          %{status: "unavailable", reason: "unexpected dedup result: #{inspect(other)}"}
      end

    Map.put(result, :stats, recurrence_stats())
  end

  defp summarize_submission(existing) when is_map(existing) do
    %{
      hash: Map.get(existing, :hash),
      title: Map.get(existing, :title),
      platform: Map.get(existing, :platform),
      submitted_at: Map.get(existing, :submitted_at)
    }
  end

  defp summarize_submission(existing), do: %{detail: inspect(existing)}

  defp summarize_similar(%{title: title, hash: hash, similarity: similarity}) do
    %{title: title, hash: hash, score: Float.round(similarity / 1, 2)}
  end

  defp summarize_similar(other), do: %{detail: inspect(other)}

  defp recurrence_stats do
    stats = Deduplicator.stats()
    %{recorded_submissions: Map.get(stats, :total_submissions, 0)}
  rescue
    _ -> %{recorded_submissions: 0}
  catch
    :exit, _ -> %{recorded_submissions: 0}
  end

  # ---------------------------------------------------------------------------
  # Templates (receiver's issue forms)
  # ---------------------------------------------------------------------------

  defp templates(repo, opts) do
    cond do
      Keyword.get(opts, :include_templates, true) == false ->
        %{templates: []}

      repo == "" ->
        %{templates: [], templates_error: "no repo to fetch templates from"}

      true ->
        fetch_templates(repo, opts)
    end
  end

  defp fetch_templates(repo, opts) do
    case TemplateFetcher.fetch(repo, opts) do
      {:ok, forms} ->
        %{templates: Enum.map(forms, &summarize_form/1)}

      {:error, reason} ->
        %{templates: [], templates_error: format_error(reason)}
    end
  end

  defp summarize_form(form) do
    %{
      name: form.name,
      file: form.file,
      questions:
        form.fields
        |> Enum.reject(&(&1.type == :markdown))
        |> Enum.map(& &1.label)
    }
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason), do: inspect(reason)

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp string_field(input, key) when is_map(input) do
    case Map.get(input, key) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp string_field(_input, _key), do: ""

  # Run a probe; any raise, throw, or exit (e.g. a dedup GenServer that
  # isn't running) becomes the probe's stated-reason fallback instead of
  # taking down the whole research call.
  defp safe(fun, fallback) do
    fun.()
  rescue
    error -> fallback.(Exception.message(error))
  catch
    :exit, reason -> fallback.("service unavailable: #{inspect(reason)}")
    kind, reason -> fallback.("#{kind}: #{inspect(reason)}")
  end
end

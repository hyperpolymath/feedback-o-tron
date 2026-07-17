# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.TextSimilarity do
  @moduledoc """
  Text normalization and similarity scoring for feedback deduplication.

  Provides:
  - Normalized Levenshtein similarity (1 - distance/max_len) in the range 0..1
  - Raw Levenshtein edit distance
  - Title and body normalization (lowercase, whitespace/punctuation cleanup)

  Extracted from `FeedbackATron.Deduplicator` so other synthesis modules
  (e.g. recurring-theme recognition) can score text similarity without
  going through the deduplication GenServer.
  """

  @doc """
  Normalized Levenshtein similarity (1 - distance/max_len).

  Returns a float in 0..1 where 1.0 means identical strings and 0.0 means
  no similarity (or one string is empty while the other is not).
  """
  @spec similarity(String.t(), String.t()) :: float()
  def similarity(s1, s2) do
    cond do
      s1 == s2 ->
        1.0

      String.length(s1) == 0 or String.length(s2) == 0 ->
        0.0

      true ->
        len1 = String.length(s1)
        len2 = String.length(s2)
        max_len = max(len1, len2)
        distance = levenshtein(s1, s2)
        1.0 - distance / max_len
    end
  end

  @doc """
  Levenshtein edit distance between two strings (grapheme-based).

  Counts the minimum number of single-character insertions, deletions,
  and substitutions needed to transform `s1` into `s2`.
  """
  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  def levenshtein(s1, s2) do
    s1_len = String.length(s1)
    s2_len = String.length(s2)

    if s1_len == 0,
      do: s2_len,
      else:
        if(s2_len == 0,
          do: s1_len,
          else: do_levenshtein(String.graphemes(s1), String.graphemes(s2), s1_len, s2_len)
        )
  end

  @doc """
  Normalize an issue title for comparison: lowercase, strip punctuation,
  collapse whitespace, trim.
  """
  @spec normalize_title(String.t()) :: String.t()
  def normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Normalize an issue body for comparison: lowercase, collapse whitespace,
  trim, then truncate to the first 500 bytes.
  """
  @spec normalize_body(String.t()) :: String.t()
  def normalize_body(body) do
    normalized =
      body
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    # Take first 500 bytes safely (after normalization)
    size = byte_size(normalized)

    if size > 500 do
      binary_part(normalized, 0, 500)
    else
      normalized
    end
  end

  # Private functions

  defp do_levenshtein(s1, s2, _len1, len2) do
    # Dynamic programming approach
    row = 0..len2 |> Enum.to_list()

    {final_row, _} =
      Enum.reduce(Enum.with_index(s1), {row, 0}, fn {c1, i}, {prev_row, _} ->
        new_row =
          Enum.reduce(Enum.with_index(s2), [i + 1], fn {c2, j}, acc ->
            cost = if c1 == c2, do: 0, else: 1

            val =
              Enum.min([
                # deletion
                Enum.at(acc, j) + 1,
                # insertion
                Enum.at(prev_row, j + 1) + 1,
                # substitution
                Enum.at(prev_row, j) + cost
              ])

            acc ++ [val]
          end)

        {new_row, i + 1}
      end)

    List.last(final_row)
  end
end

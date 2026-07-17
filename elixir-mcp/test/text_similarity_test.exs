# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Unit tests for FeedbackATron.TextSimilarity.
#
# Pure functions, no shared state, so these tests run concurrently.
#
# Tests cover:
#   - Normalized Levenshtein similarity (identical, disjoint, empty inputs)
#   - Raw Levenshtein edit distances (known values)
#   - Title normalization (case, punctuation, whitespace)
#   - Body normalization (whitespace collapse, 500-byte truncation)
#   - Near-duplicate detection above the deduplicator's 0.85 threshold

defmodule FeedbackATron.TextSimilarityTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.TextSimilarity

  describe "similarity/2" do
    test "identical strings score 1.0" do
      assert TextSimilarity.similarity("hello world", "hello world") == 1.0
    end

    test "identical empty strings score 1.0" do
      assert TextSimilarity.similarity("", "") == 1.0
    end

    test "completely different strings score low" do
      # levenshtein("hello", "world") == 4, so similarity == 1 - 4/5 == 0.2
      score = TextSimilarity.similarity("hello", "world")
      assert_in_delta score, 0.2, 0.0001
      assert score < 0.5
    end

    test "empty vs non-empty scores 0.0" do
      assert TextSimilarity.similarity("", "something") == 0.0
      assert TextSimilarity.similarity("something", "") == 0.0
    end

    test "a near-duplicate pair scores above the 0.85 dedup threshold" do
      a = "app crashes when clicking save"
      b = "app crashes when clicking safe"
      assert TextSimilarity.similarity(a, b) > 0.85
    end

    test "similarity is symmetric" do
      a = "network timeout on upload"
      b = "network timeouts on uploads"
      assert TextSimilarity.similarity(a, b) == TextSimilarity.similarity(b, a)
    end
  end

  describe "levenshtein/2" do
    test "kitten -> sitting is the classic distance of 3" do
      assert TextSimilarity.levenshtein("kitten", "sitting") == 3
    end

    test "identical strings have distance 0" do
      assert TextSimilarity.levenshtein("same", "same") == 0
    end

    test "distance to or from an empty string is the other string's length" do
      assert TextSimilarity.levenshtein("", "abc") == 3
      assert TextSimilarity.levenshtein("abc", "") == 3
    end

    test "single substitution has distance 1" do
      assert TextSimilarity.levenshtein("save", "safe") == 1
    end
  end

  describe "normalize_title/1" do
    test "lowercases, strips punctuation, and collapses whitespace" do
      assert TextSimilarity.normalize_title("  Hello,   WORLD!  ") == "hello world"
    end

    test "titles differing only in case and whitespace normalize to identity" do
      a = TextSimilarity.normalize_title("Login Button   Crashes App!")
      b = TextSimilarity.normalize_title("login button crashes app")
      assert a == b
      assert TextSimilarity.similarity(a, b) == 1.0
    end
  end

  describe "normalize_body/1" do
    test "lowercases and collapses whitespace" do
      assert TextSimilarity.normalize_body("Some\n\nBody   Text ") == "some body text"
    end

    test "truncates normalized bodies to 500 bytes" do
      long = String.duplicate("a", 600)
      normalized = TextSimilarity.normalize_body(long)
      assert byte_size(normalized) == 500
    end

    test "leaves short bodies untruncated" do
      assert TextSimilarity.normalize_body("short body") == "short body"
    end
  end
end

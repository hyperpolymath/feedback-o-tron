# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Unit tests for FeedbackATron.Synthesis.IntentClassifier.
#
# Pure functions, no shared state, so these tests run concurrently.
#
# Tests cover:
#   - Intent classification for all five intents (bug/feature/question/docs/praise)
#   - Signal detection: Elixir/JS/Python stack traces, repro steps,
#     version info (semver + sha), network-related wording
#   - Abuse doctrine: pure hostility rejected with a stated reason that
#     never echoes the input; mixed content salvaged with abuse stripped;
#     praise-only feedback is genuine and never rejected
#   - Empty/too-short rejection
#   - Stack trace and repro-step block extraction

defmodule FeedbackATron.Synthesis.IntentClassifierTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Synthesis.IntentClassifier

  describe "classify/2 intent buckets" do
    test "a crash report classifies as :bug" do
      raw = "The app crashes with an error every time I save; this looks like a regression."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.intent == :bug
      assert result.confidence >= 0.5
      assert result.confidence <= 0.99
      assert result.salvaged == false
      assert result.core_text == raw
      assert result.stripped_reason == nil
    end

    test "a feature request classifies as :feature" do
      raw =
        "Feature request: could you add support for exporting reports to CSV? It would be nice."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.intent == :feature
      assert result.confidence >= 0.5
    end

    test "a how-do-I classifies as :question" do
      raw = "How do I configure the retry backoff for submissions?"

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.intent == :question
      assert result.confidence >= 0.5
    end

    test "a documentation complaint classifies as :docs" do
      raw = "The README has a typo and the documentation wording is unclear."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.intent == :docs
      assert result.confidence >= 0.5
    end

    test "praise-only feedback classifies as :praise, never rejected (doctrine)" do
      raw = "Thanks for building this, it is awesome and brilliant — love it!"

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.intent == :praise
      assert result.confidence >= 0.5
      assert result.salvaged == false
    end

    test "text with no signals at all defaults to :question at floor confidence" do
      raw = "hmm interesting behaviour over there somewhere"

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.intent == :question
      assert_in_delta result.confidence, 0.1, 0.0001
    end
  end

  describe "classify/2 stack trace signals" do
    test "detects an Elixir stack trace and defaults intent to :bug" do
      raw = """
      It exploded when I saved:
      ** (RuntimeError) boom
          MyApp.Worker.run/2
          MyApp.Server.handle_call/3
      """

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.stack_trace == true
      assert result.intent == :bug
    end

    test "detects a JavaScript stack trace" do
      raw = """
      the page dies with:
      TypeError: x is undefined
          at save (app.js:10:5)
          at onClick (app.js:22:3)
      """

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.stack_trace == true
      assert result.intent == :bug
    end

    test "detects a Python traceback" do
      raw = """
      our script fails:
      Traceback (most recent call last):
        File "app.py", line 10, in <module>
      ValueError: boom
      """

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.stack_trace == true
      assert result.intent == :bug
    end
  end

  describe "classify/2 other signals" do
    test "detects numbered repro steps" do
      raw = """
      The save button misbehaves.
      1. open the app
      2. click save
      3. watch nothing happen
      """

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.repro_steps == true
    end

    test "detects the phrase 'steps to reproduce'" do
      raw = "Steps to reproduce: open the settings page, then hit save twice."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.repro_steps == true
    end

    test "detects semver version info" do
      raw = "This has been broken since v2.1.0 on my machine."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.version_info == true
    end

    test "detects a commit sha as version info" do
      raw = "The regression was introduced in commit 9f8abc123d somewhere."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.version_info == true
    end

    test "a plain decimal number is not mistaken for a sha" do
      raw = "I clicked the button 12345678 times and nothing else happened"

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.version_info == false
    end

    test "detects network-related wording" do
      raw = "Uploads keep failing with connection refused and then a timeout."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.signals.network_related == true
    end
  end

  describe "classify/2 abuse doctrine" do
    test "pure hostility is rejected with a stated reason, never filed" do
      raw = "you idiots, this garbage is trash and you all suck"

      assert {:reject, %{reason: reason}} = IntentClassifier.classify(raw)
      assert reason =~ "nothing to file"
      # NEVER echo the hostile input back in the reason
      refute reason =~ "idiot"
      refute reason =~ "garbage"
      refute reason =~ "trash"
      refute reason =~ "suck"
    end

    test "mixed content is salvaged: abuse stripped, actionable core kept" do
      raw = "this garbage crashes with ** (RuntimeError) boom when I click save"

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.salvaged == true
      assert result.core_text =~ "RuntimeError"
      refute result.core_text =~ "garbage"
      assert result.intent == :bug
      assert result.signals.stack_trace == true
      assert result.stripped_reason =~ "removed"
    end

    test "a purely hostile sentence is dropped whole, the rest kept verbatim" do
      raw = "You are all morons. The save dialog crashes on submit."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.salvaged == true
      assert result.core_text == "The save dialog crashes on submit."
      refute result.core_text =~ "morons"
      assert result.intent == :bug
    end

    test "'garbage collection' is not treated as hostility" do
      raw = "The garbage collection pause makes the save dialog freeze."

      assert {:ok, result} = IntentClassifier.classify(raw)
      assert result.salvaged == false
      assert result.core_text == raw
    end
  end

  describe "classify/2 empty and too-short input" do
    test "empty string is rejected" do
      assert {:reject, %{reason: reason}} = IntentClassifier.classify("")
      assert reason =~ "too short"
    end

    test "whitespace-only is rejected" do
      assert {:reject, %{reason: reason}} = IntentClassifier.classify("   \n \t ")
      assert reason =~ "too short"
    end

    test "under eight characters is rejected" do
      assert {:reject, %{reason: reason}} = IntentClassifier.classify("bad")
      assert reason =~ "too short"
    end
  end

  describe "extract_stack_trace/1" do
    test "returns the largest contiguous trace block with one line of leading context" do
      raw = """
      It exploded when I saved:
      ** (RuntimeError) boom
          MyApp.Worker.run/2
          MyApp.Server.handle_call/3
      and then the window closed
      """

      extracted = IntentClassifier.extract_stack_trace(raw)

      assert extracted =~ "It exploded when I saved:"
      assert extracted =~ "** (RuntimeError) boom"
      assert extracted =~ "MyApp.Server.handle_call/3"
      refute extracted =~ "window closed"
    end

    test "returns nil when no trace is present" do
      assert IntentClassifier.extract_stack_trace("no trace here, just words") == nil
    end
  end

  describe "extract_repro_steps/1" do
    test "returns the contiguous numbered-list block" do
      raw = """
      The save button misbehaves.
      1. open the app
      2. click save
      3. watch nothing happen
      That is all I know.
      """

      extracted = IntentClassifier.extract_repro_steps(raw)

      assert extracted =~ "1. open the app"
      assert extracted =~ "3. watch nothing happen"
      refute extracted =~ "misbehaves"
      refute extracted =~ "That is all"
    end

    test "a single numbered line is not a block" do
      assert IntentClassifier.extract_repro_steps("1. only one item\nno more here") == nil
    end

    test "returns nil when no numbered list is present" do
      assert IntentClassifier.extract_repro_steps("open the app then click save") == nil
    end
  end
end

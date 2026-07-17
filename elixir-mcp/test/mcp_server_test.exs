# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Unit tests for FeedbackATron.MCP.Server.
#
# Tests the MCP server's initialization and tool registration.
# Does not test live stdio/TCP transport — those require process-level mocking.

defmodule FeedbackATron.MCP.ServerTest do
  use ExUnit.Case, async: false

  describe "module surface" do
    test "MCP.Server module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.MCP.Server)
    end

    test "MCP.Server exports start_link/1" do
      exports = FeedbackATron.MCP.Server.__info__(:functions)
      assert {:start_link, 1} in exports
    end
  end

  describe "SubmitFeedback tool" do
    test "tool module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.MCP.Tools.SubmitFeedback)
    end

    test "tool exports name/0" do
      exports = FeedbackATron.MCP.Tools.SubmitFeedback.__info__(:functions)
      assert {:name, 0} in exports
    end

    test "tool exports description/0" do
      exports = FeedbackATron.MCP.Tools.SubmitFeedback.__info__(:functions)
      assert {:description, 0} in exports
    end

    test "tool exports input_schema/0" do
      exports = FeedbackATron.MCP.Tools.SubmitFeedback.__info__(:functions)
      assert {:input_schema, 0} in exports
    end

    test "tool exports execute/2" do
      exports = FeedbackATron.MCP.Tools.SubmitFeedback.__info__(:functions)
      assert {:execute, 2} in exports
    end

    test "tool name is a string" do
      name = FeedbackATron.MCP.Tools.SubmitFeedback.name()
      assert is_binary(name)
    end

    test "tool description is a string" do
      desc = FeedbackATron.MCP.Tools.SubmitFeedback.description()
      assert is_binary(desc)
    end

    test "tool input_schema is a map" do
      schema = FeedbackATron.MCP.Tools.SubmitFeedback.input_schema()
      assert is_map(schema)
    end

    test "input_schema includes template and template_data" do
      schema = FeedbackATron.MCP.Tools.SubmitFeedback.input_schema()
      assert Map.has_key?(schema.properties, :template)
      assert Map.has_key?(schema.properties, :template_data)
    end
  end

  describe "ResearchFeedback tool" do
    test "tool module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.MCP.Tools.ResearchFeedback)
    end

    test "tool exports execute/2" do
      exports = FeedbackATron.MCP.Tools.ResearchFeedback.__info__(:functions)
      assert {:execute, 2} in exports
    end

    test "tool name is research_feedback" do
      assert FeedbackATron.MCP.Tools.ResearchFeedback.name() == "research_feedback"
    end

    test "tool description is a string" do
      desc = FeedbackATron.MCP.Tools.ResearchFeedback.description()
      assert is_binary(desc)
    end

    test "input_schema requires repo and title" do
      schema = FeedbackATron.MCP.Tools.ResearchFeedback.input_schema()
      assert schema.required == ["repo", "title"]
    end

    test "input_schema declares the canonical properties" do
      schema = FeedbackATron.MCP.Tools.ResearchFeedback.input_schema()

      for key <- [:repo, :title, :body, :limit, :include_templates] do
        assert Map.has_key?(schema.properties, key)
      end
    end
  end

  describe "SynthesizeFeedback tool" do
    test "tool module is loaded" do
      assert Code.ensure_loaded?(FeedbackATron.MCP.Tools.SynthesizeFeedback)
    end

    test "tool exports execute/2" do
      exports = FeedbackATron.MCP.Tools.SynthesizeFeedback.__info__(:functions)
      assert {:execute, 2} in exports
    end

    test "tool name is synthesize_feedback" do
      assert FeedbackATron.MCP.Tools.SynthesizeFeedback.name() == "synthesize_feedback"
    end

    test "tool description is a string" do
      desc = FeedbackATron.MCP.Tools.SynthesizeFeedback.description()
      assert is_binary(desc)
    end

    test "input_schema requires raw_feedback and repo" do
      schema = FeedbackATron.MCP.Tools.SynthesizeFeedback.input_schema()
      assert schema.required == ["raw_feedback", "repo"]
    end

    test "input_schema declares the canonical properties" do
      schema = FeedbackATron.MCP.Tools.SynthesizeFeedback.input_schema()

      for key <- [:raw_feedback, :repo, :context, :system_state, :template, :network_probe] do
        assert Map.has_key?(schema.properties, key)
      end
    end
  end
end

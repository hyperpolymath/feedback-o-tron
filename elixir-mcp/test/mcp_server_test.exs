# SPDX-License-Identifier: PMPL-1.0-or-later
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
  end
end

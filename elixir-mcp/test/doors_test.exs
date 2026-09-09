# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.DoorsTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Doors

  describe "config/2 defaults" do
    test "both doors closed, loopback 7722" do
      assert Doors.config([], %{}) == %{
               mcp_stdio: false,
               http: false,
               http_port: 7722,
               http_ip: {127, 0, 0, 1}
             }
    end
  end

  describe "config/2 precedence" do
    test "application env beats OS env" do
      sys = %{"FEEDBACK_O_TRON_MCP" => "1", "FEEDBACK_O_TRON_HTTP_PORT" => "9999"}

      assert %{mcp_stdio: false, http_port: 8123} =
               Doors.config([mcp_stdio: false, http_port: 8123], sys)
    end

    test "new env names open doors" do
      sys = %{"FEEDBACK_O_TRON_MCP" => "yes", "FEEDBACK_O_TRON_HTTP" => "on"}
      assert %{mcp_stdio: true, http: true} = Doors.config([], sys)
    end

    test "legacy env names still work" do
      sys = %{"FEEDBACK_A_TRON_MCP" => "true", "FEEDBACK_A_TRON_HTTP" => "1"}
      assert %{mcp_stdio: true, http: true} = Doors.config([], sys)
    end

    test "MCP_SERVER is the oldest spelling and still works" do
      assert %{mcp_stdio: true} = Doors.config([], %{"MCP_SERVER" => "1"})
    end

    test "the first present name decides: a new-name 0 beats a legacy 1" do
      sys = %{"FEEDBACK_O_TRON_MCP" => "0", "FEEDBACK_A_TRON_MCP" => "1"}
      assert %{mcp_stdio: false} = Doors.config([], sys)
    end

    test "values are trimmed and case-insensitive" do
      assert %{http: true} = Doors.config([], %{"FEEDBACK_O_TRON_HTTP" => " TRUE\n"})
      assert %{http: false} = Doors.config([], %{"FEEDBACK_O_TRON_HTTP" => "maybe"})
    end
  end

  describe "config/2 port and bind" do
    test "port and bind come from env" do
      sys = %{"FEEDBACK_O_TRON_HTTP_PORT" => "8123", "FEEDBACK_O_TRON_HTTP_BIND" => "0.0.0.0"}
      assert %{http_port: 8123, http_ip: {0, 0, 0, 0}} = Doors.config([], sys)
    end

    test "legacy port and bind names work" do
      sys = %{"FEEDBACK_A_TRON_HTTP_PORT" => "8124", "FEEDBACK_A_TRON_HTTP_BIND" => "::1"}
      assert %{http_port: 8124, http_ip: {0, 0, 0, 0, 0, 0, 0, 1}} = Doors.config([], sys)
    end

    test "a bad port or bind falls back to the default" do
      sys = %{"FEEDBACK_O_TRON_HTTP_PORT" => "seventy", "FEEDBACK_O_TRON_HTTP_BIND" => "nowhere"}
      assert %{http_port: 7722, http_ip: {127, 0, 0, 1}} = Doors.config([], sys)
      assert %{http_port: 7722} = Doors.config([], %{"FEEDBACK_O_TRON_HTTP_PORT" => "0"})
      assert %{http_port: 7722} = Doors.config([], %{"FEEDBACK_O_TRON_HTTP_PORT" => "70000"})
    end

    test "application env accepts an ip tuple" do
      assert %{http_ip: {0, 0, 0, 0}} = Doors.config([http_ip: {0, 0, 0, 0}], %{})
    end
  end

  describe "children/1" do
    test "no children when both doors are closed" do
      assert Doors.children(Doors.config([], %{})) == []
    end

    test "the MCP child is the stdio server named feedback-o-tron" do
      [{FeedbackATron.MCP.Server, opts}] = Doors.children(Doors.config([mcp_stdio: true], %{}))
      assert opts[:name] == "feedback-o-tron"
      assert is_binary(opts[:version])

      assert opts[:tools] == [
               FeedbackATron.MCP.Tools.SubmitFeedback,
               FeedbackATron.MCP.Tools.ResearchFeedback,
               FeedbackATron.MCP.Tools.SynthesizeFeedback
             ]
    end

    test "the HTTP child is Bandit on the configured ip and port" do
      {:ok, probe} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      {:ok, port} = :inet.port(probe)
      :ok = :gen_tcp.close(probe)

      config = Doors.config([http: true, http_port: port, http_ip: {127, 0, 0, 1}], %{})
      [{Bandit, opts}] = Doors.children(config)
      assert opts[:plug] == FeedbackATron.HTTPIntake.Router
      assert opts[:scheme] == :http
      assert opts[:ip] == {127, 0, 0, 1}
      assert opts[:port] == port
    end

    test "the HTTP child is skipped while another socket owns the port" do
      {:ok, holder} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, reuseaddr: true)
      {:ok, port} = :inet.port(holder)
      config = Doors.config([http: true, http_port: port, http_ip: {127, 0, 0, 1}], %{})

      assert Doors.children(config) == []

      :ok = :gen_tcp.close(holder)
      assert [{Bandit, _}] = Doors.children(config)
    end
  end
end

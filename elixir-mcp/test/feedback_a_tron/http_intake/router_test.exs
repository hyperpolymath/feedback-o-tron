# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.HTTPIntake.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias FeedbackATron.HTTPIntake.Router

  @opts Router.init([])

  defp json_post(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  test "GET /health returns ok" do
    conn = conn(:get, "/health") |> Router.call(@opts)
    assert conn.status == 200
    assert %{"status" => "ok"} = Jason.decode!(conn.resp_body)
  end

  test "POST /api/v1/submit_feedback rejects missing required fields" do
    conn = json_post("/api/v1/submit_feedback", %{title: "t", body: "b"})
    assert conn.status == 400
    body = Jason.decode!(conn.resp_body)
    assert body["error"] == "missing_required_fields"
    assert "repo" in body["fields"]
  end

  test "POST /api/v1/submit_feedback treats blank strings as missing" do
    conn = json_post("/api/v1/submit_feedback", %{title: "  ", body: "b", repo: "o/r"})
    assert conn.status == 400
    body = Jason.decode!(conn.resp_body)
    assert "title" in body["fields"]
  end

  test "unknown route returns 404 json" do
    conn = conn(:get, "/nope") |> Router.call(@opts)
    assert conn.status == 404
    assert %{"error" => "not_found"} = Jason.decode!(conn.resp_body)
  end

  test "unknown POST route returns 404 json" do
    conn = json_post("/api/v1/nope", %{})
    assert conn.status == 404
    assert %{"error" => "not_found"} = Jason.decode!(conn.resp_body)
  end

  describe "POST /api/v1/research_feedback" do
    test "rejects missing required fields" do
      conn = json_post("/api/v1/research_feedback", %{title: "t"})
      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "missing_required_fields"
      assert "repo" in body["fields"]
    end

    test "treats blank strings as missing" do
      conn = json_post("/api/v1/research_feedback", %{repo: "o/r", title: "   "})
      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert "title" in body["fields"]
    end
  end

  describe "POST /api/v1/synthesize_feedback" do
    test "rejects missing required fields" do
      conn = json_post("/api/v1/synthesize_feedback", %{repo: "o/r"})
      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "missing_required_fields"
      assert "raw_feedback" in body["fields"]
    end

    test "zero-signal abuse is rejected with a stated reason, never filed" do
      # Doctrine: the gate is usefulness, not tone. A hostile string with no
      # actionable signal must come back rejected — with the reason stated —
      # rather than being shaped into a report or silently dropped.
      conn =
        json_post("/api/v1/synthesize_feedback", %{
          raw_feedback: "you idiots, this garbage is trash and you all suck",
          repo: "owner/repo"
        })

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["rejected"] == true
      assert is_binary(body["reason"])
      assert body["reason"] != ""
    end
  end
end

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
end

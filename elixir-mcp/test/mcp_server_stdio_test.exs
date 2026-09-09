# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.MCP.ServerStdioTest do
  use ExUnit.Case, async: false

  alias FeedbackATron.MCP.Server

  @initialize ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}})
  @tools_list ~s({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})

  test "answers initialize and tools/list on the injected devices, then reports EOF" do
    parent = self()
    {:ok, input} = StringIO.open(@initialize <> "\n" <> @tools_list <> "\n")
    {:ok, output} = StringIO.open("")

    {:ok, pid} =
      Server.start_link(
        name: "feedback-o-tron",
        version: "1.0.0",
        tools: [FeedbackATron.MCP.Tools.SubmitFeedback],
        stdio_in: input,
        stdio_out: output,
        on_eof: fn -> send(parent, :eof_seen) end
      )

    assert_receive :eof_seen, 2_000

    {"", written} = StringIO.contents(output)

    [first, second] =
      written
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert first["id"] == 1
    assert first["result"]["protocolVersion"] == "2024-11-05"
    assert first["result"]["serverInfo"]["name"] == "feedback-o-tron"

    assert second["id"] == 2
    assert Enum.map(second["result"]["tools"], & &1["name"]) == ["submit_feedback"]

    GenServer.stop(pid)
  end
end

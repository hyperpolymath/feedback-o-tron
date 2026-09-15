# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.MCP.ServerStdioTest do
  use ExUnit.Case, async: false

  alias FeedbackATron.MCP.Server

  @initialize ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}})
  @tools_list ~s({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})

  # A JSON `true` from a client is not a person typing y at a terminal.
  @consent_call ~s({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"submit_feedback","arguments":{"title":"[boundary] client-asserted consent","body":"boundary body","repo":"o/r","consent":true,"dry_run":false,"skip_dedupe":true}}})

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

  describe "the MCP door cannot assert a person's consent" do
    setup do
      FeedbackATron.RateLimiter.reset(:github)
      :ok
    end

    test ~s(a client sending "consent": true does not send) do
      parent = self()
      {:ok, input} = StringIO.open(@initialize <> "\n" <> @consent_call <> "\n")
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

      assert_receive :eof_seen, 30_000

      {"", written} = StringIO.contents(output)

      [_init, call] =
        written
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert call["id"] == 3
      text = call["result"]["content"] |> hd() |> Map.fetch!("text")

      # The door drafted the report and said so in words a person can read.
      assert text =~ "drafted_needs_human_consent"
      assert text =~ "feedback-o-tron submit"

      # Nothing was filed, and the summary counts it honestly.
      refute text =~ ~s("status":"success")
      assert text =~ "Submitted: 0"
      assert text =~ "Errors: 0"
      assert text =~ "Needs consent: 1"

      GenServer.stop(pid)
    end
  end
end

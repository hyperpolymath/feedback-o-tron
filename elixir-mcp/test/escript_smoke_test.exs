# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.EscriptSmokeTest do
  @moduledoc """
  End-to-end tests of the built binary. Tagged :escript and excluded by
  default; run with `mix escript.build && mix test --only escript`.
  """
  use ExUnit.Case, async: false

  @moduletag :escript
  @moduletag timeout: 60_000

  @bin Path.expand("../feedback-o-tron", __DIR__)

  @initialize ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}})

  setup_all do
    unless File.exists?(@bin) do
      flunk("#{@bin} is missing; run `mix escript.build` first")
    end

    :ok
  end

  test "--version prints the canonical version" do
    assert {"feedback-o-tron v1.0.0\n", 0} = System.cmd(@bin, ["--version"])
  end

  test "--help names serve and never the old spelling" do
    {out, 0} = System.cmd(@bin, ["--help"])
    assert out =~ "feedback-o-tron serve"
    refute out =~ "a-tron"
  end

  test "submit --dry-run sends nothing and exits 0" do
    args = ["submit", "--repo", "o/r", "--title", "T", "--body", "B", "--dry-run"]
    {out, 0} = System.cmd(@bin, args, stderr_to_stdout: true)
    assert out =~ "[DRY RUN] github: Would submit"
  end

  test "a real submit without a terminal is refused with exit 3" do
    args = ["submit", "--repo", "o/r", "--title", "T", "--body", "B"]
    {out, 3} = System.cmd(@bin, args, stderr_to_stdout: true)
    assert out =~ "Title:        T"
    assert out =~ "not a terminal"
  end

  test "serve answers initialize on stdout, nothing else, and exits 0 at EOF" do
    err = Path.join(System.tmp_dir!(), "fot-smoke-#{System.unique_integer([:positive])}.err")

    script =
      "printf '%s\\n' '" <>
        @initialize <> "' | '" <> @bin <> "' serve --no-http 2>'" <> err <> "'"

    {out, 0} = System.cmd("sh", ["-c", script])
    File.rm(err)

    [line] = String.split(out, "\n", trim: true)

    assert %{"id" => 1, "result" => %{"serverInfo" => %{"name" => "feedback-o-tron"}}} =
             Jason.decode!(line)
  end

  test "serve opens the HTTP intake and closes it when stdin closes" do
    {:ok, probe} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(probe)
    :ok = :gen_tcp.close(probe)

    child =
      Port.open({:spawn_executable, @bin}, [
        :binary,
        :exit_status,
        args: ["serve", "--http-port", Integer.to_string(port)]
      ])

    health = "http://127.0.0.1:#{port}/health"

    assert wait_until(40, 250, fn ->
             match?(
               {:ok, %{status: 200, body: %{"status" => "ok", "service" => "feedback-o-tron"}}},
               Req.get(health, retry: false)
             )
           end),
           "HTTP intake never answered on #{health}"

    # Closing the port closes the child's stdin; the MCP loop sees EOF and
    # stops the VM, which is how an MCP host ends its server.
    Port.close(child)

    assert wait_until(40, 250, fn -> match?({:error, _}, Req.get(health, retry: false)) end),
           "HTTP intake still answering after stdin closed"
  end

  defp wait_until(0, _sleep_ms, _fun), do: false

  defp wait_until(tries, sleep_ms, fun) do
    if fun.() do
      true
    else
      Process.sleep(sleep_ms)
      wait_until(tries - 1, sleep_ms, fun)
    end
  end
end

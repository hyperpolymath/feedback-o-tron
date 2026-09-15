# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Doors do
  @moduledoc """
  Decides which doors the engine opens, and builds their child specs.

  The engine, the contract and the policy are one thing; the MCP stdio
  server and the HTTP intake are doors onto it. `config/2` is pure: it takes
  the `:doors` application env and the OS environment as a map, so it is
  unit-tested without touching either. Application env beats OS env; OS env
  beats the defaults; both doors are closed by default.

  OS env names are read new spelling first, legacy second; the first name
  that is *present* decides.
  """

  require Logger

  @default_port 7722
  @default_ip {127, 0, 0, 1}

  @mcp_names ["FEEDBACK_O_TRON_MCP", "FEEDBACK_A_TRON_MCP", "MCP_SERVER"]
  @http_names ["FEEDBACK_O_TRON_HTTP", "FEEDBACK_A_TRON_HTTP"]
  @port_names ["FEEDBACK_O_TRON_HTTP_PORT", "FEEDBACK_A_TRON_HTTP_PORT"]
  @bind_names ["FEEDBACK_O_TRON_HTTP_BIND", "FEEDBACK_A_TRON_HTTP_BIND"]

  @tools [
    FeedbackATron.MCP.Tools.SubmitFeedback,
    FeedbackATron.MCP.Tools.ResearchFeedback,
    FeedbackATron.MCP.Tools.SynthesizeFeedback
  ]

  @type config :: %{
          mcp_stdio: boolean(),
          http: boolean(),
          http_port: 1..65535,
          http_ip: :inet.ip_address()
        }

  @spec config(keyword(), %{optional(String.t()) => String.t()}) :: config()
  def config(app_env, sys_env) when is_list(app_env) and is_map(sys_env) do
    %{
      mcp_stdio: pick(app_env, :mcp_stdio, on?(first_present(sys_env, @mcp_names))),
      http: pick(app_env, :http, on?(first_present(sys_env, @http_names))),
      http_port: pick(app_env, :http_port, parse_port(first_present(sys_env, @port_names))),
      http_ip: pick(app_env, :http_ip, parse_ip(first_present(sys_env, @bind_names)))
    }
  end

  @spec children(config()) :: [{module(), keyword()}]
  def children(%{} = config) do
    mcp_children(config) ++ http_children(config)
  end

  defp mcp_children(%{mcp_stdio: true}) do
    [
      {FeedbackATron.MCP.Server,
       name: "feedback-o-tron",
       version: Application.spec(:feedback_a_tron, :vsn) |> to_string(),
       tools: @tools}
    ]
  end

  defp mcp_children(_), do: []

  defp http_children(%{http: true, http_ip: ip, http_port: port}) do
    if port_free?(ip, port) do
      [{Bandit, plug: FeedbackATron.HTTPIntake.Router, scheme: :http, ip: ip, port: port}]
    else
      Logger.warning(
        "HTTP intake not started: #{:inet.ntoa(ip)}:#{port} is already in use; " <>
          "another feedback-o-tron serve may own it"
      )

      []
    end
  end

  defp http_children(_), do: []

  defp port_free?(ip, port) do
    case :gen_tcp.listen(port, ip: ip, reuseaddr: true) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp pick(app_env, key, fallback) do
    case Keyword.fetch(app_env, key) do
      {:ok, value} -> value
      :error -> fallback
    end
  end

  defp first_present(sys_env, names) do
    Enum.find_value(names, fn name -> Map.get(sys_env, name) end)
  end

  defp on?(nil), do: false

  defp on?(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["1", "true", "yes", "on"]
  end

  defp parse_port(nil), do: @default_port

  defp parse_port(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port in 1..65535 -> port
      _ -> @default_port
    end
  end

  defp parse_ip(nil), do: @default_ip

  defp parse_ip(value) do
    case :inet.parse_address(String.to_charlist(String.trim(value))) do
      {:ok, ip} -> ip
      {:error, _} -> @default_ip
    end
  end
end

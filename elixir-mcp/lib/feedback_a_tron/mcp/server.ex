defmodule FeedbackATron.MCP.Server do
  @moduledoc """
  MCP server with stdio and optional TCP transports.

  TCP is disabled by default; enable with FEEDBACK_A_TRON_MCP_TCP=1.
  """

  use GenServer
  require Logger

  alias ElixirMcpServer.Protocol

  defstruct [:name, :version, :tools, :resources, :capabilities, :stdio?, :tcp]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    version = Keyword.fetch!(opts, :version)
    tools = Keyword.get(opts, :tools, [])
    resources = Keyword.get(opts, :resources, [])

    state = %__MODULE__{
      name: name,
      version: version,
      tools: build_tool_map(tools),
      resources: build_resource_map(resources),
      capabilities: %{
        tools: %{},
        resources: %{}
      },
      stdio?: Keyword.get(opts, :stdio, true),
      tcp: tcp_config(opts)
    }

    {:ok, state, {:continue, :start_transports}}
  end

  @impl true
  def handle_continue(:start_transports, state) do
    if state.stdio? do
      spawn_link(fn -> stdio_loop(state) end)
    end

    start_tcp_listeners(state)
    {:noreply, state}
  end

  defp build_tool_map(tool_modules) do
    Enum.into(tool_modules, %{}, fn mod -> {mod.name(), mod} end)
  end

  defp build_resource_map(resource_modules) do
    Enum.into(resource_modules, %{}, fn mod -> {mod.uri(), mod} end)
  end

  defp stdio_loop(state) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, reason} ->
        Logger.error("stdio read error: #{inspect(reason)}")

      line ->
        handle_message(String.trim(line), state, &IO.puts/1)
        stdio_loop(state)
    end
  end

  defp tcp_config(opts) do
    env_enabled = System.get_env("FEEDBACK_A_TRON_MCP_TCP")
    enabled = env_on?(env_enabled) || Keyword.get(opts, :tcp, false)

    env_port = System.get_env("FEEDBACK_A_TRON_MCP_TCP_PORT")
    port = parse_int(env_port) || Keyword.get(opts, :tcp_port, 7979)

    env_bind = System.get_env("FEEDBACK_A_TRON_MCP_TCP_BIND")
    binds =
      case env_bind do
        nil -> Keyword.get(opts, :tcp_bind, ["127.0.0.1"])
        value -> split_list(value)
      end

    binds = normalize_binds(binds)

    %{enabled: enabled, port: port, binds: binds}
  end

  defp env_on?(nil), do: false

  defp env_on?(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&Enum.member?(["1", "true", "yes", "on"], &1))
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp split_list(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_binds(binds) do
    cond do
      Enum.member?(binds, "0.0.0.0") ->
        if length(binds) > 1 do
          Logger.warn("MCP TCP bind includes 0.0.0.0; ignoring other bind addresses")
        end

        ["0.0.0.0"]

      Enum.member?(binds, "::") ->
        if length(binds) > 1 do
          Logger.warn("MCP TCP bind includes ::; ignoring other bind addresses")
        end

        ["::"]

      true ->
        binds
    end
  end

  defp start_tcp_listeners(%__MODULE__{tcp: %{enabled: false}}), do: :ok

  defp start_tcp_listeners(%__MODULE__{tcp: %{enabled: true, port: port, binds: binds}} = state) do
    Enum.each(binds, fn bind ->
      case parse_ip(bind) do
        {:ok, ip} ->
          case :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true, ip: ip]) do
            {:ok, listen_socket} ->
              Logger.info("MCP TCP listening on #{bind}:#{port}")
              spawn_link(fn -> accept_loop(listen_socket, state) end)

            {:error, reason} ->
              Logger.error("MCP TCP listen failed for #{bind}:#{port}: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.error("Invalid MCP TCP bind address #{bind}: #{inspect(reason)}")
      end
    end)
  end

  defp parse_ip(bind) do
    case :inet.parse_address(String.to_charlist(bind)) do
      {:ok, ip} -> {:ok, ip}
      {:error, reason} -> {:error, reason}
    end
  end

  defp accept_loop(listen_socket, state) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        spawn_link(fn -> socket_loop(socket, state) end)
        accept_loop(listen_socket, state)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.error("MCP TCP accept failed: #{inspect(reason)}")
    end
  end

  defp socket_loop(socket, state) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        message = String.trim_trailing(line)
        handle_message(message, state, fn response -> send_tcp(socket, response) end)
        socket_loop(socket, state)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.error("MCP TCP recv failed: #{inspect(reason)}")
    end
  end

  defp send_tcp(socket, response) do
    :gen_tcp.send(socket, response <> "\n")
  end

  defp handle_message(line, state, send_fun) do
    case Protocol.decode(line) do
      {:ok, %{"method" => "initialize", "id" => id}} ->
        response =
          Protocol.encode_response(%{
            "protocolVersion" => "2024-11-05",
            "serverInfo" => %{
              "name" => state.name,
              "version" => state.version
            },
            "capabilities" => state.capabilities
          }, id)

        send_fun.(response)

      {:ok, %{"method" => "tools/list", "id" => id}} ->
        tools =
          Enum.map(state.tools, fn {_name, mod} ->
            %{
              "name" => mod.name(),
              "description" => mod.description(),
              "inputSchema" => mod.input_schema()
            }
          end)

        response = Protocol.encode_response(%{"tools" => tools}, id)
        send_fun.(response)

      {:ok,
       %{
         "method" => "tools/call",
         "params" => %{"name" => tool_name, "arguments" => args},
         "id" => id
       }} ->
        case Map.get(state.tools, tool_name) do
          nil ->
            error = Protocol.encode_error(-32601, "Tool not found", id)
            send_fun.(error)

          tool_mod ->
            case tool_mod.execute(args, %{}) do
              {:ok, content} ->
                response = Protocol.encode_response(%{"content" => content}, id)
                send_fun.(response)

              {:error, reason} ->
                error = Protocol.encode_error(-32000, "Tool execution failed", id, reason)
                send_fun.(error)
            end
        end

      {:ok, _msg} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to decode message: #{inspect(reason)}")
    end
  end
end

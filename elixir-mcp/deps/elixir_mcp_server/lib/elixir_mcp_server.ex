defmodule ElixirMcpServer do
  @moduledoc """
  Model Context Protocol (MCP) server framework for Elixir.

  ElixirMcpServer provides a complete implementation of the MCP protocol,
  allowing you to build MCP servers that can be integrated with Claude Code
  and other MCP clients.

  ## Features

  - Complete JSON-RPC 2.0 implementation
  - stdio transport (standard for MCP)
  - Tool registration and execution
  - Resource registration and serving
  - Prompt templates support
  - Server capabilities negotiation

  ## Quick Start

      # Define a tool
      defmodule MyApp.Tools.Echo do
        use ElixirMcpServer.Tool

        @impl true
        def name, do: "echo"

        @impl true
        def description, do: "Echoes back the input message"

        @impl true
        def input_schema do
          %{
            type: "object",
            properties: %{
              message: %{type: "string", description: "Message to echo"}
            },
            required: ["message"]
          }
        end

        @impl true
        def execute(%{"message" => msg}, _context) do
          {:ok, [%{type: "text", text: "Echo: \#{msg}"}]}
        end
      end

      # Start the server
      ElixirMcpServer.start_link(
        name: "my-app",
        version: "1.0.0",
        tools: [MyApp.Tools.Echo]
      )

  ## Architecture

  The framework consists of several key components:

  - `ElixirMcpServer.Server` - Main GenServer handling protocol state
  - `ElixirMcpServer.Protocol` - JSON-RPC 2.0 message handling
  - `ElixirMcpServer.Transport.Stdio` - stdio transport implementation
  - `ElixirMcpServer.Tool` - Behavior for defining tools
  - `ElixirMcpServer.Resource` - Behavior for defining resources
  """

  alias ElixirMcpServer.Server

  @doc """
  Starts an MCP server with the given options.

  ## Options

  - `:name` - Server name (required)
  - `:version` - Server version (required)
  - `:tools` - List of tool modules (default: [])
  - `:resources` - List of resource modules (default: [])
  - `:prompts` - List of prompt modules (default: [])
  - `:transport` - Transport module (default: ElixirMcpServer.Transport.Stdio)

  ## Examples

      ElixirMcpServer.start_link(
        name: "my-server",
        version: "1.0.0",
        tools: [MyTool1, MyTool2],
        resources: [MyResource1]
      )
  """
  def start_link(opts) do
    Server.start_link(opts)
  end

  @doc """
  Registers a tool module with the server.

  ## Examples

      ElixirMcpServer.register_tool(MyApp.Tools.Echo)
  """
  defdelegate register_tool(tool_module), to: Server

  @doc """
  Registers a resource module with the server.

  ## Examples

      ElixirMcpServer.register_resource(MyApp.Resources.Config)
  """
  defdelegate register_resource(resource_module), to: Server

  @doc """
  Stops the server gracefully.
  """
  defdelegate stop(), to: Server
end

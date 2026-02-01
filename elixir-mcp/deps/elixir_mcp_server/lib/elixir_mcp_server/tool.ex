defmodule ElixirMcpServer.Tool do
  @moduledoc """
  Behavior for defining MCP tools.

  Tools are executable functions that can be called by the MCP client (e.g., Claude Code).
  Each tool must implement this behavior to define its name, description, input schema,
  and execution logic.

  ## Example

      defmodule MyApp.Tools.GetWeather do
        use ElixirMcpServer.Tool

        @impl true
        def name, do: "get_weather"

        @impl true
        def description, do: "Get current weather for a location"

        @impl true
        def input_schema do
          %{
            type: "object",
            properties: %{
              location: %{
                type: "string",
                description: "City name or zip code"
              },
              units: %{
                type: "string",
                enum: ["celsius", "fahrenheit"],
                description: "Temperature units"
              }
            },
            required: ["location"]
          }
        end

        @impl true
        def execute(%{"location" => location} = args, _context) do
          units = Map.get(args, "units", "celsius")
          # Fetch weather data...
          {:ok, [
            %{
              type: "text",
              text: "Weather in \#{location}: 20°\#{if units == "celsius", do: "C", else: "F"}"
            }
          ]}
        end
      end
  """

  @doc """
  Returns the tool name. Must be unique within the server.
  """
  @callback name() :: String.t()

  @doc """
  Returns a human-readable description of what the tool does.
  """
  @callback description() :: String.t()

  @doc """
  Returns the JSON Schema for the tool's input parameters.

  Must be a valid JSON Schema object defining the expected input structure.
  """
  @callback input_schema() :: map()

  @doc """
  Executes the tool with the given arguments and context.

  ## Arguments

  - `args` - Map of input arguments matching the input_schema
  - `context` - Execution context (reserved for future use)

  ## Returns

  - `{:ok, content}` - Success with content list
  - `{:error, reason}` - Failure with error reason

  Content is a list of content blocks, where each block is a map with:
  - `type` - "text", "image", or "resource"
  - Additional fields depending on type
  """
  @callback execute(args :: map(), context :: map()) ::
              {:ok, [map()]} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour ElixirMcpServer.Tool
    end
  end
end

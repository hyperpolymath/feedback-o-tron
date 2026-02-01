defmodule ElixirMcpServer.Protocol do
  @moduledoc """
  JSON-RPC 2.0 protocol implementation for MCP.
  """

  @jsonrpc_version "2.0"

  @doc """
  Encodes a JSON-RPC request.
  """
  def encode_request(method, params, id) do
    %{
      "jsonrpc" => @jsonrpc_version,
      "method" => method,
      "params" => params,
      "id" => id
    }
    |> Jason.encode!()
  end

  @doc """
  Encodes a JSON-RPC response.
  """
  def encode_response(result, id) do
    %{
      "jsonrpc" => @jsonrpc_version,
      "result" => result,
      "id" => id
    }
    |> Jason.encode!()
  end

  @doc """
  Encodes a JSON-RPC error response.
  """
  def encode_error(code, message, id, data \\ nil) do
    error = %{
      "code" => code,
      "message" => message
    }

    error = if data, do: Map.put(error, "data", data), else: error

    %{
      "jsonrpc" => @jsonrpc_version,
      "error" => error,
      "id" => id
    }
    |> Jason.encode!()
  end

  @doc """
  Decodes a JSON-RPC message.
  """
  def decode(json) do
    case Jason.decode(json) do
      {:ok, %{"jsonrpc" => "2.0"} = msg} -> {:ok, msg}
      {:ok, _} -> {:error, :invalid_jsonrpc_version}
      {:error, _} = error -> error
    end
  end
end

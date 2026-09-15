# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.LoggerConfigTest do
  use ExUnit.Case, async: true

  @moduledoc """
  stdout is the MCP JSON-RPC wire; every log line must go to stderr.
  """

  test "the default logger handler writes to standard_error" do
    {:ok, %{config: config}} = :logger.get_handler_config(:default)
    assert config.type == :standard_error
  end
end

# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
import Config

# stdout is the MCP JSON-RPC wire when `feedback-o-tron serve` runs under a
# host; every log line goes to stderr so the wire stays clean.
config :logger, :default_handler, config: [type: :standard_error]

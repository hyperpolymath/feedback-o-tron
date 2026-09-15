#!/usr/bin/env bash
set -euo pipefail

host=${MCP_HOST:-127.0.0.1}
port=${MCP_PORT:-7979}
payload=${MCP_PAYLOAD:-"${TMPDIR:-/tmp}/fot-mcp-smoke.json"}

command -v nc >/dev/null 2>&1 || {
    echo "mcp_tcp_smoke_test: nc not found; install netcat" >&2
    exit 2
}

cat <<'JSON' >"$payload"
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","id":"tools","method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":"call","method":"tools/call","params":{"name":"submit_feedback","arguments":{"title":"MCP TCP smoke test","body":"Automated dry run via TCP.","repo":"hyperpolymath/feedback-o-tron","platforms":["github"]}}}
JSON

# Line-delimited JSON-RPC over TCP
nc "$host" "$port" < "$payload"

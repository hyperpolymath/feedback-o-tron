;; SPDX-License-Identifier: PMPL-1.0-or-later
;; PLAYBOOK.scm - Operational runbook

(define playbook
  `((version . "1.0.1")
    (updated . "2026-01-27")
    (procedures
      ((build . ("cd elixir-mcp" "mix deps.get"))
       (test . ("MCP_PORT=844 elixir-mcp/scripts/mcp_tcp_smoke_test.sh"))
       (deploy . ("systemctl --user restart feedback-mcp.service" "sudo systemctl restart feedback-mcp.service"))
       (mcp-tcp-smoke-test . ("MCP_PORT=844 elixir-mcp/scripts/mcp_tcp_smoke_test.sh"))))
    (alerts . ())
    (contacts . ())))

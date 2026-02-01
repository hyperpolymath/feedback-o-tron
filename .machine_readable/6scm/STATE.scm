;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state

(state
  (metadata
    (version "0.1.1")
    (schema-version "1.0")
    (created "2025-01-03")
    (updated "2026-01-27")
    (project "feedback-o-tron")
    (repo "hyperpolymath/feedback-o-tron"))
  (project-context
    (name "feedback-o-tron")
    (tagline "Hyperpolymath project"))
  (current-position
    (phase "alpha")
    (overall-completion 25)
    (where-we-are "MCP server supports optional TCP adapter; smoke test script added; systemd unit drafted for port 844.")
    (where-next "Run TCP smoke test on port 844, confirm service wiring, then decide on port/bind and TLS/SSH exposure."))
  (critical-next-actions
    (immediate
      ("Run: MCP_PORT=844 elixir-mcp/scripts/mcp_tcp_smoke_test.sh"
       "Confirm systemd service on 844 or move to unprivileged port"
       "Decide on exposure/TLS vs SSH tunneling"))))

;; SPDX-License-Identifier: PMPL-1.0-or-later
;; AGENTIC.scm - AI agent config

(define agentic-config
  `((version . "1.0.1")
    (updated . "2026-01-27")
    (claude-code
      ((model . "claude-opus-4-5-20251101")
       (tools . ("read" "edit" "bash" "grep" "glob"))
       (permissions . "read-all")))
    (patterns
      ((code-review . "thorough")
       (refactoring . "conservative")))
    (constraints
      ((banned . ("typescript" "go" "python" "makefile"))))
    (notes
      ("MCP TCP adapter available; smoke test script at elixir-mcp/scripts/mcp_tcp_smoke_test.sh."))))

;; SPDX-License-Identifier: PMPL-1.0-or-later
;; META.scm - Project metadata

(define project-meta
  `((version . "1.0.1")
    (updated . "2026-01-27")
    (architecture-decisions
      ("Added MCP TCP adapter (line-delimited JSON-RPC) and smoke test script."))
    (development-practices
      ((code-style . "standard")
       (security . "openssf-scorecard")
       (versioning . "semver")
       (documentation . "asciidoc")
       (branching . "trunk-based")))
    (design-rationale . ())))

(define opsm-link "OPSM link: feedback/telemetry capture for OPSM (opt-in).")

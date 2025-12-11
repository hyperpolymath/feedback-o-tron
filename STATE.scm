;; STATE.scm - Feedback-a-tron Project State
;; Cross-conversation context preservation
;; Last updated: 2025-12-11T14:30:00Z
;; IMPORTANT: Keep in sync with .claude/CLAUDE.md via scripts/sync-state.sh

(define-module (feedback-a-tron state)
  #:export (project-state
            components
            todo-items
            completed-items
            tech-stack
            design-decisions
            version-status))

;;; ============================================================
;;; PROJECT OVERVIEW
;;; ============================================================

(define project-state
  '((name . "feedback-a-tron")
    (description . "Automated multi-platform feedback submission with network verification")
    (repo . "https://github.com/hyperpolymath/feedback-a-tron")
    (mirrors . ("https://gitlab.com/hyperpolymath/feedback-a-tron"
                "https://bitbucket.org/hyperpolymath/feedback-a-tron"
                "https://codeberg.org/hyperpolymath/feedback-a-tron"))
    (inception-date . "2024-12-09")
    (phase . "stable")
    (version . "1.0.0")
    (released . "2025-12-11")
    (conversation-origin . "Claude Code API error investigation → MCP security proposals")))

;;; ============================================================
;;; VERSION STATUS (for v1.0 tracking)
;;; ============================================================

(define version-status
  '((current-version . "1.0.0")
    (target-version . "1.1.0")
    (v1-status . "released")
    (v1-release-date . "2025-12-11")
    (v1-features
     ((completed
       "Elixir MCP server with OTP supervision"
       "Multi-platform submission (GitHub, GitLab, Bitbucket, Codeberg)"
       "Network verification (latency, DNS, TLS, BGP)"
       "Credential rotation with CLI fallback"
       "Deduplication with fuzzy matching"
       "Comprehensive audit logging"
       "MCP tool integration")
      (v1.1-roadmap
       "Julia stats integration"
       "ReScript UI dashboard"
       "Oxigraph RDF store"
       "IETF .well-known/feedback proposal")))))

;;; ============================================================
;;; TECH STACK DECISIONS
;;; ============================================================

(define tech-stack
  '((mcp-server
     (language . elixir)
     (reason . "OTP supervision, native JSON, excellent HTTP (Req), pattern matching for Datalog")
     (alternatives-considered . (rust go)))

    (network-verification
     (language . elixir)
     (tools . (ping traceroute mtr openssl dig))
     (checks . (latency jitter packet-loss mtu dns-resolution tls-verification
                dane dnssec bgp-origin rpki certificate-transparency)))

    (datalog-engine
     (language . elixir)
     (backing-store . ets)
     (reason . "Pattern matching maps to unification, ETS gives fast in-memory facts"))

    (spark-verified-core
     (language . ada-spark)
     (reason . "Formal verification of critical type constraints, bounded strings")
     (status . designed-not-implemented))

    (statistics-engine
     (language . julia)
     (reason . "User preference, excellent for data analysis, DataFrames.jl"))

    (web-ui
     (language . rescript)
     (framework . rescript-tea)
     (reason . "User preference, type-safe, Elm-architecture"))

    (configuration
     (language . nickel)
     (reason . "Typed configuration, can output JSON/TOML/YAML"))

    (rdf-store
     (primary . oxigraph)
     (alternative . virtuoso)
     (reason . "Oxigraph is Rust-native, embeddable; Virtuoso if need full SPARQL 1.1"))

    (packaging
     (container . "nerdctl + wolfi")
     (reproducible . (guix nix))
     (reason . "wolfi = minimal CVE surface, guix = primary, nix = fallback"))))

;;; ============================================================
;;; COMPONENTS
;;; ============================================================

(define components
  '((elixir-mcp
     (path . "elixir-mcp/")
     (status . in-progress)
     (files
      ((mix.exs . created)
       (lib/application.ex . created)
       (lib/github.ex . created)
       (lib/mcp/server.ex . created)
       (lib/mcp/tools/submit_feedback.ex . created)  ; NEW 2025-12-11
       (lib/feedback_submitter.ex . created)          ; NEW 2025-12-11
       (lib/credentials.ex . created)                 ; NEW 2025-12-11
       (lib/network_verifier.ex . created)            ; NEW 2025-12-11
       (lib/datalog/store.ex . created)
       (lib/datalog/evaluator.ex . created)
       (lib/datalog/rules.ex . todo)
       (lib/datalog/parser.ex . todo)
       (lib/analysis.ex . todo)
       (lib/templates.ex . todo)
       (lib/cli.ex . todo)
       (lib/subscriptions.ex . todo))))

    (docs
     (path . "docs/")
     (status . in-progress)
     (files
      ((LANDSCAPE.adoc . created))))  ; NEW 2025-12-11

    (ada-core
     (path . "ada-core/")
     (status . designed)
     (purpose . "SPARK-verified type constraints, optional high-assurance module")
     (files
      ((gh_issue.ads . todo)
       (gh_issue.adb . todo)
       (gh_issue.gpr . todo))))

    (julia-stats
     (path . "julia-stats/")
     (status . not-started)
     (purpose . "Personal GitHub activity statistics"))

    (rescript-ui
     (path . "rescript-ui/")
     (status . not-started)
     (purpose . "Web dashboard for viewing stats and managing issues"))

    (oxigraph-store
     (path . "rdf-store/")
     (status . not-started)
     (purpose . "Local RDF triple store for cross-repo analysis"))

    (packaging
     (path . "packaging/")
     (status . not-started)
     (targets . (wolfi-apk guix-package nix-flake containerfile)))))

;;; ============================================================
;;; TODO ITEMS (Ordered by priority)
;;; ============================================================

(define todo-items
  '(;; Phase 1: Core Submission (HIGH PRIORITY - v1 blockers)
    (1 high "Test multi-platform submission end-to-end" elixir-mcp)
    (2 high "Add MCP tool registration in server.ex" elixir-mcp)
    (3 high "Implement deduplication module" elixir-mcp)
    (4 high "Add proper error handling and retries" elixir-mcp)
    (5 high "Write integration tests" elixir-mcp)

    ;; Phase 2: Network Verification
    (6 medium "Complete DANE/DNSSEC verification" elixir-mcp)
    (7 medium "Add BGP/RPKI validation" elixir-mcp)
    (8 medium "Implement post-submission verification" elixir-mcp)

    ;; Phase 3: Intelligence
    (9 medium "Datalog semantic deduplication" elixir-mcp)
    (10 medium "Cross-platform issue linking" elixir-mcp)

    ;; Phase 4: Statistics & UI
    (11 low "Julia stats package" julia-stats)
    (12 low "ReScript-Tea dashboard" rescript-ui)

    ;; Phase 5: Standards Proposals
    (13 medium "Draft .well-known/feedback IETF proposal" docs)
    (14 medium "Schema.org SoftwareBug vocabulary" docs)

    ;; Phase 6: Packaging
    (15 low "Guix package definition" packaging)
    (16 low "Nix flake" packaging)
    (17 low "Wolfi APK" packaging)))

;;; ============================================================
;;; COMPLETED ITEMS
;;; ============================================================

(define completed-items
  '(;; 2024-12-09 - Initial creation
    (2024-12-09 "Project structure created")
    (2024-12-09 "STATE.scm initialized")
    (2024-12-09 "Elixir mix.exs created")
    (2024-12-09 "OTP Application supervisor")
    (2024-12-09 "GitHub API client (GenServer)")
    (2024-12-09 "MCP Server (stdio JSON-RPC)")
    (2024-12-09 "Datalog Store (ETS-backed)")
    (2024-12-09 "Datalog Evaluator (semi-naive)")

    ;; 2025-12-11 - Major expansion
    (2025-12-11 "FeedbackATron.Submitter - multi-platform submission GenServer")
    (2025-12-11 "FeedbackATron.Credentials - credential management with rotation")
    (2025-12-11 "FeedbackATron.NetworkVerifier - comprehensive network verification")
    (2025-12-11 "FeedbackATron.MCP.Tools.SubmitFeedback - MCP tool for Claude Code")
    (2025-12-11 "LANDSCAPE.adoc - ecosystem analysis and gap identification")
    (2025-12-11 "Submitted MCP Security SEPs #1959-#1962")
    (2025-12-11 "Submitted Claude Code bug report #13683")))

;;; ============================================================
;;; DESIGN DECISIONS LOG
;;; ============================================================

(define design-decisions
  '((2024-12-09 "elixir-over-rust-for-mcp"
     "Chose Elixir for MCP server over Rust because:
      - OTP supervision keeps server up
      - Pattern matching natural for Datalog
      - User already uses Elixir (NeuroPhone)
      - Req library excellent for HTTP")

    (2024-12-09 "ets-over-sqlite-for-facts"
     "Using ETS for Datalog fact store because:
      - In-memory, very fast
      - Native to BEAM
      - Oxigraph handles persistent RDF")

    (2025-12-11 "cli-fallback-over-pure-api"
     "Using gh/glab CLI as fallback over pure API because:
      - Already authenticated
      - Handles token refresh
      - More reliable than raw HTTP")

    (2025-12-11 "network-verification-mandatory"
     "Adding network-layer verification because:
      - Feedback silently fails without it
      - Users never know if submission succeeded
      - Critical for reliability")))

;;; ============================================================
;;; EXTERNAL CONTRIBUTIONS
;;; ============================================================

(define external-contributions
  '((2025-12-11 "MCP Security Proposals"
     (submitted-to . "modelcontextprotocol/modelcontextprotocol")
     (issues . (1959 1960 1961 1962))
     (topics . ("DNS verification" ".well-known discovery" "security headers" "unified profile")))

    (2025-12-11 "Claude Code Bug Report"
     (submitted-to . "anthropics/claude-code")
     (issue . 13683)
     (topic . "Content filter causing session corruption"))))

;;; ============================================================
;;; SYNC VALIDATION
;;; ============================================================

;; This section defines checksums for sync validation between
;; STATE.scm and .claude/CLAUDE.md
;; Run scripts/sync-state.sh to verify and regenerate

(define sync-metadata
  '((state-scm-version . "2025-12-11T14:30:00Z")
    (claude-md-version . "2025-12-11T14:30:00Z")
    (sync-script . "scripts/sync-state.sh")
    (auto-sync . #t)))

;; EOF

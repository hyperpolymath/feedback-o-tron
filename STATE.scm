;; STATE.scm - Feedback-a-tron Project State
;; Cross-conversation context preservation
;; Last updated: 2024-12-09T12:00:00Z

(define-module (feedback-a-tron state)
  #:export (project-state
            components
            todo-items
            completed-items
            tech-stack
            design-decisions))

;;; ============================================================
;;; PROJECT OVERVIEW
;;; ============================================================

(define project-state
  '((name . "feedback-a-tron")
    (description . "Comprehensive GitHub repository management, analysis, and feedback system")
    (repo . "https://github.com/hyperpolymath/feedback-a-tron")
    (inception-date . "2024-12-09")
    (phase . "initial-implementation")
    (conversation-origin . "Claude Code web UI archive bug investigation")))

;;; ============================================================
;;; TECH STACK DECISIONS
;;; ============================================================

(define tech-stack
  '((mcp-server
     (language . elixir)
     (reason . "OTP supervision, native JSON, excellent HTTP (Req), pattern matching for Datalog")
     (alternatives-considered . (rust go)))
    
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
       (lib/datalog/store.ex . created)
       (lib/datalog/evaluator.ex . created)
       (lib/datalog/rules.ex . todo)
       (lib/datalog/parser.ex . todo)
       (lib/analysis.ex . todo)
       (lib/templates.ex . todo)
       (lib/cli.ex . todo)
       (lib/subscriptions.ex . todo))))
    
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
     (purpose . "Personal GitHub activity statistics")
     (features
      (bug-submit-tracking
       response-time-analysis
       contribution-patterns
       watch-activity
       pr-review-stats)))
    
    (rescript-ui
     (path . "rescript-ui/")
     (status . not-started)
     (purpose . "Web dashboard for viewing stats and managing issues")
     (framework . rescript-tea))
    
    (oxigraph-store
     (path . "rdf-store/")
     (status . not-started)
     (purpose . "Local RDF triple store for cross-repo analysis")
     (queries . sparql-1.1))
    
    (repo-scraper
     (path . "scripts/scraper/")
     (status . not-started)
     (purpose . "Bulk scrape multiple repos into fact store"))
    
    (config
     (path . "config/")
     (status . not-started)
     (files
      ((main.ncl . todo)
       (repos.ncl . todo)
       (analysis-rules.ncl . todo))))
    
    (packaging
     (path . "packaging/")
     (status . not-started)
     (targets . (wolfi-apk guix-package nix-flake containerfile)))))

;;; ============================================================
;;; TODO ITEMS (Ordered by priority)
;;; ============================================================

(define todo-items
  '(;; Phase 1: Core MCP Server (Elixir)
    (1 high "Complete Datalog rules module" elixir-mcp)
    (2 high "Implement analysis queries" elixir-mcp)
    (3 high "Add issue templates" elixir-mcp)
    (4 medium "Datalog parser (text → AST)" elixir-mcp)
    (5 medium "GitHub webhook subscriptions" elixir-mcp)
    
    ;; Phase 2: Statistics & Scraping
    (6 medium "Multi-repo scraper" scripts)
    (7 medium "Julia stats package" julia-stats)
    (8 medium "Personal activity tracking" julia-stats)
    
    ;; Phase 3: Storage & Query
    (9 medium "Oxigraph integration" rdf-store)
    (10 low "SPARQL query interface" rdf-store)
    (11 low "Virtuoso fallback" rdf-store)
    
    ;; Phase 4: UI & Config
    (12 medium "Nickel config schema" config)
    (13 medium "ReScript-Tea dashboard" rescript-ui)
    (14 low "Activity visualizations" rescript-ui)
    
    ;; Phase 5: Packaging
    (15 low "Wolfi APK" packaging)
    (16 low "Guix package definition" packaging)
    (17 low "Nix flake" packaging)
    (18 low "Containerfile (nerdctl)" packaging)
    
    ;; Optional: Ada/SPARK
    (19 optional "Ada SPARK core types" ada-core)))

;;; ============================================================
;;; COMPLETED ITEMS
;;; ============================================================

(define completed-items
  '((2024-12-09 "Project structure created")
    (2024-12-09 "STATE.scm initialized")
    (2024-12-09 "Elixir mix.exs created")
    (2024-12-09 "OTP Application supervisor")
    (2024-12-09 "GitHub API client (GenServer)")
    (2024-12-09 "MCP Server (stdio JSON-RPC)")
    (2024-12-09 "Datalog Store (ETS-backed)")
    (2024-12-09 "Datalog Evaluator (semi-naive)")
    (2024-12-09 "Datalog Rules module (relationship, bug, state-sync, component, author)")
    (2024-12-09 "Analysis module (find_related, duplicates, regressions, hotspots)")
    (2024-12-09 "Templates module (bug, feature, docs, question, regression)")
    (2024-12-09 "Nickel config schema")
    (2024-12-09 "Nickel example config")
    (2024-12-09 "Julia stats package (Project.toml)")
    (2024-12-09 "Julia FeedbackStats module")
    (2024-12-09 "Multi-repo scraper script (Elixir)")
    (2024-12-09 "Containerfile (wolfi base)")
    (2024-12-09 "Guix package definition")
    (2024-12-09 "Nix flake")
    (2024-12-09 "README.md")))

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
      - Can persist to DETS if needed
      - Oxigraph handles persistent RDF")
    
    (2024-12-09 "oxigraph-over-virtuoso"
     "Preferring Oxigraph over Virtuoso because:
      - Rust-native, embeddable
      - Smaller footprint
      - Still full SPARQL 1.1
      - Virtuoso available as fallback for heavy workloads")
    
    (2024-12-09 "nickel-for-config"
     "Using Nickel for configuration because:
      - Typed configuration language
      - Can generate JSON/TOML/YAML
      - Contracts for validation
      - Better than raw JSON/YAML")))

;;; ============================================================
;;; CONVERSATION CONTEXT (for AI continuity)
;;; ============================================================

(define conversation-context
  '((origin . "Investigating Claude Code web UI session archive bug")
    (bug-summary . "Archived sessions immediately reappear due to server-side state sync overwriting user actions")
    (related-issues . (12114 10839 8667 9581))
    (target-repo . "anthropics/claude-code")
    (user-has . "60+ GitHub-connected repos with duplicate sessions")
    (evolved-to . "Comprehensive GitHub management tool with Datalog analysis")))

;;; ============================================================
;;; NEXT ACTIONS (for next conversation)
;;; ============================================================

(define next-actions
  '("1. Push to https://github.com/hyperpolymath/feedback-a-tron"
    "2. Test Elixir MCP server: cd elixir-mcp && mix deps.get && iex -S mix"
    "3. Test scraper: ./scripts/scraper.exs --repos anthropics/claude-code"
    "4. Configure MCP in Claude Code"
    "5. Build ReScript-Tea dashboard (rescript-ui/)"
    "6. Set up Oxigraph for RDF storage"
    "7. Add GitHub webhooks for real-time subscriptions"))

;; EOF

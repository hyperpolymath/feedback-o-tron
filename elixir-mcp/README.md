# Observatory

**GitHub Intelligence Platform** — Track, analyze, and visualize GitHub activity with local-first data sovereignty.

## Features

- **MCP Integration** — Use with Claude for intelligent issue management
- **Elixir MCP Server** — JSON-RPC 2.0 over stdio via elixir-mcp-server
- **Datalog Analysis** — Derive relationships, detect patterns, find regressions
- **Multi-Repo Scraping** — Track many repositories with rate limiting
- **Change Subscriptions** — Webhooks + polling for real-time updates
- **Julia Analytics** — Statistical analysis of contribution patterns
- **ReScript-Tea Frontend** — Type-safe web visualization (planned)
- **Semantic Storage** — Oxigraph RDF/SPARQL (optional)
- **Reproducible Builds** — Guix channel + Nix flake + Wolfi containers

## Quick Start

```bash
# Clone
git clone https://gitlab.com/jdajewell/observatory
cd observatory

# Install dependencies
mix deps.get

# Configure (copy and edit)
cp config/example.ncl config/local.ncl
nickel export config/local.ncl --format json > config/config.json

# Or use environment variables
export GITHUB_TOKEN=ghp_xxxx

# Run MCP server (for Claude integration)
FEEDBACK_A_TRON_MCP=1 mix run --no-halt -- --mcp-server

# Or build escript
mix escript.build
./gh-manage --mcp-server

# Optional: expose MCP over TCP (line-delimited JSON-RPC)
# Bind defaults to 127.0.0.1:7979; set FEEDBACK_A_TRON_MCP_TCP_BIND=0.0.0.0 for all interfaces
FEEDBACK_A_TRON_MCP=1 FEEDBACK_A_TRON_MCP_TCP=1 \
  FEEDBACK_A_TRON_MCP_TCP_PORT=7979 FEEDBACK_A_TRON_MCP_TCP_BIND=127.0.0.1 \
  mix run --no-halt -- --mcp-server

# TCP smoke test (defaults to 127.0.0.1:844)
MCP_PORT=844 scripts/mcp_tcp_smoke_test.sh
```

## Usage

### With Claude (MCP)

Add to your Claude Code MCP configuration:

```json
{
  "mcpServers": {
    "observatory": {
      "command": "/path/to/gh-manage",
      "args": ["--mcp-server"]
    }
  }
}
```

Then ask Claude things like:

- "Search for issues about session sync in claude-code"
- "Create a bug report for the archive persistence issue"
- "Find issues related to #12114"
- "What are the component hotspots in this repo?"
- "Show me state sync issues"

### Command Line

```bash
# Create issues interactively
gh-manage issue bug
gh-manage issue feature

# Search
gh-manage search "session archive"
gh-manage search "is:open label:bug"

# Analysis
gh-manage analyze find-related 12114
gh-manage analyze state-sync
gh-manage analyze hotspots
gh-manage analyze duplicates
gh-manage analyze regressions

# Repository management
gh-manage repos add anthropics/claude-code rust-lang/rust
gh-manage repos sync
gh-manage repos status

# Statistics (via Julia)
gh-manage stats contributions --user jdajewell
gh-manage stats hotspots

# Raw Datalog queries
gh-manage datalog "related(12114, Y, Reason)"
```

## Configuration

### Nickel (Recommended)

```nickel
# config/local.ncl
let schema = import "./schema.ncl" in

schema.make_config {
  github = {
    token = "ghp_xxxxxxxxxxxxxxxxxxxx",
  },
  
  repositories = [
    {
      owner = "anthropics",
      name = "claude-code",
      labels_of_interest = ["bug", "memory", "area:core"],
      components = [
        {
          name = "session_management",
          label_patterns = ["memory", "area:core"],
          keywords = ["session", "sync", "persist"],
        },
      ],
    },
  ],
  
  mcp = {
    default_repo = "anthropics/claude-code",
  },
} 'json
```

Generate different formats:

```bash
nickel export config/local.ncl --format json > config.json
nickel eval config/local.ncl -- to_elixir_config > config/runtime.exs
nickel eval config/local.ncl -- to_env_file > .env
nickel eval config/local.ncl -- to_guix_service > guix/service.scm
```

### Environment Variables

```bash
GITHUB_TOKEN=ghp_xxxx
GITHUB_API_URL=https://api.github.com  # or GitHub Enterprise URL
OBSERVATORY_DEFAULT_REPO=anthropics/claude-code
OBSERVATORY_SQLITE_PATH=./data/observatory.db
OBSERVATORY_POLL_INTERVAL=300
```

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Interfaces                               │
│  CLI (escript)  │  MCP Server  │  REST API  │  Web UI        │
└──────────────────────────────────────────────────────────────┘
                              │
┌──────────────────────────────────────────────────────────────┐
│                    Elixir Core (OTP)                          │
│  GitHub Client  │  Scraper  │  Subscriptions  │  Analysis     │
├──────────────────────────────────────────────────────────────┤
│  Datalog Store (ETS)  │  Datalog Evaluator  │  Rules Engine   │
└──────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐   ┌──────────┐   ┌──────────────┐
        │ Oxigraph │   │  SQLite  │   │ Julia Engine │
        │ RDF/SPARQL│   │ Timeline │   │  Statistics  │
        └──────────┘   └──────────┘   └──────────────┘
```

## Datalog Analysis

The Datalog engine derives relationships and patterns from GitHub data:

```prolog
% Find related issues
?- related(12114, Y, Reason).
% Returns: Y=10839 (same_component), Y=8667 (mentions), ...

% Find state sync issues
?- state_sync_issue(X), issue(X, Title, _, open, _, _).
% Returns: #12114, #10839, #8667, ...

% Find regression chains
?- fix_caused_regression(PR, Fixed, Broke).
% Returns: PR=1234, Fixed=100, Broke=150

% Component hotspots
?- component_hotspot(Component, Count).
% Returns: session_management=42, mcp_integration=18, ...
```

### Available Rules

| Rule | Description |
|------|-------------|
| `related(X, Y, Reason)` | Issues X and Y are related (mentions, same_component, same_label) |
| `state_sync_issue(X)` | Issue X is about state synchronization |
| `regression(X)` | Issue X was closed then reopened |
| `fix_caused_regression(PR, Fixed, Broke)` | PR fixed one issue but caused another |
| `potentially_duplicate(X, Y)` | High similarity between X and Y |
| `component_hotspot(C, N)` | Component C has N+ issues |

## Julia Analytics

Statistical analysis of contribution patterns:

```julia
using Observatory

# Load events
events = load_events("anthropics/claude-code")

# Contribution stats
stats = compute_contribution_stats(events, "jdajewell")
report = generate_report(stats)

# Generate charts
generate_charts(stats, "./charts")

# Repo stats
repo_stats = compute_repo_stats(events, "anthropics/claude-code")
```

Run as service:

```bash
julia analytics/src/Observatory.jl serve 8787
```

## Packaging

### Container (Wolfi + nerdctl)

```bash
# Build
nerdctl build -t observatory:latest -f Dockerfile.wolfi .

# Run
nerdctl run -d \
  -v ./config:/app/config \
  -v ./data:/app/data \
  -p 4000:4000 \
  -p 8080:8080 \
  observatory:latest
```

### Guix

```bash
# Add channel
guix pull --channels=./guix/channels.scm

# Install
guix install observatory

# Or use as service
guix system reconfigure config.scm
```

### Nix

```bash
# Development shell
nix develop

# Build
nix build

# NixOS module
{
  imports = [ ./flake.nix#nixosModules.default ];
  services.observatory.enable = true;
}
```

## Development

```bash
# Run tests
mix test

# Run with IEx
iex -S mix

# Type check
mix dialyzer

# Format
mix format

# Generate docs
mix docs
```

### Project Structure

```
observatory/
├── lib/
│   └── gh_manage/
│       ├── application.ex     # OTP app
│       ├── github.ex          # GitHub API client
│       ├── analysis.ex        # High-level analysis
│       ├── scraper.ex         # Multi-repo scraper
│       ├── subscriptions.ex   # Change tracking
│       ├── templates.ex       # Issue templates
│       ├── cli.ex             # CLI interface
│       ├── mcp/
│       │   └── server.ex      # MCP protocol
│       └── datalog/
│           ├── store.ex       # ETS fact store
│           ├── evaluator.ex   # Rule evaluator
│           └── rules.ex       # Inference rules
├── analytics/
│   └── src/
│       └── Observatory.jl     # Julia analytics
├── config/
│   └── schema.ncl             # Nickel config schema
├── frontend/                   # ReScript-Tea (planned)
├── guix/                       # Guix channel
├── mix.exs
├── flake.nix
└── ARCHITECTURE.md
```

## License

MPL-2.0

## Contributing

1. Fork on GitLab
2. Create feature branch
3. Make changes
4. Run tests: `mix test`
5. Submit merge request

## Acknowledgments

- Built with Elixir/OTP
- Datalog inspired by Datalog Educational System
- Configuration via Nickel
- Analytics via Julia

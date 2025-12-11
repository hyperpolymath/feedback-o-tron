# feedback-a-tron

> **SYNC STATUS**: Keep in sync with `STATE.scm` - run `scripts/sync-state.sh` to verify
> **Last sync**: 2025-12-11T14:30:00Z

## Project Overview

Automated multi-platform feedback submission with network verification.

- **Version**: 0.2.0 (alpha)
- **Phase**: ~60% to v1.0
- **Origin**: Claude Code API error investigation → MCP security proposals

## Quick Reference

### What This Project Does

1. **Multi-platform issue submission** - Submit to GitHub, GitLab, Bitbucket, Codeberg from one place
2. **Network verification** - Verify submissions actually arrive (latency, packet loss, TLS, DANE)
3. **Credential rotation** - Rotate API tokens to avoid rate limits
4. **MCP integration** - `submit_feedback` tool for Claude Code

### Key Files

```
elixir-mcp/lib/
├── feedback_submitter.ex     # Multi-platform submission GenServer
├── credentials.ex            # Credential management with rotation
├── network_verifier.ex       # Network-layer verification
└── mcp/tools/submit_feedback.ex  # MCP tool for Claude

docs/
└── LANDSCAPE.adoc            # Ecosystem analysis
```

### Tech Stack

- **MCP Server**: Elixir (OTP supervision, pattern matching)
- **Network Tools**: ping, traceroute, mtr, openssl, dig
- **Future**: Julia (stats), ReScript-Tea (UI), Oxigraph (RDF)

## v1.0 Blockers

### Must Have
- [ ] Elixir MCP server compiles and runs
- [ ] Multi-platform submission works (GitHub, GitLab)
- [ ] Network verification pre-flight checks
- [ ] Credential rotation functional
- [ ] Basic deduplication

### Should Have
- [ ] Bitbucket and Codeberg support
- [ ] Post-submission verification
- [ ] DNSSEC/DANE checks
- [ ] Audit logging

## Recent Work (2025-12-11)

1. Created `FeedbackATron.Submitter` - multi-platform submission
2. Created `FeedbackATron.Credentials` - credential rotation
3. Created `FeedbackATron.NetworkVerifier` - network verification
4. Created MCP tool `submit_feedback`
5. Submitted MCP Security SEPs (#1959-#1962)
6. Submitted Claude Code bug report (#13683)

## External Contributions

| Date | Target | Issues | Topic |
|------|--------|--------|-------|
| 2025-12-11 | modelcontextprotocol | #1959-#1962 | MCP Security (DNS, .well-known, headers, unified profile) |
| 2025-12-11 | anthropics/claude-code | #13683 | Content filter session corruption |

## Design Decisions

- **Elixir over Rust**: OTP supervision, pattern matching for Datalog
- **ETS over SQLite**: In-memory speed, Oxigraph for persistence
- **CLI fallback**: gh/glab already authenticated, handles token refresh
- **Network verification mandatory**: Feedback silently fails without it

## Commands

```bash
# Run MCP server
cd elixir-mcp && mix deps.get && iex -S mix

# Test submission (when complete)
FeedbackATron.Submitter.submit(%{
  title: "Test issue",
  body: "Testing",
  repo: "owner/repo"
}, platforms: [:github])
```

## Sync Validation

STATE.scm is the source of truth. CLAUDE.md is derived.

```bash
# Check sync
./scripts/sync-state.sh check

# Regenerate CLAUDE.md from STATE.scm
./scripts/sync-state.sh generate
```

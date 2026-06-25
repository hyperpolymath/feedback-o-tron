<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL_2.0--1.0-blue.svg)](https://github.com/hyperpolymath/palimpsest-license) ![Version
1.0.0](https://img.shields.io/badge/version-1.0.0-blue) ![RSR
Certified](https://img.shields.io/badge/RSR-Certified-gold) ![Idris
Inside](https://img.shields.io/badge/Idris-inside-purple) ![Production
Ready](https://img.shields.io/badge/Status-Production%20Ready-green)

Jonathan D.A. Jewell \<[j.d.a.jewell@open.ac](j.d.a.jewell@open.ac).uk\>
v1.0.0, 2026-02-07 :toc: macro :icons: font :source-highlighter: rouge
:experimental: :url-github:
<https://github.com/hyperpolymath/feedback-o-tron> :url-gitlab:
<https://gitlab.com/hyperpolymath/feedback-o-tron> :url-bitbucket:
<https://bitbucket.org/hyperpolymath/feedback-o-tron> :url-codeberg:
<https://codeberg.org/hyperpolymath/feedback-o-tron>

**Autonomous multi-platform bug reporting for AI agents** — Fully tested
in production with real Bugzilla submissions.

![Real World
Tested](https://img.shields.io/badge/Validated-2%20Real%20Bugs%20Filed-brightgreen)

<div id="toc">

</div>

> [!TIP]
> **AI-Assisted Install:** Just tell any AI:\
> `Set` `up` `feedback-o-tron` `from`
> [`https://github.com/hyperpolymath/feedback-o-tron`](https://github.com/hyperpolymath/feedback-o-tron)\
> It reads this repo, asks a few questions, and does everything.
> <a href="#ai-install" class="cross-reference">Details below</a>.

# AI-Assisted Installation (Recommended)

## Just Say It

**You don’t need to read this README.** Just say this to any AI
assistant:

```text
Set up feedback-o-tron from https://github.com/hyperpolymath/feedback-o-tron
```

**The URL is the spec.** The AI fetches this repo, reads
`docs/AI_INSTALLATION_GUIDE.adoc` inside it, and knows exactly what to
do. It figures out your system, installs prerequisites, builds the tool,
walks you through credentials, and verifies everything works. You answer
a few questions (what platforms, confirm privacy notice) and that’s it.
No manual steps, no forms, no copying commands.

Any AI that can read a URL and run commands (or generate commands for
you to paste) can do this. The guide inside the repo tells the AI
everything — your system config, your preferences, none of that needs to
be in the prompt.

The AI handles:

- Checking and installing prerequisites (Elixir, Erlang, Git)

- Cloning, building, and installing the CLI

- Walking you through credential creation for your platforms

- Configuring MCP integration (if you use Claude Code)

- Running a verification test

- Showing you how to use it

## Other Ways to Say It

If your AI already knows about feedback-o-tron (e.g. it can search the
web), shorter versions work:

- "Set up feedback-o-tron for automated bug reporting"

- "Install feedback-o-tron and configure it for GitHub and Bugzilla"

- "Help me set up feedback-o-tron as an MCP server for Claude Code"

If it doesn’t know the project, just include the URL:

- "Set up <https://github.com/hyperpolymath/feedback-o-tron> on my
  machine"

- "I want automated bug filing — install from
  [https://github.com/hyperpolymath/feedback-o-tron"](https://github.com/hyperpolymath/feedback-o-tron")

## What You’ll Be Asked

Your AI will ask you:

1.  **Which platforms?** (GitHub, GitLab, Bugzilla, Codeberg, Bitbucket,
    Email)

2.  **Privacy confirmation** — what the tool does with your credentials

3.  **Credential creation** — the AI tells you where to click, you paste
    the token back

That’s it. Everything else is automatic.

## Privacy & Security Notice

> [!IMPORTANT]
> **What feedback-o-tron does:**
>
> - Sends bug reports to platforms you configure
>
> - Uses API tokens you provide (stored in environment variables only)
>
> - Logs all operations locally (JSON-lines audit trail)
>
> - Deduplicates to prevent submitting the same bug twice
>
> **What feedback-o-tron does NOT do:**
>
> - Collect analytics or telemetry
>
> - Send data anywhere except your configured platforms
>
> - Store your API tokens in files
>
> - Submit bugs without your explicit command
>
> **You control everything:** which platforms, dry-run mode, full audit
> trail, uninstall anytime.

## After Install

Once your AI finishes, you can:

```bash
# File a bug (or just tell your AI to do it)
./feedback-a-tron submit --repo "owner/repo" --title "Bug" --body "Details" --platform github

# Dry-run (safe test)
./feedback-a-tron submit --repo "test" --title "Test" --body "Test" --dry-run

# Or with Claude Code MCP integration, just say:
# "File a bug about the crash in maliit-keyboard on Fedora Bugzilla"
```

## Uninstall

Tell your AI: "Remove feedback-o-tron from my system"

## Troubleshooting

| Problem | Solution |
|----|----|
| "elixir: command not found" | AI will install Elixir for you. Or: `asdf` `install` `elixir` `latest` |
| "401 Unauthorized" | Token expired or wrong scopes. Tell your AI and it will guide you through regeneration. |
| "duplicate detected" | Deduplicator working correctly. Use `--force` to submit anyway. |

<div id="manual-installation" wrapper="1">

For manual installation without AI assistance, see the
<a href="#manual-quick-start" class="cross-reference">Manual Quick
Start</a> section below.

</div>

------------------------------------------------------------------------

# Overview

feedback-o-tron is a production-ready tool for autonomous AI agents to
submit bug reports across multiple platforms. Successfully validated on
2026-02-07 with 2 real bugs filed to Fedora Bugzilla:

- <a href="https://bugzilla.redhat.com/show_bug.cgi?id=2437503"
  id="2437503">Bug</a>: maliit-keyboard crash loop (SIGABRT)

- <a href="https://bugzilla.redhat.com/show_bug.cgi?id=2437504"
  id="2437504">Bug</a>: xwaylandvideobridge portal error

Built for reliability with an Idris2 ABI specification layer (proofs
planned — see <a href="PROOF-NEEDS.md" class="md">PROOF-NEEDS</a> for
current status).

## Key Features

- **Multi-platform submission**: GitHub, GitLab, Bitbucket, Codeberg,
  Bugzilla, Email (6 platforms)

- **Bugzilla REST API**: Full support for product/component/version
  targeting

- **Deduplication**: Prevents duplicate submissions using fuzzy matching
  (Levenshtein distance)

- **Formal specification**: Idris2 ABI layer (dependent type proofs
  planned — see PROOF-NEEDS.md)

- **Credential rotation**: Avoids rate limits by rotating credentials

- **Audit logging**: Complete JSON-lines format record of all operations

- **MCP integration**: Works as Claude Code tool or standalone CLI

- **CLI mode**: Standalone escript for batch operations and testing

# Quick Start for AI Agents

## Zero-Knowledge Setup Prompt

Copy-paste this prompt to **any LLM or SLM** (Claude, ChatGPT, Gemini,
local models) to automatically configure feedback-o-tron:

```text
I need you to set up feedback-o-tron, an autonomous bug reporting tool. Here's what you need to do:

1. Clone the repository from https://github.com/hyperpolymath/feedback-o-tron
2. Navigate to the elixir-mcp directory
3. Run `mix deps.get` to install dependencies
4. Build the escript with `mix escript.build`
5. Test with dry-run: `./feedback-a-tron submit --repo "test/repo" --title "Test" --body "Test body" --platform github --dry-run`
6. Set up credentials:
   - For GitHub: export GITHUB_TOKEN=ghp_your_token
   - For Bugzilla: export BUGZILLA_API_KEY=your_api_key
7. Configure as MCP server in ~/.config/claude/mcp_servers.json:
   {
     "feedback-o-tron": {
       "command": "/full/path/to/feedback-a-tron",
       "args": ["--mcp-server"],
       "env": {
         "GITHUB_TOKEN": "${GITHUB_TOKEN}",
         "BUGZILLA_API_KEY": "${BUGZILLA_API_KEY}"
       }
     }
   }

After setup, you can submit bugs with commands like:
./feedback-a-tron submit --repo "Fedora" --title "App crashes on launch" --body "Details..." --platform bugzilla --component "kde" --version "43"

Check .machine_readable/6a2/STATE.a2ml in .machine_readable/ for project status and integrate with your workflow.
```

The AI agent will read this prompt and execute all setup steps
automatically.

## Manual Quick Start

```bash
# Clone
git clone {url-github}
cd feedback-o-tron/elixir-mcp

# Install dependencies
mix deps.get

# Build standalone CLI
mix escript.build

# Test (dry-run mode)
./feedback-a-tron submit \
  --repo "owner/repo" \
  --title "Bug title" \
  --body "Description" \
  --platform github \
  --dry-run

# Run MCP server mode
mix run --no-halt
```

# Production Status (2026-02-07)

**v1.0.0 - Production Ready** ✅

Successfully validated in real-world production:

- ✅ 2 bugs filed to Fedora Bugzilla
  (<a href="https://bugzilla.redhat.com/show_bug.cgi?id=2437503"
  id="2437503">https://bugzilla.redhat.com/show_bug.cgi?id=2437503</a>,
  <a href="https://bugzilla.redhat.com/show_bug.cgi?id=2437504"
  id="2437504">https://bugzilla.redhat.com/show_bug.cgi?id=2437504</a>)

- ✅ CLI module: Complete with --mcp-server, submit, --version, --help
  commands

- ✅ Bugzilla REST API: Full product/component/version support

- ✅ 6 platforms: GitHub, GitLab, Bitbucket, Codeberg, Bugzilla, Email

- ✅ Credential loading: Environment variables + CLI configs (gh, glab)

- ✅ Deduplication: Fuzzy matching with Levenshtein distance

- ✅ Audit logging: Complete event tracking with JSON-lines format

- ✅ Test suite: 26/26 tests passing

**Bugs fixed during validation:**

1.  Mix.env() usage in escript (replaced with Application.get_env)

2.  Missing CLI module

3.  Missing :submission event type

4.  Deduplicator binary_part out of range

5.  Bugzilla credentials not loading

6.  Bugzilla component hardcoded (now configurable via --component flag)

**MCP Integration:**

- MCP server supports stdio (default) for Claude Code integration

- TCP mode available (line-delimited JSON-RPC on port 844)

- Systemd service files included for daemon mode

# Usage

## As Standalone CLI

```bash
# Submit to GitHub
./feedback-a-tron submit \
  --repo "owner/repo" \
  --title "Bug: Something is broken" \
  --body "Full description..." \
  --platform github \
  --label "bug"

# Submit to Bugzilla (real-world tested)
./feedback-a-tron submit \
  --repo "Fedora" \
  --title "maliit-keyboard crash loop on startup" \
  --body "Package: maliit-keyboard\nCrashes with SIGABRT..." \
  --platform bugzilla \
  --component "maliit-keyboard" \
  --version "43"

# Multi-platform submission
./feedback-a-tron submit \
  --repo "owner/repo" \
  --title "Feature request" \
  --body "..." \
  --platform github \
  --platform gitlab \
  --platform codeberg

# Dry-run (test without submitting)
./feedback-a-tron submit \
  --repo "test/repo" \
  --title "Test" \
  --body "Test" \
  --dry-run

# Show version
./feedback-a-tron --version

# Show help
./feedback-a-tron --help
```

## As Elixir Library

```elixir
# Submit to GitHub
FeedbackATron.Submitter.submit(%{
  title: "Bug: Something is broken",
  body: "Description of the issue...",
  repo: "owner/repo"
}, platforms: [:github])

# Submit to Bugzilla
FeedbackATron.Submitter.submit(%{
  title: "maliit-keyboard crash",
  body: "Package crashes on startup...",
  repo: "Fedora"
}, platforms: [:bugzilla], component: "maliit-keyboard", version: "43")

# Submit to multiple platforms
FeedbackATron.Submitter.submit(%{
  title: "Feature request",
  body: "...",
  repo: "owner/repo"
}, platforms: [:github, :gitlab, :codeberg, :bugzilla])

# With deduplication check
FeedbackATron.Deduplicator.check(%{title: "...", body: "..."})
# => {:ok, :unique} | {:duplicate, existing} | {:similar, matches}
```

## As MCP Tool (Claude Code)

The MCP server exposes a `submit_feedback` tool for autonomous AI bug
reporting:

```json
{
  "tool": "submit_feedback",
  "params": {
    "title": "Bug report",
    "body": "Full description with reproduction steps...",
    "platforms": ["github", "gitlab", "bugzilla"],
    "repo": "owner/repo"
  }
}
```

MCP configuration in `~/.config/claude/mcp_servers.json`:

```json
{
  "feedback-o-tron": {
    "command": "/path/to/feedback-a-tron",
    "args": ["--mcp-server"],
    "env": {
      "GITHUB_TOKEN": "${GITHUB_TOKEN}",
      "BUGZILLA_API_KEY": "${BUGZILLA_API_KEY}"
    }
  }
}
```

# Formal Specification with Idris2 (Planned)

feedback-o-tron has an **Idris2** ABI specification layer for defining
platform types and FFI boundaries. Full dependent-type proofs for memory
safety and correctness are planned but not yet materialized.

> [!NOTE]
> The original template ABI files (Types.idr, Layout.idr, Foreign.idr)
> were removed on 2026-03-29 as they contained only scaffolding. See
> <a href="PROOF-NEEDS.md" class="md">PROOF-NEEDS</a> for what needs to
> be proven and the current status.

## Planned Proofs

- **Deduplication correctness**: Prove the deduplicator never drops
  unique entries

- **Submission atomicity**: Prove submissions fully succeed or fully
  fail

- **Memory layout**: Dependent type proofs for ABI layout correctness

- **Rate limiting fairness**: Prove rate limiting does not permanently
  block legitimate users

## Integration with Proven Repo

Can leverage 90+ formally verified modules from the
[proven](https://github.com/hyperpolymath/proven) repo:

- **SafeMath**: Overflow-safe arithmetic with mathematical proofs

- **SafeString**: Buffer overflow prevention with length proofs

- **SafeJSON**: Type-safe JSON parsing with schema validation

- **SafeURL**: URL parsing with format guarantees

Integration architecture:

    Idris2 (Formal Specifications → Proofs)
       ↓
    Zig FFI (C ABI Bridge)
       ↓
    Elixir/BEAM (Runtime)

This architecture will enable **provable correctness** at the ABI
boundary while maintaining **runtime flexibility** in Elixir.

# Architecture

See <a href="TOPOLOGY.md" class="md">TOPOLOGY</a> for a visual
architecture map and completion dashboard.

    ┌─────────────────────────────────────────────────────────────┐
    │                   FeedbackOTron                             │
    ├─────────────────────────────────────────────────────────────┤
    │  ┌──────────┐  ┌──────────────┐  ┌─────────────────────┐   │
    │  │Submitter │  │ Deduplicator │  │ NetworkVerifier     │   │
    │  │          │  │              │  │  - Latency/jitter   │   │
    │  │ - GitHub │  │ - SHA-256    │  │  - DNS verification │   │
    │  │ - GitLab │  │ - Levenshtein│  │  - TLS validation   │   │
    │  │-Bitbucket│  │ - Fuzzy match│  │  - BGP/RPKI checks  │   │
    │  │-Codeberg │  │              │  │                     │   │
    │  │-Bugzilla │  │              │  │                     │   │
    │  │ - Email  │  │              │  │                     │   │
    │  └──────────┘  └──────────────┘  └─────────────────────┘   │
    │                                                             │
    │  ┌──────────────────────────────────────────────────────┐  │
    │  │                  AuditLog                             │  │
    │  │  - All submissions recorded                          │  │
    │  │  - JSON lines format                                 │  │
    │  │  - Event types: :submission, :success, :error       │  │
    │  └──────────────────────────────────────────────────────┘  │
    ├─────────────────────────────────────────────────────────────┤
    │                   Credentials                               │
    │  - Environment variables (GITHUB_TOKEN, BUGZILLA_API_KEY)  │
    │  - CLI configs (gh, glab)                                  │
    │  - Rotation for rate limit avoidance                       │
    ├─────────────────────────────────────────────────────────────┤
    │            Idris2 ABI Layer (Formal Specification)           │
    │  - Platform type definitions                                │
    │  - FFI boundary specs via Zig C ABI bridge                  │
    │  - Dependent type proofs planned (see PROOF-NEEDS.md)       │
    └─────────────────────────────────────────────────────────────┘

# Setup for Different LLMs

## Claude Code (Anthropic)

1.  Add to `~/.config/claude/mcp_servers.json`:

    ``` json
    {
      "feedback-o-tron": {
        "command": "/full/path/to/feedback-a-tron",
        "args": ["--mcp-server"],
        "env": {
          "GITHUB_TOKEN": "${GITHUB_TOKEN}",
          "BUGZILLA_API_KEY": "${BUGZILLA_API_KEY}"
        }
      }
    }
    ```

<!-- -->

2.  Restart Claude Code

3.  Use tool: `submit_feedback` with parameters

## ChatGPT / GPT-4 (OpenAI)

Use as CLI tool with GPT Code Interpreter or via API:

```bash
# GPT can execute shell commands
./feedback-a-tron submit --repo "owner/repo" --title "..." --body "..." --platform github
```

Or integrate via API wrapper.

## Gemini (Google)

Use as CLI tool:

```bash
# Gemini can execute commands in code execution environment
./feedback-a-tron submit --repo "..." --title "..." --body "..." --platform bugzilla --component "..." --version "..."
```

## Local SLMs (Ollama, LM Studio, etc.)

1.  Install feedback-o-tron as escript

2.  Expose via function calling or tool use API

3.  Configure credentials in environment

4.  Call via shell execution

Example function definition:

```json
{
  "name": "submit_bug_report",
  "description": "Submit a bug report to GitHub, GitLab, Bitbucket, Codeberg, Bugzilla, or Email",
  "parameters": {
    "type": "object",
    "properties": {
      "title": {"type": "string", "description": "Bug title"},
      "body": {"type": "string", "description": "Full bug description"},
      "repo": {"type": "string", "description": "Repository (owner/repo or product name for Bugzilla)"},
      "platform": {"type": "string", "enum": ["github", "gitlab", "bitbucket", "codeberg", "bugzilla", "email"]},
      "component": {"type": "string", "description": "Bugzilla component (optional)"},
      "version": {"type": "string", "description": "Bugzilla version (optional)"}
    },
    "required": ["title", "body", "repo", "platform"]
  }
}
```

# Troubleshooting

## Build Errors

**Error**: `Could` `not` `generate` `escript,` `module`
`Elixir.FeedbackATron.CLI` `could` `not` `be` `loaded`

- **Fix**: Ensure CLI module exists at `lib/feedback_a_tron/cli.ex`

- Run: `mix` `compile` before `mix` `escript.build`

**Error**: `function` `Mix.env/0` `is` `undefined` `(module` `Mix` `is`
`not` `available)`

- **Cause**: Mix module not available in compiled escript

- **Fix**: Use `Application.get_env(:feedback_a_tron,` `:env)` instead

## Credential Issues

**Error**: `{:error,` `:no_credentials}`

- Check environment variables are set: `echo` `$GITHUB_TOKEN`

- Or check CLI configs exist:

  - `~/.config/gh/hosts.yml` (GitHub)

  - `~/.config/glab-cli/config.yml` (GitLab)

**Error**: Bugzilla authentication failed

- Verify API key: `export` `BUGZILLA_API_KEY=your_key`

- Test with curl:

  ``` bash
  curl -H "Authorization: Bearer $BUGZILLA_API_KEY" \
    https://bugzilla.redhat.com/rest/bug/2437503
  ```

## Platform-Specific Errors

**Bugzilla**: `There` `is` `no` `component` `named` `’X’` `in` `the`
`’Y’` `product`

- **Fix**: Use correct component name with `--component` flag

- List valid components via Bugzilla web UI or API

**GitHub**: Rate limit exceeded

- **Fix**: Credential rotation will automatically use next token

- Or wait for rate limit reset

## Deduplication

**Error**: `binary_part` out of range

- **Fixed in v1.0.0**: Body normalization now happens before slicing

- Upgrade to latest version

# Network Verification

Before and after submission, FeedbackOTron verifies:

| Check           | Purpose                     |
|-----------------|-----------------------------|
| Latency/Jitter  | Detect unstable connections |
| Packet loss     | Ensure data integrity       |
| DNS resolution  | Verify correct destination  |
| DNSSEC          | Prevent DNS spoofing        |
| TLS certificate | Verify endpoint identity    |
| BGP origin      | Detect route hijacking      |

# Configuration

## Credentials

Environment variables (recommended):

```bash
# GitHub (or auto-detected from gh CLI)
export GITHUB_TOKEN=ghp_...

# GitLab (or auto-detected from glab CLI)
export GITLAB_TOKEN=glpat_...

# Bitbucket (requires username)
export BITBUCKET_TOKEN=...
export BITBUCKET_USERNAME=your_username

# Codeberg (Gitea-compatible API)
export CODEBERG_TOKEN=...

# Bugzilla (tested with Fedora Bugzilla)
export BUGZILLA_API_KEY=your_api_key
export BUGZILLA_URL=https://bugzilla.redhat.com  # optional, defaults to RH

# Email (SMTP configuration)
export SMTP_HOST=smtp.example.com
export SMTP_PORT=587
export SMTP_USERNAME=user
export SMTP_PASSWORD=pass
export SMTP_FROM=feedback@example.com
export FEEDBACK_EMAIL_TO=bugs@example.com
```

**Auto-detection**: If environment variables are not set,
feedback-o-tron will attempt to load credentials from:

- `~/.config/gh/hosts.yml` (GitHub)

- `~/.config/glab-cli/config.yml` (GitLab)

## Platform-Specific Options

**Bugzilla:**

```bash
# Component and version are REQUIRED for Bugzilla
./feedback-a-tron submit \
  --repo "Fedora" \
  --title "..." \
  --body "..." \
  --platform bugzilla \
  --component "maliit-keyboard" \  # Required: package/component name
  --version "43"                   # Required: version (or "rawhide")
```

Default values:

- Component: "distribution" (generic)

- Version: "rawhide" (development)

- Severity: "medium"

- OS: "Linux"

- Platform: "x86_64"

# Testing

## Unit Tests

```bash
cd elixir-mcp
mix test
```

**Test coverage:**

- Submitter: GitHub, GitLab, Bitbucket, Codeberg, Bugzilla platforms

- Deduplicator: Exact hash, fuzzy matching, Levenshtein distance

- Credentials: Environment variables, CLI config loading

- Audit log: Event recording, JSON-lines format

## Integration Tests

**Dry-run mode** (no actual submission):

```bash
./feedback-a-tron submit \
  --repo "test/repo" \
  --title "Test bug" \
  --body "Test description" \
  --platform github \
  --dry-run
```

Expected output: ---- ✅ Submission ABC123 completed \[DRY RUN\] github:
Would submit ----

## Real-World Validation

**Production bugs filed (2026-02-07):**

1.  **<a href="https://bugzilla.redhat.com/show_bug.cgi?id=2437503"
    id="2437503">Bug</a>**: maliit-keyboard crash loop

    - Platform: Fedora Bugzilla

    - Component: maliit-keyboard

    - Version: 43

    - Status: Successfully submitted with full stack trace

<!-- -->

2.  **<a href="https://bugzilla.redhat.com/show_bug.cgi?id=2437504"
    id="2437504">Bug</a>**: xwaylandvideobridge portal error

    - Platform: Fedora Bugzilla

    - Component: plasma-desktop

    - Version: 43

    - Status: Successfully submitted with error details

Both bugs demonstrate end-to-end workflow:

- AI agent detected crashes via system logs

- Formatted bug reports with reproduction steps

- Submitted to Bugzilla REST API

- Received bug IDs and URLs

- Audit logs recorded all operations

# Future Enhancements

## Proven Repo Integration

The [proven](https://github.com/hyperpolymath/proven) repository
provides 90+ formally verified Idris2 modules that can enhance
feedback-o-tron:

**SafeMath**: Overflow-safe arithmetic with mathematical proofs

```idris
-- Addition with overflow detection
safeAdd : (a : Nat) -> (b : Nat) -> Either OverflowError (n : Nat ** n = a + b)
```

**SafeString**: Buffer overflow prevention

```idris
-- String operations with length proofs
safeConcat : (s1 : String) -> (s2 : String) ->
             {auto prf : length s1 + length s2 <= maxLen} -> String
```

**SafeJSON**: Type-safe JSON parsing with schema validation

```idris
-- Parse JSON with compile-time schema validation
parseJSON : (schema : JSONSchema) -> String -> Either ParseError (JSONValue schema)
```

**Integration approach:**

1.  Use Idris2 for formal specification of API contracts

2.  Generate Zig FFI bindings via C ABI

3.  Call from Elixir via NIFs

4.  Maintain formal proofs for critical paths

**Benefits:**

- Compile-time guarantees of API correctness

- Memory safety proofs at FFI boundaries

- Mathematical verification of deduplication algorithms

- Provably correct credential rotation

# Mirrors

| Platform         | URL             |
|------------------|-----------------|
| GitHub (primary) | {url-github}    |
| GitLab           | {url-gitlab}    |
| Bitbucket        | {url-bitbucket} |
| Codeberg         | {url-codeberg}  |

# License

Licensed under MPL-2.0 (MPL-2.0).

See <a href="LICENSE.txt" class="txt">LICENSE</a> for details.

# Contributing

See <a href="CONTRIBUTING.adoc" class="adoc">CONTRIBUTING</a>.

# OPSM Link

    OPSM Core
      |
      v
    feedback-o-tron (feedback/telemetry capture for OPSM (opt‑in))

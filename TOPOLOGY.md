<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- TOPOLOGY.md — Project architecture map and completion dashboard -->
<!-- Last updated: 2026-07-09 -->

# feedback-o-tron — Project Topology

## System Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              AI AGENTS / USERS          │
                        │        (Claude, Gemini, ChatGPT)        │
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │          INTERFACE LAYER                │
                        │  ┌────────┐ ┌────────────┐ ┌─────────┐ │
                        │  │  MCP   │ │ Standalone │ │  HTTP   │ │
                        │  │ Server │ │CLI(Escript)│ │ Intake  │ │
                        │  │3 tools │ │            │ │:7722 boj│ │
                        │  └───┬────┘ └─────┬──────┘ └────┬────┘ │
                        └──────│────────────│─────────────│──────┘
                               │            │             │
                               ▼            ▼             ▼
                        ┌─────────────────────────────────────────┐
                        │       SYNTHESIS ENGINE (ELIXIR)         │
                        │       agent-in-the-loop, no LLM         │
                        │  ┌──────────────┐ ┌──────────────────┐ │
                        │  │TemplateFetch │ │ IntentClassifier │ │
                        │  │  + Cache     │ │ (usefulness gate)│ │
                        │  └──────┬───────┘ └────────┬─────────┘ │
                        │  ┌──────▼───────┐ ┌────────▼─────────┐ │
                        │  │  Hydrator    │ │ Research         │ │
                        │  │(+NetVerifier)│ │ (forge + dedup)  │ │
                        │  └──────┬───────┘ └────────┬─────────┘ │
                        │  ┌──────▼──────────────────▼─────────┐ │
                        │  │ Synthesizer → FormValidator →     │ │
                        │  │ FormRenderer                      │ │
                        │  └──────────────────┬────────────────┘ │
                        └───────────────────── │ ─────────────────┘
                                              │
                                              ▼
                        ┌─────────────────────────────────────────┐
                        │           CORE LOGIC (ELIXIR)           │
                        │                                         │
                        │  ┌───────────┐  ┌───────────────────┐  │
                        │  │ Submitter │  │  Deduplicator     │  │
                        │  │ (Multi-P) │  │  (Fuzzy/Lev)      │  │
                        │  │ validates │  │  WIRED: record/3  │  │
                        │  │ template  │  │  on success       │  │
                        │  └─────┬─────┘  └────────┬──────────┘  │
                        │        │                 │              │
                        │  ┌─────▼─────┐  ┌────────▼──────────┐  │
                        │  │ AuditLog  │  │ NetworkVerifier   │  │
                        │  │ (JSON-L)  │  │ (DNS/TLS/BGP)     │  │
                        │  └─────┬─────┘  └────────┬──────────┘  │
                        └────────│─────────────────│──────────────┘
                                 │                 │
                                 ▼                 ▼
                        ┌─────────────────────────────────────────┐
                        │   VALIDATION CONTRACT (IDRIS2 + ELIXIR) │
                        │  Idris2 contract spec (real, CI-checked)│
                        │  src/abi/FeedbackOTron/Contract.idr     │
                        │  + Elixir FormValidator runtime boundary│
                        │  Zig FFI = stub (no FFI enforcement)    │
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │          EXTERNAL PLATFORMS             │
                        │  ┌───────────┐  ┌───────────┐  ┌───────┐│
                        │  │ GitHub    │  │ GitLab    │  │ B-Zilla││
                        │  └───────────┘  └───────────┘  └───────┘│
                        │  ┌───────────┐  ┌───────────┐  ┌───────┐│
                        │  │ Codeberg  │  │ Bitbucket │  │ Email ││
                        │  └───────────┘  └───────────┘  └───────┘│
                        └─────────────────────────────────────────┘
```

## Completion Dashboard

```
COMPONENT                          STATUS              NOTES
─────────────────────────────────  ──────────────────  ─────────────────────────────────
INTERFACE LAYER
  MCP Server (Stdio/TCP)            ██████████ 100%    research/synthesize/submit tools
  CLI Module (Escript)              ██████████ 100%    Full flag support
  HTTP Intake (Bandit, :7722)       ██████████ 100%    Localhost-only; off by default;
                                                       drives boj bug-filing-mcp wire

SYNTHESIS ENGINE (ELIXIR)
  TemplateFetcher + Cache           ██████████ 100%    Engine-side fetch of bug.yml etc.
  IntentClassifier                  ██████████ 100%    Usefulness gate; salvage/reject
  Hydrator                          ██████████ 100%    Fields from context/system state
  Research (forge + local dedup)    ██████████ 100%    Pre-filing duplicate search
  FormValidator / FormRenderer      ██████████ 100%    Runtime side of Idris2 contract
  Synthesizer (orchestrator)        ██████████ 100%    Agent-in-the-loop, no embedded LLM

CORE LOGIC (ELIXIR)
  Submitter (Multi-platform)        █████████░  90%    Bugzilla validated real-world;
                                                       other channels API-complete
  Deduplicator (Fuzzy Match)        ██████████ 100%    WIRED: record/3 called on success
  NetworkVerifier                   ███████░░░  70%    Real probing; opt-in via Hydrator
                                                       network_probe; BGP/RPKI partial
  AuditLog (JSON-L)                 ██████████ 100%    Complete event tracking

VALIDATION CONTRACT
  Contract.idr (Idris2 spec)        ██████████ 100%    Real, total, proof-carrying,
                                                       CI-checked; no postulates
  Elixir runtime boundary           ██████████ 100%    FormValidator enforces the spec
  Zig FFI Bridge                    █░░░░░░░░░  10%    STUB — no FFI enforcement yet

EXTERNAL PLATFORMS
  GitHub Integration                ██████████ 100%    Token/CLI config support
  Bugzilla REST API                 ██████████ 100%    Validated with Fedora bugs
  GitLab/Codeberg/Bitbucket         █████████░  90%    API integration; less real-world
  Email (SMTP)                      █████████░  90%    Validated with local relays

REPO INFRASTRUCTURE
  Justfile                          ██████████ 100%    Standard build tasks
  .machine_readable/                ██████████ 100%    STATE.a2ml tracking
  Test Suite (ExUnit)               █████████░  90%    Suite in CI; coverage still growing

─────────────────────────────────────────────────────────────────────────────
OVERALL:                            ████████░░ ~75%    Core validated; synthesis new;
                                                       FFI enforcement not built
```

## Key Dependencies

```
Idris2 contract spec ──(mirrored by)──► Elixir FormValidator
        │                                      │
        └──(Zig FFI bridge: STUB, ──► planned enforcement path)
                                               │
                                        Elixir Core
                                               │
              ┌──────────┬────────────┬────────┴──────┬──────────┐
              ▼          ▼            ▼               ▼          ▼
          Submitter  Deduplicator  Synthesis     AuditLog   Verifier
              │          │         Engine            │          │
              └──────────┴────────────┬──────────────┴──────────┘
                                      ▼
                                EXTERNAL APIs
```

## Update Protocol

This file is maintained by both humans and AI agents. When updating:

1. **After completing a component**: Change its bar and percentage
2. **After adding a component**: Add a new row in the appropriate section
3. **After architectural changes**: Update the ASCII diagram
4. **Date**: Update the `Last updated` comment at the top of this file
5. **Honesty rule**: a bar only reaches 100% when the code exists, is wired
   in, and does what the row says. "Aspirational" boxes get a low bar and a
   note — never a full bar. No universal "100% Production Ready" rows.

Progress bars use: `█` (filled) and `░` (empty), 10 characters wide.
Percentages: 0%, 10%, 20%, ... 100% (in 10% increments).

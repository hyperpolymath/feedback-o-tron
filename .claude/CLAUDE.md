<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
## Machine-Readable Artefacts

The following files in `.machine_readable/` contain structured project metadata:

- `.machine_readable/6a2/STATE.a2ml` - Current project state and progress
- `.machine_readable/6a2/META.a2ml` - Architecture decisions and development practices
- `.machine_readable/6a2/ECOSYSTEM.a2ml` - Position in the ecosystem and related projects
- `.machine_readable/6a2/AGENTIC.a2ml` - AI agent interaction patterns
- `.machine_readable/6a2/NEUROSYM.a2ml` - Neurosymbolic integration config
- `.machine_readable/6a2/PLAYBOOK.a2ml` - Operational runbook

---

# CLAUDE.md - AI Assistant Instructions

## Language Policy (Hyperpolymath Standard)

### ALLOWED Languages & Tools

| Language/Tool | Use Case | Notes |
|---------------|----------|-------|
| **AffineScript** | Primary application code | Affine-typed, compiles to typed-wasm or ESM |
| **Bun** | JS runtime & package management (tier 1) | Default for all new work. Runs compiled ESM/JS directly — no bundler step. Uses an npm-compatible `package.json` plus `bun.lock` — both are expected, not anti-patterns. |
| **Rust** | Performance-critical, systems, WASM | Preferred for CLI tools |
| **Tauri 2.0+** | Mobile apps (iOS/Android) | Rust backend + web UI |
| **Dioxus** | Mobile apps (native UI) | Pure Rust, React-like |
| **Gleam** | Backend services | Runs on BEAM or compiles to JS |
| **Bash/POSIX Shell** | Scripts, automation | Keep minimal |
| **JavaScript** | Only where AffineScript cannot | MCP protocol glue, Bun APIs |
| **Nickel** | Configuration language | For complex configs |
| **Guile Scheme** | State/meta files | .machine_readable/6a2/STATE.a2ml, .machine_readable/6a2/META.a2ml, .machine_readable/6a2/ECOSYSTEM.a2ml |
| **Julia** | Batch scripts, data processing | Per RSR |
| **OCaml** | AffineScript compiler | Language-specific |
| **Ada** | Safety-critical systems | Where required |

### BANNED - Do Not Use

| Banned | Replacement |
|--------|-------------|
| TypeScript | AffineScript |
| Deno | Bun |
| Node.js | Bun |
| npm | Bun |
| pnpm/yarn | Bun |
| Go | Rust |
| Python | Julia/Rust/AffineScript |
| Java/Kotlin | Rust/Tauri/Dioxus |
| Swift | Tauri/Dioxus |
| React Native | Tauri/Dioxus |
| Flutter/Dart | Tauri/Dioxus |

### ABI / FFI Baseline (Estate-wide, verified 2026-07-17)

- **Any ABI must be Idris2** — dependent-type proofs, `%default total`, zero
  `believe_me`/`postulate`/`assert_total` in the trusted core. This repo's own
  `src/abi/FeedbackOTron/Contract.idr` follows this (real, CI-checked by
  `proofs.yml`).
- **Any FFI must be Zig.** This repo's `ffi/zig/src/main.zig` is currently a
  labeled stub — no other language is substituted for it.
- **The "unified adapter" protocol-bridge layer** (Zig, single loopback
  listener, exposure-gated dispatch into one C ABI — see `boj-server` and
  `boj-server-cartridges` CLAUDE.md for the full contract) is a **boj
  cartridge** concept. This repo is the wrapped *engine*, not a cartridge
  itself (the cartridge is `bug-filing-mcp` in `boj-server-cartridges`), so it
  does not carry an `adapter/` directory of its own. Its front doors (MCP
  stdio/TCP, HTTP intake) are Elixir/OTP by architecture decision, unrelated
  to the Zig adapter pattern.
- Naming lineage: the fuller "Hexadeca-Connector" (16-protocol-surface) pattern
  lives in `hyperpolymath/hypatia` and `hyperpolymath/proven-servers`, descended
  from a **retired** V-lang reference (`developer-ecosystem/v-ecosystem/v_api_interfaces`),
  replaced by Zig+Idris2+Rust-client per the estate-wide V-lang ban
  (2026-04-10). Never resurrect a V-lang adapter/ABI/FFI.

### Mobile Development

**No exceptions for Kotlin/Swift** - use Rust-first approach:

1. **Tauri 2.0+** - Web UI (AffineScript) + Rust backend, MIT/Apache-2.0
2. **Dioxus** - Pure Rust native UI, MIT/Apache-2.0

Both are FOSS with independent governance (no Big Tech).

### Enforcement Rules

1. **No new TypeScript files** - Convert existing TS to AffineScript
2. **Use `package.json` + `bun.lock` for JS runtime deps** - Bun is npm-compatible; a manifest is REQUIRED
3. **`bun install --production` for production deps** - resolved from `package.json`, pinned via `bun.lock`
4. **No Go code** - Use Rust instead
5. **No Python anywhere** - Use Julia for data/batch, Rust for systems, AffineScript for apps
6. **No Kotlin/Swift for mobile** - Use Tauri 2.0+ or Dioxus

### Package Management

- **Primary**: Guix (guix.scm)
- **Fallback**: Guix (flake.guix)
- **JS deps**: Bun (`package.json` + `bun.lock`). Declare tooling as a devDependency and run `bunx --no-install --bun <tool>` — a bare `bunx <tool>` can fetch an unpinned package and may start Node via its shebang.

### Security Requirements

- No MD5/SHA1 for security (use SHA256+)
- HTTPS only (no HTTP URLs)
- No hardcoded secrets
- SHA-pinned dependencies
- SPDX license headers on all files


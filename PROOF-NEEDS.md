# Proof Requirements

## Current state
- `src/abi/Types.idr` — Feedback types
- `src/abi/Layout.idr` — Memory layout
- `src/abi/Foreign.idr` — FFI declarations
- No dangerous patterns in ABI layer
- Claims: "formal verification via Idris2 for critical ABI definitions and memory safety proofs", "Production Ready"
- 92K lines of source

## What needs proving
- **Deduplication correctness**: Prove the deduplicator never drops unique feedback entries and never allows true duplicates through
- **Submission atomicity**: Prove feedback submissions either fully succeed or fully fail (no partial submissions that corrupt state)
- **Memory layout proofs**: The README claims "memory safety proofs" — these should be materialized in the ABI layer with actual dependent type proofs for layout correctness
- **Rate limiting fairness**: Prove rate limiting does not permanently block legitimate users

## Recommended prover
- **Idris2** — Already used for ABI; the claim of "memory safety proofs" needs to be substantiated with actual proofs in the existing `.idr` files

## Priority
- **MEDIUM** — The README explicitly claims formal verification and memory safety proofs. If those proofs do not exist in substance, the claim is misleading. Priority is to either write the proofs or soften the claims.

## Template ABI Cleanup (2026-03-29)

Template ABI removed -- was creating false impression of formal verification.
The removed files (Types.idr, Layout.idr, Foreign.idr) contained only RSR template
scaffolding with unresolved {{PROJECT}}/{{AUTHOR}} placeholders and no domain-specific proofs.

# Test & Benchmark Requirements

## CRG Grade: C — ACHIEVED 2026-04-04

## Current State
- Unit tests: NONE (0 test files found)
- Integration tests: NONE
- E2E tests: NONE
- Benchmarks: NONE
- panic-attack scan: NEVER RUN

## What's Missing
### Point-to-Point (P2P)
34 Elixir source files with ZERO test files:
- feedback_a_tron/application.ex — no tests
- feedback_a_tron/deduplicator.ex — no tests
- feedback_a_tron/mcp/tools/submit_feedback.ex — no tests
- feedback_a_tron/mcp/tools/migration_observe.ex — no tests
- feedback_a_tron/mcp/server.ex — no tests
- feedback_a_tron/network_verifier.ex — no tests
- feedback_a_tron/submitter.ex — no tests
- feedback_a_tron/audit_log.ex — no tests
- feedback_a_tron/cli.ex — no tests
- feedback_a_tron/migration_observer.ex — no tests
- feedback_a_tron/verisim_writer.ex — no tests
- feedback_a_tron/batch_reviewer.ex — no tests
- feedback_a_tron/report_generator.ex — no tests
- feedback_a_tron/pipeline/supervisor.ex — no tests
- feedback_a_tron/pipeline/producer.ex — no tests
- feedback_a_tron/pipeline/verisim_consumer.ex — no tests
- feedback_a_tron/pipeline/review_consumer.ex — no tests
- feedback_a_tron/secure_dns.ex — no tests
- feedback_a_tron/channels/nntp.ex — no tests
- feedback_a_tron/channels/discourse.ex — no tests
- Plus ~14 more modules
- 3 Idris2 ABI files — no tests
- 1 Julia file — no tests

### End-to-End (E2E)
- Submit feedback -> deduplicate -> review -> write to VeriSimDB
- MCP server: receive tool call -> process -> respond
- Batch review: load batch -> review all -> generate report
- Pipeline: produce events -> consume -> write to VeriSimDB
- Migration observation: detect migration -> observe -> record
- NNTP channel: receive -> process -> forward
- Discourse channel: receive -> process -> forward
- CLI: submit/review/report commands

### Aspect Tests
- [ ] Security (MCP tool injection, network verifier bypass, NNTP injection, audit log tampering)
- [ ] Performance (batch review throughput, pipeline backpressure, VeriSimDB write latency)
- [ ] Concurrency (GenStage pipeline, concurrent submissions, supervisor restart)
- [ ] Error handling (VeriSimDB unavailable, network failures, malformed feedback)
- [ ] Accessibility (N/A)

### Build & Execution
- [ ] mix compile — not verified
- [ ] mix test — not verified (no test files to run)
- [ ] MCP server starts — not verified
- [ ] CLI --help works — not verified
- [ ] Self-diagnostic — none

### Benchmarks Needed
- Feedback submission throughput
- Deduplication speed and accuracy
- Pipeline end-to-end latency
- VeriSimDB write performance
- Batch review performance at scale

### Self-Tests
- [ ] panic-attack assail on own repo
- [ ] MCP server health check
- [ ] Pipeline self-test

## Priority
- **HIGH** — 34 Elixir source files with ZERO tests. This is a feedback processing system with MCP integration, GenStage pipeline, multi-channel input (NNTP, Discourse), VeriSimDB integration, and audit logging. Not a single module has a test file. The pipeline supervisor/producer/consumer pattern especially needs testing for correctness under load and failure conditions.

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage

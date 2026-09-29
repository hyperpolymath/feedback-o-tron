#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Acceptance test for the SP1b pre-ledger rule.
#
# The rule: nothing leaves this machine unless a person has read the whole
# payload and typed y. Consent cannot be asserted over the wire, so an MCP
# client must never be able to make the engine file anything.
#
# This once failed. Before the fail-closed choke point in Submitter, a client
# calling submit_feedback over stdio caused three real `gh issue create` calls
# with no payload shown and no y typed. This script is the measurement that
# caught it, kept as a regression test.
#
# Method: put a fake `gh` first on PATH that records every argv it is handed
# and refuses to run, hand the engine a credential so it cannot stop early for
# the wrong reason, then drive the MCP door exactly as a host would.
#
# PASS: the engine made no `gh issue create` call AND the door answered
#       "drafted".
# FAIL (exit 1): any `gh issue create` call, or a response that is not drafted.
#
# Counting: only `gh issue create` is a send, so only `gh issue create` is
# counted. `gh auth token` is a credential probe, not a submission — counting
# it made this verdict depend on whether the engine happened to probe, so the
# check could pass or fail for a reason that had nothing to do with consent.
#
# Positive control: `--self-test` builds a mutant whose consent gate is
# defeated, checks that this script FAILS against it, restores the tree and
# re-checks the real one. A harness that has never been seen to fail is not
# evidence of anything.
#
# Usage:
#   scripts/consent_bypass_check.sh              (run from elixir-mcp/)
#   scripts/consent_bypass_check.sh --self-test  (also prove the harness bites)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

self_test=false
case "${1:-}" in
  --self-test) self_test=true ;;
  "") ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac

submitter="lib/feedback_a_tron/submitter.ex"
work="$(mktemp -d)"
ghlog="$work/gh-calls.log"
: >"$ghlog"

# A `gh` that cannot send, but tells us it was asked to.
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$ghlog"
exit 1
FAKE
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

cleanup() {
  # Restore the tree if the self-test left a mutant in place, however we exit.
  if [ -f "$work/submitter.ex.orig" ]; then
    cp "$work/submitter.ex.orig" "$submitter"
  fi
  rm -rf "$work"
  rm -f feedback-o-tron
}
trap cleanup EXIT

# A pristine HOME, so that what this script measures is the engine and not the
# machine it runs on. `Credentials` reads ~/.config/gh/hosts.yml, so on a
# developer box with a logged-in gh the file answers and the fake `gh` below is
# never reached, while on a CI runner with no hosts.yml the same code shells
# out. That made this check pass locally and fail in CI for a reason that had
# nothing to do with consent. An acceptance test whose verdict depends on
# whether the host happens to hold a credential file is not a test.
#
# Only the engine run is isolated: `mix escript.build` legitimately needs the
# real HOME for ~/.hex and ~/.mix.
fakehome="$work/home"
mkdir -p "$fakehome"

# A syntactically valid token the engine will accept. This is what gives the
# check its teeth: it is the credential a bypass would actually send with.
# Measured against a mutant whose consent gate was defeated, the check records
#
#     gh issue create --repo ... --title consent bypass check --body ...
#
# naming the send and its payload. Without the token the same mutant stops at
# {:error, :no_credentials} and never reaches `gh issue create`, so the check
# would be resting on the incidental `gh auth token` probe rather than on the
# send -- and would fall silent the day that probe is made conditional. The
# value is fake and is never transmitted: the only `gh` on PATH refuses to run.
#
# It is assembled at runtime rather than written out as a literal. A
# token-shaped string of this length in a tracked file is indistinguishable
# from a real leak to a secret scanner, and `scan / shell-secrets` fails the
# build on exactly that shape -- correctly, because a scanner that believed a
# neighbouring comment saying "this one is fake" would be worth nothing.
export GITHUB_TOKEN="ghp_$(printf '0%.0s' $(seq 34))"

# Two frames, line-delimited JSON-RPC, exactly as an MCP host sends them.
# No dry_run key: this asks the engine to file for real.
req="$work/request.jsonl"
cat >"$req" <<'JSON'
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","id":"call","method":"tools/call","params":{"name":"submit_feedback","arguments":{"title":"consent bypass check","body":"If this text reaches a tracker, the pre-ledger rule is broken.","repo":"hyperpolymath/feedback-o-tron","platforms":["github"],"skip_dedupe":true}}}
JSON

# The send, and only the send. Everything else `gh` may be asked to do is a
# probe, and a probe is not a submission.
count_sends() {
  grep -c '^issue create' "$ghlog" 2>/dev/null || true
}

# One measurement: build the binary on disk, drive the MCP door with nobody at
# the terminal, and report what `gh` was asked to send. Exit status is the
# verdict.
run_probe() {
  : >"$ghlog"
  echo "==> building escript"
  mix escript.build >/dev/null

  echo "==> driving the MCP door with no person present"
  out="$work/response.jsonl"
  env HOME="$fakehome" ./feedback-o-tron serve --no-http <"$req" >"$out" 2>"$work/stderr.log" || true

  sends="$(count_sends | tr -d ' ')"
  echo "==> gh issue create calls: ${sends:-0} (must be 0)"

  probes="$(grep -vc '^issue create' "$ghlog" 2>/dev/null || true)"
  if [ "${probes:-0}" -gt 0 ] 2>/dev/null; then
    echo "==> other gh probes: ${probes} (not sends; ignored by the verdict)"
  fi

  if [ "${sends:-0}" -ne 0 ]; then
    echo "FAIL: the door reached the network. Send calls recorded:"
    grep '^issue create' "$ghlog" | sed 's/^/    gh /'
    return 1
  fi

  if ! grep -q 'drafted_needs_human_consent' "$out"; then
    echo "FAIL: no drafted status in the response. Door answered:"
    sed 's/^/    /' "$out"
    return 1
  fi

  echo "==> door answered: drafted_needs_human_consent"
  echo "PASS: nothing left the machine, and the door said why."
  return 0
}

if [ "$self_test" = false ]; then
  if run_probe; then exit 0; else exit 1; fi
fi

# ---------------------------------------------------------------------------
# Positive control
# ---------------------------------------------------------------------------
# A gate is only as good as the test that can fail. This builds the bypass the
# script exists to catch, and requires the script to catch it. If a mutant
# with its consent check defeated walks through unchallenged, the harness --
# not the engine -- is what is broken, and this exits non-zero saying so.

echo "==> positive control: the harness must fail against a bypassing build"

cp "$submitter" "$work/submitter.ex.orig"

mutant_marker='Consent.redeem(Keyword.get(opts, :consent), issue, opts) == :ok'

if ! grep -qF "$mutant_marker" "$submitter"; then
  echo "FAIL: the mutant marker is not in $submitter." >&2
  echo "      The self-test defeats the gate by rewriting this line; if the" >&2
  echo "      gate has moved, the self-test must move with it, or it is" >&2
  echo "      asserting nothing." >&2
  exit 1
fi

# The bypass: consent is granted whatever the caller hands over. This is the
# shape of the defect this script was written to catch.
python3 - "$submitter" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = 'Consent.redeem(Keyword.get(opts, :consent), issue, opts) == :ok'
assert text.count(old) == 1, "expected exactly one consent check to mutate"
p.write_text(text.replace(old, 'true'))
PY

echo "==> mutant built: the consent check now answers true unconditionally"
if run_probe; then
  echo "FAIL: the harness passed against a build whose gate is defeated." >&2
  echo "      A check that cannot fail is not a check. Fix the harness." >&2
  exit 1
fi
echo "==> mutant killed: the harness failed, as it must"

# Restore the real gate and re-measure, so the last word is about the tree
# that is actually committed.
cp "$work/submitter.ex.orig" "$submitter"
rm -f "$work/submitter.ex.orig"
echo
echo "==> restored: re-running against the real gate"
if run_probe; then real=0; else real=$?; fi

if [ "$real" -ne 0 ]; then
  echo "FAIL: the restored tree does not pass its own consent check." >&2
  exit 1
fi

echo "SELF-TEST PASS: the harness kills a bypassing build and passes the real one."

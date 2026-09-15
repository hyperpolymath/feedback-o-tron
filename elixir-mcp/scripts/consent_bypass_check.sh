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
# PASS: the fake gh was never called AND the door answered "drafted".
# FAIL (exit 1): any gh invocation, or a response that is not drafted.
#
# Usage: scripts/consent_bypass_check.sh     (run from elixir-mcp/)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

work="$(mktemp -d)"
ghlog="$work/gh-calls.log"
: >"$ghlog"

# The built escript is a git-ignored, untracked artefact of this run.
# Remove it however we exit, so a verification run never dirties the tree.
cleanup() {
  rm -rf "$work"
  rm -f feedback-o-tron
}
trap cleanup EXIT

# A `gh` that cannot send, but tells us it was asked to.
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$ghlog"
exit 1
FAKE
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

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
#     gh auth token
#     gh issue create --repo ... --title consent bypass check --body ...   (x3)
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

echo "==> building escript"
mix escript.build >/dev/null

# Two frames, line-delimited JSON-RPC, exactly as an MCP host sends them.
# No dry_run key: this asks the engine to file for real.
req="$work/request.jsonl"
cat >"$req" <<'JSON'
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","id":"call","method":"tools/call","params":{"name":"submit_feedback","arguments":{"title":"consent bypass check","body":"If this text reaches a tracker, the pre-ledger rule is broken.","repo":"hyperpolymath/feedback-o-tron","platforms":["github"],"skip_dedupe":true}}}
JSON

echo "==> driving the MCP door with no person present"
out="$work/response.jsonl"
env HOME="$fakehome" ./feedback-o-tron serve --no-http <"$req" >"$out" 2>"$work/stderr.log" || true

calls="$(wc -l <"$ghlog" | tr -d ' ')"
echo "==> gh invocations: $calls (must be 0)"
if [ "$calls" -ne 0 ]; then
  echo "FAIL: the door reached the network. Calls recorded:"
  sed 's/^/    gh /' "$ghlog"
  exit 1
fi

if ! grep -q 'drafted_needs_human_consent' "$out"; then
  echo "FAIL: no drafted status in the response. Door answered:"
  sed 's/^/    /' "$out"
  exit 1
fi

echo "==> door answered: drafted_needs_human_consent"
echo "PASS: nothing left the machine, and the door said why."

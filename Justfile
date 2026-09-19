# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# feedback-o-tron — development tasks.
# The engine is an Elixir/OTP application under elixir-mcp/.

set shell := ["bash", "-uc"]
set dotenv-load := true

import? "contractile.just"

project := "feedback-o-tron"
engine := "elixir-mcp"

# Show all recipes
default:
    @just --list --unsorted

# Fetch and compile dependencies
deps:
    cd {{engine}} && mix deps.get

# Compile the engine with warnings as errors
build: deps
    cd {{engine}} && mix compile --warnings-as-errors

# Run the test suite (escript tests are excluded; see `just smoke`)
test: deps
    cd {{engine}} && mix test

# Check formatting without changing anything
fmt:
    cd {{engine}} && mix format --check-formatted

# Rewrite sources to canonical format
fmt-write:
    cd {{engine}} && mix format

# Compile clean and check formatting
lint: build fmt

# Build the standalone binary at elixir-mcp/feedback-o-tron
escript: deps
    cd {{engine}} && mix escript.build

# Build the binary, run the end-to-end tests against it, then prove the MCP
# door cannot file anything with nobody present
smoke: escript
    cd {{engine}} && mix test --only escript
    cd {{engine}} && scripts/consent_bypass_check.sh

# Run the engine in the foreground; Ctrl-D on stdin stops it
serve: escript
    {{engine}}/feedback-o-tron serve

# Install the binary to ~/.local/bin
install: escript
    install -Dm755 {{engine}}/feedback-o-tron ~/.local/bin/feedback-o-tron
    @echo "Installed ~/.local/bin/feedback-o-tron"

# Remove build output and the built binary
clean:
    rm -rf {{engine}}/_build {{engine}}/deps {{engine}}/feedback-o-tron

# Build the Guix package defined in guix.scm
guix-build:
    guix build -f build/guix.scm

# Enter a development shell with the toolchain from guix.scm
guix-shell:
    guix shell -f build/guix.scm

# Check the toolchain and report what is missing
doctor:
    #!/usr/bin/env bash
    echo "feedback-o-tron doctor"
    echo
    pass=0; fail=0; warn=0
    ver() {
        case "$1" in
            elixir) elixir --short-version ;;
            erl)    erl -noshell -eval 'io:format("~s~n",[erlang:system_info(otp_release)]), halt().' ;;
            *)      "$1" --version 2>&1 | head -1 ;;
        esac
    }
    probe() {
        local kind="$1" cmd="$2" hint="$3"
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  [ok]   $cmd $(ver "$cmd")"
            pass=$((pass + 1))
        elif [ "$kind" = need ]; then
            echo "  [FAIL] $cmd not found ($hint)"
            fail=$((fail + 1))
        else
            echo "  [warn] $cmd not found ($hint)"
            warn=$((warn + 1))
        fi
    }
    probe need elixir "1.15 or newer"
    probe need erl    "OTP 26 or newer"
    probe need git    "2.40 or newer"
    probe need gh     "GitHub CLI, required to submit issues"
    probe want podman "only for the container image"
    probe want guix   "only for the Guix route"
    echo
    echo "  $pass ok, $fail missing, $warn optional missing"
    if [ "$fail" -gt 0 ]; then
        echo "  Install routes: docs/AI_INSTALLATION_GUIDE.adoc"
        exit 1
    fi

# Run the panic-attacker pre-commit scan if it is installed
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "panic-attack not found — https://github.com/hyperpolymath/panic-attacker"

# Print the current CRG grade (reads '**Current Grade:** X' from READINESS.md)
crg-grade:
    @grade=$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$grade" ] && grade="X"; \
    echo "$grade"

# Generate a shields.io badge for the current CRG grade
crg-badge:
    @grade=$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$grade" ] && grade="X"; \
    case "$grade" in \
      A) color="brightgreen" ;; B) color="green" ;; C) color="yellow" ;; \
      D) color="orange" ;; E) color="red" ;; F) color="critical" ;; \
      *) color="lightgrey" ;; esac; \
    echo "[![CRG $grade](https://img.shields.io/badge/CRG-$grade-$color?style=flat-square)](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)"

secret-scan-trufflehog:
    @command -v trufflehog >/dev/null && trufflehog filesystem . --only-verified || true

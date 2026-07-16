<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# feedback-o-tron ABI/FFI Documentation

This file describes what actually exists, honestly. Three layers, three
different maturity levels:

| Layer | Path | Status |
|---|---|---|
| Verified contract spec (Idris2) | `src/abi/FeedbackOTron/Contract.idr` | **REAL** — compiles, proofs machine-checked, CI-gated |
| Runtime implementation (Elixir) | `elixir-mcp/lib/feedback_a_tron/synthesis/form_validator.ex` | **REAL** — the validator on the live dispatch path |
| C-ABI FFI (Zig) | `ffi/zig/src/main.zig` | **STUB** — scaffolding only, not wired to anything |

## 1. The verified contract spec (Idris2) — REAL

`src/abi/FeedbackOTron/Contract.idr` (package `src/abi/feedback-o-tron.ipkg`,
depends on `base` only) states the form-validation contract once, totally,
and proves that its `validate` function enforces it. It is type-checked in
CI by `.github/workflows/proofs.yml` on every push/PR touching `src/abi/**`,
under pinned Idris2 0.7.0.

The model:

- `Field` — `fieldId`, `label`, `required : Bool`, `options : List String`,
  `fieldKind` (`Input | Textarea | Dropdown | Checkboxes | Markdown`)
- `Form` — a list of `Field`s
- `Answers` — `List (String, String)` (field id ↦ answer text)
- `Violation` — `RequiredMissing fieldId | UnknownField key | InvalidOption fieldId value`
- `validate : Form -> Answers -> Either (List Violation) ValidPayload`

The central safety device is `ValidPayload`: its data constructor is
**private** (the type is `export`, the constructor is not), so the only way
to obtain a `ValidPayload` is to get `validate` to say `Right`. Holding one
is machine-checked evidence the gate passed. `getAnswers : ValidPayload ->
Answers` reads the validated answers back out.

### Proved lemmas (no `believe_me`, no `postulate`, no `assert_total`)

Everything is `%default total`; the trusted base is **empty** and CI enforces
that with a source audit (`trusted-base` job in `proofs.yml`).

| Lemma | Statement |
|---|---|
| `validCompleteness` | `IsRight (validate f a)` → `AllRequiredAnswered f a` (Bool-reflection: `allRequiredAnswered f a = True`) — a successful validate means every required non-markdown field was answered |
| `validNoUnknownFields` | `IsRight (validate f a)` → `noUnknownFields f a = True` — no answer key outside the form's non-markdown field ids |
| `validOptionsValid` | `IsRight (validate f a)` → `allOptionsValid f a = True` — every dropdown answer is one of its field's options |
| `validGate` | `IsRight (validate f a)` → `checksPass f a = True` (the master gate; the three above are its `&&`-eliminations) |
| `checksPassValidates` | converse: `checksPass f a = True` → `IsRight (validate f a)` — validate is pinned to the boolean spec in both directions |
| `validateAnswersPreserved` | `validate f a = Right vp` → `getAnswers vp = a` — validate never invents or drops answers |
| `emptyFormEmptyAnswersOk` | sanity witness: the empty form with no answers validates |

The proofs are deliberately by-inspection: `validate` is *defined via* the
boolean reflection (`validateGo (checksPass f a) (violations f a) a`), so the
lemmas follow by case analysis and `&&`-elimination, not heroics.

Check locally:

```bash
cd src/abi
idris2 --typecheck feedback-o-tron.ipkg
```

## 2. The runtime implementation (Elixir) — REAL

`FeedbackATron.Synthesis.FormValidator.validate/2` is the runtime
implementation of the same contract, on the live synthesis/dispatch path.
The correspondence, field by field:

| Contract (Idris2) | Runtime (Elixir) | Meaning |
|---|---|---|
| `RequiredMissing fieldId` | `%{error: :required_missing}` | a required field is unanswered (Elixir also treats a whitespace-only answer, or an empty checkbox list, as missing) |
| `UnknownField key` | `%{error: :unknown_field}` | an answer key that is not a non-markdown field id of the form |
| `InvalidOption fieldId value` | `%{error: :invalid_option}` | a dropdown answer that is not one of the field's declared options |
| — (unrepresentable: `Answers` is typed `List (String, String)`) | `%{error: :not_a_string}` | a non-string answer value; the Idris contract rules this out by type, the dynamically-typed runtime must check it |
| markdown fields excluded from `knownFields` | markdown fields rejected from `known_fields`, answers to them are `:unknown_field` | markdown blocks are display-only |
| `Left` collects **all** violations (required first in form order, then options, then unknown keys) | `{:error, errors}` collects all violations (form-order field errors, then sorted unknown keys) | nothing fails fast; the caller sees the whole picture |
| `Right ValidPayload` (private constructor) | `:ok` | gate passed |

Divergences to know about (deliberate, documented rather than hidden):

- The Elixir validator trims whitespace before deciding blankness; the Idris
  spec models blankness as `v /= ""` without trimming.
- Checkbox answers are lists in Elixir; the Idris spec models all answers as
  strings, so checkbox-list type checks live only in the runtime.
- Nothing *mechanically* connects the two today — the Elixir module mirrors
  the spec by construction and code review, not by extraction. See §4.

## 3. The Zig FFI — STUB

`ffi/zig/src/main.zig` is **scaffolding, not a working FFI**. It exports
generic `feedback_o_tron_init/free/process`-style lifecycle functions and
refers in comments to `src/abi/Types.idr` and `src/abi/Foreign.idr`, which
**do not exist** — the real Idris module is `FeedbackOTron/Contract.idr` and
no C headers are generated from it. Nothing in the running system calls this
library. It is kept as the intended shape of a future C-ABI surface and must
not be described as functional until it is.

## 4. What full enforcement would look like (not built yet)

The honest end state is an Idris-derived validator on the dispatch path —
either code generated from `Contract.idr` (via a C library that the Zig FFI
wraps and Elixir calls through a NIF/port), or a conformance test suite
generated from the spec that the Elixir validator must pass in CI. Until
then, the guarantee chain is: spec proved (Idris, CI-gated) → implementation
mirrors spec (review + unit tests). Full FFI enforcement is tracked in a
follow-up issue: (follow-up issue: filed at PR time).

## License

- Code: MPL-2.0
- This document: CC-BY-SA-4.0

## See Also

- `src/abi/FeedbackOTron/Contract.idr` — the contract, with per-lemma docs
- `.github/workflows/proofs.yml` — the CI gate (type-check + trusted-base audit)
- `elixir-mcp/lib/feedback_a_tron/synthesis/form_validator.ex` — the runtime validator
- [Idris2 documentation](https://idris2.readthedocs.io)

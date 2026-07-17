-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
||| FeedbackOTron.Contract: the verified validation contract for issue-form
||| submissions.
|||
||| This module is the CONTRACT SPEC for
||| `FeedbackATron.Synthesis.FormValidator` (Elixir, elixir-mcp/): a form's
||| answers are only fileable when every required field is answered, every
||| answer key names a known non-markdown field, and every dropdown answer
||| is one of the field's declared options. The Elixir module is the runtime
||| implementation; this module states the rules once, totally, and proves
||| that `validate` enforces them.
|||
||| The central safety device is `ValidPayload`: its data constructor is
||| private, so the ONLY way to obtain one is through `validate`. Code that
||| holds a `ValidPayload` therefore holds machine-checked evidence that all
||| three rule families passed.
|||
||| Trusted base: none. No believe_me, no postulate, no assert_total.
||| Everything below is `%default total` and structurally recursive.
module FeedbackOTron.Contract

%default total

--------------------------------------------------------------------------------
-- Model: fields, forms, answers, violations
--------------------------------------------------------------------------------

||| The kind of a GitHub issue-form field
||| (mirrors `TemplateFetcher` field `type`: :input | :textarea | :dropdown
||| | :checkboxes | :markdown).
public export
data FieldKind
  = Input       -- single-line text
  | Textarea    -- multi-line text
  | Dropdown    -- one answer, constrained to `options`
  | Checkboxes  -- zero or more ticked boxes
  | Markdown    -- display-only; never answered, never required

||| One field of a parsed issue form.
public export
record Field where
  constructor MkField
  fieldId   : String
  label     : String
  required  : Bool
  options   : List String
  fieldKind : FieldKind

||| A parsed issue form: an ordered list of fields.
public export
record Form where
  constructor MkForm
  fields : List Field

||| A validation violation, mirroring the Elixir error atoms one-for-one:
|||   RequiredMissing fieldId       <-> :required_missing
|||   UnknownField    key           <-> :unknown_field
|||   InvalidOption   fieldId value <-> :invalid_option
||| (:not_a_string has no counterpart here: `Answers` is typed
||| `List (String, String)`, so a non-string answer is a type error,
||| not a runtime violation.)
public export
data Violation
  = RequiredMissing String
  | UnknownField String
  | InvalidOption String String

||| Answers as an association list from field id to answer text.
public export
Answers : Type
Answers = List (String, String)

--------------------------------------------------------------------------------
-- Boolean checks (the reflection layer the proofs run over)
--------------------------------------------------------------------------------

||| Recursive `all` — structurally obvious, easy to reason about.
public export
allRec : (a -> Bool) -> List a -> Bool
allRec p [] = True
allRec p (x :: xs) = p x && allRec p xs

||| Look up the answer for a field id.
public export
lookupAnswer : String -> Answers -> Maybe String
lookupAnswer k [] = Nothing
lookupAnswer k ((k', v) :: rest) =
  if k == k' then Just v else lookupAnswer k rest

||| Markdown blocks are display-only: excluded from validation entirely
||| (the Elixir validator likewise rejects markdown ids as :unknown_field).
public export
isMarkdown : Field -> Bool
isMarkdown fld = case fieldKind fld of
                   Markdown => True
                   _ => False

||| The fields that participate in validation: everything but markdown.
public export
knownFields : Form -> List Field
knownFields frm = go (fields frm)
  where
    go : List Field -> List Field
    go [] = []
    go (fld :: rest) =
      if isMarkdown fld then go rest else fld :: go rest

||| Membership test for a string in a list of strings.
public export
hasString : String -> List String -> Bool
hasString s [] = False
hasString s (x :: xs) = s == x || hasString s xs

||| A field counts as answered when an answer exists and is non-empty.
||| (The Elixir side additionally trims whitespace; a blank answer is
||| treated as missing there too.)
public export
answered : Answers -> Field -> Bool
answered a fld = case lookupAnswer (fieldId fld) a of
                   Nothing => False
                   Just v => v /= ""

||| Rule 1, per field: a required field must be answered.
public export
requiredOk : Answers -> Field -> Bool
requiredOk a fld = if required fld then answered a fld else True

||| Rule 1, per form: every required (non-markdown) field is answered.
||| This is the Bool-reflection that `AllRequiredAnswered` wraps.
public export
allRequiredAnswered : Form -> Answers -> Bool
allRequiredAnswered frm a = allRec (requiredOk a) (knownFields frm)

||| Rule 2, per form: every answer key names a known non-markdown field.
public export
noUnknownFields : Form -> Answers -> Bool
noUnknownFields frm a =
  allRec (\kv => hasString (fst kv) (map fieldId (knownFields frm))) a

||| Rule 3, per field: a dropdown answer must be one of the options.
public export
optionOk : Answers -> Field -> Bool
optionOk a fld = case fieldKind fld of
                   Dropdown => case lookupAnswer (fieldId fld) a of
                                 Nothing => True
                                 Just v => hasString v (options fld)
                   _ => True

||| Rule 3, per form.
public export
allOptionsValid : Form -> Answers -> Bool
allOptionsValid frm a = allRec (optionOk a) (knownFields frm)

||| The whole gate: validate succeeds exactly when this is True.
public export
checksPass : Form -> Answers -> Bool
checksPass frm a =
  allRequiredAnswered frm a && (noUnknownFields frm a && allOptionsValid frm a)

--------------------------------------------------------------------------------
-- Violation reporting (the Left side of validate)
--------------------------------------------------------------------------------

||| Concatenating flat-map, defined recursively for obvious totality.
public export
collect : (a -> List b) -> List a -> List b
collect g [] = []
collect g (x :: xs) = g x ++ collect g xs

||| RequiredMissing violations, in form order.
public export
requiredViolations : Form -> Answers -> List Violation
requiredViolations frm a =
  collect (\fld => if requiredOk a fld
                      then []
                      else [RequiredMissing (fieldId fld)])
          (knownFields frm)

||| UnknownField violations, in answer order.
public export
unknownViolations : Form -> Answers -> List Violation
unknownViolations frm a =
  collect (\kv => if hasString (fst kv) (map fieldId (knownFields frm))
                     then []
                     else [UnknownField (fst kv)])
          a

||| InvalidOption violations, in form order.
public export
optionViolations : Form -> Answers -> List Violation
optionViolations frm a = collect report (knownFields frm)
  where
    report : Field -> List Violation
    report fld = case fieldKind fld of
                   Dropdown => case lookupAnswer (fieldId fld) a of
                                 Nothing => []
                                 Just v => if hasString v (options fld)
                                              then []
                                              else [InvalidOption (fieldId fld) v]
                   _ => []

||| All violations: field errors first (form order), then unknown keys —
||| the same ordering the Elixir validator documents.
public export
violations : Form -> Answers -> List Violation
violations frm a =
  requiredViolations frm a ++ optionViolations frm a ++ unknownViolations frm a

--------------------------------------------------------------------------------
-- ValidPayload: evidence of a passed gate, unconstructable outside validate
--------------------------------------------------------------------------------

||| A payload that passed validation. The constructor is NOT exported
||| (plain `export`, not `public export`): outside this module the only
||| source of a ValidPayload is `validate`.
export
data ValidPayload : Type where
  MkValidPayload : Answers -> ValidPayload

||| Read the validated answers back out.
export
getAnswers : ValidPayload -> Answers
getAnswers (MkValidPayload a) = a

--------------------------------------------------------------------------------
-- validate
--------------------------------------------------------------------------------

||| The decision core, split out so the lemmas below follow by inspection:
||| Right exactly when the boolean gate is True.
public export
validateGo : Bool -> List Violation -> Answers ->
             Either (List Violation) ValidPayload
validateGo True  _  a = Right (MkValidPayload a)
validateGo False vs _ = Left vs

||| Validate answers against a form. Succeeds (Right) exactly when
||| `checksPass frm a = True`; otherwise reports every violation found.
export
validate : Form -> Answers -> Either (List Violation) ValidPayload
validate frm a = validateGo (checksPass frm a) (violations frm a) a

--------------------------------------------------------------------------------
-- Lemmas
--------------------------------------------------------------------------------

||| Witness that an Either is a Right.
public export
data IsRight : Either e r -> Type where
  ItIsRight : IsRight (Right x)

||| The reflection wrapper the completeness lemma promises: the proposition
||| "every required field of `f` is answered in `a`", stated as the Boolean
||| check having evaluated to True.
public export
AllRequiredAnswered : Form -> Answers -> Type
AllRequiredAnswered frm a = allRequiredAnswered frm a = True

||| Left-elimination for (&&): if a conjunction is True, so is its left arm.
export
andElimLeft : (x, y : Bool) -> (x && y) = True -> x = True
andElimLeft True  y prf = Refl
andElimLeft False y prf = absurd prf

||| Right-elimination for (&&).
export
andElimRight : (x, y : Bool) -> (x && y) = True -> y = True
andElimRight True  y prf = prf
andElimRight False y prf = absurd prf

||| validateGo only answers Right when its gate is True.
export
validateGoTrue : (b : Bool) -> (vs : List Violation) -> (a : Answers) ->
                 IsRight (validateGo b vs a) -> b = True
validateGoTrue True  vs a p = Refl
validateGoTrue False vs a p impossible

||| If validate succeeded, the whole gate was True.
export
validGate : (f : Form) -> (a : Answers) ->
            IsRight (validate f a) -> checksPass f a = True
validGate f a p = validateGoTrue (checksPass f a) (violations f a) a p

||| COMPLETENESS: a successful validate implies every required field was
||| answered. Follows by inspection of validate's gate.
export
validCompleteness : (f : Form) -> (a : Answers) ->
                    (p : IsRight (validate f a)) ->
                    AllRequiredAnswered f a
validCompleteness f a p =
  andElimLeft (allRequiredAnswered f a)
              (noUnknownFields f a && allOptionsValid f a)
              (validGate f a p)

||| A successful validate implies no unknown answer keys.
export
validNoUnknownFields : (f : Form) -> (a : Answers) ->
                       IsRight (validate f a) -> noUnknownFields f a = True
validNoUnknownFields f a p =
  andElimLeft (noUnknownFields f a) (allOptionsValid f a)
    (andElimRight (allRequiredAnswered f a)
                  (noUnknownFields f a && allOptionsValid f a)
                  (validGate f a p))

||| A successful validate implies every dropdown answer was a listed option.
export
validOptionsValid : (f : Form) -> (a : Answers) ->
                    IsRight (validate f a) -> allOptionsValid f a = True
validOptionsValid f a p =
  andElimRight (noUnknownFields f a) (allOptionsValid f a)
    (andElimRight (allRequiredAnswered f a)
                  (noUnknownFields f a && allOptionsValid f a)
                  (validGate f a p))

||| SOUNDNESS (converse): if the boolean gate holds, validate succeeds.
||| Together with validGate this pins validate to the spec exactly.
export
checksPassValidates : (f : Form) -> (a : Answers) ->
                      checksPass f a = True -> IsRight (validate f a)
checksPassValidates f a prf =
  replace {p = \b => IsRight (validateGo b (violations f a) a)}
          (sym prf) ItIsRight

||| validate never invents answers: the payload carries exactly the
||| answers that were validated.
export
validateAnswersPreserved : (f : Form) -> (a : Answers) ->
                           (vp : ValidPayload) ->
                           validate f a = Right vp -> getAnswers vp = a
validateAnswersPreserved f a vp prf =
  go (checksPass f a) (violations f a) vp prf
  where
    go : (b : Bool) -> (vs : List Violation) -> (vp' : ValidPayload) ->
         validateGo b vs a = Right vp' -> getAnswers vp' = a
    go True  vs _ Refl = Refl
    go False vs _ prf' impossible

||| Sanity witness: the empty form with no answers validates.
export
emptyFormEmptyAnswersOk : IsRight (Contract.validate (MkForm []) [])
emptyFormEmptyAnswersOk = ItIsRight

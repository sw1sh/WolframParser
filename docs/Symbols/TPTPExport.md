---
Template: Symbol
Name: TPTPExport
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/TPTPExport
Keywords: [tptp, theorem prover, atp, automated reasoning, szs, derivation, proof, cnf, export, serialize]
SeeAlso: [TPTPImport, EBNFParse, Parse, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[TPTPExport]()[*derivation*]</code> renders an SZS-output *derivation* [Association]() back to SZS-framed TPTP text — the inverse of <code>[TPTPImport]()[*source*, "SZS"]</code>.

## Details & Options

- *derivation* is an [Association]() carrying a `"Derivation"` — a list of step records — and optional `"Status"`, `"Problem"`, and `"OutputForm"` framing keys. Each step is <code>[Association]()[{"Head", "Name", "Role", "Formula", "Rule", "Status", "Parents", …}]</code>, the record [TPTPImport]() returns for each clause in `"SZS"` mode.
- The result is a [String]() of SZS-framed TPTP text, one clause per line, ending in a newline.
- The `% SZS status …` line is emitted when `"Status"` is a string; the `% SZS output start …` / `% SZS output end …` markers when `"OutputForm"` is a string. `"Problem"` supplies the trailing problem name and defaults to `unknown`.
- Each step renders as `head(name, role, formula, source).`.
- An inference step re-renders structurally from its `"Rule"`, `"Status"`, and `"Parents"` fields as `inference(rule, [status(...)], [parents])`; a missing status leaves an empty `[]`.
- Any other source — a `file(...)` axiom, an `introduced(...)` clause — is reproduced verbatim from the step's retained `"RawSource"`. A step with neither an inference rule nor a `"RawSource"` renders with no source annotation.
- Formula bodies re-render through the inverse of the [TPTPImport]() action map: [Equal]() / [Unequal]() to `=` / `!=`, [Not]() to `~`, [And]() / [Or]() to `&` / `|`, [Implies]() to `=>`, [Equivalent]() to `<=>`, [Xor]() to `<~>`, [True]() / [False]() to `$true` / `$false`; a String-headed compound `"f"[a, b]` to `f(a, b)` and a nullary `"c"[]` to `c`. A compound subformula of a connective is parenthesized.
- A clause body the SZS reader kept as raw source text (one it does not lift to a Wolfram formula) is emitted unchanged.
- Round-trip: for a *derivation* obtained from [TPTPImport](), <code>[TPTPImport]()[[TPTPExport]()[*derivation*], "SZS"]</code> reproduces it.

## Basic Examples

Import a small SZS refutation, then render it back — the framing, the clauses, and the inference records all return:

```wl
szsText = "% SZS status Unsatisfiable for GRP001
% SZS output start Refutation for GRP001
cnf(left_id, axiom, mult(e, X) = X, file('GRP001.p', left_id)).
cnf(goal, plain, mult(a, b) = c, inference(superposition, [status(thm)], [left_id])).
cnf(bot, plain, $false, inference(cr, [status(thm)], [goal])).
% SZS output end Refutation for GRP001";
szs = TPTPImport[szsText, "SZS"];
TPTPExport[szs]
```

<!-- => "% SZS status Unsatisfiable for GRP001\n% SZS output start Refutation for GRP001\ncnf(left_id, axiom, mult(e, X) = X, file('GRP001.p', left_id)).\ncnf(goal, plain, mult(a, b) = c, inference(superposition, [status(thm)], [left_id])).\ncnf(bot, plain, $false, inference(cr, [status(thm)], [goal])).\n% SZS output end Refutation for GRP001\n" -->

<!-- #| annotation: 26.07.26: Design review - TPTPExport is the serializer inverse of TPTPImport[src, "SZS"], keyed to exactly what that reader produces rather than being a complete TPTP/TSTP writer. Two reconstruction paths keep the round-trip exact without modelling every annotation grammar: inference steps re-render structurally from their {Rule, Status, Parents} fields, while any other source (file(...), introduced(...)) is reproduced verbatim from the step's retained "RawSource" - so read-then-emit is identity on the fields the reader captured. Formula bodies re-render through the inverse of the ~50-entry import action map (formulaToTPTP: Equal/Unequal, And/Or/Not/Implies/Equivalent/Xor, $true/$false, and String-headed compounds f(a,b) / c), and a clause body the SZS reader left as raw source text is echoed unchanged. The framing (% SZS status / output start / end) is emitted only for the keys present, so a bare {"Derivation" -> ...} yields unframed clauses. -->

---

Because the reader captures every field the writer needs, an import followed by an export and re-import round-trips exactly:

```wl
TPTPImport[TPTPExport[szs], "SZS"]["Derivation"] === szs["Derivation"]
```

<!-- => True -->

## Scope

A derivation can be built by hand. With only a `"Derivation"` and no framing keys, the result is bare clauses — no `% SZS` lines:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "cnf", "Name" -> "a", "Role" -> "axiom",
     "Formula" -> ("mult"["e"[], X_] == X_)|>}|>]
```

<!-- => "cnf(a, axiom, mult(e, X) = X).\n" -->

---

Supplying `"Status"` and `"Problem"` adds the SZS status line:

```wl
TPTPExport[<|"Status" -> "Theorem", "Problem" -> "P", "Derivation" -> {
   <|"Head" -> "fof", "Name" -> "a", "Role" -> "axiom", "Formula" -> "p"[]|>}|>]
```

<!-- => "% SZS status Theorem for P\nfof(a, axiom, p).\n" -->

---

An inference step reconstructs its `inference(...)` source from the `"Rule"`, `"Status"`, and `"Parents"` fields:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "cnf", "Name" -> "d", "Role" -> "plain",
     "Formula" -> Or["p"[X_], "q"[X_], Not["r"[X_]]],
     "Rule" -> "split", "Status" -> "thm", "Parents" -> {"c1"}|>}|>]
```

<!-- => "cnf(d, plain, p(X) | q(X) | ~r(X), inference(split, [status(thm)], [c1])).\n" -->

---

A step with parents but no `"Status"` leaves the status list empty:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "cnf", "Name" -> "c", "Role" -> "plain",
     "Formula" -> ("p"["a"[]] != "b"[]),
     "Rule" -> "resolution", "Parents" -> {"3", "5"}|>}|>]
```

<!-- => "cnf(c, plain, p(a) != b, inference(resolution, [], [3, 5])).\n" -->

### Formula rendering

The Boolean connectives map back to their TPTP tokens — [And]() to `&`:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "fof", "Name" -> "a", "Role" -> "axiom",
     "Formula" -> And["p"[], "q"[], "r"[]]|>}|>]
```

<!-- => "fof(a, axiom, p & q & r).\n" -->

---

A compound subformula of a connective is parenthesized, so [Implies]() of an [And]() keeps the grouping:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "fof", "Name" -> "a", "Role" -> "axiom",
     "Formula" -> Implies[And["p"[], "q"[]], "r"[]]|>}|>]
```

<!-- => "fof(a, axiom, (p & q) => r).\n" -->

---

The empty clause [False]() renders as `$false`:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "cnf", "Name" -> "bot", "Role" -> "plain", "Formula" -> False,
     "Rule" -> "cr", "Status" -> "thm", "Parents" -> {"goal"}|>}|>]
```

<!-- => "cnf(bot, plain, $false, inference(cr, [status(thm)], [goal])).\n" -->

## Properties and Relations

[TPTPImport]() in `"SZS"` mode is the reader and [TPTPExport]() the writer. A `file(...)`-sourced axiom is not reconstructed from fields — it is echoed from the `"RawSource"` the reader retained — so the imported step exports with its `file(...)` annotation intact:

```wl
TPTPExport[<|"Derivation" -> {
   SelectFirst[szs["Derivation"], #["Name"] === "left_id" &]}|>]
```

<!-- => "cnf(left_id, axiom, mult(e, X) = X, file('GRP001.p', left_id)).\n" -->

## Possible Issues

A non-inference source survives only through `"RawSource"`. A hand-built step whose `"Rule"` is `"file"` but that carries no `"RawSource"` renders with the source annotation dropped:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "cnf", "Name" -> "a", "Role" -> "axiom",
     "Formula" -> ("mult"["e"[], X_] == X_), "Rule" -> "file", "Parents" -> {}|>}|>]
```

<!-- => "cnf(a, axiom, mult(e, X) = X).\n" -->

---

A `"Formula"` given as raw source text is emitted verbatim — the way the SZS reader represents a clause body it does not lift — so a quantified body passes straight through:

```wl
TPTPExport[<|"Derivation" -> {
   <|"Head" -> "fof", "Name" -> "a", "Role" -> "axiom",
     "Formula" -> "! [X] : big(X)"|>}|>]
```

<!-- => "fof(a, axiom, ! [X] : big(X)).\n" -->

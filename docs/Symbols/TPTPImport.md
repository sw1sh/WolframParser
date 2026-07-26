---
Template: Symbol
Name: TPTPImport
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/TPTPImport
Keywords: [tptp, theorem prover, atp, automated reasoning, cnf, fof, thf, szs, first-order logic, import]
SeeAlso: [TPTPExport, EBNFParse, Parse, ParseOperatorTable, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[TPTPImport]()[[File]()[*path*]]</code> parses a TPTP (Thousands of Problems for Theorem Provers) problem file into an [Association]() of its axioms and conjecture.

<code>[TPTPImport]()[*source*]</code> parses TPTP source given directly as a string.

<code>[TPTPImport]()[*source*, "SZS"]</code> reads an SZS-output derivation instead, returning its status and proof steps.

## Details & Options

- The default result partitions the problem into `"Axioms"` — the formulas of the `axiom` and `hypothesis` clauses — and `"Conjecture"`, the goal of a `conjecture` clause, or a `negated_conjecture` flipped through [Not]() so the returned goal is positive, or [None]() when there is none.
- Function and predicate symbols return as String-headed compounds: `"multiply"[x, y]`, `"p"[x]`, a constant as `"c"[]`. A parsed symbol therefore cannot collide with a Wolfram Language binding, and an equational atom stays symbolic instead of eagerly evaluating.
- Variables return as <code>[Pattern]()[*name*, [Blank]()[]]</code>, rendering as `X_`.
- Quantifiers `!` and `?` lift to [ForAll]() and [Exists](); the Boolean connectives to [And](), [Or](), [Not](), [Implies](), [Equivalent](), and [Xor](); the equational atoms `=` and `!=` to [Equal]() and [Unequal]().
- The clause heads `cnf`, `fof`, and `thf` lift to Wolfram Language formulas; `tff` and `tcf` clauses are recognized and partitioned but their formula bodies may come back as the raw parse tree; a `tpi` clause is skipped.
- THF connectives (`@`, `&`, `|`, `<=>`, …) are parsed through [ParseOperatorTable](), which stays linear where an ordered-choice cascade over the shared operand would backtrack exponentially.
- The top-level universal quantifier of a clause is dropped — a clause is read under its implicit universal closure — while inner quantifiers are kept.
- `$true` and `$false` map to [True]() and [False](); other `$`-defined atoms keep their token (`$sum`, `$distinct`).
- `include('path')` directives resolve recursively against the directory of the including file, then the `$TPTP` and `$TPTP/Problems` environment roots. A selector `include('path', [a, b])` admits only the named clauses.
- In `"SZS"` mode the `"Derivation"` value is a list of step records <code>[Association]()[{"Head", "Name", "Role", "Formula", "Rule", "Status", "Parents", …}]</code>; this mode is the inverse of [TPTPExport]().
- The parser is built once per kernel session by [EBNFParse]() from the published TPTPWorld `SyntaxBNF` grammar plus an action map; the grammar is fetched on the first call.

## Basic Examples

Import a small first-order (`fof`) formula; the propositional axiom `p => q` lifts to [Implies]():

```wl
TPTPImport["fof(a, axiom, p => q)."]
```

<!-- => <|"Axioms" -> {Implies["p"[], "q"[]]}, "Conjecture" -> None|> -->

<!-- #| annotation: 26.07.26: Design review - TPTPImport is the worked end-to-end consumer of EBNFParse: the recogniser is generated from the published TPTP SyntaxBNF and only the ~50-entry action map that lifts the raw tree to Wolfram terms is hand-written, so a spec bump is a re-fetch, not a per-rule code diff. Two representation choices are deliberate. Function/predicate symbols are String-headed compounds ("p"[X_], "c"[]) rather than interned Symbols, so a parsed name can never collide with a Global binding and an equational atom like "and"[a, b] == "c" stays symbolic instead of evaluating to False. Variables are Pattern[name, Blank[]] so they print as X_ and slot into WL pattern machinery. Positioned against a bespoke recursive-descent TPTP reader (the ~1100-line sibling reference), this trades some THF completeness for staying in lockstep with the grammar file; THF connectives route through ParseOperatorTable to avoid the exponential ordered-choice blow-up. -->

---

Predicate and function symbols return as String-headed compounds and variables as `X_`; the implicit top-level universal quantifier is dropped:

```wl
TPTPImport["fof(comm, axiom, ! [X, Y] : mult(X, Y) = mult(Y, X))."]
```

<!-- => <|"Axioms" -> {"mult"[X_, Y_] == "mult"[Y_, X_]}, "Conjecture" -> None|> -->

---

A clause-normal-form (`cnf`) axiom lifts the same way:

```wl
TPTPImport["cnf(a, axiom, and(X, Y) = and(Y, X))."]
```

<!-- => <|"Axioms" -> {"and"[X_, Y_] == "and"[Y_, X_]}, "Conjecture" -> None|> -->

---

A `conjecture` clause lands in the `"Conjecture"` slot instead of `"Axioms"`:

```wl
TPTPImport["fof(goal, conjecture, ! [X] : p(X))."]
```

<!-- => <|"Axioms" -> {}, "Conjecture" -> "p"[X_]|> -->

## Scope

A multi-clause problem — the axioms collect into a list and the conjecture is separated out:

```wl
TPTPImport["fof(assoc, axiom, ! [X, Y, Z] : mult(mult(X, Y), Z) = mult(X, mult(Y, Z))).
fof(left_id, axiom, ! [X] : mult(e, X) = X).
fof(goal, conjecture, ! [X] : mult(X, e) = X)."]
```

<!-- => <|"Axioms" -> {"mult"["mult"[X_, Y_], Z_] == "mult"[X_, "mult"[Y_, Z_]], "mult"["e"[], X_] == X_}, "Conjecture" -> "mult"[X_, "e"[]] == X_|> -->

---

Import from a file with [File]():

```wl
probPath = FileNameJoin[{$TemporaryDirectory, "group.p"}];
Export[probPath,
    "cnf(comm, axiom, mult(X, Y) = mult(Y, X)).
cnf(goal, negated_conjecture, mult(a, b) != mult(b, a)).", "Text"];
TPTPImport[File[probPath]]
```

<!-- => <|"Axioms" -> {"mult"[X_, Y_] == "mult"[Y_, X_]}, "Conjecture" -> "mult"["a"[], "b"[]] == "mult"["b"[], "a"[]]|> -->

---

A `negated_conjecture` is flipped through [Not]() — here [Unequal]() becomes [Equal]() — so the returned goal is positive:

```wl
TPTPImport["cnf(g, negated_conjecture, foo(sk) != sk)."]
```

<!-- => <|"Axioms" -> {}, "Conjecture" -> "foo"["sk"[]] == "sk"[]|> -->

### Boolean connectives and quantifiers

`&` maps to [And]():

```wl
TPTPImport["fof(a, axiom, p & q & r)."]["Axioms"]
```

<!-- => {"p"[] && "q"[] && "r"[]} -->

---

`<=>` maps to [Equivalent]():

```wl
TPTPImport["fof(a, axiom, p <=> q)."]["Axioms"]
```

<!-- => {Equivalent["p"[], "q"[]]} -->

---

`?` maps to [Exists]():

```wl
TPTPImport["fof(a, axiom, ? [X] : p(X))."]["Axioms"]
```

<!-- => {Exists[{X_}, "p"[X_]]} -->

---

A cnf disjunction with a negative literal becomes an [Or]() of the literals:

```wl
TPTPImport["cnf(a, axiom, p(X) | q(X) | ~r(X))."]["Axioms"]
```

<!-- => {"p"[X_] || "q"[X_] || ! "r"[X_]} -->

### Term-level atoms

A single-quoted atom keeps its text as one symbol, spaces and all:

```wl
TPTPImport["cnf(a, axiom, eq(a, 'hello world'))."]["Axioms"]
```

<!-- => {"eq"["a"[], "hello world"[]]} -->

---

`$true` and `$false` map to the Boolean constants:

```wl
TPTPImport["fof(a, axiom, $true)."]["Axioms"]
```

<!-- => {True} -->

### Includes

`include` pulls axioms from another file, resolved relative to the including file:

```wl
incDir = CreateDirectory[];
Export[FileNameJoin[{incDir, "ax.ax"}],
    "cnf(a1, axiom, mult(X, e) = X).
cnf(a2, axiom, mult(e, X) = X).", "Text"];
Export[FileNameJoin[{incDir, "main.p"}],
    "include('ax.ax').
cnf(g, negated_conjecture, mult(a, b) != c).", "Text"];
TPTPImport[File @ FileNameJoin[{incDir, "main.p"}]]
```

<!-- => <|"Axioms" -> {"mult"[X_, "e"[]] == X_, "mult"["e"[], X_] == X_}, "Conjecture" -> "mult"["a"[], "b"[]] == "c"[]|> -->

---

A clause-name selector admits only the listed clauses of the included file:

```wl
Export[FileNameJoin[{incDir, "one.p"}], "include('ax.ax', [a1]).", "Text"];
TPTPImport[File @ FileNameJoin[{incDir, "one.p"}]]
```

<!-- => <|"Axioms" -> {"mult"[X_, "e"[]] == X_}, "Conjecture" -> None|> -->

## Properties and Relations

Because symbols are String-headed compounds, an equational atom over distinct constants stays symbolic rather than evaluating to [False]():

```wl
TPTPImport["cnf(a, axiom, and(a, b) = c)."]["Axioms"]
```

<!-- => {"and"["a"[], "b"[]] == "c"[]} -->

### SZS derivations

In `"SZS"` mode the status line, problem name, and output form are read out of the derivation framing:

```wl
szsText = "% SZS status Unsatisfiable for GRP001-4
% SZS output start CNFRefutation for GRP001-4
cnf(associativity, axiom, multiply(multiply(X,Y),Z) = multiply(X,multiply(Y,Z)), file('GRP001-4.p', associativity)).
cnf(left_identity, axiom, multiply(identity,X) = X, file('GRP001-4.p', left_identity)).
cnf(c7, plain, multiply(a,b) = c, inference(superposition, [status(thm)], [associativity, left_identity])).
cnf(c12, plain, $false, inference(cr, [status(thm)], [c7, prove_goal])).
% SZS output end CNFRefutation for GRP001-4";
szs = TPTPImport[szsText, "SZS"];
szs["Status"]
```

<!-- => "Unsatisfiable" -->

---

The `"Derivation"` value is the list of proof steps:

```wl
Length @ szs["Derivation"]
```

<!-- => 4 -->

---

Each step carries its parsed formula and, for an inference, the rule, status, and parent names:

```wl
SelectFirst[szs["Derivation"], #["Name"] === "c7" &]
```

<!-- => <|"Head" -> "cnf", "Name" -> "c7", "Role" -> "plain", "Formula" -> "multiply"["a"[], "b"[]] == "c"[], "Rule" -> "superposition", "Status" -> "thm", "Parents" -> {"associativity", "left_identity"}, "RawSource" -> "inference(superposition, [status(thm)], [associativity, left_identity])"|> -->

---

[TPTPExport]() renders a derivation back to SZS-framed text, so an export followed by a re-import round-trips:

```wl
TPTPImport[TPTPExport[szs], "SZS"]["Derivation"] === szs["Derivation"]
```

<!-- => True -->

## Possible Issues

Source that does not match the grammar emits a `TPTPImport::badparse` message and returns [$Failed]():

```wl
TPTPImport["this is not tptp at all"]
```

<!-- => $Failed  (with a TPTPImport::badparse message) -->

---

`tff` and `tcf` clauses are partitioned by role, but their formula bodies are not yet lifted to Wolfram terms — the body comes back as the raw parse-tree token list:

```wl
TPTPImport["tff(ax, axiom, p(a))."]["Axioms"]
```

<!-- => {{"p", "(", {"a"[], {}}, ")"}} -->

## Neat Examples

A higher-order (`thf`) formula: curried application `p @ a` lifts to `"p"[]["a"[]]`, and the `&` / `=>` connectives are parsed by the [ParseOperatorTable]() the THF grammar installs:

```wl
TPTPImport["thf(a, axiom, p @ a)."]
```

<!-- => <|"Axioms" -> {"p"[]["a"[]]}, "Conjecture" -> None|> -->

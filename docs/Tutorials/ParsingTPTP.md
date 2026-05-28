---
Template: TechNote
Name: ParsingTPTP
Title: Parsing TPTP, Auto-Generated from the Published BNF
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/ParsingTPTP
Keywords: [TPTP, ATP, automated theorem proving, CNF, FOF, TFF, BNF, grammar, benchmark, EBNFParse]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingBNFGrammars, DesignAndCompilationStrategy]
---

## What this note covers

[TPTP](https://tptp.org/) (Thousands of Problems for Theorem Provers) is the standard cross-prover benchmark corpus for automated reasoning - 25,775 problems across 48 mathematical domains, used by Vampire, E, Twee, Waldmeister, and every modern ATP system. Every problem is a `.p` file with one of six clause heads: `cnf`, `fof`, `tff`, `tcf`, `thf`, `ncf`. The [TPTPWorld project](https://github.com/TPTPWorld/SyntaxBNF) publishes the formal grammar as a 735-line BNF file (`SyntaxBNF-v9.2.1.4`, 354 rules).

This note shows a TPTP parser built mechanically from that BNF using [EBNFParse]() - no per-rule hand-coding. It works in two steps:

1. Read the BNF into an `Association[name -> ParserCombinator]`.
2. Apply the result to TPTP source - optionally with an `"Actions"` map that lifts the raw parse tree to a Wolfram-Language data shape.

The lowering applies three standard PEG-vs-CFG rewrites automatically: direct left-recursion elimination, longest-alt-first sorting, and POSIX longest-match for rule bodies whose alternatives have equal element counts (the default `"ChoiceMode" -> "Auto"`). Together these handle the eleven left-recursive TPTP rules, the shared-prefix alternatives like `<constant> | <functor>(<fof_arguments>)`, and the cross-rule ambiguity in `<fof_atomic_formula> ::= <fof_plain_atomic_formula> | <fof_defined_atomic_formula>` where both branches can consume the same leading term but only the second one continues into the trailing `= rhs`. See [Parsing BNF Grammars](paclet:Wolfram/WolframParser/tutorial/ParsingBNFGrammars) for the grammar-level mechanics; this note is the TPTP-specific story.

---

## Bootstrapping a TPTP parser

```wl
Needs["Wolfram`Parser`"]

tptpBnf = Import[
    FileNameJoin[{PacletObject["Wolfram/WolframParser"]["Location"], "Tests", "tptp-bnf.txt"}],
    "Text"
];

parsers = EBNFParse[tptpBnf];
(* Association of 338 rule-name -> ParserCombinator. No PrimitiveOverrides, no options.
   Default `"ChoiceMode" -> "Auto"` enables longest-match for rules whose
   alternatives have equal element counts; PEG order for the rest. *)
```

Every `::-` (token) and `:::` (char-class) rule auto-compiles through a regex meta-parser built out of the same `Parse*` combinators. The meta-parser handles char classes (`[a-z]`, `[abc]`, and meta chars literally as in `[|]` / `[*]`), negation (`[^x]`), octal escapes (``[\40-\41]``), named escapes (``\n``, ``\r``, ``\t``), the bare-`.` regex any-char, ref forms (`<name>`, `{name}`), grouping (`(...)`), alternation (`|`), and the postfix repetition operators (`*`, `+`, `?`). The full TPTP lexical layer (`<lower_word>`, `<upper_word>`, `<integer>`, `<single_quoted>`, `<distinct_object>`, `<dollar_word>`, the punctuation tokens like `<vline>` / `<star>`, and the regex-heavy `<sq_char>` / `<do_char>` / `<not_star_slash>`) all compile from the published BNF without manual help.

That's the entire setup. `parsers["TPTP_file"]` is the top-level parser; `parsers["cnf_annotated"]`, `parsers["fof_annotated"]`, etc. are the per-clause-head parsers; `parsers["fof_unitary_formula"]`, `parsers["fof_quantified_formula"]`, ... are the inner rules.

A real TPTP problem, parsed end-to-end:

```wl
groupAxioms = "fof(group_assoc, axiom, ! [X, Y, Z] :
    multiply(multiply(X, Y), Z) = multiply(X, multiply(Y, Z))).
fof(group_left_id, axiom, ! [X] : multiply(identity, X) = X).
fof(group_left_inv, axiom, ! [X] : multiply(inverse(X), X) = identity).
fof(commutator_def, axiom, ! [X, Y] :
    commutator(X, Y) = multiply(multiply(X, Y),
                                 multiply(inverse(X), inverse(Y)))).
fof(goal, conjecture, ! [X] : commutator(X, identity) = identity).";

Length @ Parse[parsers["TPTP_file"], groupAxioms]
(* 5 *)
```

Five clauses, quantifiers, function application, equality - all parsed. But the value above is the raw parse tree (a list of clauses, each clause a list of literal tokens and sub-rule results). For a workable downstream shape, pass a per-rule `"Actions"` map.

---

## Lifting to a useful shape: the `"Actions"` map

Each entry in `"Actions" -> <|name -> fn|>` wraps the named rule's parser in a `ParseAction`. The function receives the rule's parsed value via the normal splatted convention - `Function[#1, #2, ...]` indexes into the sequence of matched sub-pieces. The action map below mechanically lifts the auto-generated parser's raw tree to the same Wolfram-Language shape the handwritten [TPTPImport](https://github.com/sw1sh/thvm) returns:

```wl
binConn[op_String, x_, y_] := Switch[op,
    "<=>", Equivalent[x, y], "=>", Implies[x, y],
    "<=",  Implies[y, x],    "<~>", Xor[x, y],
    "~|",  Nor[x, y],        "~&", Nand[x, y]
];

(* Flattener for right-recursive `<x> | <x>,<right>` rules
   (used by fof_arguments and fof_variable_list). *)
rightList[args__] := Module[{a = {args}},
    Switch[Length[a], 1, {a[[1]]}, 3, Prepend[a[[3]], a[[1]]]]
];

(* ForAll / Exists are HoldAll, so a literal call holds the bound
   var list and body uninterpreted. Apply substitutes them before
   the head holds; Quiet swallows the ForAll::ivar warning that
   fires because our TPTP variables are strings, not symbols. *)
quant[q_, vs_, body_] := Quiet[
    Apply[If[q === "!", ForAll, Exists], {vs, body}],
    {ForAll::ivar, Exists::ivar}
];

tptpActions = <|
    (* Term level. Constants emit as `tok[]` (String-headed 0-ary
       compound) to sidestep `Equal["a", "b"] -> False` eager
       evaluation - the same trick TPTPImport uses. *)
    "constant"  -> Function[#1[]],
    "functor"   -> Function[#1], "variable"  -> Function[#1],
    "fof_term"  -> Function[#1], "fof_function_term" -> Function[#1],
    "fof_plain_term" -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 4, a[[1]] @@ a[[3]]]
    ]],
    "fof_arguments"  -> rightList,

    (* Atomic formula plumbing. *)
    "fof_atomic_formula"         -> Function[#1],
    "fof_plain_atomic_formula"   -> Function[#1],
    "fof_defined_atomic_formula" -> Function[#1],
    "fof_defined_plain_formula"  -> Function[#1],
    "fof_defined_infix_formula"  -> Function[Equal[#1, #3]],
    "fof_infix_unary"            -> Function[Unequal[#1, #3]],

    (* Boolean grammar. *)
    "nonassoc_connective" -> Function[Block[{a = {##}},
        If[Length[a] === 1, a[[1]], StringJoin @@ a]
    ]],
    "fof_binary_nonassoc" -> Function[binConn[#2, #1, #3]],
    "fof_and_formula" -> Function[Block[{a = {##}},
        And @@ Join[{a[[1]], a[[3]]}, a[[4]][[All, 2]]]
    ]],
    "fof_or_formula" -> Function[Block[{a = {##}},
        Or @@ Join[{a[[1]], a[[3]]}, a[[4]][[All, 2]]]
    ]],
    "fof_binary_assoc"   -> Function[#1],
    "fof_binary_formula" -> Function[#1],
    "fof_logic_formula"  -> Function[#1],
    "fof_unary_formula"  -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 2, Not[a[[2]]]]
    ]],
    "fof_unit_formula"    -> Function[#1],
    "fof_unitary_formula" -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 3, a[[2]]]
    ]],

    (* Quantifiers. *)
    "fof_quantifier"         -> Function[#1],
    "fof_variable_list"      -> rightList,
    "fof_quantified_formula" -> Function[quant[#1, #3, #6]],
    "fof_formula"            -> Function[#1],

    (* CNF body: single literal stays bare, multi-literal becomes Or[...]. *)
    "cnf_literal" -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 2, Not[a[[2]]], 4, Not[a[[3]]]]
    ]],
    "cnf_disjunction" -> Function[Block[{a = {##}},
        If[ Length[#2] === 0, #1,
            Or @@ Prepend[#2[[All, 2]], #1]]
    ]],
    "cnf_formula" -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 3, a[[2]]]
    ]],

    (* Top-level clauses and file partition. negated_conjecture is
       flipped through Not, matching TPTPImport's convention. *)
    "cnf_annotated" -> Function[<|"Head" -> "cnf",
        "Name" -> #3, "Role" -> #5, "Formula" -> #7|>],
    "fof_annotated" -> Function[<|"Head" -> "fof",
        "Name" -> #3, "Role" -> #5, "Formula" -> #7|>],
    "tff_annotated" -> Function[<|"Head" -> "tff",
        "Name" -> #3, "Role" -> #5, "Formula" -> #7|>],
    "include" -> Function[<|"Head" -> "include", "File" -> #3|>],
    "TPTP_file" -> Function[Module[{cs = {##}}, <|
        "Includes" -> Cases[cs,
            kv:KeyValuePattern["Head" -> "include"] :> kv["File"]],
        "Axioms" -> Cases[cs,
            kv:KeyValuePattern["Role" -> "axiom" | "hypothesis"] :>
                kv["Formula"]],
        "Conjecture" -> Module[{
            c  = FirstCase[cs, KeyValuePattern["Role" -> "conjecture"], None],
            nc = FirstCase[cs, KeyValuePattern["Role" -> "negated_conjecture"], None]},
            Which[c =!= None, c["Formula"],
                  nc =!= None, Not[nc["Formula"]],
                  True, None]
        ]
    |>]]
|>;

parsers = EBNFParse[tptpBnf, "Actions" -> tptpActions];

Parse[parsers["TPTP_file"],
    "fof(assoc, axiom, ! [X, Y, Z] :
        multiply(multiply(X, Y), Z) = multiply(X, multiply(Y, Z))).
fof(left_id, axiom, ! [X] : multiply(identity, X) = X).
fof(goal, conjecture, ! [X] : multiply(X, identity) = X)."]

(* <|"Includes"   -> {},
     "Axioms"     -> {
        ForAll[{X, Y, Z}, multiply[multiply[X, Y], Z] ==
                          multiply[X, multiply[Y, Z]]],
        ForAll[{X}, multiply[identity[], X] == X]
     },
     "Conjecture" -> ForAll[{X}, multiply[X, identity[]] == X]|> *)
```

This is the shape the production [TPTPImport](https://github.com/sw1sh/thvm) returns: `ForAll`/`Exists` quantifiers, function application as `head[args...]`, `Equal`/`Unequal` for `=`/`!=`, the full Boolean grammar as `And`/`Or`/`Not`/`Implies`/`Equivalent`/`Xor`/`Nor`/`Nand`, cnf disjunctions as `Or[...]` (single literal stays bare), the file partitioned into `<|"Includes", "Axioms", "Conjecture"|>`, and `negated_conjecture` flipped through `Not`. The action map is ~50 entries, one per BNF rule on the path from `<TPTP_file>` to `<constant>`. The recogniser is unchanged - the same `EBNFParse` call drives both the with-actions and without-actions flows.

Without actions, the parser is just a recogniser - it tells you whether the source matches the grammar but the value is the structural skeleton. The action layer is what turns that into a workable Wolfram Language data structure.

---

## Benchmark on the published corpus

On the small CNF / FOF problems from the published `v9.2.1` distribution, per-clause parse time lands in the tens of milliseconds for short clauses (a few atoms, ground equations) and climbs into the hundreds of milliseconds for clauses with nested quantifiers and function applications. The 5-clause group-theory problem at the top of this note parses in ~700 ms end-to-end on a 2024 laptop with default `"ChoiceMode" -> "Auto"`.

For reference, the handwritten [TPTPImport](https://github.com/sw1sh/thvm) parses the full 25,775-problem corpus at roughly 80 ms per problem (~35 minutes total). The auto-generated parser is comparable on small CNF and noticeably slower on FOF with deep boolean / quantifier nesting - the cost of trying every alternative under longest-match without memoisation. Adding [packrat-style memoisation](https://en.wikipedia.org/wiki/Parsing_expression_grammar#Implementing_parsers_from_parsing_expression_grammars) to `ParseRecursive` would close most of the throughput gap; a Pratt-style precedence climber for the connective grammar would be the right move for THF, where alternative explosion overwhelms even longest-match.

### ParserCompile is currently a stub

```wl
compiled = ParserCompile[parsers["TPTP_file"]];
(* same parser with "Code" key in opts, but routed through an
   interpretive shim - no real FunctionCompile lowering yet *)
```

Per the [ParserCompile]() usage string: "v0.2: stubbed via the interpreter; the real FunctionCompile lowering lands later". A head-to-head bench on the 4 passing files confirms it - interpretive vs compiled are within measurement noise (1.00x speedup). Wiring up the real FunctionCompile path is a v0.4 item; the compiler infrastructure (`compilableQ`, `compileParser`, `interpretCompiledShim`, `CompileFeasibility` test suite) is in place but the per-combinator codegen rules aren't all written yet.

### What the ChoiceMode flip fixes

The earlier draft of this note reported a cluster of failures around equations and disequations whose left side was a function application, in `cnf` and `fof` contexts. Example: `multiply(b, a) != c` inside `cnf(_, negated_conjecture, multiply(b, a) != c).`. PEG-ordered `Choice` was committing to `<fof_plain_atomic_formula>` on `multiply(b, a)`, then expecting end-of-clause, but the source continued with `!= c` which only `<fof_infix_unary>` (a sibling alt at the same `<cnf_literal>` level) reaches.

The default `"ChoiceMode" -> "Auto"` resolves that whole cluster: for rule bodies whose alternatives have equal element counts (the static `longest-alt-first` sort can't break the tie), the lowering uses POSIX longest-match - every alt is tried at the current position and the one that consumed the most input wins. The `<fof_atomic_formula>` choice, `<cnf_literal>` choice, and a handful of other shape-ambiguous rules become correct without changing the grammar. The cost is some throughput - longest-match cannot early-exit on first hit, so deeply nested choices pay a constant factor over PEG. Set `"ChoiceMode" -> "PEG"` to opt back into the fast-but-strict ordering when the grammar is unambiguous; set `"ChoiceMode" -> "Longest"` to use longest-match unconditionally (correct on more grammars, slowest).

Remaining failures cluster on the higher-order alternatives in `<thf_*>` (the recursive `<thf_typeable_formula>` rule and friends). These exhibit *exponential* backtracking under any ordered-choice strategy and want either packrat memoisation or a Pratt-style precedence parser to be tractable - both unimplemented.

---

## Building the bench yourself

The TPTP distribution lives at https://tptp.org/TPTP/Distribution/TPTP-v9.2.1.tgz (922 MB compressed). Extract a sample and run:

```wl
(* ... primitiveOverrides + parsers from above ... *)

loadClean[path_String] := StringTrim @ StringReplace[
    Import[path, "Text"],
    RegularExpression["%[^\n]*"] -> ""
];

benchOne[file_] := Block[{src = loadClean[file], r, t},
    t = AbsoluteTime[];
    r = TimeConstrained[Parse[parsers["TPTP_file"], src], 30, "TO"];
    <|"File" -> FileBaseName[file],
      "Bytes" -> StringLength[src],
      "Time" -> AbsoluteTime[] - t,
      "Status" -> Which[
          r === "TO", "TIMEOUT",
          MatchQ[r, _ParseError], "ERROR",
          True, "OK"],
      "Clauses" -> If[ListQ[r], Length[r], 0]|>
];

results = benchOne /@ Take[
    FileNames["*.p", "/path/to/TPTP-v9.2.1/Problems", Infinity],
    100
];
Counts[#["Status"] & /@ results]
```

For the THF problems, raise the timeout or skip them (`StringContainsQ[FileBaseName[#], "^"] &` filters them out). The TFF / TCF cases land somewhere between CNF and THF in difficulty.

To run the same bench against the compiled path, swap the parser:

```wl
tptpCompiled = ParserCompile[parsers["TPTP_file"]];
benchOne[file_] := Block[{src = loadClean[file], r, t},
    t = AbsoluteTime[];
    r = TimeConstrained[Parse[tptpCompiled, src], 30, "TO"];
    ...
];
```

The current `ParserCompile` is interpretive-equivalent (stubbed), so per-file times will be within ~1% of the interpretive baseline. When the real FunctionCompile lowering lands, this swap is what surfaces the speedup.

---

## Comparison to the handwritten TPTPImport

The [TPTPImport](https://github.com/sw1sh/thvm) (sibling project, ~1100 lines of WL) is a complete reference implementation: CNF, FOF, TFF, TCF, THF, NCF clauses, the full Boolean grammar, quantifiers, sequents, includes with optional clause-name selectors, the term-level coverage (variables, distinct objects, numeric literals, single-quoted atoms), and the WL-term lifting that gives `<|"Axioms" -> {phi1, ...}, "Conjecture" -> phi|>` for downstream consumers.

What you get for free with the EBNF-driven approach:

- **The recogniser.** 280 of the 354 TPTP rules lower automatically; small CNF/FOF clauses parse end-to-end via a generic mechanism.
- **Grammar-tracking.** When TPTP-v9.3 ships, you re-run `EBNFParse` on the new BNF file and re-bind the actions - no per-rule diff. The handwritten parser has to be updated rule by rule.
- **Single source of truth.** The grammar IS the parser definition; the parser cannot disagree with the published BNF because they are the same file.

What still needs hand-work:

- **Term-level disambiguation.** The `<fof_plain_term>` left-factoring issue described above. Either a deeper structural rewrite or memoisation.
- **THF higher-order.** The mutual recursion + alternative explosion in the higher-order grammar needs memoisation or a different parsing strategy (e.g. Pratt-style precedence climbing) to be tractable.
- **Lexical primitives.** The `PrimitiveOverrides` map above covers the common cases; a complete map adds `real`, `rational`, `dollar_dollar_word`, the spacing tokens, comment / whitespace rules. A small `:::`-to-`ParseCharacter` compiler would generate these from the BNF too.

For a single-purpose ATP frontend, the handwritten parser remains the production choice today: faster, action-complete, and battle-tested against the full corpus. For evolving formal-grammar work where the published spec is moving and the hand-coded shadow drifts, the EBNF-driven path is what closes the gap.

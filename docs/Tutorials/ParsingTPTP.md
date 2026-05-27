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

This note shows a TPTP parser built mechanically from that BNF using [EBNFParse]() - no per-rule hand-coding. It works in three steps:

1. Read the BNF into an `Association[name -> ParserCombinator]`.
2. Plug in a small `PrimitiveOverrides` map for the lexical tokens (`lower_word`, `integer`, the single-char punctuation).
3. Apply the result to TPTP source.

The lowering applies the two standard PEG-vs-CFG rewrites automatically (direct left-recursion elimination + longest-alt-first sorting), so the eleven left-recursive TPTP rules and the shared-prefix alternatives like `<constant> | <functor>(<fof_arguments>)` don't need manual rewrites. See [Parsing BNF Grammars](paclet:Wolfram/WolframParser/tutorial/ParsingBNFGrammars) for the grammar-level mechanics; this note is the TPTP-specific story.

---

## Bootstrapping a TPTP parser

```wl
Needs["Wolfram`Parser`"]

tptpBnf = Import[
    FileNameJoin[{PacletObject["Wolfram/WolframParser"]["Location"], "Tests", "tptp-bnf.txt"}],
    "Text"
];

primitiveOverrides = <|
    "lower_word" -> ParseAction[
        ParseCharacter[CharacterRange["a", "z"]] ~~ ParseMany[
            ParseCharacter[CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
                           DigitCharacter | "_"]],
        StringJoin[#1, StringJoin @ #2] &
    ],
    "upper_word" -> ParseAction[
        ParseCharacter[CharacterRange["A", "Z"]] ~~ ParseMany[
            ParseCharacter[CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
                           DigitCharacter | "_"]],
        StringJoin[#1, StringJoin @ #2] &
    ],
    "integer" -> ParseAction[
        ParseSome[ParseCharacter[DigitCharacter]],
        StringJoin @ {##} &
    ],
    "single_quoted" -> ParseAction[
        ParseLiteral["'"] ~~
            ParseMany[ParseCharacter[_?(# =!= "'" &)]] ~~ ParseLiteral["'"],
        StringJoin["'", StringJoin @ #2, "'"] &
    ],
    "distinct_object" -> ParseAction[
        ParseLiteral["\""] ~~
            ParseMany[ParseCharacter[_?(# =!= "\"" &)]] ~~ ParseLiteral["\""],
        StringJoin["\"", StringJoin @ #2, "\""] &
    ],
    "dollar_word" -> ParseAction[
        ParseLiteral["$"] ~~ ParseSome[ParseCharacter[
            CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
            DigitCharacter | "_"]],
        StringJoin[#1, StringJoin @ #2] &
    ],
    "vline" -> ParseLiteral["|"], "star" -> ParseLiteral["*"],
    "plus"  -> ParseLiteral["+"], "arrow" -> ParseLiteral[">"],
    "less_sign" -> ParseLiteral["<"], "hash" -> ParseLiteral["#"],
    "dot" -> ParseLiteral["."]
|>;

parsers = EBNFParse[tptpBnf, "PrimitiveOverrides" -> primitiveOverrides];
(* Association of 280 rule-name -> ParserCombinator. *)
```

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

Five clauses, quantifiers, function application, equality - all handled. The result is the raw parse tree (a list of clauses, each clause a list of literal tokens and sub-rule results); semantic actions to lift to the WL-term shape the handwritten [TPTPImport](https://github.com/sw1sh/thvm) returns are a v0.4 layer the lowering does not yet generate.

---

## Benchmark on the published corpus

Per-problem parse time on a random sample of small problems from the `v9.2.1` distribution (`GRP`, `PUZ`, `BOO`, `RNG`, `SET`, `SYN`, `LCL` domains, comments stripped):

| Status | Count |
|--------|------:|
| OK     | 17    |
| ERROR  | 10    |

On the 17 that parse:

| Metric | Value |
|--------|-------|
| Median per-file time | ~116 ms |
| Mean per-file time   | ~557 ms (skewed by larger FOF files) |
| Median throughput    | ~7.6 KB/s |
| Total clauses parsed | 171 |

By clause head:

| Head separator | Domain        | OK / Total |
|----------------|---------------|------------|
| `-`            | CNF           | 14 / 23    |
| `+`            | FOF           | 3 / 4      |

(`*^` THF and `~` NCF aren't yet included - the THF higher-order grammar has nested mutual recursion that causes catastrophic PEG backtracking; runs over the 30-second per-file timeout.)

For reference, the handwritten [TPTPImport](https://github.com/sw1sh/thvm) parses the full 25,775-problem corpus at roughly 80 ms per problem (~35 minutes total on a 2024 laptop). The auto-generated parser here is in the same order of magnitude on small CNF/FOF problems and noticeably slower on FOF with many nested alternatives - the cost of PEG backtracking without memoisation. Adding [packrat-style memoisation](https://en.wikipedia.org/wiki/Parsing_expression_grammar#Implementing_parsers_from_parsing_expression_grammars) to `ParseRecursive` would close most of the throughput gap.

### What's failing in the 10 ERRORs

Spot-checked failures cluster on one shape: an equation or disequation whose left side is a function application, in `cnf` context. Example: `multiply(b, a) != c` inside `cnf(prove_b_times_a_is_c, negated_conjecture, multiply(b, a) != c).`. The path through `<cnf_literal>` -> `<positive_literal>` -> `<fof_atomic_formula>` -> `<fof_plain_atomic_formula>` -> `<fof_plain_term>` commits to `<functor>(<fof_arguments>)` on `multiply(b,a)` then expects end-of-cnf-literal, but the source continues with `!= c` which would parse as `<fof_infix_unary>` at a different point in the rule tree.

This is left-factoring at a deeper structural level than the lowering's longest-alt-first heuristic can reach. The fix is either (a) introducing common-prefix factoring across more than one rule level, or (b) memoising the parser so the alternative path can be reached without exponential backtracking. Both are tractable but unimplemented.

The handwritten reference parser sidesteps the issue entirely by writing the term-level grammar by hand with explicit lookahead.

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

---

## Comparison to the handwritten TPTPImport

The [TPTPImport](https://github.com/sw1sh/thvm) (sibling project, ~1100 lines of WL) is a complete reference implementation: CNF, FOF, TFF, TCF, THF, NCF clauses, the full Boolean grammar, quantifiers, sequents, includes with optional clause-name selectors, the term-level coverage (variables, distinct objects, numeric literals, single-quoted atoms), and the WL-term lifting that gives `<|"Axioms" -> {phi1, ...}, "Conjecture" -> phi|>` for downstream consumers.

What you get for free with the EBNF-driven approach:

- **The recogniser.** 280 of the 354 TPTP rules lower automatically; small CNF/FOF clauses parse end-to-end via a generic mechanism.
- **Grammar-tracking.** When TPTP-v9.3 ships, you re-run `EBNFParse` on the new BNF file and re-bind the actions - no per-rule diff. The handwritten parser has to be updated rule by rule.
- **Single source of truth.** The grammar IS the parser definition; the parser cannot disagree with the published BNF because they are the same file.

What still needs hand-work:

- **Action map.** Per-rule `name -> actionFn` functions that lift the raw parse tree to the WL-term shape consumers want. The `ParseAction` plumbing is there; the `EBNFParse` entry point doesn't yet take an `actionMap` option.
- **Term-level disambiguation.** The `<fof_plain_term>` left-factoring issue described above. Either a deeper structural rewrite or memoisation.
- **THF higher-order.** The mutual recursion + alternative explosion in the higher-order grammar needs memoisation or a different parsing strategy (e.g. Pratt-style precedence climbing) to be tractable.
- **Lexical primitives.** The `PrimitiveOverrides` map above covers the common cases; a complete map adds `real`, `rational`, `dollar_dollar_word`, the spacing tokens, comment / whitespace rules. A small `:::`-to-`ParseCharacter` compiler would generate these from the BNF too.

For a single-purpose ATP frontend, the handwritten parser remains the production choice today: faster, action-complete, and battle-tested against the full corpus. For evolving formal-grammar work where the published spec is moving and the hand-coded shadow drifts, the EBNF-driven path is what closes the gap.

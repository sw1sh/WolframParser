---
Template: TechNote
Name: ParsingBNFGrammars
Title: Parsing BNF Grammars (and bootstrapping a TPTP parser)
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/ParsingBNFGrammars
Keywords: [BNF, EBNF, grammar, meta-grammar, bootstrap, TPTP, ATP, SyntaxBNF, GrammarApply, parser combinator, ParseRecursive]
RelatedGuides: [WolframParser]
RelatedTutorials: [DesignAndCompilationStrategy, ParsingGrammarRules]
---

## What this note covers

A grammar definition file - the kind tool authors publish to describe their input language - is itself a string with structure. The TPTP project's [SyntaxBNF-v9.2.1.4](https://github.com/TPTPWorld/SyntaxBNF/blob/master/SyntaxBNF-v9.2.1.4) is 735 lines and 338 rules of the shape `<name> ::= <alt1> | <alt2> | ...`. If we have a parser combinator library, the natural question is: can we use it to parse the BNF file, then turn the parsed rules back into combinators that parse the language the grammar describes? The answer is "yes, with caveats" - this note works the example end-to-end and is honest about where the bootstrap breaks down.

Three parts:

1. **The EBNF parser.** `Wolfram\`Parser\`EBNF\`` reads a BNF source file using nothing but `Parse*` combinators - no regex `StringCases`, no hand-cracked line scanning. The output is an `Association[name -> ParserCombinator]`. Tested against TPTP's full 354-rule grammar.
2. **Bootstrapping TPTP.** A minimal `PrimitiveOverrides` map plugs in lexical tokens (`lower_word`, `upper_word`, `integer`, `single_quoted`, ...) that the BNF defines as `::-` / `:::` regex-style rules. With that wired up, the auto-generated parsers handle the simplest TPTP clauses. The end-to-end test parses `cnf(test, axiom, p).`.
3. **The PEG wall.** Where the bootstrap stops, and what the [handwritten TPTPImport](https://github.com/sw1sh/thvm) does that the auto-generation can't yet.

---

## Part 1 - The EBNF parser, built from our own combinators

`Wolfram\`Parser\`EBNF\`` is in two layers:

**(a) The BNF grammar itself, expressed as `Parse*` combinators.** The whole grammar is about 100 lines, with a `nonTerm` parser for `<name>` references, a `literalLetters` and `literalPunct` pair for the two flavours of literal token, a `rawElt` choice over (`nonTerm` + optional `*`, plain `nonTerm`, letters, punct), an `altSeq` of repeated elements separated by whitespace, an `alts` that's `ParseSepBy1[altSeq, "|"]`, a `ruleP` that ties it all together with the arrow, and finally `grammarP` = `ParseMany[ruleP]`. PEG ordering does the heavy lifting: `nonTerm` is tried before `literalPunct`, so `<name>` is consumed as a non-terminal; if `<` isn't followed by `name>`, `literalPunct` picks it up as a bare `<` (e.g. the `<<` in `<subtype_sign> ::= <<`).

One small piece deserves attention - the `literalPunct` lookahead:

```wl
literalPunct = ParseAction[
    ParseSome[
        ParseAction[
            ParseNotFollowedBy[nonTerm] ~~ ParseCharacter[_?literalIsPunctChar],
            #2 &
        ]
    ],
    Lit[StringJoin[{##}]] &
]
```

Without the `ParseNotFollowedBy[nonTerm]`, a punctuation run is greedy and would eat the `<` of an immediately-adjacent non-terminal (so `(<source>` would tokenize as `[(<, source, >]` instead of `[(, <source>]`). The guard checks at each character whether the cursor is at the start of a valid `<name>` and stops the run if so. This is the kind of context-sensitive disambiguation that's awkward in pure regex but natural with combinators.

**(b) The lowering: rule list -> `Association[name -> parser]`.** Each rule is walked: literals become `ParseLiteral`, non-terminals become `ParseRecursive[symbol]` where each rule has an allocated `Unique` symbol holding its lowered parser. The fresh-symbol indirection is what lets the lowering build the parser map *in any order* - mutual recursion among rules ties through the symbols, looked up at parse time. Once every rule is lowered, each rule's parser is bound to its symbol; the `ParseRecursive` references resolve and the whole grammar wakes up.

```wl
g = EBNFParse["
    <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
    <number> ::= <digit><digit>*
    <expr>   ::= <number> + <number>
"];
Parse[g["expr"], "12 + 34"]
(* {{"1", {"2"}}, "+", {"3", {"4"}}} *)
```

Whitespace between adjacent elements is automatic - the lowering inserts an optional-whitespace parser between every two sequence elements, so `12+34` and `12 + 34` both parse.

---

## Part 2 - Bootstrapping a TPTP parser

The TPTP BNF distinguishes four rule kinds:

| Arrow  | Meaning                                                                              |
|--------|--------------------------------------------------------------------------------------|
| `::=`  | syntactic rule (the parser's job)                                                    |
| `:==`  | semantic rule (lifts a parse tree to a specific value - same surface shape as `::=`) |
| `::-`  | token-construction rule (e.g. `<single_quoted> ::- <single_quote><sq_char>* ...`)    |
| `:::`  | character-class rule (e.g. `<star> ::: [*]`, `<lower_alpha> ::: [a-z]`)              |

The first two parse cleanly via our lowering. The latter two are mostly regex-style definitions that the EBNF parser reads but does NOT auto-lower (you'd build a small regex-to-`ParseCharacter` compiler to handle the `[a-z]` / `[^*]` classes). For the bootstrap, we hand-define the lexical primitives that the syntactic rules call out by name:

```wl
primitiveOverrides = <|
    "lower_word" -> ParseAction[
        ParseCharacter[CharacterRange["a", "z"]] ~~ ParseMany[
            ParseCharacter[CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
                           DigitCharacter | "_"]
        ],
        StringJoin[#1, StringJoin @ #2] &
    ],
    "upper_word" -> ...,
    "integer"    -> ParseAction[ParseSome[ParseCharacter[DigitCharacter]], StringJoin @ {##} &],
    "single_quoted" -> ...,
    "vline" -> ParseLiteral["|"],
    "star"  -> ParseLiteral["*"],
    "plus"  -> ParseLiteral["+"],
    ...
|>;

tptpBnf  = Import["https://raw.githubusercontent.com/TPTPWorld/SyntaxBNF/master/SyntaxBNF-v9.2.1.4", "Text"];
parsers  = EBNFParse[tptpBnf, "PrimitiveOverrides" -> primitiveOverrides];

Parse[parsers["cnf_annotated"], "cnf(test, axiom, p)."]
(* {"cnf", "(", "test", ",", "axiom", ",", "p", Null, ")."} *)
```

The output is the raw parse tree - a list of matched literals and sub-parser results. Turning it into the WL-term shape (`<|"Axioms" -> {phi1, ...}, "Conjecture" -> phi|>` with atoms as `String`-headed compounds) is the *semantic action* layer. Each rule needs a `ParseAction` that lifts the raw tree to the right WL value. The paclet ships the result as [TPTPImport](); see [Parsing TPTP](paclet:Wolfram/WolframParser/tutorial/ParsingTPTP) for the ~50-entry action map.

---

## Part 3 - PEG-vs-CFG rewrites done at lowering time

The TPTP grammar is published in a form that assumes an LALR/yacc parser with operator-precedence support. PEG parser combinators handle a strict subset of CFGs cleanly. Two categorical mismatches surface in the published BNF; the lowering rewrites both automatically.

**(a) Left recursion.** Eleven TPTP rules are directly left-recursive:

```
<cnf_disjunction>      ::= <cnf_literal> | <cnf_disjunction> <vline> <cnf_literal>
<fof_or_formula>       ::= <fof_unit_formula> <vline> <fof_unit_formula> |
                          <fof_or_formula> <vline> <fof_unit_formula>
<thf_apply_formula>    ::= <thf_unit_formula> @ <thf_unit_formula> |
                          <thf_apply_formula> @ <thf_unit_formula>
...  (and 8 others: fof_and_formula, thf_or_formula, thf_and_formula,
      thf_xprod_type, thf_union_type, tff_or_formula, tff_and_formula,
      tff_xprod_type)
```

A PEG parser following the literal grammar would never reach the recursive alt (the non-recursive alt always matches the prefix first and commits). The lowering applies the standard rewrite:

```
A ::= A r1 | A r2 | ... | b1 | b2 | ...
```

becomes the right-recursive equivalent

```
A ::= b1 (r1 | r2 | ...)*  |  b2 (r1 | r2 | ...)*  |  ...
```

Implemented as `Rep["ManyAlts", recursive]` appended to each non-recursive alt. After the rewrite, `p | q | r` parses correctly as `cnf_disjunction`, `p & q & r` parses as `fof_and_formula`, etc.

**(b) Left factoring via longest-alt-first sorting.** When two alts share a common prefix - the canonical example is

```
<fof_plain_term> ::= <constant> | <functor>(<fof_arguments>)
```

where both `<constant>` and `<functor>` expand to `<atomic_word>` - PEG would commit to the shorter alt (`<constant>` matches `p` in `p(a)` and never reaches the function-application form). The lowering sorts each rule's alternatives by length, longest first. The longer alt is tried first; if its longer suffix fails (e.g. no `(` after the functor), PEG backtracks to the shorter prefix-only alt. This is a heuristic approximation of true left factoring but it covers the cases TPTP needs.

After both rewrites land, real TPTP inputs parse via the auto-generated parser:

| Input                                                         | Result |
|---------------------------------------------------------------|--------|
| `cnf(test, axiom, p).`                                        | OK     |
| ``cnf(t, axiom, p \| q \| r).``                                 | OK     |
| ``cnf(t, axiom, p(a) \| ~q(b)).``                               | OK     |
| `fof(t, axiom, p & q & r & s).`                               | OK     |
| `fof(t, axiom, p => q).` / `p <=> q`                          | OK     |
| `fof(t, axiom, p(a, b, c)).`                                  | OK     |
| `fof(t, axiom, p = q).` / `p != q`                            | OK     |
| `fof(t, axiom, ! [X] : p(X)).`                                | OK     |
| `fof(t, axiom, ? [X] : p(X)).`                                | OK     |
| `fof(t, axiom, ! [X, Y] : (p(X) & q(Y))).`                    | OK     |
| 5-clause group-theory problem with quantifiers and equality   | OK     |
| `include('Axioms/SET006-0.ax').`                              | OK     |

What still doesn't lower automatically:

**Dual definitions.** Many rules have BOTH a `::=` and a `:==` definition for the same name. The auto-lowering keys both into one `name -> parser` map and the second definition overwrites the first.

**`::-` / `:::` rules untouched.** The lowering reads them (so all 338 rules parse), but only `::=` and `:==` get auto-lowered. The `::-` / `:::` rules need either a small regex-to-`ParseCharacter` compiler or hand-defined primitives via `PrimitiveOverrides` (the same 12-entry override map shown in Part 2).

**Semantic actions.** What `<cnf_annotated>` parses to today is the raw token tree `{"cnf", "(", name, ",", role, ",", {formula, {tail-matches}}, annotations, ")."}` - the literals and the sub-parser results in BNF order, with `{}` placeholders where ParseMany produced zero matches. The handwritten [TPTPImport](https://github.com/sw1sh/thvm) lifts this to the `<|"Axioms" -> {phi1, ...}, "Conjecture" -> phi|>` shape via per-rule actions; the lowering doesn't yet take an `actionMap` option.

---

## Comparison to the handwritten TPTPImport

The [TPTPImport](https://github.com/sw1sh/thvm) (a sibling project, ~1100 lines) is a complete reference implementation: cnf, fof, tff, tcf, thf, ncf clauses, the full Boolean grammar, quantifiers, sequents, includes with optional clause-name selectors, the term-level coverage (variables, distinct objects, numeric literals, single-quoted atoms), and the WL-term lifting.

What the EBNF approach gives you:

- **The recogniser, done.** 338 rules parsed, 280 lowered, the two PEG-vs-CFG rewrites applied automatically. Real TPTP problems with quantifiers, function application, equality, and multi-term boolean connectives parse end to end - the action layer that lifts the raw tree to canonical Wolfram-Language terms ships as [TPTPImport]().
- **Vendored grammar tracking.** When the upstream TPTP grammar updates (the `v9.2.1.x` version numbers in the comment header), the auto-generated parser updates with it - re-run `EBNFParse` on the new file. The handwritten parser has to be diffed line-by-line against the new grammar.
- **Single source of truth.** The grammar IS the parser definition; you can't end up with a parser that disagrees with the published grammar.

What still has to be written by hand:

- **`::-` and `:::` primitives** for the lexical tokens. The 12-entry `PrimitiveOverrides` map in Part 2 is a working starter set; a more complete one would cover `real`, `rational`, `dollar_dollar_word`, the spacing / punctuation tokens, and the comment / whitespace rules properly.
- **The action map** that lifts each rule's raw parse tree to the WL value the consumer wants. For TPTP this is the `clauseToFormula` / `readTerm` / sequent-rewrite logic from the handwritten reference. The lowering's `ParseAction` is the right shape; what's missing is the `name -> actionFn` plumbing through `EBNFParse`.

The endpoint is a v0.4 of `EBNFParse` that takes a BNF + action map + override map and returns a parser whose output is the user-defined WL shape. The hard parts (recogniser construction, left-recursion elimination, left-factoring) are done.

---

## Try it

The tests in ``Tests/EBNF.wlt`` cover the unit cases above plus the five-clause group-theory TPTP problem end-to-end. They fetch the canonical [TPTPWorld BNF](https://github.com/TPTPWorld/SyntaxBNF) directly. To experiment:

```wl
Needs["Wolfram`Parser`"]

source = "<S> ::= a <S> b | <epsilon>
          <epsilon> ::=";
g = EBNFParse[source];
Parse[g["S"], "aaabbb"]
(* the classic a^n b^n grammar - parses cleanly *)
```

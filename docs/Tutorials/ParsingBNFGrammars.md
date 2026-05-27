---
Template: TechNote
Name: ParsingBNFGrammars
Title: Parsing BNF Grammars (and bootstrapping a TPTP parser)
Context: Wolfram`Parser`EBNF`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/ParsingBNFGrammars
Keywords: [BNF, EBNF, grammar, meta-grammar, bootstrap, TPTP, ATP, SyntaxBNF, GrammarApply, parser combinator, ParseRecursive]
RelatedGuides: [WolframParser]
RelatedTutorials: [DesignAndCompilationStrategy, ParsingGrammarRules]
---

## What this note covers

A grammar definition file - the kind tool authors publish to describe their input language - is itself a string with structure. The TPTP project's [SyntaxBNF-v9.2.1.4](https://github.com/TPTPWorld/SyntaxBNF/blob/master/SyntaxBNF-v9.2.1.4) is 735 lines and 354 rules of the shape `<name> ::= <alt1> | <alt2> | ...`. If we have a parser combinator library, the natural question is: can we use it to parse the BNF file, then turn the parsed rules back into combinators that parse the language the grammar describes? The answer is "yes, with caveats" - this note works the example end-to-end and is honest about where the bootstrap breaks down.

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
Needs["Wolfram`Parser`EBNF`"]

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

tptpBnf  = Import["Tests/tptp-bnf.txt", "Text"];
parsers  = EBNFParse[tptpBnf, "PrimitiveOverrides" -> primitiveOverrides];

Parse[parsers["cnf_annotated"], "cnf(test, axiom, p)."]
(* {"cnf", "(", "test", ",", "axiom", ",", "p", Null, ")."} *)
```

The output is the raw parse tree - a list of matched literals and sub-parser results. Turning it into the WL-term shape the production [TPTPImport](https://github.com/sw1sh/thvm) returns (`<|"Axioms" -> {phi1, ...}, "Conjecture" -> phi|>` with atoms as `String`-headed compounds) is the *semantic action* layer, which the auto-generated parser doesn't yet ship. Each rule needs a `ParseAction` that lifts the raw tree to the right WL value (a `clauseToFormula`-equivalent per rule). The handwritten implementation is ~1100 lines and most of that is exactly these lifters.

---

## Part 3 - The PEG wall: where the bootstrap stops

The TPTP grammar is published in a form that assumes an LALR or LL parser with operator-precedence support. PEG parser combinators (which is what `Wolfram\`Parser\`` is) handle a strict subset cleanly. The categorical issues that the auto-generation cannot resolve without grammar rewrites:

**Left recursion.** Multiple TPTP rules are left-recursive:

```
<thf_apply_formula>   ::= <thf_unit_formula> @ <thf_unit_formula> |
                          <thf_apply_formula> @ <thf_unit_formula>

<thf_xprod_type>      ::= <thf_unitary_type> <star> <thf_unitary_type> |
                          <thf_xprod_type> <star> <thf_unitary_type>
```

A PEG parser following the literal grammar would infinite-loop on the second alternative (it tries `<thf_apply_formula>`, which immediately tries `<thf_apply_formula>`, ...). Left-recursive rules must be rewritten to right-recursive + `ParseChainLeft` before they can run on a PEG. This is a *mechanical* transformation (Paull's algorithm) but the EBNF parser doesn't apply it automatically.

**Dual definitions.** Many rules have BOTH a `::=` and a `:==` definition for the same name, expressing the syntactic shape and the semantic value separately:

```
<formula_role> ::= <lower_word> | <lower_word>-<general_term>
<formula_role> :== axiom | hypothesis | definition | assumption | lemma |
                   theorem | corollary | conjecture | ...
```

The auto-lowering keys both into a single `name -> parser` map and the second definition overwrites the first, losing the syntactic / semantic distinction the grammar deliberately encodes.

**`::-` / `:::` rules untouched.** These produce tokens and character classes. The auto-lowering reads them (so the EBNF parser successfully parses all 354 rules - 230 `::=`, 68 `:==`, 18 `::-`, 38 `:::`), but only the first two kinds get lowered to combinators. The `::-` / `:::` rules require either a small regex-to-`ParseCharacter` compiler or hand-defined primitives via `PrimitiveOverrides`.

**Semantic actions.** What `<cnf_annotated>` parses to today is `{"cnf", "(", "name", ",", "role", ",", parsedFormula, parsedAnnotation, ")."}` - the raw token list. The handwritten parser's per-rule action turns that into `clauseToFormula[name, "cnf", "axiom", formula]` which then becomes `Or[lit1, ...]`. The lowering would need a hook for `name -> actionFn` mappings, with each `actionFn` taking the auto-generated raw tuple and emitting the WL value. Adding this is straightforward - the `ParseAction` is already the right shape - but the *content* of each action is grammar-specific.

---

## Comparison to the handwritten TPTPImport

The [TPTPImport](https://github.com/sw1sh/thvm) (a sibling project, ~1100 lines) is a complete reference implementation of the TPTP subset its author needed: cnf, fof, tff, tcf, thf, ncf clauses, the full Boolean grammar, quantifiers, sequents, includes with optional clause-name selectors, the term-level coverage (variables, distinct objects, numeric literals, single-quoted atoms), and the WL-term lifting that gives downstream consumers the right structure.

What the EBNF approach gives you for free:

- **The recogniser skeleton.** 354 rules, ~280 of which lower to `ParserCombinator`s without any manual work. The recogniser stops at the four points above (left recursion, dual definitions, `::-`/`:::`, semantic actions).
- **Vendored grammar tracking.** When the upstream TPTP grammar updates (the `v9.2.1.x` version numbers in the comment header), the auto-generated parser updates with it - you re-run `EBNFParse` on the new file and rebind the actions. The handwritten parser has to be diffed line-by-line against the new grammar.
- **Single source of truth.** The grammar IS the parser definition; you can't end up with a parser that disagrees with the published grammar because they're the same file.

What you still need to do by hand:

- **Eliminate left recursion** in `<thf_apply_formula>`, `<thf_xprod_type>`, the relevant `<fof_*_formula>` rules - replace recursive-LHS alternatives with `ParseChainLeft` / `ParseChainRight` over the right-recursive form.
- **Provide `::-` and `:::` primitives** for `lower_word`, `upper_word`, `integer`, `real`, `rational`, `single_quoted`, `distinct_object`, `dollar_word`, `dollar_dollar_word`, and the punctuation tokens (`vline`, `star`, etc.).
- **Write the action map** that lifts each rule's raw parse tree to the WL value the consumer wants. For TPTP this is the `clauseToFormula` / `readTerm` / sequent-rewrite logic from the handwritten reference.

The endpoint is a v0.4 of `Wolfram\`Parser\`EBNF\`` that takes a BNF + an action map + an override map, applies Paull's left-recursion elimination automatically, and returns a parser whose output is the user-defined WL shape - same surface contract as `GrammarRules`, but for the formal-grammar-with-actions case instead of the natural-language-templates case. The pieces are all here; what's left is wiring them into one entry point.

---

## Try it

The tests in `Tests/EBNF.wlt` cover the unit cases above. The vendored grammar lives at `Tests/tptp-bnf.txt`. To experiment:

```wl
Needs["Wolfram`Parser`"]
Needs["Wolfram`Parser`EBNF`"]

source = "<S> ::= a <S> b | epsilon
          <epsilon> ::=";
g = EBNFParse[source];
Parse[g["S"], "aaabbb"]
(* the classic a^n b^n grammar - parses cleanly *)
```

For the TPTP case, the test `EBNF: minimal cnf clause parses via auto-generated TPTP parser` is the working end-to-end demo. Extending it - left-recursion elimination, the action map, the production WL-term shape - is the v0.4 chapter of this story.

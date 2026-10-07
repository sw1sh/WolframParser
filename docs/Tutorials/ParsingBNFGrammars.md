---
Template: TechNote
Name: ParsingBNFGrammars
Title: Parsing BNF Grammars (and bootstrapping a TPTP parser)
Context: Wolfram`Parser`
ContextPath: [Global`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/ParsingBNFGrammars
Keywords: [BNF, EBNF, grammar, meta-grammar, bootstrap, TPTP, ATP, SyntaxBNF, GrammarApply, parser combinator, ParseRecursive]
RelatedGuides: [WolframParser]
RelatedTutorials: [DesignAndCompilationStrategy, ParsingGrammarRules]
---

## What this note covers

A grammar definition file - the kind tool authors publish to describe their input language - is itself a string with structure. The TPTP project's [SyntaxBNF-v9.2.1.4](https://github.com/TPTPWorld/SyntaxBNF/blob/da4fbddc9da7b066f03a4fd47edb148fa6e17c91/SyntaxBNF-v9.2.1.4) is 735 lines and 338 rules of the shape `<name> ::= <alt1> | <alt2> | ...`. If we have a parser combinator library, the natural question is: can we use it to parse the BNF file, then turn the parsed rules back into combinators that parse the language the grammar describes? The answer is "yes, with caveats" - this note works the example end-to-end and is honest about where the bootstrap breaks down.

Three parts:

1. **The EBNF parser.** `Wolfram\`Parser\`EBNF\`` reads a BNF source file using nothing but `Parse*` combinators - no regex `StringCases`, no hand-cracked line scanning. The output is an `Association[name -> ParserCombinator]`. Tested against TPTP's full 354-rule grammar.
2. **Bootstrapping TPTP.** The whole TPTP grammar lowers in one call, its regex-style token and character-class rules included, and the generated parsers read real clauses. An `"Actions"` map lifts each rule's raw parse tree to a Wolfram Language value - which is how [TPTPImport]() is built.
3. **The PEG wall.** Where a grammar written for an LALR parser needs rewriting for PEG, which rewrites the lowering does itself, and what still takes a hand-written parser.

---

## Part 1 - The EBNF parser, built from our own combinators

`Wolfram\`Parser\`EBNF\`` is in two layers:

**(a) The BNF grammar itself, expressed as `Parse*` combinators.** The whole grammar is about 100 lines, with a `nonTerm` parser for `<name>` references, a `literalLetters` and `literalPunct` pair for the two flavours of literal token, a `rawElt` choice over (`nonTerm` + optional `*`, plain `nonTerm`, letters, punct), an `altSeq` of repeated elements separated by whitespace, an `alts` that's `ParseSepBy1[altSeq, "|"]`, a `ruleP` that ties it all together with the arrow, and finally `grammarP` = `ParseMany[ruleP]`. PEG ordering does the heavy lifting: `nonTerm` is tried before `literalPunct`, so `<name>` is consumed as a non-terminal; if `<` isn't followed by `name>`, `literalPunct` picks it up as a bare `<` (e.g. the `<<` in `<subtype_sign> ::= <<`).

One small piece of the source deserves attention - the `literalPunct` lookahead, listed as `EBNF.wl` defines it:

```wl
#| eval: false
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

A three-rule grammar lowers to one parser per rule:

```wl
g = EBNFParse["
    <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
    <number> ::= <digit><digit>*
    <expr>   ::= <number> + <number>
"]
```

The `<expr>` parser gives the raw tree of its rules' results:

```wl
Parse[g["expr"], "12 + 34"]
```

<!-- => {{"1", {"2"}}, "+", {"3", {"4"}}} -->

Whitespace between adjacent elements is automatic - the lowering inserts an optional-whitespace parser between every two sequence elements, so the same tree comes from the input with no spaces:

```wl
Parse[g["expr"], "12+34"]
```

<!-- => {{"1", {"2"}}, "+", {"3", {"4"}}} -->

---

## Part 2 - Bootstrapping a TPTP parser

The TPTP BNF distinguishes four rule kinds:

| Arrow  | Meaning                                                                              |
|--------|--------------------------------------------------------------------------------------|
| `::=`  | syntactic rule (the parser's job)                                                    |
| `:==`  | semantic rule (lifts a parse tree to a specific value - same surface shape as `::=`) |
| `::-`  | token-construction rule (e.g. `<single_quoted> ::- <single_quote><sq_char>* ...`)    |
| `:::`  | character-class rule (e.g. `<star> ::: [*]`, `<lower_alpha> ::: [a-z]`)              |

The lowering handles all four. `::=` and `:==` rules lower to sequences and choices; the `::-` and `:::` bodies are regex-style (`[a-z]`, `[*]`) and are compiled to [ParseCharacter]() classes. The grammar file, read in once:

```wl
tptpBnf = Import["https://raw.githubusercontent.com/TPTPWorld/SyntaxBNF/da4fbddc9da7b066f03a4fd47edb148fa6e17c91/SyntaxBNF-v9.2.1.4", "Text"];
```

One rule of each kind, as the file states them:

```wl
Select[StringSplit[tptpBnf, "\n"], StringStartsQ[#, "<cnf_annotated>" | "<lower_word>" | "<lower_alpha>" | "<single_quoted>"] &]
```

The whole grammar lowers in one call:

```wl
tptpParsers = EBNFParse[tptpBnf];
```

A parser per rule name - here the first three of them:

```wl
Take[tptpParsers, 3]
```

All 338 rule names:

```wl
Length[tptpParsers]
```

<!-- => 338 -->

The `<cnf_annotated>` parser reads a clause straight away:

```wl
Parse[tptpParsers["cnf_annotated"], "cnf(test, axiom, p)."]
```

<!-- => {"cnf", "(", "test", ",", "axiom", ",", {"p", {}}, Null, ")."} -->

The output is the raw parse tree - the matched literals and sub-parser results in grammar order. Turning it into a Wolfram Language value is the *semantic action* layer: an `"Actions"` entry wraps one rule's parser in [ParseAction](). On the small grammar from Part 1, an action for `<number>` turns each digit tree into an integer:

```wl
gNum = EBNFParse[
    "<digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
     <number> ::= <digit><digit>*
     <expr>   ::= <number> + <number>",
    "Actions" -> <|"number" -> Function[FromDigits @ StringJoin[#1, StringJoin @ #2]]|>
]
```

```wl
Parse[gNum["expr"], "12 + 34"]
```

<!-- => {12, "+", 34} -->

[TPTPImport]() is this layer done for TPTP: 72 actions over the same grammar lift every clause to Wolfram Language terms. See [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP) for the action map.

```wl
TPTPImport["cnf(test, axiom, p)."]
```

<!-- => <|"Axioms" -> {"p"[]}, "Conjecture" -> None|> -->

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

What the lowering does not fix is the cost of a shared prefix. The higher-order rule `<thf_binary_assoc>` is an ordered choice whose three alternatives all begin with the same operand; lowered to a PEG with no memo, that operand is re-parsed once per alternative, and since an operand can itself be a parenthesised formula the cost grows as $3^{\text{depth}}$. [TPTPImport]() replaces `<thf_logic_formula>` with a [ParseOperatorTable]() through the `"PrimitiveOverrides"` option, so each operand is parsed once and the connectives are consumed by precedence - every other rule is the lowered grammar.

---

## What the grammar gives you

- **The recogniser, done.** 338 rules lowered, the two PEG-vs-CFG rewrites applied automatically. Real TPTP problems with quantifiers, function application, equality and multi-term Boolean connectives parse end to end.
- **Grammar tracking.** When the upstream TPTP grammar changes version, re-running [EBNFParse]() on the new file re-derives the parser; the actions only need touching where a rule's shape changed.
- **Single source of truth.** The grammar is the parser definition; the parser cannot disagree with the published grammar.

---

## Try it

The tests in ``Tests/EBNF.wlt`` cover the unit cases above plus the five-clause group-theory TPTP problem end-to-end, against the same pinned [TPTPWorld grammar](https://github.com/TPTPWorld/SyntaxBNF). To experiment, the classic $a^n b^n$ grammar:

```wl
anbn = EBNFParse["<S> ::= a <S> b | <epsilon>
                  <epsilon> ::="]
```

```wl
Parse[anbn["S"], "aaabbb"]
```

<!-- => {"a", {"a", {"a", Null, "b"}, "b"}, "b"} -->

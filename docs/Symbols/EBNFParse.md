---
Template: Symbol
Name: EBNFParse
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/EBNFParse
Keywords: [ebnf, bnf, grammar, meta-grammar, parser generator, lowering, left recursion, tptp, syntaxbnf, combinator]
SeeAlso: [EBNFRules, Parse, ParseAction, ParseChoice, ParseRecursive, ParseOperatorTable, TPTPImport, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[EBNFParse]()[*source*]</code> reads a BNF / EBNF grammar from the string *source* and returns an [Association]() mapping each rule name to the [ParserCombinator]() it lowers to.

<code>[EBNFParse]()[[File]()[*path*]]</code> reads the grammar from a file.

## Details & Options

- A grammar rule has the shape `<name> ::= alt1 | alt2 | …`: a non-terminal name in angle brackets, an arrow, then alternatives separated by `|`. Each alternative is a whitespace-separated sequence of elements.
- In a rule body a non-terminal reference `<name>` lowers to a recursive reference resolved at parse time (through [ParseRecursive]()), a bare token lowers to a [ParseLiteral](), and a postfix `<name>*` lowers to a [ParseMany]().
- Whitespace between adjacent elements is consumed automatically, so `12+34` and `12 + 34` both parse.
- Each value in the returned association is the parser for one rule; run it on input with [Parse]().
- Four arrow kinds are recognized: `::=` (syntactic), `:==` (semantic, same surface shape), `::-` (token construction), and `:::` (character class). The `::-` and `:::` bodies compile through a regex-style meta-parser that handles classes (`[a-z]`, `[^*]`), grouping (`(x|y)`), references (`<name>`), and the postfix operators `*`, `+`, `?`.
- A directly left-recursive rule `A ::= A r | b` is rewritten to the equivalent `A ::= b (r)*` before lowering; indirect (mutual) left recursion is not rewritten.
- Each rule's alternatives are sorted longest-first by element count, so a longer shared-prefix alternative is tried before a shorter one.
- The BNF source is itself parsed by a grammar built entirely from `Parse*` combinators — see the tutorial [Parsing BNF Grammars](paclet:Wolfram/Parser/tutorial/ParsingBNFGrammars).

| Option | Default | Description |
| --- | --- | --- |
| `"PrimitiveOverrides"` | `<||>` | an association of parsers to bind for named non-terminals — used to plug in lexical primitives (or override any rule) |
| `"Actions"` | `<||>` | an association of per-rule functions that transform a rule's parse result, wrapping that rule's parser in [ParseAction]() |
| `"ChoiceMode"` | `"Auto"` | how alternatives combine: `"PEG"` (first match wins), `"Longest"` (longest match wins), or `"Auto"` (longest match only when alternatives have equal element counts) |

## Basic Examples

Read a three-rule arithmetic grammar; the result is an association keyed by rule name:

```wl
g = EBNFParse["
    <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
    <number> ::= <digit><digit>*
    <expr>   ::= <number> + <number>
"];
Keys[g]
```

<!-- => {"digit", "number", "expr"} -->

<!-- #| annotation: 26.07.26: Design review - EBNFParse bootstraps a parser for a language directly from its published BNF, using nothing but this paclet's own Parse* combinators (the meta-grammar that reads the BNF is itself combinator-built). It differs from a classical parser generator (yacc/bison, ANTLR) in kind: those emit parser source in a separate build step, whereas EBNFParse returns live ParserCombinator values in one call, so the grammar IS the parser and re-running on an updated grammar re-derives it with no code regeneration. Scope is deliberately honest - it rewrites direct left recursion and approximates left-factoring by longest-first sorting, but does not handle indirect/mutual left recursion (Paull's algorithm), and the lowered output is a bare recogniser tree unless an "Actions" map lifts it. TPTPImport is the worked end-to-end consumer. -->

---

Each rule name maps to the parser combinator it lowers to:

```wl
g["number"]
```

<!-- => ParserCombinator[Action] (the lowered <number> parser, a summary box) -->

---

Run one of the lowered rules on input with [Parse]():

```wl
Parse[g["number"], "12345"]
```

<!-- => {"1", {"2", "3", "4", "5"}} -->

---

The `<expr>` rule composes the other rules, and the whitespace around `+` is optional:

```wl
Parse[g["expr"], "12 + 34"]
```

<!-- => {{"1", {"2"}}, "+", {"3", {"4"}}} -->

## Scope

Read the grammar from a file with [File]():

```wl
path = FileNameJoin[{$TemporaryDirectory, "greeting.bnf"}];
Export[path, "<greeting> ::= hello | bye", "Text"];
gFile = EBNFParse[File[path]];
Parse[gFile["greeting"], "bye"]
```

<!-- => "bye" -->

---

A recursive rule — the classic $a^n b^n$ language — parses by referring to itself, with an empty `<epsilon>` alternative for the base case:

```wl
anbn = EBNFParse["<S> ::= a <S> b | <epsilon>
                  <epsilon> ::="];
Parse[anbn["S"], "aaabbb"]
```

<!-- => {"a", {"a", {"a", Null, "b"}, "b"}, "b"} -->

---

The empty `<epsilon>` alternative matches the empty string, so the base case succeeds:

```wl
Parse[anbn["S"], ""]
```

<!-- => Null -->

---

`::-` (token) and `:::` (character-class) rules compile through the regex-style meta-parser:

```wl
charGram = EBNFParse["<word>  ::- <lower><lower>*
<lower> ::: [a-z]"];
Parse[charGram["word"], "hello"]
```

<!-- => "hello" -->

### The "Actions" option

An `"Actions"` entry wraps a rule's parser in [ParseAction](), lifting that rule's raw parse tree to a value — here the `<number>` tree to an integer:

```wl
gAct = EBNFParse[
    "<digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
     <number> ::= <digit><digit>*",
    "Actions" -> <|"number" -> Function[FromDigits @ StringJoin[#1, StringJoin @ #2]]|>
];
Parse[gAct["number"], "42"]
```

<!-- => 42 -->

### The "PrimitiveOverrides" option

`"PrimitiveOverrides"` binds a parser for a non-terminal the grammar names but does not define — here the lexical token `<word>`, supplied as a [ParseRegex]():

```wl
gOver = EBNFParse["<greeting> ::= <word>",
    "PrimitiveOverrides" -> <|"word" -> ParseRegex["[a-z]+"]|>];
Parse[gOver["greeting"], "hello"]
```

<!-- => "hello" -->

### The "ChoiceMode" option

With `"ChoiceMode" -> "PEG"` alternatives are tried in order and the first match commits, so `a` matches and leaves `b` unconsumed:

```wl
pegTok = EBNFParse["<tok> ::= a | ab", "ChoiceMode" -> "PEG"];
Parse[pegTok["tok"], "ab"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "<end of input>", "Found" -> "b"|>] -->

---

The default `"Auto"` uses longest-match when a rule's alternatives have equal length, so the longer `ab` alternative wins:

```wl
autoTok = EBNFParse["<tok> ::= a | ab"];
Parse[autoTok["tok"], "ab"]
```

<!-- => "ab" -->

---

`"Longest"` always takes the longest-matching alternative, regardless of element counts:

```wl
lngTok = EBNFParse["<tok> ::= a | ab", "ChoiceMode" -> "Longest"];
Parse[lngTok["tok"], "ab"]
```

<!-- => "ab" -->

## Properties and Relations

[EBNFRules]() exposes the same rules *before* lowering; the keys of the [EBNFParse]() result are exactly the rule names it lists:

```wl
Keys @ EBNFParse["<digit> ::= 0 | 1
                  <number> ::= <digit><digit>*"]
```

<!-- => {"digit", "number"} -->

---

[TPTPImport]() is [EBNFParse]() applied to the published TPTP `SyntaxBNF` grammar together with an `"Actions"` map; the same construction, driven from a file that changes with the spec, is described in [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP). The THF connective grammar it produces is parsed through [ParseOperatorTable]().

## Possible Issues

A non-terminal named in a rule body but never defined (and not supplied via `"PrimitiveOverrides"`) lowers to a failing parser:

```wl
Parse[EBNFParse["<greeting> ::= <word>"]["greeting"], "hello"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "No parser bound for non-terminal: word", "Found" -> ""|>] -->

---

When a name has both a `::=` and a `:==` definition, the syntactic (`::=`) body is kept; the semantic body is not lowered separately. Indirectly left-recursive and deeply ambiguous grammars (the TPTP `<thf_*>` higher-order rules) can still backtrack exponentially — [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP) covers the boundary.

## Neat Examples

A miniature TPTP grammar, mixing `::=` syntactic rules, a `::-` token rule, and `:::` character classes, with an `"Actions"` map that partitions clauses into a workable shape:

```wl
mini = EBNFParse["<TPTP_file>     ::= <cnf_annotated>*
<cnf_annotated> ::= cnf(<name>, <role>, <atom>).
<name>          ::= <lower_word>
<role>          ::= <lower_word>
<atom>          ::= <lower_word>
<lower_word>    ::- <lower_alpha><alpha_numeric>*
<lower_alpha>   ::: [a-z]
<alpha_numeric> ::: [a-zA-Z0-9_]",
    "Actions" -> <|
        "cnf_annotated" -> Function[<|"Role" -> #5, "Atom" -> #7|>],
        "TPTP_file" -> Function[
            <|"Axioms" -> Map[#["Atom"] &, Cases[{##}, KeyValuePattern["Role" -> "axiom"]]]|>]
    |>];
Parse[mini["TPTP_file"], "cnf(t1, axiom, p).cnf(t2, axiom, q).cnf(t3, hypothesis, r)."]
```

<!-- => <|"Axioms" -> {"p", "q"}|> -->

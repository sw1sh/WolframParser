---
Template: Symbol
Name: EBNFParse
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/EBNFParse
Keywords: [ebnf, bnf, grammar, meta-grammar, parser generator, lowering, left recursion, tptp, syntaxbnf, combinator]
SeeAlso: [EBNFRules, Parse, ParseAction, ParseChoice, ParseRecursive, ParseOperatorTable, TPTPImport, ABCBNF, ParserCombinator]
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
- With `"Dialect" -> "Classic"` the grammar is in the BNF of many language reports: `<name> ::=` or `<name> ::`, terminals in double or single quotes with `\n` `\r` `\t` escapes, non-terminals as `<name>` or a bare name, `[...]` for an optional part, `{...}` for a repeated one, `(...)` for a group, and `"a" | ... | "z"` for the characters from `a` to `z`. An optional part that is absent gives `Missing["NoMatch"]`.
- `"Whitespace"` names the characters skipped between elements; an element that itself begins with one of them, such as a space the grammar writes out, is not preceded by the skip. A rule in `"Tokens"` is matched without skipping, as is every rule it reaches, and its value is the text it matched; an AST node its action builds from that text carries the token's source span. A rule in `"Spans"` hands its action the `{start, end}` character span it matched, after its values.
- The BNF source is itself parsed by a grammar built entirely from `Parse*` combinators — see the tutorial [Parsing BNF Grammars](paclet:Wolfram/Parser/tutorial/ParsingBNFGrammars).

| Option | Default | Description |
| --- | --- | --- |
| `"PrimitiveOverrides"` | `<||>` | an association of parsers to bind for named non-terminals — used to plug in lexical primitives (or override any rule) |
| `"Actions"` | `<||>` | an association of per-rule functions that transform a rule's parse result, wrapping that rule's parser in [ParseAction]() |
| `"ChoiceMode"` | `"Auto"` | how alternatives combine: `"PEG"` (first match wins), `"Longest"` (longest match wins), or `"Auto"` (longest match only when alternatives have equal element counts) |
| `"Dialect"` | `"TPTP"` | the grammar's notation: `"TPTP"`, the one the TPTP project publishes, or `"Classic"` |
| `"Whitespace"` | `Automatic` | the characters skipped between elements, a pattern such as `" " \| "\t"`; `Automatic` skips any whitespace |
| `"Tokens"` | `{}` | rules matched without skipping, whose values are the text they matched |
| `"Spans"` | `{}` | rules whose actions also get the span they matched |

## Basic Examples

Read a three-rule arithmetic grammar; the result is an association of one parser per rule:

```wl
g = EBNFParse["
    <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
    <number> ::= <digit><digit>*
    <expr>   ::= <number> + <number>
"]
```

Its keys are the rule names:

```wl
Keys[g]
```

<!-- => {"digit", "number", "expr"} -->

<!-- #| annotation: 26.07.26: Design review - EBNFParse bootstraps a parser for a language directly from its published BNF, using nothing but this paclet's own Parse* combinators (the meta-grammar that reads the BNF is itself combinator-built). It differs from a classical parser generator (yacc/bison, ANTLR) in kind: those emit parser source in a separate build step, whereas EBNFParse returns live ParserCombinator values in one call, so the grammar IS the parser and re-running on an updated grammar re-derives it with no code regeneration. Scope is deliberately honest - it rewrites direct left recursion and approximates left-factoring by longest-first sorting, but does not handle indirect/mutual left recursion (Paull's algorithm), and the lowered output is a bare recogniser tree unless an "Actions" map lifts it. TPTPImport is the worked end-to-end consumer. -->

---

Each rule name maps to the parser combinator it lowers to:

```wl
g["number"]
```

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

Read the grammar from a file with [File]() - here one written out first, [Export]() giving back its path:

```wl
gFile = EBNFParse[File[Export[FileNameJoin[{$TemporaryDirectory, "greeting.bnf"}], "<greeting> ::= hello | bye", "Text"]]]
```

```wl
Parse[gFile["greeting"], "bye"]
```

<!-- => "bye" -->

---

A recursive rule — the classic $a^n b^n$ language — parses by referring to itself, with an empty `<epsilon>` alternative for the base case:

```wl
anbn = EBNFParse["<S> ::= a <S> b | <epsilon>
                  <epsilon> ::="]
```

```wl
Parse[anbn["S"], "aaabbb"]
```

<!-- => {"a", {"a", {"a", Null, "b"}, "b"}, "b"} -->

---

The empty `<epsilon>` alternative matches the empty string, so the base case succeeds:

```wl
Parse[anbn["S"], ""]
```

---

`::-` (token) and `:::` (character-class) rules compile through the regex-style meta-parser:

```wl
charGram = EBNFParse["<word>  ::- <lower><lower>*
<lower> ::: [a-z]"]
```

```wl
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
]
```

```wl
Parse[gAct["number"], "42"]
```

<!-- => 42 -->

### The "PrimitiveOverrides" option

`"PrimitiveOverrides"` binds a parser for a non-terminal the grammar names but does not define — here the lexical token `<word>`, supplied as a [ParseRegex]():

```wl
gOver = EBNFParse["<greeting> ::= <word>",
    "PrimitiveOverrides" -> <|"word" -> ParseRegex["[a-z]+"]|>]
```

```wl
Parse[gOver["greeting"], "hello"]
```

<!-- => "hello" -->

### The "ChoiceMode" option

With `"ChoiceMode" -> "PEG"` alternatives are tried in order and the first match commits, so `a` matches and leaves `b` unconsumed:

```wl
pegTok = EBNFParse["<tok> ::= a | ab", "ChoiceMode" -> "PEG"]
```

```wl
Parse[pegTok["tok"], "ab"]
```

---

The default `"Auto"` uses longest-match when a rule's alternatives have equal length, so the longer `ab` alternative wins:

```wl
autoTok = EBNFParse["<tok> ::= a | ab"]
```

```wl
Parse[autoTok["tok"], "ab"]
```

<!-- => "ab" -->

---

`"Longest"` always takes the longest-matching alternative, regardless of element counts:

```wl
lngTok = EBNFParse["<tok> ::= a | ab", "ChoiceMode" -> "Longest"]
```

```wl
Parse[lngTok["tok"], "ab"]
```

<!-- => "ab" -->

### The "Dialect" option

`"Dialect" -> "Classic"` reads quoted terminals, an optional part in `[...]` and a repeated one in `{...}`:

```wl
greet = EBNFParse["
    <greeting> :: 'hello' [\", \" <who>] { \"!\" }
    <who>      :: \"world\" | \"you\"",
    "Dialect" -> "Classic"]
```

The optional part present, and the exclamation repeated:

```wl
Parse[greet["greeting"], "hello, world!!"]
```

<!-- => {"hello", {", ", "world"}, {"!", "!"}} -->

An alternative that is only `...` between two one-character terminals stands for the characters between them:

```wl
digit = EBNFParse["<digit> :: \"0\" | ... | \"9\"", "Dialect" -> "Classic"]
```

```wl
Parse[digit["digit"], "7"]
```

<!-- => "7" -->

### The "Whitespace" and "Tokens" options

Here the space after `say` is part of the grammar, a word is a token, and spaces are skipped everywhere else:

```wl
say = EBNFParse["
    <say>    :: \"say\" <sp> <word>
    <sp>     :: \" \" [<sp>]
    <word>   :: <letter> [<word>]
    <letter> :: \"a\" | ... | \"z\"",
    "Dialect" -> "Classic", "Whitespace" -> " ", "Tokens" -> {"word"}]
```

The word comes back as the text it matched:

```wl
Parse[say["say"], "say   hi"]
```

<!-- => {"say", {" ", {" ", {" ", Missing["NoMatch"]}}}, "hi"} -->

The space after `say` is required, since the skip does not go before an element that begins with a space:

```wl
Parse[say["say"], "sayhi"]
```

### The "Spans" option

A rule in `"Spans"` gets the span it matched after its values, and a token's node carries its own:

```wl
assign = EBNFParse["
    <assign> :: <word> \"=\" <word>
    <word>   :: <letter> [<word>]
    <letter> :: \"a\" | ... | \"z\"",
    "Dialect" -> "Classic", "Whitespace" -> " ", "Tokens" -> {"word"}, "Spans" -> {"assign"},
    "Actions" -> <|"word" -> (LeafNode["Symbol", #, <||>] &), "assign" -> Function[{l, eq, r, span}, {l, r, span}]|>]
```

```wl
Parse[assign["assign"], "ab = cd"]
```

<!-- => {LeafNode["Symbol", "ab", <|"Source" -> {1, 3}|>], LeafNode["Symbol", "cd", <|"Source" -> {6, 8}|>], {1, 8}} -->

## Properties and Relations

[EBNFRules]() exposes the same rules *before* lowering; the keys of the [EBNFParse]() result are exactly the rule names it lists:

```wl
Keys @ EBNFParse["<digit> ::= 0 | 1
                  <number> ::= <digit><digit>*"]
```

<!-- => {"digit", "number"} -->

---

[ABCGrammar]() is [EBNFParse]() applied to [ABCBNF](), the grammar the ABC specification publishes, in the classic dialect, with `"Whitespace"`, `"Tokens"`, `"Spans"` and `"Actions"` for the prose around it; the ABC tech note covers it.

---

[TPTPImport]() is [EBNFParse]() applied to the published TPTP `SyntaxBNF` grammar together with an `"Actions"` map; the same construction, driven from a file that changes with the spec, is described in [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP). The THF connective grammar it produces is parsed through [ParseOperatorTable]().

## Possible Issues

A non-terminal named in a rule body but never defined (and not supplied via `"PrimitiveOverrides"`) lowers to a failing parser:

```wl
Parse[EBNFParse["<greeting> ::= <word>"]["greeting"], "hello"]
```

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
    |>]
```

Three clauses, two of them axioms:

```wl
Parse[mini["TPTP_file"], "cnf(t1, axiom, p).cnf(t2, axiom, q).cnf(t3, hypothesis, r)."]
```

<!-- => <|"Axioms" -> {"p", "q"}|> -->

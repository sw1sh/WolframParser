---
Template: Symbol
Name: ABCBNF
Context: Wolfram`Parser`Languages`ABC`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ABCBNF
Keywords: [ABC, BNF, grammar, specification, classic BNF, EBNFParse, parser generator]
SeeAlso: [ABCGrammar, EBNFParse, EBNFRules, ABCRun]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingABC, ParsingBNFGrammars]
---

## Usage

[ABCBNF]() is the grammar of the ABC language as its specification 1.06 publishes it, a string in the classic BNF dialect of [EBNFParse]().

## Details & Options

- The grammar is the specification's, as published at [cs.usu.edu.ru/langs/abc](https://web.archive.org/web/20240820091751/http://cs.usu.edu.ru/langs/spec_lang.html): sixteen rules with `::` arrows, quoted terminals, `[...]` for an optional part, and `"a" | ... | "z"` for a range of characters.
- [ABCGrammar]() builds the ABC parser by reading it with [EBNFParse](), `"Dialect" -> "Classic"`.
- The grammar sets no precedence for its operators and leaves two things to the prose around it: names are case insensitive, and the space it writes as `<SP>` is required after `print` and ignored everywhere else.

## Basic Examples

The grammar as the specification publishes it:

```wl
ABCBNF
```

The names of its rules, read by [EBNFRules]():

```wl
First /@ EBNFRules[ABCBNF, "Dialect" -> "Classic"]
```

<!-- => {"Program", "Line", "NamedCalc", "StopOp", "PrintOp", "Calc", "CalcList", "OP", "Name", "SymbolList", "Symbol", "Letter", "DigitList", "Digit", "NL", "SP"} -->

## Properties & Relations

[EBNFParse]() lowers every rule to a parser. `<Digit>`, written `"0" | ... | "9"`, reads one digit:

```wl
Parse[EBNFParse[ABCBNF, "Dialect" -> "Classic"]["Digit"], "7"]
```

<!-- => "7" -->

[ABCGrammar]() is the parser [EBNFParse]() makes of it, with actions for an algebra:

```wl
Parse[ABCGrammar[ABCSemantic], "max = a - b + b\nprint max"]
```

<!-- => {{"define", "max", {"+", {"-", "a", "b"}, "b"}}, {"print", "max"}} -->

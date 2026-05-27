---
Template: Guide
Name: WolframParser
Title: Parsing in the Wolfram Language
Context: Wolfram`WolframParser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/guide/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - parser combinators, EBNF grammars, and structured ASTs, all running locally.
Keywords: [parser, parsing, grammar, combinator, EBNF, parsec, AST]
RelatedGuides: [StringManipulation]
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)"]
---

## Abstract

The Wolfram Language has rich *piecewise* support for parsing: [StringExpression]() and [RegularExpression]() for regex-style patterns, [Interpreter]() for type-driven extraction from text, [CodeParser]() for parsing Wolfram code itself, and [GrammarRules]() for higher-level rule-based grammars (cloud-only). What it does not have is a single, general, *local* parser library that lets you compose your own grammar at any scale - the niche occupied by Parsec in Haskell, nom in Rust, or pyparsing in Python. `WolframParser` is meant to fill that niche.

The v0.1 release is a survey + scaffold. The tech note [ParserLandscape](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) is the design document; the library itself is being filled in iteratively from there.

## Functions

The function list will land alongside the implementation. The intended shape:

### Combinator entry point
- `WolframParse[parser, input]` run a parser on an input
- `Parser[...]` head for a parser expression - composable algebraic data
- Combinators: `Sequence`, `Choice`, `Many`, `Some`, `Optional`, `Between`, `SepBy`, `ChainLeft`, `ChainRight`, `Lookahead`, `Try`

### Declarative grammar
- `Grammar[rules]` an EBNF / GrammarRules-style declarative grammar
- `GrammarParse[grammar, input]` apply a `Grammar` to an input
- `GrammarToParser[grammar]` compile a `Grammar` into a `Parser`

### Token utilities
- `Tokenize[input, rules]` lex an input into a list of tagged tokens
- `Token[type, value, pos]` a tagged token with source position

### Diagnostics
- `ParseError` structured error with position and expected-tokens info
- `ExplainParseError[err]` human-readable rendering of a parse error

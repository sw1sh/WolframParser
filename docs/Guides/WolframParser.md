---
Template: Guide
Name: WolframParser
Title: Parsing in the Wolfram Language
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/guide/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - parser combinators, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution.
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile, LaTeX, TPTP, DSL]
RelatedGuides: [StringManipulation]
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)"]
---

## Abstract

The Wolfram Language has rich *piecewise* support for parsing: [StringExpression]() and [RegularExpression]() for regex-style patterns, [Interpreter]() for type-driven extraction from text, [CodeParser]() for parsing Wolfram code itself, and [GrammarRules]() for higher-level rule-based grammars (cloud-only). What it does not have is a single, general, *local* parser library that lets you compose your own grammar at any scale - the niche occupied by Parsec in Haskell, nom in Rust, or pyparsing in Python.

This paclet (context `Wolfram\`Parser\``) fills that niche. The strategy is twofold:

- **Reuse the [GrammarRules]() declarative DSL.** The same `"the weather in <city>" -> city` slot syntax that compiles to a CloudDeploy round-trip in the built-in path compiles to a local parser here, via [FunctionCompile]().
- **Expose a Parsec-style combinator core** for grammars that don't fit the declarative shape.

The v0.1 release is *design + scaffold*: two tech notes carry the design, the library code lands incrementally against them.

## Tech notes (read these first)

- [The Parser Landscape: a survey of existing tech](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) — what's already in WL and outside, where the gaps are
- [Design and Compilation Strategy](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy) — API, parser algebra, FunctionCompile lowering, worked targets (LaTeX math, TPTP)

## Functions (intended shape)

### Compile entry point
- `Parse[grammar, input]` run a grammar on an input (transparent JIT compile + memoise)
- `ParserCompile[grammar]` materialise a compiled parser function, the local analogue of [CloudDeploy](`)[`[GrammarRules](`)[...`]`]`
- `ParserFunction[...]` head for the compiled parser object

### Combinator core
- `Parser[...]` head for a parser expression (algebraic, inspectable)
- Combinators: `Sequence`, `Choice`, `Many`, `Some`, `Optional`, `Between`, `SepBy`, `ChainLeft`, `ChainRight`, `Lookahead` (`&`), `NotFollowedBy` (`!`), `Try`
- Operator overloads: `p1 | p2` (Choice), `p1 ~ p2` (Sequence), `p..` (Many), `p ..` (Some)

### Declarative grammars (GrammarRules-compatible)
- The same `GrammarRules[{"slot syntax" -> action}]` declarations accepted by the built-in path
- `GrammarToken[type]` and `Restricted[type, constraints]` slot fillers work as in the built-in path

### Token utilities
- `Tokenize[input, rules]` lex an input into a list of tagged tokens
- `Token[type, value, pos]` a tagged token carrying source position

### Diagnostics
- `ParseError` structured error with position, rule, and expected-tokens
- `ExplainParseError[err]` "expected X at line L col C, saw Y" rendering

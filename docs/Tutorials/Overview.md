---
Template: Overview
Name: WolframParser
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/Overview
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile]
---

# WolframParser

## Guide

- [WolframParser](paclet:Wolfram/WolframParser/guide/WolframParser)

## Symbols

### The wrapper
- [ParserCombinator]()

### Run a parser
- [Parse]()
- [ParserCompile]()

### Terminals
- [ParseLiteral]()
- [ParseCharacter]()

### Composition
- [ParseSequence]()
- [ParseChoice]()
- [ParseBetween]()
- `ParseSepBy`, `ParseSepBy1`
- `ParseChainLeft`, `ParseChainRight`

### Repetition
- [ParseMany]()
- [ParseSome]()
- [ParseOptional]()

### Lookahead, backtracking, recursion
- `ParseLookahead`, `ParseNotFollowedBy`
- `ParseTry`
- `ParseRecursive` - lazy symbol-ref for cyclic / mutually-recursive grammars

### Action and declarative grammars
- [ParseAction]()
- `Parse[GrammarRules[{...}], input]` - the [GrammarRules]() declarative DSL is accepted as input and lowered locally (no [CloudDeploy]() round-trip)

### LaTeX math
- `LaTeXMathParse[texSource]` - parse LaTeX math notation to a box expression suitable for an `InlineFormula` cell. Handles font-style commands (`\mathbb`, `\mathcal`, `\mathfrak`), fractions, roots, sub/superscripts, big operators, Greek letters, parens, and a long list of named symbols (`\leq`, `\in`, `\cup`, `\to`, ...)

## Tutorials

- [The Parser Landscape: a survey of existing tech](paclet:Wolfram/WolframParser/tutorial/ParserLandscape)
- [Design and Compilation Strategy](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy)

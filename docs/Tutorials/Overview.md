---
Template: Overview
Name: WolframParser
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/Overview
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile]
---

# WolframParser

## Guide

- [WolframParser](paclet:Wolfram/Parser/guide/WolframParser)

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

- [The Parser Landscape: a survey of existing tech](paclet:Wolfram/Parser/tutorial/ParserLandscape)
- [Design and Compilation Strategy](paclet:Wolfram/Parser/tutorial/DesignAndCompilationStrategy)
- [Parsing GrammarRules Locally](paclet:Wolfram/Parser/tutorial/ParsingGrammarRules)
- [A Markdown Inline Parser in Parser Combinators](paclet:Wolfram/Parser/tutorial/ParsingMarkdownInline)
- [Implementing the LaTeX Math Parser](paclet:Wolfram/Parser/tutorial/LaTeXMathParserImplementation)
- [Parsing BNF Grammars](paclet:Wolfram/Parser/tutorial/ParsingBNFGrammars)
- [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP)

---
Template: Overview
Name: WolframParser
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/Overview
Keywords: [parser, parsing, grammar, combinator, operator precedence, GrammarRules, EBNF, TPTP, LaTeX, FunctionCompile]
---

# WolframParser

A general, composable parser-combinator library for the Wolfram Language: build a
parser of arbitrary complexity locally, run it with [Parse](), and lower it to a
single compiled function or an LPEG-style machine with [ParserCompile](). It
reuses the [GrammarRules]() declarative DSL, parses BNF / EBNF grammars
([EBNFParse]()), ships domain parsers for LaTeX math, Markdown, and TPTP, and
covers operator-precedence expression grammars with a Pratt engine
([ParseOperatorTable]()).

## Guide

- [WolframParser](paclet:Wolfram/Parser/guide/WolframParser)

## Symbols

### The wrapper
- [ParserCombinator]() - the single head every parser normalises to
- `ParserCombinatorQ` - test for a normalised combinator

### Run a parser
- [Parse]() - run a parser, requiring it to consume the whole input
- `ParsePartial` - run a parser, returning `{result, leftover}`
- [ParserCompile]() - lower to a compiled function (default) or an LPEG-style `"PEGVM"` machine

### Terminals
- [ParseLiteral]() - match an exact string
- [ParseCharacter]() - match one character against a class
- `ParseRegex` - match as much as a PCRE-style regex consumes
- `ParseSucceed`, `ParseFail` - the always-succeed / always-fail leaves

### Composition
- [ParseSequence]() - match parsers in order
- [ParseChoice]() - PEG-ordered alternation (first match wins)
- `ParseChoiceLongest` - POSIX longest-match alternation, for shared-prefix alternatives
- [ParseBetween]() - bracketed `open p close`
- `ParseSepBy`, `ParseSepBy1` - separated lists

### Repetition
- [ParseMany]() - zero or more
- [ParseSome]() - one or more
- [ParseOptional]() - zero or one

### Operator precedence
- `ParseChainLeft`, `ParseChainRight` - a single left- / right-associative operator level
- [ParseOperatorTable]() - a full precedence table by Pratt / TDOP binding-power climbing; linear where an ordered-choice cascade over a shared operand backtracks exponentially. See [TDOP vs PEG](paclet:Wolfram/Parser/tutorial/PrattVsPEG)

### Lookahead, backtracking, recursion
- `ParseLookahead`, `ParseNotFollowedBy` - zero-width positive / negative assertions
- `ParseTry` - restore the position on failure (opt back into full backtracking)
- `ParseRecursive` - lazy symbol-ref for cyclic / mutually-recursive grammars

### Action and declarative grammars
- [ParseAction]() - run a parser and transform its result
- `Parse[GrammarRules[{...}], input]` - the [GrammarRules]() declarative DSL is accepted as input and lowered locally (no [CloudDeploy]() round-trip)
- `EBNFParse`, `EBNFRules` - read a BNF / EBNF grammar string into an association of named parsers

### Domain parsers
- `LaTeXMathParse`, `LaTeXMathParser`, `LaTeXMathStyle` - parse LaTeX math notation (`\mathbb`, `\frac`, `\sum_{}^{}`, roots, sub/superscripts, named symbols) to a box expression for an `InlineFormula` cell
- `MarkdownInlineParse`, `MarkdownParse` - Markdown inline / block structure
- `TPTPImport`, `TPTPExport` - the TPTP theorem-prover formats (CNF / FOF / TFF / TCF / THF), with THF connectives parsed through [ParseOperatorTable]()

## Tutorials

- [The Parser Landscape: a survey of existing tech](paclet:Wolfram/Parser/tutorial/ParserLandscape)
- [Design and Compilation Strategy](paclet:Wolfram/Parser/tutorial/DesignAndCompilationStrategy)
- [TDOP vs PEG: Two Ways to Parse Operators](paclet:Wolfram/Parser/tutorial/PrattVsPEG)
- [Parsing GrammarRules Locally](paclet:Wolfram/Parser/tutorial/ParsingGrammarRules)
- [A Markdown Inline Parser in Parser Combinators](paclet:Wolfram/Parser/tutorial/ParsingMarkdownInline)
- [Implementing the LaTeX Math Parser](paclet:Wolfram/Parser/tutorial/LaTeXMathParserImplementation)
- [Wolfram Box Typesetting](paclet:Wolfram/Parser/tutorial/WolframBoxTypesetting)
- [A MaTeX Comparison Showcase](paclet:Wolfram/Parser/tutorial/MaTeXComparisonShowcase)
- [Parsing BNF Grammars](paclet:Wolfram/Parser/tutorial/ParsingBNFGrammars)
- [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP)
- [Code Analysis Internals](paclet:Wolfram/Parser/tutorial/CodeAnalysisInternals)

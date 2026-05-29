---
Template: Guide
Name: WolframParser
Title: Parsing in the Wolfram Language
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/guide/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - Parse* combinators around a single ParserCombinator wrapper, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution.
Keywords: [parser, parsing, grammar, combinator, ParserCombinator, GrammarRules, FunctionCompile, LaTeX, KaTeX, TPTP, DSL]
RelatedGuides: [StringManipulation]
RelatedTutorials: [ParserLandscape, DesignAndCompilationStrategy, ParsingGrammarRules, LaTeXMathParserImplementation, ParsingBNFGrammars, ParsingTPTP]
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)"]
---

## Abstract

<code>Wolfram\`Parser\`</code> is a Parsec-style parser combinator library: every parser is a [ParserCombinator]() value built from `Parse*` constructors, runnable directly via [Parse]() or compiled with [ParserCompile](). [GrammarRules]() declarations are lowered to the same combinators (no [CloudDeploy]() round-trip). [LaTeXMathParse]() is a working LaTeX-math parser built on the combinator core; [EBNFParse]() reads a BNF grammar file into a parser map.

## Functions

### Running a parser

- [Parse]() apply a parser to an input; returns its value or a [Failure]()
- [ParsePartial]() return `{result, leftover-suffix}` instead of requiring whole-input match
- [ParserCompile]() materialize the [FunctionCompile]()d form

### The wrapper

- [ParserCombinator]() the single computable head every parser is represented as
- [ParserCombinatorQ]() test whether an expression is a [ParserCombinator]()

### Terminals

- [ParseLiteral]() match an exact string
- [ParseCharacter]() match a single character against a character class
- [ParseSucceed]() always succeed with the given value, consuming nothing
- [ParseFail]() always fail with the given message

### Composition

- [ParseSequence]() each parser in order
- [ParseChoice]() the first that matches, PEG-ordered
- [ParseBetween]() open, then `p`, then close; the result is `p`'s
- [ParseSepBy]() zero or more `p` separated by `sep`
- [ParseSepBy1]() one or more `p` separated by `sep`
- [ParseChainLeft]() left-associative operator chain
- [ParseChainRight]() right-associative operator chain

### Repetition

- [ParseMany]() zero or more
- [ParseSome]() one or more
- [ParseOptional]() zero or one

### Lookahead / backtracking

- [ParseLookahead]() succeed iff `p` would match, consuming nothing
- [ParseNotFollowedBy]() succeed iff `p` would not match, consuming nothing
- [ParseTry]() backtrack on failure even after partial consumption

### Action / recursion

- [ParseAction]() apply a function to a parser's result
- [ParseRecursive]() defer the lookup of a parser definition until parse time

### Diagnostics

- `Failure["ParseError", ...]` structured failure with `"Position"`, `"Expected"`, `"Found"` keys

### LaTeX math

- [LaTeXMathParse]() parse LaTeX math source into a tree of Wolfram boxes

### BNF grammars

- [EBNFParse]() read a BNF grammar (a string or <code>[File]()[path]</code>) and return an <code>[Association]()[name -> [ParserCombinator]()]</code>
- [EBNFRules]() return the unlowered list of <code>[EBNFRule]()[name, kind, body]</code> records

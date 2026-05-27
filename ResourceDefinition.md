---
Template: Paclet
ResourceType: Paclet
Name: Wolfram/WolframParser
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - parser combinators, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution
ContributedBy: Nikolay Murzin, Claude (Anthropic)
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile, LaTeX, TPTP, DSL]
MainGuide: Documentation/English/Guides/WolframParser.nb
License: MIT
WolframVersion: 14.0+
Categories: [Core Language & Structure]
Sources: ["Daan Leijen, *Parsec: Direct Style Monadic Parser Combinators for the Real World*, 2001", "Bryan Ford, *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*, POPL 2004"]
SourceControlURL: https://github.com/sw1sh/WolframParser
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)", "[AntonAntonov/FunctionalParsers (paclet)](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/)"]
---

## Details & Options

- The library reuses the [GrammarRules]() declarative slot-syntax DSL, but compiles each grammar to a local parser via [FunctionCompile]() instead of round-tripping through [CloudDeploy]().
- A Parsec-style combinator core covers grammars that don't fit the declarative shape (LaTeX math, TPTP formula bodies, custom DSLs with backtracking / lookahead).
- Operates uniformly on strings, on lists of tagged tokens, and on lists of Wolfram expressions (so the same combinators that lex a string can walk a [CodeParser]() AST).
- The kernel is dependency-free and has no C library; performance comes from [FunctionCompile]()'s LLVM backend.

## Usage

`v0.1` ships the two design tech notes - the survey of existing tech and the design / compilation strategy - and a placeholder kernel. The implementation lands incrementally against the design.

## Author Notes

This paclet was authored together with Anthropic's [Claude](https://www.anthropic.com/claude) (`claude-opus-4-7`). Claude wrote the prose, the kernel code, and the survey of existing parser tech; the human author chose the design direction, vetted the comparisons against the actual implementations, and integrated each iteration. AI-assisted authorship is disclosed here so a reader can weigh the source appropriately.

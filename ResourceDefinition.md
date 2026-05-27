---
Template: Paclet
ResourceType: Paclet
Name: Wolfram/WolframParser
Context: Wolfram`WolframParser`
Paclet: Wolfram/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - parser combinators, EBNF grammars, and structured ASTs, all running locally
ContributedBy: Nikolay Murzin, Claude (Anthropic)
Keywords: [parser, parsing, grammar, combinator, EBNF, parsec, AST, tokenization]
MainGuide: Documentation/English/Guides/WolframParser.nb
License: MIT
WolframVersion: 14.0+
Categories: [Core Language & Structure]
Sources: ["Daan Leijen, *Parsec: Direct Style Monadic Parser Combinators for the Real World*, 2001", "Bryan Ford, *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*, POPL 2004"]
SourceControlURL: https://github.com/sw1sh/WolframParser
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)", "[AntonAntonov/FunctionalParsers (paclet)](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/)"]
---

## Details & Options

- The library combines parser combinators ([Parsec]()-style), declarative EBNF / GrammarRules-style grammars, and a token-oriented core that works on strings, lists of tokens, and lists of Wolfram expressions.
- It runs entirely locally - in contrast to [GrammarRules](), which requires cloud deployment.
- The kernel is dependency-free.

## Usage

`v0.1` ships only the survey tech note. The implementation is being filled in iteratively; see the survey for the design problem and the [Tutorials](#tutorials) for what each piece is meant to look like.

## Author Notes

This paclet was authored together with Anthropic's [Claude](https://www.anthropic.com/claude) (`claude-opus-4-7`). Claude wrote the prose, the kernel code, and the survey of existing parser tech; the human author chose the design direction, vetted the comparisons against the actual implementations, and integrated each iteration. AI-assisted authorship is disclosed here so a reader can weigh the source appropriately.

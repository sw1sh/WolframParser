---
Template: Paclet
ResourceType: Paclet
Name: Wolfram/WolframParser
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - parser combinators, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution, a LaTeX math parser at 100% KaTeX corpus coverage
ContributedBy: Nikolay Murzin, Claude (Anthropic)
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile, LaTeX, KaTeX, TPTP, DSL]
MainGuide: Documentation/English/Guides/WolframParser.nb
License: MIT
WolframVersion: 14.0+
Categories: [Core Language & Structure]
Sources: ["Daan Leijen, *Parsec: Direct Style Monadic Parser Combinators for the Real World*, 2001", "Bryan Ford, *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*, POPL 2004"]
SourceControlURL: https://github.com/sw1sh/WolframParser
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)", "[AntonAntonov/FunctionalParsers (paclet)](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/)", "[KaTeX screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml)"]
RelatedResources: [Wolfram/MarkdownToNotebook, Wolfram/PAdic]
---

## Details & Options

- The library reuses the [GrammarRules]() declarative slot-syntax DSL, but compiles each grammar to a local parser via [FunctionCompile]() instead of round-tripping through [CloudDeploy](). The supported subset of `GrammarRules` is mapped in the [Parsing GrammarRules Locally](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) tech note.
- A Parsec-style combinator core (`Parse*` constructors) covers grammars that don't fit the declarative shape: LaTeX math, custom DSLs with backtracking / lookahead, recursive descent over [CodeParser]() ASTs.
- A sub-context `Wolfram\`Parser\`LaTeX\`` ships `LaTeXMathParse[s]`, a working LaTeX math-mode parser at 126 / 126 coverage of [KaTeX's own screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml). Output is a Wolfram boxes tree (`FractionBox`, `SubsuperscriptBox`, `RadicalBox`, `GridBox`, ...) ready to drop into a notebook cell or wrap with [DisplayForm](paclet:ref/DisplayForm) for kernel-side rendering.
- Operates uniformly on strings, on lists of tagged tokens, and on lists of Wolfram expressions (so the same combinators that lex a string can walk a [CodeParser]() AST).
- The kernel is dependency-free and has no C library; performance comes from [FunctionCompile]()'s LLVM backend.

## Usage

```
PacletInstall["Wolfram/WolframParser"];
Needs["Wolfram`Parser`"];

(* a literal-string parser *)
Parse[ParseLiteral["foo"], "foo"]
(* "foo" *)

(* a one-or-more digit parser, with an action that converts to Integer *)
digits = ParseAction[ParseSome[ParseCharacter[DigitCharacter]], FromDigits @ StringJoin[{##}] &];
Parse[digits, "12345"]
(* 12345 *)

(* a GrammarRules-flavoured slot template, parsed locally *)
Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
(* 8 *)

(* a LaTeX math expression *)
Needs["Wolfram`Parser`LaTeX`"];
LaTeXMathParse["\\frac{x^2}{y^2} = z^2"]
(* RowBox[{FractionBox[SuperscriptBox["x", "2"], SuperscriptBox["y", "2"]], "=", SuperscriptBox["z", "2"]}] *)
```

## Author Notes

This paclet was authored together with Anthropic's [Claude](https://www.anthropic.com/claude) (`claude-opus-4-7`). Claude wrote the prose, the kernel code, and the survey of existing parser tech; the human author chose the design direction, vetted the comparisons against the actual implementations, and integrated each iteration. AI-assisted authorship is disclosed here so a reader can weigh the source appropriately.

---
Template: Paclet
ResourceType: Paclet
Name: Wolfram/WolframParser
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
Description: Parser combinators for the Wolfram Language - GrammarRules compatible, locally compiled, with a LaTeX math parser
ContributedBy: Nikolay Murzin, Claude (Anthropic)
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile, LaTeX, KaTeX, TPTP, DSL]
MainGuide: Documentation/English/Guides/WolframParser.nb
License: MIT
WolframVersion: 14.0+
Categories: [Core Language & Structure]
Sources: ["Daan Leijen, *Parsec: Direct Style Monadic Parser Combinators for the Real World*, 2001", "Bryan Ford, *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*, POPL 2004"]
SourceControlURL: https://github.com/sw1sh/WolframParser
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)", "[AntonAntonov/FunctionalParsers (paclet)](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/)", "[KaTeX screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml)"]
RelatedResources: [Wolfram/MarkdownToNotebook]
---

## Details & Options

- The library reuses the [GrammarRules]() declarative slot-syntax DSL, but compiles each grammar to a local parser via [FunctionCompile]() instead of round-tripping through [CloudDeploy](). The supported subset of `GrammarRules` is mapped in the [Parsing GrammarRules Locally](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) tech note.
- A Parsec-style combinator core (`Parse*` constructors) covers grammars that don't fit the declarative shape: LaTeX math, custom DSLs with backtracking / lookahead, recursive descent over [CodeParser]() ASTs.
- [LaTeXMathParse]() is a working LaTeX math-mode parser at 126 / 126 coverage of [KaTeX's own screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml). Output is a tree of Wolfram boxes ([FractionBox](), [SubsuperscriptBox](), [RadicalBox](), [GridBox](), ...) ready to drop into a notebook cell or wrap with [DisplayForm](paclet:ref/DisplayForm) for kernel-side rendering.
- Operates uniformly on strings, on lists of tagged tokens, and on lists of Wolfram expressions (so the same combinators that lex a string can walk a [CodeParser]() AST).
- The kernel is dependency-free and has no C library; performance comes from [FunctionCompile]()'s LLVM backend.

## Usage

The package provides [Parse]() and [ParserCompile]() as the entry points, [ParserCombinator]() as the single computable head every constructor returns, and the `Parse*` family of constructors - [ParseLiteral](), [ParseCharacter](), [ParseSequence](), [ParseChoice](), [ParseMany](), [ParseSome](), [ParseOptional](), [ParseBetween](), [ParseAction](), [ParseRecursive](), [ParseLookahead](), [ParseNotFollowedBy](), [ParseTry](). [GrammarRules]() is accepted as input to `Parse` and lowered locally. [LaTeXMathParse]() parses LaTeX math-mode source to a tree of Wolfram boxes.

## Basic Examples

A literal-string parser:

```wl
Parse[ParseLiteral["foo"], "foo"]
```

<!-- => "foo" -->

---

A one-or-more digit parser with an action that folds the captured digits into an integer:

```wl
Parse[
    ParseAction[
        ParseSome[ParseCharacter[DigitCharacter]],
        FromDigits @ StringJoin[{##}] &
    ],
    "12345"
]
```

<!-- => 12345 -->

---

A `GrammarRules` slot template, parsed locally (no `CloudDeploy` round-trip):

```wl
Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
```

<!-- => 8 -->

---

`LaTeXMathParse` on an inline math source - the output is a tree of Wolfram boxes ready to drop into a notebook cell:

```wl
LaTeXMathParse["\\frac{x^2}{y^2} = z^2"]
```

<!-- => RowBox[{FractionBox[SuperscriptBox["x", "2"], SuperscriptBox["y", "2"]], "=", SuperscriptBox["z", "2"]}] -->

## Hero Image

The parser in action: a raw LaTeX source string on top, an arrow, and
the tree of Wolfram boxes `LaTeXMathParse` produces below it (the
front end renders those boxes as typeset math).

```wl
With[{src = "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}"},
    Rasterize[
        Framed[
            Column[{
                Style[src, FontFamily -> "Source Code Pro", FontSize -> 22, GrayLevel[0.45]],
                Spacer[{0, 20}],
                Style["\[DownArrow]", FontSize -> 32, GrayLevel[0.7]],
                Spacer[{0, 20}],
                Style[DisplayForm @ LaTeXMathParse[src], FontSize -> 64, FontColor -> GrayLevel[0.15]]
            }, Alignment -> Center],
            Background -> GrayLevel[0.98], FrameMargins -> 80,
            FrameStyle -> GrayLevel[0.9], RoundingRadius -> 20,
            ImageSize -> {700, 500}
        ],
        ImageResolution -> 144, Background -> None
    ]
]
```

## Author Notes

This paclet was authored together with Anthropic's [Claude](https://www.anthropic.com/claude) (`claude-opus-4-7`). Claude wrote the prose, the kernel code, and the survey of existing parser tech; the human author chose the design direction, vetted the comparisons against the actual implementations, and integrated each iteration. AI-assisted authorship is disclosed here so a reader can weigh the source appropriately.

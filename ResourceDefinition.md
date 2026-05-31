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

- The library reuses the [GrammarRules](paclet:ref/GrammarRules) declarative slot-syntax DSL, but compiles each grammar to a local parser via [FunctionCompile](paclet:ref/FunctionCompile) instead of round-tripping through [CloudDeploy](paclet:ref/CloudDeploy). The supported subset of `GrammarRules` is mapped in the [Parsing GrammarRules Locally](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) tech note.
- A Parsec-style combinator core (`Parse*` constructors) covers grammars that don't fit the declarative shape: LaTeX math, custom DSLs with backtracking / lookahead, recursive descent over [CodeParser](paclet:ref/CodeParser) ASTs.
- [LaTeXMathParse](paclet:Wolfram/WolframParser/ref/LaTeXMathParse) is a working LaTeX math-mode parser at 126 / 126 coverage of [KaTeX's own screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml). Output is a tree of Wolfram boxes ([FractionBox](paclet:ref/FractionBox), [SubsuperscriptBox](paclet:ref/SubsuperscriptBox), [RadicalBox](paclet:ref/RadicalBox), [GridBox](paclet:ref/GridBox), ...) ready to drop into a notebook cell or wrap with [DisplayForm](paclet:ref/DisplayForm) for kernel-side rendering.
- Operates uniformly on strings, on lists of tagged tokens, and on lists of Wolfram expressions (so the same combinators that lex a string can walk a [CodeParser](paclet:ref/CodeParser) AST).
- The kernel is dependency-free and has no C library; performance comes from [FunctionCompile](paclet:ref/FunctionCompile)'s LLVM backend.

## Usage

The package provides [Parse](paclet:Wolfram/WolframParser/ref/Parse) and [ParserCompile](paclet:Wolfram/WolframParser/ref/ParserCompile) as the entry points, [ParserCombinator](paclet:Wolfram/WolframParser/ref/ParserCombinator) as the single computable head every constructor returns, and the `Parse*` family of constructors - [ParseLiteral](paclet:Wolfram/WolframParser/ref/ParseLiteral), [ParseCharacter](paclet:Wolfram/WolframParser/ref/ParseCharacter), [ParseSequence](paclet:Wolfram/WolframParser/ref/ParseSequence), [ParseChoice](paclet:Wolfram/WolframParser/ref/ParseChoice), [ParseMany](paclet:Wolfram/WolframParser/ref/ParseMany), [ParseSome](paclet:Wolfram/WolframParser/ref/ParseSome), [ParseOptional](paclet:Wolfram/WolframParser/ref/ParseOptional), [ParseBetween](paclet:Wolfram/WolframParser/ref/ParseBetween), [ParseAction](paclet:Wolfram/WolframParser/ref/ParseAction), [ParseRecursive](paclet:Wolfram/WolframParser/ref/ParseRecursive), [ParseLookahead](paclet:Wolfram/WolframParser/ref/ParseLookahead), [ParseNotFollowedBy](paclet:Wolfram/WolframParser/ref/ParseNotFollowedBy), [ParseTry](paclet:Wolfram/WolframParser/ref/ParseTry). [GrammarRules](paclet:ref/GrammarRules) is accepted as input to `Parse` and lowered locally. [LaTeXMathParse](paclet:Wolfram/WolframParser/ref/LaTeXMathParse) parses LaTeX math-mode source to a tree of Wolfram boxes.

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

The parser in action on a real-world formula (one of Maxwell's
equations): the raw LaTeX source on top, and below it the typeset result
`LaTeXMathParse` produces. The boxes are restyled with [LaTeXMathStyle](paclet:Wolfram/WolframParser/ref/LaTeXMathStyle)
into the same Computer-Modern face LaTeX itself uses, so the rendering is
faithful to the source - vector bold (`\mathbf`), Greek subscripts, and a
stacked partial-derivative fraction all land where TeX would put them.

```wl
With[{src = "\\nabla \\times \\mathbf{B} = \\mu_0 \\mathbf{J} + \\mu_0 \\epsilon_0 \\frac{\\partial \\mathbf{E}}{\\partial t}"},
    Rasterize[
        Framed[
            Column[{
                Style[src, FontFamily -> "Source Code Pro", FontSize -> 17, GrayLevel[0.55]],
                Spacer[{0, 14}],
                Style["LaTeXMathParse  \[LongRightArrow]", FontFamily -> "Source Code Pro", FontSize -> 13, GrayLevel[0.62]],
                Spacer[{0, 26}],
                Style[
                    RawBoxes @ StyleBox[LaTeXMathStyle @ LaTeXMathParse[src], ScriptLevel -> 0],
                    FontSize -> 52, FontColor -> GrayLevel[0.1]
                ]
            }, Alignment -> Center],
            Background -> GrayLevel[0.985], FrameMargins -> 64,
            FrameStyle -> GrayLevel[0.88], RoundingRadius -> 22,
            ImageSize -> {940, 460}
        ],
        ImageResolution -> 144, Background -> None
    ]
]
```

## Author Notes

This paclet was authored together with Anthropic's [Claude](https://www.anthropic.com/claude) (`claude-opus-4-7`). Claude wrote the prose, the kernel code, and the survey of existing parser tech; the human author chose the design direction, vetted the comparisons against the actual implementations, and integrated each iteration. AI-assisted authorship is disclosed here so a reader can weigh the source appropriately.

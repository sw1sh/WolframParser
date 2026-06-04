---
Template: Symbol
Name: LaTeXMathParse
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LaTeXMathParse
Keywords: [LaTeX, math, parser, KaTeX, FractionBox, SubsuperscriptBox, GridBox, RowBox, StyleBox, MathML]
SeeAlso: [Parse, ParserCombinator, FractionBox, SubsuperscriptBox, RadicalBox, GridBox, RowBox, StyleBox]
RelatedGuides: [WolframParser]
---

## Usage

<code>[LaTeXMathParse]()[$s$]</code> parses a LaTeX math-mode source string $s$ into a tree of Wolfram boxes ([FractionBox](), [SubsuperscriptBox](), [RadicalBox](), [GridBox](), [RowBox](), [StyleBox]()). Returns a [Failure]() (tagged `"ParseError"`) if the input is not parseable.

## Details & Options

- The parser handles the inline-math subset of LaTeX commonly written inside `$...$` or `\(...\)` (no preamble, no `\documentclass`).
- Output is a tree of Wolfram boxes, ready to drop into a notebook cell or wrap in [DisplayForm]() / [RawBoxes]() for rendering.
- 126 / 126 cases from [KaTeX's screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml) parse cleanly. See [Implementing the LaTeX Math Parser](paclet:Wolfram/Parser/tutorial/LaTeXMathParserImplementation) for the design and the corpus.
- The parser is tolerant: macros it doesn't know are emitted as their literal `\name` followed by their `{arg}` payload, so an unknown command doesn't abort the whole expression.

## Basic Examples

A simple fraction:

```wl
LaTeXMathParse["\\frac{a}{b}"]
```

<!-- => FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]] -->

Subscript / superscript / both:

```wl
{
    LaTeXMathParse["x^2"],
    LaTeXMathParse["a_i"],
    LaTeXMathParse["x_i^2"]
}
```

<!-- => {SuperscriptBox[StyleBox["x", "TI"], "2"], SubscriptBox[StyleBox["a", "TI"], StyleBox["i", "TI"]], SubsuperscriptBox[StyleBox["x", "TI"], StyleBox["i", "TI"], "2"]} -->

A named function:

```wl
LaTeXMathParse["\\sin x + \\cos y"]
```

<!-- => RowBox[{StyleBox["sin", FontSlant -> "Plain"], StyleBox["x", "TI"], "+", StyleBox["cos", FontSlant -> "Plain"], StyleBox["y", "TI"]}] -->

A matrix environment:

```wl
LaTeXMathParse["\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}"]
```

<!-- => RowBox[{"(", GridBox[{{StyleBox["a", "TI"], StyleBox["b", "TI"]}, {StyleBox["c", "TI"], StyleBox["d", "TI"]}}], ")"}] -->

A square root with an order:

```wl
LaTeXMathParse["\\sqrt[3]{x}"]
```

<!-- => RadicalBox[StyleBox["x", "TI"], "3"] -->

## Scope

Greek letters, named constants:

```wl
LaTeXMathParse["\\alpha + \\beta = \\pi"]
```

<!-- => RowBox[{"\[Alpha]", "+", "\[Beta]", "=", "\[Pi]"}] -->

Font styles `\mathbb`, `\mathcal`, `\mathfrak`:

```wl
{
    LaTeXMathParse["\\mathbb{R}"],
    LaTeXMathParse["\\mathcal{L}"],
    LaTeXMathParse["\\mathfrak{g}"]
}
```

<!-- => {"\[DoubleStruckCapitalR]", "\[ScriptCapitalL]", "\[GothicSmallG]"} -->

A `\left...\right` group with independent open / close delimiters:

```wl
LaTeXMathParse["\\left( x^2 \\right)"]
```

<!-- => RowBox[{"(", SuperscriptBox[StyleBox["x", "TI"], "2"], ")"}] -->

The mismatched-delimiter form (open `(`, close `]`) is also supported - the renderer sees both:

```wl
LaTeXMathParse["\\left( x \\right]"]
```

<!-- => RowBox[{"(", StyleBox["x", "TI"], "]"}] -->

## Properties and Relations

The result is a tree of WL boxes - drop into a notebook cell verbatim, or wrap with [DisplayForm]() for typeset display in the kernel:

```wl
DisplayForm @ LaTeXMathParse["\\sum_{i=1}^{n} \\frac{1}{i^2}"]
```

<!-- => the Basel-problem sum, rendered as typeset math -->

For the markdown-to-notebook pipeline, `LaTeXMathParse` is the routing target for `$...$` blocks: any time the markdown source contains inline LaTeX, [MarkdownToNotebook]() routes it through this parser to produce a proper math cell rather than a code-as-text cell.

## Possible Issues

The parser is *math-mode only*. `\text{...}` content is parsed *as if it were math* (with `$...$` toggles silently consumed), so prose with embedded math comes out approximate.

Some TeX shapes are deliberately not modeled: spacing rules (\thinspace, the implicit spaces around \mathop / \mathrel / \mathbin), big-delimiter visual sizing (\bigl(, \Bigl, ...), `\genfrac`'s six-argument `<delim><delim>{thk}{style}{num}{denom}` shape, `\substack`'s grid layout. The input parses but the visual output is approximate.

User-defined macros via `\def` / `\newcommand` are accepted as no-ops (their definition is discarded). A `\def\foo{...}\foo` will see `\foo` as an unknown command, not as the user-defined macro.

## Neat Examples

Maxwell's equation, parsed and rendered:

```wl
DisplayForm @ LaTeXMathParse[
    "\\oint_S \\vec{E} \\cdot \\hat{n} \\, dA = \\frac{q_{\\text{enc}}}{\\varepsilon_0}"
]
```

<!-- => the integral form of Gauss's law, typeset -->

End-to-end: count how many of KaTeX's own test cases parse cleanly:

```wl
cases = Association @ Import[
    FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Tests", "katex-cases.json"}]
];
Count[Values[cases], _ ? (! FailureQ[LaTeXMathParse[#]] &)]
```

<!-- => 126  (out of 126 total) -->

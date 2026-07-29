---
Template: Symbol
Name: ExportLaTeX
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ExportLaTeX
Keywords: [LaTeX, export, boxes, serialize, TeX, math, FractionBox, GridBox, matrix, Ket, inverse, round-trip]
SeeAlso: [LaTeXMathParse, LaTeXMathParser, LaTeXMathStyle, RawBoxes, FractionBox, TeXForm]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ExportLaTeX]()[*boxes*]</code> serializes a Wolfram box tree *boxes* to a LaTeX math string - the inverse of [LaTeXMathParse](). It also accepts a <code>[RawBoxes]()[*boxes*]</code> wrapper or a [Cell](), extracting the box content first.

## Details & Options

- [ExportLaTeX]() is the inverse direction of [LaTeXMathParse](): `boxes` -> LaTeX, where [LaTeXMathParse]() goes LaTeX -> `boxes`. Round-tripping <code>[LaTeXMathParse]() @ [ExportLaTeX]()[*boxes*]</code> reproduces the box tree.
- It returns the *body* of a math expression - no surrounding `$...$` delimiters, so the caller places it into inline or display math as needed.
- It handles the structural boxes ([FractionBox](), [SuperscriptBox](), [SubscriptBox](), [SqrtBox](), [RadicalBox](), the script/accent boxes) and [GridBox]() matrices, promoting an author's fence ( `(` `[` `{` `|` ) around a grid to the matching `pmatrix` / `bmatrix` / `Bmatrix` / `vmatrix` environment.
- Quantum and algebra [TemplateBox]() forms map to their commands: `Ket` -> <code>&#124;*x*\rangle</code>, `Bra` -> `\langle`*x*`|`, `Dagger` -> *x*`^\dagger`, `Norm` -> `\lVert`*x*`\rVert`, `Abs` -> `\lvert`*x*`\rvert`.
- A math-italic identifier of two or more letters ([StyleBox]() tagged `"TI"`) becomes `\mathit{...}` so TeX does not read it as a product of single letters; Greek and operator glyphs map to their TeX commands.
- An unknown box falls back to its [InputForm]() string, so the function is total: it always returns a string.

## Basic Examples

A fraction serializes to `\frac`:

```wl
ExportLaTeX[FractionBox["a", "b"]]
```

<!-- => "\frac{a}{b}" -->

A superscript:

```wl
ExportLaTeX[SuperscriptBox["x", "2"]]
```

<!-- => "x^{2}" -->

[ExportLaTeX]() is the inverse of [LaTeXMathParse]() - feed it that parser's output and it reconstructs the source:

```wl
ExportLaTeX[LaTeXMathParse["\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"]]
```

<!-- => "\frac{-b\pm \sqrt{b^{2}-4ac}}{2a}" -->

## Scope

A Greek glyph maps to its command:

```wl
ExportLaTeX["\[Alpha]"]
```

<!-- => "\alpha " -->

A quantum ket:

```wl
ExportLaTeX[TemplateBox[{"\[Psi]"}, "Ket"]]
```

<!-- => "|\psi \rangle " -->

A grid becomes a matrix environment; an author's parentheses around it promote it to `pmatrix`:

```wl
ExportLaTeX[RowBox[{"(", GridBox[{{"1", "0"}, {"0", "1"}}], ")"}]]
```

<!-- => "\begin{pmatrix}1 & 0 \\ 0 & 1\end{pmatrix}" -->

A two-or-more-letter italic identifier is wrapped in `\mathit` so it does not read as a product of letters:

```wl
ExportLaTeX[StyleBox["output", "TI"]]
```

<!-- => "\mathit{output}" -->

## Properties and Relations

`ExportLaTeX` and [LaTeXMathParse]() are inverse: a LaTeX source parsed to boxes and exported back reproduces the (normalized) source.

```wl
ExportLaTeX[LaTeXMathParse["x^2 + y^2 = z^2"]]
```

<!-- => "x^{2}+y^{2}=z^{2}" -->

It accepts a [RawBoxes]() wrapper, so the output of a typeset cell can be exported directly:

```wl
ExportLaTeX[RawBoxes[SqrtBox["2"]]]
```

<!-- => "\sqrt{2}" -->

It also accepts a [Cell](), extracting the [BoxData]() content:

```wl
ExportLaTeX[Cell[BoxData[SubscriptBox["x", "i"]], "Input"]]
```

<!-- => "x_{i}" -->

## Possible Issues

`ExportLaTeX` is total: an unrecognized box does not fail but falls back to its [InputForm]() text, which may not be valid LaTeX. Prefer feeding it boxes produced by [LaTeXMathParse]() or a typeset math cell.

```wl
ExportLaTeX[SomeUnknownBox[1, 2]]
```

<!-- => "SomeUnknownBox[1, 2]" -->

The result is the math *body* with no `$` delimiters; wrap it yourself to embed it in a document.

## Neat Examples

Round-trip a whole formula - parse LaTeX to boxes, restyle for display, then export the styled boxes back to LaTeX:

```wl
ExportLaTeX[LaTeXMathParse["\\sum_{i=1}^{n} \\frac{1}{i^2} = \\frac{\\pi^2}{6}"]]
```

<!-- => "\sum _{i=1}^{n}\frac{1}{i^{2}}=\frac{\pi^{2}}{6}" -->

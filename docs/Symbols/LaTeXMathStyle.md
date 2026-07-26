---
Template: Symbol
Name: LaTeXMathStyle
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LaTeXMathStyle
Keywords: [LaTeX, math, font, Computer Modern, Latin Modern, math italic, StyleBox, blackboard, MSBM, MaTeX, restyle]
SeeAlso: [LaTeXMathParse, LaTeXMathParser, StyleBox, RawBoxes, DisplayForm, FractionBox]
RelatedGuides: [WolframParser]
---

## Usage

<code>[LaTeXMathStyle]()[*boxes*]</code> restyles the box tree *boxes* - as produced by [LaTeXMathParse]() - into a Computer-Modern look matching LaTeX / MaTeX, auto-detecting the best installed Computer-Modern font.

<code>[LaTeXMathStyle]()[*boxes*, *font*]</code> wraps *boxes* in the named family *font* and restyles to it; <code>[LaTeXMathStyle]()[*boxes*, None]</code> returns *boxes* unchanged.

## Details & Options

- The parser is font-agnostic: [LaTeXMathParse]() tags every math-italic identifier as `StyleBox[`*letter*`, "TI"]` (the front end's default Times-based math italic). [LaTeXMathStyle]() rewrites those style tags into the chosen family's math look and wraps the whole tree in a [StyleBox]() carrying `FontFamily -> `*font*.
- With an OpenType *math* font (a family whose name contains `"Math"`, such as `"Latin Modern Math"`), each italic letter is remapped to its math-italic (cmmi) *codepoint* - `StyleBox["x", "TI"]` becomes `StyleBox["𝑥"]` - because a math font carries the italic letterforms at the math-alphanumeric codepoints rather than via [FontSlant]().
- With a *text* font (`"Latin Modern Roman"`, `"CMU Serif"`), each italic letter instead gets `FontSlant -> Italic`.
- It recognizes the front end's short math style tags and rewrites each: `"TI"` (italic), `"TBI"` (bold italic), `"TB"` (bold), and `"TR"` (roman).
- Double-struck `\mathbb` letters (`ℝ ℂ ℤ ℕ ℚ …`) render in the AMS blackboard font: when `MSBM10.otf` is installed they are wrapped in the `"MSBM10"` family to match real LaTeX; otherwise they stay in the outer family.
- With no *font* argument the family is auto-detected, trying `"Latin Modern Math"`, then `"Latin Modern Roman"`, then `"CMU Serif"`. If none is installed the detected font is [None]() and *boxes* is returned unchanged.
- A [Failure]() (for example the tagged `"ParseError"` from an unparseable [LaTeXMathParse]() call) or [$Failed]() is returned unchanged, so <code>[LaTeXMathStyle]() @ [LaTeXMathParse]()[*s*]</code> is safe to write over input that may not parse.

## Basic Examples

[LaTeXMathParse]() produces font-agnostic boxes, with identifiers tagged `"TI"`:

```wl
frac = LaTeXMathParse["\\frac{a}{b}"]
```

<!-- => FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]] -->

<!-- #| annotation: 26.07.26: Design review - LaTeXMathStyle restyles the front end's own boxes into a Computer-Modern face with no external toolchain. It positions against MaTeX, which shells out to a real LaTeX install (latex + dvisvgm) and returns genuine Computer Modern vector graphics: MaTeX is the gold standard for fidelity, LaTeXMathStyle is the toolchain-free approximation over live, editable boxes. The math-vs-text split is forced by OpenType: a math font (Latin Modern Math) carries cmmi italics at math-alphanumeric codepoints, so we remap codepoints; a text font has no such block, so we fall back to FontSlant. Alternative name considered: LaTeXMathFontStyle. -->

Restyle to an OpenType math font - italic letters are remapped to their math-italic codepoints and the whole tree is wrapped in the family:

```wl
LaTeXMathStyle[frac, "Latin Modern Math"]
```

<!-- => StyleBox[FractionBox[StyleBox["𝑎"], StyleBox["𝑏"]], FontFamily -> "Latin Modern Math"]  (𝑎 𝑏 are math-italic a, b at U+1D44E, U+1D44F) -->

---

Restyle to a text font instead - here italic letters get `FontSlant -> Italic`:

```wl
LaTeXMathStyle[frac, "CMU Serif"]
```

<!-- => StyleBox[FractionBox[StyleBox["a", FontSlant -> Italic], StyleBox["b", FontSlant -> Italic]], FontFamily -> "CMU Serif"] -->

## Scope

A single tagged atom is the unit the rewrite works on - a `"TI"` letter under a math font becomes its math-italic codepoint:

```wl
LaTeXMathStyle[StyleBox["x", "TI"], "Latin Modern Math"]
```

<!-- => StyleBox[StyleBox["𝑥"], FontFamily -> "Latin Modern Math"]  (𝑥 is math-italic x, U+1D465) -->

---

The same atom under a text font keeps its glyph and gets a slant:

```wl
LaTeXMathStyle[StyleBox["x", "TI"], "CMU Serif"]
```

<!-- => StyleBox[StyleBox["x", FontSlant -> Italic], FontFamily -> "CMU Serif"] -->

---

A bold-italic `"TBI"` tag maps to explicit [FontWeight]() and [FontSlant]() directives:

```wl
LaTeXMathStyle[StyleBox["v", "TBI"], "CMU Serif"]
```

<!-- => StyleBox[StyleBox["v", FontWeight -> Bold, FontSlant -> Italic], FontFamily -> "CMU Serif"] -->

---

With no *font* argument the family is auto-detected from the installed fonts:

```wl
LaTeXMathStyle[frac]
```

<!-- => the boxes remapped and wrapped in the first detected CM family (Latin Modern Math on this machine), or returned unchanged if no CM font is installed -->

---

Passing [None]() for *font* is an explicit no-op, returning the boxes untouched:

```wl
LaTeXMathStyle[frac, None]
```

<!-- => FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]] -->

---

A `\mathbb` letter parses to a bare double-struck character, which [LaTeXMathStyle]() routes to the blackboard font when `MSBM10.otf` is installed:

```wl
LaTeXMathStyle[LaTeXMathParse["\\mathbb{R}"], "Latin Modern Math"]
```

<!-- => StyleBox[StyleBox["\[DoubleStruckCapitalR]", FontFamily -> "MSBM10"], FontFamily -> "Latin Modern Math"]  (the inner MSBM10 wrap appears only when MSBM10.otf is installed) -->

## Properties and Relations

[LaTeXMathStyle]() restyles only the parser's style tags; it leaves structure ([FractionBox](), [SuperscriptBox](), …) intact. A named operator, tagged upright by the parser, stays upright while the variable beside it goes italic:

```wl
LaTeXMathStyle[LaTeXMathParse["\\sin x"], "Latin Modern Math"]
```

<!-- => StyleBox[RowBox[{StyleBox["sin", FontSlant -> "Plain"], " ", StyleBox["𝑥"]}], FontFamily -> "Latin Modern Math"] -->

---

A [Failure]() passes straight through, so styling an unparseable source returns the failure itself:

```wl
bad = LaTeXMathParse["{unclosed"];
LaTeXMathStyle[bad, "Latin Modern Math"] === bad
```

<!-- => True -->

## Possible Issues

When no Computer-Modern font is installed, auto-detection returns [None]() and the boxes come back unchanged - the same as passing [None]() explicitly. Force a family with the two-argument form if you need a specific face regardless of what is installed.

The blackboard remap depends on `MSBM10.otf`. When that font is installed, double-struck `\mathbb` letters are routed to the `"MSBM10"` family regardless of the outer *font* (as in the Scope example above); when it is absent they are not rerouted and simply inherit the outer family.

[LaTeXMathStyle]() rewrites the short style tags; a style already expanded to explicit directives - for example the `FontWeight -> "Bold"` that `\mathbf` emits - is left as is and only picks up the outer family wrap:

```wl
LaTeXMathStyle[LaTeXMathParse["\\mathbf{v}"], "CMU Serif"]
```

<!-- => StyleBox[StyleBox["v", FontWeight -> "Bold", FontSlant -> "Plain"], FontFamily -> "CMU Serif"] -->

## Neat Examples

Parse and restyle a whole formula - every italic identifier in the quadratic formula is remapped to its math-italic codepoint, the structure untouched:

```wl
quad = LaTeXMathParse["x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"];
LaTeXMathStyle[quad, "Latin Modern Math"]
```

<!-- => StyleBox[RowBox[{StyleBox["𝑥"], "=", FractionBox[RowBox[{"-", StyleBox["𝑏"], "±", SqrtBox[RowBox[{SuperscriptBox[StyleBox["𝑏"], "2"], "-", "4", StyleBox["𝑎"], StyleBox["𝑐"]}]]}], RowBox[{"2", StyleBox["𝑎"]}]]}], FontFamily -> "Latin Modern Math"] -->

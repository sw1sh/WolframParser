---
Template: TechNote
Name: WolframBoxTypesetting
Title: The Wolfram Box Typesetting Reference
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/WolframBoxTypesetting
Keywords: [boxes, typesetting, RowBox, GridBox, FractionBox, SqrtBox, RadicalBox, SubscriptBox, SuperscriptBox, SubsuperscriptBox, UnderoverscriptBox, StyleBox, AdjustmentBox, FrameBox, Magnification, FractionLine, ColumnAlignments, LimitsPositioning, DisplayForm, RawBoxes, MakeBoxes, notebook, spacing]
RelatedGuides: [WolframParser]
RelatedTutorials: [LaTeXMathParserImplementation, DesignAndCompilationStrategy]
---

## Why this reference exists

[LaTeXMathParse]() turns TeX source into a tree of *boxes* - the low-level
expressions the Wolfram notebook front end (FE) typesets into two-dimensional
math. There is no single official "box typesetting manual": the knowledge is
spread across the [Low-Level Notebook Structure](https://reference.wolfram.com/language/guide/LowLevelNotebookStructure.html)
guide, the individual `*Box` symbol pages, and the
[textual box-syntax](https://reference.wolfram.com/language/tutorial/StringRepresentationOfBoxes.html)
tutorial. This note consolidates what a *box producer* - a parser, a code
generator, a `MakeBoxes` overload - actually needs: the construct set, their
argument shapes and options, how the front end renders and spaces them, and the
non-obvious behaviours that only surface when you generate boxes
programmatically and rasterize the result.

Everything here is grounded in kernel introspection (`Options`, `::usage`) and
in rendering experiments; the rough edges in the last section are the ones the
parser actually hit.

---

## Part 1 - What a box is, and how to see one

A **box** is an inert expression the front end knows how to lay out. Boxes nest:
a `FractionBox` whose numerator is a `RowBox` whose third element is a
`SuperscriptBox`, and so on, down to **leaf boxes** which are ordinary strings
(`"x"`, `"+"`, `"\[Alpha]"`). Leaves carry the characters; the wrapping boxes
carry the geometry.

Three round-trips connect expressions, boxes, and rendered output:

| Direction | Function | Example |
|-----------|----------|---------|
| expression → boxes | `ToBoxes[expr]`, `MakeBoxes[expr, form]` | `ToBoxes[x^2]` → `SuperscriptBox["x", "2"]` |
| boxes → rendered | `DisplayForm[box]`, `RawBoxes[box]` | `DisplayForm[FractionBox["a","b"]]` shows a fraction |
| boxes → expression | `ToExpression[box]`, `MakeExpression[box, form]` | parses the box back to a value |

```wl
ToBoxes[Sqrt[x]/2]
(* FractionBox[SqrtBox["x"], "2"] *)

DisplayForm @ RowBox[{"a", "+", SuperscriptBox["b", "2"]}]
(* renders:  a + b^2  *)
```

`DisplayForm` is the workhorse when you have a box tree in hand and want to
*see* it (it wraps the box so the FE typesets it instead of showing the raw
`FractionBox[...]`). `RawBoxes[box]` is the same idea as a building block you
can nest inside other expressions. In a live notebook, `Ctrl+Shift+E` toggles
any cell between rendered and box form, and the literal `\( box \)` syntax lets
you type boxes directly.

> **Tip for parser work:** to verify what `LaTeXMathParse` produced, rasterize
> it - `Rasterize[Style[DisplayForm[box], FontSize -> 24]]` - rather than
> trusting the box tree by eye. A structurally plausible tree can still render
> wrong (a stacked limit that should be a side script, a fraction bar that
> collapsed). What you see is what the engine actually did.

---

## Part 2 - Structural boxes

These carry no glyphs of their own; they arrange their children.

### RowBox

```
RowBox[{box1, box2, ...}]
```

A horizontal run of boxes with baselines aligned. This is the spine of almost
every formula - operators, operands, and delimiters are just successive string
leaves and sub-boxes in one `RowBox`. It takes **no options**; spacing between
its children comes from the front end's math-spacing model (Part 5), not from
`RowBox` itself.

A single-element row should usually be unwrapped (`RowBox[{x}]` → `x`); the FE
tolerates it, but it clutters the tree and can confuse downstream box rewrites.

### GridBox

```
GridBox[{{box11, box12, ...}, {box21, box22, ...}, ...}]
```

A two-dimensional grid - the substrate for matrices, `cases`, aligned
equations, `\substack`, and `\binom`. Rows must be rectangular (pad short rows
with `""`). Its option set is by far the largest of the typesetting boxes:

| Option | Controls | Notes |
|--------|----------|-------|
| `ColumnAlignments` | per-column horizontal alignment | `Left`/`Center`/`Right`/`"."` (decimal point), or a **list that cycles** across columns - e.g. `{Right, Left}` gives R L R L … |
| `RowAlignments` | per-row vertical alignment | `Baseline`/`Center`/`Top`/`Bottom`/`Axis` |
| `ColumnSpacings`, `RowSpacings` | gaps between columns / rows | in units of the current font's em-ish width; a number or per-gap list |
| `ColumnLines`, `RowLines` | rules between columns / rows | `True`/`False` or list; the `\hline`/`|` of an `array` |
| `GridBoxDividers` | fine-grained rules | `{"Columns" -> {...}, "Rows" -> {...}}` |
| `GridBoxAlignment` | master alignment spec | `{"Columns" -> {...}, "Rows" -> {...}}` |
| `GridBoxItemSize`, `ColumnWidths`, `RowHeights` | cell sizing | |
| `BaselinePosition` | which row sits on the surrounding baseline | important when a grid is one factor in a larger row |
| `GridBoxBackground`, `ColumnBackgrounds`, `RowBackgrounds` | cell fills | |

The cycling-list behaviour of `ColumnAlignments` is the key one for math: TeX's
`align`/`aligned`/`split` alternate right-aligned and left-aligned columns so
the relation signs line up. Build the spec with `PadRight[{}, width, {Right,
Left}]` to get exactly `width` entries and avoid relying on the FE's cycling.

```wl
DisplayForm @ GridBox[
  {{"a", "=", "1"}, {"bb", "=", "2"}},
  ColumnAlignments -> {Right, Left, Left}
]
(* the two "=" line up in a column *)
```

---

## Part 3 - Math layout boxes

These are the genuinely two-dimensional constructs. All take their arguments as
boxes (strings or nested boxes), never as raw expressions.

### Fractions and radicals

| Box | Shape | Renders | Key options |
|-----|-------|---------|-------------|
| `FractionBox[x, y]` | x over y with a rule | x⁄y | `FractionLine` (bar thickness; **`0` = no bar**, which is `\atop`) |
| `SqrtBox[x]` | square root | √x | `MinSize` (minimum radical height) |
| `RadicalBox[x, n]` | n-th root | ⁿ√x | `MinSize` |

```wl
DisplayForm @ FractionBox["a", "b"]               (* a/b with bar      *)
DisplayForm @ FractionBox["a", "b", FractionLine -> 0]   (* a over b, no bar  *)
DisplayForm @ RadicalBox["x", "3"]                (* cube root of x    *)
```

Note `FractionLine -> 0` is the textbook way to get an `\atop` / `\binom` stack
*with* the fraction machinery (centred, scaled numerator/denominator). The
parser instead uses a barless `GridBox` for those, because it wants the
binomial-coefficient delimiters around the stack and finer control of the
spacing - either is valid.

### Scripts: side vs. stacked

This is the distinction that trips up every math renderer.

| Box | Shape | Used for |
|-----|-------|----------|
| `SubscriptBox[x, y]` | x with y low-right | `x_i` |
| `SuperscriptBox[x, y]` | x with y high-right | `x^2` |
| `SubsuperscriptBox[x, y, z]` | x with y low-right **and** z high-right | `x_i^2` |
| `UnderscriptBox[x, y]` | y centred **below** x | `\lim_{...}`, accents below |
| `OverscriptBox[x, y]` | y centred **above** x | `\hat`, `\overline`, `\overbrace` |
| `UnderoverscriptBox[x, y, z]` | y below **and** z above x | display-style `\sum_a^b` |

The same TeX source (`\sum_a^b`) maps to **either** `SubsuperscriptBox`
(bounds to the side) **or** `UnderoverscriptBox` (bounds stacked above/below)
depending on the operator and the math style:

- **Limits-stacking operators** - `\sum \prod \coprod \bigcup \bigcap \bigvee
  \bigwedge \bigoplus \bigotimes \bigsqcup` - stack their bounds in display
  style. The parser keeps a set (`$bigOpChars`) and rewrites
  `SubsuperscriptBox[op, lo, hi]` → `UnderoverscriptBox[op, lo, hi]` for them.
- **Integrals** - `\int \oint \iint ...` - keep their bounds **to the side**
  even in display style (TeX `\nolimits`). They must *not* be in that set.

`Under`/`Over`/`UnderoverscriptBox` carry one option, `LimitsPositioning`: when
`True` (the default for these boxes in some styles) the bounds drop to the side
in inline/script size and stack in display size, mirroring `\displaystyle`
behaviour. Generators usually pick the box explicitly (as above) rather than
relying on `LimitsPositioning`.

```wl
DisplayForm @ SubsuperscriptBox["\[Integral]", "a", "b"]   (* side bounds  *)
DisplayForm @ UnderoverscriptBox["\[Sum]", "a", "b"]       (* stacked      *)
```

---

## Part 4 - Styling, sizing, and adjustment

### StyleBox

```
StyleBox[boxes, options...]      StyleBox[boxes, "NamedStyle", options...]
```

Wraps boxes with display directives. It accepts essentially any front-end style
option; the ones that matter for math:

| Option | Effect |
|--------|--------|
| `FontSlant` | `"Italic"` / `"Plain"` - math variables are italic, operator names (`sin`) upright |
| `FontWeight` | `"Bold"` / `"Plain"` |
| `FontFamily` | `"Times"`, `"Courier"` (typewriter), `"Helvetica"` (sans), `"Latin Modern Math"` … |
| `FontColor` | any colour directive (`RGBColor[...]`, `Red`, …) |
| `FontSize` | absolute points, or `Scaled[r]` (see the gotcha below) |
| `Magnification` | uniform scale of the wrapped box relative to its surroundings |
| `AutoSpacing` | `False` suppresses the FE's automatic math spacing inside this box |
| `ShowStringCharacters` | `False` hides the quotes around string leaves |

The named-style form, `StyleBox[boxes, "TI"]`, pulls the option settings for a
stylesheet style ("TI" = TraditionalForm italic) instead of spelling out
directives. The parser tags every identifier `StyleBox["x", "TI"]` so a single
stylesheet switch could restyle all math at once.

### Sizing: `Magnification`, not `FontSize -> Scaled`

To make one glyph bigger relative to its context - a `\big(` delimiter, say -
the obvious `FontSize -> Scaled[1.8]` is a **trap when you rasterize**. In a
standalone `Rasterize`, `Scaled` resolves against the *image canvas*, not the
parent font size, and the glyph balloons to thousands of pixels (an
out-of-memory raster). `Magnification -> 1.8` scales the box uniformly relative
to the surrounding text and rasterizes correctly:

```wl
(* \big( \Big( \bigg( \Bigg(  ~ 1.2 / 1.8 / 2.4 / 3.0x *)
StyleBox["(", Magnification -> 1.8]      (* robust          *)
StyleBox["(", FontSize -> Scaled[1.8]]   (* blows up under Rasterize *)
```

Inside a real notebook cell (with a resolved ambient `FontSize`) `Scaled` does
behave relatively; the failure is specific to headless rasterization, which is
exactly how box output is usually verified.

### AdjustmentBox - manual kerning

```
AdjustmentBox[box, BoxMargins -> {{left, right}, {bottom, top}}, BoxBaselineShift -> n]
```

Nudges a box's placement; margins are in font-relative (em-ish) units and may be
**negative**, which pulls neighbours closer or makes boxes overlap. The parser
uses a negative right margin to overlay a `/` on a glyph for a generic `\not`:

```wl
RowBox[{AdjustmentBox["=", BoxMargins -> {{0, -0.55}, {0, 0}}], "/"}]
(* the slash sits on top of the "=" -> a "not equal" built by overlap *)
```

`BoxBaselineShift` raises (`> 0`) or lowers (`< 0`) the box relative to the
baseline, in em units - useful for fine vertical alignment that the script
boxes don't give you.

### FrameBox and friends

`FrameBox[box]` draws a frame around `box` (TeX `\boxed`); it accepts
`FrameMargins`, `RoundingRadius`, `Background`, and `FrameStyle`. `RotationBox`,
`PaneBox`, `OverlayBox`, and `InsetBox` exist for rotation, fixed-size panes,
stacking, and embedding boxes into graphics, respectively.

---

## Part 5 - Spacing: the front end's model

This is the single biggest source of *visual* divergence from TeX/KaTeX, and the
one you have the least direct control over.

When boxes render in a math context, the FE inserts horizontal space around
operator characters according to their **character class** - binary operators
(`+`, `-`, `\[CenterDot]`) get medium space, relations (`=`, `<`, `\[Element]`)
get thick space, punctuation gets thin space, and ordinary letters/digits get
none. This is automatic and class-driven, much like TeX's own math spacing - but
the *amounts* and the *class assignments* are the FE's, not TeX's, so the two
engines disagree at the few-pixel level (the FE tends to space a touch more
loosely inside delimiters, e.g. `|a|` or `(=1)`).

You can influence it two ways:

1. **Explicit space leaves.** Insert a named space character as its own string
   leaf in the `RowBox`. These have fixed widths matched to TeX's eighteenths-of-
   an-em:

   | Leaf | ~width | TeX |
   |------|--------|-----|
   | `"\[VeryThinSpace]"` | 1/18 em | |
   | `"\[ThinSpace]"` | 3/18 em | `\,` |
   | `"\[MediumSpace]"` | 4/18 em | `\:` `\>` |
   | `"\[ThickSpace]"` | 5/18 em | `\;` |
   | `"\[NegativeThinSpace]"` etc. | negative | `\!`, `\negthinspace` |

   The parser maps `\,`/`\:`/`\;` to these (it previously dropped them, losing
   the thin space before `dx` in `\int x\,dx`). Negative named spaces exist too,
   though overlap via `AdjustmentBox` is often more predictable.

2. **`AutoSpacing -> False`** on a `StyleBox` turns off the automatic class-based
   spacing for everything inside, letting your explicit leaves stand alone. Use
   it when the FE's spacing actively fights you (e.g. text inside `\text{...}`
   that should not get math spacing around its `<`, `=`).

There is no setting that makes the FE's spacing *pixel-identical* to KaTeX; the
right target is "structurally correct and not jarring," with explicit spaces and
`AutoSpacing` reserved for the cases that read clearly wrong.

---

## Part 6 - Semantic and wrapper boxes

These display as their first argument but carry extra meaning for input,
copy/paste, or evaluation. A renderer that only cares about *display* can mostly
ignore them, but they matter the moment output must round-trip back to an
expression.

| Box | Displays as | Extra role |
|-----|-------------|------------|
| `TagBox[boxes, tag]` | `boxes` | keeps `tag` to guide interpretation on input and copy; used to attach a "this is really a `Foo`" hint |
| `InterpretationBox[boxes, expr]` | `boxes` | evaluates to `expr` when the cell is read as input - the display and the meaning are decoupled |
| `FormBox[boxes, form]` | `boxes` | interpret `boxes` under `form`'s rules (e.g. `TraditionalForm`) |
| `TemplateBox[{args...}, "tag"]` | per stylesheet `DisplayFunction` | parameterized, stylesheet-driven display + `InterpretationFunction` for input; how many built-in typeset objects are stored |
| `ErrorBox[boxes]` | `boxes`, flagged | marks boxes that can't be interpreted |

`InterpretationBox` is the one to reach for when generated output must remain
*selectable and re-evaluatable* as the original expression while displaying as
custom typeset math.

---

## Part 7 - Gotchas and recipes

Hard-won, mostly absent from the official pages:

- **`Switch` does not bind patterns.** `Switch[x, RowBox[{a___}], f[a]]` leaves
  `a` as the literal symbol `a` - `Switch` is a structural matcher, not a
  rewrite. Use `Replace`/`ReplaceAll` (which bind) to destructure a box.
- **Empty-string leaves accumulate.** No-op handlers and the `\\` line break
  leave `""` leaves and `RowBox[{"", x}]` shells behind. Strip them before any
  neighbour-based post-pass (digit grouping, limit stacking) or the "neighbour"
  is an empty string.
- **A lone `RowBox[{x}]` renders with stray structure** in some rewrites; unwrap
  single-element rows.
- **`Magnification` over `FontSize -> Scaled`** for relative glyph sizing under
  `Rasterize` (Part 4).
- **`ColumnAlignments` takes a cycling list** - `{Right, Left}` is all you need
  for an `align` block; pad to the column count to be explicit (Part 2).
- **Integrals are not limits-stacking operators** - keep them out of the
  `UnderoverscriptBox` rewrite set (Part 3).
- **Stacked rows leave a trailing empty row** when the source ends with `\\`;
  drop trailing all-empty grid rows (but never the last surviving row).
- **`MultilineFunction -> None`** on a script/fraction box controls how it
  breaks across lines; rarely needed for inline math but worth knowing it exists.

---

## Part 8 - The full `*Box` catalogue

The kernel defines ~114 `System` symbols ending in `Box`. Only the first group
is typesetting; the rest are listed so you can recognize them when they appear
in a box tree.

**Typesetting / formatting**
: `RowBox` `GridBox` `GridBoxAlignment` `FractionBox` `SqrtBox` `RadicalBox`
  `SubscriptBox` `SuperscriptBox` `SubsuperscriptBox` `UnderscriptBox`
  `OverscriptBox` `UnderoverscriptBox` `StyleBox` `AdjustmentBox` `FrameBox`
  `ItemBox` `PaneBox` `PanelBox` `RotationBox` `OverlayBox` `InsetBox`

**Structural / semantic wrappers**
: `TagBox` `InterpretationBox` `FormBox` `TemplateBox` `TemplateArgBox`
  `DynamicBox` `DynamicModuleBox` `DynamicWrapperBox` `NamespaceBox`
  `ErrorBox` `Box` `ParentBox` `EvaluationBox` `ValueBox` `OptionValueBox`
  `CounterBox`

**Interactive / control**
: `ButtonBox` `ActionMenuBox` `CheckboxBox` `RadioButtonBox` `OpenerBox`
  `SliderBox` `Slider2DBox` `InputFieldBox` `PopupMenuBox` `SetterBox`
  `ColorSetterBox` `LocatorBox` `LocatorPaneBox` `TogglerBox`
  `ProgressIndicatorBox` `AnimatorBox` `TabViewBox` `TableViewBox`
  `PaneSelectorBox` `ListPickerBox`

**2D graphics primitives**
: `GraphicsBox` `GraphicsComplexBox` `GraphicsGroupBox` `GraphicsGridBox`
  `LineBox` `PointBox` `PolygonBox` `RectangleBox` `DiskBox` `CircleBox`
  `ArrowBox` `BezierCurveBox` `BSplineCurveBox` `FilledCurveBox` `JoinedCurveBox`
  `RasterBox` `TextBox` `InsetBox` `GeometricTransformationBox` `RotationBox`

**3D graphics primitives**
: `Graphics3DBox` `Cuboid`/`Sphere`/`Cylinder`/`Cone`/`Tube`/`Prism`/`Pyramid`/
  `Tetrahedron`/`Hexahedron`/`Polyhedron``Box`, `Line3DBox` `Point3DBox`
  `Polygon3DBox` `Arrow3DBox` `Text3DBox` `Raster3DBox` and the
  `*Curve3DBox` / `*Surface3DBox` families

---

## References

The authoritative (if scattered) Wolfram sources:

- [Low-Level Notebook Structure](https://reference.wolfram.com/language/guide/LowLevelNotebookStructure.html) - the box-construct hub
- [String Representation of Boxes](https://reference.wolfram.com/language/tutorial/StringRepresentationOfBoxes.html) - the textual `\( ... \)` box syntax
- [RowBox](https://reference.wolfram.com/language/ref/RowBox.html) · [GridBox](https://reference.wolfram.com/language/ref/GridBox.html) · [FractionBox](https://reference.wolfram.com/language/ref/FractionBox.html) - representative symbol pages
- [Find the Underlying Box Structure of a Formatted Expression](https://reference.wolfram.com/language/workflow/FindTheUnderlyingBoxStructureOfAFormattedExpression.html) - the `ToBoxes` workflow

Related notes in this paclet: [LaTeXMathParserImplementation](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation)
puts these boxes to work translating real TeX, and
[DesignAndCompilationStrategy](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy)
covers the combinator core that drives the parse.

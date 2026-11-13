---
Template: Symbol
Name: MathMLBoxes
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MathMLBoxes
Keywords: [MathML, boxes, presentation MathML, content MathML, XML, TraditionalForm, MathMLToBoxes, import]
SeeAlso: [MathMLHeld, MathMLExpression, MathMLImport, XMLRead, LaTeXMathParse, WolframLanguageBoxes, ImportString, MathMLForm]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MathMLBoxes]()[*mathml*]</code> gives the boxes of the MathML text *mathml*, presentation or content, as ``XML`MathML`MathMLToBoxes`` and ``Developer`MathMLToBoxes`` give them in Wolfram 15.

<code>[MathMLBoxes]()[*xml*]</code> takes symbolic XML: an [XMLElement]() or an `XMLObject["Document"][...]`.

## Details & Options

- The result is <code>[FormBox]()[[TagBox]()[*boxes*, *tag*, [AutoDelete]() -> True], [TraditionalForm]()]</code>, the tag `"MathMLPresentationTag"` or `"MathMLContentTag"`; text that is not well-formed XML gives [$Failed]().
- The text is read by the grammar of XML, [XMLEBNF](), through [XMLRead](). The entities of MathML are in the paclet, and no importer of the kernel is called.
- A row of MathML, an `mrow` or the children of an element that takes a row, is grouped as a notebook groups typed input, by [WolframLanguageBoxes](): `a + b c` nests its product, and the rows within a row are read as one row. A parenthesis right after a name applies it, as [TraditionalForm]() reads `f(x)`.
- Content MathML is first made an expression, held, and typeset in [TraditionalForm]() by [MakeBoxes]().
- An element of one kind within an element of the other, or within one that is neither, carries the [TagBox]() of its kind.
- `semantics` gives its first child. A MathML annotation is kept beside it under `"AnnotationsTagWrapper"`, and an annotation in the `Mathematica` encoding that holds boxes is taken in place of the child. The text of such an annotation is read and never evaluated.
- An element Wolfram 15 does not read, or one with the wrong children, gives its name applied to its children, with a message.
- [MathMLBoxes]() has no options, as the functions of Wolfram 15 have none.
- The messages of every MathML function are given under [MathMLBoxes](): `prserr` for text that is not well-formed, `nfprserr` for an entity MathML does not have, `incrt` for a root that is not `math`, `nmmlr` for a root that is no element of MathML, `unkntag`, `unknstrc` and `msngargs` for an element that is not read, and `bmml` for text outside a token element.

## Basic Examples

The boxes of a fraction:

```wl
MathMLBoxes["<math><mfrac><mn>1</mn><mi>x</mi></mfrac></math>"]
```

<!-- => FormBox[TagBox[FractionBox["1", "x"], "MathMLPresentationTag", AutoDelete -> True], TraditionalForm] -->

The boxes of content MathML are its expression in [TraditionalForm]():

```wl
MathMLBoxes["<math><apply><plus/><ci>x</ci><cn>1</cn></apply></math>"]
```

<!-- => FormBox[TagBox[RowBox[{"x", "+", "1"}], "MathMLContentTag", AutoDelete -> True], TraditionalForm] -->

The boxes displayed:

```wl
RawBoxes[MathMLBoxes["<math><mrow><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mfrac><mn>1</mn><mi>y</mi></mfrac></mrow></math>"]]
```

## Scope

A row is grouped by the precedence of its operators, and an invisible multiplication between two factors is the space of a product:

```wl
MathMLBoxes["<math><mrow><mi>a</mi><mo>+</mo><mi>b</mi><mo>&InvisibleTimes;</mo><mi>c</mi></mrow></math>"]
```

<!-- => FormBox[TagBox[RowBox[{"a", "+", RowBox[{"b", " ", "c"}]}], "MathMLPresentationTag", AutoDelete -> True], TraditionalForm] -->

A parenthesis after a name applies it:

```wl
MathMLBoxes["<math><mrow><mi>f</mi><mo>(</mo><mi>x</mi><mo>)</mo></mrow></math>"]
```

<!-- => FormBox[TagBox[RowBox[{"f", "(", "x", ")"}], "MathMLPresentationTag", AutoDelete -> True], TraditionalForm] -->

Entities and character references are the characters the Wolfram Language names:

```wl
MathMLBoxes["<math><mi>&alpha;</mi><mo>&le;</mo><mi>&#x3B2;</mi></math>"]
```

<!-- => FormBox[TagBox[RowBox[{"\[Alpha]", "\[LessEqual]", "\[Beta]"}], "MathMLPresentationTag", AutoDelete -> True], TraditionalForm] -->

A style attribute is a [StyleBox]():

```wl
MathMLBoxes["<math><mi mathvariant='bold'>v</mi></math>"]
```

<!-- => FormBox[TagBox[StyleBox["v", FontFamily -> "Times", FontWeight -> "Bold", FontSlant -> "Plain"], "MathMLPresentationTag", AutoDelete -> True], TraditionalForm] -->

Symbolic XML is read as the text is:

```wl
MathMLBoxes[XMLElement["math", {}, {XMLElement["msqrt", {}, {XMLElement["mi", {}, {"x"}]}]}]]
```

<!-- => FormBox[TagBox[SqrtBox["x"], "MathMLPresentationTag", AutoDelete -> True], TraditionalForm] -->

## Properties and Relations

[MathMLHeld]() gives the expression the boxes read as:

```wl
MathMLHeld["<math><mfrac><mn>1</mn><mi>x</mi></mfrac></math>"]
```

<!-- => HoldComplete[1/x] -->

[MathMLImport]() gives the same boxes as its element `"Boxes"`:

```wl
MathMLImport["<math><mfrac><mn>1</mn><mi>x</mi></mfrac></math>", "Boxes"] === MathMLBoxes["<math><mfrac><mn>1</mn><mi>x</mi></mfrac></math>"]
```

<!-- => True -->

## Possible Issues

Text that is not well-formed XML gives [$Failed](), with a message that says where reading stopped:

```wl
MathMLBoxes["<math><mi>x</mi>"]
```

<!-- => the message MathMLBoxes::prserr is issued and $Failed is returned -->

An element with the wrong children is its name applied to them:

```wl
MathMLBoxes["<math><mfrac><mn>1</mn></mfrac></math>"]
```

<!-- => the message MathMLBoxes::unknstrc is issued and the boxes of mfrac(1) are returned -->

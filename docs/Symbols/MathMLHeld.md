---
Template: Symbol
Name: MathMLHeld
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MathMLHeld
Keywords: [MathML, expression, HoldComplete, HeldExpression, TraditionalForm, content MathML, presentation MathML, import]
SeeAlso: [MathMLBoxes, MathMLExpression, MathMLImport, WolframLanguageHeld, HoldComplete, ImportString, ErrorBox]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MathMLHeld]()[*mathml*]</code> gives the expression of the MathML text *mathml* in [HoldComplete](), as <code>[ImportString]()[*mathml*, {"MathML", "HeldExpression"}]</code> gives it in Wolfram 15.

<code>[MathMLHeld]()[*xml*]</code> takes symbolic XML.

## Details & Options

- The expression is the one the boxes of [MathMLBoxes]() read as in [TraditionalForm](): a row is read by [WolframLanguageHeld](), its names, numbers and boxes at their places, and nothing is evaluated.
- A name [TraditionalForm]() uses for a function is that function where it is applied: `sin(x)` is <code>[Sin]()[x]</code>, `ln(x)` is <code>[Log]()[x]</code>. Alone it is the name.
- A fraction is a product with a power `-1`, a root a power, a table a list of lists, text a [TextCell](), and a sum, a product or an integral sign with limits gives [Sum](), [Product]() or [Integrate]() with its range.
- Content MathML is read from the boxes it is typeset as, as Wolfram 15 reads it, so a quotient of content is a product with a power `-1` too.
- Boxes that do not read give <code>[ErrorBox]()[[FormBox]()[..., [TraditionalForm]()]]</code> around them, and text that is not well-formed XML gives <code>[HoldComplete]()[$Failed]</code>.

## Basic Examples

An expression, held:

```wl
MathMLHeld["<math><mrow><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mn>1</mn></mrow></math>"]
```

<!-- => HoldComplete[x^2 + 1] -->

Nothing is evaluated:

```wl
MathMLHeld["<math><mrow><mn>1</mn><mo>+</mo><mn>2</mn></mrow></math>"]
```

<!-- => HoldComplete[1 + 2] -->

## Scope

A function [TraditionalForm]() names:

```wl
MathMLHeld["<math><mrow><mi>sin</mi><mo>&ApplyFunction;</mo><mo>(</mo><mi>x</mi><mo>)</mo></mrow></math>"]
```

<!-- => HoldComplete[Sin[x]] -->

A sum with its limits:

```wl
MathMLHeld["<math><mrow><munderover><mo>&sum;</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><msup><mi>i</mi><mn>2</mn></msup></mrow></math>"]
```

<!-- => HoldComplete[Sum[i^2, {i, 1, n}]] -->

An integral:

```wl
MathMLHeld["<math><mrow><msubsup><mo>&int;</mo><mn>0</mn><mn>1</mn></msubsup><mrow><mi>x</mi><mo>&InvisibleTimes;</mo><mrow><mo>&DifferentialD;</mo><mi>x</mi></mrow></mrow></mrow></math>"]
```

<!-- => HoldComplete[Integrate[x, {x, 0, 1}]] -->

A table is a list of its rows:

```wl
MathMLHeld["<math><mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></mtable></math>"]
```

<!-- => HoldComplete[{{1, 2}, {3, 4}}] -->

Content MathML:

```wl
MathMLHeld["<math><apply><int/><bvar><ci>t</ci></bvar><lowlimit><cn>0</cn></lowlimit><uplimit><cn>1</cn></uplimit><apply><power/><ci>t</ci><cn>2</cn></apply></apply></math>"]
```

<!-- => HoldComplete[Integrate[t^2, {t, 0, 1}]] -->

## Properties and Relations

[MathMLExpression]() releases the hold:

```wl
MathMLExpression["<math><mrow><mn>1</mn><mo>+</mo><mn>2</mn></mrow></math>"]
```

<!-- => 3 -->

## Possible Issues

Boxes that do not read as an expression come back in an [ErrorBox]():

```wl
MathMLHeld["<math><mrow><mi>x</mi><mo>+</mo></mrow></math>"]
```

<!-- => ErrorBox[FormBox[ErrorBox[RowBox[{"x", "+"}]], TraditionalForm]] -->

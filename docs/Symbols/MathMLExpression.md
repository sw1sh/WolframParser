---
Template: Symbol
Name: MathMLExpression
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MathMLExpression
Keywords: [MathML, expression, evaluate, MathMLToExpression, content MathML, presentation MathML, import]
SeeAlso: [MathMLHeld, MathMLBoxes, MathMLImport, ReleaseHold, ImportString]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MathMLExpression]()[*mathml*]</code> gives the expression of the MathML text *mathml*, evaluated, as ``XML`MathML`MathMLToExpression`` gives it in Wolfram 15.

<code>[MathMLExpression]()[*xml*]</code> takes symbolic XML.

## Details & Options

- It is the expression of [MathMLHeld](), released. An equation written with `=` is an assignment, as it is in Wolfram 15: `x = 1` sets `x`.
- Boxes that do not read as an expression, and text that is not well-formed XML, give [$Failed]().

## Basic Examples

An expression is evaluated:

```wl
MathMLExpression["<math><mrow><mn>1</mn><mo>+</mo><mn>2</mn></mrow></math>"]
```

<!-- => 3 -->

Content MathML:

```wl
MathMLExpression["<math><apply><sin/><apply><divide/><pi/><cn>2</cn></apply></apply></math>"]
```

<!-- => 1 -->

## Scope

An integral is done:

```wl
MathMLExpression["<math><apply><int/><bvar><ci>t</ci></bvar><lowlimit><cn>0</cn></lowlimit><uplimit><cn>1</cn></uplimit><apply><power/><ci>t</ci><cn>2</cn></apply></apply></math>"]
```

<!-- => 1/3 -->

## Possible Issues

Boxes that do not read give [$Failed]():

```wl
MathMLExpression["<math><mrow><mi>x</mi><mo>+</mo></mrow></math>"]
```

<!-- => $Failed -->

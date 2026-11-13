---
Template: Symbol
Name: MathMLImport
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MathMLImport
Keywords: [MathML, import, ImportString, elements, Boxes, Expression, HeldExpression, XMLElement, XMLObject]
SeeAlso: [MathMLBoxes, MathMLHeld, MathMLExpression, XMLRead, ImportString, XMLElement]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MathMLImport]()[*mathml*, *element*]</code> gives an element of the MathML text *mathml* as <code>[ImportString]()[*mathml*, {"MathML", *element*}]</code> gives it in Wolfram 15.

<code>[MathMLImport]()[*mathml*]</code> gives the boxes.

## Details & Options

- The elements are `"Boxes"`, `"Expression"`, `"HeldExpression"`, `"XMLElement"` and `"XMLObject"`, and `"Elements"` lists them.
- `"Boxes"` is [MathMLBoxes]() and `"HeldExpression"` is [MathMLHeld](). `"Expression"` is the held expression released; boxes that do not read are given in their [ErrorBox](), where [MathMLExpression]() gives [$Failed]().
- `"XMLElement"` is the root as Wolfram 15 has it: each name without its prefix, a namespace declaration of the root under the prefix it declares, an attribute with a prefix under `{namespace, name}`, text with its runs of whitespace one space and none at its ends, and no comment or processing instruction.
- `"XMLObject"` is `XMLObject["Document"][prolog, element, epilog]`, the comments before and after the root in its prolog and epilog. It has no document type, which in Wolfram 15 names a file of the installation.

## Basic Examples

The elements:

```wl
MathMLImport["<math><mi>x</mi></math>", "Elements"]
```

<!-- => {"Boxes", "Expression", "HeldExpression", "XMLElement", "XMLObject"} -->

The held expression:

```wl
MathMLImport["<math><mn>2</mn><mo>+</mo><mn>2</mn></math>", "HeldExpression"]
```

<!-- => HoldComplete[2 + 2] -->

## Scope

The root element, its names without their prefix:

```wl
MathMLImport["<m:math xmlns:m='http://www.w3.org/1998/Math/MathML'><m:mi> x </m:mi></m:math>", "XMLElement"]
```

<!-- => XMLElement["math", {"m" -> "http://www.w3.org/1998/Math/MathML"}, {XMLElement["mi", {}, {"x"}]}] -->

The document:

```wl
MathMLImport["<!-- c --><math><mi>x</mi></math>", "XMLObject"]
```

<!-- => XMLObject["Document"][{XMLObject["Comment"][" c "]}, XMLElement["math", {}, {XMLElement["mi", {}, {"x"}]}], {}] -->

## Possible Issues

`"Expression"` gives boxes that do not read as they are:

```wl
MathMLImport["<math><mrow><mi>x</mi><mo>+</mo></mrow></math>", "Expression"]
```

<!-- => ErrorBox[FormBox[ErrorBox[RowBox[{"x", "+"}]], TraditionalForm]] -->

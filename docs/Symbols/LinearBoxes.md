---
Template: Symbol
Name: LinearBoxes
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LinearBoxes
Keywords: [linear syntax, boxes, MakeExpression, RowBox, SuperscriptBox, FractionBox, parser zoo]
SeeAlso: [WolframLanguageHeld, WolframLanguageHeldNext, MakeExpression, RowBox, ToExpression]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LinearBoxes]()[*boxes*]</code> stands for a group of boxes that Wolfram Language source asks to be read as input, *boxes* the group's boxes, in what [WolframLanguageHeld]() and [WolframLanguageHeldNext]() read.

## Details & Options

- Wolfram Language source can hold boxes written as text, linear syntax: a group that a backslash and an opening parenthesis open and a backslash and a closing parenthesis close. A backslash and an exclamation mark before the group ask for it to be read as input.
- Inside a group, a backslash before a caret, an underscore, a percent sign, an ampersand, a plus sign, a slash or an at sign builds a superscript, a subscript, the third box of a script or a root, an overscript, an underscript, a fraction or a square root from the boxes beside it. A backslash before an asterisk reads the input after it as boxes, a backslash before a backtick gives the boxes after it the form before it, and a backslash before a space, `t` or `n` is a space, a tab or a newline. The rest is a row of tokens, nested as the operators between them nest.
- A group alone reads as its boxes, as the kernel's reader reads it. A group read as input reads as `LinearBoxes` of its boxes, where the kernel's reader gives the expression <code>[MakeExpression]()[*boxes*, [StandardForm]()]</code> makes of them, so that a program reading source makes it with its own [MakeExpression]().
- `LinearBoxes` has no definitions; it holds the boxes as they are.

## Basic Examples

A superscript written as linear syntax and read as input:

```wl
held = WolframLanguageHeld["\\!\\(x\\^2\\) + 1"]
```

<!-- => {HoldComplete[LinearBoxes[SuperscriptBox["x", "2"]] + 1]} -->

The expression the kernel's reader gives in its place:

```wl
Cases[held, LinearBoxes[b_] :> MakeExpression[b, StandardForm], Infinity]
```

<!-- => {HoldComplete[x^2]} -->

## Scope

A group not read as input is its boxes, a row nested as its operators nest:

```wl
WolframLanguageHeld["\\(a + b c\\)"]
```

<!-- => {HoldComplete[RowBox[{"a", "+", RowBox[{"b", "c"}]}]]} -->

Scripts, roots and fractions:

```wl
WolframLanguageHeld["\\(x\\_i\\^2 + \\@y\\/z\\)"]
```

<!-- => {HoldComplete[RowBox[{SuperscriptBox[SubscriptBox["x", "i"], "2"], "+", FractionBox[SqrtBox["y"], "z"]}]]} -->

Input after a backslash and an asterisk is read as boxes:

```wl
WolframLanguageHeld["\\!\\(\\*FractionBox[\"1\", \"2\"]\\)"]
```

<!-- => {HoldComplete[LinearBoxes[FractionBox["1", "2"]]]} -->

## Properties and Relations

The boxes of a group are those the kernel's reader gives:

```wl
WolframLanguageHeld["\\(x\\_i\\^2 + \\@y\\/z\\)"] === {ToExpression["\\(x\\_i\\^2 + \\@y\\/z\\)", InputForm, HoldComplete]}
```

<!-- => True -->

[WolframLanguageHeldNext]() reads a statement of linear syntax the same way:

```wl
WolframLanguageHeldNext["a = 1\n\\!\\(x\\^2\\)", 7]
```

<!-- => {HoldComplete[LinearBoxes[SuperscriptBox["x", "2"]]], 17, <|"Warnings" -> {}|>} -->

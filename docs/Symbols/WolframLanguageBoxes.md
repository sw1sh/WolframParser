---
Template: Symbol
Name: WolframLanguageBoxes
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageBoxes
Keywords: [Wolfram Language, boxes, RowBox, front end, ReparseBoxStructurePacket, input cell, typed text, concrete syntax tree]
SeeAlso: [WolframLanguageConcrete, WolframLanguageHeld, WolframLanguageAST]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageBoxes]()[*code*]</code> gives the boxes Wolfram 15's front end makes of the Wolfram Language text *code* typed in an input cell, as it answers `FrontEnd``ReparseBoxStructurePacket`[*code*].

<code>[WolframLanguageBoxes]()[{*token*<sub>1</sub>, *token*<sub>2</sub>, ...}]</code> gives the row the front end makes of a list of tokens when it reads a row again, each string a token and each box an operand.

## Details & Options

- The boxes come from the concrete syntax tree [WolframLanguageConcrete]() gives: each token is a string and each node a `RowBox` of its children, as the front end lays out typed text. A kernel without a front end can make with it the boxes a notebook's input cell holds.
- Spaces, tabs and newlines keep their places, and a run of spaces and tabs is one string. Whitespace, newlines and comments at the edges of a node stand outside it, in the row around it.
- A comment is a row of its own, `"(*"`, its text read as code inside brackets, so a newline in it ends no expression, and `"*)"`.
- A long name the front end knows is its character, in a string too: `\[Lambda]` gives `"λ"`. A `\\` before `[` keeps the `[` as text.
- A string that stands alone, the whole of *code*, keeps its text as typed, its long names spelled out.
- Active linear syntax, `\(...\)` in its own characters, is one piece of text in a string, quotes and all.
- A blank at the end of *code* after an operand is in the row of the innermost operator before it. After a bracket, a call or a postfix operator it stands outside, in the row around.
- What the front end reads as one token is one string: a pattern such as `x_`, `_h` or `x_.`, a slot such as `#1`, an `Out` such as `%2`, the primes of `y''` and `=.`. A `!!` before an operand is two `!`s.
- Text that is not Wolfram Language gives the tokens the front end gives: an operator without its operand is that operator alone, and a group the text does not close is its opener with what follows it in one row.
- A token alone is that string, not a `RowBox`, and empty text gives `""`.
- The boxes are those of the front end for the text the documentation converter sends it: every one of the 57,675 distinct code strings of PureMath's 4,242 pages. The front end reads some other text otherwise, all of it listed by kind in the paclet's tests: a newline outside brackets ending an expression, the flat chains it keeps of different operators (`===` and `=!=`, `;;`, `~`), operators of other precedences (`\[PlusMinus]`, `\[DiscreteShift]`, integrals), closers that close another group, `??`, backquotes, `=[`, and long names it does not know.

## Basic Examples

The boxes of a call:

```wl
WolframLanguageBoxes["f[x, y]"]
```

<!-- => RowBox[{"f", "[", RowBox[{"x", ",", " ", "y"}], "]"}] -->

A definition:

```wl
WolframLanguageBoxes["f[x_] := x^2"]
```

<!-- => RowBox[{RowBox[{"f", "[", "x_", "]"}], " ", ":=", " ", RowBox[{"x", "^", "2"}]}] -->

## Scope

A run of spaces is one string:

```wl
WolframLanguageBoxes["f[a,   b]"]
```

<!-- => RowBox[{"f", "[", RowBox[{"a", ",", "   ", "b"}], "]"}] -->

Newlines and tabs keep their places:

```wl
WolframLanguageBoxes["Simplify[\n\tf[x] +\n\t\tg[x]\n]"]
```

<!-- => RowBox[{"Simplify", "[", "\n", "\t", RowBox[{RowBox[{"f", "[", "x", "]"}], " ", "+", "\n", "\t\t", RowBox[{"g", "[", "x", "]"}]}], "\n", "]"}] -->

A comment is a row of its own, its text read as code:

```wl
WolframLanguageBoxes["f[x] (* a comment *)"]
```

<!-- => RowBox[{RowBox[{"f", "[", "x", "]"}], " ", RowBox[{"(*", " ", RowBox[{"a", " ", "comment"}], " ", "*)"}]}] -->

The space after a list's last comma stands outside the list's items:

```wl
WolframLanguageBoxes["f[x, ]"]
```

<!-- => RowBox[{"f", "[", RowBox[{"x", ","}], " ", "]"}] -->

A pattern test, its pattern one token:

```wl
WolframLanguageBoxes["g_?MatrixLieGroupQ"]
```

<!-- => RowBox[{"g_", "?", "MatrixLieGroupQ"}] -->

Derivatives, the primes of each one token:

```wl
WolframLanguageBoxes["y''[x] + y'[x]/x"]
```

<!-- => RowBox[{RowBox[{RowBox[{"y", "''"}], "[", "x", "]"}], " ", "+", " ", RowBox[{RowBox[{RowBox[{"y", "'"}], "[", "x", "]"}], "/", "x"}]}] -->

A long name is its character, in a string too:

```wl
WolframLanguageBoxes["{\\[Lambda], \"\\[Bullet]\"}"]
```

<!-- => RowBox[{"{", RowBox[{"\[Lambda]", ",", " ", "\"\[Bullet]\""}], "}"}] -->

An operator alone:

```wl
WolframLanguageBoxes["^"]
```

<!-- => "^" -->

A call the text does not close:

```wl
WolframLanguageBoxes["f[\"MinimizingTerms\","]
```

<!-- => RowBox[{"f", "[", RowBox[{"\"MinimizingTerms\"", ","}]}] -->

## Properties and Relations

The boxes of a definition:

```wl
boxes = WolframLanguageBoxes["f[x_] := x^2"]
```

<!-- => RowBox[{RowBox[{"f", "[", "x_", "]"}], " ", ":=", " ", RowBox[{"x", "^", "2"}]}] -->

They make the expression the text reads as, as an input cell's boxes do:

```wl
MakeExpression[boxes, StandardForm]
```

<!-- => HoldComplete[f[x_] := x^2] -->

[WolframLanguageHeld]() reads the text itself to the same expression:

```wl
WolframLanguageHeld["f[x_] := x^2"]
```

<!-- => {HoldComplete[f[x_] := x^2]} -->

The boxes' strings, joined, are the text where it holds no long name:

```wl
StringJoin[Cases[boxes, _String, Infinity]] === "f[x_] := x^2"
```

<!-- => True -->

## Possible Issues

The boxes follow the concrete syntax tree, which continues a sum past a newline before its next `+` as CodeParser reads it. The front end ends the expression at the newline, as the kernel reads it, and makes `RowBox[{RowBox[{"a", " ", "+", " ", "b"}], "\n", " ", RowBox[{"+", " ", "c"}]}]` of this text:

```wl
WolframLanguageBoxes["a + b\n + c"]
```

<!-- => RowBox[{"a", " ", "+", " ", "b", "\n", " ", "+", " ", "c"}] -->

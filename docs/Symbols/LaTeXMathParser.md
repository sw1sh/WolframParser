---
Template: Symbol
Name: LaTeXMathParser
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LaTeXMathParser
Keywords: [LaTeX, math, parser, ParserCombinator, parser object, compiled, PEGVM, KaTeX, reusable]
SeeAlso: [LaTeXMathParse, LaTeXMathStyle, Parse, ParserCompile, ParserCombinator, ParserCombinatorQ]
RelatedGuides: [WolframParser]
---

## Usage

<code>[LaTeXMathParser]()</code> is the [ParserCombinator]() that recognizes LaTeX math-mode source and builds a tree of Wolfram boxes ([FractionBox](), [SuperscriptBox](), [RadicalBox](), [GridBox](), [RowBox](), [StyleBox]()). It is the reusable parser object that [LaTeXMathParse]() runs.

## Details & Options

- [LaTeXMathParser]() is the parser *object*; [LaTeXMathParse]() is the one-shot *call*. <code>[LaTeXMathParse]()[*s*]</code> preprocesses *s*, evaluates <code>[Parse]()[[LaTeXMathParser](), *s*]</code>, then runs a set of post-passes over the boxes. Running the object directly with <code>[Parse]()[[LaTeXMathParser](), *s*]</code> gives the *raw* grammar output, without the wrapper's pre- and post-processing.
- It is an ordinary [ParserCombinator](): [Head]() is [ParserCombinator](), its type tag is `"Action"`, and [ParserCombinatorQ]() returns [True](). Every `Parse*` operation that accepts a parser accepts it.
- Run it on one input with <code>[Parse]()[[LaTeXMathParser](), *s*]</code>; reuse it across many inputs by compiling once with <code>[ParserCompile]()[[LaTeXMathParser](), Method -> "PEGVM"]</code> and applying the returned object.
- The paclet ships a precompiled PEG-VM form of [LaTeXMathParser]() as an asset. [LaTeXMathParse]() loads it on first use only when the stored grammar [Hash]() matches the current object, so a stale asset is ignored and the interpreter is used instead.
- The interpreted object handles the full Unicode grammar; the compiled PEG-VM form lowers character classes to ASCII ranges, so [LaTeXMathParse]() routes any input carrying a non-ASCII codepoint back through the interpreted [LaTeXMathParser]().
- *Preprocessing* done only by [LaTeXMathParse]() (not by a raw [Parse]()): delimiter-sizing macros such as `\bigl`, `\Big`, `\biggr` are stripped before parsing.
- *Post-processing* done only by [LaTeXMathParse]() (not by a raw [Parse]()): line breaks `\\` fold into a [GridBox](), Dirac `\langle`/`\rangle` bra-ket rewrites to a [TemplateBox](), pasted Unicode symbols are unwrapped to upright glyphs, and empty rows are pruned.

## Basic Examples

The object itself is a [ParserCombinator](), shown as a summary box:

```wl
LaTeXMathParser
```

<!-- => ParserCombinator[Action] summary box (Type "Action", one child, uncompiled) -->

<!-- #| annotation: 26.07.26: Design review - LaTeXMathParser is the parser exposed as a first-class value, the split every parser-combinator library makes: the grammar is a reusable object you can Parse, ParserCompile, serialize, or embed, distinct from the one-shot LaTeXMathParse convenience call. This differs from a stock importer like ImportString[s, "LaTeX"], which exposes only the finished call and no reusable, compilable grammar object. Alternative name considered: LaTeXMathGrammar. -->

Run it on a source string with [Parse]() - a fraction:

```wl
Parse[LaTeXMathParser, "\\frac{a}{b}"]
```

<!-- => FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]] -->

---

A subscript-superscript combination:

```wl
Parse[LaTeXMathParser, "x_i^2"]
```

<!-- => SubsuperscriptBox[StyleBox["x", "TI"], StyleBox["i", "TI"], "2"] -->

## Scope

Compile the object once with the PEG-VM backend; the result is a [ParserCombinator]() carrying a `"Code"` function, callable directly on each input:

```wl
latex = ParserCompile[LaTeXMathParser, Method -> "PEGVM"];
latex["\\frac{a}{b}"]
```

<!-- => FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]] -->

---

The compiled object is reusable - apply it to another input without recompiling:

```wl
latex["\\sqrt[3]{x}"]
```

<!-- => RadicalBox[StyleBox["x", "TI"], "3"] -->

---

Reuse the uncompiled object across a list of inputs:

```wl
Parse[LaTeXMathParser, #] & /@ {"a+b", "x^2", "\\frac{1}{2}"}
```

<!-- => {RowBox[{StyleBox["a", "TI"], "+", StyleBox["b", "TI"]}], SuperscriptBox[StyleBox["x", "TI"], "2"], FractionBox["1", "2"]} -->

## Properties and Relations

On inputs that need no pre- or post-processing, a raw [Parse]() of [LaTeXMathParser]() equals [LaTeXMathParse]():

```wl
Parse[LaTeXMathParser, "\\frac{a}{b}"] === LaTeXMathParse["\\frac{a}{b}"]
```

<!-- => True -->

---

Where the wrapper's post-pass matters, the two diverge. A line break `\\` is left as an internal marker by the raw parser:

```wl
Parse[LaTeXMathParser, "a \\\\ b"]
```

<!-- => RowBox[{StyleBox["a", "TI"], <the private $lineBreakMark symbol>, StyleBox["b", "TI"]}] -->

---

[LaTeXMathParse]() folds that marker into a two-row [GridBox]():

```wl
LaTeXMathParse["a \\\\ b"]
```

<!-- => GridBox[{{StyleBox["a", "TI"]}, {StyleBox["b", "TI"]}}] -->

---

A Dirac ket is likewise finished only by the wrapper: raw parsing leaves bare fence characters, while [LaTeXMathParse]() rewrites it to a `"Ket"` [TemplateBox]():

```wl
LaTeXMathParse["|\\psi\\rangle"]
```

<!-- => TemplateBox[{StyleBox["\[Psi]", "TI"]}, "Ket"] -->

---

[LaTeXMathParser]() answers [ParserCombinatorQ]() with [True]():

```wl
ParserCombinatorQ[LaTeXMathParser]
```

<!-- => True -->

## Possible Issues

A raw [Parse]() of [LaTeXMathParser]() skips the preprocessing [LaTeXMathParse]() does, so delimiter-sizing macros survive as unknown commands. Here `\bigl` and `\bigr` leak into the output:

```wl
Parse[LaTeXMathParser, "\\bigl( x \\bigr)"]
```

<!-- => RowBox[{"\\bigl", StyleBox["(", SpanMaxSize -> 1], RowBox[{StyleBox["x", "TI"], "\\bigr"}], StyleBox[")", SpanMaxSize -> 1]}] -->

---

[LaTeXMathParse]() strips the sizing macros first, so the same source yields clean sized delimiters:

```wl
LaTeXMathParse["\\bigl( x \\bigr)"]
```

<!-- => RowBox[{StyleBox["(", FontSize -> 1.2*Inherited], StyleBox["x", "TI"], StyleBox[")", FontSize -> 1.2*Inherited]}] -->

For finished box output, call [LaTeXMathParse](); reach for [LaTeXMathParser]() when you need the parser as a value - to [ParserCompile]() it, serialize it, or embed it in a larger grammar.

## Neat Examples

Compile the parser with the PEG-VM backend, serialize the compiled table, and reload it in a fresh kernel with no recompilation - the pattern the shipped asset uses:

```wl
latex = ParserCompile[LaTeXMathParser, Method -> "PEGVM"];
Export[FileNameJoin[{$TemporaryDirectory, "latex.wxf"}], latex];
reloaded = Import[FileNameJoin[{$TemporaryDirectory, "latex.wxf"}]];
reloaded["\\frac{a^2 + b^2}{c}"]
```

<!-- => FractionBox[RowBox[{SuperscriptBox[StyleBox["a", "TI"], "2"], "+", SuperscriptBox[StyleBox["b", "TI"], "2"]}], StyleBox["c", "TI"]] -->

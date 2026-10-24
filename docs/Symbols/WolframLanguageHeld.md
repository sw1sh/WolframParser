---
Template: Symbol
Name: WolframLanguageHeld
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageHeld
Keywords: [Wolfram Language, InputForm, package, held expressions, HoldComplete, ImportString, parser zoo]
SeeAlso: [WolframLanguageAST, WolframLanguageConcrete, WolframLanguageGrammar, WolframLanguageSemantic, ParseOperatorTable, ImportString]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageHeld]()[*code*]</code> parses the Wolfram Language source string *code* to the list of its top-level expressions, each in [HoldComplete]().

## Details & Options

- The result is what <code>[ImportString]()[*code*, {"WL", "HeldExpressions"}]</code> gives: the expressions as the kernel reads them, before any of them evaluates. A statement that is `Null` alone is left out, as the kernel leaves it out.
- Outside brackets a newline ends an expression wherever the expression could end, so `a` on one line and `+ b` on the next are two expressions, while `a +` followed by `b` is one. Inside brackets a newline is whitespace. Comments, nested ones included, are whitespace. A `\` at the end of a line, outside a string, continues it: `a\` and `b` on the next line are the name `ab`. A `?` or `??` where an operand begins asks about the words after it, as `?Plot*` is `Information["Plot*", LongForm -> False]`, and a `.` before a digit begins a number, so `a.5` is `a*0.5`.
- The forms come out as the kernel builds them: `a - b` is `Plus[a, Times[-1, b]]`, `a/b` is `Times[a, Power[b, -1]]`, a minus folds into a number (`-2` is the integer `-2`), and a chain of one flat operator is one call (`a + b + c` is `Plus[a, b, c]`).
- The binding powers are the precedences [CodeParser]() publishes; [WolframLanguageGrammar]() generates the levels of its [ParseOperatorTable]() from them.
- A long name that is an operator, a bracket or an integral reads as the kernel reads it, spelt out or as its character: `a \[CircleTimes] b` is `CircleTimes[a, b]`, `\[LeftFloor]x\[RightFloor]` is `Floor[x]` and `\[Integral] f \[DifferentialD] x` is `Integrate[f, x]`; a long name that is whitespace is whitespace.
- The operand of an integral reads whole, a differential such as `\[DifferentialD] x` in it a factor like any other. An integral of a product whose last factor is a differential is `Integrate` of the factors before it over its variable, an integral of a differential alone is `Integrate[1, x]`, and any other integral keeps its own head: `\[Integral]\[Integral] f \[DifferentialD] x \[DifferentialD] y` is `Integral[Integrate[f \[DifferentialD] x, y]]`, as the kernel reads it.
- The algebra reads numbers and strings from their text itself: a real keeps the precision or accuracy its marks give, or that its digits give past a machine real's, and a string's escapes are decoded, an unknown one kept as written. The file of `<<` and `>>` keeps a `\` in it, as in `<<a\b.m`, and decodes its long names. A name is the one leaf read by the kernel's reader, under [HoldComplete](), so it is made in [$Context]() as the kernel makes it.
- `WolframLanguageHeld` reads *code* in time linear in its length: one compiled pass over the character codes makes the tokens, compiled precedence climbing over the tokens, by the levels [WolframLanguageGrammar]() generates, makes a postfix program, and the builders of [WolframLanguageSemantic]() make the expressions from it. Source that this reader does not take [WolframLanguageGrammar]() reads over [WolframLanguageSemantic](), so its result is the grammar's. [WolframLanguageAST]() runs the grammar over [ASTAlgebra]().
- Source that is no Wolfram Language gives a <code>[Failure]()["ParseError", ...]</code> at once, the grammar never built for it. Its `"Position"` is the character of *code* just past the token reading stops at, where the kernel's own reader puts the caret of its syntax message; its `"Incomplete"` is True where *code* ends before its expression does, in an open bracket, string or comment or after an operator, which is the kernel's message of incomplete input, and False otherwise.

## Basic Examples

A definition, held:

```wl
WolframLanguageHeld["f[x_] := x^2 + 1"]
```

<!-- => {HoldComplete[f[x_] := x^2 + 1]} -->

Each line is an expression of its own:

```wl
WolframLanguageHeld["a = 1\nb = a + 1"]
```

<!-- => {HoldComplete[a = 1], HoldComplete[b = a + 1]} -->

## Scope

A sum is one call, each term after a `-` negated:

```wl
FullForm[WolframLanguageHeld["a - b + c"]]
```

<!-- => FullForm[{HoldComplete[a - b + c]}] -->

A chain of different relations is an [Inequality]():

```wl
FullForm[WolframLanguageHeld["0 < x <= 1"]]
```

<!-- => FullForm[{HoldComplete[Inequality[0, Less, x, LessEqual, 1]]}] -->

An operator at the end of a line carries the expression on to the next:

```wl
WolframLanguageHeld["total = a +\n  b"]
```

<!-- => {HoldComplete[total = a + b]} -->

A comment is whitespace, inside an expression or on a line of its own:

```wl
WolframLanguageHeld["(* a note *)\nf[x (* the argument *)]"]
```

<!-- => {HoldComplete[f[x]]} -->

Patterns, spans and pure functions:

```wl
WolframLanguageHeld["Replace[m[[2 ;; -1]], x:{__Integer} :> Total[x] / Length[x] & /@ x]"]
```

<!-- => {HoldComplete[Replace[m[[2 ;; -1]], (x:{__Integer} :> Total[x]/Length[x] & ) /@ x]]} -->

## Properties and Relations

`WolframLanguageHeld` gives what [ImportString]() gives:

```wl
code = "Module[{s = 0}, Do[s += i^2, {i, 10}]; s]\nf[x_?NumericQ] := Sqrt[x] /; x > 0"
```

<!-- => "Module[{s = 0}, Do[s += i^2, {i, 10}]; s]\nf[x_?NumericQ] := Sqrt[x] /; x > 0" -->

```wl
WolframLanguageHeld[code] === ImportString[code, {"WL", "HeldExpressions"}]
```

<!-- => True -->

## Possible Issues

An unclosed bracket is a [Failure](), *code* ending before its expression does:

```wl
WolframLanguageHeld["a = 1\nb = (c"]
```

A closer that closes nothing stops reading just past it:

```wl
WolframLanguageHeld["f[x)"]["Position"]
```

<!-- => 5 -->

## Neat Examples

The grammar reads its own source as the kernel reads it:

```wl
source = Import[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages", "WolframLanguage.wl"}], "Text"];
```

```wl
WolframLanguageHeld[source] === ImportString[source, {"WL", "HeldExpressions"}]
```

<!-- => True -->

---
Template: Symbol
Name: WolframLanguageHeld
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageHeld
Keywords: [Wolfram Language, InputForm, package, held expressions, HoldComplete, ImportString, parser zoo]
SeeAlso: [WolframLanguageHeldNext, WolframLanguageSyntaxQ, WolframLanguageAST, WolframLanguageConcrete, WolframLanguageGrammar, WolframLanguageSemantic, LinearBoxes, ParseOperatorTable, ImportString]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageHeld]()[*code*]</code> parses the Wolfram Language source string *code* to the list of its top-level expressions, each in [HoldComplete]().

## Details & Options

- The result is what <code>[ImportString]()[*code*, {"WL", "HeldExpressions"}]</code> gives: the expressions as the kernel reads them, before any of them evaluates, but where a notebook's input cell reads *code* otherwise, as the bullets below say, and for what Wolfram 15 reads wrongly, marked [W15 bug]. A statement that is `Null` alone is left out, as the kernel leaves it out.
- Linear syntax, a group of boxes written as text, reads as its boxes, as the kernel reads it; a group that *code* asks to be read as input reads as [LinearBoxes]() of them, where the kernel gives the expression [MakeExpression]() makes of them.
- Outside brackets a newline ends an expression wherever the expression could end, so `a` on one line and `+ b` on the next are two expressions, while `a +` followed by `b` is one. Inside brackets a newline is whitespace, and so is one right after a `;;`, as a notebook reads it, but for one before another `;;` where the first has no operand before it: `a ;;` on one line and `b` on the next are `a ;; b`, while `;;` and `;;` on two lines are two spans. Comments, nested ones included, are whitespace; in a comment a `\` before an opening paren takes it, so that it opens no comment, and a star after a `\` ends one, as a notebook reads it. A `\` at the end of a line, outside a string, continues it: `a\` and `b` on the next line are the name `ab`. A `\:xxxx`, `\.xx` or `\|xxxxxx` outside a string or a comment is the character its hexadecimal digits name, as the kernel reads it before it reads tokens: `a \:2192 b` is `RightArrow[a, b]`. A `?` or `??` that begins a statement asks about the words after it, as `?Plot*` is `Information["Plot*", LongForm -> False]`, which a notebook answers itself; elsewhere, as a notebook reads it, `?` asks about the expression after it, all that binds more tightly than `=`, a word of one token its text, so `f[?a b]` is `f[Information[a b, LongForm -> False]]` and `f[?x]` is `f[Information["x", LongForm -> False]]`, `??` takes a word of one token alone, a `?` or a `;;` after a `;` is a pattern test or a span of the compound, and a `?` after a pattern test is no Wolfram Language. A `.` before a digit begins a number, so `a.5` is `a*0.5`.
- The forms come out as a notebook builds them: `a - b` is `Plus[a, Times[-1, b]]`, `a/b` is `Times[a, Power[b, -1]]`, a minus folds into an integer or a real written right after it (`-2` is the integer `-2`) and takes anything else whole, a rational as `1*^-3` too (`-(2)` is `Times[-1, 2]` and `a - b c` is `Plus[a, Times[-1, Times[b, c]]]`), a unary plus is its own call (`a + +b` is `Plus[a, Plus[b]]`), `f @ x` is the call wherever it stands (`a <> StringJoin @ b` is `StringJoin[a, StringJoin[b]]`), and a chain of one flat operator is one call (`a + b + c` is `Plus[a, b, c]`). Right after a `.`, a prefix operator begins an operand, as a notebook reads it, so `a . -b` is `Dot[a, -b]`.
- A colon after a symbol names a pattern, as `x : _Integer` is `Pattern[x, _Integer]`, and a colon after a pattern gives its default, so `x_ : 1` is `Optional[x_, 1]` and `x_ | y_ : 1` is `x_ | Optional[y_, 1]`; after any other expression a colon is no Wolfram Language. The function between the two tildes of `a ~ f ~ b` is what binds more tightly than `~`, as a notebook reads it: `a ~ f++ ~ b` is `(f++)[a, b]`, while `a ~ f & ~ b` is no Wolfram Language.
- After `::`, as a notebook reads it, a word of one token, a name, a number, a blank, a slot or a `%`, is its text, and a group or a prefix operator and its operand is the expression: `a::1` is `MessageName[a, "1"]`, `a::b_` is `MessageName[a, "b_"]`, `a::(b)` is `MessageName[a, b]` and `a::-b` is `MessageName[a, -b]`. A name with a colon after it is a pattern, as `a::b:c` is `MessageName[a, b:c]`, and each `::` adds a part, as `a::b::c::d` is `MessageName[a, "b", "c", "d"]`.
- An operand of a span left out is `All`, as `a ;;` is `Span[a, All]`, but one a prefix operator begins is never left out: `a ;; !b` is `Span[a, !b]`, as in any other operand and as [CodeParser]() reads it, where Wolfram 15 ends the span before `!`, `!!` and a long-name prefix operator and multiplies, `(a ;; All)*(!b)` [W15 bug]. The `;;` after a span's second operand takes a third only where one begins after it; there, and after a span of three, a `;;` begins a span of its own, the spans one product: `a ;; b ;;` is `(a ;; b)*(1 ;; All)` and `a ;; b ;; c ;; d` is `(a ;; b ;; c)*(1 ;; d)`.
- A `=[` begins free-form input, as a notebook reads it: its text to the first `]`, the `]` of a long name too, is [FreeformEvaluate]() of the text from its first character that is no whitespace to the end of its line, a space where nothing is left, an operand like any other, so `a =[b, c]` is `a*FreeformEvaluate["b, c"]` and `=[ b ]` is `FreeformEvaluate["b "]`; text on a second line is no Wolfram Language. An operator that ends in `=`, but `//=` and `^:=`, ends before a `=[`, so `a==[b]` is `a = FreeformEvaluate["b"]`. A `=` with whitespace before the `[` begins no free-form input.
- The binding powers are the precedences [CodeParser]() publishes; [WolframLanguageGrammar]() generates the levels of its [ParseOperatorTable]() from them.
- A long name that is an operator, a bracket or an integral reads as the kernel reads it, spelt out or as its character: `a \[CircleTimes] b` is `CircleTimes[a, b]`, `\[LeftFloor]x\[RightFloor]` is `Floor[x]` and `\[Integral] f \[DifferentialD] x` is `Integrate[f, x]`; a long name that is whitespace is whitespace. `\[Application]` nests to the left, as a notebook reads it: `a \[Application] b \[Application] c` is `Application[Application[a, b], c]`.
- A return is a newline, and so is a long name that is one, NewLine, RawReturn, IndentingNewLine, LineSeparator or ParagraphSeparator, written out or as its character: outside brackets it ends an expression, as [ToExpression]() reads it. [ImportString]() leaves out the expressions after one written out; the two discretionary separators are no Wolfram Language.
- An integral reads as a notebook reads it: its signs of one kind, as `\[Integral]\[Integral]`, and its operand, read whole, whose factors end in as many differentials, `\[DifferentialD] x` or `\[CapitalDifferentialD] x`, no other factor one and none in parentheses, are the integral's head of the factors before them, 1 where there are none, and the variables, the last first: `\[Integral] f \[DifferentialD] x` is `Integrate[f, x]`, `\[ContourIntegral] f \[DifferentialD] x` is `ContourIntegral[f, x]` and `\[Integral]\[Integral] f \[DifferentialD] x \[DifferentialD] y` is `Integrate[f, y, x]`. Any other operand, as that of `\[Integral] f`, with no differential, is no Wolfram Language.
- The algebra reads numbers and strings from their text itself: a real keeps the precision or accuracy its marks give, or that its digits give past a machine real's, and a string's escapes are decoded, an unknown one kept as written. The file of `<<` and `>>` keeps a `\` in it, as in `<<a\b.m`, holds letters past ASCII and a bracket to its `]` or to the end of the source, as in `<<b[c].m`, and decodes its long names; an operator's character ends it, as a notebook reads it, so `<<a+b` is `Get["a"] + b`. After `>>` or `>>>` a file alone is the file, where the end of the line, `;`, `,` or a closer comes after it; else, as a notebook reads it, all that follows is an expression, so `x >> a b` is `Put[x, a b]` and `x >> a.m` is `Put[x, "a.m"]`. A name is the one leaf read by the kernel's reader, under [HoldComplete](), so it is made in [$Context]() as the kernel makes it.
- `WolframLanguageHeld` reads *code* in time linear in its length: one compiled pass over the character codes makes the tokens, compiled precedence climbing over the tokens, by the levels [WolframLanguageGrammar]() generates, makes a postfix program, and one pass over the program makes the expressions from it, as [WolframLanguageSemantic]() builds them. A statement that this reader does not take [WolframLanguageGrammar]() reads over [WolframLanguageSemantic](), and the statements after it this reader again, as [WolframLanguageHeldNext]() reads them. [WolframLanguageAST]() runs the grammar over [ASTAlgebra]().
- The paclet's `Kernel/WolframLanguageReader.wl` loads the parser core and the Wolfram Language's reader alone, with no other language or module of the paclet, for a program that only reads Wolfram Language text; [Get]() it in place of loading the whole paclet with [Needs]().
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

A `;;` after a span of three begins a span of its own, the spans a product:

```wl
WolframLanguageHeld["a ;; b ;; c ;; d"]
```

<!-- => {HoldComplete[(a ;; b ;; c)*(1 ;; d)]} -->

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

A prefix operator after `;;` begins the span's operand:

```wl
WolframLanguageHeld["a ;; !b"]
```

<!-- => {HoldComplete[a ;; ( !b)]} -->

Wolfram 15 ends the span there and multiplies [W15 bug]:

```wl
ImportString["a ;; !b", {"WL", "HeldExpressions"}]
```

<!-- => {HoldComplete[(a ;; All)*( !b)]} -->

## Neat Examples

The grammar reads its own source as the kernel reads it:

```wl
source = Import[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages", "WolframLanguage.wl"}], "Text"];
```

```wl
WolframLanguageHeld[source] === ImportString[source, {"WL", "HeldExpressions"}]
```

<!-- => True -->

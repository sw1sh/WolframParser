---
Template: Symbol
Name: WolframLanguageHeldNext
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageHeldNext
Keywords: [Wolfram Language, statement, one at a time, package, Get, HoldComplete, ToExpression, parser zoo]
SeeAlso: [WolframLanguageHeld, WolframLanguageGrammar, WolframLanguageSemantic, LinearBoxes, ToExpression, Get, EndOfFile]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageHeldNext]()[*code*, *pos*]</code> reads the statement of the Wolfram Language source string *code* whose line begins at position *pos*, giving <code>{[HoldComplete]()[*statement*], *next*, <|"Warnings" -> *warnings*|>}</code>, where *next* is the position the line after it begins at and *warnings* the syntax warnings the kernel gives as it reads the statement.

## Details & Options

- Reading *code* from position 1, then from each *next* in turn, gives its statements one at a time until it gives [EndOfFile](): the parts of <code>[ToExpression]()[*code*, [InputForm](), [HoldComplete]()]</code>, in order.
- A line ends at each newline, each return and each long name that is a newline, outside comments and strings, so a return and a newline together end two lines. Each line end after a statement's own, before the next statement or the end of *code*, gives a <code>[HoldComplete]()[[Null]()]</code>, as each line end before the first statement does. A source with no statement gives one such [Null]() for each of its line ends, or one where it has none.
- The names in a statement are made when that statement is read, in the [$Context]() and [$ContextPath]() of that moment. A statement evaluated before the next is read, such as [BeginPackage]() or [Begin](), so decides where the names after it are made, as [Get]() reads a package.
- The first call on *code* reads all of it, in one compiled pass over its characters and one over its tokens, and keeps what it finds for the calls after it, each of which builds only its own statement, until a call gives [EndOfFile]() or a [Failure](). What the last few sources read hold is kept.
- A statement that cannot be read gives <code>{[Failure]()["ParseError", ...], *pos*}</code>, with the `"Position"` and `"Incomplete"` that [WolframLanguageHeld]() gives for *code*; the statements before it read as they are. Reading stops at the line that holds the failure: `a )` fails as a whole, as the kernel reads it, rather than giving `a` first.
- *warnings* lists the warnings in the order the kernel's reader gives them, each `{tag}` or `{tag, argument}` of the message `Syntax::tag`: `{"com"}` for each [Null]() a comma leaves, after the opener of a bracket or before another comma, the closer or a token that begins no operand; `{"stresc", "q"}` for an escape such as `\q` that a string keeps as written; `{"sntoct1"}`, `{"sntoct2"}`, `{"snthex"}` and `{"snthex32"}` for an octal, `\.`, `\:` or `\|` code with too few digits; `{"sntufn", name}` for a long name no character has, or one not closed in code; `{"sntunc", name}` for one not closed at the end of a string, or `{"sntufn", name}` where the source ends in the string; and `{"sntmsng", text}` for a long name with no name, *text* the source from the statement on.
- A [Failure]() carries under its `"Warnings"` key the warnings the statement that cannot be read gives before reading stops.
- *pos* is 1 or a position an earlier call gave; from any other position the call reads the first statement whose line begins at or after it.
- A statement the compiled reader does not take is read by [WolframLanguageGrammar]() over [WolframLanguageSemantic](), and the statements after it by the compiled reader again.
- Linear syntax reads as [WolframLanguageHeld]() reads it: a group of boxes as its boxes, a group read as input as [LinearBoxes]() of them.

## Basic Examples

The first statement of a source, and the position the line of the next one begins at:

```wl
WolframLanguageHeldNext["x = 1\ny = x + 1", 1]
```

<!-- => {HoldComplete[x = 1], 7, <|"Warnings" -> {}|>} -->

From there, the next statement:

```wl
WolframLanguageHeldNext["x = 1\ny = x + 1", 7]
```

<!-- => {HoldComplete[y = x + 1], 16, <|"Warnings" -> {}|>} -->

Past the last statement:

```wl
WolframLanguageHeldNext["x = 1\ny = x + 1", 16]
```

<!-- => EndOfFile -->

A comma with nothing after it leaves a Null, with the warning the kernel gives for it:

```wl
WolframLanguageHeldNext["f[1,]", 1]
```

<!-- => {HoldComplete[f[1, Null]], 6, <|"Warnings" -> {{"com"}}|>} -->

## Scope

A function that reads every statement of a source, up to the first that cannot be read:

```wl
statements[code_String] := Module[{pos = 1, r, out = {}},
    While[ListQ[r = WolframLanguageHeldNext[code, pos]] && ! FailureQ[First[r]], AppendTo[out, First[r]]; pos = r[[2]]];
    out]
```

A line with only a comment on it is a Null between two definitions:

```wl
statements["f[x_] := x^2\n(* a note *)\ng[y_] := f[y] + 1"]
```

<!-- => {HoldComplete[f[x_] := x^2], HoldComplete[Null], HoldComplete[g[y_] := f[y] + 1]} -->

Inside brackets a newline is whitespace, so a statement can run over several lines:

```wl
statements["total = Plus[\n  a,\n  b]\ntotal"]
```

<!-- => {HoldComplete[total = a + b], HoldComplete[total]} -->

A string keeps an escape it has no meaning for as written, with a warning:

```wl
WolframLanguageHeldNext["\"a\\qb\"", 1]
```

<!-- => {HoldComplete["a\\qb"], 7, <|"Warnings" -> {{"stresc", "q"}}|>} -->

A long name that no character has stops reading; the [Failure]() holds its warning:

```wl
WolframLanguageHeldNext["a \\[Foo] b", 1][[1]]["Warnings"]
```

<!-- => {{"sntufn", "Foo"}} -->

## Properties and Relations

A source of two definitions and a comment:

```wl
code = "f[x_] := x^2\n\n(* a note *)\ng[y_] := f[y] + 1\n"
```

<!-- => "f[x_] := x^2\n\n(* a note *)\ng[y_] := f[y] + 1\n" -->

`statements`, defined under Scope, gives the parts [ToExpression]() gives the source held:

```wl
statements[code] === List @@ (HoldComplete /@ ToExpression[code, InputForm, HoldComplete])
```

<!-- => True -->

[WolframLanguageHeld]() gives the same statements, without the Nulls:

```wl
DeleteCases[statements[code], HoldComplete[Null]] === WolframLanguageHeld[code]
```

<!-- => True -->

## Possible Issues

A statement that cannot be read is a [Failure](), at the position its line begins at; the statements before it read as they are:

```wl
WolframLanguageHeldNext["a = 1\nb = (c", 1]
```

<!-- => {HoldComplete[a = 1], 7, <|"Warnings" -> {}|>} -->

```wl
WolframLanguageHeldNext["a = 1\nb = (c", 7]
```

A return and a newline are two line ends, as [ToExpression]() counts them, so a blank line between two statements written with both gives three Nulls:

```wl
statements["a\r\n\r\nb"]
```

<!-- => {HoldComplete[a], HoldComplete[Null], HoldComplete[Null], HoldComplete[Null], HoldComplete[b]} -->

```wl
ToExpression["a\r\n\r\nb", InputForm, HoldComplete]
```

<!-- => HoldComplete[a, Null, Null, Null, b] -->

## Neat Examples

Evaluating each statement before the next is read makes the names of a package in the contexts its [BeginPackage]() and [Begin]() give:

```wl
code = "BeginPackage[\"Demo`\"]\nsquare\nBegin[\"`Private`\"]\nhelper\nEnd[]\nEndPackage[]"
```

<!-- => "BeginPackage[\"Demo`\"]\nsquare\nBegin[\"`Private`\"]\nhelper\nEnd[]\nEndPackage[]" -->

```wl
Reap[Module[{pos = 1, r},
    While[ListQ[r = WolframLanguageHeldNext[code, pos]] && ! FailureQ[First[r]],
        If[MatchQ[First[r], HoldComplete[_Symbol]], Sow[Context @@ First[r]], ReleaseHold[First[r]]];
        pos = r[[2]]]]][[2, 1]]
```

<!-- => {"Demo`", "Demo`Private`"} -->

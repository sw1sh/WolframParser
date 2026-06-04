---
Template: Symbol
Name: Parse
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/Parse
Keywords: [parser, parse, run, entry point]
SeeAlso: [ParserCompile, ParserCombinator, ParsePartial, Interpreter]
RelatedGuides: [WolframParser]
---

## Usage

<code>[Parse]()[parser, input]</code> runs a parser (a [ParserCombinator]() or a [GrammarRules]() declaration) against an input (a [String](), a [List]() of tokens, or a [List]() of Wolfram expressions). Returns the parse result on success, or a [Failure]() object (tagged `"ParseError"`) on failure.

## Details & Options

- `Parse` requires the parser to consume the *entire* input. To accept a partial parse and get back the leftover, use [ParsePartial]().
- A `GrammarRules` declaration is lowered to a `ParserCombinator` (and JIT-compiled the first time it is seen) before being run; the lowering result is cached so a second `Parse[grammar, ...]` call against the same grammar reuses the work.
- For a `ParserCombinator` *without* a `"Code"` entry in its options, `Parse` runs the **interpretive** path. For a parser already passed through [ParserCompile](), `Parse` invokes the compiled function directly. Either way, `parser[input]` and `Parse[parser, input]` are equivalent ([ParserCombinator]() carries a SubValue rule that routes one to the other).
- On success the return value is the structured result the combinator built - usually a string, a list of children, or an action's return value.
- On failure the return value is a `Failure["ParseError", <|"Position" -> _, "Expected" -> _, "Found" -> _, ...|>]` association carrying the position of the furthest-advanced failure, the set of expected tokens at that position, and what was found instead.

## Basic Examples

A literal parser matches when the input is exactly the literal:

```wl
Parse[ParseLiteral["foo"], "foo"]
```

<!-- => "foo" -->

A digit parser:

```wl
Parse[ParseCharacter[DigitCharacter], "5"]
```

<!-- => "5" -->

A sequence built with the `~~` operator:

```wl
Parse[ParseLiteral["foo"] ~~ ParseLiteral["bar"], "foobar"]
```

<!-- => {"foo", "bar"} -->

The same via the SubValue (`parser[input]` is `Parse[parser, input]`):

```wl
(ParseLiteral["foo"] ~~ ParseLiteral["bar"])["foobar"]
```

<!-- => {"foo", "bar"} -->

## Scope

Choice with the `|` operator - PEG-ordered, first match wins:

```wl
Parse[ParseLiteral["foo"] | ParseLiteral["bar"], "bar"]
```

<!-- => "bar" -->

A repetition - one-or-more digits:

```wl
Parse[ParseCharacter[DigitCharacter].., "123"]
```

<!-- => {"1", "2", "3"} -->

## Properties and Relations

A `GrammarRules` declaration is accepted directly (and lowered + compiled internally):

```wl
Parse[
    GrammarRules[{"the weather in <city>" -> city}],
    "the weather in NYC"
]
```

<!-- => "NYC" -->

`Parse` requires the *whole* input to be consumed. A partial match is an error:

```wl
Parse[ParseLiteral["foo"], "foobar"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> "<end of input>", "Found" -> "b", "Rule" -> Literal["foo"]|>] -->

[ParsePartial]() relaxes this and returns the leftover:

```wl
ParsePartial[ParseLiteral["foo"], "foobar"]
```

<!-- => {"foo", "bar"} -->

## Possible Issues

A complete-input mismatch returns a `Failure["ParseError", ...]` rather than throwing - the error is a value, easy to pattern-match on:

```wl
Parse[ParseLiteral["foo"], "xyz"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "foo", "Found" -> "x", "Rule" -> Literal["foo"]|>] -->

Use [MatchQ]() to branch on success vs failure:

```wl
res = Parse[ParseLiteral["foo"], "xyz"];
If[FailureQ[res], "failed: " <> res["Found"], "ok: " <> res]
```

<!-- => "failed: x" -->

## Neat Examples

A floating-point parser, end-to-end:

```wl
Parse[
    ParseAction[
        ParseCharacter[DigitCharacter].. ~~ Optional[
            ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]..
        ],
        ToExpression @ StringJoin @ Flatten[{##}] &
    ],
    "3.14"
]
```

<!-- => 3.14 -->

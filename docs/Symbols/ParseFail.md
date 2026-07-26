---
Template: Symbol
Name: ParseFail
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseFail
Keywords: [parser, fail, failure, error, custom error, message, ParseChoice, guard]
SeeAlso: [ParseSucceed, ParseChoice, Parse, ParserCombinator, Failure]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseFail]()[*msg*]</code> returns the [ParserCombinator]() that always fails, reporting *msg* as the expected token at the current position and consuming no input.

## Details & Options

- [ParseFail]() never matches: running it produces a [Failure]() (tagged `"ParseError"`) whose `"Expected"` field is *msg* and whose `"Found"` field is the empty string `""`, since nothing was inspected.
- The failure carries the current `"Position"`; placed after other parsers in a [ParseSequence](), it reports the position reached so far — a way to attach a custom message to a specific point in a grammar.
- It is the dual of [ParseSucceed]() and the zero of [ParseChoice](): a branch that can never win.
- As a branch of a [ParseChoice](), *msg* joins the accumulated `"Expected"` set alongside the other branches' expected tokens at the furthest-advanced position.
- *msg* is carried verbatim into the `"Expected"` field, so a descriptive string reads best in the rendered failure.

## Basic Examples

The constructor holds its message in a `"Fail"` combinator:

```wl
ParseFail["nope"]
```

<!-- => ParserCombinator[Fail, "nope", <||>] -->

<!-- #| annotation: 26.07.26: Design review - ParseFail is the parser monad's zero: the always-failing parser, the dual of ParseSucceed and the identity of ParseChoice. Modelled on Parsec's parserZero / fail, but instead of raising it surfaces the same structured Failure["ParseError", ...] every other parse failure does, so it composes with Confirm / Enclose and pattern-matches uniformly. The message is data (the "Expected" field), not a thrown string. -->

Running it fails with that message whatever the input, with an empty `"Found"`:

```wl
Parse[ParseFail["boom"], "anything"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "boom", "Found" -> ""|>] -->

## Scope

Used after a matched prefix, [ParseFail]() attaches a custom message at the position the sequence reached — here rejecting an empty pair of parentheses at position 2:

```wl
Parse[ParseLiteral["("] ~~ ParseFail["empty groups not allowed"] ~~ ParseLiteral[")"], "()"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "empty groups not allowed", "Found" -> ""|>] -->

As the last branch of a [ParseChoice](), it contributes its message to the diagnostic when every real alternative has failed:

```wl
Parse[ParseChoice[ParseLiteral["yes"], ParseFail["expected yes/no"]], "maybe"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> {"yes", "expected yes/no"}, "Found" -> "m"|>] -->

## Properties and Relations

A [ParseFail]() branch does not interfere when a real alternative matches — the choice still returns the first success:

```wl
Parse[ParseChoice[ParseLiteral["yes"], ParseLiteral["no"], ParseFail["expected yes or no"]], "no"]
```

<!-- => "no" -->

[ParseSucceed]() is the dual: where [ParseFail]() never matches, [ParseSucceed]() always does, consuming nothing.

```wl
Parse[ParseSucceed["always"], ""]
```

<!-- => "always" -->

## Possible Issues

The failure is a returned value, not a thrown exception, so it is inspected with [FailureQ]() or by reading its fields rather than caught. The `"Found"` field is always the empty string, because [ParseFail]() consumes and inspects nothing:

```wl
Parse[ParseFail["boom"], "xyz"]["Found"]
```

<!-- => "" -->

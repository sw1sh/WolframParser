---
Template: Symbol
Name: ParsePartial
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParsePartial
Keywords: [parser, partial, leftover, remaining, prefix, unconsumed, incremental]
SeeAlso: [Parse, ParserCombinator, ParserCompile, StringDrop]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParsePartial]()[*parser*, *input*]</code> runs *parser* against *input* without requiring it to consume all of *input*; on success it returns <code>{*result*, *leftover*}</code> — the parser's result together with the unconsumed suffix of *input*.

## Details & Options

- Where [Parse]() fails on any unconsumed input, [ParsePartial]() succeeds and hands that remainder back as *leftover*, a [String]().
- On a full-input match *leftover* is the empty string `""`; *result* is exactly what [Parse]() would return for the consumed prefix.
- Only the whole-input requirement differs from [Parse](): a *genuine* parse failure (the parser cannot match at all) returns the same [Failure]() (tagged `"ParseError"`) that [Parse]() would.
- The callable form `parser[input]` routes to [Parse](), not [ParsePartial]() — call [ParsePartial]() explicitly to keep the leftover.

| Option | Default | Description |
|--------|---------|-------------|
| `"Memoize"` | `False` | cache each nonterminal's result per `{rule, position}` (packrat), turning an ordered-choice grammar that re-parses a shared operand from exponential to linear time; sound for PEG, so the result is unchanged |

## Basic Examples

A parser that matches a prefix returns its result and the leftover suffix:

```wl
ParsePartial[ParseLiteral["foo"], "foobar"]
```

<!-- => {"foo", "bar"} -->

<!-- #| annotation: 26.07.26: Design review - Parse and ParsePartial share one interpreter; Parse is ParsePartial plus an end-of-input check. Splitting them keeps the common case (whole-input parse, the top-level entry point) honest about leftover while still exposing the {result, leftover} pair a tokeniser or REPL-style incremental reader needs. Modelled on Parsec's runParser leaving unconsumed input in its state, surfaced here as an explicit second list element rather than hidden parser state. -->

On a full match the leftover is the empty string:

```wl
ParsePartial[ParseLiteral["foo"], "foo"]
```

<!-- => {"foo", ""} -->

The same call under [Parse]() fails, because [Parse]() requires the whole input to be consumed and `"bar"` is left over:

```wl
Parse[ParseLiteral["foo"], "foobar"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> "<end of input>", "Found" -> "b"|>] -->

## Scope

*result* keeps its full structure — here a [ParseSequence]() result — with the leftover as the second element:

```wl
ParsePartial[ParseLiteral["foo"] ~~ ParseLiteral["bar"], "foobarbaz"]
```

<!-- => {{"foo", "bar"}, "baz"} -->

Memoisation is sound for PEG, so `"Memoize" -> True` never changes the result — only the time and space taken to reach it:

```wl
ParsePartial[ParseLiteral["foo"], "foobar", "Memoize" -> True]
```

<!-- => {"foo", "bar"} -->

## Properties and Relations

[Parse]() is [ParsePartial]() plus a check that the leftover is empty; on a full match the two agree up to that wrapping:

```wl
Parse[ParseLiteral["foo"], "foo"]
```

<!-- => "foo" -->

The callable form of a [ParserCombinator]() is [Parse](), not [ParsePartial](), so it still requires the whole input — call [ParsePartial]() by name to accept a leftover:

```wl
(ParseLiteral["foo"])["foobar"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> "<end of input>", "Found" -> "b"|>] -->

## Possible Issues

[ParsePartial]() relaxes only the end-of-input check; a parser that cannot match at the current position still fails, exactly as under [Parse]():

```wl
ParsePartial[ParseLiteral["foo"], "xyz"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "foo", "Found" -> "x"|>] -->

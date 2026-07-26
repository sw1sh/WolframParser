---
Template: Symbol
Name: ParseSucceed
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseSucceed
Keywords: [parser, succeed, pure, return, unit, constant, default, monad]
SeeAlso: [ParseFail, ParseChoice, ParseAction, Parse, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseSucceed]()[*val*]</code> returns the [ParserCombinator]() that always succeeds, consuming no input and yielding *val* as its result.

## Details & Options

- [ParseSucceed]() never consumes input and never fails: the parse position is left exactly where it started.
- It is the `pure` / `return` of the parser — a way to lift a plain value into a parser that produces it without examining the input.
- As the final branch of a [ParseChoice](), it supplies a default when none of the earlier alternatives match, so the choice cannot fail.
- Pair it with [ParseAction]() to inject a *computed* constant, or with [ParseSequence]() (`~~`) to splice a fixed value between matched pieces.
- Because it consumes nothing, a top-level [Parse]() of [ParseSucceed]() alone succeeds only on the empty string; on any other input the unconsumed remainder makes [Parse]() report a leftover. Use [ParsePartial](), or embed it in a larger grammar, when there is input to leave behind.

## Basic Examples

The constructor holds its value in a `"Succeed"` combinator:

```wl
ParseSucceed[42]
```

<!-- => ParserCombinator[Succeed, 42, <||>] -->

<!-- #| annotation: 26.07.26: Design review - ParseSucceed is the parser monad's pure/return (Parsec's return / pure): it lifts a value into a trivially-succeeding parser and consumes nothing. Named ParseSucceed rather than Return / Pure to keep the Parse* family verb-first and to avoid clashing with the built-in Return. Its dual is ParseFail; together they are the unit and zero of ParseChoice. -->

It succeeds on empty input, returning the constant:

```wl
Parse[ParseSucceed["always"], ""]
```

<!-- => "always" -->

It consumes nothing, so under [ParsePartial]() the whole input comes back as leftover:

```wl
ParsePartial[ParseSucceed[42], "abc"]
```

<!-- => {42, "abc"} -->

## Scope

Splice a fixed value into a sequence — [ParseSucceed]() contributes its value without advancing the position:

```wl
Parse[ParseSucceed["x"] ~~ ParseLiteral["foo"], "foo"]
```

<!-- => {"x", "foo"} -->

As the last branch of a [ParseChoice](), a real alternative still wins when it matches:

```wl
Parse[ParseChoice[ParseLiteral["yes"], ParseSucceed["default"]], "yes"]
```

<!-- => "yes" -->

---

When no earlier branch matches, the [ParseSucceed]() branch supplies the default and consumes nothing, so the input is left for [ParsePartial]() to return:

```wl
ParsePartial[ParseChoice[ParseLiteral["yes"], ParseSucceed["default"]], "maybe"]
```

<!-- => {"default", "maybe"} -->

## Properties and Relations

Wrapped in [ParseAction](), [ParseSucceed]() is `pure` feeding a function — the value is lifted in, then transformed:

```wl
Parse[ParseAction[ParseSucceed[3], (#^2 &)], ""]
```

<!-- => 9 -->

The `optional-with-default` idiom: try to read a number, else fall back to a constant that the same action converts:

```wl
Parse[ParseAction[ParseChoice[ParseRegex["[0-9]+"], ParseSucceed["0"]], FromDigits], ""]
```

<!-- => 0 -->

[ParseFail]() is the dual: where [ParseSucceed]() always matches, [ParseFail]() never does.

```wl
ParseFail["nope"]
```

<!-- => ParserCombinator[Fail, "nope", <||>] -->

## Possible Issues

Because it consumes nothing, a top-level [Parse]() of [ParseSucceed]() on non-empty input fails on the leftover — the value was produced, but the input was not consumed:

```wl
Parse[ParseSucceed["x"], "abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<end of input>", "Found" -> "a"|>] -->

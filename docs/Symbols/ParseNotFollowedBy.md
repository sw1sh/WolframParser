---
Template: Symbol
Name: ParseNotFollowedBy
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseNotFollowedBy
Keywords: [parser, negative lookahead, not followed by, zero-width, syntactic predicate, assertion, word boundary, PEG]
SeeAlso: [ParseLookahead, ParseChoice, ParseSequence, ParseAction, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseNotFollowedBy]()[*p*]</code> returns the [ParserCombinator]() that succeeds only when *p* would not match at the current position, and fails when it would, consuming no input.

## Details & Options

- `ParseNotFollowedBy` is a *zero-width* negative assertion (the PEG predicate `!p`): on success the input position is unchanged.
- The result on success is [Null](); on failure the reported `"Expected"` is `"<not followed by parser>"` at the current position.
- It is the dual of [ParseLookahead]() (`&p`): on any input exactly one of `ParseLookahead[p]` and `ParseNotFollowedBy[p]` succeeds.
- A common use is a *word boundary* - match a keyword only when it is not immediately followed by more identifier characters.
- Because it consumes nothing, it contributes a [Null]() to a [ParseSequence]() result; reshape with [ParseAction]() if that placeholder is unwanted.

## Basic Examples

A negative lookahead succeeds when its parser would not match, consuming nothing - [ParsePartial]() shows the input still fully available:

```wl
ParsePartial[ParseNotFollowedBy[ParseLiteral["a"]], "xbc"]
```

<!-- => {Null, "xbc"} -->

---

It fails when *p* would match:

```wl
Parse[ParseNotFollowedBy[ParseLiteral["a"]], "abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<not followed by parser>", "Found" -> "a"|>] -->

---

The combinator wraps its argument:

```wl
ParseNotFollowedBy[ParseLiteral["bar"]]
```

<!-- => ParserCombinator[NotFollowedBy, ParserCombinator[Literal, "bar", <||>], <||>] -->

## Scope

After `"foo"`, assert that `"bar"` does not follow - it does not, so the parse succeeds and the assertion contributes a [Null]():

```wl
Parse[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]], "foo"]
```

<!-- => {"foo", Null} -->

---

When the forbidden `"bar"` does follow, the assertion fails at that position:

```wl
Parse[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]] ~~ ParseLiteral["bar"], "foobar"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> "<not followed by parser>", "Found" -> "b"|>] -->

---

A keyword with a word boundary - `"let"` matches only when no letter follows it:

```wl
Parse[ParseLiteral["let"] ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], "let"]
```

<!-- => {"let", Null} -->

---

On `"lets"` the boundary assertion fails, so `"let"` is not accepted as a keyword here:

```wl
Parse[ParseLiteral["let"] ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], "lets"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> "<not followed by parser>", "Found" -> "s"|>] -->

## Properties and Relations

[ParseLookahead]() is the positive dual - it succeeds on exactly the inputs where [ParseNotFollowedBy]() fails:

```wl
ParsePartial[ParseLookahead[ParseLiteral["a"]], "abc"]
```

<!-- => {Null, "abc"} -->

---

Wrap the sequence with [ParseAction]() to drop the assertion's [Null]() and keep only the matched value:

```wl
Parse[ParseAction[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]], (#1 &)], "foo"]
```

<!-- => "foo" -->

## Possible Issues

A negative lookahead consumes nothing, so on its own it leaves the input unconsumed and [Parse]() - which requires the *entire* input to be consumed - reports an end-of-input failure. Combine it with a consumer, or use [ParsePartial]():

```wl
Parse[ParseNotFollowedBy[ParseLiteral["x"]], "abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<end of input>", "Found" -> "a"|>] -->

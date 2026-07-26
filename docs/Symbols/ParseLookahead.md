---
Template: Symbol
Name: ParseLookahead
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseLookahead
Keywords: [parser, lookahead, positive lookahead, zero-width, syntactic predicate, assertion, PEG]
SeeAlso: [ParseNotFollowedBy, ParseChoice, ParseSequence, ParsePosition, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseLookahead]()[*p*]</code> returns the [ParserCombinator]() that succeeds when *p* would match at the current position and fails when it would not, consuming no input.

## Details & Options

- `ParseLookahead` is a *zero-width* assertion (a syntactic predicate): on success the input position is unchanged, so the next parser in a [ParseSequence]() re-reads from the same place.
- The result on success is [Null](), never *p*'s result. Use a lookahead as a guard, not to capture a value.
- On failure it reports *p*'s own diagnostic - the position, expected token, and found token *p* would have produced.
- It is the PEG positive-lookahead predicate `&p`; [ParseNotFollowedBy]() is the negative predicate `!p`, and the two are complementary - on any input exactly one of them succeeds.
- Because it consumes nothing, a lookahead used on its own leaves the whole input unconsumed. Pair it with a parser that consumes, or run it under [ParsePartial]().

## Basic Examples

A positive lookahead succeeds when its parser would match, consuming nothing - [ParsePartial]() returns the leftover, showing the input is still fully available:

```wl
ParsePartial[ParseLookahead[ParseLiteral["a"]], "abc"]
```

<!-- => {Null, "abc"} -->

---

It fails, carrying *p*'s own diagnostic, when *p* would not match:

```wl
Parse[ParseLookahead[ParseLiteral["a"]], "xbc"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "a", "Found" -> "x"|>] -->

---

The combinator wraps its argument:

```wl
ParseLookahead[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Lookahead, ParserCombinator[Literal, "foo", <||>], <||>] -->

## Scope

In a sequence the lookahead consumes nothing, so a following parser re-reads from the same position - here the same `"foo"` is checked, then matched:

```wl
Parse[ParseLookahead[ParseLiteral["foo"]] ~~ ParseLiteral["foo"], "foo"]
```

<!-- => {Null, "foo"} -->

---

Used as a guard, commit to a branch only once the lookahead confirms what is ahead - check for a leading digit, then consume the run of digits:

```wl
Parse[ParseLookahead[ParseCharacter[DigitCharacter]] ~~ ParseCharacter[DigitCharacter].., "42"]
```

<!-- => {Null, {"4", "2"}} -->

## Properties and Relations

[ParseNotFollowedBy]() is the negation: where `ParseLookahead[p]` succeeds, `ParseNotFollowedBy[p]` fails. Here `"a"` is present, so the negative form fails:

```wl
Parse[ParseNotFollowedBy[ParseLiteral["a"]], "abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<not followed by parser>", "Found" -> "a"|>] -->

---

Two negative lookaheads compose to a positive one - `ParseNotFollowedBy[ParseNotFollowedBy[p]]` succeeds exactly when *p* is present, still consuming nothing:

```wl
ParsePartial[ParseNotFollowedBy[ParseNotFollowedBy[ParseLiteral["x"]]], "x"]
```

<!-- => {Null, "x"} -->

## Possible Issues

A lookahead consumes nothing, so on its own it leaves the input unconsumed and [Parse]() - which requires the *entire* input to be consumed - reports an end-of-input failure. Pair the lookahead with a consumer, or use [ParsePartial]():

```wl
Parse[ParseLookahead[ParseLiteral["foo"]], "foo"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<end of input>", "Found" -> "f"|>] -->

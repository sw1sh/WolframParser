---
Template: Symbol
Name: ParseSome
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseSome
Keywords: [parser, repetition, one or more, Kleene plus, Repeated]
SeeAlso: [ParseMany, ParseOptional, ParseSepBy1, ParserCombinator, Repeated]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseSome]()[$p$]</code> returns the [ParserCombinator]() that matches *one or more* successive copies of $p$, returning the [List]() of results. Fails if zero copies match.

## Details & Options

- "One or more" - the parser requires at least one match.
- The operator overload `$p$..` lowers to `ParseSome[$p$]` via [Repeated]().
- Greedy by default.
- Result type: [List]() of $p$'s result type (always non-empty).

## Basic Examples

One or more digits:

```wl
Parse[ParseSome[ParseCharacter[DigitCharacter]], "123"]
```

<!-- => {"1", "2", "3"} -->

The same via the `..` operator:

```wl
Parse[ParseCharacter[DigitCharacter].., "123"]
```

<!-- => {"1", "2", "3"} -->

The empty input fails:

```wl
Parse[ParseSome[ParseCharacter[DigitCharacter]], ""]
```

<!-- => ParseError[<|"Position" -> 1, "Expected" -> "<digit>", "Found" -> "<end of input>"|>] -->

## Scope

A single match is fine:

```wl
Parse[ParseSome[ParseCharacter[DigitCharacter]], "5"]
```

<!-- => {"5"} -->

## Properties and Relations

`ParseSome[$p$]` and `ParseMany[$p$]` differ only at the empty match:

```wl
{Parse[ParseSome[ParseLiteral["x"]], "xxx"], Parse[ParseMany[ParseLiteral["x"]], "xxx"]}
```

<!-- => {{"x", "x", "x"}, {"x", "x", "x"}} -->

`ParseSome[$p$]` is `$p$ ** ParseMany[$p$]` reshaped to a flat list:

```wl
Parse[ParseSome[ParseCharacter[DigitCharacter]], "42"]
```

<!-- => {"4", "2"} -->

## Possible Issues

The `..` postfix binds tighter than `**`, so `p1 ** p2..` is `ParseSequence[p1, ParseSome[p2]]` - the `..` only applies to `p2`. Use parentheses to repeat a sequence: `(p1 ** p2)..`.

```wl
Parse[ParseLiteral["a"] ** ParseLiteral["b"]..., "abbb"]
```

<!-- => {"a", {"b", "b", "b"}} -->

## Neat Examples

A whole-string number:

```wl
Parse[
    ParseAction[ParseCharacter[DigitCharacter].., FromDigits @ StringJoin[#] &],
    "12345"
]
```

<!-- => 12345 -->

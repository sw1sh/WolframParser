---
Template: Symbol
Name: ParseSepBy1
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseSepBy1
Keywords: [parser, separator, separated by, one or more, non-empty list, delimited]
SeeAlso: [ParseSepBy, ParseSome, ParseMany, ParseChainLeft, ParseOperatorTable, ParseBetween, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseSepBy1]()[*p*, *sep*]</code> returns the [ParserCombinator]() that matches *one or more* occurrences of *p* separated by *sep*, returning the nonempty [List]() of *p*'s results. It fails if no *p* matches.

## Details & Options

- "One or more" — at least one *p* is required; input on which the first *p* fails is rejected with an `"at least one occurrence"` error.
- Identical to [ParseSepBy]() except at the empty match: where [ParseSepBy]() returns `{}`, `ParseSepBy1` fails. This is the [ParseSome]() / [ParseMany]() distinction carried to separated lists.
- The separators are consumed but not kept; the result is the flat [List]() of *p* results only.
- A *trailing* separator is not consumed, as in [ParseSepBy]().
- Result type: nonempty [List]() of *p*'s result type.

## Basic Examples

One or more comma-separated digits:

```wl
digit = ParseCharacter[DigitCharacter];
comma = ParseLiteral[","];
Parse[ParseSepBy1[digit, comma], "7,8"]
```

<!-- => {"7", "8"} -->

---

A single item, with no separator, still matches — "one or more" includes exactly one:

```wl
Parse[ParseSepBy1[digit, comma], "5"]
```

<!-- => {"5"} -->

---

The empty input fails, because at least one item is required:

```wl
Parse[ParseSepBy1[digit, comma], ""]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "at least one occurrence", "Found" -> "<end of input>"|>] -->

## Scope

The item and separator can be any parsers — here whole words separated by `,`:

```wl
word = ParseAction[ParseSome[ParseCharacter[LetterCharacter]], StringJoin];
Parse[ParseSepBy1[word, comma], "foo,bar"]
```

<!-- => {"foo", "bar"} -->

---

The constructor returns a [ParserCombinator](), rendered as a summary box:

```wl
ParseSepBy1[digit, comma]
```

<!-- => ParserCombinator[SepBy1] -->

## Properties and Relations

`ParseSepBy1` and [ParseSepBy]() agree on every non-empty input and differ only when nothing matches — [ParseSepBy]() succeeds with `{}` there:

```wl
Parse[ParseSepBy[digit, comma], ""]
```

<!-- => {} -->

## Possible Issues

A *leading* separator has no first *p* to match, so the parse fails at the very first position:

```wl
Parse[ParseSepBy1[digit, comma], ",1"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "at least one occurrence", "Found" -> ","|>] -->

## Neat Examples

A function-call argument list that must be non-empty — [ParseBetween]() supplies the parentheses and `ParseSepBy1` the arguments:

```wl
call = ParseSequence[word,
   ParseBetween[ParseLiteral["("], ParseSepBy1[word, comma], ParseLiteral[")"]]];
Parse[call, "f(a,b,c)"]
```

<!-- => {"f", {"a", "b", "c"}} -->

---

A single argument is fine:

```wl
Parse[call, "f(a)"]
```

<!-- => {"f", {"a"}} -->

---

An empty argument list `f()` is rejected — exactly the guarantee [ParseSepBy]() would not give:

```wl
Parse[call, "f()"]
```

<!-- => Failure["ParseError", <|"Position" -> 3, "Expected" -> "at least one occurrence", "Found" -> ")"|>] -->

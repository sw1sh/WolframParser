---
Template: Symbol
Name: ParseSequence
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseSequence
Keywords: [parser, sequence, composition, StringExpression]
SeeAlso: [ParseChoice, ParseBetween, ParseMany, ParserCombinator, StringExpression]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseSequence]()[$p_1$, $p_2$, …, $p_n$]</code> returns the [ParserCombinator]() that matches each $p_i$ in order at successive input positions, returning the list `{$r_1$, $r_2$, …, $r_n$}` of their results.

## Details & Options

- Failure of any $p_i$ aborts the sequence; the failure is reported at the *furthest-advanced* position reached.
- The operator overload `p1 ~~ p2` lowers to `ParseSequence[p1, p2]` via [StringExpression](). The UpValue *only* fires when both sides are `ParserCombinator` instances - plain string sequences are unaffected. Chains flatten: `p1 ~~ p2 ~~ p3` is one `ParseSequence` of three children, not nested pairs.
- Result type: [List](). Use [ParseAction]() to reshape it.

## Basic Examples

A two-element sequence:

```wl
Parse[ParseSequence[ParseLiteral["foo"], ParseLiteral["bar"]], "foobar"]
```

<!-- => {"foo", "bar"} -->

The same via the `~~` operator:

```wl
Parse[ParseLiteral["foo"] ~~ ParseLiteral["bar"], "foobar"]
```

<!-- => {"foo", "bar"} -->

## Scope

Three-element sequence flattens:

```wl
ParseLiteral["a"] ~~ ParseLiteral["b"] ~~ ParseLiteral["c"]
```

<!-- => ParserCombinator[Sequence, {ParserCombinator[Literal, "a", <||>], ParserCombinator[Literal, "b", <||>], ParserCombinator[Literal, "c", <||>]}, <||>] -->

Mixed with a character class:

```wl
Parse[
    ParseLiteral["v"] ~~ ParseCharacter[DigitCharacter] ~~ ParseCharacter[DigitCharacter],
    "v42"
]
```

<!-- => {"v", "4", "2"} -->

## Properties and Relations

`ParseSequence` is the dual of [ParseChoice](): sequence is *all of these in order*, choice is *first of these that matches*. They compose in the natural way:

```wl
Parse[
    ParseSequence[
        ParseChoice[ParseLiteral["red"], ParseLiteral["green"]],
        ParseLiteral["-light"]
    ],
    "red-light"
]
```

<!-- => {"red", "-light"} -->

A single-element sequence is the parser itself (the `Sequence` head is dropped by the constructor's canonicalisation):

```wl
ParseSequence[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Literal, "foo", <||>] -->

## Possible Issues

A partial-match failure on $p_2$ does *not* backtrack what $p_1$ already consumed (PEG semantics). Wrap with [ParseTry]() if you need full backtracking on failure of a later branch:

```wl
Parse[
    ParseChoice[
        ParseTry[ParseLiteral["fo"] ~~ ParseLiteral["x"]],
        ParseLiteral["fo"] ~~ ParseLiteral["o"]
    ],
    "foo"
]
```

<!-- => {"fo", "o"} -->

## Neat Examples

A key-value parser - identifier, equals, value:

```wl
Parse[
    ParseAction[
        ParseCharacter[LetterCharacter].. ~~
            ParseLiteral["="] ~~
            ParseCharacter[DigitCharacter]..,
        Function[{lhs, _, rhs}, StringJoin[lhs] -> FromDigits @ StringJoin[rhs]]
    ],
    "x=42"
]
```

<!-- => "x" -> 42 -->

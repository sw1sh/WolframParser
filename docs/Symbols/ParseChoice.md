---
Template: Symbol
Name: ParseChoice
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseChoice
Keywords: [parser, choice, alternation, PEG, ordered, Alternatives]
SeeAlso: [ParseSequence, ParseTry, ParserCombinator, Alternatives]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseChoice]()[$p_1$, $p_2$, …, $p_n$]</code> returns the [ParserCombinator]() that tries each $p_i$ in order and returns the result of the *first* one that matches.

## Details & Options

- *PEG-ordered*: once a branch matches, the rest are not tried, even if a *later* production in the surrounding grammar later fails. To get full backtracking, wrap with [ParseTry]() on the branches that need it.
- The operator overload `p1 | p2` lowers to `ParseChoice[p1, p2]` via [Alternatives](). Chains flatten - `p1 | p2 | p3` is one `ParseChoice` of three children.
- On failure, the reported error is the *furthest-advanced* failure across all tried branches; the `Expected` set is the *union* of the per-branch expected sets at that position.
- Result type: whatever the matched branch returned.

## Basic Examples

A two-branch choice:

```wl
ParseChoice[ParseLiteral["foo"], ParseLiteral["bar"]]
```

Run on input, the first branch that matches gives the result:

```wl
Parse[ParseChoice[ParseLiteral["foo"], ParseLiteral["bar"]], "bar"]
```

<!-- => "bar" -->

The same via the `|` operator:

```wl
Parse[ParseLiteral["foo"] | ParseLiteral["bar"], "bar"]
```

<!-- => "bar" -->

PEG-ordered - the first matching branch wins:

```wl
Parse[ParseLiteral["foo"] | ParseLiteral["foobar"], "foobar"]
```

(The `ParseLiteral["foo"]` branch matched, then `Parse` rejected the leftover `"bar"`. Swap the order to make `ParseLiteral["foobar"]` the first try.)

## Scope

A three-way choice flattens through the `|` chain:

```wl
ParseLiteral["a"] | ParseLiteral["b"] | ParseLiteral["c"]
```

Choice can mix combinator types:

```wl
Parse[
    ParseChoice[
        ParseCharacter[DigitCharacter],
        ParseLiteral["null"]
    ],
    "null"
]
```

<!-- => "null" -->

## Properties and Relations

A single-branch choice is the branch itself (canonicalisation):

```wl
ParseChoice[ParseLiteral["foo"]]
```

The failure diagnostic accumulates across branches:

```wl
Parse[ParseLiteral["foo"] | ParseLiteral["bar"], "xyz"]
```

## Possible Issues

PEG ordering matters. The classic pitfall is putting a shorter literal before a longer one with the same prefix:

```wl
(* WRONG: "fo" matches first, leaves "o" unmatched *)
Parse[ParseLiteral["fo"] | ParseLiteral["foo"], "foo"]
```

The fix is to order longest-first:

```wl
Parse[ParseLiteral["foo"] | ParseLiteral["fo"], "foo"]
```

<!-- => "foo" -->

## Neat Examples

A keyword parser:

```wl
keyword = ParseChoice @@ (ParseLiteral /@ {"if", "else", "while", "return"})
```

```wl
Parse[keyword, "while"]
```

<!-- => "while" -->

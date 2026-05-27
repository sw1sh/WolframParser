---
Template: Symbol
Name: ParseOptional
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseOptional
Keywords: [parser, optional, zero or one, ?]
SeeAlso: [ParseMany, ParseSome, ParserCombinator, Optional, Missing]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseOptional]()[$p$]</code> returns the [ParserCombinator]() that matches *zero or one* copy of $p$. Returns $p$'s result on a match, or `Missing["NoMatch"]` if absent.

## Details & Options

- The parser always succeeds: present + matched, or absent (consumes nothing).
- Lowers from the [Optional]() wrapper - `Optional[$p$]` where $p$ is a `ParserCombinator` produces a `ParseOptional[$p$]`.
- Result type: $p$'s result type, or [Missing]()`["NoMatch"]`.

## Basic Examples

A present optional:

```wl
Parse[ParseOptional[ParseLiteral["foo"]], "foo"]
```

<!-- => "foo" -->

An absent optional - succeeds, returns Missing:

```wl
Parse[ParseOptional[ParseLiteral["foo"]], ""]
```

<!-- => Missing["NoMatch"] -->

## Scope

Optional in the middle of a sequence:

```wl
Parse[
    ParseLiteral["a"] ** ParseOptional[ParseLiteral["b"]] ** ParseLiteral["c"],
    "abc"
]
```

<!-- => {"a", "b", "c"} -->

The absent case still succeeds:

```wl
Parse[
    ParseLiteral["a"] ** ParseOptional[ParseLiteral["b"]] ** ParseLiteral["c"],
    "ac"
]
```

<!-- => {"a", Missing["NoMatch"], "c"} -->

## Properties and Relations

`ParseOptional[$p$]` is `ParseChoice[$p$, ParseSucceed[Missing["NoMatch"]]]`:

```wl
{
    Parse[ParseOptional[ParseLiteral["x"]], "x"],
    Parse[ParseChoice[ParseLiteral["x"], ParseSucceed[Missing["NoMatch"]]], "x"]
}
```

<!-- => {"x", "x"} -->

The `Optional[]` wrapper has a UpValue that lowers a `ParserCombinator` argument:

```wl
Optional[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Optional, ParserCombinator[Literal, "foo", <||>], <||>] -->

## Possible Issues

`Missing["NoMatch"]` is the *typed* absent marker - tests for it with [MissingQ](), not for `Null`:

```wl
res = Parse[ParseOptional[ParseLiteral["x"]], ""];
MissingQ[res]
```

<!-- => True -->

## Neat Examples

An optional sign in a numeric literal:

```wl
Parse[
    ParseAction[
        ParseOptional[ParseLiteral["-"]] ** ParseCharacter[DigitCharacter]..,
        Function[{sign, digits},
            If[MissingQ[sign], 1, -1] * FromDigits @ StringJoin[digits]]
    ],
    "-42"
]
```

<!-- => -42 -->

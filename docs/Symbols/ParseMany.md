---
Template: Symbol
Name: ParseMany
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseMany
Keywords: [parser, repetition, zero or more, Kleene star, RepeatedNull]
SeeAlso: [ParseSome, ParseOptional, ParseSepBy, ParserCombinator, RepeatedNull]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseMany]()[$p$]</code> returns the [ParserCombinator]() that matches *zero or more* successive copies of $p$, returning the [List]() of results (empty if no match).

## Details & Options

- "Zero or more" - the parser always succeeds; the empty match returns `{}`.
- The operator overload `p...` lowers to `ParseMany[p]` via [RepeatedNull]().
- `ParseMany` is *greedy*: it consumes as much as it can. Use [ParseSepBy]() or an explicit terminator if you need to stop earlier.
- Result type: [List]() of $p$'s result type.

## Basic Examples

Zero or more digits, greedy:

```wl
Parse[ParseMany[ParseCharacter[DigitCharacter]], "123"]
```

<!-- => {"1", "2", "3"} -->

The same via the `...` operator:

```wl
Parse[ParseCharacter[DigitCharacter]..., "123"]
```

<!-- => {"1", "2", "3"} -->

The empty input matches (zero copies):

```wl
Parse[ParseMany[ParseCharacter[DigitCharacter]], ""]
```

<!-- => {} -->

## Scope

`ParseMany` over a multi-character literal:

```wl
Parse[ParseMany[ParseLiteral["ab"]], "ababab"]
```

<!-- => {"ab", "ab", "ab"} -->

A partial match stops the repetition and leaves the leftover for the surrounding parser:

```wl
ParsePartial[ParseMany[ParseCharacter[DigitCharacter]], "12x"]
```

<!-- => {{"1", "2"}, "x"} -->

## Properties and Relations

`ParseMany[$p$]` is `ParseSome[$p$] | ParseSucceed[{}]`. The empty-match success is the only difference from [ParseSome]():

```wl
{Parse[ParseMany[ParseLiteral["x"]], ""], Parse[ParseSome[ParseLiteral["x"]], ""]}
```

<!-- => {{}, ParseError[<|"Position" -> 1, "Expected" -> "x", "Found" -> "<end of input>"|>]} -->

Combined with [StringJoin]() / [ParseAction]() to flatten a string lex:

```wl
Parse[ParseAction[ParseCharacter[LetterCharacter]..., StringJoin], "hello"]
```

<!-- => "hello" -->

## Possible Issues

A `ParseMany` over a parser that succeeds *without consuming* loops forever. The compiler refuses such grammars at lowering time:

```wl
ParserCompile[ParseMany[ParseSucceed["nothing"]]]
```

<!-- => ParserCompile::infloop message + $Failed -->

## Neat Examples

Comma-separated digits (via the dedicated `ParseSepBy` helper):

```wl
Parse[ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], "1,2,3,4"]
```

<!-- => {"1", "2", "3", "4"} -->

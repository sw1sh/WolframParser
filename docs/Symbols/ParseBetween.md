---
Template: Symbol
Name: ParseBetween
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseBetween
Keywords: [parser, bracketing, delimited, surround]
SeeAlso: [ParseSequence, ParseSepBy, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseBetween]()[$open$, $p$, $close$]</code> returns the [ParserCombinator]() that matches $open$, then $p$, then $close$, returning just $p$'s result (the delimiters are consumed and discarded).

## Details & Options

- Equivalent to <code>[ParseAction]()[[ParseSequence]()[$open$, $p$, $close$], #2 &]</code> - i.e. it strips the delimiters from the result.
- Both $open$ and $close$ may be any combinators, not just literals - e.g. `ParseBetween[ParseLiteral["("], expr, ParseLiteral[")"]]` matches parenthesised expressions.
- Result type: $p$'s result type.

## Basic Examples

Parenthesised content:

```wl
Parse[
    ParseBetween[ParseLiteral["("], ParseCharacter[LetterCharacter], ParseLiteral[")"]],
    "(x)"
]
```

<!-- => "x" -->

A brace-wrapped LaTeX-style group:

```wl
Parse[
    ParseBetween[ParseLiteral["{"], ParseCharacter[LetterCharacter].., ParseLiteral["}"]],
    "{abc}"
]
```

<!-- => {"a", "b", "c"} -->

## Scope

Multi-character delimiters work as expected:

```wl
Parse[
    ParseBetween[ParseLiteral["<!--"], ParseCharacter[LetterCharacter].., ParseLiteral["-->"]],
    "<!--note-->"
]
```

<!-- => {"n", "o", "t", "e"} -->

The delimiters may be the same:

```wl
Parse[
    ParseBetween[ParseLiteral["\""], ParseCharacter[LetterCharacter].., ParseLiteral["\""]],
    "\"hello\""
]
```

<!-- => {"h", "e", "l", "l", "o"} -->

## Properties and Relations

`ParseBetween` makes recursive nested-bracket grammars natural - the inner argument can be the parser itself, via the [ParseRecursive]() tie that defers the lookup until parse time:

```wl
group = ParseBetween[
    ParseLiteral["("],
    ParseMany[ParseCharacter[LetterCharacter] | ParseRecursive[group]],
    ParseLiteral[")"]
];
Parse[group, "((a)(b))"]
(* {{"a"}, {"b"}} *)
```

The same technique drives the recursive cross-references inside [LaTeXMathParse]()'s grammar (factor refers to atom which refers to bracedArg which refers back to atom, ...).

The `ParseAction[Sequence, #2 &]` derivation matches the convenience helper:

```wl
{
    Parse[ParseBetween[ParseLiteral["["], ParseLiteral["x"], ParseLiteral["]"]], "[x]"],
    Parse[ParseAction[ParseSequence[ParseLiteral["["], ParseLiteral["x"], ParseLiteral["]"]], #2 &], "[x]"]
}
```

<!-- => {"x", "x"} -->

## Possible Issues

If $close$ never matches, the failure is reported at the $close$ position, not at the $open$:

```wl
Parse[
    ParseBetween[ParseLiteral["("], ParseCharacter[LetterCharacter], ParseLiteral[")"]],
    "(x"
]
```

<!-- => ParseError[<|"Position" -> 3, "Expected" -> ")", "Found" -> "<end of input>"|>] -->

## Neat Examples

A bracketed comma-separated list:

```wl
Parse[
    ParseBetween[
        ParseLiteral["["],
        ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]],
        ParseLiteral["]"]
    ],
    "[1,2,3]"
]
```

<!-- => {"1", "2", "3"} -->

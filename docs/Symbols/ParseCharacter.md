---
Template: Symbol
Name: ParseCharacter
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseCharacter
Keywords: [parser, character, class, terminal, LetterCharacter, DigitCharacter]
SeeAlso: [ParseLiteral, ParseToken, ParserCombinator, LetterCharacter, DigitCharacter, CharacterRange]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseCharacter]()[$pat$]</code> returns the [ParserCombinator]() that matches a single character against the character-class pattern $pat$, consuming and returning that character.

## Details & Options

- $pat$ may be a built-in character-class atom ([LetterCharacter](), [DigitCharacter](), [WhitespaceCharacter](), [WordCharacter](), [HexadecimalCharacter](), [PunctuationCharacter]()), a [CharacterRange]()`[$a$, $b$]`, an [Alternatives]() of these, or a literal one-character [String]().
- Result: the matched character as a [String]() of length one.
- For non-string inputs (token lists), `ParseCharacter[$pat$]` is equivalent to `ParseToken[$pat$]`.

## Basic Examples

A digit:

```wl
ParseCharacter[DigitCharacter]
```

<!-- => ParserCombinator[Character, DigitCharacter, <||>] -->

Apply it:

```wl
Parse[ParseCharacter[DigitCharacter], "5"]
```

<!-- => "5" -->

A letter:

```wl
Parse[ParseCharacter[LetterCharacter], "x"]
```

<!-- => "x" -->

## Scope

A character range - lowercase ASCII letters:

```wl
Parse[ParseCharacter[CharacterRange["a", "z"]], "m"]
```

<!-- => "m" -->

An alternation of classes - either a letter or a digit:

```wl
Parse[ParseCharacter[LetterCharacter | DigitCharacter], "7"]
```

<!-- => "7" -->

A literal one-character match:

```wl
Parse[ParseCharacter["+"], "+"]
```

<!-- => "+" -->

## Properties and Relations

`ParseCharacter[$pat$]` combined with `..` matches one or more characters of the class - the natural way to lex a number or an identifier head:

```wl
Parse[ParseCharacter[DigitCharacter].., "12345"]
```

<!-- => {"1", "2", "3", "4", "5"} -->

To get the digits as one string rather than a list, attach an action:

```wl
Parse[
    ParseAction[ParseCharacter[DigitCharacter].., StringJoin],
    "12345"
]
```

<!-- => "12345" -->

## Possible Issues

The wrong character class produces a `ParseError`:

```wl
Parse[ParseCharacter[DigitCharacter], "x"]
```

<!-- => ParseError[<|"Position" -> 1, "Expected" -> "<digit>", "Found" -> "x", "Rule" -> Character[DigitCharacter]|>] -->

`ParseCharacter` consumes *exactly one* character. To match a multi-character literal, use [ParseLiteral]() instead.

## Neat Examples

An identifier - letter followed by any number of letters or digits:

```wl
Parse[
    ParseAction[
        ParseCharacter[LetterCharacter] **
            (ParseCharacter[LetterCharacter] | ParseCharacter[DigitCharacter])...,
        StringJoin @ Flatten[{##}] &
    ],
    "foo123"
]
```

<!-- => "foo123" -->

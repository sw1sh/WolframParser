---
Template: Symbol
Name: ParseLiteral
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseLiteral
Keywords: [parser, literal, terminal, string match]
SeeAlso: [ParseCharacter, ParseToken, ParserCombinator, Parse]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseLiteral]()[$s$]</code> returns the [ParserCombinator]() that matches the exact string (or token) $s$ at the current input position, consuming it and returning it as the result.

## Details & Options

- For a [String]() input, `ParseLiteral["foo"]` matches the literal four characters and consumes them.
- For a token-list input, `ParseLiteral[$tok$]` matches a token equal to $tok$ (under [SameQ]()).
- Result: the matched literal itself (so `Parse[ParseLiteral["foo"], "foo"]` is just `"foo"`).
- The combinator type is `Literal`.

## Basic Examples

The simplest possible parser - exactly the string "foo":

```wl
ParseLiteral["foo"]
```

<!-- => ParserCombinator[Literal, "foo", <||>] -->

Apply it:

```wl
Parse[ParseLiteral["foo"], "foo"]
```

<!-- => "foo" -->

A mismatched input fails:

```wl
Parse[ParseLiteral["foo"], "bar"]
```

<!-- => ParseError[<|"Position" -> 1, "Expected" -> "foo", "Found" -> "b", "Rule" -> Literal["foo"]|>] -->

## Scope

The empty literal succeeds on any input and consumes nothing:

```wl
Parse[ParseLiteral[""], "anything"]
```

<!-- => ParseError[<|"Position" -> 1, "Expected" -> "<end of input>", "Found" -> "a"|>] (Parse requires whole-input consumption; ParsePartial would return {"", "anything"}) -->

A multi-character literal:

```wl
Parse[ParseLiteral["the weather"], "the weather"]
```

<!-- => "the weather" -->

## Properties and Relations

`ParseLiteral` is the building block for any parser that matches fixed text. Combined with `**` to sequence with other combinators:

```wl
Parse[ParseLiteral["hello "] ** ParseLiteral["world"], "hello world"]
```

<!-- => {"hello ", "world"} -->

## Possible Issues

`ParseLiteral` does *not* automatically skip whitespace. For grammars where whitespace is insignificant, wrap with a `ParseToken[...]` form that strips spaces, or run a tokeniser pass first.

```wl
Parse[ParseLiteral["foo"] ** ParseLiteral["bar"], "foo bar"]
```

<!-- => ParseError[<|"Position" -> 4, "Expected" -> "bar", "Found" -> " "|>] -->

## Neat Examples

A literal-only choice tries each in order (PEG-ordered):

```wl
Parse[
    ParseLiteral["red"] | ParseLiteral["green"] | ParseLiteral["blue"],
    "green"
]
```

<!-- => "green" -->

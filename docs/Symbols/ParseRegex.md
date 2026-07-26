---
Template: Symbol
Name: ParseRegex
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseRegex
Keywords: [parser, regex, regular expression, PCRE, token, lexer, match, anchored, greedy]
SeeAlso: [ParseCharacter, ParseLiteral, ParseAction, RegularExpression, StringCases]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseRegex]()[*regex*]</code> returns the [ParserCombinator]() that matches *regex* against the input at the current position and returns the matched substring.

*regex* is a string in PCRE syntax — the same form [RegularExpression]() takes.

## Details & Options

- The match is *anchored* to the current position (as if *regex* began with [StartOfString]()); [ParseRegex]() does not search forward for a match later in the input.
- Matching is *greedy*: the longest substring *regex* allows from the current position is taken, and the position advances past it.
- The result is the matched substring, kept as a [String](); wrap it in [ParseAction]() to convert it — for example [FromDigits]() for an integer.
- On no match the parse fails, with the pattern reported as the expected token in the form `regex /…/` and `"Found"` the character at the current position.
- A pattern that can match the empty string (such as `[0-9]*`) always succeeds, consuming as few as zero characters.
- A [RegularExpression]() pattern inside a [GrammarRules]() declaration lowers to [ParseRegex]().

## Basic Examples

The constructor holds the pattern in a `"Regex"` combinator:

```wl
ParseRegex["[0-9]+"]
```

<!-- => ParserCombinator[Regex, "[0-9]+", <||>] -->

<!-- #| annotation: 26.07.26: Design review - ParseRegex is the lexer-level escape hatch: rather than force every terminal to be spelled as a tree of ParseCharacter combinators, it hands a whole token class to the engine's regex matcher (StringCases with a StartOfString anchor, so it matches at the current position instead of searching). Matches PCRE, the same dialect RegularExpression takes, and a RegularExpression pattern inside a GrammarRules declaration lowers to exactly this primitive - so hand-built and declarative grammars share one regex path. -->

A lowercase run, matched greedily:

```wl
Parse[ParseRegex["[a-z]+"], "hello"]
```

<!-- => "hello" -->

A run of digits (`\d` is PCRE for a digit):

```wl
Parse[ParseRegex["\\d+"], "42"]
```

<!-- => "42" -->

## Scope

Alternation inside the pattern:

```wl
Parse[ParseRegex["cat|dog"], "dog"]
```

<!-- => "dog" -->

The matched string is raw text; [ParseAction]() converts it — this is the canonical integer terminal used across the grammar examples:

```wl
Parse[ParseAction[ParseRegex["[0-9]+"], FromDigits], "42"]
```

<!-- => 42 -->

---

Under [ParsePartial]() the regex consumes only what it matches and hands back the rest:

```wl
ParsePartial[ParseRegex["[0-9]+"], "42abc"]
```

<!-- => {"42", "abc"} -->

## Properties and Relations

A [RegularExpression]() pattern in a [GrammarRules]() rule lowers to [ParseRegex](), so the two spellings parse identically:

```wl
Parse[GrammarRules[{n : RegularExpression["\\d+"] :> FromDigits[n]}], "42"]
```

<!-- => 42 -->

Where [ParseCharacter]() matches exactly one character against a class, [ParseRegex]() matches a whole run in one step; `[0-9]+` is the multi-character analogue of <code>[ParseCharacter]()[[DigitCharacter]()]..</code>.

## Possible Issues

The match is anchored, not a search: a pattern that would match later in the input still fails if it does not match at the current position:

```wl
Parse[ParseRegex["[0-9]+"], "abc123"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "regex /[0-9]+/", "Found" -> "a"|>] -->

A non-match reports the pattern as the expected token:

```wl
Parse[ParseRegex["\\d+"], "abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "regex /\d+/", "Found" -> "a"|>] -->

The regex consumes only what it matches, so at top level [Parse]() still requires the rest of the input to be consumed — here `"42"` matches but `"abc"` is left over:

```wl
Parse[ParseRegex["[0-9]+"], "42abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 3, "Expected" -> "<end of input>", "Found" -> "a"|>] -->

Use [ParsePartial]() or continue the grammar to consume the remainder.

A pattern that can match empty never fails — `[0-9]*` matches zero digits and succeeds, consuming nothing:

```wl
ParsePartial[ParseRegex["[0-9]*"], "abc"]
```

<!-- => {"", "abc"} -->

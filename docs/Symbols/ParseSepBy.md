---
Template: Symbol
Name: ParseSepBy
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseSepBy
Keywords: [parser, separator, separated by, comma-separated list, delimited, zero or more]
SeeAlso: [ParseSepBy1, ParseMany, ParseSome, ParseChainLeft, ParseBetween, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseSepBy]()[*p*, *sep*]</code> returns the [ParserCombinator]() that matches *zero or more* occurrences of *p* separated by *sep* — a comma-separated list and its kin — returning the [List]() of *p*'s results and discarding the separators.

## Details & Options

- "Zero or more" — the parser always succeeds; input on which no *p* matches returns `{}`, exactly like [ParseMany](). Require at least one item with [ParseSepBy1]().
- The separators are consumed but not kept: the result is the flat [List]() of *p* results only.
- Conceptually *p* followed by zero or more `sep ~~ p` pairs, keeping only the *p* results.
- A *trailing* separator is not consumed — parsing stops after the last *p*, leaving a dangling *sep* in the input. Append [ParseOptional]()[*sep*] (or a terminator) to accept one.
- Each iteration must advance the position: after a *sep*, the following *p* must consume input, or the repetition stops.
- Result type: [List]() of *p*'s result type, possibly empty.

## Basic Examples

Comma-separated digits — the separators drop out of the result:

```wl
digit = ParseCharacter[DigitCharacter];
comma = ParseLiteral[","];
Parse[ParseSepBy[digit, comma], "1,2,3,4"]
```

<!-- => {"1", "2", "3", "4"} -->

---

Input with no item succeeds with the empty list:

```wl
Parse[ParseSepBy[digit, comma], ""]
```

<!-- => {} -->

---

A single item, with no separator at all, is a one-element list:

```wl
Parse[ParseSepBy[digit, comma], "5"]
```

<!-- => {"5"} -->

## Scope

The item and the separator can each be any parser — here whole words split on `,`:

```wl
word = ParseAction[ParseSome[ParseCharacter[LetterCharacter]], StringJoin];
Parse[ParseSepBy[word, comma], "foo,bar,baz"]
```

<!-- => {"foo", "bar", "baz"} -->

---

Splitting a path on a `/` separator:

```wl
Parse[ParseSepBy[word, ParseLiteral["/"]], "usr/local/bin"]
```

<!-- => {"usr", "local", "bin"} -->

---

The constructor returns a [ParserCombinator](), rendered as a summary box:

```wl
ParseSepBy[digit, comma]
```

<!-- => ParserCombinator[SepBy] -->

## Properties and Relations

`ParseSepBy` and [ParseSepBy1]() differ only at the empty match: where `ParseSepBy` yields `{}`, [ParseSepBy1]() fails:

```wl
Parse[ParseSepBy1[digit, comma], ""]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "at least one occurrence", "Found" -> "<end of input>"|>] -->

---

Like [ParseMany](), the flat list is the whole point. When the "separator" is really a binary *operator* whose operands you want to fold into a value or tree, reach for [ParseChainLeft]() / [ParseChainRight]() (one precedence level) or [ParseOperatorTable]() (many) instead — the same items and separators, folded rather than listed:

```wl
Parse[ParseChainLeft[ParseAction[digit, FromDigits], ParseAction[comma, (f &)]], "1,2,3"]
```

<!-- => f[f[1, 2], 3] -->

## Possible Issues

A trailing separator is not consumed, so [Parse]() — which demands all input be used — reports the dangling *sep* as leftover:

```wl
Parse[ParseSepBy[digit, comma], "1,2,"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> "<end of input>", "Found" -> ","|>] -->

---

[ParsePartial]() reveals what was matched and what the trailing separator left behind:

```wl
ParsePartial[ParseSepBy[digit, comma], "1,2,"]
```

<!-- => {{"1", "2"}, ","} -->

---

To permit an optional trailing separator, follow the list with [ParseOptional]()[*sep*]; its slot then holds the consumed separator (or `Missing["NoMatch"]` when absent):

```wl
Parse[ParseSepBy[digit, comma] ~~ ParseOptional[comma], "1,2,"]
```

<!-- => {{"1", "2"}, ","} -->

## Neat Examples

A bracketed integer-list parser — [ParseBetween]() supplies the delimiters, `ParseSepBy` the elements:

```wl
numList = ParseBetween[
   ParseLiteral["["],
   ParseSepBy[ParseAction[ParseRegex["[0-9]+"], FromDigits], comma],
   ParseLiteral["]"]];
Parse[numList, "[1,2,3]"]
```

<!-- => {1, 2, 3} -->

---

The same parser accepts the empty list `[]`, because `ParseSepBy` allows zero items:

```wl
Parse[numList, "[]"]
```

<!-- => {} -->

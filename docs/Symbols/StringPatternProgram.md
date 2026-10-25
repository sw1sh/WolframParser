---
Template: Symbol
Name: StringPatternProgram
Context: Wolfram`Parser`StringPatterns`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`StringPatterns`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/StringPatternProgram
Keywords: [string pattern, StringExpression, StringCases, StringMatchQ, regular expression, backtracking, character class]
SeeAlso: [StringPatternMatches, StringExpression, StringCases, StringMatchQ, StringReplace, RegularExpression]
RelatedGuides: [WolframParser]
---

## Usage

<code>[StringPatternProgram]()[*patt*]</code> gives the program of the string pattern *patt*, an object from which [StringPatternMatches]() finds the matches of *patt* as Wolfram 15's String functions find them.

## Details & Options

- A program matches its pattern as Wolfram 15 does:
  - the alternatives in the order given, the first that matches taken;
  - a repeat the longest first, and every repeat in [Shortest]() the shortest first, but not those of [NumberString]();
  - a test of [PatternTest]() on each character that its pattern matched;
  - <code>[Except]()[*c*, *p*]</code> as *p* after a character that *c*, a pattern of one character, does not match;
  - a name that occurs again, after it on the way a match goes, as the text it matched first;
  - the names of a repeated part as the text they matched the first time round.
- The classes of characters, such as [LetterCharacter](), [DigitCharacter]() and [WhitespaceCharacter](), are Wolfram 15's at every code point, as the paclet records them.
- The properties of a program are:

| Property | Value |
|---|---|
| `"Pattern"` | the pattern *patt* |
| `"Program"` | the program, or [None]() if *patt* has a part that no program has |
| `"RegexLike"` | whether a regex's leftmost longest match finds the matches the program finds |
| `"RegexFinds"` | whether a regex finds a match wherever the program has one |
| `"Class"` | `{test, min, max}` for a pattern of one character class or a repeat of one, else [None]() |
| `"Run"` | `{test, min}` for a repeat of one character class from *min* times on, as many as there are, else [None]() |
| `"ClassCodes"` | for a pattern of one character class, its codes below 65536 as a packed table of 1 and 0 by code + 1, else [None]() |
| `"Properties"` | the properties |

- A pattern has no program if it has a [RegularExpression](), a part that is no string pattern, a repeat of an anchor such as [StartOfString](), or an [Except]() of a pattern of more than one character.
- A kernel builds its String functions of patterns on [StringPatternProgram]() and [StringPatternMatches]().

## Basic Examples

The program of a letter followed by digits:

```wl
prog = StringPatternProgram["a" ~~ DigitCharacter ..]
```

A regex's leftmost longest match finds what the program finds:

```wl
prog["RegexLike"]
```

<!-- => True -->

## Scope

The properties of a program:

```wl
prog["Properties"]
```

<!-- => {"Pattern", "Program", "RegexLike", "RegexFinds", "Class", "Run", "ClassCodes"} -->

A regex takes the longest of its alternatives, and a pattern the first, so a regex does not match as these alternatives do:

```wl
StringPatternProgram["a" | "ab"]["RegexLike"]
```

<!-- => False -->

It still finds a match wherever they have one:

```wl
StringPatternProgram["a" | "ab"]["RegexFinds"]
```

<!-- => True -->

A repeat of one class, from once on, runs as far as its characters go:

```wl
Last[StringPatternProgram[WhitespaceCharacter ..]["Run"]]
```

<!-- => 1 -->

The codes below 65536 of a class of one character, here the 44 that Wolfram 15 takes as whitespace:

```wl
Total[StringPatternProgram[WhitespaceCharacter]["ClassCodes"]]
```

<!-- => 44 -->

A pattern with a regular expression has no program:

```wl
StringPatternProgram[RegularExpression["a+"]]["Program"]
```

<!-- => None -->

## Properties and Relations

[StringPatternMatches]() finds the matches of a program:

```wl
matches = StringPatternMatches["a1b22a3", {prog}, "Each"]
```

<!-- => {{0, 2, 1, {}}, {5, 7, 1, {}}} -->

Their texts are those that [StringCases]() gives:

```wl
StringTake["a1b22a3", {#[[1]] + 1, #[[2]]}] & /@ matches
```

<!-- => {"a1", "a3"} -->

```wl
StringCases["a1b22a3", "a" ~~ DigitCharacter ..]
```

<!-- => {"a1", "a3"} -->

The decimal digits of every script are digits:

```wl
StringTake["1\:0661\:0662\:0663 2", {#[[1]] + 1, #[[2]]}] & /@ StringPatternMatches["1\:0661\:0662\:0663 2", {StringPatternProgram[DigitCharacter ..]}, "Each"]
```

<!-- => {"1١٢٣", "2"} -->

## Possible Issues

In <code>[Except]()[*c*, *p*]</code>, Wolfram 15 matches the strings of *p* as the text of a regular expression, where a program matches them as text:

```wl
StringCases["aa+", Except["x", "a+"]]
```

<!-- => {"aa"} -->

```wl
StringTake["aa+", {#[[1]] + 1, #[[2]]}] & /@ StringPatternMatches["aa+", {StringPatternProgram[Except["x", "a+"]]}, "Each"]
```

<!-- => {"a+"} -->

---
Template: Symbol
Name: StringPatternMatches
Context: Wolfram`Parser`StringPatterns`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`StringPatterns`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/StringPatternMatches
Keywords: [string pattern, matches, StringCases, StringPosition, StringReplace, StringSplit, Overlaps, backtracking]
SeeAlso: [StringPatternProgram, StringPatternRecords, StringCases, StringPosition, StringReplace, StringSplit, StringCount]
RelatedGuides: [WolframParser]
---

## Usage

<code>[StringPatternMatches]()[*s*, {*prog*<sub>1</sub>, *prog*<sub>2</sub>, ...}, *mode*]</code> gives the matches in the string *s* of the programs *prog*<sub>*i*</sub> that [StringPatternProgram]() gives, from the left, each <code>{*start*, *end*, *k*, *rules*}</code>.

## Details & Options

- In a match <code>{*start*, *end*, *k*, *rules*}</code>, the program *prog*<sub>*k*</sub> matched the characters of *s* after position *start* up to position *end*, and *rules* bind the names of its pattern to the text each matched.
- A name that took no part in a match is bound to `""`, or to `{}` if it occurs more than once in the pattern.
- The modes take the matches as Wolfram 15's String functions do:

| Mode | At each position | As |
|---|---|---|
| `"First"` | the first program that matches there | [StringReplace](), [StringSplit]() |
| `"Each"` | the programs in turn, the next tried there after one that matches nothing | [StringCases](), [StringCount]() |
| `"Overlapping"` | every program that matches there | [StringPosition]() |
| `"All"` | every way each program matches there, in the order its parts try them, the same text as often as it matches | [StringCases]() and [StringPosition]() with [Overlaps]() `->` [All]() |

- After a match that is not empty, `"First"` and `"Each"` go on at its end; otherwise the next match is looked for a character later.
- [StringPatternRecords]() gives the same matches as packed records, with the left sides of the names.
- A group of a [RegularExpression]() is bound by its number, *n* `->` *text*, as a rule's `"$n"` takes it.
- [StringPatternMatches]() gives [None]() if one of the programs has none, as [StringPatternProgram]() gives for a regular expression with recursion.
- The option [Method]() gives the matcher:

| Value | Matcher |
|---|---|
| [Automatic](), `"VM"` | a typed backtracking machine over the bytecode of the programs, compiled once |
| `"Interpreter"` | the interpreter of the programs, the reference the machine is held to |

## Basic Examples

The runs of digits in a string:

```wl
StringPatternMatches["a1b22", {StringPatternProgram[DigitCharacter ..]}, "Each"]
```

<!-- => {{1, 2, 1, {}}, {3, 5, 1, {}}} -->

## Scope

The names of a pattern, bound to what they matched:

```wl
StringPatternMatches["x=1, y=2", {StringPatternProgram[k : LetterCharacter ~~ "=" ~~ v : DigitCharacter]}, "Each"]
```

<!-- => {{0, 3, 1, {HoldPattern[k] -> "x", HoldPattern[v] -> "1"}}, {5, 8, 1, {HoldPattern[k] -> "y", HoldPattern[v] -> "2"}}} -->

A name that took no part in a match is bound to the empty string:

```wl
StringPatternMatches["b", {StringPatternProgram[(x : "a") | "b"]}, "Each"]
```

<!-- => {{0, 1, 1, {HoldPattern[x] -> ""}}} -->

Two programs, the first of which matches nothing at every position:

```wl
progs = StringPatternProgram /@ {"x"..., "a"}
```

In the mode `"Each"`, the second is tried where the first matched nothing:

```wl
StringPatternMatches["ab", progs, "Each"]
```

<!-- => {{0, 0, 1, {}}, {0, 1, 2, {}}, {1, 1, 1, {}}, {2, 2, 1, {}}} -->

In the mode `"First"`, the first that matches is taken:

```wl
StringPatternMatches["ab", progs, "First"]
```

<!-- => {{0, 0, 1, {}}, {1, 1, 1, {}}, {2, 2, 1, {}}} -->

In the mode `"Overlapping"`, every program that matches at a position gives a match there:

```wl
StringPatternMatches["aaa", StringPatternProgram /@ {"a", "aa"}, "Overlapping"]
```

<!-- => {{0, 1, 1, {}}, {0, 2, 2, {}}, {1, 2, 1, {}}, {1, 3, 2, {}}, {2, 3, 1, {}}} -->

In the mode `"All"`, every way a program matches at a position gives a match there, a repeat the longest first:

```wl
StringPatternMatches["abc", {StringPatternProgram[__]}, "All"]
```

<!-- => {{0, 3, 1, {}}, {0, 2, 1, {}}, {0, 1, 1, {}}, {1, 3, 1, {}}, {1, 2, 1, {}}, {2, 3, 1, {}}} -->

## Options

### Method

The interpreter of the programs gives the same matches as the typed machine:

```wl
StringPatternMatches["a1b22", {StringPatternProgram[DigitCharacter ..]}, "Each", Method -> "Interpreter"]
```

<!-- => {{1, 2, 1, {}}, {3, 5, 1, {}}} -->

## Properties and Relations

The mode `"Each"` takes the matches as [StringCases]() does:

```wl
StringCases["ab", {"x"..., "a"}]
```

<!-- => {"", "a", "", ""} -->

The mode `"First"` takes them as [StringReplace]() does, which leaves the `"a"` as it is:

```wl
StringReplace["ab", {"x"... -> "1", "a" -> "2"}]
```

<!-- => "1a1b1" -->

The mode `"Overlapping"` takes them as [StringPosition]() does:

```wl
StringPosition["aaa", {"a", "aa"}]
```

<!-- => {{1, 1}, {1, 2}, {2, 2}, {2, 3}, {3, 3}} -->

The mode `"All"` takes them as [StringCases]() does with [Overlaps]() `->` [All]():

```wl
StringCases["abc", __, Overlaps -> All]
```

<!-- => {"abc", "ab", "a", "bc", "b", "c"} -->

## Possible Issues

A regular expression with recursion has no program, so there are no matches to give:

```wl
StringPatternMatches["(a)", {StringPatternProgram[RegularExpression["\\((?R)?\\)"]]}, "Each"]
```

<!-- => None -->

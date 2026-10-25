---
Template: Symbol
Name: StringPatternRecords
Context: Wolfram`Parser`StringPatterns`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`StringPatterns`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/StringPatternRecords
Keywords: [string pattern, matches, records, packed array, names, StringCases, Overlaps]
SeeAlso: [StringPatternMatches, StringPatternProgram, StringCases, StringPosition, StringTake]
RelatedGuides: [WolframParser]
---

## Usage

<code>[StringPatternRecords]()[*s*, {*prog*<sub>1</sub>, *prog*<sub>2</sub>, ...}, *mode*]</code> gives the matches of [StringPatternMatches]() as an association of their records and the left sides of their names.

## Details & Options

- [StringPatternRecords]() takes the programs, the modes and the option [Method]() of [StringPatternMatches]().
- `"Records"` is a packed array with a row <code>{*start*, *end*, *k*, *s*<sub>1</sub>, *e*<sub>1</sub>, *s*<sub>2</sub>, *e*<sub>2</sub>, ...}</code> for each match: the program *prog*<sub>*k*</sub> matched the characters after position *start* up to position *end*, and its *i*th name the characters after *s*<sub>*i*</sub> up to *e*<sub>*i*</sub>.
- A name that took no part in a match has the span <code>{-1, -1}</code>, and one that took no part the first time round a repeat <code>{-2, -1}</code>. Every row is as long as the most names of a program make it, the rest <code>{-1, -1}</code>.
- `"Sides"` gives, for each program, a pair <code>{*lhs*, *twice*}</code> for each of its names: *lhs* the left side of the name's rule, and *twice* whether the name occurs more than once in the pattern, so that it is bound to `{}` where it matched nothing.
- The groups of a [RegularExpression]() come after the names, each with its number for *lhs*.
- The records come from the matcher with no rule made for each match, for a host that binds the names itself.
- [StringPatternRecords]() gives [None]() if one of the programs has none.

## Basic Examples

The records of the runs of digits, the name `x` bound to each:

```wl
StringPatternRecords["a1b22", {StringPatternProgram[x : DigitCharacter ..]}, "Each"]
```

<!-- => <|"Records" -> {{1, 2, 1, 1, 2}, {3, 5, 1, 3, 5}}, "Sides" -> {{{HoldPattern[x], False}}}|> -->

## Scope

Two programs, the name of the second taking no part in its match of `"b"`:

```wl
StringPatternRecords["ab1", StringPatternProgram /@ {x : DigitCharacter, (y : "a") | "b"}, "Each"]
```

<!-- => <|"Records" -> {{0, 1, 2, 0, 1}, {1, 2, 2, -1, -1}, {2, 3, 1, 2, 3}}, "Sides" -> {{{HoldPattern[x], False}}, {{HoldPattern[y], False}}}|> -->

The groups of a regular expression, after its names:

```wl
StringPatternRecords["ab12", {StringPatternProgram[RegularExpression["([a-z]+)(\\d+)?"]]}, "Each"]
```

<!-- => <|"Records" -> {{0, 4, 1, 0, 2, 2, 4}}, "Sides" -> {{{1, False}, {2, False}}}|> -->

The records of every way a pattern matches at each start:

```wl
Dimensions[StringPatternRecords[StringRepeat["ab", 500], {StringPatternProgram["a" ~~ __ ~~ "b"]}, "All"]["Records"]]
```

<!-- => {124750, 3} -->

## Options

### Method

The interpreter of the programs gives the same records as the typed machine:

```wl
StringPatternRecords["a1b22", {StringPatternProgram[x : DigitCharacter ..]}, "Each", Method -> "Interpreter"]
```

<!-- => <|"Records" -> {{1, 2, 1, 1, 2}, {3, 5, 1, 3, 5}}, "Sides" -> {{{HoldPattern[x], False}}}|> -->

## Properties and Relations

The texts of the matches come from the first two columns of the records:

```wl
With[{r = StringPatternRecords["a1b22", {StringPatternProgram[DigitCharacter ..]}, "Each"]["Records"]},
    StringTake["a1b22", Transpose[{r[[All, 1]] + 1, r[[All, 2]]}]]]
```

<!-- => {"1", "22"} -->

[StringPatternMatches]() gives the same matches with a rule for each name:

```wl
StringPatternMatches["a1b22", {StringPatternProgram[x : DigitCharacter ..]}, "Each"]
```

<!-- => {{1, 2, 1, {HoldPattern[x] -> "1"}}, {3, 5, 1, {HoldPattern[x] -> "22"}}} -->

As many records as [StringCases]() gives matches with [Overlaps]() `->` [All]():

```wl
Length[StringCases[StringRepeat["ab", 500], "a" ~~ __ ~~ "b", Overlaps -> All]]
```

<!-- => 124750 -->

## Possible Issues

A regular expression with recursion has no program, so there are no records to give:

```wl
StringPatternRecords["(a)", {StringPatternProgram[RegularExpression["\\((?R)?\\)"]]}, "Each"]
```

<!-- => None -->

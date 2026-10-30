---
Template: Symbol
Name: StringPatternMatcher
Context: Wolfram`Parser`StringPatterns`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`StringPatterns`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/StringPatternMatcher
Keywords: [string pattern, matcher, prepared, records, bytecode, cache, StringCases]
SeeAlso: [StringPatternRecords, StringPatternProgram, StringPatternMatches]
RelatedGuides: [WolframParser]
---

## Usage

<code>[StringPatternMatcher]()[{*prog*<sub>1</sub>, *prog*<sub>2</sub>, ...}, *mode*]</code> gives the matcher of the programs *prog*<sub>*i*</sub> in the mode *mode*, made once for them, which <code>[StringPatternRecords]()[*s*, *matcher*]</code> runs on a string *s*.

## Details & Options

- The modes are those of [StringPatternMatches](): `"First"`, `"Each"`, `"Overlapping"` and `"All"`.
- A matcher holds what the matches of every string take: the programs of the mode, the bytecode of the typed matcher, its parameters, and the classes of characters, where no test of a character needs the string. A call of [StringPatternRecords]() with it does only the work of its string.
- <code>*matcher*["Sides"]</code> gives the `"Sides"` of [StringPatternRecords](): for each program, the left side of each name's rule and whether the name occurs more than once. <code>*matcher*["Mode"]</code> gives the mode, and <code>*matcher*["Method"]</code> `"Typed"` or `"Interpreter"`.
- [StringPatternMatcher]() takes the option [Method]() of [StringPatternMatches]().
- [StringPatternMatcher]() gives [None]() if one of the programs has none for the mode.

## Basic Examples

The matcher of the runs of digits in the mode of [StringCases]():

```wl
digits = StringPatternMatcher[{StringPatternProgram[x : DigitCharacter ..]}, "Each"]
```

---

The records of its matches in a string:

```wl
StringPatternRecords["a1b22", digits]
```

<!-- => {{1, 2, 1, 1, 2}, {3, 5, 1, 3, 5}} -->

---

The same matcher in another string:

```wl
StringPatternRecords["333 4", digits]
```

<!-- => {{0, 3, 1, 0, 3}, {4, 5, 1, 4, 5}} -->

## Scope

The left side of each name's rule, and whether the name occurs more than once:

```wl
digits["Sides"]
```

<!-- => {{{HoldPattern[x], False}}} -->

---

The matcher of the interpreter:

```wl
StringPatternMatcher[{StringPatternProgram[x : DigitCharacter ..]}, "Each", Method -> "Interpreter"]["Method"]
```

<!-- => "Interpreter" -->

## Properties and Relations

The records of a matcher are those [StringPatternRecords]() gives of its programs:

```wl
StringPatternRecords["a1b22", digits] === StringPatternRecords["a1b22", {StringPatternProgram[x : DigitCharacter ..]}, "Each"]["Records"]
```

<!-- => True -->

## Possible Issues

A program with none for the mode has no matcher:

```wl
StringPatternMatcher[{StringPatternProgram[RegularExpression["(*FAIL)"]]}, "Each"]
```

<!-- => None -->

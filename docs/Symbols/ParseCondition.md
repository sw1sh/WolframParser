---
Template: Symbol
Name: ParseCondition
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseCondition
Keywords: [parser, condition, semantic predicate, guard, test, filter, PEG]
SeeAlso: [ParseAction, ParseLookahead, ParseScope, ParseScoped, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseCondition]()[*p*, *test*]</code> returns the [ParserCombinator]() that runs *p* and succeeds with its result where *test* applied to the result gives [True](), and fails where it does not.

## Details & Options

- `ParseCondition` is a semantic predicate: it tells apart inputs that the grammar alone cannot, as a name that one table knows from one it does not.
- Where *test* does not give [True](), `ParseCondition` fails at the position where *p* began, so a [ParseChoice]() goes on to its next alternative.
- Where *p* itself fails, `ParseCondition` gives *p*'s failure.
- Over [ParseScope](), it tests the scope instead of input.

## Basic Examples

A parser of digits that only takes an even number:

```wl
even = ParseCondition[ParseRegex["[0-9]+"], EvenQ[FromDigits[#]] &]
```

```wl
Parse[even, "42"]
```

<!-- => "42" -->

An odd one fails:

```wl
Parse[even, "43"]
```

## Scope

In a choice, a condition that fails lets the next alternative read the input:

```wl
Parse[ParseChoice[ParseAction[even, {"even", #} &], ParseAction[ParseRegex["[0-9]+"], {"odd", #} &]], "43"]
```

<!-- => {"odd", "43"} -->

## Properties and Relations

[ParseAction]() turns a result into another, and `ParseCondition` keeps or rejects it; together they read and check a token:

```wl
Parse[ParseAction[ParseCondition[ParseRegex["[0-9]+"], StringLength[#] <= 3 &], FromDigits], "123"]
```

<!-- => 123 -->

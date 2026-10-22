---
Template: Symbol
Name: ParseScoped
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseScoped
Keywords: [parser, scope, context, state, nesting, brackets, enclosing, PEG]
SeeAlso: [ParseScope, ParseCondition, ParseRecursive, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseScoped]()[*label*, *p*]</code> returns the [ParserCombinator]() that runs *p* with *label* added to the scope, and gives *p*'s result.

## Details & Options

- The scope is the list of the labels of the `ParseScoped` parsers around a parser, innermost last. It is `{}` where a parse begins.
- [ParseScope]() gives the scope, and [ParseCondition]() over it makes a parser that matches only in some scopes, as a closing bracket that closes none of the groups around it.
- The scope is dynamic: it holds while *p* runs, and a parser that fails or backtracks leaves it as it was.
- With packrat memoization (`"Memoize" -> True`), a rule's result at a position is cached for the scope it was read in.

## Basic Examples

A parser run with a label in its scope:

```wl
ParseScoped["list", ParseScope[]]
```

The scope it sees holds the label:

```wl
Parse[ParseScoped["list", ParseScope[]], ""]
```

<!-- => {"list"} -->

## Scope

Labels nest, the innermost last:

```wl
Parse[ParseScoped["list", ParseScoped["call", ParseScope[]]], ""]
```

<!-- => {"list", "call"} -->

Past the scoped parser the scope is as it was:

```wl
Parse[ParseScoped["list", ParseLiteral["x"]] ~~ ParseScope[], "x"]
```

<!-- => {"x", {}} -->

## Applications

A closing bracket that closes none of the groups around it is an error of its own, and one in the scope ends its group. A parser of the stray ones:

```wl
stray[c_] := ParseAction[ParseLiteral[c] ~~ ParseCondition[ParseScope[], FreeQ[#, c] &], "stray " <> c &];
```

Within a group that `)` closes, a `]` is stray:

```wl
Parse[ParseScoped[")", ParseMany[ParseChoice[stray["]"], ParseRegex["[a-z]+"]]]], "ab]cd"]
```

<!-- => {"ab", "stray ]", "cd"} -->

while a `)` ends the group's contents, and the group takes it:

```wl
Parse[ParseScoped[")", ParseMany[ParseChoice[stray[")"], ParseRegex["[a-z]+"]]]] ~~ ParseLiteral[")"], "ab)"]
```

<!-- => {{"ab"}, ")"} -->

## Properties and Relations

[ParseRecursive]() rules see the scope of the parser that reached them, so one grammar reads a construct differently inside and outside another.

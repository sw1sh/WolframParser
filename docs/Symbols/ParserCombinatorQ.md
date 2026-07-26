---
Template: Symbol
Name: ParserCombinatorQ
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParserCombinatorQ
Keywords: [parser, predicate, test, ParserCombinator, type check]
SeeAlso: [ParserCombinator, Parse, ParserCompile, ParseLiteral]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParserCombinatorQ]()[*expr*]</code> gives [True]() if *expr* is a [ParserCombinator]() and [False]() otherwise.

## Details & Options

- [ParserCombinatorQ]() tests the head only: any value built by a `Parse*` constructor answers [True](); anything else answers [False]().
- Like other `…Q` predicates it always returns [True]() or [False]() and never stays unevaluated, so it is safe as a pattern test or [If]() condition.
- A parser passed through [ParserCompile]() is still a [ParserCombinator](), so it answers [True]() — compilation adds a `"Code"` entry to the options but does not change the head.

## Basic Examples

A value built by a `Parse*` constructor is a [ParserCombinator]():

```wl
ParserCombinatorQ[ParseLiteral["foo"]]
```

<!-- => True -->

<!-- #| annotation: 26.07.26: Design review - ParserCombinatorQ is the standard WL …Q head-test over the single ParserCombinator wrapper every Parse* constructor returns. Two clauses only (matches _ParserCombinator, else False), so it is a total predicate usable as a pattern gate - the discipline WL's own DirectedGraphQ / AssociationQ follow. It reports the wrapper's presence, not that the object came through a Parse* constructor; the API contract is that user code builds combinators only through those constructors. -->

An ordinary expression is not:

```wl
ParserCombinatorQ[42]
```

<!-- => False -->

---

A plain string is not a parser either:

```wl
ParserCombinatorQ["foo"]
```

<!-- => False -->

## Properties and Relations

A parser stays a [ParserCombinator]() after [ParserCompile](), so the predicate holds across compilation:

```wl
ParserCombinatorQ[ParserCompile[ParseLiteral["foo"]]]
```

<!-- => True -->

---
Template: Symbol
Name: RecRef
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/RecRef
Keywords: [recursion, recursive grammar, parser, reference, ParseRecursive, parser zoo]
SeeAlso: [RecCell, SetRec, ParseRecursive, ParseChoice, ParseBetween]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[RecRef]()[*cell*]</code> is a [ParseRecursive]() reference to a recursion cell allocated by [RecCell]().

## Details & Options

- `RecRef` is how a production refers back to a recursion cell. It returns a [ParserCombinator]() of type `"Recursive"` whose target is the cell's symbol; the symbol is looked up *at parse time*, so the parser need not exist yet when the reference is built.
- It is therefore safe to build a `RecRef` *before* or *after* the matching [SetRec]() - a forward reference into a not-yet-defined production is exactly the point - and to use it in any number of places. Each occurrence re-enters the same production.
- One cell, many references: an item that can recur on either side of a separator just drops a `RecRef[cell]` at each spot.
- Make the recursion target a [ParseChoice]() of concrete alternatives rather than a production that begins with a nullable parser; re-entering at a nullable prefix can match empty and bail instead of recursing.

## Basic Examples

Build a reference before the production exists, then close the loop with [SetRec]() - a self-describing s-expression grammar where an expression is an atom or a parenthesised list of expressions:

```wl
expr = RecCell[];
ref = RecRef[expr];
SetRec[expr, ParseChoice[ParseRegex["[a-z]+"], ParseBetween[ParseLiteral["("], ParseSepBy[ref, ParseLiteral[" "]], ParseLiteral[")"]]]];
Parse[ref, "(a (b c) d)"]
```

<!-- => {"a", {"b", "c"}, "d"} -->

The same reference parses a bare atom - the recursion is simply not entered:

```wl
Parse[ref, "x"]
```

<!-- => "x" -->

## Scope

A `RecRef` is a [ParserCombinator]() of type `"Recursive"`:

```wl
ref[[1]]
```

<!-- => "Recursive" -->

The reference `ref` is the production itself, so it can be parsed directly - no separate top-level wrapper is needed:

```wl
Parse[ref, "(a b c)"]
```

<!-- => {"a", "b", "c"} -->

## Possible Issues

An unbalanced form is an honest [Failure](), reported at the position where the closing delimiter was expected:

```wl
Parse[ref, "(a b"]
```

<!-- => Failure["ParseError", <|"Position" -> 5, "Expected" -> {")"}, "Found" -> "<end of input>"|>] -->

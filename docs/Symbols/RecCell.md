---
Template: Symbol
Name: RecCell
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/RecCell
Keywords: [recursion, recursive grammar, parser, cell, ParseRecursive, parser zoo]
SeeAlso: [RecRef, SetRec, ParseRecursive, ParseChoice, ParseBetween]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[RecCell]()[]</code> allocates a recursion cell - a stable symbol for a self- or mutually-recursive grammar production.

## Details & Options

- A recursive grammar needs a production that refers back to itself before it is fully built. The cell is the named hole: reference it with [RecRef]() wherever the production recurs, and close the loop with <code>[SetRec]()[*cell*, *parser*]</code> once the parser is in hand.
- The cell wraps a fresh global [Unique]() symbol kept un-evaluated. A [ParseRecursive]() target must outlive the function that built the grammar; a [Module]()-local symbol can be garbage-collected once the builder returns - its only live reference is held inside [ParseRecursive]() - which silently breaks the recursion. The global cell never gets collected and resolves regardless of when its parser is set. This mirrors the [Unique]()-per-rule wiring the paclet's own EBNF front end uses.
- Allocate one cell per recursive production. Mutually-recursive productions each get their own cell and reference each other through [RecRef]().
- A raw cell is an internal wrapper around its symbol; it is meant to be wired into a grammar with [RecRef]() and [SetRec](), not displayed on its own.

## Basic Examples

Allocate a cell, reference it inside a nested-list production with [RecRef](), and close the loop with [SetRec]() - the cell lets an item be either a number or a whole sub-list:

```wl
cell = RecCell[];
list = ParseBetween[
    ParseLiteral["["],
    ParseSepBy[ParseChoice[ParseRegex["[0-9]+"], RecRef[cell]], ParseLiteral[","]],
    ParseLiteral["]"]
];
SetRec[cell, list];
Parse[list, "[1,[2,3],[]]"]
```

<!-- => {"1", {"2", "3"}, {}} -->

The same grammar handles a flat list - the recursion is simply not exercised:

```wl
Parse[list, "[1,2,3]"]
```

<!-- => {"1", "2", "3"} -->

## Scope

One cell can be referenced any number of times. Here the same `cell` recurs through the item choice, so lists nest to arbitrary depth on both sides of a comma:

```wl
Parse[list, "[[1],[2,[3]]]"]
```

<!-- => {{"1"}, {"2", {"3"}}} -->

## Properties and Relations

The bound parser is also reachable directly through its cell - <code>[RecRef]()[*cell*]</code> is a [ParseRecursive]() reference that [Parse]() follows to the same `list` grammar:

```wl
Parse[RecRef[cell], "[1,[2]]"]
```

<!-- => {"1", {"2"}} -->

## Possible Issues

An unbalanced input is an honest [Failure](), reporting how far it parsed and what it expected next:

```wl
Parse[list, "[1,[2]"]
```

<!-- => Failure["ParseError", <|"Position" -> 7, "Expected" -> "]", "Found" -> "<end of input>"|>] -->

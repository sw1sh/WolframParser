---
Template: Symbol
Name: SetRec
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/SetRec
Keywords: [recursion, recursive grammar, parser, set, ParseRecursive, mutual recursion, parser zoo]
SeeAlso: [RecCell, RecRef, ParseRecursive, ParseChoice, ParseBetween]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[SetRec]()[*cell*, *parser*]</code> gives a recursion cell its parser, closing a recursive grammar's loop.

## Details & Options

- A recursive grammar is built in two moves: allocate a cell with [RecCell]() and reference it with [RecRef]() while writing the productions, then call `SetRec` to bind the cell's symbol to the finished parser. Until `SetRec` runs, a [RecRef]() points at an unset cell.
- `SetRec` assigns the parser to the cell's underlying [Unique]() symbol, where [ParseRecursive]() looks it up at parse time. It returns the *parser* it was given, so it can stand as the last line of a builder.
- Make *parser* a [ParseChoice]() of concrete alternatives rather than a production beginning with a nullable parser; re-entering at a nullable prefix can match empty and bail instead of recursing.
- Mutually-recursive productions each get their own cell; bind each with its own `SetRec`, in any order, since the references resolve lazily.

## Basic Examples

Allocate a cell, write a nested-list production that refers to it through [RecRef](), and close the loop with `SetRec`:

```wl
cell = RecCell[];
list = ParseBetween[
    ParseLiteral["["],
    ParseSepBy[ParseChoice[ParseRegex["[0-9]+"], RecRef[cell]], ParseLiteral[","]],
    ParseLiteral["]"]
];
SetRec[cell, list];
Parse[list, "[1,[2,3]]"]
```

<!-- => {"1", {"2", "3"}} -->

`SetRec` returns the parser it was handed, so it composes as the tail of a grammar builder:

```wl
SetRec[RecCell[], ParseLiteral["x"]]
```

<!-- => ParserCombinator["Literal", "x", <||>] -->

## Scope

Two cells bind two mutually-recursive productions - a value is a number or a list, and a list holds values. Each `SetRec` closes one loop, and they resolve through each other:

```wl
valueCell = RecCell[];
listCell = RecCell[];
SetRec[valueCell, ParseChoice[ParseRegex["[0-9]+"], RecRef[listCell]]];
SetRec[listCell, ParseBetween[ParseLiteral["("], ParseSepBy[RecRef[valueCell], ParseLiteral[","]], ParseLiteral[")"]]];
Parse[RecRef[valueCell], "(1,(2,3),4)"]
```

<!-- => {"1", {"2", "3"}, "4"} -->

## Possible Issues

An input whose list never closes is an honest [Failure](), reporting the position where the close delimiter was expected:

```wl
Parse[RecRef[valueCell], "(1,2"]
```

<!-- => Failure["ParseError", <|"Position" -> 5, "Expected" -> {")"}, "Found" -> "<end of input>"|>] -->

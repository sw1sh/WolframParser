---
Template: Symbol
Name: ABCAST
Context: Wolfram`Parser`Languages`ABC`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ABCAST
Keywords: [ABC, abstract syntax tree, AST, esoteric language, parser zoo]
SeeAlso: [ABCRun, ABCGrammar, ABCSemantic, ASTAlgebra, ASTStripSource]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingABC, ParserZoo]
---

## Usage

<code>[ABCAST]()[*program*]</code> parses the ABC source string *program* to a standard syntax tree: a [ContainerNode]() of one node per line.

## Details & Options

- `ABCAST` runs [ABCGrammar]() over [ASTAlgebra](), extended with the three statements. The grammar is the one [ABCRun]() executes; only the algebra differs.
- A `print` line is a [CallNode]() headed by a `"Keyword"` [LeafNode]() with its expression as the argument, and a `stop` line the same with no argument. A named calculation is a [BinaryNode]() `"="` of its name and its expression.
- Within an expression, numbers are `"Integer"` leaves, names `"Symbol"` leaves, operators [BinaryNode]() objects, and a call a [CallNode]() headed by the name's leaf.
- Every node carries its `"Source"` span, as `{start, end}` positions; [ASTStripSource]() removes them.
- A program that does not parse gives the [Failure]() of [Parse]().

## Basic Examples

The tree of a one-line program, every node with its source span:

```wl
ABCAST["print a - b + b"]
```

The same tree with the spans removed:

```wl
ASTStripSource @ ABCAST["print a - b + b"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Keyword", "print", <||>], {BinaryNode["+", {BinaryNode["-", {LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "b", <||>]}, <||>], LeafNode["Symbol", "b", <||>]}, <||>]}, <||>]}, <||>] -->

## Scope

A named calculation is an `"="` node, a call a [CallNode]() headed by its name, and `stop` a keyword with no argument:

```wl
ASTStripSource @ ABCAST["f = f(t - 1) * t + (1 - t)\nprint f(3)\nstop"]
```

<!-- => ContainerNode["String", {BinaryNode["=", {LeafNode["Symbol", "f", <||>], BinaryNode["+", {BinaryNode["*", {CallNode[LeafNode["Symbol", "f", <||>], {BinaryNode["-", {LeafNode["Symbol", "t", <||>], LeafNode["Integer", "1", <||>]}, <||>]}, <||>], LeafNode["Symbol", "t", <||>]}, <||>], BinaryNode["-", {LeafNode["Integer", "1", <||>], LeafNode["Symbol", "t", <||>]}, <||>]}, <||>]}, <||>], CallNode[LeafNode["Keyword", "print", <||>], {CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Integer", "3", <||>]}, <||>]}, <||>], CallNode[LeafNode["Keyword", "stop", <||>], {}, <||>]}, <||>] -->

`*` binds tighter than `+`, so the product is the left operand of the sum:

```wl
ASTStripSource @ ABCAST["print 1 + 2 * 3"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Keyword", "print", <||>], {BinaryNode["+", {LeafNode["Integer", "1", <||>], BinaryNode["*", {LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>]}, <||>]}, <||>]}, <||>] -->

## Properties & Relations

[ABCRun]() runs the same source instead of describing it:

```wl
ABCRun["print 1 + 2 * 3"]
```

<!-- => {7} -->

## Possible Issues

`print` needs a space before its expression, so `print(1)` does not parse:

```wl
ABCAST["print(1)"]
```

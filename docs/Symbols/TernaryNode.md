---
Template: Symbol
Name: TernaryNode
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/TernaryNode
Keywords: [AST, ternary, conditional, operator, three operands, syntax tree, parser zoo, CodeParser]
SeeAlso: [BinaryNode, InfixNode, PrefixNode, PostfixNode, ASTNodeQ, ToCodeParser]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[TernaryNode]()[*op*, {*a*, *b*, *c*}, *meta*]</code> is a ternary-operator application: *op* is the operator descriptor string, the child list holds the three operands *a*, *b* and *c*, and *meta* is a metadata association.

## Details & Options

- `TernaryNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``TernaryNode`.
- The child list always has exactly three elements - the canonical case is a C-style conditional `c ? a : b`, whose descriptor might be written `"?"`.
- *op* stays a language-native descriptor string rather than a Wolfram symbol.
- `TernaryNode` is part of the standard vocabulary, but none of the five sample grammars (calculator, JSON, Lisp, lambda, Brainfuck) define a ternary operator, so they never emit one. The `"Ternary"` builder of [ASTAlgebra]() is present for grammars that need it. The examples below build the node literally.
- *meta* holds a `"Source"` position when the node comes from a real parse, and is an empty `<||>` when you build it by hand - as in every example here.

## Basic Examples

A ternary node built literally holds its operator and three-element child list - here a conditional `c ? a : b`:

```wl
TernaryNode["?", {LeafNode["Symbol", "c", <||>], LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "b", <||>]}, <||>]
```

<!-- => TernaryNode["?", {LeafNode["Symbol", "c", <||>], LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "b", <||>]}, <||>] -->

A `TernaryNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[TernaryNode["?", {LeafNode["Symbol", "c", <||>], LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "b", <||>]}, <||>]]
```

<!-- => True -->

## Properties and Relations

[ToCodeParser]() projects the ternary application onto a three-argument `CodeParser``CallNode`. With no entry for the *op* descriptor in the operator map, the head leaf keeps the descriptor string verbatim:

```wl
ToCodeParser[TernaryNode["?", {LeafNode["Symbol", "c", <||>], LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "b", <||>]}, <||>]]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, "?", <||>], {CodeParser`LeafNode[Symbol, "c", <||>], CodeParser`LeafNode[Symbol, "a", <||>], CodeParser`LeafNode[Symbol, "b", <||>]}, <||>] -->

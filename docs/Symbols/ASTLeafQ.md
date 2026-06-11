---
Template: Symbol
Name: ASTLeafQ
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ASTLeafQ
Keywords: [AST, leaf, terminal, predicate, test, parser zoo, LeafNode]
SeeAlso: [ASTNodeQ, ASTContainer, ASTAlgebra, LeafNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ASTLeafQ]()[*node*]</code> tests whether *node* is a [LeafNode]() - the terminal of a standard AST.

## Details & Options

- A [LeafNode]() is the only terminal in the standard vocabulary: `LeafNode[kind, source, <|meta|>]`, where *kind* is a descriptor string (`"Integer"`, `"Real"`, `"String"`, `"Symbol"`, `"Token"`, ...) and *source* is the matched text.
- `ASTLeafQ` returns [True]() only for a [LeafNode](); any interior node ([BinaryNode](), [CallNode](), [GroupNode](), ...) and any non-node return [False]().
- It is a total predicate - it returns [False]() rather than staying unevaluated on a non-node argument, so it composes with [Select]() and pattern tests.
- For the broader test "is this any standard AST node", use [ASTNodeQ]().

## Basic Examples

A [LeafNode]() is a leaf:

```wl
ASTLeafQ[LeafNode["Integer", "1", <||>]]
```

<!-- => True -->

An interior [BinaryNode]() is not:

```wl
ASTLeafQ[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]]
```

<!-- => False -->

A non-node argument is [False](), not an unevaluated predicate:

```wl
ASTLeafQ[42]
```

<!-- => False -->

## Scope

Because it is total, `ASTLeafQ` filters a mixed list directly with [Select]():

```wl
Select[{LeafNode["Integer", "1", <||>], BinaryNode["+", {}, <||>], LeafNode["Symbol", "x", <||>]}, ASTLeafQ]
```

<!-- => {LeafNode["Integer", "1", <||>], LeafNode["Symbol", "x", <||>]} -->

## Properties and Relations

Every leaf is also a node, so `ASTLeafQ` is strictly narrower than [ASTNodeQ](). An interior [GroupNode]() is a node but not a leaf:

```wl
ASTNodeQ[GroupNode["Array", {}, <||>]]
```

<!-- => True -->

The same [GroupNode]() is not a leaf:

```wl
ASTLeafQ[GroupNode["Array", {}, <||>]]
```

<!-- => False -->

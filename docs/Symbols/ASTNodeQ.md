---
Template: Symbol
Name: ASTNodeQ
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ASTNodeQ
Keywords: [AST, node, predicate, test, syntax tree, parser zoo]
SeeAlso: [ASTLeafQ, ASTContainer, ASTAlgebra, LeafNode, CallNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ASTNodeQ]()[*node*]</code> tests whether *node* is any standard AST node.

## Details & Options

- The standard vocabulary has ten heads: [LeafNode](), [CallNode](), [PrefixNode](), [PostfixNode](), [BinaryNode](), [InfixNode](), [TernaryNode](), [GroupNode](), [ContainerNode]() and `ErrorNode`. `ASTNodeQ` returns [True]() when the head of *node* is one of these.
- It is a total predicate - any other expression, including a number or a bare [Association](), returns [False]() rather than staying unevaluated, so it composes with [Cases]() and pattern tests like `_ ? ASTNodeQ`.
- The test is on the head only; it does not recurse into children or check arity. A malformed `BinaryNode[]` would still pass.
- For the narrower test "is this a terminal", use [ASTLeafQ]().

## Basic Examples

A [LeafNode]() is a node:

```wl
ASTNodeQ[LeafNode["Integer", "1", <||>]]
```

<!-- => True -->

So is an interior [BinaryNode]():

```wl
ASTNodeQ[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]]
```

<!-- => True -->

A plain string is not a node:

```wl
ASTNodeQ["x"]
```

<!-- => False -->

## Scope

The root [ContainerNode]() is a node too, so a whole tree passes at its root:

```wl
ASTNodeQ[ContainerNode["String", {}, <||>]]
```

<!-- => True -->

Because it is total, `ASTNodeQ` works as a pattern test to keep only the nodes out of a mixed list:

```wl
Cases[{LeafNode["Integer", "1", <||>], 42, GroupNode["Array", {}, <||>], "x"}, _ ? ASTNodeQ]
```

<!-- => {LeafNode["Integer", "1", <||>], GroupNode["Array", {}, <||>]} -->

## Properties and Relations

`ASTNodeQ` is the broad test; [ASTLeafQ]() is the narrow one for terminals only. An interior node passes [ASTNodeQ]() but fails [ASTLeafQ]():

```wl
ASTLeafQ[GroupNode["Array", {}, <||>]]
```

<!-- => False -->

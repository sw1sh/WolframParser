---
Template: Symbol
Name: ASTContainer
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ASTContainer
Keywords: [AST, container, root node, syntax tree, parser zoo, ContainerNode]
SeeAlso: [ASTAlgebra, ASTNodeQ, ToCodeParser, ContainerNode, LeafNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ASTContainer]()[*children*]</code> wraps a list of top-level forms in a [ContainerNode]()`["String", ..]` root.

<code>[ASTContainer]()[*child*]</code> wraps a single form, lifting it into a one-element list first.

## Details & Options

- The [ContainerNode]() is the root of every standard AST, mirroring [CodeParser]()'s own top-level wrapper. The first slot is the source kind `"String"`; the second is the list of top-level children; the third is empty `<||>` metadata.
- A language entry point applies `ASTContainer` to the result of [Parse]() once it has succeeded, so the tree has a single, uniform root whether the source held one form or many. [CalculatorAST](), [JSONAST]() and [LispAST]() all finish this way.
- The one-argument form is a convenience: <code>[ASTContainer]()[*child*]</code> is <code>[ASTContainer]()[{*child*}]</code>.
- `ASTContainer` does not validate its children; it is a structural wrapper. Use [ASTNodeQ]() to test a node.

## Basic Examples

Wrap a list of top-level leaves:

```wl
ASTContainer[{LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>] -->

A single form is lifted into a one-element child list:

```wl
ASTContainer[LeafNode["Symbol", "x", <||>]]
```

<!-- => ContainerNode["String", {LeafNode["Symbol", "x", <||>]}, <||>] -->

The root head is always [ContainerNode]():

```wl
Head[ASTContainer[LeafNode["Integer", "1", <||>]]]
```

<!-- => ContainerNode -->

## Scope

An empty top level is a [ContainerNode]() with no children:

```wl
ASTContainer[{}]
```

<!-- => ContainerNode["String", {}, <||>] -->

A nested tree is wrapped whole - `ASTContainer` only adds the root, it does not descend:

```wl
ASTContainer[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]}, <||>] -->

## Properties and Relations

The produced root is itself a standard AST node, so [ASTNodeQ]() accepts it:

```wl
ASTNodeQ[ASTContainer[{LeafNode["Integer", "1", <||>]}]]
```

<!-- => True -->

[ToCodeParser]() maps the wrapper onto [CodeParser]()'s own `ContainerNode`, keeping the `"String"` kind:

```wl
ToCodeParser[ASTContainer[LeafNode["Integer", "1", <||>]]]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`LeafNode[Integer, "1", <||>]}, <||>] -->

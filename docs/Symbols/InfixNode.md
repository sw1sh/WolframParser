---
Template: Symbol
Name: InfixNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/InfixNode
Keywords: [AST, infix, n-ary, flat, operator, chain, syntax tree, parser zoo, CodeParser]
SeeAlso: [BinaryNode, PrefixNode, PostfixNode, TernaryNode, ASTNodeQ, ToCodeParser]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[InfixNode]()[*op*, {*children*}, *meta*]</code> is a flat n-ary operator chain: *op* is the operator descriptor string, *children* is the list of two or more operands, and *meta* is a metadata association.

## Details & Options

- `InfixNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``InfixNode`.
- The difference from [BinaryNode]() is arity: an `InfixNode` flattens a whole same-operator run `a+b+c` into one node with three children, whereas a `BinaryNode` chain nests pairwise.
- *op* stays a language-native descriptor string (`"+"`) rather than a Wolfram symbol.
- `InfixNode` is part of the standard vocabulary, but the five sample grammars do not flatten chains: [CalculatorAST]() builds nested [BinaryNode]() nodes for `1+2+3` instead of one `InfixNode`. The `"Infix"` builder of [ASTAlgebra]() is present for grammars that prefer the flat form. The first example below builds the node literally.
- *meta* holds a `"Source"` position when the node comes from a real parse, and is an empty `<||>` when you build it by hand.

## Basic Examples

An infix node built literally flattens the whole `1+2+3` run into one node with three children:

```wl
InfixNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>]
```

<!-- => InfixNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>] -->

The calculator does *not* flatten: the same `1+2+3` parses to nested [BinaryNode]() nodes, not an `InfixNode`:

```wl
CalculatorAST["1+2+3"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>] -->

## Properties and Relations

An `InfixNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[InfixNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the chain onto a single `CodeParser``CallNode` with all children as arguments, mapping the *op* descriptor to a Wolfram symbol through the supplied operator map:

```wl
ToCodeParser[InfixNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>], <|"+" -> Plus|>]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>], {CodeParser`LeafNode[Integer, "1", <||>], CodeParser`LeafNode[Integer, "2", <||>], CodeParser`LeafNode[Integer, "3", <||>]}, <||>] -->

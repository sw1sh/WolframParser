---
Template: Symbol
Name: ToCodeParser
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`Languages`Lisp`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ToCodeParser
Keywords: [AST, CodeParser, projection, conversion, opmap, parser zoo, CallNode]
SeeAlso: [ASTAlgebra, ASTContainer, ASTAddSource, CalculatorAST, LeafNode, ContainerNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ToCodeParser]()[*tree*]</code> best-effort projects a neutral node *tree* onto [CodeParser]()-exact nodes.

<code>[ToCodeParser]()[*tree*, *opmap*]</code> additionally maps each operator descriptor to a Wolfram symbol through the [Association]() *opmap*.

## Details & Options

- The standard AST nodes share [CodeParser]()'s 3-slot shape but keep operator descriptors as language-native strings (`"+"`, not `Plus`). `ToCodeParser` rewrites a tree into the `CodeParser`-namespaced heads so it can flow into tools that expect real [CodeParser]() output.
- The operator-bearing nodes ([BinaryNode](), [InfixNode](), [PrefixNode](), [PostfixNode](), [TernaryNode]()) all become a `CodeParser`CallNode` headed by a symbol leaf; the descriptor is looked up in *opmap*, defaulting to the descriptor string itself when absent.
- A [LeafNode]() kind string is mapped to a Wolfram symbol where there is an obvious one: `"Integer" -> Integer`, `"Real" -> Real`, `"String" -> String`, `"Symbol" -> Symbol`, `"Rational" -> Rational`; any other kind becomes `Symbol`.
- A [GroupNode]() becomes a `CallNode` headed by a symbol leaf carrying the group kind; a [ContainerNode]() becomes a `CodeParser`ContainerNode`; a [CallNode]() keeps its head and arguments.
- It is *best-effort*: the projection is structural, so an unmapped operator stays a string leaf. Metadata is carried through untouched - when the input tree already has `Source -> {{line, col}, {line, col}}` (as a [CalculatorAST]() or [LispAST]() tree does, via [SpannedToken]() and [ASTAddSource]()), the projected `CodeParser`-nodes keep it; a literally-built node with `<||>` projects to `<||>`.

## Basic Examples

A neutral [CalculatorAST]() tree projects onto [CodeParser]()'s shape; the *opmap* turns `"+"` into a real [Plus](), and the `Source` spans the grammar stamped on each node carry through:

```wl
ToCodeParser[CalculatorAST["1+2"], <|"+" -> Plus|>]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>], {CodeParser`LeafNode[Integer, "1", <|"Source" -> {{1, 1}, {1, 2}}|>], CodeParser`LeafNode[Integer, "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

A [BinaryNode]() becomes a `CodeParser`CallNode` headed by the mapped symbol:

```wl
ToCodeParser[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>], <|"+" -> Plus|>]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>], {CodeParser`LeafNode[Integer, "1", <||>], CodeParser`LeafNode[Integer, "2", <||>]}, <||>] -->

A [LeafNode]() kind string is mapped to the matching Wolfram symbol:

```wl
ToCodeParser[LeafNode["Integer", "1", <||>]]
```

<!-- => CodeParser`LeafNode[Integer, "1", <||>] -->

## Scope

With no *opmap*, an operator descriptor stays a string in the head leaf - the projection is structural, not interpretive:

```wl
ToCodeParser[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, "+", <||>], {CodeParser`LeafNode[Integer, "1", <||>], CodeParser`LeafNode[Integer, "2", <||>]}, <||>] -->

A [GroupNode]() projects to a `CodeParser`CallNode` headed by a symbol leaf carrying the group kind:

```wl
ToCodeParser[GroupNode["Array", {LeafNode["Integer", "1", <||>]}, <||>]]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, "Array", <||>], {CodeParser`LeafNode[Integer, "1", <||>]}, <||>] -->

## Properties and Relations

The projection is grammar-agnostic. The same *opmap* idea turns a [LispAST]() `(+ 1 2)` into a real [Plus]() call - here `"+"` is left unmapped to show the default, descriptor-as-string leaf:

```wl
ToCodeParser[LispAST["(+ 1 2)"]]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`CallNode[CodeParser`LeafNode[Symbol, "+", <|"Source" -> {{1, 2}, {1, 3}}|>], {CodeParser`LeafNode[Integer, "1", <|"Source" -> {{1, 4}, {1, 5}}|>], CodeParser`LeafNode[Integer, "2", <|"Source" -> {{1, 6}, {1, 7}}|>]}, <|"Source" -> {{1, 2}, {1, 7}}|>]}, <|"Source" -> {{1, 2}, {1, 7}}|>] -->

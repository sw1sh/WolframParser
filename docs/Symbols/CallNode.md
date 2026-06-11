---
Template: Symbol
Name: CallNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Lisp`, Wolfram`Parser`Languages`Lambda`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/CallNode
Keywords: [AST, call, application, syntax tree, s-expression, lambda, parser zoo, CodeParser]
SeeAlso: [LeafNode, GroupNode, ContainerNode, ASTNodeQ, ToCodeParser, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[CallNode]()[*head*, *args*, *meta*]</code> is an application node of the standard syntax tree: *head* is itself a node (usually a [LeafNode]()), *args* is the list of argument nodes, and *meta* is a metadata association.

## Details & Options

- `CallNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``CallNode`, differing only in that *head* may stay a language-native leaf rather than a Wolfram symbol.
- Unlike the operator nodes, the *head* of a `CallNode` is a full node, not an operator descriptor string. This makes it the right shape for prefix-application languages where the operator position holds an arbitrary expression.
- *args* is always a list, even for a single argument.
- [LispAST]() turns a non-empty list `(f a b)` into a `CallNode` headed by its first element; [LambdaAST]() uses it both for application (juxtaposition `f x`) and for abstraction, where the head is the lambda leaf `LeafNode["Symbol", "λ", <||>]` and the two children are the bound name and the body.
- The calculator and JSON grammars build operator nodes ([BinaryNode](), [PrefixNode](), [GroupNode]()) instead of `CallNode`. *meta* holds a `"Source"` position when the call comes from a real parse, and is an empty `<||>` when you build the node by hand.

## Basic Examples

A call built literally holds its head and argument list:

```wl
CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Symbol", "x", <||>]}, <||>]
```

<!-- => CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Symbol", "x", <||>]}, <||>] -->

A Lisp s-expression reads head-first into a `CallNode`:

```wl
LispAST["(f x)"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "f", <|"Source" -> {{1, 2}, {1, 3}}|>], {LeafNode["Symbol", "x", <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 2}, {1, 5}}|>]}, <|"Source" -> {{1, 2}, {1, 5}}|>] -->

Lambda-calculus application juxtaposes the two terms into a `CallNode`:

```wl
LambdaAST["f x"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "f", <|"Source" -> {{1, 1}, {1, 2}}|>], {LeafNode["Symbol", "x", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

## Properties and Relations

A `CallNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Symbol", "x", <||>]}, <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the neutral call onto a `CodeParser``-namespaced `CodeParser``CallNode`, recursing into the head and arguments:

```wl
ToCodeParser[CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Symbol", "x", <||>]}, <||>]]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, "f", <||>], {CodeParser`LeafNode[Symbol, "x", <||>]}, <||>] -->

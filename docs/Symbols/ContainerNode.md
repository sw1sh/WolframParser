---
Template: Symbol
Name: ContainerNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`Languages`Lisp`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ContainerNode
Keywords: [AST, container, root, top level, syntax tree, parser zoo, CodeParser]
SeeAlso: [GroupNode, CallNode, LeafNode, ASTNodeQ, ToCodeParser, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ContainerNode]()[*kind*, {*children*}, *meta*]</code> is the root node wrapping every top-level form: *kind* names the source container (`"String"` for the zoo grammars), *children* is the list of top-level forms, and *meta* is a metadata association.

## Details & Options

- `ContainerNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``ContainerNode`, the root every `CodeParser` form is wrapped in.
- Every zoo language function ([CalculatorAST](), [JSONAST](), [LispAST](), [LambdaAST](), [BrainfuckAST]()) returns a `ContainerNode["String", …]` at the top, so a parsed program has one uniform root regardless of language. The convenience builder `ASTContainer` produces it.
- *children* is the list of top-level forms. Most grammars parse a single form (a one-element list), but Lisp reads several top-level s-expressions into several children.
- *kind* is `"String"` because the source is a string. *meta* holds a `"Source"` position spanning the whole parsed program when the root comes from a real parse, and is an empty `<||>` when you build the node by hand.

## Basic Examples

A container built literally holds its kind and the list of top-level forms:

```wl
ContainerNode["String", {LeafNode["Integer", "1", <||>]}, <||>]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "1", <||>]}, <||>] -->

Every parse is wrapped in a `ContainerNode["String", …]` root - here a single leaf:

```wl
CalculatorAST["1"]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>]}, <|"Source" -> {{1, 1}, {1, 2}}|>] -->

A Lisp source with two top-level forms reads as two children of one container:

```wl
LispAST["1 ; one\n2"]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{2, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 1}, {2, 2}}|>] -->

## Properties and Relations

A `ContainerNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[ContainerNode["String", {}, <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the root onto a `CodeParser``ContainerNode`, keeping *kind* and recursing into the children:

```wl
ToCodeParser[ContainerNode["String", {LeafNode["Integer", "1", <||>]}, <||>]]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`LeafNode[Integer, "1", <||>]}, <||>] -->

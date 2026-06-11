---
Template: Symbol
Name: LeafNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`Languages`Brainfuck`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LeafNode
Keywords: [AST, leaf, terminal, token, syntax tree, parser zoo, CodeParser]
SeeAlso: [CallNode, GroupNode, ContainerNode, ASTNodeQ, ToCodeParser, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LeafNode]()[*kind*, *source*, *meta*]</code> is a terminal node of the standard syntax tree, carrying the descriptor string *kind*, the matched text *source*, and a metadata association *meta*.

## Details & Options

- `LeafNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It exists only to give parsed output a uniform, inspectable shape, mirroring `CodeParser``s own `CodeParser``LeafNode`.
- *kind* is a language-native descriptor string such as `"Integer"`, `"Real"`, `"String"`, `"Symbol"`, `"Boolean"`, `"Null"`, `"Command"` or `"Token"`. It labels the terminal without committing to a Wolfram symbol.
- *source* is the literal matched text, kept verbatim: the integer one is `"1"`, not `1`, and a JSON string leaf keeps its surrounding quotes. A value is only interpreted in a language's evaluating mode (for example [CalculatorEval]()).
- *meta* is an association of metadata. When the leaf comes from a real parse it holds a `"Source"` position `{{`*line*`, `*col*`}, {`*line*`, `*col*`}}` spanning the matched text; a node you build by hand carries an empty `<||>`.
- Every zoo grammar emits leaves: [CalculatorAST]() tags numbers `"Integer"`/`"Real"` and identifiers `"Symbol"`; [JSONAST]() adds `"String"`, `"Boolean"` and `"Null"`; [BrainfuckAST]() tags each of the eight commands `"Command"`; [LispAST]() and [LambdaAST]() use `"Symbol"` for identifiers.

## Basic Examples

A leaf built literally holds its three slots unevaluated:

```wl
LeafNode["Integer", "1", <||>]
```

<!-- => LeafNode["Integer", "1", <||>] -->

A bare integer parses to a single `"Integer"` leaf inside the [ContainerNode]() root:

```wl
CalculatorAST["42"]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "42", <|"Source" -> {{1, 1}, {1, 3}}|>]}, <|"Source" -> {{1, 1}, {1, 3}}|>] -->

Each Brainfuck command is a `"Command"` leaf:

```wl
BrainfuckAST["+"]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>]}, <|"Source" -> {{1, 1}, {1, 2}}|>] -->

## Properties and Relations

A `LeafNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[LeafNode["Integer", "1", <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the neutral leaf onto a `CodeParser``-namespaced node, turning the *kind* descriptor into the matching Wolfram symbol head:

```wl
ToCodeParser[LeafNode["Integer", "1", <||>]]
```

<!-- => CodeParser`LeafNode[Integer, "1", <||>] -->

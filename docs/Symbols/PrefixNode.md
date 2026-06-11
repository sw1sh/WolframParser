---
Template: Symbol
Name: PrefixNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`Languages`Lisp`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/PrefixNode
Keywords: [AST, prefix, unary, operator, syntax tree, parser zoo, CodeParser]
SeeAlso: [PostfixNode, BinaryNode, InfixNode, LeafNode, ASTNodeQ, ToCodeParser]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[PrefixNode]()[*op*, *operand*, *meta*]</code> is a prefix-operator application: *op* is the operator descriptor string, *operand* is the node the operator applies to, and *meta* is a metadata association.

## Details & Options

- `PrefixNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``PrefixNode`.
- *op* stays a language-native descriptor string (`"-"`, `"'"`) rather than a Wolfram symbol, so the same node serves any language's prefix operators.
- *operand* is a single node (not a list), distinguishing the prefix shape from the multi-child [InfixNode]() and [GroupNode]().
- [CalculatorAST]() emits a `PrefixNode["-", …]` for unary minus, declared as a `"Prefix"` level in its operator table. [LispAST]() emits a `PrefixNode["'", …]` for the quote reader macro.
- *meta* holds a `"Source"` position `{{`*line*`, `*col*`}, {`*line*`, `*col*`}}` when the node comes from a real parse, and is an empty `<||>` when you build the node by hand.

## Basic Examples

A prefix node built literally holds its operator and operand:

```wl
PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>]
```

<!-- => PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>] -->

Unary minus in the calculator parses to a `PrefixNode` with descriptor `"-"`:

```wl
CalculatorAST["-x"]
```

<!-- => ContainerNode["String", {PrefixNode["-", LeafNode["Symbol", "x", <|"Source" -> {{1, 2}, {1, 3}}|>], <|"Source" -> {{1, 2}, {1, 3}}|>]}, <|"Source" -> {{1, 2}, {1, 3}}|>] -->

The Lisp quote reader macro `'x` is a `PrefixNode` with descriptor `"'"`:

```wl
LispAST["'x"]
```

<!-- => ContainerNode["String", {PrefixNode["'", LeafNode["Symbol", "x", <|"Source" -> {{1, 2}, {1, 3}}|>], <|"Source" -> {{1, 2}, {1, 3}}|>]}, <|"Source" -> {{1, 2}, {1, 3}}|>] -->

## Properties and Relations

A `PrefixNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the prefix application onto a unary `CodeParser``CallNode`, mapping the *op* descriptor to a Wolfram symbol through the supplied operator map:

```wl
ToCodeParser[PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>], <|"-" -> Minus|>]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, Minus, <||>], {CodeParser`LeafNode[Symbol, "x", <||>]}, <||>] -->

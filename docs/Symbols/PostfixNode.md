---
Template: Symbol
Name: PostfixNode
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/PostfixNode
Keywords: [AST, postfix, unary, operator, factorial, syntax tree, parser zoo, CodeParser]
SeeAlso: [PrefixNode, BinaryNode, InfixNode, TernaryNode, ASTNodeQ, ToCodeParser]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[PostfixNode]()[*operand*, *op*, *meta*]</code> is a postfix-operator application: *operand* is the node the operator applies to, *op* is the operator descriptor string, and *meta* is a metadata association.

## Details & Options

- `PostfixNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``PostfixNode`.
- The slot order is the mirror of [PrefixNode](): the *operand* comes first and the *op* descriptor second, matching the surface order of a postfix operator such as factorial `x!`.
- *op* stays a language-native descriptor string (`"!"`, `"++"`) rather than a Wolfram symbol.
- `PostfixNode` is part of the standard vocabulary, but none of the five sample grammars (calculator, JSON, Lisp, lambda, Brainfuck) define a postfix operator, so they never emit one. The `"Postfix"` builder of [ASTAlgebra]() is present for grammars that need it. The examples below build the node literally.
- *meta* holds a `"Source"` position when the node comes from a real parse, and is an empty `<||>` when you build it by hand - as in every example here.

## Basic Examples

A postfix node built literally puts the operand before the operator descriptor - here a factorial `x!`:

```wl
PostfixNode[LeafNode["Symbol", "x", <||>], "!", <||>]
```

<!-- => PostfixNode[LeafNode["Symbol", "x", <||>], "!", <||>] -->

A `PostfixNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[PostfixNode[LeafNode["Symbol", "x", <||>], "!", <||>]]
```

<!-- => True -->

## Properties and Relations

[ToCodeParser]() projects the postfix application onto a unary `CodeParser``CallNode`, mapping the *op* descriptor to a Wolfram symbol through the supplied operator map:

```wl
ToCodeParser[PostfixNode[LeafNode["Symbol", "x", <||>], "!", <||>], <|"!" -> Factorial|>]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, Factorial, <||>], {CodeParser`LeafNode[Symbol, "x", <||>]}, <||>] -->

---
Template: Symbol
Name: BinaryNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`Languages`JSON`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/BinaryNode
Keywords: [AST, binary, operator, infix, syntax tree, parser zoo, CodeParser]
SeeAlso: [InfixNode, PrefixNode, PostfixNode, TernaryNode, ASTNodeQ, ToCodeParser]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[BinaryNode]()[*op*, {*lhs*, *rhs*}, *meta*]</code> is a binary-operator application: *op* is the operator descriptor string, the child list holds the left operand *lhs* and the right operand *rhs*, and *meta* is a metadata association.

## Details & Options

- `BinaryNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``BinaryNode`.
- *op* stays a language-native descriptor string (`"+"`, `":"`) rather than a Wolfram symbol, so one node serves arithmetic operators and a JSON `key: value` pairing alike.
- The child list always has exactly two elements. A left- or right-associative chain of the same operator nests as `BinaryNode` inside `BinaryNode`, rather than flattening into a single [InfixNode]().
- [CalculatorAST]() builds a `BinaryNode` for each of `+` `-` `*` `/` `^`, with the operator table giving `^` right associativity and the rest left. [JSONAST]() uses `BinaryNode[":", {`*key*`, `*value*`}]` for each object member.
- The zoo grammars use `BinaryNode` (nested) where a flattening grammar might use [InfixNode](). *meta* holds a `"Source"` position when the node comes from a real parse, and is an empty `<||>` when you build the node by hand.

## Basic Examples

A binary node built literally holds its operator and two-element child list:

```wl
BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]
```

<!-- => BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>] -->

An arithmetic sum parses to a `BinaryNode["+", …]`:

```wl
CalculatorAST["1+2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

Each JSON object member is a `BinaryNode[":", …]` pairing the key leaf with the value:

```wl
JSONAST["{\"k\": 1}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"k\"", <|"Source" -> {{1, 2}, {1, 5}}|>], LeafNode["Integer", "1", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>] -->

## Scope

A same-operator chain nests left, so `1+2+3` is a `BinaryNode` whose left child is itself a `BinaryNode`, not a flat [InfixNode]():

```wl
CalculatorAST["1+2+3"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>] -->

## Properties and Relations

A `BinaryNode` answers [ASTNodeQ]() with [True]():

```wl
ASTNodeQ[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the binary application onto a two-argument `CodeParser``CallNode`, mapping the *op* descriptor to a Wolfram symbol through the supplied operator map:

```wl
ToCodeParser[BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>], <|"+" -> Plus|>]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>], {CodeParser`LeafNode[Integer, "1", <||>], CodeParser`LeafNode[Integer, "2", <||>]}, <||>] -->

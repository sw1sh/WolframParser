---
Template: Symbol
Name: GroupNode
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`JSON`, Wolfram`Parser`Languages`Brainfuck`, Wolfram`Parser`Languages`Lisp`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/GroupNode
Keywords: [AST, group, delimited, bracket, object, array, loop, syntax tree, parser zoo, CodeParser]
SeeAlso: [ContainerNode, CallNode, LeafNode, BinaryNode, ASTNodeQ, ToCodeParser]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[GroupNode]()[*kind*, {*children*}, *meta*]</code> is a delimited group: *kind* is a descriptor string naming the delimiter or container, *children* is the list of enclosed nodes, and *meta* is a metadata association.

## Details & Options

- `GroupNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``GroupNode`.
- *kind* is a language-native descriptor string such as `"Paren"`, `"Object"`, `"Array"`, `"List"` or `"Loop"`. It records what kind of bracketed construct produced the group, not its delimiter glyphs.
- *children* is the list of enclosed nodes, possibly empty (an empty object or empty list is a `GroupNode` with no children).
- [JSONAST]() emits a `GroupNode["Object", …]` for `{…}` and a `GroupNode["Array", …]` for `[…]`. [BrainfuckAST]() emits a `GroupNode["Loop", …]` for a `[…]` loop body. [LispAST]() uses `GroupNode["List", {}]` for the empty list `()` (a non-empty list becomes a [CallNode]() instead).
- *meta* holds a `"Source"` position when the group comes from a real parse, and is an empty `<||>` when you build the node by hand (or for a group with no content, like the empty Lisp list `()`). The recorded span covers the group's *content*, not its delimiter glyphs.

## Basic Examples

A group built literally holds its kind and child list:

```wl
GroupNode["Paren", {LeafNode["Integer", "1", <||>]}, <||>]
```

<!-- => GroupNode["Paren", {LeafNode["Integer", "1", <||>]}, <||>] -->

A JSON object is a `GroupNode["Object", …]` whose children are `":"` [BinaryNode]() members:

```wl
JSONAST["{\"k\": 1}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"k\"", <|"Source" -> {{1, 2}, {1, 5}}|>], LeafNode["Integer", "1", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>] -->

A Brainfuck loop body is a `GroupNode["Loop", …]` of command leaves:

```wl
BrainfuckAST["+[>]"]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>], GroupNode["Loop", {LeafNode["Command", ">", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

## Scope

The empty Lisp list `()` has no head, so it is a `GroupNode["List", {}]` rather than a [CallNode]():

```wl
LispAST["()"]
```

<!-- => ContainerNode["String", {GroupNode["List", {}, <||>]}, <||>] -->

## Properties and Relations

A `GroupNode` answers [ASTNodeQ]() with [True]() even when empty:

```wl
ASTNodeQ[GroupNode["Paren", {}, <||>]]
```

<!-- => True -->

[ToCodeParser]() projects the group onto a `CodeParser``CallNode` whose head is a leaf naming the *kind*, with the children as arguments:

```wl
ToCodeParser[GroupNode["List", {LeafNode["Integer", "1", <||>]}, <||>]]
```

<!-- => CodeParser`CallNode[CodeParser`LeafNode[Symbol, "List", <||>], {CodeParser`LeafNode[Integer, "1", <||>]}, <||>] -->

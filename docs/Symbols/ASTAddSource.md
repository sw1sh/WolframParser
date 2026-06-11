---
Template: Symbol
Name: ASTAddSource
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ASTAddSource
Keywords: [AST, source, span, line, column, finalize, parser zoo, CodeParser]
SeeAlso: [SpannedToken, ParsePosition, ToCodeParser, ASTStripSource, LeafNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ASTAddSource]()[*tree*, *source*]</code> finalizes source metadata: it fills each composite node's `Source` by spanning its children, then converts every offset span to a `{{startLine, startColumn}, {endLine, endColumn}}` pair against the string *source*.

## Details & Options

- `ASTAddSource` is the last step of source tracking. [SpannedToken]() leaves each leaf carrying a raw `{start, end}` character-offset span; `ASTAddSource` runs over the whole *tree* and produces the [CodeParser]()-style line/column metadata on every node.
- It works in two passes. First it fills spans bottom-up: a composite node with no `Source` of its own gets `{Min[child starts], Max[child ends]}` from the offset spans of its children, so an interior node spans exactly the source its subtree covers. Then it converts every offset span - leaves' and composites' alike - to `{{line, column}, {line, column}}` against *source*, counting newlines for the line and characters since the last newline for the column.
- A node that *already* has a `Source` (an explicit offset span) is kept and only converted, not re-spanned from its children.
- *source* is the original input string the offsets index into. It is needed because the offset-to-line/column conversion depends on where the newlines fall.
- This is what turns the raw offset spans into the `{{startLine, startColumn}, {endLine, endColumn}}` convention [CodeParser]() uses, so the finished tree's `Source` matches Wolfram's own LineColumn shape. A language entry point such as [CalculatorAST]() calls it internally after [Parse]() succeeds.

## Basic Examples

Build a small tree whose leaves carry offset spans (as [SpannedToken]() would leave them) and finalize it - the composite [BinaryNode]() gets a span covering both leaves, and every offset is converted to `{line, column}`:

```wl
ASTAddSource[ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {1, 2}|>], LeafNode["Integer", "2", <|"Source" -> {3, 4}|>]}, <||>]}, <||>], "1+2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

The [BinaryNode]() had no `Source` of its own; `ASTAddSource` spanned it from its children to `{{1, 1}, {1, 4}}`, covering the whole `"1+2"`.

A multi-line *source* makes the line component count up - an offset on the second line converts to line `2`:

```wl
ASTAddSource[ContainerNode["String", {LeafNode["Integer", "9", <|"Source" -> {3, 4}|>]}, <||>], "1\n9"]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "9", <|"Source" -> {{2, 1}, {2, 2}}|>]}, <|"Source" -> {{2, 1}, {2, 2}}|>] -->

## Properties and Relations

A language entry point wires [SpannedToken]() and `ASTAddSource` together, so the tree it returns already carries finalized line/column `Source`. [CalculatorAST]() calls `ASTAddSource` internally - the spans below are the same `{{line, col}, {line, col}}` pairs the manual call produces:

```wl
CalculatorAST["1+2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

[ASTStripSource]() is the inverse direction - it clears the `Source` `ASTAddSource` added, leaving bare structure.

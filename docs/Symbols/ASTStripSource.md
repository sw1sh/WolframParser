---
Template: Symbol
Name: ASTStripSource
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ASTStripSource
Keywords: [AST, source, strip, clear, structural, comparison, test, parser zoo]
SeeAlso: [ASTAddSource, SpannedToken, ASTNodeQ, LeafNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ASTStripSource]()[*tree*]</code> clears the `Source` metadata from every node of *tree*, leaving the bare structure.

## Details & Options

- `ASTStripSource` is the inverse of [ASTAddSource](): it walks *tree* and drops the `"Source"` key from every node's metadata association, so each node is left with `<||>` (or whatever non-`Source` keys it held).
- It is the practical tool for *structural comparison and tests*: two trees that differ only in where they came from compare equal once both are stripped, so a test can assert on shape without pinning exact line/column spans.
- It does not change a tree's shape - same heads, same children, same descriptors - only the `Source` entries are removed. A stripped tree is still a valid standard AST, so [ASTNodeQ]() still accepts it.
- A node that never carried `Source` (a literally-built `LeafNode["Integer", "1", <||>]`) is unaffected.

## Basic Examples

Strip the `Source` spans a language entry point added - [CalculatorAST]() returns a tree with line/column metadata; `ASTStripSource` leaves `<||>` everywhere:

```wl
ASTStripSource[CalculatorAST["1+2"]]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>]}, <||>] -->

It descends the whole tree, so a deeper expression is stripped at every level:

```wl
ASTStripSource[CalculatorAST["1 + 2*3"]]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <||>], BinaryNode["*", {LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>]}, <||>]}, <||>] -->

## Properties and Relations

Stripping leaves a valid standard AST - only the metadata changes, not the structure - so [ASTNodeQ]() still accepts the result:

```wl
ASTNodeQ[ASTStripSource[CalculatorAST["1+2"]]]
```

<!-- => True -->

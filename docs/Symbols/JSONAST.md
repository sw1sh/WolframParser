---
Template: Symbol
Name: JSONAST
Context: Wolfram`Parser`Languages`JSON`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/JSONAST
Keywords: [JSON, AST, syntax tree, parser zoo, RFC 8259, GroupNode]
SeeAlso: [JSONImport, JSONGrammar, JSONSemantic, GroupNode, BinaryNode, LeafNode, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[JSONAST]()[*json*]</code> parses the JSON string *json* to a standard syntax tree - a [ContainerNode]() of [GroupNode](), [BinaryNode]() and [LeafNode]().

## Details & Options

- `JSONAST` is the standard-AST mode of the JSON grammar: it runs [JSONGrammar]() over a tree-building algebra, so the result carries no native value, only structure.
- A JSON object is a `"Object"` [GroupNode](); a JSON array is an `"Array"` [GroupNode](); each object member is a `":"` [BinaryNode]() pairing the key leaf with the value.
- A [LeafNode]() keeps the literal source text, including the surrounding quotes of a string (`"\"a\""`, not `"a"`) and the raw digits of a number (`"42"`, not `42`); values are only interpreted in the [JSONImport]() mode.
- Number leaves are tagged `"Integer"` or `"Real"` from the literal form - a decimal point or exponent makes it `"Real"`.
- Every node carries a `"Source"` span in its metadata, a [CodeParser]() line-column pair `{{startLine, startCol}, {endLine, endCol}}`. A leaf spans its own text; a [GroupNode]() spans its content (the brackets themselves are not included), so a multi-line input gives a span whose endpoints sit on different lines.
- [JSONImport]() runs the *same* [JSONGrammar]() over [JSONSemantic]() instead, folding to a native Wolfram value. The grammar is written once; only the algebra differs.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

An object is a `"Object"` [GroupNode]() of `":"` [BinaryNode]() members:

```wl
JSONAST["{\"a\": [1, true]}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"a\"", <|"Source" -> {{1, 2}, {1, 5}}|>], GroupNode["Array", {LeafNode["Integer", "1", <|"Source" -> {{1, 8}, {1, 9}}|>], LeafNode["Boolean", "true", <|"Source" -> {{1, 11}, {1, 15}}|>]}, <|"Source" -> {{1, 8}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>] -->

An array is a `"Array"` [GroupNode]():

```wl
JSONAST["[1, 2]"]
```

<!-- => ContainerNode["String", {GroupNode["Array", {LeafNode["Integer", "1", <|"Source" -> {{1, 2}, {1, 3}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 2}, {1, 6}}|>]}, <|"Source" -> {{1, 2}, {1, 6}}|>] -->

The same source through [JSONImport]() is a native value, not a tree:

```wl
JSONImport["{\"a\": [1, true]}"]
```

<!-- => <|"a" -> {1, True}|> -->

## Scope

A [LeafNode]() preserves the literal source text - a string leaf still carries its quotes, and the `\n` escape is left undecoded:

```wl
JSONAST["\"a\\nb\""]
```

<!-- => ContainerNode["String", {LeafNode["String", "\"a\\nb\"", <|"Source" -> {{1, 1}, {1, 7}}|>]}, <|"Source" -> {{1, 1}, {1, 7}}|>] -->

A number leaf is tagged `"Integer"` or `"Real"` from the literal form - an exponent makes it `"Real"` even with no decimal point:

```wl
JSONAST["1e3"]
```

<!-- => ContainerNode["String", {LeafNode["Real", "1e3", <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

Every node records a `"Source"` span. Each [LeafNode]() spans its own text and a [GroupNode]() spans its content, and the span crosses lines when the input does - with `2` on line 2 its leaf reads `{{2, 1}, {2, 2}}`:

```wl
JSONAST["[1,\n2]"]
```

<!-- => ContainerNode["String", {GroupNode["Array", {LeafNode["Integer", "1", <|"Source" -> {{1, 2}, {1, 3}}|>], LeafNode["Integer", "2", <|"Source" -> {{2, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 2}, {2, 2}}|>]}, <|"Source" -> {{1, 2}, {2, 2}}|>] -->

The empty object and empty array are [GroupNode]() with no children - and with no content to span, their metadata is `<||>`:

```wl
JSONAST["{}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {}, <||>]}, <||>] -->

## Properties and Relations

Objects nest as nested `"Object"` groups; the tree mirrors the source structure exactly:

```wl
JSONAST["{\"a\": {\"b\": [1]}}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"a\"", <|"Source" -> {{1, 2}, {1, 5}}|>], GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"b\"", <|"Source" -> {{1, 8}, {1, 11}}|>], GroupNode["Array", {LeafNode["Integer", "1", <|"Source" -> {{1, 14}, {1, 15}}|>]}, <|"Source" -> {{1, 14}, {1, 15}}|>]}, <|"Source" -> {{1, 8}, {1, 15}}|>]}, <|"Source" -> {{1, 8}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>] -->

`JSONAST` and [JSONImport]() share one [JSONGrammar]() and differ only in the algebra fed to it. `JSONAST` builds the [LeafNode]() / [GroupNode]() tree; [JSONImport]() folds to the value `<|"a" -> {1, True}|>`.

## Possible Issues

A truncated array is an honest [Failure](), reporting how far it parsed and what it expected next:

```wl
JSONAST["[1, 2"]
```

<!-- => Failure["ParseError", <|"Position" -> 6, "Expected" -> {"]"}, "Found" -> "<end of input>"|>] -->

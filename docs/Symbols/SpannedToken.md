---
Template: Symbol
Name: SpannedToken
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/SpannedToken
Keywords: [AST, source, span, token, leaf, parser zoo, ParsePosition, LeafNode]
SeeAlso: [ParsePosition, ASTAddSource, ASTStripSource, LeafNode, ParseAction]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[SpannedToken]()[*token*, *ws*, *build*]</code> matches *token*, captures its source span via [ParsePosition](), eats trailing whitespace *ws*, builds the leaf with *build*, and stamps `Source -> {start, end}` (character offsets) onto the node.

## Details & Options

- `SpannedToken` is how the parser-zoo grammars give their leaves source spans. It brackets *token* with two [ParsePosition]() probes - `ParsePosition[] ~~ token ~~ ParsePosition[] ~~ ws` - then applies *build* to the matched text and `setSource`s the captured `{start, end}` onto the result.
- *token* is the parser for the leaf's text (often a `ParseRegex` or [ParseLiteral]()); *ws* is the trailing-whitespace parser to consume *after* the span is closed (so the span covers the token only); *build* is the leaf constructor, e.g. `LeafNode["Integer", #, <||>] &`.
- The captured span is a raw `{start, end}` pair of *1-based character offsets*, where *end* is one past the last character *token* matched - `end - start` is the token's length. The trailing whitespace *ws* is eaten *outside* the two [ParsePosition]()s, so it never widens the span.
- A non-node *build* result passes through *unstamped*: when the grammar runs over a semantic algebra, *build* returns a value (a number, say) rather than a node, and there is nothing to carry `Source`, so `SpannedToken` returns it unchanged.
- The `{start, end}` offsets here are *not yet* line/column. [ASTAddSource]() is the finalizer that spans the composites and converts every offset span to a `{{startLine, startColumn}, {endLine, endColumn}}` pair against the source.

## Basic Examples

Match an integer token, skip trailing whitespace, and build a [LeafNode]() carrying its span - `Source -> {1, 3}` is the character offsets of `"42"`:

```wl
Parse[SpannedToken[ParseRegex["[0-9]+"], ParseMany[ParseCharacter[WhitespaceCharacter]], (LeafNode["Integer", #, <||>] &)], "42"]
```

<!-- => LeafNode["Integer", "42", <|"Source" -> {1, 3}|>] -->

The span is `{start, end}` with *end* one past the last character, so `end - start` is the token length - here `3 - 1 = 2`, the two digits of `"42"`.

The trailing whitespace *ws* is consumed *outside* the span, so it never widens it - parsing `"42   "` still yields the span `{1, 3}`:

```wl
Parse[SpannedToken[ParseRegex["[0-9]+"], ParseMany[ParseCharacter[WhitespaceCharacter]], (LeafNode["Integer", #, <||>] &)], "42   "]
```

<!-- => LeafNode["Integer", "42", <|"Source" -> {1, 3}|>] -->

## Scope

A non-node *build* result passes through unstamped - when *build* returns a plain value rather than a node (as a semantic algebra would), there is nothing to carry `Source`:

```wl
Parse[SpannedToken[ParseRegex["[0-9]+"], ParseMany[ParseCharacter[WhitespaceCharacter]], (FromDigits[#] &)], "42"]
```

<!-- => 42 -->

## Properties and Relations

`SpannedToken` is the packaged form of the [ParsePosition]() bracketing pattern. The raw offsets it records are later promoted to [CodeParser]()-style line/column by [ASTAddSource]() - the two together are how a [CalculatorAST]() leaf ends up with a `{{line, col}, {line, col}}` `Source`:

```wl
CalculatorAST["1+2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

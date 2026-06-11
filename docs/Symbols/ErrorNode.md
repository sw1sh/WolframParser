---
Template: Symbol
Name: ErrorNode
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ErrorNode
Keywords: [AST, error, syntax error, error token, recovery, syntax tree, parser zoo, CodeParser]
SeeAlso: [LeafNode, ContainerNode, ASTNodeQ, ToCodeParser, Parse]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[ErrorNode]()[*kind*, *source*, *meta*]</code> is a syntax-error token: *kind* is a descriptor string naming the error, *source* is the offending text, and *meta* is a metadata association.

## Details & Options

- `ErrorNode` is inert data: it carries no [DownValues](), so building one just holds the three arguments. It mirrors `CodeParser``s own `CodeParser``ErrorNode`, the marker an error-recovering parser leaves in place of a malformed token.
- It has the same three-slot shape as a [LeafNode]() - *kind* descriptor, *source* text, *meta* - but flags a syntax error rather than a valid terminal, so a tree carrying an `ErrorNode` is still well-shaped and inspectable.
- `ErrorNode` is part of the standard vocabulary, but the five sample grammars do not do error recovery: a malformed input returns a [Failure]() from [Parse]() (reporting position, expected set and what was found) rather than producing a tree with an embedded `ErrorNode`. The examples below build the node literally to show its shape.
- *meta* holds a `"Source"` position when the node comes from a real parse, and is an empty `<||>` when you build it by hand - as in every example here.

## Basic Examples

An error node built literally holds its error descriptor and the offending source text:

```wl
ErrorNode["UnterminatedString", "\"abc", <||>]
```

<!-- => ErrorNode["UnterminatedString", "\"abc", <||>] -->

An `ErrorNode` answers [ASTNodeQ]() with [True](), so an error-recovering tree stays a valid AST:

```wl
ASTNodeQ[ErrorNode["UnterminatedString", "\"abc", <||>]]
```

<!-- => True -->

## Properties and Relations

[ToCodeParser]() has no rewrite rule for `ErrorNode`, so the node passes through unchanged - it is already the marker `CodeParser` uses, and its descriptor stays language-native:

```wl
ToCodeParser[ErrorNode["UnterminatedString", "\"abc", <||>]]
```

<!-- => ErrorNode["UnterminatedString", "\"abc", <||>] -->

---
Template: Symbol
Name: MermaidSemantic
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidSemantic
Keywords: [Mermaid, algebra, semantic, parser zoo]
SeeAlso: [MermaidGrammar, MermaidRead, MermaidAST, ASTAlgebra]
RelatedGuides: [WolframParser]
RelatedTutorials: [MermaidDiagrams, ParserZoo, ParsingBNFGrammars]
---
## Usage

[MermaidSemantic]() is the algebra that builds a Mermaid diagram as nested rules *kind* `->` `{`*part*, …`}`, with strings unquoted and numbers read.

## Details & Options

- [MermaidSemantic]() has two builders. `"Leaf"` gives the text of a token: a quoted string without its quotes, a text trimmed, with a line break where it writes `<br/>`, a number as an integer. `"Node"` gives *kind* `->` *parts* for a composite.
- [MermaidRead]() runs [MermaidGrammar]() over [MermaidSemantic]() and turns the rules into the data of the diagram.

## Basic Examples

The builders of the algebra:

```wl
Keys[MermaidSemantic]
```

<!-- => {"Leaf", "Node"} -->

A quoted string loses its quotes:

```wl
MermaidSemantic["Leaf"]["String", "\"two words\""]
```

<!-- => "two words" -->

A composite is a rule from its kind to its parts:

```wl
MermaidSemantic["Node"]["Vertex", {"A"}]
```

<!-- => "Vertex" -> {"A"} -->

## Properties & Relations

[MermaidGrammar]() over [MermaidSemantic]() parses a diagram to nested rules:

```wl
Parse[MermaidGrammar[MermaidSemantic], "graph LR\n A[one] -->|go| B"]
```

<!-- => {"Flowchart" -> {"LR", "Chain" -> {"Nodes" -> {"Vertex" -> {"A", "Rectangle" -> {"one"}}}, "Link" -> {"-->", "go"}, "Nodes" -> {"Vertex" -> {"B"}}}}} -->

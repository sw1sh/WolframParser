---
Template: Symbol
Name: MermaidGrammar
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidGrammar
Keywords: [Mermaid, grammar, algebra, EBNF, PEG, parser zoo]
SeeAlso: [MermaidEBNF, MermaidSemantic, MermaidAST, MermaidRead, EBNFParse]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserZoo, ParsingBNFGrammars]
---
## Usage

<code>[MermaidGrammar]()[*alg*]</code> builds the Mermaid parser over the algebra *alg*, an [Association]() of builder functions, from the grammar [MermaidEBNF]().

## Details & Options

- The grammar is [MermaidEBNF](), read by [EBNFParse]() in its classic dialect as a PEG; *alg* gives each rule its value. [MermaidSemantic]() builds the nested rules [MermaidRead]() turns into data, and [ASTAlgebra]() with one more builder gives the tree of [MermaidAST]().
- *alg* supplies `"Leaf"`, called with a kind (`"Identifier"`, `"Text"`, `"String"`, `"Operator"`, `"Keyword"`, `"Direction"`, `"Integer"`, `"Property"` or `"Annotation"`) and the source text, and `"Node"`, called with a kind such as `"Flowchart"`, `"Chain"` or `"Vertex"` and the list of its parts.
- Spaces and tabs are skipped between the elements of a statement; a newline or a semicolon ends a statement; a line that starts with `%%` is a comment.
- The parser gives a list: the front matter, where the source has one, and the diagram.

## Basic Examples

The parser over the meaningful algebra:

```wl
MermaidGrammar[MermaidSemantic]
```

It parses a diagram to nested rules:

```wl
Parse[MermaidGrammar[MermaidSemantic], "graph LR\n A --> B"]
```

<!-- => {"Flowchart" -> {"LR", "Chain" -> {"Nodes" -> {"Vertex" -> {"A"}}, "Link" -> {"-->"}, "Nodes" -> {"Vertex" -> {"B"}}}}} -->

## Scope

An algebra of your own gives a diagram another meaning. This one counts what a diagram holds, by kind:

```wl
counter = <|
    "Leaf" -> Function[{kind, text}, <|kind -> 1|>],
    "Node" -> Function[{kind, parts}, Merge[Append[parts, <|kind -> 1|>], Total]]
|>;
```

The links and the vertices of a chain:

```wl
First[Parse[MermaidGrammar[counter], "graph LR\n A --> B --> C"]][[{"Link", "Vertex"}]] // Normal
```

<!-- => {"Link" -> 2, "Vertex" -> 3} -->

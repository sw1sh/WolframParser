---
Template: Symbol
Name: MermaidAST
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidAST
Keywords: [Mermaid, AST, syntax tree, source positions, parser zoo]
SeeAlso: [MermaidRead, MermaidGrammar, MermaidDiagram, ASTAlgebra, ASTStripSource, CallNode, LeafNode]
RelatedGuides: [WolframParser]
RelatedTutorials: [MermaidDiagrams, ParserZoo, ParsingBNFGrammars]
---
## Usage

<code>[MermaidAST]()["*source*"]</code> parses the Mermaid diagram *source* to a standard AST: a [ContainerNode]() of one [CallNode]() for the diagram, headed by its type, holding a [CallNode]() per statement.

## Details & Options

- [MermaidAST]() runs [MermaidGrammar]() over [ASTAlgebra](): a composite is a [CallNode]() headed by a [LeafNode]() of its kind, such as `"Flowchart"`, `"Chain"`, `"Vertex"`, `"Link"`, `"Subgraph"`, `"Message"` or `"Transition"`, and a token is a [LeafNode]() of kind `"Identifier"`, `"Text"`, `"String"`, `"Operator"`, `"Keyword"`, `"Direction"` or `"Integer"`.
- Every leaf read from the source carries its `"Source"`, a `{{line, column}, {line, column}}` span; a composite spans its parts.
- A front matter is a [CallNode]() of kind `"FrontMatter"` before the diagram. Comments are left out.

## Basic Examples

The tree of a two-node flowchart:

```wl
MermaidAST["graph LR\n A --> B"]
```

The same tree without its source positions:

```wl
ASTStripSource @ MermaidAST["graph LR\n A --> B"]
```

## Scope

The identifiers of a diagram, each with its span in the source:

```wl
Cases[MermaidAST["graph LR\n A[one] --> B"], LeafNode["Identifier", name_, meta_] :> name -> meta["Source"], Infinity]
```

<!-- => {"A" -> {{2, 2}, {2, 3}}, "B" -> {{2, 13}, {2, 14}}} -->

The kinds of statement of a sequence diagram:

```wl
Cases[MermaidAST["sequenceDiagram\n participant A\n A ->> B: hi\n Note over A,B: both"], CallNode[LeafNode["Symbol", kind_, _], _, _] :> kind, {4}]
```

<!-- => {"Participant", "Message", "Note"} -->

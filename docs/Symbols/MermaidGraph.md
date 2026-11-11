---
Template: Symbol
Name: MermaidGraph
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidGraph
Keywords: [Mermaid, graph, flowchart, state diagram, class diagram, vertices, edges]
SeeAlso: [MermaidDiagram, MermaidRead, Graph]
RelatedGuides: [WolframParser]
RelatedTutorials: [MermaidDiagrams, ParserZoo, ParsingBNFGrammars]
---
## Usage

<code>[MermaidGraph]()["*source*"]</code> gives the [Graph]() of a Mermaid flowchart, state diagram or class diagram: its nodes as vertices and its links as directed edges.

<code>[MermaidGraph]()[*data*]</code> takes the diagram [MermaidRead]() gave.

## Details & Options

- The vertices are the names of the nodes, states or classes, labeled with their text; the edges are the links, transitions or relations, labeled with theirs.
- The graph is laid out in layers along the diagram's direction.
- [MermaidGraph]() takes the options of [Graph]().
- [MermaidDiagram]() draws a diagram with its shapes, groups and styles; [MermaidGraph]() is the diagram to compute with.

## Basic Examples

The graph of a flowchart:

```wl
g = MermaidGraph["graph LR
    A[Start] --> B{Ready?}
    B -->|yes| C([Go])
    B -->|no| A"]
```

Its vertices are the names of the nodes:

```wl
VertexList[g]
```

<!-- => {"A", "B", "C"} -->

The graph has a cycle:

```wl
AcyclicGraphQ[g]
```

<!-- => False -->

## Scope

The graph of a state diagram:

```wl
MermaidGraph["stateDiagram-v2
    [*] --> Still
    Still --> Moving
    Moving --> Crash
    Moving --> Still"]
```

The classes a class inherits from, by a path in the graph of a class diagram:

```wl
FindShortestPath[MermaidGraph["classDiagram
    Animal <|-- Mammal
    Mammal <|-- Dog
    Animal <|-- Bird"], "Animal", "Dog"]
```

<!-- => {"Animal", "Mammal", "Dog"} -->

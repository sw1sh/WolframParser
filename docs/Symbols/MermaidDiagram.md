---
Template: Symbol
Name: MermaidDiagram
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidDiagram
Keywords: [Mermaid, diagram, flowchart, sequence diagram, state diagram, class diagram, graph layout, Markdown, light and dark]
SeeAlso: [MermaidRead, MermaidGraph, MermaidAST, MermaidGrammar, MermaidEBNF, Graphics]
RelatedGuides: [WolframParser]
RelatedTutorials: [MermaidDiagrams, ParserZoo, ParsingBNFGrammars]
---
## Usage

<code>[MermaidDiagram]()["*source*"]</code> draws the Mermaid diagram *source* as [Graphics]().

<code>[MermaidDiagram]()[*data*]</code> draws the diagram [MermaidRead]() gave.

## Details & Options

- [MermaidDiagram]() draws flowcharts (`graph`, `flowchart`), sequence diagrams (`sequenceDiagram`), state diagrams (`stateDiagram`, `stateDiagram-v2`) and class diagrams (`classDiagram`). The source is read by [MermaidRead](), whose parser [EBNFParse]() generates from the grammar [MermaidEBNF](); nothing leaves the kernel.
- A flowchart, a state diagram and a class diagram are laid out in layers along the diagram's direction, `TB`, `BT`, `LR` or `RL`: links point down the layers, the boxes of a layer are ordered so that few links cross, and a link over several layers bends around the boxes between. A subgraph, a composite state and a namespace are laid out by themselves and placed as one box, with a frame and a title.
- A flowchart node has the shape its brackets give it: `[ ]` a rectangle, `( )` rounded, `([ ])` a stadium, `{ }` a diamond, `(( ))` a circle, `((( )))` a double circle, `[[ ]]` a subroutine, `[( )]` a cylinder, `{{ }}` a hexagon, `> ]` a flag, `[/ /]` and `[\ \]` parallelograms, `[/ \]` and `[\ /]` trapezoids. A link is normal, thick (`==>`) or dotted (`-.->`), ends in an arrow, a circle (`--o`), a cross (`--x`) or nothing (`---`), and carries its text at its middle.
- `classDef`, `class`, `:::`, `style` and `linkStyle` color a flowchart: `fill`, `stroke`, `stroke-width`, `stroke-dasharray` and `color` are applied, with colors as `#rgb`, `#rrggbb`, `rgb(r, g, b)` or a common name.
- A sequence diagram is a column for each participant and a row for each message, with activations, notes, numbered messages (`autonumber`) and the frames of `loop`, `alt`, `opt`, `par`, `critical`, `break` and `rect` blocks.
- The colors of a drawing are [LightDarkSwitched]() values, so it suits a light and a dark notebook. Text on a face a style colors is dark on a light face and light on a dark one.
- One unit of the drawing is one printer's point at its natural [ImageSize](); font sizes are fractions of the width, so the text keeps its place at any size. Text is measured from a table of character widths: a drawing is the same with and without a front end.
- [MermaidDiagram]() takes the options of [Graphics](). A source that does not parse gives the [Failure]() of [Parse]() and the message MermaidRead::syntax.

## Basic Examples

A flowchart, from top to bottom:

```wl
MermaidDiagram["graph TD
    A[Markdown source] --> B{Mermaid block?}
    B -->|yes| C([MermaidRead])
    B -- no --> D[Other cells]
    C --> E[(Grammar)]
    E --> F((Graphics))"]
```

A subgraph is a group with a frame and a title:

```wl
MermaidDiagram["flowchart LR
    start((Start)) --> build[Build]
    subgraph checks [Checks]
        build --> test{Tests pass?}
        test -->|yes| docs[/Build docs/]
    end
    test -->|no| fix>Fix it]
    fix --> build
    docs ==> done(((Done)))"]
```

## Scope

### Flowcharts

The shapes of nodes:

```wl
MermaidDiagram["graph LR
    a[rectangle] --> b(rounded) --> c([stadium]) --> d{diamond} --> e((circle))
    f[[subroutine]] --> g[(cylinder)] --> h{{hexagon}} --> i>flag] --> j[/parallelogram/] --> k[/trapezoid\\]"]
```

The lines and the ends of links, and their text:

```wl
MermaidDiagram["graph LR
    A -->|arrow| B
    A ---|open| C
    A -.->|dotted| D
    A ==>|thick| E
    A --o F
    A --x G
    A <--> H"]
```

`&` links every node on one side to every node on the other, and a chain of links is one statement:

```wl
MermaidDiagram["graph TD
    A & B --> C --> D & E"]
```

Subgraphs nest, and a link may end at a subgraph:

```wl
MermaidDiagram["graph TD
    subgraph outer [Outer]
        subgraph inner [Inner]
            A --> B
        end
        B --> C
    end
    C --> D
    D --> outer"]
```

Classes and styles color nodes and links:

```wl
MermaidDiagram["graph LR
    A:::good --> B --> C:::bad
    classDef good fill:#d4f7d4,stroke:#2e8b57
    classDef bad fill:#fdd,stroke:#c33,stroke-width:2px
    style B fill:#ffe9a8,stroke:#b8860b
    linkStyle 1 stroke:#c33,stroke-width:2px"]
```

### Sequence diagrams

Participants, messages, an activation, a note and blocks:

```wl
MermaidDiagram["sequenceDiagram
    autonumber
    actor U as User
    participant M as Converter
    participant P as Parser
    U ->> M: build the docs
    M ->> +P: MermaidDiagram[source]
    Note right of P: reads the grammar once
    P -->> -M: Graphics
    alt it parses
        M -->> U: notebook
    else it does not
        M --x U: Failure
    end"]
```

### State diagrams

States, transitions, a composite state, a choice and a note:

```wl
MermaidDiagram["stateDiagram-v2
    [*] --> Idle
    Idle --> Parsing : source arrives
    state Parsing {
        [*] --> Lexing
        Lexing --> Grammar : tokens
        Grammar --> [*]
    }
    state check <<choice>>
    Parsing --> check
    check --> Drawing : parsed
    check --> Idle : syntax error
    Drawing --> [*]
    note right of Drawing : layered layout"]
```

### Class diagrams

Classes with their members, and the relations between them:

```wl
MermaidDiagram["classDiagram
    class Shape {
        <<abstract>>
        +String name
        +area() float
    }
    class Circle {
        +float radius
    }
    Shape <|-- Circle
    Shape <|-- Square
    Canvas \"1\" *-- \"many\" Shape : holds
    Canvas ..> Renderer : uses"]
```

## Options

[MermaidDiagram]() takes the options of [Graphics](); here a smaller [ImageSize]():

```wl
MermaidDiagram["graph LR
    A --> B --> C", ImageSize -> 200]
```

## Properties & Relations

[MermaidDiagram]() of a source is [MermaidDiagram]() of what [MermaidRead]() reads from it:

```wl
MermaidDiagram["graph LR\n A --> B"] === MermaidDiagram[MermaidRead["graph LR\n A --> B"]]
```

<!-- => True -->

[MermaidGraph]() gives the same diagram as a [Graph](), to compute with:

```wl
MermaidGraph["graph LR\n A --> B --> C\n A --> C"]
```

## Possible Issues

A diagram that does not parse gives a [Failure]() with the position where reading stopped:

```wl
MermaidDiagram["graph TD\n A --> "]
```

<!-- => the message MermaidRead::syntax is issued and the Failure of Parse is returned -->

A diagram type that is not read is a [Failure]() too:

```wl
MermaidDiagram["pie\n \"a\" : 1"]
```

<!-- => the message MermaidRead::syntax is issued and the Failure of Parse is returned -->

---
Template: Symbol
Name: MermaidRead
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidRead
Keywords: [Mermaid, diagram, flowchart, sequence diagram, state diagram, class diagram, reader, parser zoo]
SeeAlso: [MermaidDiagram, MermaidGraph, MermaidAST, MermaidGrammar, MermaidSemantic, MermaidEBNF]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserZoo, ParsingBNFGrammars]
---
## Usage

<code>[MermaidRead]()["*source*"]</code> reads the Mermaid diagram *source* to plain Wolfram data, an [Association]() of its type and what a diagram of that type holds.

## Details & Options

- The source is read by [MermaidGrammar](), which [EBNFParse]() generates from the grammar [MermaidEBNF](), over the algebra [MermaidSemantic]().
- `"Type"` is `"Flowchart"`, `"Sequence"`, `"State"` or `"Class"`, and `"Title"` the title a front matter or a `title` statement gives, or [None]().
- A flowchart has `"Direction"` (`"TB"`, `"BT"`, `"LR"` or `"RL"`), `"Nodes"` by name, each with its `"Label"`, `"Shape"`, `"Classes"`, `"Style"` and `"Parent"`, the subgraph that holds it; `"Edges"`, each with `"From"`, `"To"`, `"Line"` (`"Normal"`, `"Thick"`, `"Dotted"` or `"Invisible"`), `"Head"` and `"Tail"` (`"Arrow"`, `"Circle"`, `"Cross"` or `"None"`), `"Length"`, `"Label"` and `"Style"`; `"Subgraphs"` by name, each with its `"Title"`, `"Parent"` and `"Direction"`; and `"ClassDefinitions"`.
- A sequence diagram has `"Participants"` by name, each with its `"Label"` and `"Kind"` (`"Participant"` or `"Actor"`), `"Autonumber"`, and `"Events"` in order: an `"Event"` is `"Message"`, `"Note"`, `"Activate"`, `"Deactivate"`, `"BlockStart"`, `"BlockBranch"` or `"BlockEnd"`.
- A state diagram has `"Direction"`, `"States"` by name, each with its `"Label"`, `"Kind"` (`"State"`, `"Start"`, `"End"`, `"Choice"`, `"Fork"`, `"Join"` or `"Composite"`), `"Descriptions"` and `"Parent"`, `"Transitions"` and `"Notes"`. `[*]` is the start of its scope where a transition leaves it and the end where one enters it.
- A class diagram has `"Direction"`, `"Classes"` by name, each with its `"Label"`, `"Annotations"`, `"Attributes"`, `"Methods"` and `"Parent"`, its namespace; `"Relations"`, each with `"From"`, `"To"`, `"Line"`, `"Head"`, `"Tail"`, `"Label"`, `"FromLabel"` and `"ToLabel"`; `"Namespaces"` and `"Notes"`.
- A node belongs to the innermost subgraph whose body first names it. A quoted label holds any characters, and `<br/>` in a label is a line break.
- A line that starts with `%%` is a comment. `click` statements, `accTitle` and `accDescr` are read and left out of the data.
- A source that does not parse gives the [Failure]() of [Parse]() and the message MermaidRead::syntax.

## Basic Examples

A flowchart as data:

```wl
chart = MermaidRead["graph LR
    A[Start] --> B{Ready?}
    B -->|yes| C([Go])"]
```

Its nodes by name:

```wl
Keys[chart["Nodes"]]
```

<!-- => {"A", "B", "C"} -->

The shape of each node:

```wl
Normal[chart["Nodes"][[All, "Shape"]]]
```

<!-- => {"A" -> "Rectangle", "B" -> "Diamond", "C" -> "Stadium"} -->

The label of its second edge:

```wl
chart["Edges"][[2, "Label"]]
```

<!-- => "yes" -->

## Scope

A subgraph holds the nodes its body names:

```wl
Normal[MermaidRead["graph TD
    A --> B
    subgraph group [A group]
        B --> C
    end"]["Nodes"][[All, "Parent"]]]
```

<!-- => {"A" -> None, "B" -> "group", "C" -> "group"} -->

The events of a sequence diagram:

```wl
Lookup[MermaidRead["sequenceDiagram
    Alice ->> +Bob: Hello
    Note right of Bob: thinks
    Bob -->> -Alice: Hi"]["Events"], "Event"]
```

<!-- => {"Message", "Activate", "Note", "Message", "Deactivate"} -->

The transitions of a state diagram, `[*]` read as the start and the end:

```wl
Values /@ MermaidRead["stateDiagram-v2
    [*] --> Still
    Still --> Moving : go
    Moving --> [*]"]["Transitions"]
```

<!-- => {{"root_start", "Still", None}, {"Still", "Moving", "go"}, {"Moving", "root_end", None}} -->

The members of a class:

```wl
Normal[MermaidRead["classDiagram
    class Animal {
        +String name
        +eat(food) void
    }
    Animal <|-- Dog"]["Classes", "Animal"][[{"Attributes", "Methods"}]]]
```

<!-- => {"Attributes" -> {"+String name"}, "Methods" -> {"+eat(food) void"}} -->

## Properties & Relations

[MermaidDiagram]() draws the data:

```wl
MermaidDiagram[chart]
```

[MermaidAST]() describes the same source as a syntax tree, each leaf with its place in the source:

```wl
MermaidAST["graph LR\n A --> B"]
```

## Possible Issues

A link needs a node at each end:

```wl
MermaidRead["graph TD\n A --> "]
```

<!-- => the message MermaidRead::syntax is issued and the Failure of Parse is returned -->

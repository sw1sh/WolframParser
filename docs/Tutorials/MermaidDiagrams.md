---
Template: TechNote
Name: MermaidDiagrams
Title: Drawing Mermaid Diagrams
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/MermaidDiagrams
Description: "A gallery of Mermaid diagrams drawn in the kernel: flowcharts, sequence diagrams, state diagrams and class diagrams, read by a grammar and laid out as Graphics, then the same diagrams as data and as graphs."
Keywords: [Mermaid, diagram, flowchart, sequence diagram, state diagram, class diagram, subgraph, graph layout, Markdown, light and dark]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserZoo, ParsingBNFGrammars, BuildingLanguageFrontEnds]
---

## What this note covers

Mermaid is the diagram language of Markdown documents: a header line names the kind of diagram, and each line after it is one statement. [MermaidDiagram]() draws such a text as [Graphics](). The text is read by a parser that [EBNFParse]() generates from the grammar [MermaidEBNF](), and the drawing is laid out in the kernel: no browser, no web service.

This note is a gallery first. It draws flowcharts, sequence diagrams, state diagrams and class diagrams, small ones that show one feature each and a larger one of each kind. Then it takes the same diagrams as data, with [MermaidRead](), and as graphs to compute with, with [MermaidGraph](). It ends with what is not read or not drawn.

Every drawing takes its colors from the notebook's appearance, light or dark, and its text keeps its place at any size.

```wl
MermaidDiagram["flowchart TD
    md[Markdown file] --> block{Mermaid block?}
    block -->|yes| read([MermaidRead])
    block -->|no| other[Other cells]
    subgraph parser [Wolfram/Parser]
        read --> grammar[(Grammar)]
        grammar ==> layout[[Layered layout]]
        layout -.-> drawing((Graphics))
    end
    drawing --> cell[/Notebook cell/]
    other --> cell"]
```

## Flowcharts

A flowchart starts with `flowchart` or `graph` and a direction. `TD` runs from the top down:

```wl
MermaidDiagram["flowchart TD
    Idea --> Draft
    Draft --> Review
    Review --> Publish"]
```

`LR` runs from left to right. `BT` and `RL` run the other two ways:

```wl
MermaidDiagram["flowchart LR
    Idea --> Draft --> Review --> Publish"]
```

### Shapes

The brackets around a node's text give its shape. Each row here is one chain:

```wl
MermaidDiagram["flowchart LR
    a[Rectangle] --> b(Rounded) --> c([Stadium]) --> d{Diamond}
    e((Circle)) --> f(((Double))) --> g[[Subroutine]] --> h[(Cylinder)]
    i{{Hexagon}} --> j>Flag] --> k[/Parallelogram/] --> l(-Ellipse-)"]
```

A decision is a diamond, a store a cylinder, a start and an end a stadium:

```wl
MermaidDiagram["flowchart TD
    start([Request]) --> cached{In cache?}
    cached -->|hit| serve[Serve it]
    cached -->|miss| db[(Database)]
    db --> fill[Fill the cache]
    fill --> serve
    serve --> done([Response])"]
```

### Links

A link is normal, thick or dotted. It ends in an arrow, a circle, a cross, or nothing, at one end or at both, and it carries its text at its middle:

```wl
MermaidDiagram["flowchart LR
    hub((Hub)) -->|arrow| a[One]
    hub ---|open| b[Two]
    hub -.->|dotted| c[Three]
    hub ==>|thick| d[Four]
    hub --o|circle| e[Five]
    hub --x|cross| f[Six]
    hub <-->|both ways| g[Seven]"]
```

`&` links every node on one side to every node on the other, so three lines draw a small network:

```wl
MermaidDiagram["flowchart TD
    in1[Input A] & in2[Input B] & in3[Input C] --> h1((H1)) & h2((H2))
    h1 & h2 --> out{{Output}}"]
```

A longer arrow is a longer link: each dash more, and each dot more in a dotted link, spans one more layer. Here the shortcut has three dots and spans three layers, beside the steps:

```wl
MermaidDiagram["flowchart TD
    A[Start] --> B[Step one]
    B --> C[Step two]
    C --> D[Finish]
    A -. skip ...-> D"]
```

### Subgraphs

`subgraph` and `end` put nodes in a group with a frame and a title. A link crosses a frame at the side it leaves by and bends around the boxes in its way:

```wl
MermaidDiagram["flowchart LR
    subgraph front [Front end]
        web[Web app] --> cache[(Cache)]
    end
    subgraph back [Back end]
        api[API] --> db[(Database)]
        api --> queue[[Queue]]
    end
    web --> api"]
```

Subgraphs nest, and a link may end at a subgraph itself:

```wl
MermaidDiagram["flowchart TD
    client([Client]) --> cloud
    subgraph cloud [Cloud]
        subgraph region [Region]
            lb{Balancer} --> s1[Server 1] & s2[Server 2]
        end
        s1 & s2 --> store[(Storage)]
    end
    store --> backup[(Backup)]"]
```

A subgraph that no link enters or leaves keeps a direction of its own:

```wl
MermaidDiagram["flowchart TD
    subgraph monday [Monday]
        direction LR
        m1[Plan] --> m2[Build] --> m3[Test]
    end
    subgraph tuesday [Tuesday]
        direction LR
        t1[Fix] --> t2[Ship]
    end
    monday --> tuesday"]
```

### Styles

`classDef` names a style, and three colons after a node, or a `class` statement, give it to nodes. `style` colors one node and `linkStyle` one link, counted from 0. Text on a colored face stays readable in a light and in a dark notebook:

```wl
MermaidDiagram["flowchart LR
    plan[Plan]:::calm --> build[Build]:::calm --> test{Tests?}
    test -->|pass| ship([Ship]):::good
    test -->|fail| fix[Fix]:::bad
    fix --> build
    classDef calm fill:#e3f2fd,stroke:#1e88e5
    classDef good fill:#d4f7d4,stroke:#2e8b57,stroke-width:2px
    classDef bad fill:#ffe0e0,stroke:#c62828,stroke-width:2px
    style test fill:#fff3cd,stroke:#b8860b
    linkStyle 3 stroke:#c62828,stroke-width:2px"]
```

### A release pipeline

A larger flowchart: three checks side by side in one subgraph, a decision, and two more stages:

```wl
MermaidDiagram["flowchart TD
    commit([Commit]) --> lint & unit & docs
    subgraph check [Check]
        lint[Lint]
        unit[Unit tests]
        docs[Doc examples]
    end
    lint & unit & docs --> ok{All green?}
    ok -->|yes| pack
    ok -->|no| fix[Fix and push]
    subgraph build [Build]
        pack[Pack the paclet] --> pages[Build the pages]
    end
    pages --> tag
    subgraph release [Release]
        tag[Tag] ==> publish[(Repository)]
    end
    classDef stop fill:#ffe0e0,stroke:#c62828
    classDef go fill:#d4f7d4,stroke:#2e8b57
    class fix stop
    class publish go"]
```

## Sequence diagrams

A sequence diagram starts with `sequenceDiagram`. Each participant is a column, and each message a row, in the order written. A solid arrow is a call and a dotted one a reply:

```wl
MermaidDiagram["sequenceDiagram
    Alice ->> Bob: Hello Bob, how are you?
    Bob -->> Alice: Fine, thanks
    Alice -) Bob: See you later
    Bob --x Alice: Message lost"]
```

`participant` and `actor` declare the columns and give them longer names. `+` and `-` at an arrow start and end an activation, and a note goes beside a participant or over several:

```wl
MermaidDiagram["sequenceDiagram
    actor U as User
    participant B as Browser
    participant S as Server
    U ->> B: click Sign in
    B ->> +S: POST /login
    Note right of S: checks the password
    S -->> -B: 200 and a token
    Note over U,B: the session starts
    B -->> U: welcome page"]
```

### An API call

A larger one, with numbered messages, a loop, and the two branches of an `alt`:

```wl
MermaidDiagram["sequenceDiagram
    autonumber
    actor C as Client
    participant G as Gateway
    participant A as Auth
    participant O as Orders
    participant D as Database
    C ->> +G: GET /orders
    G ->> +A: verify the token
    A -->> -G: valid
    alt token is valid
        G ->> +O: list the orders
        loop each page
            O ->> +D: select
            D -->> -O: rows
        end
        O -->> -G: orders
        G -->> C: 200 OK
    else token expired
        G -->> C: 401 Unauthorized
    end
    deactivate G"]
```

## State diagrams

A state diagram starts with `stateDiagram`, here in its second version. A star in square brackets is the start where a transition leaves it and the end where one enters it, and the text after a colon labels a transition:

```wl
MermaidDiagram["stateDiagram-v2
    [*] --> Still
    Still --> Moving : push
    Moving --> Still : brake
    Moving --> Crash : obstacle
    Crash --> [*]"]
```

A state with braces is a composite state, with a start and an end of its own. The word `choice` in double angle brackets makes a state a branch point, and a note is tied to its state:

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

### The life of an order

A state machine from left to right, with a fork into two tasks that a join brings together:

```wl
MermaidDiagram["stateDiagram-v2
    direction LR
    [*] --> Placed
    Placed --> Paid
    Placed --> Cancelled : timeout
    state split <<fork>>
    state merge <<join>>
    Paid --> split
    split --> Packing
    split --> Invoicing
    Packing --> merge
    Invoicing --> merge
    merge --> Shipped
    Shipped --> [*]
    Cancelled --> [*]"]
```

## Class diagrams

A class diagram starts with `classDiagram`. A class lists its members between braces, a member with parentheses is a method, and the line with a closed arrowhead draws inheritance toward the parent:

```wl
MermaidDiagram["classDiagram
    class Shape {
        <<abstract>>
        +String name
        +area() float
        +draw()
    }
    class Circle {
        +float radius
        +area() float
    }
    class Square {
        +float side
        +area() float
    }
    Shape <|-- Circle
    Shape <|-- Square"]
```

The ends of a line say what a relation is: a triangle for inheritance, a filled diamond for composition, an open one for aggregation, an arrow for association, and a dotted line for a dependency or a realization:

```wl
MermaidDiagram["classDiagram
    direction LR
    Vehicle <|-- Car : inheritance
    Car *-- Engine : composition
    Car o-- Driver : aggregation
    Driver --> License : association
    Car ..> Fuel : dependency
    Engine ..|> Machine : realization"]
```

### A small domain model

Multiplicities go in quotes at the ends of a relation, a name between tildes is a generic parameter, and a namespace groups its classes:

```wl
MermaidDiagram["classDiagram
    class Customer {
        +String name
        +String email
        +place(Cart cart) Order
    }
    class Order {
        +Date placed
        +List~Line~ lines
        +total() Money
    }
    class Line {
        +int quantity
        +price() Money
    }
    class Product {
        +String title
        +Money price
    }
    namespace Payments {
        class Payment {
            <<interface>>
            +pay(Money amount)
        }
        class Card
        class Transfer
    }
    Customer \"1\" --> \"*\" Order : places
    Order \"1\" *-- \"1..*\" Line : holds
    Product <-- Line
    Order ..> Payment : paid by
    Payment <|.. Card
    Payment <|.. Transfer"]
```

## Diagrams as data

[MermaidRead]() reads a diagram without drawing it. The result is an association: the type of the diagram and what a diagram of that type holds.

```wl
chart = MermaidRead["flowchart LR
    build[Build] --> test{Tests?}
    test -->|pass| ship([Ship])
    test -->|fail| build"]
```

The keys of a flowchart:

```wl
Keys[chart]
```

<!-- => {"Type", "Title", "Direction", "Nodes", "Edges", "Subgraphs", "ClassDefinitions"} -->

Its nodes, each with the shape its brackets gave it:

```wl
Normal[chart["Nodes"][[All, "Shape"]]]
```

<!-- => {"build" -> "Rectangle", "test" -> "Diamond", "ship" -> "Stadium"} -->

Its links as rules, with the text of those that carry one:

```wl
Map[(#From -> #To) -> #Label &, chart["Edges"]]
```

<!-- => {("build" -> "test") -> None, ("test" -> "ship") -> "pass", ("test" -> "build") -> "fail"} -->

[MermaidDiagram]() draws the data as it draws the text, so a diagram can be changed between reading and drawing. Here every link becomes dotted:

```wl
MermaidDiagram[MapAt[Append[#, "Line" -> "Dotted"] &, chart, {"Edges", All}]]
```

### Graphs

[MermaidGraph]() gives a flowchart, a state diagram or a class diagram as a [Graph](): the nodes are its vertices, labeled, and the links its directed edges.

```wl
g = MermaidGraph["flowchart LR
    home[Home] --> search[Search] --> product[Product]
    home --> product
    product --> cart[Cart] --> checkout[Checkout]
    checkout --> paid([Paid])
    cart --> search
    help[Help] --> faq[FAQ]"]
```

The shortest way from the home page to a paid order:

```wl
FindShortestPath[g, "home", "paid"]
```

<!-- => {"home", "product", "cart", "checkout", "paid"} -->

The diagram has two parts that no link joins:

```wl
WeaklyConnectedComponents[g]
```

<!-- => {{"home", "search", "product", "cart", "checkout", "paid"}, {"faq", "help"}} -->

And one loop, between the search, the product and the cart:

```wl
FindCycle[g]
```

<!-- => {{DirectedEdge["search", "product"], DirectedEdge["product", "cart"], DirectedEdge["cart", "search"]}} -->

### Options

[MermaidDiagram]() takes the options of [Graphics](). The natural size of a drawing is one printer's point to a unit; [ImageSize]() sets another, and the text follows:

```wl
MermaidDiagram["flowchart LR
    Small --> Diagram", ImageSize -> 160]
```

A [Background]() and a frame, as for any graphic:

```wl
MermaidDiagram["flowchart LR
    A((A)) --> B((B)) --> C((C))", Background -> LightDarkSwitched[RGBColor[0.96, 0.97, 1], RGBColor[0.1, 0.11, 0.18]], Frame -> True, FrameTicks -> None]
```

## What is not read or drawn

- Other kinds of diagram, such as pie charts, Gantt charts, entity relationship diagrams, journeys and mind maps, are not read: [MermaidRead]() gives a [Failure]() for them.
- In a flowchart: nodes whose shape is named in braces after an at sign, links with a name before the arrow, and a `%%` comment after a statement on the same line. `click` statements are read and have no effect. A label's Markdown is shown as plain text.
- In a sequence diagram: `box` groups are read and not drawn, `create` and `destroy` are read and have no effect, and the half arrows are not read.
- In a state diagram: the regions of a concurrent state, divided by a line of two dashes, are read and drawn as one region, and a note goes where the layout puts it, whatever side it names.
- In a class diagram: a generic parameter inside another, `cssClass`, and the lollipop of an interface as a shape of its own.
- A link that leaves a subgraph against the diagram's direction leaves by the far side and turns back.

A text that does not parse gives the [Failure]() of [Parse](), with the position where reading stopped, and the message MermaidRead::syntax:

```wl
MermaidDiagram["flowchart TD
    A --> "]
```

<!-- => the message MermaidRead::syntax is issued and the Failure of Parse is returned -->

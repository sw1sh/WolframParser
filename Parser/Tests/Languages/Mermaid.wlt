(* :Title: Mermaid.wlt - Mermaid tests *)
(* :Context: Wolfram`Parser`Languages`Mermaid` *)
(* :Summary: flowcharts, sequence diagrams, state diagrams and class diagrams read by MermaidRead,
   the standard AST, and the drawings of MermaidDiagram. Run via run-tests.wls. *)

(* === flowcharts: header, nodes and shapes === *)
VerificationTest[MermaidRead["graph TD\n A --> B"][[{"Type", "Direction"}]], <|"Type" -> "Flowchart", "Direction" -> "TB"|>,
    TestID -> "mermaid: graph TD is a flowchart from top to bottom"]
VerificationTest[MermaidRead["flowchart " <> # <> "\n A"]["Direction"] & /@ {"TB", "TD", "BT", "LR", "RL"}, {"TB", "TB", "BT", "LR", "RL"},
    TestID -> "mermaid: the five directions, TD read as TB"]
VerificationTest[MermaidRead["flowchart\n A"]["Direction"], "TB",
    TestID -> "mermaid: a header without a direction runs from top to bottom"]
VerificationTest[
    Values[MermaidRead["graph LR\n a[one]\n b(two)\n c([three])\n d{four}\n e((five))\n f[[six]]\n g>seven]\n h[(eight)]\n i{{nine}}\n j(((ten)))\n k[/eleven/]\n l[\\twelve\\]\n m[/thirteen\\]\n n[\\fourteen/]"]["Nodes"]][[All, "Shape"]],
    {"Rectangle", "Rounded", "Stadium", "Diamond", "Circle", "Subroutine", "Flag", "Cylinder", "Hexagon", "DoubleCircle", "Parallelogram", "ParallelogramAlt", "Trapezoid", "TrapezoidAlt"},
    TestID -> "mermaid: the brackets around a node's text give its shape"]
VerificationTest[MermaidRead["graph LR\n a[\"a (quoted) [label]\"] --> b[plain (text)]"]["Nodes"][[All, "Label"]],
    <|"a" -> "a (quoted) [label]", "b" -> "plain (text)"|>,
    TestID -> "mermaid: a quoted label holds any brackets"]
VerificationTest[MermaidRead["graph LR\n a[one<br/>two] --> b"]["Nodes", "a", "Label"], "one\ntwo",
    TestID -> "mermaid: <br/> breaks a label's line"]
VerificationTest[Keys[MermaidRead["graph LR\n node-1 --> v1.2 --> \:041f\:0440\:0438\:0432\:0435\:0442"]["Nodes"]], {"node-1", "v1.2", "\:041f\:0440\:0438\:0432\:0435\:0442"},
    TestID -> "mermaid: names hold single dashes, dots and letters of any script"]
VerificationTest[MermaidRead["graph LR\n A\n A[text]\n A --> B"]["Nodes", "A"][[{"Label", "Shape"}]], <|"Label" -> "text", "Shape" -> "Rectangle"|>,
    TestID -> "mermaid: a node is one node however often it is named"]

(* === flowcharts: links === *)
VerificationTest[
    MermaidRead["graph LR\n A --> B\n A --- B\n A -.-> B\n A ==> B\n A ~~~ B\n A -.- B\n A === B"]["Edges"][[All, {"Line", "Head"}]],
    {<|"Line" -> "Normal", "Head" -> "Arrow"|>, <|"Line" -> "Normal", "Head" -> "None"|>, <|"Line" -> "Dotted", "Head" -> "Arrow"|>,
     <|"Line" -> "Thick", "Head" -> "Arrow"|>, <|"Line" -> "Invisible", "Head" -> "None"|>, <|"Line" -> "Dotted", "Head" -> "None"|>,
     <|"Line" -> "Thick", "Head" -> "None"|>},
    TestID -> "mermaid: normal, dotted, thick and invisible links, with and without an arrow"]
VerificationTest[
    MermaidRead["graph LR\n A -->|one| B\n A -- two --> B\n A -. three .-> B\n A == four ==> B\n A -->|\"five | six\"| B"]["Edges"][[All, {"Line", "Label"}]],
    {<|"Line" -> "Normal", "Label" -> "one"|>, <|"Line" -> "Normal", "Label" -> "two"|>, <|"Line" -> "Dotted", "Label" -> "three"|>,
     <|"Line" -> "Thick", "Label" -> "four"|>, <|"Line" -> "Normal", "Label" -> "five | six"|>},
    TestID -> "mermaid: a link's text between bars or inside the arrow"]
VerificationTest[
    MermaidRead["graph LR\n A <--> B\n A --o B\n A x--x B\n A o--o B"]["Edges"][[All, {"Tail", "Head"}]],
    {<|"Tail" -> "Arrow", "Head" -> "Arrow"|>, <|"Tail" -> "None", "Head" -> "Circle"|>, <|"Tail" -> "Cross", "Head" -> "Cross"|>, <|"Tail" -> "Circle", "Head" -> "Circle"|>},
    TestID -> "mermaid: arrow, circle and cross ends, at one end or both"]
VerificationTest[MermaidRead["graph LR\n A --> B\n A ---> B\n A -----> B\n A -...-> B\n A ==== B"]["Edges"][[All, "Length"]], {1, 2, 4, 3, 2},
    TestID -> "mermaid: a longer arrow is a longer link"]
VerificationTest[{#From, #To} & /@ MermaidRead["graph LR\n A --> B --> C"]["Edges"], {{"A", "B"}, {"B", "C"}},
    TestID -> "mermaid: a chain of links"]
VerificationTest[{#From, #To} & /@ MermaidRead["graph LR\n A & B --> C & D"]["Edges"], {{"A", "C"}, {"A", "D"}, {"B", "C"}, {"B", "D"}},
    TestID -> "mermaid: & links every node on one side to every node on the other"]
VerificationTest[{#From, #To, #Head} & /@ MermaidRead["graph LR\n A --o B --> C"]["Edges"], {{"A", "B", "Circle"}, {"B", "C", "Arrow"}},
    TestID -> "mermaid: where a whole arrow can be read it is, as Mermaid's lexer reads it"]

(* === flowcharts: subgraphs, comments, statements === *)
VerificationTest[
    With[{d = MermaidRead["graph TD\n A --> B\n subgraph one [The first]\n  B --> C\n  subgraph two\n   direction LR\n   D\n  end\n end\n subgraph \"Third group\"\n  E\n end"]},
        {d["Subgraphs"][[All, {"Title", "Parent", "Direction"}]], d["Nodes"][[All, "Parent"]]}],
    {<|"one" -> <|"Title" -> "The first", "Parent" -> None, "Direction" -> None|>, "two" -> <|"Title" -> "two", "Parent" -> "one", "Direction" -> "LR"|>,
       "subGraph3" -> <|"Title" -> "Third group", "Parent" -> None, "Direction" -> None|>|>,
     <|"A" -> None, "B" -> "one", "C" -> "one", "D" -> "two", "E" -> "subGraph3"|>},
    TestID -> "mermaid: subgraphs, nested, titled and directed, hold the nodes their bodies name"]
VerificationTest[{#From, #To} & /@ MermaidRead["graph TD\n subgraph one\n A\n end\n subgraph two\n B\n end\n one --> two\n A --> two"]["Edges"],
    {{"one", "two"}, {"A", "two"}},
    TestID -> "mermaid: a link may end at a subgraph"]
VerificationTest[Keys[MermaidRead["graph TD\n subgraph one\n A\n end\n one --> B"]["Nodes"]], {"A", "B"},
    TestID -> "mermaid: a subgraph a link names is not also a node"]
VerificationTest[Keys[MermaidRead["%% first\n%%{init: {\"theme\": \"dark\"}}%%\ngraph TD\n %% a comment\n A --> B\n\n\n   %% another\n C"]["Nodes"]], {"A", "B", "C"},
    TestID -> "mermaid: a line that starts with %% is a comment, a directive among them"]
VerificationTest[Keys[MermaidRead["graph TD; A --> B; B --> C;"]["Nodes"]], {"A", "B", "C"},
    TestID -> "mermaid: a semicolon ends a statement"]
VerificationTest[MermaidRead["\n\n  graph TD\r\n  A --> B\r\n\r\n"]["Edges"] // Length, 1,
    TestID -> "mermaid: blank lines, indentation and CRLF line ends"]
VerificationTest[MermaidRead["---\ntitle: My chart\n---\ngraph TD\n A"]["Title"], "My chart",
    TestID -> "mermaid: the title of a front matter"]
VerificationTest[Keys[MermaidRead["graph TD\n endpoint --> classic --> styled"]["Nodes"]], {"endpoint", "classic", "styled"},
    TestID -> "mermaid: a name may start with a keyword"]
VerificationTest[
    With[{d = MermaidRead["graph TD\n A:::hot --> B\n classDef hot fill:#f96,stroke:#333,stroke-width:2px\n classDef cold fill:#9cf\n class B cold\n style B stroke:#f00,stroke-dasharray: 5 5\n linkStyle 0 stroke:#0f0\n click A href \"https://example.com\""]},
        {d["ClassDefinitions"], d["Nodes"][[All, {"Classes", "Style"}]], d["Edges"][[1, "Style"]]}],
    {<|"hot" -> <|"fill" -> "#f96", "stroke" -> "#333", "stroke-width" -> "2px"|>, "cold" -> <|"fill" -> "#9cf"|>|>,
     <|"A" -> <|"Classes" -> {"hot"}, "Style" -> <||>|>, "B" -> <|"Classes" -> {"cold"}, "Style" -> <|"stroke" -> "#f00", "stroke-dasharray" -> "5 5"|>|>|>,
     <|"stroke" -> "#0f0"|>},
    TestID -> "mermaid: classDef, class, :::, style and linkStyle; click is read and ignored"]
VerificationTest[Head @ MermaidRead["graph TD\n A --> "], Failure, {MermaidRead::syntax},
    TestID -> "mermaid: a link with no node after it does not parse"]
VerificationTest[Head @ MermaidRead["pie\n \"a\" : 1"], Failure, {MermaidRead::syntax},
    TestID -> "mermaid: a diagram type that is not read is a Failure"]

(* === sequence diagrams === *)
VerificationTest[
    MermaidRead["sequenceDiagram\n participant A as Alice\n actor B\n A->>B: Hello\n B-->>C: Hi"]["Participants"],
    <|"A" -> <|"Label" -> "Alice", "Kind" -> "Participant"|>, "B" -> <|"Label" -> "B", "Kind" -> "Actor"|>, "C" -> <|"Label" -> "C", "Kind" -> "Participant"|>|>,
    TestID -> "mermaid: participants declared, with an alias or as an actor, and those a message first names"]
VerificationTest[
    MermaidRead["sequenceDiagram\n A->>B: a\n A-->>B: b\n A->B: c\n A-->B: d\n A-xB: e\n A--xB: f\n A-)B: g\n A--)B: h\n A<<->>B: i"]["Events"][[All, {"Line", "Head", "Tail"}]] // Map[Values],
    {{"Solid", "Arrow", "None"}, {"Dotted", "Arrow", "None"}, {"Solid", "None", "None"}, {"Dotted", "None", "None"}, {"Solid", "Cross", "None"},
     {"Dotted", "Cross", "None"}, {"Solid", "Open", "None"}, {"Dotted", "Open", "None"}, {"Solid", "Arrow", "Arrow"}},
    TestID -> "mermaid: the arrows of a message"]
VerificationTest[
    MermaidRead["sequenceDiagram\n John Doe ->> my-service: call it\n activate my-service\n my-service -->> John Doe: done\n deactivate my-service"]["Events"][[All, "Event"]],
    {"Message", "Activate", "Message", "Deactivate"},
    TestID -> "mermaid: names with spaces and dashes, activate and deactivate"]
VerificationTest[
    Lookup[MermaidRead["sequenceDiagram\n A->>+B: go\n B-->>-A: back"]["Events"], {"Event", "Participant"}, None],
    {{"Message", None}, {"Activate", "B"}, {"Message", None}, {"Deactivate", "B"}},
    TestID -> "mermaid: + and - at an arrow activate and deactivate"]
VerificationTest[
    MermaidRead["sequenceDiagram\n Note over A,B: both\n Note right of A: one\n note left of B: other"]["Events"][[All, {"Placement", "Participants", "Text"}]] // Map[Values],
    {{"Over", {"A", "B"}, "both"}, {"RightOf", {"A"}, "one"}, {"LeftOf", {"B"}, "other"}},
    TestID -> "mermaid: notes over, right of and left of participants"]
VerificationTest[
    Lookup[MermaidRead["sequenceDiagram\n loop every minute\n  A->>B: ping\n end\n alt ok\n  B->>A: pong\n else lost\n  B-xA: nothing\n end"]["Events"], {"Event", "Kind", "Label"}, None],
    {{"BlockStart", "loop", "every minute"}, {"Message", None, None}, {"BlockEnd", None, None}, {"BlockStart", "alt", "ok"}, {"Message", None, None},
     {"BlockBranch", "else", "lost"}, {"Message", None, None}, {"BlockEnd", None, None}},
    TestID -> "mermaid: loop and alt ... else blocks"]
VerificationTest[MermaidRead["sequenceDiagram\n autonumber\n title: A talk\n A->>B: hi"][[{"Autonumber", "Title"}]], <|"Autonumber" -> True, "Title" -> "A talk"|>,
    TestID -> "mermaid: autonumber and title"]

(* === state diagrams === *)
VerificationTest[
    With[{d = MermaidRead["stateDiagram-v2\n [*] --> Still\n Still --> Moving : go\n Moving --> [*]"]},
        {d["States"][[All, "Kind"]], Values /@ d["Transitions"]}],
    {<|"root_start" -> "Start", "Still" -> "State", "Moving" -> "State", "root_end" -> "End"|>,
     {{"root_start", "Still", None}, {"Still", "Moving", "go"}, {"Moving", "root_end", None}}},
    TestID -> "mermaid: states, transitions with text, and [*] as the start and the end"]
VerificationTest[
    MermaidRead["stateDiagram-v2\n state \"Long name\" as s1\n s2 : described\n state fork1 <<fork>>\n state pick <<choice>>\n s1 --> s2"]["States"][[All, {"Label", "Kind", "Descriptions"}]] // Map[Values],
    <|"s1" -> {"Long name", "State", {}}, "s2" -> {"s2", "State", {"described"}}, "fork1" -> {"fork1", "Fork", {}}, "pick" -> {"pick", "Choice", {}}|>,
    TestID -> "mermaid: state declarations: a text, a description, a fork and a choice"]
VerificationTest[
    MermaidRead["stateDiagram-v2\n [*] --> Outer\n state Outer {\n  [*] --> In\n  In --> [*]\n }"]["States"][[All, {"Kind", "Parent"}]] // Map[Values],
    <|"root_start" -> {"Start", None}, "Outer" -> {"Composite", None}, "Outer_start" -> {"Start", "Outer"}, "In" -> {"State", "Outer"}, "Outer_end" -> {"End", "Outer"}|>,
    TestID -> "mermaid: a composite state has a start and an end of its own"]
VerificationTest[
    MermaidRead["stateDiagram\n direction LR\n A --> B\n note right of A : short\n note left of B\n  two\n  lines\n end note"][[{"Direction", "Notes"}]],
    <|"Direction" -> "LR", "Notes" -> {<|"State" -> "A", "Side" -> "Right", "Text" -> "short"|>, <|"State" -> "B", "Side" -> "Left", "Text" -> "two\nlines"|>}|>,
    TestID -> "mermaid: the direction of a state diagram and its notes, on one line or up to end note"]

(* === class diagrams === *)
VerificationTest[
    MermaidRead["classDiagram\n class Animal {\n  <<abstract>>\n  +String name\n  +eat(food) void\n }\n Animal : +int age\n Animal : +sleep()"]["Classes", "Animal"][[{"Annotations", "Attributes", "Methods"}]],
    <|"Annotations" -> {"abstract"}, "Attributes" -> {"+String name", "+int age"}, "Methods" -> {"+eat(food) void", "+sleep()"}|>,
    TestID -> "mermaid: the members of a class, in its braces or after a colon; one with parentheses is a method"]
VerificationTest[
    MermaidRead["classDiagram\n A <|-- B\n A *-- C\n A o-- D\n A --> E\n A ..> F\n A ..|> G\n A -- H\n A .. I"]["Relations"][[All, {"To", "Line", "Tail", "Head"}]] // Map[Values],
    {{"B", "Solid", "Triangle", "None"}, {"C", "Solid", "Diamond", "None"}, {"D", "Solid", "DiamondOpen", "None"}, {"E", "Solid", "None", "Open"},
     {"F", "Dotted", "None", "Open"}, {"G", "Dotted", "None", "Triangle"}, {"H", "Solid", "None", "None"}, {"I", "Dotted", "None", "None"}},
    TestID -> "mermaid: inheritance, composition, aggregation, association, dependency and realization"]
VerificationTest[
    MermaidRead["classDiagram\n Customer \"1\" --> \"*\" Order : places"]["Relations"][[1, {"FromLabel", "ToLabel", "Label"}]],
    <|"FromLabel" -> "1", "ToLabel" -> "*", "Label" -> "places"|>,
    TestID -> "mermaid: the multiplicities and the text of a relation"]
VerificationTest[
    With[{d = MermaidRead["classDiagram\n direction LR\n class List~T~ {\n  +add(T item)\n  +List~T~ rest\n }\n <<interface>> Shape\n namespace Geometry {\n  class Shape\n  class Circle\n }\n note for Shape \"a note\""]},
        {d["Direction"], d["Classes"][[All, "Label"]], d["Classes", "List", "Attributes"], d["Classes", "Shape", "Annotations"], d["Classes"][[All, "Parent"]], d["Notes"]}],
    {"LR", <|"List" -> "List<T>", "Shape" -> "Shape", "Circle" -> "Circle"|>, {"+List<T> rest"}, {"interface"},
     <|"List" -> None, "Shape" -> None, "Circle" -> "Geometry"|>, {<|"Class" -> "Shape", "Text" -> "a note"|>}},
    TestID -> "mermaid: generic classes, annotations, namespaces and notes"]

(* === the standard AST === *)
VerificationTest[
    ASTStripSource @ MermaidAST["graph LR\n A[one] --> B"],
    ContainerNode["String", {CallNode[LeafNode["Symbol", "Flowchart", <||>], {
        LeafNode["Direction", "LR", <||>],
        CallNode[LeafNode["Symbol", "Chain", <||>], {
            CallNode[LeafNode["Symbol", "Nodes", <||>], {CallNode[LeafNode["Symbol", "Vertex", <||>], {LeafNode["Identifier", "A", <||>],
                CallNode[LeafNode["Symbol", "Rectangle", <||>], {LeafNode["Text", "one", <||>]}, <||>]}, <||>]}, <||>],
            CallNode[LeafNode["Symbol", "Link", <||>], {LeafNode["Operator", "-->", <||>]}, <||>],
            CallNode[LeafNode["Symbol", "Nodes", <||>], {CallNode[LeafNode["Symbol", "Vertex", <||>], {LeafNode["Identifier", "B", <||>]}, <||>]}, <||>]
        }, <||>]}, <||>]}, <||>],
    TestID -> "mermaid: the standard AST of a flowchart"]
VerificationTest[
    Cases[MermaidAST["graph LR\n A[one] --> B"], LeafNode["Identifier" | "Operator", text_, meta_] :> {text, meta["Source"]}, Infinity],
    {{"A", {{2, 2}, {2, 3}}}, {"-->", {{2, 9}, {2, 12}}}, {"B", {{2, 13}, {2, 14}}}},
    TestID -> "mermaid: the leaves of the AST carry their place in the source"]
VerificationTest[
    Cases[MermaidAST[#], CallNode[LeafNode["Symbol", kind_, _], _, _] :> kind, {2}] & /@ {"sequenceDiagram\n A->>B: hi", "stateDiagram-v2\n A --> B", "classDiagram\n A <|-- B"},
    {{"Sequence"}, {"State"}, {"Class"}},
    TestID -> "mermaid: the AST of each diagram type is headed by its type"]
VerificationTest[Parse[MermaidGrammar[MermaidSemantic], "graph LR\n A --> B"],
    {"Flowchart" -> {"LR", "Chain" -> {"Nodes" -> {"Vertex" -> {"A"}}, "Link" -> {"-->"}, "Nodes" -> {"Vertex" -> {"B"}}}}},
    TestID -> "mermaid: the grammar over the meaningful algebra gives nested rules"]
VerificationTest[StringQ[MermaidEBNF] && AllTrue[{"<Mermaid>", "<Flowchart>", "<Sequence>", "<State>", "<Class>"}, StringContainsQ[MermaidEBNF, # <> " "] &] && ! FailureQ[EBNFRules[MermaidEBNF, "Dialect" -> "Classic"]],
    True, TestID -> "mermaid: MermaidEBNF is a classic grammar with a rule for each diagram type"]

(* === the drawings === *)
VerificationTest[
    Head /@ {
        MermaidDiagram["graph TD\n A[Start] --> B{Choice}\n B -->|yes| C([End])\n B -- no --> A\n subgraph group [A group]\n  C --> D[(Data)]\n end\n D --> D"],
        MermaidDiagram["sequenceDiagram\n autonumber\n actor U\n U->>+S: ask\n Note right of S: thinks\n loop twice\n  S->>S: work\n end\n S-->>-U: answer"],
        MermaidDiagram["stateDiagram-v2\n [*] --> A\n state A {\n  [*] --> B\n }\n A --> [*]\n note right of A : a note"],
        MermaidDiagram["classDiagram\n class A {\n  +x\n  +f()\n }\n A <|-- B\n A \"1\" *-- \"n\" C : has"]
    },
    {Graphics, Graphics, Graphics, Graphics},
    TestID -> "mermaid: each diagram type draws as Graphics"]
VerificationTest[
    With[{g = MermaidDiagram["graph " <> # <> "\n A --> B --> C"]}, #2 > #1 & @@ Flatten[Differences /@ (PlotRange /. Options[g, PlotRange])]] & /@ {"TB", "LR"},
    {True, False},
    TestID -> "mermaid: a chain is tall from top to bottom and wide from left to right"]
VerificationTest[
    With[{g = MermaidDiagram["graph TD\n A --> B"]}, {! FreeQ[g, _LightDarkSwitched], FreeQ[g, Black | White | GrayLevel[0] | GrayLevel[1]]}],
    {True, True},
    TestID -> "mermaid: a drawing's colors switch with the notebook's appearance, none pinned to black or white"]
VerificationTest[
    With[{g = MermaidDiagram["graph TD\n A --> B\n style A fill:#ff0000,stroke:#00ff00"]}, {! FreeQ[g, RGBColor[1., 0., 0.]], ! FreeQ[g, RGBColor[0., 1., 0.]]}],
    {True, True},
    TestID -> "mermaid: a style statement colors its node"]
VerificationTest[MermaidDiagram["graph LR\n A --> B\n B --> C\n C --> A"] === MermaidDiagram[MermaidRead["graph LR\n A --> B\n B --> C\n C --> A"]],
    True, TestID -> "mermaid: a diagram draws the same from its source and from its data, cycles included"]
VerificationTest[Options[MermaidDiagram["graph LR\n A --> B", ImageSize -> 300], ImageSize], {ImageSize -> 300},
    TestID -> "mermaid: MermaidDiagram takes the options of Graphics"]
VerificationTest[Head @ MermaidDiagram["graph TD\n A --> "], Failure, {MermaidRead::syntax},
    TestID -> "mermaid: a diagram that does not parse draws as its Failure"]
VerificationTest[
    With[{g = MermaidGraph["graph LR\n A[one] -->|go| B\n B --> C"]}, {VertexList[g], EdgeList[g], AnnotationValue[{g, "A"}, VertexLabels]}],
    {{"A", "B", "C"}, {DirectedEdge["A", "B"], DirectedEdge["B", "C"]}, "one"},
    TestID -> "mermaid: MermaidGraph gives the Graph of a flowchart"]
VerificationTest[
    EdgeList /@ {MermaidGraph["stateDiagram-v2\n A --> B"], MermaidGraph["classDiagram\n A <|-- B"]},
    {{DirectedEdge["A", "B"]}, {DirectedEdge["A", "B"]}},
    TestID -> "mermaid: MermaidGraph of a state diagram and of a class diagram"]

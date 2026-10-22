---
Template: Symbol
Name: WolframLanguageConcrete
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageConcrete
Keywords: [Wolfram Language, concrete syntax tree, CST, CodeParser, CodeConcreteParse, trivia, comments, whitespace, source, boxes, parser zoo]
SeeAlso: [WolframLanguageAST, WolframLanguageHeld, WolframLanguageGrammar, ASTStripSource, ParseOperatorTable]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageConcrete]()[*code*]</code> parses the Wolfram Language source string *code* to its concrete syntax tree, as `CodeParser``CodeConcreteParse` gives it.

<code>[WolframLanguageConcrete]()[[File]()[*file*]]</code> parses the text of *file*, read as UTF-8.

## Details & Options

- The tree is [CodeParser]()'s, in its own nodes: a `ContainerNode` of the top-level expressions and the whitespace, newlines and comments around them, each operator named by the head CodeParser names it with (`Plus`, `CodeParser``BinaryAt`, `CodeParser``InfixInequality`) and each token by its own symbol (`Token``Plus`, `Token``LongName``Rule`).
- Every character of *code* is in a leaf: the texts of the leaves, joined, are *code*. A number, a string and a name keep the text they are written with.
- Whitespace, newlines and comments sit in the smallest node around them. A token stands for what was left out: `Token``Fake``ImplicitTimes` between the factors of `a b`, `Token``Fake``ImplicitNull` after a final `;`, `Token``Fake``ImplicitOne` and `Token``Fake``ImplicitAll` in a span left open.
- Outside brackets a newline ends an expression wherever the expression could end, but for a chain of one operator (`a + b`, `a; b`, `a::b`, `a == b`), the second `~` of `a ~f~ b` and the `=` of `t /: lhs = rhs`, which continue past it, as CodeParser's do. [WolframLanguageHeld]() reads such source as the kernel does, which ends them at the newline.
- Every node carries `CodeParser``Source` <code>-> {{*line*, *column*}, {*line*, *column*}}</code>, the second just past the node; a token for what was left out takes no room. The container lists where the tokens are that hold a line continuation, as `"SimpleLineContinuations"` outside a string and `"ComplexLineContinuations"` inside one, and the strings and comments that hold a newline (`"EmbeddedNewlines"`) or a tab (`"EmbeddedTabs"`).
- The container of <code>[File]()[*file*]</code> is a `File` one whose `"FileName"` is the full path of *file*.
- The binding powers are those [WolframLanguageGrammar]() uses, CodeParser's published precedences, and the tokens are its tokens.
- CodeParser's `SyntaxIssues`, the diagnostics it adds to the container (a remark on each character past ASCII, for one), are not given. A line continuation outside a string is not read.
- Source that cannot be read gives a <code>[Failure]()["ParseError", ...]</code> whose `"Position"` is the character offset in *code* where reading stopped.

## Basic Examples

The concrete syntax tree of a sum, every node with its source:

```wl
WolframLanguageConcrete["a + 1"]
```

Without the source, the structure reads more easily:

```wl
ASTStripSource[WolframLanguageConcrete["f[x_] := x^2"]]
```

## Scope

A comment and the newline after an expression are leaves of the container:

```wl
ASTStripSource[WolframLanguageConcrete["f[x] (* a call *)\n"]]
```

A product written without a `*` holds the token for it:

```wl
ASTStripSource[WolframLanguageConcrete["2 x"]]
```

A newline ends an expression that can end there, so these are two:

```wl
ASTStripSource[WolframLanguageConcrete["a\n+ b"]]
```

A sum continues past a newline before its next `+`, as CodeParser reads it:

```wl
ASTStripSource[WolframLanguageConcrete["a + b\n+ c"]]
```

A source file of the paclet:

```wl
brainfuck = FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages", "Brainfuck.wl"}];
```

Its container is a `File` one:

```wl
First[WolframLanguageConcrete[File[brainfuck]]]
```

<!-- => File -->

It names the file:

```wl
FileNameTake[WolframLanguageConcrete[File[brainfuck]][[3, "FileName"]]]
```

<!-- => "Brainfuck.wl" -->

## Properties and Relations

A source of two definitions:

```wl
source = "f[x_] := (* square *) x^2\ng[y_] := y + 1"
```

<!-- => "f[x_] := (* square *) x^2\ng[y_] := y + 1" -->

Its leaves hold it, every character:

```wl
StringJoin[Cases[WolframLanguageConcrete[source], CodeParser`LeafNode[_, s_String, _] :> s, Infinity]] === source
```

<!-- => True -->

With CodeParser loaded, the tree is the one it gives:

```wl
Needs["CodeParser`"];
```

```wl
WolframLanguageConcrete[source] === CodeParser`CodeConcreteParse[source]
```

<!-- => True -->

CodeParser makes the boxes of an input cell from the tree, as a front end lays the input out:

```wl
CodeParser`ToStandardFormBoxes[CodeParser`ContainerNode[Box, WolframLanguageConcrete["f[x_] := x^2"][[2]], <||>]]
```

<!-- => RowBox[{RowBox[{"f", "[", "x_", "]"}], " ", ":=", " ", RowBox[{"x", "^", "2"}]}] -->

[WolframLanguageAST]() reads the same source to a standard syntax tree, operators named by strings:

```wl
ASTStripSource[WolframLanguageAST["a + 1"]]
```

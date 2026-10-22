---
Template: Symbol
Name: WolframLanguageConcrete
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageConcrete
Keywords: [Wolfram Language, concrete syntax tree, CST, CodeParser, CodeConcreteParse, trivia, comments, whitespace, source, boxes, long names, parser zoo]
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
- The binding powers are those [WolframLanguageGrammar]() uses, CodeParser's published precedences, and the tokens are its tokens. Every long name that is an operator reads as CodeParser reads it, at CodeParser's precedence for it, spelled out (`\[CircleTimes]`) or as its character.
- A long name that is a bracket opens or closes a group as a bracket does: `\[LeftAngleBracket]a\[RightAngleBracket]` is an `AngleBracket` group and `f\[LeftDoubleBracket]1\[RightDoubleBracket]` a call. An integral with its differential, `\[Integral] f \[DifferentialD] x`, is a `PrefixBinaryNode`. A long name that is whitespace or a newline, such as `\[InvisibleSpace]` or `\[IndentingNewLine]`, is a leaf of that kind, and `\[InvisibleComma]` separates as a comma does.
- Source that is not Wolfram Language reads as CodeParser reads it, and nothing fails:
  - An operand left out is a `Token``Error``ExpectedOperand`.
  - A group not closed is a `GroupMissingCloserNode`. One still open at the end of the source keeps, as CodeParser's does, the leaves on its lines up to a line that begins a new definition, a directive or an annotation comment; the rest of the source is in no node.
  - A closer that closes none of the groups around it is a `Token``Error``UnexpectedCloser`, and one that closes an outer group ends the inner one.
  - Text that is no token is an `ErrorNode` of CodeParser's kind for it: `UnterminatedString`, `UnterminatedComment`, `Number`, `UnsupportedToken` (`??`, or a long name CodeParser does not read, such as `\[PartialD]`), `UnhandledCharacter`, `ExpectedLetterlike`. Such a token is the whole of an expression it begins.
  - A `~` without its second `~`, a `/:` without its `=` and a `:` after what is neither a name nor a pattern are a `SyntaxErrorNode`.
- CodeParser's `SyntaxIssues`, the diagnostics it adds to the container (a remark on each character past ASCII, for one), are not given. A line continuation outside a string is not read.

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

An operator written as a long name:

```wl
ASTStripSource[WolframLanguageConcrete["a \\[CircleTimes] b"]]
```

A bracket written as long names makes a group:

```wl
ASTStripSource[WolframLanguageConcrete["\\[LeftAngleBracket]a, b\\[RightAngleBracket]"]]
```

An integral with its differential:

```wl
ASTStripSource[WolframLanguageConcrete["\\[Integral] f \\[DifferentialD] x"]]
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

An operand left out:

```wl
ASTStripSource[WolframLanguageConcrete["f[x] ="]]
```

A group the source does not close:

```wl
ASTStripSource[WolframLanguageConcrete["{1, 2"]]
```

A closer that closes no group:

```wl
ASTStripSource[WolframLanguageConcrete["a)"]]
```

<!-- => CodeParser`ContainerNode[String, {CodeParser`LeafNode[Symbol, "a", <||>], CodeParser`ErrorNode[Token`Error`UnexpectedCloser, ")", <||>]}, <||>] -->

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

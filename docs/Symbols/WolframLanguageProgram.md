---
Template: Symbol
Name: WolframLanguageProgram
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageProgram
Keywords: [Wolfram Language, program, instructions, leaves, statement, builder, kernel, ToExpression, parser zoo]
SeeAlso: [WolframLanguageHeldNext, WolframLanguageHeld, WolframLanguageSyntaxQ, ToExpression, Get]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageProgram]()[*code*]</code> gives the program the compiled reader makes of the Wolfram Language source string *code*, <code>{*codes*, *prog*, *parts*}</code>: its character codes, the instructions of its statements, and its leaves with a row for each part [WolframLanguageHeldNext]() reads of it, where *code* reads whole with no line continuation and no syntax warning, and [None]() for any other *code*.

## Details & Options

- The program is three packed arrays of integers:

| Array | Value |
|---|---|
| *codes* | the character codes of *code* |
| *prog* | `{0, n}`, then the *n* instructions of all the statements of *code*, three integers each: instruction *k* is <code>*prog*[[3 *k* ;; 3 *k* + 2]]</code> |
| *parts* | `{0, m, r}`, then the kinds of the *m* leaves, their marks, their starts and their ends, *m* integers each, then a row of four for each of the *r* parts of *code* |

- A leaf is a token whose value an instruction pushes. Its mark is 1 for a number literal and 0 for any other, and its text the characters of *code* from its start to the one before its end.
- A statement's row is `{first, last, firstLeaf, lastLeaf}`: its instructions from *first* to *last*, the last of them the one that ends the statement, and its leaves from *firstLeaf* to *lastLeaf*. A statement with no leaf, such as `{}`, has a *lastLeaf* one less than its *firstLeaf*.
- The rows are the statements' alone: a blank line, a return and a newline, and a line holding only a comment part statements and have no row, as [Get]() reads them, where Wolfram 15's [ToExpression]() reads each as a [Null]() [W15 bug]. A source with no statement has no rows.
- Each statement built from its instructions over its leaves, as the reader's build pass builds it, is the part [WolframLanguageHeldNext]() gives, its names made in the [$Context]() and [$ContextPath]() of the moment it is built. The program makes no names: a leaf is its characters.
- The instructions and the kinds of the leaves are those of the reader's build program, which the paclet's note `ReaderBuild.md` describes for a builder of its own, such as a kernel's.
- The *codes* of the empty source are `{}`, a list Wolfram 15 does not pack.
- A source with a line continuation, a source that does not read whole, and a source with a statement that gives a syntax warning, such as a comma that leaves a [Null]() or a string escape with no meaning, have no program; [WolframLanguageHeldNext]() reads them.
- Each call reads *code* anew, and nothing is kept for a call after it.

## Basic Examples

The program of a source of two statements with a blank line between them:

```wl
WolframLanguageProgram["x = 1\n\ny = x + 1"]
```

<!-- => {{120, 32, 61, 32, 49, 10, 10, 121, 32, 61, 32, 120, 32, 43, 32, 49}, {0, 10, 1, 1, 1, 1, 3, 3, 4, 61, 0, 25, 1, 4, 1, 1, 4, 1, 1, 6, 1, 3, 8, 5, 28, 2, 4, 61, 0, 25, 4, 9}, {0, 5, 2, 1, 3, 1, 1, 3, 0, 1, 0, 0, 1, 1, 5, 8, 12, 16, 2, 6, 9, 13, 17, 1, 4, 1, 2, 5, 10, 3, 5}} -->

Its parts: 5 leaves and 2 parts, then the leaves' kinds, marks, starts and ends, then a row for each of the statements `x = 1` and `y = x + 1`, the blank line between them no part:

```wl
Partition[WolframLanguageProgram["x = 1\n\ny = x + 1"][[3, 24 ;;]], 4]
```

<!-- => {{1, 4, 1, 2}, {5, 10, 3, 5}} -->

A comma that leaves a Null gives a warning, so the source has no program:

```wl
WolframLanguageProgram["f[1,]"]
```

<!-- => None -->

## Scope

The rows of a program, after its leaves:

```wl
rows[program_] := Partition[program[[3, 4 + 4 program[[3, 2]] ;;]], 4]
```

A line with only a comment on it parts two definitions:

```wl
rows[WolframLanguageProgram["f[x_] := x^2\n(* a note *)\ng[y_] := f[y] + 1"]]
```

<!-- => {{1, 8, 1, 4}, {9, 18, 5, 9}} -->

A statement with no leaf ends its leaves before they begin:

```wl
rows[WolframLanguageProgram["{}"]]
```

<!-- => {{1, 2, 1, 0}} -->

A source with no statement has no parts:

```wl
WolframLanguageProgram[""]
```

<!-- => {{}, {0, 0}, {0, 0, 0}} -->

The texts of the leaves, the characters of the source from each one's start to the one before its end:

```wl
With[{p = WolframLanguageProgram["x = 1\n\ny = x + 1"]}, MapThread[FromCharacterCode[p[[1, #1 ;; #2 - 1]]] &, {p[[3, 14 ;; 18]], p[[3, 19 ;; 23]]}]]
```

<!-- => {"x", "1", "y", "x", "1"} -->

## Properties and Relations

There is a row for each part that [ToExpression]() gives the source held:

```wl
Length[ToExpression["x = 1\n\ny = x + 1", InputForm, HoldComplete]]
```

<!-- => 3 -->

The program of a source makes none of its names:

```wl
ListQ[WolframLanguageProgram["programNewName"]]
```

<!-- => True -->

```wl
Names["*`programNewName"]
```

<!-- => {} -->

## Possible Issues

A source with a line continuation has no program, though it reads:

```wl
WolframLanguageProgram["a = 1 + \\\n 2"]
```

<!-- => None -->

[WolframLanguageHeldNext]() reads it:

```wl
WolframLanguageHeldNext["a = 1 + \\\n 2", 1]
```

<!-- => {HoldComplete[a = 1 + 2], 13, <|"Warnings" -> {}|>} -->

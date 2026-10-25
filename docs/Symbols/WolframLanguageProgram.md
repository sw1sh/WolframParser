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

<code>[WolframLanguageProgram]()[*code*]</code> gives the program the compiled reader makes of the Wolfram Language source string *code*, its instructions, its leaves and a row for each part [WolframLanguageHeldNext]() reads of it, where *code* reads whole with no line continuation and no syntax warning, and [None]() for any other *code*.

## Details & Options

- The program is an [Association]() with these keys:

| Key | Value |
|---|---|
| `"Steps"` | the instructions of all the statements of *code*, three integers each, one after another: instruction *k* is <code>*steps*[[3 *k* - 2 ;; 3 *k*]]</code> |
| `"Kinds"` | the kind of each leaf, a token whose value an instruction pushes |
| `"Texts"` | the text of each leaf in *code* |
| `"Marks"` | the mark of each leaf, 1 for a number literal and 0 for any other |
| `"Statements"` | a row for each part of *code*, in order |

- A statement's row is `{first, last, firstLeaf, lastLeaf}`: its instructions from *first* to *last*, the last of them the one that ends the statement, and its leaves from *firstLeaf* to *lastLeaf*. A statement with no leaf, such as `{}`, has a *lastLeaf* one less than its *firstLeaf*.
- A row `{0, 0, 0, 0}` is a Null, a line with no statement on it, which [WolframLanguageHeldNext]() reads as <code>[HoldComplete]()[[Null]()]</code>, as [ToExpression]() gives the parts of *code*. A source with no statement is one Null.
- Each statement built from its instructions over its leaves, as the reader's build pass builds it, is the part [WolframLanguageHeldNext]() gives, its names made in the [$Context]() and [$ContextPath]() of the moment it is built. The program makes no names: a leaf is its text.
- The instructions and the kinds of the leaves are those of the reader's build program, which the paclet's note `ReaderBuild.md` describes for a builder of its own, such as a kernel's.
- `"Steps"`, `"Kinds"`, `"Marks"` and `"Statements"` are packed arrays of integers, but for an empty list, which is not packed.
- A source with a line continuation, a source that does not read whole, and a source with a statement that gives a syntax warning, such as a comma that leaves a [Null]() or a string escape with no meaning, have no program; [WolframLanguageHeldNext]() reads them.
- Each call reads *code* anew, and nothing is kept for a call after it.

## Basic Examples

The program of a source of two statements with a blank line between them:

```wl
WolframLanguageProgram["x = 1\n\ny = x + 1"]
```

<!-- => <|"Steps" -> {1, 1, 1, 1, 3, 3, 4, 61, 0, 25, 1, 4, 1, 1, 4, 1, 1, 6, 1, 3, 8, 5, 28, 2, 4, 61, 0, 25, 4, 9}, "Kinds" -> {1, 3, 1, 1, 3}, "Texts" -> {"x", "1", "y", "x", "1"}, "Marks" -> {0, 1, 0, 0, 1}, "Statements" -> {{1, 4, 1, 2}, {0, 0, 0, 0}, {5, 10, 3, 5}}|> -->

Its rows are the statement `x = 1`, a Null for the blank line, and the statement `y = x + 1`:

```wl
WolframLanguageProgram["x = 1\n\ny = x + 1"]["Statements"]
```

<!-- => {{1, 4, 1, 2}, {0, 0, 0, 0}, {5, 10, 3, 5}} -->

A comma that leaves a Null gives a warning, so the source has no program:

```wl
WolframLanguageProgram["f[1,]"]
```

<!-- => None -->

## Scope

The texts of the leaves of a statement are those its row names:

```wl
With[{p = WolframLanguageProgram["x = 1\n\ny = x + 1"]}, p["Texts"][[p["Statements"][[3, 3]] ;; p["Statements"][[3, 4]]]]]
```

<!-- => {"y", "x", "1"} -->

A line with only a comment on it is a Null between two definitions:

```wl
WolframLanguageProgram["f[x_] := x^2\n(* a note *)\ng[y_] := f[y] + 1"]["Statements"]
```

<!-- => {{1, 8, 1, 4}, {0, 0, 0, 0}, {9, 18, 5, 9}} -->

A statement with no leaf ends its leaves before they begin:

```wl
WolframLanguageProgram["{}"]["Statements"]
```

<!-- => {{1, 2, 1, 0}} -->

A source with no statement is one Null:

```wl
WolframLanguageProgram[""]["Statements"]
```

<!-- => {{0, 0, 0, 0}} -->

## Properties and Relations

There is a row for each part that [ToExpression]() gives the source held:

```wl
Length[ToExpression["x = 1\n\ny = x + 1", InputForm, HoldComplete]]
```

<!-- => 3 -->

The program of a source makes none of its names:

```wl
AssociationQ[WolframLanguageProgram["programNewName"]]
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

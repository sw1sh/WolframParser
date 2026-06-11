---
Template: Symbol
Name: BrainfuckRun
Context: Wolfram`Parser`Languages`Brainfuck`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/BrainfuckRun
Keywords: [brainfuck, run, interpreter, esoteric language, closure, parser zoo]
SeeAlso: [BrainfuckAST, BrainfuckGrammar, BrainfuckSemantic, FromCharacterCode, RightComposition]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[BrainfuckRun]()[*code*]</code> compiles the Brainfuck source string *code* to a Wolfram closure, runs it on a fresh byte tape, and returns the output string.

<code>[BrainfuckRun]()[*code*, *input*]</code> runs the program with *input* supplied to the `,` command.

## Details & Options

- `BrainfuckRun` is the *executing* mode of the Brainfuck grammar: it runs [BrainfuckGrammar]() over [BrainfuckSemantic](), the algebra that compiles each construct to a function machine -> machine. The parsed program *is* an executable closure; running it threads a fresh machine through and collects its output.
- The machine is a single [Association]() carrying a byte `"tape"` (an [Association]() of cell index to value), a cell `"ptr"`, the remaining `"in"` bytes, and the accumulated `"out"` bytes. Every cell starts at `0`; arithmetic on a cell is taken [Mod]() `256`.
- Each `.` appends the current cell to the output; the final byte list is decoded with [FromCharacterCode]() into the returned string. Each `,` consumes one byte of *input*, or writes `0` once the input is exhausted.
- To see the structure of *code* rather than run it, use [BrainfuckAST](), which runs the *same* grammar over a neutral node-building algebra. The grammar is written once; only the algebra differs.
- Source whose brackets do not balance does not parse to completion and returns a [Failure]() (see [Parse]()).

## Basic Examples

The canonical "A" program: build `60` in a cell with a multiply loop, add `5`, and print it:

```wl
BrainfuckRun["++++++[>++++++++++<-]>+++++."]
```

<!-- => "A" -->

The classic hello-world program returns the greeting, newline and all:

```wl
BrainfuckRun["++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."]
```

<!-- => "Hello World!\n" -->

The same source through [BrainfuckAST]() describes the program instead of running it:

```wl
BrainfuckAST["+++."]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Command", "+", <|"Source" -> {{1, 2}, {1, 3}}|>], LeafNode["Command", "+", <|"Source" -> {{1, 3}, {1, 4}}|>], LeafNode["Command", ".", <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 1}, {1, 5}}|>] -->

## Scope

With a second argument, `,` reads from *input*. A cat program echoes its input back byte for byte:

```wl
BrainfuckRun[",[.,]", "Hi!"]
```

<!-- => "Hi!" -->

Non-command characters are comments, so a program can be documented inline without changing what it does:

```wl
BrainfuckRun["add five +++++ then print ."]
```

<!-- => " " -->

A program with no `.` command produces no output:

```wl
BrainfuckRun["+++++"]
```

<!-- => "" -->

## Properties and Relations

Running over [BrainfuckSemantic]() through [BrainfuckGrammar]() directly is what `BrainfuckRun` does under the hood; the wrapper only threads a fresh machine and decodes the output bytes with [FromCharacterCode]():

```wl
BrainfuckRun["++++++++[>+++++++++<-]>."]
```

<!-- => "H" -->

## Possible Issues

Brackets must balance. An unclosed `[` does not parse to completion and returns an honest [Failure]() rather than running a malformed program:

```wl
BrainfuckRun["+[>+"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "<end of input>", "Found" -> "["|>] -->

A stray `]` with no matching `[` fails the same way:

```wl
BrainfuckRun["+]"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "<end of input>", "Found" -> "]"|>] -->

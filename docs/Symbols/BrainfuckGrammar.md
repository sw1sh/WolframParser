---
Template: Symbol
Name: BrainfuckGrammar
Context: Wolfram`Parser`Languages`Brainfuck`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/BrainfuckGrammar
Keywords: [brainfuck, grammar, algebra, parser combinator, compiler, parser zoo]
SeeAlso: [BrainfuckAST, BrainfuckRun, BrainfuckSemantic, RightComposition, ParserCombinator, ParseRecursive]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[BrainfuckGrammar]()[*alg*]</code> builds the Brainfuck parser - a [ParserCombinator]() - over the algebra *alg*, an [Association]() of builder functions its semantic actions call.

## Details & Options

- `BrainfuckGrammar` is the heart of Brainfuck's dual-algebra design: the grammar is written *once*, parameterized over *alg*. Over [BrainfuckSemantic]() it becomes a *compiler* - the parsed program is an executable closure - and over a neutral node-building algebra it emits a standard syntax tree. The grammar never changes; only the algebra does.
- The parser is tiny but recursive: the eight commands `>` `<` `+` `-` `.` `,` `[` `]` are the only significant characters, every other character is a comment, and `[` … `]` loops nest arbitrarily via [ParseRecursive](). Each command runs the action `alg["Op"][token]`; a `[` … `]` body runs `alg["Loop"][children]`; the whole sequence runs `alg["Seq"][children]`.
- Over [BrainfuckSemantic]() the actions compile rather than describe. A command becomes a function machine -> machine, a sequence their [RightComposition](), and a loop a [NestWhile](). So <code>[BrainfuckGrammar]()[[BrainfuckSemantic]()][*code*]</code> returns the program *as a closure*, ready to run on a machine.
- The result of `BrainfuckGrammar[alg]` is a built [ParserCombinator](). Run it on input either as <code>*pc*[*code*]</code> or equivalently with <code>[Parse]()[*pc*, *code*]</code>.
- [BrainfuckAST]() and [BrainfuckRun]() are thin wrappers over this builder: `BrainfuckAST` runs the grammar over a neutral algebra (wrapping the result in a [ContainerNode]()), and `BrainfuckRun` runs it over [BrainfuckSemantic]() and threads a fresh machine through the resulting closure.

## Basic Examples

Building the grammar over an algebra yields a [ParserCombinator]():

```wl
Head[BrainfuckGrammar[BrainfuckSemantic]]
```

<!-- => ParserCombinator -->

Over [BrainfuckSemantic]() the grammar is a compiler: parsing *code* returns the program *as a closure* - a [RightComposition]() of the per-command machines:

```wl
Head[BrainfuckGrammar[BrainfuckSemantic]["+++"]]
```

<!-- => RightComposition -->

Run that closure on a fresh machine to execute the program. Three `>` moves the data pointer three cells right:

```wl
BrainfuckGrammar[BrainfuckSemantic][">>>"][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>]["ptr"]
```

<!-- => 3 -->

## Scope

A `[` … `]` loop compiles to a [NestWhile](): the body runs while the current cell is nonzero. The idiom `[-]` zeroes a cell, so `+++[-]` builds `3` then clears it back to `0`:

```wl
BrainfuckGrammar[BrainfuckSemantic]["+++[-]"][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>]["ptr"]
```

<!-- => 0 -->

A built grammar runs equivalently through [Parse]():

```wl
Head[Parse[BrainfuckGrammar[BrainfuckSemantic], "+++"]]
```

<!-- => RightComposition -->

## Properties and Relations

[BrainfuckRun]() is this grammar over [BrainfuckSemantic](), packaged to thread a fresh machine and decode the output bytes:

```wl
BrainfuckRun["++++++[>++++++++++<-]>+++++."]
```

<!-- => "A" -->

[BrainfuckAST]() is the *same* grammar over a neutral node-building algebra, so the same source yields a standard syntax tree instead of a closure:

```wl
BrainfuckAST["+[>]"]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>], GroupNode["Loop", {LeafNode["Command", ">", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

## Possible Issues

A grammar built over [BrainfuckSemantic]() returns an honest [Failure]() on input it cannot parse to completion - here an unclosed `[` - the same as any [Parse]():

```wl
BrainfuckGrammar[BrainfuckSemantic]["+["]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "<end of input>", "Found" -> "["|>] -->

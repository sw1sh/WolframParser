---
Template: Symbol
Name: BrainfuckSemantic
Context: Wolfram`Parser`Languages`Brainfuck`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/BrainfuckSemantic
Keywords: [brainfuck, algebra, semantic, compiler, closure, parser zoo]
SeeAlso: [BrainfuckRun, BrainfuckGrammar, BrainfuckAST, RightComposition, NestWhile]
RelatedGuides: [ParserZoo]
---

## Usage

[BrainfuckSemantic]() is the algebra - an [Association]() of builder functions - that compiles a Brainfuck parse to an executable machine -> machine closure.

## Details & Options

- `BrainfuckSemantic` is one of the *two* algebras the Brainfuck grammar runs over. It is the meaningful, executable one: each builder turns a parsed construct into a function machine -> machine, so the whole parse compiles to a closure that *runs* the program. The neutral alternative builds a standard syntax tree instead, surfaced through [BrainfuckAST]().
- It is a plain [Association]() with three keys: `"Op"`, `"Seq"`, and `"Loop"`. [BrainfuckGrammar]()'s semantic actions look up these keys, so the algebra *is* the language's meaning - swap it and the same grammar means something else.
- `"Op"` compiles one command token to a machine -> machine [Function](): `>` `<` move the cell pointer, `+` `-` change the current cell (taken [Mod]() `256`), `.` appends the cell to the output, and `,` consumes one input byte (or writes `0` when input is exhausted).
- `"Seq"` composes a list of command machines with [RightComposition]() - run left to right. `"Loop"` wraps a body in a [NestWhile](): the body runs while the current cell is nonzero.
- [BrainfuckRun]() is just [BrainfuckGrammar]()`[BrainfuckSemantic]` packaged as a function: it threads a fresh machine through the compiled closure and decodes the collected output bytes. To get the standard tree for the same grammar, use [BrainfuckAST]() instead.

## Basic Examples

The algebra is an [Association]() of builder functions, keyed by construct:

```wl
Keys[BrainfuckSemantic]
```

<!-- => {"Op", "Seq", "Loop"} -->

The `"Op"` builder compiles one command to a machine -> machine [Function]():

```wl
Head[BrainfuckSemantic["Op"]["+"]]
```

<!-- => Function -->

Apply that machine to a fresh state: `+` increments the current cell from `0` to `1`:

```wl
Lookup[BrainfuckSemantic["Op"]["+"][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>]["tape"], 0]
```

<!-- => 1 -->

The `>` command moves the cell pointer one step right:

```wl
BrainfuckSemantic["Op"][">"][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>]["ptr"]
```

<!-- => 1 -->

## Scope

`"Seq"` composes a list of command machines with [RightComposition](), so a sequence is itself a single machine -> machine closure:

```wl
Head[BrainfuckSemantic["Seq"][{BrainfuckSemantic["Op"][">"], BrainfuckSemantic["Op"][">"]}]]
```

<!-- => RightComposition -->

Running that composed machine moves the pointer twice:

```wl
BrainfuckSemantic["Seq"][{BrainfuckSemantic["Op"][">"], BrainfuckSemantic["Op"][">"]}][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>]["ptr"]
```

<!-- => 2 -->

`"Loop"` wraps a body in a [NestWhile](), running it while the current cell is nonzero. Cell arithmetic wraps [Mod]() `256`, so `-` on a zero cell gives `255`:

```wl
Lookup[BrainfuckSemantic["Op"]["-"][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>]["tape"], 0]
```

<!-- => 255 -->

## Properties and Relations

`BrainfuckSemantic` is the algebra that drives [BrainfuckRun]() - running [BrainfuckGrammar]() over it compiles an input string to a runnable closure:

```wl
BrainfuckRun["++++++[>++++++++++<-]>+++++."]
```

<!-- => "A" -->

It is one of a pair with the neutral node-building algebra behind [BrainfuckAST](). Where `BrainfuckSemantic` compiles `+` to an incrementing machine, the neutral algebra keeps it as a `"Command"` [LeafNode]():

```wl
BrainfuckAST["+"]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>]}, <|"Source" -> {{1, 1}, {1, 2}}|>] -->

## Neat Examples

Because the algebra is a plain [Association](), a single key can be overridden to retarget the language. Making `.` append the *negated* cell while every other rule stays put produces a program whose output is byte-complemented - here the `"A"` program emits `Mod[-65, 256]` instead:

```wl
twist = <|BrainfuckSemantic, "Op" -> Function[c, If[c === ".", Function[m, <|m, "out" -> Append[m["out"], Mod[-Lookup[m["tape"], m["ptr"], 0], 256]]|>], BrainfuckSemantic["Op"][c]]]|>;
Lookup[BrainfuckGrammar[twist]["++++++[>++++++++++<-]>+++++."][<|"tape" -> <||>, "ptr" -> 0, "in" -> {}, "out" -> {}|>], "out"]
```

<!-- => {191} -->

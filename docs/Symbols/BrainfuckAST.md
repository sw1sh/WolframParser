---
Template: Symbol
Name: BrainfuckAST
Context: Wolfram`Parser`Languages`Brainfuck`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/BrainfuckAST
Keywords: [brainfuck, AST, syntax tree, esoteric language, loop, parser zoo]
SeeAlso: [BrainfuckRun, BrainfuckGrammar, BrainfuckSemantic, GroupNode, LeafNode, ContainerNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[BrainfuckAST]()[*code*]</code> parses the Brainfuck source string *code* to a standard syntax tree - a [ContainerNode]() of [LeafNode]() commands and `[`-`]` loops as [GroupNode]()`["Loop", …]`.

## Details & Options

- `BrainfuckAST` is the standard-AST mode of the Brainfuck grammar: it runs [BrainfuckGrammar]() over a neutral node-building algebra, so the result carries only structure - which commands run, and how the loops nest - and no executable meaning.
- The eight commands `>` `<` `+` `-` `.` `,` `[` `]` are the only significant characters. Each of the first six becomes a `"Command"` [LeafNode]() holding its literal token; every *other* character is a comment and is dropped from the tree.
- A matched `[` … `]` pair becomes a [GroupNode]()`["Loop", {…}]` whose children are the parsed body. Loops nest arbitrarily, so a `GroupNode["Loop", …]` can itself contain `GroupNode["Loop", …]`.
- [BrainfuckRun]() runs the *same* grammar over [BrainfuckSemantic]() instead, compiling the program to an executable closure and returning its output. The grammar is written once; only the algebra differs.
- Source whose brackets do not balance does not parse to completion and returns a [Failure]() (see [Parse]()).

## Basic Examples

A single command is a `"Command"` [LeafNode](); a `[` … `]` pair is a [GroupNode]()`["Loop", …]`:

```wl
BrainfuckAST["+[>]"]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>], GroupNode["Loop", {LeafNode["Command", ">", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

Every node carries a `"Source"` span of `{{`*startLine*`, `*startCol*`}, {`*endLine*`, `*endCol*`}}` ([CodeParser]() LineColumn). Each command [LeafNode]() spans its single character, and the `GroupNode["Loop", …]` spans its *content* - here the `>` at columns `3`-`4`, with the enclosing `[` and `]` delimiters excluded.

Every non-command character is a comment and leaves no trace - here only the `+` survives:

```wl
BrainfuckAST["a+b"]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 2}, {1, 3}}|>]}, <|"Source" -> {{1, 2}, {1, 3}}|>] -->

The same source through [BrainfuckRun]() runs the program rather than describing it:

```wl
BrainfuckRun["++++++[>++++++++++<-]>+++++."]
```

<!-- => "A" -->

## Scope

Loops nest, and the tree nests with them - a [GroupNode]()`["Loop", …]` inside another:

```wl
BrainfuckAST["[[+]]"]
```

<!-- => ContainerNode["String", {GroupNode["Loop", {GroupNode["Loop", {LeafNode["Command", "+", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 3}, {1, 4}}|>] -->

An all-comment program parses to an empty [ContainerNode]() - no commands, no loops, and with no content to span its metadata stays empty `<||>`:

```wl
BrainfuckAST["hello"]
```

<!-- => ContainerNode["String", {}, <||>] -->

## Properties and Relations

[BrainfuckAST]() and [BrainfuckRun]() share one grammar and differ only in the algebra. The tree form records the structure; the run form collapses it to the program's output string:

```wl
BrainfuckAST["+++."]
```

<!-- => ContainerNode["String", {LeafNode["Command", "+", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Command", "+", <|"Source" -> {{1, 2}, {1, 3}}|>], LeafNode["Command", "+", <|"Source" -> {{1, 3}, {1, 4}}|>], LeafNode["Command", ".", <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 1}, {1, 5}}|>] -->

```wl
BrainfuckRun["++++++++[>+++++++++<-]>."]
```

<!-- => "H" -->

## Possible Issues

Brackets must balance. An unclosed `[` does not parse to completion and returns an honest [Failure](), reporting how far it got and what it expected:

```wl
BrainfuckAST["+[>+"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "<end of input>", "Found" -> "["|>] -->

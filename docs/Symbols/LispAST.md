---
Template: Symbol
Name: LispAST
Context: Wolfram`Parser`Languages`Lisp`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LispAST
Keywords: [lisp, s-expression, sexpr, AST, syntax tree, read, parser zoo]
SeeAlso: [LispRead, LispSymbol, LispGrammar, LispSemantic, CallNode, ContainerNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LispAST]()[*sexpr*]</code> parses one or more s-expressions in the string *sexpr* to a standard syntax tree - a [ContainerNode]() of [CallNode](), [LeafNode]() and [PrefixNode]().

## Details & Options

- `LispAST` is the standard-AST mode of the Lisp reader: it runs [LispGrammar]() over an internal AST algebra, so the result carries no Lisp-specific meaning, only structure - the same neutral node vocabulary the rest of the parser zoo emits.
- The grammar is a single self-similar rule: an atom (symbol, number or string), a parenthesised list, or a quoted form. Whitespace skips both spaces and `;`-to-end-of-line comments.
- A non-empty list `(f a b)` becomes a [CallNode]() whose head is the first element; the empty list `()` is a [GroupNode]() with kind `"List"`.
- The reader-macro quote `'x` becomes a [PrefixNode]() with operator descriptor `'`.
- A [LeafNode]() keeps the literal source text (`"42"`, not `42`) and a `"Symbol"`, `"Integer"`, `"Real"` or `"String"` kind descriptor; values are only interpreted in the [LispRead]() mode.
- [LispRead]() runs the *same* grammar over [LispSemantic]() instead, reading to native Wolfram data. The grammar is written once; only the algebra differs.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

A nested call reads to a [CallNode]() tree, head-first:

```wl
LispAST["(+ 1 (max 2 3))"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "+", <|"Source" -> {{1, 2}, {1, 3}}|>], {LeafNode["Integer", "1", <|"Source" -> {{1, 4}, {1, 5}}|>], CallNode[LeafNode["Symbol", "max", <|"Source" -> {{1, 7}, {1, 10}}|>], {LeafNode["Integer", "2", <|"Source" -> {{1, 11}, {1, 12}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 7}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>] -->

Every node carries a `"Source"` span of `{{`*startLine*`, `*startCol*`}, {`*endLine*`, `*endCol*`}}` ([CodeParser]() LineColumn). Each [LeafNode]() spans just its token, and a composite spans its children: the inner `max` call runs columns `7`-`14`, the whole `+` call columns `2`-`14`.

The quote reader macro `'x` is a [PrefixNode]() with descriptor `'`:

```wl
LispAST["'x"]
```

<!-- => ContainerNode["String", {PrefixNode["'", LeafNode["Symbol", "x", <|"Source" -> {{1, 2}, {1, 3}}|>], <|"Source" -> {{1, 2}, {1, 3}}|>]}, <|"Source" -> {{1, 2}, {1, 3}}|>] -->

The same source through [LispRead]() is native data, not a tree:

```wl
LispRead["(+ 1 (max 2 3))"]
```

<!-- => {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}} -->

## Scope

A Lisp identifier need not be a Wolfram identifier - `list->vector` is one `"Symbol"` [LeafNode]():

```wl
LispAST["(list->vector x)"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "list->vector", <|"Source" -> {{1, 2}, {1, 14}}|>], {LeafNode["Symbol", "x", <|"Source" -> {{1, 15}, {1, 16}}|>]}, <|"Source" -> {{1, 2}, {1, 16}}|>]}, <|"Source" -> {{1, 2}, {1, 16}}|>] -->

A quoted list quotes the whole [CallNode]():

```wl
LispAST["'(a b)"]
```

<!-- => ContainerNode["String", {PrefixNode["'", CallNode[LeafNode["Symbol", "a", <|"Source" -> {{1, 3}, {1, 4}}|>], {LeafNode["Symbol", "b", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 3}, {1, 6}}|>], <|"Source" -> {{1, 3}, {1, 6}}|>]}, <|"Source" -> {{1, 3}, {1, 6}}|>] -->

The empty list is a [GroupNode]() rather than a [CallNode]() (it has no head); with no children to span, its metadata stays empty `<||>`:

```wl
LispAST["()"]
```

<!-- => ContainerNode["String", {GroupNode["List", {}, <||>]}, <||>] -->

A `;` comment runs to end of line, so two top-level forms separated by a comment read as two children of the [ContainerNode](). Because the second form is on line `2`, its `"Source"` start line bumps to `2` while the container spans from line `1` to line `2`:

```wl
LispAST["1 ; one\n2"]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{2, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 1}, {2, 2}}|>] -->

## Properties and Relations

The neutral nodes project onto Wolfram's own [CodeParser]() shape with [ToCodeParser](), so a Lisp `(+ 1 2)` can become a real [Plus]() call:

```wl
ToCodeParser[LispAST["(+ 1 2)"], <|"+" -> Plus|>]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`CallNode[CodeParser`LeafNode[Symbol, "+", <|"Source" -> {{1, 2}, {1, 3}}|>], {CodeParser`LeafNode[Integer, "1", <|"Source" -> {{1, 4}, {1, 5}}|>], CodeParser`LeafNode[Integer, "2", <|"Source" -> {{1, 6}, {1, 7}}|>]}, <|"Source" -> {{1, 2}, {1, 7}}|>]}, <|"Source" -> {{1, 2}, {1, 7}}|>] -->

## Possible Issues

An unbalanced list is an honest [Failure](), reporting how far it got and what it expected next:

```wl
LispAST["(a b"]
```

<!-- => Failure["ParseError", <|"Position" -> 5, "Expected" -> {")"}, "Found" -> "<end of input>"|>] -->

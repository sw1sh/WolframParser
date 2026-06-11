---
Template: Symbol
Name: LispRead
Context: Wolfram`Parser`Languages`Lisp`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LispRead
Keywords: [lisp, read, s-expression, sexpr, reader, native data, parser zoo]
SeeAlso: [LispAST, LispSymbol, LispGrammar, LispSemantic, ToExpression]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LispRead]()[*sexpr*]</code> reads the s-expressions in the string *sexpr* to native nested Wolfram data: lists for lists, numbers and strings for literals, and [LispSymbol]() wrappers for symbols.

<code>[LispRead]()[*sexpr*]</code> returns the single form when *sexpr* holds exactly one top-level form, and the list of forms otherwise.

## Details & Options

- `LispRead` is the classic Lisp `read`: it runs [LispGrammar]() over [LispSemantic](), the algebra whose builders fold each form straight to a native Wolfram value, ready for a downstream evaluator.
- A non-empty list `(f a b)` reads to a flat [List]() `{`*f*, *a*, *b*`}`; the empty list `()` reads to `{}`. There is no special head - a Lisp list is just a Wolfram list.
- A symbol reads to a [LispSymbol]() wrapper, kept distinct from a Wolfram [Symbol]() because Lisp names like `+` or `list->vector` are not Wolfram identifiers.
- An integer or real literal reads to the corresponding Wolfram number; a `"..."` string literal reads to a Wolfram [String]() (via JSON, so escapes like `\n` are honored).
- The quote reader macro `'x` reads to `{`[LispSymbol]()`["quote"], `*x*`}`, the two-element list a downstream evaluator expects.
- Whitespace skips both spaces and `;`-to-end-of-line comments.
- To see the standard syntax tree for the same input instead, use [LispAST](), which runs the *same* grammar over an internal AST algebra.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

A nested list reads head-and-all to plain Wolfram lists, with symbols wrapped:

```wl
LispRead["(+ 1 (max 2 3))"]
```

<!-- => {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}} -->

A bare atom reads to a single [LispSymbol](), not a list:

```wl
LispRead["foo"]
```

<!-- => LispSymbol["foo"] -->

The same source through [LispAST]() is a [CallNode]() tree, not data:

```wl
LispAST["(+ 1 (max 2 3))"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "+", <|"Source" -> {{1, 2}, {1, 3}}|>], {LeafNode["Integer", "1", <|"Source" -> {{1, 4}, {1, 5}}|>], CallNode[LeafNode["Symbol", "max", <|"Source" -> {{1, 7}, {1, 10}}|>], {LeafNode["Integer", "2", <|"Source" -> {{1, 11}, {1, 12}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 7}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>] -->

## Scope

The quote reader macro expands to a two-element `quote` list, exactly what a downstream evaluator dispatches on:

```wl
LispRead["'(1 2 3)"]
```

<!-- => {LispSymbol["quote"], {1, 2, 3}} -->

A string literal reads through JSON, so escapes are interpreted:

```wl
LispRead["\"a\\nb\""]
```

<!-- => "a\nb" -->

A Lisp name that is not a Wolfram identifier still reads cleanly, because it lands inside a [LispSymbol]() wrapper:

```wl
LispRead["(list->vector x)"]
```

<!-- => {LispSymbol["list->vector"], LispSymbol["x"]} -->

## Properties and Relations

With one top-level form, `LispRead` returns that form; with several it returns the list of them. A `;` comment separates two forms here:

```wl
LispRead["1 ; one\n2"]
```

<!-- => {1, 2} -->

Two top-level lists read to a list of two lists:

```wl
LispRead["(a) (b)"]
```

<!-- => {{LispSymbol["a"]}, {LispSymbol["b"]}} -->

`LispRead` and [LispAST]() share one grammar and differ only in the algebra: [LispRead]() folds to native data, [LispAST]() builds the neutral [ContainerNode]() tree.

## Possible Issues

An unbalanced list is an honest [Failure](), reporting how far it got and what it expected next:

```wl
LispRead["(a b"]
```

<!-- => Failure["ParseError", <|"Position" -> 5, "Expected" -> {")"}, "Found" -> "<end of input>"|>] -->

---
Template: Symbol
Name: LispGrammar
Context: Wolfram`Parser`Languages`Lisp`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LispGrammar
Keywords: [lisp, grammar, algebra, parser combinator, s-expression, recursive, parser zoo]
SeeAlso: [LispAST, LispRead, LispSymbol, LispSemantic, ParserCombinator, ParseRecursive]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LispGrammar]()[*alg*]</code> builds the Lisp reader - a [ParserCombinator]() - over the algebra *alg*, an [Association]() of builder functions its semantic actions call.

## Details & Options

- `LispGrammar` is the heart of the Lisp reader's dual-algebra design: the grammar is written *once*, parameterized over *alg*. Hand it [LispSemantic]() and it reads to native Wolfram data; the internal AST algebra emits a standard syntax tree (reached through the [LispAST]() function). The grammar never changes; only the algebra does.
- The semantic actions never construct results directly. They call into *alg* by key - `alg["Sym"][name]`, `alg["Num"][digits]`, `alg["Str"][raw]`, `alg["Quote"][form]`, `alg["List"][elems]` - so swapping the algebra reroutes every action at once.
- The whole language is one self-similar production: an atom, a parenthesised list, or a quoted form, all wired together with [ParseRecursive](). This makes the reader a good stress test of recursion and comment-aware whitespace rather than of operator precedence.
- Whitespace skips both spaces and `;`-to-end-of-line comments.
- The result is a built [ParserCombinator](). Run it on input either as <code>*pc*[*input*]</code> or equivalently with <code>[Parse]()[*pc*, *input*]</code>; it returns the *list* of top-level forms.
- [LispRead]() and [LispAST]() are thin wrappers: `LispRead` runs `LispGrammar[LispSemantic]` (unwrapping a single top form), and `LispAST` runs the grammar over the internal AST algebra (wrapping the result in a [ContainerNode]()).

## Basic Examples

Building the grammar over an algebra yields a [ParserCombinator]():

```wl
Head[LispGrammar[LispSemantic]]
```

<!-- => ParserCombinator -->

The built combinator is a summary box you can run directly:

```wl
LispGrammar[LispSemantic]
```

<!-- => ParserCombinator[Action, ...] -->

Over [LispSemantic](), input reads to the list of top-level forms as native data:

```wl
LispGrammar[LispSemantic]["(+ 1 2)"]
```

<!-- => {{LispSymbol["+"], 1, 2}} -->

## Scope

A built grammar runs equivalently through [Parse]():

```wl
Parse[LispGrammar[LispSemantic], "(+ 1 2)"]
```

<!-- => {{LispSymbol["+"], 1, 2}} -->

The grammar always returns the *list* of top-level forms; [LispRead]() is the wrapper that unwraps a single form:

```wl
LispRead["(+ 1 2)"]
```

<!-- => {LispSymbol["+"], 1, 2} -->

## Properties and Relations

`LispGrammar` is what [LispRead]() and [LispAST]() share: one grammar, two algebras. Reading the same source two ways differs only in the algebra `LispGrammar` is handed. Over [LispSemantic]() the result is native data:

```wl
LispRead["(+ 1 (max 2 3))"]
```

<!-- => {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}} -->

Over the internal AST algebra (via [LispAST]()) the same source is a [CallNode]() tree:

```wl
LispAST["(+ 1 (max 2 3))"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "+", <|"Source" -> {{1, 2}, {1, 3}}|>], {LeafNode["Integer", "1", <|"Source" -> {{1, 4}, {1, 5}}|>], CallNode[LeafNode["Symbol", "max", <|"Source" -> {{1, 7}, {1, 10}}|>], {LeafNode["Integer", "2", <|"Source" -> {{1, 11}, {1, 12}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 7}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>] -->

## Possible Issues

A grammar built over [LispSemantic]() returns an honest [Failure]() on input it cannot parse to completion, the same as any [Parse]():

```wl
LispGrammar[LispSemantic]["(a b"]
```

<!-- => Failure["ParseError", <|"Position" -> 5, "Expected" -> {")"}, "Found" -> "<end of input>"|>] -->

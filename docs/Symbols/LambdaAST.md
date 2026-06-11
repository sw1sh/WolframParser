---
Template: Symbol
Name: LambdaAST
Context: Wolfram`Parser`Languages`Lambda`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LambdaAST
Keywords: [lambda calculus, AST, syntax tree, abstraction, application, binder, parser zoo]
SeeAlso: [LambdaEval, LambdaGrammar, LambdaSemantic, CallNode, LeafNode, ContainerNode]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LambdaAST]()[*term*]</code> parses the untyped lambda-calculus *term* to a standard syntax tree - a [ContainerNode]() of [CallNode]() and [LeafNode]().

## Details & Options

- `LambdaAST` is the standard-AST mode of the lambda grammar: it runs [LambdaGrammar]() over the shared abstract-syntax algebra, so the result carries only structure, no reduction.
- The surface syntax is `\`*name*`.`*body* (or the unicode `λ`*name*`.`*body*) for abstraction, juxtaposition for application (left associative), and parentheses for grouping. `\x y. b` is sugar for `\x.\y. b`. In a Wolfram string a backslash doubles, so the term `\x.x` is written `"\\x.x"`.
- A variable is a [LeafNode]() with kind `"Symbol"`. An application *f* *x* is a [CallNode]() with *f* as its head and `{`*x*`}` as its single argument. An abstraction `\`*name*`.`*body* is a [CallNode]() headed by the lambda leaf `LeafNode["Symbol", "λ", <||>]`, with the bound name and the body as its two children.
- [LambdaEval]() runs the *same* grammar over [LambdaSemantic]() instead, compiling each abstraction to a native [Function]() and letting the kernel beta-reduce. The grammar is written once; only the algebra differs.
- Application binds tighter than abstraction, so `\x.x y` reads as `\x.(x y)`, not `(\x.x) y`.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

The identity term is a [CallNode]() headed by the lambda leaf, binding `x` over the body `x`:

```wl
LambdaAST["\\x.x"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], LeafNode["Symbol", "x", <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 4}, {1, 5}}|>] -->

Nodes carry a `"Source"` span of `{{`*startLine*`, `*startCol*`}, {`*endLine*`, `*endCol*`}}` ([CodeParser]() LineColumn). An abstraction is special: its `λ` head and its bound-name leaf are *synthesized* by the builder, not lexed from a token, so they have no source and keep empty metadata `<||>`. Only the parsed variable occurrence in the body - here the trailing `x` at columns `4`-`5` - carries a span, and the abstraction node inherits that body span (the binder is not included).

The K combinator `\x.\y.x` nests one abstraction inside another:

```wl
LambdaAST["\\x.\\y.x"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "y", <||>], LeafNode["Symbol", "x", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 7}, {1, 8}}|>] -->

The same source through [LambdaEval]() reduces to a value, not a tree:

```wl
LambdaEval["(\\x.\\y.x) a b"]
```

<!-- => a -->

## Scope

Application is left associative, so `f x y` nests as `(f x) y` - a [CallNode]() whose head is itself a [CallNode]():

```wl
LambdaAST["f x y"]
```

<!-- => ContainerNode["String", {CallNode[CallNode[LeafNode["Symbol", "f", <|"Source" -> {{1, 1}, {1, 2}}|>], {LeafNode["Symbol", "x", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>], {LeafNode["Symbol", "y", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>] -->

The `\x y. b` sugar folds to nested single-binder abstractions, so it produces the very same tree as `\x.\y. b`:

```wl
LambdaAST["\\x y.x"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "y", <||>], LeafNode["Symbol", "x", <|"Source" -> {{1, 6}, {1, 7}}|>]}, <|"Source" -> {{1, 6}, {1, 7}}|>]}, <|"Source" -> {{1, 6}, {1, 7}}|>]}, <|"Source" -> {{1, 6}, {1, 7}}|>] -->

The unicode `λ` is accepted as an alternative to the `\` token and yields an identical tree:

```wl
LambdaAST["\[Lambda]x.x"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], LeafNode["Symbol", "x", <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 4}, {1, 5}}|>]}, <|"Source" -> {{1, 4}, {1, 5}}|>] -->

A free variable parses to a bare [LeafNode]() with no surrounding [CallNode]():

```wl
LambdaAST["x"]
```

<!-- => ContainerNode["String", {LeafNode["Symbol", "x", <|"Source" -> {{1, 1}, {1, 2}}|>]}, <|"Source" -> {{1, 1}, {1, 2}}|>] -->

## Properties and Relations

`LambdaAST` and [LambdaEval]() share one grammar and differ only in the algebra. The tree form records the binder structure; the eval form compiles it to a closure and reduces. Applying Church-numeral 2 to `g` and `y` is a deep [CallNode]() spine as a tree:

```wl
LambdaAST["(\\f.\\x.f (f x)) g y"]
```

<!-- => ContainerNode["String", {CallNode[CallNode[CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "f", <||>], CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], CallNode[LeafNode["Symbol", "f", <|"Source" -> {{1, 8}, {1, 9}}|>], {CallNode[LeafNode["Symbol", "f", <|"Source" -> {{1, 11}, {1, 12}}|>], {LeafNode["Symbol", "x", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 11}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>], {LeafNode["Symbol", "g", <|"Source" -> {{1, 17}, {1, 18}}|>]}, <|"Source" -> {{1, 8}, {1, 18}}|>], {LeafNode["Symbol", "y", <|"Source" -> {{1, 19}, {1, 20}}|>]}, <|"Source" -> {{1, 8}, {1, 20}}|>]}, <|"Source" -> {{1, 8}, {1, 20}}|>] -->

The same term through [LambdaEval]() beta-reduces to a stable value:

```wl
LambdaEval["(\\f.\\x.f (f x)) g y"]
```

<!-- => g[g[y]] -->

## Possible Issues

A partial parse is an honest [Failure](), reporting how far it got and what it expected next - here a dangling `\x.` with no body:

```wl
LambdaAST["\\x."]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> {"\\", "λ", "(", "regex /[A-Za-z][A-Za-z0-9_]*/"}, "Found" -> "<end of input>"|>] -->

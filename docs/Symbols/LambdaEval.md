---
Template: Symbol
Name: LambdaEval
Context: Wolfram`Parser`Languages`Lambda`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LambdaEval
Keywords: [lambda calculus, beta reduction, closure, Function, evaluate, parser zoo]
SeeAlso: [LambdaAST, LambdaGrammar, LambdaSemantic, Function, Parse]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LambdaEval]()[*term*]</code> compiles the untyped lambda-calculus *term* to a native Wolfram [Function]() and lets the kernel beta-reduce it; free variables stay symbolic.

## Details & Options

- `LambdaEval` is the *evaluating* mode of the lambda grammar: it runs [LambdaGrammar]() over [LambdaSemantic](), the algebra whose builders turn each abstraction into a real Wolfram [Function]() and each application into real Wolfram application. The kernel then does the beta-reduction for free.
- The surface syntax is `\`*name*`.`*body* (or the unicode `λ`*name*`.`*body*) for abstraction, juxtaposition for application (left associative), and parentheses for grouping. `\x y. b` is sugar for `\x.\y. b`. In a Wolfram string a backslash doubles, so the term `\x.x` is written `"\\x.x"`.
- Each bound variable is renamed to a fresh symbol when its abstraction compiles, so shadowing is capture-safe: an inner binder replaces its own occurrences before an outer one runs.
- A free variable folds to the matching Wolfram [Symbol](), so a term with unbound names returns a symbolic expression rather than a closure.
- To see the standard syntax tree for the same input instead, use [LambdaAST](), which runs the *same* grammar over the abstract-syntax algebra.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

The K combinator `(\x.\y.x) a b` projects its first argument - the kernel reduces both applications:

```wl
LambdaEval["(\\x.\\y.x) a b"]
```

<!-- => a -->

Its dual `\x.\y.y` projects the second argument:

```wl
LambdaEval["(\\x.\\y.y) a b"]
```

<!-- => b -->

The same term through [LambdaAST]() is a tree, not a value:

```wl
LambdaAST["(\\x.\\y.x) a b"]
```

<!-- => ContainerNode["String", {CallNode[CallNode[CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "y", <||>], LeafNode["Symbol", "x", <|"Source" -> {{1, 8}, {1, 9}}|>]}, <|"Source" -> {{1, 8}, {1, 9}}|>]}, <|"Source" -> {{1, 8}, {1, 9}}|>], {LeafNode["Symbol", "a", <|"Source" -> {{1, 11}, {1, 12}}|>]}, <|"Source" -> {{1, 8}, {1, 12}}|>], {LeafNode["Symbol", "b", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>] -->

## Scope

A free variable stays symbolic, folding to the matching Wolfram [Symbol]():

```wl
LambdaEval["f x"]
```

<!-- => f[x] -->

Church-numeral 2, `\f.\x.f (f x)`, applies its function argument twice - here `g` to `y`:

```wl
LambdaEval["(\\f.\\x.f (f x)) g y"]
```

<!-- => g[g[y]] -->

The `\x y. b` sugar reduces exactly like the desugared form:

```wl
LambdaEval["(\\x y.x) a b"]
```

<!-- => a -->

Church addition of 1 and 2 applies `g` three times (the second numeral binds `k` rather than the conventional `n`, since a backslash immediately followed by `n` in a Wolfram string is a newline escape):

```wl
LambdaEval["(\\m.\\k.\\f.\\x.m f (k f x)) (\\f.\\x.f x) (\\f.\\x.f (f x)) g y"]
```

<!-- => g[g[g[y]]] -->

## Properties and Relations

Because abstraction compiles to a real [Function]() with a fresh bound symbol, shadowing is capture-safe: in `(\x.\x.x) a b` the inner `x` shadows the outer, so the result is the *second* argument, not the first:

```wl
LambdaEval["(\\x.\\x.x) a b"]
```

<!-- => b -->

Calling the parser built by [LambdaGrammar]() over [LambdaSemantic]() directly does the same reduction:

```wl
LambdaGrammar[LambdaSemantic]["(\\x.\\y.x) a b"]
```

<!-- => a -->

## Possible Issues

An *unapplied* abstraction compiles to a [Function]() whose parameter is a freshly generated unique symbol (`u$nnn`), so the printed form varies from run to run. Apply the term to reach a stable value - the identity `\x.x` applied to `a` reduces to `a`:

```wl
LambdaEval["(\\x.x) a"]
```

<!-- => a -->

A partial parse is an honest [Failure](), reporting how far it got and what it expected next - here an unclosed parenthesis:

```wl
LambdaEval["(\\x.x"]
```

<!-- => Failure["ParseError", <|"Position" -> 6, "Expected" -> {")"}, "Found" -> "<end of input>"|>] -->

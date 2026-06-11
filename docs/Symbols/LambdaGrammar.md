---
Template: Symbol
Name: LambdaGrammar
Context: Wolfram`Parser`Languages`Lambda`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LambdaGrammar
Keywords: [lambda calculus, grammar, algebra, parser combinator, binder, recursion, parser zoo]
SeeAlso: [LambdaAST, LambdaEval, LambdaSemantic, ParserCombinator, ParseChoice, Parse]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LambdaGrammar]()[*alg*]</code> builds the lambda-calculus parser - a [ParserCombinator]() - over the algebra *alg*, an [Association]() of builder functions its semantic actions call.

## Details & Options

- `LambdaGrammar` is the heart of the lambda language's dual-algebra design: the grammar is written *once*, parameterized over *alg*. Hand it the abstract-syntax algebra and the same grammar emits a standard syntax tree; hand it [LambdaSemantic]() and it compiles straight to a native Wolfram closure. The grammar never changes; only the algebra does.
- The semantic actions never build output directly. They call into *alg* by key - `alg["Var"][`*name*`]` for a variable, `alg["App"][`*f*`, `*x*`]` for an application, `alg["Abs"][`*name*`, `*body*`]` for an abstraction - so swapping the algebra reroutes every action at once.
- The surface syntax is `\`*name*`.`*body* (or the unicode `λ`*name*`.`*body*) for abstraction, juxtaposition for application (left associative), and parentheses for grouping. `\x y. b` is sugar for `\x.\y. b`. The grammar is left-recursion-free: it folds a run of atoms for application and recurses through a recursion cell for the abstraction body.
- The result is a built [ParserCombinator](). Run it on input either as <code>*pc*[*input*]</code> or equivalently with <code>[Parse]()[*pc*, *input*]</code>.
- [LambdaAST]() and [LambdaEval]() are thin wrappers: `LambdaAST` runs `LambdaGrammar` over the abstract-syntax algebra (wrapping the result in a [ContainerNode]()), and `LambdaEval` runs `LambdaGrammar[LambdaSemantic]`.

## Basic Examples

Building the grammar over an algebra yields a [ParserCombinator]():

```wl
Head[LambdaGrammar[LambdaSemantic]]
```

<!-- => ParserCombinator -->

Over [LambdaSemantic](), the same input compiles to a closure and the kernel reduces it - the K combinator projects its first argument:

```wl
LambdaGrammar[LambdaSemantic]["(\\x.\\y.x) a b"]
```

<!-- => a -->

## Scope

A built grammar runs equivalently through [Parse]():

```wl
Parse[LambdaGrammar[LambdaSemantic], "(\\x.\\y.y) a b"]
```

<!-- => b -->

Application folds left-associatively across a run of atoms, so `f x y` reduces with `f` applied to `x` and then to `y`:

```wl
LambdaGrammar[LambdaSemantic]["(\\f.\\x.f (f x)) g y"]
```

<!-- => g[g[y]] -->

## Properties and Relations

[LambdaEval]() is exactly this grammar over [LambdaSemantic](); calling either gives the same reduction:

```wl
LambdaEval["(\\x y.x) a b"]
```

<!-- => a -->

```wl
LambdaGrammar[LambdaSemantic]["(\\x y.x) a b"]
```

<!-- => a -->

## Possible Issues

A grammar built over [LambdaSemantic]() returns an honest [Failure]() on input it cannot parse to completion, the same as any [Parse]() - here a `\` with no binder name:

```wl
LambdaGrammar[LambdaSemantic]["\\.x"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> {"regex /[A-Za-z][A-Za-z0-9_]*/"}, "Found" -> "."|>] -->

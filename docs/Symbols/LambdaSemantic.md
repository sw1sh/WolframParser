---
Template: Symbol
Name: LambdaSemantic
Context: Wolfram`Parser`Languages`Lambda`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LambdaSemantic
Keywords: [lambda calculus, semantics, algebra, closure, Function, beta reduction, parser zoo]
SeeAlso: [LambdaEval, LambdaGrammar, LambdaAST, Function, Association]
RelatedGuides: [ParserZoo]
---

## Usage

[LambdaSemantic]() is the algebra that compiles lambda terms to native Wolfram closures - an [Association]() of builder functions keyed `"Var"`, `"App"` and `"Abs"`.

## Details & Options

- `LambdaSemantic` is the *evaluating* algebra for the lambda grammar. Handed to [LambdaGrammar](), it turns each abstraction into a real Wolfram [Function]() and each application into real Wolfram application, so the kernel does the beta-reduction; this is exactly what [LambdaEval]() runs.
- The three builders are: `"Var"` folds a name to the matching Wolfram [Symbol](); `"App"` is real application, `f[x]`; `"Abs"` builds a closure by renaming the bound variable to a fresh symbol so application is genuine beta-reduction and shadowing stays capture-safe.
- The fresh-symbol renaming is what makes shadowing safe: because terms are built bottom-up, an inner binder has replaced its own occurrences before an outer binder runs, so substitution never captures a shadowed variable.
- It is a drop-in swap for the abstract-syntax algebra: the *same* [LambdaGrammar]() yields a standard tree over that algebra (run by [LambdaAST]()) and a closure over `LambdaSemantic`. The grammar is untouched; only the algebra differs.

## Basic Examples

The algebra is an [Association]() of three builder functions:

```wl
Keys[LambdaSemantic]
```

<!-- => {"Var", "App", "Abs"} -->

The `"Var"` builder folds a name string to the matching Wolfram [Symbol]():

```wl
LambdaSemantic["Var"]["q"]
```

<!-- => q -->

The `"App"` builder is ordinary Wolfram application:

```wl
LambdaSemantic["App"][f, x]
```

<!-- => f[x] -->

The other half of the dual design is the abstract-syntax algebra; the *same* grammar over it emits a standard tree instead of a closure, which [LambdaAST]() runs:

```wl
LambdaAST["(\\x.\\x.x) a b"]
```

<!-- => ContainerNode["String", {CallNode[CallNode[CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], CallNode[LeafNode["Symbol", "λ", <||>], {LeafNode["Symbol", "x", <||>], LeafNode["Symbol", "x", <|"Source" -> {{1, 8}, {1, 9}}|>]}, <|"Source" -> {{1, 8}, {1, 9}}|>]}, <|"Source" -> {{1, 8}, {1, 9}}|>], {LeafNode["Symbol", "a", <|"Source" -> {{1, 11}, {1, 12}}|>]}, <|"Source" -> {{1, 8}, {1, 12}}|>], {LeafNode["Symbol", "b", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>] -->

## Scope

Handed to [LambdaGrammar](), the algebra builds a parser that compiles terms to closures the kernel reduces - the K combinator projects its first argument:

```wl
LambdaGrammar[LambdaSemantic]["(\\x.\\y.x) a b"]
```

<!-- => a -->

This is exactly what [LambdaEval]() runs, so the two agree:

```wl
LambdaEval["(\\x.\\y.x) a b"]
```

<!-- => a -->

## Properties and Relations

Because the `"Abs"` builder renames each bound variable to a fresh symbol, shadowing is capture-safe. The neutral tree above keeps both binders named `x`; over `LambdaSemantic` the *same* term reduces, and the inner binder shadows the outer, so the result is the *second* argument:

```wl
LambdaGrammar[LambdaSemantic]["(\\x.\\x.x) a b"]
```

<!-- => b -->

This is exactly what [LambdaEval]() runs, so the two agree:

```wl
LambdaEval["(\\x.\\x.x) a b"]
```

<!-- => b -->

## Neat Examples

Church-numeral 2, `\f.\x.f (f x)`, compiles to a closure that applies its function argument twice - `g` to `y` gives `g[g[y]]`:

```wl
LambdaGrammar[LambdaSemantic]["(\\f.\\x.f (f x)) g y"]
```

<!-- => g[g[y]] -->

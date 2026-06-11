---
Template: Symbol
Name: CalculatorGrammar
Context: Wolfram`Parser`Languages`Calculator`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/CalculatorGrammar
Keywords: [calculator, grammar, algebra, parser combinator, operator table, parser zoo]
SeeAlso: [CalculatorAST, CalculatorEval, CalculatorSemantic, ASTAlgebra, ParseOperatorTable, ParserCombinator]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[CalculatorGrammar]()[*alg*]</code> builds the calculator parser - a [ParserCombinator]() - over the algebra *alg*, an [Association]() of builder functions its semantic actions call.

## Details & Options

- `CalculatorGrammar` is the heart of the calculator's dual-algebra design: the grammar is written *once*, parameterized over *alg*. Hand it [ASTAlgebra]() and the same grammar emits a standard syntax tree; hand it [CalculatorSemantic]() and it folds straight to a number. The grammar never changes; only the algebra does.
- The semantic actions never construct nodes directly. They call into *alg* by key - `alg["Leaf"][kind, src]`, `alg["Binary"][op, l, r]`, `alg["Prefix"][op, x]` - so swapping the algebra reroutes every action at once.
- The grammar covers `+` `-` `*` `/` `^`, unary minus, parentheses, integer and real literals, and bare identifiers. Precedence is set by [ParseOperatorTable](), the library's Pratt / precedence-climbing combinator: tightest first, parentheses, unary minus, `^` (right associative), `*` `/`, `+` `-`.
- The result is a built [ParserCombinator](). Run it on input either as <code>*pc*[*input*]</code> or equivalently with <code>[Parse]()[*pc*, *input*]</code>.
- [CalculatorAST]() and [CalculatorEval]() are thin wrappers: `CalculatorAST` runs `CalculatorGrammar[ASTAlgebra]` (wrapping the result in a [ContainerNode]()), and `CalculatorEval` runs `CalculatorGrammar[CalculatorSemantic]`.

## Basic Examples

Building the grammar over an algebra yields a [ParserCombinator]():

```wl
Head[CalculatorGrammar[CalculatorSemantic]]
```

<!-- => ParserCombinator -->

The two algebras share this one grammar. Over [CalculatorSemantic](), the same input folds to a number:

```wl
CalculatorGrammar[CalculatorSemantic]["1+2*3"]
```

<!-- => 7 -->

Over [ASTAlgebra](), the same grammar emits a standard syntax-tree node instead:

```wl
CalculatorGrammar[ASTAlgebra]["1+2"]
```

<!-- => BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {1, 2}|>], LeafNode["Integer", "2", <|"Source" -> {3, 4}|>]}, <||>] -->

## Scope

A built grammar runs equivalently through [Parse]():

```wl
Parse[CalculatorGrammar[ASTAlgebra], "1+2"]
```

<!-- => BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {1, 2}|>], LeafNode["Integer", "2", <|"Source" -> {3, 4}|>]}, <||>] -->

Unary minus routes through the algebra's `"Prefix"` builder, so the [ASTAlgebra]() form is a [PrefixNode]():

```wl
CalculatorGrammar[ASTAlgebra]["-x"]
```

<!-- => PrefixNode["-", LeafNode["Symbol", "x", <|"Source" -> {2, 3}|>], <||>] -->

## Properties and Relations

[CalculatorAST]() wraps the [ASTAlgebra]() grammar's result in a [ContainerNode]() root and resolves each `"Source"` span into a line-column pair `{{line, col}, {line, col}}`; the grammar alone returns the bare node, whose leaves still carry the raw character offsets `{start, end}`:

```wl
CalculatorAST["1+2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

```wl
CalculatorGrammar[ASTAlgebra]["1+2"]
```

<!-- => BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {1, 2}|>], LeafNode["Integer", "2", <|"Source" -> {3, 4}|>]}, <||>] -->

## Possible Issues

A grammar built over [CalculatorSemantic]() returns an honest [Failure]() on input it cannot parse to completion, the same as any [Parse]():

```wl
CalculatorGrammar[CalculatorSemantic]["1 +"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> {"(", "regex /[0-9]+\\.[0-9]+|[0-9]+/", "regex /[A-Za-z][A-Za-z0-9]*/"}, "Found" -> "<end of input>"|>] -->

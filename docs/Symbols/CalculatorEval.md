---
Template: Symbol
Name: CalculatorEval
Context: Wolfram`Parser`Languages`Calculator`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/CalculatorEval
Keywords: [calculator, evaluate, arithmetic, fold, semantic, parser zoo]
SeeAlso: [CalculatorAST, CalculatorGrammar, CalculatorSemantic, ASTAlgebra, ParseOperatorTable]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[CalculatorEval]()[*expr*]</code> parses the arithmetic expression string *expr* and evaluates it to a Wolfram number; bare identifiers stay symbolic.

## Details & Options

- `CalculatorEval` is the *evaluating* mode of the calculator grammar: it runs [CalculatorGrammar]() over [CalculatorSemantic](), the algebra whose builders fold each node straight to a Wolfram value.
- The grammar covers `+` `-` `*` `/` `^`, unary minus, parentheses, integer and real literals, and bare identifiers. Precedence, tightest first: parentheses, unary minus, `^` (right associative), `*` `/`, `+` `-`.
- Folding happens *during* the parse: there is no intermediate tree. To see the standard syntax tree for the same input instead, use [CalculatorAST](), which runs the *same* grammar over [ASTAlgebra]().
- An integer literal folds with [FromDigits]() and a real literal with [ToExpression](), so `"7/2"` stays an exact [Rational]() and `"1.5"` is a machine [Real]().
- An identifier folds to the matching Wolfram [Symbol](), so the result can carry unbound variables and is simplified by ordinary evaluation ([Plus](), [Times]() and friends).
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

Multiplication binds tighter than addition, and the result is a number, not a tree:

```wl
CalculatorEval["1 + 2*3"]
```

<!-- => 7 -->

Parentheses override precedence:

```wl
CalculatorEval["(1+2)*3"]
```

<!-- => 9 -->

Exponentiation is right associative, so this is `2^(3^2)`:

```wl
CalculatorEval["2^3^2"]
```

<!-- => 512 -->

## Scope

Division of integers stays exact, since the [Binary]() builder folds with ordinary [Times]() and [Power]():

```wl
CalculatorEval["7/2"]
```

<!-- => 7/2 -->

A real literal makes the whole expression inexact:

```wl
CalculatorEval["1.5 + 2"]
```

<!-- => 3.5 -->

Unary minus is a prefix operator, looser than `^` but tighter than the infix operators:

```wl
CalculatorEval["-3 + 4"]
```

<!-- => 1 -->

A bare identifier folds to a [Symbol](), so the value can stay symbolic:

```wl
CalculatorEval["2*x + 3*y"]
```

<!-- => 2*x + 3*y -->

## Properties and Relations

`CalculatorEval` and [CalculatorAST]() share one grammar and differ only in the algebra. The tree form keeps the literal source text and structure; the eval form collapses it to a value:

```wl
CalculatorAST["1 + 2*3"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], BinaryNode["*", {LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 5}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>] -->

```wl
CalculatorEval["1 + 2*3"]
```

<!-- => 7 -->

Calling the parser built by [CalculatorGrammar]() over [CalculatorSemantic]() directly does the same fold:

```wl
CalculatorGrammar[CalculatorSemantic]["1 + 2*3"]
```

<!-- => 7 -->

## Possible Issues

A partial parse is an honest [Failure](), reporting how far it got and what it expected next:

```wl
CalculatorEval["1 +"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> {"(", "regex /[0-9]+\\.[0-9]+|[0-9]+/", "regex /[A-Za-z][A-Za-z0-9]*/"}, "Found" -> "<end of input>"|>] -->

An unexpected character fails at its position rather than being silently dropped:

```wl
CalculatorEval["1 + @"]
```

<!-- => Failure["ParseError", <|"Position" -> 5, "Expected" -> {"(", "regex /[0-9]+\\.[0-9]+|[0-9]+/", "regex /[A-Za-z][A-Za-z0-9]*/"}, "Found" -> "@"|>] -->

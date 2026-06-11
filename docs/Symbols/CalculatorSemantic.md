---
Template: Symbol
Name: CalculatorSemantic
Context: Wolfram`Parser`Languages`Calculator`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/CalculatorSemantic
Keywords: [calculator, algebra, semantic, fold, builder functions, parser zoo]
SeeAlso: [CalculatorEval, CalculatorGrammar, CalculatorAST, ASTAlgebra, ParseOperatorTable]
RelatedGuides: [ParserZoo]
---

## Usage

[CalculatorSemantic]() is the algebra - an [Association]() of builder functions - that folds the calculator parse to a numeric or symbolic Wolfram value.

## Details & Options

- `CalculatorSemantic` is one of the *two* algebras the calculator grammar runs over. It is the meaningful, language-specific one: each builder maps a parsed construct directly to its arithmetic value. The neutral alternative is [ASTAlgebra](), which builds a standard syntax tree instead.
- It is a plain [Association]() with three keys: `"Leaf"`, `"Binary"`, and `"Prefix"`. [CalculatorGrammar]()'s semantic actions look up these keys, so the algebra *is* the language's meaning - swap it and the same grammar means something else.
- `"Leaf"` turns matched source text into a value by kind: an `"Integer"` folds with [FromDigits](), a `"Real"` with [ToExpression](), and anything else (a `"Symbol"`) becomes the matching Wolfram [Symbol]().
- `"Binary"` maps an operator descriptor to the matching Wolfram operation ([Plus](), [Subtract](), [Times](), [Divide](), [Power]()); `"Prefix"` negates for `"-"` and is the identity otherwise.
- [CalculatorEval]() is just [CalculatorGrammar]()`[CalculatorSemantic]` packaged as a function. To get the standard tree for the same grammar, run it over [ASTAlgebra]() instead.

## Basic Examples

The algebra is an [Association]() of builder functions, keyed by node role:

```wl
Keys[CalculatorSemantic]
```

<!-- => {"Leaf", "Binary", "Prefix"} -->

The `"Leaf"` builder interprets matched source text. An integer kind folds with [FromDigits]():

```wl
CalculatorSemantic["Leaf"]["Integer", "42"]
```

<!-- => 42 -->

A `"Symbol"` leaf becomes the matching Wolfram [Symbol](), keeping the value open:

```wl
CalculatorSemantic["Leaf"]["Symbol", "x"]
```

<!-- => x -->

The `"Binary"` builder maps an operator descriptor onto the Wolfram operation:

```wl
CalculatorSemantic["Binary"]["+", 1, 2]
```

<!-- => 3 -->

## Scope

A `"Real"` leaf folds with [ToExpression](), giving a machine [Real]():

```wl
CalculatorSemantic["Leaf"]["Real", "1.5"]
```

<!-- => 1.5 -->

The `"Prefix"` builder negates for the `"-"` descriptor:

```wl
CalculatorSemantic["Prefix"]["-", 5]
```

<!-- => -5 -->

## Properties and Relations

`CalculatorSemantic` is the algebra that drives [CalculatorEval]() - running [CalculatorGrammar]() over it folds an input string to a value:

```wl
CalculatorGrammar[CalculatorSemantic]["1+2*3"]
```

<!-- => 7 -->

It is one of a pair. [ASTAlgebra]() shares the same builder-key protocol but carries more keys and builds nodes rather than values:

```wl
Keys[ASTAlgebra]
```

<!-- => {"Leaf", "Prefix", "Postfix", "Binary", "Infix", "Ternary", "Call", "Group", "Container"} -->

Where `CalculatorSemantic`'s `"Leaf"` folds to a number, [ASTAlgebra]()'s keeps the literal source text in a [LeafNode]():

```wl
ASTAlgebra["Leaf"]["Integer", "1"]
```

<!-- => LeafNode["Integer", "1", <||>] -->

## Neat Examples

Because the algebra is a plain [Association](), a single key can be overridden to retarget the language. Folding `"+"` to [Subtract]() makes addition mean subtraction, while every other rule stays put:

```wl
twist = <|CalculatorSemantic, "Binary" -> Function[{op, l, r}, If[op === "+", l - r, CalculatorSemantic["Binary"][op, l, r]]]|>;
CalculatorGrammar[twist]["10 + 3"]
```

<!-- => 7 -->

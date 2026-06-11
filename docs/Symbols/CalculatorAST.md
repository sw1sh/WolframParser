---
Template: Symbol
Name: CalculatorAST
Context: Wolfram`Parser`Languages`Calculator`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/CalculatorAST
Keywords: [calculator, AST, syntax tree, arithmetic, parser zoo]
SeeAlso: [CalculatorEval, CalculatorGrammar, BinaryNode, PrefixNode, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[CalculatorAST]()[*expr*]</code> parses the arithmetic expression string *expr* to a standard syntax tree - a [ContainerNode]() of [BinaryNode](), [PrefixNode]() and [LeafNode]().

## Details & Options

- `CalculatorAST` is the standard-AST mode of the calculator grammar: it runs [CalculatorGrammar]() over the shared [ASTAlgebra](), so the result carries no language-specific meaning, only structure.
- The grammar covers `+` `-` `*` `/` `^`, unary minus, parentheses, integer and real literals, and bare identifiers. Precedence, tightest first: parentheses, unary minus, `^` (right associative), `*` `/`, `+` `-`.
- [CalculatorEval]() runs the *same* grammar over [CalculatorSemantic]() instead, evaluating to a number. The grammar is written once; only the algebra differs.
- A [LeafNode]() keeps the literal source text (`"1"`, not `1`); the value is only interpreted in the [CalculatorEval]() mode.
- Every node carries a `"Source"` span in its metadata, a [CodeParser]() line-column pair `{{startLine, startCol}, {endLine, endCol}}`. A leaf spans its own text; a composite spans its children, so a multi-line input gives a span whose endpoints sit on different lines.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

The tree nests by precedence - `*` binds tighter than `+`:

```wl
CalculatorAST["1 + 2*3"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], BinaryNode["*", {LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 5}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>] -->

Unary minus is a [PrefixNode](), and an identifier is a `"Symbol"` [LeafNode]():

```wl
CalculatorAST["-x"]
```

<!-- => ContainerNode["String", {PrefixNode["-", LeafNode["Symbol", "x", <|"Source" -> {{1, 2}, {1, 3}}|>], <|"Source" -> {{1, 2}, {1, 3}}|>]}, <|"Source" -> {{1, 2}, {1, 3}}|>] -->

The same source through [CalculatorEval]() is a number, not a tree:

```wl
CalculatorEval["1 + 2*3"]
```

<!-- => 7 -->

## Scope

Every node records a `"Source"` span as a line-column pair. Each [LeafNode]() spans its own text and each composite spans its children, so the `+` [BinaryNode]() here runs from column 1 to column 6:

```wl
CalculatorAST["1 + 2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>] -->

The span crosses lines when the input does. With the `2` on line 2, its leaf reads `{{2, 1}, {2, 2}}` and the enclosing [BinaryNode]() spans both lines:

```wl
CalculatorAST["1 +\n2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{2, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 1}, {2, 2}}|>] -->

## Properties and Relations

The neutral nodes project onto Wolfram's own [CodeParser]() shape with [ToCodeParser](), mapping each operator descriptor to a Wolfram symbol:

```wl
ToCodeParser[CalculatorAST["1+2"], <|"+" -> Plus|>]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>], {CodeParser`LeafNode[Integer, "1", <|"Source" -> {{1, 1}, {1, 2}}|>], CodeParser`LeafNode[Integer, "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

## Possible Issues

A partial parse is an honest [Failure](), reporting how far it got and what it expected:

```wl
CalculatorAST["1 +"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> {"(", "regex /[0-9]+\\.[0-9]+|[0-9]+/", "regex /[A-Za-z][A-Za-z0-9]*/"}, "Found" -> "<end of input>"|>] -->

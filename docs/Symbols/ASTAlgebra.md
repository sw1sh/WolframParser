---
Template: Symbol
Name: ASTAlgebra
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ASTAlgebra
Keywords: [AST, algebra, syntax tree, builder, parser zoo, semantic action, CodeParser]
SeeAlso: [ASTContainer, ASTNodeQ, ASTLeafQ, ToCodeParser, SpannedToken, ASTAddSource, BinaryNode, LeafNode]
RelatedGuides: [ParserZoo]
---

## Usage

[ASTAlgebra]() is the [Association]() of builder functions that emit the standard AST nodes. A grammar written over an *algebra* - an [Association]() its semantic actions call - produces a standard syntax tree when handed `ASTAlgebra`.

## Details & Options

- An *algebra* is the indirection at the heart of the parser zoo: a grammar builder takes an algebra *alg* and its actions call `alg["Binary"][op, l, r]`, `alg["Leaf"][kind, src]`, and so on, never naming a node head directly. Feed the grammar `ASTAlgebra` and it builds a standard tree; feed it the language's own semantic algebra and the *same* grammar yields a meaningful value. The grammar is untouched; only the algebra is swapped.
- The keys are the node *constructors*: `"Leaf"`, `"Prefix"`, `"Postfix"`, `"Binary"`, `"Infix"`, `"Ternary"`, `"Call"`, `"Group"`, `"Container"`. Each maps to a function that returns the matching node with empty `<||>` metadata.
- The standard nodes mirror Wolfram's own [CodeParser]() shape - a 3-slot `Head[descriptor, children, <|meta|>]` triple - but operator descriptors stay language-native strings (`"+"`, `":"`, `"'"`) rather than being forced into Wolfram symbols. [ToCodeParser]() projects a neutral tree onto `CodeParser`-exact nodes when that is wanted.
- Extend it for language-specific constructs that map onto a standard node: `<|ASTAlgebra, "Object" -> (GroupNode["Object", #, <||>] &)|>`.
- `ASTAlgebra` is the *bare* builder: each function emits a node with empty `<||>` metadata and no `Source`. Source positions are added afterwards - [SpannedToken]() captures a leaf's character span at parse time, and [ASTAddSource]() spans the composites and converts to `{{line, col}, {line, col}}`. A language entry point like [CalculatorAST]() wires both in, so its output carries `Source`; the algebra builders called in isolation do not.

## Basic Examples

The `"Binary"` builder makes a [BinaryNode]() from an operator descriptor and two children:

```wl
ASTAlgebra["Binary"]["+", LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]]
```

<!-- => BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>] -->

The `"Leaf"` builder makes a terminal from a kind descriptor and the matched source text:

```wl
ASTAlgebra["Leaf"]["Integer", "42"]
```

<!-- => LeafNode["Integer", "42", <||>] -->

The nine builder keys:

```wl
Keys[ASTAlgebra]
```

<!-- => {"Leaf", "Prefix", "Postfix", "Binary", "Infix", "Ternary", "Call", "Group", "Container"} -->

## Scope

The `"Prefix"` builder makes a [PrefixNode]() - an operator descriptor and its operand:

```wl
ASTAlgebra["Prefix"]["-", LeafNode["Symbol", "x", <||>]]
```

<!-- => PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>] -->

The `"Call"` builder makes a [CallNode]() - a head node and its argument list:

```wl
ASTAlgebra["Call"][LeafNode["Symbol", "f", <||>], {LeafNode["Integer", "1", <||>]}]
```

<!-- => CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Integer", "1", <||>]}, <||>] -->

The `"Group"` builder makes a delimited [GroupNode]() - a kind descriptor and its children:

```wl
ASTAlgebra["Group"]["Array", {LeafNode["Integer", "1", <||>]}]
```

<!-- => GroupNode["Array", {LeafNode["Integer", "1", <||>]}, <||>] -->

The `"Container"` builder makes the root [ContainerNode]() that wraps the top-level forms:

```wl
ASTAlgebra["Container"][{LeafNode["Integer", "1", <||>]}]
```

<!-- => ContainerNode["String", {LeafNode["Integer", "1", <||>]}, <||>] -->

## Properties and Relations

Feeding a grammar `ASTAlgebra` yields a standard tree. [CalculatorAST]() runs the calculator grammar over `ASTAlgebra`, so its actions build [BinaryNode]() / [LeafNode]() and the precedence shows in the nesting. It also wires in [SpannedToken]() and [ASTAddSource](), so the finished tree carries `Source -> {{line, col}, {line, col}}` that the bare builders above never add:

```wl
CalculatorAST["1 + 2*3"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], BinaryNode["*", {LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 5}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>] -->

The very same grammar over [CalculatorSemantic]() instead computes a number - the actions call `alg["Binary"]["+", l, r]` either way, but the algebra makes the `"+"` build a [BinaryNode]() here and add there:

```wl
CalculatorEval["1 + 2*3"]
```

<!-- => 7 -->

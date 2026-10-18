---
Template: Symbol
Name: ABCSemantic
Context: Wolfram`Parser`Languages`ABC`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ABCSemantic
Keywords: [ABC, algebra, semantic, plain data, parser zoo]
SeeAlso: [ABCRun, ABCGrammar, ABCAST, ASTAlgebra]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingABC, ParserZoo]
---

## Usage

[ABCSemantic]() is the algebra, an [Association]() of builder functions, that makes [ABCGrammar]() build an ABC program as plain Wolfram data.

## Details & Options

- A program becomes a list of statements: `{"print", `*expr*`}`, `{"stop"}` and `{"define", `*name*`, `*expr*`}`.
- An expression is an integer, a name as a lower-case string, `{`*op*`, `*left*`, `*right*`}` with *op* one of `"+"`, `"-"`, `"*"`, `"/"`, `"%"`, or `{"call", `*name*`, {`*args*`}}`.
- Names are lower-cased, since ABC names are case insensitive.
- [ABCRun]() parses with [ABCGrammar]()`[ABCSemantic]` and executes the data on the ABC machine. [ABCAST]() runs the same grammar over [ASTAlgebra]() instead.

## Basic Examples

The algebra's builders, by construct:

```wl
Keys[ABCSemantic]
```

<!-- => {"Leaf", "Binary", "Call", "Print", "Stop", "Define", "Program"} -->

A program as the data [ABCRun]() executes:

```wl
Parse[ABCGrammar[ABCSemantic], "Fact = fact(t - 1) * t + (1 - t)\nprint FACT(5)"]
```

<!-- => {{"define", "fact", {"+", {"*", {"call", "fact", {{"-", "t", 1}}}, "t"}, {"-", 1, "t"}}}, {"print", {"call", "fact", {5}}}} -->

## Properties & Relations

[ABCRun]() executes that data:

```wl
ABCRun["Fact = fact(t - 1) * t + (1 - t)\nprint FACT(5)"]
```

<!-- => {120} -->

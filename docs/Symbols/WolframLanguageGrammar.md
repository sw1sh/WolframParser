---
Template: Symbol
Name: WolframLanguageGrammar
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageGrammar
Keywords: [Wolfram Language, grammar, algebra, operator table, precedence, CodeParser, parser zoo]
SeeAlso: [WolframLanguageHeld, WolframLanguageConcrete, WolframLanguageAST, WolframLanguageSemantic, ParseOperatorTable, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageGrammar]()[*alg*]</code> builds the Wolfram Language parser, a [ParserCombinator](), over the algebra *alg*; the parser gives the list of the top-level expressions of a source.

## Details & Options

- *alg* has the keys of [ASTAlgebra](): `"Leaf"`, `"Prefix"`, `"Postfix"`, `"Binary"`, `"Infix"`, `"Ternary"`, `"Call"` and `"Group"`. The grammar calls them with operators named by their heads, `alg["Infix"]["Plus", terms]` for a sum. [ASTAlgebra]() gives a syntax tree, [WolframLanguageSemantic]() held expressions.
- The expression grammar is one [ParseOperatorTable]() whose levels are generated from the precedences [CodeParser]() publishes. Flat operators are its `"InfixN"` chains, `a ~f~ b` its `"Ternary"`.
- Forms whose operands are optional or are not expressions (`a ;; b`, a trailing `;`, `t /: lhs = rhs`, `f::tag`, `x >> file`) are postfix operators whose own parser reads those operands.
- The grammar is built twice over, for two kinds of whitespace: outside brackets the whitespace after an operand stops at a newline, so the expression can end there; inside brackets and after an operator it takes newlines too.
- An operator token is the longest operator there: `-` is not read where `->`, `--` or `-=` is.
- Building the grammar takes a fraction of a second; [WolframLanguageHeld]() and [WolframLanguageAST]() build theirs once, at their first use.

## Basic Examples

The grammar over [ASTAlgebra]():

```wl
astGrammar = WolframLanguageGrammar[ASTAlgebra]
```

It gives the list of top-level expressions, here one:

```wl
ASTStripSource[Parse[astGrammar, "a + b"]]
```

<!-- => {InfixNode["Plus", {LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "b", <||>]}, <||>]} -->

## Scope

Over [WolframLanguageSemantic](), each expression is a node whose `"Expr"` is the expression held:

```wl
heldGrammar = WolframLanguageGrammar[WolframLanguageSemantic]
```

```wl
Lookup[Parse[heldGrammar, "x_ /; x > 0 :> -x"], "Expr"]
```

<!-- => {HoldComplete[x_ /; x > 0 :> -x]} -->

## Properties and Relations

[WolframLanguageHeld]() runs the grammar over [WolframLanguageSemantic]() and takes each node's expression:

```wl
WolframLanguageHeld["x_ /; x > 0 :> -x"]
```

<!-- => {HoldComplete[x_ /; x > 0 :> -x]} -->

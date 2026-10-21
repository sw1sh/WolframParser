---
Template: Symbol
Name: WolframLanguageAST
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageAST
Keywords: [Wolfram Language, AST, syntax tree, CodeParser, source spans, parser zoo]
SeeAlso: [WolframLanguageHeld, WolframLanguageGrammar, ASTAlgebra, InfixNode, ASTAddSource]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageAST]()[*code*]</code> parses the Wolfram Language source string *code* to a standard syntax tree: a [ContainerNode]() of its top-level expressions.

## Details & Options

- `WolframLanguageAST` runs [WolframLanguageGrammar]() over the shared [ASTAlgebra](), so the tree carries structure only. [WolframLanguageHeld]() runs the same grammar over [WolframLanguageSemantic]() and gives held expressions.
- Each operator is named by the head it stands for: `"Plus"`, `"SetDelayed"`, `"PatternTest"`. A flat chain is one [InfixNode]() (`a + b + c`), a binary operator a [BinaryNode](), a call `f[x]` a [CallNode](), and `a ~f~ b`, `f @ x` and `x // f` are calls of `f` too.
- A term after a `-` is a [PrefixNode]() `"Minus"` inside the sum's [InfixNode]() `"Plus"`; a chain of different relations is an [InfixNode]() `"Inequality"` whose operands alternate with the relations' names, as [Inequality]() takes them.
- Parentheses, lists and associations are [GroupNode]() `"Paren"`, `"List"` and `"Association"`.
- A leaf keeps its source text: a [LeafNode]() of kind `"Integer"`, `"Real"`, `"String"`, `"Symbol"`, `"Blank"` (`x_h`), `"Slot"`, `"Out"`, `"Tag"` (the tag of `f::tag`) or `"File"` (the file of `<<` and `>>`).
- Every node carries a `"Source"` span `{{line, column}, {line, column}}`, added by [ASTAddSource]().

## Basic Examples

A definition as a tree:

```wl
WolframLanguageAST["f[x_] := x^2"]
```

Without the source spans, the structure reads more easily:

```wl
ASTStripSource[WolframLanguageAST["a - b c"]]
```

## Scope

A relation chain names its relations between its operands:

```wl
ASTStripSource[WolframLanguageAST["a < b <= c"]]
```

The span of an expression crosses lines when the expression does:

```wl
WolframLanguageAST["a +\n  b"][[2, 1, 3, "Source"]]
```

<!-- => {{1, 1}, {2, 4}} -->

## Properties and Relations

[ToCodeParser]() turns the tree into [CodeParser]()'s nodes:

```wl
ToCodeParser[ASTStripSource[WolframLanguageAST["a + b"]], <|"Plus" -> Plus|>]
```

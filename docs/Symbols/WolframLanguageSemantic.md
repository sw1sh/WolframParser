---
Template: Symbol
Name: WolframLanguageSemantic
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageSemantic
Keywords: [Wolfram Language, algebra, semantic, held expressions, HoldComplete, parser zoo]
SeeAlso: [WolframLanguageGrammar, WolframLanguageHeld, ASTAlgebra, HoldComplete]
RelatedGuides: [ParserZoo]
---

## Usage

[WolframLanguageSemantic]() is the algebra that builds each expression of a Wolfram Language source held, as the kernel reads it.

## Details & Options

- It has the keys of [ASTAlgebra](), so [WolframLanguageGrammar]() runs over either. Where [ASTAlgebra]() makes a node, `WolframLanguageSemantic` makes an [Association]() whose `"Expr"` is the expression in [HoldComplete]().
- Two more keys tell the forms a minus treats apart: `"Literal"` is [True]() for a number as written, into which a minus folds (`-2`, also `-(2)`), and `"Chain"` for a product written as one (`b c`), whose factors a minus joins (`a - b c` is `Plus[a, Times[-1, b, c]]`). Parentheses keep the first and drop the second.
- `"Binary"` gives `a/b` as `Times[a, Power[b, -1]]`; every other operator is a call of the head it is named by.
- `"Leaf"` reads a number and a string from its text: `1.5`20` is a real of precision 20, a real of more digits than a machine real holds keeps the accuracy they give, and `"\[Alpha]\n"` decodes its escapes. A blank `x_h` is `Pattern[x, Blank[h]]`, `#2` is `Slot[2]` and `%%` is `Out[-2]`. A name is the one leaf the kernel's reader reads, under [HoldComplete](), since nothing else makes a symbol from its name without evaluating it.

## Basic Examples

`WolframLanguageSemantic` is keyed by the builders [WolframLanguageGrammar]() calls:

```wl
Keys[WolframLanguageSemantic]
```

<!-- => {"Leaf", "Prefix", "Postfix", "Binary", "Infix", "Ternary", "Call", "Group"} -->

A leaf is the token's expression, held:

```wl
WolframLanguageSemantic["Leaf"]["Blank", "x__Integer"]["Expr"]
```

<!-- => HoldComplete[x__Integer] -->

## Scope

A real with a precision mark keeps its precision:

```wl
WolframLanguageSemantic["Leaf"]["Real", "0.1`20"]["Expr"]
```

<!-- => HoldComplete[0.1`20.] -->

A minus folds into a number:

```wl
WolframLanguageSemantic["Prefix"]["Minus", WolframLanguageSemantic["Leaf"]["Integer", "2"]]["Expr"]
```

<!-- => HoldComplete[-2] -->

A quotient is a product with a power:

```wl
FullForm[WolframLanguageSemantic["Binary"]["Divide", WolframLanguageSemantic["Leaf"]["Symbol", "a"], WolframLanguageSemantic["Leaf"]["Symbol", "b"]]["Expr"]]
```

<!-- => FullForm[HoldComplete[a/b]] -->

## Properties and Relations

[WolframLanguageHeld]() is [WolframLanguageGrammar]() over `WolframLanguageSemantic`:

```wl
WolframLanguageHeld["a - 2 b"]
```

<!-- => {HoldComplete[a - 2*b]} -->

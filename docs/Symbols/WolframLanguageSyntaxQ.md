---
Template: Symbol
Name: WolframLanguageSyntaxQ
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageSyntaxQ
Keywords: [Wolfram Language, syntax, syntax check, SyntaxQ, incomplete input, parser zoo]
SeeAlso: [WolframLanguageSyntaxLength, WolframLanguageHeld, WolframLanguageHeldNext, SyntaxQ, SyntaxLength, ToExpression]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageSyntaxQ]()[*code*]</code> gives [True]() if the string *code* is Wolfram Language source that reads without a syntax error, and [False]() otherwise.

## Details & Options

- `WolframLanguageSyntaxQ` gives what [SyntaxQ]() gives for *code*, by the compiled lexer and parser that [WolframLanguageHeld]() reads with, and builds no expression: checking a source makes none of its names.
- A source of several statements, one to a line, reads when each of its statements does, as [ToExpression]() reads them.
- A source that ends before its expression does, such as an opener with no closer or an operator with no operand after it, does not read; nor does a closer that no opener matches, or a token that no expression can hold where it is.
- A source of only whitespace and comments reads. The empty string does not, as [SyntaxQ]() gives for it.
- Linear syntax reads where each of its groups closes.
- A statement that the compiled parser does not take is read by [WolframLanguageHeld](), which builds it.

## Basic Examples

A definition that reads:

```wl
WolframLanguageSyntaxQ["f[x_] := x^2 + 1"]
```

<!-- => True -->

The same definition cut short:

```wl
WolframLanguageSyntaxQ["f[x_] := x^2 +"]
```

<!-- => False -->

## Scope

A source of several lines reads when each of its statements does:

```wl
WolframLanguageSyntaxQ["a = 1\nb = a + 1\n(* done *)"]
```

<!-- => True -->

A closer that no opener matches:

```wl
WolframLanguageSyntaxQ["f[x]]"]
```

<!-- => False -->

A pattern takes a default after a colon, here the second alternative's:

```wl
WolframLanguageSyntaxQ["f[x_ | y_ : 1] := {x, y}"]
```

<!-- => True -->

A group of boxes written as linear syntax, read as input:

```wl
WolframLanguageSyntaxQ["\\!\\(x\\^2\\) + 1"]
```

<!-- => True -->

## Properties and Relations

Some sources that read and some that do not:

```wl
sources = {"a + b", "a +", "f[x", "f[x]]", "(* c *)", "x_ : 1", "f[x] : 1", "a ~ b ~ c", "a ~ b c"}
```

<!-- => {"a + b", "a +", "f[x", "f[x]]", "(* c *)", "x_ : 1", "f[x] : 1", "a ~ b ~ c", "a ~ b c"} -->

`WolframLanguageSyntaxQ` gives what [SyntaxQ]() gives for each:

```wl
WolframLanguageSyntaxQ /@ sources === SyntaxQ /@ sources
```

<!-- => True -->

Checking a source makes none of its names:

```wl
WolframLanguageSyntaxQ["aNameOnlyChecked + 1"]
```

<!-- => True -->

```wl
Names["*`aNameOnlyChecked"]
```

<!-- => {} -->

[WolframLanguageSyntaxLength]() gives how many characters of a source read:

```wl
WolframLanguageSyntaxLength["a + b) + c"]
```

<!-- => 5 -->

## Possible Issues

Only a pattern takes a default after a colon, so a colon after any other expression is a syntax error:

```wl
WolframLanguageSyntaxQ["f[x] : 1"]
```

<!-- => False -->

The empty string does not read, though a source of only whitespace does:

```wl
WolframLanguageSyntaxQ[""]
```

<!-- => False -->

```wl
WolframLanguageSyntaxQ[" "]
```

<!-- => True -->

---
Template: Symbol
Name: WolframLanguageSyntaxLength
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageSyntaxLength
Keywords: [Wolfram Language, syntax, syntax error, SyntaxLength, incomplete input, error position, parser zoo]
SeeAlso: [WolframLanguageSyntaxQ, WolframLanguageHeld, WolframLanguageHeldNext, SyntaxLength, SyntaxQ, ToExpression]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageSyntaxLength]()[*code*]</code> gives the number of characters at the start of the Wolfram Language source string *code* that read, as [SyntaxLength]() counts them.

## Details & Options

- `WolframLanguageSyntaxLength` gives what [SyntaxLength]() gives for *code*, by the compiled lexer and parser that [WolframLanguageHeld]() reads with, and builds no expression: counting makes none of the source's names.
- For a source that reads, the result is its length.
- For a source with a syntax error, the result is the number of characters before the token that no expression can hold where it is, such as a closer that no opener matches.
- For a source that ends before its expression does, the result is past its length, by 2.
- A line continuation, a backslash at the end of a line, is counted with the token after it, but with a name or a number that it continues.
- A comment or a string that the source does not close stops reading at the position it begins at, or, for a string that begins a statement after the first line, at the newline that ends the line before; where it begins the source, the result is the length of the source.
- A long name that no character has stops reading before it, or before the name it is joined to, as does a name that ends with a context mark; where that begins the source, the result is the length of the source.
- A `::` with no tag after it stops reading at its position where it directly follows the symbol a message name begins with, and before it otherwise.
- A statement that the compiled parser does not take is read by [WolframLanguageHeld](), which builds it.

## Basic Examples

All of a source that reads:

```wl
WolframLanguageSyntaxLength["f[x_] := x^2"]
```

<!-- => 12 -->

The characters before a closer that no opener matches:

```wl
WolframLanguageSyntaxLength["f[x_] := x^2]"]
```

<!-- => 12 -->

A source that ends before its expression does gives a number past its length:

```wl
WolframLanguageSyntaxLength["f[x_] := x^2 +"]
```

<!-- => 16 -->

## Scope

Reading stops at the first statement that cannot be read; the statements before it count in full:

```wl
WolframLanguageSyntaxLength["a = 1\nb = (c))"]
```

<!-- => 13 -->

An opener that the source does not close leaves its expression incomplete:

```wl
WolframLanguageSyntaxLength["<|a -> 1, b -> 2"]
```

<!-- => 18 -->

A string that the source does not close stops reading at the position it begins at:

```wl
WolframLanguageSyntaxLength["a + \"abc"]
```

<!-- => 5 -->

## Properties and Relations

Some sources that read and some that do not:

```wl
sources = {"a + b", "a + b)", "f[x", "f[x)", "a::", "a\n)", "x_ : 1", "x_. : 1", "a ~ b c"}
```

<!-- => {"a + b", "a + b)", "f[x", "f[x)", "a::", "a\n)", "x_ : 1", "x_. : 1", "a ~ b c"} -->

`WolframLanguageSyntaxLength` gives what [SyntaxLength]() gives for each:

```wl
WolframLanguageSyntaxLength /@ sources === SyntaxLength /@ sources
```

<!-- => True -->

[WolframLanguageSyntaxQ]() gives whether the whole source reads:

```wl
WolframLanguageSyntaxQ["a + b) + c"]
```

<!-- => False -->

## Possible Issues

A count equal to the length of the source does not mean it reads. A comment that begins the source and is not closed gives its length:

```wl
WolframLanguageSyntaxLength["(* a note"]
```

<!-- => 9 -->

```wl
WolframLanguageSyntaxQ["(* a note"]
```

<!-- => False -->

---
Template: Symbol
Name: ParseScope
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseScope
Keywords: [parser, scope, context, state, zero-width, PEG]
SeeAlso: [ParseScoped, ParseCondition, ParsePosition, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseScope]()[]</code> returns the [ParserCombinator]() that gives the scope, the labels of the [ParseScoped]() parsers around it, innermost last, consuming no input.

## Details & Options

- The scope is `{}` where a parse begins.
- Like [ParsePosition](), `ParseScope` consumes nothing and never fails.
- [ParseCondition]() over `ParseScope[]` makes a parser that succeeds only in the scopes a test allows.

## Basic Examples

The parser:

```wl
ParseScope[]
```

Outside any [ParseScoped]() the scope is empty:

```wl
Parse[ParseScope[], ""]
```

<!-- => {} -->

Inside one, it holds that parser's label:

```wl
Parse[ParseScoped[1, ParseScope[]], ""]
```

<!-- => {1} -->

## Scope

A test of the scope that consumes nothing, here that no group is open:

```wl
Parse[ParseCondition[ParseScope[], # === {} &] ~~ ParseLiteral["x"], "x"]
```

<!-- => {{}, "x"} -->

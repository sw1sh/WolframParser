---
Template: Symbol
Name: ParseChainLeft
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseChainLeft
Keywords: [parser, left-associative, binary operator, chaining, operator, fold]
SeeAlso: [ParseChainRight, ParseOperatorTable, ParseSepBy, ParseAction, ParserCombinator, Fold]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseChainLeft]()[*p*, *op*]</code> returns the [ParserCombinator]() that parses a *left-associative* chain of operands *p* joined by the binary-operator parser *op*, folding the operands leftward so that `1-2-3` groups as `(1-2)-3`.

## Details & Options

- *op returns its combining function.* *op* matches an operator token and yields a **binary** function, applied as <code>*f*[*left*, *right*]</code> — the same op-returns-a-function convention as [ParseOperatorTable](). Attach it with [ParseAction](): `ParseAction[ParseLiteral["-"], (Subtract &)]`.
- *Left-associative fold.* Operands accumulate left to right: `p op p op p` becomes `f[f[f[p1, p2], p3], p4]`. For [Subtract]() this makes `1-2-3` evaluate as `(1-2)-3`.
- *One or more operands.* At least one *p* is required, so empty input fails. A lone operand with no following operator returns that operand *itself*, not a one-element list.
- *Mixed operators share the level.* When *op* is a [ParseChoice]() of several operator parsers, each returning its own function, they associate together left to right — for example `+` and `-` in one additive chain.
- *One precedence level.* `ParseChainLeft` handles a single operator precedence. For several levels, or for prefix / postfix operators, use [ParseOperatorTable]() — its one-`"InfixL"`-operator table is exactly this combinator, in one linear pass.
- Result type: whatever *op*'s function returns, not necessarily a list.

## Basic Examples

Left-associative subtraction — the chain `1-2-3` folds as `(1-2)-3`:

```wl
num = ParseAction[ParseCharacter[DigitCharacter], FromDigits];
sub = ParseAction[ParseLiteral["-"], (Subtract &)];
Parse[ParseChainLeft[num, sub], "1-2-3"]
```

<!-- => -4 -->

---

A single operand, with no operator, returns the operand itself — not `{5}` and not `f[5]`:

```wl
Parse[ParseChainLeft[num, sub], "5"]
```

<!-- => 5 -->

---

A longer additive chain, with an operator that returns [Plus]():

```wl
plus = ParseAction[ParseLiteral["+"], (Plus &)];
Parse[ParseChainLeft[num, plus], "1+2+3+4"]
```

<!-- => 10 -->

## Scope

Attaching an inert head instead of an arithmetic function makes the left-nesting visible in the result tree:

```wl
Parse[ParseChainLeft[num, ParseAction[ParseLiteral["-"], (minus &)]], "1-2-3"]
```

<!-- => minus[minus[1, 2], 3] -->

---

Multi-character operands — here a regex operand parser handles multi-digit numbers:

```wl
numR = ParseAction[ParseRegex["[0-9]+"], FromDigits];
Parse[ParseChainLeft[numR, sub], "10-3-2"]
```

<!-- => 5 -->

---

Operators that share a precedence level go in one [ParseChoice](); `+` and `-` then associate together, left to right:

```wl
addsub = ParseChoice[plus, sub];
Parse[ParseChainLeft[numR, addsub], "10-2+3"]
```

<!-- => 11 -->

---

The constructor returns a [ParserCombinator](), rendered as a summary box:

```wl
ParseChainLeft[num, sub]
```

<!-- => ParserCombinator[ChainLeft] -->

## Properties and Relations

The right-associative sibling [ParseChainRight]() groups the *same* input the other way, `1-(2-3)`, giving a different value:

```wl
Parse[ParseChainRight[num, sub], "1-2-3"]
```

<!-- => 2 -->

---

`ParseChainLeft` is a left [Fold]() over the operands; folding the same numbers with [Fold]() agrees:

```wl
Fold[Subtract, {1, 2, 3}]
```

<!-- => -4 -->

---

A one-level, one-operator [ParseOperatorTable]() with fixity `"InfixL"` is exactly this combinator:

```wl
Parse[ParseOperatorTable[num, {{"InfixL", sub}}], "1-2-3"]
```

<!-- => -4 -->

## Possible Issues

The operator parser must *return a function*. A bare [ParseLiteral]() returns the matched string, which is then used as a head and never evaluates:

```wl
Parse[ParseChainLeft[num, ParseLiteral["+"]], "1+2"]
```

<!-- => "+"[1, 2] -->

---

At least one operand is required, so empty input fails:

```wl
Parse[ParseChainLeft[num, sub], ""]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<digit>", "Found" -> "<end of input>"|>] -->

## Neat Examples

A left-to-right additive calculator — mixed `+` and `-` at one level, evaluated as the chain is folded:

```wl
Parse[ParseChainLeft[num, addsub], "1+2-3+4"]
```

<!-- => 4 -->

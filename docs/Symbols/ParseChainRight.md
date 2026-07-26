---
Template: Symbol
Name: ParseChainRight
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseChainRight
Keywords: [parser, right-associative, binary operator, chaining, operator, exponentiation]
SeeAlso: [ParseChainLeft, ParseOperatorTable, ParseSepBy, ParseAction, ParserCombinator, Fold]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseChainRight]()[*p*, *op*]</code> returns the [ParserCombinator]() that parses a *right-associative* chain of operands *p* joined by the binary-operator parser *op*, folding the operands rightward so that `2^3^2` groups as `2^(3^2)`.

## Details & Options

- *op returns its combining function.* *op* matches an operator token and yields a **binary** function, applied as <code>*f*[*left*, *right*]</code> — the same op-returns-a-function convention as [ParseOperatorTable](). Attach it with [ParseAction](): `ParseAction[ParseLiteral["^"], (Power &)]`.
- *Right-associative fold.* Operands nest to the right: `p op p op p` becomes `f[p1, f[p2, f[p3, p4]]]`. For [Power]() this makes `2^3^2` evaluate as `2^(3^2)`.
- *One or more operands.* At least one *p* is required, so empty input fails. A lone operand with no following operator returns that operand *itself*, not a one-element list.
- *One precedence level.* `ParseChainRight` handles a single operator precedence. For several levels, or for prefix / postfix operators, use [ParseOperatorTable]() — its one-`"InfixR"`-operator table is exactly this combinator, in one linear pass.
- The mirror image of [ParseChainLeft](): identical grammar, opposite grouping.
- Result type: whatever *op*'s function returns, not necessarily a list.

## Basic Examples

Right-associative exponentiation — the chain `2^3^2` folds as `2^(3^2)`, i.e. `2^9`:

```wl
num = ParseAction[ParseCharacter[DigitCharacter], FromDigits];
pow = ParseAction[ParseLiteral["^"], (Power &)];
Parse[ParseChainRight[num, pow], "2^3^2"]
```

<!-- => 512 -->

---

Right-associative subtraction groups the other way from the everyday reading — `1-2-3` becomes `1-(2-3)`:

```wl
sub = ParseAction[ParseLiteral["-"], (Subtract &)];
Parse[ParseChainRight[num, sub], "1-2-3"]
```

<!-- => 2 -->

---

A single operand, with no operator, returns the operand itself:

```wl
Parse[ParseChainRight[num, sub], "5"]
```

<!-- => 5 -->

## Scope

Attaching an inert head instead of an arithmetic function makes the right-nesting visible in the result tree:

```wl
Parse[ParseChainRight[num, ParseAction[ParseLiteral["^"], (caret &)]], "2^3^2"]
```

<!-- => caret[2, caret[3, 2]] -->

---

Right associativity is the natural shape for a `cons`-style list constructor, where `a:b:c` means `a:(b:c)`:

```wl
word = ParseAction[ParseSome[ParseCharacter[LetterCharacter]], StringJoin];
Parse[ParseChainRight[word, ParseAction[ParseLiteral[":"], (cons &)]], "a:b:c"]
```

<!-- => cons["a", cons["b", "c"]] -->

---

The constructor returns a [ParserCombinator](), rendered as a summary box:

```wl
ParseChainRight[num, pow]
```

<!-- => ParserCombinator[ChainRight] -->

## Properties and Relations

The left-associative sibling [ParseChainLeft]() groups the *same* input the other way, `(1-2)-3`, giving a different value:

```wl
Parse[ParseChainLeft[num, sub], "1-2-3"]
```

<!-- => -4 -->

---

A one-level, one-operator [ParseOperatorTable]() with fixity `"InfixR"` is exactly this combinator:

```wl
Parse[ParseOperatorTable[num, {{"InfixR", pow}}], "2^3^2"]
```

<!-- => 512 -->

## Possible Issues

Associativity changes the value for a non-associative operator. Exponentiation is right-associative, so `2^2^3` is `2^(2^3) = 2^8`:

```wl
Parse[ParseChainRight[num, pow], "2^2^3"]
```

<!-- => 256 -->

---

Chaining the same operator with [ParseChainLeft]() would compute `(2^2)^3 = 4^3` instead — the wrong grouping for powers:

```wl
Parse[ParseChainLeft[num, pow], "2^2^3"]
```

<!-- => 64 -->

---

The operator parser must *return a function*. A bare [ParseLiteral]() returns the matched string, which is then used as a head and never evaluates:

```wl
Parse[ParseChainRight[num, ParseLiteral["^"]], "2^3"]
```

<!-- => "^"[2, 3] -->

---

At least one operand is required, so empty input fails:

```wl
Parse[ParseChainRight[num, sub], ""]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<digit>", "Found" -> "<end of input>"|>] -->

## Neat Examples

A right-associative power tower — `2^2^2^2` is `2^(2^(2^2)) = 2^16`:

```wl
Parse[ParseChainRight[num, pow], "2^2^2^2"]
```

<!-- => 65536 -->

---
Template: Symbol
Name: ParseRecursive
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseRecursive
Keywords: [parser, recursion, recursive grammar, fixed point, lazy reference, mutual recursion, nonterminal, HoldFirst]
SeeAlso: [ParseOperatorTable, ParseBetween, ParseChoice, ParseOptional, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseRecursive]()[*symbol*]</code> returns the [ParserCombinator]() that, at parse time, looks up the parser bound to *symbol* and runs it - a lazy reference for building self-referential and mutually-recursive grammars.

## Details & Options

- `ParseRecursive` holds its argument ([HoldFirst]()): *symbol* need not have a parser value when the reference is built. The value is looked up when [Parse]() runs.
- The reference stores the symbol *name*, not the parser it currently names: `ParseRecursive[s]` is `ParserCombinator["Recursive", Hold[s], <||>]`.
- The lazy lookup lets a grammar be *self-referential* - a symbol whose definition mentions itself - or *mutually recursive* - symbols that mention each other - without pre-declaring every node.
- *symbol* must be bound to a [ParserCombinator]() by the time [Parse]() runs; it is resolved at parse time, not at construction.
- A recursive grammar runs on the interpretive engine, and the recursive-descent nesting is bounded by a depth guard, so deeply nested input returns a [Failure]() rather than overflowing the stack.
- [ParseOperatorTable]() uses `ParseRecursive` to re-enter itself for a parenthesised sub-expression.

## Basic Examples

The reference holds a symbol and looks it up at parse time, so it can be built before the grammar is defined:

```wl
ParseRecursive[expr]
```

<!-- => ParserCombinator[Recursive, Hold[expr], <||>] -->

---

A self-referential grammar - a value is a number, or a bracketed comma-separated list of values - refers back to itself through `ParseRecursive`:

```wl
value = ParseChoice[
    ParseAction[ParseCharacter[DigitCharacter].., FromDigits @* StringJoin],
    ParseBetween[ParseLiteral["["],
        ParseSepBy[ParseRecursive[value], ParseLiteral[","]],
        ParseLiteral["]"]]
];
Parse[value, "[1,[2,3],4]"]
```

<!-- => {1, {2, 3}, 4} -->

---

The base case - a bare number - needs no recursion:

```wl
Parse[value, "42"]
```

<!-- => 42 -->

## Scope

Recursion nests to any depth. Here an action rebuilds the nesting it matched, so the depth is visible in the result:

```wl
parens = ParseAction[
    ParseBetween[ParseLiteral["("], ParseOptional[ParseRecursive[parens]], ParseLiteral[")"]],
    "(" <> ToString[#] <> ")" &
];
Parse[parens, "((()))"]
```

<!-- => "(((Missing[NoMatch])))" -->

---

At the bottom of the nest the [ParseOptional]() matches nothing, so the innermost result is [Missing]()`["NoMatch"]`:

```wl
nestBrackets = ParseBetween[ParseLiteral["["], ParseOptional[ParseRecursive[nestBrackets]], ParseLiteral["]"]];
Parse[nestBrackets, "[[[]]]"]
```

<!-- => Missing["NoMatch"] -->

---

Two symbols that refer to each other form a mutually-recursive grammar - an `"a"`-rule that may be followed by a `"b"`-rule, and vice versa:

```wl
ruleA = ParseLiteral["a"] ~~ ParseOptional[ParseRecursive[ruleB]];
ruleB = ParseLiteral["b"] ~~ ParseOptional[ParseRecursive[ruleA]];
Parse[ruleA, "abab"]
```

<!-- => {"a", {"b", {"a", {"b", Missing["NoMatch"]}}}} -->

---

Because the symbol is resolved at parse time, a parser may refer to one defined *after* it - here `wrap` refers to `body`, which is defined on the next line:

```wl
wrap = ParseBetween[ParseLiteral["<"], ParseRecursive[body], ParseLiteral[">"]];
body = ParseChoice[ParseCharacter[LetterCharacter].., wrap];
Parse[wrap, "<<abc>>"]
```

<!-- => {"a", "b", "c"} -->

## Properties and Relations

The reference holds the symbol *name* even when the symbol is already bound - it does not inline the grammar it points to:

```wl
ParseRecursive[value]
```

<!-- => ParserCombinator[Recursive, Hold[value], <||>] -->

## Possible Issues

A *left-recursive* rule - one that re-enters itself before consuming any input - recurses until the depth guard stops it, returning a clean [Failure]() instead of overflowing the stack:

```wl
badLeft = ParseRecursive[badLeft] ~~ ParseLiteral["a"];
Parse[badLeft, "aaa"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "<input within nesting limit>", "Found" -> "a"|>] -->

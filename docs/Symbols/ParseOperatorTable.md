---
Template: Symbol
Name: ParseOperatorTable
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseOperatorTable
Keywords: [parser, operator precedence, Pratt, TDOP, binding power, precedence climbing, infix, prefix, postfix, expression grammar]
SeeAlso: [ParseChainLeft, ParseChainRight, ParseRecursive, ParseSequence, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseOperatorTable]()[*unit*, *levels*]</code> returns the [ParserCombinator]() that parses an operator-precedence expression grammar — operands separated by prefix, infix, and postfix operators — in a single linear left-to-right pass.

*unit* parses one operand (an atom, or a parenthesised sub-expression via [ParseRecursive]()). *levels* is a list of precedence levels, **tightest-binding first**; each level is a list of operator specs <code>{*fixity*, *opParser*}</code>.

It is the [Pratt / top-down-operator-precedence](https://tdop.github.io/) ("precedence climbing") engine, exposed as a combinator: precedence becomes *data* (the table) instead of *structure* (a hand-cascaded tower of [ParseChainLeft]() / [ParseChainRight]() nonterminals).

## Details & Options

- *fixity* is one of the strings `"InfixL"` (left-associative), `"InfixR"` (right-associative), `"Prefix"`, or `"Postfix"`.
- <code>{"InfixN", *opParser*, *combine*}</code> is a *flat* operator: a run of `"InfixN"` operators of one level that share *combine* builds one node, <code>*combine*[{*operand1*, *operand2*, …}, {*opResult1*, …}]</code>, so `a + b - c` can be one sum and `a < b <= c` one chain. Without *combine*, a run continues only across the same operator, and the first operator's result is applied to the operands.
- <code>{"Ternary", *op1Parser*, *op2Parser*}</code> parses *left* *op1* *middle* *op2* *right*, and *op2Parser*'s result is applied to the three operands; it is left-associative, and `"TernaryR"` is right-associative.
- *Dispatch on the first character.* The table is built with the characters each operator parser can begin with, so at each position it tries only the operators that could begin there, in table order. An operator whose first character cannot be told (one beginning with a [ParseRegex]() or a [ParseRecursive]()) is tried everywhere.
- *Operator parsers return their combining function* — the same convention as [ParseChainLeft](). *opParser* matches the operator token and yields a function: **binary** <code>*f*[*left*, *right*]</code> for infix, **unary** <code>*f*[*operand*]</code> for prefix / postfix. Use [ParseAction]() to attach the function, e.g. `ParseAction[ParseLiteral["+"], (Plus &)]`.
- *Precedence is the level position.* The first level binds tightest; the last binds loosest. Operators that share a level share a precedence (e.g. `+` and `-`).
- *A lone spec stands in for a one-operator level*: `{"InfixL", op}` is accepted as shorthand for `{{"InfixL", op}}`.
- *Recursion* is via [ParseRecursive](): a parenthesised-expression branch inside *unit* refers back to the symbol the table is bound to, so the engine re-enters at binding power 0 inside brackets.
- *Linear time.* The leading operand is parsed **once**; operators are then consumed while their binding power exceeds the caller's. A [ParseChoice]() over `or | and | apply` re-parses the shared leading operand once per alternative and backtracks exponentially (the TPTP THF blow-up); [ParseOperatorTable]() does not.
- *Depth guard.* Right-nested recursion carries the same nesting limit as the rest of the interpreter, returning a clean <code>[Failure]()["ParseError", …]</code> rather than tripping [$RecursionLimit]().
- *Generalises the chain combinators.* A single-level table of one `"InfixL"` operator is exactly [ParseChainLeft](); one `"InfixR"` operator is [ParseChainRight](). The table adds multiple precedence levels and prefix / postfix in one pass.

## Basic Examples

A four-operator arithmetic calculator — `*` `/` bind tighter than `+` `-`, and the operator parsers return the actual arithmetic functions, so the result *evaluates*. A number is the operand:

```wl
num = ParseAction[ParseRegex["[0-9]+"], FromDigits]
```

Each operator parser returns the function its operator stands for:

```wl
addOp = ParseChoice[ParseAction[ParseLiteral["+"], (Plus &)],
                    ParseAction[ParseLiteral["-"], (Subtract &)]]
```

```wl
mulOp = ParseChoice[ParseAction[ParseLiteral["*"], (Times &)],
                    ParseAction[ParseLiteral["/"], (Divide &)]]
```

A *unit* - what the table combines - is a number or a bracketed expression:

```wl
unit = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[calc], ParseLiteral[")"]],
   num]
```

The table lists its levels tightest first:

```wl
calc = ParseOperatorTable[unit, {
   {{"InfixL", mulOp}},   (* tightest *)
   {{"InfixL", addOp}}    (* loosest  *)
}]
```

```wl
Parse[calc, "2*3+4*5"]
```

<!-- => 26 -->

Precedence - `*` binds tighter than `+`:

```wl
Parse[calc, "1+2*3"]
```

<!-- => 7 -->

Left-associativity - `1-2-3` groups as `(1-2)-3`:

```wl
Parse[calc, "1-2-3"]
```

<!-- => -4 -->

Parentheses re-enter the table at the bottom binding power:

```wl
Parse[calc, "(1+2)*3"]
```

<!-- => 9 -->

## Scope

**Right-associativity.** `"InfixR"` makes the operator nest to the right — here with an inert head so the tree is visible:

```wl
pow = ParseOperatorTable[ParseAction[ParseRegex["[0-9]+"], FromDigits],
   {{"InfixR", ParseAction[ParseLiteral["^"], (power &)]}}]
```

```wl
Parse[pow, "2^3^2"]
```

<!-- => power[2, power[3, 2]] -->

**Prefix and postfix.** A propositional-logic grammar with prefix `~`, infix `&` `|`, and right-associative `=>`, mapping to the built-in boolean heads:

```wl
sym = ParseAction[ParseChoice @@ (ParseLiteral /@ {"p", "q", "r"}), Symbol]
```

```wl
lunit = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[logic], ParseLiteral[")"]],
   sym]
```

```wl
logic = ParseOperatorTable[lunit, {
   {{"Prefix", ParseAction[ParseLiteral["~"],  (Not &)]}},
   {{"InfixL", ParseAction[ParseLiteral["&"],  (And &)]}},
   {{"InfixL", ParseAction[ParseLiteral["|"],  (Or &)]}},
   {{"InfixR", ParseAction[ParseLiteral["=>"], (Implies &)]}}
}]
```

`&` binds tighter than `|`:

```wl
Parse[logic, "p|q&r"]
```

<!-- => p || (q && r) -->

Prefix `~` binds tighter still:

```wl
Parse[logic, "~p&q"]
```

<!-- =>  !p && q -->

A postfix operator (factorial) at the tightest level:

```wl
fac = ParseOperatorTable[ParseAction[ParseRegex["[0-9]+"], FromDigits], {
   {{"Postfix", ParseAction[ParseLiteral["!"], (fact &)]}},
   {{"InfixL",  ParseAction[ParseLiteral["+"], (plus &)]}}
}]
```

```wl
Parse[fac, "3!+4!"]
```

<!-- => plus[fact[3], fact[4]] -->

**Flat chains.** `"+"` and `"-"` sharing one *combine* gather a whole sum into one node; *combine* gets the operands and what the operator parsers returned:

```wl
sum = ParseOperatorTable[ParseAction[ParseRegex["[0-9]+"], FromDigits], {
   {{"InfixN", ParseAction[ParseLiteral["+"], "+" &], (terms[#1, #2] &)},
    {"InfixN", ParseAction[ParseLiteral["-"], "-" &], (terms[#1, #2] &)}}
}]
```

```wl
Parse[sum, "1+2-3+4"]
```

<!-- => terms[{1, 2, 3, 4}, {"+", "-", "+"}] -->

**Ternary operators.** `?` and `:` around a middle operand, left-associative:

```wl
cond = ParseOperatorTable[ParseAction[ParseRegex["[0-9]+"], FromDigits], {
   {"Ternary", ParseLiteral["?"], ParseAction[ParseLiteral[":"], (if &)]}
}]
```

```wl
Parse[cond, "1?2:3?4:5"]
```

<!-- => if[if[1, 2, 3], 4, 5] -->

## Properties and Relations

A one-level, one-operator table is exactly [ParseChainLeft]() / [ParseChainRight]():

```wl
chainL = ParseOperatorTable[num, {{"InfixL", ParseAction[ParseLiteral["+"], (Plus &)]}}]
```

```wl
Parse[chainL, "1+2+3"]
```

<!-- => 6 -->

Multiple operators on one level share precedence and associate together left-to-right (`+` and `-` both additive):

```wl
Parse[calc, "10-2+3"]
```

<!-- => 11 -->

## Possible Issues

- *The operator parser must return a function.* `ParseLiteral["+"]` alone returns the string `"+"`; the table would then try to call `"+"[left, right]`. Wrap it: `ParseAction[ParseLiteral["+"], (Plus &)]`. When one parser matches several operators, branch with [ParseChoice]() so each branch returns its own function.
- *Levels are tightest-first.* The first level in the list binds most tightly. Reversing the list inverts every precedence relationship.
- *Operator-token prefixes.* If `<=` and `<` are both operators, order the [ParseChoice]() / table so the longer token is tried first, exactly as with [ParseChoice]() — `<` would otherwise shadow `<=`.
- *Left recursion in unit.* *unit* must not be able to match the empty string at the start of an operand, or the climber cannot make progress. Keep *unit* to atoms and bracketed groups; let the table own the operators.
- *`"InfixN"` is flat, not non-associative.* It gathers `a = b = c` into one node rather than rejecting it; a grammar that forbids the chain checks the operand count in *combine*.

## Neat Examples

The input shape that makes a [ParseChoice]() over `or | and | apply` backtrack exponentially — a left-nested apply chain `f[n] = "(" <> f[n-1] <> "@b)"` — stays linear here. At depth 200 (an 801-character string) it parses in milliseconds, where the equivalent [ParseChoice]() / [ParseRecursive]() grammar times out by depth 10:

```wl
apOp = ParseAction[ParseLiteral["@"], (app &)]
```

```wl
u = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[e], ParseLiteral[")"]],
   ParseAction[ParseChoice @@ (ParseLiteral /@ {"a", "b"}), Symbol]]
```

```wl
e = ParseOperatorTable[u, {{"InfixL", apOp}}]
```

The nested inputs, each wrapping the last in one more `(... @b)`:

```wl
f[k_] := f[k] = If[k == 0, "a", "(" <> f[k - 1] <> "@b)"]
```

Three levels deep:

```wl
f[3]
```

<!-- => "(((a@b)@b)@b)" -->

It parses to three nested applications:

```wl
Parse[e, f[3]]
```

<!-- => app[app[app[a, b], b], b] -->

The seconds the 200-level input takes:

```wl
First @ AbsoluteTiming[Parse[e, f[200]]]
```

This is the "Pratt-style precedence climber" the [Parsing TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP) note points to for the higher-order (THF) connective grammar, where alternative explosion overwhelms even longest-match. [TPTPImport]() now parses the THF `@` / `&` / `|` / `<=>` connectives through exactly this combinator.

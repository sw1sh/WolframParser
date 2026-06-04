---
Template: TechNote
Name: PrattVsPEG
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/PrattVsPEG
Keywords: [TDOP, Pratt, PEG, operator precedence, binding power, parsing expression grammar, ParseOperatorTable, ParseChoice, expression grammar]
---

# TDOP vs PEG: Two Ways to Parse Operators

There are two ways to teach a parser that `1 + 2 * 3` is `1 + (2 * 3)` and not
`(1 + 2) * 3`. You can put the precedence in the **shape of the grammar** — a
cascade of rules, one per precedence level — and parse it with ordered choice;
that is the [PEG](https://en.wikipedia.org/wiki/Parsing_expression_grammar) way.
Or you can put the precedence in **data** — a number, the *binding power*, on
each operator — and let one small loop consume operators by strength; that is
Vaughan Pratt's 1973 [Top-Down Operator Precedence](https://tdop.github.io/)
(TDOP), the technique behind Crockford's JavaScript parser and dozens of DSLs.

`` Wolfram`Parser` `` ships both. [ParseChoice]() / [ParseRecursive]() build the
PEG cascade; [ParseOperatorTable]() is the Pratt engine. This note parses the
same little expression language both ways, shows exactly where the PEG version
falls off a cliff, and ends at the real payoff — the TPTP THF grammar, where the
switch turned a parser that timed out at 13 bytes into a linear one.

## The PEG way: precedence is grammar structure

A PEG encodes "`*` binds tighter than `+`" as a tower of nonterminals: an
*expr* is a sum of *terms*, a *term* is a product of *factors*, a *factor* is a
number or a parenthesised *expr*. Each level is its own rule, and
[ParseChainLeft]() folds the left-associative chain at that level. The rules
refer back to each other through [ParseRecursive](), which looks a parser up by
symbol at parse time so the cycle can be written before every node exists.

```wl
num    = ParseAction[ParseRegex["[0-9]+"], FromDigits];
addOp  = ParseChoice[ParseAction[ParseLiteral["+"], (Plus &)],
                     ParseAction[ParseLiteral["-"], (Subtract &)]];
mulOp  = ParseChoice[ParseAction[ParseLiteral["*"], (Times &)],
                     ParseAction[ParseLiteral["/"], (Divide &)]];
factor = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[expr], ParseLiteral[")"]],
   num];
term   = ParseChainLeft[factor, mulOp];
expr   = ParseChainLeft[term, addOp];

Parse[expr, "1+2*3"]
```

<!-- => 7 -->

It works, and on a flat input it is fast. But notice what the cascade costs even
when it succeeds: to read the bare number `1`, the parser still descends
*expr → term → factor*, three rule entries for one token. Precedence lives in
that descent. Every operand pays for every level above it.

## Where PEG breaks: shared-prefix alternatives

The cascade is fine while each level has a distinct shape. It breaks when a level
offers several alternatives that all **begin with the same operand**. The
canonical case is a grammar with more than one binary family at the same tier —
*or*, *and*, and (in a higher-order language) *application* — each written

```
<binary> ::= <unit> "|" <unit> | <unit> "&" <unit> | <unit> "@" <unit>
```

Lowered to an ordered [ParseChoice](), the three alternatives each re-parse the
leading `<unit>` from scratch, because a PEG has no memo of what the previous
alternative already matched. When `<unit>` can itself be a parenthesised
sub-expression, that re-parse recurses, and the cost of a left-nested chain
becomes **O(3^depth)**. Here is the shape, built honestly with the combinators:

```wl
atom = ParseChoice[ParseLiteral["a"], ParseLiteral["b"]];
unit = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[logic], ParseLiteral[")"]],
   atom];
orF  = ParseSequence[ParseRecursive[unit], ParseLiteral["|"], ParseRecursive[unit]];
andF = ParseSequence[ParseRecursive[unit], ParseLiteral["&"], ParseRecursive[unit]];
appF = ParseSequence[ParseRecursive[unit], ParseLiteral["@"], ParseRecursive[unit]];
logic = ParseChoice[orF, andF, appF, ParseRecursive[unit]];

Parse[logic, "((a@b)@b)"]
```

<!-- => {{"a", "@", "b"}, "@", "b"}  (a raw tree - the point here is the cost, not the value) -->

Each extra layer of `(… @ b)` multiplies the work by three: `orF` parses the
inner group and fails at `@`, `andF` re-parses it and fails at `@`, `appF`
re-parses it a third time and succeeds — and every one of those parses repeats
the same three-way split one level down. Timing the depth makes the curve
unmistakable (this is the standalone measurement from `dev/pratt-vs-peg.wls`):

| depth | bytes | PEG ordered-choice | Pratt table |
|------:|------:|-------------------:|------------:|
| 5  | 21 | 0.085 s | 0.0001 s |
| 7  | 29 | 0.775 s | 0.0001 s |
| 9  | 37 | 7.59 s  | 0.0002 s |
| 10 | 41 | **> 15 s (timeout)** | 0.0002 s |

The input grows four bytes per level; the runtime triples. That 3 is not a
mystery — it is the three alternatives of the choice, each re-parsing the shared
operand. No ordering or longest-match trick removes it, because all three
alternatives genuinely start the same way.

## The Pratt way: precedence is data

Pratt's move is to stop encoding precedence in the grammar's shape and put it in
a table. Each operator gets a *binding power*; the parser reads one operand,
then loops: while the next operator binds tighter than the caller's threshold,
consume it and its right operand, fold, repeat. The leading operand is parsed
**once**. Two functions per token carry the behaviour — *nud* (null denotation:
how a token acts with nothing to its left, e.g. a prefix `~`) and *led* (left
denotation: how it acts on a left operand, e.g. infix `&`).

[ParseOperatorTable]() is that engine as a combinator:
<code>[ParseOperatorTable]()[*unit*, *levels*]</code> takes a *unit* parser and a
list of precedence levels, tightest first; each operator parser returns its
combining function, the same convention as [ParseChainLeft]().

The same expression language as the cascade above, now as one table — and it
*evaluates*, because the operator parsers return the real arithmetic functions:

```wl
num2  = ParseAction[ParseRegex["[0-9]+"], FromDigits];
unit2 = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[calc], ParseLiteral[")"]],
   num2];
calc  = ParseOperatorTable[unit2, {
   {{"InfixL", ParseChoice[ParseAction[ParseLiteral["*"], (Times &)],
                           ParseAction[ParseLiteral["/"], (Divide &)]]}},
   {{"InfixL", ParseChoice[ParseAction[ParseLiteral["+"], (Plus &)],
                           ParseAction[ParseLiteral["-"], (Subtract &)]]}}}];

Parse[calc, "1+2*3"]
```

<!-- => 7 -->

Same answer, but no cascade: one rule, two table rows. And the shared-prefix
grammar that blew up under ordered choice is now linear, because the operand is
read once and the operator is chosen by looking at the *next token*, not by
re-parsing the operand under each hypothesis:

```wl
ap   = ParseAction[ParseLiteral["@"], (app &)];
u    = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[e], ParseLiteral[")"]],
   ParseAction[ParseChoice @@ (ParseLiteral /@ {"a", "b"}), Symbol]];
e    = ParseOperatorTable[u, {{"InfixL", ap}}];

f[0] = "a"; f[k_] := f[k] = "(" <> f[k - 1] <> "@b)";
Parse[e, f[12]]
```

<!-- => app[app[app[app[app[app[app[app[app[app[app[app[a, b], b], b], b], b], b], b], b], b], b], b], b] -->

Depth 12 is where the PEG version needs minutes; the table returns instantly. The
nud/led loop never re-parses the operand, so the 3^depth factor is simply gone.

## They compose — use each where it is strong

This is not PEG *or* Pratt. A real grammar is mostly recognition — keywords,
brackets, lists, the overall clause shape — and ordered choice with
[ParseChoice]() / [ParseRecursive]() is exactly right for that. Operator
expressions are the one sub-problem where ordered choice is the wrong tool, and
that is the sub-problem [ParseOperatorTable]() owns. The two nest cleanly: a
table's *unit* parser is an ordinary [ParseRecursive]() back into the PEG
grammar (for parenthesised groups, quantifiers, atoms), and the table is just
another node the surrounding PEG can call.

A one-level, one-operator table *is* [ParseChainLeft]() (or [ParseChainRight]()
for `"InfixR"`); the table generalises them with multiple precedence levels and
prefix / postfix in a single linear pass. So the rule of thumb: PEG for the
grammar, Pratt for the operators inside it.

## The payoff: TPTP THF

The motivating case is real. The [TPTP](paclet:Wolfram/Parser/tutorial/ParsingTPTP)
THF (Typed Higher-order Form) grammar has exactly the pathological rule —
`<thf_binary_assoc> ::= <thf_or_formula> | <thf_and_formula> | <thf_apply_formula>`,
three alternatives over a shared `<thf_unit_formula>` — and on the published BNF
the ordered-choice parser **times out on a 13-byte formula**.

[TPTPImport]() now overrides that rule with a [ParseOperatorTable]() over
`<thf_unitary_formula>`, with `@` (application), `&`, `|`, the nonassoc
connectives, prefix `~`, and `=` / `!=` as table entries. The blow-up is gone —
a 321-byte nested formula parses in under a third of a second — and the
higher-order structure comes back as clean Wolfram Language terms:

```wl
TPTPImport["thf(a, axiom, ! [X:$i] : ? [Y:$i] : ( r @ X @ Y ))."]["Axioms"]
```

<!-- => {ForAll[{X_}, Exists[{Y_}, r[][X_][Y_]]]} -->

Quantifiers nest, `^`-lambdas survive as binders, application curries:

```wl
TPTPImport["thf(two, axiom, two = ( ^ [F:$i>$i, X:$i] : ( F @ ( F @ X ) ) ))."]["Axioms"]
```

<!-- => {two[] == ^[{F_, X_}, (F_)[(F_)[X_]]]} -->

That is the whole argument in one place: the grammar shape PEG could only parse
exponentially, Pratt parses in a line — and the binding-power table that does it
is the same `nud`/`led` idea Pratt wrote down in 1973.

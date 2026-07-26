---
Template: Symbol
Name: ParseChoiceLongest
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseChoiceLongest
Keywords: [parser, choice, alternation, longest match, POSIX, ambiguous grammar, shared prefix, backtracking]
SeeAlso: [ParseChoice, Parse, ParseTry, ParseOperatorTable, EBNFParse, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseChoiceLongest]()[$p_1$, $p_2$, …, $p_n$]</code> returns the [ParserCombinator]() that runs every $p_i$ at the current position and returns the result of the *longest* successful match.

## Details & Options

- Where [ParseChoice]() is PEG-ordered — it stops at the *first* alternative that matches — [ParseChoiceLongest]() is POSIX-style: it runs *every* alternative and commits to the one that consumed the most input.
- Ties between equal-length successes resolve to the first listed alternative, mirroring [ParseChoice]()'s left-bias.
- It cannot early-exit at the first hit, so it always runs all branches; it is slower than [ParseChoice]() by that constant factor.
- The case it exists for: alternatives that share a *leaf-level prefix* and differ only in what follows, so the shorter alternative is a prefix of the correct one. Ordering longest-first cannot fix this when the alternatives are factored across separate rules — TPTP's `<fof_atomic_formula> ::= <fof_plain_atomic_formula> | <fof_defined_atomic_formula>`, where both branches consume the same leading term but only the second reaches a trailing `= rhs`.
- There is no operator overload: `p1 | p2` lowers to [ParseChoice]() (via [Alternatives]()), never to [ParseChoiceLongest](). Call [ParseChoiceLongest]() explicitly.
- A single-branch <code>[ParseChoiceLongest]()[*p*]</code> canonicalises to *p*.
- Nested same-type children flatten: a [ParseChoiceLongest]() directly inside another merges into one.
- On total failure the reported error is the furthest-advanced failure across all branches, and its `Expected` set is the union of the per-branch expected sets at that position — the same diagnostic [ParseChoice]() produces.
- Result type: whatever the winning branch returned.
- It is the combinator [EBNFParse]() folds a rule's alternatives with under `"ChoiceMode" -> "Longest"` and, for length-ambiguous rules, `"ChoiceMode" -> "Auto"`.

## Basic Examples

Two alternatives share the prefix `ab`; longest-match takes the branch that consumes the whole input:

```wl
Parse[ParseChoiceLongest[ParseLiteral["ab"], ParseLiteral["abc"]], "abc"]
```

<!-- => "abc" -->

<!-- #| annotation: 26.07.26: Design review - ParseChoiceLongest is POSIX longest-match alternation, the complement to ParseChoice's PEG first-match (Ford 2004): PEG commits to the first alternative that matches and never revisits it, while this runs every alternative and commits to the one that consumed the most input. Both are provided because they are correct for different grammars - PEG is the fast default; longest-match is required when alternatives are factored across separate rule levels so the shorter alternative is a leaf-level prefix of the correct one and reordering cannot fix it (TPTP's <fof_atomic_formula> ::= <fof_plain_atomic_formula> | <fof_defined_atomic_formula>, where both branches consume the same leading term but only the second reaches the trailing = rhs). It is the combinator EBNFParse folds alternatives with under "ChoiceMode" -> "Longest" / "Auto". The cost is no early exit - every branch runs - so where alternation over a shared operand explodes combinatorially, ParseOperatorTable's Pratt climber is the linear escape hatch. -->

---

The same two alternatives under [ParseChoice]() pick the shorter branch first, leaving `c` unconsumed and failing the whole-input match:

```wl
Parse[ParseChoice[ParseLiteral["ab"], ParseLiteral["abc"]], "abc"]
```

<!-- => Failure["ParseError", <|"Position" -> 3, "Expected" -> "<end of input>", "Found" -> "c"|>] -->

---

Longest-match is independent of the order the alternatives are listed — the longer branch wins even when it comes first:

```wl
Parse[ParseChoiceLongest[ParseLiteral["abc"], ParseLiteral["ab"]], "abc"]
```

<!-- => "abc" -->

## Scope

The grammar case longest-match is for: a *plain* atom and an *infix-equality* atom that share the same leading term, the shape of TPTP's `<fof_atomic_formula>`. `eqAtom[#1, #3]&` keeps the two operands and drops the `"="` at position 2:

```wl
plain = ParseAction[ParseRegex["[a-z]+"], plainAtom];
infix = ParseAction[
   ParseSequence[ParseRegex["[a-z]+"], ParseLiteral["="], ParseRegex["[a-z]+"]],
   eqAtom[#1, #3] &];
Parse[ParseChoice[plain, infix], "a=b"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> "<end of input>", "Found" -> "="|>] -->

[ParseChoice]() commits to *plain* — it matches the leading `a` and never reaches the `= b`. Longest-match runs both and keeps the branch that consumed further:

```wl
Parse[ParseChoiceLongest[plain, infix], "a=b"]
```

<!-- => eqAtom["a", "b"] -->

---

On input with no `=`, only *plain* succeeds, so it is trivially the longest:

```wl
Parse[ParseChoiceLongest[plain, infix], "a"]
```

<!-- => plainAtom["a"] -->

---

Three graded prefixes — the maximal one wins:

```wl
Parse[ParseChoiceLongest[ParseLiteral["a"], ParseLiteral["ab"], ParseLiteral["abc"]], "abc"]
```

<!-- => "abc" -->

## Properties and Relations

A single-branch choice is the branch itself:

```wl
ParseChoiceLongest[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Literal, "foo", <||>] -->

---

A [ParseChoiceLongest]() nested directly in another flattens to one combinator over all the leaves:

```wl
ParseChoiceLongest[ParseLiteral["a"], ParseChoiceLongest[ParseLiteral["b"], ParseLiteral["c"]]]
```

<!-- => ParserCombinator[ChoiceLongest, {ParserCombinator[Literal, "a", <||>], ParserCombinator[Literal, "b", <||>], ParserCombinator[Literal, "c", <||>]}, <||>] -->

---

When two branches match the same span, the tie resolves to the first listed — here the first action tag wins:

```wl
Parse[ParseChoiceLongest[ParseAction[ParseLiteral["ab"], first], ParseAction[ParseLiteral["ab"], second]], "ab"]
```

<!-- => first["ab"] -->

---

The `|` operator is [ParseChoice](), not [ParseChoiceLongest]() — to get longest-match you name the combinator:

```wl
ParseLiteral["a"] | ParseLiteral["b"]
```

<!-- => ParserCombinator[Choice, {ParserCombinator[Literal, "a", <||>], ParserCombinator[Literal, "b", <||>]}, <||>] -->

---

[ParserCompile]() preserves longest-match semantics — each alternative is measured and the furthest-reaching one committed, so the compiled parser agrees with [Parse]():

```wl
ParserCompile[ParseChoiceLongest[ParseLiteral["ab"], ParseLiteral["abc"]]]["abc"]
```

<!-- => "abc" -->

## Possible Issues

When no alternative matches, the failure is the furthest-advanced one and its `Expected` is the union across branches at that position:

```wl
Parse[ParseChoiceLongest[ParseLiteral["foo"], ParseLiteral["bar"]], "xyz"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> {"foo", "bar"}, "Found" -> "x"|>] -->

---

Every branch is run — there is no short-circuit — so alternation over a shared operand that re-parses it per branch can blow up. Where that happens, [ParseOperatorTable]()'s Pratt-style climber stays linear where even longest-match does not; it parses the same leading operand once instead of once per alternative:

```wl
Parse[ParseOperatorTable[ParseAction[ParseRegex["[0-9]+"], FromDigits],
   {{"InfixL", ParseAction[ParseLiteral["+"], (Plus &)]}}], "1+2+3"]
```

<!-- => 6 -->

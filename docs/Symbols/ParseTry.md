---
Template: Symbol
Name: ParseTry
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParseTry
Keywords: [parser, backtracking, try, commit, ordered choice, restore position, PEG]
SeeAlso: [ParseChoice, ParseSequence, ParseLookahead, ParserCompile, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseTry]()[*p*]</code> returns the [ParserCombinator]() that runs *p* and, if *p* fails, restores the input position to where *p* began, so that an enclosing [ParseChoice]() can try its next alternative.

## Details & Options

- On success `ParseTry[p]` returns *p*'s result unchanged; on failure it reports *p*'s failure with the position reset to where `ParseTry` started.
- `ParseTry` marks *p* as a backtracking point. In a committed-PEG parser an ordered choice whose alternative consumes input and then fails is committed to that consumption and the whole choice fails; wrapping the alternative in `ParseTry` restores the position so the next alternative is tried.
- In this parser [ParseChoice]() already restarts every alternative from the position where the choice began, so it recovers from partial consumption on its own. Wrapping an alternative in `ParseTry` therefore does not change the result.
- The combinator is preserved through [ParserCompile](), so a grammar's shape stays identical to one written for a backtracking-by-default combinator library.
- `ParseTry` does not change [ParseChoice]()'s ordering - the first alternative that matches still wins; it is not a longest-match.

## Basic Examples

The combinator wraps its argument:

```wl
ParseTry[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Try, ParserCombinator[Literal, "foo", <||>], <||>] -->

---

On success `ParseTry` is transparent - it returns its parser's result unchanged:

```wl
Parse[ParseTry[ParseLiteral["foo"]], "foo"]
```

<!-- => "foo" -->

---

The result passes through whatever the wrapped parser built, here a [ParseSequence]() list:

```wl
Parse[ParseTry[ParseLiteral["a"] ~~ ParseLiteral["b"]], "ab"]
```

<!-- => {"a", "b"} -->

---

On failure it reports the wrapped parser's own diagnostic:

```wl
Parse[ParseTry[ParseLiteral["foo"]], "bar"]
```

<!-- => Failure["ParseError", <|"Position" -> 1, "Expected" -> "foo", "Found" -> "b"|>] -->

## Scope

As an alternative in an ordered choice, a failing `ParseTry` hands control to the next branch:

```wl
Parse[ParseTry[ParseLiteral["foo"]] | ParseLiteral["fo"], "fo"]
```

<!-- => "fo" -->

## Properties and Relations

[ParseChoice]() already backtracks over partial consumption. Here the first alternative consumes `"a"` then fails on `"b"`, and the choice restarts the second alternative from the start - recovering without `ParseTry`:

```wl
Parse[(ParseLiteral["a"] ~~ ParseLiteral["b"]) | ParseLiteral["a"], "a"]
```

<!-- => "a" -->

---

Wrapping that alternative in `ParseTry` yields the identical result - the combinator records the backtracking intent without changing the outcome:

```wl
Parse[ParseTry[ParseLiteral["a"] ~~ ParseLiteral["b"]] | ParseLiteral["a"], "a"]
```

<!-- => "a" -->

## Possible Issues

In Parsec- and attoparsec-style libraries `try` is *required* to recover from an alternative that consumed input before failing. In this parser [ParseChoice]() backtracks by default, so `ParseTry` is never required and does not alter results - an alternative that partially matches `"ab"` then fails still lets a shorter alternative match, with no `ParseTry`:

```wl
Parse[(ParseLiteral["ab"] ~~ ParseLiteral["c"]) | ParseLiteral["ab"], "ab"]
```

<!-- => "ab" -->

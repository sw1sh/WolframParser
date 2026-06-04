---
Template: Symbol
Name: ParserCombinator
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParserCombinator
Keywords: [parser, combinator, wrapper, summary box, UpValues, SubValues]
SeeAlso: [Parse, ParserCompile, ParseLiteral, ParseSequence, ParseChoice, ParseMany]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParserCombinator]()[type, args, opts]</code> is the single computable wrapper every parser in the library is represented as. The head is *opaque* to user code: build a `ParserCombinator` by calling one of the [Parse*](paclet:Wolfram/Parser/guide/WolframParser) constructors ([ParseLiteral](), [ParseSequence](), [ParseChoice](), ...), never by hand.

## Details & Options

- `type` is a [Symbol]() naming the combinator shape (`Literal`, `Character`, `Sequence`, `Choice`, `Many`, `Some`, `Optional`, `Between`, `Lookahead`, `NotFollowedBy`, `Try`, `Action`, `Capture`, `Recursive`, ...).
- `args` are the combinator's children: other `ParserCombinator` instances, terminal data (a string for `Literal`, a character class for `Character`), or a function (for `Action`).
- `opts` is an [Association]() of compile-time / runtime options. After [ParserCompile]() the options carry a `"Code" -> CompiledCodeFunction[...]` entry; absence of `"Code"` is what makes the parser uncompiled (no extra `"Compiled"` flag is needed).
- A `ParserCombinator` is **callable as a function** via a [SubValues]() rule: `pc[input]` is equivalent to `Parse[pc, input]`. If `"Code"` is present in `opts`, the compiled function is invoked; otherwise the *interpretive* path runs.
- `ParserCombinator` carries [UpValues]() for the WL operators that overload to combinator composition:

| WL syntax                  | UpValue                      | Combinator         |
|----------------------------|------------------------------|--------------------|
| <code>p1 \| p2</code>      | [Alternatives]()             | [ParseChoice]()    |
| <code>p1 ~~ p2</code>      | [StringExpression]()         | [ParseSequence]()  |
| <code>p..</code>           | [Repeated]()                 | [ParseSome]()      |
| <code>p...</code>          | [RepeatedNull]()             | [ParseMany]()      |
| <code>Optional[p]</code>   | [Optional]()                 | [ParseOptional]()  |

- `~~` is overloaded *only* when **both** sides are `ParserCombinator` instances. Plain `"foo" ~~ "bar"` between strings keeps its built-in [StringExpression]() meaning.
- `~` is *not* overloaded - it stays as WL's infix function notation `a~f~b == f[a, b]`.
- A `ParserCombinator` formats as a Wolfram-style [SummaryBox]() showing the combinator type, arity, compile status, a structural sketch of the tree, and the options.

## Basic Examples

A literal-matching parser is a `ParserCombinator` with type `Literal`:

```wl
ParseLiteral["foo"]
```

<!-- => ParserCombinator[Literal, "foo", <||>] -->

A sequence built with the `~~` operator is the same expression you'd get from [ParseSequence]() directly:

```wl
ParseLiteral["foo"] ~~ ParseLiteral["bar"]
```

<!-- => ParserCombinator[Sequence, {ParserCombinator[Literal, "foo", <||>], ParserCombinator[Literal, "bar", <||>]}, <||>] -->

The same `ParseSequence` call explicitly:

```wl
ParseSequence[ParseLiteral["foo"], ParseLiteral["bar"]]
```

<!-- => ParserCombinator[Sequence, {ParserCombinator[Literal, "foo", <||>], ParserCombinator[Literal, "bar", <||>]}, <||>] -->

## Scope

A `ParseChoice` built with the `|` operator collapses associativity through [Alternatives]():

```wl
ParseLiteral["a"] | ParseLiteral["b"] | ParseLiteral["c"]
```

<!-- => ParserCombinator[Choice, {ParserCombinator[Literal, "a", <||>], ParserCombinator[Literal, "b", <||>], ParserCombinator[Literal, "c", <||>]}, <||>] -->

Repetition operators lower to `ParseSome` / `ParseMany`:

```wl
ParseLiteral["x"]..
```

<!-- => ParserCombinator[Some, ParserCombinator[Literal, "x", <||>], <||>] -->

---

```wl
ParseLiteral["x"]...
```

<!-- => ParserCombinator[Many, ParserCombinator[Literal, "x", <||>], <||>] -->

Subvalue: a `ParserCombinator` is callable directly:

```wl
ParseLiteral["foo"]["foo"]
```

<!-- => "foo" -->

(equivalent to `Parse[ParseLiteral["foo"], "foo"]`.)

## Properties and Relations

[ParserCompile]() returns a `ParserCombinator` with the same head and a `CompiledCodeFunction` added to its options under the `"Code"` key:

```wl
With[{compiled = ParserCompile[ParseLiteral["foo"]]},
    {Head[compiled], KeyExistsQ[compiled[[3]], "Code"]}]
```

<!-- => {ParserCombinator, True} -->

A `ParserCombinator` is *inert* until applied - it does not run when first constructed:

```wl
parser = ParseLiteral["foo"];
{Head[parser], Parse[parser, "foo"]}
```

<!-- => {ParserCombinator, "foo"} -->

The `~~` overload only fires when both sides are `ParserCombinator` instances, so plain string sequences are unaffected:

```wl
{
    "foo" ~~ "bar",                                 (* a built-in StringExpression *)
    ParseLiteral["foo"] ~~ ParseLiteral["bar"]      (* a ParserCombinator *)
}
```

<!-- => {"foo" ~~ "bar", ParserCombinator[Sequence, {ParserCombinator[Literal, "foo", <||>], ParserCombinator[Literal, "bar", <||>]}, <||>]} -->

## Possible Issues

The head is opaque. Building one by hand without a constructor is unsupported - the structural invariants the lowering relies on (canonical type names, normalised options, *etc.*) are only guaranteed when you go through the `Parse*` API.

## Neat Examples

The operator overloads compose without ever spelling `ParserCombinator` by hand. A floating-point number:

```wl
ParseCharacter[DigitCharacter].. ~~ Optional[ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]...]
```

<!-- => a Sequence ParserCombinator with one Some and one Optional child, whose body is itself a Sequence of a Literal and a Many -->

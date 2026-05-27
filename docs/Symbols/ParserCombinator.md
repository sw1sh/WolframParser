---
Template: Symbol
Name: ParserCombinator
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParserCombinator
Keywords: [parser, combinator, wrapper, summary box, UpValues]
SeeAlso: [Parse, ParserCompile, ParseLiteral, ParseSequence, ParseChoice, ParseMany]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParserCombinator]()[$type$, $args$, $opts$]</code> is the single computable wrapper every parser in the library is represented as. The head is *opaque* to user code: build a `ParserCombinator` by calling one of the [Parse*](paclet:Wolfram/WolframParser/guide/WolframParser) constructors ([ParseLiteral](), [ParseSequence](), [ParseChoice](), ...), never by hand.

## Details & Options

- `$type$` is a [Symbol]() naming the combinator shape (`Literal`, `Character`, `Sequence`, `Choice`, `Many`, `Some`, `Optional`, `Between`, `Lookahead`, `NotFollowedBy`, `Try`, `Action`, `Capture`, `Recursive`, ...).
- `$args$` is the combinator's children: other `ParserCombinator` instances, terminal data (a string for `Literal`, a character class for `Character`), or a function (for `Action`).
- `$opts$` is an [Association]() of compile-time / runtime options - `<|"Compiled" -> True, "Code" -> CompiledCodeFunction[...]|>` after [ParserCompile](), `<|"Memoize" -> True|>` for packrat memoisation, *etc*.
- `ParserCombinator` carries [UpValues]() for the WL operators that overload to combinator composition:

| WL syntax        | UpValue                          | Combinator         |
|------------------|----------------------------------|--------------------|
| `$p_1$ \| $p_2$` | [Alternatives]()                 | [ParseChoice]()    |
| `$p_1$ ** $p_2$` | [NonCommutativeMultiply]()       | [ParseSequence]()  |
| `$p$..`          | [Repeated]()                     | [ParseSome]()      |
| `$p$...`         | [RepeatedNull]()                 | [ParseMany]()      |
| `Optional[$p$]`  | [Optional]()                     | [ParseOptional]()  |

- `~~` is *not* overloaded (it stays as [StringExpression]()). `~` is *not* overloaded (it stays as WL's infix function notation `$a$~$f$~$b$` = $f$[$a$, $b$]).
- A `ParserCombinator` formats as a Wolfram-style [SummaryBox]() showing the combinator type, arity, compile status, a structural sketch of the tree, and the options.

## Basic Examples

A literal-matching parser is a `ParserCombinator` with type `Literal`:

```wl
ParseLiteral["foo"]
```

<!-- => ParserCombinator[Literal, "foo", <||>] -->

A sequence built with the `**` operator is the same expression you'd get from [ParseSequence]() directly:

```wl
ParseLiteral["foo"] ** ParseLiteral["bar"]
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

## Properties and Relations

[ParserCompile]() returns a `ParserCombinator` with the same head, mutated options (`"Compiled" -> True`), and a `CompiledCodeFunction` in `$opts$`:

```wl
With[{compiled = ParserCompile[ParseLiteral["foo"]]},
    {Head[compiled], Lookup[compiled[[3]], "Compiled"]}]
```

<!-- => {ParserCombinator, True} -->

A `ParserCombinator` is *inert* - it does not run until passed to [Parse]() or applied as a function:

```wl
parser = ParseLiteral["foo"];
Parse[parser, "foo"]
```

<!-- => "foo" -->

## Possible Issues

The head is opaque. Building one by hand without a constructor is unsupported - the structural invariants the lowering relies on (canonical type names, normalised options, etc.) are only guaranteed when you go through the `Parse*` API:

```wl
(* don't do this *)
ParserCombinator[MyType, {"foo"}, <||>]
```

<!-- => ParserCombinator[MyType, {"foo"}, <||>] (no validation - the compiler will reject MyType at lowering time) -->

## Neat Examples

The operator overloads compose without ever spelling `ParserCombinator` by hand. A floating-point number:

```wl
ParseCharacter[DigitCharacter].. ** Optional[ParseLiteral["."] ** ParseCharacter[DigitCharacter]...]
```

<!-- => a Sequence ParserCombinator with one Some and one Optional child, whose body is itself a Sequence of a Literal and a Many -->

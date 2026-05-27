---
Template: Symbol
Name: ParserCompile
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParserCompile
Keywords: [parser, compile, FunctionCompile, native code, CloudDeploy]
SeeAlso: [Parse, ParserCombinator, FunctionCompile, CloudDeploy, GrammarRules]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParserCompile]()[parser]</code> compiles `parser` (a [ParserCombinator]() or a [GrammarRules]() declaration) to native code via [FunctionCompile](), returning a `ParserCombinator` with a [CompiledCodeFunction]() stored under the `"Code"` key of its options.

<code>[ParserCompile]()[parser, opts]</code> accepts options - `"Memoize" -> True | False` (default `False`), `"InputType" -> "UTF8String" | "TokenList" | "ExpressionList"` (default inferred from the grammar).

## Details & Options

- `ParserCompile` is the local analogue of cloud-deploying a [GrammarRules](): both turn a grammar declaration into a deployable callable, one ships it to the cloud, the other ships it through [FunctionCompile]() into the local kernel.
- The result is a `ParserCombinator` of the *same head* as the input, with the compiled function folded into the options as `"Code" -> CompiledCodeFunction[...]`. No separate `"Compiled" -> True` flag - the presence of `"Code"` is the marker.
- A compiled `ParserCombinator` is callable as a function via the [SubValues]() rule the wrapper carries: `compiled[input]` equals `Parse[compiled, input]`. Both end up invoking the cached compiled function rather than the interpreter.
- The compile cost is paid once per grammar; reuse the returned object across many `[input]` calls.

## Basic Examples

Compile a literal parser:

```wl
ParserCompile[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Literal, "foo", <|"Code" -> CompiledCodeFunction[...]|>] -->

The compiled object is callable directly via its SubValue:

```wl
parser = ParserCompile[ParseLiteral["foo"]];
parser["foo"]
```

<!-- => "foo" -->

## Scope

Compile a `GrammarRules` declaration - the local analogue of pushing it to the cloud:

```wl
g = GrammarRules[{"the weather in <city>" -> city}];
parser = ParserCompile[g];
parser["the weather in NYC"]
```

<!-- => "NYC" -->

Compile a small expression grammar:

```wl
expr = ParserCompile[
    ParseAction[
        ParseCharacter[DigitCharacter]..,
        FromDigits @ StringJoin[#] &
    ]
];
expr["42"]
```

<!-- => 42 -->

## Properties and Relations

[Parse]() and `ParserCompile` produce the same result on the same input - `Parse` is just `ParserCompile` + apply, with the compile result cached:

```wl
With[{p = ParseLiteral["foo"] | ParseLiteral["bar"]},
    {Parse[p, "foo"], ParserCompile[p]["foo"]}]
```

<!-- => {"foo", "foo"} -->

`InputForm` still shows the parser tree, with the compile metadata in the options slot:

```wl
ParserCompile[ParseLiteral["foo"]] // InputForm
```

<!-- => ParserCombinator[Literal, "foo", <|"Code" -> CompiledCodeFunction[...]|>] -->

`"Code"`-presence is the canonical "is this compiled?" predicate:

```wl
compiled = ParserCompile[ParseLiteral["foo"]];
uncompiled = ParseLiteral["foo"];
{KeyExistsQ[compiled[[3]], "Code"], KeyExistsQ[uncompiled[[3]], "Code"]}
```

<!-- => {True, False} -->

## Possible Issues

A grammar that uses [ParseAction]() with a function the compiler cannot type-infer may fail to compile - in which case `ParserCompile` falls back to the interpretive path and emits a [Message]() warning. The returned parser still works (interpretively); only the speed-up is lost.

```wl
ParserCompile[ParseAction[ParseLiteral["foo"], SomeUserFunction]]
```

<!-- => ParserCompile::nocompile message + a ParserCombinator without "Code" in its options -->

## Neat Examples

For a grammar used many times against many inputs, compile once and apply repeatedly:

```wl
identifier = ParserCompile[
    ParseAction[
        ParseCharacter[LetterCharacter] ~~
            (ParseCharacter[LetterCharacter] | ParseCharacter[DigitCharacter])...,
        StringJoin
    ]
];
identifier /@ {"foo", "bar1", "baz_qux"}
```

<!-- => {"foo", "bar1", ParseError[<|"Position" -> 4, "Expected" -> "<letter or digit>", "Found" -> "_", ...|>]} -->

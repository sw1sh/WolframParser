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

<code>[ParserCompile]()[$parser$]</code> compiles $parser$ (a [ParserCombinator]() or a [GrammarRules]() declaration) to native code via [FunctionCompile](), returning a `ParserCombinator` with `"Compiled" -> True` and a [CompiledCodeFunction]() in its options.

<code>[ParserCompile]()[$parser$, $opts$]</code> accepts options - `"Memoize" -> True \| False` (default `False`), `"InputType" -> "UTF8String" \| "TokenList" \| "ExpressionList"` (default inferred from the grammar).

## Details & Options

- `ParserCompile` is the *local analogue of [CloudDeploy](`)[`[GrammarRules](`)[...`]`]`*: the cloud path returns a [CloudObject](), `ParserCompile` returns a callable `ParserCombinator`. The two compile a `GrammarRules` declaration into a deployable form; one runs in the cloud, the other in the local kernel.
- The result is a `ParserCombinator` of the *same head* as the input, with the compile metadata folded into the options. This means `InputForm` still shows the parser tree - the compile is *additive*, not opaque.
- A compiled `ParserCombinator` is callable as a function: `compiled[input]` is equivalent to `Parse[parser, input]` but skips the JIT-compile step.
- The compile cost is paid once per grammar; reuse the returned object across many `[input]` calls.

## Basic Examples

Compile a literal parser:

```wl
ParserCompile[ParseLiteral["foo"]]
```

<!-- => ParserCombinator[Literal, "foo", <|"Compiled" -> True, "Code" -> CompiledCodeFunction[...]|>] -->

The compiled object is callable directly:

```wl
parser = ParserCompile[ParseLiteral["foo"]];
parser["foo"]
```

<!-- => "foo" -->

## Scope

Compile a `GrammarRules` declaration - the local analogue of `CloudDeploy[GrammarRules[...]]`:

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

The compile is additive - `InputForm` still shows the parser tree, with the compile metadata in the options slot:

```wl
ParserCompile[ParseLiteral["foo"]] // InputForm
```

<!-- => ParserCombinator[Literal, "foo", <|"Compiled" -> True, "Code" -> CompiledCodeFunction[...]|>] -->

## Possible Issues

A grammar that uses [ParseAction]() with a function the compiler cannot type-infer may fail to compile - in which case `ParserCompile` falls back to the interpretive path and emits a [Message]() warning. The returned parser still works (interpretively); only the speed-up is lost.

```wl
ParserCompile[ParseAction[ParseLiteral["foo"], SomeUserFunction]]
```

<!-- => ParserCompile::nocompile message + a parser with "Compiled" -> False -->

## Neat Examples

For a grammar used many times against many inputs, compile once and apply repeatedly:

```wl
identifier = ParserCompile[
    ParseAction[
        ParseCharacter[LetterCharacter] **
            (ParseCharacter[LetterCharacter] | ParseCharacter[DigitCharacter])...,
        StringJoin
    ]
];
identifier /@ {"foo", "bar1", "baz_qux"}
```

<!-- => {"foo", "bar1", ParseError[<|"Position" -> 4, "Expected" -> "<letter or digit>", "Found" -> "_", ...|>]} -->

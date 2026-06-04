---
Template: Symbol
Name: ParserCompile
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParserCompile
Keywords: [parser, compile, FunctionCompile, native code, CloudDeploy]
SeeAlso: [Parse, ParserCombinator, FunctionCompile, CloudDeploy, GrammarRules]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParserCompile]()[parser]</code> compiles `parser` (a [ParserCombinator]() or a [GrammarRules]() declaration) to native code via [FunctionCompile](), returning a `ParserCombinator` with a [CompiledCodeFunction]() stored under the `"Code"` key of its options.

<code>[ParserCompile]()[parser, Method -> "PEGVM"]</code> uses the **PEG-VM backend** instead of [FunctionCompile](): the grammar is lowered to an integer instruction table run on a single, once-compiled LPEG-style parsing machine. This scales to large recursive grammars (LaTeX math, TPTP) that [FunctionCompile]() cannot compile in practical time, and runs 1-2 orders of magnitude faster than the interpreter. See [Possible Issues]().

<code>[ParserCompile]()[parser, opts]</code> also accepts `"Memoize" -> True | False` (default `False`), `"InputType" -> "UTF8String" | "TokenList" | "ExpressionList"` (default inferred from the grammar).

## Details & Options

- **Two backends.** `Method -> Automatic` (default) lowers the combinator tree to a single [FunctionCompile]()'d function - fast for small/medium grammars; recursive grammars need `"Recursive" -> True` and otherwise stay interpretive. `Method -> "PEGVM"` lowers the grammar to a flat integer instruction table interpreted by one native parsing machine (compiled once, shared by every grammar). Because the grammar is *data*, not code, the PEG-VM "compiles" any grammar of any size in milliseconds-to-seconds of plain Wolfram Language - no per-grammar [FunctionCompile]() - and handles arbitrary recursion via an explicit stack. Captures recorded during the native run are replayed by a Wolfram post-pass to rebuild the exact result (same actions as [Parse]()).

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
        FromDigits @ StringJoin[{##}] &
    ]
];
expr["42"]
```

<!-- => 42 -->

The `ParseAction` callback is compiled in place via [KernelFunction]() - the whole parser, recogniser *and* semantic action, becomes one [CompiledCodeFunction](). The result is threaded through compiled code as an `"InertExpression"`, so an action may return *any* Wolfram expression.

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

The compiled path covers the full non-recursive combinator algebra: every `Parse*` constructor except [ParseRecursive]() lowers to native code, with results threaded as `"InertExpression"` and [ParseAction]() callbacks run in place via [KernelFunction](). Because actions execute in the kernel, *any* action function compiles - there is no type-inference restriction on it.

A parser built with [ParseRecursive]() (directly or mutually recursive) cannot be lowered to a single compiled function by the default backend; `ParserCompile` keeps it runnable on the interpretive path and emits a `ParserCompile::nocompile` warning. The returned parser still works (interpretively); only the speed-up is lost. **Use `Method -> "PEGVM"` to compile recursive grammars** (it has no such restriction).

```wl
ClearAll[expr];
expr = ParseChoice[ParseBetween[ParseLiteral["("], ParseRecursive[expr], ParseLiteral[")"]], ParseLiteral["x"]];
ParserCompile[expr]["((x))"]                      (* default: interpretive, ParserCompile::nocompile *)
ParserCompile[expr, Method -> "PEGVM"]["((x))"]   (* PEG-VM: native *)
```

<!-- => "x"  (both) -->

A [ParseMany]() (or [ParseSome]()) over a parser that can succeed *without consuming input* would loop forever; the default backend refuses it outright:

```wl
ParserCompile[ParseMany[ParseSucceed["nothing"]]]
```

<!-- => ParserCompile::infloop message + $Failed -->

### The PEG-VM backend (`Method -> "PEGVM"`)

The PEG-VM lowers any grammar - recursive or not, of any size - to an integer instruction table run on a single native parsing machine. It is the backend for large grammars the FunctionCompile path cannot handle, and for compiled parsers you want to *serialize*:

```wl
latex = ParserCompile[LaTeXMathParser, Method -> "PEGVM"];   (* a 380k-instruction table, built in a couple of seconds *)
Export["latex.wxf", latex];                                  (* compile once, save *)
(* in a fresh kernel: *)
Needs["Wolfram`Parser`"];
latex = Import["latex.wxf"];                                  (* reloads instantly, no recompile *)
latex["\\frac{a^2+b^2}{c}"]
```

Limitations of the PEG-VM backend, relative to the interpreter:

- **Generic failure messages.** On a parse failure it returns a `Failure["ParseError", ...]` with `"Expected" -> "<parse failed>"` rather than the full expected-token set (the native run does not track the expected set). Successful parses are bit-identical to [Parse]().
- **ASCII character classes.** [ParseCharacter]() classes are matched against code points ≤ 128; [ParseLiteral]() handles full Unicode. Fine for ASCII-source grammars (LaTeX, TPTP, EBNF).
- **`ParseChoiceLongest`** is handled with true longest-match (each alternative is measured and the furthest-reaching one is committed), so prefix-sharing alternatives - e.g. TPTP's `a` vs `a = b` - parse correctly.

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

<!-- => {"foo", "bar1", Failure["ParseError", <|"Position" -> 4, "Expected" -> "<letter or digit>", "Found" -> "_", ...|>]} -->

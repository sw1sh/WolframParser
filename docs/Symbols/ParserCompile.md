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

<code>[ParserCompile]()[*parser*]</code> compiles *parser* (a [ParserCombinator]() or a [GrammarRules]() declaration) to native code via [FunctionCompile](), returning a `ParserCombinator` that carries the compiled function under the `"Code"` key of its options.

<code>[ParserCompile]()[*parser*, Method -> "PEGVM"]</code> uses the **PEG-VM backend** instead of [FunctionCompile](): the grammar is lowered to an integer instruction table run on a single, once-compiled LPEG-style parsing machine. This scales to large recursive grammars (LaTeX math, TPTP) that [FunctionCompile]() cannot compile in practical time, and runs 1-2 orders of magnitude faster than the interpreter. See [Possible Issues]().

<code>[ParserCompile]()[*parser*, "Recursive" -> True]</code> attempts native code for a recursive grammar on the default backend.

## Details & Options

- **Two backends.** `Method -> Automatic` (default) lowers the combinator tree to a single [FunctionCompile]()'d function - fast for small/medium grammars. `Method -> "PEGVM"` lowers the grammar to a flat integer instruction table interpreted by one native parsing machine (compiled once, shared by every grammar). Because the grammar is *data*, not code, the PEG-VM "compiles" any grammar of any size in milliseconds-to-seconds of plain Wolfram Language - no per-grammar [FunctionCompile]() - and handles arbitrary recursion via an explicit stack. Captures recorded during the native run are replayed by a Wolfram post-pass to rebuild the exact result (same actions as [Parse]()).
- **Recursive grammars.** On the default backend a grammar built with [ParseRecursive]() stays on the interpretive path unless `"Recursive" -> True` asks for the (slow) mutual-recursion code generation; when that [FunctionCompile]() fails, the message `ParserCompile::nocompile` is issued and the parser falls back to the interpreter.
- `ParserCompile` is the local analogue of cloud-deploying a [GrammarRules](): both turn a grammar declaration into a deployable callable, one ships it to the cloud, the other ships it through [FunctionCompile]() into the local kernel.
- The result is a `ParserCombinator` of the *same head* as the input, with the compiled function folded into the options as `"Code"`.
- A compiled `ParserCombinator` is callable as a function via the [SubValues]() rule the wrapper carries: `compiled[input]` equals `Parse[compiled, input]`. Both end up invoking the cached compiled function rather than the interpreter.
- The compile cost is paid once per grammar; reuse the returned object across many `[input]` calls.

## Basic Examples

Compile a literal parser:

```wl
ParserCompile[ParseLiteral["foo"]]
```

The compiled object is callable directly via its SubValue:

```wl
foo = ParserCompile[ParseLiteral["foo"]]
```

```wl
foo["foo"]
```

<!-- => "foo" -->

## Scope

Compile a [GrammarRules]() declaration - the local analogue of pushing it to the cloud:

```wl
weather = GrammarRules[{"the weather in <city>" -> city}]
```

<!-- => GrammarRules[{"the weather in <city>" -> city}] -->

```wl
cityParser = ParserCompile[weather]
```

```wl
cityParser["the weather in NYC"]
```

<!-- => "NYC" -->

Compile a parser with a semantic action:

```wl
number = ParserCompile[
    ParseAction[
        ParseCharacter[DigitCharacter]..,
        FromDigits @ StringJoin[{##}] &
    ]
]
```

```wl
number["42"]
```

<!-- => 42 -->

The `ParseAction` callback is compiled in place via [KernelFunction]() - the whole parser, recogniser *and* semantic action, becomes one [CompiledCodeFunction](). The result is threaded through compiled code as an `"InertExpression"`, so an action may return *any* Wolfram expression.

## Properties and Relations

[Parse]() and `ParserCompile` give the same result on the same input:

```wl
fooOrBar = ParseLiteral["foo"] | ParseLiteral["bar"]
```

```wl
Parse[fooOrBar, "bar"]
```

<!-- => "bar" -->

Compiled, it gives the same result:

```wl
ParserCompile[fooOrBar]["bar"]
```

<!-- => "bar" -->

The compiled parser keeps its tree and adds one option, the compiled function:

```wl
Keys @ Last[ParserCompile[ParseLiteral["foo"]]]
```

<!-- => {"Code"} -->

## Possible Issues

On the default backend a recursive grammar stays interpretive, with no message; it still parses, only the speed-up is lost:

```wl
nested = ParseChoice[ParseBetween[ParseLiteral["("], ParseRecursive[nested], ParseLiteral[")"]], ParseLiteral["x"]]
```

```wl
ParserCompile[nested]["((x))"]
```

<!-- => "x" -->

`Method -> "PEGVM"` compiles the same grammar natively:

```wl
ParserCompile[nested, Method -> "PEGVM"]["((x))"]
```

<!-- => "x" -->

A [ParseMany]() (or [ParseSome]()) over a parser that can succeed *without consuming input* would loop forever; the default backend refuses it outright:

```wl
ParserCompile[ParseMany[ParseSucceed["nothing"]]]
```

<!-- => the message ParserCompile::infloop is issued and the result is $Failed -->

### The PEG-VM backend (`Method -> "PEGVM"`)

The PEG-VM lowers any grammar - recursive or not, of any size - to an integer instruction table run on a single native parsing machine. It is the backend for large grammars the FunctionCompile path cannot handle. The whole LaTeX math grammar compiles in a few seconds:

```wl
latex = ParserCompile[LaTeXMathParser, Method -> "PEGVM"]
```

```wl
latex["\\frac{a^2+b^2}{c}"]
```

<!-- => FractionBox[RowBox[{SuperscriptBox[StyleBox["a", "TI"], "2"], "+", SuperscriptBox[StyleBox["b", "TI"], "2"]}], StyleBox["c", "TI"]] -->

A compiled parser is plain data, so it can be saved once and reloaded in a fresh kernel without recompiling:

```wl
#| eval: false
Export["latex.wxf", latex];
(* in a fresh kernel, after Needs["Wolfram`Parser`"]: *)
latex = Import["latex.wxf"];
```

Limitations of the PEG-VM backend, relative to the interpreter:

- **Generic failure messages.** On a parse failure it returns a `Failure["ParseError", ...]` with `"Expected" -> "<parse failed>"` rather than the full expected-token set (the native run does not track the expected set). Successful parses are bit-identical to [Parse]().
- **Compound quantifier bodies in TPTP.** On the full TPTP grammar the PEG-VM currently rejects a quantified formula whose body is itself a compound formula (`! [X] : p(X) & q(X)`), which [Parse]() accepts; [TPTPImport]() parses with the interpreter.
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
]
```

```wl
identifier /@ {"foo", "bar1", "x9y"}
```

<!-- => {"foo", "bar1", "x9y"} -->

An underscore is neither a letter nor a digit, so the parse stops there and reports where:

```wl
identifier["baz_qux"]
```

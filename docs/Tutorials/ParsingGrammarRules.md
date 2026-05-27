---
Template: TechNote
Name: ParsingGrammarRules
Title: Parsing GrammarRules Locally
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/ParsingGrammarRules
Keywords: [GrammarRules, GrammarApply, GrammarToken, CloudDeploy, Interpreter, slot, FixedOrder, DelimitedSequence, parser, local]
RelatedGuides: [WolframParser]
RelatedTutorials: [DesignAndCompilationStrategy, LaTeXMathParserImplementation]
---

## What this note covers

[`GrammarRules`](paclet:ref/GrammarRules) is the Wolfram Language's declarative grammar DSL. The built-in implementation only runs after a [CloudDeploy](paclet:ref/CloudDeploy): you write a `GrammarRules[...]` expression, ship it to a cloud object, then call [GrammarApply](paclet:ref/GrammarApply) (or [Interpreter](paclet:ref/Interpreter)) on the URL. Local kernels have no way to evaluate a `GrammarRules` expression directly - the symbol exists but is inert. `Wolfram\`Parser\`` takes the same `GrammarRules` head, lowers it to a [ParserCombinator](paclet:Wolfram/WolframParser/ref/ParserCombinator), and runs it on the local kernel - so the same grammar that backed your `CloudObject` can be parsed without a network round-trip.

This note has four parts:

1. **What the built-in supports** - the full pattern vocabulary `GrammarRules` accepts, verified against `CloudDeploy["TestGrammar_N"]` deployments.
2. **What the local implementation supports today** - the subset of that vocabulary that `Parse[GrammarRules[...], input]` handles in v0.2.5, with side-by-side examples.
3. **The gap** - which built-in features are NOT yet ported, the workarounds, and what would be needed to close each one.
4. **When to use which** - decision guide.

---

## Part 1 - What the built-in supports

Deployed and verified against the cloud:

| Cloud test name           | Pattern shape                                                  | Result                              |
|---------------------------|----------------------------------------------------------------|-------------------------------------|
| `TestGrammar_1`           | `"hello" -> "greeting"`                                        | literal string match                |
| `TestGrammar_2`           | `FixedOrder["add", a:GrammarToken["SemanticNumber"], "and", b:GrammarToken["SemanticNumber"]] :> a+b` | named slot with type via `GrammarToken` |
| `TestGrammar_3`           | `FixedOrder["turn", OptionalElement["the"], appl:("stove"|"oven"|"fridge"), state:("on"|"off")] :> {appl, state}` | alternatives, optional elements, `AllowLooseGrammar` trims trailing fluff |
| `TestGrammar_4`           | `nums:DelimitedSequence[GrammarToken["SemanticNumber"], ","|"and"] :> Total[nums]` | one-or-more with delimiter |
| `TestGrammar_5`           | `GrammarRules[{rules}, {defs}]` with subsidiary `"MyCity" -> ...` definitions | named-domain definitions |
| `TestGrammar_6`           | `c:GrammarToken["City"]` resolving to an `Entity["City", ...]` | Interpreter-backed semantic tokens |
| `TestGrammar_8`           | `AnyOrder["red", "green", "blue"] :> "all three colors named"` | permutation matching |
| `TestGrammar_10loose`     | `AllowLooseGrammar -> True` (default)                          | matches inside arbitrary surrounding text |
| `TestGrammar_12`          | `CaseSensitive["Hello"] -> ...`                                | per-rule case sensitivity |

The pattern shapes accepted, as documented in [`GrammarRules`](paclet:ref/GrammarRules):

```
"string"                       literal string
StringExpression[...]          arbitrary string pattern
RegularExpression[...]         regular expression
form1 | form2 | ...            alternative forms
OptionalElement[form, def]     optional form, with default
FixedOrder[form1, form2, ...]  forms in a fixed order
AnyOrder[form1, form2, ...]    forms in any order
form..                         repeated
DelimitedSequence[form, sep]   form repeated with delimiters
GrammarToken["name"]           built-in or defined domain
CaseSensitive[form]            case-sensitive match
x : form                       named binding
```

Built-in `GrammarToken` types that resolved in cloud tests (more exist):

- `"SemanticNumber"` ("six" → 6)
- `"Number"`, `"Integer"`, `"Real"` (digit-based)
- `"Percent"` (`"5"` → `Quantity[5, "Percent"]`)
- `"City"`, `"Country"` (Interpreter-backed)
- `"Color"`, `"Date"`, `"Time"`, `"DateString"`
- `"MathExpression"` (`"1+1"` → `2`)

---

## Part 2 - What `Wolfram\`Parser\`` supports locally today

The shape `Wolfram\`Parser\`` accepts is the *string-template* form - the same `<name:Type>` slot syntax used by [Interpreter](paclet:ref/Interpreter)`["..."]` and [FormFunction](paclet:ref/FormFunction). It maps cleanly to a [ParserCombinator](paclet:Wolfram/WolframParser/ref/ParserCombinator) tree:

```
GrammarRules[{
    template_String -> body,     (* Rule: body evaluated at compile time *)
    template_String :> body      (* RuleDelayed: body evaluated per match *)
}]
```

Each template is split into literal segments and `<name:Type>` slots. The slot bindings flow into `body` via [ReplaceAll](paclet:ref/ReplaceAll) on the named symbols.

### Slot type table

| `<name:Type>`            | Recognizer                                              | Result form         |
|--------------------------|---------------------------------------------------------|---------------------|
| `<name>` (bare)          | `ParseSome[ParseCharacter[WordCharacter]]`              | `String`            |
| `<name:Word>`            | `ParseSome[ParseCharacter[LetterCharacter]]`            | `String`            |
| `<name:Number>`          | `ParseSome[ParseCharacter[DigitCharacter]]` + `FromDigits` | `Integer`        |
| `<name:Integer>`         | alias for `Number`                                      | `Integer`           |
| any other type           | `ParseFail` with "slot type ... not supported" message  | -                   |

### Verified working

```wl
In[]:= Parse[GrammarRules[{"the weather in <city>" -> city}], "the weather in NYC"]
Out[]= "NYC"

In[]:= Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
Out[]= 8

In[]:= Parse[GrammarRules[{"<verb:Word> <obj:Word>" :> {verb, obj}}], "eat sushi"]
Out[]= {"eat", "sushi"}

In[]:= Parse[GrammarRules[{"hello" -> "greeting", "bye" -> "farewell"}], "bye"]
Out[]= "farewell"

In[]:= Parse[GrammarRules[{"<n:Integer>" :> n^2}], "42"]
Out[]= 1764

In[]:= Parse[GrammarRules[{"" -> "empty"}], ""]
Out[]= "empty"
```

The rule head is either `Rule` or `RuleDelayed`:

```wl
In[]:= Parse[GrammarRules[{"<n:Number>" -> n}],  "42"]      (* Rule: body evaluates *)
Out[]= 42

In[]:= Parse[GrammarRules[{"<n:Number>" :> n+1}], "42"]     (* RuleDelayed: body evaluates per match *)
Out[]= 43
```

`Parse` is strict - input must match the *whole* template, not just a prefix:

```wl
In[]:= Parse[GrammarRules[{"hello" -> "hi"}], "hello there"]
Out[]= ParseError[<|"Position" -> 6, "Expected" -> "<end of input>", "Found" -> " "|>]
```

Use [ParsePartial](paclet:Wolfram/WolframParser/ref/Parse) when you want a prefix match.

### The same rules through `ParserCompile`

A `GrammarRules` lowers to a `ParserCombinator`; `ParserCompile` then materializes the [FunctionCompile](paclet:ref/FunctionCompile)d form:

```wl
In[]:= cf = ParserCompile[GrammarRules[{"<n:Integer>" :> n^2}]];
       cf["42"]
Out[]= 1764
```

Same syntax, same result, faster on hot paths.

---

## Part 3 - The gap

The built-in `GrammarRules` accepts a substantially richer pattern language than the local template form. Each unsupported feature, and the workaround:

### Not yet ported: pattern combinators

`FixedOrder`, `AnyOrder`, `OptionalElement`, `DelimitedSequence`, `RegularExpression`, `CaseSensitive`, `x : form`, bare `form..` repetition, and `GrammarToken["name"]` are all pattern-level constructs. The local parser sees only the *string template* form, so a rule like

```wl
GrammarRules[{
    FixedOrder["add", a:GrammarToken["SemanticNumber"], "and", b:GrammarToken["SemanticNumber"]] :> a+b
}]
```

does not match the `template_String -> body` shape `lowerGrammarRule` expects, and `Parse` falls through to a no-op (returns the input unevaluated).

**Workaround for now:** drop to the combinator core. The grammar above is

```wl
addNum = ParseAction[
    ParseSome[ParseCharacter[DigitCharacter]],
    FromDigits @ StringJoin[{##}] &
];
addRule = ParseAction[
    ParseLiteral["add"] ~~ ParseLiteral[" "] ~~ addNum ~~ ParseLiteral[" and "] ~~ addNum,
    Function[{_, _, a, _, b}, a + b]
];
Parse[addRule, "add 3 and 5"]
(* 8 *)
```

The translation is mechanical. A future `v0.3` lowering of the real pattern shapes would mostly automate this rewrite.

### Not yet ported: semantic `GrammarToken` types

`<name:City>` and `<name:Color>` and friends in the local form go through `slotParser[other_]` and return a `ParseFail`. The built-in resolves them via `Interpreter`. To plug the gap, the local parser would need to call `Interpreter[type, _, _]` on the matched substring - feasible, but introduces a kernel dependency that the combinator core deliberately avoids.

**Workaround for now:** parse the slot as a `Word` (or use `ParseSome[ParseCharacter[...]]` directly) and call `Interpreter[type]` in the rule action:

```wl
Parse[
    GrammarRules[{"weather in <c:Word>" :> Interpreter["City"][c]}],
    "weather in Boston"
]
(* Entity["City", {"Boston", "Massachusetts", "UnitedStates"}] *)
```

### Not yet ported: `AllowLooseGrammar`, `IgnoreCase`, `IgnoreDiacritics`

The built-in's default `AllowLooseGrammar -> True` lets `GrammarApply[g, "could you please tell me the weather in Boston"]` match a `"weather <c:City>"` rule by ignoring surrounding fluff. The local parser is strict-PEG: every character must match. Same for case insensitivity (`IgnoreCase -> True` by default in the cloud, no equivalent locally) and diacritic stripping.

**Workaround:** for loose-grammar behavior, wrap the rule with [ParseTry](paclet:Wolfram/WolframParser/ref/ParseTry) and scan with [StringPosition](paclet:ref/StringPosition); for case insensitivity, lowercase the input before parsing. Both are awkward; better to add real options to `Parse[GrammarRules[...]]` in a future version.

### Not yet ported: subsidiary definitions

`GrammarRules[rules, defs]` lets a rule reference a named domain (`GrammarToken["MyCity"]`) defined in `defs`. The local lowering ignores the second argument.

**Workaround:** inline the alternatives directly into the rule template (`"<x:Word>"` with explicit alternative-matching in the action), or compose `ParseChoice` over the alternatives in the combinator core.

---

## Part 4 - When to use which

| Situation | Choice |
|-----------|--------|
| You need named-entity recognition (`City`, `Country`, `Color`, `Date`) on free-form natural-language input | `CloudDeploy[GrammarRules[...]]` + `GrammarApply` - the built-in is doing real work the local parser doesn't replicate |
| You need a structured template like `"add <a:Number> and <b:Number>"` for digit/word patterns, no NLP | `Parse[GrammarRules[...]]` locally - no network, no auth, no rate limits |
| You're parsing a formal grammar (a DSL, a math expression, a file format) | Skip `GrammarRules` entirely - the bare `Parse*` combinators in [`Wolfram\`Parser\``](paclet:Wolfram/WolframParser/guide/WolframParser) are the right tool |
| You want to test offline what would deploy to the cloud later | `Parse[GrammarRules[...]]` for the template form; for the `FixedOrder` / `GrammarToken` shapes you still need the cloud round-trip until v0.3 lowers them |
| You want maximum speed for a fixed grammar | `ParserCompile[GrammarRules[...]]` - same shape, returns a [CompiledCodeFunction](paclet:ref/CompiledCodeFunction) |

The two-tier story behind the design: `GrammarRules` is the *declarative* layer; `Parse*` is the *combinator* layer. Anything you can write declaratively, you can also write as combinators; the declarative form just compiles down. For now, the local declarative layer is a strict subset of the cloud one. The combinator layer has no such gap.

---

## Worked example: porting a deployed grammar to local

Here's the `TestGrammar_3` "appliance controller" from Part 1, ported from the cloud form to the local combinator form:

**Cloud (deployed):**

```wl
GrammarRules[{
    FixedOrder[
        "turn",
        OptionalElement["the"],
        appl : ("stove" | "oven" | "fridge"),
        state : ("on" | "off")
    ] :> {appl, state}
}]
```

**Local (combinator):**

```wl
ws       = ParseSome[ParseCharacter[WhitespaceCharacter]];
appliance = ParseAction[
    ParseChoice[ParseLiteral["stove"], ParseLiteral["oven"], ParseLiteral["fridge"]],
    Identity
];
state    = ParseAction[
    ParseChoice[ParseLiteral["on"], ParseLiteral["off"]],
    Identity
];
controller = ParseAction[
    ParseLiteral["turn"] ~~ ws ~~
        ParseOptional[ParseLiteral["the"] ~~ ws] ~~
        appliance ~~ ws ~~ state,
    Function[args, {args[[4]], args[[6]]}]
];
Parse[controller, "turn the stove on"]
(* {"stove", "on"} *)
Parse[controller, "turn oven off"]
(* {"oven", "off"} *)
```

This is more verbose than the declarative form, but it runs locally, is fully testable, compiles, and lives in your paclet rather than a cloud object whose URL you have to remember.

The end-state once `v0.3` lowers the full pattern vocabulary: the cloud form above should `Parse` directly, with `GrammarToken["SemanticNumber"]` and friends falling through to local `Interpreter` calls when present, so the *only* difference between the two paths becomes whether you wanted the network round-trip or not.

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

`Parse[GrammarRules[{...}], input]` accepts two surface shapes for the rule LHS, both lowered on the same code path:

### (a) The string-template form

The simpler shape (which the cloud's built-in does *not* accept, but [Interpreter](paclet:ref/Interpreter)`["..."]` and [FormFunction](paclet:ref/FormFunction) do): a string with `<name:Type>` slots, like `"add <a:Number> and <b:Number>"`. Each template is split into literal segments and slot recognizers, sequenced into a `ParseSequence`, and the slot bindings flow into the rule body via [ReplaceAll](paclet:ref/ReplaceAll) on the named symbols.

Slot types supported:

| `<name:Type>`            | Recognizer                                              | Result form         |
|--------------------------|---------------------------------------------------------|---------------------|
| `<name>` (bare)          | `ParseSome[ParseCharacter[WordCharacter]]`              | `String`            |
| `<name:Word>`            | `ParseSome[ParseCharacter[LetterCharacter]]`            | `String`            |
| `<name:Number>`          | `ParseSome[ParseCharacter[DigitCharacter]]` + `FromDigits` | `Integer`        |
| `<name:Integer>`         | alias for `Number`                                      | `Integer`           |
| any other type           | `ParseFail` (use the pattern form for semantic types)   | -                   |

```wl
In[]:= Parse[GrammarRules[{"the weather in <city>" -> city}], "the weather in NYC"]
Out[]= "NYC"

In[]:= Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
Out[]= 8

In[]:= Parse[GrammarRules[{"<verb:Word> <obj:Word>" :> {verb, obj}}], "eat sushi"]
Out[]= {"eat", "sushi"}
```

### (b) The pattern form (matches the built-in's surface syntax)

The same shapes the cloud-deployed [GrammarRules](paclet:ref/GrammarRules) accepts - `FixedOrder`, `Alternatives` (`form1 | form2`), `OptionalElement`, `DelimitedSequence`, `Repeated` (`form..`), `CaseSensitive`, `GrammarToken["Name"]`, and the `x : form` capture form (`Pattern[name, form]`). The same `GrammarRules[...]` expression you would `CloudDeploy` runs locally without modification.

Each pattern node lowers to a `ParserCombinator`; the captures collected by `Pattern[name, _]` nodes bubble up as an `Association` of bindings, which then substitute into the rule body via the same `ReplaceAll` machinery the template form uses.

| Built-in pattern node             | Lowered to                                                |
|-----------------------------------|-----------------------------------------------------------|
| `"string"`                        | `ParseLiteral`                                            |
| `form1 \| form2 \| ...`           | `ParseChoice`                                             |
| `FixedOrder[f1, f2, ...]`         | `ParseSequence` with optional whitespace between elements |
| `OptionalElement[form]`           | `ParseChoice[form, ParseSucceed[Missing["NoMatch"]]]`     |
| `OptionalElement[form, default]`  | `ParseChoice[form, ParseSucceed[default]]`                |
| `form..` (`Repeated`)             | `ParseSome`                                               |
| `form...` (`RepeatedNull`)        | `ParseMany`                                               |
| `DelimitedSequence[form, sep]`    | `ParseSepBy1`                                             |
| `CaseSensitive[form]`             | inner `form` (case-insensitive matching not modeled)      |
| `GrammarToken["Number"]`          | the local `slotParser["Number"]` (digit-based)            |
| `GrammarToken["Word"]`            | the local `slotParser["Word"]` (letter-based)             |
| `GrammarToken[<other>]`           | `ParseFail` (no local Interpreter call yet)               |
| `Pattern[name, form]` (`x : form`)| inner form, with `name -> matchedValue` added to bindings |
| `AnyOrder[...]`, `RegularExpression[...]` | not yet lowered                                   |

```wl
In[]:= Parse[
       GrammarRules[{
           FixedOrder["add", a : GrammarToken["Number"], "and", b : GrammarToken["Number"]] :> a + b
       }],
       "add 3 and 5"
   ]
Out[]= 8

In[]:= Parse[
       GrammarRules[{appl : ("stove" | "oven" | "fridge") :> appl}],
       "fridge"
   ]
Out[]= "fridge"

In[]:= Parse[
       GrammarRules[{nums : DelimitedSequence[GrammarToken["Number"], ","] :> Total[nums]}],
       "1,2,3,4"
   ]
Out[]= 10

In[]:= Parse[
       GrammarRules[{
           FixedOrder["turn", OptionalElement["the", "no-the"], appl : ("stove" | "oven")] :> appl
       }],
       "turn stove"
   ]
Out[]= "stove"
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

What the local lowering does *not* cover yet, with the workarounds:

### Not yet lowered: `AnyOrder`, `RegularExpression`, subsidiary `GrammarRules[rules, defs]`

`AnyOrder[f1, f2, f3]` requires permutation matching (combinatorial in the number of elements). For small N the desugaring `AnyOrder[a, b, c] -> a~~b~~c | a~~c~~b | b~~a~~c | ...` is tractable, but the local lowering doesn't generate it today.

`RegularExpression[r]` would need to wrap a `StringCases`-style runtime check at the current parse position. Skipped pending a use case.

`GrammarRules[rules, defs]` lets a rule reference a named domain (`GrammarToken["MyCity"]`) defined in `defs`. The local lowering currently ignores the second argument; only the *rules* list is consumed. Workaround: inline the domain's alternatives directly into the rule via `GrammarToken["X"] -> ("foo" | "bar" | ...)` substitution, or compose the alternatives in the combinator core.

### Not yet lowered: semantic `GrammarToken` types

`GrammarToken["City"]`, `GrammarToken["Color"]`, `GrammarToken["Date"]`, `GrammarToken["SemanticNumber"]`, ... resolve via [Interpreter](paclet:ref/Interpreter) in the cloud. Locally, only the digit-and-letter classes (`Number`, `Integer`, `Word`, the default any-word slot) are wired up.

**Workaround:** capture the slot as a `Word` and call `Interpreter[type]` yourself in the rule body:

```wl
Parse[
    GrammarRules[{
        FixedOrder["weather in", c : GrammarToken["Word"]] :> Interpreter["City"][c]
    }],
    "weather in Boston"
]
(* Entity["City", {"Boston", "Massachusetts", "UnitedStates"}] *)
```

Adding `Interpreter[type]` as the implementation of `slotParser[type]` for unsupported types is on the v0.4 list - it would make the cloud / local rendering of `GrammarToken[...]` exactly symmetric (modulo the network round-trip).

### Not yet lowered: `AllowLooseGrammar`, `IgnoreCase`, `IgnoreDiacritics`

The cloud's default `AllowLooseGrammar -> True` lets `GrammarApply[g, "could you please tell me the weather in Boston"]` match a `"weather <c:City>"` rule by ignoring surrounding fluff. The local parser is strict-PEG: every character must match. Same for case insensitivity (`IgnoreCase -> True` by default in the cloud, no equivalent locally) and diacritic stripping.

**Workaround:** for loose-grammar behavior, scan with [StringPosition](paclet:ref/StringPosition) for a candidate substring and run the rule on that; for case insensitivity, lowercase the input before parsing. Both are awkward; honoring the `GrammarRules` options at lowering time is the eventual fix.

---

## Part 4 - When to use which

| Situation | Choice |
|-----------|--------|
| You need named-entity recognition (`City`, `Country`, `Color`, `Date`) on free-form natural-language input | `CloudDeploy[GrammarRules[...]]` + `GrammarApply` - the built-in is doing real Interpreter work the local parser doesn't replicate |
| You need a structured template like `"add <a:Number> and <b:Number>"` for digit/word patterns, no NLP | `Parse[GrammarRules[...]]` locally - no network, no auth, no rate limits |
| You're parsing a formal grammar (a DSL, a math expression, a file format) | Skip `GrammarRules` entirely - the bare `Parse*` combinators in [`Wolfram\`Parser\``](paclet:Wolfram/WolframParser/guide/WolframParser) are the right tool |
| You want to test offline what would deploy to the cloud later | `Parse[GrammarRules[...]]` accepts the same `FixedOrder` / `OptionalElement` / `DelimitedSequence` / `x : GrammarToken[...]` shapes the cloud does, modulo the semantic-token gap above |
| You want maximum speed for a fixed grammar | `ParserCompile[GrammarRules[...]]` - same shape, returns a [CompiledCodeFunction](paclet:ref/CompiledCodeFunction) |

The two-tier story behind the design: `GrammarRules` is the *declarative* layer; `Parse*` is the *combinator* layer. Anything you can write declaratively, you can also write as combinators; the declarative form lowers down. For the common subset, the local declarative layer is *symmetric* with the cloud one - same `GrammarRules[...]` expression, different deployment target.

---

## Worked example: same `GrammarRules` runs locally and in the cloud

The `TestGrammar_3` "appliance controller" from Part 1:

```wl
applianceRule = GrammarRules[{
    FixedOrder[
        "turn",
        OptionalElement["the", "no-the"],
        appl : ("stove" | "oven" | "fridge"),
        state : ("on" | "off")
    ] :> {appl, state}
}];
```

**Cloud-deployed:**

```wl
co = CloudDeploy[applianceRule, "TestGrammar_3", Permissions -> "Public"];
GrammarApply[co, "turn the stove on"]
(* {"stove", "on"} *)
GrammarApply[co, "turn oven off"]
(* {"oven", "off"} *)
```

**Local, same expression:**

```wl
Needs["Wolfram`Parser`"];
Parse[applianceRule, "turn the stove on"]
(* {"stove", "on"} *)
Parse[applianceRule, "turn oven off"]
(* {"oven", "off"} *)
```

The local path also compiles:

```wl
cf = ParserCompile[applianceRule];
cf["turn the fridge on"]
(* {"fridge", "on"} *)
```

No rewrite, no separate combinator shape - the `applianceRule` value flows through `CloudDeploy + GrammarApply`, `Parse`, or `ParserCompile` interchangeably. Where the cloud and local paths still diverge is the semantic-token wall: replace one of the alternatives with `c : GrammarToken["City"]` and you'd need the cloud's Interpreter access (or the `Interpreter[c]`-in-body workaround) to resolve "Boston" into a city Entity. Everything else lowers identically.

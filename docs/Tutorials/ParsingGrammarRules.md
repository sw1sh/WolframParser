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

[GrammarRules]() is the Wolfram Language's declarative grammar DSL. The built-in implementation only runs after a [CloudDeploy](): you write a <code>[GrammarRules]()[...]</code> expression, ship it to a cloud object, then call [GrammarApply]() (or [Interpreter]()) on the URL. Local kernels have no way to evaluate a [GrammarRules]() expression directly - the symbol exists but is inert. <code>Wolfram\`Parser\`</code> takes the same [GrammarRules]() head, lowers it to a [ParserCombinator](), and runs it on the local kernel - so the same grammar that backed your [CloudObject]() can be parsed without a network round-trip.

This note has four parts:

1. **What the built-in supports** - the full pattern vocabulary [GrammarRules]() accepts, verified against <code>[CloudDeploy]()["TestGrammar_N"]</code> deployments.
2. **What the local implementation supports today** - the subset of that vocabulary that `Parse[GrammarRules[...], input]` handles in v0.2.5, with side-by-side examples.
3. **The gap** - which built-in features are NOT yet ported, the workarounds, and what would be needed to close each one.
4. **When to use which** - decision guide.

---

## Part 1 - What the built-in supports

Deployed and verified against the cloud:

| Cloud test name           | Pattern shape                                                  | Result                              |
|---------------------------|----------------------------------------------------------------|-------------------------------------|
| `TestGrammar_1`           | `"hello" -> "greeting"`                                        | literal string match                |
| `TestGrammar_2`           | <code>[FixedOrder]()["add", a:[GrammarToken]()["SemanticNumber"], "and", b:[GrammarToken]()["SemanticNumber"]] :> a+b</code> | named slot with type via <code>[GrammarToken]()</code> |
| `TestGrammar_3`           | `FixedOrder["turn", OptionalElement["the"], appl:("stove"|"oven"|"fridge"), state:("on"|"off")] :> {appl, state}` | alternatives, optional elements, `AllowLooseGrammar` trims trailing fluff |
| `TestGrammar_4`           | `nums:DelimitedSequence[GrammarToken["SemanticNumber"], ","|"and"] :> Total[nums]` | one-or-more with delimiter |
| `TestGrammar_5`           | `GrammarRules[{rules}, {defs}]` with subsidiary `"MyCity" -> ...` definitions | named-domain definitions |
| `TestGrammar_6`           | `c:GrammarToken["City"]` resolving to an `Entity["City", ...]` | Interpreter-backed semantic tokens |
| `TestGrammar_8`           | `AnyOrder["red", "green", "blue"] :> "all three colors named"` | permutation matching |
| `TestGrammar_10loose`     | `AllowLooseGrammar -> True` (default)                          | matches inside arbitrary surrounding text |
| `TestGrammar_12`          | `CaseSensitive["Hello"] -> ...`                                | per-rule case sensitivity |

The pattern shapes accepted, as documented in [GrammarRules]():

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

## Part 2 - What <code>Wolfram\`Parser\`</code> supports locally today

`Parse[GrammarRules[{...}], input]` accepts two surface shapes for the rule LHS, both lowered on the same code path:

### (a) The string-template form

The simpler shape (which the cloud's built-in does *not* accept, but [Interpreter]()`["..."]` and [FormFunction]() do): a string with `<name:Type>` slots, like `"add <a:Number> and <b:Number>"`. Each template is split into literal segments and slot recognizers, sequenced into a `ParseSequence`, and the slot bindings flow into the rule body via [ReplaceAll]() on the named symbols.

Slot types supported:

| `<name:Type>`            | Recognizer                                              | Result form         |
|--------------------------|---------------------------------------------------------|---------------------|
| `<name>` (bare)          | `ParseSome[ParseCharacter[WordCharacter]]`              | `String`            |
| `<name:Word>`            | `ParseSome[ParseCharacter[LetterCharacter]]`            | `String`            |
| `<name:Number>`          | `ParseSome[ParseCharacter[DigitCharacter]]` + `FromDigits` | `Integer`        |
| `<name:Integer>`         | alias for `Number`                                      | `Integer`           |
| any other type           | `ParseFail` (use the pattern form for semantic types)   | -                   |

Bare slot captures a word run:

```wl
Parse[GrammarRules[{"the weather in <city>" -> city}], "the weather in NYC"]
```

Typed slots and arithmetic in the rule body:

```wl
Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
```

Multi-slot template with a list-shaped result:

```wl
Parse[GrammarRules[{"<verb:Word> <obj:Word>" :> {verb, obj}}], "eat sushi"]
```

### (b) The pattern form (matches the built-in's surface syntax)

The same shapes the cloud-deployed [GrammarRules]() accepts - `FixedOrder`, `Alternatives` (`form1 | form2`), `OptionalElement`, `DelimitedSequence`, `Repeated` (`form..`), `CaseSensitive`, `GrammarToken["Name"]`, and the `x : form` capture form (`Pattern[name, form]`). The same `GrammarRules[...]` expression you would `CloudDeploy` runs locally without modification.

Each pattern node lowers to a `ParserCombinator`; the captures collected by `Pattern[name, _]` nodes bubble up as an `Association` of bindings, which then substitute into the rule body via the same `ReplaceAll` machinery the template form uses.

| Built-in pattern node             | Lowered to                                                |
|-----------------------------------|-----------------------------------------------------------|
| `"string"`                        | [ParseLiteral]()                                          |
| `form1 \| form2 \| ...`           | [ParseChoice]()                                           |
| `FixedOrder[f1, f2, ...]`         | [ParseSequence]() with optional whitespace between elements |
| `AnyOrder[f1, f2, ...]`           | [ParseChoice]() over every permutation of the FixedOrder lowering (N! alternatives) |
| `OptionalElement[form]`           | `ParseChoice[form, ParseSucceed[Missing["NoMatch"]]]`     |
| `OptionalElement[form, default]`  | `ParseChoice[form, ParseSucceed[default]]`                |
| `form..` (`Repeated`)             | [ParseSome]()                                             |
| `form...` (`RepeatedNull`)        | [ParseMany]()                                             |
| `DelimitedSequence[form, sep]`    | [ParseSepBy1]()                                           |
| `CaseSensitive[form]`             | inner `form` (case-insensitive matching not modeled)      |
| `RegularExpression["r"]`          | [ParseRegex]() (anchored regex match at the current position) |
| `GrammarToken["Number"]`          | the local `slotParser["Number"]` (digit-based, no [Interpreter]() call) |
| `GrammarToken["Word"]`            | the local `slotParser["Word"]` (letter-based)             |
| `GrammarToken["Integer"]`         | alias for `Number`                                        |
| `GrammarToken[<other-string>]`    | a word-ish run fed to `Interpreter[type]`; parser fails when interpretation fails |
| `Pattern[name, form]` (`x : form`)| inner form, with `name -> matchedValue` added to bindings |

`FixedOrder` with two typed slots, arithmetic in the body:

```wl
Parse[
    GrammarRules[{
        FixedOrder["add", a : GrammarToken["Number"], "and", b : GrammarToken["Number"]] :> a + b
    }],
    "add 3 and 5"
]
```

`Alternatives` with a captured choice:

```wl
Parse[GrammarRules[{appl : ("stove" | "oven" | "fridge") :> appl}], "fridge"]
```

`DelimitedSequence` collecting a list of numbers:

```wl
Parse[GrammarRules[{nums : DelimitedSequence[GrammarToken["Number"], ","] :> Total[nums]}], "1,2,3,4"]
```

`OptionalElement` with a default:

```wl
Parse[
    GrammarRules[{
        FixedOrder["turn", OptionalElement["the", "no-the"], appl : ("stove" | "oven")] :> appl
    }],
    "turn stove"
]
```

`AnyOrder` matching any permutation of three literals:

```wl
Parse[GrammarRules[{AnyOrder["red", "green", "blue"] :> "all three"}], "blue red green"]
```

`RegularExpression` as a slot:

```wl
Parse[GrammarRules[{n : RegularExpression["\\d+"] :> ToExpression[n]}], "42"]
```

Subsidiary-domain definitions via the two-argument `GrammarRules[rules, defs]`:

```wl
Parse[
    GrammarRules[
        {FixedOrder["from", c : GrammarToken["MyCity"]] :> c},
        {"MyCity" -> ("Paris" | "Tokyo" | "Boston")}
    ],
    "from Paris"
]
```

A semantic `GrammarToken[type]` resolves via [Interpreter]():

```wl
Parse[GrammarRules[{c : GrammarToken["Color"] :> c}], "red"]
```

```wl
Parse[GrammarRules[{n : GrammarToken["SemanticNumber"] :> n}], "five"]
```

The rule head is either [Rule]() or [RuleDelayed](). With [Rule](), the body evaluates at lowering:

```wl
Parse[GrammarRules[{"<n:Number>" -> n}], "42"]
```

With [RuleDelayed](), the body re-evaluates per match (useful when the body is non-trivial):

```wl
Parse[GrammarRules[{"<n:Number>" :> n+1}], "42"]
```

[Parse]() is strict - input must match the *whole* template, not just a prefix:

```wl
Parse[GrammarRules[{"hello" -> "hi"}], "hello there"]
```

Use [ParsePartial](paclet:Wolfram/WolframParser/ref/Parse) when you want a prefix match.

### The same rules through [ParserCompile]()

A [GrammarRules]() lowers to a [ParserCombinator](); [ParserCompile]() then materializes the [FunctionCompile]()d form. Compile once, run repeatedly:

```wl
ParserCompile[GrammarRules[{"<n:Integer>" :> n^2}]]["42"]
```

Same syntax, same result, faster on hot paths.

---

## Part 3 - The gap

The local lowering now covers every documented pattern node: `FixedOrder`, `AnyOrder`, `Alternatives`, `OptionalElement`, `Repeated`, `RepeatedNull`, `DelimitedSequence`, `CaseSensitive`, `RegularExpression`, `Pattern`, `GrammarToken` (digit / letter / Interpreter-backed), and the `GrammarRules[rules, defs]` two-argument form. The remaining gap is the **option-level** behaviour the cloud sets by default:

### Not yet honoured: `AllowLooseGrammar`, `IgnoreCase`, `IgnoreDiacritics`

The cloud's default `AllowLooseGrammar -> True` lets `GrammarApply[g, "could you please tell me the weather in Boston"]` match a `"weather <c:City>"` rule by ignoring surrounding fluff. The local parser is strict-PEG: every character must match. Same for case insensitivity (`IgnoreCase -> True` by default in the cloud, no equivalent locally) and diacritic stripping.

**Workaround:** for loose-grammar behavior, scan with [StringPosition]() for a candidate substring and run the rule on that; for case insensitivity, lowercase the input before parsing. Both are awkward; honoring the `GrammarRules` options at lowering time is the eventual fix.

### Caveats on the Interpreter-backed slots

A `GrammarToken[type]` whose `type` isn't one of `Number` / `Integer` / `Word` consumes a single word-ish run (`[A-Za-z0-9][A-Za-z0-9_'.\-]*`) from the current position and feeds it to `Interpreter[type]`. Two consequences:

- **Multi-word entities** (`City "New York"`, `DateString "March 5 2026"`) don't match through a single `GrammarToken[type]` because the local consumer stops at the first whitespace. Compose with `FixedOrder` or a custom `RegularExpression["..."]` slot when the entity spans whitespace.
- **Network-required types** (`City`, `Country`, `Quantity`, ...) still call out to the Wolfram knowledge engine via `Interpreter[type]`; the *grammar* is local, the *semantic resolution* is not.

---

## Part 4 - When to use which

| Situation | Choice |
|-----------|--------|
| You need named-entity recognition (`City`, `Country`, `Color`, `Date`) on free-form natural-language input | `CloudDeploy[GrammarRules[...]]` + `GrammarApply` - the built-in is doing real Interpreter work the local parser doesn't replicate |
| You need a structured template like `"add <a:Number> and <b:Number>"` for digit/word patterns, no NLP | `Parse[GrammarRules[...]]` locally - no network, no auth, no rate limits |
| You're parsing a formal grammar (a DSL, a math expression, a file format) | Skip `GrammarRules` entirely - the bare `Parse*` combinators in [`Wolfram\`Parser\``](paclet:Wolfram/WolframParser/guide/WolframParser) are the right tool |
| You want to test offline what would deploy to the cloud later | `Parse[GrammarRules[...]]` accepts the same `FixedOrder` / `OptionalElement` / `DelimitedSequence` / `x : GrammarToken[...]` shapes the cloud does, modulo the semantic-token gap above |
| You want maximum speed for a fixed grammar | `ParserCompile[GrammarRules[...]]` - same shape, returns a [CompiledCodeFunction]() |

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

**Cloud-deployed**, via [CloudDeploy]() + [GrammarApply]():

```wl
co = CloudDeploy[applianceRule, "TestGrammar_3", Permissions -> "Public"]
```

```wl
GrammarApply[co, "turn the stove on"]
```

```wl
GrammarApply[co, "turn oven off"]
```

**Local, same expression**, via [Parse]() with no network round-trip:

```wl
Parse[applianceRule, "turn the stove on"]
```

```wl
Parse[applianceRule, "turn oven off"]
```

The local path also compiles:

```wl
ParserCompile[applianceRule]["turn the fridge on"]
```

No rewrite, no separate combinator shape - the `applianceRule` value flows through [CloudDeploy]() + [GrammarApply](), [Parse](), or [ParserCompile]() interchangeably. Where the cloud and local paths still diverge is the semantic-token wall: replace one of the alternatives with <code>c : [GrammarToken]()["City"]</code> and you'd need the cloud's [Interpreter]() access (or the in-body workaround) to resolve "Boston" into a city [Entity](). Everything else lowers identically.

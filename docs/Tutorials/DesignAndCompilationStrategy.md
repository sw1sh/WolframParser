---
Template: TechNote
Name: DesignAndCompilationStrategy
Title: Design and Compilation Strategy
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy
Keywords: [parser, design, FunctionCompile, GrammarRules, LaTeX, TPTP, compilation, combinator, ParserCombinator, PEG]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserLandscape]
---

## What this note covers

The [ParserLandscape](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) survey lays out *what's already there*; this note lays out *what we are building*. The plan in one sentence: **reuse the [GrammarRules]() declarative DSL, but compile the rules to a local parser via [FunctionCompile]() instead of round-tripping through [CloudDeploy](), and pair that with an Anton-style `Parse*` combinator core that all funnels into a single computable `ParserCombinator` head.**

The note has six parts:

1. **The single `ParserCombinator` head**: one canonical wrapper that every combinator constructor produces, with [UpValues]() for operator composition and a [SummaryBox]()-style formatter.
2. **`Parse*` constructors**: the user-facing functions, named in the [`AntonAntonov/FunctionalParsers`](paclet:AntonAntonov/FunctionalParsers/guide/FunctionalParsers) tradition.
3. **Two-tier API**: a declarative GrammarRules-compatible entry point that *lowers* to `ParserCombinator`, and the bare combinator core for grammars that don't fit the declarative shape.
4. **Parser algebra**: the small set of primitive combinators all higher-level constructs lower to.
5. **Compilation strategy**: how a `ParserCombinator` tree lowers to a typed first-order form and what [FunctionCompile]() makes of it.
6. **Worked targets**: LaTeX math and TPTP - the two grammars that motivate the choice of primitives.
7. **Open questions**: things deliberately left unresolved in v0.1.

---

## Part 1 - The single `ParserCombinator` head

Every parser is a single computable object `ParserCombinator[type, args, opts]`:

- `type` - a symbol naming the combinator shape (`Sequence`, `Choice`, `Many`, `Literal`, ...)
- `args` - the combinator's children (other `ParserCombinator` instances, or terminal data)
- `opts` - an [Association]() of options (`<|"Memoize" -> True, ...|>`)

The head is *opaque* to user code: you never write `ParserCombinator[...]` by hand. Instead you call one of the `Parse*` constructors (next section), each of which returns a `ParserCombinator` of the appropriate type. The head exists for three reasons:

**(1) Composition via UpValues.** Because every parser is a `ParserCombinator`, we can attach [UpValues]() to that head and overload the WL operators that actually parse:

| WL syntax       | Lowers to                               | Combinator                |
|-----------------|-----------------------------------------|---------------------------|
| `p1 \| p2`      | `Alternatives[p1, p2]`                  | `ParseChoice`             |
| `p1 ~~ p2`      | `StringExpression[p1, p2]`              | `ParseSequence`           |
| `p..`           | `Repeated[p]`                           | `ParseSome` (one or more) |
| `p...`          | `RepeatedNull[p]`                       | `ParseMany` (zero or more)|
| `Optional[p]`   | `Optional[p]`                           | `ParseOptional`           |

Why these and not others:

- `|` is `Alternatives` - the semantic match to choice is exact, and the operator is the same one PEG / regex / EBNF use.
- `~~` is [StringExpression](). The UpValue *only* fires when both sides are `ParserCombinator` instances - plain string sequences (`"foo" ~~ "bar"`) keep their built-in meaning. This dual interpretation is the point: a parser library that overloads `~~` reads naturally to a user who already thinks of string sequences in those terms.
- `..` / `...` are [Repeated]() / [RepeatedNull](), which already mean "one or more" / "zero or more" in pattern context. Reusing them for parser repetition is the obvious mapping.
- `~` is *not* overloaded - `a~f~b` is WL's infix function notation `f[a, b]`, not a binary operator.

**(2) SubValue: call a parser as a function.** Every `ParserCombinator` also carries a SubValues rule: `pc[input]` evaluates to `Parse[pc, input]`. So a constructed parser is *directly callable*, the same way a `CompiledCodeFunction` or an `InterpolatingFunction` is. For an uncompiled parser the SubValue routes to the interpreter; for one passed through `ParserCompile` it routes to the cached compiled function.

A sample composition:

```wl
(* match one or more digits, followed optionally by a dot-and-fraction *)
number = ParseCharacter[DigitCharacter].. ~~ Optional[ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]...];
```

UpValues mean each operator picks the right combinator without the user ever typing `ParserCombinator[...]`.

**(3) A canonical, inspectable representation.** Every parser is a tree of `ParserCombinator` nodes, so the compiler, the pretty-printer, and the diagnostic machinery all walk *one* expression shape. There is no separate "compiled form" data type at the user-visible level - `ParserCompile[p]` adds a `"Code" -> CompiledCodeFunction[...]` entry to the wrapper's options and otherwise leaves the tree alone. The presence of `"Code"` is the canonical "is this compiled?" marker; no separate `"Compiled" -> True` flag is needed.

**(4) A nice summary box.** `ParserCombinator` carries a [BoxForm`ArrangeSummaryBox]() formatter modelled on `FiniteFieldElement` / `PAdicNumber` / `Quantity`. Always-visible: combinator type, arity, compile status. Expanded: the structural sketch, the option association, an icon hinting at the combinator family (a sequence of glyphs for `Sequence`, a fork for `Choice`, a star for `Many`, a brace for `Between`, *etc.*). Concretely:

```
ParserCombinator
  ── Type: Sequence
  ── Arity: 3
  ── Compiled: False
  ── Structure: Literal["the weather in "] ~~ Capture["city", Restricted["City", "USA"]] ~~ Literal["."]
  ── Options: <|"Memoize" -> False, "TrackPosition" -> True|>
```

The summary box is the same convention used by every modern WL computable object - users get a one-line glance plus an opener, not an opaque blob.

---

## Part 2 - `Parse*` constructors

Following the [`AntonAntonov/FunctionalParsers`](paclet:AntonAntonov/FunctionalParsers/guide/FunctionalParsers) naming convention, every constructor is a function with a `Parse*` prefix that returns a `ParserCombinator`. The full table (v0.1 plan):

| Constructor                            | Returns `ParserCombinator[...]` of type | What it matches                                  |
|----------------------------------------|------------------------------------------|--------------------------------------------------|
| `ParseLiteral[s]`                      | `Literal`                                | the exact string / token `s`                     |
| `ParseCharacter[pat]`                  | `Character`                              | a single character matching `pat` ([LetterCharacter](), [DigitCharacter](), [CharacterRange]()`[a, b]`, an `Alternatives` of these, or a literal 1-char string) |
| `ParseToken[type]`                     | `Token`                                  | a tagged `Token[type, _, _]`                     |
| `ParseSucceed[val]`                    | `Succeed`                                | always succeed with `val` (no input consumed)    |
| `ParseFail[msg]`                       | `Fail`                                   | always fail with `msg`                           |
| `ParseSequence[p1, p2, ...]`           | `Sequence`                               | each `pi` in order; result is a list             |
| `ParseChoice[p1, p2, ...]`             | `Choice`                                 | first `pi` that matches (PEG-ordered)            |
| `ParseMany[p]`                         | `Many`                                   | zero or more `p`                                 |
| `ParseSome[p]`                         | `Some`                                   | one or more `p`                                  |
| `ParseOptional[p]`                     | `Optional`                               | zero or one `p`                                  |
| `ParseBetween[open, p, close]`         | `Between`                                | `open`, then `p`, then `close`; result is `p`'s  |
| `ParseSepBy[p, sep]`                   | `SepBy`                                  | zero or more `p` separated by `sep`              |
| `ParseSepBy1[p, sep]`                  | `SepBy1`                                 | one or more `p` separated by `sep`               |
| `ParseChainLeft[p, op, init]`          | `ChainLeft`                              | left-associative operator chain                  |
| `ParseChainRight[p, op, init]`         | `ChainRight`                             | right-associative operator chain                 |
| `ParseLookahead[p]`                    | `Lookahead`                              | succeed iff `p` would match, *consume nothing*   |
| `ParseNotFollowedBy[p]`                | `NotFollowedBy`                          | succeed iff `p` would *not* match, consume nothing |
| `ParseTry[p]`                          | `Try`                                    | backtrack on failure even after consuming        |
| `ParseAction[p, f]`                    | `Action`                                 | apply `f` to `p`'s result                        |
| `ParseCapture[name, p]`                | `Capture`                                | tag `p`'s result with `name` (for `GrammarRules` slot lowering) |
| `ParseRecursive[name, body]`           | `Recursive`                              | a named recursive parser body                    |

The constructors are *just* `ParserCombinator` builders - they do not run the parser; they only produce the value. Running is `Parse[parser, input]` (interpretive) or `ParserCompile[parser][input]` (compiled).

### Worked sample composition

The same number-parser, three equivalent ways:

```wl
(* operator form - shortest, idiomatic for new code *)
number = ParseCharacter[DigitCharacter].. ~~ Optional[ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]...];

(* explicit constructor form - what the UpValues lower to *)
number = ParseSequence[
    ParseSome[ParseCharacter[DigitCharacter]],
    ParseOptional[ParseSequence[
        ParseLiteral["."],
        ParseMany[ParseCharacter[DigitCharacter]]
    ]]
];

(* mixed - drop into the operator form wherever readable, fall back to explicit calls when it helps *)
number = ParseSequence[
    ParseCharacter[DigitCharacter]..,
    ParseOptional[ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]...]
];
```

All three return *the same* `ParserCombinator` expression. Composability is a single-axis story - whatever you write, it lowers into one canonical tree.

---

## Part 3 - Two-tier API

### Tier 1 - the declarative path (`GrammarRules`-compatible)

The built-in [GrammarRules]() takes a list of slot-templates paired with actions and returns an inert symbolic form. Today the only way to *evaluate* a `GrammarRules` object is to deploy it as a cloud object and call `GrammarApply` against the deployment; the declaration itself is just data:

```wl
GrammarRules[{
    "the weather in <city:Restricted[\"City\", \"USA\"]>" -> city,
    "convert <amount:Number> <from:Restricted[\"Currency\"]> to <to:Restricted[\"Currency\"]>"
        :> CurrencyConvert[Quantity[amount, from], to]
}]
```

`WolframParser` accepts the same declaration, and provides two ways to use it locally:

```wl
(* "just parse" - JIT-compile the grammar, cache it, parse the input *)
Parse[grammar, "the weather in NYC"]

(* explicit compile - get back a parser holding the compiled code *)
parser = ParserCompile[grammar];
parser["the weather in NYC"]
```

The compile step is the local analogue of [CloudDeploy](): it materialises a callable parser. The cloud path returns a `CloudObject`; the local path returns a `ParserCombinator` with a `"Code" -> CompiledCodeFunction[...]` entry added to its options. The presence of `"Code"` is what marks the parser as compiled - both `Parse` and the SubValues route compiled parsers through that function.

The slot vocabulary is identical to the built-in one - `<name>`, `<name:Type>`, `<name:Restricted[Type, constraints]>` - and [GrammarToken]() is honoured. The differences are confined to *where* compilation happens, not *what* a grammar means.

### Tier 2 - the combinator core

For grammars where the slot-template DSL is too coarse - LaTeX environments, TPTP formula bodies, expression grammars with operator precedence, anything that needs backtracking control or lookahead - the `Parse*` constructors (with optional operator overloads) are the entry point. The example in Part 2 is the shape.

### How the tiers connect

`GrammarRules[...]` lowers to a `ParserCombinator` expression internally. The two tiers are not parallel implementations of the same thing - tier 1 is a *front-end* to tier 2:

```
GrammarRules[{"the weather in <city:Restricted[\"City\"]>" -> city}]
       │  lower
       ▼
ParserCombinator[Action,
    {ParserCombinator[Sequence, {
        ParserCombinator[Literal, "the weather in ", <||>],
        ParserCombinator[Capture, {"city", Interpreter["City"]}, <||>]
    }, <||>],
    city &},
    <||>]
       │  ParserCompile
       ▼
ParserCombinator[Action, {...}, <|"Code" -> CompiledCodeFunction[...]|>]
```

Adding to either tier benefits the other: a new combinator becomes available as a lowering target for new slot syntaxes; a new slot syntax just extends the lowering.

---

## Part 4 - The parser algebra

Concretely, a parser is a function of two arguments - the input and a starting position - that returns one of:

- `ParseSuccess[result, newPosition]`
- `ParseFailure[position, expected]`

Equivalently, a parser has the type signature `(Input, Position) -> Either[Failure, (Result, Position)]`. This is the same abstract shape Parsec uses; the choice to spell it as a *tagged* sum (rather than a `Maybe[(Result, Pos)]`) is deliberate - it makes the diagnostic info first-class instead of an afterthought.

The combinators are defined by structural equations:

```
ParseSequence[p1, p2] (in, pos)
    = let r1 = p1 (in, pos);
      if r1 is ParseFailure, return r1;
      let (v1, pos1) = r1.value;
      let r2 = p2 (in, pos1);
      if r2 is ParseFailure, return r2;
      let (v2, pos2) = r2.value;
      return ParseSuccess[{v1, v2}, pos2].

ParseChoice[p1, p2] (in, pos)
    = let r1 = p1 (in, pos);
      if r1 is ParseSuccess, return r1;
      let r2 = p2 (in, pos);
      if r2 is ParseSuccess, return r2;
      return ParseFailure[max(r1.pos, r2.pos), r1.expected ++ r2.expected].

ParseMany[p] (in, pos)
    = let acc = {}, cur = pos;
      loop:
        let r = p (in, cur);
        if r is ParseFailure, return ParseSuccess[acc, cur];
        let (v, next) = r.value;
        acc := acc ++ {v}, cur := next;
        goto loop.

ParseLookahead[p] (in, pos)
    = let r = p (in, pos);
      if r is ParseSuccess, return ParseSuccess[Null, pos]; (* position unchanged *)
      return r.

ParseNotFollowedBy[p] (in, pos)
    = let r = p (in, pos);
      if r is ParseSuccess, return ParseFailure[pos, "not " ++ name(p)];
      return ParseSuccess[Null, pos].
```

Every higher-level combinator (`ParseOptional`, `ParseBetween`, `ParseSepBy`, `ParseChainLeft`, *etc.*) is defined as a derivation from these primitives. There are no special cases inside the compiler - if you want a new combinator, define it in terms of the primitives, and the existing lowering picks it up.

### Two design choices worth flagging

**PEG-ordered choice by default.** `ParseChoice[p1, p2]` tries `p1` first and commits if it matches - it does not backtrack to try `p2` if a later production fails. This eliminates the ambiguity that plagues general CFG parsers and is what makes a parser linear-time. The trade-off is that grammar authors have to think about rule ordering. For grammars that need full backtracking (rare in practice), `ParseTry[p1] | p2` is the explicit opt-in.

**Failure information accumulates.** When a `ParseChoice` fails, the `expected` set of the surviving failure is the *union* of the expected sets from each branch, taken at the furthest-advanced position. This is the standard Parsec / megaparsec convention for producing "expected X, Y, or Z" error messages instead of just "expected Z".

---

## Part 5 - The compilation strategy

The interpretive path is straightforward: each combinator is a function, `ParseSequence[p1, p2][in, pos]` is just function application, and the whole thing runs at WL-evaluator speed. This is what `AntonAntonov/FunctionalParsers` does, and it's perfectly adequate for grammar-sized inputs (kilobytes).

The compiled path is the interesting part. The goal is to take a `ParserCombinator` tree and lower it to a [FunctionCompile]()-friendly form: a typed first-order representation that the Wolfram Compiler can ship through LLVM.

### Why FunctionCompile is the right hammer

[FunctionCompile]() is the public-facing entry point to the Wolfram Compiler. It takes a pure function, infers types (or accepts explicit `Typed[...]` annotations), and produces a `CompiledCodeFunction` backed by native code. The interesting consequences for a parser:

- **Native integers and strings.** `Typed[Integer64]` for positions, `Typed["UTF8String"]` for input. No boxing on every character access.
- **Mutual recursion.** `FunctionCompile[<|name1 -> f1, name2 -> f2|>]` accepts an association of mutually-recursive functions and compiles them together. A grammar with two non-terminals `<expr>` and `<term>` calling each other compiles to one binary with two entry points.
- **Type stability is enforced.** A function that returns sometimes `Integer` and sometimes `String` won't compile. This shapes the parser's result representation: every parser must produce results of a *single* compiled type, or be lowered to one.
- **No C dependency.** The compiler is part of the kernel. A user installing the paclet does not also install a toolchain.

### The lowering pipeline

```
ParserCombinator[...] expression        (high-level, untyped, structural)
       │  Phase 1: normalisation
       ▼
canonical ParserCombinator tree         (every node is a primitive combinator)
       │  Phase 2: typing
       ▼
typed ParserCombinator tree             (each node tagged with its result type)
       │  Phase 3: result-encoding choice
       ▼
result-encoded tree                     (results unified to one Typed[...] tag)
       │  Phase 4: codegen
       ▼
FunctionCompile-ready function spec     (a function (in, pos) -> Typed[...])
       │  Phase 5: FunctionCompile
       ▼
ParserCombinator with "Code" -> CompiledCodeFunction in its options
```

A few decisions in detail:

**Phase 3 - result encoding.** Different parsers return different result types. `ParseMany[digit]` returns a list of characters; `ParseAction[p, f]` returns whatever `f` returns. FunctionCompile requires a single, statically-known result type, so every parser must produce results of *one* compiled type. The fix is to encode all results as `"InertExpression"` - a managed handle to an ordinary Wolfram expression that flows through compiled code unchanged. Terminals pack their matched substring into one; combinators thread them; and - crucially - **`ParseAction`'s Wolfram callback compiles too**, via `Typed[KernelFunction[f], {"InertExpression"} -> "InertExpression"][...]`. `KernelFunction` lets compiled code call back into the kernel for exactly the arbitrary-Wolfram-function case actions need, so a grammar with semantic actions (including any `GrammarRules` rule) is fully compilable in a single pass - it does not have to drop to the interpreter. The v0.3 codegen only ships the *recognition* subset (results are substrings, return type is a bare position integer); the `InertExpression`-threaded, `KernelFunction`-action codegen is the v0.4 step, de-risked by the working feasibility tests in `Tests/CompileFeasibility.wlt`.

**Phase 4 - codegen.** A parser of shape `ParseSequence[ParseLiteral["foo"], ParseSome[digit]]` compiles to roughly:

```wl
Function[{in, pos},
    Module[{p = pos, acc = {}, ch},
        If[ StringTake[in, {p, p + 2}] =!= "foo",
            ParseFailure[p, "foo"],
            p = p + 3;
            (* ParseSome[digit] body *)
            While[
                ch = StringTake[in, {p, p}];
                DigitQ[ch] && p <= StringLength[in],
                AppendTo[acc, ch]; p++
            ];
            If[acc === {},
                ParseFailure[p, "digit"],
                ParseSuccess[{"foo", acc}, p]
            ]
        ]
    ]
]
```

with the `StringTake` / `DigitQ` / `StringLength` calls replaced by their compiled equivalents (`UTF8StringTake`, `CharacterCodeRange`, *etc.*) where they exist. The codegen is mechanical - each combinator has a fixed expansion. Mutually-recursive non-terminals lower together in the association form `<|expr -> Function[...], term -> Function[...]|>`.

**Memoisation (the packrat option).** The combinator algebra is already linear-time for non-recursive grammars. Recursive grammars in PEG semantics can require packrat memoisation for worst-case-linear time. Memoisation is an opt-in option `ParserCompile[grammar, "Memoize" -> True]` - the default is no memoisation (smaller code, fine for almost everything), but the option exists for grammars that need it.

### What the compile does not buy us

Honest accounting: FunctionCompile is not a magic 100× speedup for parsing.

- **String access still bounces through UTF-8 decoding** for any non-ASCII grammar. This is unavoidable without a separate tokenisation step.
- **Heap-allocating result construction** (building an output AST) does not compile to anything faster than the interpreted path; we minimise it by lowering "structural" results to packed forms where possible.
- **The compile itself takes time**, which is why `ParserCompile[grammar]` is a separate step from `Parse[grammar, input]`. For one-shot parses of small inputs, the interpreted path wins; the compiled path is for grammars used repeatedly or on long inputs.

A realistic expectation is 3-10× over the interpreted path on lexer-heavy grammars (LaTeX math, JSON, TPTP), and a smaller factor on grammars dominated by AST construction.

---

## Part 6 - Worked targets

The choice of primitives above is motivated by two concrete targets. This section walks through how each maps onto the algebra, with enough detail to validate the design.

### Target A - LaTeX math

LaTeX math has been the breaking point for `MarkdownToNotebook`'s built-in path repeatedly. `ImportString[..., "TeX"]` drops styling commands (`\mathbb{R}` becomes a plain `R`); `ToExpression[..., TeXForm]` parses some structure but fails on common constructs like `dx` in integrals; neither composes with the kind of custom-macro extension a real user wants.

A `WolframParser` LaTeX math grammar (sketched at the combinator level - non-evaluating prose, the productions are mutually recursive and depend on a `ParseRecursive` tie not in v0.2):

```
math = expr;

expr = ParseAction[
    term ~~ (ParseChoice[ParseLiteral["+"], ParseLiteral["-"]] ~~ term)...,
    Function[{first, rest}, FoldOperator[first, rest]]
];

term = ParseAction[
    factor ~~ (ParseChoice[ParseLiteral["*"], ParseLiteral["/"]] ~~ factor)...,
    FoldOperator
];

factor = group | command | atom;

group = ParseBetween[ParseLiteral["{"], expr, ParseLiteral["}"]];

command = ParseAction[
    ParseLiteral["\\"] ~~ ParseSome[ParseCharacter[LetterCharacter]] ~~
        Optional[bracketedArg] ~~ ParseMany[bracedArg],
    buildCommand
];

bracedArg = ParseBetween[ParseLiteral["{"], expr, ParseLiteral["}"]];
bracketedArg = ParseBetween[ParseLiteral["["], expr, ParseLiteral["]"]];

atom = number | identifier | bigOperator;

bigOperator = ParseAction[
    (ParseLiteral["\\sum"] | ParseLiteral["\\int"] | ParseLiteral["\\prod"]) ~~
        Optional[ParseLiteral["_"] ~~ group] ~~ Optional[ParseLiteral["^"] ~~ group],
    buildBigOperator
];
```

The `buildCommand` action handles the font-style commands (`\mathbb`, `\mathcal`, `\mathfrak`, `\boldsymbol`) by looking up the macro name and producing the correct `StyleBox` or named character (`\[DoubleStruckCapitalR]` for `\mathbb{R}`, *etc.*) - the exact preprocessing pass that, in the absence of a real parser, would have to live as a `StringReplace` table in `MarkdownToNotebook` itself.

What this grammar gets right that the current built-ins don't:

- **Nested braces** are handled by the recursive `group = ParseBetween["{", expr, "}"]` rule. `StringExpression` cannot express this.
- **Optional arguments** (`\sqrt[3]{x}`) compose naturally via `Optional[bracketedArg]`.
- **`\begin{env}…\end{env}`** is a separate production that captures the environment name and re-enters the grammar with mode-specific rules (math mode in a `\begin{matrix}`, *etc.*).
- **Custom-macro extension** is a matter of `AppendTo[command-action-lookup, "\\mycmd" -> Function[args, ...]]` - no parser regeneration.

### Target B - TPTP

[TPTP](https://www.tptp.org/) (Thousands of Problems for Theorem Provers) is a family of formats for automated theorem proving: FOF (first-order formulas), CNF (clause normal form), TFF (typed FOF), THF (higher-order). A TPTP problem is a sequence of *annotated formulas*:

```
fof(commutativity_of_plus, axiom,
    ! [X, Y]: (plus(X, Y) = plus(Y, X))).

fof(some_property, conjecture,
    ? [X]: (greater(X, zero) & even(X))).
```

The grammar is BNF, publicly specified, and of moderate size (~100 productions for full TFF/THF). The combinators that matter:

- **`ParseSepBy[formula, comma]`** for argument lists
- **`ParseChainLeft[unitFormula, binaryOp]`** for operator-precedence parsing of `&`, `|`, `=>`, `<=>`
- **`ParseTry[...]`** for the LR-conflict-like cases (FOF vs TFF can look identical at the prefix)
- **`ParseBetween[ParseLiteral["("], expr, ParseLiteral[")"]]`** everywhere

A skeleton (non-evaluating prose - mutually recursive):

```
tptpFile = formula...;

formula = (ParseLiteral["fof"] | ParseLiteral["cnf"] | ParseLiteral["tff"] | ParseLiteral["thf"]) ~~
          ParseBetween[ParseLiteral["("], formulaBody, ParseLiteral[")"]] ~~
          ParseLiteral["."];

formulaBody = name ~~ ParseLiteral[","] ~~ role ~~ ParseLiteral[","] ~~ logicFormula;

logicFormula = quantified | binary | unit;

quantified = (ParseLiteral["!"] | ParseLiteral["?"]) ~~ varList ~~ ParseLiteral[":"] ~~ logicFormula;

binary = unit ~~ (ParseLiteral["&"] | ParseLiteral["|"] |
                  ParseLiteral["=>"] | ParseLiteral["<=>"]) ~~ logicFormula;

unit = atom | ParseBetween[ParseLiteral["("], logicFormula, ParseLiteral[")"]] | ParseLiteral["~"] ~~ unit;

atom = predicate ~~ Optional[ParseBetween[ParseLiteral["("], ParseSepBy[term, ParseLiteral[","]], ParseLiteral[")"]]];

term = variable | functionApp | constant;
```

The grammar is straightforward parser-combinator material; the productions above lower to FunctionCompile-able forms by the standard pipeline. The motivation for including TPTP as a target is dual:

1. It validates the *scale* of the grammar - if the combinator algebra cannot express a 100-production grammar cleanly, the algebra is wrong.
2. It validates the *integration* story - the parser returns a structured AST that can be transformed (skolemisation, clausification) by other WL code, which is the use case that drives a lot of automated-reasoning work in the Wolfram ecosystem.

### What the targets imply about the algebra

The two grammars motivate every primitive in the combinator table. `ParseLookahead` and `ParseNotFollowedBy` come from TPTP's FOF/TFF prefix disambiguation; `ParseTry` from the same. `ParseBetween`, `ParseSepBy`, `ParseChoice` are LaTeX-driven. `ParseMany` and `ParseSome` are universal. The fact that both grammars are *recursive* (LaTeX through `group`, TPTP through `logicFormula`) is what makes the mutually-recursive FunctionCompile lowering load-bearing rather than incidental.

---

## Part 7 - Open questions

A list of things explicitly *not* decided in v0.1:

1. **Operator-precedence parsing.** Do we ship a dedicated `ParseOperatorTable[{prec, assoc, op}, ...]` combinator (like Parsec's `buildExpressionParser`), or do users hand-write the precedence cascade via `ParseChainLeft` / `ParseChainRight`? The TPTP and LaTeX grammars both want this; the question is the syntax.
2. **Streaming input.** The current design assumes the input is in memory (string or list). Streaming (parse-while-reading) is an open question - relevant for large TPTP corpora and for editor integration.
3. **Error recovery.** A parse failure currently aborts the whole parse. Some grammars (editors, IDE tools) want to continue past a syntax error and collect multiple errors. This is a separate research problem (panic-mode recovery, FOLLOW-set recovery) and is deferred.
4. **Left-recursion.** Naive PEG / combinator parsers cannot directly express left-recursive rules (`expr = expr "+" term | term` loops forever). The TPTP and LaTeX grammars above all work around this via `ParseMany` / `ParseChainLeft`, which is the standard idiom. Whether to additionally support direct left-recursion (Warth's algorithm, GLR backend) is open.
5. **Packrat memoisation on by default.** Currently `"Memoize" -> False` is the default. Real benchmarks against a corpus of grammars will tell us whether to flip this.
6. **Source-position carrying in `Token`.** The token type is sketched as `Token[type, value, pos]`. The question is what `pos` is - a single character offset (cheap, easy to compile) or a `{line, col}` pair (better diagnostics, more bookkeeping). The lean answer is "character offset in the input, with line/col computed on demand for error messages."

Each of these will be answered by implementation experience against the targets above. The job of the v0.1 release is to ship the survey and this design, get the structure into the working directory, and start filling in the combinator primitives one at a time.

## What ships in v0.1

- The two tech notes ([ParserLandscape](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) and this one).
- The PacletInfo / ResourceDefinition scaffolding under context `` Wolfram`Parser` ``.
- A placeholder kernel.

What lands next (v0.2):

- `ParserCombinator[...]` head, its [SummaryBox]() formatter, its [SubValues]() rule (`pc[input]` -> `Parse[pc, input]`), and its [UpValues]() for `Alternatives` / `StringExpression` / `Repeated` / `RepeatedNull` / `Optional`.
- The primitive `Parse*` constructors (`ParseLiteral`, `ParseCharacter`, `ParseSequence`, `ParseChoice`, `ParseMany`, `ParseSome`, `ParseOptional`, `ParseBetween`, `ParseLookahead`, `ParseNotFollowedBy`, `ParseTry`).
- An interpretive `Parse[parser, input]` that runs the combinators directly.
- A first pass at the `GrammarRules` → `ParserCombinator` lowering.

After that (v0.3+): the FunctionCompile codegen, the LaTeX math grammar, the TPTP grammar, and benchmarks against `AntonAntonov/FunctionalParsers` to see where the compiled path actually wins.

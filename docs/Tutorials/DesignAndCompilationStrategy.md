---
Template: TechNote
Name: DesignAndCompilationStrategy
Title: Design and Compilation Strategy
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy
Keywords: [parser, design, FunctionCompile, GrammarRules, LaTeX, TPTP, compilation, combinator, PEG]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserLandscape]
---

## What this note covers

The [ParserLandscape](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) survey lays out *what's already there*; this one lays out *what we are building*. The plan in one sentence: **reuse the [GrammarRules]() declarative DSL, but compile the rules to a local parser via [FunctionCompile]() instead of round-tripping through [CloudDeploy](), and pair that with a Parsec-style combinator core for everything that doesn't fit the declarative shape.**

The note has five parts:

1. **Two-tier API**: a declarative entry point (GrammarRules-compatible) and a combinator core.
2. **Parser algebra**: the small set of combinators all higher-level constructs lower to.
3. **Compilation strategy**: how a parser lowers to a typed first-order form and what FunctionCompile makes of it.
4. **Worked targets**: LaTeX math and TPTP - the two grammars that motivate the choice of primitives.
5. **Open questions**: things deliberately left unresolved in v0.1, so they're decided against real implementation experience rather than upfront.

---

## Part 1 - Two-tier API

### Tier 1: the declarative path (GrammarRules-compatible)

The built-in [GrammarRules]() takes a list of slot-templates paired with actions and returns an inert symbolic form. Today the only way to *evaluate* a `GrammarRules` object is to deploy it as a cloud object and call `GrammarApply` against the deployment. The declarations themselves are just data:

```wl
GrammarRules[{
    "the weather in <city:Restricted[\"City\", \"USA\"]>" -> city,
    "convert <amount:Number> <from:Restricted[\"Currency\"]> to <to:Restricted[\"Currency\"]>"
        :> CurrencyConvert[Quantity[amount, from], to]
}]
```

`WolframParser` accepts the same declaration, and provides two ways to use it:

```wl
(* "just parse" - JIT-compile the grammar, cache it, parse the input *)
Parse[grammar, "the weather in NYC"]

(* explicit compile - get back a ParserFunction object that holds the compiled code *)
parser = ParserCompile[grammar];
parser["the weather in NYC"]
```

The compile step is the local analogue of [CloudDeploy](): it materialises a callable parser. The cloud path returns a `CloudObject`; the local path returns a `ParserFunction[...]` carrying the FunctionCompile-built kernel.

The slot vocabulary is identical to the built-in one - `<name>`, `<name:Type>`, `<name:Restricted[Type, constraints]>` - and `GrammarToken[type]` is honoured. The differences are confined to *where* compilation happens, not *what* a grammar means.

### Tier 2: the combinator core

For grammars where the slot-template DSL is too coarse - LaTeX environments, TPTP formula bodies, expression grammars with operator precedence, anything that needs backtracking control or lookahead - the combinator core is the entry point. A parser is a head `Parser[...]`, combinators are functions on parsers, operator overloads provide short forms:

```wl
expr = factor ~ ("+" | "-") ~ expr | factor;
factor = digit..;
digit = ParserCharacter[DigitCharacter];

Parse[expr, "12+34-5"]
```

Combinator primitives (Parsec / PEG vocabulary):

| Combinator                | Operator   | Shape                                  |
|---------------------------|------------|----------------------------------------|
| `Sequence[p1, p2, ...]`   | `p1 ~ p2`  | match each in order, collect results   |
| `Choice[p1, p2, ...]`     | `p1 \| p2` | first that matches wins (PEG-ordered)  |
| `Many[p]`                 | `p..`      | zero or more                           |
| `Some[p]`                 | `p ..`     | one or more                            |
| `Optional[p]`             | `p?`       | zero or one (overload tbd)             |
| `Between[open, p, close]` |            | match `open`, then `p`, then `close`   |
| `SepBy[p, sep]`           |            | `p` separated by `sep`                 |
| `Lookahead[p]`            | `&p`       | succeed iff `p` would match, don't consume |
| `NotFollowedBy[p]`        | `!p`       | succeed iff `p` would NOT match, don't consume |
| `Try[p]`                  |            | backtrack on failure even after consuming     |
| `Action[p, f]`            | `p :> f`   | apply `f` to the result                |

Operator-overload notes:
- `|` is naturally PEG-ordered (first-match-wins). This is the *common* case; for true unordered choice, wrap explicitly in `Choice[]` and request `Longest` semantics via an option.
- `..` is `Many` (zero-or-more) by convention with [Repeated](), not `RepeatedNull` - we accept the deviation in exchange for `p..` reading like a Kleene star.
- `~` for sequencing rather than `~~` keeps `~~` available for [StringExpression]() interop.

### How the tiers connect

`GrammarRules[...]` is lowered to a `Parser[...]` expression internally. The two tiers are not parallel implementations of the same thing - tier 1 is a *front-end* to tier 2:

```
GrammarRules[{"the weather in <city:Restricted[\"City\"]>" -> city}]
       │  lower
       ▼
Parser[Action[
    Sequence[
        ParserLiteral["the weather in "],
        Capture[city, Interpreter["City"]]
    ],
    city &
]]
       │  FunctionCompile
       ▼
ParserFunction[<CompiledCodeFunction>, ...metadata...]
```

So adding to either tier benefits the other: a new combinator becomes available as a lowering target for new slot syntaxes; a new slot syntax just extends the lowering.

---

## Part 2 - The parser algebra

Concretely, a parser is a function of two arguments - the input and a starting position - that returns one of:

- `ParseSuccess[result, newPosition]`
- `ParseFailure[position, expected]`

Equivalently, a parser has the type signature `(Input, Position) -> Either[Failure, (Result, Position)]`. This is the same abstract shape Parsec uses; the choice to spell it as a *tagged* sum (rather than a `Maybe[(Result, Pos)]`) is deliberate - it makes the diagnostic info first-class instead of an afterthought.

The combinators are defined by structural equations:

```
Sequence[p1, p2] (in, pos)
    = let r1 = p1 (in, pos);
      if r1 is ParseFailure, return r1;
      let (v1, pos1) = r1.value;
      let r2 = p2 (in, pos1);
      if r2 is ParseFailure, return r2;
      let (v2, pos2) = r2.value;
      return ParseSuccess[{v1, v2}, pos2].

Choice[p1, p2] (in, pos)
    = let r1 = p1 (in, pos);
      if r1 is ParseSuccess, return r1;
      let r2 = p2 (in, pos);
      if r2 is ParseSuccess, return r2;
      return ParseFailure[max(r1.pos, r2.pos), r1.expected ++ r2.expected].

Many[p] (in, pos)
    = let acc = {}, cur = pos;
      loop:
        let r = p (in, cur);
        if r is ParseFailure, return ParseSuccess[acc, cur];
        let (v, next) = r.value;
        acc := acc ++ {v}, cur := next;
        goto loop.

Lookahead[p] (in, pos)
    = let r = p (in, pos);
      if r is ParseSuccess, return ParseSuccess[Null, pos]; (* position unchanged *)
      return r.

NotFollowedBy[p] (in, pos)
    = let r = p (in, pos);
      if r is ParseSuccess, return ParseFailure[pos, "not " ++ name(p)];
      return ParseSuccess[Null, pos].
```

Every higher-level combinator (`Optional`, `Between`, `SepBy`, `ChainLeft`, etc.) is defined as a derivation from these primitives. There are no special cases inside the compiler - if you want a new combinator, define it in terms of the primitives, and the existing lowering picks it up.

### Two design choices worth flagging

**PEG-ordered choice by default.** `Choice[p1, p2]` tries `p1` first and commits if it matches - it does not backtrack to try `p2` if a later production fails. This eliminates the ambiguity that plagues general CFG parsers and is what makes a parser linear-time. The trade-off is that grammar authors have to think about rule ordering. For grammars that need full backtracking (rare in practice), `Try[p1] | p2` is the explicit opt-in.

**Failure information accumulates.** When a `Choice` fails, the `expected` set of the surviving failure is the *union* of the expected sets from each branch, taken at the furthest-advanced position. This is the standard Parsec / megaparsec convention for producing "expected X, Y, or Z" error messages instead of just "expected Z".

---

## Part 3 - The compilation strategy

The interpretive path is straightforward: each combinator is a function, `Sequence[p1, p2][in, pos]` is just function application, and the whole thing runs at WL evaluator speed. This is what `AntonAntonov/FunctionalParsers` does, and it's perfectly adequate for grammar-sized inputs (kilobytes).

The compiled path is the interesting part. The goal is to take a parser expression and lower it to a [FunctionCompile]()-friendly form: a typed first-order representation that the Wolfram Compiler can ship through LLVM.

### Why FunctionCompile is the right hammer

[FunctionCompile]() is the public-facing entry point to the Wolfram Compiler. It takes a pure function, infers types (or accepts explicit `Typed[...]` annotations), and produces a `CompiledCodeFunction` backed by native code. The interesting consequences for a parser:

- **Native integers and strings.** `Typed[Int64]` for positions, `Typed["UTF8String"]` for input. No boxing on every character access.
- **Mutual recursion.** `FunctionCompile[<| name1 -> f1, name2 -> f2 |>]` accepts an association of mutually-recursive functions and compiles them together. A grammar with two non-terminals `<expr>` and `<term>` calling each other compiles to one binary with two entry points.
- **Type stability is enforced.** A function that returns sometimes `Integer` and sometimes `String` won't compile. This shapes the parser's result representation: every parser must produce results of a *single* compiled type, or be lowered to one.
- **No C dependency.** The compiler is part of the kernel. A user installing the paclet does not also install a toolchain.

### The lowering pipeline

```
Parser[...] expression                  (high-level, untyped, structural)
       │  Phase 1: normalisation
       ▼
canonical parser AST                    (every node is a primitive combinator)
       │  Phase 2: typing
       ▼
typed parser AST                        (each parser tagged with its result type)
       │  Phase 3: result-encoding choice
       ▼
result-encoded AST                      (results unified to one Typed[...] tag)
       │  Phase 4: codegen
       ▼
FunctionCompile-ready function spec     (a function (in, pos) -> Typed[...])
       │  Phase 5: FunctionCompile
       ▼
CompiledCodeFunction                    (LLVM-backed native code)
```

A few decisions in detail:

**Phase 3 - result encoding.** Different parsers return different result types. `Many[digit]` returns a list of characters; `Action[p, f]` returns whatever `f` returns. FunctionCompile won't take a function that returns one of several types. The fix is *result-encoding* - pick one wide-enough type for the whole grammar and let each parser pack its result into it. For most grammars, a `Typed["GenericObject"]` (a managed Wolfram expression handle) is the path of least resistance; for hot lexers, a packed-array-of-tokens form is faster.

**Phase 4 - codegen.** A parser of shape `Sequence[Literal["foo"], Many[Digit]]` compiles to roughly:

```wl
Function[{in, pos},
    Module[{p = pos, acc = {}, ch},
        If[ StringTake[in, {p, p + 2}] =!= "foo",
            ParseFailure[p, "foo"],
            p = p + 3;
            (* Many[Digit] body *)
            While[
                ch = StringTake[in, {p, p}];
                DigitQ[ch] && p <= StringLength[in],
                AppendTo[acc, ch]; p++
            ];
            ParseSuccess[{"foo", acc}, p]
        ]
    ]
]
```

with the [`StringTake`/`DigitQ`/`StringLength`] calls replaced by their compiled equivalents (`UTF8StringTake`, `CharacterCodeRange`, etc.) where they exist. The codegen is mechanical - each combinator has a fixed expansion. Mutually recursive non-terminals lower together in the association form `<|expr -> Function[...], term -> Function[...]|>`.

**Memoisation (the packrat option).** The combinator algebra is already linear-time for non-recursive grammars. Recursive grammars in PEG semantics can require packrat memoisation for worst-case-linear time. We make memoisation an opt-in option on `ParserCompile[grammar, Memoize -> True]` - the default is no memoisation (smaller code, fine for almost everything), but the option exists for grammars that need it.

### What the compile does not buy us

Honest accounting: FunctionCompile is not a magic 100x speedup for parsing.

- **String access still bounces through UTF-8 decoding** for any non-ASCII grammar. This is unavoidable without a separate tokenisation step.
- **Heap-allocating result construction** (building an output AST) does not compile to anything faster than the interpreted path; we minimise it by lowering "structural" results to packed forms where possible.
- **The compile itself takes time**, which is why `ParserCompile[grammar]` is a separate step from `Parse[grammar, input]`. For one-shot parses of small inputs, the interpreted path wins; the compiled path is for grammars used repeatedly or on long inputs.

A realistic expectation is 3-10× over the interpreted path on lexer-heavy grammars (LaTeX math, JSON, TPTP), and a smaller factor on grammars dominated by AST construction.

---

## Part 4 - Worked targets

The choice of primitives above is motivated by two concrete targets. This section walks through how each maps onto the algebra, with enough detail to validate the design.

### Target A - LaTeX math

LaTeX math has been the breaking point for `MarkdownToNotebook`'s built-in path repeatedly. `ImportString[..., "TeX"]` drops styling commands (`\mathbb{R}` becomes a plain `R`), `ToExpression[..., TeXForm]` parses some structure but fails on common constructs like `dx` in integrals, and neither composes with the kind of custom-macro extension a real user wants.

A `WolframParser` LaTeX math grammar (sketched at the combinator level):

```wl
math = expr;

expr = term ~ Many[("+" | "-") ~ term]
         :> (Function[{first, rest}, FoldOperator[first, rest]]);

term = factor ~ Many[("*" | "/") ~ factor]
         :> FoldOperator;

factor = group | command | atom;

group = Between["{", expr, "}"];

command = "\\" ~ Some[LetterCharacter] ~ Optional[bracketedArg] ~ Many[bracedArg]
            :> buildCommand;

bracedArg = Between["{", expr, "}"];
bracketedArg = Between["[", expr, "]"];

atom = number | identifier | bigOperator;

bigOperator = ("\\sum" | "\\int" | "\\prod") ~
              Optional["_" ~ group] ~ Optional["^" ~ group)
              :> buildBigOperator;
```

The `buildCommand` action handles the font-style commands (`\mathbb`, `\mathcal`, `\mathfrak`, `\boldsymbol`) by looking up the macro name and producing the correct `StyleBox` or named character (`\[DoubleStruckCapitalR]` for `\mathbb{R}`, etc.) - the exact preprocessing pass that, in the absence of a real parser, would have to live as a `StringReplace` table in `MarkdownToNotebook` itself.

What this grammar gets right that the current built-ins don't:

- **Nested braces** are handled by the recursive `group = Between["{", expr, "}"]` rule. `StringExpression` cannot express this.
- **Optional arguments** (`\sqrt[3]{x}`) compose naturally via `Optional[bracketedArg]`.
- **`\begin{env}…\end{env}`** is a separate production that captures the environment name and re-enters the grammar with mode-specific rules (math mode in a `\begin{matrix}`, *etc.*).
- **Custom-macro extension** is a matter of `Append[command-action-lookup, "\\mycmd" -> Function[args, ...]]` - no parser regeneration.

### Target B - TPTP

[TPTP](https://www.tptp.org/) (Thousands of Problems for Theorem Provers) is a family of formats for automated theorem proving: FOF (first-order formulas), CNF (clause normal form), TFF (typed FOF), THF (higher-order). A TPTP problem is a sequence of *annotated formulas*:

```
fof(commutativity_of_plus, axiom,
    ! [X, Y]: (plus(X, Y) = plus(Y, X))).

fof(some_property, conjecture,
    ? [X]: (greater(X, zero) & even(X))).
```

The grammar is BNF, publicly specified, and of moderate size (~100 productions for full TFF/THF). The combinators that matter:

- **`SepBy[formula, comma]`** for argument lists
- **`ChainLeft[unitFormula, binaryOp]`** for operator-precedence parsing of `&`, `|`, `=>`, `<=>`
- **`Try[...]`** for the LR-conflict-like cases (FOF vs TFF can look identical at the prefix)
- **`Between["(", expr, ")"]`** everywhere

A skeleton:

```wl
tptpFile = formula..;

formula = ("fof" | "cnf" | "tff" | "thf") ~
          Between["(", formulaBody, ")"] ~
          ".";

formulaBody = name ~ "," ~ role ~ "," ~ logicFormula;

logicFormula = quantified | binary | unit;

quantified = ("!" | "?") ~ varList ~ ":" ~ logicFormula;

binary = unit ~ ("&" | "|" | "=>" | "<=>") ~ logicFormula;

unit = atom | "(" ~ logicFormula ~ ")" | "~" ~ unit;

atom = predicate ~ Optional[Between["(", SepBy[term, ","], ")"]];

term = variable | functionApp | constant;
```

The grammar is straightforward parser-combinator material; the productions above lower to FunctionCompile-able forms by the standard pipeline. The motivation for including TPTP as a target is dual:

1. It validates the *scale* of the grammar - if the combinator algebra cannot express a 100-production grammar cleanly, the algebra is wrong.
2. It validates the *integration* story - the parser returns a structured AST that can be transformed (skolemisation, clausification) by other WL code, which is the use case that drives a lot of automated-reasoning work in the Wolfram ecosystem.

### What the targets imply about the algebra

The two grammars motivate every primitive in the combinator table. `Lookahead` and `NotFollowedBy` come from TPTP's FOF/TFF prefix disambiguation; `Try` from the same. `Between`, `SepBy`, `Choice` are LaTeX-driven. `Many` and `Some` are universal. The fact that both grammars are *recursive* (LaTeX through `group`, TPTP through `logicFormula`) is what makes the mutually-recursive FunctionCompile lowering load-bearing rather than incidental.

---

## Part 5 - Open questions

A list of things explicitly *not* decided in v0.1:

1. **Operator-precedence parsing.** Do we ship a dedicated `OperatorTable[{prec, assoc, op}, ...]` combinator (like Parsec's `buildExpressionParser`), or do users hand-write the precedence cascade? The TPTP and LaTeX grammars both want this; the question is the syntax.
2. **Streaming input.** The current design assumes the input is in memory (string or list). Streaming (parse-while-reading) is an open question - relevant for large TPTP corpora and for editor integration.
3. **Error recovery.** A parse failure currently aborts the whole parse. Some grammars (editors, IDE tools) want to continue past a syntax error and collect multiple errors. This is a separate research problem (panic-mode recovery, FOLLOW-set recovery) and is deferred.
4. **Left-recursion.** Naive PEG / combinator parsers cannot directly express left-recursive rules (`expr = expr "+" term | term` loops forever). The TPTP and LaTeX grammars above all work around this via `Many` / `ChainLeft`, which is the standard idiom. Whether to additionally support direct left-recursion (Warth's algorithm, GLR backend) is open.
5. **Packrat memoisation on by default.** Currently `Memoize -> False` is the default. Real benchmarks against a corpus of grammars will tell us whether to flip this.
6. **Source-position carrying in `Token`.** The token type is sketched as `Token[type, value, pos]`. The question is what `pos` is - a single character offset (cheap, easy to compile) or a `{line, col}` pair (better diagnostics, more bookkeeping). The lean answer is "character offset in the input, with line/col computed on demand for error messages."

Each of these will be answered by implementation experience against the targets above. The job of the v0.1 release is to ship the survey and this design, get the structure into the working directory, and start filling in the combinator primitives one at a time.

## What ships in v0.1

- The two tech notes ([ParserLandscape](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) and this one).
- The PacletInfo / ResourceDefinition scaffolding under context `` Wolfram`Parser` ``.
- A placeholder kernel.

What lands next (v0.2):

- `Parser[...]` head and the primitive combinators (`Sequence`, `Choice`, `Many`, `Some`, `Optional`, `Between`, `Lookahead`, `NotFollowedBy`, `Try`).
- An interpretive `Parse[parser, input]` that runs the combinators directly.
- A first pass at the `GrammarRules` → `Parser` lowering.

After that (v0.3+): the FunctionCompile codegen, the LaTeX math grammar, the TPTP grammar, and benchmarks against `AntonAntonov/FunctionalParsers` to see where the compiled path actually wins.

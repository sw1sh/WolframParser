---
Template: TechNote
Name: ParserLandscape
Title: The Parser Landscape - a Survey of What Exists Today
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/ParserLandscape
Keywords: [parser, parsing, grammar, combinator, EBNF, parsec, survey, comparison]
RelatedGuides: [WolframParser]
---

## Why this note exists

Parsing is a long-solved problem - in *most* languages. Haskell has Parsec. Rust has nom. Python has pyparsing. Lua has LPeg. Even modest scripting languages tend to ship at least one composable parser library that handles strings, tokens, and structured trees uniformly.

The Wolfram Language is an unusual exception. It has many partial answers - `StringExpression`, `RegularExpression`, `Interpreter`, `GrammarRules`, `CodeParser`, `XMLObject` - but no single library that lets a user build a custom parser of arbitrary complexity, *locally*, with the kind of compositional ergonomics Parsec made famous. This note surveys what's actually available, in order to be honest about *why* `WolframParser` is being written: not because nothing exists, but because what exists is fragmented along axes that don't compose.

The survey is structured into three parts:

1. **Wolfram built-ins** - what ships with the kernel.
2. **Community libraries** - what's on the Paclet Repository / GitHub.
3. **Outside Wolfram** - the design heritage `WolframParser` borrows from.

Each section says what the tool does well, where it stops, and how `WolframParser` aims to fit alongside it.

---

## Part 1 - Wolfram built-ins

### `StringExpression` and the string-pattern atoms

The native pattern language for strings - `StringExpression` plus the character-class atoms ([LetterCharacter](), [DigitCharacter](), [WhitespaceCharacter](), [WordCharacter](), [HexadecimalCharacter](), [PunctuationCharacter](), [CharacterRange]()) that slot into it. Composable in the sense that you can `~~` two patterns together, name parts, and use named character classes - `LetterCharacter`, `DigitCharacter`, `WhitespaceCharacter`, `WordBoundary`, etc. It plugs directly into [StringCases](), [StringSplit](), [StringReplace](), [StringMatchQ]() and the rest of the string toolkit.

```wl
StringCases["v3.14 v2.71", "v" ~~ x : NumberString :> x]
```

<!-- => {"3.14", "2.71"} -->

**What it does well.** Concise, fast (C-backed), integrates with everything in the string namespace, expressive for *regular* grammars. Captures via `x : pat` are clean. The `Shortest` / `Longest` modifiers handle backtracking control.

**Where it stops.** `StringExpression` is fundamentally a regex - it cannot express recursion or balanced brackets. A `Shortest["(" ~~ ___ ~~ ")"]` will happily match `(a(b)`:

```wl
StringCases["(a(b)c)", Shortest["(" ~~ ___ ~~ ")"]]
```

<!-- => {"(a(b)"} -->

There is also no native way to attach *actions* to subpatterns and assemble a structured result, other than collecting the substring captures and post-processing them yourself. That works for simple cases and creaks for grammars with more than a handful of productions.

### `RegularExpression`

A thin PCRE wrapper. Useful when you have a regex from somewhere else and need to drop it in unchanged. The same limitations as `StringExpression` apply, plus the usual regex unreadability:

```wl
StringCases["v3.14", RegularExpression["v(\\d+\\.\\d+)"] -> "$1"]
```

<!-- => {"3.14"} -->

### `Interpreter`

A high-level, type-driven parser. `Interpreter[type]` returns a function that tries to *interpret* an input string as something of the given type. Built-in types are extensive - numbers, dates, colors, locations, units, even free-form English noun phrases:

```wl
Interpreter["Color"]["sky blue"]
```

<!-- => RGBColor[0.529, 0.808, 0.922] -->

`Restricted[type, constraints]` narrows the interpretation:

```wl
Interpreter[Restricted["Integer", {0, 100}]]["50"]
```

<!-- => 50 -->

**What it does well.** Outstanding for "extract a typed value from text" tasks where the type is one of the built-in entity / quantity / data interpretations. Often the right answer for input forms, configuration parsing, and natural-language commands.

**Where it stops.** Not user-extensible in any deep sense - the type system is closed. You can compose interpreters at the *list* level (`Interpreter[{type1, type2}]`) but not write your own type with custom production rules. Failure modes are opaque - you get a `Failure[...]` object with limited diagnostic information.

### `GrammarRules`, `GrammarApply`, `GrammarToken`

The cleanest WL-native API for higher-level grammars. A grammar is a list of rules with slot syntax, and `GrammarApply` walks the input against the rules to extract structured matches:

```wl
GrammarApply[
    GrammarRules[{"the weather in <who>" -> who}],
    "the weather in NYC"
]
```

The catch is right there in the documentation:

> `GrammarRules[rules]` represents grammar rules **to be deployed to a cloud object**.

Run the example above locally and you get:

> `GrammarApply::arg1: The first argument ... is expected to be a cloud object or list of cloud objects.`

So `GrammarRules` is the most ergonomic WL grammar surface, and it is also the one with the hardest dependency: you can use it in production *only* if your workflow tolerates round-tripping through a CloudObject. For a paclet that wants to embed a grammar in a piece of local computation - parsing a config file, lexing a DSL, post-processing CodeParser output - this is a non-starter.

The *design* of `GrammarRules`, however, is the right shape. `WolframParser` borrows the slot-rule notation directly, and runs it locally.

### `CodeParser`

A first-party paclet (`CodeParser\``) that tokenises and parses Wolfram Language source code into a typed AST. The implementation is in C with a thin WL surface, so it is *very* fast and very precise about source positions:

```wl
Needs["CodeParser`"];
CodeParse["f[x_] := x + 1"]
```

returns a `ContainerNode[String, {CallNode[LeafNode[Symbol, "SetDelayed", ...], ...]}]` tree with per-leaf `Source` positions for every token.

**What it does well.** The gold standard for WL source - used by the front-end, the linter, the formatter, and a small ecosystem of paclets. The AST is well-typed and easy to walk.

**Where it stops.** It parses *one* language - Wolfram. There is no way to retarget it to parse JSON, TOML, a custom DSL, or even a near-relative like a `.wlt` test file. The C backend means you cannot add productions; you can only consume what the parser emits.

`WolframParser` does not try to compete with `CodeParser` for WL source - on the contrary, it interoperates: you can feed a `CodeParser` AST into a `WolframParser` grammar that walks the tree and extracts higher-level structure (e.g. "find all `Module` definitions with a particular shape"). That dual-mode of "string parser" + "expression-tree parser" is what the *token-oriented* design enables.

### `ResourceFunction["CodeStructure"]` - the `CodeAnalysis` paclet

The `CodeParser` story, one language over: a first-party parser for **C/C++** source, delivered through the Function Repository. `ResourceFunction["CodeStructure"]` is itself only a *loader shim* - its entire definition is three lines that install and load the `CodeAnalysis` paclet on first use, then hand every call off to `CodeAnalysis`CodeStructure`:

```wl
CodeStructure[args___]  := (getCodeAnalysis[]; Symbol["CodeAnalysis`CodeStructure"][args])
getCodeAnalysis[]       := getCodeAnalysis[] = (installCodeAnalysis[]; Block[{$ContextPath}, Needs["CodeAnalysis`"]])
installCodeAnalysis[]   := PacletInstall["CodeAnalysis"] /; PacletFind["CodeAnalysis"] === {}
```

The real engine is the `CodeAnalysis` paclet (v0.9.6 at writing), which parses C by **shelling out to Clang** and post-processing its AST dump into a Wolfram expression tree. The options give the backend away: `ClangBinariesDirectory`, `CommandLineArguments`, `BinaryLocation`, `ShellProlog` (plus the `$BuildError` / `$ExtractError` / `$OptError` channels for the three external stages).

```wl
ResourceFunction["CodeStructure"]["int main(void){ return 41+1; }"]
```

<!-- => CodeElement[{CodeElement[{CodeElementToken["int","Keyword","SourceRange"->{0,3}], CodeElementToken["main","Identifier",...], ... CodeElement[{...},"ReturnStmt",...]}, "FunctionDecl","SourceRange"->{0,30}]}, "TranslationUnit","SourceRange"->{0,30}] -->

The tree mirrors Clang's AST node names - `TranslationUnit`, `FunctionDecl`, `CompoundStmt`, `ReturnStmt`, `BinaryOperator`, `IntegerLiteral` - with a byte `SourceRange` on every node. Internal nodes are `CodeElement[{children}, type, opts]`; leaves are `CodeElementToken[text, class, opts]` with `class` one of `"Keyword"`, `"Identifier"`, `"Punctuation"`, `"Literal"`, etc. A second argument picks an alternative representation - `"SyntaxTree"`, `"SyntaxAnnotation"`, `"SourceAnnotation"`, `"TokenAnnotation"`, `"CallGraph"`, `"FileCallGraph"` - and the companion `CodeCases` walks a `CodeElement` tree the way `Cases` walks any expression.

**What it does well.** A precise, source-accurate C/C++ AST with zero Clang plumbing on your part - the paclet handles the install, the compiler invocation, and the AST-dump parsing. The right tool for "find every function that calls `malloc`", call-graph extraction, and source-to-source tooling over C.

**Where it stops.** It parses *C* and only C, through an external Clang it shells out to: you cannot retarget it, add productions, or run it on a machine with no Clang on the path. Like `CodeParser`, it is an analyzer for one fixed language rather than a construction kit - and, as with `CodeParser`, the part that matters to this survey is the structured-AST *output*. A `CodeElement` tree is exactly what `WolframParser`'s expression-tree input mode is built to walk: the same combinators that lex a string can match `CodeElement[_, "FunctionDecl", _]` nodes to pull out higher-level structure without re-parsing the C.

### `XMLObject`, `JSON`, `ImportString`

`ImportString[text, "XML"]`, `ImportString[text, "JSON"]`, and friends cover the cases where someone else has already done the parsing work for a well-known format. They are not really parsers in the construction sense - they are *importers*. Useful when applicable, irrelevant when you have a format that doesn't already have an importer.

---

## Part 2 - Community libraries

### `AntonAntonov/FunctionalParsers`

The most complete pure-WL parser combinator library on the Paclet Repository. Anton Antonov has been working on it for years; the API is a faithful Wolfram port of the Haskell `Parsec` design.

```wl
Needs["AntonAntonov`FunctionalParsers`"];
ebnf = "<expr> = <num> , { \"+\" , <num> } ; <num> = \"0\" | \"1\" | \"2\" ;";
GenerateParsersFromEBNF[ParseToEBNFTokens[ebnf]];
ParseShortest[pEXPR][ToTokens["1 + 2 + 0"]]
```

<!-- => {{{}, {"1", {{"+", "2"}, {"+", "0"}}}}} -->

The library provides:

- **Primitive combinators**: `ParseSymbol`, `ParseToken`, `ParsePredicate`, `ParseEpsilon`, `ParseFail`.
- **Composition**: `ParseSequentialComposition`, `ParseAlternativeComposition`, `ParseSequentialCompositionPickLeft`, `ParseSequentialCompositionPickRight`.
- **Repetition**: `ParseMany`, `ParseMany1`, `ParseSome`, `ParseListOf`.
- **Modifiers**: `ParseOption`, `ParseOption1`, `ParseShortest`, `ParseModify`, `ParseApply`.
- **Bracketing**: `ParseBracketed`, `ParseParenthesized`, `ParseCurlyBracketed`.
- **Chaining**: `ParseChainLeft`, `ParseChainRight`, `ParseChain1Left`.
- **An EBNF front end**: `ParseToEBNFTokens`, `GenerateParsersFromEBNF`, `EBNF*` rule heads.

**What it does well.** Genuinely complete - every combinator a Parsec user would expect is there. The EBNF generator means you can write a grammar declaratively and get a working parser without hand-wiring combinators. It is pure WL and runs locally. Several large projects (especially Anton's own NLP-oriented work) use it in production.

**Where it stops.**

- **Naming overhead.** `ParseSequentialCompositionPickRight` is descriptive and unambiguous, but a parser line full of `ParseSequentialComposition[ParseSymbol["("], ParseSequentialCompositionPickLeft[expr, ParseSymbol[")"]]]` is dense to read. Parsec uses `<|>`, `<*>`, `<$>` as binary operators; nom uses `tuple((...))` and macros; pyparsing uses `+` / `|` / `>>`. A short, *combinable* operator vocabulary is part of the ergonomics story and is not present here.
- **Speed.** Pure interpretation - every combinator allocates closures and walks lists. Acceptable for grammar-sized inputs (kilobytes), painful for megabyte-scale inputs. There is no compilation path.
- **Token shape.** The library always tokenises first via `ToTokens`. Operating directly on a string (without explicit tokenisation) or on a list of Wolfram expressions (e.g. a `CodeParser` AST) is not idiomatic.
- **Diagnostics.** Failure is a missing match - you get `{}` back. There is no positional error message of the form "expected `)` at line 3 col 12, saw `]`".

`WolframParser` aims to share the combinator vocabulary, but add an operator surface, a token-or-string-or-expression-uniform input model, and structured parse-failure diagnostics.

### Other paclet-repository entries

A handful of related entries on the Paclet Repository - `WolframLanguageExtras`, `JSONParser`, `XMLConverter`, *etc.* - target specific formats rather than the general-purpose niche. None compete with `FunctionalParsers` for the role of "general parser combinator library."

---

## Part 3 - Outside Wolfram (design heritage)

This is the literature `WolframParser` reads to figure out what *good* looks like.

### Parsec (Haskell)

Daan Leijen's `Parsec` (2001) is the reference design. Two key ideas have spread to nearly every modern parser library:

1. A parser is a *function* (or monadic value) that consumes input and returns either a result with the remainder, or a failure with diagnostic information.
2. Bigger parsers are built from smaller ones with a tiny vocabulary of *combinators*: alternation (`<|>`), sequence (`<*>` / `>>`), zero-or-more (`many`), one-or-more (`many1`), optional (`optional`), backtracking control (`try`).

Parsec's brilliance is the *applicative* shorthand: most useful parsers don't need full monadic power; they look like

```haskell
expr = (+) <$> term <* char '+' <*> expr
```

which reads as "parse a `term`, then a literal `+`, then an `expr`, and combine the two results with `(+)`." A parser library that does not provide *something* equivalent to that is much harder to use than one that does.

**Descendants.** `megaparsec` (better errors), `attoparsec` (faster, less ambitious errors), `nom` (Rust), `pyparsing` (Python), `parsimmon` (JavaScript), `Combine` (Swift). The design has held up for two decades.

### PEG - Parsing Expression Grammars (Ford, 2004)

Bryan Ford's PEG formalism is the other big design tradition. A PEG looks similar to a context-free grammar but with two key differences:

1. The **`/` choice operator is ordered**. Once an alternative matches, the others are not tried. This eliminates the ambiguity that plagues general CFG parsers.
2. Combinators include **`&` (positive lookahead)** and **`!` (negative lookahead)**, which are not expressible in pure CFGs.

The combination is expressive enough for most real-world languages, parses in linear time with packrat memoisation, and gives unambiguous parse trees by construction. Implementations: **LPeg** (Lua, by Roberto Ierusalimschy - widely cited as one of the best parser libraries in any language), **pest** (Rust), **PEG.js** (JavaScript).

`WolframParser` adopts the ordered-choice / lookahead vocabulary from PEG - even if the primary surface is Parsec-style combinators, having `&p` and `!p` available is a meaningful expressivity gain.

### ANTLR / LALR generators

The "generate code from a `.g4` file" school. ANTLR4 (LL(*)), Bison/Yacc (LALR(1)), Lark (Earley / LALR(1) toggle). Strengths: handle huge grammars, well-understood theory, separate compilation step lets the generator do expensive analyses. Weaknesses: heavyweight tooling, external code-generation step, the grammar lives in its own file in its own little language.

These are excellent for compilers and SQL parsers; they are massively over-engineered for the "I need to parse this small DSL" use case that drives most parser library work. `WolframParser` does not try to be ANTLR.

### Earley / GLR / GLL

For the genuinely-ambiguous case (natural language, scientific notation, legacy formats), general parsers that handle the full class of context-free grammars are necessary. **Marpa** (a remarkable Earley implementation by Jeffrey Kegler) handles arbitrary CFGs in cubic time and most "real" CFGs in linear time. `tree-sitter` (a GLR variant) is what powers incremental editor parsing.

These are *not* in the v0.1 design scope for `WolframParser`. Combinator parsing covers the 95% case; adding a general CFG backend later is an open question, not a v0.1 goal.

---

## Cross-reference table

| Capability                             | `StringExpression` | `Interpreter` | `GrammarRules` | `CodeParser` | `FunctionalParsers` | `WolframParser` (target) |
|----------------------------------------|:------------------:|:-------------:|:--------------:|:------------:|:-------------------:|:------------------------:|
| Regex / regular grammars               | ✓                  |               |                |              | ✓                   | ✓                        |
| Recursive / context-free grammars      |                    |               | ✓              | (WL only)    | ✓                   | ✓                        |
| Ordered choice (PEG)                   |                    |               |                |              | partial             | ✓                        |
| Lookahead (`&` / `!`)                  |                    |               |                |              |                     | ✓                        |
| User-defined types / actions           | weak               |               | ✓              |              | ✓                   | ✓                        |
| Declarative EBNF / rule grammar        |                    |               | ✓              |              | ✓                   | ✓                        |
| Combinator (Parsec-style) entry point  |                    |               |                |              | ✓                   | ✓                        |
| Operator syntax (`p1 \| p2`, `p..`)    | partial            |               |                |              |                     | ✓                        |
| Runs locally (no cloud)                | ✓                  | ✓             | ✗              | ✓            | ✓                   | ✓                        |
| Token + string + expression input      | string             | string        | string         | string→tree  | string→tokens       | all three                |
| Structured parse errors with positions |                    | weak          |                | ✓            |                     | ✓                        |
| Compilation / hot-path optimisation    | C-backed           | C-backed      | (cloud)        | C-backed     |                     | partial (planned)        |

---

## The shape of WolframParser

The survey above defines the niche by exclusion. Concretely, the paclet aims to provide:

1. **A combinator core** in the Parsec / FunctionalParsers tradition, with constructors named in Anton's `Parse*` style (`ParseSequence`, `ParseChoice`, `ParseMany`, `ParseSome`, `ParseOptional`, `ParseBetween`, `ParseSepBy`, `ParseChainLeft`, `ParseChainRight`, `ParseLookahead`, `ParseNotFollowedBy`, `ParseTry`, `ParseAction`). Each returns a single computable `ParserCombinator` head that formats as a [SummaryBox]() and carries operator [UpValues](): `p1 | p2` for choice ([Alternatives]()), `p1 ~~ p2` for sequence ([StringExpression](), fired only when both sides are `ParserCombinator` instances), `p..` for one-or-more ([Repeated]()), `p...` for zero-or-more ([RepeatedNull]()). The wrapper also carries a [SubValues]() rule: `parser[input]` is `Parse[parser, input]`.

2. **A declarative `GrammarRules`-compatible entry point.** The same `GrammarRules[{"slot syntax" -> action}]` declaration that the built-in path ships off to [CloudDeploy]() is accepted here and compiled to a local parser via [FunctionCompile](). Anything the cloud path accepts, the local path accepts; only the deployment changes.

3. **A uniform input model**: a parser runs on a string (chars as tokens), on a list of tagged tokens (`Token[type, value, pos]`), or on a list of Wolfram expressions (so the same combinators that lex a string can walk a [CodeParser]() AST, an XML tree, or any other expression).

4. **Structured parse-failure diagnostics**: a failure carries the position, the rule that was being matched, and the set of expected tokens. `ExplainParseError` renders it as a "expected X at line L col C, saw Y" message - the bare minimum to make a parser library usable for end users, conspicuously missing from `FunctionalParsers`.

5. **A `FunctionCompile`-based compilation path for hot loops**: simple parsers (terminals, character classes, regex-equivalent shapes) fall through to `StringExpression` under the hood; richer grammars are lowered to a typed first-order representation and shipped through [FunctionCompile]() for LLVM codegen. No C dependency.

What the paclet is *not* trying to be:
- a `CodeParser` replacement (we interoperate with it instead)
- an ANTLR (the generator-based heavyweight school is a different ecosystem)
- a general CFG parser (Earley / GLR / GLL backends are out of scope for v0.1)
- a tokeniser for any specific format (those belong in companion paclets that *use* this library to define their lexers)

The detailed API design, the parser algebra, and the FunctionCompile lowering live in [DesignAndCompilationStrategy](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy). This note's job is to be honest about what already exists, so the design decisions there can be read against the alternatives instead of in a vacuum.

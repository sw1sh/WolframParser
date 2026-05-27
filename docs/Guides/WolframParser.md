---
Template: Guide
Name: WolframParser
Title: Parsing in the Wolfram Language
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/guide/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - Parse* combinators around a single ParserCombinator wrapper, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution.
Keywords: [parser, parsing, grammar, combinator, ParserCombinator, GrammarRules, FunctionCompile, LaTeX, TPTP, DSL]
RelatedGuides: [StringManipulation]
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)"]
---

## Abstract

The Wolfram Language has rich *piecewise* support for parsing: [StringExpression]() and [RegularExpression]() for regex-style patterns, [Interpreter]() for type-driven extraction from text, [CodeParser]() for parsing Wolfram code itself, and [GrammarRules]() for higher-level rule-based grammars (cloud-only). What it does not have is a single, general, *local* parser library that lets you compose your own grammar at any scale - the niche occupied by Parsec in Haskell, nom in Rust, or pyparsing in Python.

This paclet (context `Wolfram`Parser` `) fills that niche. The strategy is twofold:

- **Reuse the [GrammarRules]() declarative DSL.** The same `"the weather in <city>" -> city` slot syntax that the built-in path ships to [CloudDeploy]() is compiled here to a local parser via [FunctionCompile](). Same declaration, different deployment.
- **Expose a `Parse*` combinator core** for grammars that don't fit the declarative shape, all funneling into a single computable [ParserCombinator]() head with [UpValues]() for the natural WL operator overloads and a [SubValues]() rule that makes `parser[input]` work directly.

The v0.1 release is *design + scaffold*: two tech notes carry the design, the library code lands incrementally against them.

## Tech notes (read these first)

- [The Parser Landscape: a survey of existing tech](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) — what's already in WL and outside, where the gaps are
- [Design and Compilation Strategy](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy) — `ParserCombinator` wrapper, `Parse*` constructors, operator UpValues, FunctionCompile lowering, worked LaTeX-math and TPTP targets

## Functions (intended shape)

### Run a parser
- `Parse[parser, input]` apply a parser to an input (interpretive for an uncompiled `ParserCombinator`, the cached compiled function for a compiled one)
- `parser[input]` equivalent SubValue form - the wrapper carries the rule
- `ParserCompile[parser]` materialise the compiled form: attaches a `CompiledCodeFunction` under the `"Code"` key of the wrapper's options

### The wrapper
- `ParserCombinator[type, args, opts]` the single computable head every constructor returns; opaque to user code, formats as a summary box, carries the operator UpValues and the call-as-function SubValue

### Parse* constructors (Anton-style naming, each returns a `ParserCombinator`)

#### Terminals
- `ParseLiteral[s]` match an exact string / token
- `ParseCharacter[pat]` match a single character against a character-class atom ([LetterCharacter](), [DigitCharacter](), [WordCharacter](), [WhitespaceCharacter](), ...), a [CharacterRange]()`[a, b]`, an [Alternatives]() of these, or a literal one-character [String]()
- `ParseToken[type]` match a tagged `Token[type, _, _]`
- `ParseSucceed[val]` always succeed with `val` (consume nothing)
- `ParseFail[msg]` always fail with `msg`

#### Composition
- `ParseSequence[p1, p2, ...]` each in order
- `ParseChoice[p1, p2, ...]` first that matches (PEG-ordered)
- `ParseBetween[open, p, close]` open, then p, then close; result is p's
- `ParseSepBy[p, sep]` zero or more `p` separated by `sep`
- `ParseSepBy1[p, sep]` one or more `p` separated by `sep`
- `ParseChainLeft[p, op]` left-associative operator chain
- `ParseChainRight[p, op]` right-associative operator chain

#### Repetition
- `ParseMany[p]` zero or more
- `ParseSome[p]` one or more
- `ParseOptional[p]` zero or one

#### Lookahead / backtracking
- `ParseLookahead[p]` succeed iff `p` would match, consume nothing
- `ParseNotFollowedBy[p]` succeed iff `p` would not match, consume nothing
- `ParseTry[p]` backtrack on failure even after consuming

#### Capture / action
- `ParseCapture[name, p]` tag `p`'s result with `name` (for slot lowering)
- `ParseAction[p, f]` apply `f` to `p`'s result

#### Recursion
- `ParseRecursive[name, body]` a named recursive parser body

### Operator overloads on `ParserCombinator`

| Syntax        | Lowers to                       | Combinator       |
|---------------|---------------------------------|------------------|
| `p1 \| p2`    | `Alternatives[p1, p2]`          | `ParseChoice`    |
| `p1 ~~ p2`    | `StringExpression[p1, p2]`      | `ParseSequence`  |
| `p..`         | `Repeated[p]`                   | `ParseSome`      |
| `p...`        | `RepeatedNull[p]`               | `ParseMany`      |
| `Optional[p]` | `Optional[p]`                   | `ParseOptional`  |

The `~~` UpValue *only* fires when both sides are `ParserCombinator` instances; plain `"foo" ~~ "bar"` between strings keeps its built-in [StringExpression]() meaning. `~` is *not* overloaded - it stays as WL's infix function notation `a~f~b == f[a, b]`.

### Diagnostics
- `ParseError` structured error with position, rule, expected tokens
- `ExplainParseError[err]` "expected X at line L col C, saw Y" rendering

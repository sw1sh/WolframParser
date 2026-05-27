---
Template: Guide
Name: WolframParser
Title: Parsing in the Wolfram Language
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/guide/WolframParser
Description: A general, fast, composable parser library for the Wolfram Language - Parse* combinators around a single ParserCombinator wrapper, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution, a working LaTeX math parser at 100% KaTeX corpus coverage.
Keywords: [parser, parsing, grammar, combinator, ParserCombinator, GrammarRules, FunctionCompile, LaTeX, KaTeX, TPTP, DSL]
RelatedGuides: [StringManipulation]
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)"]
---

## Abstract

The Wolfram Language has rich *piecewise* support for parsing: [StringExpression]() and [RegularExpression]() for regex-style patterns, [Interpreter]() for type-driven extraction from text, [CodeParser]() for parsing Wolfram code itself, and [GrammarRules]() for higher-level rule-based grammars (cloud-only). What it does not have is a single, general, *local* parser library that lets you compose your own grammar at any scale - the niche occupied by Parsec in Haskell, nom in Rust, or pyparsing in Python.

This paclet (context `Wolfram`Parser` `) fills that niche on three fronts:

- **A `Parse*` combinator core** around a single computable [ParserCombinator]() head, with [UpValues]() for the natural WL operator overloads (`p1 | p2`, `p1 ~~ p2`, `p..`, `p...`, `Optional[p]`) and a [SubValues]() rule that makes `parser[input]` work directly.
- **[GrammarRules]() declarative compatibility.** `Parse[GrammarRules[{"the weather in <city>" -> city}], "the weather in NYC"]` lowers each rule to a `ParserCombinator` and runs it locally, no [CloudDeploy](). See [Parsing GrammarRules Locally](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) for the supported subset.
- **A LaTeX math parser** ([`Wolfram\`Parser\`LaTeX\``](paclet:Wolfram/WolframParser/ref/LaTeXMathParse)) that parses 126/126 of [KaTeX's own screenshotter corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml) into Wolfram boxes (`FractionBox`, `SubsuperscriptBox`, `GridBox`, ...) - turn `$\frac{a}{b}$` markdown into a renderable notebook cell.

## Tech notes (read these first)

- [The Parser Landscape: a survey of existing tech](paclet:Wolfram/WolframParser/tutorial/ParserLandscape) - what's already in WL and outside, where the gaps are
- [Design and Compilation Strategy](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy) - `ParserCombinator` wrapper, `Parse*` constructors, operator UpValues, FunctionCompile lowering, worked LaTeX-math and TPTP targets
- [Implementing the LaTeX Math Parser](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) - how the doc-math layer handles real-world TeX (`\big*` stripping, `\left/\right` mismatched delim pairs, matrix env aliases, the row variants topRow / cellRow / outerRow)
- [Parsing GrammarRules Locally](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) - the supported subset of [GrammarRules]() and how to drop to the combinator core for the rest
- [Parsing BNF Grammars](paclet:Wolfram/WolframParser/tutorial/ParsingBNFGrammars) - the `Wolfram\`Parser\`EBNF\`` sub-context reads a BNF grammar (verified on the 354-rule TPTP SyntaxBNF) and lowers it to a `ParserCombinator` map; bootstraps a TPTP recognizer from the published grammar

## Functions

### Run a parser
- [Parse]() apply a parser to an input - returns the parser's value or a `ParseError`
- [ParsePartial]() return `{result, leftover-suffix}` instead of requiring whole-input match
- `parser[input]` SubValue form, equivalent to `Parse[parser, input]`
- [ParserCompile]() materialise the [FunctionCompile]()d form - attaches a `CompiledCodeFunction` under the `"Code"` key of the wrapper's options

### The wrapper
- [ParserCombinator]() the single computable head every constructor returns; opaque to user code, formats as a summary box, carries the operator UpValues and the call-as-function SubValue
- [ParserCombinatorQ]() test whether an expression is a `ParserCombinator`

### Parse* constructors (each returns a `ParserCombinator`)

#### Terminals
- [ParseLiteral]() match an exact string
- [ParseCharacter]() match a single character against a character-class atom ([LetterCharacter](), [DigitCharacter](), [WordCharacter](), [WhitespaceCharacter](), ...), a [CharacterRange]()`[a, b]`, an [Alternatives]() of these, or a literal one-character [String]()
- [ParseSucceed]() always succeed with the given value (consume nothing)
- [ParseFail]() always fail with the given message

#### Composition
- [ParseSequence]() each in order
- [ParseChoice]() first that matches (PEG-ordered)
- [ParseBetween]() open, then p, then close; result is p's
- [ParseSepBy]() zero or more `p` separated by `sep`
- [ParseSepBy1]() one or more `p` separated by `sep`
- [ParseChainLeft]() left-associative operator chain
- [ParseChainRight]() right-associative operator chain

#### Repetition
- [ParseMany]() zero or more
- [ParseSome]() one or more
- [ParseOptional]() zero or one

#### Lookahead / backtracking
- [ParseLookahead]() succeed iff `p` would match, consume nothing
- [ParseNotFollowedBy]() succeed iff `p` would not match, consume nothing
- [ParseTry]() backtrack on failure even after consuming

#### Action / recursion
- [ParseAction]() apply a function to a parser's result
- [ParseRecursive]() defer the lookup of a parser definition until parse time (the recursion knot)

### LaTeX math sub-context (`Wolfram\`Parser\`LaTeX\``)

- `LaTeXMathParse[s]` parse a LaTeX math expression into a Wolfram `Box`. Returns one of `FractionBox`, `SubsuperscriptBox`, `RadicalBox`, `GridBox`, `RowBox`, `StyleBox`, ..., or `ParseError`. 100% coverage of KaTeX's inline screenshotter test corpus; see [Implementing the LaTeX Math Parser](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation).

### EBNF sub-context (`Wolfram\`Parser\`EBNF\``)

- `EBNFParse[source]` / `EBNFParse[File[path]]` read a BNF grammar in the TPTP / Backus-Naur style (`<name> ::= alt1 | alt2 | ...`) and return an `Association[name -> ParserCombinator]`. The BNF parser itself is built out of `Parse*` combinators (no regex [StringCases]()); the lowering ties non-terminal references via `ParseRecursive` symbols so mutually recursive rules wake up together. Verified against the [TPTPWorld SyntaxBNF v9.2.1.4](https://github.com/TPTPWorld/SyntaxBNF/blob/master/SyntaxBNF-v9.2.1.4) (354 rules parse). See [Parsing BNF Grammars](paclet:Wolfram/WolframParser/tutorial/ParsingBNFGrammars).
- `EBNFRules[source]` / `EBNFRules[File[path]]` returns the unlowered list of `EBNFRule[name, kind, body]` records for inspection.

### Operator overloads on `ParserCombinator`

| Syntax                          | Lowers to                                       | Combinator           |
|---------------------------------|-------------------------------------------------|----------------------|
| <code>p1 \| p2</code>           | <code>[Alternatives]()[p1, p2]</code>           | [ParseChoice]()      |
| <code>p1 ~~ p2</code>           | <code>[StringExpression]()[p1, p2]</code>       | [ParseSequence]()    |
| <code>p..</code>                | <code>[Repeated]()[p]</code>                    | [ParseSome]()        |
| <code>p...</code>               | <code>[RepeatedNull]()[p]</code>                | [ParseMany]()        |
| <code>Optional[p]</code>        | <code>[Optional]()[p]</code>                    | [ParseOptional]()    |

The `~~` UpValue *only* fires when at least one side is a `ParserCombinator`; plain `"foo" ~~ "bar"` between strings keeps its built-in [StringExpression]() meaning. `~` is *not* overloaded - it stays as WL's infix function notation `a~f~b == f[a, b]`.

### GrammarRules

`Parse[GrammarRules[...], input]` accepts two surface shapes for the rule LHS, lowered on the same code path:

```
(* string-template form - the Interpreter / FormFunction style *)
Parse[GrammarRules[{"the weather in <city>" -> city}], "the weather in NYC"]
(* "NYC" *)

Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
(* 8 *)

(* pattern form - the same shape the built-in cloud-deployed GrammarRules takes *)
Parse[
    GrammarRules[{
        FixedOrder["add", a : GrammarToken["Number"], "and", b : GrammarToken["Number"]] :> a + b
    }],
    "add 3 and 5"
]
(* 8 *)
```

Pattern nodes lowered: `"string"`, `form1 | form2`, `FixedOrder`, `OptionalElement`, `form..` / `form...`, `DelimitedSequence`, `CaseSensitive`, `GrammarToken["Number" | "Integer" | "Word"]`, and the `Pattern[name, form]` capture form (`x : form`). What's still cloud-only: semantic `GrammarToken` types (`"City"`, `"Color"`, `"SemanticNumber"`, ...) that need [Interpreter](paclet:ref/Interpreter), `AnyOrder`, `RegularExpression`, subsidiary domain defs in `GrammarRules[rules, defs]`, and the `AllowLooseGrammar` / `IgnoreCase` / `IgnoreDiacritics` options. See [ParsingGrammarRules](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) for the full coverage map and workarounds.

### Diagnostics
- [ParseError]() structured error with `"Position"`, `"Expected"`, `"Found"` keys

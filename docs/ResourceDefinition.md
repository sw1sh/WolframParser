---
Template: Paclet
ResourceType: Paclet
Name: Wolfram/Parser
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
Description: Parser combinators for the Wolfram Language - GrammarRules compatible, locally compiled, with a LaTeX math parser
ContributedBy: Nikolay Murzin, Claude (Anthropic)
Keywords: [parser, parsing, grammar, combinator, GrammarRules, FunctionCompile, LaTeX, KaTeX, TPTP, DSL]
MainGuide: Documentation/English/Guides/WolframParser.nb
License: MIT
WolframVersion: 14.0+
Categories: [Core Language & Structure]
Sources: ["Daan Leijen, *Parsec: Direct Style Monadic Parser Combinators for the Real World*, 2001", "Bryan Ford, *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*, POPL 2004"]
SourceControlURL: https://github.com/sw1sh/WolframParser
Links: ["[Parser combinator (Wikipedia)](https://en.wikipedia.org/wiki/Parser_combinator)", "[Parsing expression grammar (Wikipedia)](https://en.wikipedia.org/wiki/Parsing_expression_grammar)", "[AntonAntonov/FunctionalParsers (paclet)](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/)", "[KaTeX screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml)"]
RelatedResources: [Wolfram/MarkdownToNotebook]
---

## Details & Options

- The library reuses the [GrammarRules]() declarative slot-syntax DSL, but compiles each grammar to a local parser via [FunctionCompile]() instead of round-tripping through [CloudDeploy](). The supported subset of `GrammarRules` is mapped in the [Parsing GrammarRules Locally](paclet:Wolfram/Parser/tutorial/ParsingGrammarRules) tech note.
- A Parsec-style combinator core (`Parse*` constructors) covers grammars that don't fit the declarative shape: LaTeX math, custom DSLs with backtracking / lookahead, recursive descent over [CodeParser]() ASTs.
- [LaTeXMathParse]() is a working LaTeX math-mode parser at 126 / 126 coverage of [KaTeX's own screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml). Output is a tree of Wolfram boxes ([FractionBox](), [SubsuperscriptBox](), [RadicalBox](), [GridBox](), ...) ready to drop into a notebook cell or wrap with [DisplayForm]() for kernel-side rendering.
- Operates uniformly on strings, on lists of tagged tokens, and on lists of Wolfram expressions (so the same combinators that lex a string can walk a [CodeParser]() AST).
- The kernel is dependency-free and has no C library; performance comes from [FunctionCompile]()'s LLVM backend.

## Usage

The package provides [Parse]() and [ParserCompile]() as the entry points, [ParserCombinator]() as the single computable head every constructor returns, and the `Parse*` family of constructors - [ParseLiteral](), [ParseCharacter](), [ParseSequence](), [ParseChoice](), [ParseMany](), [ParseSome](), [ParseOptional](), [ParseBetween](), [ParseAction](), [ParseRecursive](), [ParseLookahead](), [ParseNotFollowedBy](), [ParseTry](). [GrammarRules]() is accepted as input to `Parse` and lowered locally. [LaTeXMathParse]() parses LaTeX math-mode source to a tree of Wolfram boxes.

## Basic Examples

A literal-string parser:

```wl
Parse[ParseLiteral["foo"], "foo"]
```

<!-- => "foo" -->

---

A one-or-more digit parser with an action that folds the captured digits into an integer:

```wl
Parse[
    ParseAction[
        ParseSome[ParseCharacter[DigitCharacter]],
        FromDigits @ StringJoin[{##}] &
    ],
    "12345"
]
```

<!-- => 12345 -->

---

A [GrammarRules]() slot template, parsed locally (no [CloudDeploy]() round-trip):

```wl
Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
```

<!-- => 8 -->

---

[LaTeXMathParse]() on an inline math source - the output is a tree of Wolfram boxes ready to drop into a notebook cell:

```wl
LaTeXMathParse["\\frac{x^2}{y^2} = z^2"]
```

<!-- => RowBox[{FractionBox[SuperscriptBox["x", "2"], SuperscriptBox["y", "2"]], "=", SuperscriptBox["z", "2"]}] -->

## Scope

### Combinator primitives

Every constructor returns a [ParserCombinator](); the wrapper carries the constructor's name, args, and an options [Association](). [Parse]() interprets the tree, [ParserCompile]() lowers it to a [FunctionCompile]() / PEG-VM backend.

A bare-literal parser is the smallest non-trivial example - it matches its argument exactly and returns the matched string:

```wl
Parse[ParseLiteral["wolfram"], "wolfram"]
```

[ParseCharacter]() matches one character against a pattern (a literal, an alternation, or a named character class):

```wl
Parse[ParseSome[ParseCharacter[LetterCharacter]], "abc"]
```

[ParseSequence]() runs combinators in order, returning the list of their results; [ParseChoice]() returns the first one that succeeds (PEG-ordered):

```wl
Parse[ParseSequence[ParseLiteral["x"], ParseLiteral["="], ParseSome[ParseCharacter[DigitCharacter]]], "x=42"]
```

[ParseAction]() wraps a parser with a transformer; the transformer is splatted across the parser's result list, so [ParseSome]() followed by [StringJoin]() rejoins the matched chars:

```wl
Parse[ParseAction[ParseSome[ParseCharacter[DigitCharacter]], StringJoin], "12345"]
```

### Lookahead and backtracking

[ParseLookahead]() succeeds iff its argument would match - consuming nothing. [ParseNotFollowedBy]() is its negation. Together they bound a body's content without committing to the delimiter:

```wl
Parse[
    ParseAction[
        ParseSome[ParseSequence[ParseNotFollowedBy[ParseLiteral["END"]], ParseCharacter[_]]],
        StringJoin @ Map[#[[2]] &, {##}] &
    ],
    "hello world END"
]
```

### Recursion

[ParseRecursive]() defers binding until parse time, so a parser may name itself or its peers without pre-declaration. A balanced-parentheses parser is one line:

```wl
parens = ParseChoice[
    ParseAction[ParseSequence[ParseLiteral["("], ParseRecursive[parens], ParseLiteral[")"]], #2 &],
    ParseLiteral[""]
];
Parse[parens, "((()))"]
```

### Declarative grammars

A [GrammarRules]() expression lowers to a [ParserCombinator]() and runs locally - no [CloudDeploy](). The pattern form mirrors what the cloud accepts; the slot-template form (`<name:Type>`) is the convenient surface for word / digit captures:

```wl
Parse[GrammarRules[{"weather in <city>" -> city}], "weather in Boston"]
```

The pattern form accepts the same shapes [CloudDeploy]()'d [GrammarRules]() does - [FixedOrder](), [AnyOrder](), [OptionalElement](), [DelimitedSequence](), [RegularExpression](), [Pattern](), and [GrammarToken](). The [Parsing GrammarRules Locally](paclet:Wolfram/Parser/tutorial/ParsingGrammarRules) tech note walks through every pattern.

### Compilation

[ParserCompile]() lowers a [ParserCombinator]() to a [FunctionCompile]() function for the small / non-recursive case, or to a PEG-VM instruction table for large / recursive grammars (LaTeX, TPTP). The choice is opt-in via `Method -> "PEGVM"`:

```wl
With[{cf = ParserCompile[ParseSome[ParseCharacter[DigitCharacter]]]},
    Parse[cf, "12345"]
]
```

The compiled artifact can be `Export`'d to a `.wxf` file and `Import`'d without recompiling - that is how [LaTeXMathParse]() ships its compiled core (`Assets/LaTeXMathParserCompiled.wxf`).

## Options

[ParserCompile]() takes a `Method` option choosing the compilation backend:

- `Method -> Automatic` *(default)* - lowers the parser to a [FunctionCompile]() function. Fast on small to medium grammars; inliner aborts on large recursive trees (LaTeX, TPTP).
- `Method -> "PEGVM"` - lowers to an integer instruction table run by an LPEG-style parsing machine. Scales to recursive grammars [FunctionCompile]() cannot handle, with 1-2 orders of magnitude better runtime than the interpreter. The compiled artifact `Export`'s to `.wxf` and `Import`'s without recompiling.

```wl
ParserCompile[ParseSome[ParseCharacter[DigitCharacter]], Method -> "PEGVM"]
```

[Parse]() and [ParsePartial]() take no user-facing options; the parser tree is the configuration.

## Applications

### LaTeX math

[LaTeXMathParse]() is the largest grammar in the paclet: a PEG over the full inline-math fragment of TeX. It handles `\frac`, `\sqrt`, sub/superscripts, `\left/\right` delimiters, `\begin/end{matrix}` environments, big operators with limits, and 40+ KaTeX macros. The build ships a `.wxf` of the PEG-VM-compiled parser; first use auto-loads it if its grammar hash matches the source:

```wl
LaTeXMathParse["\\sum_{i=1}^{n} \\frac{1}{i^2} = \\frac{\\pi^2}{6}"]
```

### Markdown inline

[MarkdownInlineParse]() parses inline markdown - emphasis, code spans, math, links, sub/sup, escapes - to a tree of typed atoms ([MdText](), [MdBold](), [MdMathInline](), [MdLink](), ...). The grammar is ~75 lines of [ParseChoice]() over the primitives; see the [Markdown inline parser](paclet:Wolfram/Parser/tutorial/ParsingMarkdownInline) tech note:

```wl
MarkdownInlineParse["**bold $x$** and `code`"]
```

### EBNF / BNF grammars

[EBNFParse]() reads a `::=` / `:==` / `::-` / `:::` BNF source (the TPTP project's `SyntaxBNF` shape) and returns an [Association]() of rule names to [ParserCombinator](). The BNF parser is itself written in the [ParserCombinator]() core - a literal demonstration that the combinators are enough to parse their own meta-grammar:

```wl
EBNFParse["<digit> ::= 0 | 1 | 2 | 3\n<number> ::= <digit> | <digit> <number>"]
```

### TPTP

[TPTPImport]() parses a `.p` file from the TPTP problem library - first-order, equational, higher-order, and typed fragments - returning a list of formulas. The parser handles the full TPTP grammar (10k+ lines of BNF) by composing the [EBNFParse]() output with a small post-processing pass.

### Walking Wolfram ASTs

The combinators operate uniformly on strings, on lists of tokens, and on lists of Wolfram expressions, so the same primitives that lex a string can walk a [CodeParser]() AST. The two domains share the implementation; only the leaf [ParseCharacter]() / [ParseLiteral]() definitions differ.

## Properties and Relations

[GrammarRules]() with [GrammarApply]() requires a [CloudDeploy]() round-trip; the cloud also resolves [Interpreter]()-backed semantic types (`City`, `Date`, `Quantity`, ...) via Wolfram knowledge. The local lowering trades the round-trip for offline evaluation - every documented pattern node is supported except the option flags (`AllowLooseGrammar`, `IgnoreCase`, `IgnoreDiacritics`). The [Parsing GrammarRules Locally](paclet:Wolfram/Parser/tutorial/ParsingGrammarRules) tech note maps the supported subset.

[CodeParser]() parses Wolfram-language source to an AST; it is the *target* of a parser walk, not a combinator core itself. [Wolfram`Parser`]()'s [ParseRecursive]() + [ParseChoice]() pair walks a [CodeParser]() AST the same way it walks a token list - same primitives, different leaf type.

[StringCases]() with [StringExpression]() patterns is the WL idiom for one-shot string matching; it does not compose, does not capture nested structure, and does not return a typed parse tree. [Wolfram`Parser`]() is the path to a real parse tree when [StringCases]() outgrows the single-rule shape.

[AntonAntonov/FunctionalParsers](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/) is the closest sibling - a Wolfram parser-combinator library predating this one. Differences: this paclet ships a [FunctionCompile]() / PEG-VM compile path, [GrammarRules]() compatibility, and the LaTeX / TPTP / Markdown front-ends out of the box.

## Possible Issues

### PEG ordering

[ParseChoice]() is PEG-ordered: alternatives are tried left-to-right, and the first match wins (no longest-match backtracking). `"north" | "northwest"` matches `"north"` on input `"northwest"` and leaves `"west"` unconsumed. Order alternatives longer-first, or use [ParseChoiceLongest]() when POSIX longest-match is required:

```wl
Parse[ParseChoice[ParseLiteral["northwest"], ParseLiteral["north"]], "northwest"]
```

### Recursive grammars

[FunctionCompile]() inlines combinator graphs, so a recursive grammar (LaTeX, TPTP) hits the inliner's size cap and either compiles slowly or aborts. Use `Method -> "PEGVM"` for those: the PEG-VM lowers to an integer instruction table that is recursive at runtime, not at compile time.

### Semantic-token network dependency

A [GrammarToken]() whose type is not `Number` / `Integer` / `Word` / `Automatic` calls out to [Interpreter]() at parse time. `City`, `Country`, `Quantity`, `Date`, ... need the Wolfram knowledge engine reachable. Tests that depend on these are not offline-stable.

### Strict-PEG full-input match

[Parse]() requires the *entire* input to match the grammar. A prefix match returns a [Failure]() with `Expected -> "<end of input>"`. Use [ParsePartial]() to get `{result, leftover}` for prefix-matching grammars (REPL prompts, line-based protocols).

## Neat Examples

### A self-parsing BNF

[EBNFParse]() can parse the BNF that describes its own grammar. The library's [EBNFParse]() definition (in [Kernel/EBNF.wl](https://github.com/sw1sh/WolframParser/blob/main/Kernel/EBNF.wl)) is built from `<rule> ::= <name> ::= <body>`-shaped patterns; running the parser on a BNF source that *describes* that very shape is the smallest non-trivial self-host.

### Greek-letter LaTeX

A one-character math source resolves to its Wolfram named character:

```wl
LaTeXMathParse["\\alpha + \\beta = \\gamma"]
```

The output contains `"\[Alpha]"`, `"\[Beta]"`, `"\[Gamma]"` glyphs - the parser's command-to-glyph table covers the full Greek alphabet plus a long tail of math symbols.

### Markdown link-with-code-label

The recursive label parser in [MarkdownInlineParse]() handles a code-styled label inside a link, producing one [MdLink]() whose label is itself a parsed-list:

```wl
MarkdownInlineParse["See [`Range`](paclet:ref/Range) for details."]
```

### A grammar in one [GrammarRules]() expression

The "appliance controller" grammar fits in one declarative expression with no helper definitions - the same shape that round-trips through [CloudDeploy]() runs locally with [Parse]():

```wl
Parse[
    GrammarRules[{
        FixedOrder[
            "turn",
            OptionalElement["the", "no-the"],
            appl : ("stove" | "oven" | "fridge"),
            state : ("on" | "off")
        ] :> {appl, state}
    }],
    "turn the stove on"
]
```

## Hero Image

Test snippets from the suite, floating: typeset math the LaTeX parser
produces (the Basel sum, a Gaussian integral, Euler's identity, a matrix,
a nested radical, a bra-ket, Greek letters) interleaved with parser
combinator fragments (`Parse`, `ParseChoice`, `GrammarRules`). Loaded
from the paclet's registered `Hero` asset.

```wl
Import[PacletObject["Wolfram/Parser"]["AssetLocation", "Hero"]]
```

## Author Notes

This paclet was authored together with Anthropic's [Claude](https://www.anthropic.com/claude) (`claude-opus-4-7`). Claude wrote the prose, the kernel code, and the survey of existing parser tech; the human author chose the design direction, vetted the comparisons against the actual implementations, and integrated each iteration. AI-assisted authorship is disclosed here so a reader can weigh the source appropriately.

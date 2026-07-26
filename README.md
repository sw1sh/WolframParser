# WolframParser

A general, fast, composable parser library for the Wolfram Language. Reuses
the [`GrammarRules`](https://reference.wolfram.com/language/ref/GrammarRules.html)
declarative DSL but compiles each grammar to a local parser via
[`FunctionCompile`](https://reference.wolfram.com/language/ref/FunctionCompile.html)
instead of round-tripping through `CloudDeploy`. Pairs that with a
Parsec-style combinator core for grammars that don't fit the declarative
shape.

WL package context: `` Wolfram`Parser` ``. Top-level entry point: `Parse[grammar, input]`.

## Why

The Wolfram Language has rich *piecewise* parsing support
([`StringExpression`](https://reference.wolfram.com/language/ref/StringExpression.html),
[`Interpreter`](https://reference.wolfram.com/language/ref/Interpreter.html),
`GrammarRules`, `CodeParser`,
[AntonAntonov/FunctionalParsers](https://resources.wolframcloud.com/PacletRepository/resources/AntonAntonov/FunctionalParsers/)),
but no single library that lets you compose a custom parser of arbitrary
complexity, *locally*, with the kind of compositional ergonomics Parsec
made famous. This paclet aims to fill that gap.

Target use cases:

- **LaTeX math** — the gnarly bits `StringExpression` can't reach (`\mathbb{R}`, `\frac{a}{b}`, `\sum_{}^{}`, `\begin{matrix}…\end{matrix}`).
- **TPTP** — first-order / clausal / typed first-order theorem-prover formats.
- **Any custom DSL** — config files, query languages, internal small languages.

## Status

**v0.2.3** — a working library. The `` Wolfram`Parser` `` kernel is six files under
`Parser/Kernel/`: a Parsec-style combinator core plus the `GrammarRules` lowering
([`Parser.wl`](Parser/Kernel/Parser.wl)), a LaTeX math-mode parser at 126 / 126 on
KaTeX's screenshotter corpus ([`LaTeX.wl`](Parser/Kernel/LaTeX.wl)), a Markdown parser
([`Markdown.wl`](Parser/Kernel/Markdown.wl)), an EBNF grammar reader
([`EBNF.wl`](Parser/Kernel/EBNF.wl)), a TPTP importer/exporter
([`TPTP.wl`](Parser/Kernel/TPTP.wl)), and the AST vocabulary — `LeafNode` / `CallNode` /
… / `ToCodeParser` ([`AST.wl`](Parser/Kernel/AST.wl)). A `Languages/` showcase builds five
example front-ends (Calculator, JSON, Lisp, Lambda, Brainfuck, plus OpenQASM) on the core.

The kernel is dependency-free — no C library — with performance from `FunctionCompile`'s
LLVM backend. It ships as a full paclet (`Guides` / `Symbols` / `Tutorials` documentation,
built from `docs/` by [`build.wls`](build.wls)) and is covered by ~360 core + ~70 language
tests (`wl -f run-tests.wls`).

## Layout

```
WolframParser/
|-- Parser/                         the paclet
|   |-- PacletInfo.wl
|   |-- Kernel/                     AST.wl EBNF.wl LaTeX.wl Markdown.wl Parser.wl TPTP.wl (+ Languages/)
|   |-- Assets/                     hero.png, LaTeXMathParserCompiled.wxf
|   |-- Tests/                      *.wlt, per subsystem
|   `-- Documentation/English/      built ref pages / guides / tutorials (from docs/)
|-- docs/                           literate-markdown documentation sources
|   |-- DOC_GUIDE.md                house style for these sources
|   |-- ResourceDefinition.md       the paclet resource page
|   `-- Guides/  Symbols/  Tutorials/
|-- build.wls                       docs/*.md -> notebooks via MarkdownToNotebook
`-- README.md
```

## License

MIT

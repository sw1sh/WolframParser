# WolframParser

A general, fast, composable parser library for the Wolfram Language. Reuses
the [`GrammarRules`](https://reference.wolfram.com/language/ref/GrammarRules.html)
declarative DSL but compiles each grammar to a local parser via
[`FunctionCompile`](https://reference.wolfram.com/language/ref/FunctionCompile.html)
instead of round-tripping through `CloudDeploy`. Pairs that with a
Parsec-style combinator core for grammars that don't fit the declarative
shape.

WL package context: `` Wolfram`Parser` ``. Top-level entry point: `Parse[grammar, input]`.

Documentation: the [WolframParser site](https://www.wolframcloud.com/obj/wolframinstitute/WolframParser),
over the paclet resource
[Wolfram/Parser](https://www.wolframcloud.com/obj/wolframinstitute/DeployedResources/Paclet/Wolfram/Parser).

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

**v1.7.2** — a working library. The `` Wolfram`Parser` `` kernel is six files under
`Parser/Kernel/`: a Parsec-style combinator core plus the `GrammarRules` lowering
([`Parser.wl`](Parser/Kernel/Parser.wl)), a LaTeX math-mode parser at 126 / 126 on
KaTeX's screenshotter corpus ([`LaTeX.wl`](Parser/Kernel/LaTeX.wl)), a Markdown parser
([`Markdown.wl`](Parser/Kernel/Markdown.wl)), an EBNF grammar reader
([`EBNF.wl`](Parser/Kernel/EBNF.wl)), a TPTP importer/exporter
([`TPTP.wl`](Parser/Kernel/TPTP.wl)), and the AST vocabulary — `LeafNode` / `CallNode` /
… / `ToCodeParser` ([`AST.wl`](Parser/Kernel/AST.wl)). A `Languages/` showcase builds six
example front-ends (Calculator, JSON, Lisp, Lambda, Brainfuck, ABC), plus OpenQASM and the Wolfram Language itself, on the core;
`WolframLanguageHeld` reads the 7,000 sources of a Wolfram installation as the kernel's reader does, by a compiled lexer and
a compiled parser over packed tokens.

The kernel is dependency-free — no C library — with performance from `FunctionCompile`'s
LLVM backend. It ships as a full paclet (`Guides` / `Symbols` / `Tutorials` documentation,
built from `docs/` with [PacletPage](https://github.com/WolframInstitute/PacletPage)) and is
covered by 446 core and 963 language tests (`wl -f run-tests.wls`).

[`build.wls`](build.wls) builds the documentation, [`release.wls`](release.wls) builds it,
deploys the paclet resource and publishes the documentation site, and
[`submit.wls`](submit.wls) submits the paclet to the Paclet Repository; they share
[`pacletpage.wl`](pacletpage.wl).

## Layout

```
WolframParser/
|-- Parser/                         the paclet
|   |-- PacletInfo.wl
|   |-- Kernel/                     AST.wl EBNF.wl LaTeX.wl Markdown.wl Parser.wl TPTP.wl (+ Languages/)
|   |-- Assets/                     hero.png, LaTeXMathParserCompiled.wxf
|   |-- Tests/                      *.wlt, per subsystem
|   `-- Documentation/English/      ref pages / guides / tutorials, built from docs/
|-- docs/                           literate-markdown documentation sources
|   |-- DOC_GUIDE.md                house style for these sources
|   |-- ResourceDefinition.md       the paclet resource page
|   `-- Guides/  Symbols/  Tutorials/
|-- build.wls                       docs/*.md -> notebooks, with PacletPage
|-- release.wls                     build, deploy the resource, publish the site
|-- submit.wls                      submit to the Paclet Repository
|-- pacletpage.wl                   what the three share
|-- run-tests.wls                   every Parser/Tests/**/*.wlt
`-- README.md
```

## License

MIT

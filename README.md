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

**v0.1** — design + scaffold. Two tech notes drive the implementation:

- [`docs/Tutorials/ParserLandscape.md`](docs/Tutorials/ParserLandscape.md) — what already exists in the WL parser landscape and outside it.
- [`docs/Tutorials/DesignAndCompilationStrategy.md`](docs/Tutorials/DesignAndCompilationStrategy.md) — the API, the parser algebra, the FunctionCompile lowering, and the worked LaTeX / TPTP targets.

The kernel is intentionally empty — the design comes first so the code can
be written against it.

## Layout

```
WolframParser/
|-- PacletInfo.wl
|-- Kernel/Parser.wl
|-- README.md
|-- ResourceDefinition.md
|-- docs/
|   |-- Guides/WolframParser.md
|   |-- Symbols/
|   `-- Tutorials/
|       |-- ParserLandscape.md                  (the survey)
|       |-- DesignAndCompilationStrategy.md     (the design)
|       `-- Overview.md
```

## License

MIT

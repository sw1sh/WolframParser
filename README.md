# WolframParser

A general, fast, composable parser library for the Wolfram Language - parser
combinators, EBNF grammars, and structured ASTs, all running **locally** (no
cloud).

The library bridges what is otherwise scattered across the Wolfram parser
landscape:

- declarative pattern matching ([StringExpression](), [StringCases]())
- type-driven parsing ([Interpreter]())
- cloud-only grammars ([GrammarRules](), [GrammarApply]())
- WL-only fast parsing ([CodeParser]())
- pure-WL combinators ([AntonAntonov/FunctionalParsers](https://github.com/antononcube/MathematicaForPrediction))

See the survey tech note
[`docs/Tutorials/ParserLandscape.md`](docs/Tutorials/ParserLandscape.md)
for the design problem this paclet is trying to solve.

## Status

v0.1 - **survey only**. The kernel is a placeholder; the design and the
landscape doc come first so the API can be informed by what's actually out
there.

## Layout

```
WolframParser/
|-- PacletInfo.wl
|-- Kernel/WolframParser.wl
|-- README.md
|-- ResourceDefinition.md
|-- docs/
|   |-- Guides/WolframParser.md
|   |-- Symbols/
|   `-- Tutorials/
|       |-- ParserLandscape.md   (the survey)
|       `-- Overview.md
```

## License

MIT

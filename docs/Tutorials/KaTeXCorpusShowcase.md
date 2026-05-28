---
Template: TechNote
Name: KaTeXCorpusShowcase
Title: KaTeX Corpus Showcase
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/KaTeXCorpusShowcase
Keywords: [LaTeX, math, parser, KaTeX, showcase, corpus, FractionBox, GridBox, RowBox]
RelatedGuides: [WolframParser]
RelatedTutorials: [LaTeXMathParserImplementation]
---

## What this note covers

[KaTeX](https://katex.org) ships an internal [screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml) - 126 hand-picked LaTeX math expressions covering every feature the project supports, from `\frac` and `\sqrt` to full `align`/`pmatrix`/`cases` environments, color macros, big-operator decorations, and the long tail of named symbols. KaTeX itself uses these to rasterise reference images for visual diffing.

`LaTeXMathParse` parses **126 / 126** of them into a Wolfram box tree. This note is the corpus, evaluated end-to-end: for each entry it shows the raw LaTeX source on the left and `LaTeXMathParse`'s output on the right (the front end renders the boxes as typeset math). It's the most honest read on what the parser covers - the corpus *is* the coverage.

The same `Tests/katex-cases.json` file is loaded by the `Tests/LaTeX.wlt` test suite; the parser is expected to return a non-[ParseError]() for every one. See [LaTeXMathParserImplementation](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) for the design decisions behind making real-world TeX parse.

## The corpus

Every row below was produced by `LaTeXMathParse[source]` on a single cell - no per-case hand-massaging, no fallback rasteriser.

```wl
With[{
    cases = Association @ Import @ FileNameJoin[{
        PacletObject["Wolfram/WolframParser"]["Location"],
        "Tests", "katex-cases.json"
    }]
},
    Grid[
        Prepend[
            KeyValueMap[
                {
                    Style[#1, Bold, 11],
                    Pane[
                        Style[#2, FontFamily -> "Source Code Pro", FontSize -> 9, GrayLevel[0.4]],
                        {320, Automatic}, Alignment -> {Left, Top}
                    ],
                    Pane[
                        Style[DisplayForm @ LaTeXMathParse[#2], FontColor -> GrayLevel[0.15]],
                        {Scaled[1], Automatic}, Alignment -> {Left, Center}
                    ]
                } &,
                cases
            ],
            Style[#, Bold, GrayLevel[0.2]] & /@ {"Name", "Source", "Output"}
        ],
        Frame -> All,
        Alignment -> {Left, Top},
        FrameStyle -> GrayLevel[0.85],
        Background -> {None, {GrayLevel[0.92], {GrayLevel[0.99], GrayLevel[0.96]}}},
        ItemSize -> {{15, 40, Automatic}, Automatic},
        Spacings -> {1.5, 1}
    ]
]
```

## Failure mode

The parser is *tolerant*: if a `\macro` it doesn't know shows up, the macro name is emitted as a literal token together with its `{arg}` payload rather than aborting the whole expression. So `\foo{a}` from an unknown macro renders as `\foo a` in the output, and the rest of the surrounding math is unaffected. That's why every corpus entry produces a usable result even when the macro is rarely-used (e.g. `\colorbox`, `\htmlId`, `\includegraphics`).

A real failure - a malformed brace pair, an unclosed `\begin{...}`, a delimiter without its match - returns a [ParseError]() with a `"Position"` / `"Expected"` / `"Found"` triple. None of the 126 corpus entries trip that path, but it's the same shape `Parse` returns for any parser.

## See also

- [LaTeXMathParserImplementation](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) - design and implementation notes
- [LaTeXMathParse](paclet:Wolfram/WolframParser/ref/LaTeXMathParse) - the symbol reference page
- [KaTeX support table](https://katex.org/docs/support_table.html) - the human-readable list of what KaTeX claims to support, mirrored by the screenshotter corpus

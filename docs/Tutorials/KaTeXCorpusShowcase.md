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

[KaTeX](https://katex.org) ships an internal [screenshotter test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml) - 126 hand-picked LaTeX math expressions covering every feature the project supports, from ``\frac`` and ``\sqrt`` to full ``align`` / ``pmatrix`` / ``cases`` environments, color macros, big-operator decorations, and the long tail of named symbols. KaTeX itself uses these to rasterise reference images for visual diffing.

`LaTeXMathParse` parses **126 / 126** of them into a Wolfram box tree. This note is the corpus, evaluated end-to-end: for each entry it shows the raw LaTeX source on the left and `LaTeXMathParse`'s output on the right (the front end renders the boxes as typeset math). It's the most honest read on what the parser covers - the corpus *is* the coverage.

The same ``Tests/katex-cases.json`` file is loaded by the ``Tests/LaTeX.wlt`` test suite; the parser is expected to return a non-[ParseError]() for every one. See [LaTeXMathParserImplementation](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) for the design decisions behind making real-world TeX parse.

## The corpus

Every row below shows the LaTeX source, KaTeX's reference rendering (fetched from KaTeX's [screenshotter image set](https://github.com/KaTeX/KaTeX/tree/main/test/screenshotter/images)), and `LaTeXMathParse`'s rasterised output. Both renders are bitmaps so visual rendering issues in the notebook front end can't hide a parser bug - what you see is what each engine actually produced.

```wl
(* Force the front end to Light appearance up front - the headless
   build session would otherwise resolve Automatic to Dark, and the
   Rasterize calls below would emit white-text-on-black tiles
   for `LaTeXMathParse` while KaTeX's reference PNGs stay light, so
   the side-by-side compare reads as a colour difference rather than
   a content one.  The setting is process-wide for the FE session;
   later examples inherit it. *)
Quiet @ UsingFrontEnd[CurrentValue[$FrontEnd, LightDark] = "Light"];

$katexImageURL[name_String] :=
    "https://raw.githubusercontent.com/KaTeX/KaTeX/main/test/screenshotter/images/" <> name <> "-chrome.png";

(* Cache reference PNGs locally so re-builds don't re-download.  The
   cache lives outside the paclet so it's not in the build artifact. *)
$katexCacheDir = FileNameJoin[{$TemporaryDirectory, "katex-corpus-refs"}];
Quiet @ CreateDirectory[$katexCacheDir, CreateIntermediateDirectories -> True];

katexReference[name_String] := Module[{cached, url, img},
    cached = FileNameJoin[{$katexCacheDir, name <> ".png"}];
    If[ !FileExistsQ[cached],
        url = $katexImageURL[name];
        Quiet @ URLDownload[url, cached]
    ];
    If[ FileExistsQ[cached],
        (* The published PNGs are 1024 x 768 with the math centred in
           an otherwise-empty canvas - ImageCrop to the content bounding
           box so the visible rendering isn't a postage stamp inside a
           full screenshot. *)
        ImageCrop[Import[cached, "PNG"]],
        Missing["NotFetched"]
    ]
];

(* KaTeX renders in Computer Modern (its KaTeX_Math face).  Our boxes
   inherit the front end's default math font, which is Times-based, so
   the side-by-side glyph shapes differ even when the structure matches.
   Prefer an installed Computer-Modern-family font so the comparison is
   about content, not typeface; fall back to the FE default otherwise.

   Detection is by FONT FILE on disk, not $FontFamilies: a headless
   build FE returns {} for $FontFamilies yet still RENDERS a family by
   name.  `font-computer-modern` installs the CMU TrueType set
   (cmun*.ttf); Latin Modern installs lmroman*/latinmodern*. *)
$fontDirs = {FileNameJoin[{$HomeDirectory, "Library", "Fonts"}], "/Library/Fonts"};
$mathFont = Which[
    FileNames["lmroman*" | "latinmodern*", $fontDirs] =!= {}, "Latin Modern Roman",
    FileNames["cmun*", $fontDirs] =!= {}, "CMU Serif",
    True, None];
$mathFontOpts = If[$mathFont === None, {}, {FontFamily -> $mathFont}];

(* The parser tags italic identifiers StyleBox[c, "TI"]; that named
   style pins its own face and ignores an outer FontFamily, so without
   this rewrite the CM font reaches digits/operators but not the
   letters.  Promote "TI" to explicit italic + the CM family. *)
applyMathFont[box_] := If[$mathFont === None, box,
    box /. StyleBox[a_, "TI", r___] :> StyleBox[a, FontSlant -> Italic, FontFamily -> $mathFont, r]];

(* Rasterise our parse at a font size chosen to roughly match the
   visual scale of KaTeX's published screenshots (default WL math is
   ~10pt, KaTeX renders nearer to ~24pt). Both renders end up as
   bitmaps so the side-by-side compare honestly reflects what each
   engine produced. *)
ourRender[src_String] := Module[{r = Quiet @ Check[LaTeXMathParse[src], $Failed]},
    If[ MatchQ[r, _ParseError | $Failed],
        Style["ParseError", Red, FontSize -> 14],
        Rasterize[
            Style[DisplayForm[applyMathFont[r]], FontSize -> 24, Sequence @@ $mathFontOpts],
            ImageResolution -> 144
        ]
    ]
];

(* Resize both renders to a common height so KaTeX's reference image
   and LaTeXMathParse's render line up at the same visual scale per
   row. Fixed height (aspect preserved); the row's width adjusts. *)
$rowHeight = 80;
normalise[img_Image] := ImageResize[img, {Automatic, $rowHeight}]
normalise[other_] := other  (* ParseError style, Missing, etc. *)

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
                        Style[#2, FontFamily -> "Source Code Pro",
                            FontSize -> 9, GrayLevel[0.3]],
                        {280, Automatic}, Alignment -> {Left, Top}
                    ],
                    Pane[
                        normalise @ katexReference[#1],
                        {Automatic, $rowHeight + 8},
                        Alignment -> {Center, Center}
                    ],
                    Pane[
                        normalise @ ourRender[#2],
                        {Automatic, $rowHeight + 8},
                        Alignment -> {Center, Center}
                    ]
                } &,
                cases
            ],
            Style[#, Bold, GrayLevel[0.15]] & /@ {"Name", "Source", "KaTeX", "LaTeXMathParse"}
        ],
        Frame -> All,
        Alignment -> {Left, Center},
        FrameStyle -> GrayLevel[0.85],
        Spacings -> {1.5, 1}
    ]
]
```

The first build fetches all 126 reference PNGs from GitHub (about 3 MB total) into `$TemporaryDirectory/katex-corpus-refs/` and caches them there; subsequent builds reuse the cache.

## Failure mode

The parser is *tolerant*: if a ``\macro`` it doesn't know shows up, the macro name is emitted as a literal token together with its ``{arg}`` payload rather than aborting the whole expression. So ``\foo{a}`` from an unknown macro renders as ``\foo a`` in the output, and the rest of the surrounding math is unaffected. That's why every corpus entry produces a usable result even when the macro is rarely-used (e.g. ``\colorbox``, ``\htmlId``, ``\includegraphics``).

A real failure - a malformed brace pair, an unclosed ``\begin{...}``, a delimiter without its match - returns a [ParseError]() with a `"Position"` / `"Expected"` / `"Found"` triple. None of the 126 corpus entries trip that path, but it's the same shape `Parse` returns for any parser.

## See also

- [LaTeXMathParserImplementation](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) - design and implementation notes
- [LaTeXMathParse](paclet:Wolfram/WolframParser/ref/LaTeXMathParse) - the symbol reference page
- [KaTeX support table](https://katex.org/docs/support_table.html) - the human-readable list of what KaTeX claims to support, mirrored by the screenshotter corpus

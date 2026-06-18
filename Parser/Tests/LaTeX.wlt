(* :Title: tests-latex.wlt - LaTeX math parser test suite *)
(* :Context: Wolfram`Parser` *)

Needs["Wolfram`Parser`"]


(* === atoms === *)

VerificationTest[
    LaTeXMathParse["x"],
    StyleBox["x", "TI"],
    TestID -> "LaTeX: single-letter identifier is italic"
]

VerificationTest[
    LaTeXMathParse["42"],
    "42",
    TestID -> "LaTeX: integer literal"
]

VerificationTest[
    LaTeXMathParse["3.14"],
    "3.14",
    TestID -> "LaTeX: decimal literal"
]


(* === binary operators === *)

VerificationTest[
    LaTeXMathParse["x + 1"],
    RowBox[{StyleBox["x", "TI"], "+", "1"}],
    TestID -> "LaTeX: x + 1"
]

VerificationTest[
    LaTeXMathParse["x = 1"],
    RowBox[{StyleBox["x", "TI"], "=", "1"}],
    TestID -> "LaTeX: equation x = 1"
]


(* === font-style commands === *)

(* Use Unicode mathematical-alphanumeric-symbols block directly -
   covers full A-Z (with legacy-block exceptions for ℝ, ℂ, ℍ, ...),
   plus lowercase a-z and digits which WL's named-character coverage
   skips. *)
VerificationTest[
    LaTeXMathParse["\\mathbb{R}"],
    FromCharacterCode[16^^211D],   (* ℝ - in legacy Letterlike block *)
    TestID -> "LaTeX: \\mathbb{R} -> blackboard R"
]

VerificationTest[
    LaTeXMathParse["\\mathcal{F}"],
    FromCharacterCode[16^^2131],   (* ℱ - script F in legacy block *)
    TestID -> "LaTeX: \\mathcal{F} -> script F"
]

VerificationTest[
    LaTeXMathParse["\\mathfrak{G}"],
    FromCharacterCode[16^^1D50A],  (* 𝔊 - fraktur G in SMP block *)
    TestID -> "LaTeX: \\mathfrak{G} -> gothic G"
]


(* === Greek letters === *)

VerificationTest[
    LaTeXMathParse["\\alpha"],
    StyleBox["\[Alpha]", "TI"],
    TestID -> "LaTeX: Greek \\alpha"
]

VerificationTest[
    LaTeXMathParse["\\Omega"],
    "\[CapitalOmega]",
    TestID -> "LaTeX: Greek \\Omega"
]


(* === raw Unicode atoms (pasted, not \macro) ===
   The PEGVM-compiled parser matches char classes (LetterCharacter, the
   unicodeAtom predicate) as ASCII only, so a pasted Unicode letter/symbol
   fails to match there. LaTeXMathParse detects non-ASCII input and routes it
   to the interpreted grammar, which handles it via identAtom / unicodeAtom -
   this is what lifts the KaTeX corpus from 117 to 126. *)
VerificationTest[
    LaTeXMathParse["\[Alpha]"],
    StyleBox["\[Alpha]", "TI"],
    TestID -> "LaTeX: raw Unicode Greek alpha -> italic atom"
]

VerificationTest[
    LaTeXMathParse["\\frac{\[Alpha]\[Beta]}{\[Gamma]}"],
    FractionBox[
        RowBox[{StyleBox["\[Alpha]", "TI"], StyleBox["\[Beta]", "TI"]}],
        StyleBox["\[Gamma]", "TI"]
    ],
    TestID -> "LaTeX: raw Unicode Greek inside \\frac"
]

VerificationTest[
    MatchQ[LaTeXMathParse[FromCharacterCode[16^^3F5]], _Failure],
    False,
    TestID -> "LaTeX: variant epsilon (U+03F5) parses, no ParseError"
]

(* A pasted Unicode SYMBOL or pre-styled letter must render upright, exactly
   as its \macro form does - not italicised like a variable. *)
VerificationTest[
    LaTeXMathParse[FromCharacterCode[16^^2202]],
    LaTeXMathParse["\\partial"],
    TestID -> "LaTeX: pasted symbol == its macro (raw \[PartialD] == \\partial, upright)"
]

VerificationTest[
    LaTeXMathParse[FromCharacterCode[16^^211D]],
    LaTeXMathParse["\\mathbb{R}"],
    TestID -> "LaTeX: pasted pre-styled letter == its macro (raw double-struck R == \\mathbb{R})"
]


(* === fractions, roots, sub/super === *)

VerificationTest[
    LaTeXMathParse["\\frac{a}{b}"],
    FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]],
    TestID -> "LaTeX: \\frac{a}{b}"
]

VerificationTest[
    LaTeXMathParse["\\sqrt{x}"],
    SqrtBox[StyleBox["x", "TI"]],
    TestID -> "LaTeX: \\sqrt{x}"
]

VerificationTest[
    LaTeXMathParse["\\sqrt[3]{x}"],
    RadicalBox[StyleBox["x", "TI"], "3"],
    TestID -> "LaTeX: \\sqrt[3]{x}"
]

VerificationTest[
    LaTeXMathParse["x^2"],
    SuperscriptBox[StyleBox["x", "TI"], "2"],
    TestID -> "LaTeX: x^2"
]

VerificationTest[
    LaTeXMathParse["x_i"],
    SubscriptBox[StyleBox["x", "TI"], StyleBox["i", "TI"]],
    TestID -> "LaTeX: x_i"
]


(* === big operators === *)

VerificationTest[
    LaTeXMathParse["\\sum"],
    "\[Sum]",
    TestID -> "LaTeX: \\sum bare"
]

VerificationTest[
    LaTeXMathParse["\\int"],
    "\[Integral]",
    TestID -> "LaTeX: \\int bare"
]


(* === named symbols === *)

VerificationTest[
    LaTeXMathParse["x \\leq y"],
    RowBox[{StyleBox["x", "TI"], "\[LessEqual]", StyleBox["y", "TI"]}],
    TestID -> "LaTeX: \\leq lowered to LessEqual"
]

VerificationTest[
    LaTeXMathParse["x \\in \\mathbb{R}"],
    RowBox[{StyleBox["x", "TI"], "\[Element]", FromCharacterCode[16^^211D]}],
    TestID -> "LaTeX: \\in + \\mathbb compose"
]


(* === complex compositions === *)

VerificationTest[
    LaTeXMathParse["\\sum_{n=0}^{\\infty} \\frac{1}{n^2}"],
    RowBox[{
        (* limits-stacking operators (\sum, \prod, \bigcup, ...) get
           their bounds stacked above/below in display style, matching
           KaTeX.  Integrals are the exception - they keep side bounds. *)
        UnderoverscriptBox["\[Sum]",
            RowBox[{StyleBox["n", "TI"], "=", "0"}],
            "\[Infinity]", LimitsPositioning -> False
        ],
        FractionBox["1", SuperscriptBox[StyleBox["n", "TI"], "2"]]
    }],
    TestID -> "LaTeX: Basel sum"
]

VerificationTest[
    LaTeXMathParse["e^{-x^2}"],
    SuperscriptBox[
        StyleBox["e", "TI"],
        RowBox[{"-", SuperscriptBox[StyleBox["x", "TI"], "2"]}]
    ],
    TestID -> "LaTeX: e^{-x^2} (unary minus inside exponent)"
]

VerificationTest[
    LaTeXMathParse["f(x) = x^2 + 1"],
    RowBox[{
        StyleBox["f", "TI"], StyleBox["(", SpanMaxSize -> 1], StyleBox["x", "TI"], StyleBox[")", SpanMaxSize -> 1],
        "=", SuperscriptBox[StyleBox["x", "TI"], "2"], "+", "1"
    }],
    TestID -> "LaTeX: f(x) = x^2 + 1"
]


(* === unknown commands fall back to literal === *)

VerificationTest[
    LaTeXMathParse["\\unknownmacro"],
    RowBox[{"\\unknownmacro"}],
    TestID -> "LaTeX: unknown command falls back to literal RowBox"
]


(* === failures === *)

VerificationTest[
    MatchQ[LaTeXMathParse["{unclosed"], _Failure],
    True,
    TestID -> "LaTeX: unclosed brace returns ParseError"
]


(* === division === *)

(* `/` is rendered as a slash operator (inline), NOT as a stacked
   FractionBox - that's `\frac{a}{b}`'s job.  Matches KaTeX's default. *)
VerificationTest[
    LaTeXMathParse["1/2"],
    RowBox[{"1", "/", "2"}],
    TestID -> "LaTeX: `/` renders as inline slash, not a stacked fraction"
]

VerificationTest[
    LaTeXMathParse["1/49 = 1/7^2"],
    RowBox[{"1", "/", "49", "=", "1", "/", SuperscriptBox["7", "2"]}],
    TestID -> "LaTeX: `/` with relations stays inline"
]

VerificationTest[
    LaTeXMathParse["\\frac{1}{2}"],
    FractionBox["1", "2"],
    TestID -> "LaTeX: `\\frac{a}{b}` builds a FractionBox"
]


(* === absolute-value / norm bars === *)

VerificationTest[
    (* the bars are the FE's matchfix bracketing-bar characters, which hug
       and stretch to the content like LaTeX instead of getting "|"'s looser
       relation spacing.  The trailing VeryThinSpace is italic correction -
       an italic x leans into the right bar, so a 1-mu space rebalances it
       (upright content gets none; see endsItalicQ in Kernel/LaTeX.wl). *)
    LaTeXMathParse["|x|"],
    RowBox[{"\[LeftBracketingBar]", StyleBox["x", "TI"], "\[VeryThinSpace]", "\[RightBracketingBar]"}],
    TestID -> "LaTeX: absolute-value bars"
]

VerificationTest[
    LaTeXMathParse["|x|_p"],
    SubscriptBox[
        RowBox[{"\[LeftBracketingBar]", StyleBox["x", "TI"], "\[VeryThinSpace]", "\[RightBracketingBar]"}],
        StyleBox["p", "TI"]],
    TestID -> "LaTeX: norm bars with subscript"
]

VerificationTest[
    (* \| renders a double-bar glyph; \|v\| is a plain row (no matchfix
       grouping - see the note in Kernel/LaTeX.wl on why norm isn't an
       atom). The point of this test is that \| no longer ParseErrors. *)
    LaTeXMathParse["\\|v\\|"],
    RowBox[{"\[DoubleVerticalBar]", StyleBox["v", "TI"], "\[DoubleVerticalBar]"}],
    TestID -> "LaTeX: \\| ... \\| norm bars render (no error)"
]

(* === named matchfix bracket pairs (kerned, content grouped inside) === *)

VerificationTest[
    (* \lceil..\rceil is a real matchfix group, not loose ⌈ x ⌉ tokens (the
       closers are guarded out of commandAtom).  The bracket chars are
       matchfix delimiters, so they hug the content with no kern. *)
    LaTeXMathParse["\\lceil x \\rceil"],
    RowBox[{StyleBox["\[LeftCeiling]", SpanMaxSize -> 1], StyleBox["x", "TI"], "\[VeryThinSpace]", StyleBox["\[RightCeiling]", SpanMaxSize -> 1]}],
    TestID -> "LaTeX: \\lceil ... \\rceil matchfix"
]

VerificationTest[
    (* the comma list lives INSIDE the angle brackets (one group), not
       bound to a single operand as before. *)
    LaTeXMathParse["\\langle a, b \\rangle"],
    RowBox[{
        StyleBox["\[LeftAngleBracket]", SpanMaxSize -> 1],
        RowBox[{StyleBox["a", "TI"], ",", StyleBox["b", "TI"]}],
        "\[VeryThinSpace]",
        StyleBox["\[RightAngleBracket]", SpanMaxSize -> 1]
    }],
    TestID -> "LaTeX: \\langle ... \\rangle groups its content"
]

VerificationTest[
    (* \lVert..\rVert is the proper norm: matchfix double bracketing bars *)
    LaTeXMathParse["\\lVert v \\rVert"],
    RowBox[{StyleBox["\[LeftDoubleBracketingBar]", SpanMaxSize -> 1], StyleBox["v", "TI"], "\[VeryThinSpace]", StyleBox["\[RightDoubleBracketingBar]", SpanMaxSize -> 1]}],
    TestID -> "LaTeX: \\lVert ... \\rVert norm matchfix"
]

(* A \lvert ... \rangle ket maps to an auto-growing bracketed RowBox (left
   bracketing-bar + right angle), sized to its content rather than fixed. *)
VerificationTest[
    LaTeXMathParse["\\lvert\\psi\\rangle"],
    RowBox[{"\[LeftBracketingBar]", StyleBox["\[Psi]", "TI"], "\[RightAngleBracket]"}],
    TestID -> "dirac: \\lvert\\psi\\rangle -> ket box"
]

(* Integral bounds stack above/below the sign in display style, like sums. *)
VerificationTest[
    LaTeXMathParse["\\int_a^b f"],
    RowBox[{
        UnderoverscriptBox["\[Integral]", StyleBox["a", "TI"], StyleBox["b", "TI"], LimitsPositioning -> False],
        StyleBox["f", "TI"]
    }],
    TestID -> "LaTeX: integral bounds stack above/below"
]

VerificationTest[
    (* an unmatched closer still renders as its glyph (via outerPuncToken),
       not a ParseError *)
    MatchQ[LaTeXMathParse["a \\rangle"], _Failure],
    False,
    TestID -> "LaTeX: unmatched \\rangle does not error"
]


(* === function application spacing === *)

VerificationTest[
    (* a named function gets TeX's thin application space before its
       argument; plain juxtaposition (2x) does not. *)
    LaTeXMathParse["\\sin x"],
    RowBox[{StyleBox["sin", FontSlant -> "Plain"], "\[ThinSpace]", StyleBox["x", "TI"]}],
    TestID -> "LaTeX: \\sin x function-application thin space"
]

VerificationTest[
    LaTeXMathParse["2x"],
    RowBox[{"2", StyleBox["x", "TI"]}],
    TestID -> "LaTeX: plain juxtaposition stays tight (no function space)"
]


(* === negative spaces (the negative mirror of \, \: \;) === *)

VerificationTest[
    LaTeXMathParse["a\\!b"],
    RowBox[{StyleBox["a", "TI"], "\[NegativeThinSpace]", StyleBox["b", "TI"]}],
    TestID -> "LaTeX: \\! negative thin space"
]

VerificationTest[
    {LaTeXMathParse["x\\negmedspace y"], LaTeXMathParse["x\\negthickspace y"]},
    {
        RowBox[{StyleBox["x", "TI"], "\[NegativeMediumSpace]", StyleBox["y", "TI"]}],
        RowBox[{StyleBox["x", "TI"], "\[NegativeThickSpace]", StyleBox["y", "TI"]}]
    },
    TestID -> "LaTeX: \\negmedspace / \\negthickspace"
]


(* === unary signs === *)

VerificationTest[
    LaTeXMathParse["v(0) = +\\infty"],
    RowBox[{StyleBox["v", "TI"], StyleBox["(", SpanMaxSize -> 1], "0", StyleBox[")", SpanMaxSize -> 1], "=", "+", "\[Infinity]"}],
    TestID -> "LaTeX: unary + after relation"
]


(* === commas / colons in sequences and parens === *)

VerificationTest[
    LaTeXMathParse["(a, b, c)"],
    RowBox[{StyleBox["(", SpanMaxSize -> 1], RowBox[{StyleBox["a", "TI"], ",", StyleBox["b", "TI"], ",", StyleBox["c", "TI"]}], StyleBox[")", SpanMaxSize -> 1]}],
    TestID -> "LaTeX: comma-separated tuple in parens"
]

VerificationTest[
    LaTeXMathParse["f(x, y)"],
    RowBox[{StyleBox["f", "TI"], StyleBox["(", SpanMaxSize -> 1], RowBox[{StyleBox["x", "TI"], ",", StyleBox["y", "TI"]}], StyleBox[")", SpanMaxSize -> 1]}],
    TestID -> "LaTeX: function of two args"
]

VerificationTest[
    (* every math comma is a bare `,` - the FE supplies punctuation spacing
       (a small gap after, none before) at whatever script size applies. *)
    LaTeXMathParse["a_{i,j}"],
    SubscriptBox[StyleBox["a", "TI"], RowBox[{StyleBox["i", "TI"], ",", StyleBox["j", "TI"]}]],
    TestID -> "LaTeX: comma in a subscript is tight"
]


(* === named symbols / commands added in the bugfix pass === *)

VerificationTest[
    LaTeXMathParse["a \\colon b"],
    RowBox[{StyleBox["a", "TI"], ":", StyleBox["b", "TI"]}],
    TestID -> "LaTeX: \\colon"
]

VerificationTest[
    LaTeXMathParse["\\max"],
    StyleBox["max", FontSlant -> "Plain"],
    TestID -> "LaTeX: \\max upright operator"
]

VerificationTest[
    LaTeXMathParse["\\{1, 2\\}"],
    RowBox[{RowBox[{"{", "1"}], ",", RowBox[{"2", "}"}]}],
    TestID -> "LaTeX: escaped braces \\{ \\}"
]

VerificationTest[
    LaTeXMathParse["a \\cdot b"],
    (* `\cdot` is U+22C5 CENTER DOT (·), distinct from `\times` (×)
       and `*` (asterisk operator) - KaTeX renders all three with
       different glyphs and so do we now. *)
    RowBox[{StyleBox["a", "TI"], "\[CenterDot]", StyleBox["b", "TI"]}],
    TestID -> "LaTeX: \\cdot visible product"
]

VerificationTest[
    LaTeXMathParse["\\ldots"],
    "\[Ellipsis]",
    TestID -> "LaTeX: \\ldots ellipsis"
]


(* === the full PAdic-style corpus parses without ParseError === *)

VerificationTest[
    AllTrue[
        {
            "\\mathbb{Q}", "\\mathbb{R}", "|x|_p", "\\mathbb{Q}_p",
            "v_p \\colon \\mathbb{Q}^\\times \\to \\mathbb{Z}",
            "v_p(0) = +\\infty", "1/49 = 1/7^2",
            "v_p(xy) = v_p(x) + v_p(y)", "|x|_p = p^{-v_p(x)}",
            "v_p(n) = \\max\\{e \\ge 0 : p^e \\mid n\\}",
            "\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}",
            "\\lim_{n \\to \\infty} a_n", "f(x, y) = x^2 + y^2",
            "|x + y|_p \\leq \\max(|x|_p, |y|_p)",
            "\\mathbb{Q}_p \\setminus \\mathbb{Z}_p"
        },
        ! MatchQ[LaTeXMathParse[#], _Failure] &
    ],
    True,
    TestID -> "LaTeX: full PAdic corpus parses without error"
]


(* ============================================================
   KaTeX-coverage tests (modelled on the KaTeX support table,
   https://katex.org/docs/support_table.html). Grouped by the same
   categories KaTeX documents: accents, fonts, fractions/binomials,
   delimiters & sizing, operators, relations, arrows, big operators,
   over/under decorations, modular arithmetic, and symbols.
   ============================================================ *)

(* === accents === *)

VerificationTest[
    LaTeXMathParse["\\hat{x}"],
    OverscriptBox[StyleBox["x", "TI"], "^"],
    TestID -> "KaTeX accents: \\hat{x}"
]

VerificationTest[
    LaTeXMathParse["\\vec{v}"],
    OverscriptBox[StyleBox["v", "TI"], "\[RightVector]"],
    TestID -> "KaTeX accents: \\vec{v}"
]

VerificationTest[
    LaTeXMathParse["\\overline{AB}"],
    OverscriptBox[
        StyleBox[RowBox[{StyleBox["A", "TI"], StyleBox["B", "TI"]}], AutoSpacing -> False],
        "_"],
    TestID -> "KaTeX accents: \\overline spans its arg"
]

VerificationTest[
    LaTeXMathParse["\\underline{x}"],
    UnderscriptBox[StyleBox["x", "TI"], "_"],
    TestID -> "KaTeX accents: \\underline"
]


(* === fonts === *)

(* `\mathsf` / `\mathtt` / `\mathrm` / `\mathbf` strip the per-letter
   italic styling that identAtom puts on math letters by default - in
   TeX these macros switch to upright text faces. *)
VerificationTest[
    LaTeXMathParse["\\mathsf{X}"],
    StyleBox["X", FontFamily -> "Helvetica", FontSlant -> "Plain"],
    TestID -> "KaTeX fonts: \\mathsf"
]

VerificationTest[
    LaTeXMathParse["\\mathtt{x}"],
    StyleBox["x", FontFamily -> "Courier", FontSlant -> "Plain"],
    TestID -> "KaTeX fonts: \\mathtt"
]


(* === fractions & binomials === *)

VerificationTest[
    LaTeXMathParse["\\dfrac{a}{b}"],
    FractionBox[StyleBox["a", "TI"], StyleBox["b", "TI"]],
    TestID -> "KaTeX fractions: \\dfrac"
]

VerificationTest[
    LaTeXMathParse["\\binom{n}{k}"],
    TemplateBox[{StyleBox["n", "TI"], StyleBox["k", "TI"]}, "Binomial"],
    TestID -> "KaTeX binomials: \\binom"
]


(* === delimiters & sizing (\left \right \big stripped) === *)

VerificationTest[
    LaTeXMathParse["\\left( x \\right)"],
    RowBox[{"(", StyleBox["x", "TI"], ")"}],
    TestID -> "KaTeX delimiters: \\left( ... \\right) sizing stripped"
]

VerificationTest[
    (* \bigl / \bigr keep the delimiter glyph AND size it (1.2x for the
       \big level). A matched pair is two sized standalone glyphs around
       the content; an unmatched opener renders the same way via the
       grammar's bare-delimiter fallback. *)
    LaTeXMathParse["\\bigl( a \\bigr)"],
    RowBox[{
        StyleBox["(", FontSize -> 1.2 Inherited],
        StyleBox["a", "TI"],
        StyleBox[")", FontSize -> 1.2 Inherited]
    }],
    TestID -> "KaTeX delimiters: \\bigl ... \\bigr keep + size their delim"
]

VerificationTest[
    (* unmatched \big( in a superscript: sized paren stays visible *)
    LaTeXMathParse["x^{\\big(}"],
    SuperscriptBox[StyleBox["x", "TI"], StyleBox["(", FontSize -> 1.2 Inherited]],
    TestID -> "KaTeX delimiters: unmatched \\big( renders sized paren"
]

VerificationTest[
    (* \Big\uparrow: arrow glyph, sized up at the \Big level (1.8x) *)
    LaTeXMathParse["a_{\\Big\\uparrow}"],
    SubscriptBox[StyleBox["a", "TI"], StyleBox["\[UpArrow]", FontSize -> 1.8 Inherited]],
    TestID -> "KaTeX delimiters: \\Big\\uparrow sizes the arrow"
]

(* --- issue #26: scripts on bare-sign tokens and closing delimiters --- *)

VerificationTest[
    (* a bare sign as a script argument: \sigma_- is the same subscript as
       \sigma_{-} (TeX's "_ takes any single token") *)
    LaTeXMathParse["\\sigma_-"],
    SubscriptBox[StyleBox["\[Sigma]", "TI"], "-"],
    TestID -> "scripts: bare-sign subscript \\sigma_- = \\sigma_{-}"
]

VerificationTest[
    (* the braced form must be identical - localizes the fix to the bare case *)
    LaTeXMathParse["\\sigma_-"] === LaTeXMathParse["\\sigma_{-}"],
    True,
    TestID -> "scripts: \\sigma_- identical to braced \\sigma_{-}"
]

VerificationTest[
    LaTeXMathParse["a^-"],
    SuperscriptBox[StyleBox["a", "TI"], "-"],
    TestID -> "scripts: bare-sign superscript a^-"
]

VerificationTest[
    LaTeXMathParse["x_*"],
    SubscriptBox[StyleBox["x", "TI"], "*"],
    TestID -> "scripts: bare-star subscript x_*"
]

VerificationTest[
    (* an unmatched \rangle with no script still renders as the bare glyph
       (attachScripts with empty posts is a no-op; no Dirac opener, so the
       templatize pass leaves it alone) *)
    LaTeXMathParse["\\rangle"],
    StyleBox["\[RightAngleBracket]", SpanMaxSize -> 1],
    TestID -> "scripts: bare \\rangle unchanged (empty postfix is a no-op)"
]

(* --- Dirac bra/ket -> auto-growing bracketed RowBoxes (content-sized) --- *)

VerificationTest[
    LaTeXMathParse["|01\\rangle"],
    RowBox[{"\[LeftBracketingBar]", "01", "\[RightAngleBracket]"}],
    TestID -> "dirac: ket |01> -> ket box"
]

VerificationTest[
    LaTeXMathParse["\\langle\\phi|\\psi\\rangle"],
    RowBox[{"\[LeftAngleBracket]", StyleBox["\[Phi]", "TI"], "\[RightBracketingBar]", StyleBox["\[Psi]", "TI"], "\[RightAngleBracket]"}],
    TestID -> "dirac: braket <phi|psi> -> braket box"
]

VerificationTest[
    (* operator sandwich decomposes to bra ... ket *)
    LaTeXMathParse["\\langle\\psi|H|\\psi\\rangle"],
    RowBox[{
        RowBox[{"\[LeftAngleBracket]", StyleBox["\[Psi]", "TI"], "\[RightBracketingBar]"}],
        StyleBox["H", "TI"],
        RowBox[{"\[LeftBracketingBar]", StyleBox["\[Psi]", "TI"], "\[RightAngleBracket]"}]}],
    TestID -> "dirac: sandwich <psi|H|psi> -> bra H ket"
]

VerificationTest[
    (* a power on the ket lifts onto the whole bracketed box *)
    LaTeXMathParse["|0\\rangle^{\\otimes 10}"],
    SuperscriptBox[RowBox[{"\[LeftBracketingBar]", "0", "\[RightAngleBracket]"}], RowBox[{"\[CircleTimes]", "10"}]],
    TestID -> "dirac: ket power |0>^{\\otimes 10}"
]

VerificationTest[
    (* a power on the bra's closing bar lifts onto the box *)
    LaTeXMathParse["\\langle 1|^{2}"],
    SuperscriptBox[RowBox[{"\[LeftAngleBracket]", "1", "\[RightBracketingBar]"}], "2"],
    TestID -> "dirac: bra power <1|^2"
]

VerificationTest[
    (* a subsystem label (subscript) on a ket *)
    LaTeXMathParse["|\\psi\\rangle_{AB}"],
    SubscriptBox[RowBox[{"\[LeftBracketingBar]", StyleBox["\[Psi]", "TI"], "\[RightAngleBracket]"}],
        RowBox[{StyleBox["A", "TI"], StyleBox["B", "TI"]}]],
    TestID -> "dirac: labeled ket |psi>_{AB}"
]

VerificationTest[
    (* \bigcup must NOT be mangled by the \big stripper *)
    LaTeXMathParse["\\bigcup"],
    "\[Union]",
    TestID -> "KaTeX delimiters: \\bigcup survives the \\big stripper"
]


(* === modular arithmetic === *)

VerificationTest[
    LaTeXMathParse["a \\equiv b \\pmod{p}"],
    RowBox[{
        StyleBox["a", "TI"], "\[Congruent]", StyleBox["b", "TI"],
        "(", StyleBox["mod", FontSlant -> "Plain"], " ", StyleBox["p", "TI"], ")"
    }],
    TestID -> "KaTeX modular: a \\equiv b \\pmod{p}"
]


(* === operators / relations / arrows / symbols parse clean === *)

VerificationTest[
    AllTrue[
        {
            "a \\div b", "x \\wedge y", "p \\vee q", "A \\sqsubseteq B",
            "x \\preceq y", "a \\parallel b", "x \\perp y", "a \\asymp b",
            "x \\prec y", "A \\supseteq B", "x \\ni y",
            "a \\gets b", "x \\leftrightarrow y", "P \\Leftrightarrow Q",
            "x \\longrightarrow y", "a \\hookrightarrow b",
            "P \\implies Q", "P \\impliedby Q", "P \\iff Q",
            "\\therefore x", "\\because y",
            "\\bigcup_{i=1}^n A_i", "\\bigcap_i B_i", "\\bigoplus_k V_k",
            "\\nexists x", "\\top", "\\bot", "\\angle ABC",
            "\\ell", "\\wp", "\\hbar", "\\aleph_0",
            "\\flat", "\\sharp", "\\clubsuit",
            "\\mathring{a}", "\\check{x}", "\\breve{u}", "\\acute{e}", "\\grave{a}",
            "\\widetilde{xy}", "\\overrightarrow{AB}",
            "\\operatorname{lcm}(a, b)", "x \\simeq y", "a \\doteq b"
        },
        ! MatchQ[LaTeXMathParse[#], _Failure] &
    ],
    True,
    TestID -> "KaTeX coverage: operators / relations / arrows / symbols parse clean"
]


(* === diagonal arrows, harpoons, hook / squiggle / two-headed / dashed ===
   Diagonal arrows and harpoons map to Wolfram named chars; the rest have no
   named char and use the raw Unicode arrow codepoint. *)
VerificationTest[
    LaTeXMathParse /@ {
        "\\nearrow", "\\searrow", "\\swarrow", "\\nwarrow",
        "\\leftharpoonup", "\\leftharpoondown", "\\rightharpoonup", "\\rightharpoondown",
        "\\rightleftharpoons", "\\leftrightharpoons",
        "\\hookrightarrow", "\\hookleftarrow", "\\rightsquigarrow", "\\leadsto",
        "\\twoheadrightarrow", "\\twoheadleftarrow", "\\dashrightarrow", "\\dashleftarrow"
    },
    {
        "\[UpperRightArrow]", "\[LowerRightArrow]", "\[LowerLeftArrow]", "\[UpperLeftArrow]",
        "\[LeftVector]", "\[DownLeftVector]", "\[RightVector]", "\[DownRightVector]",
        "\[Equilibrium]", "\[ReverseEquilibrium]",
        "\:21aa", "\:21a9", "\:21dd", "\:21dd",
        "\:21a0", "\:219e", "\:21e2", "\:21e0"
    },
    TestID -> "KaTeX arrows: diagonal / harpoon / hook / squiggle / two-head / dashed glyphs"
]


(* === sub/superscript order + primes (KaTeX Exponents / Prime cases) === *)

VerificationTest[
    LaTeXMathParse["x_i^2"],
    SubsuperscriptBox[StyleBox["x", "TI"], StyleBox["i", "TI"], "2"],
    TestID -> "KaTeX scripts: x_i^2"
]

VerificationTest[
    LaTeXMathParse["x^2_i"],
    SubsuperscriptBox[StyleBox["x", "TI"], StyleBox["i", "TI"], "2"],
    TestID -> "KaTeX scripts: x^2_i (super-before-sub, same result)"
]

VerificationTest[
    LaTeXMathParse["f'"],
    SuperscriptBox[StyleBox["f", "TI"], "\[Prime]"],
    TestID -> "KaTeX primes: f'"
]

VerificationTest[
    LaTeXMathParse["x''"],
    SuperscriptBox[StyleBox["x", "TI"], "\[DoublePrime]"],
    TestID -> "KaTeX primes: x'' (double)"
]

VerificationTest[
    ! MatchQ[LaTeXMathParse["x'^2_3"], _Failure],
    True,
    TestID -> "KaTeX primes: x'^2_3 (prime + super + sub interleaved)"
]


(* === stackrel / overset / underset === *)

VerificationTest[
    LaTeXMathParse["\\stackrel{a}{x}"],
    OverscriptBox[StyleBox["x", "TI"], StyleBox["a", "TI"]],
    TestID -> "KaTeX stackrel: \\stackrel{top}{base}"
]


(* === robustness: malformed input fails cleanly, never recurses === *)

VerificationTest[
    MatchQ[LaTeXMathParse["\\"], _Failure],
    True,
    TestID -> "Robustness: lone backslash returns ParseError (no infinite recursion)"
]

VerificationTest[
    (* Top-level \\ is a tolerated line break (renders empty); the point
       of this test is just that it terminates, not that it errors. *)
    MatchQ[
        TimeConstrained[LaTeXMathParse["a\\\\b"], 5, $TimedOut],
        Except[$TimedOut]
    ],
    True,
    TestID -> "Robustness: row-break \\\\ parses cleanly (no infinite recursion)"
]

VerificationTest[
    (* a genuinely unsupported macro mid-expression must fail cleanly,
       not recurse / segfault *)
    MatchQ[
        TimeConstrained[LaTeXMathParse["a \\smash{b} \\notarealmacro{"], 5, $TimedOut],
        _Failure
    ],
    True,
    TestID -> "Robustness: malformed / unsupported input returns ParseError (no recursion)"
]


(* === KaTeX screenshotter corpus coverage ===
   The full inline corpus from KaTeX's own screenshot test data, vendored
   verbatim as Tests/katex-cases.json (test/screenshotter/ss_data.yaml,
   with each entry's TeX extracted). We don't render every LaTeX corner -
   text-mode sublexing (\verb, smart quotes, accented \i), \mathop /
   \mathrel / \limits, \big delimiter sizing, \smash, \kern, htmlId /
   includegraphics, and the more exotic environments (CD, subarray,
   substack) are genuinely out of scope for a doc-math parser. The
   floor below asserts the count of cases that DO parse without error,
   so a regression here is loud. Raising it is welcome - just bump the
   number once you've made more pass. *)

VerificationTest[
    With[{
        cases = Association @ Import[
            FileNameJoin[{DirectoryName[$TestFileName], "katex-cases.json"}]
        ]
    },
        Count[Values[cases], _ ? (! MatchQ[LaTeXMathParse[#], _Failure] &)]
    ],
    126,
    TestID -> "KaTeX corpus: all 126 inline cases parse clean"
]


(* === environments / matrices === *)

VerificationTest[
    LaTeXMathParse["\\begin{matrix} a & b \\\\ c & d \\end{matrix}"],
    GridBox[{
        {StyleBox["a", "TI"], StyleBox["b", "TI"]},
        {StyleBox["c", "TI"], StyleBox["d", "TI"]}
    }],
    TestID -> "Env: matrix -> bare GridBox"
]

VerificationTest[
    LaTeXMathParse["\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}"],
    RowBox[{"(", GridBox[{{"1", "2"}, {"3", "4"}}], ")"}],
    TestID -> "Env: pmatrix -> parenthesised GridBox"
]

VerificationTest[
    LaTeXMathParse["\\begin{bmatrix} x \\\\ y \\end{bmatrix}"],
    RowBox[{"[", GridBox[{{StyleBox["x", "TI"]}, {StyleBox["y", "TI"]}}], "]"}],
    TestID -> "Env: bmatrix -> bracketed GridBox"
]

VerificationTest[
    LaTeXMathParse["\\begin{vmatrix} a & b \\\\ c & d \\end{vmatrix}"],
    RowBox[{"\[LeftBracketingBar]", GridBox[{{StyleBox["a", "TI"], StyleBox["b", "TI"]}, {StyleBox["c", "TI"], StyleBox["d", "TI"]}}], "\[RightBracketingBar]"}],
    TestID -> "Env: vmatrix -> bar-delimited GridBox"
]

VerificationTest[
    ! MatchQ[LaTeXMathParse["\\begin{cases} 1 & x > 0 \\\\ 0 & x \\le 0 \\end{cases}"], _Failure],
    True,
    TestID -> "Env: cases parses"
]

VerificationTest[
    (* ragged rows pad to a rectangle *)
    LaTeXMathParse["\\begin{matrix} a & b \\\\ c \\end{matrix}"],
    GridBox[{{StyleBox["a", "TI"], StyleBox["b", "TI"]}, {StyleBox["c", "TI"], ""}}],
    TestID -> "Env: ragged rows padded to rectangle"
]

VerificationTest[
    (* \begin{array}{cc} - the column spec is consumed and ignored *)
    ! MatchQ[LaTeXMathParse["\\begin{array}{cc} a & b \\\\ c & d \\end{array}"], _Failure],
    True,
    TestID -> "Env: array column spec consumed"
]


(* === wildcard-bug regression (StringMatchQ metacharacters) === *)

VerificationTest[
    {
        MatchQ[Parse[ParseCharacter["*"], "x"], _Failure],
        Parse[ParseCharacter["*"], "*"]
    },
    {True, "*"},
    TestID -> "Regression: ParseCharacter[\"*\"] matches literal * only (not wildcard)"
]


(* === LaTeXMathStyle: Computer-Modern restyling of parser output === *)

VerificationTest[
    (* a text font: "TI" letters get FontSlant -> Italic, all wrapped in the family *)
    LaTeXMathStyle[StyleBox["x", "TI"], "CMU Serif"],
    StyleBox[StyleBox["x", FontSlant -> Italic], FontFamily -> "CMU Serif"],
    TestID -> "LaTeXMathStyle: text font uses FontSlant"
]

VerificationTest[
    (* an OpenType *math* font: "TI" letters become their math-italic codepoint *)
    LaTeXMathStyle[StyleBox["x", "TI"], "Latin Modern Math"],
    StyleBox[StyleBox[FromCharacterCode[16^^1D465]], FontFamily -> "Latin Modern Math"],
    TestID -> "LaTeXMathStyle: math font remaps to math-italic codepoint"
]

VerificationTest[
    (* None (no CM font) leaves the boxes untouched *)
    LaTeXMathStyle[StyleBox["x", "TI"], None],
    StyleBox["x", "TI"],
    TestID -> "LaTeXMathStyle: None is a no-op"
]

VerificationTest[
    (* a parse Failure passes straight through *)
    With[{f = LaTeXMathParse["{unclosed"]}, LaTeXMathStyle[f, "Latin Modern Math"] === f],
    True,
    TestID -> "LaTeXMathStyle: Failure passes through"
]

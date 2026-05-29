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
            "\[Infinity]"
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
        StyleBox["f", "TI"], "(", StyleBox["x", "TI"], ")",
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
    MatchQ[LaTeXMathParse["{unclosed"], _ParseError],
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
    (* the bars are kerned toward the content (AdjustmentBox negative
       margin) so they hug it the way LaTeX does, instead of getting the
       FE's looser relation spacing. *)
    LaTeXMathParse["|x|"],
    RowBox[{
        AdjustmentBox["|", BoxMargins -> {{0, -0.2}, {0, 0}}],
        StyleBox["x", "TI"],
        AdjustmentBox["|", BoxMargins -> {{-0.2, 0}, {0, 0}}]
    }],
    TestID -> "LaTeX: absolute-value bars"
]

VerificationTest[
    LaTeXMathParse["|x|_p"],
    SubscriptBox[
        RowBox[{
            AdjustmentBox["|", BoxMargins -> {{0, -0.2}, {0, 0}}],
            StyleBox["x", "TI"],
            AdjustmentBox["|", BoxMargins -> {{-0.2, 0}, {0, 0}}]
        }],
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


(* === unary signs === *)

VerificationTest[
    LaTeXMathParse["v(0) = +\\infty"],
    RowBox[{StyleBox["v", "TI"], "(", "0", ")", "=", "+", "\[Infinity]"}],
    TestID -> "LaTeX: unary + after relation"
]


(* === commas / colons in sequences and parens === *)

VerificationTest[
    LaTeXMathParse["(a, b, c)"],
    RowBox[{"(", RowBox[{StyleBox["a", "TI"], "," <> "\[ThinSpace]", StyleBox["b", "TI"], "," <> "\[ThinSpace]", StyleBox["c", "TI"]}], ")"}],
    TestID -> "LaTeX: comma-separated tuple in parens"
]

VerificationTest[
    LaTeXMathParse["f(x, y)"],
    RowBox[{StyleBox["f", "TI"], "(", RowBox[{StyleBox["x", "TI"], "," <> "\[ThinSpace]", StyleBox["y", "TI"]}], ")"}],
    TestID -> "LaTeX: function of two args"
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
    RowBox[{RowBox[{"{", "1"}], "," <> "\[ThinSpace]", RowBox[{"2", "}"}]}],
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
        ! MatchQ[LaTeXMathParse[#], _ParseError] &
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
    OverscriptBox[RowBox[{StyleBox["A", "TI"], StyleBox["B", "TI"]}], "_"],
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
    RowBox[{"(", GridBox[{{StyleBox["n", "TI"]}, {StyleBox["k", "TI"]}}], ")"}],
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
        StyleBox["(", Magnification -> 1.2],
        StyleBox["a", "TI"],
        StyleBox[")", Magnification -> 1.2]
    }],
    TestID -> "KaTeX delimiters: \\bigl ... \\bigr keep + size their delim"
]

VerificationTest[
    (* unmatched \big( in a superscript: sized paren stays visible *)
    LaTeXMathParse["x^{\\big(}"],
    SuperscriptBox[StyleBox["x", "TI"], StyleBox["(", Magnification -> 1.2]],
    TestID -> "KaTeX delimiters: unmatched \\big( renders sized paren"
]

VerificationTest[
    (* \Big\uparrow: arrow glyph, sized up at the \Big level (1.8x) *)
    LaTeXMathParse["a_{\\Big\\uparrow}"],
    SubscriptBox[StyleBox["a", "TI"], StyleBox["\[UpArrow]", Magnification -> 1.8]],
    TestID -> "KaTeX delimiters: \\Big\\uparrow sizes the arrow"
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
        ! MatchQ[LaTeXMathParse[#], _ParseError] &
    ],
    True,
    TestID -> "KaTeX coverage: operators / relations / arrows / symbols parse clean"
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
    ! MatchQ[LaTeXMathParse["x'^2_3"], _ParseError],
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
    MatchQ[LaTeXMathParse["\\"], _ParseError],
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
        _ParseError
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
        Count[Values[cases], _ ? (! MatchQ[LaTeXMathParse[#], _ParseError] &)]
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
    RowBox[{"|", GridBox[{{StyleBox["a", "TI"], StyleBox["b", "TI"]}, {StyleBox["c", "TI"], StyleBox["d", "TI"]}}], "|"}],
    TestID -> "Env: vmatrix -> bar-delimited GridBox"
]

VerificationTest[
    ! MatchQ[LaTeXMathParse["\\begin{cases} 1 & x > 0 \\\\ 0 & x \\le 0 \\end{cases}"], _ParseError],
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
    ! MatchQ[LaTeXMathParse["\\begin{array}{cc} a & b \\\\ c & d \\end{array}"], _ParseError],
    True,
    TestID -> "Env: array column spec consumed"
]


(* === wildcard-bug regression (StringMatchQ metacharacters) === *)

VerificationTest[
    {
        MatchQ[Parse[ParseCharacter["*"], "x"], _ParseError],
        Parse[ParseCharacter["*"], "*"]
    },
    {True, "*"},
    TestID -> "Regression: ParseCharacter[\"*\"] matches literal * only (not wildcard)"
]

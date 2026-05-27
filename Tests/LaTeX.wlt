(* :Title: tests-latex.wlt - LaTeX math parser test suite *)
(* :Context: Wolfram`Parser`LaTeX` *)

Needs["Wolfram`Parser`"]
Needs["Wolfram`Parser`LaTeX`"]


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

VerificationTest[
    LaTeXMathParse["\\mathbb{R}"],
    "\[DoubleStruckCapitalR]",
    TestID -> "LaTeX: \\mathbb{R} -> blackboard R"
]

VerificationTest[
    LaTeXMathParse["\\mathcal{F}"],
    "\[ScriptCapitalF]",
    TestID -> "LaTeX: \\mathcal{F} -> script F"
]

VerificationTest[
    LaTeXMathParse["\\mathfrak{G}"],
    "\[GothicCapitalG]",
    TestID -> "LaTeX: \\mathfrak{G} -> gothic G"
]


(* === Greek letters === *)

VerificationTest[
    LaTeXMathParse["\\alpha"],
    "\[Alpha]",
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
    RowBox[{StyleBox["x", "TI"], "\[Element]", "\[DoubleStruckCapitalR]"}],
    TestID -> "LaTeX: \\in + \\mathbb compose"
]


(* === complex compositions === *)

VerificationTest[
    LaTeXMathParse["\\sum_{n=0}^{\\infty} \\frac{1}{n^2}"],
    RowBox[{
        SubsuperscriptBox["\[Sum]",
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

VerificationTest[
    LaTeXMathParse["1/2"],
    FractionBox["1", "2"],
    TestID -> "LaTeX: inline division -> FractionBox"
]

VerificationTest[
    LaTeXMathParse["1/49 = 1/7^2"],
    RowBox[{FractionBox["1", "49"], "=", FractionBox["1", SuperscriptBox["7", "2"]]}],
    TestID -> "LaTeX: division with relation"
]


(* === absolute-value / norm bars === *)

VerificationTest[
    LaTeXMathParse["|x|"],
    RowBox[{"|", StyleBox["x", "TI"], "|"}],
    TestID -> "LaTeX: absolute-value bars"
]

VerificationTest[
    LaTeXMathParse["|x|_p"],
    SubscriptBox[RowBox[{"|", StyleBox["x", "TI"], "|"}], StyleBox["p", "TI"]],
    TestID -> "LaTeX: norm bars with subscript"
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
    RowBox[{StyleBox["a", "TI"], "\[Times]", StyleBox["b", "TI"]}],
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

VerificationTest[
    LaTeXMathParse["\\mathsf{X}"],
    StyleBox[StyleBox["X", "TI"], FontFamily -> "SansSerif"],
    TestID -> "KaTeX fonts: \\mathsf"
]

VerificationTest[
    LaTeXMathParse["\\mathtt{x}"],
    StyleBox[StyleBox["x", "TI"], FontFamily -> "Courier"],
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
    LaTeXMathParse["\\bigl( a \\bigr)"],
    RowBox[{"(", StyleBox["a", "TI"], ")"}],
    TestID -> "KaTeX delimiters: \\bigl ... \\bigr stripped"
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

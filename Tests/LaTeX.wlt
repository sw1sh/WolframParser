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
        RowBox[{StyleBox["f", "TI"], RowBox[{"(", StyleBox["x", "TI"], ")"}]}],
        "=",
        RowBox[{SuperscriptBox[StyleBox["x", "TI"], "2"], "+", "1"}]
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

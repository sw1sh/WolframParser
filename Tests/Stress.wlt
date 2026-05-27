(* :Title: Stress.wlt - adversarial / pathological inputs *)
(* :Summary:
    A parser must always terminate - on deeply nested, very long, or
    malformed input it should return a result or a clean ParseError,
    never hang or stack-overflow. Every case here runs under a
    TimeConstrained guard; a $TimedOut result fails the test. *)

Needs["Wolfram`Parser`"]

terminates[expr_] := TimeConstrained[expr; True, 15, False]


(* === deep nesting (must recurse to bounded depth, then return) === *)

VerificationTest[
    terminates @ LaTeXMathParse[
        StringJoin[ConstantArray["\\frac{1}{", 30]] <> "x" <> StringJoin[ConstantArray["}", 30]]
    ],
    True,
    TestID -> "Stress: 30-deep nested \\frac terminates"
]

VerificationTest[
    terminates @ LaTeXMathParse[
        StringJoin[ConstantArray["(", 50]] <> "x" <> StringJoin[ConstantArray[")", 50]]
    ],
    True,
    TestID -> "Stress: 50-deep nested parens terminates"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["x^{", 20]] <> "1" <> StringJoin[ConstantArray["}", 20]]],
    True,
    TestID -> "Stress: 20-deep nested superscripts terminates"
]

VerificationTest[
    With[{deep = StringJoin[ConstantArray["{", 60]] <> "a" <> StringJoin[ConstantArray["}", 60]]},
        terminates @ LaTeXMathParse[deep]
    ],
    True,
    TestID -> "Stress: 60-deep nested braces terminates"
]


(* === long flat input === *)

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["1+", 500]] <> "1"],
    True,
    TestID -> "Stress: 1000-token alternating sum terminates"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["\\alpha ", 300]]],
    True,
    TestID -> "Stress: 300 juxtaposed Greek letters terminates"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringRepeat["1234567890", 200]],
    True,
    TestID -> "Stress: 2000-digit run terminates"
]


(* === malformed / adversarial: must NOT hang or crash === *)

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["\\", 500]]],
    True,
    TestID -> "Stress: 500 lone backslashes terminate (no recursion)"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["{", 500]]],
    True,
    TestID -> "Stress: 500 unclosed open-braces terminate"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["}", 500]]],
    True,
    TestID -> "Stress: 500 stray close-braces terminate"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["^", 200]]],
    True,
    TestID -> "Stress: 200 stray carets terminate"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["\\\\", 300]]],
    True,
    TestID -> "Stress: 300 row-breaks outside an environment terminate"
]

VerificationTest[
    terminates @ LaTeXMathParse["\\begin{matrix}" <> StringJoin[ConstantArray["a & ", 100]] <> "b\\end{matrix}"],
    True,
    TestID -> "Stress: 100-column matrix row terminates"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["a & b \\\\ ", 100]] <> "\\end{matrix}"],
    True,
    TestID -> "Stress: unterminated 100-row matrix-ish input terminates"
]

VerificationTest[
    (* random-ish soup of metacharacters and partial commands *)
    terminates @ LaTeXMathParse["\\frac{\\sqrt[}{\\mathbb{|^_&}\\begin{x}\\\\\\end"],
    True,
    TestID -> "Stress: metacharacter soup terminates"
]

VerificationTest[
    terminates @ LaTeXMathParse[StringJoin[ConstantArray["|", 400]]],
    True,
    TestID -> "Stress: 400 stray bars terminate"
]


(* === empty / trivial === *)

VerificationTest[
    MatchQ[LaTeXMathParse[""], _ParseError],
    True,
    TestID -> "Stress: empty string returns ParseError"
]

VerificationTest[
    MatchQ[LaTeXMathParse["   "], _ParseError],
    True,
    TestID -> "Stress: whitespace-only returns ParseError"
]

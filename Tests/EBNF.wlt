(* :Title: EBNF.wlt - tests for the Wolfram`Parser`EBNF` BNF reader. *)

Needs["Wolfram`Parser`"]
Needs["Wolfram`Parser`EBNF`"]


(* ===== EBNFRules: BNF source -> structured rule list ===== *)

VerificationTest[
    EBNFRules["<greeting> ::= hello | bye"] // Length,
    1,
    TestID -> "EBNF: single rule extracted"
]

VerificationTest[
    EBNFRules["
        <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        <number> ::= <digit><digit>*
        <expr>   ::= <number> + <number>
    "] // Length,
    3,
    TestID -> "EBNF: three rules extracted, with non-terminals + repetition + literals"
]

VerificationTest[
    EBNFRules["<arrow> ::= ::- | :::"] // Length,
    1,
    TestID -> "EBNF: arrow-like literal tokens in rule body parse"
]


(* ===== EBNFParse: lower to Association[name -> parser] ===== *)

VerificationTest[
    Module[{g = EBNFParse["<greeting> ::= hello | bye"]},
        Parse[g["greeting"], "hello"]
    ],
    "hello",
    TestID -> "EBNF: parse via lowered rule (literal alternation)"
]

VerificationTest[
    Module[{g = EBNFParse["
        <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        <number> ::= <digit><digit>*
    "]},
        Parse[g["number"], "12345"]
    ],
    {"1", {"2", "3", "4", "5"}},
    TestID -> "EBNF: recursive non-terminal + `*` repetition lower correctly"
]

VerificationTest[
    Module[{g = EBNFParse["
        <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        <number> ::= <digit><digit>*
        <expr>   ::= <number> + <number>
    "]},
        Parse[g["expr"], "12 + 34"]
    ],
    {{"1", {"2"}}, "+", {"3", {"4"}}},
    TestID -> "EBNF: whitespace between literals/non-terminals tolerated automatically"
]


(* ===== TPTP coverage: the full grammar parses ===== *)

VerificationTest[
    Length @ EBNFRules @ Import[
        FileNameJoin[{DirectoryName[$TestFileName], "tptp-bnf.txt"}],
        "Text"
    ],
    354,
    TestID -> "EBNF: TPTPWorld SyntaxBNF-v9.2.1.4 parses to 354 rule records"
]

VerificationTest[
    Module[{
        bnf = Import[
            FileNameJoin[{DirectoryName[$TestFileName], "tptp-bnf.txt"}],
            "Text"
        ],
        primOverrides,
        parsers
    },
        primOverrides = <|
            "lower_word" -> ParseAction[
                ParseCharacter[CharacterRange["a", "z"]] ~~
                    ParseMany[ParseCharacter[
                        CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
                        DigitCharacter | "_"
                    ]],
                StringJoin[#1, StringJoin @ #2] &
            ],
            "upper_word" -> ParseAction[
                ParseCharacter[CharacterRange["A", "Z"]] ~~
                    ParseMany[ParseCharacter[
                        CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
                        DigitCharacter | "_"
                    ]],
                StringJoin[#1, StringJoin @ #2] &
            ],
            "integer" -> ParseAction[
                ParseSome[ParseCharacter[DigitCharacter]],
                StringJoin @ {##} &
            ],
            "single_quoted" -> ParseAction[
                ParseLiteral["'"] ~~
                    ParseMany[ParseCharacter[_?(# =!= "'" &)]] ~~
                    ParseLiteral["'"],
                StringJoin["'", StringJoin @ #2, "'"] &
            ],
            "vline" -> ParseLiteral["|"],
            "star"  -> ParseLiteral["*"],
            "plus"  -> ParseLiteral["+"],
            "arrow" -> ParseLiteral[">"],
            "less_sign" -> ParseLiteral["<"],
            "hash"  -> ParseLiteral["#"],
            "dot"   -> ParseLiteral["."]
        |>;
        parsers = EBNFParse[bnf, "PrimitiveOverrides" -> primOverrides];
        (* A minimal cnf clause from a real TPTP problem: name, role,
           a single-literal formula, terminated by `).`. The output is
           the raw parse tree (no semantic actions); going further to
           the WL-term shape the handwritten TPTPImport returns is a
           v0.2 task of writing the lowering's action functions. *)
        Parse[parsers["cnf_annotated"], "cnf(test, axiom, p)."]
    ],
    {"cnf", "(", "test", ",", "axiom", ",", "p", Null, ")."},
    TestID -> "EBNF: minimal cnf clause parses via auto-generated TPTP parser"
]

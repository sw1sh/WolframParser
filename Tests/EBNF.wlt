(* :Title: EBNF.wlt - tests for the BNF reader in Wolfram`Parser`. *)

Needs["Wolfram`Parser`"]


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
        (* A minimal cnf clause from a real TPTP problem. The output is
           the raw parse tree; the formula slot contains the nested
           `{"p", {}}` because left-recursion elimination of
           `cnf_disjunction` produced a ParseMany whose zero-match
           continuation is `{}`. Going from the raw tree to the WL-term
           shape the handwritten TPTPImport returns is the semantic-
           action layer the lowering does not yet generate. *)
        Parse[parsers["cnf_annotated"], "cnf(test, axiom, p)."]
    ],
    {"cnf", "(", "test", ",", "axiom", ",", {"p", {}}, Null, ")."},
    TestID -> "EBNF: minimal cnf clause parses via auto-generated TPTP parser"
]

VerificationTest[
    Module[{
        bnf = Import[
            FileNameJoin[{DirectoryName[$TestFileName], "tptp-bnf.txt"}],
            "Text"
        ],
        primOverrides, parsers, source
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
            "distinct_object" -> ParseAction[
                ParseLiteral["\""] ~~
                    ParseMany[ParseCharacter[_?(# =!= "\"" &)]] ~~
                    ParseLiteral["\""],
                StringJoin["\"", StringJoin @ #2, "\""] &
            ],
            "dollar_word" -> ParseAction[
                ParseLiteral["$"] ~~ ParseSome[ParseCharacter[
                    CharacterRange["a", "z"] | CharacterRange["A", "Z"] |
                    DigitCharacter | "_"
                ]],
                StringJoin[#1, StringJoin @ #2] &
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
        (* A real-world TPTP problem: group axioms + a commutator
           definition + a conjecture. Five fof clauses with quantifiers,
           function application, and equality - the constructs the
           left-recursion-elimination + longest-alt-first rewrites
           enable. The handwritten TPTPImport on the same input returns
           the lifted WL-term shape; the auto-generated parser here
           still returns the raw parse tree (no actions wired up). *)
        source = "fof(group_assoc, axiom, ! [X, Y, Z] : multiply(multiply(X, Y), Z) = multiply(X, multiply(Y, Z))).
fof(group_left_id, axiom, ! [X] : multiply(identity, X) = X).
fof(group_left_inv, axiom, ! [X] : multiply(inverse(X), X) = identity).
fof(commutator_def, axiom, ! [X, Y] : commutator(X, Y) = multiply(multiply(X, Y), multiply(inverse(X), inverse(Y)))).
fof(goal, conjecture, ! [X] : commutator(X, identity) = identity).";
        Length @ Parse[parsers["TPTP_file"], source]
    ],
    5,
    TestID -> "EBNF: five-clause group-theory TPTP problem parses via auto-generated parser"
]

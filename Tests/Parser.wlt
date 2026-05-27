(* :Title: tests.wlt - WolframParser test suite *)
(* :Context: Wolfram`Parser` *)
(* :Summary:
    VerificationTest entries that exercise every documented behavior of
    the Wolfram`Parser` paclet. Run via run-tests.wls (TestReport-based).
    Each test has a TestID with the shape "Symbol: behavior".
*)


(* === ParserCombinator: constructor wrappers === *)

VerificationTest[
    ParseLiteral["foo"],
    ParserCombinator["Literal", "foo", <||>],
    TestID -> "ParseLiteral: constructor"
]

VerificationTest[
    ParseCharacter[DigitCharacter],
    ParserCombinator["Character", DigitCharacter, <||>],
    TestID -> "ParseCharacter: constructor"
]

VerificationTest[
    ParseSucceed[42],
    ParserCombinator["Succeed", 42, <||>],
    TestID -> "ParseSucceed: constructor"
]

VerificationTest[
    ParseFail["nope"],
    ParserCombinator["Fail", "nope", <||>],
    TestID -> "ParseFail: constructor"
]

VerificationTest[
    ParseSequence[ParseLiteral["foo"]],
    ParserCombinator["Literal", "foo", <||>],
    TestID -> "ParseSequence: single arg unwraps"
]

VerificationTest[
    ParseChoice[ParseLiteral["foo"]],
    ParserCombinator["Literal", "foo", <||>],
    TestID -> "ParseChoice: single arg unwraps"
]


(* === Operator overloads === *)

VerificationTest[
    ParseLiteral["foo"] ~~ ParseLiteral["bar"],
    ParserCombinator["Sequence",
        {ParserCombinator["Literal", "foo", <||>],
         ParserCombinator["Literal", "bar", <||>]},
        <||>],
    TestID -> "Overload ~~: lowers to ParseSequence"
]

VerificationTest[
    ParseLiteral["a"] ~~ ParseLiteral["b"] ~~ ParseLiteral["c"],
    ParserCombinator["Sequence",
        {ParserCombinator["Literal", "a", <||>],
         ParserCombinator["Literal", "b", <||>],
         ParserCombinator["Literal", "c", <||>]},
        <||>],
    TestID -> "Overload ~~: three-element sequence flattens"
]

VerificationTest[
    ParseLiteral["a"] | ParseLiteral["b"],
    ParserCombinator["Choice",
        {ParserCombinator["Literal", "a", <||>],
         ParserCombinator["Literal", "b", <||>]},
        <||>],
    TestID -> "Overload |: lowers to ParseChoice"
]

VerificationTest[
    ParseLiteral["a"] | ParseLiteral["b"] | ParseLiteral["c"],
    ParserCombinator["Choice",
        {ParserCombinator["Literal", "a", <||>],
         ParserCombinator["Literal", "b", <||>],
         ParserCombinator["Literal", "c", <||>]},
        <||>],
    TestID -> "Overload |: three-element choice flattens"
]

VerificationTest[
    ParseLiteral["x"]..,
    ParserCombinator["Some", ParserCombinator["Literal", "x", <||>], <||>],
    TestID -> "Overload ..: lowers to ParseSome"
]

VerificationTest[
    ParseLiteral["x"]...,
    ParserCombinator["Many", ParserCombinator["Literal", "x", <||>], <||>],
    TestID -> "Overload ...: lowers to ParseMany"
]

VerificationTest[
    Optional[ParseLiteral["foo"]],
    ParserCombinator["Optional", ParserCombinator["Literal", "foo", <||>], <||>],
    TestID -> "Overload Optional: lowers to ParseOptional"
]

(* Plain string sequences are NOT hijacked by the ~~ overload *)
VerificationTest[
    MatchQ["foo" ~~ "bar", _ParserCombinator],
    False,
    TestID -> "Overload ~~: plain string sequence is not a ParserCombinator"
]


(* === Parse: terminals === *)

VerificationTest[
    Parse[ParseLiteral["foo"], "foo"],
    "foo",
    TestID -> "Parse Literal: exact match"
]

VerificationTest[
    Parse[ParseCharacter[DigitCharacter], "5"],
    "5",
    TestID -> "Parse Character: digit match"
]

VerificationTest[
    Parse[ParseCharacter[LetterCharacter], "x"],
    "x",
    TestID -> "Parse Character: letter match"
]

VerificationTest[
    Parse[ParseCharacter[CharacterRange["a", "z"]], "m"],
    "m",
    TestID -> "Parse Character: range match"
]

VerificationTest[
    Parse[ParseCharacter[LetterCharacter | DigitCharacter], "7"],
    "7",
    TestID -> "Parse Character: alternation match"
]

VerificationTest[
    Parse[ParseSucceed["always"], ""],
    "always",
    TestID -> "Parse Succeed: returns the constant"
]


(* === Parse: composition === *)

VerificationTest[
    Parse[ParseLiteral["foo"] ~~ ParseLiteral["bar"], "foobar"],
    {"foo", "bar"},
    TestID -> "Parse Sequence: two-piece"
]

VerificationTest[
    Parse[ParseLiteral["a"] ~~ ParseLiteral["b"] ~~ ParseLiteral["c"], "abc"],
    {"a", "b", "c"},
    TestID -> "Parse Sequence: three-piece"
]

VerificationTest[
    Parse[ParseLiteral["foo"] | ParseLiteral["bar"], "bar"],
    "bar",
    TestID -> "Parse Choice: second branch matches"
]

VerificationTest[
    Parse[ParseLiteral["foo"] | ParseLiteral["bar"], "foo"],
    "foo",
    TestID -> "Parse Choice: first branch matches"
]

VerificationTest[
    Parse[
        ParseBetween[ParseLiteral["("], ParseCharacter[LetterCharacter], ParseLiteral[")"]],
        "(x)"
    ],
    "x",
    TestID -> "Parse Between: strips delimiters"
]


(* === Parse: repetition === *)

VerificationTest[
    Parse[ParseCharacter[DigitCharacter].., "123"],
    {"1", "2", "3"},
    TestID -> "Parse Some: three digits"
]

VerificationTest[
    Parse[ParseCharacter[DigitCharacter].., "5"],
    {"5"},
    TestID -> "Parse Some: one digit"
]

VerificationTest[
    Parse[ParseCharacter[DigitCharacter]..., "123"],
    {"1", "2", "3"},
    TestID -> "Parse Many: three digits"
]

VerificationTest[
    Parse[ParseCharacter[DigitCharacter]..., ""],
    {},
    TestID -> "Parse Many: empty input succeeds with {}"
]

VerificationTest[
    Parse[Optional[ParseLiteral["foo"]], "foo"],
    "foo",
    TestID -> "Parse Optional: present"
]

VerificationTest[
    Parse[Optional[ParseLiteral["foo"]], ""],
    Missing["NoMatch"],
    TestID -> "Parse Optional: absent returns Missing"
]

VerificationTest[
    Parse[
        ParseLiteral["a"] ~~ Optional[ParseLiteral["b"]] ~~ ParseLiteral["c"],
        "ac"
    ],
    {"a", Missing["NoMatch"], "c"},
    TestID -> "Parse Optional: absent inside sequence"
]


(* === Parse: action === *)

VerificationTest[
    Parse[
        ParseAction[ParseCharacter[DigitCharacter].., StringJoin],
        "12345"
    ],
    "12345",
    TestID -> "Parse Action: variadic StringJoin"
]

VerificationTest[
    Parse[
        ParseAction[ParseCharacter[DigitCharacter].., FromDigits @ StringJoin[{##}] &],
        "42"
    ],
    42,
    TestID -> "Parse Action: digit list to integer"
]

VerificationTest[
    Parse[ParseAction[ParseLiteral["foo"], Identity], "foo"],
    "foo",
    TestID -> "Parse Action: Identity is the unit"
]


(* === Parse: failures === *)

VerificationTest[
    MatchQ[Parse[ParseLiteral["foo"], "xyz"], _ParseError],
    True,
    TestID -> "Parse Failure: literal mismatch returns ParseError"
]

VerificationTest[
    MatchQ[Parse[ParseLiteral["foo"], "foobar"], _ParseError],
    True,
    TestID -> "Parse Failure: partial match returns ParseError"
]

VerificationTest[
    MatchQ[Parse[ParseSome[ParseCharacter[DigitCharacter]], ""], _ParseError],
    True,
    TestID -> "Parse Failure: ParseSome on empty input"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"][[1]]["Position"],
    1,
    TestID -> "ParseError: Position field"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"][[1]]["Expected"],
    "foo",
    TestID -> "ParseError: Expected field"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"][[1]]["Found"],
    "x",
    TestID -> "ParseError: Found field"
]


(* === ParsePartial === *)

VerificationTest[
    ParsePartial[ParseLiteral["foo"], "foobar"],
    {"foo", "bar"},
    TestID -> "ParsePartial: returns {result, leftover}"
]

VerificationTest[
    ParsePartial[ParseLiteral["foo"], "foo"],
    {"foo", ""},
    TestID -> "ParsePartial: full match leaves empty leftover"
]


(* === SubValue (parser as function) === *)

VerificationTest[
    ParseLiteral["foo"]["foo"],
    "foo",
    TestID -> "SubValue: pc[input] equals Parse[pc, input]"
]

VerificationTest[
    (ParseLiteral["foo"] ~~ ParseLiteral["bar"])["foobar"],
    {"foo", "bar"},
    TestID -> "SubValue: works on composed parsers"
]


(* === ParserCompile (stub) === *)

VerificationTest[
    KeyExistsQ[ParserCompile[ParseLiteral["foo"]][[3]], "Code"],
    True,
    TestID -> "ParserCompile: adds Code key to opts"
]

VerificationTest[
    Head[ParserCompile[ParseLiteral["foo"]]],
    ParserCombinator,
    TestID -> "ParserCompile: returns a ParserCombinator"
]

VerificationTest[
    ParserCompile[ParseLiteral["foo"]][[1]],
    "Literal",
    TestID -> "ParserCompile: preserves the type"
]

VerificationTest[
    ParserCompile[ParseLiteral["foo"]]["foo"],
    "foo",
    TestID -> "ParserCompile: compiled parser runs"
]

VerificationTest[
    With[{p = ParseLiteral["a"] | ParseLiteral["b"]},
        {Parse[p, "a"], ParserCompile[p]["a"]}
    ],
    {"a", "a"},
    TestID -> "ParserCompile: same result as Parse"
]


(* === ParserCombinatorQ === *)

VerificationTest[
    ParserCombinatorQ[ParseLiteral["foo"]],
    True,
    TestID -> "ParserCombinatorQ: True for a constructed PC"
]

VerificationTest[
    ParserCombinatorQ[42],
    False,
    TestID -> "ParserCombinatorQ: False for non-PC"
]

VerificationTest[
    ParserCombinatorQ["foo"],
    False,
    TestID -> "ParserCombinatorQ: False for plain string"
]


(* === A small end-to-end grammar === *)

VerificationTest[
    Parse[
        ParseAction[
            ParseOptional[ParseLiteral["-"]] ~~
                ParseCharacter[DigitCharacter].. ~~
                ParseOptional[ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]..],
            Function[{sign, intPart, fracPart},
                (If[MissingQ[sign], 1, -1]) *
                    ToExpression @ StringJoin[
                        StringJoin[intPart],
                        If[MissingQ[fracPart], "", "." <> StringJoin[fracPart[[2]]]]
                    ]
            ]
        ],
        "-3.14"
    ],
    -3.14,
    TestID -> "End-to-end: signed decimal"
]

VerificationTest[
    Parse[
        ParseBetween[
            ParseLiteral["["],
            ParseAction[
                ParseCharacter[DigitCharacter] ~~
                    (ParseLiteral[","] ~~ ParseCharacter[DigitCharacter])...,
                Function[{first, rest},
                    Prepend[Map[Last, rest], first]
                ]
            ],
            ParseLiteral["]"]
        ],
        "[1,2,3]"
    ],
    {"1", "2", "3"},
    TestID -> "End-to-end: bracketed comma-separated list"
]


(* === ParseSepBy / ParseSepBy1 === *)

VerificationTest[
    Parse[ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], "1,2,3,4"],
    {"1", "2", "3", "4"},
    TestID -> "ParseSepBy: comma-separated digits"
]

VerificationTest[
    Parse[ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], ""],
    {},
    TestID -> "ParseSepBy: empty input succeeds with {}"
]

VerificationTest[
    Parse[ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], "5"],
    {"5"},
    TestID -> "ParseSepBy: single element"
]

VerificationTest[
    MatchQ[Parse[ParseSepBy1[ParseCharacter[DigitCharacter], ParseLiteral[","]], ""], _ParseError],
    True,
    TestID -> "ParseSepBy1: empty input fails"
]

VerificationTest[
    Parse[ParseSepBy1[ParseCharacter[DigitCharacter], ParseLiteral[","]], "1,2"],
    {"1", "2"},
    TestID -> "ParseSepBy1: non-empty succeeds"
]


(* === ParseChainLeft / ParseChainRight === *)

VerificationTest[
    Parse[
        ParseChainLeft[
            ParseAction[ParseSome[ParseCharacter[DigitCharacter]], ToExpression @ StringJoin[{##}] &],
            ParseAction[ParseLiteral["+"], Plus &]
        ],
        "1+2+3+4"
    ],
    10,
    TestID -> "ParseChainLeft: left-associative sum"
]

VerificationTest[
    Parse[
        ParseChainLeft[
            ParseAction[ParseSome[ParseCharacter[DigitCharacter]], ToExpression @ StringJoin[{##}] &],
            ParseAction[ParseLiteral["-"], Subtract &]
        ],
        "10-3-2"
    ],
    5,
    TestID -> "ParseChainLeft: left-associative subtraction (10-3-2 = 5)"
]

VerificationTest[
    Parse[
        ParseChainRight[
            ParseAction[ParseSome[ParseCharacter[DigitCharacter]], ToExpression @ StringJoin[{##}] &],
            ParseAction[ParseLiteral["-"], Subtract &]
        ],
        "10-3-2"
    ],
    9,
    TestID -> "ParseChainRight: right-associative subtraction (10-(3-2) = 9)"
]


(* === ParseLookahead / ParseNotFollowedBy / ParseTry === *)

VerificationTest[
    Parse[ParseLookahead[ParseLiteral["foo"]] ~~ ParseLiteral["foo"], "foo"],
    {Null, "foo"},
    TestID -> "ParseLookahead: consumes nothing on match"
]

VerificationTest[
    MatchQ[Parse[ParseLookahead[ParseLiteral["foo"]] ~~ ParseLiteral["foo"], "bar"], _ParseError],
    True,
    TestID -> "ParseLookahead: propagates failure"
]

VerificationTest[
    Parse[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]], "foo"],
    {"foo", Null},
    TestID -> "ParseNotFollowedBy: succeeds when next thing absent"
]

VerificationTest[
    MatchQ[Parse[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]] ~~ ParseLiteral["bar"], "foobar"], _ParseError],
    True,
    TestID -> "ParseNotFollowedBy: fails when next thing present"
]

VerificationTest[
    Parse[ParseTry[ParseLiteral["foo"]] | ParseLiteral["fo"], "fo"],
    "fo",
    TestID -> "ParseTry: backtracks on inner failure"
]


(* === ParseRecursive === *)

VerificationTest[
    Module[{nest},
        nest = ParseAction[
            ParseBetween[ParseLiteral["("], Optional[ParseRecursive[nest]], ParseLiteral[")"]],
            "(" <> ToString[#] <> ")" &
        ];
        Parse[nest, "((()))"]
    ],
    "(((Missing[NoMatch])))",
    TestID -> "ParseRecursive: nested parens"
]

VerificationTest[
    Module[{nest},
        nest = ParseBetween[ParseLiteral["["], Optional[ParseRecursive[nest]], ParseLiteral["]"]];
        Parse[nest, "[[[]]]"]
    ],
    Missing["NoMatch"],
    TestID -> "ParseRecursive: inner of deepest nest is empty"
]


(* === GrammarRules lowering === *)

VerificationTest[
    Parse[
        GrammarRules[{"the weather in <city>" -> city}],
        "the weather in NYC"
    ],
    "NYC",
    TestID -> "GrammarRules: bare slot captures word"
]

VerificationTest[
    Parse[
        GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}],
        "add 3 and 5"
    ],
    8,
    TestID -> "GrammarRules: Number slots + RuleDelayed action"
]

VerificationTest[
    Parse[
        GrammarRules[{"hello" -> "greeting", "bye" -> "farewell"}],
        "bye"
    ],
    "farewell",
    TestID -> "GrammarRules: multi-rule choice"
]

VerificationTest[
    MatchQ[
        Parse[
            GrammarRules[{"hello" -> "greeting"}],
            "xyz"
        ],
        _ParseError
    ],
    True,
    TestID -> "GrammarRules: no matching rule returns ParseError"
]

VerificationTest[
    Parse[
        GrammarRules[{"<verb:Word> <obj:Word>" :> kind -> obj}],
        "eat sushi"
    ],
    kind -> "sushi",
    TestID -> "GrammarRules: multi-slot template"
]

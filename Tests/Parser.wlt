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
    MatchQ[Parse[ParseLiteral["foo"], "xyz"], _Failure],
    True,
    TestID -> "Parse Failure: literal mismatch returns ParseError"
]

VerificationTest[
    MatchQ[Parse[ParseLiteral["foo"], "foobar"], _Failure],
    True,
    TestID -> "Parse Failure: partial match returns ParseError"
]

VerificationTest[
    MatchQ[Parse[ParseSome[ParseCharacter[DigitCharacter]], ""], _Failure],
    True,
    TestID -> "Parse Failure: ParseSome on empty input"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"]["Position"],
    1,
    TestID -> "ParseError: Position field"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"]["Expected"],
    "foo",
    TestID -> "ParseError: Expected field"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"]["Found"],
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


(* === ParserCompile : value-threading codegen ===
   The compiled function returns the actual parse result (not just a
   recognised position), threading values as InertExpression and running
   actions via KernelFunction. Each case asserts compiled === interpreted
   over the full non-recursive algebra. *)

(* helper: a parser is genuinely compiled (vs interpreter fallback) iff
   its "Code" closure carries a CompiledCodeFunction. *)
ClearAll[nativeCompiledQ];
nativeCompiledQ[p_ParserCombinator] := !FreeQ[p[[3]]["Code"], _CompiledCodeFunction];

VerificationTest[
    nativeCompiledQ[ParserCompile[ParseSequence[ParseLiteral["a"], ParseLiteral["b"]]]],
    True,
    TestID -> "ParserCompile: sequence compiles to native code"
]

VerificationTest[
    nativeCompiledQ[ParserCompile[
        ParseAction[ParseSome[ParseCharacter[DigitCharacter]], FromDigits @ StringJoin[{##}] &]]],
    True,
    TestID -> "ParserCompile: action-bearing grammar compiles to native code"
]

(* compiled === interpreted across the algebra *)
With[{
    suite = {
        {"literal", ParseLiteral["foo"], "foo"},
        {"sequence", ParseSequence[ParseLiteral["a"], ParseLiteral["b"]], "ab"},
        {"choice-2nd", ParseLiteral["a"] | ParseLiteral["b"], "b"},
        {"some-digits", ParseSome[ParseCharacter[DigitCharacter]], "42"},
        {"many-empty-leftover", ParseMany[ParseCharacter[DigitCharacter]], "x"},
        {"optional-present", ParseOptional[ParseLiteral["a"]], "a"},
        {"optional-absent", ParseSequence[ParseOptional[ParseLiteral["a"]], ParseLiteral["b"]], "b"},
        {"action-fromdigits", ParseAction[ParseSome[ParseCharacter[DigitCharacter]], FromDigits @ StringJoin[{##}] &], "42"},
        {"identifier", ParseAction[ParseSequence[ParseCharacter[LetterCharacter],
            ParseMany[ParseCharacter[LetterCharacter] | ParseCharacter[DigitCharacter]]], StringJoin], "bar1"},
        {"between", ParseBetween[ParseLiteral["("], ParseSome[ParseCharacter[DigitCharacter]], ParseLiteral[")"]], "(42)"},
        {"choice-fail", ParseLiteral["a"] | ParseLiteral["b"], "c"},
        {"charrange", ParseSome[ParseCharacter[CharacterRange["a", "z"]]], "abc"},
        {"alt-class", ParseSome[ParseCharacter[LetterCharacter | DigitCharacter | "_"]], "a_9"},
        {"lookahead", ParseSequence[ParseLookahead[ParseLiteral["a"]], ParseLiteral["ab"]], "ab"},
        {"notfollowedby", ParseSequence[ParseLiteral["a"], ParseNotFollowedBy[ParseLiteral["b"]], ParseLiteral["c"]], "ac"},
        {"sepby", ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], "1,2,3"},
        {"sepby-empty", ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], ""},
        {"sepby-trailing", ParseSequence[ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], ParseLiteral[";"]], "1,2;"},
        {"sepby1-ok", ParseSepBy1[ParseCharacter[DigitCharacter], ParseLiteral[","]], "7,8"},
        {"sepby1-fail", ParseSepBy1[ParseCharacter[DigitCharacter], ParseLiteral[","]], ""},
        {"chainleft", ParseChainLeft[ParseAction[ParseCharacter[DigitCharacter], FromDigits], ParseAction[ParseLiteral["+"], Plus &]], "1+2+3"},
        {"chainright", ParseChainRight[ParseAction[ParseCharacter[DigitCharacter], FromDigits], ParseAction[ParseLiteral["^"], Power &]], "2^3^2"},
        {"choicelongest", ParseChoiceLongest[ParseLiteral["ab"], ParseLiteral["abc"]], "abc"}
    }},
    Scan[
        Function[case,
            VerificationTest[
                ParserCompile[case[[2]]][case[[3]]],
                Parse[case[[2]], case[[3]]],
                TestID -> "ParserCompile-vs-Parse: " <> case[[1]]
            ]
        ],
        suite
    ]
]

(* GrammarRules compiles to native code and parses (the local CloudDeploy
   analogue). *)
VerificationTest[
    With[{g = GrammarRules[{"the weather in <city>" -> city}]},
        {nativeCompiledQ[ParserCompile[g]], ParserCompile[g]["the weather in NYC"]}
    ],
    {True, "NYC"},
    TestID -> "ParserCompile: GrammarRules compiles and parses"
]

(* the doc's identifier example, mapped over inputs *)
VerificationTest[
    With[{identifier = ParserCompile[ParseAction[
        ParseCharacter[LetterCharacter] ~~
            (ParseCharacter[LetterCharacter] | ParseCharacter[DigitCharacter])...,
        StringJoin]]},
        identifier /@ {"foo", "bar1"}
    ],
    {"foo", "bar1"},
    TestID -> "ParserCompile: identifier example, mapped"
]

(* a parser using ParseRecursive cannot compile to native code, but still
   runs (interpreter fallback) and matches Parse. *)
VerificationTest[
    Module[{expr, compiled},
        ClearAll[expr];
        expr = ParseChoice[
            ParseBetween[ParseLiteral["("], ParseRecursive[expr], ParseLiteral[")"]],
            ParseLiteral["x"]];
        compiled = ParserCompile[expr];
        {nativeCompiledQ[compiled], compiled["((x))"], Parse[expr, "((x))"]}
    ],
    {False, "x", "x"},
    TestID -> "ParserCompile: recursive parser falls back to interpreter"
]

(* a ParseMany over a non-consuming parser is refused at compile time. *)
VerificationTest[
    ParserCompile[ParseMany[ParseSucceed["nothing"]]],
    $Failed,
    {ParserCompile::infloop},
    TestID -> "ParserCompile: infinite-loop repetition refused"
]


(* === ParserCompile : PEG-VM backend (Method -> "PEGVM") ===
   Lowers the grammar to an integer instruction table run on a single
   once-compiled parsing machine; scales to large recursive grammars and
   produces the same result as the interpreter. *)

(* the PEG-VM is a single shared compiled function referenced by the
   "Code" closure (not embedded), so just check the parser is compiled and
   runs - behavioural fidelity is covered by the suite below. *)
VerificationTest[
    With[{p = ParserCompile[ParseLiteral["foo"], Method -> "PEGVM"]},
        {KeyExistsQ[p[[3]], "Code"], p["foo"]}],
    {True, "foo"},
    TestID -> "ParserCompile PEGVM: compiles and runs"
]

(* compiled === interpreted across the algebra, including recursion and
   the derived combinators the FunctionCompile backend can't lower at scale *)
With[{
    suite = {
        {"literal", ParseLiteral["foo"], "foo"},
        {"sequence", ParseSequence[ParseLiteral["a"], ParseLiteral["b"]], "ab"},
        {"choice", ParseLiteral["a"] | ParseLiteral["b"], "b"},
        {"some-digits", ParseSome[ParseCharacter[DigitCharacter]], "42"},
        {"action", ParseAction[ParseSome[ParseCharacter[DigitCharacter]], FromDigits @ StringJoin[{##}] &], "42"},
        {"identifier", ParseAction[ParseSequence[ParseCharacter[LetterCharacter],
            ParseMany[ParseCharacter[LetterCharacter] | ParseCharacter[DigitCharacter]]], StringJoin], "bar1"},
        {"between", ParseBetween[ParseLiteral["("], ParseSome[ParseCharacter[DigitCharacter]], ParseLiteral[")"]], "(42)"},
        {"sepby", ParseSepBy[ParseCharacter[DigitCharacter], ParseLiteral[","]], "1,2,3"},
        {"chainleft", ParseChainLeft[ParseAction[ParseCharacter[DigitCharacter], FromDigits], ParseAction[ParseLiteral["+"], Plus &]], "1+2+3"},
        {"choicelongest", ParseChoiceLongest[ParseLiteral["ab"], ParseLiteral["abc"]], "abc"},
        {"choicelongest-prefix", ParseChoiceLongest[ParseLiteral["a"],
            ParseSequence[ParseLiteral["a"], ParseLiteral["="], ParseLiteral["b"]]], "a=b"}
    }},
    Scan[
        Function[case,
            VerificationTest[
                ParserCompile[case[[2]], Method -> "PEGVM"][case[[3]]],
                Parse[case[[2]], case[[3]]],
                TestID -> "ParserCompile-PEGVM-vs-Parse: " <> case[[1]]
            ]
        ],
        suite
    ]
]

(* a recursive grammar compiles natively on the PEG-VM (unlike the default
   backend, which keeps recursion interpretive) and matches Parse *)
VerificationTest[
    Module[{expr, compiled},
        ClearAll[expr];
        expr = ParseChoice[
            ParseBetween[ParseLiteral["("], ParseRecursive[expr], ParseLiteral[")"]],
            ParseLiteral["x"]];
        compiled = ParserCompile[expr, Method -> "PEGVM"];
        {KeyExistsQ[compiled[[3]], "Code"], compiled["((x))"], Parse[expr, "((x))"]}
    ],
    {True, "x", "x"},
    TestID -> "ParserCompile PEGVM: recursive grammar compiles and matches Parse"
]

(* invalid input is rejected (a ParseError, like the interpreter - though
   the PEG-VM reports a generic message rather than the expected-set). *)
VerificationTest[
    Head @ ParserCompile[ParseLiteral["a"] | ParseLiteral["b"], Method -> "PEGVM"]["c"],
    Failure,
    TestID -> "ParserCompile PEGVM: rejects invalid input with a ParseError"
]

(* a PEG-VM-compiled parser survives serialization (compile once, reuse):
   Export to WXF and re-Import yields the same results without recompiling *)
VerificationTest[
    Module[{p, file, reloaded},
        p = ParserCompile[
            ParseAction[ParseSome[ParseCharacter[DigitCharacter]], FromDigits @ StringJoin[{##}] &],
            Method -> "PEGVM"];
        file = FileNameJoin[{$TemporaryDirectory, "wparser-pegvm-test.wxf"}];
        Export[file, p];
        reloaded = Import[file];
        DeleteFile[file];
        {reloaded["42"], reloaded["100"]}
    ],
    {42, 100},
    TestID -> "ParserCompile PEGVM: Export/Import round-trip preserves behavior"
]


(* === Information[ParserCombinator, ...] === *)

VerificationTest[
    Information[ParseSequence[ParseLiteral["a"], ParseLiteral["b"]], "Type"],
    "Sequence",
    TestID -> "Information: Type"
]

VerificationTest[
    {Information[ParseLiteral["foo"], "Compiled"],
     Information[ParserCompile[ParseLiteral["foo"]], "Compiled"]},
    {False, True},
    TestID -> "Information: Compiled predicate"
]

VerificationTest[
    Head @ Information[ParserCompile[ParseLiteral["foo"]], "CompiledFunction"],
    CompiledCodeFunction,
    TestID -> "Information: CompiledFunction extracts the CompiledCodeFunction"
]

VerificationTest[
    {Information[ParserCompile[ParseLiteral["foo"]], "Backend"],
     Information[ParserCompile[ParseLiteral["foo"], Method -> "PEGVM"], "Backend"],
     Information[ParseLiteral["foo"], "Backend"]},
    {"FunctionCompile", "PEGVM", Missing["NotCompiled"]},
    TestID -> "Information: Backend"
]

VerificationTest[
    MemberQ[Information[ParseLiteral["x"], "Properties"], "CompiledFunction"],
    True,
    TestID -> "Information: Properties lists CompiledFunction"
]


(* === ParseError is a Failure["ParseError", ...] (Confirm-usable) === *)

VerificationTest[
    Head @ Parse[ParseLiteral["foo"], "xyz"],
    Failure,
    TestID -> "Failure: parse failure is a Failure object"
]

VerificationTest[
    FailureQ @ Parse[ParseLiteral["foo"], "xyz"],
    True,
    TestID -> "Failure: FailureQ on a parse failure"
]

VerificationTest[
    Parse[ParseLiteral["foo"], "xyz"][["Tag"]],
    "ParseError",
    TestID -> "Failure: tag is ParseError"
]

VerificationTest[
    Enclose[Confirm[Parse[ParseLiteral["foo"], "xyz"]]; "no-throw", "caught" &],
    "caught",
    TestID -> "Failure: Confirm throws on a parse failure"
]

VerificationTest[
    Enclose[Confirm[Parse[ParseLiteral["foo"], "foo"]], "threw" &],
    "foo",
    TestID -> "Failure: Confirm passes a successful parse through"
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
    MatchQ[Parse[ParseSepBy1[ParseCharacter[DigitCharacter], ParseLiteral[","]], ""], _Failure],
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
    MatchQ[Parse[ParseLookahead[ParseLiteral["foo"]] ~~ ParseLiteral["foo"], "bar"], _Failure],
    True,
    TestID -> "ParseLookahead: propagates failure"
]

VerificationTest[
    Parse[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]], "foo"],
    {"foo", Null},
    TestID -> "ParseNotFollowedBy: succeeds when next thing absent"
]

VerificationTest[
    MatchQ[Parse[ParseLiteral["foo"] ~~ ParseNotFollowedBy[ParseLiteral["bar"]] ~~ ParseLiteral["bar"], "foobar"], _Failure],
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
        _Failure
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


(* === GrammarRules: lowering the *pattern* form ===
   The same shapes a real cloud-deployed GrammarRules takes - FixedOrder,
   Alternatives (form1 | form2), OptionalElement, DelimitedSequence,
   Repeated (form..), CaseSensitive, GrammarToken[...], and the
   Pattern[name, form] capture form (`x : form`). *)

VerificationTest[
    Parse[
        GrammarRules[{
            FixedOrder["add",
                a : GrammarToken["Number"], "and",
                b : GrammarToken["Number"]
            ] :> a + b
        }],
        "add 3 and 5"
    ],
    8,
    TestID -> "GrammarRules pattern: FixedOrder + Pattern + GrammarToken[Number]"
]

VerificationTest[
    Parse[
        GrammarRules[{appl : ("stove" | "oven" | "fridge") :> appl}],
        "fridge"
    ],
    "fridge",
    TestID -> "GrammarRules pattern: Alternatives with Pattern capture"
]

VerificationTest[
    Parse[
        GrammarRules[{
            FixedOrder["turn", OptionalElement["the", ""],
                appl : ("stove" | "oven")] :> appl
        }],
        "turn the stove"
    ],
    "stove",
    TestID -> "GrammarRules pattern: OptionalElement (present)"
]

VerificationTest[
    Parse[
        GrammarRules[{
            FixedOrder["turn", OptionalElement["the", "no-the"],
                appl : ("stove" | "oven")] :> appl
        }],
        "turn stove"
    ],
    "stove",
    TestID -> "GrammarRules pattern: OptionalElement (absent uses default)"
]

VerificationTest[
    Parse[
        GrammarRules[{
            nums : DelimitedSequence[GrammarToken["Number"], ","] :> Total[nums]
        }],
        "1,2,3,4"
    ],
    10,
    TestID -> "GrammarRules pattern: DelimitedSequence"
]

VerificationTest[
    Parse[
        GrammarRules[{xs : (GrammarToken["Number"] ..) :> xs}],
        "42"
    ],
    {42},
    TestID -> "GrammarRules pattern: Repeated (form..)"
]

VerificationTest[
    Parse[GrammarRules[{CaseSensitive["Hello"] -> "matched"}], "Hello"],
    "matched",
    TestID -> "GrammarRules pattern: CaseSensitive wrapper (no-op locally)"
]

VerificationTest[
    Parse[
        GrammarRules[{
            FixedOrder["from", a : GrammarToken["Word"], "to", b : GrammarToken["Word"]] :> {a, b}
        }],
        "from foo to bar"
    ],
    {"foo", "bar"},
    TestID -> "GrammarRules pattern: GrammarToken[Word] + multi-slot binding"
]


(* === AnyOrder permutation matching === *)

VerificationTest[
    Parse[
        GrammarRules[{AnyOrder["red", "green", "blue"] :> "all three"}],
        "blue red green"
    ],
    "all three",
    TestID -> "GrammarRules pattern: AnyOrder permutation match"
]

VerificationTest[
    Parse[
        GrammarRules[{AnyOrder[a : "red", b : "green"] :> {a, b}}],
        "green red"
    ],
    {"red", "green"},
    TestID -> "GrammarRules pattern: AnyOrder captures resolve by name regardless of input order"
]


(* === RegularExpression pattern (lowers to ParseRegex) === *)

VerificationTest[
    Parse[
        GrammarRules[{n : RegularExpression["\\d+"] :> ToExpression[n]}],
        "42"
    ],
    42,
    TestID -> "GrammarRules pattern: RegularExpression captures the regex match"
]

VerificationTest[
    Parse[ParseRegex["[a-z]+"], "hello"],
    "hello",
    TestID -> "ParseRegex primitive: greedy match"
]

VerificationTest[
    MatchQ[Parse[ParseRegex["\\d+"], "abc"], _Failure],
    True,
    TestID -> "ParseRegex primitive: non-match returns Failure"
]


(* === GrammarRules[rules, defs] subsidiary domains === *)

VerificationTest[
    Parse[
        GrammarRules[
            {FixedOrder["from", c : GrammarToken["MyCity"]] :> c},
            {"MyCity" -> ("Paris" | "Tokyo" | "Boston")}
        ],
        "from Paris"
    ],
    "Paris",
    TestID -> "GrammarRules[rules, defs]: a GrammarToken[name] resolves to the subsidiary domain"
]

VerificationTest[
    MatchQ[
        Parse[
            GrammarRules[
                {FixedOrder["from", c : GrammarToken["MyCity"]] :> c},
                {"MyCity" -> ("Paris" | "Tokyo")}
            ],
            "from Berlin"
        ],
        _Failure
    ],
    True,
    TestID -> "GrammarRules[rules, defs]: input outside the domain fails"
]

VerificationTest[
    Parse[
        GrammarRules[
            {FixedOrder["go", d : GrammarToken["MyDir"]] :> d},
            {"MyDir" -> ("north" | "south" | GrammarToken["MyDiagonal"]),
             "MyDiagonal" -> ("northeast" | "northwest")}
        ],
        "go south"
    ],
    "south",
    TestID -> "GrammarRules[rules, defs]: subsidiary domains can reference each other"
]


(* === Interpreter-backed semantic GrammarToken types === *)

VerificationTest[
    Parse[
        GrammarRules[{c : GrammarToken["Color"] :> c}],
        "red"
    ],
    RGBColor[1, 0, 0],
    TestID -> "GrammarRules: GrammarToken[Color] resolves via Interpreter"
]

VerificationTest[
    Parse[
        GrammarRules[{n : GrammarToken["SemanticNumber"] :> n}],
        "five"
    ],
    5,
    TestID -> "GrammarRules: GrammarToken[SemanticNumber] interprets 'five' to 5"
]

VerificationTest[
    MatchQ[
        Parse[GrammarRules[{c : GrammarToken["Color"] :> c}], "zzzzznotacolor"],
        _Failure
    ],
    True,
    TestID -> "GrammarRules: an Interpreter slot that fails to interpret fails the parse"
]

VerificationTest[
    (* Number stays on the digit-fast-path, not Interpreter, so the result
       is the bare Integer and no network call happens. *)
    Parse[
        GrammarRules[{n : GrammarToken["Number"] :> n}],
        "42"
    ],
    42,
    TestID -> "GrammarRules: GrammarToken[Number] stays on the digit-fast-path"
]

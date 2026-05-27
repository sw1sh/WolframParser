(* :Title: Parser *)
(* :Context: Wolfram`Parser` *)
(* :Summary:
    A general, fast, composable parser library for the Wolfram Language.

    v0.2 prototype: the interpretive path against the doc-driven-dev
    spec in docs/Symbols/. Every Parse* constructor wraps into a single
    ParserCombinator[type, args, opts] head; the wrapper carries
    UpValues for the WL operators that overload to combinator
    composition (Alternatives, StringExpression, Repeated, RepeatedNull,
    Optional) and a SubValues rule that makes pc[input] equivalent to
    Parse[pc, input]. The compile path (ParserCompile / FunctionCompile
    lowering) is stubbed; presence of a "Code" entry in the options
    is the canonical "is this compiled?" marker.

    type is a String ("Literal", "Character", "Sequence", "Choice",
    "Many", "Some", "Optional", "Between", "Lookahead",
    "NotFollowedBy", "Try", "Action", "Capture", "Recursive",
    "Succeed", "Fail"), kept open so future combinator additions do
    not need to mint a fresh System symbol.

    Design references:
      docs/Tutorials/ParserLandscape.md
      docs/Tutorials/DesignAndCompilationStrategy.md
      docs/Guides/WolframParser.md
      docs/Symbols/*.md
*)

BeginPackage["Wolfram`Parser`"]

Parse::usage = "Parse[parser, input] runs parser against input. Returns the parse result on success or a ParseError on failure. Requires the parser to consume the entire input; use ParsePartial to accept a leftover."

ParsePartial::usage = "ParsePartial[parser, input] runs parser against input and returns {result, leftover} on success, or a ParseError on failure."

ParserCompile::usage = "ParserCompile[parser] returns a ParserCombinator with a \"Code\" entry in its options that, when called, runs the parser. v0.2: stubbed via the interpreter; the real FunctionCompile lowering lands later."

ParserCombinator::usage = "ParserCombinator[type, args, opts] is the single computable wrapper every parser is represented as. Build one by calling a Parse* constructor, never by hand. Carries operator UpValues (Alternatives | StringExpression | Repeated | RepeatedNull | Optional) and a SubValues rule that makes pc[input] equivalent to Parse[pc, input]."

ParserCombinatorQ::usage = "ParserCombinatorQ[expr] tests whether expr is a normalised ParserCombinator."

ParseError::usage = "ParseError[<|\"Position\" -> _, \"Expected\" -> _, \"Found\" -> _|>] is the structured failure value returned by Parse / ParsePartial."

ParseLiteral::usage = "ParseLiteral[s] returns the ParserCombinator that matches the exact string s."

ParseCharacter::usage = "ParseCharacter[pat] returns the ParserCombinator that matches a single character against the character-class pattern pat."

ParseSucceed::usage = "ParseSucceed[val] returns the ParserCombinator that always succeeds with val, consuming nothing."

ParseFail::usage = "ParseFail[msg] returns the ParserCombinator that always fails with msg."

ParseSequence::usage = "ParseSequence[p1, p2, ...] matches each pi in order; result is the list of their results."

ParseChoice::usage = "ParseChoice[p1, p2, ...] tries each pi in order (PEG-ordered) and returns the first match."

ParseMany::usage = "ParseMany[p] matches zero or more p; result is the list."

ParseSome::usage = "ParseSome[p] matches one or more p; result is the list."

ParseOptional::usage = "ParseOptional[p] matches zero or one p; returns p's result or Missing[\"NoMatch\"]."

ParseBetween::usage = "ParseBetween[open, p, close] matches open, then p, then close; result is p's."

ParseAction::usage = "ParseAction[p, f] runs p and applies f to its result; f is splatted across the elements when p's result is a list."


Begin["`Private`"]


(* === predicate === *)

ParserCombinatorQ[_ParserCombinator] := True
ParserCombinatorQ[_] := False


(* === constructors ===
   Each Parse* function returns a ParserCombinator[type, args, opts]
   with type a String. The type strings are an open vocabulary;
   adding a combinator means adding a (constructor, interpret rule,
   colour, name) pair, not minting a new symbol. *)

ParseLiteral[s_String] := ParserCombinator["Literal", s, <||>]

ParseCharacter[pat_] := ParserCombinator["Character", pat, <||>]

ParseSucceed[val_] := ParserCombinator["Succeed", val, <||>]

ParseFail[msg_] := ParserCombinator["Fail", msg, <||>]

ParseSequence[pc_ParserCombinator] := pc
ParseSequence[pcs__ParserCombinator] /; Length[{pcs}] >= 2 :=
    ParserCombinator["Sequence", flattenChildren["Sequence", {pcs}], <||>]

ParseChoice[pc_ParserCombinator] := pc
ParseChoice[pcs__ParserCombinator] /; Length[{pcs}] >= 2 :=
    ParserCombinator["Choice", flattenChildren["Choice", {pcs}], <||>]

(* Flatten any direct-child ParserCombinator of the same type into the
   parent's args. Only flattens children with no extra options
   (avoid losing memoisation hints, source positions, etc.). *)
flattenChildren[targetType_String, pcs_List] :=
    Flatten[
        Replace[
            pcs,
            ParserCombinator[targetType, inner_List, <||>] :> inner,
            {1}
        ],
        1
    ]

ParseMany[pc_ParserCombinator] := ParserCombinator["Many", pc, <||>]
ParseSome[pc_ParserCombinator] := ParserCombinator["Some", pc, <||>]
ParseOptional[pc_ParserCombinator] := ParserCombinator["Optional", pc, <||>]

ParseBetween[open_ParserCombinator, p_ParserCombinator, close_ParserCombinator] :=
    ParserCombinator["Between", {open, p, close}, <||>]

ParseAction[pc_ParserCombinator, f_] :=
    ParserCombinator["Action", {pc, f}, <||>]


(* === operator overloads ===
   The pattern-special heads (Alternatives, Optional, Repeated,
   RepeatedNull) are ordinarily refused by SetDelayed and TagSetDelayed
   because the system treats them as pattern primitives. Wrapping
   the LHS head in Verbatim[...] sidesteps that interpretation and
   lets the UpValue install cleanly. StringExpression is not pattern-
   special and works without the wrap. *)

ParserCombinator /: StringExpression[pcs__ParserCombinator] := ParseSequence[pcs]

ParserCombinator /: Verbatim[Alternatives][pcs__ParserCombinator] := ParseChoice[pcs]

ParserCombinator /: Verbatim[Optional][pc_ParserCombinator] := ParseOptional[pc]

ParserCombinator /: Verbatim[Repeated][pc_ParserCombinator] := ParseSome[pc]

ParserCombinator /: Verbatim[RepeatedNull][pc_ParserCombinator] := ParseMany[pc]


(* === SubValue: call a ParserCombinator as a function ===
   Restricted to String / List input so the SummaryBox internals (which
   apply pc to Hold-wrapped expressions during box rendering) don't
   trigger the parser and recurse. *)

ParserCombinator /: (pc : ParserCombinator[_, _, _])[input_String] :=
    Parse[pc, input]
ParserCombinator /: (pc : ParserCombinator[_, _, _])[input_List] :=
    Parse[pc, input]


(* === top-level Parse / ParsePartial === *)

Parse[pc_ParserCombinator, input_String] :=
    Block[{r, len = StringLength[input]},
        r = interpret[pc, input, 1];
        Which[
            MatchQ[r, _parseErr],
                errToParseError[r]
            ,
            r[[2]] != len + 1,
                ParseError[<|
                    "Position" -> r[[2]],
                    "Expected" -> "<end of input>",
                    "Found" -> safeChar[input, r[[2]]]
                |>]
            ,
            True,
                r[[1]]
        ]
    ]

ParsePartial[pc_ParserCombinator, input_String] :=
    Block[{r = interpret[pc, input, 1]},
        If[ MatchQ[r, _parseErr],
            errToParseError[r],
            {r[[1]], StringDrop[input, r[[2]] - 1]}
        ]
    ]

errToParseError[parseErr[pos_, expected_, found_]] :=
    ParseError[<|"Position" -> pos, "Expected" -> expected, "Found" -> found|>]

safeChar[input_, pos_] :=
    If[ pos > StringLength[input],
        "<end of input>",
        StringTake[input, {pos, pos}]
    ]


(* === interpretive engine ===
   The internal contract: interpret[pc, input, pos] returns either
       parseOk[result, newPos]    - success
       parseErr[pos, expected, found] - failure
   parseOk / parseErr are private internal heads. *)

(* compiled dispatch: if the options carry "Code", call it. *)
interpret[ParserCombinator[_, _, opts_Association], input_, pos_] /;
    KeyExistsQ[opts, "Code"] := opts["Code"][input, pos]

interpret[ParserCombinator["Literal", s_String, _], input_, pos_] :=
    Block[{len = StringLength[s]},
        If[ pos + len - 1 > StringLength[input],
            parseErr[pos, s, "<end of input>"],
            If[ StringTake[input, {pos, pos + len - 1}] === s,
                parseOk[s, pos + len],
                parseErr[pos, s, safeChar[input, pos]]
            ]
        ]
    ]

interpret[ParserCombinator["Character", pat_, _], input_, pos_] :=
    If[ pos > StringLength[input],
        parseErr[pos, charPatName[pat], "<end of input>"],
        Block[{ch = StringTake[input, {pos, pos}]},
            If[ StringMatchQ[ch, pat],
                parseOk[ch, pos + 1],
                parseErr[pos, charPatName[pat], ch]
            ]
        ]
    ]

interpret[ParserCombinator["Succeed", val_, _], _, pos_] :=
    parseOk[val, pos]

interpret[ParserCombinator["Fail", msg_, _], _, pos_] :=
    parseErr[pos, msg, ""]

interpret[ParserCombinator["Sequence", pcs_List, _], input_, pos_] :=
    Catch[
        Block[{final},
            final = Fold[
                Function[{state, p},
                    With[{r = interpret[p, input, state[[2]]]},
                        If[ MatchQ[r, _parseErr], Throw[r] ];
                        {Append[state[[1]], r[[1]]], r[[2]]}
                    ]
                ],
                {{}, pos},
                pcs
            ];
            parseOk[final[[1]], final[[2]]]
        ]
    ]

interpret[ParserCombinator["Choice", pcs_List, _], input_, pos_] :=
    Catch[
        Block[{errs, maxPos, atMax},
            errs = Map[
                Function[p,
                    With[{r = interpret[p, input, pos]},
                        If[MatchQ[r, _parseOk], Throw[r], r]
                    ]
                ],
                pcs
            ];
            maxPos = Max[errs[[All, 1]]];
            atMax = Select[errs, #[[1]] === maxPos &];
            parseErr[
                maxPos,
                Flatten[atMax[[All, 2]]],
                First[atMax][[3]]
            ]
        ]
    ]

interpret[ParserCombinator["Many", p_, _], input_, pos_] :=
    Block[{cur = pos, lastSawn, results},
        lastSawn = pos - 1;
        results = Last @ Reap[
            While[
                Block[{r = interpret[p, input, cur]},
                    If[ MatchQ[r, _parseOk] && r[[2]] > lastSawn,
                        Sow[r[[1]]]; lastSawn = cur; cur = r[[2]]; True,
                        False
                    ]
                ]
            ]
        ];
        parseOk[If[results === {}, {}, results[[1]]], cur]
    ]

interpret[ParserCombinator["Some", p_, _], input_, pos_] :=
    Block[{first = interpret[p, input, pos]},
        If[ MatchQ[first, _parseErr],
            first,
            Block[{cur = first[[2]], lastSawn = pos, rest},
                rest = Last @ Reap[
                    While[
                        Block[{r = interpret[p, input, cur]},
                            If[ MatchQ[r, _parseOk] && r[[2]] > lastSawn,
                                Sow[r[[1]]]; lastSawn = cur; cur = r[[2]]; True,
                                False
                            ]
                        ]
                    ]
                ];
                parseOk[
                    Prepend[If[rest === {}, {}, rest[[1]]], first[[1]]],
                    cur
                ]
            ]
        ]
    ]

interpret[ParserCombinator["Optional", p_, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseOk], r, parseOk[Missing["NoMatch"], pos] ]
    ]

interpret[ParserCombinator["Between", {open_, p_, close_}, _], input_, pos_] :=
    Catch[
        Block[{r1, r2, r3},
            r1 = interpret[open, input, pos];
            If[MatchQ[r1, _parseErr], Throw[r1]];
            r2 = interpret[p, input, r1[[2]]];
            If[MatchQ[r2, _parseErr], Throw[r2]];
            r3 = interpret[close, input, r2[[2]]];
            If[MatchQ[r3, _parseErr], Throw[r3]];
            parseOk[r2[[1]], r3[[2]]]
        ]
    ]

interpret[ParserCombinator["Action", {p_, f_}, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseErr],
            r,
            parseOk[If[ListQ[r[[1]]], f @@ r[[1]], f[r[[1]]]], r[[2]]]
        ]
    ]


(* === character-class names for diagnostics === *)

charPatName[DigitCharacter] := "<digit>"
charPatName[LetterCharacter] := "<letter>"
charPatName[WhitespaceCharacter] := "<whitespace>"
charPatName[WordCharacter] := "<word character>"
charPatName[HexadecimalCharacter] := "<hex digit>"
charPatName[PunctuationCharacter] := "<punctuation>"
charPatName[HoldPattern[CharacterRange[a_String, b_String]]] := "<" <> a <> "-" <> b <> ">"
charPatName[Alternatives[pats__]] := "<" <> StringRiffle[charPatName /@ {pats}, " or "] <> ">"
charPatName[s_String] := s
charPatName[other_] := ToString[other, InputForm]


(* === ParserCompile stub ===
   v0.2: attach a thunk that routes back through the interpreter. The
   shape the docs promise is in place; the real FunctionCompile
   lowering replaces the thunk later. *)

ParserCompile[pc_ParserCombinator, OptionsPattern[]] :=
    ParserCombinator[
        pc[[1]], pc[[2]],
        Append[
            pc[[3]],
            "Code" -> Function[{input, pos},
                interpret[
                    ParserCombinator[pc[[1]], pc[[2]], KeyDrop[pc[[3]], "Code"]],
                    input, pos
                ]
            ]
        ]
    ]


(* === SummaryBox formatter ===
   Modelled on the PAdicNumber / FiniteFieldElement convention. *)

arity[args_List] := Length[args]
arity[_] := 1

briefArg[ParserCombinator[t_String, _, _]] :=
    Style[t, FontWeight -> "Bold"]
briefArg[s_String] := "\"" <> s <> "\""
briefArg[expr_] := Short[ToString[expr, InputForm], 20]

structureSketch[type_String, args_List] :=
    Row[{type, "[", Row[Riffle[briefArg /@ args, ", "]], "]"}]
structureSketch[type_String, arg_] :=
    Row[{type, "[", briefArg[arg], "]"}]

colorFor[t_String] := Replace[
    t,
    {
        "Literal" | "Character" | "Succeed" | "Fail" -> StandardBlue,
        "Sequence" -> StandardOrange,
        "Choice" -> StandardPurple,
        "Many" | "Some" | "Optional" -> StandardGreen,
        "Between" -> StandardYellow,
        "Action" | "Capture" -> StandardRed,
        _ -> StandardGray
    }
]

parserIcon[type_String] :=
    Graphics[
        {colorFor[type], Disk[]},
        ImageSize -> Dynamic[{Automatic,
            3.5 CurrentValue["FontCapHeight"] / AbsoluteCurrentValue[Magnification]
        }],
        PlotRangePadding -> None
    ]

ParserCombinator /: MakeBoxes[
    pc : ParserCombinator[type_String, args_, opts_Association],
    form : (StandardForm | TraditionalForm)
] :=
    BoxForm`ArrangeSummaryBox[
        ParserCombinator, pc, parserIcon[type],
        {
            BoxForm`SummaryItem[{"Type: ", type}],
            BoxForm`SummaryItem[{"Arity: ", arity[args]}],
            BoxForm`SummaryItem[{"Compiled: ", KeyExistsQ[opts, "Code"]}]
        },
        {
            BoxForm`SummaryItem[{"Structure: ", structureSketch[type, args]}],
            BoxForm`SummaryItem[{"Options: ", KeyDrop[opts, "Code"]}]
        },
        form
    ]


End[]

EndPackage[]

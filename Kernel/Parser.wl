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

ParseSepBy::usage = "ParseSepBy[p, sep] matches zero or more p separated by sep; result is the list of p's results."

ParseSepBy1::usage = "ParseSepBy1[p, sep] matches one or more p separated by sep."

ParseChainLeft::usage = "ParseChainLeft[p, op] parses a left-associative chain: p, op, p, op, p, ..., folding op(prev, next) leftward."

ParseChainRight::usage = "ParseChainRight[p, op] parses a right-associative chain."

ParseLookahead::usage = "ParseLookahead[p] succeeds iff p would match at the current position, consuming nothing."

ParseNotFollowedBy::usage = "ParseNotFollowedBy[p] succeeds iff p would NOT match at the current position, consuming nothing."

ParseTry::usage = "ParseTry[p] runs p; on failure, the input position is restored to where ParseTry started (no commitment to partial consumption). Use to opt back into full-backtracking semantics when PEG-ordered choice is too eager."

ParseRecursive::usage = "ParseRecursive[symbol] is a lazy reference to a parser bound to symbol; the symbol is looked up at parse time so cyclic / mutually-recursive grammars can be written without pre-declaring every node."

ParseAction::usage = "ParseAction[p, f] runs p and applies f to its result; f is splatted across the elements when p's result is a list."

GrammarRules::usage = "GrammarRules is the built-in declarative grammar head. Parse[GrammarRules[{...}], input] lowers each rule to a ParserCombinator and runs it locally (no CloudDeploy)."


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

ParseSepBy[p_ParserCombinator, sep_ParserCombinator] :=
    ParserCombinator["SepBy", {p, sep}, <||>]

ParseSepBy1[p_ParserCombinator, sep_ParserCombinator] :=
    ParserCombinator["SepBy1", {p, sep}, <||>]

ParseChainLeft[p_ParserCombinator, op_ParserCombinator] :=
    ParserCombinator["ChainLeft", {p, op}, <||>]

ParseChainRight[p_ParserCombinator, op_ParserCombinator] :=
    ParserCombinator["ChainRight", {p, op}, <||>]

ParseLookahead[p_ParserCombinator] :=
    ParserCombinator["Lookahead", p, <||>]

ParseNotFollowedBy[p_ParserCombinator] :=
    ParserCombinator["NotFollowedBy", p, <||>]

ParseTry[p_ParserCombinator] :=
    ParserCombinator["Try", p, <||>]

(* Recursive reference: hold the symbol so the user can write
   `expr = ParseLiteral["x"] | ParseLiteral["("] ~~ ParseRecursive[expr] ~~ ParseLiteral[")"]`
   without expr being evaluated (it's unbound at that moment). The symbol
   is looked up at parse time. *)
SetAttributes[ParseRecursive, HoldFirst]
ParseRecursive[s_Symbol] := ParserCombinator["Recursive", Hold[s], <||>]

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

(* Accept GrammarRules as an input grammar: lower to ParserCombinator. *)
Parse[g : HoldPattern[GrammarRules[_List, ___]], input_String] :=
    Parse[lowerGrammarRules[g], input]

ParsePartial[g : HoldPattern[GrammarRules[_List, ___]], input_String] :=
    ParsePartial[lowerGrammarRules[g], input]

ParserCompile[g : HoldPattern[GrammarRules[_List, ___]], opts___] :=
    ParserCompile[lowerGrammarRules[g], opts]

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

(* SepBy / SepBy1: zero/one or more of p separated by sep. Same loop
   shape as Many / Some, but each iteration eats a sep before the
   next p. *)
interpret[ParserCombinator["SepBy", {p_, sep_}, _], input_, pos_] :=
    Block[{first = interpret[p, input, pos], cur, lastSawn, rest},
        If[ MatchQ[first, _parseErr],
            parseOk[{}, pos],
            cur = first[[2]];
            lastSawn = pos;
            rest = Last @ Reap[
                While[
                    Block[{rSep = interpret[sep, input, cur]},
                        If[ MatchQ[rSep, _parseOk],
                            Block[{rP = interpret[p, input, rSep[[2]]]},
                                If[ MatchQ[rP, _parseOk] && rP[[2]] > lastSawn,
                                    Sow[rP[[1]]]; lastSawn = cur; cur = rP[[2]]; True,
                                    False
                                ]
                            ],
                            False
                        ]
                    ]
                ]
            ];
            parseOk[Prepend[If[rest === {}, {}, rest[[1]]], first[[1]]], cur]
        ]
    ]

interpret[ParserCombinator["SepBy1", {p_, sep_}, _], input_, pos_] :=
    Block[{r = interpret[ParserCombinator["SepBy", {p, sep}, <||>], input, pos]},
        If[ MatchQ[r, _parseOk] && r[[1]] === {},
            parseErr[pos, "at least one occurrence", safeChar[input, pos]],
            r
        ]
    ]

(* ChainLeft / ChainRight: operator-precedence helpers. ChainLeft folds
   leftward as `op(prev, next)`; ChainRight folds rightward. The op
   parser is expected to return a 2-arg-binary head (a function or
   symbol) which is applied to the operands. *)
interpret[ParserCombinator["ChainLeft", {p_, op_}, _], input_, pos_] :=
    Block[{first = interpret[p, input, pos], cur, acc, rOp, rNext},
        If[ MatchQ[first, _parseErr], Return[first, Block] ];
        acc = first[[1]];
        cur = first[[2]];
        While[
            rOp = interpret[op, input, cur];
            MatchQ[rOp, _parseOk] && (rNext = interpret[p, input, rOp[[2]]]; MatchQ[rNext, _parseOk]),
            acc = rOp[[1]][acc, rNext[[1]]];
            cur = rNext[[2]]
        ];
        parseOk[acc, cur]
    ]

interpret[ParserCombinator["ChainRight", {p_, op_}, _], input_, pos_] :=
    Block[{first = interpret[p, input, pos], cur, ops = {}, vals, rOp, rNext},
        If[ MatchQ[first, _parseErr], Return[first, Block] ];
        vals = {first[[1]]};
        cur = first[[2]];
        While[
            rOp = interpret[op, input, cur];
            MatchQ[rOp, _parseOk] && (rNext = interpret[p, input, rOp[[2]]]; MatchQ[rNext, _parseOk]),
            AppendTo[ops, rOp[[1]]];
            AppendTo[vals, rNext[[1]]];
            cur = rNext[[2]]
        ];
        parseOk[
            Fold[
                Function[{acc, idx}, ops[[idx]][vals[[idx]], acc]],
                Last[vals],
                Reverse @ Range[Length[ops]]
            ],
            cur
        ]
    ]

(* Lookahead: succeed iff p matches, but reset position. *)
interpret[ParserCombinator["Lookahead", p_, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseOk], parseOk[Null, pos], r ]
    ]

(* NotFollowedBy: succeed iff p does NOT match. *)
interpret[ParserCombinator["NotFollowedBy", p_, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseOk],
            parseErr[pos, "<not followed by parser>", safeChar[input, pos]],
            parseOk[Null, pos]
        ]
    ]

(* Try: identical to interpret[p, ...] in the interpretive path -
   there is no committed-input distinction to roll back, since the
   interpretive engine doesn't commit until Sequence has accumulated
   the result. Kept as an explicit combinator so the grammar shape
   stays the same as in a backtracking-by-default parser library, and
   so the FunctionCompile lowering can give it different semantics if
   needed. *)
interpret[ParserCombinator["Try", p_, _], input_, pos_] :=
    interpret[p, input, pos]

(* Recursive: look up the held symbol's current value and interpret it. *)
interpret[ParserCombinator["Recursive", Hold[s_Symbol], _], input_, pos_] :=
    interpret[s, input, pos]


(* === GrammarRules lowering ===
   The built-in GrammarRules is just inert data:
       GrammarRules[{template -> action, template :> action, ...}]
   Each template is a string with optional <name> or <name:Type> slots.
   We split each template into literal segments and slot specs, build a
   ParseSequence of literal-parsers and slot-parsers, then wrap with a
   ParseAction that binds the captured slot values to the slot names in
   the action body. *)

lowerGrammarRules[HoldPattern[GrammarRules[rules_List, ___]]] :=
    Block[{ps = lowerGrammarRule /@ rules},
        Switch[Length[ps],
            0, ParseFail["empty grammar"],
            1, First[ps],
            _, ParseChoice @@ ps
        ]
    ]

lowerGrammarRule[(Rule | RuleDelayed)[template_String, body_]] :=
    lowerGrammarRule[template, HoldComplete[body]]

(* second form: take template and held body together.
   With[{...}] is what gives the Function closure access to the local
   slotNames / slotPositions values at parse time (Block-local symbols
   would otherwise be out of scope by then). *)
lowerGrammarRule[template_String, held : HoldComplete[_]] :=
    Block[{segments, slotNames, segParsers, slotPositions},
        segments = parseGrammarTemplate[template];
        slotNames = Cases[segments, grammarSlot[name_, _] :> name];
        segParsers = lowerSegment /@ segments;
        slotPositions = Flatten @ Position[
            segments, grammarSlot[_, _], {1}, Heads -> False
        ];
        Switch[Length[segParsers],
            0,
                With[{n = slotNames},
                    ParseAction[ParseSucceed[Null], evalBoundBody[held, n, {}] &]
                ],
            1,
                If[ slotPositions === {1},
                    With[{n = slotNames},
                        ParseAction[First[segParsers], evalBoundBody[held, n, {#}] &]
                    ],
                    With[{n = slotNames},
                        ParseAction[First[segParsers], evalBoundBody[held, n, {}] &]
                    ]
                ],
            _,
                With[{n = slotNames, p = slotPositions},
                    ParseAction[
                        ParseSequence @@ segParsers,
                        evalBoundBody[held, n, {##}[[p]]] &
                    ]
                ]
        ]
    ]

(* Splits a template string into a flat list of grammarLit[s] and
   grammarSlot[name, type] segments. The slot syntax accepted is
       <name>           (bare; type Automatic)
       <name:Type>      (e.g. Number, Word, Integer)
   Type is read as a single bareword - more elaborate Restricted[...]
   etc. forms will lower to v0.3+ Interpreter-backed parsers. *)
parseGrammarTemplate[s_String] :=
    Block[{lits, rest},
        lits = StringSplit[s,
            RegularExpression["<([A-Za-z][A-Za-z0-9_]*)(?::([^>]+))?>"]
                :> Function[Null, grammarSlot["$1", "$2"], HoldFirst]
        ];
        (* StringSplit gives interleaved {literal, capture, literal, ...} *)
        Map[
            Switch[#,
                "" | _String, grammarLit[#],
                _, #
            ] &,
            DeleteCases[lits, ""]
        ]
    ]

(* StringSplit's :> Function form is fiddly; do it iteratively instead. *)
parseGrammarTemplate[s_String] :=
    Block[{result = {}, rest = s, m},
        While[
            m = StringCases[rest,
                RegularExpression["<([A-Za-z][A-Za-z0-9_]*)(?::([^>]+))?>"] :>
                    {"$1", "$2", "$0"},
                1
            ];
            m =!= {},
            Block[{name = m[[1, 1]], typ = m[[1, 2]], whole = m[[1, 3]],
                   idx = StringPosition[rest, m[[1, 3]], 1][[1, 1]]
            },
                If[idx > 1, AppendTo[result, grammarLit[StringTake[rest, idx - 1]]]];
                AppendTo[result, grammarSlot[name, If[typ === "", Automatic, typ]]];
                rest = StringDrop[rest, idx - 1 + StringLength[whole]]
            ]
        ];
        If[rest =!= "", AppendTo[result, grammarLit[rest]]];
        result
    ]

lowerSegment[grammarLit[s_String]] := ParseLiteral[s]
lowerSegment[grammarSlot[_, type_]] := slotParser[type]

(* Default slot parser: a maximal run of word characters, joined. *)
slotParser[Automatic] :=
    ParseAction[ParseSome[ParseCharacter[WordCharacter]], StringJoin]

slotParser["Word"] :=
    ParseAction[ParseSome[ParseCharacter[LetterCharacter]], StringJoin]

slotParser["Number"] :=
    ParseAction[
        ParseSome[ParseCharacter[DigitCharacter]],
        FromDigits @ StringJoin[{##}] &
    ]

slotParser["Integer"] := slotParser["Number"]

slotParser[other_] :=
    ParseFail[
        "Slot type " <> ToString[other, InputForm] <> " not supported in v0.2.5 (only Word, Number / Integer, and the default any-word slot)"
    ]

(* Build the binding { slotName -> value, ... } and substitute into the
   held body, then release. Uses ReplaceAll on the bare symbols, scoped
   by the slot name list. *)
evalBoundBody[HoldComplete[body_], slotNames_List, values_List] :=
    ReleaseHold[
        HoldComplete[body] /. Thread[
            (Symbol /@ slotNames) -> values
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

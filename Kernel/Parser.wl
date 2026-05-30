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

Parse::usage = "Parse[parser, input] runs parser against input. Returns the parse result on success or a Failure[\"ParseError\", ...] on failure (usable with Confirm / Enclose). Requires the parser to consume the entire input; use ParsePartial to accept a leftover."

ParsePartial::usage = "ParsePartial[parser, input] runs parser against input and returns {result, leftover} on success, or a Failure[\"ParseError\", ...] on failure."

ParserCompile::usage = "ParserCompile[parser] returns a ParserCombinator with a \"Code\" entry in its options that, when called, runs the parser. The default backend lowers the combinator tree to a single FunctionCompile'd function (fast for small/medium grammars; recursive grammars need \"Recursive\" -> True and stay interpretive otherwise). ParserCompile[parser, Method -> \"PEGVM\"] uses an LPEG-style parsing machine instead: the grammar is lowered to an integer instruction table run on a once-compiled native VM, which scales to large recursive grammars (LaTeX, TPTP) that FunctionCompile cannot. The returned object can be Export'd and re-Import'd without recompiling."

ParserCombinator::usage = "ParserCombinator[type, args, opts] is the single computable wrapper every parser is represented as. Build one by calling a Parse* constructor, never by hand. Carries operator UpValues (Alternatives | StringExpression | Repeated | RepeatedNull | Optional) and a SubValues rule that makes pc[input] equivalent to Parse[pc, input]."

ParserCombinatorQ::usage = "ParserCombinatorQ[expr] tests whether expr is a normalised ParserCombinator."

ParseLiteral::usage = "ParseLiteral[s] returns the ParserCombinator that matches the exact string s."

ParseCharacter::usage = "ParseCharacter[pat] returns the ParserCombinator that matches a single character against the character-class pattern pat."

ParseSucceed::usage = "ParseSucceed[val] returns the ParserCombinator that always succeeds with val, consuming nothing."

ParseFail::usage = "ParseFail[msg] returns the ParserCombinator that always fails with msg."

ParseSequence::usage = "ParseSequence[p1, p2, ...] matches each pi in order; result is the list of their results."

ParseChoice::usage = "ParseChoice[p1, p2, ...] tries each pi in order (PEG-ordered) and returns the first match."

ParseChoiceLongest::usage = "ParseChoiceLongest[p1, p2, ...] runs every pi at the current position and returns the longest successful match (POSIX-style). Slower than ParseChoice (it cannot stop at the first hit) but correct for grammars whose alternatives share a leaf-level prefix - e.g. TPTP's `<fof_atomic_formula> ::= <fof_plain_atomic_formula> | <fof_defined_atomic_formula>` where both alternatives can parse a leading term but only the second one (re-entered via `<fof_defined_infix_formula>`) carries the trailing `= rhs`."

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

ParseChoiceLongest[pc_ParserCombinator] := pc
ParseChoiceLongest[pcs__ParserCombinator] /; Length[{pcs}] >= 2 :=
    ParserCombinator["ChoiceLongest",
        flattenChildren["ChoiceLongest", {pcs}], <||>]

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


(* === Information ===
   Information[pc, "prop"] exposes the wrapper's structure without the
   user reaching into the (opaque) ParserCombinator[type, args, opts]
   layout by hand. "CompiledFunction" pulls the underlying
   CompiledCodeFunction out of a FunctionCompile-backed parser (or the
   instruction table out of a PEG-VM one); "Code" is the raw callable. *)

$parserCombinatorProperties = {"Type", "Arity", "Children", "Options",
    "Compiled", "Backend", "CompiledFunction", "Code", "Properties"};

parserProperty[ParserCombinator[type_, _, _], "Type"] := type
parserProperty[ParserCombinator[_, args_, _], "Arity"] := arity[args]
parserProperty[ParserCombinator[_, args_, _], "Children"] := args
parserProperty[ParserCombinator[_, _, opts_], "Options"] := KeyDrop[opts, "Code"]
parserProperty[ParserCombinator[_, _, opts_], "Compiled"] := KeyExistsQ[opts, "Code"]
parserProperty[ParserCombinator[_, _, opts_], "Code"] := Lookup[opts, "Code", Missing["NotCompiled"]]
parserProperty[ParserCombinator[_, _, opts_], "Backend"] :=
    Which[! KeyExistsQ[opts, "Code"], Missing["NotCompiled"],
        ! FreeQ[opts["Code"], _CompiledCodeFunction], "FunctionCompile",
        ! FreeQ[opts["Code"], HoldPattern[pegMachine]], "PEGVM",
        True, "Interpretive"]
(* the compiled function: the embedded CompiledCodeFunction for the
   FunctionCompile backend (it appears applied, cf[input, pos], so match
   it as a head), or the callable "Code" closure otherwise. *)
parserProperty[ParserCombinator[_, _, opts_], "CompiledFunction"] :=
    If[! KeyExistsQ[opts, "Code"], Missing["NotCompiled"],
        FirstCase[opts["Code"], (h : _CompiledCodeFunction)[___] :> h, opts["Code"], Infinity]]
parserProperty[_, "Properties"] := $parserCombinatorProperties
parserProperty[_, other_] := Missing["UnknownProperty", other]

ParserCombinator /: Information[pc : ParserCombinator[_, _, _], prop_String] := parserProperty[pc, prop]
ParserCombinator /: Information[pc : ParserCombinator[_, _, _], props_List] := parserProperty[pc, #] & /@ props
ParserCombinator /: Information[pc : ParserCombinator[_, _, _]] :=
    Association[# -> parserProperty[pc, #] & /@ DeleteCases[$parserCombinatorProperties, "Properties"]]


(* === top-level Parse / ParsePartial ===
   $RecursionLimit is capped at a deliberately modest value: the
   recursive-descent interpreter nests several frames per grammar
   level, so input nested hundreds of levels deep can exhaust the
   stack. We bound it well below the segfault threshold and convert
   any overflow (TerminatedEvaluation) into a clean
   "too deeply nested" ParseError. The parser must always return a
   value - never a raw TerminatedEvaluation, never a crash. *)

$maxParseRecursion = 12000

(* The Block wraps ONLY the interpret call - we inspect the result
   OUTSIDE the raised-limit scope, where the limit is back to default
   and there's stack headroom to build the ParseError. (Doing the
   inspection inside the Block re-trips the limit before the
   conversion can run.) *)
Parse[pc_ParserCombinator, input_String] :=
    Module[{r, len = StringLength[input]},
        r = Block[{$RecursionLimit = $maxParseRecursion}, interpret[pc, input, 1]];
        Which[
            MatchQ[r, _TerminatedEvaluation],
                makeFailure[1, "<input within nesting limit>", "<input nested too deeply>"]
            ,
            MatchQ[r, _parseErr],
                errToFailure[r]
            ,
            r[[2]] != len + 1,
                makeFailure[r[[2]], "<end of input>", safeChar[input, r[[2]]]]
            ,
            True,
                r[[1]]
        ]
    ]

ParsePartial[pc_ParserCombinator, input_String] :=
    Module[{r},
        r = Block[{$RecursionLimit = $maxParseRecursion}, interpret[pc, input, 1]];
        Which[
            MatchQ[r, _TerminatedEvaluation],
                makeFailure[1, "<input within nesting limit>", "<input nested too deeply>"],
            MatchQ[r, _parseErr],
                errToFailure[r],
            True,
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

(* All parse failures surface as a Failure["ParseError", ...] so the
   built-in Confirm / ConfirmBy / Enclose machinery treats them as
   failures, while still carrying the structured "Position"/"Expected"/
   "Found" fields (accessible as f["Position"], etc.). *)
makeFailure[pos_, expected_, found_] := Failure["ParseError", <|
    "MessageTemplate" -> "Parse failed at position `Position`: expected `Expected`, found `Found`.",
    "MessageParameters" -> <|"Position" -> pos, "Expected" -> expected, "Found" -> found|>,
    "Position" -> pos, "Expected" -> expected, "Found" -> found|>]

errToFailure[parseErr[pos_, expected_, found_]] := makeFailure[pos, expected, found]

safeChar[input_, pos_] :=
    If[ pos > StringLength[input],
        "<end of input>",
        StringTake[input, {pos, pos}]
    ]


(* === interpretive engine ===
   The internal contract: interpret[pc, input, pos] returns either
       parseOk[result, newPos]    - success
       parseErr[pos, expected, found] - failure
   parseOk / parseErr are private internal heads.

   interpret itself is a thin depth-guarding wrapper around the
   per-combinator interpretDispatch clauses. The guard is a parser-
   level recursion bound: it counts nesting (every interpret call bumps
   the dynamically-scoped $parseDepth) and bails with a clean parseErr
   when the input is nested past $maxParseDepth. This is what keeps the
   parser from ever exhausting the WL stack on pathological input - a
   controlled return, not a $RecursionLimit trip (which unwinds past
   any catch and would leak a raw TerminatedEvaluation). *)

$maxParseDepth = 800

interpret[pc_, input_, pos_] :=
    Block[{$parseDepth = $parseDepth + 1},
        If[ $parseDepth > $maxParseDepth,
            parseErr[pos, "<input within nesting limit>", safeChar[input, pos]],
            interpretDispatch[pc, input, pos]
        ]
    ]

$parseDepth = 0

(* compiled dispatch: if the options carry "Code", call it. *)
interpretDispatch[ParserCombinator[_, _, opts_Association], input_, pos_] /;
    KeyExistsQ[opts, "Code"] := opts["Code"][input, pos]

interpretDispatch[ParserCombinator["Literal", s_String, _], input_, pos_] :=
    Block[{len = StringLength[s]},
        If[ pos + len - 1 > StringLength[input],
            parseErr[pos, s, "<end of input>"],
            If[ StringTake[input, {pos, pos + len - 1}] === s,
                parseOk[s, pos + len],
                parseErr[pos, s, safeChar[input, pos]]
            ]
        ]
    ]

interpretDispatch[ParserCombinator["Character", pat_, _], input_, pos_] :=
    If[ pos > StringLength[input],
        parseErr[pos, charPatName[pat], "<end of input>"],
        Block[{ch = StringTake[input, {pos, pos}]},
            If[ charMatchesQ[ch, pat],
                parseOk[ch, pos + 1],
                parseErr[pos, charPatName[pat], ch]
            ]
        ]
    ]

(* Match a single character against a class. Literal-string classes
   compare by equality (NOT StringMatchQ - that treats "*", "@", "\\"
   as wildcards / metacharacters, so e.g. ParseCharacter["*"] would
   match any character). Alternatives recurse so a mixed class like
   LetterCharacter | "*" works correctly. Named classes
   (LetterCharacter, DigitCharacter, CharacterRange, ...) fall through
   to StringMatchQ, which is correct for them. *)
charMatchesQ[ch_String, s_String] := ch === s
charMatchesQ[ch_String, Verbatim[Alternatives][pats__]] :=
    AnyTrue[{pats}, charMatchesQ[ch, #] &]
charMatchesQ[ch_String, pat_] := StringMatchQ[ch, pat]

interpretDispatch[ParserCombinator["Succeed", val_, _], _, pos_] :=
    parseOk[val, pos]

interpretDispatch[ParserCombinator["Fail", msg_, _], _, pos_] :=
    parseErr[pos, msg, ""]

interpretDispatch[ParserCombinator["Sequence", pcs_List, _], input_, pos_] :=
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

interpretDispatch[ParserCombinator["Choice", pcs_List, _], input_, pos_] :=
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

(* Run every alternative, then commit to the one that consumed the
   most input. The Choice combinator above stops at the first match -
   correct for PEG, wrong for grammars whose alternatives share a
   leaf-level prefix and only differ in what comes AFTER that prefix
   (TPTP's atomic-formula / cnf-literal rules are the canonical
   example). Ties between equal-length successes resolve to the first
   listed alternative, mirroring PEG's left-bias. *)
interpretDispatch[ParserCombinator["ChoiceLongest", pcs_List, _], input_, pos_] :=
    Block[{results, oks, errs, maxPos, atMax},
        results = interpret[#, input, pos] & /@ pcs;
        oks = Cases[results, _parseOk];
        If[ Length[oks] > 0,
            First @ MaximalBy[oks, #[[2]] &],
            errs = Cases[results, _parseErr];
            maxPos = Max[errs[[All, 1]]];
            atMax = Select[errs, #[[1]] === maxPos &];
            parseErr[
                maxPos,
                Flatten[atMax[[All, 2]]],
                First[atMax][[3]]
            ]
        ]
    ]

interpretDispatch[ParserCombinator["Many", p_, _], input_, pos_] :=
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

interpretDispatch[ParserCombinator["Some", p_, _], input_, pos_] :=
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

interpretDispatch[ParserCombinator["Optional", p_, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseOk], r, parseOk[Missing["NoMatch"], pos] ]
    ]

interpretDispatch[ParserCombinator["Between", {open_, p_, close_}, _], input_, pos_] :=
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

interpretDispatch[ParserCombinator["Action", {p_, f_}, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseErr],
            r,
            parseOk[If[ListQ[r[[1]]], f @@ r[[1]], f[r[[1]]]], r[[2]]]
        ]
    ]

(* SepBy / SepBy1: zero/one or more of p separated by sep. Same loop
   shape as Many / Some, but each iteration eats a sep before the
   next p. *)
interpretDispatch[ParserCombinator["SepBy", {p_, sep_}, _], input_, pos_] :=
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

interpretDispatch[ParserCombinator["SepBy1", {p_, sep_}, _], input_, pos_] :=
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
interpretDispatch[ParserCombinator["ChainLeft", {p_, op_}, _], input_, pos_] :=
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

interpretDispatch[ParserCombinator["ChainRight", {p_, op_}, _], input_, pos_] :=
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
interpretDispatch[ParserCombinator["Lookahead", p_, _], input_, pos_] :=
    Block[{r = interpret[p, input, pos]},
        If[ MatchQ[r, _parseOk], parseOk[Null, pos], r ]
    ]

(* NotFollowedBy: succeed iff p does NOT match. *)
interpretDispatch[ParserCombinator["NotFollowedBy", p_, _], input_, pos_] :=
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
interpretDispatch[ParserCombinator["Try", p_, _], input_, pos_] :=
    interpret[p, input, pos]

(* Recursive: look up the held symbol's current value and interpret it. *)
interpretDispatch[ParserCombinator["Recursive", Hold[s_Symbol], _], input_, pos_] :=
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
        "Slot type " <> ToString[other, InputForm] <> " not supported"
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


(* === GrammarRules: lowering the *pattern* form ===
   Templates ("the weather in <city>") are handled above. This branch
   handles the richer pattern shapes that real GrammarRules expressions
   carry: FixedOrder, AnyOrder, OptionalElement, DelimitedSequence,
   Repeated (form..), Alternatives (form1 | form2), CaseSensitive,
   GrammarToken["Name"], and the Pattern[name, form] capture form
   (`x : form` syntactic sugar).

   The internal contract: every parser returned by lowerPat emits a
   2-list `{value, bindings}`. `value` is the matched value for the
   parent context to use; `bindings` is an Association of all captured
   {slotName -> capturedValue} that bubble up from Pattern[] inside.
   The top-level rule lowering reads the final bindings and substitutes
   the names into the rule body via the same evalBoundBody machinery
   the template path uses. *)

grammarWs := ParseMany[ParseCharacter[WhitespaceCharacter]]

lowerPat[s_String] := ParseAction[ParseLiteral[s], {#, <||>} &]

(* Verbatim[Pattern] is needed because Pattern[name_, form_] would
   itself be parsed AS a pattern (head Pattern in a pattern context
   names a sub-pattern). Verbatim pins it to the literal head. *)
lowerPat[Verbatim[Pattern][name_, form_]] :=
    With[{nm = SymbolName[Unevaluated[name]], inner = lowerPat[form]},
        ParseAction[
            inner,
            Function[{v, b}, {v, Join[b, <|nm -> v|>]}]
        ]
    ]

lowerPat[FixedOrder[fs__]] :=
    With[{lowered = lowerPat /@ {fs}},
        ParseAction[
            ParseSequence @@ Riffle[lowered, grammarWs],
            (* args are {v1,b1}, ws1, {v2,b2}, ws2, ..., {vn,bn}; the
               odd indices are the elements, the evens are whitespace *)
            Function[Block[{parts = {##}[[Range[1, Length[{##}], 2]]]},
                {parts[[All, 1]], Join @@ parts[[All, 2]]}
            ]]
        ]
    ]

(* Verbatim[Alternatives] - bare Alternatives in pattern position means
   pattern-OR, which would swallow every call. Pin it to the literal. *)
lowerPat[Verbatim[Alternatives][fs__]] :=
    ParseChoice @@ (lowerPat /@ {fs})

lowerPat[OptionalElement[form_, default_]] :=
    ParseChoice[
        lowerPat[form],
        ParseAction[ParseSucceed[Null], {default, <||>} &]
    ]

lowerPat[OptionalElement[form_]] :=
    ParseChoice[
        lowerPat[form],
        ParseAction[ParseSucceed[Null], {Missing["NoMatch"], <||>} &]
    ]

(* Verbatim[Repeated] / Verbatim[RepeatedNull] - Repeated[form] is the
   "form.." pattern in WL, similar pinning needed. *)
lowerPat[Verbatim[Repeated][form_]] :=
    ParseAction[
        ParseSome[lowerPat[form]],
        Function[{{##}[[All, 1]], Join @@ {##}[[All, 2]]}]
    ]

lowerPat[Verbatim[RepeatedNull][form_]] :=
    ParseAction[
        ParseMany[lowerPat[form]],
        Function[
            If[ Length[{##}] === 0,
                {{}, <||>},
                {{##}[[All, 1]], Join @@ {##}[[All, 2]]}
            ]
        ]
    ]

(* DelimitedSequence[form, sep] - one or more `form`s with `sep`
   between. Sep can be a literal string or an Alternatives of strings,
   so lower it the same way and discard its {v, b} pair. *)
lowerPat[DelimitedSequence[form_, sep_]] :=
    ParseAction[
        ParseSepBy1[lowerPat[form], lowerPat[sep]],
        Function[{{##}[[All, 1]], Join @@ {##}[[All, 2]]}]
    ]

(* CaseSensitive[form] - we don't model case insensitivity locally,
   so this is a no-op wrapper. *)
lowerPat[CaseSensitive[form_]] := lowerPat[form]

(* GrammarToken["Name"] - look up the local slot parser. Unsupported
   types fail through slotParser's catchall. *)
lowerPat[GrammarToken[name_String]] :=
    ParseAction[slotParser[name], {#, <||>} &]

lowerPat[other_] :=
    ParseFail[
        "Pattern element not supported in local GrammarRules lowering: " <>
            ToString[Unevaluated[other], InputForm]
    ]

(* Lower a non-template rule. Tried after the template_String branch
   because that one is more specific. *)
lowerGrammarRule[(Rule | RuleDelayed)[pattern_, body_]] :=
    lowerGrammarRulePattern[pattern, HoldComplete[body]]

lowerGrammarRulePattern[pattern_, held : HoldComplete[_]] :=
    With[{p = lowerPat[pattern]},
        ParseAction[
            p,
            Function[{value, bindings},
                evalBoundBody[
                    held,
                    Keys[bindings],
                    Values[bindings]
                ]
            ]
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
(* Verbatim[Alternatives] - a bare Alternatives[...] on a pattern LHS is
   read as the pattern-OR operator (matching ANY arg), which made this
   clause swallow every call and recurse. Verbatim pins it to the literal
   Alternatives head. *)
charPatName[Verbatim[Alternatives][pats__]] :=
    "<" <> StringRiffle[charPatName /@ {pats}, " or "] <> ">"
charPatName[s_String] := s
charPatName[other_] := ToString[other, InputForm]


(* === ParserCompile : value-threading codegen ===
   Lowers a ParserCombinator tree to a SINGLE FunctionCompile'd function

       (cgInput :: "String", cgPos :: "MachineInteger") -> {finalPos, value}

   threading the position natively (MachineInteger, the fast lexing path)
   and the *result* as an "InertExpression" built once per matched node
   via KernelFunction callbacks. finalPos = -1 marks failure; on failure
   the shim re-walks the interpreter once to recover the exact ParseError
   (failure is the rare path). Recursion (ParseRecursive) and any node the
   codegen does not handle fall back to the interpreter, as before.

   This replaces the earlier recognition-only codegen (which returned a
   bare position and rebuilt the result interpretively even on success);
   the compiled function now returns the actual result directly. *)

(* kernel-side inert value builders, invoked from compiled code via
   Typed[KernelFunction[..]]. They run in the kernel, so an action f can
   be ANY Wolfram function - hence action-bearing grammars now compile. *)
cgStr = Identity;
cgListN = (List[##] &);
cgAppend = Append;
cgMissing = (Missing["NoMatch"] &);
cgNull = (Null &);
cgAction = Function[{f, v}, If[ListQ[v], f @@ v, f[v]]];
cgApplyOp = Function[{op, a, b}, op[a, b]];
cgChainRight = Function[{vals, ops},
    Fold[Function[{acc, idx}, ops[[idx]][vals[[idx]], acc]], Last[vals], Reverse[Range[Length[ops]]]]];

cgInertT = "InertExpression";
cgKF[f_, at_List, ret_] := Typed[KernelFunction[f], at -> ret]
cgNullInert[] := cgKF[cgNull, {}, cgInertT][]

(* held-AST kit: conditions with SameQ and all Set/If/While/CompoundExpr
   must be built held (they would evaluate eagerly against the value-free
   data symbols cgInput/cgPP/cgOK and the fresh cgV/cgI locals). Inert
   value expressions are safe to build eagerly and injected via With. *)
cgIf3[Hold[c_], Hold[t_], Hold[e_]] := Hold[If[c, t, e]]
cgIf2[Hold[c_], Hold[t_]] := Hold[If[c, t]]
cgWhile[Hold[c_], Hold[b_]] := Hold[While[c, b]]
cgSeq[h_Hold] := h
cgSeq[Hold[a___], Hold[b___]] := Hold[a; b]
cgSeq[h1_, h2_, hs__] := cgSeq[cgSeq[h1, h2], hs]
cgSet[sym_, rhs_] := With[{s = sym, r = rhs}, Hold[s = r]]
cgCond[c_] := With[{cc = c}, Hold[cc]]
cgOkk := Hold[cgOK]

cgCtr = 0; cgVsyms = {}; cgIsyms = {};
cgFreshV[] := With[{s = Symbol["Wolfram`Parser`Private`cgV" <> ToString[cgCtr++]]}, AppendTo[cgVsyms, s]; s]
cgFreshI[] := With[{s = Symbol["Wolfram`Parser`Private`cgI" <> ToString[cgCtr++]]}, AppendTo[cgIsyms, s]; s]

(* cgEmit[pc] -> {Hold[statements], valueSym}. Throws cgFail[node] on a
   node the codegen does not handle (e.g. Recursive), or cgInfloop[node]
   for a Many/Some over a nullable parser. *)
cgEmit[other_] := Throw[other, cgFail]

cgEmit[ParserCombinator["Literal", s_String, _]] := With[{v = cgFreshV[], len = StringLength[s], lit = s},
    {cgIf3[
        Hold[cgPP + len - 1 <= StringLength[cgInput] && StringTake[cgInput, {cgPP, cgPP + len - 1}] === lit],
        cgSeq[cgSet[v, cgKF[cgStr, {"String"}, cgInertT][lit]], cgSet[cgPP, cgPP + len]],
        cgSet[cgOK, False]], v}]

cgEmit[ParserCombinator["Character", pat_, _]] := With[{v = cgFreshV[]},
    {cgIf3[
        cgCharCond[pat],
        cgSeq[cgSet[v, cgKF[cgStr, {"String"}, cgInertT][StringTake[cgInput, {cgPP, cgPP}]]], cgSet[cgPP, cgPP + 1]],
        cgSet[cgOK, False]], v}]

(* native tests (DigitQ, ToCharacterCode ranges) inline to fast code; any
   other class falls back to a KernelFunction wrapping the interpreter's
   own charMatchesQ, so the compiled test matches Parse exactly. *)
cgCharCond[pat_] := With[{t = cgCharTest[pat]}, Hold[cgPP <= StringLength[cgInput] && t]]
cgCharTest[pat_] := With[{nt = cgNativeCharTest[pat]},
    If[nt === $cgNoNative,
        cgKF[(charMatchesQ[#, pat] &), {"String"}, "Boolean"][StringTake[cgInput, {cgPP, cgPP}]],
        nt]]
cgNativeCharTest[DigitCharacter] := DigitQ[StringTake[cgInput, {cgPP, cgPP}]]
cgNativeCharTest[s_String] /; StringLength[s] === 1 :=
    With[{cc = First @ ToCharacterCode[s]}, First[ToCharacterCode[StringTake[cgInput, {cgPP, cgPP}]]] == cc]
cgNativeCharTest[HoldPattern[CharacterRange[a_String, b_String]]] :=
    With[{lo = First @ ToCharacterCode[a], hi = First @ ToCharacterCode[b]},
        lo <= First[ToCharacterCode[StringTake[cgInput, {cgPP, cgPP}]]] <= hi]
cgNativeCharTest[Verbatim[Alternatives][ps__]] :=
    With[{sub = cgNativeCharTest /@ {ps}}, If[FreeQ[sub, $cgNoNative], Fold[Or, sub], $cgNoNative]]
cgNativeCharTest[_] := $cgNoNative

cgEmit[ParserCombinator["Succeed", val_, _]] := With[{v = cgFreshV[]},
    {cgSet[v, cgKF[(val &), {}, cgInertT][]], v}]

cgEmit[ParserCombinator["Fail", _, _]] := With[{v = cgFreshV[]},
    {cgSet[cgOK, False], v}]

cgEmit[ParserCombinator["Sequence", pcs_List, _]] := Module[{parts = cgEmit /@ pcs, vs, v = cgFreshV[], n = Length[pcs]},
    vs = parts[[All, 2]];
    {cgSeq[
        Fold[Function[{acc, part}, cgSeq[acc, cgIf2[cgOkk, part[[1]]]]],
            First[parts][[1]], Rest[parts]],
        cgIf2[cgOkk, cgSet[v, cgKF[cgListN, ConstantArray[cgInertT, n], cgInertT] @@ vs]]], v}]

cgEmit[ParserCombinator["Choice", pcs_List, _]] := Module[{parts = cgEmit /@ pcs, v = cgFreshV[], st = cgFreshI[]},
    {cgSeq[
        cgSet[st, cgPP],
        Fold[
            Function[{elseAcc, part},
                cgSeq[cgSet[cgOK, True], cgSet[cgPP, st], part[[1]],
                    cgIf3[cgOkk, cgSet[v, part[[2]]], elseAcc]]],
            cgSet[cgOK, False],
            Reverse[parts]]], v}]

cgEmit[ParserCombinator["ChoiceLongest", pcs_List, _]] := Module[
    {parts = cgEmit /@ pcs, v = cgFreshV[], st = cgFreshI[], best = cgFreshI[], any = cgFreshI[]},
    {cgSeq[
        cgSet[st, cgPP], cgSet[best, -1], cgSet[any, 0],
        cgSeq @@ Map[
            Function[part,
                cgSeq[cgSet[cgPP, st], cgSet[cgOK, True], part[[1]],
                    cgIf2[cgCond[cgOK && cgPP > best],
                        cgSeq[cgSet[best, cgPP], cgSet[v, part[[2]]], cgSet[any, 1]]]]],
            parts],
        cgIf3[cgCond[any > 0],
            cgSeq[cgSet[cgOK, True], cgSet[cgPP, best]],
            cgSet[cgOK, False]]], v}]

cgEmit[ParserCombinator["Optional", p_, _]] := Module[{part = cgEmit[p], v = cgFreshV[], st = cgFreshI[]},
    {cgSeq[cgSet[st, cgPP], part[[1]],
        cgIf3[cgOkk, cgSet[v, part[[2]]],
            cgSeq[cgSet[cgOK, True], cgSet[cgPP, st], cgSet[v, cgKF[cgMissing, {}, cgInertT][]]]]], v}]

cgEmit[ParserCombinator["Many", p_, _]] := (cgInfloopCheck["Many", p];
    Module[{part = cgEmit[p], v = cgFreshV[], st = cgFreshI[], loop = cgFreshI[]},
    {cgSeq[
        cgSet[v, cgKF[cgListN, {}, cgInertT][]],
        cgSet[loop, 1],
        cgWhile[cgCond[loop > 0],
            cgSeq[cgSet[st, cgPP], cgSet[cgOK, True], part[[1]],
                cgIf3[cgCond[cgOK && cgPP > st],
                    cgSet[v, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][v, part[[2]]]],
                    cgSeq[cgSet[cgOK, True], cgSet[cgPP, st], cgSet[loop, 0]]]]]], v}])

cgEmit[ParserCombinator["Some", p_, _]] := (cgInfloopCheck["Some", p];
    Module[{part = cgEmit[p], v = cgFreshV[], st = cgFreshI[], loop = cgFreshI[], cnt = cgFreshI[]},
    {cgSeq[
        cgSet[v, cgKF[cgListN, {}, cgInertT][]],
        cgSet[loop, 1], cgSet[cnt, 0],
        cgWhile[cgCond[loop > 0],
            cgSeq[cgSet[st, cgPP], cgSet[cgOK, True], part[[1]],
                cgIf3[cgCond[cgOK && cgPP > st],
                    cgSeq[cgSet[v, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][v, part[[2]]]], cgSet[cnt, cnt + 1]],
                    cgSeq[cgSet[cgOK, True], cgSet[cgPP, st], cgSet[loop, 0]]]]],
        cgSet[cgOK, cnt > 0]], v}])

cgEmit[ParserCombinator["Between", {o_, p_, c_}, _]] := Module[{po = cgEmit[o], pm = cgEmit[p], pc2 = cgEmit[c], v = cgFreshV[]},
    {cgSeq[po[[1]], cgIf2[cgOkk, pm[[1]]], cgIf2[cgOkk, pc2[[1]]],
        cgIf2[cgOkk, cgSet[v, pm[[2]]]]], v}]

cgEmit[ParserCombinator["Action", {p_, f_}, _]] := Module[{part = cgEmit[p], v = cgFreshV[]},
    {cgSeq[part[[1]],
        cgIf2[cgOkk, cgSet[v, cgKF[cgAction, {cgInertT, cgInertT}, cgInertT][cgKF[(f &), {}, cgInertT][], part[[2]]]]]], v}]

cgEmit[ParserCombinator["Lookahead", p_, _]] := Module[{part = cgEmit[p], v = cgFreshV[], st = cgFreshI[]},
    {cgSeq[cgSet[st, cgPP], part[[1]],
        cgIf2[cgOkk, cgSeq[cgSet[cgPP, st], cgSet[v, cgKF[cgNull, {}, cgInertT][]]]]], v}]

cgEmit[ParserCombinator["NotFollowedBy", p_, _]] := Module[{part = cgEmit[p], v = cgFreshV[], st = cgFreshI[]},
    {cgSeq[cgSet[st, cgPP], part[[1]], cgSet[cgPP, st],
        cgIf3[cgOkk, cgSet[cgOK, False], cgSeq[cgSet[cgOK, True], cgSet[v, cgKF[cgNull, {}, cgInertT][]]]]], v}]

cgEmit[ParserCombinator["Try", p_, _]] := cgEmit[p]

(* sepBy / sepBy1 - result is the list of p-results; a trailing separator
   is not consumed (rolled back to the last fully-matched p). *)
cgSepLoop[firstPart_, sepPart_, loopPart_, v_, cur_, loop_] :=
    cgSeq[
        cgSet[v, cgKF[cgListN, {}, cgInertT][]],
        cgSet[v, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][v, firstPart[[2]]]],
        cgSet[cur, cgPP], cgSet[loop, 1],
        cgWhile[cgCond[loop > 0],
            cgSeq[cgSet[cgPP, cur], cgSet[cgOK, True], sepPart[[1]],
                cgIf3[cgOkk,
                    cgSeq[loopPart[[1]],
                        cgIf3[cgCond[cgOK && cgPP > cur],
                            cgSeq[cgSet[v, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][v, loopPart[[2]]]], cgSet[cur, cgPP]],
                            cgSet[loop, 0]]],
                    cgSet[loop, 0]]]],
        cgSet[cgOK, True], cgSet[cgPP, cur]]

cgEmit[ParserCombinator["SepBy", {p_, sep_}, _]] := Module[
    {fp = cgEmit[p], sp = cgEmit[sep], lp = cgEmit[p], v = cgFreshV[], st = cgFreshI[], cur = cgFreshI[], loop = cgFreshI[]},
    {cgSeq[
        cgSet[st, cgPP], cgSet[cgOK, True], fp[[1]],
        cgIf3[cgOkk,
            cgSepLoop[fp, sp, lp, v, cur, loop],
            cgSeq[cgSet[cgOK, True], cgSet[cgPP, st], cgSet[v, cgKF[cgListN, {}, cgInertT][]]]]], v}]

cgEmit[ParserCombinator["SepBy1", {p_, sep_}, _]] := Module[
    {fp = cgEmit[p], sp = cgEmit[sep], lp = cgEmit[p], v = cgFreshV[], cur = cgFreshI[], loop = cgFreshI[]},
    {cgSeq[
        cgSet[cgOK, True], fp[[1]],
        cgIf2[cgOkk, cgSepLoop[fp, sp, lp, v, cur, loop]]], v}]

cgEmit[ParserCombinator["ChainLeft", {p_, op_}, _]] := Module[
    {fp = cgEmit[p], opp = cgEmit[op], np = cgEmit[p], v = cgFreshV[], cur = cgFreshI[], loop = cgFreshI[]},
    {cgSeq[
        cgSet[cgOK, True], fp[[1]],
        cgIf2[cgOkk,
            cgSeq[cgSet[v, fp[[2]]], cgSet[cur, cgPP], cgSet[loop, 1],
                cgWhile[cgCond[loop > 0],
                    cgSeq[cgSet[cgPP, cur], cgSet[cgOK, True], opp[[1]],
                        cgIf3[cgOkk,
                            cgSeq[np[[1]],
                                cgIf3[cgOkk,
                                    cgSeq[cgSet[v, cgKF[cgApplyOp, {cgInertT, cgInertT, cgInertT}, cgInertT][opp[[2]], v, np[[2]]]], cgSet[cur, cgPP]],
                                    cgSet[loop, 0]]],
                            cgSet[loop, 0]]]],
                cgSet[cgOK, True], cgSet[cgPP, cur]]]], v}]

cgEmit[ParserCombinator["ChainRight", {p_, op_}, _]] := Module[
    {fp = cgEmit[p], opp = cgEmit[op], np = cgEmit[p], v = cgFreshV[], vals = cgFreshV[], ops = cgFreshV[], cur = cgFreshI[], loop = cgFreshI[]},
    {cgSeq[
        cgSet[cgOK, True], fp[[1]],
        cgIf2[cgOkk,
            cgSeq[
                cgSet[vals, cgKF[cgListN, {}, cgInertT][]], cgSet[ops, cgKF[cgListN, {}, cgInertT][]],
                cgSet[vals, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][vals, fp[[2]]]],
                cgSet[cur, cgPP], cgSet[loop, 1],
                cgWhile[cgCond[loop > 0],
                    cgSeq[cgSet[cgPP, cur], cgSet[cgOK, True], opp[[1]],
                        cgIf3[cgOkk,
                            cgSeq[np[[1]],
                                cgIf3[cgCond[cgOK && cgPP > cur],
                                    cgSeq[
                                        cgSet[ops, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][ops, opp[[2]]]],
                                        cgSet[vals, cgKF[cgAppend, {cgInertT, cgInertT}, cgInertT][vals, np[[2]]]],
                                        cgSet[cur, cgPP]],
                                    cgSet[loop, 0]]],
                            cgSet[loop, 0]]]],
                cgSet[v, cgKF[cgChainRight, {cgInertT, cgInertT}, cgInertT][vals, ops]],
                cgSet[cgOK, True], cgSet[cgPP, cur]]]], v}]

(* nullable check for infloop diagnosis *)
cgNullableQ[ParserCombinator["Succeed", _, _]] := True
cgNullableQ[ParserCombinator["Fail", _, _]] := False
cgNullableQ[ParserCombinator["Literal", s_String, _]] := s === ""
cgNullableQ[ParserCombinator["Character", _, _]] := False
cgNullableQ[ParserCombinator["Optional" | "Many" | "Lookahead" | "NotFollowedBy" | "SepBy", _, _]] := True
cgNullableQ[ParserCombinator["Some" | "Try" | "Action" | "SepBy1" | "ChainLeft" | "ChainRight", {p_, ___}, _]] := cgNullableQ[p]
cgNullableQ[ParserCombinator["Some" | "Try" | "Action", p : ParserCombinator[__], _]] := cgNullableQ[p]
cgNullableQ[ParserCombinator["Sequence", pcs_List, _]] := AllTrue[pcs, cgNullableQ]
cgNullableQ[ParserCombinator["Choice" | "ChoiceLongest", pcs_List, _]] := AnyTrue[pcs, cgNullableQ]
cgNullableQ[ParserCombinator["Between", {o_, p_, c_}, _]] := AllTrue[{o, p, c}, cgNullableQ]
cgNullableQ[_] := False

cgInfloopCheck[which_, p_] := If[cgNullableQ[p], Throw[ParserCombinator[which, p, <||>], cgInfloop]]

(* driver: assemble the held Function and feed to FunctionCompile *)
(* Build Hold[{cgPP=cgPos, cgOK=True, v=ni..., i=0...}] in one O(n) pass.
   (A per-symbol ReplaceAll into a growing Vars[...] is O(n^2) and chokes
   on large grammars - the inlined non-terminal bodies run to tens of
   thousands of locals.) *)
cgMkVarBlock[vsyms_List, isyms_List] := With[{ni = cgNullInert[]},
    Module[{vh, ih, allh},
        vh = (With[{s = #}, Hold[s = ni]] &) /@ vsyms;
        ih = (With[{s = #}, Hold[s = 0]] &) /@ isyms;
        allh = Join[{Hold[cgPP = cgPos], Hold[cgOK = True]}, vh, ih];
        Replace[Flatten[Hold @@ allh, 1, Hold], Hold[xs___] :> Hold[{xs}]]]]

cgMkModule[Hold[vars_], Hold[body_]] := Hold[Module[vars, body]]
cgMkFunction[Hold[mb_]] := Hold[Function[{Typed[cgInput, "String"], Typed[cgPos, "MachineInteger"]}, mb]]

(* Quiet wraps the whole assembly: building char-class tests and length
   guards evaluates StringTake/StringLength/DigitQ/CharacterRange over the
   value-free codegen symbols cgInput/cgPP, which emit harmless ::strse /
   ::string / ::argtype messages. No user code runs here (actions are
   wrapped in KernelFunction, not executed), so suppressing is safe. *)
cgAssemble[pc_] := Quiet @ Module[{er, stmts, rootV, bodyHold, retH, varBlk},
    cgCtr = 0; cgVsyms = {}; cgIsyms = {};
    er = cgEmit[pc];
    stmts = er[[1]]; rootV = er[[2]];
    retH = With[{rv = rootV, ni = cgNullInert[]}, Hold[If[cgOK, {cgPP, rv}, {-1, ni}]]];
    bodyHold = cgSeq[stmts, retH];
    varBlk = cgMkVarBlock[cgVsyms, cgIsyms];
    ReleaseHold[cgMkFunction[cgMkModule[varBlk, bodyHold]]]]

(* shim bridging the compiled {finalPos, value} to the parseOk/parseErr
   internal contract that interpretDispatch's "Code" path expects. The
   stripped tree is baked into the closure so the failure re-walk works
   even after the compiled parser is serialized and reloaded in a fresh
   kernel; if that re-walk can't run (e.g. a recursive grammar whose
   ParseRecursive symbol bindings are absent after reload) it degrades to
   a generic-but-valid ParseError rather than leaking a malformed result. *)
cgShim[pc_, cf_CompiledCodeFunction] :=
    With[{stripped = ParserCombinator[pc[[1]], pc[[2]], KeyDrop[pc[[3]], "Code"]],
          recursiveQ = ! FreeQ[pc, ParserCombinator["Recursive", _, _]]},
        Function[{input, pos},
            Module[{r = cf[input, pos]},
                Which[
                    r[[1]] >= 0, parseOk[r[[2]], r[[1]]],
                    (* non-recursive: a clean interpreter re-walk recovers
                       the exact ParseError (works in-session and after
                       serialization - the stripped tree is self-contained). *)
                    ! recursiveQ, interpret[stripped, input, pos],
                    (* recursive: the re-walk would need ParseRecursive
                       symbol bindings that may be gone after a reload, so
                       report a self-contained generic failure instead. *)
                    True, parseErr[pos, "<parse failed>", safeChar[input, pos]]
                ]
            ]
        ]
    ]

(* === Recursive grammars ===
   A grammar that uses ParseRecursive can't be lowered to a single flat
   function. Instead each non-terminal becomes a typed FunctionDeclaration
   returning an inert parse-state cgOkState[value, newPos] / cgFailState,
   and a ParseRecursive[s] reference compiles to a call to that
   declaration; the whole set goes through FunctionCompile together via
   mutual recursion. The root function still returns the {finalPos, value}
   tuple the shim expects.

   NOTE: this path is correct but the Wolfram Compiler is slow on it -
   even a one-non-terminal grammar takes tens of seconds, and a grammar
   whose non-recursive references inline into one huge function (LaTeX)
   can exceed any practical budget. It is therefore invoked only on
   explicit "Recursive" -> True, and the result is meant to be compiled
   once and serialized (Export/Import of the returned ParserCombinator). *)

cgMkOk = Function[{v, p}, cgOkState[v, p]];
cgMkFail = (cgFailState &);
cgPosOf = Function[st, If[Head[st] === cgOkState, st[[2]], -1]];
cgValOf = Function[st, If[Head[st] === cgOkState, st[[1]], Null]];

cgEmit[ParserCombinator["Recursive", h : Hold[_Symbol], _]] :=
    If[KeyExistsQ[cgNtNameMap, h],
        With[{v = cgFreshV[], stTmp = cgFreshV[], fn = cgNtNameMap[h]},
            {cgSeq[
                cgSet[stTmp, fn[cgInput, cgPP]],
                cgSet[cgPP, cgKF[cgPosOf, {cgInertT}, "MachineInteger"][stTmp]],
                cgSet[cgOK, cgPP >= 0],
                cgSet[v, cgKF[cgValOf, {cgInertT}, cgInertT][stTmp]]], v}],
        Throw[ParserCombinator["Recursive", h, <||>], cgFail]]
cgNtNameMap = <||>;

(* collect all Hold[sym] reachable through Recursive nodes *)
cgCollectNts[rootPc_] := Module[{seen = {}, queue, cur, found},
    found[x_] := Cases[x, ParserCombinator["Recursive", hh_Hold, _] :> hh, Infinity];
    queue = found[rootPc];
    While[queue =!= {},
        cur = First[queue]; queue = Rest[queue];
        If[! MemberQ[seen, cur],
            AppendTo[seen, cur];
            queue = Join[queue, found[ReleaseHold[cur]]]]];
    seen]

(* one function body; asTuple=True for the root (returns {finalPos,value}),
   False for a non-terminal (returns inert state). Snapshots the fresh-var
   lists so each compiled function gets its own locals. *)
cgEmitFnBody[pc_, asTuple_] := Module[{v0 = Length[cgVsyms], i0 = Length[cgIsyms], er, stmts, rootV, retH, varBlk},
    er = cgEmit[pc];
    stmts = er[[1]]; rootV = er[[2]];
    retH = If[asTuple,
        With[{rv = rootV, ni = cgNullInert[]}, Hold[If[cgOK, {cgPP, rv}, {-1, ni}]]],
        With[{rv = rootV, mkOk = cgKF[cgMkOk, {cgInertT, "MachineInteger"}, cgInertT],
              mkFail = cgKF[cgMkFail, {}, cgInertT]},
            Hold[If[cgOK, mkOk[rv, cgPP], mkFail[]]]]];
    varBlk = cgMkVarBlock[cgVsyms[[v0 + 1 ;;]], cgIsyms[[i0 + 1 ;;]]];
    cgMkModule[varBlk, cgSeq[stmts, retH]]]

cgMkDecl[Hold[fnsym_], Hold[mb_]] :=
    Hold[FunctionDeclaration[fnsym, Typed[{"String", "MachineInteger"} -> "InertExpression"]@
        Function[{Typed[cgInput, "String"], Typed[cgPos, "MachineInteger"]}, mb]]]

cgJoinDecls[declHolds_List, Hold[rootFn_]] :=
    With[{dd = declHolds /. Hold[d_] :> d, rf = rootFn}, Hold[{dd, rf}]]

cgAssembleRec[rootPc_] := Quiet @ Module[{nts, declHolds, rootFnHold},
    cgCtr = 0; cgVsyms = {}; cgIsyms = {};
    nts = cgCollectNts[rootPc];
    cgNtNameMap = Association @ MapIndexed[
        #1 -> Symbol["Wolfram`Parser`Private`cgNT" <> ToString[#2[[1]]]] &, nts];
    declHolds = (With[{fnsym = cgNtNameMap[#], body = cgEmitFnBody[ReleaseHold[#], False]},
        cgMkDecl[Hold[fnsym], body]] &) /@ nts;
    rootFnHold = cgMkFunction[cgEmitFnBody[rootPc, True]];
    ReleaseHold[cgJoinDecls[declHolds, rootFnHold]]]


(* ============================================================
   PEG-VM backend ("Method" -> "PEGVM")
   ------------------------------------------------------------
   The Wolfram Compiler is too slow to FunctionCompile a large
   recursive grammar (LaTeX is one ~24k-node function) and old Compile
   cannot compile recursion natively. The PEG-VM sidesteps both: a single
   LPEG-style parsing machine is compiled ONCE (native, recursion via an
   explicit stack), and each grammar is lowered to an integer instruction
   table - DATA, not code - so any grammar of any size "compiles" in plain
   WL in milliseconds-to-seconds and runs on the one native VM. Captures
   record (nodeId, position) events during the native run; a WL post-pass
   rebuilds the exact result (same actions as the interpreter).

   Opcodes (3 ints/instruction, ip steps by 3):
     1 Char a | 2 Any | 3 Range a b | 17 Set a(classRow)  - terminals
     4 Jump | 5 Choice | 6 Call | 7 Return | 8 Commit
     13 PartialCommit | 14 BackCommit | 15 FailTwice | 9 Fail | 10 End
     18 OpenCap a(nodeId) | 19 CloseCap
   ============================================================ *)

(* the VM, compiled once and memoised on first use *)
pegMachine := pegMachine = Compile[
    {{prog, _Integer, 1}, {codes, _Integer, 1}, {classes, _Integer, 2},
     {start, _Integer}, {stackMax, _Integer}, {capMax, _Integer}, {maxSteps, _Integer}},
    Module[{ip = 1, sp = start, n = Length[codes], top = 0, op, a, fail, result = -1, halt = 0, c, steps = 0,
            stkIp = Table[0, {stackMax}], stkSp = Table[0, {stackMax}], stkCap = Table[0, {stackMax}],
            capTop = 0, capTag = Table[0, {capMax}], capSp = Table[0, {capMax}],
            csTop = 0, csStk = Table[0, {stackMax}], stkCs = Table[0, {stackMax}],   (* capTop save-stack (sep captures) + its backtrack record *)
            lgTop = 0, lgSp = Table[0, {stackMax}], lgBest = Table[0, {stackMax}],
            lgAlt = Table[0, {stackMax}], lgCap = Table[0, {stackMax}],
            cw = Length[classes[[1]]]},   (* char-class table width (>=128; wider when the input has non-ASCII codes remapped in) *)
        (* maxSteps bounds total work: without packrat memoisation a PEG can
           backtrack super-linearly on adversarial input, and a native loop
           is not TimeConstrained-interruptible, so we abort to a failure
           (result stays -1) - matching the interpreter's bounded behaviour. *)
        While[halt == 0,
            steps++;
            (* bail on a runaway: too many steps (catastrophic backtracking)
               or the frame stack nearing its bound (deep nesting). Both
               abort to a failure, like the interpreter's depth guard, so a
               native loop can't run away / overflow its arrays. *)
            If[steps > maxSteps || top >= stackMax - 16, halt = 1; result = -1,
            op = prog[[ip]]; a = prog[[ip + 1]]; fail = 0;
            Which[
                (* longest-match (ChoiceLongest): 20 LStart, 21 LMeasure altIdx,
                   22 LDispatch nAlts (followed by an inline address table).
                   capTop is saved/restored because measurement re-enters
                   capture-emitting non-terminal blocks via Call. *)
                op == 20, lgTop++; lgSp[[lgTop]] = sp; lgCap[[lgTop]] = capTop; lgBest[[lgTop]] = -1; lgAlt[[lgTop]] = -1; ip += 3,
                op == 21, If[sp > lgBest[[lgTop]], lgBest[[lgTop]] = sp; lgAlt[[lgTop]] = a]; sp = lgSp[[lgTop]]; capTop = lgCap[[lgTop]]; ip += 3,
                op == 22, If[lgBest[[lgTop]] < 0, lgTop--; fail = 1, sp = lgSp[[lgTop]]; capTop = lgCap[[lgTop]]; ip = prog[[ip + 3 + 3*lgAlt[[lgTop]] + 1]]; lgTop--],
                op == 1, If[sp <= n && codes[[sp]] == a, sp++; ip += 3, fail = 1],
                op == 3, If[sp <= n && a <= codes[[sp]] <= prog[[ip + 2]], sp++; ip += 3, fail = 1],
                op == 2, If[sp <= n, sp++; ip += 3, fail = 1],
                op == 17, If[sp <= n && (c = codes[[sp]]) <= cw && classes[[a, c]] == 1, sp++; ip += 3, fail = 1],
                op == 4, ip = a,
                op == 5, top++; stkIp[[top]] = a; stkSp[[top]] = sp; stkCap[[top]] = capTop; stkCs[[top]] = csTop; ip += 3,
                op == 6, top++; stkIp[[top]] = ip + 3; stkSp[[top]] = -1; stkCap[[top]] = capTop; stkCs[[top]] = csTop; ip = a,
                op == 7, ip = stkIp[[top]]; top--,
                op == 8, top--; ip = a,
                (* PartialCommit with a progress guard: if the loop body
                   advanced, update the frame and iterate; if it matched
                   without consuming (nullable body), discard its captures
                   and exit the loop instead of spinning forever. *)
                op == 13, If[sp > stkSp[[top]],
                    stkSp[[top]] = sp; stkCap[[top]] = capTop; stkCs[[top]] = csTop; ip = a,
                    capTop = stkCap[[top]]; csTop = stkCs[[top]]; top--; ip += 3],
                op == 14, sp = stkSp[[top]]; capTop = stkCap[[top]]; csTop = stkCs[[top]]; top--; ip = a,
                op == 15, top--; fail = 1,
                op == 18, capTop++; capTag[[capTop]] = a; capSp[[capTop]] = sp; ip += 3,
                op == 19, capTop++; capTag[[capTop]] = 0; capSp[[capTop]] = sp; ip += 3,
                op == 23, csTop++; csStk[[csTop]] = capTop; ip += 3,   (* CapPush: save capTop *)
                op == 24, capTop = csStk[[csTop]]; csTop--; ip += 3,    (* CapPop: discard captures since the CapPush *)
                op == 9, fail = 1,
                op == 10, result = sp; halt = 1,
                True, halt = 1
            ];
            If[fail == 1,
                While[top > 0 && stkSp[[top]] == -1, top--];
                If[top == 0, result = -1; halt = 1,
                    sp = stkSp[[top]]; ip = stkIp[[top]]; capTop = stkCap[[top]]; csTop = stkCs[[top]]; top--]]
            ]   (* close If[steps > maxSteps, abort, dispatch] *)
        ];
        Join[{result, capTop}, Take[capTag, capTop], Take[capSp, capTop]]]];

(* lower for the PEG backend: keep Action/derived; ChoiceLongest -> Choice *)
pegLower[ParserCombinator[t : ("Sequence" | "Choice" | "ChoiceLongest"), ps_List, o_]] := ParserCombinator[t, pegLower /@ ps, o]
pegLower[ParserCombinator["Action", {p_, f_}, o_]] := ParserCombinator["Action", {pegLower[p], f}, o]
pegLower[ParserCombinator[t : ("Many" | "Some" | "Optional" | "Lookahead" | "NotFollowedBy" | "Try"), p_ParserCombinator, o_]] := ParserCombinator[t, pegLower[p], o]
pegLower[ParserCombinator[t : ("SepBy" | "SepBy1" | "ChainLeft" | "ChainRight"), {p_, q_}, o_]] := ParserCombinator[t, {pegLower[p], pegLower[q]}, o]
pegLower[ParserCombinator["Between", {a_, b_, c_}, o_]] := ParserCombinator["Between", {pegLower[a], pegLower[b], pegLower[c]}, o]
pegLower[other_] := other

(* lower a grammar to <|"Prog","Classes","Spec"|>; throws pegFail on a
   node the backend doesn't handle. Recognition-only sub-emit (eRec) is
   used for separators so they don't pollute the capture tree. *)
pegCompile[root_] := Module[
    {lblCtr = 0, nodeCtr = 0, ntLbl = <||>, ntQueue = {}, classMap = <||>, classRows = {}, classPats = {}, specTable = <||>,
     fresh, classIdx, getNtLbl, reg, eNode, eRaw, eRec, eRawChoiceTail, instrs, rootLbl, blocks, h},
    fresh[] := (++lblCtr);
    (* a class is an ASCII (1..128) membership row; the pattern itself is
       kept too so non-ASCII input codes can be classified at parse time. *)
    classIdx[pat_] := Lookup[classMap, Key[pat], (
        AppendTo[classRows, Boole[charMatchesQ[FromCharacterCode[#], pat]] & /@ Range[128]];
        AppendTo[classPats, pat];
        classMap[pat] = Length[classRows])];
    getNtLbl[hh_Hold] := If[KeyExistsQ[ntLbl, hh], ntLbl[hh],
        With[{lb = fresh[]}, ntLbl[hh] = lb; AppendTo[ntQueue, hh]; lb]];
    (* store a COMPACT per-node record: rebuild only needs the type, plus
       the action function / literal string / succeed value. Keeping the
       whole ParserCombinator (with its child subtrees) per node blows the
       serialized size up by orders of magnitude. *)
    reg[pc_] := (++nodeCtr; specTable[nodeCtr] = Switch[pc[[1]],
        "Literal", {"Literal", pc[[2]]},
        "Action", {"Action", pc[[2, 2]]},
        "Succeed", {"Succeed", pc[[2]]},
        _, {pc[[1]]}]; nodeCtr);

    (* longest-match: measure each alt with eRec, remember the furthest, then
       re-run only that alt with commitEmit (eNode carries its captures). *)
    emitLongest[ps_, commitEmit_] := Module[{k = Length[ps], marks, clbls, lend = fresh[], meas, tbl, blocks},
        marks = Table[fresh[], {k + 1}]; clbls = Table[fresh[], {k}];
        meas = Join @@ Table[With[{mi = fresh[]},
            Join[{Mark[marks[[i]]], {5, Lbl[marks[[i + 1]]], 0}}, eRec[ps[[i]]],
                {{8, Lbl[mi], 0}, Mark[mi], {21, i - 1, 0}}]], {i, k}];
        tbl = Table[{0, Lbl[clbls[[j]]], 0}, {j, k}];
        blocks = Join @@ Table[Join[{Mark[clbls[[j]]]}, commitEmit[ps[[j]]], {{4, Lbl[lend], 0}}], {j, k}];
        Join[{{20, 0, 0}}, meas, {Mark[marks[[k + 1]]], {22, k, 0}}, tbl, blocks, {Mark[lend]}]];

    eRec[ParserCombinator["Literal", s_, _]] := ({1, #, 0} & /@ ToCharacterCode[s]);
    eRec[ParserCombinator["Character", pat_, _]] := {{17, classIdx[pat], 0}};
    eRec[ParserCombinator["Succeed", _, _]] := {}; eRec[ParserCombinator["Fail", _, _]] := {{9, 0, 0}};
    eRec[ParserCombinator["Sequence", ps_, _]] := Join @@ (eRec /@ ps);
    eRec[ParserCombinator["Choice", {p_}, _]] := eRec[p];
    eRec[ParserCombinator["Choice", ps_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[a], 0}}, eRec[First[ps]], {{8, Lbl[b], 0}, Mark[a]}, eRec[ParserCombinator["Choice", Rest[ps], <||>]], {Mark[b]}]];
    eRec[ParserCombinator["Many", p_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[b], 0}, Mark[a]}, eRec[p], {{13, Lbl[a], 0}, Mark[b]}]];
    eRec[ParserCombinator["Some", p_, _]] := Join[eRec[p], eRec[ParserCombinator["Many", p, <||>]]];
    eRec[ParserCombinator["Optional", p_, _]] := Module[{a = fresh[]}, Join[{{5, Lbl[a], 0}}, eRec[p], {{8, Lbl[a], 0}, Mark[a]}]];
    eRec[ParserCombinator["Between", {o_, p_, c_}, _]] := Join[eRec[o], eRec[p], eRec[c]];
    eRec[ParserCombinator["Recursive", hh_Hold, _]] := {{6, Lbl[getNtLbl[hh]], 0}};
    eRec[ParserCombinator["Lookahead", p_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[a], 0}}, eRec[p], {{14, Lbl[b], 0}, Mark[a], {9, 0, 0}, Mark[b]}]];
    eRec[ParserCombinator["NotFollowedBy", p_, _]] := Module[{a = fresh[]}, Join[{{5, Lbl[a], 0}}, eRec[p], {{15, 0, 0}, Mark[a]}]];
    eRec[ParserCombinator["Action", {p_, _}, _]] := eRec[p];
    eRec[ParserCombinator["Try", p_, _]] := eRec[p];
    eRec[ParserCombinator[t : ("SepBy" | "SepBy1"), {p_, sep_}, _]] := Module[{a = fresh[], b = fresh[], c = fresh[]},
        With[{core = Join[eRec[p], {{5, Lbl[b], 0}, Mark[a]}, eRec[sep], eRec[p], {{13, Lbl[a], 0}, Mark[b]}]},
            If[t === "SepBy", Join[{{5, Lbl[c], 0}}, core, {{8, Lbl[c], 0}, Mark[c]}], core]]];
    eRec[ParserCombinator[("ChainLeft" | "ChainRight"), {p_, op_}, _]] := eRec[ParserCombinator["Sequence", {p, ParserCombinator["Many", ParserCombinator["Sequence", {op, p}, <||>], <||>]}, <||>]];
    eRec[ParserCombinator["ChoiceLongest", ps_, _]] := emitLongest[ps, eRec];
    eRec[other_] := Throw[other, pegFail];

    eNode[r : ParserCombinator["Recursive", _, _]] := eRaw[r];
    eNode[pc_] := With[{id = reg[pc]}, Join[{{18, id, 0}}, eRaw[pc], {{19, 0, 0}}]];

    eRaw[ParserCombinator["Literal", s_, _]] := ({1, #, 0} & /@ ToCharacterCode[s]);
    eRaw[ParserCombinator["Character", pat_, _]] := {{17, classIdx[pat], 0}};
    eRaw[ParserCombinator["Succeed", _, _]] := {}; eRaw[ParserCombinator["Fail", _, _]] := {{9, 0, 0}};
    eRaw[ParserCombinator["Sequence", ps_, _]] := Join @@ (eNode /@ ps);
    eRaw[ParserCombinator["Choice", {p_}, _]] := eNode[p];
    eRaw[ParserCombinator["Choice", ps_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[a], 0}}, eNode[First[ps]], {{8, Lbl[b], 0}, Mark[a]}, eRawChoiceTail[Rest[ps]], {Mark[b]}]];
    eRawChoiceTail[{p_}] := eNode[p];
    eRawChoiceTail[ps_] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[a], 0}}, eNode[First[ps]], {{8, Lbl[b], 0}, Mark[a]}, eRawChoiceTail[Rest[ps]], {Mark[b]}]];
    eRaw[ParserCombinator["Many", p_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[b], 0}, Mark[a]}, eNode[p], {{13, Lbl[a], 0}, Mark[b]}]];
    eRaw[ParserCombinator["Some", p_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[eNode[p], {{5, Lbl[b], 0}, Mark[a]}, eNode[p], {{13, Lbl[a], 0}, Mark[b]}]];
    eRaw[ParserCombinator["Optional", p_, _]] := Module[{a = fresh[]}, Join[{{5, Lbl[a], 0}}, eNode[p], {{8, Lbl[a], 0}, Mark[a]}]];
    eRaw[ParserCombinator["Between", {o_, p_, c_}, _]] := Join[eNode[o], eNode[p], eNode[c]];
    eRaw[ParserCombinator["Recursive", hh_Hold, _]] := {{6, Lbl[getNtLbl[hh]], 0}};
    eRaw[ParserCombinator["Lookahead", p_, _]] := Module[{a = fresh[], b = fresh[]},
        Join[{{5, Lbl[a], 0}}, eRec[p], {{14, Lbl[b], 0}, Mark[a], {9, 0, 0}, Mark[b]}]];
    eRaw[ParserCombinator["NotFollowedBy", p_, _]] := Module[{a = fresh[]}, Join[{{5, Lbl[a], 0}}, eRec[p], {{15, 0, 0}, Mark[a]}]];
    eRaw[ParserCombinator["Action", {p_, _}, _]] := eNode[p];
    eRaw[ParserCombinator["Try", p_, _]] := eNode[p];
    eRaw[ParserCombinator[t : ("SepBy" | "SepBy1"), {p_, sep_}, _]] := Module[{a = fresh[], b = fresh[], c = fresh[]},
        (* the separator is recognition-only (its value is dropped), but its
           recursive calls hit capture-emitting blocks; CapPush/CapPop (23/24)
           discard those so they don't leak into the SepBy result. *)
        With[{core = Join[eNode[p], {{5, Lbl[b], 0}, Mark[a], {23, 0, 0}}, eRec[sep], {{24, 0, 0}}, eNode[p], {{13, Lbl[a], 0}, Mark[b]}]},
            If[t === "SepBy", Join[{{5, Lbl[c], 0}}, core, {{8, Lbl[c], 0}, Mark[c]}], core]]];
    eRaw[ParserCombinator[("ChainLeft" | "ChainRight"), {p_, op_}, _]] := Module[{a = fresh[], b = fresh[]},
        Join[eNode[p], {{5, Lbl[b], 0}, Mark[a]}, eNode[op], eNode[p], {{13, Lbl[a], 0}, Mark[b]}]];
    eRaw[ParserCombinator["ChoiceLongest", ps_, _]] := emitLongest[ps, eNode];
    eRaw[other_] := Throw[other, pegFail];

    rootLbl = fresh[];
    blocks = Join[{{6, Lbl[rootLbl], 0}, {10, 0, 0}}, {Mark[rootLbl]}, eNode[pegLower[root]], {{7, 0, 0}}];
    While[ntQueue =!= {},
        h = First[ntQueue]; ntQueue = Rest[ntQueue];
        blocks = Join[blocks, {Mark[ntLbl[h]]}, eNode[pegLower[ReleaseHold[h]]], {{7, 0, 0}}]];
    instrs = blocks;
    Module[{ip = 1, labelIp = <||>, real},
        Scan[If[MatchQ[#, Mark[_]], labelIp[#[[1]]] = ip, ip += 3] &, instrs];
        real = DeleteCases[instrs, Mark[_]] /. Lbl[id_] :> labelIp[id];
        <|"Prog" -> Flatten[real], "Classes" -> If[classRows === {}, {Table[0, {128}]}, classRows],
          "ClassPats" -> classPats, "Spec" -> specTable|>]
];

(* events -> capture tree, via a single O(n) recursive descent over the
   balanced open/close event list (an earlier MapAt-per-close version was
   O(n*depth) and slow on the large grammars). *)
pegBuildTree[events_] := Module[{i = 1, parse},
    parse[] := Module[{id = events[[i, 1]], start = events[[i, 2]], kids = Internal`Bag[]},
        i++;
        While[events[[i, 1]] > 0, Internal`StuffBag[kids, parse[]]];
        With[{node = <|"id" -> id, "start" -> start, "end" -> events[[i, 2]],
                       "ch" -> Internal`BagPart[kids, All]|>}, i++; node]];
    parse[]];

(* rebuild the result from the capture tree - same shaping as the interpreter *)
pegRebuild[node_, input_, spec_] := Module[{rec = spec[node["id"]], type, ch = node["ch"], r},
    type = rec[[1]];
    Switch[type,
        "Literal", rec[[2]],
        "Character", StringTake[input, {node["start"], node["end"] - 1}],
        "Sequence", pegRebuild[#, input, spec] & /@ ch,
        "Choice" | "ChoiceLongest", pegRebuild[First[ch], input, spec],
        "Many" | "Some", pegRebuild[#, input, spec] & /@ ch,
        "Optional", If[ch === {}, Missing["NoMatch"], pegRebuild[First[ch], input, spec]],
        "Between", pegRebuild[ch[[2]], input, spec],
        "Action", (r = pegRebuild[First[ch], input, spec]; With[{f = rec[[2]]}, If[ListQ[r], f @@ r, f[r]]]),
        "Try", pegRebuild[First[ch], input, spec],
        "Lookahead" | "NotFollowedBy", Null,
        "Succeed", rec[[2]],
        "SepBy" | "SepBy1", pegRebuild[#, input, spec] & /@ ch,
        "ChainLeft", Fold[Function[{acc, k}, (pegRebuild[ch[[k]], input, spec])[acc, pegRebuild[ch[[k + 1]], input, spec]]],
            pegRebuild[ch[[1]], input, spec], Range[2, Length[ch], 2]],
        "ChainRight", Module[{vals = pegRebuild[#, input, spec] & /@ ch[[1 ;; ;; 2]], ops = pegRebuild[#, input, spec] & /@ ch[[2 ;; ;; 2]]},
            Fold[Function[{acc, i}, ops[[i]][vals[[i]], acc]], Last[vals], Reverse@Range[Length[ops]]]],
        _, rec]];

(* the runnable "Code" closure for a PEG-VM-compiled parser. compiledData
   is <|Prog, Classes, ClassPats, Spec|>; returns parseOk/parseErr.

   The char-class table only covers ASCII (1..128). When the input has
   non-ASCII codes we extend it at parse time: classify each distinct
   non-ASCII code with the interpreter's own charMatchesQ (so it stays
   exactly equivalent), append those columns, and remap the codes to the
   new column indices. Safe because the grammar's Char/Range opcodes are
   all ASCII (they never compare a code > 128). *)
pegCodeFn[compiledData_] := Function[{input, pos},
    Module[{codes = ToCharacterCode[input], classes = compiledData["Classes"],
            pats = Lookup[compiledData, "ClassPats", {}], highs, len, out, fp, nc, events},
        highs = DeleteDuplicates[Select[codes, # > 128 &]];
        If[highs =!= {} && pats =!= {},
            Module[{nh = Length[highs], extra},
                extra = Outer[Boole[charMatchesQ[FromCharacterCode[#2], #1]] &, pats, highs, 1];
                classes = Join[classes, extra, 2];
                codes = codes /. Thread[highs -> (128 + Range[nh])]]];
        len = Length[codes];
        out = pegMachine[compiledData["Prog"], codes, classes, pos,
            Max[2000, 4 len], Max[8000, 24 len], Max[5000000, 30000 len]];
        fp = out[[1]];
        If[ fp < 0,
            parseErr[pos, "<parse failed>", safeChar[input, pos]],
            nc = out[[2]];
            events = Transpose[{out[[3 ;; 2 + nc]], out[[3 + nc ;; 2 + 2 nc]]}];
            parseOk[pegRebuild[pegBuildTree[events], input, compiledData["Spec"]], fp]]]];

pegParserCompile[pc_] := Module[{data = Catch[pegCompile[pc], pegFail, $pegUnsupported &]},
    If[ data === $pegUnsupported,
        Message[ParserCompile::nopeg, pc]; cgInterpFallback[pc],
        ParserCombinator[pc[[1]], pc[[2]], Append[pc[[3]], "Code" -> pegCodeFn[data]]]]];

ParserCompile::nopeg = "Parser `` uses a node the PEG-VM backend does not support; falling back to interpretive evaluation.";


ParserCompile::nocompile = "Failed to FunctionCompile parser ``; falling back to interpretive evaluation."
ParserCompile::infloop = "Parser `` loops forever (repetition of a parser that can succeed without consuming input); not compilable.";

Options[ParserCompile] = {"Recursive" -> Automatic, Method -> Automatic};

ParserCompile[pc_ParserCombinator, OptionsPattern[]] :=
    Module[{recOpt = OptionValue["Recursive"], method = OptionValue[Method], isRec, fn, cf},
        isRec = ! FreeQ[pc, ParserCombinator["Recursive", _, _]];
        Which[
            (* PEG-VM backend: lowers to an integer instruction table run on
               the once-compiled parsing machine. Scales to any grammar size
               (LaTeX/TPTP), unlike the FunctionCompile backend. *)
            method === "PEGVM",
                pegParserCompile[pc],
            (* recursive grammar: only attempt the (slow) mutual-recursion
               codegen when explicitly asked; otherwise stay interpretive. *)
            isRec && recOpt =!= True,
                cgInterpFallback[pc],
            isRec,
                fn = Catch[Catch[cgAssembleRec[pc], cgFail, $cgUnsupported &], cgInfloop, $cgInfloopHit &];
                cgFinishCompile[pc, fn, FunctionCompile @@ # &],
            True,
                fn = Catch[Catch[cgAssemble[pc], cgFail, $cgUnsupported &], cgInfloop, $cgInfloopHit &];
                cgFinishCompile[pc, fn, FunctionCompile]
        ]
    ]

(* shared tail: turn an assembled spec into a compiled ParserCombinator,
   or fall back / message as appropriate. compileFn applies FunctionCompile
   in the shape the spec needs (a function, or {decls, root}). *)
cgFinishCompile[pc_, fn_, compileFn_] := Module[{cf},
    Which[
        fn === $cgInfloopHit, Message[ParserCompile::infloop, pc]; $Failed,
        fn === $cgUnsupported, cgInterpFallback[pc],
        True,
            cf = Quiet @ Check[compileFn[fn], $Failed];
            If[ MatchQ[cf, _CompiledCodeFunction],
                ParserCombinator[pc[[1]], pc[[2]], Append[pc[[3]], "Code" -> cgShim[pc, cf]]],
                Message[ParserCompile::nocompile, pc];
                cgInterpFallback[pc]
            ]
    ]]

cgInterpFallback[pc_] := ParserCombinator[pc[[1]], pc[[2]],
    Append[pc[[3]], "Code" -> Function[{input, pos},
        interpret[ParserCombinator[pc[[1]], pc[[2]], KeyDrop[pc[[3]], "Code"]], input, pos]]]]


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

(* LaTeX, EBNF, and TPTP sub-modules all BeginPackage["Wolfram`Parser`"]
   and add their public symbols (LaTeXMathParse / LaTeXMathParser /
   EBNFParse / EBNFRules / TPTPImport) to the root context, so a single
   Needs["Wolfram`Parser`"] loads everything. *)
Get[FileNameJoin[{DirectoryName[$InputFileName], "LaTeX.wl"}]];
Get[FileNameJoin[{DirectoryName[$InputFileName], "EBNF.wl"}]];
Get[FileNameJoin[{DirectoryName[$InputFileName], "TPTP.wl"}]];

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
                ParseError[<|
                    "Position" -> 1, "Expected" -> "<input within nesting limit>",
                    "Found" -> "<input nested too deeply>"
                |>]
            ,
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
    Module[{r},
        r = Block[{$RecursionLimit = $maxParseRecursion}, interpret[pc, input, 1]];
        Which[
            MatchQ[r, _TerminatedEvaluation],
                ParseError[<|
                    "Position" -> 1, "Expected" -> "<input within nesting limit>",
                    "Found" -> "<input nested too deeply>"
                |>],
            MatchQ[r, _parseErr],
                errToParseError[r],
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


(* === ParserCompile ===
   For a "regular-grammar" subset (Literal, Character, Sequence, Choice,
   Optional, Many, Some - the parsers whose results are substrings of
   the input), generate a single fused Function via FunctionCompile.
   The compiled function returns the new position (or -1 on failure);
   the Parse driver checks the return value and reconstructs the result
   by re-walking the tree interpretively (cheap when the match is
   known to succeed).

   For trees that include Action / Capture / Recursive / Lookahead /
   NotFollowedBy / Try / SepBy / ChainLeft / ChainRight or any unknown
   node, the stub Function fallback runs the interpreter - same shape
   the user gets back, just no speedup. *)

ParserCompile[pc_ParserCombinator, OptionsPattern[]] :=
    If[ compilableQ[pc],
        compileParser[pc],
        ParserCombinator[
            pc[[1]], pc[[2]],
            Append[
                pc[[3]],
                "Code" -> Function[{input, pos},
                    interpretCompiledShim[pc, input, pos]
                ]
            ]
        ]
    ]

(* Predicate: is this combinator tree in the *recognition* subset that
   the current string-codegen lowers to a position-advancing
   CompiledCodeFunction? This is the v0.3 fast path: terminals,
   sequence, choice, repetition, between - all of whose results are
   substrings of the input.

   Action / Capture are NOT in this set yet, but NOT because the
   compiler can't run their callbacks: a Wolfram action *can* go
   through FunctionCompile via Typed[KernelFunction[f], {types} -> ret]
   (see Tests/compile-feasibility, which compiles ParseAction end to
   end). Threading those callback results requires every parser to
   return an "InertExpression" value rather than a bare position - a
   uniform-result-type redesign of the codegen that is the v0.4 work.
   Until then, Action-bearing grammars run interpretively. *)
compilableQ[ParserCombinator["Literal", _String, _]] := True
compilableQ[ParserCombinator["Character", pat_, _]] := compilableCharPatQ[pat]
compilableQ[ParserCombinator["Sequence", pcs_List, _]] := AllTrue[pcs, compilableQ]
compilableQ[ParserCombinator["Choice", pcs_List, _]] := AllTrue[pcs, compilableQ]
compilableQ[ParserCombinator["Optional", p_, _]] := compilableQ[p]
compilableQ[ParserCombinator["Many", p_, _]] := compilableQ[p]
compilableQ[ParserCombinator["Some", p_, _]] := compilableQ[p]
compilableQ[ParserCombinator["Between", {open_, p_, close_}, _]] :=
    compilableQ[open] && compilableQ[p] && compilableQ[close]
compilableQ[_] := False

compilableCharPatQ[DigitCharacter | LetterCharacter | WhitespaceCharacter |
    WordCharacter | HexadecimalCharacter | PunctuationCharacter] := True
compilableCharPatQ[_String] := True
compilableCharPatQ[HoldPattern[CharacterRange[_String, _String]]] := True
compilableCharPatQ[Alternatives[args__]] := AllTrue[{args}, compilableCharPatQ]
compilableCharPatQ[_] := False

(* === Codegen (string-based) ===
   Each emitCheck returns a string of WL source code that, when read,
   evaluates to a MachineInteger (the new position, or -1 on failure).
   The source uses bare symbols `input` and `pos` for the (yet-
   unbound) Function parameters; compileParser wraps the assembled
   source in a typed Function and feeds it through FunctionCompile.

   String codegen is verbose but avoids any of the held-expression
   evaluation pitfalls of expression-based composition - each combinator
   just splices subparser source-strings together. *)

emitCheck[ParserCombinator["Literal", s_String, _]] :=
    With[{len = StringLength[s], lit = ToString[s, InputForm]},
        "If[ StringLength[input] - pos + 1 >= " <> ToString[len] <>
        " && StringTake[input, {pos, pos + " <> ToString[len - 1] <> "}] === " <> lit <>
        ", pos + " <> ToString[len] <> ", -1]"
    ]

emitCheck[ParserCombinator["Character", pat_, _]] :=
    "If[ pos <= StringLength[input] && (" <> emitCharTest[pat] <>
    "), pos + 1, -1]"

emitCharTest[DigitCharacter] := "DigitQ[StringTake[input, {pos, pos}]]"
emitCharTest[LetterCharacter] := "LetterQ[StringTake[input, {pos, pos}]]"
emitCharTest[WhitespaceCharacter] :=
    "StringMatchQ[StringTake[input, {pos, pos}], WhitespaceCharacter]"
emitCharTest[WordCharacter] :=
    "StringMatchQ[StringTake[input, {pos, pos}], WordCharacter]"
emitCharTest[HexadecimalCharacter] :=
    "StringMatchQ[StringTake[input, {pos, pos}], HexadecimalCharacter]"
emitCharTest[PunctuationCharacter] :=
    "StringMatchQ[StringTake[input, {pos, pos}], PunctuationCharacter]"
emitCharTest[s_String] /; StringLength[s] === 1 :=
    "StringTake[input, {pos, pos}] === " <> ToString[s, InputForm]
emitCharTest[HoldPattern[CharacterRange[a_String, b_String]]] :=
    "MemberQ[" <> ToString[CharacterRange[a, b], InputForm] <>
    ", StringTake[input, {pos, pos}]]"
emitCharTest[Verbatim[Alternatives][args__]] :=
    "(" <> StringRiffle[emitCharTest /@ {args}, " || "] <> ")"

emitCheck[ParserCombinator["Sequence", pcs_List, _]] :=
    Fold[
        Function[{accSrc, nextSrc},
            "Block[{p2 = " <> accSrc <> "}, If[p2 < 0, -1, Block[{pos = p2}, " <>
                nextSrc <> "]]]"
        ],
        emitCheck[First[pcs]],
        emitCheck /@ Rest[pcs]
    ]

emitCheck[ParserCombinator["Choice", pcs_List, _]] :=
    Fold[
        Function[{accSrc, nextSrc},
            "Block[{r = " <> accSrc <> "}, If[r >= 0, r, " <> nextSrc <> "]]"
        ],
        emitCheck[First[pcs]],
        emitCheck /@ Rest[pcs]
    ]

emitCheck[ParserCombinator["Optional", p_, _]] :=
    "Block[{r = " <> emitCheck[p] <> "}, If[r >= 0, r, pos]]"

emitCheck[ParserCombinator["Many", p_, _]] :=
    With[{inner = emitCheck[p]},
        "Module[{cur = pos, prev = pos - 1, r}, " <>
            "While[True, r = Block[{pos = cur}, " <> inner <> "]; " <>
                "If[r < 0 || r <= prev, Break[]]; prev = cur; cur = r]; cur]"
    ]

emitCheck[ParserCombinator["Some", p_, _]] :=
    With[{inner = emitCheck[p]},
        "Module[{r1 = " <> inner <> ", cur, prev, r}, " <>
            "If[r1 < 0, -1, cur = r1; prev = pos; " <>
                "While[True, r = Block[{pos = cur}, " <> inner <> "]; " <>
                    "If[r < 0 || r <= prev, Break[]]; prev = cur; cur = r]; cur]]"
    ]

emitCheck[ParserCombinator["Between", {open_, p_, close_}, _]] :=
    emitCheck[ParserCombinator["Sequence", {open, p, close}, <||>]]

(* compileParser: assemble the source, wrap in a typed Function, and
   feed to FunctionCompile. *)
compileParser[pc_ParserCombinator] :=
    Module[{src, fnSrc, fn, cf},
        src = emitCheck[pc];
        fnSrc = "Function[{Typed[input, \"String\"], Typed[pos, \"MachineInteger\"]}, " <>
            src <> "]";
        fn = ToExpression[fnSrc];
        cf = Quiet @ Check[FunctionCompile[fn], $Failed];
        If[ MatchQ[cf, _CompiledCodeFunction],
            ParserCombinator[pc[[1]], pc[[2]],
                Append[pc[[3]], "Code" -> compiledShim[pc, cf]]
            ],
            Message[ParserCompile::nocompile, pc];
            ParserCombinator[pc[[1]], pc[[2]],
                Append[pc[[3]],
                    "Code" -> Function[{input, pos},
                        interpretCompiledShim[pc, input, pos]
                    ]
                ]
            ]
        ]
    ]

ParserCompile::nocompile = "Failed to FunctionCompile parser ``; falling back to interpretive evaluation."

(* compiledShim: the bridge between the integer-only compiled function
   and the parseOk / parseErr internal contract. Calls the compiled
   function for the position-advancing predicate; reconstructs the
   result via the interpreter (which is guaranteed to succeed when the
   predicate says so) when newPos is non-negative. *)
compiledShim[pc_, cf_CompiledCodeFunction] :=
    Function[{input, pos},
        Block[{newPos = cf[input, pos]},
            If[ newPos < 0,
                parseErr[pos, "<compiled-predicate failure>", safeChar[input, pos]],
                (* re-walk the original tree interpretively to build the result *)
                interpretCompiledShim[
                    ParserCombinator[pc[[1]], pc[[2]], KeyDrop[pc[[3]], "Code"]],
                    input, pos
                ]
            ]
        ]
    ]

(* The fallback / re-walker: just calls interpret. Kept as a named
   helper so the stub-fallback path and the post-success rebuild path
   share the same name. *)
interpretCompiledShim[pc_, input_, pos_] :=
    interpret[
        ParserCombinator[pc[[1]], pc[[2]], KeyDrop[pc[[3]], "Code"]],
        input, pos
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

(* LaTeX, EBNF, and TPTP sub-modules all BeginPackage["Wolfram`Parser`"]
   and add their public symbols (LaTeXMathParse / LaTeXMathParser /
   EBNFParse / EBNFRules / TPTPImport) to the root context, so a single
   Needs["Wolfram`Parser`"] loads everything. *)
Get[FileNameJoin[{DirectoryName[$InputFileName], "LaTeX.wl"}]];
Get[FileNameJoin[{DirectoryName[$InputFileName], "EBNF.wl"}]];
Get[FileNameJoin[{DirectoryName[$InputFileName], "TPTP.wl"}]];

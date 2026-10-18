(* ::Package:: *)

(* :Title: ABC.wl - the ABC language of the Ural contests, parsed and run *)
(* :Context: Wolfram`Parser`Languages`ABC` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    ABC, the language of the Arithmetic Branchless Calculator, made at Ural State University
    for teaching and used in the contests EACP 2008 and K:-)M 2009 (specification 1.06,
    24 April 2008). A program is lines: "print expr", "stop", and, from mode 2, named
    calculations "name = expr", called with arguments from mode 3. Numbers are non-negative
    integers: subtraction stops at 0, and "*" does not evaluate its left operand when its
    right one is 0, which is what ends a recursion. A name that names no calculation is a
    parameter, read from the machine's stack: the first such name in a calculation is the top
    of the stack, the next the element below, and so on. Two runs:

      ABCAST["print a - b + b"]            -> standard AST (a ContainerNode of CallNodes)
      ABCRun["print a - b + b", {3, 8}]    -> {8}, the numbers the program prints

    Precedence: * / % above + -, all left associative.
*)

BeginPackage["Wolfram`Parser`Languages`ABC`", {"Wolfram`Parser`"}]

ABCAST::usage = "ABCAST[\"program\"] parses an ABC program to a standard AST: a ContainerNode of one CallNode per line, for print, stop and named calculations."
ABCRun::usage = "ABCRun[\"program\", inputs] runs an ABC program on the ABC machine with inputs, a list of non-negative integers or a string of them, on its stack, the first on top, and gives the list of numbers it prints."
ABCGrammar::usage = "ABCGrammar[alg] builds the ABC parser over the algebra alg."
ABCSemantic::usage = "ABCSemantic is the algebra that builds an ABC program as plain Wolfram data: a list of statements {\"print\", expr}, {\"stop\"} and {\"define\", name, expr}, with integers, names as strings, {op, left, right} and {\"call\", name, args}."

ABCRun::syntax = "The ABC program does not parse: `1`."
ABCRun::input = "`1` is not a list of non-negative integers."

Begin["`Private`"]

(* --- the grammar, parameterised over an algebra --- *)
ABCGrammar[alg_] := Module[{sp, tok, number, name, args, call, unit, bin, expr, top, stop, print, define, line, blank, nl},
    expr = RecCell[];
    (* spaces and tabs separate tokens anywhere on a line; a line break ends a statement *)
    sp = ParseRegex["[ \\t]*"];
    tok[p_] := ParseAction[p ~~ sp, #1 &];

    number = SpannedToken[ParseRegex["[0-9]+"], sp, Function[s, alg["Leaf"]["Integer", s]]];
    name = SpannedToken[ParseRegex["[A-Za-z_][A-Za-z0-9_]*"], sp, Function[s, alg["Leaf"]["Symbol", s]]];

    args = ParseSepBy[RecRef[expr], tok @ ParseLiteral[","]];
    call = ParseAction[name ~~ tok @ ParseLiteral["("] ~~ args ~~ tok @ ParseLiteral[")"], (alg["Call"][#1, #3]) &];
    unit = ParseChoice[
        ParseBetween[tok @ ParseLiteral["("], RecRef[expr], tok @ ParseLiteral[")"]],
        number, call, name];

    bin[op_] := ParseAction[tok @ ParseLiteral[op], (Function[{l, r}, alg["Binary"][op, l, r]]) &];
    top = ParseOperatorTable[unit, {
        {{"InfixL", bin["*"]}, {"InfixL", bin["/"]}, {"InfixL", bin["%"]}},
        {{"InfixL", bin["+"]}, {"InfixL", bin["-"]}}
    }];
    SetRec[expr, top];

    (* keywords are case insensitive, as names are; print needs a space after it *)
    stop = ParseAction[
        SpannedToken[ParseRegex["(?i)stop(?=[ \\t]*(?:\\r?\\n|\\z))"], sp, Function[s, alg["Leaf"]["Keyword", s]]],
        (alg["Stop"][#1]) &];
    print = ParseAction[
        SpannedToken[ParseRegex["(?i)print(?=[ \\t])"], sp, Function[s, alg["Leaf"]["Keyword", s]]] ~~ RecRef[expr],
        (alg["Print"][#1, #2]) &];
    define = ParseAction[name ~~ tok @ ParseLiteral["="] ~~ RecRef[expr], (alg["Define"][#1, #3]) &];
    line = ParseAction[sp ~~ ParseChoice[stop, print, define], #2 &];

    blank = ParseRegex["(?:[ \\t]*\\r?\\n)*[ \\t]*"];
    nl = ParseRegex["(?:[ \\t]*\\r?\\n)+"];
    ParseAction[blank ~~ ParseSepBy[line, nl] ~~ blank, (alg["Program"][#2]) &]
]

(* --- the standard AST: a line is a CallNode headed by its keyword, a definition an "=" --- *)
abcAstAlgebra = Join[ASTAlgebra, <|
    "Print"   -> Function[{keyword, e}, CallNode[keyword, {e}, <||>]],
    "Stop"    -> Function[keyword, CallNode[keyword, {}, <||>]],
    "Define"  -> Function[{n, e}, BinaryNode["=", {n, e}, <||>]],
    "Program" -> Function[lines, lines]
|>]

(* --- the meaningful algebra: the program as plain data, names lower-cased --- *)
ABCSemantic = <|
    "Leaf"    -> Function[{kind, src}, Switch[kind, "Integer", FromDigits[src], "Symbol", ToLowerCase[src], _, src]],
    "Binary"  -> Function[{op, l, r}, {op, l, r}],
    "Call"    -> Function[{head, args}, {"call", head, args}],
    "Print"   -> Function[{keyword, e}, {"print", e}],
    "Stop"    -> Function[keyword, {"stop"}],
    "Define"  -> Function[{n, e}, {"define", n, e}],
    "Program" -> Function[lines, lines]
|>

$astParser = ABCGrammar[abcAstAlgebra]
$semParser = ABCGrammar[ABCSemantic]

ABCAST[s_String] := With[{r = Parse[$astParser, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

(* --- the machine --- *)

(* the mode a program needs: 3 with a call, 2 with a named calculation, 1 otherwise *)
programMode[program_List] := Which[
    ! FreeQ[program, {"call", _String, _List}], 3,
    MemberQ[program, {"define", __}], 2,
    True, 1
]

(* the parameters of a calculation: the names that name no calculation, in the order they
   first appear in its text; a call's head is a calculation, its arguments are text *)
parameters[e_, defs_Association] := DeleteDuplicates @ Flatten @ Reap[paramWalk[e, defs]][[2]]
paramWalk[n_Integer, _] := Null
paramWalk[x_String, defs_] := If[! KeyExistsQ[defs, x], Sow[x]]
paramWalk[{"call", _String, args_List}, defs_] := Scan[paramWalk[#, defs] &, args]
paramWalk[{_String, l_, r_}, defs_] := (paramWalk[l, defs]; paramWalk[r, defs])

inputList[s_String] := With[{words = StringSplit[s]},
    If[AllTrue[words, StringMatchQ[#, DigitCharacter ..] &], FromDigits /@ words, $Failed]]
inputList[l_List] /; AllTrue[l, IntegerQ[#] && NonNegative[#] &] := l
inputList[_] := $Failed

machineFailure[tag_String, message_String, out_List, line_] := Failure[tag, <|
    "MessageTemplate" -> message, "Output" -> out, "Line" -> line|>]

Options[ABCRun] = {"Mode" -> 3, "Calls" -> "Push", "MaxNumber" -> Infinity, "MaxDepth" -> 2000};

(* the inputs are a list or a string; an empty input list is not mistaken for options *)
ABCRun[s_String, inputs : (_List | _String), opts : OptionsPattern[]] := Module[{program = Parse[$semParser, s], stack},
    stack = inputList[inputs];
    Which[
        FailureQ[program], Message[ABCRun::syntax, program["Message"]]; program,
        stack === $Failed, Message[ABCRun::input, inputs]; $Failed,
        programMode[program] > OptionValue["Mode"],
            Failure["ABCMode", <|"MessageTemplate" -> "The program needs mode `1`; the machine runs in mode `2`.",
                "MessageParameters" -> {programMode[program], OptionValue["Mode"]}|>],
        True, runMachine[program, stack, OptionValue["Calls"], OptionValue["MaxNumber"], OptionValue["MaxDepth"]]
    ]
]
ABCRun[s_String, opts : (_Rule | _RuleDelayed) ...] := ABCRun[s, {}, opts]

(* The stack is an array of cells, the first input on top: offset i from the top is cell
   top - i, and cell 1 is the bottom. Every calculation numbers its own parameters. A call
   either pushes its arguments, the last first, and pops them after ("Push", the rule of
   EACP 2008), or moves the top up by the smaller of the callee's parameter count and the
   argument count, writes the arguments from the top down, over what was there, and after
   the call pops as many cells as it had arguments, an empty stack staying empty ("Advance",
   K:-)M 2009): a call with more arguments than parameters so drops the extra cells. An
   argument that would land below the bottom is lost. A binary operator evaluates its right
   operand first; "*" stops there at 0. *)
runMachine[program_List, inputs_List, calls_, maxNumber_, maxDepth_] := Module[
    {defs = <||>, params = <||>, cells, top, out = {}, line = None, depth = 0, check, read, ev, calc, result},
    Scan[If[MatchQ[#, {"define", _, _}] && ! KeyExistsQ[defs, #[[2]]], defs[#[[2]]] = #[[3]]] &, program];
    params = AssociationMap[parameters[defs[#], defs] &, Keys[defs]];
    cells = Association @ MapIndexed[(Length[inputs] - First[#2] + 1) -> #1 &, inputs];
    top = Length[inputs];
    check[v_] := If[v > maxNumber, Throw[machineFailure["ABCOverflow", "A result exceeds the largest number, " <> ToString[maxNumber] <> ".", out, line], "abc"], v];
    read[offset_] := With[{index = top - offset},
        If[KeyExistsQ[cells, index], cells[index],
            Throw[machineFailure["ABCStack", "A parameter reads below the bottom of the stack.", out, line], "abc"]]];
    ev[n_Integer, _, _] := check[n];
    ev[x_String, ps_, active_] := If[KeyExistsQ[defs, x], calc[x, active], read[First[FirstPosition[ps, x]] - 1]];
    ev[{"call", f_String, args_List}, ps_, active_] := Module[{vals, saved, k = Length[args], r},
        If[! KeyExistsQ[defs, f], Throw[machineFailure["ABCName", "There is no calculation named " <> f <> ".", out, line], "abc"]];
        vals = Reverse[ev[#, ps, active] & /@ Reverse[args]];
        If[++depth > maxDepth, Throw[machineFailure["ABCDepth", "The calls nest deeper than " <> ToString[maxDepth] <> ".", out, line], "abc"]];
        saved = top;
        If[ calls === "Advance",
            top = top + Min[Length[params[f]], k];
            Do[If[top - j + 1 >= 1, cells[top - j + 1] = vals[[j]]], {j, k}],
            Do[top++; cells[top] = vals[[j]], {j, k, 1, -1}]
        ];
        r = calc[f, {}];
        top = If[calls === "Advance", Max[top - k, 0], saved];
        depth--;
        r
    ];
    ev[{op_String, l_, r_}, ps_, active_] := With[{rv = ev[r, ps, active]},
        If[ op === "*" && rv === 0, 0,
            With[{lv = ev[l, ps, active]}, check @ Switch[op,
                "+", lv + rv,
                "-", Max[lv - rv, 0],
                "*", lv rv,
                "/" | "%", If[rv === 0,
                    Throw[machineFailure["ABCDivision", "A division by zero.", out, line], "abc"],
                    If[op === "/", Quotient[lv, rv], Mod[lv, rv]]]
            ]]
        ]
    ];
    (* a calculation evaluated again within itself, with no call between, has no value *)
    calc[f_, active_] := If[MemberQ[active, f],
        Throw[machineFailure["ABCCycle", "The calculation " <> f <> " depends on itself.", out, line], "abc"],
        ev[defs[f], params[f], Append[active, f]]];
    result = Block[{$RecursionLimit = Max[$RecursionLimit, 64 Min[maxDepth, 10^5] + 4096]},
        Catch[
            Do[
                line = i;
                Switch[program[[i]],
                    {"stop"}, Break[],
                    {"print", _}, With[{e = program[[i, 2]]}, AppendTo[out, ev[e, parameters[e, defs], {}]]],
                    _, Null
                ],
                {i, Length[program]}
            ];
            out,
            "abc"
        ]
    ];
    result
]

End[]

EndPackage[]

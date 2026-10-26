#!/usr/bin/env wolframscript
(* Holds the engine's "RegexLike" to what it claims: that a regex's leftmost longest match, as the
   C library's regexec takes it, is the match the program finds first, at every start. Over random
   sequences of literals and repeats of one character and of more, and strings of a and b, it
   compares the end of the program's first match with the longest end of all its matches, wherever
   the program says a regex matches as it does. Run it with Wolfram 15:
       wl -f dev/check-regex-like.wls [cases] [seed]
   It prints the patterns where the two differ, then the counts. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];

(* the arguments after the script's path, by wolframscript or by WolframKernel -script *)
arguments = If[$ScriptCommandLine =!= {}, Rest[$ScriptCommandLine], Replace[$CommandLine, {{___, "-script", _, rest___} :> {rest}, _ -> {}}]];
count = If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 20000];
seed = If[Length[arguments] >= 2, Interpreter["Integer"][arguments[[2]]], 1];
SeedRandom[seed];

part[] := RandomChoice[{
    RandomChoice[{"a", "b", "ab", "ba"}] &,
    RandomChoice[{Repeated, RepeatedNull}][RandomChoice[{"a", "b", {"a", "b"}, _}]] &,
    RandomChoice[{Repeated, RepeatedNull}][RandomChoice[{"ab", "ba", "aa", "a" ~~ "b"..., {"a", "b"} ~~ "a"}]] &,
    Pattern[Evaluate[RandomChoice[{x, y}]], RandomChoice[{"a", "b"..., {"a", "b"} ..}]] &}][]

Begin["Wolfram`Parser`StringPatterns`Private`"];
(* the end of the program's first match at i, and the longest end of all its matches there *)
firstEnd[p_, z_, i_] := Replace[matched[p, z, i, <||>, Function[{j, b}, j]], $noMatch -> None]
longestEnd[p_, z_, i_] := Replace[Reap[matched[p, z, i, <||>, Function[{j, b}, Sow[j, longestEnd]; $noMatch]], longestEnd][[2]],
    {{ends_List} :> Max[ends], _ -> None}]
End[];

like = 0; differ = {};
Do[
    With[{p = StringExpression @@ Table[part[], RandomInteger[{2, 3}]], s = StringJoin[RandomChoice[{"a", "b"}, RandomInteger[{1, 8}]]]},
        With[{program = StringPatternProgram[p]},
            If[TrueQ[program["RegexLike"]],
                like++;
                With[{z = Wolfram`Parser`StringPatterns`Private`subject[ToCharacterCode[s], StringLength[s], s], ir = program["Program"]},
                    With[{at = SelectFirst[Range[0, StringLength[s]],
                            Wolfram`Parser`StringPatterns`Private`firstEnd[ir, z, #] =!= Wolfram`Parser`StringPatterns`Private`longestEnd[ir, z, #] &]},
                        If[IntegerQ[at], AppendTo[differ, {p, s, at}]]]]]]],
    {count}];

Scan[Print["   ", ToString[#[[1]], InputForm], " on ", #[[2]], " at ", #[[3]]] &, Take[differ, UpTo[20]]];
Print["regex like: ", count, " cases, seed ", seed, ": ", like, " where a regex matches as the program does, ", Length[differ],
    " where its longest match is not the program's first"];

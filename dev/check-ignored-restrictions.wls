#!/usr/bin/env wolframscript
(* Holds the "IgnoredRestrictions" of the programs of string patterns to Wolfram 15's
   StringExpression::cond: the later occurrences of a name whose own pattern the matcher ignores,
   of each of which Wolfram 15 warns once, the first time it compiles the pattern. Wolfram 15 keeps
   what it compiles, so each pattern here is new to the session: the listed ones name u, v and w,
   the random ones x, y and z. Run it with Wolfram 15:
       wl -f dev/check-ignored-restrictions.wls [seed]
   It prints the patterns that disagree, then the counts. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
Get[FileNameJoin[{root, "Parser", "Kernel", "StringPatterns.wl"}]];
(* the arguments after the script's path, by wolframscript or by WolframKernel -script *)
arguments = If[$ScriptCommandLine =!= {}, Rest[$ScriptCommandLine], Replace[$CommandLine, {{___, "-script", _, rest___} :> {rest}, _ -> {}}]];
SeedRandom[If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 5]];

w15[p_] := Cases[EvaluationData[StringCases["ab", p]]["MessagesExpressions"], Hold[Message[MessageName[StringExpression, "cond"], _, b_]] :> HoldForm[b]];
differing[patterns_List] := With[{first = AssociationMap[w15, patterns]},
    Select[Map[{#, StringPatternProgram[#]["IgnoredRestrictions"], first[#]} &, patterns], #[[2]] =!= #[[3]] &]];
show[differ_List] := Scan[Print["   ", InputForm[#[[1]]], "  engine ", InputForm[#[[2]]], "  W15 ", InputForm[#[[3]]]] &, Take[differ, UpTo[12]]];

listed = {(u : "a") ~~ (u : "a"), ((u : "a") | (u : "b")) ~~ ((u : "a") | (u : "b")), (u : "b") ~~ (u : _), (u : "b") ~~ u__, (u : "b") ~~ (u : Except["b"]),
    (u : "a") | (u : "c"), u_ ~~ u_, (u : "a") ~~ u__ ~~ (u : "b"), (u : "c") ~~ ((u : "d") | (v : "d")) ~~ (v : "d"), ((u : "d") ..) ~~ (u : "d"),
    (u : "e") ~~ (u : "e" ..), u : (u : "a"), (v : "a") ~~ (v : "b") ~~ (v : "c") ~~ (v : "d") ~~ (v : "e") ~~ (v : "f"), (w : "a") ~~ (w : "c") ~~ (w : "c"),
    {(w : "b") ~~ (w : "c"), (w : "q") ~~ (w : "r")}, (u : "a") ~~ (u : (v : "b")) ~~ (v : "b")};
listedDiffer = differing[listed];
show[listedDiffer];
Print["listed: ", Length[listed], " patterns, ", Length[listedDiffer], " differ"];

leaf[] := RandomChoice[{"a", "b", _, __, ___, DigitCharacter, Except["a"], "ab"}];
pat[0] := If[RandomReal[] < 0.5, Pattern[Evaluate[RandomChoice[{x, y, z}]], leaf[]], leaf[]];
pat[d_] := RandomChoice[{pat[0] &, StringExpression[pat[d - 1], pat[d - 1]] &, Alternatives[pat[d - 1], pat[d - 1]] &, Repeated[pat[d - 1]] &,
    Pattern[Evaluate[RandomChoice[{x, y, z}]], pat[d - 1]] &, Shortest[pat[d - 1]] &}][];
random = DeleteDuplicates[Table[StringExpression[pat[RandomInteger[{0, 2}]], pat[RandomInteger[{0, 2}]]], {1500}]];
randomDiffer = differing[random];
show[randomDiffer];
Print["random: ", Length[random], " patterns, ", Length[randomDiffer], " differ, ", Count[random, p_ /; StringPatternProgram[p]["IgnoredRestrictions"] =!= {}], " with a restriction ignored"];
If[listedDiffer =!= {} || randomDiffer =!= {}, Exit[1]];

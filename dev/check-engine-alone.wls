#!/usr/bin/env wolframscript
(* Loads the engine of string patterns alone, as a kernel does at its first string pattern, from
   Parser/Kernel/StringPatterns.wl, and checks that it loads nothing more of the paclet than the
   characters of the classes, from CharacterClassRuns.wl: no core, no reader. Then it matches a few
   patterns, classes beyond ASCII among them, as Wolfram 15's String functions do. Run it with
   Wolfram 15:
       wl -f dev/check-engine-alone.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
contexts = Contexts[];
time = First[AbsoluteTiming[Get[FileNameJoin[{root, "Parser", "Kernel", "StringPatterns.wl"}]]]];
added = Complement[Contexts[], contexts];

matches[s_String, patterns_List, mode_String] := StringPatternMatches[s, StringPatternProgram /@ patterns, mode]
(* a list of patterns is a program each, as StringCases takes them *)
texts[s_String, p_] := Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, matches[s, Flatten[{p}], "Each"]]
cases = {
    {"a1b22", DigitCharacter ..}, {"h\[EAcute]llo w\[ODoubleDot]rld", LetterCharacter ..},
    {"1" <> FromCharacterCode[{16^^0661, 16^^0662}] <> " 2", DigitCharacter ..}, {"<a><b>", "<" ~~ Shortest[__] ~~ ">"},
    {"ab", {"x"..., "a"}}, {"a\[NonBreakingSpace]b", WhitespaceCharacter}};
agree = Count[cases, {s_, p_} /; texts[s, p] === StringCases[s, p]];
positions = Map[{#[[1]] + 1, #[[2]]} &, matches["aaa", {"a", "aa"}, "Overlapping"]] === StringPosition["aaa", {"a", "aa"}];

Print["engine alone: loaded in ", Round[1000 time, 0.1], " ms, contexts added ", added, "; ",
    agree, " of ", Length[cases], " cases as StringCases, overlapping positions as StringPosition: ", positions];
If[MemberQ[$Packages, "Wolfram`Parser`"] || Names["Wolfram`Parser`ParserCombinator"] =!= {} || Names["Wolfram`Parser`Languages`*`*"] =!= {} ||
    ! SubsetQ[{"Wolfram`Parser`StringPatterns`", "Wolfram`Parser`StringPatterns`Private`", "Wolfram`Parser`Private`", "Wolfram`", "Wolfram`Parser`"}, added] ||
    agree < Length[cases] || ! positions, Exit[1]];

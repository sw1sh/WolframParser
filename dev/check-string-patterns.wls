#!/usr/bin/env wolframscript
(* Holds the engine of string patterns, Wolfram`Parser`StringPatterns`, to Wolfram 15's own String
   functions over random patterns and strings: for each pattern that has a program, the texts of
   its matches against StringCases, their spans one at each start against StringPosition, whether
   a whole string matches against StringMatchQ, the names it binds against a rule's right side,
   the parts between its matches against StringSplit, and, with a second pattern, which of two
   rules matched against StringCases, StringPosition and StringReplace; and that a pattern that has
   no program is no string pattern in Wolfram 15. Run it with Wolfram 15:
       wl -f dev/check-string-patterns.wls [cases] [seed]
   It prints what disagrees, then the counts. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];

arguments = Rest[$ScriptCommandLine];
count = If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 3000];
seed = If[Length[arguments] >= 2, Interpreter["Integer"][arguments[[2]]], 1];
SeedRandom[seed];

(* --- random strings and patterns --- *)

$alphabet = {"a", "b", "c", "1", "2", " ", "\n", "-", ".", "_", "\[EAcute]", FromCharacterCode[16^^0663], "\[Alpha]", "\t", "A"};
randomString[] := StringJoin[RandomChoice[$alphabet, RandomInteger[{0, 8}]]]

(* no literal holds a regex's metacharacter: in Except[c, p], Wolfram 15 matches p's literals as the
   text of a regex, StringCases["aa+", Except["x", "a+"]] giving {"aa"} [WL 15.0.0], where the
   engine matches them as text *)
$literals = {"a", "b", "ab", "ba", "aa", "1", " ", "-", ",", "\[EAcute]"};
$classes = {DigitCharacter, LetterCharacter, WordCharacter, WhitespaceCharacter, PunctuationCharacter, HexadecimalCharacter};
$anchors = {StartOfString, EndOfString, StartOfLine, EndOfLine, WordBoundary};

leaf[] := RandomChoice[{4, 2, 4, 1, 1, 1} -> {
    RandomChoice[$literals] &,
    RandomChoice[{Blank[], BlankSequence[], BlankNullSequence[]}] &,
    RandomChoice[$classes] &,
    RandomChoice[{Whitespace, NumberString, {"a", "1"}, {"b", " ", "-"}}] &,
    RandomChoice[$anchors] &,
    Except[RandomChoice[Join[$classes, {"a", {"a", "1"}}]]] &}][]

pattern[0] := leaf[]
pattern[depth_Integer] := RandomChoice[{6, 4, 3, 2, 2, 1, 1, 2, 1, 1, 1} -> {
    leaf[] &,
    StringExpression[pattern[depth - 1], pattern[depth - 1]] &,
    Alternatives[pattern[depth - 1], pattern[depth - 1]] &,
    Repeated[pattern[depth - 1]] &,
    RepeatedNull[pattern[depth - 1]] &,
    Repeated[pattern[depth - 1], RandomChoice[{{1, 2}, {0, 1}, {2}, 2}]] &,
    Shortest[pattern[depth - 1]] &,
    Pattern[Evaluate[RandomChoice[{x, y}]], pattern[depth - 1]] &,
    Except[RandomChoice[$classes], pattern[depth - 1]] &,
    PatternTest[pattern[depth - 1], StringLength[#] <= 2 &] &,
    Condition[Pattern[z, pattern[depth - 1]], StringLength[z] > 1] &}][]

(* --- the engine's answers --- *)

engineMatches[s_String, patterns_List, mode_String] := StringPatternMatches[s, StringPatternProgram /@ patterns, mode]
texts[s_String, matches_List] := Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, matches]
between[s_String, matches_List] := Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, Partition[Join[{0}, Catenate[Map[Take[#, 2] &, matches]], {StringLength[s]}], 2]]
engineCases[s_String, p_] := texts[s, engineMatches[s, {p}, "Each"]]
enginePosition[s_String, ps_List] := Map[{#[[1]] + 1, #[[2]]} &, engineMatches[s, ps, "Overlapping"]]
engineMatchQ[s_String, p_] := engineMatches[s, {StartOfString ~~ p ~~ EndOfString}, "First"] =!= {}
engineNames[s_String, p_] := Map[{x, y} /. #[[4]] &, engineMatches[s, {p}, "Each"]]
engineRules[s_String, p_, q_] := Map[#[[3]] &, engineMatches[s, {p, q}, "Each"]]
engineReplace[s_String, p_, q_] := With[{matches = engineMatches[s, {p, q}, "First"]}, StringJoin[Riffle[between[s, matches], Map[{"<1>", "<2>"}[[#[[3]]]] &, matches]]]]
engineSplit[s_String, p_] := With[{parts = between[s, engineMatches[s, {p}, "First"]]},
    With[{kept = Flatten[Position[parts, Except[""], {1}, Heads -> False]]}, If[kept === {}, {}, Take[parts, {First[kept], Last[kept]}]]]]

(* Wolfram 15's, $Failed where a pattern is not one there: a pattern that is no string pattern
   in Wolfram 15 messages, and is no case *)
native[e_] := Block[{$Messages = {}}, Check[TimeConstrained[e, 5, $Aborted], $Failed]]
SetAttributes[native, HoldFirst];

answers[s_String, p_, q_] := <|
    "Cases" -> {engineCases[s, p], native[StringCases[s, p]]},
    "Position" -> {enginePosition[s, {p}], native[StringPosition[s, p]]},
    "MatchQ" -> {engineMatchQ[s, p], native[StringMatchQ[s, p]]},
    "Names" -> {engineNames[s, p], native[StringCases[s, p :> {x, y}]]},
    "Rules" -> {engineRules[s, p, q], native[StringCases[s, {p -> 1, q -> 2}]]},
    "Positions" -> {enginePosition[s, {p, q}], native[StringPosition[s, {p, q}]]},
    "Replace" -> {engineReplace[s, p, q], native[StringReplace[s, {p -> "<1>", q -> "<2>"}]]},
    "Split" -> {engineSplit[s, p], native[StringSplit[s, p]]}|>

(* --- the cases --- *)

differ = {}; noProgram = 0; notNative = 0; agree = 0; twice = 0;
Do[
    With[{p = pattern[RandomInteger[{0, 3}]], q = pattern[RandomInteger[{0, 2}]], s = randomString[]},
        Which[
            (* a pattern that has no program is none in Wolfram 15 either *)
            StringPatternProgram[p]["Program"] === None || StringPatternProgram[q]["Program"] === None,
                noProgram++;
                Scan[Function[r, If[StringPatternProgram[r]["Program"] === None && ! MatchQ[native[StringCases[s, r]], $Failed | $Aborted],
                    AppendTo[differ, {s, r, None, <|"Program" -> {None, native[StringCases[s, r]]}|>}]]], {p, q}],
            (* a test reads a name that occurs more than once by where it occurs first [WL 15.0.0], and the
               engine by what it matched: no case *)
            Count[{p, q}, Verbatim[Pattern][z, _], Infinity] > 1, twice++,
            True, With[{a = answers[s, p, q]},
                With[{bad = Select[a, MatchQ[#[[2]], $Failed | $Aborted] &], wrong = Select[a, ! MatchQ[#[[2]], $Failed | $Aborted] && #[[1]] =!= #[[2]] &]},
                    If[Length[bad] === Length[a], notNative++,
                        If[wrong === <||>, agree++, AppendTo[differ, {s, p, q, wrong}]]]]]]],
    {count}];

Scan[Function[d, Print["   ", ToString[d[[1]], InputForm], "  ", ToString[d[[2]], InputForm], "  (second: ", ToString[d[[3]], InputForm], ")"];
    KeyValueMap[Print["      ", #1, ": engine ", ToString[#2[[1]], InputForm], "  W15 ", ToString[#2[[2]], InputForm]] &, d[[4]]]],
    Take[differ, UpTo[40]]];
Print["string patterns: ", count, " cases, seed ", seed, ": ", agree, " agree, ", Length[differ], " differ, ",
    noProgram, " with no program, ", notNative, " no string pattern in Wolfram 15, ", twice, " with a tested name twice"];

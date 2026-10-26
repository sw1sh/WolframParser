#!/usr/bin/env wolframscript
(* Holds the typed matcher of the engine of string patterns to the programs' interpreter, the
   reference, over random patterns and strings: StringPatternMatches by each, of one pattern and of
   two, in each mode. With compile, it also builds the matcher by FunctionCompile and holds its
   matches to those of the matcher Compile builds, on a long text. Run it with Wolfram 15:
       wl -f dev/check-string-vm.wls [cases] [seed] [compile]
   It prints what disagrees, then the counts and times. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];

(* the arguments after the script's path, by wolframscript or by WolframKernel -script *)
arguments = If[$ScriptCommandLine =!= {}, Rest[$ScriptCommandLine], Replace[$CommandLine, {{___, "-script", _, rest___} :> {rest}, _ -> {}}]];
count = If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 2000];
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

(* --- the cases --- *)

differ = {}; same = 0; tooLong = 0; interpreterTime = 0.; vmTime = 0.;

(* a run past 10 seconds or a gigabyte, $Aborted: every way of a repeat of repeats that may match
   nothing is more than either matcher makes in that, which both are counted for *)
bounded[e_] := MemoryConstrained[TimeConstrained[e, 10, $Aborted], 10^9, $Aborted]
SetAttributes[bounded, HoldFirst];
Do[
    With[{p = pattern[RandomInteger[{0, 3}]], q = pattern[RandomInteger[{0, 2}]], s = randomString[]},
        With[{programs = StringPatternProgram /@ {p, q}},
            If[ FreeQ[Map[#["Program"] &, programs], None],
                Do[ Module[{a, b, ta, tb},
                        {ta, a} = AbsoluteTiming[bounded[StringPatternMatches[s, Take[programs, n], mode, Method -> "Interpreter"]]];
                        {tb, b} = AbsoluteTiming[bounded[StringPatternMatches[s, Take[programs, n], mode]]];
                        Which[
                            a === $Aborted && b === $Aborted, tooLong++,
                            a === b, interpreterTime += ta; vmTime += tb; same++,
                            True, AppendTo[differ, {s, Take[{p, q}, n], mode, a, b}]]],
                    {n, 1, 2}, {mode, {"First", "Each", "Overlapping", "All"}}]]]],
    {count}];

Scan[Print["   ", ToString[#[[1]], InputForm], "  ", ToString[#[[2]], InputForm], "  ", #[[3]], "\n      interpreter ", ToString[#[[4]], InputForm],
    "\n      vm          ", ToString[#[[5]], InputForm]] &, Take[differ, UpTo[20]]];
Print["string vm: ", count, " cases, seed ", seed, ": ", same, " runs agree, ", Length[differ], " differ, ", tooLong, " too long for both; interpreter ", Round[interpreterTime, 0.01],
    " s, vm ", Round[vmTime, 0.01], " s, each new pattern's bytecode made"];

(* --- FunctionCompile --- *)

(* the names of the engine's own, written whole: the block is read whole, before a Begin in it *)
If[ MemberQ[arguments, "compile"],
    {time, compiled} = AbsoluteTiming[FunctionCompile[{Wolfram`Parser`StringPatterns`Private`$vmMemberDeclaration, Wolfram`Parser`StringPatterns`Private`$vmDeclaration},
        Wolfram`Parser`StringPatterns`Private`vmRun]];
    text = StringJoin[Table[RandomChoice[{"item", "ab", "<x>", " ", "a1", "22", ",", "\n", "abab", "z"}], {3000}]];
    codes = Developer`ToPackedArray[ToCharacterCode[text]];
    agree = Flatten[Outer[Function[{p, mode}, With[{bc = Wolfram`Parser`StringPatterns`Private`vmBytecode[{StringPatternProgram[p]["Program"]}]},
        With[{classes = Wolfram`Parser`StringPatterns`Private`vmClasses[bc, codes], none = Developer`ToPackedArray[{0}][[1 ;; 0]],
                parameters = Developer`ToPackedArray[{mode, 0, 1, bc["MaxNames"], bc["Registers"], bc["Table"]}]},
            compiled[bc["Code"], bc["Pool"], classes, codes, parameters, none] ===
                Wolfram`Parser`StringPatterns`Private`vmFunction[bc["Code"], bc["Pool"], classes, codes, parameters, none]]]],
        {"a" ~~ DigitCharacter .., x : LetterCharacter .., "<" ~~ Shortest[__] ~~ ">", (x : "ab") .., x_ ~~ x_, WordBoundary ~~ "item", "\[Alpha]" ~~ LetterCharacter ..},
        {2, 4}, 1]];
    Print["FunctionCompile: ", Head[compiled], " in ", Round[time], " s; its matches as Compile's: ", Count[agree, True], " of ", Length[agree]];
    If[Head[compiled] =!= CompiledCodeFunction || ! And @@ agree, Exit[1]]];
If[differ =!= {}, Exit[1]];

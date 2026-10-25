#!/usr/bin/env wolframscript
(* Holds the values the reader gives number literals to Wolfram 15's own reading of them, over random
   literals: bases 10, 2, 8, 16 and 36, digits before and after a point, no mark, a mark with no
   precision, a precision, an accuracy, and powers of the base from none to 10^15. A value agrees
   where it is the same number, a machine one where Wolfram 15's is, at the same precision; one
   that differs only in its precision's last digits, as Wolfram 15's own arithmetic makes them for
   long digits, is counted apart; and where Wolfram 15 does not stop reading, nor may the reader.
   Run it with Wolfram 15:
       wl -f dev/check-numbers.wls [count] [seed]
   It prints the counts, then what differs. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
arguments = Rest[$ScriptCommandLine];
count = If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 6000];
seed = If[Length[arguments] >= 2, Interpreter["Integer"][arguments[[2]]], 1];
numberValue = Symbol["Wolfram`Parser`Languages`WolframLanguage`Private`numberValue"];
SeedRandom[seed];

digitsOf[b_, n_] := StringJoin[RandomChoice[Take[Join[CharacterRange["0", "9"], CharacterRange["a", "z"]], b], n]];
literal[] := Module[{b = RandomChoice[{14, 1, 1, 2, 1} -> {10, 2, 8, 16, 36}], int, frac, point, mark, exp},
    int = digitsOf[b, RandomChoice[{2, 6, 4, 2, 1} -> {0, 1, 3, 10, 20}]];
    point = RandomReal[] < 0.6; frac = If[point, digitsOf[b, RandomChoice[{2, 4, 4, 2, 1} -> {0, 1, 4, 12, 22}]], ""];
    If[int === "" && (! point || frac === ""), int = "1"];
    mark = RandomChoice[{10, 3, 2, 2, 1, 1, 1} -> {"", "`", "`" <> ToString[RandomInteger[{0, 40}]], "``" <> ToString[RandomInteger[{0, 40}]], "`-" <> ToString[RandomInteger[{1, 5}]],
        "``-" <> ToString[RandomInteger[{1, 5}]], "`" <> ToString[RandomInteger[{1, 30}]] <> "." <> ToString[RandomInteger[{0, 9}]]}];
    exp = RandomChoice[{8, 4, 4, 1, 1} -> {"", "*^" <> ToString[RandomInteger[{-30, 30}]], "*^" <> ToString[RandomChoice[{-1, 1}] RandomInteger[{290, 330}]],
        "*^" <> ToString[RandomChoice[{-1, 1}] RandomInteger[{1000, 100000}]], "*^" <> ToString[RandomChoice[{-1, 1}] RandomInteger[{10^14, 10^15}]]}];
    (* an accuracy on a vast number asks for its every digit, which no reader makes *)
    If[StringStartsQ[mark, "``"] && StringMatchQ[exp, "*^" ~~ DigitCharacter ..] && Interpreter["Integer"][StringDrop[exp, 2]] > 1000, exp = "*^" <> ToString[RandomInteger[{0, 30}]]];
    If[b === 10, "", ToString[b] <> "^^"] <> int <> If[point, "." <> frac, ""] <> mark <> exp];
literals = DeleteDuplicates[Table[literal[], {count}]];

bounded[e_] := Catch[Block[{$Messages = {}}, MemoryConstrained[TimeConstrained[e, 5, $Aborted], 10^9, $Aborted]], _SystemException, $Aborted &];
SetAttributes[bounded, HoldFirst];
w15[s_String] := With[{r = bounded[ToExpression[s, InputForm, HoldComplete]]}, If[MatchQ[r, _HoldComplete], First[r], r]];
same[a_, b_] := a === b && If[NumberQ[a] && ! ExactNumberQ[a], Precision[a] === Precision[b] && MachineNumberQ[a] === MachineNumberQ[b], True];

results = Map[Function[s, With[{w = w15[s], e = bounded[numberValue[s]]},
    Which[
        w === $Failed, {s, If[WolframLanguageSyntaxQ[s], "read, where Wolfram 15 does not", "no number"]},
        e === $Aborted && w === $Aborted, {s, "both stop"},
        e === $Aborted, {s, "stops", w, e},
        same[w, e], {s, "same"},
        NumberQ[w] && NumberQ[e] && w == e && MachineNumberQ[w] === MachineNumberQ[e] && Abs[Precision[w] - Precision[e]] < 10^-10, {s, "precision's last digits"},
        True, {s, "differs", w, e}]]], literals];

show[x_] := If[NumberQ[x] && ! ExactNumberQ[x], ToString[x, InputForm] <> If[MachineNumberQ[x], " (machine)", ""], ToString[x, InputForm]];
wrong = Select[results, MemberQ[{"differs", "stops", "read, where Wolfram 15 does not"}, #[[2]]] &];
Scan[Print["   ", #[[1]], "  ", #[[2]], If[Length[#] > 2, "  Wolfram 15 " <> StringTake[show[#[[3]]], UpTo[90]] <> "  reader " <> StringTake[show[#[[4]]], UpTo[90]], ""]] &, Take[wrong, UpTo[30]]];
Print["numbers: ", Length[literals], " literals, seed ", seed, ": ", Counts[results[[All, 2]]]];
If[wrong =!= {}, Exit[1]];

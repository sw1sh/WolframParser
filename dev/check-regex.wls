#!/usr/bin/env wolframscript
(* Holds the programs of RegularExpression, Wolfram`Parser`StringPatterns`, to Wolfram 15's own
   String functions over random regexes and strings, by the typed matcher and by the interpreter:
   the texts of the matches against StringCases, each match's groups against a rule's "$n", every
   way of each against Overlaps -> All, and that a regex Wolfram 15 does not take has no program.
   Run it with Wolfram 15:
       wl -f dev/check-regex.wls [cases] [seed]
   It prints what disagrees, then the counts. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];

arguments = Rest[$ScriptCommandLine];
count = If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 3000];
seed = If[Length[arguments] >= 2, Interpreter["Integer"][arguments[[2]]], 1];
SeedRandom[seed];

(* --- random strings and regexes --- *)

$alphabet = {"a", "b", "A", "B", "c", "1", "2", " ", "\n", "-", ".", "_", "\[EAcute]", "\[CapitalEAcute]", "\[Alpha]", "\t", FromCharacterCode[16^^0663], "\r"};
randomString[] := StringJoin[RandomChoice[$alphabet, RandomInteger[{0, 9}]]]

$characters = {"a", "b", "A", "c", "1", " ", "-", "\[EAcute]", "\\.", "\\-", "\\n", "\\t", "\\x{e9}", "\\x41", "_"};
$classes = {".", "\\d", "\\w", "\\s", "\\D", "\\W", "\\S", "\\h", "\\v", "\\N", "[ab]", "[^ab]", "[a-c]", "[[:alpha:]]", "[[:upper:]]", "[[:lower:]]",
    "[\\d\\s]", "[^[:punct:]]", "\\p{Lu}", "\\p{L}", "\\P{L}", "\\p{Nd}", "[\\p{Ll}1]", "[A-Za-z]"};
$anchors = {"^", "$", "\\b", "\\B", "\\A", "\\z", "\\Z"};
$quantifiers = {"*", "+", "?", "{2}", "{1,2}", "{0,1}", "{2,}", "*?", "+?", "??", "{1,2}?", "*+", "++", "?+"};

atom[0] := RandomChoice[{5, 4, 1} -> {RandomChoice[$characters] &, RandomChoice[$classes] &, RandomChoice[$anchors] &}][]
atom[d_Integer] := RandomChoice[{6, 2, 2, 1, 1, 1, 1, 1, 1, 1} -> {
    atom[0] &,
    "(" <> regex[d - 1] <> ")" &,
    "(?:" <> regex[d - 1] <> ")" &,
    "(?=" <> regex[d - 1] <> ")" &,
    "(?!" <> regex[d - 1] <> ")" &,
    "(?<=" <> RandomChoice[{"a", "\\d", "ab", "a|bc", "[ab]"}] <> ")" &,
    "(?<!" <> RandomChoice[{"a", "\\s", "ab", "a|b"}] <> ")" &,
    "(?>" <> regex[d - 1] <> ")" &,
    RandomChoice[{"(?i)", "(?m)", "(?s)", "(?i:" <> regex[d - 1] <> ")"}] &,
    "\\1" &}][]
piece[d_Integer] := With[{a = atom[d]}, If[RandomReal[] < 0.35 && ! MemberQ[$anchors, a], a <> RandomChoice[$quantifiers], a]]
branch[d_Integer] := StringJoin[Table[piece[d], {RandomInteger[{1, 3}]}]]
regex[d_Integer] := StringRiffle[Table[branch[d], {RandomChoice[{6, 2, 1} -> {1, 2, 3}]}], "|"]

(* --- the answers --- *)

native[e_] := Block[{$Messages = {}}, Check[TimeConstrained[e, 5, $Aborted], $Failed]];
SetAttributes[native, HoldFirst];
cut[s_String, matches_List] := Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, matches];
groups[matches_List] := Map[Cases[#[[4]], (_Integer -> t_) :> t] &, matches];

differ = {}; agree = 0; noProgram = 0; notNative = 0; both = 0; unmade = {};
Do[
    With[{re = regex[RandomInteger[{0, 2}]], s = randomString[]},
        With[{p = StringPatternProgram[RegularExpression[re]], w = native[StringCases[s, RegularExpression[re]]]},
            Which[
                (* a regex that has no program: Wolfram 15 takes it or not, it is no case *)
                p["Program"] === None, noProgram++; If[MatchQ[w, $Failed | $Aborted], both++, AppendTo[unmade, re]],
                (* a regex that Wolfram 15 does not take has no program *)
                MatchQ[w, $Failed | $Aborted], notNative++; AppendTo[differ, {re, s, "Program", {p["Program"], w}}],
                True, With[{n = Length[Union[Cases[p["Program"], Wolfram`Parser`StringPatterns`Private`capture[k_, _] :> k, {0, Infinity}]]]},
                    With[{wanted = {w, native[StringCases[s, RuleDelayed @@ {RegularExpression[re], Table["$" <> ToString[k], {k, n}]}]], native[StringCases[s, RegularExpression[re], Overlaps -> All]]}},
                        With[{wrong = Select[
                                AssociationMap[Function[method, With[{e = StringPatternMatches[s, {p}, "Each", Method -> method], a = StringPatternMatches[s, {p}, "All", Method -> method]},
                                    {cut[s, e], groups[e], cut[s, a]}]], {"VM", "Interpreter"}],
                                # =!= wanted &]},
                            If[wrong === <||>, agree++, AppendTo[differ, {re, s, Keys[wrong], {First[Values[wrong]], wanted}}]]]]]]]],
    {count}];

Scan[Function[d, Print["   ", ToString[d[[1]], InputForm], " on ", ToString[d[[2]], InputForm], " (", d[[3]], ")\n      engine ", ToString[d[[4, 1]], InputForm],
    "\n      W15    ", ToString[d[[4, 2]], InputForm]]], Take[differ, UpTo[30]]];
Print["   a sample of the regexes with no program that Wolfram 15 takes: ", ToString[Take[unmade, UpTo[12]], InputForm]];
Print["regex: ", count, " cases, seed ", seed, ": ", agree, " agree, ", Length[differ], " differ, ", noProgram, " with no program (", both,
    " of them no regex in Wolfram 15 either), ", notNative, " no regex in Wolfram 15 with a program"];
If[differ =!= {}, Exit[1]];

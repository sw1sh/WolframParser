#!/usr/bin/env wolframscript
(* Holds WolframLanguageProgram to WolframLanguageHeldNext. Where a source is plain, read whole
   with no line continuation and no syntax warning, its program's statements, each built alone by
   the reader's build pass, are the parts WolframLanguageHeldNext gives, a Null for each row of
   zeros, its lists packed; any other source has no program. The sources are those of
   check-held-next.wls: the paclet's own files, a sample of the system's packages, and chunks of the
   paclet's files cut short, with a character taken out and with one put in. Run it with Wolfram 15:
       wl -f dev/check-reader-program.wls [count]
   It prints how many are plain and how many are wrong in each set, then each wrong one, up to
   count (by default 10). *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
Off[General::stop];
SeedRandom[20261024];
shown = Replace[Interpreter["Integer"][Last[$ScriptCommandLine, "10"]], Except[_Integer] -> 10];
private = "Wolfram`Parser`Languages`WolframLanguage`Private`";

(* the parts WolframLanguageHeldNext gives s, and whether s is plain *)
heldParts[s_String] := Module[{pos = 1, r, parts = {}, plain = Symbol[private <> "lineContinuations"][s] === {}},
    While[ ListQ[r = WolframLanguageHeldNext[s, pos]],
        If[FailureQ[First[r]], plain = False; Break[]];
        AppendTo[parts, First[r]]; If[r[[3, "Warnings"]] =!= {}, plain = False]; pos = r[[2]]];
    {parts, plain}];

(* the parts of a program {codes, prog, parts}, each statement built alone, its leaves' texts the
   codes from their starts to their ends *)
programParts[{codes_List, prog_List, d_List}] := With[{build = Symbol[private <> "fastBuild"], m = d[[2]]},
    With[{kinds = d[[4 ;; 3 + m]], marks = d[[4 + m ;; 3 + 2 m]], texts = MapThread[FromCharacterCode[codes[[#1 ;; #2 - 1]]] &, {d[[4 + 2 m ;; 3 + 3 m]], d[[4 + 3 m ;; 3 + 4 m]]}]},
        Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fcodes = codes},
            Map[If[#[[1]] === 0, HoldComplete[Null],
                First[build[prog[[3 #[[1]] ;; 3 #[[2]] + 2]], kinds[[#[[3]] ;; #[[4]]]], texts[[#[[3]] ;; #[[4]]]], marks[[#[[3]] ;; #[[4]]]]]]] &,
                Partition[d[[4 + 4 m ;;]], 4]]]]];

packedQ[list_] := list === {} || Developer`PackedArrayQ[list, Integer];

(* what is wrong for s: none, or {s, why, the program's parts, WolframLanguageHeldNext's} *)
wrong[s_String] := With[{p = WolframLanguageProgram[s], h = heldParts[s]},
    Which[
        p === None, If[h[[2]], {{s, "no program", None, h[[1]]}}, {}],
        ! h[[2]], {{s, "a program", None, h[[1]]}},
        ! AllTrue[p, packedQ], {{s, "not packed", None, h[[1]]}},
        p[[1]] =!= ToCharacterCode[s] || p[[3, 1]] =!= 0, {{s, "codes or commas' Nulls", None, h[[1]]}},
        True, With[{parts = programParts[p]}, If[parts === h[[1]], {}, {{s, "parts", parts, h[[1]]}}]]]];

report[name_String, sources_List] := With[{found = Catenate[wrong /@ sources]},
    Print[name, ": ", Length[sources], " sources, ", Count[sources, s_ /; WolframLanguageProgram[s] =!= None], " plain, ", Length[found], " wrong"];
    Scan[Print["   ", StringTake[ToString[#[[1]], InputForm, CharacterEncoding -> "ASCII"], UpTo[200]], "  ", #[[2]],
        "\n      WolframLanguageProgram ", StringTake[ToString[#[[3]], InputForm, CharacterEncoding -> "ASCII"], UpTo[300]],
        "\n      WolframLanguageHeldNext ", StringTake[ToString[#[[4]], InputForm, CharacterEncoding -> "ASCII"], UpTo[300]]] &, Take[found, UpTo[shown]]];
    Length[found]];

text[file_String] := ByteArrayToString[ReadByteArray[file], "UTF-8"];
files = Catenate[FileNames["*.wl" | "*.wls" | "*.m", FileNameJoin[{root, #}], Infinity] & /@ {"Parser/Kernel", "Parser/Tests", "dev"}];
system = RandomSample[Select[FileNames["*.m" | "*.wl", FileNameJoin[{$InstallationDirectory, "SystemFiles", "Components"}], 3], FileByteCount[#] < 400000 &], UpTo[150]];
chunks = RandomSample[Select[Catenate[StringSplit[text[#], "\n\n"] & /@ files], 10 < StringLength[#] < 400 &], UpTo[300]];
characters = Join[Characters[")]},;+*[{(\"~@/:=.!#&|<>\\-^'_\n"], {",", "\\q", "\\["}];
mutated = DeleteDuplicates[Catenate[Function[b, Join[
    Table[StringTake[b, k], {k, 1, StringLength[b] - 1, Max[1, Floor[StringLength[b] / 5]]}],
    Table[With[{k = RandomInteger[{1, StringLength[b]}]}, StringDrop[b, {k}]], {3}],
    Table[With[{k = RandomInteger[{1, StringLength[b] + 1}]}, StringInsert[b, RandomChoice[characters], k]], {6}],
    {b <> "\n\n" <> b, "\n" <> b <> "\r\n\r\n" <> b <> "\n"}]] /@ chunks]];
cases = {"", "\n", " ", "a\n\n", "\n\na", "a\r\n\r\nb", "(* c *)\n(* d *)", "{}", "f[a,]", "{,}", "\"a\\qb\"", "\"a\\nb\"", "a \\\n b",
    "x = \"\\[Alpha]\"", "?a*=b", "a::b_", "\\!\\(x\\^2\\)", "\\(x\\)", "f[x_] := x^2; g[]", "a )", "1 +"};

failed = Total[{
    report["cases", cases],
    report["paclet files", text /@ files],
    report["system packages", Select[text /@ system, StringQ]],
    report["mutated chunks", mutated]}];
If[failed > 0, Exit[1]];

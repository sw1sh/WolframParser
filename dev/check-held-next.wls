#!/usr/bin/env wolframscript
(* Checks WolframLanguageHeldNext against Wolfram 15's ToExpression, which reads a source one
   statement at a time: the parts it gives a source, read from position 1 to EndOfFile, and the
   Syntax warnings the kernel gives as it reads them. Where the kernel reads the source, the parts
   are the kernel's; where it does not, the parts before the failure are those the kernel gives the
   source before the failure's line, and the failure is the one WolframLanguageHeld gives. The
   sources are the paclet's own files, a sample of the system's packages, and chunks of the
   paclet's files cut short, with a character taken out and with one put in. Run it with Wolfram 15:
       wl -f dev/check-held-next.wls [count]
   It prints how many agree in each set, then each that does not, up to count (by default 10). *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
Off[General::stop];
SeedRandom[20261024];
shown = Replace[Interpreter["Integer"][Last[$ScriptCommandLine, "10"]], Except[_Integer] -> 10];

(* the parts and warnings WolframLanguageHeldNext gives, a failure as {"Failure", position,
   incomplete, where its line begins} *)
ours[s_String] := Module[{pos = 1, r, parts = {}, warnings = {}},
    While[ ListQ[r = WolframLanguageHeldNext[s, pos]],
        If[ FailureQ[First[r]],
            AppendTo[parts, {"Failure", r[[1]]["Position"], r[[1]]["Incomplete"], r[[2]]}];
            warnings = Join[warnings, r[[1]]["Warnings"]]; Break[]];
        AppendTo[parts, First[r]]; warnings = Join[warnings, r[[3, "Warnings"]]]; pos = r[[2]]];
    {parts, warnings}];

(* the kernel's parts, $Failed where it does not read the source, and its Syntax warnings, a
   comma's without the newline it names and a missing long name's text without the newline after it *)
kernel[s_String] := With[{d = EvaluationData[ToExpression[s, InputForm, HoldComplete]]},
    {If[d["Result"] === $Failed, $Failed, List @@ Map[HoldComplete, d["Result"]]],
     Cases[d["MessagesExpressions"], Hold[Message[HoldPattern[MessageName[Syntax, tag_]], args___]] :>
        Replace[Prepend[Replace[{args}, HoldCompleteForm[x_] :> x, {1}], tag], {{"com", "\n"} -> {"com"}, {"sntmsng", x_String} :> {"sntmsng", StringTrim[x, "\n"]}}]]}];

held[s_String] := With[{r = WolframLanguageHeld[s]}, If[FailureQ[r], {r["Position"], r["Incomplete"]}, r]];

(* what differs for s: none, or the parts, the failure or the warnings *)
problems[s_String] := Module[{o = ours[s], k = kernel[s], h, last, bad = {}},
    last = Last[o[[1]], None];
    If[ k[[1]] =!= $Failed,
        If[o[[1]] =!= k[[1]], AppendTo[bad, "parts"]],
        h = held[s];
        Which[
            ! MatchQ[last, {"Failure", __}] || Take[last, {2, 3}] =!= h, AppendTo[bad, "failure"],
            last[[4]] > 1 && Most[o[[1]]] =!= kernel[StringTake[s, last[[4]] - 1]][[1]], AppendTo[bad, "parts before the failure"]]];
    If[o[[2]] =!= k[[2]], AppendTo[bad, "warnings"]];
    If[bad === {}, {}, {{s, bad, o, k}}]];

report[name_String, sources_List] := With[{found = Catenate[problems /@ sources]},
    Print[name, ": ", Length[sources], " sources, ", Length[sources] - Length[found], " agree"];
    Scan[Print["   ", StringTake[ToString[#[[1]], InputForm, CharacterEncoding -> "ASCII"], UpTo[200]], "  ", #[[2]],
        "\n      WolframLanguageHeldNext ", StringTake[ToString[#[[3]], InputForm, CharacterEncoding -> "ASCII"], UpTo[300]],
        "\n      kernel ", StringTake[ToString[#[[4]], InputForm, CharacterEncoding -> "ASCII"], UpTo[300]]] &, Take[found, UpTo[shown]]]];

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

report["paclet files", text /@ files];
report["system packages", Select[text /@ system, StringQ]];
report["mutated chunks", mutated];

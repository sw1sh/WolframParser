#!/usr/bin/env wolframscript
(* Checks where WolframLanguageHeld says reading of a source that is no Wolfram Language stops,
   and whether the source ends too early, against Wolfram 15's own report of it: ToExpression's
   ToExpression::sntxi, the source ending before its expression does, or the caret of its
   ToExpression::sntx, past the leading whitespace its message leaves out. The sources are
   mutations of valid single-line expressions, the paclet's own statements and a list of forms:
   each cut short, with a character taken out and with one put in, those the kernel reads left
   out. Run it with Wolfram 15:
       wl -f dev/check-failure-positions.wls [count]
   It prints how many agree, then each that does not, up to count (by default 40). *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
Off[General::stop];
SeedRandom[20261024];
shown = Replace[Interpreter["Integer"][Last[$ScriptCommandLine, "40"]], Except[_Integer] -> 40];

forms = {"f[x_] := x^2", "a + b - c", "a b c", "x:_Integer", "a -> b -> c", "f@g@x", "a // f // g", "f /@ x", "a~f~b~g~c",
    "f''[x]", "a && b || c", "a;;b;;c", "a::b::c", "t/:a:=b", "{a, b}", "<|a -> 1|>", "a[[1, 2]]", "(a + b) c", "a < b <= c",
    "#2 + ##", "16^^ff", "1.5`20", "\"a\\nb\"", "f[x_?NumericQ]", "x_ /; y", "f[x_:y]", "Function[x, x]&", "a @@@ b",
    "a //. b", "a ^:= b", "x|->x^2", "a<->b", "a~~b", "f@*g", "a \\[Rule] b", "\\[LeftAngleBracket]a, b\\[RightAngleBracket]",
    "\\[Integral] x \\[DifferentialD]x", "<<file", "a >> \"b\"", "Module[{x = 1}, x + y]", "If[a > 0, b, c]"};
statements = Flatten[Map[
    Function[file, Select[StringReplace[#, "\n" -> " "] & /@ StringSplit[ByteArrayToString[ReadByteArray[file], "UTF-8"], "\n\n"],
        StringLength[#] < 160 && StringFreeQ[#, "(*"] && SyntaxQ[#] &]],
    FileNames["*.wl", FileNameJoin[{root, "Parser", "Kernel"}], Infinity]]];
bases = Select[DeleteDuplicates[Join[forms, RandomSample[statements, UpTo[250]]]], StringFreeQ[#, "\n"] && StringLength[#] > 1 && SyntaxQ[#] &];

characters = Characters[")]},;+*[{(\"~@/:=.!#&|<>\\-^'_"];
mutations[b_String] := DeleteDuplicates[Join[
    Table[StringTake[b, k], {k, 1, StringLength[b] - 1, Max[1, Floor[StringLength[b] / 6]]}],
    Table[With[{k = RandomInteger[{1, StringLength[b]}]}, StringDrop[b, {k}]], {4}],
    Table[With[{k = RandomInteger[{1, StringLength[b] + 1}]}, StringInsert[b, RandomChoice[characters], k]], {6}]]];

(* the kernel's report: {where reading stops, whether the source ends too early}, None where
   ToExpression says nothing *)
leading[s_String] := StringLength[s] - StringLength[StringDelete[s, StartOfString ~~ Whitespace]];
kernelStop[s_String] := Module[{messages},
    messages = Cases[EvaluationData[ToExpression[s, InputForm, HoldComplete]]["MessagesExpressions"],
        Hold[Message[HoldPattern[MessageName[ToExpression, tag : "sntx" | "sntxi"]], args___]] :> {tag, {args}}];
    Which[
        messages === {}, None,
        messages[[1, 1]] === "sntxi", {StringLength[s] + 1, True},
        True, Replace[messages[[1, 2, 1]],
            {HoldCompleteForm[t_String] :> {StringLength[Last[StringSplit[t, "\n"]]] + leading[s], False}, _ -> None}]]];
ours[s_String] := With[{r = WolframLanguageHeld[s]}, If[FailureQ[r], {r["Position"], r["Incomplete"]}, "reads it"]];

sources = Select[DeleteDuplicates[Flatten[mutations /@ bases]], ! SyntaxQ[#] &];
results = Select[Map[{#, kernelStop[#], ours[#]} &, sources], #[[2]] =!= None &];
differ = Select[results, #[[2]] =!= #[[3]] &];

Print[Length[results], " sources the kernel reports, from ", Length[bases], " expressions: ", Length[results] - Length[differ], " agree, ",
    Count[differ, {_, _, "reads it"}], " read though the kernel does not, ", Length[differ] - Count[differ, {_, _, "reads it"}], " stop elsewhere"];
Scan[Print[ToString[#[[1]], InputForm, CharacterEncoding -> "ASCII"], "   kernel ", #[[2]], "   WolframLanguageHeld ", #[[3]]] &, Take[differ, UpTo[shown]]];

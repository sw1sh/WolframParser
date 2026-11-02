#!/usr/bin/env wolframscript
(* Lists the forms of the box tests whose boxes WolframLanguageBoxes gives otherwise than the
   front end, by kind, into Parser/Tests/Languages/WolframLanguageBoxes.wlt, between its
   "BEGIN open" and "END open" lines; the tests leave them out. Run it after
   dev/freeze-boxes.wls and after a change to the box mode:
       wl -f dev/list-boxes-open.wls *)

$ProgressReporting = False;
root = ParentDirectory[DirectoryName[$InputFileName]];
parser = FileNameJoin[{root, "Parser"}];
wlt = FileNameJoin[{parser, "Tests", "Languages", "WolframLanguageBoxes.wlt"}];
PacletDirectoryLoad[parser]; Needs["Wolfram`Parser`"]; Needs["Wolfram`Parser`Languages`WolframLanguage`"];
text = ByteArrayToString[ReadByteArray[wlt], "UTF-8"];
cases = First[Cases[ImportString[text, {"Package", "HeldExpressions"}], HoldPattern[$frontEndBoxes = l_List] :> l, Infinity]];
open = Select[cases, Wolfram`Parser`Languages`WolframLanguage`WolframLanguageBoxes[#[[1]]] =!= #[[2]] &][[All, 1]];
balancedQ[s_] := Module[{depth = 0, ok = True},
	Scan[Which[MemberQ[{"(", "[", "{"}, #], depth++, MemberQ[{")", "]", "}"}, #], depth--; If[depth < 0, ok = False]] &, Characters[StringDelete[s, "\"" ~~ Shortest[___] ~~ "\""]]];
	ok && depth === 0];
kind[s_] := Which[
	StringContainsQ[s, "\n" | "\r"], "a newline outside brackets ends the expression, as the kernel reads it",
	StringContainsQ[s, "??"], "?? and what follows it",
	StringContainsQ[s, "`"], "backquotes",
	StringContainsQ[s, "=["], "=[",
	! balancedQ[s], "groups not closed and closers that close another group",
	StringContainsQ[s, "\\[" | "\[Integral]"], "long names: operators of other precedences, unknown names, spaces",
	True, "operator chains the front end keeps flat, and tokens"];
shown[e_] := ToString[e, InputForm, CharacterEncoding -> "ASCII"];
groups = GroupBy[open, kind];
block = StringJoin["$frontEndOpen = {\n", StringRiffle[KeyValueMap[Function[{k, v}, "    (* " <> k <> " *)\n    " <> StringRiffle[shown /@ v, ", "]], groups], ",\n"], "\n};\n"];
updated = StringReplace[text, start : ("(* BEGIN open" ~~ Shortest[___] ~~ "*)\n") ~~ Shortest[___] ~~ end : "(* END open *)" :> start <> block <> end, 1];
With[{stream = OpenWrite[wlt, CharacterEncoding -> "UTF-8"]}, WriteString[stream, updated]; Close[stream]];
Print[Length[open], " open in ", Length[groups], " kinds: ", Normal[Length /@ groups]];

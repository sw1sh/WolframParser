#!/usr/bin/env wolframscript
(* Wolfram 15's kernel text reader against its notebook front end, source by source: the kernel's
   ToExpression[s, InputForm, HoldComplete], which Get and ImportString agree with, against what an
   input cell holding s gives, the front end's parse of the typed text to boxes made an expression
   by ToExpression[BoxData[b], StandardForm, HoldComplete], each line on its own. The sources are
   dev/frontend-compare-probes.wl, the source tables of the Wolfram Language tests, forms with a
   character cut, taken out or put in, and random strings of tokens. Run it with Wolfram 15's
   kernel, which starts its own front end:
       WolframKernel -script dev/frontend-compare.wls [out]
   It prints how many sources differ, how, and Puts {{source, kernel, front end} ...} for each that
   does into out, by default frontend-compare.m in the working directory. *)

$ProgressReporting = False;
arguments = Replace[$CommandLine, {{___, "-script", script_, rest___} :> {script, rest}, _ -> {}}];
root = ParentDirectory[DirectoryName[First[arguments]]];
out = If[Length[arguments] >= 2, arguments[[2]], "frontend-compare.m"];
SeedRandom[20261028];

probes = Get[FileNameJoin[{root, "dev", "frontend-compare-probes.wl"}]];
wlt = Import[FileNameJoin[{root, "Parser", "Tests", "Languages", "WolframLanguage.wlt"}], {"WL", "HeldExpressions"}];
tables = Catenate[Cases[wlt, (HoldComplete[Set[s_Symbol, rhs_List]] | HoldComplete[CompoundExpression[Set[s_Symbol, rhs_List], Null]]) /;
        StringStartsQ[SymbolName[Unevaluated[s]], "$wl"] :> Cases[rhs, {src_String, ___} | src_String :> src, {1}], {1}]];
forms = {"f[x_] := x^2", "a + b - c", "a b c", "x:_Integer", "a -> b -> c", "f@g@x", "a // f // g", "f /@ x", "a~f~b~g~c",
    "f''[x]", "a && b || c", "a;;b;;c", "a::b::c", "t/:a:=b", "{a, b}", "<|a -> 1|>", "a[[1, 2]]", "(a + b) c", "a < b <= c",
    "#2 + ##", "16^^ff", "1.5`20", "\"a\\nb\"", "f[x_?NumericQ]", "x_ /; y", "f[x_:y]", "Function[x, x]&", "a @@@ b",
    "a //. b", "a ^:= b", "x|->x^2", "a<->b", "a~~b", "f@*g", "a \\[Rule] b", "\\[LeftAngleBracket]a, b\\[RightAngleBracket]",
    "\\[Integral] x \\[DifferentialD]x", "<<file", "a >> \"b\"", "Module[{x = 1}, x + y]", "If[a > 0, b, c]", "a = b", "a := b", "f[a;b]",
    "x_.", "x__h", "a?b", "a!", "a!!", "a'", "a++", "--a", "a..", "a...", "a=.", "?a", "??a*", "a::b", "a&", "a|b|c", "a.b.c", "a^b^c", "-a^b", "a/b/c"};
characters = Join[Characters[")]},;+*[{(\"~@/:=.!#&|<>\\-^'_\n` ?%$"], {",", "\\[", "\\:", "\\n", "\\(", "(*", "*)", "=[", "<<", ">>", ";;", "::"}];
mutate[b_String] := Join[
    Table[StringTake[b, k], {k, 1, StringLength[b] - 1}],
    Table[With[{k = RandomInteger[{1, StringLength[b]}]}, StringDrop[b, {k}]], {4}],
    Table[With[{k = RandomInteger[{1, StringLength[b] + 1}]}, StringInsert[b, RandomChoice[characters], k]], {10}]];
mutated = Catenate[mutate /@ forms];
pieces = {"\\[Alpha]", "\\[RightArrow]", "\\[", "x_", "x__.", "_h", "a`b", "16^^ff", "1.5`20", "1*^-3", ".5", "#", "##3", "#name", "%%", "%3", "f''",
    "\\(x\\)", "\\!\\(x\\^2\\)", "\"str\"", "\"\\n\"", "(*c*)", "<<file", ">>\"f.m\"", "=.", "===", "//.", "^:=", "a", "1", " ", "\n", "+", "-", "*", "[", "]",
    "{", "}", "(", ")", "<|", "|>", ",", ";", "::", "->", "&&", "~", "@", "@@", "?", "*=", "f[", "g[x]", "/:", ":=", "~f~", "\\[Integral]", ";;", "!", "=[q]", "'", "&", "..", "."};
random = Table[StringJoin[RandomChoice[pieces, RandomInteger[{1, 7}]]], {2500}];
sources = DeleteDuplicates[Join[probes, tables, forms, mutated, random]];
Print["sources: ", Length[sources], " (probes ", Length[probes], ", tables ", Length[tables], ", mutated ", Length[mutated], ", random ", Length[random], ")"];

show[r_] := ToString[FullForm[r], CharacterEncoding -> "ASCII"];
kernelRead[s_String] := Block[{$Messages = {}}, With[{r = Quiet[ToExpression[s, InputForm, HoldComplete]]}, If[MatchQ[r, _HoldComplete], show[r], "$Failed"]]];
(* the front end's boxes of s, one item for each line, each made an expression as a cell's is; the
   parser packet's False mode, as True's stops the front end on some sources *)
lineBoxes[b_List] := Select[b, # =!= "\n" &];
lineBoxes[b_] := {b};
frontEndRead[s_String] := Module[{p, made},
    p = TimeConstrained[MathLink`CallFrontEnd[FrontEnd`UndocumentedTestFEParserPacket[s, False]], 10, $Aborted];
    If[ ! MatchQ[p, {BoxData[_], ___}], "$Failed",
        made = Block[{$Messages = {}}, Quiet[ToExpression[BoxData[#], StandardForm, HoldComplete] & /@ lineBoxes[p[[1, 1]]]]];
        If[MemberQ[made, Except[_HoldComplete]], "$Failed", show[Join @@ made]]]];

results = UsingFrontEnd[Table[{s, kernelRead[s], frontEndRead[s]}, {s, sources}]];
differ = Select[results, #[[2]] =!= #[[3]] &];
Print["differ: ", Length[differ], " of ", Length[results], "; the kernel fails where the front end reads: ", Count[differ, {_, "$Failed", _}],
    "; the front end fails where the kernel reads: ", Count[differ, {_, Except["$Failed"], "$Failed"}],
    "; both read, differently: ", Count[differ, {_, Except["$Failed"], Except["$Failed"]}]];
Put[differ, out];
Print["into ", out];

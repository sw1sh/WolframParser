#!/usr/bin/env wolframscript
(* The held expressions a notebook's input cell gives for each source, as Wolfram 15's front end
   reads typed text: the front end parses the text to boxes, and the kernel makes the boxes of
   each line an expression, as it does a cell's. Wolfram/Parser reads Wolfram Language as this
   does. Run it with Wolfram 15's kernel, which starts its own front end:
       WolframKernel -script dev/frontend-held.wls sources [out]
   sources is a file of WL that evaluates to a list of strings, or of text with one source on each
   line. out, a file it writes {{source, held} ...} into in FullForm, which Get reads back as it
   is (InputForm writes FreeformEvaluate["b"] as =[b], which does not), held a HoldComplete of the
   expressions or $Failed; without it, each is printed. *)

$ProgressReporting = False;
arguments = Replace[$CommandLine, {{___, "-script", _, rest___} :> {rest}, _ -> {}}];
If[arguments === {}, Print["usage: WolframKernel -script dev/frontend-held.wls sources [out]"]; Exit[1]];
input = First[arguments];
sources = Replace[Quiet[Get[input], {Get::noopen, Syntax::sntx, Syntax::sntxi}], {
    l : {___String} :> l,
    _ :> Select[StringSplit[ByteArrayToString[ReadByteArray[input], "UTF-8"], "\n"], StringLength[#] > 0 &]}];

(* the front end's boxes of s, one item for each line *)
lineBoxes[b_List] := Select[b, # =!= "\n" &]
lineBoxes[b_] := {b}

(* what an input cell holding s gives: HoldComplete of the expressions of its lines, or $Failed;
   the parser packet's False mode, as True's stops the front end on some sources *)
frontEndHeld[s_String] := Module[{p, made},
    p = TimeConstrained[MathLink`CallFrontEnd[FrontEnd`UndocumentedTestFEParserPacket[s, False]], 10, $Aborted];
    If[ ! MatchQ[p, {BoxData[_], ___}], $Failed,
        made = Block[{$Messages = {}}, Quiet[ToExpression[BoxData[#], StandardForm, HoldComplete] & /@ lineBoxes[p[[1, 1]]]]];
        If[MemberQ[made, Except[_HoldComplete]], $Failed, Join @@ made]]]

results = UsingFrontEnd[{#, frontEndHeld[#]} & /@ sources];
If[ Length[arguments] >= 2,
    Export[arguments[[2]], ToString[FullForm[results], CharacterEncoding -> "ASCII"], "Text"]; Print[Length[results], " sources into ", arguments[[2]]],
    Scan[Print[ToString[#[[1]], InputForm, CharacterEncoding -> "ASCII"], "  ", ToString[#[[2]], InputForm, CharacterEncoding -> "ASCII"]] &, results]]

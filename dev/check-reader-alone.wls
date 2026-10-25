#!/usr/bin/env wolframscript
(* Loads the Wolfram Language reader alone, as a kernel does, from Parser/Kernel/WolframLanguageReader.wl,
   reads the paclet's own sources and the inputs whose tokens the reader splits, one at a time too,
   and checks that it built no grammar and loaded no engine of string patterns. Run it with
   Wolfram 15:
       wl -f dev/check-reader-alone.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
Get[FileNameJoin[{root, "Parser", "Kernel", "WolframLanguageReader.wl"}]];

sources = Map[ByteArrayToString[ReadByteArray[#], "UTF-8"] &, FileNames["*.wl", FileNameJoin[{root, "Parser", "Kernel"}], Infinity]];
split = {"?a*=b", "??a*=b", "?a*:=b", "?x`*", "a::b_", "a::b_c", "f[a::b_]", "x = a::b_ + 1", "a::_", "a::b::_", "?a*=b\na::b_"};
read = Map[Wolfram`Parser`Languages`WolframLanguage`WolframLanguageHeld, Join[sources, split]];
next = Map[Function[s, Wolfram`Parser`Languages`WolframLanguage`WolframLanguageHeldNext[s, 1]], split];
syntax = Map[Wolfram`Parser`Languages`WolframLanguage`WolframLanguageSyntaxQ, split];

(* the grammar is built the first time it is asked for: its definition is then a value *)
grammarDelayed = MatchQ[OwnValues[Wolfram`Parser`Languages`WolframLanguage`Private`$heldGrammar], {_ :> _Set}];
Print["reader alone: ", Length[sources], " sources and ", Length[split], " split inputs read, ",
    Count[read, _List], " read whole, ", Count[read, _Failure], " failures; grammar built: ", ! grammarDelayed,
    "; string patterns loaded: ", Names["Wolfram`Parser`StringPatterns`*"] =!= {}];
If[! grammarDelayed || Names["Wolfram`Parser`StringPatterns`*"] =!= {} || Count[read, _List] < Length[sources], Exit[1]];

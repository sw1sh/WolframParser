(* Records what Wolfram 15.0's MathML readers give for the corpus and the round trip, into Parser/Tests/mathml-cases.json.
   Run with the 15.0 kernel:  WolframKernel -noinit -script dev/mathml/record.wls [limit]
   A run adds the inputs the file does not have yet, at most limit of them (300 where none is given), so that a
   corpus is recorded in runs of under a minute and nothing is recorded twice; it says how many are left.

   A case is <|"Corpus", "Input", "Boxes", "Held", "Expression", ...|>, each result the text of its FullForm in ASCII:
   what XML`MathML`MathMLToBoxes gives, ImportString's "HeldExpression", and XML`MathML`MathMLToExpression. With them,
   where they say more: "ImportExpression", ImportString's "Expression" where it is not the "Expression"; "XMLElement",
   outside the round trip; "XMLObject", in the xml corpus, without its document type, which names a file of the
   installation and keeps the identifiers of a document read before; "Messages", those of XML`MathML`MathMLToBoxes.
   Developer`MathMLToBoxes, ImportString's "Boxes" and its default element give the boxes XML`MathML`MathMLToBoxes gives
   for every input: a run stops at one where they do not. The definitions an input makes, which reading x = 1 as an
   expression does, are cleared after it. *)

SetSystemOptions["ParallelOptions" -> {"ParallelThreadNumber" -> 2}];
(* the names of this script are kept apart from Global`, which is cleared after each case and where the corpus's are *)
Begin["MathMLRecorder`"];
here = DirectoryName[$InputFileName];
limit = If[Length[$CommandLine] > 0 && StringMatchQ[Last[$CommandLine], DigitCharacter ..], FromDigits[Last[$CommandLine]], 300];
out = FileNameJoin[{ParentDirectory[ParentDirectory[here]], "Parser", "Tests", "mathml-cases.json"}];
text[e_] := ToString[FullForm[e], CharacterEncoding -> "ASCII"];
SetAttributes[withMessages, HoldFirst];
withMessages[e_] := Block[{$MessageList = {}}, {e, text /@ DeleteDuplicates[$MessageList]}];

record[corpus_String, s_String] := Module[{boxes, messages, held, expression, importExpression},
	{boxes, messages} = withMessages[XML`MathML`MathMLToBoxes[s]];
	expression = XML`MathML`MathMLToExpression[s];
	If[ Developer`MathMLToBoxes[s] =!= boxes || ImportString[s, "MathML"] =!= boxes || ImportString[s, {"MathML", "Boxes"}] =!= boxes,
		Print["The readers of boxes differ for ", s]; Exit[1]];
	held = ImportString[s, {"MathML", "HeldExpression"}];
	importExpression = ImportString[s, {"MathML", "Expression"}];
	Join[
		<|"Corpus" -> corpus, "Input" -> s, "Boxes" -> text[boxes], "Held" -> text[held], "Expression" -> text[expression]|>,
		If[importExpression === expression, <||>, <|"ImportExpression" -> text[importExpression]|>],
		If[StringStartsQ[corpus, "roundtrip"], <||>, <|"XMLElement" -> text[ImportString[s, {"MathML", "XMLElement"}]]|>],
		If[corpus === "xml", <|"XMLObject" -> text[DeleteCases[ImportString[s, {"MathML", "XMLObject"}], XMLObject["Doctype"][___], {2}]]|>, <||>],
		If[messages === {}, <||>, <|"Messages" -> messages|>]
	]
];

{corpus, held} = Block[{$Context = "Global`"}, {Get[FileNameJoin[{here, "corpus.wl"}]], Get[FileNameJoin[{here, "roundtrip.wl"}]]}];
export[HoldComplete[e_], formats_] := XML`MathML`ExpressionToMathML[e, "Formats" -> formats];
roundtrip = <|
	"roundtrip-presentation" -> Map[export[#, {"PresentationMathML"}] &, held],
	"roundtrip-content" -> Map[export[#, {"ContentMathML"}] &, held],
	"roundtrip-both" -> Map[export[#, {"PresentationMathML", "ContentMathML"}] &, held]
|>;
all = Map[DeleteDuplicates, Join[corpus, Select[#, StringQ] & /@ roundtrip]];
have = If[FileExistsQ[out], Developer`ReadRawJSONFile[out], {}];
known = Association[Map[{#Corpus, #Input} -> True &, have]];
missing = Select[Catenate[KeyValueMap[Function[{name, inputs}, Map[{name, #} &, inputs]], all]], ! KeyExistsQ[known, #] &];
Off[General::stop];
(* an input may assign: x = 1 read as an expression sets x. Each case starts from no definitions. *)
new = Map[Function[case, With[{result = Block[{$Context = "Global`"}, record @@ case]}, ClearAll["Global`*"]; result]], Take[missing, UpTo[limit]]];
(* the cases in the order of the corpus *)
order = Association[MapIndexed[#1 -> First[#2] &, Catenate[KeyValueMap[Function[{name, inputs}, Map[{name, #} &, inputs]], all]]]];
cases = SortBy[Join[have, new], Lookup[order, Key[{#Corpus, #Input}], Infinity] &];
If[ new =!= {}, Export[out, cases, "RawJSON", "Compact" -> True]];
Print[Length[new], " recorded, ", Length[missing] - Length[new], " left, ", Length[cases], " in ", out];
Print[Counts[Lookup[cases, "Corpus"]]];
End[];

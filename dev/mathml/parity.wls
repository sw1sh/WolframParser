(* The parity of the MathML reader with Wolfram 15.0: for each corpus of Parser/Tests/mathml-cases.json and each
   result recorded there, how many of the cases the paclet answers as 15.0 does. Run:  wl -f dev/mathml/parity.wls
   The environment variable MATHML_CORPUS, where set, keeps the corpora whose names begin with it; MATHML_SHOW the
   number of differences to print, of the result MATHML_FIELD. *)

SetSystemOptions["ParallelOptions" -> {"ParallelThreadNumber" -> 2}];
(* the names of this script are kept apart from Global`, which is cleared after each case *)
Begin["MathMLParity`"];
root = ParentDirectory[ParentDirectory[DirectoryName[$InputFileName]]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];

setting[name_String, default_] := Replace[Environment[name], {$Failed -> default, value_String :> If[IntegerQ[default], FromDigits[value], value]}];
prefix = setting["MATHML_CORPUS", ""];
show = setting["MATHML_SHOW", 0];
shown = setting["MATHML_FIELD", "Boxes"];

cases = Select[Developer`ReadRawJSONFile[FileNameJoin[{root, "Parser", "Tests", "mathml-cases.json"}]], StringStartsQ[#Corpus, prefix] &];
text[e_] := ToString[FullForm[e], CharacterEncoding -> "ASCII"];

Off[General::stop];
(* the answers of the paclet for one input, the messages of its boxes among them *)
answers[input_String] := Module[{boxes, issued},
	(* no message is printed, and each is still listed *)
	Block[{$MessageList = {}, $Messages = {}}, boxes = MathMLBoxes[input]; issued = $MessageList];
	Block[{$Messages = {}}, <|
		"Boxes" -> boxes,
		"Held" -> MathMLHeld[input],
		"Expression" -> MathMLExpression[input],
		"ImportExpression" -> MathMLImport[input, "Expression"],
		"XMLElement" -> MathMLImport[input, "XMLElement"],
		"XMLObject" -> MathMLImport[input, "XMLObject"],
		"Messages" -> Sort[DeleteDuplicates[Cases[issued, HoldForm[MessageName[_, tag_String]] :> tag]]]
	|>]
];

sameQ["Messages", mine_, recorded_] := mine === Sort[DeleteDuplicates[Flatten[StringCases[recorded, "\"" ~~ tag : Except["\""] .. ~~ "\"]]" :> tag]]]]
sameQ[_, mine_, recorded_String] := Block[{$Context = "Global`"}, text[mine] === recorded || mine === Block[{$Messages = {}}, ToExpression[recorded]]]

count = 0;
results = Catenate[Map[
	Function[case, With[{mine = Block[{$Context = "Global`"}, answers[case["Input"]]]},
		(* an input may assign, as x = 1 does where it is evaluated: each case starts from no definitions *)
		ClearAll["Global`*"];
		KeyValueMap[
			Function[{field, recorded}, With[{same = sameQ[field, mine[field], recorded]},
				If[ ! same && field === shown && count < show, count++;
					Print["== ", StringReplace[case["Input"], "\n" -> "\\n"]]; Print["  15.0: ", recorded]; Print["  ours: ", text[mine[field]]]];
				{case["Corpus"], field} -> same
			]],
			Join[KeyTake[case, {"Boxes", "Held", "Expression", "XMLElement", "XMLObject"}],
				<|"ImportExpression" -> Lookup[case, "ImportExpression", case["Expression"]], "Messages" -> Lookup[case, "Messages", {}]|>]
		]
	]],
	cases
]];
table = Map[ToString[Count[#, True]] <> "/" <> ToString[Length[#]] &, GroupBy[results, First -> Last]];
fields = {"XMLElement", "XMLObject", "Boxes", "Held", "Expression", "ImportExpression", "Messages"};
Print[TableForm[
	Map[Function[corpus, Map[Lookup[table, Key[{corpus, #}], "-"] &, fields]], DeleteDuplicates[Lookup[cases, "Corpus"]]],
	TableHeadings -> {DeleteDuplicates[Lookup[cases, "Corpus"]], fields}
]];
Put[table, FileNameJoin[{$TemporaryDirectory, "mathml-parity-" <> If[prefix === "", "all", prefix] <> ".wl"}]];
End[];

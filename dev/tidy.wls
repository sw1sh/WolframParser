(* ::Package:: *)

(* Lays Wolfram Language sources out as the v2 kernel's style guide asks
	(docs/wl-style.md of the kernel), moving no code:

	- tabs indent, one for each four columns of the spaces they replace;
	- no ; ends a top-level definition;
	- a section is a package-editor section, (* ::Section:: *) then its title,
	in place of a (* --- title --- *) or (* === title === *) banner;
	- a bracket, brace, association or parenthesis that spans lines closes at
	the start of a line, indented as the line it opens on; the closers of
	forms that open on one line share a line;
	- a Which or a Switch that spans lines has each test on a line of its own,
	one level deeper than its head's line, and each value on the line after,
	one level deeper again; one whose arguments span lines or hold a comment
	is left as it is.

	wl -f dev/tidy.wls [--check] file ...

	A line inside a string that spans lines keeps its whitespace, which is the
	string's. A file is written only when its held expressions are the same as
	before, but for the Null after each ; taken away. --check writes nothing and
	names the files that would change. *)

Needs["CodeParser`"]

Begin["Tidy`"]

fileText::usage = "fileText[file] gives the text of file, its UTF-8 decoded and nothing dropped."
fileText[file_String] := ByteArrayToString[ReadByteArray[file], "UTF-8"]

stringLines::usage = "stringLines[text] gives the numbers of the lines of text that lie inside a string spanning lines, after its first."
stringLines[text_String] := Union @ Flatten @ Cases[
	CodeParser`CodeConcreteParse[text, "SourceConvention" -> "LineColumn"],
	CodeParser`LeafNode[String, _, KeyValuePattern[CodeParser`Source -> {{first_, _}, {last_, _}}]] /; last > first :> Range[first + 1, last],
	Infinity
]

tabbedLine::usage = "tabbedLine[line] gives line with the spaces and tabs it begins with as tabs, one for each four columns, and an empty line \
for one of whitespace alone."
tabbedLine[line_String] := Replace[
	StringCases[line, StartOfString ~~ indent : (" " | "\t") ... ~~ rest___ ~~ EndOfString :> {indent, rest}],
	{
		{{_, ""}} :> "",
		{{indent_, rest_}} :> StringRepeat["\t", Quotient[StringCount[indent, " "] + 4 StringCount[indent, "\t"] + 2, 4]] <> rest
	}
]

tabbedText::usage = "tabbedText[text] gives text with each line indented by tabs, but for the lines inside a string that spans lines."
tabbedText[text_String] := With[{lines = StringSplit[text, "\n", All], kept = stringLines[text]},
	StringRiffle[MapIndexed[If[MemberQ[kept, First[#2]], #1, tabbedLine[#1]] &, lines], "\n"]
]

definitionSemicolons::usage = "definitionSemicolons[text] gives the character positions {start, end} of the ; that ends each top-level \
definition of text."
definitionSemicolons[text_String] := Cases[
	Replace[CodeParser`CodeConcreteParse[text, "SourceConvention" -> "SourceCharacterIndex"], CodeParser`ContainerNode[_, statements_, _] :> statements],
	CodeParser`InfixNode[
		CompoundExpression,
		{
			(CodeParser`BinaryNode | CodeParser`TernaryNode)[Set | SetDelayed | UpSet | UpSetDelayed | TagSet | TagSetDelayed, _, _],
			CodeParser`LeafNode[Token`Semi, ";", KeyValuePattern[CodeParser`Source -> {start_, end_}]],
			CodeParser`LeafNode[Token`Fake`ImplicitNull, _, _]
		},
		_
	] :> {start, end},
	{1}
]

withoutDefinitionSemicolons::usage = "withoutDefinitionSemicolons[text] gives text without the ; that ends each of its top-level definitions."
withoutDefinitionSemicolons[text_String] := With[{semicolons = definitionSemicolons[text]},
	If[semicolons === {}, text, StringReplacePart[text, "", semicolons]]
]

sectionedText::usage = "sectionedText[text] gives text with each (* --- title --- *) or (* === title === *) banner a package-editor section \
of the title, and the text after the title of a banner of more lines a comment of its own."
sectionedText[text_String] := StringReplace[text, {
	StartOfLine ~~ "(* " ~~ rule : ("-" .. | "=" ..) ~~ " " ~~ title : Shortest[Except["\n"] ..] ~~ " " ~~ rule2 : ("-" .. | "=" ..) ~~ " *)" ~~ EndOfLine /;
		rule === rule2 && StringLength[rule] >= 3 :> "(* ::Section:: *)\n(*" <> Capitalize[title] <> "*)",
	StartOfLine ~~ "(* === " ~~ title : Shortest[Except["\n"] ..] ~~ " ===\n" ~~ ("\t" | " ") .. ~~ body : Shortest[__] ~~ "*)" /; StringFreeQ[body, "(*" | "*)"] :>
		"(* ::Section:: *)\n(*" <> Capitalize[title] <> "*)\n\n(* " <> body <> "*)"
}]

(* The closer of a form that spans lines, its ], }, |> or ), goes at the start of a line, indented as
	the line its opener is on; after the closer of a form that opens on that same line, it stays on
	that closer's line. Each edit is the whitespace before a closer, replaced. *)
closerEdits::usage = "closerEdits[text] gives {{from, to}, whitespace} for each closer of a form of text that spans lines and is not where \
the style guide puts it: the whitespace from from to to before it, replaced."
closerEdits[text_String] := With[
	{
		groups = Cases[
			CodeParser`CodeConcreteParse[text, "SourceConvention" -> "SourceCharacterIndex"],
			CodeParser`GroupNode[
				_,
				{
					CodeParser`LeafNode[Token`OpenSquare | Token`OpenCurly | Token`LessBar | Token`OpenParen, _, KeyValuePattern[CodeParser`Source -> {open_, _}]],
					___,
					CodeParser`LeafNode[Token`CloseSquare | Token`CloseCurly | Token`BarGreater | Token`CloseParen, _, KeyValuePattern[CodeParser`Source -> {close_, _}]]
				},
				_
			] :> {open, close},
			Infinity
		],
		lines = Prepend[1 + Accumulate[1 - Unitize[ToCharacterCode[text] - 10]], 1],
		codes = ToCharacterCode[text]
	},
	closersPlaced[text, codes, lines, groups, Association[Map[Last[#] -> lines[[First[#]]] &, groups]]]
]

closersPlaced::usage = "closersPlaced[text, codes, lines, groups, openedOn] gives closerEdits' edits of the groups {open, close} of text, \
lines the line of each character and openedOn the line each closer's group opens on, by its closer's place."
closersPlaced[text_String, codes_List, lines_List, groups_List, openedOn_Association] := Cases[
	groups,
	{open_Integer, close_Integer} /; lines[[open]] =!= lines[[close]] :> closerEdit[text, codes, lines, openedOn, open, close]
]

closerEdit::usage = "closerEdit[text, codes, lines, openedOn, open, close] gives the edit of the whitespace before the closer at close of \
the group opened at open, or Nothing where it is placed."
closerEdit[text_String, codes_List, lines_List, openedOn_Association, open_Integer, close_Integer] := With[
	{
		before = close - LengthWhile[Reverse[Take[codes, close - 1]], 32 <= # <= 32 || # === 9 &] - 1,
		indent = lineIndent[codes, lines, lines[[open]]]
	},
	Which[
		before === 0 || codes[[before]] === 10,
			If[codesText[codes, before + 1, close - 1] === indent, Nothing, {{before + 1, close - 1}, indent}],
		Lookup[openedOn, before, 0] === lines[[open]],
			Nothing,
		True,
			{{before + 1, close - 1}, "\n" <> indent}
	]
]

lineIndent::usage = "lineIndent[codes, lines, line] gives the tabs and spaces that the line of the codes begins with."
lineIndent[codes_List, lines_List, line_Integer] := With[{start = First[FirstPosition[lines, line]]},
	FromCharacterCode[TakeWhile[Drop[codes, start - 1], # === 9 || # === 32 &]]
]

codesText::usage = "codesText[codes, from, to] gives the text of the codes from from to to, \"\" where to is before from."
codesText[codes_List, from_Integer, to_Integer] := FromCharacterCode[Take[codes, {from, to}]]

(* A closer put on a line of its own can move the line an opener after it is on, so the closers are
	placed again until none moves. *)
closedText::usage = "closedText[text] gives text with the closer of each form that spans lines where the style guide puts it."
closedText[text_String] := FixedPoint[closedOnce, text, 8]

closedOnce::usage = "closedOnce[text] gives text with the closers closerEdits gives edits of placed, once."
closedOnce[text_String] := With[{edits = closerEdits[text]},
	If[edits === {}, text, StringReplacePart[text, edits[[All, 2]], edits[[All, 1]]]]
]

(* A Which or a Switch that spans lines, its arguments each on one line and no comment in it, laid out
	again: Which[ and its tests one level deeper than its line, Switch[expr, and its forms so, each
	value one level deeper again, and the closer under the line. *)
casesEdits::usage = "casesEdits[text] gives {{from, to}, new} for the bracket of each Which or Switch of text that spans lines, the text from \
from to to laid out again as new."
casesEdits[text_String] := With[{codes = ToCharacterCode[text], lines = Prepend[1 + Accumulate[1 - Unitize[ToCharacterCode[text] - 10]], 1]},
	Cases[
		CodeParser`CodeConcreteParse[text, "SourceConvention" -> "SourceCharacterIndex"],
		CodeParser`CallNode[
			{CodeParser`LeafNode[Symbol, head : "Which" | "Switch", _]},
			CodeParser`GroupNode[
				CodeParser`GroupSquare,
				{
					CodeParser`LeafNode[Token`OpenSquare, _, KeyValuePattern[CodeParser`Source -> {open_, _}]],
					inner___,
					CodeParser`LeafNode[Token`CloseSquare, _, KeyValuePattern[CodeParser`Source -> {close_, _}]]
				},
				_
			],
			_
		] /; lines[[open]] =!= lines[[close]] :> casesEdit[text, codes, lines, head, open, close, {inner}],
		Infinity
	]
]

casesEdit::usage = "casesEdit[text, codes, lines, head, open, close, inner] gives the edit of the bracket of a Which or Switch from open to \
close, its nodes inner, or Nothing where it is left as it is."
casesEdit[text_String, codes_List, lines_List, head_String, open_Integer, close_Integer, inner_List] := casesLaidOut[
	text,
	codes,
	lines,
	head,
	open,
	close,
	Replace[
		DeleteCases[inner, CodeParser`LeafNode[Whitespace | Token`Newline, _, _]],
		{
			{CodeParser`InfixNode[Comma, items_List, _]} :> DeleteCases[items, CodeParser`LeafNode[Token`Comma | Whitespace | Token`Newline, _, _]],
			_ -> None
		}
	]
]

casesLaidOut::usage = "casesLaidOut[text, codes, lines, head, open, close, arguments] gives the edit that lays the arguments of a Which or \
Switch out again, or Nothing for arguments that span lines, hold a comment, or are not of tests and values."
casesLaidOut[text_String, codes_List, lines_List, head_String, open_Integer, close_Integer, arguments_List] /; And[
	FreeQ[arguments, CodeParser`LeafNode[Token`Comment, _, _]],
	StringFreeQ[StringTake[text, {open, close}], "(*"],
	If[head === "Which", EvenQ[Length[arguments]] && Length[arguments] >= 2, OddQ[Length[arguments]] && Length[arguments] >= 3]
] := casesText[
	head,
	open,
	close,
	Map[StringTake[text, Lookup[Last[#], CodeParser`Source]] &, arguments],
	lineIndent[codes, lines, lines[[open]]]
]
casesLaidOut[___] := Nothing

casesText::usage = "casesText[head, open, close, texts, indent] gives the edit of the bracket from open to close of a Which or Switch whose \
arguments' texts are texts, its line indented by indent, or Nothing where a text spans lines."
casesText[_String, _Integer, _Integer, texts_List, _String] /; AnyTrue[texts, StringContainsQ[#, "\n"] &] := Nothing
casesText[head_String, open_Integer, close_Integer, texts_List, indent_String] := {
	{open, close},
	StringJoin[
		"[",
		If[head === "Switch", First[texts] <> ",", ""],
		"\n",
		StringRiffle[
			MapIndexed[If[OddQ[First[#2]], indent <> "\t" <> #1, indent <> "\t\t" <> #1] &, If[head === "Switch", Rest[texts], texts]],
			",\n"
		],
		"\n",
		indent,
		"]"
	]
}

casedText::usage = "casedText[text] gives text with each Which and Switch that spans lines laid out as the style guide asks."
casedText[text_String] := With[{edits = casesEdits[text]},
	If[edits === {}, text, StringReplacePart[text, edits[[All, 2]], edits[[All, 1]]]]
]

tidyText::usage = "tidyText[text] gives text laid out as the style guide asks."
tidyText[text_String] := closedText @ FixedPoint[casedText, tabbedText @ sectionedText @ withoutDefinitionSemicolons[text], 8]

heldStatements::usage = "heldStatements[text] gives the statements of text, each held, a definition and the Null a ; after it leaves as the \
definition alone."
heldStatements[text_String] := Replace[
	ImportString[text, {"Package", "HeldExpressions"}],
	HoldComplete[CompoundExpression[definition_, Null]] :> HoldComplete[definition],
	{1}
]

tidyFile::usage = "tidyFile[file, write] lays file out as the style guide asks, writing it when write is True and its held statements stay \
the same, and gives what it did."
tidyFile[file_String, write_ : True] := With[{text = fileText[file]},
	With[{tidy = tidyText[text]},
		Which[
			tidy === text,
				"unchanged " <> file,
			heldStatements[tidy] =!= heldStatements[text],
				"NOT WRITTEN " <> file <> ": its statements would change",
			!TrueQ[write],
				"would tidy " <> file,
			True,
				With[{stream = OpenWrite[file, BinaryFormat -> True]},
					BinaryWrite[stream, StringToByteArray[tidy, "UTF-8"]];
					Close[stream]
				];
				"tidied " <> file
		]
	]
]

End[]

With[{arguments = Rest[$ScriptCommandLine]},
	Scan[Print @ Tidy`tidyFile[#, !MemberQ[arguments, "--check"]] &, DeleteCases[arguments, "--check"]]
]

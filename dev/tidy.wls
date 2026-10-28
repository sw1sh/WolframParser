(* ::Package:: *)

(* Lays Wolfram Language sources out as the v2 kernel's style guide asks
   (docs/wl-style.md of the kernel), moving no code:

   - tabs indent, one for each four columns of the spaces they replace;
   - no ; ends a top-level definition;
   - a section is a package-editor section, (* ::Section:: *) then its title,
     in place of a (* --- title --- *) or (* === title === *) banner.

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

tidyText::usage = "tidyText[text] gives text laid out as the style guide asks."
tidyText[text_String] := tabbedText @ sectionedText @ withoutDefinitionSemicolons[text]

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

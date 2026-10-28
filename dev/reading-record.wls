(* ::Package:: *)

(* Records what the Wolfram Language reader of one checkout gives on a fixed corpus, so that two
   checkouts can be held to each other, as a change that is to keep the reading must:

	wl -f dev/reading-record.wls corpus out.wxf

   The checkout is the one this script is in. The corpus is the .wl files under corpus/Parser/Kernel,
   cut into chunks of one to six lines, each read as it is, cut short, with a character taken out
   and with one put in, by a fixed seed, and a list of forms. For each source the record holds
   WolframLanguageSyntaxQ, WolframLanguageSyntaxLength, WolframLanguageHeld, every part
   WolframLanguageHeldNext gives up to its end or its failure, and WolframLanguageProgram. Two
   records are the same file where the readings are the same. *)

$ProgressReporting = False

Module[{root = ParentDirectory[DirectoryName[$InputFileName]]},
	PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]]
]
Needs["Wolfram`Parser`"]

Begin["ReadingRecord`"]

$forms = {"", " ", "a", "f[x", "f[x)", "a +", "a\nb", "a;", "(* c *)", "(* c", "\"s", "\"a\\[", "\"a\\[Alpha", "a::b:", "a::b_", "?a*=b",
	"x >> b[c", "t/:a", "t/:a:=[b", "1``-3", "0``", "f[a,,b]", "{a,}", "a \\\n+ b", "\\:0041 + 1", "<<a+b", "=[x]", "''[x]", "a ~ f! ~ b",
	"\\!\\(x\\)", "f[x_] := x^2\ng[y] = 3;\n(* c *)\n", "x = 1\n1 +"}

sourceTexts::usage = "sourceTexts[corpus] gives the text of each .wl file under corpus/Parser/Kernel."
sourceTexts[corpus_String] := Map[
	ByteArrayToString[ReadByteArray[#], "UTF-8"] &,
	Sort @ FileNames["*.wl", FileNameJoin[{corpus, "Parser", "Kernel"}], Infinity]
]

chunks::usage = "chunks[lines, n] gives n chunks of one to six of the lines, from random places."
chunks[lines_List, n_Integer] := Table[
	With[{first = RandomInteger[{1, Length[lines]}]}, StringRiffle[Take[lines, {first, Min[first + RandomInteger[{0, 5}], Length[lines]]}], "\n"]],
	{n}
]

mutations::usage = "mutations[s] gives s, s cut short, s with a character taken out and s with one put in, at random places."
mutations[""] := {""}
mutations[s_String] := {
	s,
	StringTake[s, RandomInteger[{0, StringLength[s] - 1}]],
	StringDrop[s, {RandomInteger[{1, StringLength[s]}]}],
	StringInsert[s, RandomChoice[Characters["[](){}\"\\;:,=@#%&*^`'\n_.?!~|/<>+-"]], RandomInteger[{1, StringLength[s] + 1}]]
}

heldNextParts::usage = "heldNextParts[s] gives every part WolframLanguageHeldNext gives the source s, up to its end or its failure, at \
most 400."
heldNextParts[s_String] := NestWhileList[
	Wolfram`Parser`Languages`WolframLanguage`WolframLanguageHeldNext[s, #[[2]]] &,
	Wolfram`Parser`Languages`WolframLanguage`WolframLanguageHeldNext[s, 1],
	ListQ[#] && !FailureQ[First[#]] &,
	1,
	400
]

reading::usage = "reading[s] gives the record of the source s."
reading[s_String] := {
	s,
	Wolfram`Parser`Languages`WolframLanguage`WolframLanguageSyntaxQ[s],
	Wolfram`Parser`Languages`WolframLanguage`WolframLanguageSyntaxLength[s],
	Wolfram`Parser`Languages`WolframLanguage`WolframLanguageHeld[s],
	heldNextParts[s],
	Wolfram`Parser`Languages`WolframLanguage`WolframLanguageProgram[s]
}

End[]

With[{corpus = $ScriptCommandLine[[-2]], out = $ScriptCommandLine[[-1]]},
	SeedRandom[20261028];
	With[{sources = Join[
		ReadingRecord`$forms,
		Catenate[ReadingRecord`mutations /@ ReadingRecord`chunks[Catenate[StringSplit[#, "\n"] & /@ ReadingRecord`sourceTexts[corpus]], 1500]]
	]},
		Export[out, ReadingRecord`reading /@ sources, "WXF"];
		Print[Length[sources], " sources recorded"]
	]
]

(* ::Package:: *)

(* :Title: WolframLanguageContinuations.wl - line continuations and character escapes of the Wolfram Language *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	The reading of a source that holds a line continuation or a character escape:
	WolframLanguage.wl's readSource and lineContinuations load this file at the
	first such source, so that a source of neither, as most are, loads none of it.
	It takes the line continuations out, makes each character escape its character,
	keeps the positions in the source of the characters read as runs, and gives the
	nodes and failures read their places in the source. *)

(* The file begins its private context alone and names no package to need: it loads where the
	contexts it uses are loaded already, in a kernel under that kernel's own names, where a package
	needed by name cannot be loaded as one. *)
Begin["Wolfram`Parser`Languages`WolframLanguage`Private`"]

(* ::Section:: *)
(*Line continuations*)

(* A \ before a newline, outside a string, a comment and the file name
	of << or >>, continues the line: CodeParser reads the source as though
	the \, the newline and the spaces and tabs after it were not there.
	Their text is in the token they fall in, else in the token after them,
	and at the end of the source in none, there a string's too. The spans
	{first, last} of them in s, those that follow one another one. The scan
	reads a character or an escape at a time, its state {the codes, where it
	goes on, its mode, the spans found, a linked list}, the mode 0 in code,
	-1 in a string and the depth of the comments in one. The typed scan of
	WolframLanguageFast.wl, typedContinuationSpans, reads them where it is
	loaded, in one pass over the codes; it leaves a source with a << or >>
	in code, whose file name it does not read, to this scan. *)
continuationSpans::usage = "continuationSpans[s] gives the spans {first, last} of the line continuations of s, those that follow one \
another one."
continuationSpans[s_String] := With[{typed = typedContinuationSpans[s]}, If[ListQ[typed], typed, scannedContinuationSpans[s]]]

scannedContinuationSpans::usage = "scannedContinuationSpans[s] gives continuationSpans of s by the scan a character or an escape at a time."
scannedContinuationSpans[s_String] := Reverse @ linkedItems @ Last @ NestWhile[continuationStep, {ToCharacterCode[s], 1, 0, {}}, scanOnQ]

continuationStep::usage = "continuationStep[{codes, at, mode, spans}] gives the scan's state after the character, or the escape, at at."
continuationStep[{codes_List, at_Integer, -1, spans_List}] := Which[
	codes[[at]] === 92 && continuationEnd[codes, at] === Length[codes],
		{codes, Length[codes] + 1, -1, {{at, Length[codes]}, spans}},
	codes[[at]] === 92,
		{codes, at + 2, -1, spans},
	codes[[at]] === 34,
		{codes, at + 1, 0, spans},
	True,
		{codes, at + 1, -1, spans}
]
continuationStep[{codes_List, at_Integer, depth_Integer, spans_List}] /; depth > 0 := Append[inCommentStep[codes, at, depth], spans]
continuationStep[{codes_List, at_Integer, 0, spans_List}] := Which[
	codes[[at]] === 34,
		{codes, at + 1, -1, spans},
	pairAtQ[codes, at, 40, 42],
		{codes, at + 2, 1, spans},
	pairAtQ[codes, at, 60, 60],
		{codes, fileNameEnd[codes, at + 2] + 1, 0, spans},
	pairAtQ[codes, at, 62, 62],
		{codes, fileNameEnd[codes, If[at + 2 <= Length[codes] && codes[[at + 2]] === 62, at + 3, at + 2]] + 1, 0, spans},
	codes[[at]] === 92 && continuationEnd[codes, at] >= at,
		{codes, continuationEnd[codes, at] + 1, 0, {{at, continuationEnd[codes, at]}, spans}},
	(* a \ and the character it escapes *)
	codes[[at]] === 92,
		{codes, at + 2, 0, spans},
	True,
		{codes, at + 1, 0, spans}
]

pairAtQ::usage = "pairAtQ[codes, at, a, b] is True where the codes a and b are the codes at at and after it."
pairAtQ[codes_List, at_Integer, a_Integer, b_Integer] := codes[[at]] === a && at < Length[codes] && codes[[at + 1]] === b

(* in a comment, a (* and a *) nest, and a \( escapes its parenthesis *)
inCommentStep::usage = "inCommentStep[codes, at, depth] gives {codes, the place after the character, or the pair, at at, the depth of the \
comments after it}, inside depth comments."
inCommentStep[codes_List, at_Integer, depth_Integer] := Which[
	pairAtQ[codes, at, 40, 42],
		{codes, at + 2, depth + 1},
	pairAtQ[codes, at, 42, 41],
		{codes, at + 2, depth - 1},
	pairAtQ[codes, at, 92, 40],
		{codes, at + 2, depth},
	True,
		{codes, at + 1, depth}
]

(* the last character of the continuations from at on, at - 1 if none begins there: each a \, a
	newline, a return or both, and the spaces and tabs after it *)
continuationEnd::usage = "continuationEnd[codes, at] gives the last character of the line continuations from at on, at - 1 if none \
begins there."
continuationEnd[codes_List, at_Integer] := Last[NestWhile[continuationRunStep, {codes, at}, continuationAtQ]] - 1

continuationAtQ::usage = "continuationAtQ[{codes, at}] is True where a line continuation begins at at."
continuationAtQ[{codes_List, at_Integer}] := at < Length[codes] && codes[[at]] === 92 && (codes[[at + 1]] === 10 || codes[[at + 1]] === 13)

continuationRunStep::usage = "continuationRunStep[{codes, at}] gives the place after the line continuation at at, and the spaces and tabs \
after it."
continuationRunStep[{codes_List, at_Integer}] := With[{after = at + If[codes[[at + 1]] === 13 && at + 2 <= Length[codes] && codes[[at + 2]] === 10, 3, 2]},
	{codes, NestWhile[# + 1 &, after, # <= Length[codes] && MemberQ[{32, 9, 11, 12}, codes[[#]]] &]}
]

$alphanumericCodes = AssociationThread[Join[Range[48, 57], Range[65, 90], Range[97, 122]] -> True]
(* the characters of a file name but its \ *)
$fileCharacterCodes = Join[$alphanumericCodes, AssociationThread[ToCharacterCode["$`_./~:!*?-"] -> True]]


(* The positions in s of the characters read, n of them, as runs: for each run of characters left
	out, where the characters after it begin in the text read and how many characters were left out
	up to its end, {at, out, at, out, ...}, packed. The character at c of the text read is at c + out
	in s, out that of the last run at or before c, 0 before the first. A run per line continuation
	and escape, never a position per character. *)
keptRuns::usage = "keptRuns[runs, n] stands for the positions in a source of the n characters read of it, runs {at, out, ...}: for each \
run left out, where the characters after it begin in the text read and how many were left out up to its end."

keptOf::usage = "keptOf[length, spans] gives the keptRuns of a source of that length read without the spans {first, last} of it."
keptOf[length_Integer, spans_List] := With[{runs = mergedSpans[SortBy[spans, First]]},
	With[{out = Accumulate[runs[[All, 2]] - runs[[All, 1]] + 1]},
		keptRuns[Developer`ToPackedArray[Flatten[Transpose[{runs[[All, 1]] - Prepend[Most[out], 0], out}]]], length - Last[out]]
	]
]

(* spans sorted by their first position, those that overlap made one: a span begins a new one where it
	begins past the reach of all those before it *)
mergedSpans::usage = "mergedSpans[spans] gives the spans, sorted by their first position, those that overlap made one."
mergedSpans[spans_List] := With[{firsts = spans[[All, 1]], reach = FoldList[Max, spans[[All, 2]]]},
	With[{starts = Flatten[Position[Prepend[UnitStep[Rest[firsts] - Most[reach] - 1], 1], 1]]},
		Transpose[{firsts[[starts]], reach[[Append[Rest[starts] - 1, Length[firsts]]]]}]
	]
]

keptCount::usage = "keptCount[kept] gives how many characters were read."
keptCount[keptRuns[_List, n_Integer]] := n

keptAt::usage = "keptAt[kept, c] gives the position in the source of the character at c of the text read, or the positions of the \
characters at the positions cs."
keptAt[keptRuns[runs_List, _], c_Integer] := c + leftOut[runs, c]
keptAt[keptRuns[runs_List, _], cs_List] := cs + leftOutAll[runs, cs]

(* the characters left out before the character at c of the text read: those up to the last run at
	or before c, found by halving *)
leftOut::usage = "leftOut[runs, c] gives how many characters were left out before the character at c of the text read."
leftOut[runs_List, c_Integer] := Module[{lo = 0, hi = Quotient[Length[runs], 2], mid},
	While[ lo < hi,
		mid = Quotient[lo + hi + 1, 2];
		If[runs[[2 mid - 1]] <= c, lo = mid, hi = mid - 1]
	];
	If[lo === 0, 0, runs[[2 lo]]]
]

(* the same at each of the positions cs, from one ordering of the runs' places with them: the runs at
	or before a position are those ordered before it, a run's place 2 at and a position's 2 c + 1 *)
leftOutAll::usage = "leftOutAll[runs, cs] gives how many characters were left out before each character at the positions cs of the \
text read."
leftOutAll[runs_List, cs_List] := With[{count = Quotient[Length[runs], 2]},
	With[{order = Ordering[Join[2 runs[[1 ;; ;; 2]], 2 cs + 1]]},
		Prepend[runs[[2 ;; ;; 2]], 0][[Accumulate[UnitStep[count - order]][[Ordering[order][[count + 1 ;;]]]] + 1]]
	]
]

(* ::Section:: *)
(*Character escapes*)

(* A \:xxxx, \.xx or \|xxxxxx outside a string and a comment is the character its hexadecimal
	digits name, as Wolfram 15's reader reads it before it reads tokens: a letter of a name or of a
	file, an operator, a bracket. The spans {first, last} of them in s, each with its character. The
	scan's state is continuationSpans's, its found the escapes. *)
escapeSpans::usage = "escapeSpans[s] gives {{first, last}, character} for each character escape of s outside its strings and comments."
escapeSpans[s_String] := Reverse @ linkedItems @ Last @ NestWhile[escapeStep, {ToCharacterCode[s], 1, 0, {}}, scanOnQ]

escapeStep::usage = "escapeStep[{codes, at, mode, escapes}] gives the scan's state after the character, or the escape, at at."
escapeStep[{codes_List, at_Integer, -1, escapes_List}] := Which[
	codes[[at]] === 92,
		{codes, at + 2, -1, escapes},
	codes[[at]] === 34,
		{codes, at + 1, 0, escapes},
	True,
		{codes, at + 1, -1, escapes}
]
escapeStep[{codes_List, at_Integer, depth_Integer, escapes_List}] /; depth > 0 := Append[inCommentStep[codes, at, depth], escapes]
escapeStep[{codes_List, at_Integer, 0, escapes_List}] := Which[
	codes[[at]] === 34,
		{codes, at + 1, -1, escapes},
	pairAtQ[codes, at, 40, 42],
		{codes, at + 2, 1, escapes},
	codes[[at]] === 92 && escapeWidth[codes, at] > 0,
		{codes, at + 2 + escapeWidth[codes, at], 0, {escapeOf[codes, at, escapeWidth[codes, at]], escapes}},
	(* \ooo, three octal digits: the character of that code, \101 an A *)
	codes[[at]] === 92 && octalEscapeQ[codes, at],
		{codes, at + 4, 0, {{{at, at + 3}, FromCharacterCode[FromDigits[FromCharacterCode[Take[codes, {at + 1, at + 3}]], 8]]}, escapes}},
	(* a \ and the character it escapes *)
	codes[[at]] === 92,
		{codes, at + 2, 0, escapes},
	True,
		{codes, at + 1, 0, escapes}
]

(* the digits of a \:, \. or \| escape at at: their count where they are all hexadecimal digits and
	name a character, else 0 *)
escapeWidth::usage = "escapeWidth[codes, at] gives the count of the hexadecimal digits of the character escape at at, 0 where none is \
there."
escapeWidth[codes_List, at_Integer] := With[{width = If[at < Length[codes], Switch[codes[[at + 1]], 58, 4, 46, 2, 124, 6, _, 0], 0]},
	If[width > 0 && at + 1 + width <= Length[codes] && hexadecimalCodeQ[Take[codes, {at + 2, at + 1 + width}]], width, 0]
]

octalEscapeQ::usage = "octalEscapeQ[codes, at] is True where three octal digits follow the \\ at at."
octalEscapeQ[codes_List, at_Integer] := at + 3 <= Length[codes] && AllTrue[Take[codes, {at + 1, at + 3}], 48 <= # <= 55 &]

hexadecimalCodeQ::usage = "hexadecimalCodeQ[codes] is True where the codes are hexadecimal digits that name a character."
hexadecimalCodeQ[codes_List] := AllTrue[codes, KeyExistsQ[$hexadecimalCodes, #] &] && FromDigits[FromCharacterCode[codes], 16] <= 1114111

escapeOf::usage = "escapeOf[codes, at, width] gives {{at, its last code}, the character} of the character escape at at of width digits."
escapeOf[codes_List, at_Integer, width_Integer] :=
	{{at, at + 1 + width}, FromCharacterCode[FromDigits[FromCharacterCode[Take[codes, {at + 2, at + 1 + width}]], 16]]}

$hexadecimalCodes = AssociationThread[Join[Range[48, 57], Range[65, 70], Range[97, 102]] -> True]

(* the last character of the spaces and the file name of << or >> from start on in the codes, a
	letter past ASCII one of its characters and a long name one of its characters *)
fileNameEnd::usage = "fileNameEnd[codes, start] gives the last character of the spaces and the file name of << or >> from start on."
fileNameEnd[codes_List, start_Integer] := Part[
	NestWhile[fileNameStep, {codes, start + LengthWhile[Drop[codes, start - 1], # === 32 || # === 9 &], True}, fileNameGoesOnQ],
	2
] - 1

fileNameGoesOnQ::usage = "fileNameGoesOnQ[{codes, at, going}] is True where the file name goes on at at."
fileNameGoesOnQ[{codes_List, at_Integer, going_}] := going && at <= Length[codes] && fileNameCodeQ[codes[[at]]]

fileNameCodeQ::usage = "fileNameCodeQ[code] is True for a code a file name holds: a file character, a \\ or a letter past ASCII."
fileNameCodeQ[code_Integer] := KeyExistsQ[$fileCharacterCodes, code] || code === 92 || code > 127 && LetterQ[FromCharacterCode[code]]

fileNameStep::usage = "fileNameStep[{codes, at, going}] gives the place after the character, or the long name, of the file name at at, \
and whether it goes on, False after a long name not closed."
fileNameStep[{codes_List, at_Integer, _}] /; pairAtQ[codes, at, 92, 91] :=
	longNameEnd[codes, at + 2 + LengthWhile[Drop[codes, at + 1], KeyExistsQ[$alphanumericCodes, #] &]]
fileNameStep[{codes_List, at_Integer, _}] := {codes, at + 1, True}

longNameEnd::usage = "longNameEnd[codes, at] gives the place after the ] of a long name at at and True, or at and False where none is \
there."
longNameEnd[codes_List, at_Integer] := If[at <= Length[codes] && codes[[at]] === 93, {codes, at + 1, True}, {codes, at, False}]

characterEscapes::usage = "characterEscapes[s] gives the character escapes of s outside its strings and comments, {} for none."
characterEscapes[s_String] := If[StringContainsQ[s, "\\:" | "\\." | "\\|" | ("\\" ~~ DigitCharacter)], escapeSpans[s], {}]


continuedSource::usage = "continuedSource[s] gives readSource[s] of a source with a \\ in it."
continuedSource[s_String] := With[{spans = lineContinuations[s], escapes = characterEscapes[s]},
	If[ spans === {} && escapes === {}, {s, None},
		With[{edits = SortBy[Join[Thread[{spans, ""}], escapes], #[[1, 1]] &]},
			{StringReplacePart[s, edits[[All, 2]], edits[[All, 1]]],
			keptOf[StringLength[s], Join[spans, Map[{#[[1]] + 1, #[[2]]} &, escapes[[All, 1]]]]]
			}
		]
	]
]

(* offsets into the source read without its line continuations made
	offsets into the source: a node begins where the continuations before
	its first character do, and ends past its last character *)
continuedOffsets[tree_, kept_keptRuns] := With[{at = Function[o, If[o === 1, 1, keptAt[kept, o - 1] + 1]]},
	tree /. (a_Association /; MatchQ[Lookup[a, "Source"], {_Integer, _Integer}]) :> Append[a, "Source" -> Map[at, a["Source"]]]
]

(* a failure at a character of the source read without its line
	continuations, placed at that character of the source *)
continuedFailure[f_Failure, kept_keptRuns, s_String] := With[{at = f["Position"]},
	If[ IntegerQ[at],
		With[{p = If[at <= keptCount[kept], keptAt[kept, at], StringLength[s] + 1]},
			Failure[f[[1]], Join[f[[2]], <|"Position" -> p, "MessageParameters" -> Append[Lookup[f[[2]], "MessageParameters", <||>], "Position" -> p]|>]]
		],
		f
	]
]

(* the leaves of a tree read from s without its line continuations, each
	given its text in s: kept is the keptRuns of the positions in s of the characters read, looked up
	for every leaf at once *)
continuedLeaves::usage = "continuedLeaves[children, s, kept] gives the nodes children, read from s without its line continuations, each \
leaf given its text in s, kept the keptRuns of the positions in s of the characters read."
continuedLeaves[children_List, s_String, kept_keptRuns] := With[
	{positions = Position[children, (CodeParser`LeafNode | CodeParser`ErrorNode)[_, _String, _], Infinity, Heads -> False]},
	{leaves = Extract[children, positions]},
	{lengths = Developer`ToPackedArray[leafTextLength /@ leaves]},
	{before = Most[Accumulate[Prepend[lengths, 0]]]},
	ReplacePart[
		children,
		Thread[positions -> MapThread[
			continuedLeaf[#1, s, #2, #3, If[#4 === 0, 1, #5 + 1]] &,
			{leaves, keptAt[kept, before + 1], keptAt[kept, before + lengths], before, keptAt[kept, before]}
		]]
	]
]

leafTextLength::usage = "leafTextLength[leaf] gives the length of the text of a leaf."
leafTextLength[_[_, t_String, _]] := StringLength[t]

(* a leaf its text in s: its first character read at first, its last at last, and the line
	continuations before it from from on, its text those and the continuations in it too, where any are *)
continuedLeaf::usage = "continuedLeaf[leaf, s, first, last, from] gives the leaf with its text in s, its characters read from first to \
last in s and the line continuations before it from from on."
continuedLeaf[leaf : (CodeParser`LeafNode | CodeParser`ErrorNode)[_, "", _], _String, _Integer, _Integer, _Integer] := leaf
continuedLeaf[(head : CodeParser`LeafNode | CodeParser`ErrorNode)[k_, t_String, m_], s_String, first_Integer, last_Integer, from_Integer] :=
	If[from === first && last - first + 1 === StringLength[t],
		head[k, t, m],
		head[k, StringTake[s, {from, last}], Append[m, continuedBy -> first - from]]
	]

(* The mark that this file is read: languageFileRead (WolframLanguage.wl) loads the file only
	without it, so a program that has the file built in loads nothing. *)
$continuationsRead = True

End[]

(* ::Package:: *)

(* :Title: WolframLanguageEscapes.wl - the character escapes of a source *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	The \:xxxx, \.xx, \|xxxxxx and \ooo escapes of a source outside its strings and comments, which
	the reader reads as their characters before it reads tokens: a typed scan over the source's codes,
	and the same scan a character at a time for a kernel without typed code. WolframLanguageFast.wl
	loads this file at the first source that holds such an escape. It begins its private context alone
	and names no package to need: the contexts it uses are loaded by then, in a kernel under their own
	names. *)

Begin["Wolfram`Parser`Languages`WolframLanguage`Private`"]

(* ::Section:: *)
(*Character escapes*)

(* A \:xxxx, \.xx or \|xxxxxx outside a string and a comment is the character its hexadecimal
	digits name, as Wolfram 15's reader reads it before it reads tokens: a letter of a name or of a
	file, an operator, a bracket. The spans {first, last} of them in s, each with its character. The
	scan's state is continuationSpans's, its found the escapes. *)
(* The character escapes of a source, as escapeSpans reads them, typed code over its codes:
	{m, first1, last1, code1, ..., firstm, lastm, codem} for its m escapes \:hhhh, \.hh and \|hhhhhh
	whose hexadecimal digits name a character, and \ooo of three octal digits, outside its strings
	and comments, each its first and last code and the code of its character. In a string a \ escapes the character after it; in a
	comment (* and *) nest and \( escapes its parenthesis; in code a \ that begins no such escape
	escapes the character after it. A first pass counts the escapes and a second writes them. *)
$fastCharacterEscapesDeclaration = FunctionDeclaration[fastCharacterEscapes,
	Typed[{"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{ceCodes},
		Native`UncheckedBlock[Module[{n = Length[ceCodes], pass = 1, count = 0, at = 1, mode = 0, c = 0, width = 0, k = 0, d = 0, code = 0, octal = 0, out = Native`UncheckedArray[0, 1]},
			out[[1]] = 0;
			While[ pass <= 2,
				at = 1; mode = 0; count = 0;
				While[ at <= n,
					c = ceCodes[[at]];
					Which[
						mode > 0,
							Which[
								c == 40 && at < n && ceCodes[[at + 1]] == 42, mode++; at += 2,
								c == 42 && at < n && ceCodes[[at + 1]] == 41, mode--; at += 2,
								c == 92 && at < n && ceCodes[[at + 1]] == 40, at += 2,
								True, at++
							],
						mode < 0,
							Which[
								c == 92, at += 2,
								c == 34, mode = 0; at++,
								True, at++
							],
						True,
							width = 0;
							If[ c == 92 && at < n,
								width = Which[ceCodes[[at + 1]] == 58, 4, ceCodes[[at + 1]] == 46, 2, ceCodes[[at + 1]] == 124, 6, True, 0];
								If[ width > 0 && at + 1 + width > n, width = 0];
								code = 0; k = 1;
								While[ width > 0 && k <= width,
									d = ceCodes[[at + 1 + k]];
									Which[
										d >= 48 && d <= 57, code = 16 code + d - 48,
										d >= 65 && d <= 70, code = 16 code + d - 55,
										d >= 97 && d <= 102, code = 16 code + d - 87,
										True, width = 0
									];
									k++
								];
								If[ code > 1114111, width = 0]
							];
							octal = 0;
							If[ c == 92 && width == 0 && at + 3 <= n && ceCodes[[at + 1]] >= 48 && ceCodes[[at + 1]] <= 55 &&
									ceCodes[[at + 2]] >= 48 && ceCodes[[at + 2]] <= 55 && ceCodes[[at + 3]] >= 48 && ceCodes[[at + 3]] <= 55,
								octal = 1;
								code = 64 (ceCodes[[at + 1]] - 48) + 8 (ceCodes[[at + 2]] - 48) + ceCodes[[at + 3]] - 48
							];
							Which[
								c == 34, mode = -1; at++,
								c == 40 && at < n && ceCodes[[at + 1]] == 42, mode = 1; at += 2,
								width > 0,
									count++;
									If[pass == 2, out[[3 count - 1]] = at; out[[3 count]] = at + 1 + width; out[[3 count + 1]] = code];
									at += 2 + width,
								octal == 1,
									count++;
									If[pass == 2, out[[3 count - 1]] = at; out[[3 count]] = at + 3; out[[3 count + 1]] = code];
									at += 4,
								c == 92, at += 2,
								True, at++
							]
					]
				];
				If[ pass == 1, out = Native`UncheckedArray[0, 3 count + 1]; out[[1]] = count];
				pass++
			];
			out
		]]
	]
]

(* the typed character escape scan run here, fixed at its first use *)
fastCharacterEscapesFunction := fastCharacterEscapesFunction = typedFunction[fastCharacterEscapes, $fastCharacterEscapesDeclaration]

(* escapeSpans of s by the typed scan *)
typedEscapeSpans::usage = "typedEscapeSpans[s] gives the character escapes of s by the typed scan."
typedEscapeSpans[s_String] := With[{found = fastCharacterEscapesFunction[Developer`ToPackedArray[ToCharacterCode[s]]]},
	Map[{{#[[1]], #[[2]]}, FromCharacterCode[#[[3]]]} &, Partition[Rest[found], 3]]
]

escapeSpans::usage = "escapeSpans[s] gives {{first, last}, character} for each character escape of s outside its strings and comments."
escapeSpans[s_String] := With[{typed = typedEscapeSpans[s]}, If[ListQ[typed], typed, scannedEscapeSpans[s]]]

(* the same, a character at a time: the scan the typed scan, typedEscapeSpans, reads as it is, for a
	kernel without it *)
scannedEscapeSpans::usage = "scannedEscapeSpans[s] gives escapeSpans[s] by a scan a character at a time."
scannedEscapeSpans[s_String] := Reverse @ linkedItems @ Last @ NestWhile[escapeStep, {ToCharacterCode[s], 1, 0, {}}, scanOnQ]

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

End[]

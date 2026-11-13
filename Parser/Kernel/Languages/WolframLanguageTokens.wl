(* ::Package:: *)

(* :Title: WolframLanguageTokens.wl - the tokens of Wolfram Language text, every character in one *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	WolframLanguageTokens gives the tokens of a source in order, each character of the source in
	exactly one of them: the tokens the reader's lexer reads, fastLex of WolframLanguageFast.wl,
	and between them the whitespace, the newlines and the comments it passes over. Text that is
	no Wolfram Language gives tokens too: where the lexer stops, the characters no token has are
	a token of the kind "Error" and the lexer reads on after them, and a string, a comment or
	linear syntax the source does not close is a token to the end of the source, marked
	incomplete.

	The lexer is called as it is. What this file adds in typed code, $fastTokenRowsDeclaration,
	$fastTokenGroupsDeclaration and $fastTokenEscapesDeclaration, are FunctionDeclarations a
	compiler of typed code takes as they are, as the lexer's are.
*)

BeginPackage["Wolfram`Parser`Languages`WolframLanguage`", {"Wolfram`Parser`"}]

WolframLanguageTokens::usage = "WolframLanguageTokens[\"code\"] gives the tokens of the Wolfram Language text code in order, each \
character of code in exactly one of them, whitespace, newlines and comments tokens too: a list of associations with the keys \"Kind\", \
\"Text\", \"Start\", \"End\", \"Line\", \"Column\" and \"Depth\", and \"Operator\", \"Partner\", \"Context\", \"LongName\" and \
\"Incomplete\" where they apply. The kinds are \"Symbol\", \"PatternName\", \"Blank\", \"Number\", \"String\", \"StringEscape\", \"Slot\", \
\"Out\", \"Operator\", \"Open\", \"Close\", \"Comment\", \"Whitespace\", \"Newline\", \"LinearSyntax\", \"FreeForm\" and \"Error\". Text that \
is no Wolfram Language gives tokens too, never a failure.
WolframLanguageTokens[\"code\", \"Rows\"] gives the tokens as a packed array of integers, a row {kind, start, end, line, column, depth, \
partner, operator, flags} for each.
WolframLanguageTokens[\"code\", \"Data\"] gives the rows with what their integers stand for: an association with the keys \"Columns\", \
\"Kinds\", \"Operators\", \"Flags\" and \"Rows\"."

Begin["`Private`"]

(* ::Section:: *)
(*Kinds*)

(* the kinds of token, each by its position: a row's first integer *)
$tokenKinds = {"Symbol", "PatternName", "Blank", "Number", "String", "StringEscape", "Slot", "Out", "Operator", "Open", "Close", "Comment",
	"Whitespace", "Newline", "LinearSyntax", "FreeForm", "Error"
}

(* what the integers of a row are *)
$tokenColumns = {"Kind", "Start", "End", "Line", "Column", "Depth", "Partner", "Operator", "Flags"}

(* the flags of a row, each a bit of its last integer *)
$tokenFlags = <|"Incomplete" -> 1, "Context" -> 2, "LongName" -> 4|>

(* The operators by the lexer's number of each, then the comma and the brackets the lexer has as
	kinds of token: an operator's ASCII spelling, or its long name where it has none. A row's
	operator is a position here. *)
$tokenComma := $tokenComma = $fastNewlineId + 1
$tokenOperators := $tokenOperators = Join[
	Map[If[MemberQ[$longNameOnlyOperators, #], "\\[" <> # <> "]", #] &, $fastOperators],
	Map["\\[" <> # <> "]" &, $fastLongNames],
	{" ", "\\[InvisibleComma]", "\\[Not]", "\n"},
	{",", "(", ")", "[", "]", "{", "}"}
]

(* The brackets, by operator + 1: the kind of group an operator opens, minus it where it closes
	one, 0 for an operator that is no bracket. 1 parentheses, 2 square brackets, 3 braces, 4 an
	association's, then the long-name brackets as LongNameOperators.wl lists them. *)
$tokenGroupTypes := $tokenGroupTypes = 4 + Length[$longNameTable["Groups"]]
$tokenGroups := $tokenGroups = Developer`ToPackedArray @ ReplacePart[
	ConstantArray[0, $tokenComma + 8],
	Join[
		Catenate @ MapIndexed[
			Function[{group, index}, DeleteCases[
				{fastLongOp[group[[1]]] + 1 -> 4 + First[index], fastLongOp[group[[2]]] + 1 -> -4 - First[index]},
				1 -> _
			]],
			$longNameTable["Groups"]
		],
		{$fastOpenAssociation + 1 -> 4, $fastCloseAssociation + 1 -> -4},
		Thread[$tokenComma + {2, 3, 4, 5, 6, 7} -> {1, -1, 2, -2, 3, -3}]
	]
]

(* what the typed rows take after the tables: the whitespace and the newline of a long name, ::,
	the comma, the invisible comma, the primes, the number before the brackets', <| and |>, and 1
	where a string's escapes are tokens *)
tokenParameters[escapes_] := Developer`ToPackedArray[{$fastSpaceId, $fastNewlineId, $fastColonColon, $tokenComma, $fastInvisibleCommaId, fastOp["'"],
	$tokenComma, $fastOpenAssociation, $fastCloseAssociation, If[TrueQ[escapes], 1, 0]
}]

(* ::Section:: *)
(*The rows of the tokens*)

(* The rows of a source's tokens, typed code over packed integers: the codes of the source and three
	zeros after them, the class of each code, the lexer's tokens of the source as lexerTokens gives
	them, {count, then five integers for each: its kind, its operator, its first character, the
	character after its last, and 2 where the source ends before it closes}, a kind of -1 the
	characters no token has, the table of long names, the brackets by operator and the parameters
	-> six integers for each row: its kind as $tokenKinds numbers it, its first character, the
	character after its last, its operator, its flags and the group it opens, or minus the one it
	closes.

	The characters between two of the lexer's tokens are rows too: a run of spaces and tabs, the
	long names that are whitespace among them, one row; each line break one, a return and a newline
	together; each comment one, nested ones in it, to the end of the source where it is not closed.
	A token x_h is three rows, the name, the blank and the head, and a string is one row, or a row
	for each escape in it and for the text between them. A name or a blank that touches a :: before
	it is the tag of a message, a string. Each character is in exactly one row. *)
$fastTokenRowsDeclaration = FunctionDeclaration[fastTokenRows,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]
	} -> "PackedArray"::["MachineInteger", 1]
	] @
	Function[{trCodes, trClasses, trTokens, trLongOps, trGroups, trParams},
		Native`UncheckedBlock[Module[{n = Length[trCodes] - 3, count = trTokens[[1]], out, r = 0, t = 1, at = 1, to = 0, kind = 0, op = 0, a = 0, b = 0,
				incomplete = 0, c = 0, d = 0, cl = 0, j = 0, m = 0, q = 0, e = 0, ln = 0, g = 0, base = 0, tb = 0, colon = 0, scanning = 0, width = 0,
				octal = 0, piece = 0, tick = 0, long = 0, ek = 0, ea = 0, eo = 0, ef = 0, eg = 0,
				spSpace = trParams[[1]], spNewline = trParams[[2]], colonColon = trParams[[3]], comma = trParams[[4]], invisibleComma = trParams[[5]],
				primes = trParams[[6]], bracket = trParams[[7]], spOpen = trParams[[8]], spClose = trParams[[9]], escapes = trParams[[10]]
		},
			out = Native`UncheckedArray[0, 6 n + 6];
			While[ t <= count + 1,
				tb = 5 t - 4;
				to = If[t <= count, trTokens[[tb + 3]], n + 1];
				(* the whitespace, the newlines and the comments before the token *)
				While[ at < to,
					c = trCodes[[at]]; cl = If[c > 65535, 5, trClasses[[c + 1]]]; ln = 0;
					If[c == 92, ln = lexLongName[trCodes, trLongOps, at, n]];
					ek = 17; ef = 0; j = at + 1;
					Which[
						cl == 4,
							ek = 14; If[c == 13 && j < to && trCodes[[j]] == 10, j++],
						ln > 0 && Mod[ln, 8192] - 1 == spNewline,
							ek = 14; ef = 4; j = Quotient[ln, 8192],
						cl == 3 || (ln > 0 && Mod[ln, 8192] - 1 == spSpace),
							ek = 13;
							If[cl != 3, ef = 4; j = Quotient[ln, 8192]];
							scanning = 1;
							While[ scanning == 1 && j < to,
								d = trCodes[[j]]; cl = If[d > 65535, 5, trClasses[[d + 1]]];
								Which[
									cl == 3,
										j++,
									d == 92,
										ln = lexLongName[trCodes, trLongOps, j, n];
										If[ln > 0 && Mod[ln, 8192] - 1 == spSpace, ef = 4; j = Quotient[ln, 8192], scanning = 0],
									True,
										scanning = 0
								]
							],
						c == 40 && j < to && trCodes[[j]] == 42,
							ek = 12; q = lexComment[trCodes, at, n]; j = Quotient[q, 2];
							If[Mod[q, 2] == 1 || j > to, ef = 1; j = to],
						True,
							ek = 17
					];
					If[j > to, j = to];
					base = 6 r;
					out[[base + 1]] = ek; out[[base + 2]] = at; out[[base + 3]] = j; out[[base + 4]] = 0; out[[base + 5]] = ef; out[[base + 6]] = 0;
					r++; colon = 0; at = j
				];
				If[ t <= count,
					kind = trTokens[[tb + 1]]; op = trTokens[[tb + 2]]; a = trTokens[[tb + 3]]; b = trTokens[[tb + 4]];
					incomplete = If[trTokens[[tb + 5]] == 2, 1, 0];
					If[b > n + 1, b = n + 1];
					If[ b > a,
						ek = 17; ea = a; eo = 0; ef = 0; eg = 0;
						Which[
							(* the tag of a message *)
							(kind == 1 || kind == 2) && colon == 1,
								ek = 5,
							(* a name, or a name, a blank and a head *)
							kind == 1 || kind == 2,
								tick = 0; long = 0; j = a;
								While[j < b && trCodes[[j]] != 95, If[trCodes[[j]] == 96, tick = 1]; If[trCodes[[j]] == 92, long = 1]; j++];
								ek = 1; ef = 2 tick + 4 long;
								If[ j < b,
									If[ j > a,
										base = 6 r;
										out[[base + 1]] = 2; out[[base + 2]] = a; out[[base + 3]] = j; out[[base + 4]] = 0; out[[base + 5]] = ef; out[[base + 6]] = 0;
										r++
									];
									m = j;
									While[m < b && trCodes[[m]] == 95, m++];
									If[m < b && trCodes[[m]] == 46, m++];
									ek = 3; ea = j; ef = 0;
									If[ m < b,
										base = 6 r;
										out[[base + 1]] = 3; out[[base + 2]] = j; out[[base + 3]] = m; out[[base + 4]] = 0; out[[base + 5]] = 0; out[[base + 6]] = 0;
										r++;
										tick = 0; long = 0; q = m;
										While[q < b, If[trCodes[[q]] == 96, tick = 1]; If[trCodes[[q]] == 92, long = 1]; q++];
										ek = 1; ea = m; ef = 2 tick + 4 long
									]
								],
							kind == 3 || kind == 4,
								ek = 4,
							(* a string, a row for each escape and for the text between them *)
							kind == 5 && escapes == 1,
								ek = 5; piece = a; j = a + 1;
								While[ j < b,
									If[ trCodes[[j]] == 92,
										c = If[j + 1 < b, trCodes[[j + 1]], 0];
										e = If[j + 1 < b, j + 2, j + 1];
										octal = If[48 <= c <= 55, 1, 0];
										width = Which[c == 58, 4, c == 46, 2, c == 124, 6, octal == 1, 2, True, 0];
										Which[
											c == 91,
												q = j + 2;
												While[q < b && ((48 <= trCodes[[q]] <= 57) || (65 <= trCodes[[q]] <= 90) || (97 <= trCodes[[q]] <= 122)), q++];
												If[q > j + 2 && q < b && trCodes[[q]] == 93, e = q + 1],
											width > 0 && j + 1 + width < b,
												q = j + 2; m = 0;
												While[ q <= j + 1 + width,
													d = trCodes[[q]];
													If[ octal == 1,
														If[48 <= d <= 55, m++],
														If[(48 <= d <= 57) || (65 <= d <= 70) || (97 <= d <= 102), m++]
													];
													q++
												];
												If[m == width, e = j + 2 + width],
											True,
												e = e
										];
										If[ j > piece,
											base = 6 r;
											out[[base + 1]] = 5; out[[base + 2]] = piece; out[[base + 3]] = j; out[[base + 4]] = 0; out[[base + 5]] = 0; out[[base + 6]] = 0;
											r++
										];
										If[ e >= b,
											ek = 6; ea = j; piece = b; j = b,
											base = 6 r;
											out[[base + 1]] = 6; out[[base + 2]] = j; out[[base + 3]] = e; out[[base + 4]] = 0; out[[base + 5]] = 0; out[[base + 6]] = 0;
											r++; piece = e; j = e
										],
										j++
									]
								];
								If[ek == 5, ea = piece];
								ef = incomplete,
							kind == 5 || kind == 8 || kind == 22,
								ek = 5; ef = incomplete,
							kind == 6,
								ek = 7; ef = incomplete,
							kind == 7,
								ek = 8,
							kind == 9,
								g = trGroups[[op + 1]];
								ek = If[g > 0, 10, If[g < 0, 11, 9]]; eo = op; eg = g; ef = If[trCodes[[a]] == 92, 4, 0],
							kind >= 10 && kind <= 15,
								g = Quotient[kind - 8, 2];
								ek = If[Mod[kind, 2] == 0, 10, 11]; eo = bracket + kind - 9; eg = If[Mod[kind, 2] == 0, g, -g],
							kind == 16,
								ek = 10; eo = spOpen; eg = 4; ef = If[trCodes[[a]] == 92, 4, 0],
							kind == 17,
								ek = 11; eo = spClose; eg = -4; ef = If[trCodes[[a]] == 92, 4, 0],
							kind == 18,
								ek = 9; eo = If[trCodes[[a]] == 44, comma, invisibleComma]; ef = If[trCodes[[a]] == 92, 4, 0],
							kind == 19,
								ek = 9; eo = primes,
							kind == 20,
								ek = 15; ef = incomplete,
							kind == 21,
								ek = 16; ef = incomplete,
							True,
								ek = 17
						];
						base = 6 r;
						out[[base + 1]] = ek; out[[base + 2]] = ea; out[[base + 3]] = b; out[[base + 4]] = eo; out[[base + 5]] = ef; out[[base + 6]] = eg;
						r++;
						colon = If[kind == 9 && op == colonColon, 1, 0];
						at = b
					]
				];
				t++
			];
			Take[out, 6 r]
		]]
	]
]

(* the typed rows run here, fixed at their first use *)
fastTokenRowsFunction := fastTokenRowsFunction = typedFunction[fastTokenRows, $fastTokenRowsDeclaration, {$lexLongNameDeclaration, $lexCommentDeclaration}]

(* The brackets of a source's rows, typed code: for each row the group it opens, or minus the one it
	closes, 0 for a row that is no bracket, and the number of kinds of group -> {the depth of each
	row, then the partner of each}. A row's depth is the number of groups open around it, an
	opener's and a closer's the depth of what they hold; a partner is the row that closes an opener
	or opens a closer, 0 for a bracket with none. A closer takes the nearest opener of its kind
	that is open, and the openers after that one stay with no partner; a closer with no opener of
	its kind open has none. The count of the openers open of each kind keeps the scan linear. *)
$fastTokenGroupsDeclaration = FunctionDeclaration[fastTokenGroups,
	Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger"} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{tgGroups, tgTypes},
		Native`UncheckedBlock[Module[{r = Length[tgGroups], out, stack, open, depth = 0, i = 1, g = 0, q = 0},
			out = Native`UncheckedArray[0, 2 r];
			stack = Native`UncheckedArray[0, r + 1];
			open = Native`UncheckedArray[0, tgTypes + 1];
			q = 1;
			While[q <= tgTypes + 1, open[[q]] = 0; q++];
			While[ i <= r,
				g = tgGroups[[i]];
				out[[r + i]] = 0;
				Which[
					g > 0,
						depth++; stack[[depth]] = i; open[[g]] = open[[g]] + 1; out[[i]] = depth,
					g < 0 && open[[-g]] > 0,
						While[ tgGroups[[stack[[depth]]]] != -g,
							open[[tgGroups[[stack[[depth]]]]]] = open[[tgGroups[[stack[[depth]]]]]] - 1;
							depth--
						];
						out[[i]] = depth; out[[r + i]] = stack[[depth]]; out[[r + stack[[depth]]]] = i;
						open[[-g]] = open[[-g]] - 1;
						depth--,
					True,
						out[[i]] = depth
				];
				i++
			];
			out
		]]
	]
]

(* the typed brackets run here, fixed at their first use *)
fastTokenGroupsFunction := fastTokenGroupsFunction = typedFunction[fastTokenGroups, $fastTokenGroupsDeclaration]

(* The character escapes of a source outside its strings and comments, as escapeSpans reads them,
	typed code over its codes: {count, then for each its first character, its last and the code of
	the character its hexadecimal digits name}. A \: has four digits, a \. two and a \| six, and
	the code they name is at most 1114111. *)
$fastTokenEscapesDeclaration = FunctionDeclaration[fastTokenEscapes,
	Typed[{"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{teCodes},
		Native`UncheckedBlock[Module[{n = Length[teCodes], out, count = 0, at = 1, mode = 0, c = 0, d = 0, width = 0, q = 0, value = 0, ok = 0},
			out = Native`UncheckedArray[0, 3 Quotient[n, 4] + 4];
			While[ at <= n,
				c = teCodes[[at]];
				Which[
					mode > 0,
						Which[
							c == 40 && at < n && teCodes[[at + 1]] == 42, mode++; at += 2,
							c == 42 && at < n && teCodes[[at + 1]] == 41, mode--; at += 2,
							c == 92 && at < n && teCodes[[at + 1]] == 40, at += 2,
							True, at++
						],
					mode < 0,
						Which[c == 92, at += 2, c == 34, mode = 0; at++, True, at++],
					c == 34,
						mode = -1; at++,
					c == 40 && at < n && teCodes[[at + 1]] == 42,
						mode = 1; at += 2,
					c == 92,
						d = If[at < n, teCodes[[at + 1]], 0];
						width = Which[d == 58, 4, d == 46, 2, d == 124, 6, True, 0];
						ok = 0;
						If[ width > 0 && at + 1 + width <= n,
							value = 0; ok = 1; q = at + 2;
							While[ q <= at + 1 + width,
								d = teCodes[[q]];
								Which[
									48 <= d <= 57, value = 16 value + d - 48,
									65 <= d <= 70, value = 16 value + d - 55,
									97 <= d <= 102, value = 16 value + d - 87,
									True, ok = 0
								];
								q++
							];
							If[value > 1114111, ok = 0]
						];
						If[ ok == 1,
							out[[3 count + 2]] = at; out[[3 count + 3]] = at + 1 + width; out[[3 count + 4]] = value;
							count++; at = at + 2 + width,
							at += 2
						],
					True,
						at++
				]
			];
			out[[1]] = count;
			Take[out, 3 count + 1]
		]]
	]
]

(* the typed escapes run here, fixed at their first use *)
fastTokenEscapesFunction := fastTokenEscapesFunction = typedFunction[fastTokenEscapes, $fastTokenEscapesDeclaration]

(* ::Section:: *)
(*The lexer's tokens of any text*)

(* The lexer stops at the first character no token has. The tokens of a text that is no Wolfram
	Language are those it reads before it stops, the characters it stops at as a token of kind -1,
	and those it reads from the character after them on, and so on to the end. The text read again
	after a stop is a window of it, so that a text of many stops is not copied whole at each: a
	window half the one before, at least $tokenWindow characters, and twice the one before after a
	window read with no stop. Of a window that ends before the text does, the tokens that end
	$tokenMargin characters before its end are kept, those the lexer reads the same with the rest
	of the text after them, and the next window begins after them. *)
$tokenWindow = 512
$tokenMargin = 64

lexerTokens::usage = "lexerTokens[codes] gives the lexer's tokens of the codes of any text, packed: {count, then five integers for \
each: its kind, its operator, its first character, the character after its last, and 2 where the text ends before it closes}, a kind of -1 \
the characters no token has."
lexerTokens[codes_List] := With[
	{parts = Reverse @ linkedItems @ Last @ NestWhile[lexedWindow[codes, #] &, {1, Length[codes], {}}, First[#] <= Length[codes] &]},
	Developer`ToPackedArray @ Prepend[Flatten[parts], Total[Length /@ parts]]
]

lexedWindow::usage = "lexedWindow[codes, {from, width, parts}] gives the state after the lexer reads the window of the codes of width \
characters from from on: where the next window begins, its width, and the tokens read, a linked list of their matrices."
lexedWindow[codes_List, {from_Integer, width_Integer, parts_List}] := With[{to = Min[Length[codes], from + width - 1]},
	With[{lexed = lexedCodes[paddedCodes[If[from === 1 && to === Length[codes], codes, Take[codes, {from, to}]]]]},
		windowTokens[codes, from, width, to, Partition[Drop[lexed, 2], 5], lexerStatus[lexed], parts]
	]
]

windowTokens::usage = "windowTokens[codes, from, width, to, tokens, status, parts] gives the state after the window of the codes from \
from to to, of the lexer's tokens and status."
windowTokens[codes_List, from_Integer, width_Integer, to_Integer, tokens_List, status_Integer, parts_List] := Which[
	status === 1 && (to === Length[codes] || Max[Last[tokens][[{3, 4}]]] <= to - from + 1 - $tokenMargin),
		stoppedWindow[codes, from, width, Most[tokens], stoppedToken[codes, from, to, Last[tokens]], parts],
	to === Length[codes],
		{Length[codes] + 1, width, {tokensFrom[endedTokens[tokens, status, to - from + 1], from], parts}},
	True,
		cutWindow[from, width, Most[tokens], keptCount[Most[tokens], to - from + 1 - $tokenMargin], parts]
]

stoppedToken::usage = "stoppedToken[codes, from, to, token] gives the token the lexer stops at in the window of the codes from from to \
to: the file or the free-form input it reads to there, else the characters no token has, of kind -1."
stoppedToken[codes_List, from_Integer, to_Integer, {kind_Integer, operator_Integer, start_Integer, end_Integer, _Integer}] := Which[
	end > start && kind === $tkFile,
		{kind, operator, start, Min[end, to - from + 2], 0},
	end > start && kind === $tkFreeform,
		{kind, operator, start, Min[end, to - from + 2], 2},
	end > start,
		{-1, 0, start, Min[end, to - from + 2], 0},
	True,
		{-1, 0, start, errorEnd[codes, from + start - 1] - from + 1, 0}
]

stoppedWindow::usage = "stoppedWindow[codes, from, width, tokens, stopped, parts] gives the state after a window the lexer stops in: \
the tokens before the stop and the stopped one read, the next window after it."
stoppedWindow[_List, from_Integer, width_Integer, tokens_List, stopped_List, parts_List] :=
	{from + stopped[[4]] - 1, Max[$tokenWindow, Quotient[width, 2]], {tokensFrom[Append[tokens, stopped], from], parts}}

(* the tokens of a text the lexer reads to its end: all but the end's, the last one to the end of
	the text and marked where the text ends in it, a string, a slot, a file, linear syntax or
	free-form input not closed; a \ that ends the text is the characters no token has *)
endedTokens::usage = "endedTokens[tokens, status, length] gives the lexer's tokens of a text of length characters it reads to the end."
endedTokens[tokens_List, 3, length_Integer] := With[{last = Last[tokens]},
	Which[
		last[[1]] =!= $tkEnd,
			Append[Most[tokens], {last[[1]], last[[2]], last[[3]], length + 1, 2}],
		last[[4]] > last[[3]],
			Append[Most[tokens], {-1, 0, last[[3]], length + 1, 0}],
		True,
			Most[tokens]
	]
]
endedTokens[tokens_List, _Integer, _Integer] := Most[tokens]

keptCount::usage = "keptCount[tokens, limit] gives how many of the tokens of a window that ends before its text does are kept: those \
that end by the character at limit, but a ::, a <<, a >> or a >>> at their end, which the token after it is read by."
keptCount[{}, _Integer] := 0
keptCount[tokens_List, limit_Integer] := NestWhile[# - 1 &, Total[UnitStep[limit + 1 - tokens[[All, 4]]]], # > 0 && leadingOperatorQ[tokens[[#]]] &]

leadingOperatorQ::usage = "leadingOperatorQ[token] is True for a token that is a ::, a <<, a >> or a >>>."
leadingOperatorQ[{kind_Integer, operator_Integer, __}] := kind === $tkOperator && MemberQ[{$fastColonColon, $fastGet, $fastPut, $fastPutAppend}, operator]

cutWindow::usage = "cutWindow[from, width, tokens, count, parts] gives the state after a window that ends before its text does, count of \
its tokens kept: the next window after them, or the same one four times as wide where none is."
cutWindow[from_Integer, width_Integer, _List, 0, parts_List] := {from, 4 width, parts}
cutWindow[from_Integer, width_Integer, tokens_List, count_Integer, parts_List] :=
	{from + tokens[[count, 4]] - 1, 2 width, {tokensFrom[Take[tokens, count], from], parts}}

tokensFrom::usage = "tokensFrom[tokens, from] gives the tokens of a window that begins at from, their characters numbered in the text."
tokensFrom[{}, _Integer] := {}
tokensFrom[tokens_List, 1] := tokens
tokensFrom[tokens_List, from_Integer] := tokens + ConstantArray[{0, 0, from - 1, from - 1, 0}, Length[tokens]]

(* The characters no token has from at on, where the lexer stops: a name's letters, digits and
	context marks, as a name with a mark out of place is none; a \[ and the letters and digits after
	it, its ] too, a long name not closed or one no character has; a \ and the character after it;
	else one character. The characters after them that the lexer is sure to stop at again are with
	them, so that a run of them is one token and the lexer is not called at each. *)
errorEnd::usage = "errorEnd[codes, at] gives the character after the characters no token has from at on in the codes."
errorEnd[codes_List, at_Integer] := NestWhile[errorPieceEnd[codes, #] &, errorPieceEnd[codes, at], # <= Length[codes] && sureErrorQ[codes, #] &]

errorPieceEnd::usage = "errorPieceEnd[codes, at] gives the character after the name, the long name, the escape or the character at at \
that no token has."
errorPieceEnd[codes_List, at_Integer] := With[{n = Length[codes], c = codes[[at]]},
	Which[
		MemberQ[{1, 5}, codeClass[c]],
			NestWhile[# + 1 &, at + 1, # <= n && MemberQ[{1, 2, 5}, codeClass[codes[[#]]]] &],
		c === 92 && at < n && codes[[at + 1]] === 91,
			With[{end = longNameLettersEnd[codes, at]}, If[end <= n && codes[[end]] === 93, end + 1, end]],
		c === 92 && at < n && !MemberQ[{3, 4}, codeClass[codes[[at + 1]]]],
			at + 2,
		True,
			at + 1
	]
]

longNameLettersEnd::usage = "longNameLettersEnd[codes, at] gives the character after the letters and digits of the \\[ at at."
longNameLettersEnd[codes_List, at_Integer] := NestWhile[# + 1 &, at + 2, # <= Length[codes] && KeyExistsQ[$alphanumericCodes, codes[[#]]] &]

(* the lexer stops at a \ that begins no long name the language has and no linear syntax, and at a
	character of no class that is no operator and begins no token *)
sureErrorQ::usage = "sureErrorQ[codes, at] is True where the lexer is sure to stop at the character at at of the codes."
sureErrorQ[codes_List, at_Integer] := With[{n = Length[codes], c = codes[[at]]},
	Which[
		c === 92 && at < n && codes[[at + 1]] === 91,
			With[{end = longNameLettersEnd[codes, at]},
				!(end <= n && codes[[end]] === 93 && KeyExistsQ[$fastLongNameOps, FromCharacterCode[Take[codes, {at + 2, end - 1}]]])
			],
		c === 92,
			!(at < n && MemberQ[{40, 33}, codes[[at + 1]]]),
		True,
			c <= 65535 && codeClass[c] === 0 && $fastOp1[[c + 1]] === 0 && !MemberQ[$tokenStartCodes, c]
	]
]

(* the characters of no class that begin a token and are no operator: " # % ' ( ) , . [ ] _ { } *)
$tokenStartCodes = {34, 35, 37, 39, 40, 41, 44, 46, 91, 93, 95, 123, 125}

codeClass::usage = "codeClass[code] gives the class of a character code, as $fastClasses has it."
codeClass[code_Integer] := If[code > 65535, 5, $fastClasses[[code + 1]]]

(* ::Section:: *)
(*The source as the lexer reads it*)

(* The codes of a source as the readers read it, readSource's text: without its line continuations
	and with each character escape outside a string and a comment its character; the positions in
	the source of the codes kept, None where they are all of it; and the spans of the line
	continuations. The escapes are read by the typed scan. *)
tokenSource::usage = "tokenSource[s, codes] gives {the codes of the source s as the lexer reads it, the positions in s of those codes or \
None, the spans of its line continuations}."
tokenSource[s_String, codes_List] := With[
	{spans = lineContinuations[s], escapes = If[StringContainsQ[s, "\\:" | "\\." | "\\|"], Partition[Rest[fastTokenEscapesFunction[codes]], 3], {}]},
	If[spans === {} && escapes === {}, {codes, None, {}}, editedSource[codes, spans, escapes]]
]

editedSource::usage = "editedSource[codes, spans, escapes] gives tokenSource's answer for codes with the line continuations spans and the \
character escapes escapes, {first, last, code} each."
editedSource[codes_List, spans_List, escapes_List] := With[
	{n = Length[codes], dropped = Join[spans, Map[{#[[1]] + 1, #[[2]]} &, escapes]]},
	{kept = Pick[
		Range[n],
		Most @ Accumulate @ Normal[SparseArray[Thread[dropped[[All, 1]] -> 1], n + 1] - SparseArray[Thread[dropped[[All, 2]] + 1 -> 1], n + 1]],
		0
	]},
	{Developer`ToPackedArray[ReplacePart[codes, Thread[escapes[[All, 1]] -> escapes[[All, 3]]]][[kept]]], kept, spans}
]

(* ::Section:: *)
(*The rows of a source*)

(* The rows of a source, {kind, start, end, line, column, depth, partner, operator, flags} each, a
	packed matrix: the typed rows of the source as the lexer reads it, each placed in the source. A
	row begins where its first character does and ends before the next row begins, so that a line
	continuation or a character escape inside a token is in it; a line continuation at the edge of
	a token is a row of whitespace of its own. *)
tokenRows::usage = "tokenRows[s, escapes, utf16] gives the rows of the tokens of the source s, a string's escapes rows of their own \
where escapes is True, the positions counted in UTF-16 code units where utf16 is True."
tokenRows[s_String, escapes_, utf16_] := With[{codes = Developer`ToPackedArray[ToCharacterCode[s]]},
	If[codes === {}, {}, With[{read = tokenSource[s, codes]}, sourceRows[codes, placedRows[codes, readRows[First[read], escapes], read[[2]], Last[read]], utf16]]]
]

readRows::usage = "readRows[codes, escapes] gives the typed rows of the codes, six integers each: kind, first character, the character \
after the last, operator, flags and group."
readRows[{}, _] := {}
readRows[codes_List, escapes_] := Partition[
	fastTokenRowsFunction[paddedCodes[codes], $fastClasses, lexerTokens[codes], $fastLongOpTable, $tokenGroups, tokenParameters[escapes]],
	6
]

(* the rows {kind, start, operator, flags, group} in the source: each begins at its first character
	there, the first at the source's first *)
placedRows::usage = "placedRows[codes, rows, kept, spans] gives the rows {kind, start, operator, flags, group} of the source of the codes, \
from the typed rows of it as the lexer reads it, kept the positions of what it reads and spans the line continuations."
placedRows[codes_List, {}, _, _] := {{13, 1, 0, 0, 0}}
placedRows[_List, rows_List, None, _] := rows[[All, {1, 2, 4, 5, 6}]]
placedRows[codes_List, rows_List, kept_List, spans_List] := continuationRows[
	Transpose[{rows[[All, 1]], ReplacePart[kept[[rows[[All, 2]]]], 1 -> 1], rows[[All, 4]], rows[[All, 5]], rows[[All, 6]]}],
	spans,
	Length[codes]
]

(* a line continuation that begins a row, or ends one, that is no whitespace is a row of
	whitespace before it, or after it *)
continuationRows::usage = "continuationRows[rows, spans, length] gives the rows of a source of length characters, each of the line \
continuations spans at the edge of a row that is no whitespace a row of whitespace of its own."
continuationRows[rows_List, {}, _Integer] := rows
continuationRows[rows_List, spans_List, length_Integer] := With[
	{starts = rows[[All, 2]]},
	{ends = Append[Rest[starts], length + 1], at = Accumulate[Normal[SparseArray[Thread[starts -> 1], length + 1]]]},
	{edges = Select[
		Map[Function[span, With[{i = at[[First[span]]]}, {i, First[span] === starts[[i]], Last[span] + 1 === ends[[i]], span}]], spans],
		rows[[First[#], 1]] =!= 13 && (#[[2]] || #[[3]]) &
	]},
	If[ edges === {},
		rows,
		With[
			{before = Association[Cases[edges, {i_, True, _, span_} :> i -> span]], after = Association[Cases[edges, {i_, False, True, span_} :> i -> span]]},
			Developer`ToPackedArray @ Catenate @ MapIndexed[
				Function[{row, index}, With[{i = First[index]}, {
					If[KeyExistsQ[before, i], {13, row[[2]], 0, 0, 0}, Nothing],
					If[KeyExistsQ[before, i], ReplacePart[row, 2 -> Last[before[i]] + 1], row],
					If[KeyExistsQ[after, i], {13, First[after[i]], 0, 0, 0}, Nothing]
				}]],
				rows
			]
		]
	]
]

sourceRows::usage = "sourceRows[codes, rows, utf16] gives the rows {kind, start, end, line, column, depth, partner, operator, flags} of \
the source of the codes from its rows {kind, start, operator, flags, group}."
sourceRows[codes_List, rows_List, utf16_] := With[
	{starts = rows[[All, 2]], groups = fastTokenGroupsFunction[Developer`ToPackedArray[rows[[All, 5]]], $tokenGroupTypes]},
	{ends = Append[Rest[starts] - 1, Length[codes]], lines = linePositions[codes, starts]},
	{places = If[TrueQ[utf16], utf16Positions[codes, starts, ends, Last[lines]], {starts, ends, Last[lines]}]},
	Developer`ToPackedArray @ Transpose[{rows[[All, 1]], places[[1]], places[[2]], First[lines], places[[3]], Take[groups, Length[starts]],
		Drop[groups, Length[starts]], rows[[All, 3]], rows[[All, 4]]
	}]
]

(* A line ends at a newline, at a return and a newline together, and at a return alone, as an
	editor of text counts its lines. *)
linePositions::usage = "linePositions[codes, starts] gives {the line of each of the characters at starts in the codes, its column}, the \
first line 1 and a line's first character at column 1."
linePositions[codes_List, starts_List] := With[{breaks = lineBreaks[codes]},
	If[ Total[breaks] === 0,
		{ConstantArray[1, Length[starts]], starts},
		With[{lines = 1 + Prepend[Accumulate[breaks], 0][[starts]], lineStarts = Prepend[Pick[Range[Length[codes]], breaks, 1] + 1, 1]},
			{lines, starts - lineStarts[[lines]] + 1}
		]
	]
]

lineBreaks::usage = "lineBreaks[codes] gives 1 for each of the codes that ends a line and 0 for each that does not."
lineBreaks[codes_List] := With[{feeds = 1 - Unitize[codes - 10], returns = 1 - Unitize[codes - 13]},
	feeds + returns * (1 - Append[Rest[feeds], 0])
]

(* positions in UTF-16 code units: a character past 65535 is two of them, as a browser's string
	counts it *)
utf16Positions::usage = "utf16Positions[codes, starts, ends, columns] gives {starts, ends, columns} counted in UTF-16 code units."
utf16Positions[codes_List, starts_List, ends_List, columns_List] := With[{wide = UnitStep[codes - 65536]},
	If[ Total[wide] === 0,
		{starts, ends, columns},
		With[{before = Prepend[Accumulate[wide], 0]},
			{starts + before[[starts]], ends + before[[ends + 1]], columns + before[[starts]] - before[[starts - columns + 1]]}
		]
	]
]

(* ::Section:: *)
(*WolframLanguageTokens*)

Options[WolframLanguageTokens] = {"StringEscapes" -> False, "Offsets" -> "Characters"}

WolframLanguageTokens[s_String, opts : OptionsPattern[]] := WolframLanguageTokens[s, "Tokens", opts]
WolframLanguageTokens[s_String, "Rows", opts : OptionsPattern[]] := tokenRows[s, OptionValue["StringEscapes"], OptionValue["Offsets"] === "UTF16"]
WolframLanguageTokens[s_String, "Data", opts : OptionsPattern[]] := <|
	"Columns" -> $tokenColumns,
	"Kinds" -> $tokenKinds,
	"Operators" -> $tokenOperators,
	"Flags" -> $tokenFlags,
	"Rows" -> tokenRows[s, OptionValue["StringEscapes"], OptionValue["Offsets"] === "UTF16"]
|>
WolframLanguageTokens[s_String, "Tokens", opts : OptionsPattern[]] := With[{rows = tokenRows[s, OptionValue["StringEscapes"], False]},
	If[ rows === {},
		{},
		MapThread[
			tokenAssociation,
			{If[OptionValue["Offsets"] === "UTF16", tokenRows[s, OptionValue["StringEscapes"], True], rows], tokenRowTexts[s, rows]}
		]
	]
]

tokenRowTexts::usage = "tokenRowTexts[s, rows] gives the text of each of the rows of the source s, positions counted in characters."
tokenRowTexts[s_String, rows_List] := FromCharacterCode[TakeList[ToCharacterCode[s], rows[[All, 3]] - rows[[All, 2]] + 1]]

(* a token of a row and its text: the keys every token has, then those of its kind and of its
	flags *)
tokenAssociation::usage = "tokenAssociation[row, text] gives the token of a row and its text, an association."
tokenAssociation[{kind_Integer, start_Integer, end_Integer, line_Integer, column_Integer, depth_Integer, partner_Integer, operator_Integer, flags_Integer},
	text_String
] := Association[
	"Kind" -> $tokenKinds[[kind]], "Text" -> text, "Start" -> start, "End" -> end, "Line" -> line, "Column" -> column, "Depth" -> depth,
	tokenKindRules[kind, partner, operator, flags],
	tokenFlagRules[flags]
]

tokenKindRules::usage = "tokenKindRules[kind, partner, operator, flags] gives the rules of a token that its kind alone has."
tokenKindRules[1, _Integer, _Integer, flags_Integer] := {"Context" -> BitAnd[flags, 2] === 2}
tokenKindRules[9, _Integer, operator_Integer, _Integer] := {"Operator" -> $tokenOperators[[operator]]}
tokenKindRules[10 | 11, partner_Integer, operator_Integer, _Integer] := {"Operator" -> $tokenOperators[[operator]], "Partner" -> partner}
tokenKindRules[_Integer, _Integer, _Integer, _Integer] := {}

tokenFlagRules::usage = "tokenFlagRules[flags] gives the rules of a token's flags that are set: \"LongName\" and \"Incomplete\"."
tokenFlagRules[0 | 2] := {}
tokenFlagRules[flags_Integer] := {If[BitAnd[flags, 4] === 4, "LongName" -> True, Nothing], If[BitAnd[flags, 1] === 1, "Incomplete" -> True, Nothing]}

End[]

EndPackage[]

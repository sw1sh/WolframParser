(* ::Package:: *)

(* :Title: WolframLanguageChunks.wl - a huge source lexed and parsed a window at a time *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	The typed lexer and parser take room for the most a source can need, 5 integers a code for the
	tokens and 56 a token for the program and the frames: over 1 GB for a source of 12 MB. A source of
	more than 2^20 codes is lexed and parsed here a window at a time, so the room taken is a window's,
	and the tokens and the program given are the ones a read of the whole source gives.
	WolframLanguageFast.wl loads this file at the first such source. It begins its private context
	alone and names no package to need: the contexts it uses are loaded by then, in a kernel under
	their own names. *)

Begin["Wolfram`Parser`Languages`WolframLanguage`Private`"]

(* The codes a window of the lexer reads and the tokens a window of the parser reads, at first: a
	window with no place to end in doubles. *)
$chunkCodes = 262144;
$chunkTokens = 65536;

(* ::Section:: *)
(*The tokens*)

(* The lexer's tokens of the codes, padded, a window at a time. A window's tokens are the whole
	source's up to the last of them whose next two are whole in the window: the lexer reads a token
	from its first code and looks no further than the next. Of those, the tokens before the last one
	that begins a line are kept, and the next window begins right after them, at the spaces before
	that line, so that each token's newline before it is read again. A window whose tokens hold no
	such line doubles. The last window holds the end; where the lexer stops in it, the whole source
	is lexed at once, so the stop is the lexer's own. *)
chunkedLexed::usage = "chunkedLexed[padded] gives the lexer's tokens of the codes padded, as lexedCodes gives them, lexed a window of \
codes at a time. chunkedLexed[padded, width] reads windows of width codes at first."
chunkedLexed[padded_List] := chunkedLexed[padded, $chunkCodes]
chunkedLexed[padded_List, width_Integer] := Module[{n = Length[padded] - 3, from = 1, w = width, last, window, count, line, kept, pieces},
	pieces = Last[Reap[
		While[ from <= n,
			last = Min[n, from + w - 1];
			window = windowLexed[Join[padded[[from ;; last]], $threeZeros]];
			count = tokenCount[window];
			If[ last === n,
				If[lexerStatus[window] =!= 0, Return[windowLexed[padded], Module]];
				Sow[shiftedTokens[Drop[window, 2], from - 1]]; from = n + 1,
				line = SelectFirst[Range[count - 2, 2, -1], newlineBefore[window, #] === 1 &, None];
				If[ line === None, w = 2 w,
					kept = Take[window, {3, 2 + 5 (line - 1)}];
					Sow[shiftedTokens[kept, from - 1]];
					from = from + kept[[-2]] - 1; w = width
				]
			]
		]
	]];
	With[{tokens = Join @@ First[pieces]}, Developer`ToPackedArray[Join[{0, Length[tokens] / 5}, tokens]]]
]

(* tokens of a window whose first code is at shift + 1 of the source, their codes placed in it: a sum
	of packed arrays, the shift at the third and fourth integer of each token, which takes a time in
	proportion to the tokens in the kernel as in Wolfram 15 *)
shiftedTokens::usage = "shiftedTokens[tokens, shift] gives the tokens, five integers each, with their first code and the code after their \
last shifted by shift."
shiftedTokens[tokens_List, shift_Integer] := Developer`ToPackedArray[
	tokens + shift Developer`ToPackedArray[Flatten[ConstantArray[{0, 0, 1, 1, 0}, Quotient[Length[tokens], 5]]]]
]

windowLexed::usage = "windowLexed[padded] gives the typed lexer's tokens of the codes padded, read at once."
windowLexed[padded_List] := fastLexFunction[padded, $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial]

(* ::Section:: *)
(*The program*)

(* The parser's program of the tokens, a window of them at a time. A window begins at a statement
	and ends before a token that begins a line, as the source would end there; its statements but the
	last are the whole source's, as the parser reads a statement from its first token and ends it at
	the next one's line, and the next window begins at the last one. Its instructions are the whole
	source's, but for the tokens a leaf and a statement's end name, which are shifted to the source's:
	no other instruction names a token or an instruction, and the codes it names are the source's
	already. A window that ends inside a statement, as a line of a definition over many lines begins
	one, stops in that statement, and is read again up to its first token: the statements before it
	end where they end in the source. A window that stops in its first statement, or holds one
	statement, doubles; the last holds the end, and where
	it stops the whole source is parsed at once, so the program of a source that does not read is the
	parser's own. *)
chunkedProgram::usage = "chunkedProgram[lexed, padded] gives the parser's program of the tokens lexed of the codes padded, as \
fastParseTokens gives it, parsed a window of tokens at a time. chunkedProgram[lexed, padded, width] reads windows of width tokens at first."
chunkedProgram[lexed_List, padded_List] := chunkedProgram[lexed, padded, $chunkTokens]
chunkedProgram[lexed_List, padded_List, width_Integer] := Module[
	{count = tokenCount[lexed], from = 1, w = width, upto, window, program, instructions, ends, pieces},
	pieces = Last[Reap[
		While[ from <= count,
			If[ count - from < w,
				program = windowProgram[Join[{0, count - from + 1}, Take[lexed, {3 + 5 (from - 1), 2 + 5 count}]], padded];
				If[parseStatus[program] =!= 0, Return[windowProgram[lexed, padded], Module]];
				Sow[shiftedInstructions[programInstructions[program], from - 1]]; from = count + 1,
				upto = SelectFirst[Range[from + w, from + 1, -1], newlineBefore[lexed, #] === 1 &, None];
				If[ upto === None, w = 2 w,
					program = windowProgram[windowTokens[lexed, from, upto], padded];
					If[ parseStatus[program] === 1 && statementToken[program] > 1,
						program = windowProgram[windowTokens[lexed, from, from + statementToken[program] - 1], padded]
					];
					instructions = If[parseStatus[program] === 0, Partition[programInstructions[program], 3], {}];
					ends = Flatten[Position[instructions[[All, 1]], 25]];
					If[ Length[ends] < 2, w = 2 w,
						Sow[shiftedInstructions[Flatten[Take[instructions, ends[[-2]]]], from - 1]];
						from = from + instructions[[ends[[-2]], 3]] - 1; w = width
					]
				]
			]
		]
	]];
	With[{all = Join @@ First[pieces]}, Developer`ToPackedArray[Join[{0, Length[all] / 3}, all]]]
]

(* the tokens from the token from to the one before upto, and an end at upto's first code *)
windowTokens::usage = "windowTokens[lexed, from, upto] gives the tokens lexed from the token from to the one before upto, ended at the \
first code of upto, as the source would end there."
windowTokens[lexed_List, from_Integer, upto_Integer] := Developer`ToPackedArray @ Join[
	{0, upto - from + 1},
	Take[lexed, {3 + 5 (from - 1), 2 + 5 (upto - 1)}],
	{$tkEnd, 0, tokenStart[lexed, upto], tokenStart[lexed, upto], newlineBefore[lexed, upto]}
]

(* a leaf's token and a statement's first token and the next one's, shifted by shift tokens: a sum of
	packed arrays, the shift where the operation is a leaf's (1) or a statement's end (25) *)
shiftedInstructions::usage = "shiftedInstructions[instructions, shift] gives the instructions, three integers each, with the tokens a leaf \
and a statement's end name shifted by shift."
shiftedInstructions[instructions_List, shift_Integer] := With[{ops = Developer`ToPackedArray[instructions[[1 ;; -1 ;; 3]]]},
	With[{leaf = 1 - Unitize[ops - 1], end = 1 - Unitize[ops - 25]},
		Developer`ToPackedArray[instructions + shift Developer`ToPackedArray[Flatten[Transpose[{0 ops, end, leaf + end}]]]]
	]
]

windowProgram::usage = "windowProgram[lexed, padded] gives the typed parser's program of the tokens lexed of the codes padded, read at once."
windowProgram[lexed_List, padded_List] := fastParseFunction[lexed, fastLedIndices[lexed], $fastSpecTable, $fastPrefixArray, $fastGroupArray,
	$fastIntegralArray, $fastSpecialArray, $fastHeadCodeArray, $fastKeyCodeArray, padded, $fastClasses
]

End[]

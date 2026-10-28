(* ::Package:: *)

(* :Title: WolframLanguageFast.wl - WolframLanguageHeld by typed code over tokens *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	The source WolframLanguageHeld reads, read as its grammar reads it, in
	three passes: the characters into tokens, one loop over their codes;
	the tokens into a postfix program, by precedence climbing over the
	levels of the grammar's operator table; and the program into the held
	values, each built by the held algebra's own builders. Source that is
	no Wolfram Language fails where the kernel's reader stops, and source
	this reader does not take the grammar reads instead.

	The lexer and the parser are typed code over packed integers,
	$fastLexDeclaration and $fastParseDeclaration, FunctionDeclarations
	that a compiler of typed code takes as they are; Wolfram 15 runs them
	compiled by Compile at their first use.
*)

BeginPackage["Wolfram`Parser`Languages`WolframLanguage`", {"Wolfram`Parser`"}]

Begin["`Private`"]

(* ::Section:: *)
(*Characters*)

(* the class of each character code: 1 a letter, $ or ` that begins a name,
	2 a digit, 3 a space, tab or form feed, or the character of a long name
	that is whitespace, 4 a newline, a return or the character of a long
	name that is a newline, 5 a character past ASCII that a name holds, 0
	any other. The table is read from WolframLanguageClasses.wl beside this
	file, its runs {class, length} from code 0 up as dev/freeze-classes.wls
	records them on Wolfram 15, so that every kernel lexes by Wolfram 15's own
	WhitespaceCharacter; it is computed where the file does not read as them. The file is read by
	Get alone, which a kernel that carries it in its units answers without the disk. *)
$fastClasses := $fastClasses = With[{file = FileNameJoin[{$languagesDirectory, "WolframLanguageClasses.wl"}]},
	Replace[Get[file], {
		runs : {{_Integer, _Integer} ..} /; Total[runs[[All, 2]]] === 65536 :> Developer`ToPackedArray[Join @@ Apply[ConstantArray, runs, {1}]],
		_ :> fastClassesComputed[]}]]

(* the table computed: what dev/freeze-classes.wls records, as runs, on Wolfram 15 *)
fastClassesComputed[] := Module[{t = ConstantArray[0, 65536], high = Range[128, 65535]},
	t[[ToCharacterCode["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$`"] + 1]] = 1;
	t[[Range[48, 57] + 1]] = 2;
	t[[{32, 9, 12} + 1]] = 3;
	t[[{10, 13} + 1]] = 4;
	t[[high + 1]] = 5;
	t[[ToCharacterCode[StringJoin[Keys[$nonLetterCharacters]]] + 1]] = 0;
	t[[Pick[high, StringMatchQ[Characters[FromCharacterCode[high]], WhitespaceCharacter]] + 1]] = 0;
	t[[ToCharacterCode[StringJoin[Lookup[$longNameTable["Characters"], $longNameTable["Whitespace"], Nothing]]] + 1]] = 3;
	t[[ToCharacterCode[StringJoin[Lookup[$longNameTable["Characters"], $heldNewlineNames, Nothing]]] + 1]] = 4;
	t]

(* ::Section:: *)
(*Operators*)

(* every operator by its name in the grammar: its ASCII spelling, or the
	long name of one with none *)
$fastOperators = Join[$operatorSpellings, {"DirectedEdge", "UndirectedEdge", "Element"}]
$fastOperatorIds = AssociationThread[$fastOperators -> Range[Length[$fastOperators]]]
fastOp[name_String] := $fastOperatorIds[name]

(* the long names the held grammar reads that are no ASCII operator's, each
	an operator after those, read at their first use; the whitespace ones
	one more, the invisible comma, a comma, one after it, and the newline
	ones one after \[Not]'s *)
$fastLongNames := $fastLongNames = Complement[Keys[$nonLetterNames], Keys[$asciiLongNames], $longNameTable["Whitespace"], $heldNewlineNames, {"InvisibleComma"}]
$fastLongIds := $fastLongIds = AssociationThread[$fastLongNames -> Length[$fastOperators] + Range[Length[$fastLongNames]]]
$fastSpaceId := $fastSpaceId = Length[$fastOperators] + Length[$fastLongNames] + 1
$fastInvisibleCommaId := $fastInvisibleCommaId = $fastSpaceId + 1
(* \[Not] and its character, which ! is not after an operand *)
$fastNotId := $fastNotId = $fastSpaceId + 2
$fastNewlineId := $fastNewlineId = $fastSpaceId + 3
fastLongOp[name_String] := Which[
	KeyExistsQ[$fastLongIds, name], $fastLongIds[name],
	MemberQ[$longNameTable["Whitespace"], name], $fastSpaceId,
	MemberQ[$heldNewlineNames, name], $fastNewlineId,
	name === "InvisibleComma", $fastInvisibleCommaId,
	True, 0]

(* the operators of one, two and three ASCII characters, and of a character
	past ASCII, by their codes *)
$fastOp1 := $fastOp1 = Module[{t = ConstantArray[0, 65536]},
	Scan[(t[[First[ToCharacterCode[#]] + 1]] = fastOp[#]) &, Select[$operatorSpellings, StringLength[#] === 1 &]];
	KeyValueMap[Function[{op, spellings}, Scan[(t[[First[ToCharacterCode[#]] + 1]] = fastOp[op]) &, Select[spellings, StringLength[#] === 1 &]]],
		$longNameOperators];
	Scan[With[{c = Lookup[$longNameTable["Characters"], #, None]}, If[StringQ[c] && First[ToCharacterCode[c]] <= 65535,
		t[[First[ToCharacterCode[c]] + 1]] = fastLongOp[#]]] &, Append[$fastLongNames, "InvisibleComma"]];
	With[{c = $longNameTable["Characters"]["Not"]}, t[[First[ToCharacterCode[c]] + 1]] = $fastNotId];
	t]
$fastOp2 := $fastOp2 = Module[{t = ConstantArray[0, {128, 128}]},
	Scan[With[{c = ToCharacterCode[#]}, t[[c[[1]] + 1, c[[2]] + 1]] = fastOp[#]] &, Select[$operatorSpellings, StringLength[#] === 2 &]];
	t]
$fastOp3 = Association[Map[ToCharacterCode[#] -> fastOp[#] &, Select[$operatorSpellings, StringLength[#] === 3 &]]]
(* each long name of the language: -1 a letter, else its operator *)
$fastLongNameOps := $fastLongNameOps = Join[
	AssociationMap[If[KeyExistsQ[$nonLetterNames, #], fastLongOp[#], -1] &, Keys[$longNames]],
	Association[Catenate[KeyValueMap[Function[{op, spellings},
		Map[StringTake[#, {3, -2}] -> fastOp[op] &, Select[spellings, StringStartsQ[#, "\\["] &]]], $longNameOperators]]],
	<|"Not" -> $fastNotId|>]

(* the tables of the lexer, packed: the 2-character operators by the codes
	of both, each 4096 times 1 more where a 3-character operator begins with
	the two, {c1, c2, c3, operator} for each of 3, and the long names,
	{how many, where each begins, then each, by length and then by codes,
	its length, its codes and its operator, -1 for a letter} *)
$fastOp2Flat := $fastOp2Flat = Developer`ToPackedArray[Flatten[$fastOp2 + 4096 Module[{t = ConstantArray[0, {128, 128}]},
	Scan[(t[[#[[1]] + 1, #[[2]] + 1]] = 1) &, Keys[$fastOp3]]; t]]]
$fastOp3Table = Developer`ToPackedArray[Flatten[KeyValueMap[Append[#1, #2] &, $fastOp3]]]
$fastLongOpTable := $fastLongOpTable = With[
	{entries = Map[Join[{Length[#[[1]]]}, #[[1]], {#[[2]]}] &, SortBy[KeyValueMap[{ToCharacterCode[#1], #2} &, $fastLongNameOps], {Length[#[[1]]] &, First}]]},
	Developer`ToPackedArray[Join[{Length[entries]}, 1 + Length[entries] + Most[FoldList[Plus, 1, Length /@ entries]], Flatten[entries]]]]
$fastOpenAssociation = fastOp["<|"]; $fastCloseAssociation = fastOp["|>"]
$fastGet = fastOp["<<"]; $fastPut = fastOp[">>"]; $fastPutAppend = fastOp[">>>"]
$fastSpecial := $fastSpecial = Developer`ToPackedArray[{$fastOpenAssociation, $fastCloseAssociation, $fastGet, $fastPut, $fastPutAppend, fastOp["=."], fastOp["="],
	$fastSpaceId, $fastInvisibleCommaId, $fastNewlineId}]

(* ::Section:: *)
(*Tokens*)

(* token kinds *)
$tkEnd = 0; $tkName = 1; $tkBlank = 2; $tkInteger = 3; $tkReal = 4; $tkString = 5; $tkSlot = 6; $tkOut = 7; $tkFile = 8;
$tkOperator = 9; $tkOpenParen = 10; $tkCloseParen = 11; $tkOpenSquare = 12; $tkCloseSquare = 13; $tkOpenCurly = 14;
$tkCloseCurly = 15; $tkOpenAssociation = 16; $tkCloseAssociation = 17; $tkComma = 18; $tkPrimes = 19; $tkBoxes = 20; $tkFreeform = 21; $tkWord = 22

(* The lexer's tokens of a source are one packed array: {status, count, then five integers for each
	token: its kind, its operator, its first character, the character after its last, and 1 where a
	line break comes before it, else 0}. The status is 0 for a source the lexer reads to its end, 1
	for one it stops in at its last token, and 3 for one that ends in a string or a comment it does
	not close. The last token is the end, or the one the lexer stops at. *)
lexerStatus::usage = "lexerStatus[lexed] gives the status of the lexer's tokens lexed: 0 read to the end, 1 stopped at the last token, \
3 ended in a string or a comment not closed."
lexerStatus[lexed_List] := First[lexed]

tokenCount::usage = "tokenCount[lexed] gives the number of the lexer's tokens lexed, the last among them."
tokenCount[lexed_List] := lexed[[2]]

tokenKind::usage = "tokenKind[lexed, t] gives the kind of token t of lexed, one of $tkEnd to $tkWord."
tokenKind[lexed_List, t_Integer] := lexed[[5 t - 2]]

tokenKinds::usage = "tokenKinds[lexed] gives the kind of each token of lexed."
tokenKinds[lexed_List] := Take[lexed, {3, 2 + 5 tokenCount[lexed], 5}]

tokenOperator::usage = "tokenOperator[lexed, t] gives the operator of token t of lexed, as fastOp numbers them, 0 for a token that is \
no operator."
tokenOperator[lexed_List, t_Integer] := lexed[[5 t - 1]]

tokenStart::usage = "tokenStart[lexed, t] gives the position of the first character of token t of lexed."
tokenStart[lexed_List, t_Integer] := lexed[[5 t]]

tokenStarts::usage = "tokenStarts[lexed, tokens] gives the position of the first character of each of the tokens of lexed."
tokenStarts[lexed_List, tokens_List] := lexed[[5 tokens]]

tokenEnd::usage = "tokenEnd[lexed, t] gives the position of the character after token t of lexed."
tokenEnd[lexed_List, t_Integer] := lexed[[5 t + 1]]

tokenEnds::usage = "tokenEnds[lexed, tokens] gives the position of the character after each of the tokens of lexed."
tokenEnds[lexed_List, tokens_List] := lexed[[5 tokens + 1]]

newlineBefore::usage = "newlineBefore[lexed, t] gives 1 where a line break comes before token t of lexed, else 0."
newlineBefore[lexed_List, t_Integer] := lexed[[5 t + 2]]

operatorBeforeQ::usage = "operatorBeforeQ[lexed, t, operators] is True where the token before token t of lexed is an operator that \
operators matches, one operator or an Alternatives of them."
operatorBeforeQ[lexed_List, t_Integer, operators_] := t > 1 && tokenKind[lexed, t - 1] === $tkOperator && MatchQ[tokenOperator[lexed, t - 1], operators]

(* the kinds of token that end an operand *)
$operandEndKinds = {$tkName, $tkBlank, $tkInteger, $tkReal, $tkString, $tkSlot, $tkOut, $tkCloseParen, $tkCloseSquare, $tkCloseCurly,
	$tkCloseAssociation, $tkPrimes}

(* Reading stopped at token t, where the kernel's message points: just past the token, or, at the
	end of the source, the source ending too early. But for a :: with no tag after it, the end or a
	blank, or a <<, >> or >>> with no file, the kernel's error, at the end of the ::, at the start of
	the file's operator. *)
stoppedFailure::usage = "stoppedFailure[lexed, t] gives the failure of a source whose reading stops at its token t."
stoppedFailure[lexed_List, t_Integer] := Which[
	tokenKind[lexed, t] === $tkBlank && operatorBeforeQ[lexed, t, $fastColonColon],
		fastFailure[tokenStart[lexed, t], False],
	tokenKind[lexed, t] =!= $tkEnd,
		fastFailure[tokenEnd[lexed, t], False],
	operatorBeforeQ[lexed, t, $fastColonColon],
		fastFailure[tokenStart[lexed, t], False],
	operatorBeforeQ[lexed, t, $fastGet | $fastPut | $fastPutAppend],
		fastFailure[tokenStart[lexed, t - 1], False],
	True,
		fastFailure[tokenStart[lexed, t], True]
]

(* The source is no Wolfram Language: the character where reading stops, as the kernel's reader
	stops there, and whether the source ends before its expression does, as "f[x" does. *)
fastFailure::usage = "fastFailure[position, incomplete] gives the failure of a source whose reading stops at the character at \
position, incomplete True where the source ends before its expression does."
fastFailure[position_Integer, incomplete_] := Failure["ParseError", <|
	"MessageTemplate" -> If[TrueQ[incomplete], "The source ends at position `Position` before its expression does.", "Reading stopped at position `Position`."],
	"MessageParameters" -> <|"Position" -> position|>,
	"Position" -> position,
	"Incomplete" -> TrueQ[incomplete]
|>]

(* The lexer, typed code over packed integers: the codes of a source and
	three zeros after them, so that no look ahead reads past them, the
	class of each code, the operators of 1, 2 and 3 characters, the long-name
	long names (-1 a letter, else its operator) and {<|, |>, <<, >>, >>>,
	=., =, whitespace, the invisible comma, a newline} -> {status, k, then for each of the
	k tokens its kind, operator, start, end (just past it) and newline mark
	(1 where a newline outside a comment comes before it)}, the last token
	the end. Status 1: the source holds a character no token has, where the
	last token, the one that stops there, ends; 3: the source ends in a
	string, a comment, a linear syntax's \( or a free-form input's =[ not
	closed. Whitespace and comments are in no token; after << and >> the
	file is one token, and so is a \( to its \), the boxes of linear
	syntax, a \! before it too, and a =[ to its ], free-form input.
	Its loop is kept small, which a compiler of typed code makes fast: a
	comment, a quoted string or file, a path, a number, a slot, a blank's
	head and linear syntax are each read by a typed function of its own,
	and a long name by lexLongName where the loop meets it, the last kept. *)
$fastLexDeclaration = FunctionDeclaration[fastLex,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{lexCodes, lexClasses, lexOp1, lexOp2, lexOp3, lexLongOps, lexSpecial},
		Native`UncheckedBlock[Module[{n = Length[lexCodes] - 3, out, k = 0, i = 1, j = 0, c = 0, c2 = 0, cl = 0, nl = 0, kind = 0, op = 0, file = 0,
				status = 0, done = 0, scanning = 0, m = 0, a = 0, len = 0, base = 0, start = 0, tick = 0, r = 0, e2 = 0, lnAt = 0, lnVal = 0, nest = 0, pk = 0,
				spOpen = lexSpecial[[1]], spClose = lexSpecial[[2]], spGet = lexSpecial[[3]], spPut = lexSpecial[[4]], spPutAppend = lexSpecial[[5]],
				spUnset = lexSpecial[[6]], spSet = lexSpecial[[7]], spSpace = lexSpecial[[8]], spComma = lexSpecial[[9]], spNewline = lexSpecial[[10]]},
			out = Native`UncheckedArray[0, 5 n + 7];
			While[ done == 0,
				(* whitespace, newlines and comments *)
				nl = 0; scanning = 1;
				While[ scanning == 1 && i <= n,
					c = lexCodes[[i]]; cl = If[c > 65535, 5, lexClasses[[c + 1]]];
					Which[
						cl == 3, i++,
						cl == 4, nl = 1; i++,
						c == 92,
							If[lnAt != i, lnAt = i; lnVal = lexLongName[lexCodes, lexLongOps, i, n]];
							Which[
								lnVal > 0 && Mod[lnVal, 8192] - 1 == spSpace, i = Quotient[lnVal, 8192],
								lnVal > 0 && Mod[lnVal, 8192] - 1 == spNewline, nl = 1; i = Quotient[lnVal, 8192],
								True, scanning = 0],
						c == 40 && i < n && lexCodes[[i + 1]] == 42,
							r = lexComment[lexCodes, i, n];
							If[Mod[r, 2] == 1, status = 3];
							i = Quotient[r, 2],
						True, scanning = 0]];
				k++; base = 2 + 5 (k - 1);
				out[[base + 3]] = i; out[[base + 5]] = nl;
				If[ status != 0 || i > n,
					out[[base + 1]] = 0; out[[base + 2]] = 0; out[[base + 4]] = i; done = 1,
					c = lexCodes[[i]]; cl = If[c > 65535, 5, lexClasses[[c + 1]]]; op = 0; kind = 0; j = i + 1; start = i;
					If[c == 92 && lnAt != i, lnAt = i; lnVal = lexLongName[lexCodes, lexLongOps, i, n]];
					(* after >> or >>>, as a notebook reads it, a file alone, or else all that follows code: a
						file where the end, a newline outside brackets, ;, , or a closer comes after it,
						spaces, tabs and comments between *)
					If[ file == 2,
						r = lexFile[lexCodes, lexClasses, lexLongOps, i, n]; pk = Quotient[r, 4]; scanning = 1;
						While[ scanning == 1 && pk <= n,
							c2 = lexCodes[[pk]];
							Which[
								c2 == 32 || c2 == 9 || ((c2 == 10 || c2 == 13) && nest > 0), pk++,
								c2 == 40 && lexCodes[[pk + 1]] == 42, e2 = lexComment[lexCodes, pk, n]; pk = Quotient[e2, 2],
								True, scanning = 0]];
						c2 = If[pk > n, 0, lexCodes[[pk]]];
						file = If[ pk > n || c2 == 10 || c2 == 13 || c2 == 59 || c2 == 44 || c2 == 41 || c2 == 93 || c2 == 125 ||
							(c2 == 124 && lexCodes[[pk + 1]] == 62), 1, 0];
						(* a name whose [ is not closed is no file after >>, as a notebook reads x >> b[c *)
						If[ file == 1 && lexCodes[[i]] != 34,
							m = i; a = 0;
							While[m < Quotient[r, 4], If[lexCodes[[m]] == 91, a++]; If[lexCodes[[m]] == 93, a--]; m++];
							If[a > 0, file = 0]]];
					Which[
						(* the file of << or >>: a string, or the characters of a path *)
						file == 1,
							r = lexFile[lexCodes, lexClasses, lexLongOps, i, n]; j = Quotient[r, 4]; status = Mod[r, 4]; kind = 8,
						(* a name, a blank after it *)
						cl == 1 || cl == 5 || (c == 92 && lnVal > 0 && Mod[lnVal, 8192] == 0),
							j = i; scanning = 1;
							While[ scanning == 1 && j <= n,
								c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
								Which[
									cl == 1 || cl == 5 || (cl == 2 && j > start), j++,
									c2 == 92,
										If[lnAt != j, lnAt = j; lnVal = lexLongName[lexCodes, lexLongOps, j, n]];
										If[lnVal > 0 && Mod[lnVal, 8192] == 0, j = Quotient[lnVal, 8192], scanning = 0],
									True, scanning = 0]];
							(* a context mark that ends the name, or comes before a digit or another
								mark, makes no name: reading stops at the name *)
							m = i; tick = 0;
							While[ m < j && status == 0,
								If[lexCodes[[m]] == 96, If[tick == 1, status = 1, tick = 1], If[tick == 1 && 48 <= lexCodes[[m]] <= 57, status = 1]; tick = 0];
								m++];
							If[tick == 1, status = 1];
							If[status == 1, j = i];
							kind = 1;
							If[ j <= n && lexCodes[[j]] == 95, kind = 2; c = 95],
						c == 95, j = i; kind = 2,
						(* a number *)
						cl == 2 || (c == 46 && i < n && 48 <= lexCodes[[i + 1]] <= 57),
							r = lexNumber[lexCodes, i, n]; j = Quotient[r, 4]; kind = 3 + Quotient[Mod[r, 4], 2]; status = Mod[r, 2],
						(* a string, a slot of one *)
						c == 34 || (c == 35 && i < n && lexCodes[[i + 1]] == 34),
							r = lexQuoted[lexCodes, If[c == 35, i + 2, i + 1], n]; j = Quotient[r, 2]; kind = If[c == 35, 6, 5];
							(* a string not closed right after a ::, as a notebook reads a::"b: a word of its text to the
								end of the source, kind 22; any other not closed, the source ending in it *)
							If[ Mod[r, 2] == 1,
								If[ c == 34 && k > 1 && out[[base - 4]] == 9 && out[[base - 1]] - out[[base - 2]] == 2 &&
										lexCodes[[out[[base - 2]]]] == 58 && lexCodes[[out[[base - 2]] + 1]] == 58,
									kind = 22,
									status = 3]],
						(* a slot: ## and its digits, or # and its digits or a name, read as a name's
							token reads one, a name malformed making no slot *)
						c == 35,
							r = lexSlot[lexCodes, lexClasses, lexLongOps, i, n]; j = Quotient[r, 2]; status = Mod[r, 2]; kind = 6,
						c == 37,
							While[j <= n && lexCodes[[j]] == 37, j++];
							While[j <= n && 48 <= lexCodes[[j]] <= 57, j++];
							kind = 7,
						c == 39, While[j <= n && lexCodes[[j]] == 39, j++]; kind = 19,
						c == 40, kind = 10,
						c == 41, kind = 11,
						c == 91, kind = 12,
						c == 93, kind = 13,
						c == 123, kind = 14,
						c == 125, kind = 15,
						c == 44, kind = 18,
						(* linear syntax: \( to its \), or \!\( to it *)
						c == 92 && (lexCodes[[i + 1]] == 40 || (lexCodes[[i + 1]] == 33 && lexCodes[[i + 2]] == 92 && lexCodes[[i + 3]] == 40)),
							r = lexBoxes[lexCodes, i, n]; j = Quotient[r, 2]; If[Mod[r, 2] == 1, status = 3]; kind = 20,
						(* a long name, an operator's *)
						c == 92,
							If[ lnVal > 0 && Mod[lnVal, 8192] - 1 > 0,
								op = Mod[lnVal, 8192] - 1; j = Quotient[lnVal, 8192]; kind = If[op == spComma, 18, 9],
								If[i == n, status = 3, status = 1; j = i]],
						(* an operator, the longest there: one of three characters where the
							first two begin one, then two, then one *)
						True,
							len = 0;
							If[ c < 128 && i + 1 <= n && lexCodes[[i + 1]] < 128,
								e2 = lexOp2[[128 c + lexCodes[[i + 1]] + 1]];
								If[ e2 >= 4096 && i + 2 <= n && lexCodes[[i + 2]] < 128,
									a = 1;
									While[ op == 0 && a <= Length[lexOp3],
										If[lexOp3[[a]] == c && lexOp3[[a + 1]] == lexCodes[[i + 1]] && lexOp3[[a + 2]] == lexCodes[[i + 2]], op = lexOp3[[a + 3]]; len = 3];
										a += 4]];
								If[op == 0 && Mod[e2, 4096] > 0, op = Mod[e2, 4096]; len = 2]];
							If[op == 0 && c <= 65535, op = lexOp1[[c + 1]]; len = 1];
							(* an operator that ends in =, but //= and ^:=, right before a [ ends before its =, as
								a notebook reads it: the = and the [ begin free-form input, a==[b] a = =[b] *)
							If[ len >= 2 && lexCodes[[i + len - 1]] == 61 && lexCodes[[i + len]] == 91 && ! (len == 3 && (c == 47 || c == 94)),
								e2 = If[len == 3, Mod[lexOp2[[128 c + lexCodes[[i + 1]] + 1]], 4096], 0];
								If[e2 > 0, op = e2; len = 2, op = lexOp1[[c + 1]]; len = 1]];
							(* =. before a digit: =, then a number *)
							If[op == spUnset && i + 2 <= n && 48 <= lexCodes[[i + 2]] <= 57, op = spSet; len = 1];
							j = i + len;
							Which[
								op == 0, status = 1; j = i,
								(* =[ and the free-form input after it, as a notebook reads it: to the first ], the ]
									of a long name too, its text on one line after any blank ones; text on a line after
									it is no Wolfram Language, where reading stops *)
								op == spSet && len == 1 && lexCodes[[i + 1]] == 91,
									j = i + 2; scanning = 1; a = 0;
									While[ scanning == 1 && j <= n,
										c2 = lexCodes[[j]];
										Which[
											c2 == 93, scanning = 0,
											c2 == 10 || c2 == 13, If[a == 1, a = 2]; j++,
											c2 == 32 || c2 == 9, j++,
											a == 2, status = 1; scanning = 0,
											True, a = 1; j++]];
									If[status == 0, If[j > n, status = 3, j++]];
									kind = 21,
								op == spOpen, kind = 16, op == spClose, kind = 17, op == spComma, kind = 18, True, kind = 9]];
					(* a blank: _, __ or ___, then a . or a name *)
					If[ kind == 2 && status == 0,
						r = lexBlank[lexCodes, lexClasses, lexLongOps, i, j, n]; j = Quotient[r, 2]; status = Mod[r, 2]];
					file = Which[kind == 9 && op == spGet, 1, kind == 9 && (op == spPut || op == spPutAppend), 2, True, 0];
					If[kind == 10 || kind == 12 || kind == 14 || kind == 16, nest++];
					If[(kind == 11 || kind == 13 || kind == 15 || kind == 17) && nest > 0, nest--];
					out[[base + 1]] = kind; out[[base + 2]] = If[kind == 9, op, 0]; out[[base + 4]] = j;
					If[status != 0, done = 1];
					i = j]];
			out[[1]] = status; out[[2]] = k;
			Take[out, 2 + 5 k]]]]]

(* A long name \[Name] at at, letters and digits closed by a ]: 8192 times just past it, plus 1
	more than what the table of long names gives it, -1 a letter, an operator, or 0, as for a name
	it has not; 0 where no long name is there. The table is halved to the name, its names in
	order by length and then by codes. *)
$lexLongNameDeclaration = FunctionDeclaration[lexLongName,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
	Function[{lnCodes, lnTable, lnAt, lnN},
		Native`UncheckedBlock[Module[{j = lnAt + 2, lo = 1, hi = lnTable[[1]], mid = 0, a = 0, op = 0, len = 0, size = 0, cmp = 0, q = 1, result = 0},
			If[ lnAt < lnN && lnCodes[[lnAt]] == 92 && lnCodes[[lnAt + 1]] == 91,
				While[j <= lnN && ((48 <= lnCodes[[j]] <= 57) || (65 <= lnCodes[[j]] <= 90) || (97 <= lnCodes[[j]] <= 122)), j++];
				If[ j > lnAt + 2 && j <= lnN && lnCodes[[j]] == 93,
					size = j - lnAt - 2;
					While[ op == 0 && lo <= hi,
						mid = Quotient[lo + hi, 2]; a = lnTable[[1 + mid]]; len = lnTable[[a]];
						cmp = len - size; q = 1;
						While[cmp == 0 && q <= len, cmp = lnTable[[a + q]] - lnCodes[[lnAt + 1 + q]]; q++];
						Which[cmp < 0, lo = mid + 1, cmp > 0, hi = mid - 1, True, op = lnTable[[a + len + 1]]]];
					result = 8192 (j + 1) + op + 1]];
			result]]]]

(* A comment from its opening paren and star at at, nested ones in it, a backslash before an
	opening paren taking it, so that it opens none, as a notebook reads it:
	twice just past its end, plus 1 where the source ends before it does, the place reading got to
	then. *)
$lexCommentDeclaration = FunctionDeclaration[lexComment,
	Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
	Function[{cmCodes, cmAt, cmN},
		Native`UncheckedBlock[Module[{depth = 1, j = cmAt + 2, unclosed = 0},
			While[ depth > 0,
				Which[
					j + 1 > cmN, unclosed = 1; depth = 0,
					cmCodes[[j]] == 40 && cmCodes[[j + 1]] == 42, depth++; j += 2,
					cmCodes[[j]] == 42 && cmCodes[[j + 1]] == 41, depth--; j += 2,
					cmCodes[[j]] == 92 && cmCodes[[j + 1]] == 40, j += 2,
					True, j++]];
			2 j + unclosed]]]]

(* The characters quoted from from, past the opening ": twice just past the closing ", plus 1
	where the source ends before it, a \ taking the character after it. *)
$lexQuotedDeclaration = FunctionDeclaration[lexQuoted,
	Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
	Function[{qtCodes, qtFrom, qtN},
		Native`UncheckedBlock[Module[{j = qtFrom, scanning = 1, unclosed = 0, c2 = 0},
			While[ scanning == 1,
				If[ j > qtN, unclosed = 1; scanning = 0,
					c2 = qtCodes[[j]];
					Which[c2 == 34, j++; scanning = 0, c2 == 92, j += 2, True, j++]]];
			2 j + unclosed]]]]

(* The file of << or >> at at: a quoted one, or the characters of a path, letters past ASCII
	among them, its long names whole and a bracket in it to its ], brackets nested, or to the end
	of the source, as a notebook reads it:
	4 times just past it, plus the status, 1 where reading stops at it, 3 where the source ends in
	its quotes. *)
$lexFileDeclaration = FunctionDeclaration[lexFile,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} ->
		"MachineInteger"] @
	Function[{flCodes, flClasses, flTable, flAt, flN},
		Native`UncheckedBlock[Module[{j = flAt, r = 0, status = 0, scanning = 1, c2 = 0, cl = 0, ln = 0, depth = 0},
			If[ flCodes[[flAt]] == 34,
				r = lexQuoted[flCodes, flAt + 1, flN]; j = Quotient[r, 2]; If[Mod[r, 2] == 1, status = 3],
				While[ scanning == 1 && j <= flN,
					c2 = flCodes[[j]]; cl = If[c2 > 65535, 5, flClasses[[c2 + 1]]];
					Which[
						cl == 1 || cl == 2 || cl == 5 || c2 == 95 || c2 == 46 || c2 == 47 || c2 == 126 || c2 == 58 || c2 == 33 || c2 == 42 || c2 == 63 || c2 == 45, j++,
						c2 == 92 && j + 1 <= flN && flCodes[[j + 1]] == 91,
							ln = lexLongName[flCodes, flTable, j, flN];
							If[ln > 0, j = Quotient[ln, 8192], status = 1; scanning = 0],
						c2 == 92, j++,
						c2 == 91,
							depth = 1; j++;
							While[depth > 0 && j <= flN, If[flCodes[[j]] == 91, depth++, If[flCodes[[j]] == 93, depth--]]; j++],
						True, scanning = 0]];
				If[j == flAt, status = 1]];
			4 j + status]]]]

(* A number at at: its digits, b^^ and the digits of base b, a precision or an accuracy, which has
	its digits, and a power of the base: 4 times just past it, plus 2 for a real, plus 1 where
	reading stops past it, at a base no number has or a digit its base has not. *)
$lexNumberDeclaration = FunctionDeclaration[lexNumber,
	Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
	Function[{nmCodes, nmAt, nmN},
		Native`UncheckedBlock[Module[{j = 0, a = 0, m = 0, c2 = 0, status = 0, accuracy = 0, real = 0},
			If[ nmCodes[[nmAt]] == 46,
				j = nmAt + 1; While[j <= nmN && 48 <= nmCodes[[j]] <= 57, j++],
				j = nmAt; While[j <= nmN && 48 <= nmCodes[[j]] <= 57, j++];
				Which[
					(* b^^ and a digit, or a point and a digit, as a notebook reads 16^^.f *)
					j + 2 <= nmN && nmCodes[[j]] == 94 && nmCodes[[j + 1]] == 94 &&
						((48 <= nmCodes[[j + 2]] <= 57) || (65 <= nmCodes[[j + 2]] <= 90) || (97 <= nmCodes[[j + 2]] <= 122) ||
							(nmCodes[[j + 2]] == 46 && j + 3 <= nmN && ((48 <= nmCodes[[j + 3]] <= 57) || (65 <= nmCodes[[j + 3]] <= 90) || (97 <= nmCodes[[j + 3]] <= 122)))),
						a = 0; m = nmAt;
						While[m < j, If[a <= 36, a = 10 a + nmCodes[[m]] - 48]; m++];
						j += 2;
						While[j <= nmN && ((48 <= nmCodes[[j]] <= 57) || (65 <= nmCodes[[j]] <= 90) || (97 <= nmCodes[[j]] <= 122)), j++];
						(* a point, not before another, as a notebook reads 16^^ff.. as Repeated[255] *)
						If[ j <= nmN && nmCodes[[j]] == 46 && ! (j + 1 <= nmN && nmCodes[[j + 1]] == 46),
							j++; While[j <= nmN && ((48 <= nmCodes[[j]] <= 57) || (65 <= nmCodes[[j]] <= 90) || (97 <= nmCodes[[j]] <= 122)), j++]];
						If[a < 2 || a > 36, status = 1];
						m = nmAt;
						While[m < j && nmCodes[[m]] != 94, m++];
						m += 2;
						While[ m < j && status == 0,
							c2 = nmCodes[[m]];
							If[ c2 != 46 && If[c2 <= 57, c2 - 48, If[c2 <= 90, c2 - 55, c2 - 87]] >= a, status = 1];
							m++],
					j <= nmN && nmCodes[[j]] == 46 && ! (j + 1 <= nmN && nmCodes[[j + 1]] == 46),
						j++; While[j <= nmN && 48 <= nmCodes[[j]] <= 57, j++],
					True, j = j]];
			If[ j <= nmN && nmCodes[[j]] == 96,
				j++; accuracy = 0;
				If[j <= nmN && nmCodes[[j]] == 96, j++; accuracy = 1];
				m = If[j <= nmN && (nmCodes[[j]] == 43 || nmCodes[[j]] == 45), j + 1, j];
				Which[
					m <= nmN && 48 <= nmCodes[[m]] <= 57,
						While[m <= nmN && 48 <= nmCodes[[m]] <= 57, m++];
						If[m <= nmN && nmCodes[[m]] == 46, m++; While[m <= nmN && 48 <= nmCodes[[m]] <= 57, m++]];
						j = m,
					m + 1 <= nmN && nmCodes[[m]] == 46 && 48 <= nmCodes[[m + 1]] <= 57,
						m++; While[m <= nmN && 48 <= nmCodes[[m]] <= 57, m++]; j = m,
					accuracy == 1, j -= 2,
					True, j = j]];
			If[ j + 1 <= nmN && nmCodes[[j]] == 42 && nmCodes[[j + 1]] == 94,
				m = If[j + 2 <= nmN && (nmCodes[[j + 2]] == 43 || nmCodes[[j + 2]] == 45), j + 3, j + 2];
				If[m <= nmN && 48 <= nmCodes[[m]] <= 57, While[m <= nmN && 48 <= nmCodes[[m]] <= 57, m++]; j = m]];
			m = nmAt;
			While[m < j, If[nmCodes[[m]] == 46 || nmCodes[[m]] == 96, real = 1]; m++];
			4 j + 2 real + status]]]]

(* A slot at at: ## and its digits, or # and its digits or a name, read as a name's token reads one:
	twice just past it, plus 1 where a malformed name makes none and reading stops at it. *)
$lexSlotDeclaration = FunctionDeclaration[lexSlot,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} ->
		"MachineInteger"] @
	Function[{slCodes, slClasses, slTable, slAt, slN},
		Native`UncheckedBlock[Module[{j = slAt + 1, m = 0, scanning = 1, c2 = 0, cl = 0, tick = 0, status = 0, ln = 0, d = 0},
			d = If[j <= slN, slCodes[[j]], 0];
			ln = If[j <= slN && d == 92, lexLongName[slCodes, slTable, j, slN], 0];
			Which[
				j <= slN && d == 35, j++; While[j <= slN && 48 <= slCodes[[j]] <= 57, j++],
				j <= slN && 48 <= d <= 57, While[j <= slN && 48 <= slCodes[[j]] <= 57, j++],
				j <= slN && (d > 65535 || slClasses[[Min[d, 65535] + 1]] == 1 || slClasses[[Min[d, 65535] + 1]] == 5 || (d == 92 && ln > 0 && Mod[ln, 8192] == 0)),
					m = j; scanning = 1;
					While[ scanning == 1 && j <= slN,
						c2 = slCodes[[j]]; cl = If[c2 > 65535, 5, slClasses[[c2 + 1]]];
						Which[
							cl == 1 || cl == 5 || (cl == 2 && j > m), j++,
							c2 == 92, ln = lexLongName[slCodes, slTable, j, slN]; If[ln > 0 && Mod[ln, 8192] == 0, j = Quotient[ln, 8192], scanning = 0],
							True, scanning = 0]];
					tick = 0;
					While[ m < j && status == 0,
						If[slCodes[[m]] == 96, If[tick == 1, status = 1, tick = 1], If[tick == 1 && 48 <= slCodes[[m]] <= 57, status = 1]; tick = 0];
						m++];
					If[tick == 1, status = 1];
					If[status == 1, j = slAt],
				True, j = j];
			2 j + status]]]]

(* The blank after a name or a _ at from, of the token at at: up to three _, then a head, whose
	context marks are a name's, or, after a single _, a .: twice just past it, plus 1 where a
	malformed head makes no blank and reading stops at the token. A . after __ or ___ is a token of
	its own, a Dot or the start of a number, as Wolfram 15 reads __._ and __.1. *)
$lexBlankDeclaration = FunctionDeclaration[lexBlank,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger",
		"MachineInteger"} -> "MachineInteger"] @
	Function[{bkCodes, bkClasses, bkTable, bkAt, bkFrom, bkN},
		Native`UncheckedBlock[Module[{j = bkFrom, count = 0, start = 0, scanning = 1, c2 = 0, cl = 0, m = 0, tick = 0, status = 0, ln = 0, d = 0},
			While[j <= bkN && bkCodes[[j]] == 95 && count < 3, j++; count++];
			If[ count == 1 && j <= bkN && bkCodes[[j]] == 46,
				j++,
				d = If[j <= bkN, bkCodes[[j]], 0];
				ln = If[j <= bkN && d == 92, lexLongName[bkCodes, bkTable, j, bkN], 0];
				If[ j <= bkN && (If[d > 65535, 5, bkClasses[[d + 1]]] == 1 || If[d > 65535, 5, bkClasses[[d + 1]]] == 5 || (d == 92 && ln > 0 && Mod[ln, 8192] == 0)),
					start = j; scanning = 1;
					While[ scanning == 1 && j <= bkN,
						c2 = bkCodes[[j]]; cl = If[c2 > 65535, 5, bkClasses[[c2 + 1]]];
						Which[
							cl == 1 || cl == 5 || (cl == 2 && j > start), j++,
							c2 == 92, ln = lexLongName[bkCodes, bkTable, j, bkN]; If[ln > 0 && Mod[ln, 8192] == 0, j = Quotient[ln, 8192], scanning = 0],
							True, scanning = 0]];
					(* the head's context marks, as a name's *)
					m = start; tick = 0;
					While[ m < j && status == 0,
						If[bkCodes[[m]] == 96, If[tick == 1, status = 1, tick = 1], If[tick == 1 && 48 <= bkCodes[[m]] <= 57, status = 1]; tick = 0];
						m++];
					If[tick == 1, status = 1];
					If[status == 1, j = bkAt]]];
			2 j + status]]]]

(* Linear syntax at at: \( to its \), or \!\( to it, nested ones in it: twice just past its end,
	plus 1 where the source ends before it does. *)
$lexBoxesDeclaration = FunctionDeclaration[lexBoxes,
	Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
	Function[{bxCodes, bxAt, bxN},
		Native`UncheckedBlock[Module[{j = If[bxCodes[[bxAt + 1]] == 40, bxAt + 2, bxAt + 4], depth = 1, unclosed = 0},
			While[ depth > 0,
				Which[
					j >= bxN, unclosed = 1; depth = 0; j = bxN + 1,
					bxCodes[[j]] == 92 && bxCodes[[j + 1]] == 40, depth++; j += 2,
					bxCodes[[j]] == 92 && bxCodes[[j + 1]] == 41, depth--; j += 2,
					bxCodes[[j]] == 92, j += 2,
					True, j++]];
			2 j + unclosed]]]]

(* the typed functions the lexer calls, each after those it calls *)
$fastLexHelpers := {$lexLongNameDeclaration, $lexQuotedDeclaration, $lexCommentDeclaration, $lexFileDeclaration, $lexNumberDeclaration, $lexSlotDeclaration,
	$lexBlankDeclaration, $lexBoxesDeclaration}

(* a source's codes and three zeros after them, packed, as every typed function takes them: no
	look ahead reads past them, and the empty source's are packed too *)
paddedCodes[codes_List] := Developer`ToPackedArray[Join[codes, {0, 0, 0}]]

(* The function of a typed declaration: the definition a compiler of typed
	code gave the declared symbol, where one did; else the declaration's
	Function compiled by Compile, the typed functions it calls compiled first
	and put in its code, where Compile inlines them, where Compile is; else
	evaluated, those it calls evaluated too. *)
SetAttributes[typedFunction, HoldFirst]
typedFunction[symbol_Symbol, declaration_] := typedFunction[symbol, declaration, {}]
typedFunction[symbol_Symbol, declaration_, helpers_List] := If[ DownValues[symbol] =!= {} || OwnValues[symbol] =!= {},
	symbol,
	With[{inlined = Fold[Function[{done, h}, Append[done, h[[1]] -> compiledDeclaration[h, done]]], {}, helpers]},
		If[ AllTrue[inlined[[All, 2]], MatchQ[_CompiledFunction]],
			Replace[compiledDeclaration[declaration, inlined], Except[_CompiledFunction] :> evaluatedDeclaration[declaration, helpers]],
			evaluatedDeclaration[declaration, helpers]]]]

(* a typed declaration's Function, its body out of the Native`UncheckedBlock that a compiler of
	typed code reads, which drops its index and overflow tests, and each Native`UncheckedArray, an
	array none of whose elements is set, made one of zeros *)
declarationFunction[declaration_] := (declaration[[2, 1]] /. HoldPattern[Native`UncheckedBlock[body_]] :> body) /. HoldPattern[Native`UncheckedArray[c_, k_]] :> Table[c, {k}]

(* a typed declaration's Function compiled by Compile, each argument an integer or a packed vector
	of them as its type says, the typed functions it calls put in its code, compiled *)
compiledDeclaration[declaration_, inlined_List] := With[{f = declarationFunction[declaration], types = declaration[[2, 0, 1, 1]]},
	Compile @@ Join[Hold[Evaluate[MapThread[{#1, _Integer, If[#2 === "MachineInteger", 0, 1]} &, {List @@ f[[1]], types}]]],
		Extract[f, {2}, Hold] /. inlined, Hold[CompilationOptions -> {"InlineCompiledFunctions" -> True}]]]

(* a typed declaration's Function, evaluated, the typed functions it calls their Functions *)
evaluatedDeclaration[declaration_, helpers_List] :=
	declarationFunction[declaration] /. Fold[Function[{done, h}, Append[done, h[[1]] -> (declarationFunction[h] /. done)]], {}, helpers]

(* the lexer run here, fixed at its first use *)
fastLexFunction := fastLexFunction = typedFunction[fastLex, $fastLexDeclaration, $fastLexHelpers]

(* ::Section:: *)
(*The operator table*)

(* The levels of the grammar's specs, by operator: the precedence, the
	fixity and the head. A chain's key tells the operators that make one node
	together. *)
$fastLed = Association[Map[fastOp[#[[1]]] -> Rest[#] &, {
	{"::", 184, "MessageName", "MessageName"},
	{"?", 178, "InfixL", "PatternTest"},
	{"++", 174, "Postfix", "Increment"}, {"--", 174, "Postfix", "Decrement"},
	{"@*", 170, "InfixN", "Composition"},
	{"/*", 168, "InfixN", "RightComposition"},
	{"@", 165, "InfixR", "At"},
	{"~", 162, "Ternary", "Tilde"},
	{"/@", 161, "InfixR", "Map"}, {"//@", 161, "InfixR", "MapAll"}, {"@@", 161, "InfixR", "Apply"}, {"@@@", 161, "InfixR", "MapApply"},
	{"!", 158, "Postfix", "Factorial"}, {"!!", 158, "Postfix", "Factorial2"},
	{"<>", 152, "InfixN", "StringJoin"},
	{"^", 151, "InfixR", "Power"},
	{"**", 132, "InfixN", "NonCommutativeMultiply"},
	{".", 126, "InfixN", "Dot"},
	{"/", 122, "InfixL", "Divide"},
	{"*", 108, "InfixN", "Times"},
	{"+", 86, "InfixN", "Plus"}, {"-", 86, "InfixN", "Plus"},
	{";;", 80, "Span", "Span"},
	{"DirectedEdge", 79, "InfixR", "DirectedEdge"}, {"UndirectedEdge", 79, "InfixR", "UndirectedEdge"},
	{"==", 76, "InfixN", "Equal"}, {"!=", 76, "InfixN", "Unequal"}, {"<=", 76, "InfixN", "LessEqual"},
	{">=", 76, "InfixN", "GreaterEqual"}, {"<", 76, "InfixN", "Less"}, {">", 76, "InfixN", "Greater"},
	{"===", 70, "InfixN", "SameQ"}, {"=!=", 70, "InfixN", "UnsameQ"},
	{"Element", 68, "InfixN", "Element"},
	{"&&", 62, "InfixN", "And"},
	{"||", 58, "InfixN", "Or"},
	{"..", 44, "Postfix", "Repeated"}, {"...", 44, "Postfix", "RepeatedNull"},
	{"|", 42, "InfixN", "Alternatives"},
	{"~~", 36, "InfixN", "StringExpression"},
	{"/;", 34, "InfixL", "Condition"},
	{"<->", 33, "InfixR", "TwoWayRule"},
	{"->", 31, "InfixR", "Rule"}, {":>", 31, "InfixR", "RuleDelayed"},
	{"/.", 28, "InfixL", "ReplaceAll"}, {"//.", 28, "InfixL", "ReplaceRepeated"},
	{"+=", 27, "InfixR", "AddTo"}, {"-=", 27, "InfixR", "SubtractFrom"}, {"*=", 27, "InfixR", "TimesBy"}, {"/=", 27, "InfixR", "DivideBy"},
	{"&", 24, "Postfix", "Function"},
	{"//=", 21, "InfixR", "ApplyTo"},
	{"//", 18, "InfixL", "SlashSlash"},
	{"/:", 11, "TagSet", "TagSet"},
	{"=", 9, "InfixR", "Set"}, {":=", 9, "InfixR", "SetDelayed"}, {"^=", 9, "InfixR", "UpSet"}, {"^:=", 9, "InfixR", "UpSetDelayed"},
	{"|->", 9, "InfixR", "Function"}, {"=.", 9, "Postfix", "Unset"},
	{">>", 6, "Put", "Put"}, {">>>", 6, "Put", "PutAppend"},
	{";", 4, "Compound", "CompoundExpression"}}]]

(* the operators of one chain: the products, the sums, the relations *)
$fastChainKey = <|"Times" -> "Times", "Plus" -> "Plus", "Equal" -> "Relation", "Unequal" -> "Relation", "LessEqual" -> "Relation",
	"GreaterEqual" -> "Relation", "Less" -> "Relation", "Greater" -> "Relation"|>
fastChainKey[spec_List] := If[Length[spec] >= 4, spec[[4]], Lookup[$fastChainKey, spec[[3]], spec[[3]]]]

(* the prefix operators: the precedence and the head *)
$fastPrefix = Association[Map[fastOp[#[[1]]] -> Rest[#] &, {
	{"++", 172, "PreIncrement"}, {"--", 172, "PreDecrement"}, {"-", 124, "Minus"}, {"+", 124, "Plus"}, {"!", 64, "Not"}, {"!!", 64, "NotNot"}}]]

(* The long-name operators, read at their first use: the led ones by the
	held grammar's specs, the fourth of a spec the key of the chain it makes
	with others, and the prefix ones; the brackets, the integrals and the
	prefix operators that a product goes on at. *)
$fastLedTable := $fastLedTable = Join[$fastLed, Association[Join[
	Map[Function[row, fastLongOp[row[[1]]] -> With[{head = heldLongHead[row], p = row[[4]]}, Which[
		row[[3]] === CodeParser`InfixInequality, {p, "InfixN", head, "Relation"},
		row[[1]] === "Minus", {p, "InfixN", "Plus", "Plus"},
		row[[1]] === "ImplicitPlus", {p, "InfixL", "Plus"},
		row[[1]] === "Divides", {p, "InfixN", "Divisible", "Divisible"},
		row[[1]] === "InvisibleApplication", {p, "InfixR", "At"},
		row[[2]] === "InfixNode", {p, "InfixN", head, head},
		True, {p, If[row[[5]] === "Right", "InfixR", "InfixL"], head}]]], $heldLongInfix],
	Map[fastLongOp[#[[1]]] -> {#[[4]], "Postfix", heldLongHead[#]} &, $longNameTable["Postfix"]],
	{fastLongOp["LeftDoubleBracket"] -> {176, "LongPart", "Part"}}]]]
$fastPrefixTable := $fastPrefixTable = Join[$fastPrefix,
	Association[Map[fastLongOp[#[[1]]] -> {#[[4]], heldLongHead[#]} &, $heldLongPrefix]], <|$fastNotId -> {64, "Not"}|>]
$fastGroupTable := $fastGroupTable = Association[Map[fastLongOp[#[[1]]] -> {fastLongOp[#[[2]]], SymbolName[#[[3]]]} &,
	Select[$longNameTable["Groups"], #[[1]] =!= "LeftDoubleBracket" &]]]
$fastIntegralTable := $fastIntegralTable = Association[Map[fastLongOp[#[[1]]] -> {SymbolName[#[[2]]], #[[3]]} &, $longNameTable["Integrals"]]]
$fastPrefixOnly := $fastPrefixOnly = AssociationThread[Join[DeleteCases[fastLongOp /@ $prefixOnlyNames, 0], {$fastNotId, $fastGet}] -> True]
$fastLongMinus := $fastLongMinus = fastLongOp["Minus"]
$fastRightDoubleBracket := $fastRightDoubleBracket = fastLongOp["RightDoubleBracket"]

$fastPatternColon = 40; $fastOptionalColon = 38; $fastSpanOperand = 80; $fastCompoundOperand = 4; $fastTagLeft = 9; $fastTagRight = 8; $fastImplicitTimes = 108
$fastColon = fastOp[":"]; $fastSemiSemi = fastOp[";;"]; $fastSemi = fastOp[";"]; $fastQuestion = fastOp["?"]; $fastColonColon = fastOp["::"]
$fastColonEqual = fastOp[":="]; $fastEqual = fastOp["="]; $fastEqualDot = fastOp["=."]; $fastTilde = fastOp["~"]; $fastDot = fastOp["."]; $fastMinus = fastOp["-"]

(* ::Section:: *)
(*The operator after each token*)

(* The spec of the operator after an operand, by token: all the led specs
	in a list, and each token's index in it, 0 if it is none. A token's spec
	is the operator's it is, or that of the call, a derivative or a product
	for its kind; = before . is an unset. *)
$fastSpecList := $fastSpecList = DeleteDuplicates[Join[Values[$fastLedTable],
	{{176, "Call", "Call"}, {154, "Derivative", "Derivative"}, {$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}, {9, "Unset", "Unset"}}]]
fastSpecIndex[spec_] := First[FirstPosition[$fastSpecList, spec, {0}, {1}, Heads -> False]]
$fastOpSpecIndex := $fastOpSpecIndex = With[{n = $fastNotId + 1}, Developer`ToPackedArray[
	Table[Which[KeyExistsQ[$fastLedTable, k], fastSpecIndex[$fastLedTable[k]],
		KeyExistsQ[$fastPrefixOnly, k], fastSpecIndex[{$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}], True, 0], {k, 0, n}]]]
$fastKindSpecIndex := $fastKindSpecIndex = Developer`ToPackedArray[ReplacePart[ConstantArray[0, $tkWord + 1], Join[
	{($tkOpenSquare + 1) -> fastSpecIndex[{176, "Call", "Call"}], ($tkPrimes + 1) -> fastSpecIndex[{154, "Derivative", "Derivative"}]},
	Map[(# + 1) -> fastSpecIndex[{$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}] &,
		{$tkName, $tkBlank, $tkInteger, $tkReal, $tkString, $tkSlot, $tkOut, $tkOpenParen, $tkOpenCurly, $tkOpenAssociation, $tkBoxes, $tkFreeform, $tkWord}]]]]
fastLedIndices[lexed_List] := fastLedFunction[lexed, $fastKindSpecIndex, $fastOpSpecIndex, $fastLedParams]
$fastLedParams := $fastLedParams = Developer`ToPackedArray[{$tkOperator, $fastEqual, $fastDot, $fastUnsetSpecIndex}]
$fastUnsetSpecIndex := $fastUnsetSpecIndex = fastSpecIndex[{9, "Unset", "Unset"}]

(* ::Section:: *)
(*The typed parser*)

(* The parser, typed code over packed integers, as the lexer is: the
	lexer's tokens, each token's led spec index, the
	tables of the specs {precedence, fixity, head, chain key}, of the
	prefix operators {precedence, head} and the brackets {closer, head} by
	operator, the integral of each operator, the special operators and
	precedences, heads and chain keys, and the codes and classes the lexer
	read, for the words of a ? query -> {status, n, then n instructions of
	three integers}: a postfix program the build pass makes the held values
	of. Status 1: the tokens are no Wolfram Language, and the second number
	is the farthest token reading reached, where the kernel's reader stops;
	3: a token is two, the words of a ? query ending inside it or a
	message name's blank following its tag in it, and the second number is
	the code it splits at, where splitParse lexes it apart; either way the
	third is the first token of the statement that stops it. It climbs as the grammar's table does, with no
	recursion: a stack of frames of eight integers, the expression being
	read and what waits for it, backtracking to a pattern's name or to an
	operand left out by the token and the program's length a frame saved.

	Frames: 1 an expression {min, rbp, plain}; 2 a prefix operator {head};
	3 an infix one {head}; 4 a chain {precedence, key, head, count, sign,
	min, plain}; 5 parentheses; 6 a bracket {kind, closer kind, closer
	operator, count, head}, of kind 1 a call, 2 a part, 3 a list, 4 an
	association, 5 a long-name group, 6 a long-name part, 7 a type's
	parameters; 7 a pattern and 8 an operand left out, {token, length,
	brackets}; 9 a span {state, count}; 10 a compound {count};
	11 a ternary {state, precedence, min, plain}; 12 a tag set {state}; 13
	an integral {integral, signs}; 14 a message name {count, first token, instructions}; 15 a query
	that does not begin its statement {??, first token, instructions}.

	Instructions: 1 a leaf {kind, token}; 2 prefix {head}; 3 postfix
	{head}; 4 binary {head}; 5 a flat chain {head, n}; 6 a relation's
	operator {head}; 7 a relation chain {n}; 8 a call {n}; 9 a group {head,
	n}; 10 a part {n}; 11 Null {1 where a comma leaves it, else 0}; 12 All;
	13 the 1 of a span begun with ;;;
	14 a message name {n}; 15 a type's parameters {n}; 16 a derivative
	{primes}; 17 a ~f~ b; 18 a span {n}; 19 a compound {n}; 20 a tag set
	{1 :=, 2 =, 3 =.}; 21 a put {head}; 22 a get; 23 a pattern; 24 an
	integral {integral, signs}; 25 the end of a statement {its first token, the
	token after it};
	26 a divisibility chain {n}; 27 !!; 28 the words of a query {start,
	end}; 29 a query {??}. *)
$fastParseDeclaration = FunctionDeclaration[fastParse,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} ->
		"PackedArray"::["MachineInteger", 1]] @
	Function[{pTok, pLed, pSpecs, pPrefix, pGroups, pIntegrals, pSpecial, pHeads, pKeys, pCodes, pClasses},
		Native`UncheckedBlock[Module[{n = pTok[[2]], out, fr, maxFrames, sp = 0, on = 0, t = 1, brackets = 0, status = 0, mode = 0,
				pMin = 0, pRbp = 0, pPlain = 0, base = 0, k = 0, o = 0, i = 0, bp = 0, fx = 0, hd = 0, ky = 0, mn = 0, rb = 0, pl = 0,
				ft = 0, cnt = 0, bt = 0, colons = 0, ok = 0, x = 0, lg = 0, e = 0, we = 0, c = 0, cl = 0, tt = 0, far = 0, stmt = 1, se = 0,
				nls, ps = 0, ol = 0, pe = 0, nst = 0, q = 0, nf = 0, kk = 0, trail = 0, need = 0, wq = 0},
			out = Native`UncheckedArray[0, 3 (8 n + 16) + 2];
			maxFrames = 4 n + 64;
			fr = Native`UncheckedArray[0, 8 maxFrames];
			(* the line break before each token, a newline before it outside comments, but for one
				right after a ;;, which a notebook reads as whitespace, unless another ;; comes after
				it and the first has no operand before it: nothing, a line break outside brackets,
				or a token that ends no operand; a ; ends one, as a ;; after it spans the compound *)
			nls = Native`UncheckedArray[0, n + 1];
			tt = 1;
			While[ tt <= n,
				k = pTok[[5 tt - 2]]; o = pTok[[5 tt - 1]];
				nls[[tt]] = pTok[[5 tt + 2]];
				If[ps == 1 && ! (k == 9 && o == pSpecial[[2]] && ol == 1), nls[[tt]] = 0];
				ps = If[k == 9 && o == pSpecial[[2]], 1, 0];
				If[ps == 1, ol = If[pe == 0 || (nls[[tt]] == 1 && nst == 0), 1, 0]];
				pe = Which[
					(k >= 1 && k <= 8) || k == 11 || k == 13 || k == 15 || k == 17 || k == 19 || k == 20 || k == 21 || (k == 9 && o == pSpecial[[3]]), 1,
					k == 9 && pLed[[tt]] > 0 && pSpecs[[4 pLed[[tt]] - 2]] == 4, If[pPrefix[[2 o + 1]] > 0, pe, 1],
					True, 0];
				If[k == 10 || k == 12 || k == 14 || k == 16, nst++];
				If[(k == 11 || k == 13 || k == 15 || k == 17) && nst > 0, nst--];
				tt++];
			k = 0; o = 0;
			While[ mode != 99,
				Which[
					(* a statement *)
					mode == 0,
						If[pTok[[5 t - 2]] == 0, mode = 99, stmt = t; pMin = 0; pRbp = 0; pPlain = 0; mode = 1],
					(* an expression's frame *)
					mode == 1,
						If[ sp >= maxFrames, status = 1; If[t > far, far = t]; mode = 99,
							sp++; base = 8 (sp - 1); fr[[base + 1]] = 1; fr[[base + 2]] = pMin; fr[[base + 3]] = pRbp; fr[[base + 4]] = pPlain;
							mode = 2],
					(* the operand of the expression at the top *)
					mode == 2,
						base = 8 (sp - 1); mn = fr[[base + 2]]; pl = fr[[base + 4]];
						k = pTok[[5 t - 2]]; o = pTok[[5 t - 1]];
						Which[
							(* a prefix operator, in a span's operand one of any precedence, its operand all that binds
								more tightly than it, as CodeParser reads it [W15 bug]; right after a . too, as a
								notebook reads a . -b *)
							k == 9 && pPrefix[[2 o + 1]] > 0 && (pPrefix[[2 o + 1]] > mn || mn == pSpecial[[17]]),
								hd = pPrefix[[2 o + 2]]; pRbp = pPrefix[[2 o + 1]]; t++;
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 2; fr[[base + 2]] = hd;
								pMin = If[mn == pSpecial[[17]], 0, mn]; pPlain = pl; mode = 1,
							k == 1,
								on++; out[[3 on]] = 1; out[[3 on + 1]] = 1; out[[3 on + 2]] = t; t++;
								If[ pl == 0 && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[1]] && ! (brackets == 0 && nls[[t]] == 1),
									sp++; base = 8 (sp - 1); fr[[base + 1]] = 7; fr[[base + 2]] = t; fr[[base + 3]] = on; fr[[base + 4]] = brackets;
									t++; pMin = pSpecial[[16]]; pRbp = 0; pPlain = 1; mode = 1,
									mode = 3],
							(k >= 2 && k <= 7) || k == 20 || k == 21 || k == 22,
								on++; out[[3 on]] = 1; out[[3 on + 1]] = If[k == 22, 100, k]; out[[3 on + 2]] = t; t++; mode = 3,
							k == 10,
								t++; brackets++;
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 5;
								pMin = 0; pRbp = 0; pPlain = 0; mode = 1,
							k == 14 || k == 16,
								t++; brackets++;
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 6; fr[[base + 2]] = If[k == 14, 3, 4]; fr[[base + 3]] = If[k == 14, 15, 17];
								fr[[base + 4]] = 0; fr[[base + 5]] = 0; fr[[base + 6]] = 0;
								mode = 6,
							k == 9 && pGroups[[2 o + 1]] > 0,
								t++; brackets++;
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 6; fr[[base + 2]] = 5; fr[[base + 3]] = 9; fr[[base + 4]] = pGroups[[2 o + 1]];
								fr[[base + 5]] = 0; fr[[base + 6]] = pGroups[[2 o + 2]];
								mode = 6,
							k == 9 && o == pSpecial[[9]],
								t++;
								If[ pTok[[5 t - 2]] == 8,
									on++; out[[3 on]] = 1; out[[3 on + 1]] = 8; out[[3 on + 2]] = t; t++;
									on++; out[[3 on]] = 22; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 3,
									mode = 5],
							k == 9 && o == pSpecial[[2]],
								on++; out[[3 on]] = 13; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 10,
							(* a query that does not begin its statement, as a notebook reads it: ? and the expression
								after it, all that binds more tightly than =, a word of one token its text, and ?? and a
								word of one token; frame 15 {??, first token, instructions} *)
							k == 9 && o == pSpecial[[14]] && t != stmt,
								t++; lg = 0;
								If[pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[14]] && pTok[[5 t]] == pTok[[5 t - 4]], lg = 1; t++];
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 15; fr[[base + 2]] = lg; fr[[base + 3]] = t; fr[[base + 4]] = on;
								pMin = pSpecial[[19]]; pRbp = 0; pPlain = 0; mode = 1,
							(* ?words, ??words at the beginning of a statement: Information of the words, to the end of
								their last token, or of a string, which a notebook answers itself *)
							k == 9 && o == pSpecial[[14]],
								t++; lg = 0;
								If[pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[14]] && pTok[[5 t]] == pTok[[5 t - 4]], lg = 1; t++];
								e = pTok[[5 t - 4]];
								While[pCodes[[e]] == 32 || pCodes[[e]] == 9, e++];
								If[ pCodes[[e]] == 34,
									If[ pTok[[5 t - 2]] != 5 || pTok[[5 t]] != e, mode = 5,
										on++; out[[3 on]] = 1; out[[3 on + 1]] = 5; out[[3 on + 2]] = t; t++;
										on++; out[[3 on]] = 29; out[[3 on + 1]] = lg; out[[3 on + 2]] = 0; mode = 3],
									(* words after a name's letter, to an operator; after anything else, as Wolfram 15's
										kernel reads ?[a and ?@@%3, the rest of the line, its spaces at the end left out *)
									x = e; we = e; ok = 1; tt = t;
									c = pCodes[[e]]; cl = If[c > 65535, 5, pClasses[[c + 1]]];
									If[ (cl == 1 && c != 96) || cl == 5 || (c == 92 && pTok[[5 t]] == e && (pTok[[5 t - 2]] == 1 || pTok[[5 t - 2]] == 2)),
										While[ ok == 1,
											c = pCodes[[x]]; cl = If[c > 65535, 5, pClasses[[c + 1]]];
											Which[
												cl == 1 || cl == 2 || cl == 5 || c == 42 || c == 64, x++; we = x,
												(* a letter's long name, in a name's token *)
												c == 92,
													While[tt < pTok[[2]] && pTok[[5 tt + 1]] <= x, tt++];
													If[ pTok[[5 tt - 2]] == 1 && pTok[[5 tt]] <= x && pCodes[[x + 1]] == 91,
														x += 2;
														While[(48 <= pCodes[[x]] && pCodes[[x]] <= 57) || (65 <= pCodes[[x]] && pCodes[[x]] <= 90) || (97 <= pCodes[[x]] && pCodes[[x]] <= 122), x++];
														If[pCodes[[x]] == 93, x++; we = x, ok = 0],
														ok = 0],
												c == 32 || c == 9, x++,
												True, ok = 0]],
										While[pCodes[[we]] != 0 && pCodes[[we]] != 10 && pCodes[[we]] != 13, we++];
										While[we > e && (pCodes[[we - 1]] == 32 || pCodes[[we - 1]] == 9), we--]];
									If[ we == e, mode = 5,
										While[pTok[[5 t - 2]] != 0 && pTok[[5 t]] < we, t++];
										(* words that end inside a token, as ?a*=b: the token is split there, status 3 *)
										If[ pTok[[5 t - 4]] != we, status = 3; far = we; mode = 99,
											on++; out[[3 on]] = 28; out[[3 on + 1]] = e; out[[3 on + 2]] = we;
											on++; out[[3 on]] = 29; out[[3 on + 1]] = lg; out[[3 on + 2]] = 0; wq = t; mode = 3]]],
							(* an integral, the same signs right after it one integral of as many differentials, as a
								notebook reads \[Integral]\[Integral] f \[DifferentialD]x \[DifferentialD]y *)
							k == 9 && pIntegrals[[o + 1]] > 0,
								x = pIntegrals[[o + 1]]; t++; cnt = 1;
								While[pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == o, t++; cnt++];
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 13; fr[[base + 2]] = x; fr[[base + 3]] = cnt;
								pMin = pSpecial[[15]]; pRbp = 0; pPlain = 0; mode = 1,
							True, mode = 5],
					(* after an operand: an Optional's : after a blank or a pattern, else the operator that
						takes it, if one binds tightly enough *)
					mode == 3,
						base = 8 (sp - 1); mn = fr[[base + 2]]; rb = fr[[base + 3]]; pl = fr[[base + 4]];
						i = pLed[[t]];
						(* a ;; right where a span ends begins a span of its own, the two a product *)
						If[se == t && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[2]], i = pSpecial[[22]]];
						(* right after the words of a query that begins its statement, an operator that is a prefix one
							too begins a factor, as Wolfram 15's kernel reads ?a+b as Information["a"]*(+b) *)
						If[wq == t && pTok[[5 t - 2]] == 9 && pPrefix[[2 pTok[[5 t - 1]] + 1]] > 0, i = pSpecial[[22]]];
						If[ pl == 0 && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[1]] && ! (brackets == 0 && nls[[t]] == 1) &&
								((out[[3 on]] == 1 && out[[3 on + 1]] == 2 && pCodes[[pTok[[5 out[[3 on + 2]] + 1]] - 1]] != 46) || out[[3 on]] == 23),
							t++; sp++; base = 8 (sp - 1); fr[[base + 1]] = 3; fr[[base + 2]] = pHeads[[7]];
							pMin = mn; pRbp = pSpecial[[21]]; pPlain = 0; i = -1; mode = 1];
						If[brackets == 0 && nls[[t]] == 1 && i > 0, i = 0];
						If[ i == 0, mode = 4,
							If[ i > 0,
							bp = pSpecs[[4 i - 3]]; fx = pSpecs[[4 i - 2]]; hd = pSpecs[[4 i - 1]]; ky = pSpecs[[4 i]];
							If[ bp <= rb || bp <= mn, mode = 4,
								Which[
									(* a ? after a pattern test, as a notebook reads a?b?c: no Wolfram Language *)
									fx == 1 && pTok[[5 t - 1]] == pSpecial[[14]] && out[[3 on]] == 4 && out[[3 on + 1]] == hd, mode = 5,
									fx == 1 || fx == 2,
										t++;
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 3; fr[[base + 2]] = hd;
										pMin = mn; pRbp = If[fx == 2, bp - 1, bp]; pPlain = pl; mode = 1,
									fx == 3 || fx == 15,
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 4; fr[[base + 2]] = bp; fr[[base + 3]] = ky; fr[[base + 4]] = hd; fr[[base + 5]] = 1;
										fr[[base + 6]] = If[ky == pKeys[[1]] && pTok[[5 t - 2]] == 9 && (pTok[[5 t - 1]] == pSpecial[[11]] || pTok[[5 t - 1]] == pSpecial[[12]]), 1, 0];
										fr[[base + 7]] = mn; fr[[base + 8]] = pl;
										If[ky == pKeys[[2]], on++; out[[3 on]] = 6; out[[3 on + 1]] = hd; out[[3 on + 2]] = 0];
										If[fx == 3, t++];
										pMin = mn; pRbp = bp; pPlain = pl; mode = 1,
									fx == 4, t++; on++; out[[3 on]] = 3; out[[3 on + 1]] = hd; out[[3 on + 2]] = 0,
									fx == 13, t += 2; on++; out[[3 on]] = 3; out[[3 on + 1]] = pHeads[[2]]; out[[3 on + 2]] = 0,
									fx == 5,
										If[t < n && pTok[[5 t + 3]] == 12, t += 2; bt = 2, t++; bt = 1];
										brackets++;
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 6; fr[[base + 2]] = bt; fr[[base + 3]] = 13; fr[[base + 4]] = 0; fr[[base + 5]] = 0; fr[[base + 6]] = 0;
										mode = 6,
									fx == 14,
										t++; brackets++;
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 6; fr[[base + 2]] = 6; fr[[base + 3]] = 9; fr[[base + 4]] = pSpecial[[13]]; fr[[base + 5]] = 0; fr[[base + 6]] = 0;
										mode = 6,
									fx == 6,
										on++; out[[3 on]] = 16; out[[3 on + 1]] = pTok[[5 t + 1]] - pTok[[5 t]]; out[[3 on + 2]] = 0; t++,
									fx == 7,
										t++;
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 11; fr[[base + 2]] = 1; fr[[base + 3]] = bp; fr[[base + 4]] = mn; fr[[base + 5]] = pl;
										pMin = mn; pRbp = bp; pPlain = pl; mode = 1,
									fx == 8,
										colons = pTok[[5 t + 1]]; t++;
										If[ pTok[[5 t - 2]] == 12 && pTok[[5 t]] == colons,
											t++; brackets++;
											sp++; base = 8 (sp - 1); fr[[base + 1]] = 6; fr[[base + 2]] = 7; fr[[base + 3]] = 13; fr[[base + 4]] = 0; fr[[base + 5]] = 0; fr[[base + 6]] = 0;
											mode = 6,
											(* a message name, as a notebook reads it: after each ::, an operand, read with
												no operator after it but a pattern's colon, a prefix operator of any
												precedence beginning one; frame 14 {count, first token, instructions} *)
											sp++; base = 8 (sp - 1); fr[[base + 1]] = 14; fr[[base + 2]] = 1; fr[[base + 3]] = t; fr[[base + 4]] = on;
											pMin = pSpecial[[17]]; pRbp = 100000; pPlain = 0; mode = 1],
									fx == 9, mode = 10,
									fx == 10,
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 10; fr[[base + 2]] = 1; mode = 13,
									fx == 11,
										t++;
										sp++; base = 8 (sp - 1); fr[[base + 1]] = 12; fr[[base + 2]] = 1;
										pMin = pSpecial[[19]]; pRbp = 0; pPlain = 0; mode = 1,
									(* >> or >>> and a file, else, as a notebook reads it, the expression after it *)
									fx == 12,
										t++;
										If[ pTok[[5 t - 2]] == 8,
											on++; out[[3 on]] = 1; out[[3 on + 1]] = 8; out[[3 on + 2]] = t; t++;
											on++; out[[3 on]] = 21; out[[3 on + 1]] = hd; out[[3 on + 2]] = 0,
											sp++; base = 8 (sp - 1); fr[[base + 1]] = 3; fr[[base + 2]] = hd;
											pMin = mn; pRbp = bp; pPlain = pl; mode = 1],
									True, mode = 5]]]],
					(* the expression at the top is read: what waited for it *)
					mode == 4,
						sp--;
						If[ sp == 0,
							on++; out[[3 on]] = 25; out[[3 on + 1]] = stmt; out[[3 on + 2]] = t; mode = 0,
							base = 8 (sp - 1); ft = fr[[base + 1]];
							Which[
								ft == 2,
									on++;
									If[fr[[base + 2]] == pHeads[[6]], out[[3 on]] = 27; out[[3 on + 1]] = 0, out[[3 on]] = 2; out[[3 on + 1]] = fr[[base + 2]]];
									out[[3 on + 2]] = 0; sp--; mode = 3,
								ft == 3,
									on++; out[[3 on]] = 4; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = 0; sp--; mode = 3,
								ft == 4,
									If[fr[[base + 6]] == 1, on++; out[[3 on]] = 2; out[[3 on + 1]] = pHeads[[1]]; out[[3 on + 2]] = 0];
									fr[[base + 5]] = fr[[base + 5]] + 1;
									i = pLed[[t]];
									If[se == t && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[2]], i = pSpecial[[22]]];
									If[brackets == 0 && nls[[t]] == 1, i = 0];
									If[ i > 0 && pSpecs[[4 i - 3]] == fr[[base + 2]] && (pSpecs[[4 i - 2]] == 3 || pSpecs[[4 i - 2]] == 15) && pSpecs[[4 i]] == fr[[base + 3]],
										fr[[base + 6]] = If[fr[[base + 3]] == pKeys[[1]] && pTok[[5 t - 2]] == 9 && (pTok[[5 t - 1]] == pSpecial[[11]] || pTok[[5 t - 1]] == pSpecial[[12]]), 1, 0];
										If[fr[[base + 3]] == pKeys[[2]], on++; out[[3 on]] = 6; out[[3 on + 1]] = pSpecs[[4 i - 1]]; out[[3 on + 2]] = 0];
										If[pSpecs[[4 i - 2]] == 3, t++];
										pMin = fr[[base + 7]]; pRbp = fr[[base + 2]]; pPlain = fr[[base + 8]]; mode = 1,
										on++;
										Which[
											fr[[base + 3]] == pKeys[[2]], out[[3 on]] = 7; out[[3 on + 1]] = fr[[base + 5]]; out[[3 on + 2]] = 0,
											fr[[base + 3]] == pKeys[[3]], out[[3 on]] = 26; out[[3 on + 1]] = fr[[base + 5]]; out[[3 on + 2]] = 0,
											True, out[[3 on]] = 5; out[[3 on + 1]] = fr[[base + 4]]; out[[3 on + 2]] = fr[[base + 5]]];
										sp--; mode = 3],
								ft == 5,
									If[ pTok[[5 t - 2]] == 11,
										t++; brackets--; on++; out[[3 on]] = 9; out[[3 on + 1]] = pHeads[[3]]; out[[3 on + 2]] = 1; sp--; mode = 3,
										mode = 5],
								ft == 6, fr[[base + 5]] = fr[[base + 5]] + 1; mode = 8,
								ft == 7, on++; out[[3 on]] = 23; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; sp--; mode = 3,
								ft == 8,
									sp--; base = 8 (sp - 1);
									If[fr[[base + 1]] == 9, mode = 12, fr[[base + 2]] = fr[[base + 2]] + 1; mode = 13],
								(* a span's or a compound's operand that could not be left out *)
								ft == 9, mode = 12,
								ft == 10, fr[[base + 2]] = fr[[base + 2]] + 1; mode = 13,
								(* after a ~ and its middle operand: the second ~; anything else, a postfix operator
									that binds less tightly than ~ or a ; too, as a notebook reads a ~ f & ~ b, reading on
									as the kernel's reader does, to a closer or a comma, where it stops, else to the end
									of the source *)
								ft == 11,
									If[ fr[[base + 2]] == 1,
										Which[
											pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[8]] && ! (brackets == 0 && nls[[t]] == 1),
												t++; fr[[base + 2]] = 2; pMin = fr[[base + 4]]; pRbp = fr[[base + 3]]; pPlain = fr[[base + 5]]; mode = 1,
											True,
												(* reading goes on to a closer or a comma outside brackets, no Wolfram Language,
													else the end *)
												x = 0; tt = t;
												While[ pTok[[5 tt - 2]] != 0 && ! (x == 0 && (pTok[[5 tt - 2]] == 11 || pTok[[5 tt - 2]] == 13 || pTok[[5 tt - 2]] == 15 || pTok[[5 tt - 2]] == 17 || pTok[[5 tt - 2]] == 18)),
													If[pTok[[5 tt - 2]] == 10 || pTok[[5 tt - 2]] == 12 || pTok[[5 tt - 2]] == 14 || pTok[[5 tt - 2]] == 16, x++];
													If[pTok[[5 tt - 2]] == 11 || pTok[[5 tt - 2]] == 13 || pTok[[5 tt - 2]] == 15 || pTok[[5 tt - 2]] == 17, x--];
													tt++];
												If[tt > far, far = tt]; mode = 5],
										on++; out[[3 on]] = 17; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; sp--; mode = 3],
								ft == 12,
									If[ fr[[base + 2]] == 1,
										Which[
											(brackets == 0 && nls[[t]] == 1) || pTok[[5 t - 2]] != 9, mode = 5,
											pTok[[5 t - 1]] == pSpecial[[5]] && t < n && pTok[[5 t + 3]] == 9 && pTok[[5 t + 4]] == pSpecial[[7]],
												t += 2; on++; out[[3 on]] = 20; out[[3 on + 1]] = 3; out[[3 on + 2]] = 0; sp--; mode = 3,
											pTok[[5 t - 1]] == pSpecial[[10]],
												t++; fr[[base + 2]] = 2; pMin = pSpecial[[20]]; pRbp = 0; pPlain = 0; mode = 1,
											pTok[[5 t - 1]] == pSpecial[[5]],
												t++; fr[[base + 2]] = 3; pMin = pSpecial[[20]]; pRbp = 0; pPlain = 0; mode = 1,
											pTok[[5 t - 1]] == pSpecial[[6]],
												t++; on++; out[[3 on]] = 20; out[[3 on + 1]] = 3; out[[3 on + 2]] = 0; sp--; mode = 3,
											True, mode = 5],
										on++; out[[3 on]] = 20; out[[3 on + 1]] = If[fr[[base + 2]] == 2, 1, 2]; out[[3 on + 2]] = 0; sp--; mode = 3],
								(* an integral's operand, as a notebook reads it: its factors, a parenthesis round them
									all as none, end in as many differentials as the integral has signs, and no other
									factor is one, a differential in parentheses none; else no Wolfram Language. Each
									factor is stepped over by the values its instructions take and give *)
								ft == 13,
									q = on; ok = 0;
									While[out[[3 q]] == 9 && out[[3 q + 1]] == pHeads[[3]], q--];
									Which[
										out[[3 q]] == 2 && (out[[3 q + 1]] == pHeads[[9]] || out[[3 q + 1]] == pHeads[[10]]),
											ok = If[fr[[base + 3]] == 1, 1, 0],
										out[[3 q]] == 5 && out[[3 q + 1]] == pHeads[[8]],
											nf = out[[3 q + 2]]; q--; kk = 0; trail = 1; ok = 1;
											While[ nf > 0 && ok == 1,
												If[ out[[3 q]] == 2 && (out[[3 q + 1]] == pHeads[[9]] || out[[3 q + 1]] == pHeads[[10]]),
													If[trail == 1, kk++, ok = 0],
													trail = 0];
												need = 1;
												While[ need > 0,
													c = out[[3 q]];
													need += Which[
														c == 1 || c == 6 || c == 11 || c == 12 || c == 13 || c == 28, 0,
														c == 4 || c == 21 || c == 23, 2,
														c == 5, out[[3 q + 2]],
														c == 7 || c == 14 || c == 18 || c == 19 || c == 26, out[[3 q + 1]],
														c == 8 || c == 10 || c == 15, out[[3 q + 1]] + 1,
														c == 9, If[out[[3 q + 1]] == pHeads[[3]], 1, out[[3 q + 2]]],
														c == 17, 3,
														c == 20, If[out[[3 q + 1]] == 3, 2, 3],
														True, 1] - If[c == 6, 0, 1];
													q--];
												nf--];
											If[kk != fr[[base + 3]], ok = 0],
										True, ok = 0];
									If[ ok == 0, If[t > far, far = t]; mode = 5,
										on++; out[[3 on]] = 24; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = fr[[base + 3]]; sp--; mode = 3],
								(* a query's expression: a word of one token its text, and after ?? nothing else *)
								ft == 15,
									x = If[on == fr[[base + 4]] + 1 && t == fr[[base + 3]] + 1 && out[[3 on]] == 1, 1, 0];
									If[x == 1 && (out[[3 on + 1]] <= 4 || out[[3 on + 1]] == 6 || out[[3 on + 1]] == 7), out[[3 on + 1]] = 100];
									If[ fr[[base + 2]] == 1 && x == 0, mode = 5,
										on++; out[[3 on]] = 29; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = 0; sp--; mode = 3],
								(* a message name's operand: a word of one token, a name, a number, a blank, a slot
									or a %, its text; another :: after it, another operand *)
								ft == 14,
									If[ on == fr[[base + 4]] + 1 && t == fr[[base + 3]] + 1 && out[[3 on]] == 1 &&
											(out[[3 on + 1]] <= 4 || out[[3 on + 1]] == 6 || out[[3 on + 1]] == 7),
										out[[3 on + 1]] = 100];
									fr[[base + 2]] = fr[[base + 2]] + 1;
									If[ pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[4]] && ! (brackets == 0 && nls[[t]] == 1),
										t++; fr[[base + 3]] = t; fr[[base + 4]] = on; pMin = pSpecial[[17]]; pRbp = 100000; pPlain = 0; mode = 1,
										on++; out[[3 on]] = 14; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = 0; sp--; mode = 3],
								True, mode = 5]],
					(* no Wolfram Language: back to a pattern's name or an operand left out, else the end *)
					mode == 5,
						If[t > far, far = t];
						While[sp > 0 && fr[[8 (sp - 1) + 1]] != 7 && fr[[8 (sp - 1) + 1]] != 8, sp--];
						If[ sp == 0,
							status = 1; mode = 99,
							base = 8 (sp - 1);
							t = fr[[base + 2]]; on = fr[[base + 3]]; brackets = fr[[base + 4]];
							If[ fr[[base + 1]] == 7,
								sp--; mode = 3,
								sp--; base = 8 (sp - 1);
								Which[
									fr[[base + 1]] == 9 && fr[[base + 2]] == 2,
										t--; se = t; on++; out[[3 on]] = 18; out[[3 on + 1]] = fr[[base + 3]]; out[[3 on + 2]] = 0; sp--; mode = 3,
									fr[[base + 1]] == 9,
										on++; out[[3 on]] = 12; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 12,
									True,
										on++; out[[3 on]] = 11; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; fr[[base + 2]] = fr[[base + 2]] + 1; mode = 13]]],
					(* a bracket's items: none before the closer, else the first *)
					mode == 6,
						base = 8 (sp - 1);
						If[pTok[[5 t - 2]] == fr[[base + 3]] && (fr[[base + 3]] != 9 || pTok[[5 t - 1]] == fr[[base + 4]]), mode = 9, mode = 7],
					(* an item: Null before a comma or the closer, the Null a comma leaves, else an expression *)
					mode == 7,
						base = 8 (sp - 1);
						If[ pTok[[5 t - 2]] == 18 || (pTok[[5 t - 2]] == fr[[base + 3]] && (fr[[base + 3]] != 9 || pTok[[5 t - 1]] == fr[[base + 4]])),
							on++; out[[3 on]] = 11; out[[3 on + 1]] = 1; out[[3 on + 2]] = 0; fr[[base + 5]] = fr[[base + 5]] + 1; mode = 8,
							pMin = 0; pRbp = 0; pPlain = 0; mode = 1],
					(* after an item: a comma and the next, else the closer *)
					mode == 8,
						If[pTok[[5 t - 2]] == 18, t++; mode = 7, mode = 9],
					(* the closer, and the bracket's node *)
					mode == 9,
						base = 8 (sp - 1); bt = fr[[base + 2]]; cnt = fr[[base + 5]];
						Which[
							bt == 2, If[pTok[[5 t - 2]] == 13 && t < n && pTok[[5 t + 3]] == 13, t += 2; ok = 1, If[pTok[[5 t - 2]] == 13 && t < n, t++]; ok = 0],
							pTok[[5 t - 2]] == fr[[base + 3]] && (fr[[base + 3]] != 9 || pTok[[5 t - 1]] == fr[[base + 4]]), t++; ok = 1,
							True, ok = 0];
						If[ ok == 0, mode = 5,
							brackets--; on++;
							Which[
								bt == 1, out[[3 on]] = 8; out[[3 on + 1]] = cnt; out[[3 on + 2]] = 0,
								bt == 2 || bt == 6, out[[3 on]] = 10; out[[3 on + 1]] = cnt; out[[3 on + 2]] = 0,
								bt == 3, out[[3 on]] = 9; out[[3 on + 1]] = pHeads[[4]]; out[[3 on + 2]] = cnt,
								bt == 4, out[[3 on]] = 9; out[[3 on + 1]] = pHeads[[5]]; out[[3 on + 2]] = cnt,
								bt == 5, out[[3 on]] = 9; out[[3 on + 1]] = fr[[base + 6]]; out[[3 on + 2]] = cnt,
								True, out[[3 on]] = 15; out[[3 on + 1]] = cnt; out[[3 on + 2]] = 0];
							sp--; mode = 3],
					(* a ;; and the span's frame *)
					mode == 10,
						t++;
						sp++; base = 8 (sp - 1); fr[[base + 1]] = 9; fr[[base + 2]] = 1; fr[[base + 3]] = 1;
						mode = 11,
					(* a span's operand, All where the first is left out; where the second is, the span ends
						before its ;;, which begins a span of its own. A prefix operator, a << or an integral begins
						one that is not left out. *)
					mode == 11,
						base = 8 (sp - 1); o = pTok[[5 t - 1]];
						Which[
							pTok[[5 t - 2]] == 9 && (pPrefix[[2 o + 1]] > 0 || o == pSpecial[[9]] || pIntegrals[[o + 1]] > 0) && ! (brackets == 0 && nls[[t]] == 1),
								pMin = pSpecial[[17]]; pRbp = 0; pPlain = 0; mode = 1,
							! ((pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[2]]) || (brackets == 0 && nls[[t]] == 1) || pTok[[5 t - 2]] == 0),
								sp++; base = 8 (sp - 1); fr[[base + 1]] = 8; fr[[base + 2]] = t; fr[[base + 3]] = on; fr[[base + 4]] = brackets;
								pMin = pSpecial[[17]]; pRbp = 0; pPlain = 0; mode = 1,
							fr[[base + 2]] == 2,
								t--; se = t; on++; out[[3 on]] = 18; out[[3 on + 1]] = fr[[base + 3]]; out[[3 on + 2]] = 0; sp--; mode = 3,
							True,
								on++; out[[3 on]] = 12; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 12],
					(* after a span's operand: a second ;; and its operand, else the span *)
					mode == 12,
						base = 8 (sp - 1); fr[[base + 3]] = fr[[base + 3]] + 1;
						If[ fr[[base + 2]] == 1 && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[2]] && ! (brackets == 0 && nls[[t]] == 1),
							t++; fr[[base + 2]] = 2; mode = 11,
							on++; out[[3 on]] = 18; out[[3 on + 1]] = fr[[base + 3]]; out[[3 on + 2]] = 0; sp--; se = t; mode = 3],
					(* a ; and its operand, Null where it is left out, but for one a prefix operator, a << or
						an integral begins, else the compound *)
					mode == 13,
						If[ pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[3]] && ! (brackets == 0 && nls[[t]] == 1),
							t++; o = pTok[[5 t - 1]];
							Which[
								(* Null at the end of a line, of the source, and before a ? or a ;;, a pattern test or a
									span of the compound, as a notebook reads a; ?b and a; ;; *)
								(brackets == 0 && nls[[t]] == 1) || pTok[[5 t - 2]] == 0 || (pTok[[5 t - 2]] == 9 && (o == pSpecial[[14]] || o == pSpecial[[2]])),
									on++; out[[3 on]] = 11; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0;
									base = 8 (sp - 1); fr[[base + 2]] = fr[[base + 2]] + 1,
								pTok[[5 t - 2]] == 9 && (pPrefix[[2 o + 1]] > 0 || o == pSpecial[[9]] || pIntegrals[[o + 1]] > 0),
									pMin = pSpecial[[18]]; pRbp = 0; pPlain = 0; mode = 1,
								True,
									sp++; base = 8 (sp - 1); fr[[base + 1]] = 8; fr[[base + 2]] = t; fr[[base + 3]] = on; fr[[base + 4]] = brackets;
									pMin = pSpecial[[18]]; pRbp = 0; pPlain = 0; mode = 1],
							base = 8 (sp - 1);
							on++; out[[3 on]] = 19; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = 0; sp--; mode = 3],
					True, status = 1; If[t > far, far = t]; mode = 99]];
			out[[1]] = status; out[[2]] = If[status == 1 || status == 3, far, on];
			If[status != 0, out[[3]] = stmt];
			Take[out, If[status == 0, 2 + 3 on, 3]]]]]]

(* the parser run here, fixed at its first use *)
fastParseFunction := fastParseFunction = typedFunction[fastParse, $fastParseDeclaration]

(* ::Section:: *)
(*The typed lines*)

(* The parts of a segment, typed code over packed integers as the lexer and the parser are: the
	codes and three zeros after them, the lexer's tokens, the program, the count of tokens that
	may warn before each token, the character classes, the newline long names {length, codes,
	...}, the source's position of each
	character of the source read without its line continuations ({0} where it has none), and
	{statements read, where reading stops, 1 if a statement the grammar read is pending, the
	segment, how reading stops: 0 at the end, 3 at a failure, 4 at a statement the grammar reads,
	the segment's offset in the source read, the source's length, where the pending statement
	begins, how many positions the source read keeps} -> {rows, the slot after the lines, then each
	row {kind, start, next, segment, first instruction, last, first token, last, warnings}}, its
	start and next the source's positions. A gap's line breaks are its newlines and newline long
	names outside comments; the first after a statement, or after the one pending, ends its line,
	else the token after it does. The others, as blank lines, the LF of a CRLF and a line of a
	comment alone, only part statements, as Get reads them, where Wolfram 15's ToExpression reads
	each as a Null [W15 bug]: a row's next is the next row's start. The last row is where reading
	stops, or the end, a source with no statement that row alone. *)
$fastLinesDeclaration = FunctionDeclaration[fastLines,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{lnCodes, lnLexed, lnProg, lnWarn, lnClasses, lnNames, lnKept, lnParams},
		Native`UncheckedBlock[Module[{nUse = lnParams[[1]], end = lnParams[[2]], pending = lnParams[[3]], seg = lnParams[[4]], stop = lnParams[[5]], offset = lnParams[[6]],
				srcLen = lnParams[[7]], pendingStart = lnParams[[8]], keptLen = lnParams[[9]], n = Length[lnCodes] - 3,
				js, nS = 0, j = 0, g = 0, lo = 0, hi = 0, p = 0, c = 0, depth = 0, k = 0, a = 0, len = 0, match = 0, q = 0,
				pass = 1, total = 0, out, rows = 0, slot = 1, breaks = 0, at = 0, ti = 0, fI = 0, lI = 0, fT = 0, tA = 0, kind = 0, base = 0,
				post = 1, r = 0, col = 0, v = 0},
			js = Table[0, {nUse + 1}];
			j = 1;
			While[ j <= lnProg[[2]] && nS < nUse,
				If[lnProg[[3 j]] == 25, nS++; js[[nS]] = j];
				j++];
			out = Table[0, {2}];
			While[ pass <= 2,
				If[ pass == 2,
					out = Table[0, {2 + 9 (total + post)}]];
				rows = 0; slot = 1;
				g = 1;
				While[ g <= nS + 1,
					lo = If[g == 1, 1, lnLexed[[5 lnProg[[3 js[[g - 1]] + 2]] - 4]]];
					hi = If[g <= nS, lnLexed[[5 lnProg[[3 js[[g]] + 1]]]], end];
					(* the row the gap's first break ends: the pending statement's for the first gap,
						else the statement's before it, else a Null's *)
					breaks = 0;
					p = lo; depth = 0;
					While[ p < hi,
						c = lnCodes[[p]];
						at = 0;
						Which[
							c == 40 && p < n && lnCodes[[p + 1]] == 42,
								If[p + 1 < hi, depth++; p++],
							c == 42 && p < n && lnCodes[[p + 1]] == 41,
								If[depth > 0 && p + 1 < hi, depth--; p++],
							depth > 0, at = 0,
							c == 92 && p < n && lnCodes[[p + 1]] == 91,
								k = p + 2;
								While[k < hi && lnCodes[[k]] != 93, k++];
								a = 1; match = 0;
								While[ match == 0 && a <= Length[lnNames],
									len = lnNames[[a]];
									If[ len == k - p - 2,
										match = 1; q = 1;
										While[match == 1 && q <= len, If[lnNames[[a + q]] != lnCodes[[p + 1 + q]], match = 0]; q++]];
									a += len + 1];
								If[match == 1, at = k + 1];
								p = k,
							lnClasses[[Min[Max[c, 0], 65535] + 1]] == 4, at = p + 1,
							True, at = 0];
						(* the first break after a statement ends its row; any other makes none *)
						If[ at > 0,
							breaks++;
							kind = If[breaks == 1 && (g > 1 || pending == 1), If[g == 1, 5, 1], 2];
							If[ kind != 2, If[pass == 1, total++,
								rows++; base = 2 + 9 (rows - 1);
								out[[base + 1]] = kind; out[[base + 2]] = slot; out[[base + 3]] = at;
								If[ kind == 1,
									lI = js[[g - 1]]; fI = If[g == 2, 1, js[[g - 2]] + 1]; fT = lnProg[[3 lI + 1]]; tA = lnProg[[3 lI + 2]];
									out[[base + 4]] = seg; out[[base + 5]] = fI; out[[base + 6]] = lI; out[[base + 7]] = fT; out[[base + 8]] = tA - 1;
									out[[base + 9]] = lnWarn[[tA]] - lnWarn[[fT]]];
								slot = at]]];
						p++];
					(* a statement, or the one pending, whose gap holds no break: the token after it ends its line *)
					If[ breaks == 0 && (g > 1 || pending == 1),
						kind = If[g == 1, 5, 1];
						If[pass == 1, total++,
							rows++; base = 2 + 9 (rows - 1);
							out[[base + 1]] = kind; out[[base + 2]] = slot; out[[base + 3]] = hi;
							If[ kind == 1,
								lI = js[[g - 1]]; fI = If[g == 2, 1, js[[g - 2]] + 1]; fT = lnProg[[3 lI + 1]]; tA = lnProg[[3 lI + 2]];
								out[[base + 4]] = seg; out[[base + 5]] = fI; out[[base + 6]] = lI; out[[base + 7]] = fT; out[[base + 8]] = tA - 1;
								out[[base + 9]] = lnWarn[[tA]] - lnWarn[[fT]]];
							slot = hi]];
					g++];
				pass++];
			(* where reading stops, or the end *)
			out[[2 + 9 rows + 1]] = If[stop == 0, 6, stop]; out[[2 + 9 rows + 2]] = slot; out[[2 + 9 rows + 3]] = slot;
			(* the positions the source's *)
			r = 1;
			While[ r <= rows + post,
				col = 2;
				While[ col <= 3,
					v = out[[2 + 9 (r - 1) + col]] + offset;
					If[keptLen > 0, v = If[v <= keptLen, lnKept[[v]], srcLen + v - keptLen]];
					out[[2 + 9 (r - 1) + col]] = v;
					col++];
				r++];
			If[pending == 1, out[[2 + 2]] = pendingStart];
			out[[1]] = rows + post; out[[2]] = slot;
			out]]]]

fastLinesFunction := fastLinesFunction = typedFunction[fastLines, $fastLinesDeclaration]
$fastNoKept = Developer`ToPackedArray[{0}]

(* ::Section:: *)
(*The typed led indices and warning tokens*)

(* Each token's led spec index, typed code over packed integers: the lexer's tokens, the spec
	index of each kind and of each operator, by kind + 1 and operator + 1, and {the operator kind,
	=, ., the Unset spec index} -> the index of each token, that of the operator it is or of its
	kind, Unset's for an = before a . *)
$fastLedDeclaration = FunctionDeclaration[fastLed,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{ldLexed, ldKinds, ldOps, ldParams},
		Native`UncheckedBlock[Module[{n = ldLexed[[2]], out, t = 1, u = 1, kind = 0, op = 0},
			out = Table[0, {n}];
			While[ t <= n,
				kind = ldLexed[[5 t - 2]]; op = ldLexed[[5 t - 1]];
				out[[t]] = ldKinds[[kind + 1]] + If[kind == ldParams[[1]], ldOps[[op + 1]], 0];
				u = If[t < n, t + 1, 1];
				If[op == ldParams[[2]] && ldLexed[[5 u - 1]] == ldParams[[3]] && ldLexed[[5 u - 2]] == ldParams[[1]], out[[t]] = ldParams[[4]]];
				t++];
			out]]]]

fastLedFunction := fastLedFunction = typedFunction[fastLed, $fastLedDeclaration]

(* The tokens of a lexed source a statement's warning may come from, typed code over packed
	integers: the codes, the lexer's tokens, the kinds that open a bracket's items and that close
	them, by kind + 1, the operators that do, by operator + 1, and {the operator kind, the comma
	kind, the string kind} -> {how many, those tokens, then for each token t how many come before
	it}: a comma after a token that opens a bracket or before one that closes it, a comma or the
	end, and a string with a \ in it. *)
$fastWarnDeclaration = FunctionDeclaration[fastWarn,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{wnCodes, wnLexed, wnOpenKinds, wnCloseKinds, wnOpenOps, wnCloseOps, wnParams},
		Native`UncheckedBlock[Module[{n = wnLexed[[2]], len = Length[wnCodes], marks, out, t = 1, u = 0, kind = 0, flag = 0, m = 0, p = 0, e = 0, before = 0, top = Length[wnOpenOps] - 1},
			marks = Table[0, {n}];
			While[ t <= n,
				kind = wnLexed[[5 t - 2]];
				flag = 0;
				If[ kind == wnParams[[2]],
					u = Max[t - 1, 1];
					If[ wnOpenKinds[[wnLexed[[5 u - 2]] + 1]] == 1 ||
							(wnLexed[[5 u - 2]] == wnParams[[1]] && wnOpenOps[[Min[Max[wnLexed[[5 u - 1]], 0], top] + 1]] == 1), flag = 1];
					u = Min[t + 1, n];
					If[ wnCloseKinds[[wnLexed[[5 u - 2]] + 1]] == 1 ||
							(wnLexed[[5 u - 2]] == wnParams[[1]] && wnCloseOps[[Min[Max[wnLexed[[5 u - 1]], 0], top] + 1]] == 1), flag = 1]];
				If[ kind == wnParams[[3]],
					p = wnLexed[[5 t]]; e = Min[wnLexed[[5 t + 1]], len + 1];
					While[p < e && flag == 0, If[wnCodes[[p]] == 92, flag = 1]; p++]];
				If[flag == 1, marks[[t]] = 1; m++];
				t++];
			out = Table[0, {1 + m + n + 1}];
			out[[1]] = m;
			t = 1; u = 1; before = 0;
			While[ t <= n,
				out[[1 + m + t]] = before;
				If[marks[[t]] == 1, out[[1 + u]] = t; u++; before++];
				t++];
			out[[1 + m + n + 1]] = before;
			out]]]]

fastWarnFunction := fastWarnFunction = typedFunction[fastWarn, $fastWarnDeclaration]

(* ::Section:: *)
(*The typed statement ranges and leaves*)

(* Each statement of a program read whole, typed code over packed integers: the program -> {how
	many, then for each its first instruction, its last, its first token and the token after it} *)
$fastRangesDeclaration = FunctionDeclaration[fastRanges,
	Typed[{"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{rgProg},
		Native`UncheckedBlock[Module[{n = Min[rgProg[[2]], Quotient[Length[rgProg] - 2, 3]], count = 0, j = 1, k = 0, first = 1, out},
			While[j <= n, If[rgProg[[3 j]] == 25, count++]; j++];
			out = Table[0, {1 + 4 count}];
			out[[1]] = count;
			j = 1;
			While[ j <= n,
				If[ rgProg[[3 j]] == 25,
					out[[2 + 4 k]] = first; out[[3 + 4 k]] = j; out[[4 + 4 k]] = rgProg[[3 j + 1]]; out[[5 + 4 k]] = rgProg[[3 j + 2]];
					k++; first = j + 1];
				j++];
			out]]]]

fastRangesFunction := fastRangesFunction = typedFunction[fastRanges, $fastRangesDeclaration]

(* The leaves of a program, its instructions of code 1, typed code over packed integers: the
	program and the lexer's tokens -> {how many, the instructions, 1 if their tokens come in order,
	then each one's kind, its token, its mark, 1 for a number literal, then for each instruction
	how many leaves come before it, and last the lengths to cut the codes from the first leaf by:
	each leaf's text and the gap after it} *)
$fastLeafDeclaration = FunctionDeclaration[fastLeafCodes,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{lfProg, lfLexed},
		Native`UncheckedBlock[Module[{n = Min[lfProg[[2]], Quotient[Length[lfProg] - 2, 3]], m = 0, j = 1, k = 0, t = 0, base = 0, ordered = 1, out},
			While[j <= n, If[lfProg[[3 j]] == 1, m++]; j++];
			out = Table[0, {3 + 3 m + n + 1 + Max[2 m - 1, 0]}];
			out[[1]] = m; out[[2]] = n;
			j = 1;
			While[ j <= n,
				out[[3 + 3 m + j]] = k;
				If[ lfProg[[3 j]] == 1,
					k++;
					out[[3 + k]] = lfProg[[3 j + 1]];
					out[[3 + m + k]] = lfProg[[3 j + 2]];
					out[[3 + 2 m + k]] = If[lfProg[[3 j + 1]] == 3 || lfProg[[3 j + 1]] == 4, 1, 0]];
				j++];
			out[[3 + 3 m + n + 1]] = k;
			base = 3 + 3 m + n + 1;
			k = 1;
			While[ k <= m,
				t = out[[3 + m + k]];
				out[[base + 2 k - 1]] = lfLexed[[5 t + 1]] - lfLexed[[5 t]];
				If[ k < m,
					out[[base + 2 k]] = lfLexed[[5 out[[3 + m + k + 1]]]] - lfLexed[[5 t + 1]];
					If[out[[base + 2 k]] < 0, ordered = 0]];
				k++];
			out[[3]] = ordered;
			out]]]]

fastLeafFunction := fastLeafFunction = typedFunction[fastLeafCodes, $fastLeafDeclaration]

(* The parts of a program read whole, for a builder of its own, typed code over packed integers:
	the program, the lexer's tokens and the parts fastLines gives -> {0, the program's length, the
	program, then the parts: how many Nulls a comma leaves, how many leaves, how many parts but the end, then each leaf's kind, each one's mark, 1
	for a number literal, each one's first character and the character after its last, then for
	each part {first instruction, last, first leaf, last}, a statement with no leaf's last the one
	before its first, and {0, 0, 0, 0} for a Null} *)
$fastWholeDeclaration = FunctionDeclaration[fastWhole,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
	Function[{whProg, whLexed, whLines},
		Native`UncheckedBlock[Module[{n = Min[whProg[[2]], Quotient[Length[whProg] - 2, 3]], lp = Length[whProg], m = 0, nulls = 0, parts = whLines[[1]] - 1, j = 1,
				k = 0, r = 1, t = 0, row = 0, at = 0, base = 0, before, out},
			While[j <= n, If[whProg[[3 j]] == 1, m++]; j++];
			before = Native`UncheckedArray[0, n + 1];
			out = Native`UncheckedArray[0, 2 + lp + 3 + 4 m + 4 parts];
			out[[1]] = 0; out[[2]] = lp;
			j = 1;
			While[j <= lp, out[[2 + j]] = whProg[[j]]; j++];
			at = 2 + lp;
			j = 1;
			While[ j <= n,
				before[[j]] = k;
				Which[
					whProg[[3 j]] == 1,
						k++; t = whProg[[3 j + 2]];
						out[[at + 3 + k]] = whProg[[3 j + 1]];
						out[[at + 3 + m + k]] = If[whProg[[3 j + 1]] == 3 || whProg[[3 j + 1]] == 4, 1, 0];
						out[[at + 3 + 2 m + k]] = whLexed[[5 t]];
						out[[at + 3 + 3 m + k]] = whLexed[[5 t + 1]],
					whProg[[3 j]] == 11 && whProg[[3 j + 1]] == 1, nulls++];
				j++];
			before[[n + 1]] = k;
			base = at + 3 + 4 m;
			While[ r <= parts,
				row = 2 + 9 (r - 1);
				If[ whLines[[row + 1]] == 1,
					out[[base + 4 r - 3]] = whLines[[row + 5]]; out[[base + 4 r - 2]] = whLines[[row + 6]];
					out[[base + 4 r - 1]] = before[[whLines[[row + 5]]]] + 1; out[[base + 4 r]] = before[[whLines[[row + 6]] + 1]],
					out[[base + 4 r - 3]] = 0; out[[base + 4 r - 2]] = 0; out[[base + 4 r - 1]] = 0; out[[base + 4 r]] = 0];
				r++];
			out[[at + 1]] = nulls; out[[at + 2]] = m; out[[at + 3]] = parts;
			out]]]]

fastWholeFunction := fastWholeFunction = typedFunction[fastWhole, $fastWholeDeclaration]

$fastNewlineNames := $fastNewlineNames = Developer`ToPackedArray[Flatten[Map[Join[{StringLength[#]}, ToCharacterCode[#]] &, $heldNewlineNames]]]

(* ::Section:: *)
(*The typed program*)

(* The program of a source read whole, typed code over packed integers that calls the lexer, the
	parser, the lines and the parts each once, with nothing between them: the codes and three zeros
	after them, and the tables the five take -> {0, the program's length, the program, then the
	parts}, as WolframLanguageProgram gives them; {1} for a source that has none; {2} for one the
	stages alone do not settle, a line continuation, a token that is two or a long name in a
	string, which WolframLanguageProgram reads by its stages. *)
$fastProgramDeclaration = FunctionDeclaration[fastProgram,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} ->
		"PackedArray"::["MachineInteger", 1]] @
	Function[{pgCodes, pgClasses, pgOp1, pgOp2, pgOp3, pgLongOps, pgSpecial, pgKindSpecs, pgOpSpecs, pgLedParams, pgSpecs, pgPrefix,
			pgGroups, pgIntegrals, pgSpecialOps, pgHeads, pgKeys, pgNewlineNames},
		Native`UncheckedBlock[Module[{n = Length[pgCodes] - 3, lexed, prog, lines, flat, params, out, i = 1, t = 1, p = 0, e = 0, c = 0, k = 0, q = 0, h = 0, status = 0},
			(* codes that do not end in three zeros are the stages' to read *)
			If[n < 0, status = 2, If[pgCodes[[n + 1]] != 0 || pgCodes[[n + 2]] != 0 || pgCodes[[n + 3]] != 0, status = 2]];
			While[ i <= n,
				If[pgCodes[[i]] == 92 && i < n && (pgCodes[[i + 1]] == 10 || pgCodes[[i + 1]] == 13), status = 2];
				i++];
			lexed = If[status == 0, fastLex[pgCodes, pgClasses, pgOp1, pgOp2, pgOp3, pgLongOps, pgSpecial], Table[0, {2}]];
			If[status == 0 && lexed[[1]] != 0, status = 1];
			(* each string's escapes, as stringWarnings reads them: one that warns leaves no
				program, one of a long name is the stages' to read, and the rest are quiet:
				\ooo, \.hh, \:hhhh and \|hhhhhh, \n, \t, \r, \b and \f, and \ before
				any other character but a letter *)
			While[ status == 0 && t <= lexed[[2]],
				If[ lexed[[5 t - 2]] == 5,
					p = lexed[[5 t]] + 1; e = Min[lexed[[5 t + 1]], n + 1] - 1;
					While[ p < e && status == 0,
						If[ pgCodes[[p]] != 92, p++,
							c = If[p + 1 < e, pgCodes[[p + 1]], 0];
							Which[
								c == 0 || c == 91, status = 2,
								48 <= c <= 55, If[p + 3 < e && 48 <= pgCodes[[p + 2]] <= 55 && 48 <= pgCodes[[p + 3]] <= 55, p += 4, status = 1],
								c == 46 || c == 58 || c == 124,
									k = If[c == 46, 2, If[c == 58, 4, 6]]; q = p + 2; h = 0;
									While[ h < k && q < e && (48 <= pgCodes[[q]] <= 57 || 65 <= pgCodes[[q]] <= 70 || 97 <= pgCodes[[q]] <= 102), h++; q++];
									If[h == k, p += 2 + k, status = 1],
								65 <= c <= 90 || 97 <= c <= 122, If[c == 110 || c == 116 || c == 114 || c == 98 || c == 102, p += 2, status = 1],
								True, p += 2]]]];
				t++];
			prog = If[ status == 0,
				fastParse[lexed, fastLed[lexed, pgKindSpecs, pgOpSpecs, pgLedParams], pgSpecs, pgPrefix, pgGroups, pgIntegrals, pgSpecialOps, pgHeads, pgKeys,
					pgCodes, pgClasses],
				Table[0, {2}]];
			If[status == 0 && prog[[1]] == 3, status = 2];
			If[status == 0 && prog[[1]] != 0, status = 1];
			lines = If[ status == 0,
				params = Table[0, {9}];
				params[[1]] = prog[[2]]; params[[2]] = n + 1; params[[4]] = 1; params[[7]] = n;
				fastLines[pgCodes, lexed, prog, Table[0, {lexed[[2]] + 1}], pgClasses, pgNewlineNames, Table[0, {1}], params],
				Table[0, {2}]];
			flat = If[status == 0, fastWhole[prog, lexed, lines], Table[0, {3}]];
			If[status == 0 && flat[[3 + flat[[2]]]] > 0, status = 1];
			If[status == 0, flat, out = Table[0, {1}]; out[[1]] = status; out]]]]]

(* The program of a source string, typed code that reads its characters' codes, pads them with three
	zeros and calls fastProgram: the source and the tables fastProgram takes after the codes -> {0,
	the program's length, the program, the parts, then the n codes of the source}, all in one array,
	or fastProgram's {1} or {2}. *)
$fastProgramTextDeclaration = FunctionDeclaration[fastProgramText,
	Typed[{"String", "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} ->
		"PackedArray"::["MachineInteger", 1]] @
	Function[{ptText, ptClasses, ptOp1, ptOp2, ptOp3, ptLongOps, ptSpecial, ptKindSpecs, ptOpSpecs, ptLedParams, ptSpecs, ptPrefix,
			ptGroups, ptIntegrals, ptSpecialOps, ptHeads, ptKeys, ptNewlineNames},
		Native`UncheckedBlock[Module[{codes, n = 0, padded, flat, out, m = 0, i = 1},
			codes = ToCharacterCode[ptText];
			n = Length[codes];
			padded = Native`UncheckedArray[0, n + 3];
			While[i <= n, padded[[i]] = codes[[i]]; i++];
			padded[[n + 1]] = 0; padded[[n + 2]] = 0; padded[[n + 3]] = 0;
			flat = fastProgram[padded, ptClasses, ptOp1, ptOp2, ptOp3, ptLongOps, ptSpecial, ptKindSpecs, ptOpSpecs, ptLedParams, ptSpecs, ptPrefix,
				ptGroups, ptIntegrals, ptSpecialOps, ptHeads, ptKeys, ptNewlineNames];
			If[ flat[[1]] != 0, flat,
				m = Length[flat];
				out = Native`UncheckedArray[0, m + n];
				i = 1; While[i <= m, out[[i]] = flat[[i]]; i++];
				i = 1; While[i <= n, out[[m + i]] = codes[[i]]; i++];
				out]]]]]

(* the typed program run here: the definition a compiler of typed code gave fastProgramText, where
	one did; else None, and flatProgram reads by the stages, each compiled on its own *)
fastProgramTextFunction := fastProgramTextFunction = If[DownValues[fastProgramText] =!= {} || OwnValues[fastProgramText] =!= {}, fastProgramText, None]

(* the tables fastProgram takes after the codes, made once *)
$fastProgramTables := $fastProgramTables = {$fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial, $fastKindSpecIndex, $fastOpSpecIndex,
	$fastLedParams, $fastSpecTable, $fastPrefixArray, $fastGroupArray, $fastIntegralArray, $fastSpecialArray, $fastHeadCodeArray, $fastKeyCodeArray,
	$fastNewlineNames}

(* ::Section:: *)
(*The typed parser's tables*)

(* the heads, each by the position of its name; the chain keys likewise *)
$fastHeadNames := $fastHeadNames = DeleteDuplicates[Join[{"Minus", "Unset", "Paren", "List", "Association", "NotNot", "Optional"},
	$fastSpecList[[All, 3]], Values[$fastPrefixTable][[All, 2]], Values[$fastGroupTable][[All, 2]]]]
fastHeadCode[name_String] := First[FirstPosition[$fastHeadNames, name, {0}, {1}]]
$fastKeyNames := $fastKeyNames = DeleteDuplicates[Join[{"Plus", "Relation", "Divisible"},
	Map[fastChainKey, Select[$fastSpecList, #[[2]] === "InfixN" &]]]]
fastKeyCode[key_String] := First[FirstPosition[$fastKeyNames, key, {0}, {1}]]
$fastFixityCodes = <|"InfixL" -> 1, "InfixR" -> 2, "InfixN" -> 3, "Postfix" -> 4, "Call" -> 5, "Derivative" -> 6, "Ternary" -> 7,
	"MessageName" -> 8, "Span" -> 9, "Compound" -> 10, "TagSet" -> 11, "Put" -> 12, "Unset" -> 13, "LongPart" -> 14|>

(* each spec: precedence, fixity (15 the product an operand begins), head
	and chain key *)
$fastSpecTable := $fastSpecTable = Developer`ToPackedArray[Flatten[Map[{#[[1]], If[Length[#] >= 5, 15, $fastFixityCodes[#[[2]]]], fastHeadCode[#[[3]]],
	If[#[[2]] === "InfixN", fastKeyCode[fastChainKey[#]], 0]} &, $fastSpecList]]]
(* by operator, from 0: the prefix ones' precedence and head, the
	brackets' closer and head, and the integral *)
$fastPrefixArray := $fastPrefixArray = Developer`ToPackedArray[Flatten[Table[
	If[KeyExistsQ[$fastPrefixTable, o], {$fastPrefixTable[o][[1]], fastHeadCode[$fastPrefixTable[o][[2]]]}, {0, 0}], {o, 0, $fastNotId}]]]
$fastGroupArray := $fastGroupArray = Developer`ToPackedArray[Flatten[Table[
	If[KeyExistsQ[$fastGroupTable, o], {$fastGroupTable[o][[1]], fastHeadCode[$fastGroupTable[o][[2]]]}, {0, 0}], {o, 0, $fastNotId}]]]
$fastIntegralList := $fastIntegralList = Values[$fastIntegralTable]
$fastIntegralArray := $fastIntegralArray = Developer`ToPackedArray[Table[
	If[KeyExistsQ[$fastIntegralTable, o], First[FirstPosition[Keys[$fastIntegralTable], o]], 0], {o, 0, $fastNotId}]]
(* the operators and precedences the parser names, the heads it emits and
	the chain keys it tells *)
$fastSpecialArray := $fastSpecialArray = Developer`ToPackedArray[Join[
	{$fastColon, $fastSemiSemi, $fastSemi, $fastColonColon, $fastEqual, $fastEqualDot, $fastDot, $fastTilde, $fastGet, $fastColonEqual,
	$fastMinus, $fastLongMinus, $fastRightDoubleBracket, $fastQuestion},
	{$integralPrecedence, $fastPatternColon, $fastSpanOperand, $fastCompoundOperand, $fastTagLeft, $fastTagRight, $fastOptionalColon},
	{fastSpecIndex[{$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}]}]]
$fastHeadCodeArray := $fastHeadCodeArray = Developer`ToPackedArray[fastHeadCode /@ {"Minus", "Unset", "Paren", "List", "Association", "NotNot", "Optional",
	"Times", "DifferentialD", "CapitalDifferentialD"}]
$fastKeyCodeArray := $fastKeyCodeArray = Developer`ToPackedArray[fastKeyCode /@ {"Plus", "Relation", "Divisible"}]

(* ::Section:: *)
(*The build pass*)

fastText[a_Integer, b_Integer] := FromCharacterCode[$fcodes[[a ;; b - 1]]]

$fastLeafKinds = <|1 -> "Symbol", 2 -> "Blank", 3 -> "Integer", 4 -> "Real", 5 -> "String", 6 -> "Slot", 7 -> "Out", 8 -> "File", 20 -> "Boxes", 21 -> "Freeform", 100 -> "Tag"|>

(* the held values of a postfix program, its instructions {code, a, b} one after another, and the
	kinds, texts and marks of its leaves, those fastLeafData gives: the statements'. A value on the
	stack is its expression, held, and its mark: 1 a number literal written right after where a
	minus may stand, into which the minus folds, 0 anything else, a product and a number in
	parentheses too, as a notebook reads -(2). The values wait in an association by their place on the stack, which a write does not
	copy, as it does a list of them, and the marks in a packed array. A leaf's value is made once for
	each kind and text, before the instructions run, as nothing is evaluated while the program is
	built. The names are Block's,
	not Module's, which would rewrite the body at every call, and each instruction is the rule of
	its code, a call or an operator of one or two operands its own rule. *)
fastBuild[steps_List, kinds_List, texts_List, marks_List] := Block[{vals = <||>, mk = ConstantArray[0, Length[steps] / 3 + 1], sp = 0,
		heads = <||>, hp = 0, statements = <||>, ns = 0, leafValues = fastLeafValues[kinds, texts], leafMarks = marks,
		leafIndex = 0, xs, spec},
	fastStep @@@ Partition[steps, 3];
	Values[statements]]

(* the values of the leaves of the kinds and texts: up to four each made, where a repeat costs less
	than looking for one, as nothing is evaluated while the program is built; else each kind and
	text made once, a statement's few one at a time, more by their distinct pairs *)
fastLeafValues[kinds_List, texts_List] := Which[
	Length[texts] <= 4, Table[fastLeafValue[kinds[[i]], texts[[i]]], {i, Length[texts]}],
	Length[texts] <= 64, Block[{seen = <||>}, Table[fastLeafOnce[kinds[[i]], texts[[i]]], {i, Length[texts]}]],
	True, With[{keys = Transpose[{kinds, texts}]}, With[{u = DeleteDuplicates[keys]}, Lookup[AssociationThread[u, fastLeafValue @@@ u], keys]]]]

(* a leaf's value, made at its first kind and text among those seen *)
fastLeafOnce[kind_Integer, text_String] := With[{key = {kind, text}}, If[KeyExistsQ[seen, key], seen[key], seen[key] = fastLeafValue[kind, text]]]

(* The leaves of a program, its instructions of code 1, in order, by fastLeafCodes: their kinds,
	their texts, a few one at a time, more cut from the codes in one pass where their tokens come in
	order, their marks, 1 for a number literal, and how many come before each instruction, so that
	the leaves of the instructions i to j are those from Before[[i]] + 1 to Before[[j + 1]]. *)
fastLeafData::usage = "fastLeafData[program, codes, lexed] gives the leaves of the program of the lexer's tokens lexed of the codes: \
<|\"Kinds\" -> their kinds, \"Texts\" -> their texts, \"Marks\" -> their marks, \"Before\" -> how many come before each instruction|>."
fastLeafData[program_List, codes_List, lexed_List] := leafData[fastLeafFunction[program, lexed], codes, lexed]

(* fastLeafCodes gives {m leaves, n instructions, 1 where the leaves' tokens come in order, then the
	leaves' kinds, their tokens and their marks, then for each instruction how many leaves come
	before it, and last the lengths to cut the codes from the first leaf's on by} *)
leafData::usage = "leafData[leaves, codes, lexed] gives fastLeafData's association of the array leaves that fastLeafCodes gives."
leafData[leaves_List, codes_List, lexed_List] := With[{m = First[leaves], n = leaves[[2]]},
	<|
		"Kinds" -> Take[leaves, {4, 3 + m}],
		"Texts" -> leafTexts[codes, lexed, Take[leaves, {4 + m, 3 + 2 m}], leaves[[3]] === 1, Drop[leaves, 4 + 3 m + n]],
		"Marks" -> Take[leaves, {4 + 2 m, 3 + 3 m}],
		"Before" -> Take[leaves, {4 + 3 m, 4 + 3 m + n}]
	|>
]

leafTexts::usage = "leafTexts[codes, lexed, tokens, ordered, cuts] gives the texts of the tokens of lexed: a few one at a time, more cut \
from the codes in one pass by the lengths cuts where ordered is True."
leafTexts[_List, _List, {}, _, _] := {}
leafTexts[codes_List, lexed_List, tokens_List, _, _] /; Length[tokens] <= 8 := tokenText[codes, lexed, #] & /@ tokens
leafTexts[codes_List, lexed_List, tokens_List, True, cuts_List] := Take[
	FromCharacterCode @ TakeList[Take[codes, {tokenStart[lexed, First[tokens]], tokenEnd[lexed, Last[tokens]] - 1}], cuts],
	{1, -1, 2}
]
leafTexts[codes_List, lexed_List, tokens_List, False, _] := tokenTexts[codes, tokenStarts[lexed, tokens], tokenEnds[lexed, tokens]]

tokenText::usage = "tokenText[codes, lexed, t] gives the text of token t of lexed, of the codes."
tokenText[codes_List, lexed_List, t_Integer] := FromCharacterCode @ Take[codes, {tokenStart[lexed, t], tokenEnd[lexed, t] - 1}]

(* the texts of the tokens from starts to ends in codes, in order, in one pass where they are *)
tokenTexts::usage = "tokenTexts[codes, starts, ends] gives the text of the codes from each of starts to the one before each of ends."
tokenTexts[_List, {}, {}] := {}
tokenTexts[codes_List, starts_List, ends_List] /; Length[starts] === 1 || Min[Rest[starts] - Most[ends]] >= 0 := Take[
	FromCharacterCode @ TakeList[Take[codes, {First[starts], Last[ends] - 1}], Riffle[ends - starts, Rest[starts] - Most[ends]]],
	{1, -1, 2}
]
tokenTexts[codes_List, starts_List, ends_List] := FromCharacterCode[Take[codes, #] & /@ Transpose[{starts, ends - 1}]]

(* a leaf's value by the lexer's kind of it *)
fastLeafValue[1, s_String] := heldName[s]
fastLeafValue[2, s_String] := blankExpression[s]
fastLeafValue[3 | 4, s_String] := HoldComplete @@ {numberValue[s]}
fastLeafValue[5, s_String] := HoldComplete @@ {stringValue[s]}
fastLeafValue[kind_Integer, s_String] := heldLeafValue[$fastLeafKinds[kind], s]

(* an instruction {code, a, b} of the program on the stack of fastBuild, the codes of fastParse's *)
fastStep[1, _, _] := (sp++; leafIndex++; vals[sp] = leafValues[[leafIndex]]; mk[[sp]] = leafMarks[[leafIndex]])
fastStep[8, 1, _] := (sp--; vals[sp] = heldCall[vals[sp], {vals[sp + 1]}]; mk[[sp]] = 0)
fastStep[8, 2, _] := (sp -= 2; vals[sp] = heldCall[vals[sp], {vals[sp + 1], vals[sp + 2]}]; mk[[sp]] = 0)
fastStep[8, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a; vals[sp] = heldCall[vals[sp], xs]; mk[[sp]] = 0)
fastStep[4, a_, _] := (sp--; fastBinary[a, vals[sp + 1]])
fastStep[25, _, _] := (ns++; statements[ns] = vals[sp]; sp--)
fastStep[5, a_, 2] := (sp--; vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], {vals[sp], vals[sp + 1]}]; mk[[sp]] = 0)
fastStep[5, a_, b_] := (xs = Lookup[vals, Range[sp - b + 1, sp]]; sp -= b - 1; vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], xs]; mk[[sp]] = 0)
fastStep[9, a_, b_] := If[ a === $fastParenHead, mk[[sp]] = 0,
	xs = Lookup[vals, Range[sp - b + 1, sp]]; sp -= b - 1; vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], xs]; mk[[sp]] = 0]
fastStep[19, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = symbolCall["CompoundExpression", xs]; mk[[sp]] = 0)
fastStep[2, a_, _] := (vals[sp] = If[a === $fastMinusHead, negatedHeld[vals[sp], mk[[sp]]], heldCall[heldSymbol[$fastHeadNames[[a]]], {vals[sp]}]]; mk[[sp]] = 0)
fastStep[3, a_, _] := (vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], {vals[sp]}]; mk[[sp]] = 0)
fastStep[23, _, _] := (sp--; vals[sp] = symbolCall["Pattern", {vals[sp], vals[sp + 1]}]; mk[[sp]] = 0)
fastStep[11, _, _] := (sp++; vals[sp] = heldSymbol["Null"]; mk[[sp]] = 0)
fastStep[14, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = symbolCall["MessageName", xs]; mk[[sp]] = 0)
fastStep[6, a_, _] := (hp++; heads[hp] = a)
fastStep[7, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1;
	vals[sp] = relationHeld[xs, $fastHeadNames[[Lookup[heads, Range[hp - a + 2, hp]]]]]; mk[[sp]] = 0; hp -= a - 1)
fastStep[10, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a; vals[sp] = symbolCall["Part", Prepend[xs, vals[sp]]]; mk[[sp]] = 0)
fastStep[12, _, _] := (sp++; vals[sp] = heldSymbol["All"]; mk[[sp]] = 0)
fastStep[13, _, _] := (sp++; vals[sp] = HoldComplete[1]; mk[[sp]] = 1)
fastStep[15, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a; vals[sp] = heldCall[symbolCall["TypeSpecifier", {vals[sp]}], xs]; mk[[sp]] = 0)
fastStep[16, a_, _] := (vals[sp] = heldCall[symbolCall["Derivative", {HoldComplete @@ {a}}], {vals[sp]}]; mk[[sp]] = 0)
fastStep[17, _, _] := (sp -= 2; vals[sp] = heldCall[vals[sp + 1], {vals[sp], vals[sp + 2]}]; mk[[sp]] = 0)
fastStep[18, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = symbolCall["Span", xs]; mk[[sp]] = 0)
fastStep[20, 3, _] := (sp--; vals[sp] = symbolCall["TagUnset", {vals[sp], vals[sp + 1]}]; mk[[sp]] = 0)
fastStep[20, a_, _] := (sp -= 2; vals[sp] = symbolCall[If[a === 1, "TagSetDelayed", "TagSet"], {vals[sp], vals[sp + 1], vals[sp + 2]}]; mk[[sp]] = 0)
fastStep[21, a_, _] := (sp--; vals[sp] = binaryHeld[$fastHeadNames[[a]], vals[sp], vals[sp + 1]]; mk[[sp]] = 0)
fastStep[22, _, _] := (vals[sp] = symbolCall["Get", {vals[sp]}]; mk[[sp]] = 0)
fastStep[24, a_, b_] := (vals[sp] = integralHeld[SymbolName[$fastIntegralList[[a, 2]]], vals[sp], b]; mk[[sp]] = 0)
fastStep[26, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = symbolCall["Divisible", Reverse[xs]]; mk[[sp]] = 0)
fastStep[27, _, _] := (vals[sp] = symbolCall["Not", {symbolCall["Not", {vals[sp]}]}]; mk[[sp]] = 0)
fastStep[28, a_, b_] := (sp++; vals[sp] = heldLeafValue["String", "\"" <> StringReplace[fastText[a, b], "\t" -> " "] <> "\""]; mk[[sp]] = 0)
fastStep[29, a_, _] := (vals[sp] = symbolCall["Information", {vals[sp], symbolCall["Rule", {heldSymbol["LongForm"], heldSymbol[If[a === 1, "True", "False"]]}]}];
	mk[[sp]] = 0)

(* the head codes the build pass reads apart *)
$fastMinusHead := $fastMinusHead = fastHeadCode["Minus"]
$fastParenHead := $fastParenHead = fastHeadCode["Paren"]
$fastAtHead := $fastAtHead = fastHeadCode["At"]
$fastSlashSlashHead := $fastSlashSlashHead = fastHeadCode["SlashSlash"]
$fastDivideHead := $fastDivideHead = fastHeadCode["Divide"]

(* the binary operator of code 4 on the value at the top and y: f @ x the call of f; x // f the call
	of f; a/b Times[a, Power[b, -1]]; the rest the call of its head *)
fastBinary[a_Integer, y_] := (vals[sp] = Which[
	a === $fastAtHead, heldCall[vals[sp], {y}],
	a === $fastSlashSlashHead, heldCall[y, {vals[sp]}],
	a === $fastDivideHead, binaryHeld["Divide", vals[sp], y],
	True, heldCall[heldSymbol[$fastHeadNames[[a]]], {vals[sp], y}]]; mk[[sp]] = 0)

(* a chain of relations: of one kind, not a vector one, the call of its head; else as the held
	algebra reads it *)
relationHeld[xs_List, {h_String ..}] /; ! KeyExistsQ[$vectorRelations, h] := symbolCall[h, xs]
relationHeld[xs_List, heads_List] := relationValue[WolframLanguageSemantic, held /@ xs, heads]["Expr"]


(* ::Section:: *)
(*Reading a source*)

(* The parser's program of the lexer's tokens is one packed array: {0, n, then n instructions of
	three integers, {code, a, b}} for tokens it reads to their end; {1, the token reading stops at,
	the first token of the statement it stops in} for tokens it does not; and {3, the code a token
	that is two is split at, the first token of its statement}. *)
parseStatus::usage = "parseStatus[program] gives the status of the parser's program: 0 read to the end, 1 stopped, 3 a token to split."
parseStatus[program_List] := First[program]

stopToken::usage = "stopToken[program] gives the token reading stops at, of a program of status 1."
stopToken[program_List] := program[[2]]

statementToken::usage = "statementToken[program] gives the first token of the statement reading stops in, of a program of status 1 or 3."
statementToken[program_List] := program[[3]]

splitCode::usage = "splitCode[program] gives the position of the code a token is split at, of a program of status 3."
splitCode[program_List] := program[[2]]

programInstructions::usage = "programInstructions[program] gives the instructions of a program of status 0, three integers each."
programInstructions[program_List] := Take[program, {3, 3 program[[2]] + 2}]

lexedCodes::usage = "lexedCodes[padded] gives the lexer's tokens of the codes padded."
lexedCodes[padded_List] := fastLexFunction[padded, $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial]

fastParseTokens::usage = "fastParseTokens[lexed, padded] gives the parser's program of the lexer's tokens lexed of the codes padded."
fastParseTokens[lexed_List, padded_List] := fastParseFunction[lexed, fastLedIndices[lexed], $fastSpecTable, $fastPrefixArray, $fastGroupArray,
	$fastIntegralArray, $fastSpecialArray, $fastHeadCodeArray, $fastKeyCodeArray, padded, $fastClasses]

(* The reading of the codes of a source, or of a segment of one: the codes, padded, the lexer's
	tokens, each token that is two split, the parser's program of them, and how reading stops. *)
codesReading::usage = "codesReading[codes] gives <|\"Codes\" -> codes, \"Padded\" -> them padded, \"Lexed\" -> the lexer's tokens, \
\"Program\" -> the parser's program, \"Stop\" -> how reading stops, as readingStop gives it|>."
codesReading[codes_List] := With[{padded = paddedCodes[codes]},
	readingOf[codes, padded, splitParse[lexedCodes[padded], padded]]
]

readingOf::usage = "readingOf[codes, padded, {lexed, program}] gives codesReading's association of the codes, padded, of their tokens \
lexed and of the program."
readingOf[codes_List, padded_List, {lexed_List, program_List}] := <|
	"Codes" -> codes,
	"Padded" -> padded,
	"Lexed" -> lexed,
	"Program" -> program,
	"Stop" -> readingStop[lexed, program, Length[codes]]
|>

(* The lexer's tokens of a source and the program the parser reads of them, or of those before the
	last where the lexer stops at it. Where a token is two, the parser's status 3 at the code it
	splits at, as the words of ?a*=b end inside *= and a::b_ holds a message name's tag and a blank,
	the tokens are split there and read again; a split that comes again is no Wolfram Language,
	reading stopped at the token that holds its code. *)
splitParse::usage = "splitParse[lexed, padded] gives {tokens, program}: the lexer's tokens lexed of the codes padded, each token that \
is two split, and the parser's program of them."
splitParse[lexed_List, padded_List] := splitParsed @ NestWhile[
	splitAgain[#, padded] &,
	{lexed, parsedTokens[lexed, padded], {}},
	splitPendingQ
]

parsedTokens::usage = "parsedTokens[lexed, padded] gives the parser's program of the lexer's tokens lexed, of those before the last \
where the lexer stops at it."
parsedTokens[lexed_List, padded_List] /; lexerStatus[lexed] === 0 := fastParseTokens[lexed, padded]
parsedTokens[lexed_List, padded_List] := fastParseTokens[tokensBefore[lexed, tokenCount[lexed]], padded]

splitPendingQ::usage = "splitPendingQ[{lexed, program, splits}] is True where the program splits a token at a code that splits does \
not hold."
splitPendingQ[{_List, program_List, splits_List}] := parseStatus[program] === 3 && !MemberQ[splits, splitCode[program]]

splitAgain::usage = "splitAgain[{lexed, program, splits}, padded] gives the tokens lexed split where the program splits one, the program \
of them, and splits with that code."
splitAgain[{lexed_List, program_List, splits_List}, padded_List] := With[{split = splitTokens[lexed, padded, splitCode[program]]},
	{split, parsedTokens[split, padded], Append[splits, splitCode[program]]}
]

splitParsed::usage = "splitParsed[{lexed, program, splits}] gives {lexed, program}, a split that came again the program stopped at the \
token that holds its code."
splitParsed[{lexed_List, program_List, _List}] /; parseStatus[program] === 3 := {
	lexed,
	{1, tokenAt[lexed, splitCode[program]], statementToken[program]}
}
splitParsed[{lexed_List, program_List, _List}] := {lexed, program}

(* The tokens split at the code at, inside the token that holds it or the last, where the lexer
	stopped: the tokens before that one, its codes before at as one name, a tag or the words of a
	query, with the token's line break mark, and the tokens the lexer reads of the source from at,
	the status theirs. *)
splitTokens::usage = "splitTokens[lexed, padded, at] gives the lexer's tokens lexed of the codes padded, split at the code at."
splitTokens[lexed_List, padded_List, at_Integer] := With[
	{t = tokenAt[lexed, at], tail = lexedCodes[paddedCodes[Take[padded, {at, -4}]]]},
	{named = tokenStart[lexed, t] < at},
	Developer`ToPackedArray @ Join[
		{lexerStatus[tail], t + tokenCount[tail] - If[named, 0, 1]},
		Take[lexed, {3, 2 + 5 (t - 1)}],
		If[named, {$tkName, 0, tokenStart[lexed, t], at, newlineBefore[lexed, t]}, {}],
		Flatten[(# + {0, 0, at - 1, at - 1, 0}) & /@ Partition[Take[tail, {3, 2 + 5 tokenCount[tail]}], 5]]
	]
]

(* the token that holds the code at: the first that ends past it, or the last *)
tokenAt::usage = "tokenAt[lexed, at] gives the first token of lexed that ends past the code at, or the last token."
tokenAt[lexed_List, at_Integer] := 1 + LengthWhile[Take[lexed, {6, 5 tokenCount[lexed] - 4, 5}], # <= at &]

(* the lexer's tokens 1 to t - 1, then the end, where token t begins *)
tokensBefore::usage = "tokensBefore[lexed, t] gives the lexer's tokens lexed before token t, then the end where token t begins."
tokensBefore[lexed_List, t_Integer] := Developer`ToPackedArray @ Join[
	{0, t},
	Take[lexed, {3, 2 + 5 (t - 1)}],
	{$tkEnd, 0, tokenStart[lexed, t], tokenStart[lexed, t], newlineBefore[lexed, t]}
]

(* How reading stops: None where the program reads the tokens to their end; else the failure, the
	first token of the statement where reading stops, the token its warnings are read to and the
	token they stop at. Where the lexer stops at its last token, the statements before it are read,
	and the one where reading stops is the first that cannot be, the one that holds the token or one
	before it. *)
readingStop::usage = "readingStop[lexed, program, n] gives None where the program reads the tokens lexed of n codes to their end, else \
<|\"Failure\" -> the failure, \"Statement\" -> the first token of the statement where reading stops, \"To\" -> the token its warnings are \
read to, \"Stop\" -> the token they stop at, 0 for none|>."
readingStop[lexed_List, program_List, _Integer] /; lexerStatus[lexed] === 0 && parseStatus[program] =!= 1 := None
readingStop[lexed_List, program_List, _Integer] /; lexerStatus[lexed] === 0 || parseStatus[program] === 1 && stopToken[program] < tokenCount[lexed] := <|
	"Failure" -> stoppedFailure[lexed, stopToken[program]],
	"Statement" -> statementToken[program],
	"To" -> stopToken[program],
	"Stop" -> stopToken[program]
|>
readingStop[lexed_List, program_List, n_Integer] := <|
	"Failure" -> lexerFailure[lexed, n],
	"Statement" -> If[parseStatus[program] === 1, statementToken[program], tokenCount[lexed]],
	"To" -> tokenCount[lexed],
	"Stop" -> 0
|>

(* Where the lexer stops, the failure: the source ends in a string or a comment not closed, or holds
	a character no token has; a file the lexer reads none of after <<, >> or >>>, at the start of
	the operator, where the kernel's caret is. *)
lexerFailure::usage = "lexerFailure[lexed, n] gives the failure of a source of n codes where the lexer stops."
lexerFailure[lexed_List, n_Integer] /; lexerStatus[lexed] === 3 := fastFailure[n + 1, True]
lexerFailure[lexed_List, _Integer] /; namelessFileQ[lexed, tokenCount[lexed]] := fastFailure[tokenStart[lexed, tokenCount[lexed] - 1], False]
lexerFailure[lexed_List, _Integer] := fastFailure[tokenEnd[lexed, tokenCount[lexed]], False]

namelessFileQ::usage = "namelessFileQ[lexed, t] is True where token t of lexed is a file the lexer read none of after <<, >> or >>>."
namelessFileQ[lexed_List, t_Integer] := tokenKind[lexed, t] === $tkFile && operatorBeforeQ[lexed, t, $fastGet | $fastPut | $fastPutAppend]

(* A statement's range: {its first instruction, its last, its first token, the token after it}. *)
statementRanges::usage = "statementRanges[program] gives the range of each statement of a program read whole."
statementRanges[program_List] := With[{ranges = fastRangesFunction[program]}, If[First[ranges] === 0, {}, Partition[Rest[ranges], 4]]]

rangeFirstToken::usage = "rangeFirstToken[range] gives the first token of the statement of a range."
rangeFirstToken[{_Integer, _Integer, first_Integer, _Integer}] := first

(* The source's top-level expressions, held, by the lexer, the parser and the build pass; source
	that is no Wolfram Language a failure where the kernel's reader stops. *)
fastHeld::usage = "fastHeld[s] gives the top-level expressions of the source s, each in HoldComplete, or the failure where reading it \
stops."
fastHeld[s_String] := With[{reading = codesReading[ToCharacterCode[s]]},
	If[reading["Stop"] === None, readingStatements[reading], reading["Stop"]["Failure"]]
]

readingStatements::usage = "readingStatements[reading] gives the statements of the reading of a source that reads to its end, each in \
HoldComplete."
readingStatements[reading_Association] := With[{leaves = fastLeafData[reading["Program"], reading["Codes"], reading["Lexed"]]},
	Block[{$fcodes = reading["Codes"]},
		fastBuild[programInstructions[reading["Program"]], leaves["Kinds"], leaves["Texts"], leaves["Marks"]]
	]
]

(* ::Section:: *)
(*Statements one at a time*)

(* The parts of a source that reading it one statement at a time gives, as the kernel's ToExpression
	gives them: each statement, and the Null of each line that holds none. A line ends at each
	return, each newline and each long name that is a newline, outside comments; a statement's line
	is the one it ends on, each line after it with only whitespace and comments on it is a Null, and
	the last line of the source is one only where the source holds nothing else. Reading stops at
	the first statement that cannot be read. Each part is a row of integers, {kind, where its line
	begins, where the line after it does, its segment, its first instruction and its last, its first
	token and its last, and how many of its tokens may give a warning}, positions of the source; the
	kinds are 1 a statement, 2 a Null, 3 a failure and 6 the end. The "Data" of a part, by its place,
	is a failure. A source's parts are made at its first call and kept for the calls on it after,
	until one reads its end or its failure, those of the last few sources. *)
$heldNextStates = {}

heldNextState::usage = "heldNextState[s] gives the place in $heldNextStates of the parts of the source s, made now if they are not \
there."
heldNextState[s_String] := Replace[
	FirstPosition[$heldNextStates, KeyValuePattern["Source" -> s], {0}, {1}, Heads -> False],
	{
		{0} :> ($heldNextStates = Take[Prepend[$heldNextStates, makeHeldNextState[s]], UpTo[4]]; 1),
		{place_Integer} :> place
	}
]

makeHeldNextState::usage = "makeHeldNextState[s] gives the parts of the source s: an association of the source, its text read without \
its line continuations, its codes and the positions in s of their characters, its segments, its parts, their data and an index of the \
parts by where their lines begin."
makeHeldNextState[s_String] := With[{read = readSource[s]},
	segmentParts[
		<|
			"Source" -> s,
			"Clean" -> First[read],
			"Kept" -> Last[read],
			"Codes" -> ToCharacterCode[First[read]],
			"Segments" -> {},
			"Parts" -> {},
			"Data" -> <||>,
			"Index" -> <||>
		|>,
		1
	]
]

(* a position in the source read without its line continuations, in the source *)
sourcePosition::usage = "sourcePosition[state, c] gives the position in the state's source of the character at c of it read without its \
line continuations."
sourcePosition[state_Association, c_Integer] := sourcePosition[state["Kept"], StringLength[state["Source"]], c]
sourcePosition[None, _Integer, c_Integer] := c
sourcePosition[kept_List, _Integer, c_Integer] /; c <= Length[kept] := kept[[c]]
sourcePosition[kept_List, length_Integer, c_Integer] := length + c - Length[kept]

(* a failure of the source read from its character from on, without its line continuations, at the
	character of the source it is at *)
sourceFailure::usage = "sourceFailure[state, failure, from] gives the failure of the state's source read from its character from on, \
placed at the character of the source it is at."
sourceFailure[state_Association, failure_Failure, from_Integer] := failureAt[failure, sourcePosition[state, failure["Position"] + from - 1]]

failureAt::usage = "failureAt[failure, position] gives the failure placed at the position."
failureAt[Failure[tag_, data_Association], position_Integer] := Failure[tag, Join[data, <|
	"Position" -> position,
	"MessageParameters" -> Append[Lookup[data, "MessageParameters", <||>], "Position" -> position]
|>]]

(* The state, the parts of the source read from its character from on appended to its parts and the
	segment they are read from to its segments. *)
segmentParts::usage = "segmentParts[state, from] gives the state with the parts of its source read from the character from on, and the \
segment they are read from."
segmentParts[state_Association, from_Integer] := segmentState[
	state,
	from,
	stoppedReading @ codesReading[If[from === 1, state["Codes"], Drop[state["Codes"], from - 1]]]
]

(* Where reading stops, the statements before the one it stops in, but those on its line, which the
	kernel reads with it: the program of the tokens before the statement it stops in, and the first
	token of its line. *)
stoppedReading::usage = "stoppedReading[reading] gives the reading with \"Ranges\" the ranges of the statements it reads and \"First\" \
None; where reading stops, \"First\" the first token of the line it stops in, \"Ranges\" those of the statements before that line, and \
\"Program\" the program of the tokens before the statement it stops in."
stoppedReading[reading_Association] /; reading["Stop"] === None := Join[reading, <|"Ranges" -> statementRanges[reading["Program"]], "First" -> None|>]
stoppedReading[reading_Association] := With[
	{program = fastParseTokens[tokensBefore[reading["Lexed"], reading["Stop"]["Statement"]], reading["Padded"]]},
	{line = stoppedLine[reading["Lexed"], reading["Stop"]["Statement"], statementRanges[program]]},
	Join[reading, <|"Program" -> program, "Ranges" -> Last[line], "First" -> First[line]|>]
]

(* The kernel reads the statements on the line reading stops in with the statement it stops in: the
	first token of that line, back over the statements that end on it, and the ranges before it. *)
stoppedLine::usage = "stoppedLine[lexed, first, ranges] gives {the first token of the line of token first, the ranges of the statements \
before that line}, ranges those of the statements before token first."
stoppedLine[lexed_List, first_Integer, ranges_List] := NestWhile[lineBefore, {first, ranges}, sameLineQ[lexed, #] &]

sameLineQ::usage = "sameLineQ[lexed, {first, ranges}] is True where the last statement of ranges ends on the line of token first."
sameLineQ[lexed_List, {first_Integer, ranges_List}] := ranges =!= {} && newlineBefore[lexed, first] === 0

lineBefore::usage = "lineBefore[{first, ranges}] gives the first token of the last statement of ranges, and the ranges before it."
lineBefore[{_Integer, ranges_List}] := {rangeFirstToken[Last[ranges]], Most[ranges]}

(* The state with a segment's reading: the segment appended to its segments, its rows to its parts,
	and the failure where reading stops to the data, under the place of its row. The rows are the
	lines of the segment: the Nulls of the gap before the first statement, each statement and the
	Nulls of the gap after it, then where reading stops or the end. The first line break after a
	statement ends its line, else the token after it does; each break after that one ends a Null's. *)
segmentState::usage = "segmentState[state, from, reading] gives the state with the segment and the rows of the reading of its source \
from the character from on."
segmentState[state_Association, from_Integer, reading_Association] := With[
	{segment = readingSegment[reading]},
	{parts = Join[state["Parts"], segmentRows[state, from, reading, segment, Length[state["Segments"]] + 1]]},
	Join[state, <|
		"Segments" -> Append[state["Segments"], segment],
		"Parts" -> parts,
		"Data" -> stoppedData[state, from, reading, Length[parts]],
		"Index" -> If[Length[parts] > 8, AssociationThread[rowStarts[parts] -> Range[Length[parts]]], <||>]
	|>]
]

readingSegment::usage = "readingSegment[reading] gives the segment of a reading: <|\"Codes\", \"Lexed\", \"Program\", \"Warning\" -> the \
tokens that may give a warning and how many of them come before each token, \"Leaves\" -> fastLeafData's|>."
readingSegment[reading_Association] := <|
	"Codes" -> reading["Codes"],
	"Lexed" -> reading["Lexed"],
	"Program" -> reading["Program"],
	"Warning" -> If[MemberQ[reading["Codes"], 44 | 92],
		warningTokens[reading["Codes"], reading["Lexed"]],
		{{}, ConstantArray[0, tokenCount[reading["Lexed"]] + 1]}
	],
	"Leaves" -> fastLeafData[reading["Program"], reading["Codes"], reading["Lexed"]]
|>

segmentRows::usage = "segmentRows[state, from, reading, segment, index] gives the rows fastLines makes of the reading, its segment the \
segment index of the state."
segmentRows[state_Association, from_Integer, reading_Association, segment_Association, index_Integer] := Partition[
	Drop[
		fastLinesFunction[reading["Padded"], reading["Lexed"], reading["Program"], Last[segment["Warning"]], $fastClasses, $fastNewlineNames,
			packedKept[state["Kept"]],
			Developer`ToPackedArray[{
				Length[reading["Ranges"]],
				readingEnd[reading],
				0,
				index,
				If[reading["Stop"] === None, 0, 3],
				from - 1,
				StringLength[state["Source"]],
				0,
				If[state["Kept"] === None, 0, Length[state["Kept"]]]
			}]
		],
		2
	],
	9
]

packedKept::usage = "packedKept[kept] gives the positions kept as fastLines takes them, packed, {0} for None or none."
packedKept[None | {}] := $fastNoKept
packedKept[kept_List] := Developer`ToPackedArray[kept]

readingEnd::usage = "readingEnd[reading] gives where the statements of the reading end: the first token of the line reading stops in, \
or past its codes."
readingEnd[reading_Association] /; reading["First"] === None := Length[reading["Codes"]] + 1
readingEnd[reading_Association] := tokenStart[reading["Lexed"], reading["First"]]

stoppedData::usage = "stoppedData[state, from, reading, row] gives the state's data, with the failure where the reading stops, its \
warnings in it, under the place row of its part."
stoppedData[state_Association, _Integer, reading_Association, _Integer] /; reading["Stop"] === None := state["Data"]
stoppedData[state_Association, from_Integer, reading_Association, row_Integer] := Append[
	state["Data"],
	row -> warned[
		sourceFailure[state, reading["Stop"]["Failure"], from],
		tokenWarnings[reading["Codes"], reading["Lexed"], reading["First"], reading["Stop"]["To"], reading["Stop"]["Stop"]]
	]
]

rowStarts::usage = "rowStarts[rows] gives where the line of each of the rows begins."
rowStarts[rows_List] := rows[[All, 2]]

(* the statement of the source s whose line begins at pos, 1 or the position the call before gave *)
WolframLanguageHeldNext[s_String, pos_Integer] := With[
	{place = heldNextState[s]},
	{state = $heldNextStates[[place]]},
	{index = partIndex[state, pos]},
	heldNextPart[place, state, index, state["Parts"][[index]]]
]

partIndex::usage = "partIndex[state, pos] gives the place among the state's parts of the one whose line begins at pos, or of the first \
that begins past it, or of the last."
partIndex[state_Association, pos_Integer] := Replace[
	Lookup[state["Index"], pos, 0],
	0 :> Min[LengthWhile[rowStarts[state["Parts"]], # < pos &] + 1, Length[state["Parts"]]]
]

heldNextPart::usage = "heldNextPart[place, state, index, row] gives what WolframLanguageHeldNext gives for the part of the row, at index \
among the parts of the state at place in $heldNextStates, which is dropped from there once its failure or its end is read."
heldNextPart[_Integer, state_Association, _Integer, row : {1, _, next_Integer, __}] := {
	heldNextStatement[state, row],
	next,
	<|"Warnings" -> If[Last[row] === 0, {}, statementWarnings[state, row]]|>
}
heldNextPart[_Integer, _Association, _Integer, {2, _, next_Integer, __}] := {HoldComplete[Null], next, <|"Warnings" -> {}|>}
heldNextPart[place_Integer, state_Association, index_Integer, {3, start_Integer, __}] := (
	$heldNextStates = Delete[$heldNextStates, place];
	{state["Data"][index], start}
)
heldNextPart[place_Integer, _Association, _Integer, _List] := (
	$heldNextStates = Delete[$heldNextStates, place];
	EndOfFile
)

(* the statement of a row, held, its names made now: its instructions, and its leaves among the
	segment's *)
heldNextStatement::usage = "heldNextStatement[state, row] gives the statement of the row, held, its names made now."
heldNextStatement[state_Association, {_, _, _, segmentIndex_Integer, first_Integer, last_Integer, __}] := With[
	{segment = state["Segments"][[segmentIndex]]},
	{leaves = segment["Leaves"]},
	{span = leaves["Before"][[first]] + 1 ;; leaves["Before"][[last + 1]]},
	Block[{$fcodes = segment["Codes"]},
		First @ fastBuild[Take[segment["Program"], {3 first, 3 last + 2}], leaves["Kinds"][[span]], leaves["Texts"][[span]], leaves["Marks"][[span]]]
	]
]

(* the warnings of the statement of a row, from the tokens of its segment that may give one *)
statementWarnings::usage = "statementWarnings[state, row] gives the warnings of the statement of the row."
statementWarnings[state_Association, row : {_, _, _, segmentIndex_Integer, __}] := rowWarnings[state["Segments"][[segmentIndex]], row]

rowWarnings::usage = "rowWarnings[segment, row] gives the warnings of the statement of the row, from the tokens of its segment that may \
give one."
rowWarnings[segment_Association, {_, _, _, _, _, _, first_Integer, last_Integer, _}] := With[{warning = segment["Warning"]},
	warningsAt[segment["Codes"], segment["Lexed"], first, last, 0, Take[First[warning], {Last[warning][[first]] + 1, Last[warning][[last + 1]]}]]
]

(* a failure with the warnings of the statement that cannot be read *)
warned::usage = "warned[failure, warnings] gives the failure with the warnings under its \"Warnings\"."
warned[Failure[tag_, data_Association], warnings_List] := Failure[tag, Append[data, "Warnings" -> warnings]]

(* ::Section:: *)
(*Warnings*)

(* The warnings the kernel's reader gives as it reads tokens from to to of a lexed source, codes its
	characters [WL 15.0.0]: {"com"} for each Null a comma leaves, after the opener of a bracket or
	before another comma, its closer, the end or the token stop that reading stops at, which begins
	no operand; those of each string's escapes; and where the lexer stops at a long name,
	{"sntufn", name} for one no character has or not closed, {"sntmsng", text} for one with no name
	before a quote, text the source from the statement on. *)
tokenWarnings::usage = "tokenWarnings[codes, lexed, from, to, stop] gives the warnings of the tokens from to to of lexed, reading stopped \
at token stop, 0 for none."
tokenWarnings[codes_List, lexed_List, from_Integer, to_Integer, stop_Integer : 0] :=
	warningsAt[codes, lexed, from, to, stop, Select[Range[from, to], warningKindQ[tokenKind[lexed, #]] &]]

warningKindQ::usage = "warningKindQ[kind] is True for the kinds of token a warning may come from: a string, a comma and the end."
warningKindQ[kind_Integer] := kind === $tkString || kind === $tkComma || kind === $tkEnd

(* the warnings of tokens from to to that come from the tokens among them *)
warningsAt::usage = "warningsAt[codes, lexed, from, to, stop, tokens] gives the warnings of the tokens from to to of lexed that come \
from the tokens."
warningsAt[codes_List, lexed_List, from_Integer, to_Integer, stop_Integer, tokens_List] :=
	Catenate[tokenWarning[codes, lexed, from, to, stop, #] & /@ tokens]

tokenWarning::usage = "tokenWarning[codes, lexed, from, to, stop, t] gives the warnings that token t gives, of the statement of tokens \
from to to."
tokenWarning[codes_List, lexed_List, from_Integer, to_Integer, stop_Integer, t_Integer] := Switch[tokenKind[lexed, t],
	$tkString,
		stringTokenWarnings[codes, lexed, from, t],
	$tkComma,
		commaWarnings[lexed, from, to, stop, t],
	$tkEnd,
		endWarnings[codes, lexed, from, t],
	_,
		{}
]

stringTokenWarnings::usage = "stringTokenWarnings[codes, lexed, from, t] gives the warnings of the escapes of the string of token t, of \
the statement from token from."
stringTokenWarnings[codes_List, lexed_List, from_Integer, t_Integer] := With[
	{string = Take[codes, {tokenStart[lexed, t], Min[tokenEnd[lexed, t] - 1, Length[codes]]}]},
	If[MemberQ[string, 92],
		Replace[
			stringWarnings[FromCharacterCode[string], lexerStatus[lexed] === 3 && t === tokenCount[lexed]],
			{"sntmsng"} :> {"sntmsng", statementText[codes, lexed, from]},
			{1}
		],
		{}
	]
]

statementText::usage = "statementText[codes, lexed, from] gives the text of the source from token from on."
statementText[codes_List, lexed_List, from_Integer] := FromCharacterCode @ Drop[codes, tokenStart[lexed, from] - 1]

commaWarnings::usage = "commaWarnings[lexed, from, to, stop, t] gives a {\"com\"} for each Null the comma of token t leaves: after an \
opener, and before a comma, a closer or the token stop."
commaWarnings[lexed_List, from_Integer, to_Integer, stop_Integer, t_Integer] := Join[
	If[t > from && bracketQ[lexed, t - 1, $warnOpeners], {{"com"}}, {}],
	If[t < to && (tokenKind[lexed, t + 1] === $tkComma || bracketQ[lexed, t + 1, $warnClosers] || t + 1 === stop), {{"com"}}, {}]
]

endWarnings::usage = "endWarnings[codes, lexed, from, t] gives the warnings of the long name the lexer stops at, token t, of the \
statement from token from."
endWarnings[codes_List, lexed_List, from_Integer, t_Integer] /; longNameStopQ[codes, lexed, t] :=
	longNameWarnings[codes, lexed, from, tokenStart[lexed, t] + 2, longNameText[codes, tokenStart[lexed, t] + 2]]
endWarnings[_List, _List, _Integer, _Integer] := {}

longNameStopQ::usage = "longNameStopQ[codes, lexed, t] is True where the lexer stops at its last token t, a \\[ that begins a long name."
longNameStopQ[codes_List, lexed_List, t_Integer] := And[
	t === tokenCount[lexed],
	lexerStatus[lexed] === 1,
	tokenStart[lexed, t] < Length[codes],
	codes[[tokenStart[lexed, t]]] === 92,
	codes[[tokenStart[lexed, t] + 1]] === 91
]

longNameWarnings::usage = "longNameWarnings[codes, lexed, from, at, name] gives the warning of the long name whose name, name, begins at \
the code at: {\"sntmsng\", text} for one with no name before a quote, {\"sntufn\", name} for one no character has or not closed."
longNameWarnings[codes_List, lexed_List, from_Integer, at_Integer, ""] /; at <= Length[codes] && codes[[at]] === 34 :=
	{{"sntmsng", statementText[codes, lexed, from]}}
longNameWarnings[_List, _List, _Integer, _Integer, ""] := {}
longNameWarnings[codes_List, _List, _Integer, at_Integer, name_String] /; closedLongNameQ[codes, at, name] := {}
longNameWarnings[_List, _List, _Integer, _Integer, name_String] := {{"sntufn", name}}

closedLongNameQ::usage = "closedLongNameQ[codes, at, name] is True where the long name whose name, name, begins at the code at is closed \
and a character has it."
closedLongNameQ[codes_List, at_Integer, name_String] := And[
	at + StringLength[name] <= Length[codes],
	codes[[at + StringLength[name]]] === 93,
	KeyExistsQ[longNameCharacters[], name]
]

(* The tokens of a lexed source a statement's warning may come from, each read in one pass: a comma
	after a token that opens a bracket or before one that closes it, a comma or the end, and a string
	with a \ in it. With them, for each token t, how many come before it. *)
warningTokens::usage = "warningTokens[codes, lexed] gives {the tokens of lexed a warning may come from, how many of them come before each \
token}."
warningTokens[codes_List, lexed_List] :=
	warningSplit @ fastWarnFunction[codes, lexed, $openKindFlags, $closeKindFlags, $warnOpenOps, $warnCloseOps, $fastWarnParams]

warningSplit::usage = "warningSplit[warn] gives {tokens, counts} of the array {how many tokens, the tokens, the counts} fastWarn gives."
warningSplit[warn_List] := {Take[warn, {2, First[warn] + 1}], Drop[warn, First[warn] + 1]}

$fastWarnParams := $fastWarnParams = Developer`ToPackedArray[{$tkOperator, $tkComma, $tkString}]

(* the kinds of token that open a bracket's items, and that close them, by kind + 1, and the
	operators that do, the long-name brackets, by operator + 1 *)
$openKindFlags = Developer`ToPackedArray[ReplacePart[ConstantArray[0, $tkWord + 1], Thread[{12, 14, 16} + 1 -> 1]]]
$closeKindFlags = Developer`ToPackedArray[ReplacePart[ConstantArray[0, $tkWord + 1], Thread[{0, 13, 15, 17, 18} + 1 -> 1]]]
$warnOpenOps := $warnOpenOps = Developer`ToPackedArray[ReplacePart[
	ConstantArray[0, $fastNotId + 2],
	Thread[(Append[Keys[$fastGroupTable], fastLongOp["LeftDoubleBracket"]] + 1) -> 1]
]]
$warnCloseOps := $warnCloseOps = Developer`ToPackedArray[ReplacePart[
	ConstantArray[0, $fastNotId + 2],
	Thread[(Append[Values[$fastGroupTable][[All, 1]], $fastRightDoubleBracket] + 1) -> 1]
]]

(* the letters and digits of a long name's name, from its character i on *)
longNameText::usage = "longNameText[codes, i] gives the letters and digits of the codes from i on."
longNameText[codes_List, i_Integer] := FromCharacterCode @ TakeWhile[Drop[codes, i - 1], 48 <= # <= 57 || 65 <= # <= 90 || 97 <= # <= 122 &]

(* token t of a lexed source opens, or closes, a bracket's items: its kind, or the long name it is;
	the end of the source closes them too, where the lexer reads it *)
bracketQ::usage = "bracketQ[lexed, t, brackets] is True where token t of lexed opens, or closes, a bracket's items, as brackets, \
$warnOpeners or $warnClosers, tells."
bracketQ[lexed_List, t_Integer, brackets_Association] := Switch[tokenKind[lexed, t],
	$tkOperator,
		KeyExistsQ[brackets, tokenOperator[lexed, t]],
	$tkEnd,
		brackets === $warnClosers && (lexerStatus[lexed] =!= 1 || t < tokenCount[lexed]),
	_,
		MemberQ[brackets["Kinds"], tokenKind[lexed, t]]
]

$warnOpeners := $warnOpeners = Join[
	<|"Kinds" -> {$tkOpenSquare, $tkOpenCurly, $tkOpenAssociation}|>,
	AssociationThread[Append[Keys[$fastGroupTable], fastLongOp["LeftDoubleBracket"]] -> True]
]
$warnClosers := $warnClosers = Join[
	<|"Kinds" -> {$tkCloseSquare, $tkCloseCurly, $tkCloseAssociation}|>,
	AssociationThread[Append[Values[$fastGroupTable][[All, 1]], $fastRightDoubleBracket] -> True]
]

(* The warnings of the escapes a string keeps as written [WL 15.0.0]: too few digits of a code, a
	letter no escape has, a long name no character has, or not closed before the string is, the
	string closed, and {"sntmsng"} for a long name with no name at its end, which the statement's
	text completes; unclosed, the string goes on to its token's end. *)
stringWarnings::usage = "stringWarnings[s, unclosed] gives the warnings of the escapes of the string s, unclosed True for one the source \
ends in."
stringWarnings[s_String, True] := StringCases[StringDrop[s, 1], $unclosedStringWarningRules]
stringWarnings[s_String, _] := StringCases[StringTake[s, {2, -2}], $stringWarningRules]

(* the rules of the warnings of a string's escapes, made once, a string's and one the source ends
	in, whose long name not closed at its end is one no character has *)
$stringWarningRules := $stringWarningRules = stringWarningRules["sntunc"]
$unclosedStringWarningRules := $unclosedStringWarningRules = stringWarningRules["sntufn"]

stringWarningRules::usage = "stringWarningRules[unclosedName] gives the rules of the warnings of a string's escapes, unclosedName the \
warning of a long name not closed at its end."
stringWarningRules[unclosedName_String] := Join[
	Map[First[#] -> Nothing &, $escapes],
	{
		"\\" ~~ CharacterRange["0", "7"] -> {"sntoct1"},
		"\\." -> {"sntoct2"},
		"\\:" -> {"snthex"},
		"\\|" -> {"snthex32"},
		"\\[" ~~ name : $nameCharacter .. ~~ EndOfString :> {unclosedName, name},
		"\\[" ~~ name : $nameCharacter .. :> {"sntufn", name},
		"\\[" ~~ EndOfString -> {"sntmsng"},
		"\\" ~~ c : (CharacterRange["a", "z"] | CharacterRange["A", "Z"]) :> {"stresc", c},
		"\\" ~~ _ -> Nothing
	}
]

$nameCharacter = CharacterRange["a", "z"] | CharacterRange["A", "Z"] | CharacterRange["0", "9"]

(* ::Section:: *)
(*The program of a source*)

(* The program of a source that reads whole, with no line continuation and no syntax warning, as a
	builder of its own takes it (docs/ReaderBuild.md): {codes, prog, parts}, the source's character
	codes, the parser's program of all its statements, and fastWhole's leaves and parts, a row for
	each part WolframLanguageHeldNext gives, in order. Any other source is None, for
	WolframLanguageHeldNext to read. The parser reads the tokens alone where none is two; the only
	warnings of a source read whole are the Nulls a comma leaves, which the program marks, and a
	string's escapes. Nothing is kept for a call after it. *)
WolframLanguageProgram[s_String] := Replace[flatProgram[s], flat_List :> flatParts[flat]]

flatParts::usage = "flatParts[flat] gives {codes, program, parts} of the array flat that flatProgram gives."
flatParts[flat_List] := With[
	{programLength = flat[[2]]},
	{partsLength = 3 + 4 flat[[programLength + 4]] + 4 flat[[programLength + 5]]},
	{
		Drop[flat, 2 + programLength + partsLength],
		Take[flat, {3, 2 + programLength}],
		Take[flat, {3 + programLength, 2 + programLength + partsLength}]
	}
]

(* The program of a source in one packed array, as a kernel's builder takes it with the fewest
	steps: {0, the program's length, the program, the parts, then the source's codes}, or None, the
	parts of length 3 + 4 m + 4 r for m leaves and r rows. The typed program makes it in one call
	where a compiler of typed code gave it a definition; else, and for the sources it leaves to them,
	the typed stages each in turn do. *)
flatProgram::usage = "flatProgram[s] gives the program of the source s in one packed array, {0, the program's length, the program, the \
parts, then the source's codes}, or None."
flatProgram[s_String] := flatOf[fastProgramTextFunction, s]

flatOf::usage = "flatOf[f, s] gives the program of the source s by the typed program f, or by the typed stages where f is None or leaves \
the source to them."
flatOf[None, s_String] := stagesProgram[s]
flatOf[f_, s_String] := typedFlat[f[s, Sequence @@ $fastProgramTables], s]

typedFlat::usage = "typedFlat[flat, s] gives the typed program's array flat of the source s: itself, None for {1}, and the stages' \
program for {2} or for no array."
typedFlat[flat_List, s_String] := Switch[First[flat],
	0,
		flat,
	1,
		None,
	_,
		stagesProgram[s]
]
typedFlat[_, s_String] := stagesProgram[s]

(* the program of a source by the typed stages, each called in turn, as flatProgram gives it *)
stagesProgram::usage = "stagesProgram[s] gives the program of the source s by the typed stages, each called in turn, as flatProgram gives \
it, or None."
stagesProgram[s_String] := codesProgram[s, ToCharacterCode[s]]

codesProgram::usage = "codesProgram[s, codes] gives the program of the source s of the codes by the typed stages, or None."
codesProgram[s_String, codes_List] /; MemberQ[codes, 92] && lineContinuations[s] =!= {} := None
codesProgram[_String, codes_List] := With[{padded = paddedCodes[codes]},
	{lexed = lexedCodes[padded]},
	If[lexerStatus[lexed] === 0, wholeProgram[codes, padded, splitParse[lexed, padded]], None]
]

wholeProgram::usage = "wholeProgram[codes, padded, {lexed, program}] gives flatProgram's array of a source that reads whole, or None \
where it does not, or a comma leaves a Null, or a string's escape warns."
wholeProgram[codes_List, padded_List, {lexed_List, program_List}] /; lexerStatus[lexed] === 0 && parseStatus[program] === 0 := With[
	{flat = fastWholeFunction[program, lexed, wholeLines[codes, padded, lexed, program]]},
	If[commaNulls[flat] > 0 || MemberQ[codes, 92] && escapeWarnedQ[codes, lexed], None, Developer`ToPackedArray[Join[flat, codes]]]
]
wholeProgram[_List, _List, _List] := None

wholeLines::usage = "wholeLines[codes, padded, lexed, program] gives the lines fastLines makes of a source that reads whole, for fastWhole."
wholeLines[codes_List, padded_List, lexed_List, program_List] := fastLinesFunction[
	padded,
	lexed,
	program,
	ConstantArray[0, tokenCount[lexed] + 1],
	$fastClasses,
	$fastNewlineNames,
	$fastNoKept,
	Developer`ToPackedArray[{program[[2]], Length[codes] + 1, 0, 1, 0, 0, Length[codes], 0, 0}]
]

commaNulls::usage = "commaNulls[flat] gives how many Nulls a comma leaves in the program of the array flat."
commaNulls[flat_List] := flat[[3 + flat[[2]]]]

(* whether a string of a lexed source read whole warns of an escape *)
escapeWarnedQ::usage = "escapeWarnedQ[codes, lexed] is True where a string of the lexer's tokens lexed of the codes warns of an escape."
escapeWarnedQ[codes_List, lexed_List] := AnyTrue[stringTokens[lexed], stringTokenWarnings[codes, lexed, 1, #] =!= {} &]

stringTokens::usage = "stringTokens[lexed] gives the tokens of lexed that are strings."
stringTokens[lexed_List] := Flatten @ Position[tokenKinds[lexed], $tkString]

(* ::Section:: *)
(*Syntax alone*)

(* Where reading a source stops, as the kernel's SyntaxLength counts the characters before it, or
	None where the source reads: by the lexer and the parser alone, no expression built, but for a
	statement only the grammar reads. A source that ends before its expression does stops past its
	end, by 2. Reading stops
	- before the token no Wolfram Language reaches, a line continuation before it its own, but after
	a name or a number the name's or the number's;
	- at a :: with no tag after it that touches the symbol of its message name, else before it;
	- at the end of the last operand of a /: with no assignment after it;
	- at a comment or a string the source does not close, for a string that begins a statement after
	the first line at the newline before it;
	- before a long name no character has, or a malformed name, from the name it is in;
	and at the end of the source where a comment, a string or a name of these is its first token.
	A place is {the codes of the source read without its line continuations, the positions in the
	source of their characters or None, the source's length}. *)
syntaxStop::usage = "syntaxStop[s] gives where reading the source s stops, as SyntaxLength counts the characters before it, or None where \
it reads."
syntaxStop[s_String] := With[
	{read = readSource[s]},
	{codes = ToCharacterCode[First[read]]},
	{padded = paddedCodes[codes]},
	placeStop[{codes, Last[read], StringLength[s]}, splitParse[lexedCodes[padded], padded]]
]

placeStop::usage = "placeStop[place, {lexed, program}] gives where reading the source of the place stops, its tokens lexed and the \
parser's program of them."
placeStop[place_List, {lexed_List, program_List}] /; lexerStatus[lexed] === 0 :=
	If[parseStatus[program] === 0, None, parserStop[lexed, stopToken[program], statementToken[program], place]]
placeStop[place_List, {lexed_List, program_List}] := lexerStop[place, lexed, program, tokenCount[lexed]]

(* where reading stops where the lexer stops at its last token k *)
lexerStop::usage = "lexerStop[place, lexed, program, k] gives where reading stops where the lexer stops at its last token k."
lexerStop[place : {codes_List, _, length_Integer}, lexed_List, program_List, k_Integer] := Which[
	parseStatus[program] === 1 && stopToken[program] < k,
		parserStop[lexed, stopToken[program], statementToken[program], place],
	lexerStatus[lexed] === 3 && tokenKind[lexed, k] === $tkBoxes,
		length + 2,
	lexerStatus[lexed] === 3 && tokenKind[lexed, k] === $tkFreeform,
		placeOrEnd[place, tokenStart[lexed, k], 0],
	lexerStatus[lexed] === 3 && tokenKind[lexed, k] === $tkString && newlineBefore[lexed, k] === 1 && parseStatus[program] === 0,
		sourcePlace[place, lastNewline[codes, tokenStart[lexed, k]]],
	lexerStatus[lexed] === 3 && tokenKind[lexed, k] === $tkString,
		placeOrEnd[place, tokenStart[lexed, k], 0],
	lexerStatus[lexed] === 3,
		placeOrEnd[place, unclosedComment[codes, If[k > 1, tokenEnd[lexed, k - 1], 1]], 0],
	lexerStatus[lexed] === 1 && namelessFileQ[lexed, k],
		placeOrEnd[place, tokenStart[lexed, k - 1], 1],
	newlineBefore[lexed, k] === 1 && parseStatus[program] === 0 && tokenStart[lexed, k] <= Length[codes] && nameStartCodeQ[codes[[tokenStart[lexed, k]]]],
		sourcePlace[place, lastNewline[codes, tokenStart[lexed, k]]],
	True,
		tokenStop[place, lexed, If[longNameAfterNameQ[codes, lexed, k], k - 1, k]]
]

(* reading stops at token t of the statement from token statement *)
parserStop::usage = "parserStop[lexed, t, statement, place] gives where reading stops where the parser stops at token t of the statement \
from token statement."
parserStop[lexed_List, t_Integer, statement_Integer, place : {_, _, length_Integer}] := Which[
	operatorBeforeQ[lexed, t, $fastColonColon],
		sourcePlace[place, tokenStart[lexed, t - 1]] - If[messageNameTagQ[lexed, t], 0, 1],
	tokenKind[lexed, t] =!= $tkEnd,
		sourcePlace[place, tokenStart[lexed, t]] - 1,
	operatorBeforeQ[lexed, t, $fastGet],
		placeOrEnd[place, tokenStart[lexed, t - 1], 1],
	operatorBeforeQ[lexed, t, $fastPut | $fastPutAppend],
		sourcePlace[place, tokenStart[lexed, t - 1]] - 1,
	tagSetOpenQ[lexed, statement, t - 1],
		sourcePlace[place, tokenEnd[lexed, t - 1]] - 1,
	True,
		length + 2
]

messageNameTagQ::usage = "messageNameTagQ[lexed, t] is True where the :: before token t touches the symbol of its message name, itself \
after no other ::."
messageNameTagQ[lexed_List, t_Integer] := And[
	t > 2,
	tokenKind[lexed, t - 2] === $tkName,
	tokenEnd[lexed, t - 2] === tokenStart[lexed, t - 1],
	!operatorBeforeQ[lexed, t - 2, $fastColonColon]
]

(* the tokens from statement to last hold a /: with no =, := or =. after it, outside brackets, all
	closed, and the last ends an operand *)
tagSetOpenQ::usage = "tagSetOpenQ[lexed, statement, last] is True where the tokens of lexed from statement to last hold a /: with no \
assignment after it, outside brackets, all closed, and token last ends an operand."
tagSetOpenQ[lexed_List, statement_Integer, last_Integer] := And[
	Fold[tagSetStep[lexed, #1, #2] &, {0, False}, Range[statement, last]] === {0, True},
	MemberQ[$operandEndKinds, tokenKind[lexed, last]]
]

tagSetStep::usage = "tagSetStep[lexed, {depth, open}, t] gives the depth of the brackets and whether a /: is open after token t of lexed."
tagSetStep[lexed_List, {depth_Integer, open_}, t_Integer] := Which[
	MemberQ[{$tkOpenParen, $tkOpenSquare, $tkOpenCurly, $tkOpenAssociation}, tokenKind[lexed, t]],
		{depth + 1, open},
	MemberQ[{$tkCloseParen, $tkCloseSquare, $tkCloseCurly, $tkCloseAssociation}, tokenKind[lexed, t]],
		{depth - 1, open},
	depth === 0 && tokenKind[lexed, t] === $tkOperator && tokenOperator[lexed, t] === $fastSlashColon,
		{depth, True},
	depth === 0 && tokenKind[lexed, t] === $tkOperator && MemberQ[$fastAssignments, tokenOperator[lexed, t]],
		{depth, False},
	True,
		{depth, open}
]

$fastSlashColon := $fastSlashColon = fastOp["/:"]
$fastAssignments := $fastAssignments = fastOp /@ {"=", ":=", "=."}

(* a token's place in the source, the line continuations before it its own, but after a name's or a
	number's character the name's or the number's *)
sourcePlace::usage = "sourcePlace[place, c] gives the position in the source of the character at c of it read without its line \
continuations."
sourcePlace[{_List, None, _Integer}, c_Integer] := c
sourcePlace[{codes_List, kept_List, length_Integer}, c_Integer] := Which[
	c === 1,
		1,
	c > Length[kept],
		length + c - Length[kept],
	wordCodeQ[codes[[c - 1]]],
		kept[[c]],
	True,
		kept[[c - 1]] + 1
]

wordCodeQ::usage = "wordCodeQ[code] is True for the code of a letter, a digit, $ or `."
wordCodeQ[code_Integer] := LetterQ[FromCharacterCode[code]] || DigitQ[FromCharacterCode[code]] || code === 36 || code === 96

nameStartCodeQ::usage = "nameStartCodeQ[code] is True for the code of a letter or `."
nameStartCodeQ[code_Integer] := code === 96 || LetterQ[FromCharacterCode[code]]

placeOrEnd::usage = "placeOrEnd[place, c, back] gives the source's length where the character at c is the source's first, else its \
position less back."
placeOrEnd[place : {_, _, length_Integer}, c_Integer, back_Integer] := With[{position = sourcePlace[place, c]},
	If[position === 1, length, position - back]
]

tokenStop::usage = "tokenStop[place, lexed, t] gives where reading stops before token t: the source's length where t is its first token \
and a name, a slot, a \\ or a letter, else the character before it."
tokenStop[place : {codes_List, _, length_Integer}, lexed_List, t_Integer] := With[{position = sourcePlace[place, tokenStart[lexed, t]]},
	If[position === 1 && wordStartQ[codes, lexed, t], length, position - 1]
]

wordStartQ::usage = "wordStartQ[codes, lexed, t] is True where token t of lexed is a name or a slot, or begins with a \\ or a letter."
wordStartQ[codes_List, lexed_List, t_Integer] := Or[
	codes[[tokenStart[lexed, t]]] === 92,
	tokenKind[lexed, t] === $tkName,
	tokenKind[lexed, t] === $tkSlot,
	LetterQ[FromCharacterCode[codes[[tokenStart[lexed, t]]]]]
]

longNameAfterNameQ::usage = "longNameAfterNameQ[codes, lexed, k] is True where token k, a \\[ that begins a long name, touches a name \
before it."
longNameAfterNameQ[codes_List, lexed_List, k_Integer] := And[
	k > 1,
	tokenKind[lexed, k - 1] === $tkName,
	tokenEnd[lexed, k - 1] === tokenStart[lexed, k],
	tokenStart[lexed, k] < Length[codes],
	codes[[tokenStart[lexed, k]]] === 92,
	codes[[tokenStart[lexed, k] + 1]] === 91
]

(* the last line break before the character at *)
lastNewline::usage = "lastNewline[codes, at] gives the position of the last newline or return before the character at, or 1."
lastNewline[codes_List, at_Integer] := at - 1 - LengthWhile[Reverse[Take[codes, {2, Max[at - 1, 1]}]], # =!= 10 && # =!= 13 &]

(* Where the comment that the gap from a on holds and the source does not close begins: the opener
	of the outermost comment left open, each comment opener and closer and each escaped parenthesis
	read as the scan reads them, two characters each. *)
unclosedComment::usage = "unclosedComment[codes, a] gives where the comment begins that the codes, from the gap at a on, do not close."
unclosedComment[codes_List, a_Integer] := Last @ Fold[
	commentStep[codes, #1, #2] &,
	{a, 0, a},
	a - 1 + Sort[Catenate[pairPositions[Drop[codes, a - 1], #] & /@ {{40, 42}, {42, 41}, {92, 40}}]]
]

pairPositions::usage = "pairPositions[codes, pair] gives where each occurrence of the two codes of pair begins in the codes."
pairPositions[codes_List, pair_List] := First /@ SequencePosition[codes, pair]

commentStep::usage = "commentStep[codes, {next, depth, open}, i] gives the scan's state after the pair of codes at i: where it reads next, \
how deep in comments it is, and where the outermost comment opens."
commentStep[_List, state : {next_Integer, _Integer, _Integer}, i_Integer] /; i < next := state
commentStep[codes_List, {_Integer, depth_Integer, open_Integer}, i_Integer] /; codes[[i]] === 40 := {i + 2, depth + 1, If[depth === 0, i, open]}
commentStep[codes_List, {_Integer, depth_Integer, open_Integer}, i_Integer] /; depth > 0 := {i + 2, If[codes[[i]] === 42, depth - 1, depth], open}
commentStep[_List, state_List, _Integer] := state

WolframLanguageSyntaxQ[s_String] := s =!= "" && syntaxStop[s] === None

WolframLanguageSyntaxLength[s_String] := Replace[syntaxStop[s], None -> StringLength[s]]

End[]

EndPackage[]

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

(* --- characters --- *)

(* the class of each character code: 1 a letter, $ or ` that begins a name,
   2 a digit, 3 a space, tab or form feed, or the character of a long name
   that is whitespace, 4 a newline, a return or the character of a long
   name that is a newline, 5 a character past ASCII that a name holds, 0
   any other *)
$fastClasses := $fastClasses = Module[{t = ConstantArray[0, 65536], high = Range[128, 65535]},
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

(* --- operators --- *)

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
   of both, {c1, c2, c3, operator} for each of 3, and for each long name
   that is an operator its length, its codes and the operator *)
$fastOp2Flat := $fastOp2Flat = Developer`ToPackedArray[Flatten[$fastOp2]]
$fastOp3Table = Developer`ToPackedArray[Flatten[KeyValueMap[Append[#1, #2] &, $fastOp3]]]
$fastLongOpTable := $fastLongOpTable = Developer`ToPackedArray[Flatten[KeyValueMap[Join[{StringLength[#1]}, ToCharacterCode[#1], {#2}] &, $fastLongNameOps]]]
$fastOpenAssociation = fastOp["<|"]; $fastCloseAssociation = fastOp["|>"]
$fastGet = fastOp["<<"]; $fastPut = fastOp[">>"]; $fastPutAppend = fastOp[">>>"]
$fastSpecial := $fastSpecial = Developer`ToPackedArray[{$fastOpenAssociation, $fastCloseAssociation, $fastGet, $fastPut, $fastPutAppend, fastOp["=."], fastOp["="],
    $fastSpaceId, $fastInvisibleCommaId, $fastNewlineId}]

(* --- tokens --- *)

(* token kinds *)
$tkEnd = 0; $tkName = 1; $tkBlank = 2; $tkInteger = 3; $tkReal = 4; $tkString = 5; $tkSlot = 6; $tkOut = 7; $tkFile = 8;
$tkOperator = 9; $tkOpenParen = 10; $tkCloseParen = 11; $tkOpenSquare = 12; $tkCloseSquare = 13; $tkOpenCurly = 14;
$tkCloseCurly = 15; $tkOpenAssociation = 16; $tkCloseAssociation = 17; $tkComma = 18; $tkPrimes = 19; $tkBoxes = 20

(* the source is not one this reader takes: the grammar reads it *)
fastGiveUp[] := Throw[$fastGiveUp, $fastGiveUp]

(* the source is no Wolfram Language: the character where reading stops, as
   the kernel's reader stops there, and whether the source ends before its
   expression does, as "f[x" does *)
(* reading stopped at token t, where the kernel's message points: just past the token, or, at the
   end of the source, the source ending too early. But for a :: with no tag after it, or a <<, >>
   or >>> with no file, the kernel's error, at the end of the ::, at the start of the file's
   operator. *)
stoppedFailure[lexed_List, t_Integer] := With[{before = If[t > 1, lexed[[5 (t - 1) - 1]], 0]},
    Which[
        lexed[[5 t - 2]] =!= $tkEnd, fastFailure[lexed[[5 t + 1]], False],
        t > 1 && lexed[[5 (t - 1) - 2]] === $tkOperator && before === $fastColonColon, fastFailure[lexed[[5 t]], False],
        t > 1 && lexed[[5 (t - 1) - 2]] === $tkOperator && MemberQ[{$fastGet, $fastPut, $fastPutAppend}, before], fastFailure[lexed[[5 (t - 1)]], False],
        True, fastFailure[lexed[[5 t]], True]]]

fastFailure[position_Integer, incomplete_] := Failure["ParseError", <|
    "MessageTemplate" -> If[TrueQ[incomplete], "The source ends at position `Position` before its expression does.", "Reading stopped at position `Position`."],
    "MessageParameters" -> <|"Position" -> position|>,
    "Position" -> position, "Incomplete" -> TrueQ[incomplete]|>]

(* The lexer, typed code over packed integers: the codes of a source and
   three zeros after them, so that no look ahead reads past them, the
   class of each code, the operators of 1, 2 and 3 characters, the long-name
   long names (-1 a letter, else its operator) and {<|, |>, <<, >>, >>>,
   =., =, whitespace, the invisible comma, a newline} -> {status, k, then for each of the
   k tokens its kind, operator, start, end (just past it) and newline mark
   (1 where a newline outside a comment comes before it)}, the last token
   the end. Status 1: the source holds a character no token has, where the
   last token, the one that stops there, ends; 3: the source ends in a
   string, a comment or a linear syntax's \( not closed. Whitespace and
   comments are in no token; after << and >> the file is one token, and
   so is a \( to its \), the boxes of linear syntax, a \! before it too. *)
$fastLexDeclaration = FunctionDeclaration[fastLex,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{lexCodes, lexClasses, lexOp1, lexOp2, lexOp3, lexLongOps, lexSpecial},
        Module[{n = Length[lexCodes] - 3, out, lnEnd, lnOp, k = 0, i = 1, j = 0, c = 0, c2 = 0, cl = 0, nl = 0, kind = 0, op = 0, file = 0,
                status = 0, done = 0, scanning = 0, depth = 0, m = 0, count = 0, a = 0, len = 0, match = 0, q = 0, base = 0, real = 0, start = 0,
                tick = 0},
            out = Table[0, {5 n + 7}];
            lnEnd = Table[0, {n + 1}];
            lnOp = Table[0, {n + 1}];
            (* each \[Name]: just past it, and the operator it is, if one *)
            While[i < n,
                If[ lexCodes[[i]] == 92 && lexCodes[[i + 1]] == 91,
                    j = i + 2;
                    While[j <= n && ((48 <= lexCodes[[j]] <= 57) || (65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)), j++];
                    If[ j > i + 2 && j <= n && lexCodes[[j]] == 93,
                        lnEnd[[i]] = j + 1;
                        a = 1; op = 0;
                        While[op == 0 && a <= Length[lexLongOps],
                            len = lexLongOps[[a]];
                            If[ len == j - i - 2,
                                match = 1; q = 1;
                                While[match == 1 && q <= len, If[lexLongOps[[a + q]] != lexCodes[[i + 1 + q]], match = 0]; q++];
                                If[match == 1, op = lexLongOps[[a + len + 1]]]];
                            a += len + 2];
                        lnOp[[i]] = op]];
                i++];
            i = 1;
            While[ done == 0,
                (* whitespace, newlines and comments *)
                nl = 0; scanning = 1;
                While[ scanning == 1 && i <= n,
                    c = lexCodes[[i]]; cl = If[c > 65535, 5, lexClasses[[c + 1]]];
                    Which[
                        cl == 3, i++,
                        cl == 4, nl = 1; i++,
                        c == 92 && lnEnd[[i]] > 0 && lnOp[[i]] == lexSpecial[[8]], i = lnEnd[[i]],
                        c == 92 && lnEnd[[i]] > 0 && lnOp[[i]] == lexSpecial[[10]], nl = 1; i = lnEnd[[i]],
                        c == 40 && i < n && lexCodes[[i + 1]] == 42,
                            depth = 1; j = i + 2;
                            While[ depth > 0,
                                Which[
                                    j + 1 > n, status = 3; depth = 0,
                                    lexCodes[[j]] == 40 && lexCodes[[j + 1]] == 42, depth++; j += 2,
                                    lexCodes[[j]] == 42 && lexCodes[[j + 1]] == 41, depth--; j += 2,
                                    True, j++]];
                            i = j,
                        True, scanning = 0]];
                k++; base = 2 + 5 (k - 1);
                out[[base + 3]] = i; out[[base + 5]] = nl;
                If[ status != 0 || i > n,
                    out[[base + 1]] = 0; out[[base + 4]] = i; done = 1,
                    c = lexCodes[[i]]; cl = If[c > 65535, 5, lexClasses[[c + 1]]]; op = 0; kind = 0; j = i + 1; start = i;
                    Which[
                        (* the file of << or >>: a string, or the characters of a path *)
                        file == 1 && c == 34,
                            scanning = 1;
                            While[ scanning == 1,
                                If[ j > n, status = 3; scanning = 0,
                                    c2 = lexCodes[[j]];
                                    Which[c2 == 34, j++; scanning = 0, c2 == 92, j += 2, True, j++]]];
                            kind = 8,
                        file == 1,
                            j = i; scanning = 1;
                            While[ scanning == 1 && j <= n,
                                c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
                                Which[
                                    cl == 1 || cl == 2 || c2 == 95 || c2 == 46 || c2 == 47 || c2 == 126 || c2 == 58 || c2 == 33 || c2 == 42 || c2 == 63 || c2 == 45, j++,
                                    c2 == 92 && j + 1 <= n && lexCodes[[j + 1]] == 91, If[lnEnd[[j]] > 0, j = lnEnd[[j]], status = 1; scanning = 0],
                                    c2 == 92, j++,
                                    True, scanning = 0]];
                            If[j == i, status = 1];
                            kind = 8,
                        (* a name, a blank after it *)
                        cl == 1 || cl == 5 || (c == 92 && lnEnd[[i]] > 0 && lnOp[[i]] == -1),
                            j = i; scanning = 1;
                            While[ scanning == 1 && j <= n,
                                c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
                                Which[
                                    cl == 1 || cl == 5 || (cl == 2 && j > start), j++,
                                    c2 == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == -1, j = lnEnd[[j]],
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
                            If[ c == 46,
                                j = i + 1; While[j <= n && 48 <= lexCodes[[j]] <= 57, j++],
                                j = i; While[j <= n && 48 <= lexCodes[[j]] <= 57, j++];
                                Which[
                                    j + 2 <= n && lexCodes[[j]] == 94 && lexCodes[[j + 1]] == 94 &&
                                        ((48 <= lexCodes[[j + 2]] <= 57) || (65 <= lexCodes[[j + 2]] <= 90) || (97 <= lexCodes[[j + 2]] <= 122)),
                                        (* the base, 2 to 36, and each digit after ^^ less than it, else no number:
                                           reading stops past it *)
                                        a = 0; m = i;
                                        While[m < j, If[a <= 36, a = 10 a + lexCodes[[m]] - 48]; m++];
                                        j += 2;
                                        While[j <= n && ((48 <= lexCodes[[j]] <= 57) || (65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)), j++];
                                        If[ j <= n && lexCodes[[j]] == 46,
                                            j++; While[j <= n && ((48 <= lexCodes[[j]] <= 57) || (65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)), j++]];
                                        If[a < 2 || a > 36, status = 1];
                                        m = i;
                                        While[m < j && lexCodes[[m]] != 94, m++];
                                        m += 2;
                                        While[ m < j && status == 0,
                                            c2 = lexCodes[[m]];
                                            If[ c2 != 46 && If[c2 <= 57, c2 - 48, If[c2 <= 90, c2 - 55, c2 - 87]] >= a, status = 1];
                                            m++],
                                    j <= n && lexCodes[[j]] == 46 && ! (j + 1 <= n && lexCodes[[j + 1]] == 46),
                                        j++; While[j <= n && 48 <= lexCodes[[j]] <= 57, j++],
                                    True, j = j]];
                            (* a precision or an accuracy *)
                            If[ j <= n && lexCodes[[j]] == 96,
                                j++;
                                If[j <= n && lexCodes[[j]] == 96, j++];
                                m = If[j <= n && (lexCodes[[j]] == 43 || lexCodes[[j]] == 45), j + 1, j];
                                Which[
                                    m <= n && 48 <= lexCodes[[m]] <= 57,
                                        While[m <= n && 48 <= lexCodes[[m]] <= 57, m++];
                                        If[m <= n && lexCodes[[m]] == 46, m++; While[m <= n && 48 <= lexCodes[[m]] <= 57, m++]];
                                        j = m,
                                    m + 1 <= n && lexCodes[[m]] == 46 && 48 <= lexCodes[[m + 1]] <= 57,
                                        m++; While[m <= n && 48 <= lexCodes[[m]] <= 57, m++]; j = m,
                                    True, j = j]];
                            (* a power of the base *)
                            If[ j + 1 <= n && lexCodes[[j]] == 42 && lexCodes[[j + 1]] == 94,
                                m = If[j + 2 <= n && (lexCodes[[j + 2]] == 43 || lexCodes[[j + 2]] == 45), j + 3, j + 2];
                                If[m <= n && 48 <= lexCodes[[m]] <= 57, While[m <= n && 48 <= lexCodes[[m]] <= 57, m++]; j = m]];
                            real = 0; m = i;
                            While[m < j, If[lexCodes[[m]] == 46 || lexCodes[[m]] == 96, real = 1]; m++];
                            kind = If[real == 1, 4, 3],
                        (* a string, a slot of one *)
                        c == 34 || (c == 35 && i < n && lexCodes[[i + 1]] == 34),
                            j = If[c == 35, i + 2, i + 1]; scanning = 1;
                            While[ scanning == 1,
                                If[ j > n, status = 3; scanning = 0,
                                    c2 = lexCodes[[j]];
                                    Which[c2 == 34, j++; scanning = 0, c2 == 92, j += 2, True, j++]]];
                            kind = If[c == 35, 6, 5],
                        (* a slot: ## and its digits, or # and its digits or a name, read as a name's
                           token reads one, a name malformed making no slot *)
                        c == 35,
                            Which[
                                j <= n && lexCodes[[j]] == 35, j++; While[j <= n && 48 <= lexCodes[[j]] <= 57, j++],
                                j <= n && 48 <= lexCodes[[j]] <= 57, While[j <= n && 48 <= lexCodes[[j]] <= 57, j++],
                                j <= n && (lexCodes[[j]] > 65535 || lexClasses[[Min[lexCodes[[j]], 65535] + 1]] == 1 || lexClasses[[Min[lexCodes[[j]], 65535] + 1]] == 5 ||
                                        (lexCodes[[j]] == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == -1)),
                                    m = j; scanning = 1;
                                    While[ scanning == 1 && j <= n,
                                        c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
                                        Which[
                                            cl == 1 || cl == 5 || (cl == 2 && j > m), j++,
                                            c2 == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == -1, j = lnEnd[[j]],
                                            True, scanning = 0]];
                                    tick = 0;
                                    While[ m < j && status == 0,
                                        If[lexCodes[[m]] == 96, If[tick == 1, status = 1, tick = 1], If[tick == 1 && 48 <= lexCodes[[m]] <= 57, status = 1]; tick = 0];
                                        m++];
                                    If[tick == 1, status = 1];
                                    If[status == 1, j = i],
                                True, j = j];
                            kind = 6,
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
                            j = If[lexCodes[[i + 1]] == 40, i + 2, i + 4]; depth = 1;
                            While[ depth > 0,
                                Which[
                                    j >= n, status = 3; depth = 0; j = n + 1,
                                    lexCodes[[j]] == 92 && lexCodes[[j + 1]] == 40, depth++; j += 2,
                                    lexCodes[[j]] == 92 && lexCodes[[j + 1]] == 41, depth--; j += 2,
                                    lexCodes[[j]] == 92, j += 2,
                                    True, j++]];
                            kind = 20,
                        (* a long name, an operator's *)
                        c == 92,
                            If[ lnEnd[[i]] > 0 && lnOp[[i]] > 0,
                                op = lnOp[[i]]; j = lnEnd[[i]]; kind = If[op == lexSpecial[[9]], 18, 9],
                                If[i == n, status = 3, status = 1; j = i]],
                        (* an operator, the longest there *)
                        True,
                            len = 0;
                            If[ c < 128 && i + 2 <= n && lexCodes[[i + 1]] < 128 && lexCodes[[i + 2]] < 128,
                                a = 1;
                                While[ op == 0 && a <= Length[lexOp3],
                                    If[lexOp3[[a]] == c && lexOp3[[a + 1]] == lexCodes[[i + 1]] && lexOp3[[a + 2]] == lexCodes[[i + 2]], op = lexOp3[[a + 3]]; len = 3];
                                    a += 4]];
                            If[op == 0 && c < 128 && i + 1 <= n && lexCodes[[i + 1]] < 128, op = lexOp2[[128 c + lexCodes[[i + 1]] + 1]]; len = 2];
                            If[op == 0 && c <= 65535, op = lexOp1[[c + 1]]; len = 1];
                            (* =. before a digit: =, then a number *)
                            If[op == lexSpecial[[6]] && i + 2 <= n && 48 <= lexCodes[[i + 2]] <= 57, op = lexSpecial[[7]]; len = 1];
                            j = i + len;
                            Which[op == 0, status = 1; j = i, op == lexSpecial[[1]], kind = 16, op == lexSpecial[[2]], kind = 17, op == lexSpecial[[9]], kind = 18, True, kind = 9]];
                    (* a blank: _, __ or ___, then a . or a name *)
                    If[ kind == 2 && status == 0,
                        count = 0;
                        While[j <= n && lexCodes[[j]] == 95 && count < 3, j++; count++];
                        If[ j <= n && lexCodes[[j]] == 46,
                            j++,
                            If[ j <= n && (If[lexCodes[[j]] > 65535, 5, lexClasses[[lexCodes[[j]] + 1]]] == 1 ||
                                    If[lexCodes[[j]] > 65535, 5, lexClasses[[lexCodes[[j]] + 1]]] == 5 || (lexCodes[[j]] == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == -1)),
                                start = j; scanning = 1;
                                While[ scanning == 1 && j <= n,
                                    c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
                                    Which[
                                        cl == 1 || cl == 5 || (cl == 2 && j > start), j++,
                                        c2 == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == -1, j = lnEnd[[j]],
                                        True, scanning = 0]];
                                (* the head's context marks, as a name's *)
                                m = start; tick = 0;
                                While[ m < j && status == 0,
                                    If[lexCodes[[m]] == 96, If[tick == 1, status = 1, tick = 1], If[tick == 1 && 48 <= lexCodes[[m]] <= 57, status = 1]; tick = 0];
                                    m++];
                                If[tick == 1, status = 1];
                                If[status == 1, j = i]]]];
                    file = If[kind == 9 && (op == lexSpecial[[3]] || op == lexSpecial[[4]] || op == lexSpecial[[5]]), 1, 0];
                    out[[base + 1]] = kind; out[[base + 2]] = If[kind == 9, op, 0]; out[[base + 4]] = j;
                    If[status != 0, done = 1];
                    i = j]];
            out[[1]] = status; out[[2]] = k;
            Take[out, 2 + 5 k]]]]

(* The function of a typed declaration: the definition a compiler of typed
   code gave the declared symbol, where one did; else the declaration's
   Function compiled by Compile, where Compile is, else evaluated. *)
SetAttributes[typedFunction, HoldFirst]
typedFunction[symbol_Symbol, declaration_] := If[ DownValues[symbol] =!= {} || OwnValues[symbol] =!= {},
    symbol,
    With[{f = declaration[[2, 1]]},
        Replace[Compile @@ Join[Hold[Evaluate[Map[{#, _Integer, 1} &, f[[1]]]]], Extract[f, {2}, Hold]], Except[_CompiledFunction] -> f]]]

(* the lexer run here, fixed at its first use *)
fastLexFunction := fastLexFunction = typedFunction[fastLex, $fastLexDeclaration]

(* --- the operator table --- *)

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
        row[[2]] === "InfixNode" || row[[1]] === "Application", {p, "InfixN", head, head},
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

(* --- the operator after each token --- *)

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
$fastKindSpecIndex := $fastKindSpecIndex = Developer`ToPackedArray[ReplacePart[ConstantArray[0, 21], Join[
    {($tkOpenSquare + 1) -> fastSpecIndex[{176, "Call", "Call"}], ($tkPrimes + 1) -> fastSpecIndex[{154, "Derivative", "Derivative"}]},
    Map[(# + 1) -> fastSpecIndex[{$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}] &,
        {$tkName, $tkBlank, $tkInteger, $tkReal, $tkString, $tkSlot, $tkOut, $tkOpenParen, $tkOpenCurly, $tkOpenAssociation, $tkBoxes}]]]]
fastLedIndices[lexed_List] := fastLedFunction[lexed, $fastKindSpecIndex, $fastOpSpecIndex, $fastLedParams]
$fastLedParams := $fastLedParams = Developer`ToPackedArray[{$tkOperator, $fastEqual, $fastDot, $fastUnsetSpecIndex}]
$fastUnsetSpecIndex := $fastUnsetSpecIndex = fastSpecIndex[{9, "Unset", "Unset"}]

(* --- the typed parser --- *)

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
   2: they hold what this parser does not take; either way the third is
   the first token of the statement that stops it. It climbs as the grammar's table does, with no
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
   an integral {integral}.

   Instructions: 1 a leaf {kind, token}; 2 prefix {head}; 3 postfix
   {head}; 4 binary {head}; 5 a flat chain {head, n}; 6 a relation's
   operator {head}; 7 a relation chain {n}; 8 a call {n}; 9 a group {head,
   n}; 10 a part {n}; 11 Null; 12 All; 13 the 1 of a span begun with ;;;
   14 a message name {n}; 15 a type's parameters {n}; 16 a derivative
   {primes}; 17 a ~f~ b; 18 a span {n}; 19 a compound {n}; 20 a tag set
   {1 :=, 2 =, 3 =.}; 21 a put {head}; 22 a get; 23 a pattern; 24 an
   integral {integral}; 25 the end of a statement {its first token, the
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
        Module[{n = pTok[[2]], out, fr, maxFrames, sp = 0, on = 0, t = 1, brackets = 0, status = 0, mode = 0,
                pMin = 0, pRbp = 0, pPlain = 0, base = 0, k = 0, o = 0, i = 0, bp = 0, fx = 0, hd = 0, ky = 0, mn = 0, rb = 0, pl = 0,
                ft = 0, cnt = 0, bt = 0, colons = 0, ok = 0, x = 0, lg = 0, e = 0, we = 0, c = 0, cl = 0, tt = 0, far = 0, stmt = 1},
            out = Table[0, {3 (8 n + 16) + 2}];
            maxFrames = 4 n + 64;
            fr = Table[0, {8 maxFrames}];
            While[ mode != 99,
                Which[
                    (* a statement *)
                    mode == 0,
                        If[pTok[[5 t - 2]] == 0, mode = 99, stmt = t; pMin = 0; pRbp = 0; pPlain = 0; mode = 1],
                    (* an expression's frame *)
                    mode == 1,
                        If[ sp >= maxFrames, status = 2; mode = 99,
                            sp++; base = 8 (sp - 1); fr[[base + 1]] = 1; fr[[base + 2]] = pMin; fr[[base + 3]] = pRbp; fr[[base + 4]] = pPlain;
                            mode = 2],
                    (* the operand of the expression at the top *)
                    mode == 2,
                        base = 8 (sp - 1); mn = fr[[base + 2]]; pl = fr[[base + 4]];
                        k = pTok[[5 t - 2]]; o = pTok[[5 t - 1]];
                        Which[
                            k == 9 && pPrefix[[2 o + 1]] > mn,
                                hd = pPrefix[[2 o + 2]]; pRbp = pPrefix[[2 o + 1]]; t++;
                                sp++; base = 8 (sp - 1); fr[[base + 1]] = 2; fr[[base + 2]] = hd;
                                pMin = mn; pPlain = pl; mode = 1,
                            k == 1,
                                on++; out[[3 on]] = 1; out[[3 on + 1]] = 1; out[[3 on + 2]] = t; t++;
                                If[ pl == 0 && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[1]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                                    sp++; base = 8 (sp - 1); fr[[base + 1]] = 7; fr[[base + 2]] = t; fr[[base + 3]] = on; fr[[base + 4]] = brackets;
                                    t++; pMin = pSpecial[[16]]; pRbp = 0; pPlain = 1; mode = 1,
                                    mode = 3],
                            (k >= 2 && k <= 7) || k == 20,
                                on++; out[[3 on]] = 1; out[[3 on + 1]] = k; out[[3 on + 2]] = t; t++; mode = 3,
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
                            (* ?words, ??words: Information of the words, to the end of their last token, or of a string *)
                            k == 9 && o == pSpecial[[14]],
                                t++; lg = 0;
                                If[pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[14]] && pTok[[5 t]] == pTok[[5 t - 4]], lg = 1; t++];
                                e = pTok[[5 t - 4]];
                                While[pCodes[[e]] == 32 || pCodes[[e]] == 9, e++];
                                If[ pCodes[[e]] == 34,
                                    If[ pTok[[5 t - 2]] != 5 || pTok[[5 t]] != e, status = 2; mode = 99,
                                        on++; out[[3 on]] = 1; out[[3 on + 1]] = 5; out[[3 on + 2]] = t; t++;
                                        on++; out[[3 on]] = 29; out[[3 on + 1]] = lg; out[[3 on + 2]] = 0; mode = 3],
                                    x = e; we = e; ok = 1; tt = t;
                                    While[ ok == 1,
                                        c = pCodes[[x]]; cl = If[c > 65535, 5, pClasses[[c + 1]]];
                                        Which[
                                            cl == 1 || cl == 2 || cl == 5 || c == 42 || c == 64, x++; we = x,
                                            (* a letter's long name, in a name's token *)
                                            c == 92,
                                                While[pTok[[5 tt + 1]] <= x, tt++];
                                                If[ pTok[[5 tt - 2]] == 1 && pTok[[5 tt]] <= x && pCodes[[x + 1]] == 91,
                                                    x += 2;
                                                    While[(48 <= pCodes[[x]] && pCodes[[x]] <= 57) || (65 <= pCodes[[x]] && pCodes[[x]] <= 90) || (97 <= pCodes[[x]] && pCodes[[x]] <= 122), x++];
                                                    If[pCodes[[x]] == 93, x++; we = x, ok = 0],
                                                    ok = 0],
                                            c == 32 || c == 9, x++,
                                            True, ok = 0]];
                                    If[ we == e, mode = 5,
                                        While[pTok[[5 t - 2]] != 0 && pTok[[5 t]] < we, t++];
                                        If[ pTok[[5 t - 4]] != we, status = 2; mode = 99,
                                            on++; out[[3 on]] = 28; out[[3 on + 1]] = e; out[[3 on + 2]] = we;
                                            on++; out[[3 on]] = 29; out[[3 on + 1]] = lg; out[[3 on + 2]] = 0; mode = 3]]],
                            k == 9 && pIntegrals[[o + 1]] > 0,
                                x = pIntegrals[[o + 1]]; t++;
                                sp++; base = 8 (sp - 1); fr[[base + 1]] = 13; fr[[base + 2]] = x;
                                pMin = pSpecial[[15]]; pRbp = 0; pPlain = 0; mode = 1,
                            True, mode = 5],
                    (* after an operand: an Optional's : after a blank or a pattern, else the operator that
                       takes it, if one binds tightly enough *)
                    mode == 3,
                        base = 8 (sp - 1); mn = fr[[base + 2]]; rb = fr[[base + 3]]; pl = fr[[base + 4]];
                        i = pLed[[t]];
                        If[ pl == 0 && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[1]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1) &&
                                ((out[[3 on]] == 1 && out[[3 on + 1]] == 2 && pCodes[[pTok[[5 out[[3 on + 2]] + 1]] - 1]] != 46) || out[[3 on]] == 23),
                            t++; sp++; base = 8 (sp - 1); fr[[base + 1]] = 3; fr[[base + 2]] = pHeads[[7]];
                            pMin = mn; pRbp = pSpecial[[21]]; pPlain = 0; i = -1; mode = 1];
                        If[brackets == 0 && pTok[[5 t + 2]] == 1 && i > 0, i = 0];
                        If[ i == 0, mode = 4,
                            If[ i > 0,
                            bp = pSpecs[[4 i - 3]]; fx = pSpecs[[4 i - 2]]; hd = pSpecs[[4 i - 1]]; ky = pSpecs[[4 i]];
                            If[ bp <= rb || bp <= mn, mode = 4,
                                Which[
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
                                            cnt = 1; ok = 1; x = 0;
                                            While[ ok == 1 && x < 2,
                                                Which[
                                                    pTok[[5 t]] != colons, ok = 0; mode = 5,
                                                    pTok[[5 t - 2]] == 1, on++; out[[3 on]] = 1; out[[3 on + 1]] = 100; out[[3 on + 2]] = t; t++; cnt++,
                                                    pTok[[5 t - 2]] == 5, on++; out[[3 on]] = 1; out[[3 on + 1]] = 5; out[[3 on + 2]] = t; t++; cnt++,
                                                    pTok[[5 t - 2]] == 2, ok = 0; status = 2; mode = 99,
                                                    True, ok = 0; mode = 5];
                                                x++;
                                                If[ ok == 1 && x < 2,
                                                    If[ pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[4]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                                                        colons = pTok[[5 t + 1]]; t++,
                                                        x = 2]]];
                                            If[ok == 1, on++; out[[3 on]] = 14; out[[3 on + 1]] = cnt; out[[3 on + 2]] = 0]],
                                    fx == 9, mode = 10,
                                    fx == 10,
                                        sp++; base = 8 (sp - 1); fr[[base + 1]] = 10; fr[[base + 2]] = 1; mode = 13,
                                    fx == 11,
                                        t++;
                                        sp++; base = 8 (sp - 1); fr[[base + 1]] = 12; fr[[base + 2]] = 1;
                                        pMin = pSpecial[[19]]; pRbp = 0; pPlain = 0; mode = 1,
                                    fx == 12,
                                        t++;
                                        If[ pTok[[5 t - 2]] == 8,
                                            on++; out[[3 on]] = 1; out[[3 on + 1]] = 8; out[[3 on + 2]] = t; t++;
                                            on++; out[[3 on]] = 21; out[[3 on + 1]] = hd; out[[3 on + 2]] = 0,
                                            mode = 5],
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
                                    If[brackets == 0 && pTok[[5 t + 2]] == 1, i = 0];
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
                                (* after a ~ and its middle operand: the second ~; a postfix operator on the middle
                                   operand, then what binds more tightly than ~; a ; before the second ~, the middle
                                   a compound with Null; anything else, reading on as the kernel's reader does, to a
                                   closer or a comma, where it stops, else to the end of the source *)
                                ft == 11,
                                    If[ fr[[base + 2]] == 1,
                                        i = pLed[[t]];
                                        Which[
                                            pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[8]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                                                t++; fr[[base + 2]] = 2; pMin = fr[[base + 4]]; pRbp = fr[[base + 3]]; pPlain = fr[[base + 5]]; mode = 1,
                                            i > 0 && (pSpecs[[4 i - 2]] == 4 || pSpecs[[4 i - 2]] == 6) && pSpecs[[4 i - 1]] != pHeads[[2]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                                                on++;
                                                If[ pSpecs[[4 i - 2]] == 4,
                                                    out[[3 on]] = 3; out[[3 on + 1]] = pSpecs[[4 i - 1]]; out[[3 on + 2]] = 0,
                                                    out[[3 on]] = 16; out[[3 on + 1]] = pTok[[5 t + 1]] - pTok[[5 t]]; out[[3 on + 2]] = 0];
                                                t++; x = base;
                                                sp++; base = 8 (sp - 1); fr[[base + 1]] = 1; fr[[base + 2]] = fr[[x + 4]]; fr[[base + 3]] = fr[[x + 3]]; fr[[base + 4]] = fr[[x + 5]];
                                                mode = 3,
                                            pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[3]] && t < n && pTok[[5 t + 3]] == 9 && pTok[[5 t + 4]] == pSpecial[[8]],
                                                t++; on++; out[[3 on]] = 11; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0;
                                                on++; out[[3 on]] = 19; out[[3 on + 1]] = 2; out[[3 on + 2]] = 0,
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
                                            (brackets == 0 && pTok[[5 t + 2]] == 1) || pTok[[5 t - 2]] != 9, mode = 5,
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
                                ft == 13,
                                    on++; out[[3 on]] = 24; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = 0; sp--; mode = 3,
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
                                If[ fr[[base + 1]] == 9,
                                    on++; out[[3 on]] = 12; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 12,
                                    on++; out[[3 on]] = 11; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; fr[[base + 2]] = fr[[base + 2]] + 1; mode = 13]]],
                    (* a bracket's items: none before the closer, else the first *)
                    mode == 6,
                        base = 8 (sp - 1);
                        If[pTok[[5 t - 2]] == fr[[base + 3]] && (fr[[base + 3]] != 9 || pTok[[5 t - 1]] == fr[[base + 4]]), mode = 9, mode = 7],
                    (* an item: Null before a comma or the closer, else an expression *)
                    mode == 7,
                        base = 8 (sp - 1);
                        If[ pTok[[5 t - 2]] == 18 || (pTok[[5 t - 2]] == fr[[base + 3]] && (fr[[base + 3]] != 9 || pTok[[5 t - 1]] == fr[[base + 4]])),
                            on++; out[[3 on]] = 11; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; fr[[base + 5]] = fr[[base + 5]] + 1; mode = 8,
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
                    (* a span's operand, All where it is left out *)
                    mode == 11,
                        If[ (pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[2]]) || (brackets == 0 && pTok[[5 t + 2]] == 1) || pTok[[5 t - 2]] == 0,
                            on++; out[[3 on]] = 12; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 12,
                            sp++; base = 8 (sp - 1); fr[[base + 1]] = 8; fr[[base + 2]] = t; fr[[base + 3]] = on; fr[[base + 4]] = brackets;
                            pMin = pSpecial[[17]]; pRbp = 0; pPlain = 0; mode = 1],
                    (* after a span's operand: a second ;; and its operand, else the span *)
                    mode == 12,
                        base = 8 (sp - 1); fr[[base + 3]] = fr[[base + 3]] + 1;
                        If[ fr[[base + 2]] == 1 && pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[2]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                            t++; fr[[base + 2]] = 2; mode = 11,
                            on++; out[[3 on]] = 18; out[[3 on + 1]] = fr[[base + 3]]; out[[3 on + 2]] = 0; sp--; mode = 3],
                    (* a ; and its operand, Null where it is left out, else the compound *)
                    mode == 13,
                        If[ pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[3]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                            t++;
                            If[ (brackets == 0 && pTok[[5 t + 2]] == 1) || pTok[[5 t - 2]] == 0,
                                on++; out[[3 on]] = 11; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0;
                                base = 8 (sp - 1); fr[[base + 2]] = fr[[base + 2]] + 1,
                                sp++; base = 8 (sp - 1); fr[[base + 1]] = 8; fr[[base + 2]] = t; fr[[base + 3]] = on; fr[[base + 4]] = brackets;
                                pMin = pSpecial[[18]]; pRbp = 0; pPlain = 0; mode = 1],
                            base = 8 (sp - 1);
                            on++; out[[3 on]] = 19; out[[3 on + 1]] = fr[[base + 2]]; out[[3 on + 2]] = 0; sp--; mode = 3],
                    True, status = 2; mode = 99]];
            out[[1]] = status; out[[2]] = If[status == 1, far, on];
            If[status != 0, out[[3]] = stmt];
            Take[out, If[status == 0, 2 + 3 on, 3]]]]]

(* the parser run here, fixed at its first use *)
fastParseFunction := fastParseFunction = typedFunction[fastParse, $fastParseDeclaration]

(* --- the typed lines --- *)

(* The parts of a segment, typed code over packed integers as the lexer and the parser are: codes,
   the lexer's tokens, the program, the count of tokens that may warn before each token, the
   character classes, the newline long names {length, codes, ...}, the source's position of each
   character of the source read without its line continuations ({0} where it has none), and
   {statements read, where reading stops, 1 if a statement the grammar read is pending, the
   segment, how reading stops: 0 at the end, 3 at a failure, 4 at a statement the grammar reads,
   the segment's offset in the source read, the source's length, where the pending statement
   begins, how many positions the source read keeps} -> {rows, the slot after the lines, then each
   row {kind, start, next, segment, first instruction, last, first token, last, warnings}}, its
   start and next the source's positions. A gap's line breaks are its newlines and newline long
   names outside comments; the first after a statement, or after the one pending, ends its line,
   else the token after it does, and each after that one a Null's. The last row is where reading
   stops, or the end; a source with no statement is one Null and the end. *)
$fastLinesDeclaration = FunctionDeclaration[fastLines,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{lnCodes, lnLexed, lnProg, lnWarn, lnClasses, lnNames, lnKept, lnParams},
        Module[{nUse = lnParams[[1]], end = lnParams[[2]], pending = lnParams[[3]], seg = lnParams[[4]], stop = lnParams[[5]], offset = lnParams[[6]],
                srcLen = lnParams[[7]], pendingStart = lnParams[[8]], keptLen = lnParams[[9]], n = Length[lnCodes],
                js, nS = 0, j = 0, g = 0, lo = 0, hi = 0, p = 0, c = 0, depth = 0, k = 0, a = 0, len = 0, match = 0, q = 0,
                pass = 1, total = 0, out, rows = 0, slot = 1, breaks = 0, at = 0, ti = 0, fI = 0, lI = 0, fT = 0, tA = 0, kind = 0, base = 0,
                post = 1, lone = 0, r = 0, col = 0, v = 0},
            js = Table[0, {nUse + 1}];
            j = 1;
            While[ j <= lnProg[[2]] && nS < nUse,
                If[lnProg[[3 j]] == 25, nS++; js[[nS]] = j];
                j++];
            out = Table[0, {2}];
            While[ pass <= 2,
                If[ pass == 2,
                    lone = If[stop == 0 && pending == 0 && total == 0, 1, 0];
                    post = If[lone == 1, 2, 1];
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
                        If[ at > 0,
                            breaks++;
                            kind = If[breaks == 1 && (g > 1 || pending == 1), If[g == 1, 5, 1], 2];
                            If[pass == 1, total++,
                                rows++; base = 2 + 9 (rows - 1);
                                out[[base + 1]] = kind; out[[base + 2]] = slot; out[[base + 3]] = at;
                                If[ kind == 1,
                                    lI = js[[g - 1]]; fI = If[g == 2, 1, js[[g - 2]] + 1]; fT = lnProg[[3 lI + 1]]; tA = lnProg[[3 lI + 2]];
                                    out[[base + 4]] = seg; out[[base + 5]] = fI; out[[base + 6]] = lI; out[[base + 7]] = fT; out[[base + 8]] = tA - 1;
                                    out[[base + 9]] = lnWarn[[tA]] - lnWarn[[fT]]];
                                slot = at]];
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
            (* where reading stops, or the end; a source with no statement one Null and the end *)
            If[ lone == 1,
                out[[2 + 9 rows + 1]] = 2; out[[2 + 9 rows + 2]] = 1; out[[2 + 9 rows + 3]] = n + 2;
                out[[2 + 9 rows + 10]] = 6; out[[2 + 9 rows + 11]] = n + 2; out[[2 + 9 rows + 12]] = n + 2,
                out[[2 + 9 rows + 1]] = If[stop == 0, 6, stop]; out[[2 + 9 rows + 2]] = slot; out[[2 + 9 rows + 3]] = slot];
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
            If[lone == 1, out[[2 + 2]] = 1];
            out[[1]] = rows + post; out[[2]] = slot;
            out]]];

fastLinesFunction := fastLinesFunction = typedFunction[fastLines, $fastLinesDeclaration]
$fastNoKept = Developer`ToPackedArray[{0}];

(* --- the typed led indices and warning tokens --- *)

(* Each token's led spec index, typed code over packed integers: the lexer's tokens, the spec
   index of each kind and of each operator, by kind + 1 and operator + 1, and {the operator kind,
   =, ., the Unset spec index} -> the index of each token, that of the operator it is or of its
   kind, Unset's for an = before a . *)
$fastLedDeclaration = FunctionDeclaration[fastLed,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{ldLexed, ldKinds, ldOps, ldParams},
        Module[{n = ldLexed[[2]], out, t = 1, u = 1, kind = 0, op = 0},
            out = Table[0, {n}];
            While[ t <= n,
                kind = ldLexed[[5 t - 2]]; op = ldLexed[[5 t - 1]];
                out[[t]] = ldKinds[[kind + 1]] + If[kind == ldParams[[1]], ldOps[[op + 1]], 0];
                u = If[t < n, t + 1, 1];
                If[op == ldParams[[2]] && ldLexed[[5 u - 1]] == ldParams[[3]] && ldLexed[[5 u - 2]] == ldParams[[1]], out[[t]] = ldParams[[4]]];
                t++];
            out]]];

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
        Module[{n = wnLexed[[2]], len = Length[wnCodes], marks, out, t = 1, u = 0, kind = 0, flag = 0, m = 0, p = 0, e = 0, before = 0, top = Length[wnOpenOps] - 1},
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
            out]]];

fastWarnFunction := fastWarnFunction = typedFunction[fastWarn, $fastWarnDeclaration]

(* --- the typed statement ranges and leaves --- *)

(* Each statement of a program read whole, typed code over packed integers: the program -> {how
   many, then for each its first instruction, its last, its first token and the token after it} *)
$fastRangesDeclaration = FunctionDeclaration[fastRanges,
    Typed[{"PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{rgProg},
        Module[{n = Min[rgProg[[2]], Quotient[Length[rgProg] - 2, 3]], count = 0, j = 1, k = 0, first = 1, out},
            While[j <= n, If[rgProg[[3 j]] == 25, count++]; j++];
            out = Table[0, {1 + 4 count}];
            out[[1]] = count;
            j = 1;
            While[ j <= n,
                If[ rgProg[[3 j]] == 25,
                    out[[2 + 4 k]] = first; out[[3 + 4 k]] = j; out[[4 + 4 k]] = rgProg[[3 j + 1]]; out[[5 + 4 k]] = rgProg[[3 j + 2]];
                    k++; first = j + 1];
                j++];
            out]]];

fastRangesFunction := fastRangesFunction = typedFunction[fastRanges, $fastRangesDeclaration]

(* The leaves of a program, its instructions of code 1, typed code over packed integers: the
   program and the lexer's tokens -> {how many, the instructions, 1 if their tokens come in order,
   then each one's kind, its token, its mark, 1 for a number literal, then for each instruction
   how many leaves come before it, and last the lengths to cut the codes from the first leaf by:
   each leaf's text and the gap after it} *)
$fastLeafDeclaration = FunctionDeclaration[fastLeafCodes,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{lfProg, lfLexed},
        Module[{n = Min[lfProg[[2]], Quotient[Length[lfProg] - 2, 3]], m = 0, j = 1, k = 0, t = 0, base = 0, ordered = 1, out},
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
            out]]];

fastLeafFunction := fastLeafFunction = typedFunction[fastLeafCodes, $fastLeafDeclaration]

$fastNewlineNames := $fastNewlineNames = Developer`ToPackedArray[Flatten[Map[Join[{StringLength[#]}, ToCharacterCode[#]] &, $heldNewlineNames]]]

(* --- the typed parser's tables --- *)

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
    {$integralPrecedence, $fastPatternColon, $fastSpanOperand, $fastCompoundOperand, $fastTagLeft, $fastTagRight, $fastOptionalColon}]]
$fastHeadCodeArray := $fastHeadCodeArray = Developer`ToPackedArray[fastHeadCode /@ {"Minus", "Unset", "Paren", "List", "Association", "NotNot", "Optional"}]
$fastKeyCodeArray := $fastKeyCodeArray = Developer`ToPackedArray[fastKeyCode /@ {"Plus", "Relation", "Divisible"}]

(* --- the build pass --- *)

fastText[a_Integer, b_Integer] := FromCharacterCode[$fcodes[[a ;; b - 1]]]

$fastLeafKinds = <|1 -> "Symbol", 2 -> "Blank", 3 -> "Integer", 4 -> "Real", 5 -> "String", 6 -> "Slot", 7 -> "Out", 8 -> "File", 20 -> "Boxes", 100 -> "Tag"|>

(* the held values of a postfix program, its instructions {code, a, b} one after another, and the
   kinds, texts and marks of its leaves, those fastLeafData gives: the statements'. A value on the
   stack is its expression, held, and its mark what the kernel reads differently for it: 1 a number
   literal, into which a minus folds, 2 a product, whose factors a minus joins, 3 a name's call by
   @ or a unary plus, the name and the argument in ats, a flat chain of the name reading the
   argument, 0 anything else. The values wait in an association by their place on the stack, which a write does not
   copy, as it does a list of them, and the marks in a packed array. A leaf's value is made once for
   each kind and text, before the instructions run, as nothing is evaluated while the program is
   built. The names are Block's,
   not Module's, which would rewrite the body at every call, and each instruction is the rule of
   its code, a call or an operator of one or two operands its own rule. *)
fastBuild[steps_List, kinds_List, texts_List, marks_List] := Block[{vals = <||>, mk = ConstantArray[0, Length[steps] / 3 + 1], ats = <||>, sp = 0,
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

(* the leaves of a program, its instructions of code 1, in order, by fastLeafCodes: their kinds, their
   texts, a few one at a time, more cut from the codes in one pass where their tokens come in order, their marks, 1 for a
   number literal, and how many come before each instruction, so that the leaves of the
   instructions i to j are those from Before[[i]] + 1 to Before[[j + 1]] *)
fastLeafData[prog_List, codes_List, lexed_List] := With[{d = fastLeafFunction[prog, lexed]},
    With[{m = d[[1]], n = d[[2]]},
        <|"Kinds" -> d[[4 ;; 3 + m]],
          "Texts" -> Which[
            m === 0, {},
            m <= 8, Table[FromCharacterCode[codes[[lexed[[5 d[[3 + m + i]]]] ;; lexed[[5 d[[3 + m + i]] + 1]] - 1]]], {i, m}],
            d[[3]] === 1, FromCharacterCode[TakeList[codes[[lexed[[5 d[[4 + m]]]] ;; lexed[[5 d[[3 + 2 m]] + 1]] - 1]], d[[5 + 3 m + n ;;]]][[1 ;; ;; 2]]],
            True, tokenTexts[codes, lexed[[5 d[[4 + m ;; 3 + 2 m]]]], lexed[[5 d[[4 + m ;; 3 + 2 m]] + 1]]]],
          "Marks" -> d[[4 + 2 m ;; 3 + 3 m]], "Before" -> d[[4 + 3 m ;; 4 + 3 m + n]]|>]]

(* the texts of the tokens from st to en in codes, in order, in one pass where they are *)
tokenTexts[codes_List, st_List, en_List] := Which[
    st === {}, {},
    Length[st] === 1 || Min[Rest[st] - Most[en]] >= 0, FromCharacterCode[TakeList[codes[[st[[1]] ;; en[[-1]] - 1]], Riffle[en - st, Rest[st] - Most[en]]][[1 ;; ;; 2]]],
    True, Table[FromCharacterCode[codes[[st[[i]] ;; en[[i]] - 1]]], {i, Length[st]}]]

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
fastStep[5, a_, 2] := (sp--;
    vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]],
        If[$fastSpliceHeads[[a]] === 1 && (mk[[sp]] === 3 || mk[[sp + 1]] === 3), splicedAt[a, {sp, sp + 1}], {vals[sp], vals[sp + 1]}]];
    mk[[sp]] = If[a === $fastTimesHead, 2, 0])
fastStep[5, a_, b_] := (xs = Range[sp - b + 1, sp]; sp -= b - 1;
    vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], If[$fastSpliceHeads[[a]] === 1 && MemberQ[mk[[xs]], 3], splicedAt[a, xs], Lookup[vals, xs]]];
    mk[[sp]] = If[a === $fastTimesHead, 2, 0])
fastStep[9, a_, b_] := If[ a === $fastParenHead, mk[[sp]] = If[mk[[sp]] === 1, 1, 0],
    xs = Lookup[vals, Range[sp - b + 1, sp]]; sp -= b - 1; vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], xs]; mk[[sp]] = 0]
fastStep[19, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = symbolCall["CompoundExpression", xs]; mk[[sp]] = 0)
fastStep[2, a_, _] := Which[
    a === $fastMinusHead, vals[sp] = negatedHeld[vals[sp], mk[[sp]]]; mk[[sp]] = 0,
    a === $fastPlusHead, ats[sp] = {heldSymbol["Plus"], vals[sp]}; vals[sp] = heldCall[ats[sp][[1]], {vals[sp]}]; mk[[sp]] = 3,
    True, vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], {vals[sp]}]; mk[[sp]] = 0]
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
fastStep[24, a_, _] := (spec = $fastIntegralList[[a]];
    vals[sp] = If[spec[[2]] === Integrate, integralHeld[spec[[1]], vals[sp]], symbolCall[spec[[1]], {vals[sp]}]]; mk[[sp]] = 0)
fastStep[26, a_, _] := (xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = symbolCall["Divisible", Reverse[xs]]; mk[[sp]] = 0)
fastStep[27, _, _] := (vals[sp] = symbolCall["Not", {symbolCall["Not", {vals[sp]}]}]; mk[[sp]] = 0)
fastStep[28, a_, b_] := (sp++; vals[sp] = heldLeafValue["String", "\"" <> StringReplace[fastText[a, b], "\t" -> " "] <> "\""]; mk[[sp]] = 0)
fastStep[29, a_, _] := (vals[sp] = symbolCall["Information", {vals[sp], symbolCall["Rule", {heldSymbol["LongForm"], heldSymbol[If[a === 1, "True", "False"]]}]}];
    mk[[sp]] = 0)

(* the head codes the build pass reads apart, and the heads whose flat chain reads a call of the
   head by @ as its argument *)
$fastMinusHead := $fastMinusHead = fastHeadCode["Minus"]
$fastPlusHead := $fastPlusHead = fastHeadCode["Plus"]
$fastParenHead := $fastParenHead = fastHeadCode["Paren"]
$fastTimesHead := $fastTimesHead = fastHeadCode["Times"]
$fastAtHead := $fastAtHead = fastHeadCode["At"]
$fastSlashSlashHead := $fastSlashSlashHead = fastHeadCode["SlashSlash"]
$fastDivideHead := $fastDivideHead = fastHeadCode["Divide"]
$fastSpliceHeads := $fastSpliceHeads = Boole[KeyExistsQ[$atSpliceHeads, #] & /@ $fastHeadNames]

(* the binary operator of code 4 on the value at the top and y: f @ x the call, marked as the
   name's where f is one; x // f the call of f; a/b Times[a, Power[b, -1]]; the rest the call of its
   head *)
fastBinary[a_Integer, y_] := Which[
    a === $fastAtHead,
        If[MatchQ[vals[sp], HoldComplete[_Symbol]], ats[sp] = {vals[sp], y}; mk[[sp]] = 3, mk[[sp]] = 0]; vals[sp] = heldCall[vals[sp], {y}],
    a === $fastSlashSlashHead, vals[sp] = heldCall[y, {vals[sp]}]; mk[[sp]] = 0,
    a === $fastDivideHead, vals[sp] = binaryHeld["Divide", vals[sp], y]; mk[[sp]] = 0,
    True, vals[sp] = heldCall[heldSymbol[$fastHeadNames[[a]]], {vals[sp], y}]; mk[[sp]] = 0]

(* a chain of relations: of one kind, not a vector one, the call of its head; else as the held
   algebra reads it *)
relationHeld[xs_List, {h_String ..}] /; ! KeyExistsQ[$vectorRelations, h] := symbolCall[h, xs]
relationHeld[xs_List, heads_List] := relationValue[WolframLanguageSemantic, held /@ xs, heads]["Expr"]

(* the operands of the flat chain of head a at the slots, a call of the head by @ its argument *)
splicedAt[a_Integer, slots_List] := With[{h = heldSymbol[$fastHeadNames[[a]]]}, Map[If[mk[[#]] === 3 && ats[#][[1]] === h, ats[#][[2]], vals[#]] &, slots]]

(* the source's top-level expressions, held, by the lexer, the parser and
   the build pass; source that is no Wolfram Language a failure where the
   kernel's reader stops, and the grammar reads what they do not take *)
fastHeld[s_String] := Catch[Block[{codes = ToCharacterCode[s], padded, lexed, cut, prog},
    padded = Join[codes, {0, 0, 0}];
    lexed = fastLexFunction[padded, $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial];
    (* the lexer stops at its last token: reading stops there, or at a statement before it that
       cannot be read *)
    If[ lexed[[1]] =!= 0,
        cut = tokensBefore[lexed, lexed[[2]]];
        prog = fastParseTokens[cut, padded];
        Which[
            prog[[1]] === 2, fastGiveUp[],
            prog[[1]] === 1 && prog[[2]] < lexed[[2]], Throw[stoppedFailure[cut, prog[[2]]], $fastGiveUp],
            True, Throw[lexerFailure[lexed, Length[codes]], $fastGiveUp]]];
    prog = fastParseTokens[lexed, padded];
    Switch[ prog[[1]],
        0, Null,
        1, Throw[stoppedFailure[lexed, prog[[2]]], $fastGiveUp],
        _, fastGiveUp[]];
    Block[{$fcodes = codes, $fs = lexed[[5 ;; ;; 5]], $fe = lexed[[6 ;; ;; 5]]},
        With[{leaves = fastLeafData[prog, codes, lexed]},
            fastBuild[prog[[3 ;; 3 prog[[2]] + 2]], leaves["Kinds"], leaves["Texts"], leaves["Marks"]]]]], $fastGiveUp]

(* the typed parser over the lexer's tokens of a source, its codes padded *)
fastParseTokens[lexed_List, padded_List] := fastParseFunction[lexed, fastLedIndices[lexed], $fastSpecTable,
    $fastPrefixArray, $fastGroupArray, $fastIntegralArray, $fastSpecialArray, $fastHeadCodeArray, $fastKeyCodeArray, padded, $fastClasses]

(* --- statements one at a time --- *)

(* The parts of a source that reading it one statement at a time gives, as the kernel's
   ToExpression gives them: each statement, and the Null of each line that holds none. A line ends
   at each return, each newline and each long name that is a newline, outside comments; a
   statement's line is the one it ends on, each line after it with only whitespace and comments on
   it is a Null, and the last line of the source is one only where the source holds nothing else.
   Reading stops at the first statement that cannot be read. Each part is a row of integers,
   {kind, where its line begins, where the line after it does, then for a statement its segment,
   its first instruction and its last, its first token and its last, and how many of its tokens may
   give a warning}, positions of the source; the kinds are 1 a statement, 2 a Null, 3 a failure, 4 a
   statement the grammar reads, 5 one it has read and 6 the end. The "Data" of a part, by its place,
   are a failure, a statement the grammar reads {at the character of the source read, its segment,
   its token}, and one it has read {held, its warnings}. A source's parts are made at its first call
   and kept for the calls on it after, until one reads its end or its failure, those of the last few
   sources. *)
$heldNextStates = {};

(* the place in $heldNextStates of the parts of s, made now if they are not there *)
heldNextState[s_String] := Block[{i = 1},
    While[i <= Length[$heldNextStates] && $heldNextStates[[i]]["Source"] =!= s, i++];
    If[ i <= Length[$heldNextStates], i,
        $heldNextStates = Take[Prepend[$heldNextStates, makeHeldNextState[s]], UpTo[4]]; 1]]

makeHeldNextState[s_String] := With[{spans = lineContinuations[s]},
    With[{clean = If[spans === {}, s, StringReplacePart[s, "", spans]]},
        segmentParts[<|"Source" -> s, "Clean" -> clean, "Kept" -> If[spans === {}, None, keptPositions[s, spans]],
            "Codes" -> ToCharacterCode[clean], "Segments" -> {}, "Parts" -> {}, "Data" -> <||>, "Index" -> <||>|>, 1, None]]]

(* a position in the source read without its line continuations, in the source, and those of a list *)
sourcePosition[state_Association, c_Integer] := With[{kept = state["Kept"]},
    Which[kept === None, c, c <= Length[kept], kept[[c]], True, StringLength[state["Source"]] + c - Length[kept]]]
sourcePositions[state_Association, cs_List] := With[{kept = state["Kept"]},
    If[kept === None, cs, Join[kept, StringLength[state["Source"]] + {1, 2}][[cs]]]]

(* a failure of the source read from its character from on, without its line continuations, at the
   character of the source it is at *)
sourceFailure[state_Association, f_Failure, from_Integer] := With[{p = sourcePosition[state, f["Position"] + from - 1]},
    Failure[f[[1]], Join[f[[2]], <|"Position" -> p, "MessageParameters" -> Append[Lookup[f[[2]], "MessageParameters", <||>], "Position" -> p]|>]]]

(* the lexer's tokens 1 to k - 1, then the end, where token k begins *)
tokensBefore[lexed_List, k_Integer] := Developer`ToPackedArray[Join[{0, k}, lexed[[3 ;; 2 + 5 (k - 1)]], {0, 0, lexed[[5 k]], lexed[[5 k]], lexed[[5 k + 2]]}]]

(* each statement of a program read whole: {its first instruction, its last, its first token, the token after it} *)
statementRanges[prog_List] := With[{r = fastRangesFunction[prog]}, If[r[[1]] === 0, {}, Partition[r[[2 ;;]], 4]]]

(* where the lexer stops, the failure: the source ends in a string or a comment not closed, or
   holds a character no token has *)
lexerFailure[lexed_List, n_Integer] := If[lexed[[1]] === 3, fastFailure[n + 1, True], fastFailure[lexed[[5 lexed[[2]] + 1]], False]]

(* The state, the parts of the source read from its character from on appended to its parts and
   the segment they are read from to its segments. The statement pending before them, if one, is the
   one the grammar has just read, <|"Start", "Expr", "Warnings"|>, whose line the first line break
   after it ends. The names are Block's: Module would rewrite the body at every call. *)
segmentParts[state_Association, from_Integer, pending_] := Block[
    {st = state, offset = from - 1, codes, padded, lexed, prog, first = None, stop = None, k, cut, ranges, seg, data = state["Data"],
     n0 = Length[state["Parts"]], end, made},
    codes = If[from === 1, state["Codes"], Drop[state["Codes"], offset]];
    padded = Join[codes, {0, 0, 0}];
    lexed = fastLexFunction[padded, $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial];
    (* a token, or a character no token has, on the line of the statement the grammar read: that
       statement cannot be read *)
    If[ pending =!= None && lexed[[7]] === 0 && (lexed[[3]] =!= $tkEnd || lexed[[1]] =!= 0),
        st["Parts"] = Append[st["Parts"], {3, pending["Start"], pending["Start"], 0, 0, 0, 0, 0, 0}];
        st["Data"] = Append[data, Length[st["Parts"]] -> warned[sourceFailure[st, If[lexed[[1]] === 0, stoppedFailure[lexed, 1], lexerFailure[lexed, Length[codes]]], from],
            Join[pending["Warnings"], tokenWarnings[codes, lexed, 1, 1]]]];
        Return[st, Block]];
    Which[
        lexed[[1]] === 0,
            prog = fastParseTokens[lexed, padded];
            Switch[ prog[[1]],
                0, Null,
                1, first = prog[[3]]; stop = {"Failure", stoppedFailure[lexed, prog[[2]]], prog[[2]], prog[[2]]},
                _, first = prog[[3]]; stop = {"Grammar"}],
        (* the lexer stops at its last token: the statements before it are read, and the one where
           reading stops is the first that cannot be, the one that holds the token or one before it *)
        True,
            k = lexed[[2]]; cut = tokensBefore[lexed, k];
            prog = fastParseTokens[cut, padded];
            Which[
                prog[[1]] === 2, first = prog[[3]]; stop = {"Grammar"},
                prog[[1]] === 1 && prog[[2]] < k, first = prog[[3]]; stop = {"Failure", stoppedFailure[cut, prog[[2]]], prog[[2]], prog[[2]]},
                True, first = If[prog[[1]] === 1, prog[[3]], k]; stop = {"Failure", lexerFailure[lexed, Length[codes]], k, 0}]];
    (* the statements before the one where reading stops, but those on its line, which the
       kernel reads with it *)
    ranges = If[ first === None, statementRanges[prog],
        prog = fastParseTokens[tokensBefore[lexed, first], padded];
        statementRanges[prog]];
    While[first =!= None && ranges =!= {} && lexed[[5 first + 2]] === 0, first = ranges[[-1, 3]]; ranges = Most[ranges]];
    seg = Length[st["Segments"]] + 1;
    st["Segments"] = Append[st["Segments"], <|"Codes" -> codes, "Lexed" -> lexed, "Starts" -> lexed[[5 ;; ;; 5]], "Ends" -> lexed[[6 ;; ;; 5]], "Program" -> prog,
        "Warning" -> warningTokens[codes, lexed], "Leaves" -> fastLeafData[prog, codes, lexed]|>];
    (* The lines, positions of the segment: the Nulls of the gap before the first statement, each
       statement and the Nulls of the gap after it, then where reading stops or the end. The first
       line break after a statement, or after the one pending, ends its line, else the token after
       it does; each break after that one ends a Null's. *)
    end = If[first === None, Length[codes] + 1, lexed[[5 first]]];
    made = fastLinesFunction[codes, lexed, prog, st["Segments"][[seg, "Warning", 2]], $fastClasses, $fastNewlineNames,
        If[st["Kept"] === None, $fastNoKept, Developer`ToPackedArray[st["Kept"]]],
        Developer`ToPackedArray[{Length[ranges], end, If[pending === None, 0, 1], seg, Which[stop === None, 0, stop[[1]] === "Failure", 3, True, 4], offset,
            StringLength[st["Source"]], If[pending === None, 0, pending["Start"]], If[st["Kept"] === None, 0, Length[st["Kept"]]]}]];
    made = Partition[made[[3 ;;]], 9];
    If[pending =!= None, data[n0 + 1] = {pending["Expr"], pending["Warnings"]}];
    Which[
        stop =!= None && stop[[1]] === "Failure",
            data[n0 + Length[made]] = warned[sourceFailure[st, stop[[2]], from], tokenWarnings[codes, lexed, first, stop[[3]], stop[[4]]]],
        stop =!= None,
            data[n0 + Length[made]] = {end + offset, seg, first}];
    st["Parts"] = Join[st["Parts"], made];
    st["Data"] = data;
    st["Index"] = AssociationThread[st["Parts"][[All, 2]] -> Range[Length[st["Parts"]]]];
    st]

(* --- warnings --- *)

(* The warnings the kernel's reader gives as it reads tokens from to to of a lexed source, codes
   its characters [WL 15.0.0]: {"com"} for each Null a comma leaves, after the opener of a bracket
   or before another comma, its closer, the end or the token stop that reading stops at, which
   begins no operand; those of each string's escapes; and where the lexer stops at a long name,
   {"sntufn", name} for one no character has or not closed, {"sntmsng", text} for one with no name
   before a quote, text the source from the statement on. *)
tokenWarnings[codes_List, lexed_List, from_Integer, to_Integer, stop_Integer : 0] := With[{kinds = lexed[[5 from - 2 ;; 5 to - 2 ;; 5]]},
    warningsAt[codes, lexed, from, to, stop, from - 1 + Flatten[Position[Unitize[(kinds - $tkString) (kinds - $tkComma) kinds], 0]]]]

(* the warnings of tokens from to to that come from the tokens ts among them *)
warningsAt[codes_List, lexed_List, from_Integer, to_Integer, stop_Integer, ts_List] := Module[{out = Internal`Bag[], k, text},
    text := FromCharacterCode[codes[[lexed[[5 from]] ;;]]];
    Do[ k = lexed[[5 t - 2]];
            Which[
                k === $tkString,
                    With[{string = codes[[lexed[[5 t]] ;; Min[lexed[[5 t + 1]] - 1, Length[codes]]]]},
                        If[ MemberQ[string, 92],
                            Scan[Internal`StuffBag[out, Replace[#, {"sntmsng"} :> {"sntmsng", text}]] &, stringWarnings[FromCharacterCode[string], lexed[[1]] === 3 && t === lexed[[2]]]]]],
                k === $tkComma,
                    If[t > from && bracketQ[lexed, t - 1, $warnOpeners], Internal`StuffBag[out, {"com"}]];
                    If[t < to && (lexed[[5 t + 3]] === $tkComma || bracketQ[lexed, t + 1, $warnClosers] || t + 1 === stop), Internal`StuffBag[out, {"com"}]],
                k === $tkEnd && t === lexed[[2]] && lexed[[1]] === 1 && codes[[lexed[[5 t]]]] === 92 && lexed[[5 t]] < Length[codes] && codes[[lexed[[5 t]] + 1]] === 91,
                    With[{name = longNameText[codes, lexed[[5 t]] + 2]},
                        Which[
                            name === "", If[lexed[[5 t]] + 2 <= Length[codes] && codes[[lexed[[5 t]] + 2]] === 34, Internal`StuffBag[out, {"sntmsng", text}]],
                            ! (lexed[[5 t]] + 2 + StringLength[name] <= Length[codes] && codes[[lexed[[5 t]] + 2 + StringLength[name]]] === 93 &&
                                KeyExistsQ[longNameCharacters[], name]),
                                Internal`StuffBag[out, {"sntufn", name}]]]],
        {t, ts}];
    Internal`BagPart[out, All]]

(* The tokens of a lexed source a statement's warning may come from, each read in one pass: a
   comma after a token that opens a bracket or before one that closes it, a comma or the end, and a
   string with a \ in it. With them, for each token t, how many come before it. *)
warningTokens[codes_List, lexed_List] := With[{w = fastWarnFunction[codes, lexed, $openKindFlags, $closeKindFlags, $warnOpenOps, $warnCloseOps, $fastWarnParams]},
    {w[[2 ;; w[[1]] + 1]], w[[w[[1]] + 2 ;;]]}]
$fastWarnParams := $fastWarnParams = Developer`ToPackedArray[{$tkOperator, $tkComma, $tkString}]

(* the kinds of token that open a bracket's items, and that close them, by kind + 1, and the
   operators that do, the long-name brackets, by operator + 1 *)
$openKindFlags = Developer`ToPackedArray[ReplacePart[ConstantArray[0, 21], Thread[{12, 14, 16} + 1 -> 1]]];
$closeKindFlags = Developer`ToPackedArray[ReplacePart[ConstantArray[0, 21], Thread[{0, 13, 15, 17, 18} + 1 -> 1]]];
$warnOpenOps := $warnOpenOps = Developer`ToPackedArray[ReplacePart[ConstantArray[0, $fastNotId + 2],
    Thread[(Append[Keys[$fastGroupTable], fastLongOp["LeftDoubleBracket"]] + 1) -> 1]]]
$warnCloseOps := $warnCloseOps = Developer`ToPackedArray[ReplacePart[ConstantArray[0, $fastNotId + 2],
    Thread[(Append[Values[$fastGroupTable][[All, 1]], $fastRightDoubleBracket] + 1) -> 1]]]

(* the letters and digits of a long name's name, from its character i on *)
longNameText[codes_List, i_Integer] := FromCharacterCode[TakeWhile[codes[[i ;;]], 48 <= # <= 57 || 65 <= # <= 90 || 97 <= # <= 122 &]]

(* token t of a lexed source opens, or closes, a bracket's items: its kind, or the long name it
   is; the end of the source closes them too, where the lexer reads it *)
bracketQ[lexed_List, t_Integer, ops_Association] := With[{k = lexed[[5 t - 2]]},
    Which[
        k === $tkOperator, KeyExistsQ[ops, lexed[[5 t - 1]]],
        k === $tkEnd, ops === $warnClosers && (lexed[[1]] =!= 1 || t < lexed[[2]]),
        True, MemberQ[ops["Kinds"], k]]]

$warnOpeners := $warnOpeners = Join[<|"Kinds" -> {$tkOpenSquare, $tkOpenCurly, $tkOpenAssociation}|>,
    AssociationThread[Append[Keys[$fastGroupTable], fastLongOp["LeftDoubleBracket"]] -> True]]
$warnClosers := $warnClosers = Join[<|"Kinds" -> {$tkCloseSquare, $tkCloseCurly, $tkCloseAssociation}|>,
    AssociationThread[Append[Values[$fastGroupTable][[All, 1]], $fastRightDoubleBracket] -> True]]

(* The warnings of the escapes a string keeps as written [WL 15.0.0]: too few digits of a code,
   a letter no escape has, a long name no character has, or not closed before the string is, the
   string closed, and
   {"sntmsng"} for a long name with no name at its end, which the statement's text completes;
   unclosed, the string goes on to its token's end. *)
stringWarnings[s_String, unclosed_] := StringCases[If[TrueQ[unclosed], StringDrop[s, 1], StringTake[s, {2, -2}]], Join[
    Map[First[#] -> Nothing &, $escapes], {
    "\\" ~~ CharacterRange["0", "7"] -> {"sntoct1"},
    "\\." -> {"sntoct2"},
    "\\:" -> {"snthex"},
    "\\|" -> {"snthex32"},
    "\\[" ~~ name : $nameCharacter .. ~~ EndOfString :> {If[TrueQ[unclosed], "sntufn", "sntunc"], name},
    "\\[" ~~ name : $nameCharacter .. :> {"sntufn", name},
    "\\[" ~~ EndOfString -> {"sntmsng"},
    "\\" ~~ c : (CharacterRange["a", "z"] | CharacterRange["A", "Z"]) :> {"stresc", c},
    "\\" ~~ _ -> Nothing}]]

$nameCharacter = CharacterRange["a", "z"] | CharacterRange["A", "Z"] | CharacterRange["0", "9"];

(* a failure with the warnings of the statement that cannot be read *)
warned[f_Failure, warnings_List] := Failure[f[[1]], Append[f[[2]], "Warnings" -> warnings]]

(* the warnings of the statement of a row, from the tokens of its segment that may give one *)
statementWarnings[state_Association, row_List] := With[{segment = state["Segments"][[row[[4]]]]},
    With[{before = segment["Warning"][[2]]},
        warningsAt[segment["Codes"], segment["Lexed"], row[[7]], row[[8]], 0, segment["Warning"][[1, before[[row[[7]]]] + 1 ;; before[[row[[8]] + 1]]]]]]]

(* the statement of a row, held, its names made now: its instructions, and its leaves among the
   segment's *)
heldNextStatement[state_Association, row_List] := Block[{$nextSegment = state["Segments"][[row[[4]]]], $nextLeaves, $nextSpan, $fcodes, $fs, $fe},
    $nextLeaves = $nextSegment["Leaves"];
    $nextSpan = $nextLeaves["Before"][[row[[5]]]] + 1 ;; $nextLeaves["Before"][[row[[6]] + 1]];
    $fcodes = $nextSegment["Codes"]; $fs = $nextSegment["Starts"]; $fe = $nextSegment["Ends"];
    First[fastBuild[$nextSegment["Program"][[3 row[[5]] ;; 3 row[[6]] + 2]], $nextLeaves["Kinds"][[$nextSpan]], $nextLeaves["Texts"][[$nextSpan]],
        $nextLeaves["Marks"][[$nextSpan]]]]]

(* the state, its part i, the last, a statement the grammar reads, read: a failure, or the statement,
   and the parts of the source after it read *)
grammarStatement[state_Association, i_Integer] := Module[{st = state, start = state["Parts"][[i, 2]], at, token, segment, clean = state["Clean"], r, upTo},
    {at, segment, token} = MapAt[st["Segments"][[#]] &, state["Data"][i], 2];
    r = ParsePartial[$heldGrammar["Expression"], StringDrop[clean, at - 1]];
    (* the warnings of the tokens of the statement, those that begin before the character x *)
    upTo = Function[x, tokenWarnings[segment["Codes"], segment["Lexed"], token,
        token - 1 + LengthWhile[segment["Starts"][[token ;; segment["Lexed"][[2]]]], # + at - segment["Starts"][[token]] < x &]]];
    st["Parts"] = Most[st["Parts"]];
    st["Data"] = KeyDrop[st["Data"], i];
    If[ FailureQ[r],
        st["Parts"] = Append[st["Parts"], {3, start, start, 0, 0, 0, 0, 0, 0}];
        st["Data"] = Append[st["Data"], i -> warned[grammarFailure[sourceFailure[st, r, at], StringLength[st["Source"]]], upTo[r["Position"] + at - 1]]];
        st,
        segmentParts[st, StringLength[clean] + 1 - StringLength[r[[2]]],
            <|"Start" -> start, "Expr" -> r[[1]]["Expr"], "Warnings" -> upTo[StringLength[clean] + 1 - StringLength[r[[2]]]]|>]]]

(* the statement of the source s whose line begins at pos, 1 or the position the call before gave *)
WolframLanguageHeldNext[s_String, pos_Integer] := Block[{j = heldNextState[s], state, i, row},
    state = $heldNextStates[[j]];
    i = Lookup[state["Index"], pos, 0];
    If[i === 0, i = Min[LengthWhile[state["Parts"][[All, 2]], # < pos &] + 1, Length[state["Parts"]]]];
    If[ state["Parts"][[i, 1]] === 4,
        state = grammarStatement[state, i]; $heldNextStates[[j]] = state];
    row = state["Parts"][[i]];
    Switch[ row[[1]],
        1, {heldNextStatement[state, row], row[[3]], <|"Warnings" -> If[row[[9]] === 0, {}, statementWarnings[state, row]]|>},
        2, {HoldComplete[Null], row[[3]], <|"Warnings" -> {}|>},
        5, {state["Data"][i][[1]], row[[3]], <|"Warnings" -> state["Data"][i][[2]]|>},
        3, $heldNextStates = Delete[$heldNextStates, j]; {state["Data"][i], row[[2]]},
        _, $heldNextStates = Delete[$heldNextStates, j]; EndOfFile]]

(* each statement of s read one at a time, but the Nulls, or the failure of the first that cannot be read *)
heldStatements[s_String] := Module[{pos = 1, r, out = Internal`Bag[]},
    While[ ListQ[r = WolframLanguageHeldNext[s, pos]],
        If[FailureQ[First[r]], Return[First[r], Module]];
        If[First[r] =!= HoldComplete[Null], Internal`StuffBag[out, First[r]]];
        pos = r[[2]]];
    Internal`BagPart[out, All]]

(* --- syntax alone --- *)

(* Where reading a source stops, as the kernel's SyntaxLength counts the characters before it, or
   None where the source reads: by the lexer and the parser alone, no expression built, but for a
   statement only the grammar reads. A source that ends before its expression does stops past its
   end, by 2. Reading stops
   - before the token no Wolfram Language reaches, a line continuation before it its own, but
     after a name or a number the name's or the number's;
   - at a :: with no tag after it that touches the symbol of its message name, else before it;
   - at the end of the last operand of a /: with no assignment after it;
   - at a comment or a string the source does not close, for a string that begins a statement
     after the first line at the newline before it;
   - before a long name no character has, or a malformed name, from the name it is in;
   and at the end of the source where a comment, a string or a name of these is its first token. *)
syntaxStop[s_String] := Module[{spans = lineContinuations[s], clean, kept, codes, padded, lexed, prog, k, cut, source, length = StringLength[s]},
    clean = If[spans === {}, s, StringReplacePart[s, "", spans]];
    kept = If[spans === {}, None, keptPositions[s, spans]];
    codes = ToCharacterCode[clean]; padded = Join[codes, {0, 0, 0}];
    (* a token's place in the source, the line continuations before it its own *)
    source = Function[c, Which[
        kept === None, c, c === 1, 1, c > Length[kept], length + c - Length[kept],
        LetterQ[FromCharacterCode[codes[[c - 1]]]] || DigitQ[FromCharacterCode[codes[[c - 1]]]] || MemberQ[{36, 96}, codes[[c - 1]]], kept[[c]],
        True, kept[[c - 1]] + 1]];
    lexed = fastLexFunction[padded, $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial];
    If[ lexed[[1]] === 0,
        prog = fastParseTokens[lexed, padded];
        Switch[prog[[1]], 0, None, 1, parserStop[lexed, prog[[2]], prog[[3]], source, length], _, grammarStop[s]],
        k = lexed[[2]]; cut = tokensBefore[lexed, k];
        prog = fastParseTokens[cut, padded];
        Which[
            prog[[1]] === 2, grammarStop[s],
            prog[[1]] === 1 && prog[[2]] < k, parserStop[cut, prog[[2]], prog[[3]], source, length],
            lexed[[1]] === 3 && lexed[[5 k - 2]] === $tkBoxes, length + 2,
            lexed[[1]] === 3 && lexed[[5 k - 2]] === $tkString && lexed[[5 k + 2]] === 1 && prog[[1]] === 0, source[lastNewline[codes, lexed[[5 k]]]],
            lexed[[1]] === 3 && lexed[[5 k - 2]] === $tkString, With[{p = source[lexed[[5 k]]]}, If[p === 1, length, p]],
            lexed[[1]] === 3, With[{p = source[unclosedComment[codes, If[k > 1, lexed[[5 (k - 1) + 1]], 1]]]}, If[p === 1, length, p]],
            lexed[[5 k + 2]] === 1 && prog[[1]] === 0 && lexed[[5 k]] <= Length[codes] && (codes[[lexed[[5 k]]]] === 96 || LetterQ[FromCharacterCode[codes[[lexed[[5 k]]]]]]),
                source[lastNewline[codes, lexed[[5 k]]]],
            True, With[{t = If[k > 1 && lexed[[5 (k - 1) - 2]] === $tkName && lexed[[5 (k - 1) + 1]] === lexed[[5 k]] && codes[[lexed[[5 k]]]] === 92 &&
                    lexed[[5 k]] < Length[codes] && codes[[lexed[[5 k]] + 1]] === 91, k - 1, k]},
                With[{p = source[lexed[[5 t]]]}, If[p === 1 && (codes[[lexed[[5 t]]]] === 92 || lexed[[5 t - 2]] === $tkName || lexed[[5 t - 2]] === $tkSlot ||
                    LetterQ[FromCharacterCode[codes[[lexed[[5 t]]]]]]), length, p - 1]]]]]]

(* the last newline before the character at *)
lastNewline[codes_List, at_Integer] := Block[{i = at - 1}, While[i > 1 && codes[[i]] =!= 10 && codes[[i]] =!= 13, i--]; i]

(* where the comment that the gap from a on holds and the source does not close begins *)
unclosedComment[codes_List, a_Integer] := Block[{i = a, depth = 0, open = a, n = Length[codes]},
    While[ i <= n,
        Which[
            codes[[i]] === 40 && i < n && codes[[i + 1]] === 42, If[depth === 0, open = i]; depth++; i += 2,
            codes[[i]] === 42 && i < n && codes[[i + 1]] === 41 && depth > 0, depth--; i += 2,
            True, i++]];
    open]

(* reading stops at token t of the statement from token stmt *)
parserStop[lexed_List, t_Integer, stmt_Integer, source_, length_Integer] := With[{before = If[t > 1, lexed[[5 (t - 1) - 1]], 0], kindBefore = If[t > 1, lexed[[5 (t - 1) - 2]], 0]},
    Which[
        kindBefore === $tkOperator && before === $fastColonColon,
            If[ t > 2 && lexed[[5 (t - 2) - 2]] === $tkName && lexed[[5 (t - 2) + 1]] === lexed[[5 (t - 1)]] &&
                    ! (t > 3 && lexed[[5 (t - 3) - 2]] === $tkOperator && lexed[[5 (t - 3) - 1]] === $fastColonColon),
                source[lexed[[5 (t - 1)]]], source[lexed[[5 (t - 1)]]] - 1],
        lexed[[5 t - 2]] =!= $tkEnd, source[lexed[[5 t]]] - 1,
        kindBefore === $tkOperator && before === $fastGet, If[source[lexed[[5 (t - 1)]]] === 1, length, source[lexed[[5 (t - 1)]]] - 1],
        kindBefore === $tkOperator && MemberQ[{$fastPut, $fastPutAppend}, before], source[lexed[[5 (t - 1)]]] - 1,
        tagSetOpen[lexed, stmt, t - 1], source[lexed[[5 (t - 1) + 1]]] - 1,
        True, length + 2]]

(* the tokens from stmt to last hold a /: with no =, := or =. after it, outside brackets, all closed, and the last ends an operand *)
tagSetOpen[lexed_List, stmt_Integer, last_Integer] := Block[{depth = 0, open = False, k},
    Do[
        k = lexed[[5 u - 2]];
        Which[
            MemberQ[{10, 12, 14, 16}, k], depth++,
            MemberQ[{11, 13, 15, 17}, k], depth--,
            depth === 0 && k === $tkOperator && lexed[[5 u - 1]] === $fastSlashColon, open = True,
            depth === 0 && k === $tkOperator && MemberQ[$fastAssignments, lexed[[5 u - 1]]], open = False],
        {u, stmt, last}];
    open && depth === 0 && MemberQ[{1, 2, 3, 4, 5, 6, 7, 11, 13, 15, 17, 19}, lexed[[5 last - 2]]]]

$fastSlashColon := $fastSlashColon = fastOp["/:"]
$fastAssignments := $fastAssignments = fastOp /@ {"=", ":=", "=."}

(* a statement only the grammar reads: before the token WolframLanguageHeld's failure is just past *)
grammarStop[s_String] := With[{r = WolframLanguageHeld[s]}, If[FailureQ[r], If[TrueQ[r["Incomplete"]], StringLength[s] + 2, Max[r["Position"] - 2, 0]], None]]

WolframLanguageSyntaxQ[s_String] := s =!= "" && syntaxStop[s] === None

WolframLanguageSyntaxLength[s_String] := Replace[syntaxStop[s], None -> StringLength[s]]

End[]

EndPackage[]

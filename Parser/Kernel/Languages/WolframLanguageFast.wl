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
   2 a digit, 3 a space, tab, return or form feed, or the character of a
   long name that is whitespace, 4 a newline, 5 a character past ASCII
   that a name holds, 0 any other *)
$fastClasses := $fastClasses = Module[{t = ConstantArray[0, 65536], high = Range[128, 65535]},
    t[[ToCharacterCode["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$`"] + 1]] = 1;
    t[[Range[48, 57] + 1]] = 2;
    t[[{32, 9, 13, 12} + 1]] = 3;
    t[[11]] = 4;
    t[[high + 1]] = 5;
    t[[ToCharacterCode[StringJoin[Keys[$nonLetterCharacters]]] + 1]] = 0;
    t[[Pick[high, StringMatchQ[Characters[FromCharacterCode[high]], WhitespaceCharacter]] + 1]] = 0;
    t[[ToCharacterCode[StringJoin[Lookup[$longNameTable["Characters"], $longNameTable["Whitespace"], Nothing]]] + 1]] = 3;
    t]

(* --- operators --- *)

(* every operator by its name in the grammar: its ASCII spelling, or the
   long name of one with none *)
$fastOperators = Join[$operatorSpellings, {"DirectedEdge", "UndirectedEdge", "Element"}]
$fastOperatorIds = AssociationThread[$fastOperators -> Range[Length[$fastOperators]]]
fastOp[name_String] := $fastOperatorIds[name]

(* the long names the held grammar reads that are no ASCII operator's, each
   an operator after those, read at their first use; the whitespace ones
   one more, and the invisible comma, a comma, one after it *)
$fastLongNames := $fastLongNames = Complement[Keys[$nonLetterNames], Keys[$asciiLongNames], $longNameTable["Whitespace"], {"InvisibleComma"}]
$fastLongIds := $fastLongIds = AssociationThread[$fastLongNames -> Length[$fastOperators] + Range[Length[$fastLongNames]]]
$fastSpaceId := $fastSpaceId = Length[$fastOperators] + Length[$fastLongNames] + 1
$fastInvisibleCommaId := $fastInvisibleCommaId = $fastSpaceId + 1
(* \[Not] and its character, which ! is not after an operand *)
$fastNotId := $fastNotId = $fastSpaceId + 2
fastLongOp[name_String] := Which[
    KeyExistsQ[$fastLongIds, name], $fastLongIds[name],
    MemberQ[$longNameTable["Whitespace"], name], $fastSpaceId,
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
$fastOp2Flat := $fastOp2Flat = Flatten[$fastOp2]
$fastOp3Table = Flatten[KeyValueMap[Append[#1, #2] &, $fastOp3]]
$fastLongOpTable := $fastLongOpTable = Flatten[KeyValueMap[Join[{StringLength[#1]}, ToCharacterCode[#1], {#2}] &, $fastLongNameOps]]
$fastOpenAssociation = fastOp["<|"]; $fastCloseAssociation = fastOp["|>"]
$fastGet = fastOp["<<"]; $fastPut = fastOp[">>"]; $fastPutAppend = fastOp[">>>"]
$fastSpecial := $fastSpecial = {$fastOpenAssociation, $fastCloseAssociation, $fastGet, $fastPut, $fastPutAppend, fastOp["=."], fastOp["="],
    $fastSpaceId, $fastInvisibleCommaId}

(* --- tokens --- *)

(* token kinds *)
$tkEnd = 0; $tkName = 1; $tkBlank = 2; $tkInteger = 3; $tkReal = 4; $tkString = 5; $tkSlot = 6; $tkOut = 7; $tkFile = 8;
$tkOperator = 9; $tkOpenParen = 10; $tkCloseParen = 11; $tkOpenSquare = 12; $tkCloseSquare = 13; $tkOpenCurly = 14;
$tkCloseCurly = 15; $tkOpenAssociation = 16; $tkCloseAssociation = 17; $tkComma = 18; $tkPrimes = 19

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
   =., =, whitespace, the invisible comma} -> {status, k, then for each of the
   k tokens its kind, operator, start, end (just past it) and newline mark
   (1 where a newline outside a comment comes before it)}, the last token
   the end. Status 1: the source holds a character no token has, where the
   last token, the one that stops there, ends; 3: the source ends in a
   string or a comment not closed. Whitespace and comments are in no
   token; after << and >> the file is one token. *)
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
                        c == 35,
                            If[j <= n && lexCodes[[j]] == 35, j++];
                            Which[
                                j <= n && 48 <= lexCodes[[j]] <= 57, While[j <= n && 48 <= lexCodes[[j]] <= 57, j++],
                                j <= n && ((65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)),
                                    j++; While[j <= n && ((48 <= lexCodes[[j]] <= 57) || (65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)), j++],
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
    {":", 38, "InfixL", "Optional"},
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
$fastPrefixOnly := $fastPrefixOnly = AssociationThread[Append[DeleteCases[fastLongOp /@ $prefixOnlyNames, 0], $fastNotId] -> True]
$fastLongMinus := $fastLongMinus = fastLongOp["Minus"]
$fastRightDoubleBracket := $fastRightDoubleBracket = fastLongOp["RightDoubleBracket"]

$fastPatternColon = 40; $fastSpanOperand = 80; $fastCompoundOperand = 4; $fastTagLeft = 9; $fastTagRight = 8; $fastImplicitTimes = 108
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
$fastOpSpecIndex := $fastOpSpecIndex = With[{n = $fastNotId + 1},
    Table[Which[KeyExistsQ[$fastLedTable, k], fastSpecIndex[$fastLedTable[k]],
        KeyExistsQ[$fastPrefixOnly, k], fastSpecIndex[{$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}], True, 0], {k, 0, n}]]
$fastKindSpecIndex := $fastKindSpecIndex = ReplacePart[ConstantArray[0, 20], Join[
    {($tkOpenSquare + 1) -> fastSpecIndex[{176, "Call", "Call"}], ($tkPrimes + 1) -> fastSpecIndex[{154, "Derivative", "Derivative"}]},
    Map[(# + 1) -> fastSpecIndex[{$fastImplicitTimes, "InfixN", "Times", "Times", "Implicit"}] &,
        {$tkName, $tkBlank, $tkInteger, $tkReal, $tkString, $tkSlot, $tkOut, $tkOpenParen, $tkOpenCurly, $tkOpenAssociation}]]]
fastLedIndices[kinds_List, ops_List] := Module[{index, unset},
    index = $fastKindSpecIndex[[kinds + 1]] + $fastOpSpecIndex[[ops + 1]] (1 - Unitize[kinds - $tkOperator]);
    unset = (1 - Unitize[ops - $fastEqual]) (1 - Unitize[RotateLeft[ops] - $fastDot]) (1 - Unitize[RotateLeft[kinds] - $tkOperator]);
    index (1 - unset) + unset fastSpecIndex[{9, "Unset", "Unset"}]]

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
   2: they hold what this parser does not take. It climbs as the grammar's table does, with no
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
   integral {integral}; 25 the end of a statement;
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
                ft = 0, cnt = 0, bt = 0, colons = 0, ok = 0, x = 0, lg = 0, e = 0, we = 0, c = 0, cl = 0, tt = 0, far = 0},
            out = Table[0, {3 (8 n + 16) + 2}];
            maxFrames = 4 n + 64;
            fr = Table[0, {8 maxFrames}];
            While[ mode != 99,
                Which[
                    (* a statement *)
                    mode == 0,
                        If[pTok[[5 t - 2]] == 0, mode = 99, pMin = 0; pRbp = 0; pPlain = 0; mode = 1],
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
                            k >= 2 && k <= 7,
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
                    (* after an operand: the operator that takes it, if one binds tightly enough *)
                    mode == 3,
                        base = 8 (sp - 1); mn = fr[[base + 2]]; rb = fr[[base + 3]]; pl = fr[[base + 4]];
                        i = pLed[[t]];
                        If[brackets == 0 && pTok[[5 t + 2]] == 1, i = 0];
                        If[ i == 0, mode = 4,
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
                                    True, mode = 5]]],
                    (* the expression at the top is read: what waited for it *)
                    mode == 4,
                        sp--;
                        If[ sp == 0,
                            on++; out[[3 on]] = 25; out[[3 on + 1]] = 0; out[[3 on + 2]] = 0; mode = 0,
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
                                ft == 11,
                                    If[ fr[[base + 2]] == 1,
                                        If[ pTok[[5 t - 2]] == 9 && pTok[[5 t - 1]] == pSpecial[[8]] && ! (brackets == 0 && pTok[[5 t + 2]] == 1),
                                            t++; fr[[base + 2]] = 2; pMin = fr[[base + 4]]; pRbp = fr[[base + 3]]; pPlain = fr[[base + 5]]; mode = 1,
                                            mode = 5],
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
            Take[out, If[status == 0, 2 + 3 on, 2]]]]]

(* the parser run here, fixed at its first use *)
fastParseFunction := fastParseFunction = typedFunction[fastParse, $fastParseDeclaration]

(* --- the typed parser's tables --- *)

(* the heads, each by the position of its name; the chain keys likewise *)
$fastHeadNames := $fastHeadNames = DeleteDuplicates[Join[{"Minus", "Unset", "Paren", "List", "Association", "NotNot"},
    $fastSpecList[[All, 3]], Values[$fastPrefixTable][[All, 2]], Values[$fastGroupTable][[All, 2]]]]
fastHeadCode[name_String] := First[FirstPosition[$fastHeadNames, name, {0}, {1}]]
$fastKeyNames := $fastKeyNames = DeleteDuplicates[Join[{"Plus", "Relation", "Divisible"},
    Map[fastChainKey, Select[$fastSpecList, #[[2]] === "InfixN" &]]]]
fastKeyCode[key_String] := First[FirstPosition[$fastKeyNames, key, {0}, {1}]]
$fastFixityCodes = <|"InfixL" -> 1, "InfixR" -> 2, "InfixN" -> 3, "Postfix" -> 4, "Call" -> 5, "Derivative" -> 6, "Ternary" -> 7,
    "MessageName" -> 8, "Span" -> 9, "Compound" -> 10, "TagSet" -> 11, "Put" -> 12, "Unset" -> 13, "LongPart" -> 14|>

(* each spec: precedence, fixity (15 the product an operand begins), head
   and chain key *)
$fastSpecTable := $fastSpecTable = Flatten[Map[{#[[1]], If[Length[#] >= 5, 15, $fastFixityCodes[#[[2]]]], fastHeadCode[#[[3]]],
    If[#[[2]] === "InfixN", fastKeyCode[fastChainKey[#]], 0]} &, $fastSpecList]]
(* by operator, from 0: the prefix ones' precedence and head, the
   brackets' closer and head, and the integral *)
$fastPrefixArray := $fastPrefixArray = Flatten[Table[
    If[KeyExistsQ[$fastPrefixTable, o], {$fastPrefixTable[o][[1]], fastHeadCode[$fastPrefixTable[o][[2]]]}, {0, 0}], {o, 0, $fastNotId}]]
$fastGroupArray := $fastGroupArray = Flatten[Table[
    If[KeyExistsQ[$fastGroupTable, o], {$fastGroupTable[o][[1]], fastHeadCode[$fastGroupTable[o][[2]]]}, {0, 0}], {o, 0, $fastNotId}]]
$fastIntegralList := $fastIntegralList = Values[$fastIntegralTable]
$fastIntegralArray := $fastIntegralArray = Table[
    If[KeyExistsQ[$fastIntegralTable, o], First[FirstPosition[Keys[$fastIntegralTable], o]], 0], {o, 0, $fastNotId}]
(* the operators and precedences the parser names, the heads it emits and
   the chain keys it tells *)
$fastSpecialArray := $fastSpecialArray = Join[
    {$fastColon, $fastSemiSemi, $fastSemi, $fastColonColon, $fastEqual, $fastEqualDot, $fastDot, $fastTilde, $fastGet, $fastColonEqual,
     $fastMinus, $fastLongMinus, $fastRightDoubleBracket, $fastQuestion},
    {$integralPrecedence, $fastPatternColon, $fastSpanOperand, $fastCompoundOperand, $fastTagLeft, $fastTagRight}]
$fastHeadCodeArray := $fastHeadCodeArray = fastHeadCode /@ {"Minus", "Unset", "Paren", "List", "Association", "NotNot"}
$fastKeyCodeArray := $fastKeyCodeArray = fastKeyCode /@ {"Plus", "Relation", "Divisible"}

(* --- the build pass --- *)

fastText[a_Integer, b_Integer] := FromCharacterCode[$fcodes[[a ;; b - 1]]]

fastLeaf[kind_String, text_String] := $falg["Leaf"][kind, text]

fastBinary[head_String, l_, r_] := Switch[ head,
    "At", atCall[$falg, l, r],
    "SlashSlash", $falg["Call"][r, {l}],
    _, $falg["Binary"][head, l, r]]

$fastLeafKinds = <|1 -> "Symbol", 2 -> "Blank", 3 -> "Integer", 4 -> "Real", 5 -> "String", 6 -> "Slot", 7 -> "Out", 8 -> "File", 100 -> "Tag"|>

(* the held values of a postfix program, by the held algebra's builders:
   the statements'. The values wait in an association by their place on
   the stack, which a write does not copy, as it does a list of them. *)
fastBuild[prog_List] := Module[{n = prog[[2]], vals = <||>, sp = 0, heads, hp = 0, statements = Internal`Bag[], code, a, b, xs, x, y, z, spec},
    heads = ConstantArray[0, n + 1];
    Do[
        code = prog[[3 j]]; a = prog[[3 j + 1]]; b = prog[[3 j + 2]];
        Switch[ code,
            1, sp++; vals[sp] = fastLeaf[$fastLeafKinds[a], fastText[$fs[[b]], $fe[[b]]]],
            8, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a; vals[sp] = $falg["Call"][vals[sp], xs],
            4, y = vals[sp]; sp--; vals[sp] = fastBinary[$fastHeadNames[[a]], vals[sp], y],
            9, xs = Lookup[vals, Range[sp - b + 1, sp]]; sp -= b - 1; vals[sp] = $falg["Group"][$fastHeadNames[[a]], xs],
            25, Internal`StuffBag[statements, vals[sp]]; sp--,
            19, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = $falg["Infix"]["CompoundExpression", xs],
            5, xs = Lookup[vals, Range[sp - b + 1, sp]]; sp -= b - 1; vals[sp] = $falg["Infix"][$fastHeadNames[[a]], xs],
            3, vals[sp] = $falg["Postfix"][vals[sp], $fastHeadNames[[a]]],
            2, vals[sp] = $falg["Prefix"][$fastHeadNames[[a]], vals[sp]],
            14, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = $falg["Infix"]["MessageName", xs],
            23, y = vals[sp]; sp--; vals[sp] = $falg["Binary"]["Pattern", vals[sp], y],
            6, hp++; heads[[hp]] = a,
            7, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1;
                vals[sp] = relationValue[$falg, xs, $fastHeadNames[[heads[[hp - a + 2 ;; hp]]]]]; hp -= a - 1,
            10, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a; vals[sp] = $falg["Infix"]["Part", Prepend[xs, vals[sp]]],
            11, sp++; vals[sp] = fastLeaf["Symbol", "Null"],
            12, sp++; vals[sp] = fastLeaf["Symbol", "All"],
            13, sp++; vals[sp] = fastLeaf["Integer", "1"],
            15, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a; vals[sp] = $falg["Call"][$falg["Call"][fastLeaf["Symbol", "TypeSpecifier"], {vals[sp]}], xs],
            16, vals[sp] = $falg["Call"][$falg["Call"][fastLeaf["Symbol", "Derivative"], {fastLeaf["Integer", ToString[a]]}], {vals[sp]}],
            17, z = vals[sp]; y = vals[sp - 1]; x = vals[sp - 2]; sp -= 2; vals[sp] = $falg["Call"][y, {x, z}],
            18, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = $falg["Infix"]["Span", xs],
            20, If[ a === 3,
                    y = vals[sp]; sp--; vals[sp] = $falg["Binary"]["TagUnset", vals[sp], y],
                    z = vals[sp]; y = vals[sp - 1]; x = vals[sp - 2]; sp -= 2;
                    vals[sp] = $falg["Ternary"][If[a === 1, "TagSetDelayed", "TagSet"], x, y, z]],
            21, y = vals[sp]; sp--; vals[sp] = $falg["Binary"][$fastHeadNames[[a]], vals[sp], y],
            22, vals[sp] = $falg["Prefix"]["Get", vals[sp]],
            24, spec = $fastIntegralList[[a]];
                vals[sp] = If[spec[[2]] === Integrate, integralOf[$falg, spec[[1]], vals[sp]], $falg["Prefix"][spec[[1]], vals[sp]]],
            26, xs = Lookup[vals, Range[sp - a + 1, sp]]; sp -= a - 1; vals[sp] = $falg["Infix"]["Divisible", Reverse[xs]],
            27, vals[sp] = $falg["Prefix"]["Not", $falg["Prefix"]["Not", vals[sp]]],
            28, sp++; vals[sp] = fastLeaf["String", "\"" <> StringReplace[fastText[a, b], "\t" -> " "] <> "\""],
            29, vals[sp] = $falg["Call"][fastLeaf["Symbol", "Information"], {vals[sp],
                $falg["Binary"]["Rule", fastLeaf["Symbol", "LongForm"], fastLeaf["Symbol", If[a === 1, "True", "False"]]]}]],
        {j, n}];
    expressions[Internal`BagPart[statements, All]]]

(* the source's top-level expressions, held, by the lexer, the parser and
   the build pass; source that is no Wolfram Language a failure where the
   kernel's reader stops, and the grammar reads what they do not take *)
fastHeld[s_String] := Catch[Module[{codes = ToCharacterCode[s], padded, lexed, kinds, ops, prog},
    padded = Join[codes, {0, 0, 0}];
    lexed = fastLexFunction[padded, $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial];
    Switch[ lexed[[1]],
        0, Null,
        3, Throw[fastFailure[Length[codes] + 1, True], $fastGiveUp],
        _, Throw[fastFailure[lexed[[2 + 5 (lexed[[2]] - 1) + 4]], False], $fastGiveUp]];
    kinds = lexed[[3 ;; ;; 5]]; ops = lexed[[4 ;; ;; 5]];
    prog = fastParseFunction[lexed, fastLedIndices[kinds, ops], $fastSpecTable, $fastPrefixArray, $fastGroupArray,
        $fastIntegralArray, $fastSpecialArray, $fastHeadCodeArray, $fastKeyCodeArray, padded, $fastClasses];
    Switch[ prog[[1]],
        0, Null,
        1, Throw[stoppedFailure[lexed, prog[[2]]], $fastGiveUp],
        _, fastGiveUp[]];
    Block[{$fcodes = codes, $fs = lexed[[5 ;; ;; 5]], $fe = lexed[[6 ;; ;; 5]], $falg = WolframLanguageSemantic},
        fastBuild[prog]]], $fastGiveUp]

End[]

EndPackage[]

(* ::Package:: *)

(* :Title: WolframLanguageLex.wl - the typed lexer of WolframLanguageFast.wl *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The lexer of the reader of WolframLanguageFast.wl, typed code over
    packed integers: $fastLexDeclaration, a small loop over the character
    codes, and $fastLexHelpers, the typed functions it calls for long
    names, comments, quoted strings, files, numbers, slots, blanks and
    linear syntax, each after those it calls. A compiler of typed code
    takes them together, a unit of their own; the tables they read are
    their arguments, made in WolframLanguageFast.wl.
*)

BeginPackage["Wolfram`Parser`Languages`WolframLanguage`", {"Wolfram`Parser`"}]

Begin["`Private`"]

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
   so is a \( to its \), the boxes of linear syntax, a \! before it too.
   Its loop is kept small, which a compiler of typed code makes fast: a
   comment, a quoted string or file, a path, a number, a slot, a blank's
   head and linear syntax are each read by a typed function of its own,
   and a long name by lexLongName where the loop meets it, the last kept. *)
$fastLexDeclaration = FunctionDeclaration[fastLex,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{lexCodes, lexClasses, lexOp1, lexOp2, lexOp3, lexLongOps, lexSpecial},
        Module[{n = Length[lexCodes] - 3, out, k = 0, i = 1, j = 0, c = 0, c2 = 0, cl = 0, nl = 0, kind = 0, op = 0, file = 0,
                status = 0, done = 0, scanning = 0, m = 0, a = 0, len = 0, base = 0, start = 0, tick = 0, r = 0, e2 = 0, lnAt = 0, lnVal = 0,
                spOpen = lexSpecial[[1]], spClose = lexSpecial[[2]], spGet = lexSpecial[[3]], spPut = lexSpecial[[4]], spPutAppend = lexSpecial[[5]],
                spUnset = lexSpecial[[6]], spSet = lexSpecial[[7]], spSpace = lexSpecial[[8]], spComma = lexSpecial[[9]], spNewline = lexSpecial[[10]]},
            out = Table[0, {5 n + 7}];
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
                    out[[base + 1]] = 0; out[[base + 4]] = i; done = 1,
                    c = lexCodes[[i]]; cl = If[c > 65535, 5, lexClasses[[c + 1]]]; op = 0; kind = 0; j = i + 1; start = i;
                    If[c == 92 && lnAt != i, lnAt = i; lnVal = lexLongName[lexCodes, lexLongOps, i, n]];
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
                            r = lexQuoted[lexCodes, If[c == 35, i + 2, i + 1], n]; j = Quotient[r, 2]; If[Mod[r, 2] == 1, status = 3];
                            kind = If[c == 35, 6, 5],
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
                            (* =. before a digit: =, then a number *)
                            If[op == spUnset && i + 2 <= n && 48 <= lexCodes[[i + 2]] <= 57, op = spSet; len = 1];
                            j = i + len;
                            Which[op == 0, status = 1; j = i, op == spOpen, kind = 16, op == spClose, kind = 17, op == spComma, kind = 18, True, kind = 9]];
                    (* a blank: _, __ or ___, then a . or a name *)
                    If[ kind == 2 && status == 0,
                        r = lexBlank[lexCodes, lexClasses, lexLongOps, i, j, n]; j = Quotient[r, 2]; status = Mod[r, 2]];
                    file = If[kind == 9 && (op == spGet || op == spPut || op == spPutAppend), 1, 0];
                    out[[base + 1]] = kind; out[[base + 2]] = If[kind == 9, op, 0]; out[[base + 4]] = j;
                    If[status != 0, done = 1];
                    i = j]];
            out[[1]] = status; out[[2]] = k;
            Take[out, 2 + 5 k]]]];

(* A long name \[Name] at at, letters and digits closed by a ]: 8192 times just past it, plus 1
   more than what the table of long names gives it, -1 a letter, an operator, or 0, as for a name
   it has not; 0 where no long name is there. *)
$lexLongNameDeclaration = FunctionDeclaration[lexLongName,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
    Function[{lnCodes, lnTable, lnAt, lnN},
        Module[{j = lnAt + 2, a = 1, op = 0, len = 0, match = 0, q = 1, result = 0},
            If[ lnAt < lnN && lnCodes[[lnAt]] == 92 && lnCodes[[lnAt + 1]] == 91,
                While[j <= lnN && ((48 <= lnCodes[[j]] <= 57) || (65 <= lnCodes[[j]] <= 90) || (97 <= lnCodes[[j]] <= 122)), j++];
                If[ j > lnAt + 2 && j <= lnN && lnCodes[[j]] == 93,
                    While[ op == 0 && a <= Length[lnTable],
                        len = lnTable[[a]];
                        If[ len == j - lnAt - 2,
                            match = 1; q = 1;
                            While[match == 1 && q <= len, If[lnTable[[a + q]] != lnCodes[[lnAt + 1 + q]], match = 0]; q++];
                            If[match == 1, op = lnTable[[a + len + 1]]]];
                        a += len + 2];
                    result = 8192 (j + 1) + op + 1]];
            result]]];

(* A comment from its opening paren and star at at, nested ones in it: twice just past its end,
   plus 1 where the source ends before it does, the place reading got to then. *)
$lexCommentDeclaration = FunctionDeclaration[lexComment,
    Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
    Function[{cmCodes, cmAt, cmN},
        Module[{depth = 1, j = cmAt + 2, unclosed = 0},
            While[ depth > 0,
                Which[
                    j + 1 > cmN, unclosed = 1; depth = 0,
                    cmCodes[[j]] == 40 && cmCodes[[j + 1]] == 42, depth++; j += 2,
                    cmCodes[[j]] == 42 && cmCodes[[j + 1]] == 41, depth--; j += 2,
                    True, j++]];
            2 j + unclosed]]];

(* The characters quoted from from, past the opening ": twice just past the closing ", plus 1
   where the source ends before it, a \ taking the character after it. *)
$lexQuotedDeclaration = FunctionDeclaration[lexQuoted,
    Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
    Function[{qtCodes, qtFrom, qtN},
        Module[{j = qtFrom, scanning = 1, unclosed = 0, c2 = 0},
            While[ scanning == 1,
                If[ j > qtN, unclosed = 1; scanning = 0,
                    c2 = qtCodes[[j]];
                    Which[c2 == 34, j++; scanning = 0, c2 == 92, j += 2, True, j++]]];
            2 j + unclosed]]];

(* The file of << or >> at at: a quoted one, or the characters of a path, its long names whole:
   4 times just past it, plus the status, 1 where reading stops at it, 3 where the source ends in
   its quotes. *)
$lexFileDeclaration = FunctionDeclaration[lexFile,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} ->
        "MachineInteger"] @
    Function[{flCodes, flClasses, flTable, flAt, flN},
        Module[{j = flAt, r = 0, status = 0, scanning = 1, c2 = 0, cl = 0, ln = 0},
            If[ flCodes[[flAt]] == 34,
                r = lexQuoted[flCodes, flAt + 1, flN]; j = Quotient[r, 2]; If[Mod[r, 2] == 1, status = 3],
                While[ scanning == 1 && j <= flN,
                    c2 = flCodes[[j]]; cl = If[c2 > 65535, 5, flClasses[[c2 + 1]]];
                    Which[
                        cl == 1 || cl == 2 || c2 == 95 || c2 == 46 || c2 == 47 || c2 == 126 || c2 == 58 || c2 == 33 || c2 == 42 || c2 == 63 || c2 == 45, j++,
                        c2 == 92 && j + 1 <= flN && flCodes[[j + 1]] == 91,
                            ln = lexLongName[flCodes, flTable, j, flN];
                            If[ln > 0, j = Quotient[ln, 8192], status = 1; scanning = 0],
                        c2 == 92, j++,
                        True, scanning = 0]];
                If[j == flAt, status = 1]];
            4 j + status]]];

(* A number at at: its digits, b^^ and the digits of base b, a precision or an accuracy, which has
   its digits, and a power of the base: 4 times just past it, plus 2 for a real, plus 1 where
   reading stops past it, at a base no number has or a digit its base has not. *)
$lexNumberDeclaration = FunctionDeclaration[lexNumber,
    Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
    Function[{nmCodes, nmAt, nmN},
        Module[{j = 0, a = 0, m = 0, c2 = 0, status = 0, accuracy = 0, real = 0},
            If[ nmCodes[[nmAt]] == 46,
                j = nmAt + 1; While[j <= nmN && 48 <= nmCodes[[j]] <= 57, j++],
                j = nmAt; While[j <= nmN && 48 <= nmCodes[[j]] <= 57, j++];
                Which[
                    j + 2 <= nmN && nmCodes[[j]] == 94 && nmCodes[[j + 1]] == 94 &&
                        ((48 <= nmCodes[[j + 2]] <= 57) || (65 <= nmCodes[[j + 2]] <= 90) || (97 <= nmCodes[[j + 2]] <= 122)),
                        a = 0; m = nmAt;
                        While[m < j, If[a <= 36, a = 10 a + nmCodes[[m]] - 48]; m++];
                        j += 2;
                        While[j <= nmN && ((48 <= nmCodes[[j]] <= 57) || (65 <= nmCodes[[j]] <= 90) || (97 <= nmCodes[[j]] <= 122)), j++];
                        If[ j <= nmN && nmCodes[[j]] == 46,
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
            4 j + 2 real + status]]];

(* A slot at at: ## and its digits, or # and its digits or a name, read as a name's token reads one:
   twice just past it, plus 1 where a malformed name makes none and reading stops at it. *)
$lexSlotDeclaration = FunctionDeclaration[lexSlot,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} ->
        "MachineInteger"] @
    Function[{slCodes, slClasses, slTable, slAt, slN},
        Module[{j = slAt + 1, m = 0, scanning = 1, c2 = 0, cl = 0, tick = 0, status = 0, ln = 0, d = 0},
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
            2 j + status]]];

(* The blank after a name or a _ at from, of the token at at: up to three _, then a . or a head,
   whose context marks are a name's: twice just past it, plus 1 where a malformed head makes no
   blank and reading stops at the token. *)
$lexBlankDeclaration = FunctionDeclaration[lexBlank,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger",
        "MachineInteger"} -> "MachineInteger"] @
    Function[{bkCodes, bkClasses, bkTable, bkAt, bkFrom, bkN},
        Module[{j = bkFrom, count = 0, start = 0, scanning = 1, c2 = 0, cl = 0, m = 0, tick = 0, status = 0, ln = 0, d = 0},
            While[j <= bkN && bkCodes[[j]] == 95 && count < 3, j++; count++];
            If[ j <= bkN && bkCodes[[j]] == 46,
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
            2 j + status]]];

(* Linear syntax at at: \( to its \), or \!\( to it, nested ones in it: twice just past its end,
   plus 1 where the source ends before it does. *)
$lexBoxesDeclaration = FunctionDeclaration[lexBoxes,
    Typed[{"PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger"} -> "MachineInteger"] @
    Function[{bxCodes, bxAt, bxN},
        Module[{j = If[bxCodes[[bxAt + 1]] == 40, bxAt + 2, bxAt + 4], depth = 1, unclosed = 0},
            While[ depth > 0,
                Which[
                    j >= bxN, unclosed = 1; depth = 0; j = bxN + 1,
                    bxCodes[[j]] == 92 && bxCodes[[j + 1]] == 40, depth++; j += 2,
                    bxCodes[[j]] == 92 && bxCodes[[j + 1]] == 41, depth--; j += 2,
                    bxCodes[[j]] == 92, j += 2,
                    True, j++]];
            2 j + unclosed]]];

(* the typed functions the lexer calls, each after those it calls *)
$fastLexHelpers := {$lexLongNameDeclaration, $lexQuotedDeclaration, $lexCommentDeclaration, $lexFileDeclaration, $lexNumberDeclaration, $lexSlotDeclaration,
    $lexBlankDeclaration, $lexBoxesDeclaration}

End[]

EndPackage[]

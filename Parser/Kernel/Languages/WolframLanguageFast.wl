(* ::Package:: *)

(* :Title: WolframLanguageFast.wl - WolframLanguageHeld in one pass over tokens *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The source WolframLanguageHeld reads, read as its grammar reads it, in
    two passes: the characters into tokens, one loop over their codes, then
    the tokens into expressions by precedence climbing over the levels of
    the grammar's operator table. Each value is built by the held algebra's
    own builders. Source this reader does not take, and source that is no
    Wolfram Language, the grammar reads instead, so what WolframLanguageHeld
    gives, failures too, is the grammar's.

    The lexer is typed code over packed integers, $fastLexDeclaration, a
    FunctionDeclaration that a compiler of typed code takes as it is;
    Wolfram 15 runs it compiled by Compile at its first use.
*)

BeginPackage["Wolfram`Parser`Languages`WolframLanguage`", {"Wolfram`Parser`"}]

Begin["`Private`"]

(* --- characters --- *)

(* the class of each character code: 1 a letter, $ or ` that begins a name,
   2 a digit, 3 a space, tab, return or form feed, 4 a newline, 5 a
   character past ASCII that a name holds, 0 any other *)
$fastClasses := $fastClasses = Module[{t = ConstantArray[0, 65536], high = Range[128, 65535]},
    t[[ToCharacterCode["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$`"] + 1]] = 1;
    t[[Range[48, 57] + 1]] = 2;
    t[[{32, 9, 13, 12} + 1]] = 3;
    t[[11]] = 4;
    t[[high + 1]] = 5;
    t[[ToCharacterCode[StringJoin[$operatorCharacters]] + 1]] = 0;
    t[[Pick[high, StringMatchQ[Characters[FromCharacterCode[high]], WhitespaceCharacter]] + 1]] = 0;
    t]

fastClass[c_Integer] := If[c > 65535, 5, $fastClasses[[c + 1]]]

(* --- operators --- *)

(* every operator by its name in the grammar: its ASCII spelling, or the
   long name of one with none *)
$fastOperators = Join[$operatorSpellings, {"DirectedEdge", "UndirectedEdge", "Element"}]
$fastOperatorIds = AssociationThread[$fastOperators -> Range[Length[$fastOperators]]]
fastOp[name_String] := $fastOperatorIds[name]

(* the operators of one, two and three ASCII characters, and of a character
   past ASCII, by their codes *)
$fastOp1 := $fastOp1 = Module[{t = ConstantArray[0, 65536]},
    Scan[(t[[First[ToCharacterCode[#]] + 1]] = fastOp[#]) &, Select[$operatorSpellings, StringLength[#] === 1 &]];
    KeyValueMap[Function[{op, spellings}, Scan[(t[[First[ToCharacterCode[#]] + 1]] = fastOp[op]) &, Select[spellings, StringLength[#] === 1 &]]],
        $longNameOperators];
    t]
$fastOp2 := $fastOp2 = Module[{t = ConstantArray[0, {128, 128}]},
    Scan[With[{c = ToCharacterCode[#]}, t[[c[[1]] + 1, c[[2]] + 1]] = fastOp[#]] &, Select[$operatorSpellings, StringLength[#] === 2 &]];
    t]
$fastOp3 = Association[Map[ToCharacterCode[#] -> fastOp[#] &, Select[$operatorSpellings, StringLength[#] === 3 &]]]
(* a long name that is an operator: its name -> the operator *)
$fastLongNameOps = Association[Catenate[KeyValueMap[Function[{op, spellings},
    Map[StringTake[#, {3, -2}] -> fastOp[op] &, Select[spellings, StringStartsQ[#, "\\["] &]]], $longNameOperators]]]

(* the tables of the lexer, packed: the 2-character operators by the codes
   of both, {c1, c2, c3, operator} for each of 3, and for each long name
   that is an operator its length, its codes and the operator *)
$fastOp2Flat := $fastOp2Flat = Flatten[$fastOp2]
$fastOp3Table = Flatten[KeyValueMap[Append[#1, #2] &, $fastOp3]]
$fastLongOpTable = Flatten[KeyValueMap[Join[{StringLength[#1]}, ToCharacterCode[#1], {#2}] &, $fastLongNameOps]]
$fastOpenAssociation = fastOp["<|"]; $fastCloseAssociation = fastOp["|>"]
$fastGet = fastOp["<<"]; $fastPut = fastOp[">>"]; $fastPutAppend = fastOp[">>>"]
$fastSpecial = {$fastOpenAssociation, $fastCloseAssociation, $fastGet, $fastPut, $fastPutAppend, fastOp["=."], fastOp["="]}

(* --- tokens --- *)

(* token kinds *)
$tkEnd = 0; $tkName = 1; $tkBlank = 2; $tkInteger = 3; $tkReal = 4; $tkString = 5; $tkSlot = 6; $tkOut = 7; $tkFile = 8;
$tkOperator = 9; $tkOpenParen = 10; $tkCloseParen = 11; $tkOpenSquare = 12; $tkCloseSquare = 13; $tkOpenCurly = 14;
$tkCloseCurly = 15; $tkOpenAssociation = 16; $tkCloseAssociation = 17; $tkComma = 18; $tkPrimes = 19

(* the source is not one this reader takes: the grammar reads it *)
fastGiveUp[] := Throw[$fastGiveUp, $fastGiveUp]
(* what is read here is no Wolfram Language: where the grammar reads a part
   that may be left out, it is left out, and elsewhere the grammar reads the
   source, to its failure *)
fastFail[] := Throw[$fastFail, $fastFail]

(* past [0-9a-zA-Z] from j *)
fastBaseDigitsEnd[codes_List, j0_Integer, n_Integer] := Module[{j = j0, c},
    While[j <= n && ((48 <= (c = codes[[j]]) <= 57) || (65 <= c <= 90) || (97 <= c <= 122)), j++];
    j]

(* past a \[Name] at j that is a letter, a long name no operator's; j if
   there is none *)
fastLetterNameEnd[codes_List, j_Integer, n_Integer] := Module[{k},
    If[ j + 3 <= n && codes[[j]] === 92 && codes[[j + 1]] === 91,
        k = fastBaseDigitsEnd[codes, j + 2, n];
        If[ k > j + 2 && k <= n && codes[[k]] === 93 && ! KeyExistsQ[$fastLongNameOps, FromCharacterCode[codes[[j + 2 ;; k - 1]]]],
            k + 1, j],
        j]]

(* The lexer, typed code over packed integers: the codes of a source and
   three zeros after them, so that no look ahead reads past them, the
   class of each code, the operators of 1, 2 and 3 characters, the long-name
   operators and {<|, |>, <<, >>, >>>, =., =} -> {status, k, then for each of the
   k tokens its kind, operator, start, end (just past it) and newline mark
   (1 where a newline outside a comment comes before it)}, the last token
   the end. Status 1: the source holds what the lexer does not take, a
   string or a comment not closed, a character no token has. Whitespace and
   comments are in no token; after << and >> the file is one token. *)
$fastLexDeclaration = FunctionDeclaration[fastLex,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1]} -> "PackedArray"::["MachineInteger", 1]] @
    Function[{lexCodes, lexClasses, lexOp1, lexOp2, lexOp3, lexLongOps, lexSpecial},
        Module[{n = Length[lexCodes] - 3, out, lnEnd, lnOp, k = 0, i = 1, j = 0, c = 0, c2 = 0, cl = 0, nl = 0, kind = 0, op = 0, file = 0,
                status = 0, done = 0, scanning = 0, depth = 0, m = 0, count = 0, a = 0, len = 0, match = 0, q = 0, base = 0, real = 0, start = 0},
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
                        c == 40 && i < n && lexCodes[[i + 1]] == 42,
                            depth = 1; j = i + 2;
                            While[ depth > 0,
                                Which[
                                    j + 1 > n, status = 1; depth = 0,
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
                                If[ j > n, status = 1; scanning = 0,
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
                        cl == 1 || cl == 5 || (c == 92 && lnEnd[[i]] > 0 && lnOp[[i]] == 0),
                            j = i; scanning = 1;
                            While[ scanning == 1 && j <= n,
                                c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
                                Which[
                                    cl == 1 || cl == 5 || (cl == 2 && j > start), j++,
                                    c2 == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == 0, j = lnEnd[[j]],
                                    True, scanning = 0]];
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
                                        j += 2;
                                        While[j <= n && ((48 <= lexCodes[[j]] <= 57) || (65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)), j++];
                                        If[ j <= n && lexCodes[[j]] == 46,
                                            j++; While[j <= n && ((48 <= lexCodes[[j]] <= 57) || (65 <= lexCodes[[j]] <= 90) || (97 <= lexCodes[[j]] <= 122)), j++]],
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
                                If[ j > n, status = 1; scanning = 0,
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
                        c == 92, If[lnEnd[[i]] > 0 && lnOp[[i]] > 0, op = lnOp[[i]]; j = lnEnd[[i]]; kind = 9, status = 1],
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
                            Which[op == 0, status = 1, op == lexSpecial[[1]], kind = 16, op == lexSpecial[[2]], kind = 17, True, kind = 9]];
                    (* a blank: _, __ or ___, then a . or a name *)
                    If[ kind == 2 && status == 0,
                        count = 0;
                        While[j <= n && lexCodes[[j]] == 95 && count < 3, j++; count++];
                        If[ j <= n && lexCodes[[j]] == 46,
                            j++,
                            If[ j <= n && (If[lexCodes[[j]] > 65535, 5, lexClasses[[lexCodes[[j]] + 1]]] == 1 ||
                                    If[lexCodes[[j]] > 65535, 5, lexClasses[[lexCodes[[j]] + 1]]] == 5 || (lexCodes[[j]] == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == 0)),
                                start = j; scanning = 1;
                                While[ scanning == 1 && j <= n,
                                    c2 = lexCodes[[j]]; cl = If[c2 > 65535, 5, lexClasses[[c2 + 1]]];
                                    Which[
                                        cl == 1 || cl == 5 || (cl == 2 && j > start), j++,
                                        c2 == 92 && lnEnd[[j]] > 0 && lnOp[[j]] == 0, j = lnEnd[[j]],
                                        True, scanning = 0]]]]];
                    file = If[kind == 9 && (op == lexSpecial[[3]] || op == lexSpecial[[4]] || op == lexSpecial[[5]]), 1, 0];
                    out[[base + 1]] = kind; out[[base + 2]] = If[kind == 9, op, 0]; out[[base + 4]] = j;
                    If[status != 0, done = 1];
                    i = j]];
            out[[1]] = status; out[[2]] = k;
            Take[out, 2 + 5 k]]]]

(* The lexer run here: compiled once, at its first use, where Compile is,
   else evaluated. *)
fastLexFunction := fastLexFunction = With[{f = $fastLexDeclaration[[2, 1]]},
    Replace[Compile @@ Join[Hold[Evaluate[Map[{#, _Integer, 1} &, f[[1]]]]], Extract[f, {2}, Hold]], Except[_CompiledFunction] -> f]]

(* the tokens of the codes of a source: {kinds, operator ids, starts, ends, newline marks} *)
fastTokens[codes_List] := With[{out = fastLexFunction[Join[codes, {0, 0, 0}], $fastClasses, $fastOp1, $fastOp2Flat, $fastOp3Table, $fastLongOpTable, $fastSpecial]},
    If[out[[1]] =!= 0, fastGiveUp[], Transpose[Partition[Drop[out, 2], 5]]]]

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
    {"Element", 68, "InfixL", "Element"},
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
fastChainKey[head_String] := Lookup[$fastChainKey, head, head]

(* the prefix operators: the precedence and the head *)
$fastPrefix = Association[Map[fastOp[#[[1]]] -> Rest[#] &, {
    {"++", 172, "PreIncrement"}, {"--", 172, "PreDecrement"}, {"-", 124, "Minus"}, {"+", 124, "Plus"}, {"!", 64, "Not"}, {"!!", 64, "NotNot"}}]]

$fastPatternColon = 40; $fastSpanOperand = 80; $fastCompoundOperand = 4; $fastTagLeft = 9; $fastTagRight = 8; $fastImplicitTimes = 108
$fastColon = fastOp[":"]; $fastSemiSemi = fastOp[";;"]; $fastSemi = fastOp[";"]; $fastQuestion = fastOp["?"]; $fastColonColon = fastOp["::"]
$fastColonEqual = fastOp[":="]; $fastEqual = fastOp["="]; $fastEqualDot = fastOp["=."]; $fastTilde = fastOp["~"]; $fastDot = fastOp["."]

(* --- reading the tokens --- *)

(* The reader's state, Block's: the token arrays, the token at hand, the
   brackets around it and how deep the reading has gone. *)
$fastDepthLimit = 400

fastText[a_Integer, b_Integer] := FromCharacterCode[$fcodes[[a ;; b - 1]]]
fastTokenText[] := fastText[$fs[[$ft]], $fe[[$ft]]]
fastKind[] := $fk[[$ft]]
fastOpId[] := $fo[[$ft]]
fastNext[] := $ft++

(* a newline ends the expression here: outside brackets, before the token at hand *)
fastLineEndQ[] := $fbrackets === 0 && $fn[[$ft]] === 1

(* the token at hand an operand begins with, so a product goes on *)
fastOperandStartQ[] := MemberQ[{$tkName, $tkBlank, $tkInteger, $tkReal, $tkString, $tkSlot, $tkOut, $tkOpenParen, $tkOpenCurly, $tkOpenAssociation}, $fk[[$ft]]]

(* the source's top-level expressions, held *)
fastHeld[s_String] := Replace[Catch[Catch[Module[{codes = ToCharacterCode[s], tokens, out = Internal`Bag[]},
    tokens = fastTokens[codes];
    Block[{$fcodes = codes, $fk = tokens[[1]], $fo = tokens[[2]], $fs = tokens[[3]], $fe = tokens[[4]], $fn = tokens[[5]],
           $ft = 1, $fbrackets = 0, $fdepth = 0, $falg = WolframLanguageSemantic},
        While[$fk[[$ft]] =!= $tkEnd, Internal`StuffBag[out, fastExpression[0, 0, False]]];
        expressions[Internal`BagPart[out, All]]]], $fastFail], $fastGiveUp], $fastFail -> $fastGiveUp]

(* An expression of the table of the levels above min, of its operators
   those binding more tightly than rbp; plain, its first operand is no
   name with a pattern after its :. *)
fastExpression[min_Integer, rbp_Integer, plain_] := Block[{$fdepth = $fdepth + 1},
    If[$fdepth > $fastDepthLimit, fastGiveUp[]];
    Module[{left = fastOperand[min, plain], spec, bp, more = True},
        While[ more,
            spec = fastLedSpec[];
            If[ spec === None || (bp = spec[[1]]) <= rbp || bp <= min,
                more = False,
                left = fastLed[left, spec, min, plain]]];
        left]]

(* the operator after an operand at hand: {precedence, fixity, head}, None *)
fastLedSpec[] := Which[
    fastLineEndQ[], None,
    fastSpacedUnsetQ[], {9, "Unset", "Unset"},
    $fk[[$ft]] === $tkOperator, Lookup[$fastLed, $fo[[$ft]], None],
    $fk[[$ft]] === $tkOpenSquare, {176, "Call", "Call"},
    $fk[[$ft]] === $tkPrimes, {154, "Derivative", "Derivative"},
    fastOperandStartQ[], {$fastImplicitTimes, "InfixN", "Times"},
    True, None]

fastLeaf[kind_String, text_String] := $falg["Leaf"][kind, text]

(* = then a ., trivia between them: an unset *)
fastSpacedUnsetQ[] := $fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastEqual && $ft < Length[$fk] &&
    $fk[[$ft + 1]] === $tkOperator && $fo[[$ft + 1]] === $fastDot

(* --- operands --- *)

fastOperand[min_Integer, plain_] := Module[{kind = $fk[[$ft]], spec, text, name},
    If[ kind === $tkOperator && KeyExistsQ[$fastPrefix, $fo[[$ft]]] && $fastPrefix[$fo[[$ft]]][[1]] > min,
        spec = $fastPrefix[$fo[[$ft]]]; fastNext[];
        Return[With[{x = fastExpression[min, spec[[1]], plain]},
            If[spec[[2]] === "NotNot", $falg["Prefix"]["Not", $falg["Prefix"]["Not", x]], $falg["Prefix"][spec[[2]], x]]], Module]];
    Switch[ kind,
        $tkName,
            text = fastTokenText[]; fastNext[];
            name = fastLeaf["Symbol", text];
            If[ ! plain && $fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastColon && ! fastLineEndQ[],
                fastPattern[name],
                name],
        $tkBlank, text = fastTokenText[]; fastNext[]; fastLeaf["Blank", text],
        $tkInteger, text = fastTokenText[]; fastNext[]; fastLeaf["Integer", text],
        $tkReal, text = fastTokenText[]; fastNext[]; fastLeaf["Real", text],
        $tkString, text = fastTokenText[]; fastNext[]; fastLeaf["String", text],
        $tkSlot, text = fastTokenText[]; fastNext[]; fastLeaf["Slot", text],
        $tkOut, text = fastTokenText[]; fastNext[]; fastLeaf["Out", text],
        $tkOpenParen,
            fastNext[];
            With[{e = fastBracketed[fastExpression[0, 0, False]]}, fastClose[$tkCloseParen]; $falg["Group"]["Paren", {e}]],
        $tkOpenCurly, fastNext[]; With[{xs = fastItems[$tkCloseCurly]}, fastClose[$tkCloseCurly]; $falg["Group"]["List", xs]],
        $tkOpenAssociation, fastNext[]; With[{xs = fastItems[$tkCloseAssociation]}, fastClose[$tkCloseAssociation]; $falg["Group"]["Association", xs]],
        $tkOperator,
            Which[
                $fo[[$ft]] === $fastGet, fastNext[]; $falg["Prefix"]["Get", fastFile[]],
                $fo[[$ft]] === $fastSemiSemi, fastSpan[fastLeaf["Integer", "1"], min],
                $fo[[$ft]] === $fastQuestion, fastInformation[],
                True, fastFail[]],
        _, fastFail[]]]

(* n:patt, the name binding the pattern of the levels above : after it; a
   name alone if none can be read there *)
fastPattern[name_] := Module[{at = $ft, pattern},
    fastNext[];
    pattern = Catch[fastExpression[$fastPatternColon, 0, True], $fastFail];
    If[pattern === $fastFail, $ft = at; name, $falg["Binary"]["Pattern", name, pattern]]]

(* what is read inside a bracket, where a newline is whitespace *)
SetAttributes[fastBracketed, HoldFirst]
fastBracketed[e_] := Block[{$fbrackets = $fbrackets + 1}, e]

(* the closer of the bracket *)
fastClose[kind_Integer] := If[$fk[[$ft]] === kind, fastNext[], fastFail[]]

(* expressions between commas up to the closer, an empty one Null *)
fastItems[close_Integer] := fastBracketed[Module[{items = Internal`Bag[], more = True},
    If[ $fk[[$ft]] === close,
        {},
        While[ more,
            Internal`StuffBag[items, If[MemberQ[{$tkComma, close}, $fk[[$ft]]], fastLeaf["Symbol", "Null"], fastExpression[0, 0, False]]];
            If[$fk[[$ft]] === $tkComma, fastNext[], more = False]];
        Internal`BagPart[items, All]]]]

(* the file of << and >>, a string or the characters of a path *)
fastFile[] := If[$fk[[$ft]] === $tkFile, With[{text = fastTokenText[]}, fastNext[]; fastLeaf["File", text]], fastFail[]]

(* ?name and ??name: Information of the words after it, or of a string *)
fastInformation[] := Module[{long = False, j, n = Length[$fcodes], words, endAt},
    fastNext[];
    If[ $fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastQuestion && $fs[[$ft]] === $fe[[$ft - 1]], long = True; fastNext[]];
    j = $fe[[$ft - 1]];
    While[j <= n && ($fcodes[[j]] === 32 || $fcodes[[j]] === 9), j++];
    Which[
        j <= n && $fcodes[[j]] === 34,
            If[$fk[[$ft]] =!= $tkString || $fs[[$ft]] =!= j, fastGiveUp[]];
            words = fastTokenText[]; fastNext[],
        True,
            endAt = fastInformationEnd[j];
            If[endAt === j, fastFail[]];
            words = "\"" <> StringReplace[fastText[j, endAt], "\t" -> " "] <> "\"";
            (* the tokens of the words, whose last ends where they do *)
            While[$fk[[$ft]] =!= $tkEnd && $fs[[$ft]] < endAt, fastNext[]];
            If[$fe[[$ft - 1]] =!= endAt, fastGiveUp[]]];
    $falg["Call"][fastLeaf["Symbol", "Information"], {fastLeaf["String", words],
        $falg["Binary"]["Rule", fastLeaf["Symbol", "LongForm"], fastLeaf["Symbol", If[long, "True", "False"]]]}]]

(* past the words of a query from j: letters, digits, $ ` * @, the spaces
   and tabs between them *)
fastInformationEnd[j0_Integer] := Module[{j = j0, n = Length[$fcodes], wordEnd = j0, c, cl, k},
    While[ j <= n,
        c = $fcodes[[j]]; cl = fastClass[c];
        Which[
            cl === 1 || cl === 2 || cl === 5 || c === 42 || c === 64, j++; wordEnd = j,
            c === 92 && (k = fastLetterNameEnd[$fcodes, j, n]) > j, j = k; wordEnd = j,
            c === 32 || c === 9, j++,
            True, Break[]]];
    wordEnd]

(* --- operators after an operand --- *)

fastLed[left_, {bp_Integer, fixity_String, head_String}, min_Integer, plain_] := Switch[ fixity,
    "InfixL", fastNext[]; fastBinary[head, left, fastExpression[min, bp, plain]],
    "InfixR", fastNext[]; fastBinary[head, left, fastExpression[min, bp - 1, plain]],
    "InfixN", fastChain[left, bp, head, min, plain],
    "Postfix", fastNext[]; $falg["Postfix"][left, head],
    "Unset", $ft += 2; $falg["Postfix"][left, "Unset"],
    "Call", fastCall[left],
    "Derivative",
        With[{primes = $fe[[$ft]] - $fs[[$ft]]}, fastNext[];
            $falg["Call"][$falg["Call"][fastLeaf["Symbol", "Derivative"], {fastLeaf["Integer", ToString[primes]]}], {left}]],
    "Ternary", fastNext[];
        With[{middle = fastExpression[min, bp, plain]},
            If[! ($fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastTilde) || fastLineEndQ[], fastFail[]];
            fastNext[];
            $falg["Call"][middle, {left, fastExpression[min, bp, plain]}]],
    "MessageName", fastMessageName[left],
    "Span", fastSpan[left, min],
    "Compound", fastCompound[left, min],
    "TagSet", fastTagSet[left, min],
    "Put", fastNext[]; $falg["Binary"][head, left, fastFile[]]]

fastBinary[head_String, l_, r_] := Switch[ head,
    "At", atCall[$falg, l, r],
    "SlashSlash", $falg["Call"][r, {l}],
    _, $falg["Binary"][head, l, r]]

(* a chain of the operators of one key at one level, one node *)
fastChain[left_, bp_Integer, head_String, min_Integer, plain_] := Module[{key = fastChainKey[head], operands = {left}, heads = {}, more = True, spec},
    While[ more,
        spec = fastLedSpec[];
        If[ spec =!= None && spec[[1]] === bp && spec[[2]] === "InfixN" && fastChainKey[spec[[3]]] === key,
            heads = Append[heads, If[spec[[3]] === "Plus", If[$fk[[$ft]] === $tkOperator && $fo[[$ft]] === fastOp["-"], "-", "+"], spec[[3]]]];
            If[$fk[[$ft]] === $tkOperator, fastNext[]];
            operands = Append[operands, fastExpression[min, bp, plain]],
            more = False]];
    Switch[ key,
        "Plus", $falg["Infix"]["Plus", Prepend[MapThread[If[#2 === "-", $falg["Prefix"]["Minus", #1], #1] &, {Rest[operands], heads}], First[operands]]],
        "Relation", If[Length[Union[heads]] === 1,
            $falg["Infix"][First[heads], operands],
            $falg["Infix"]["Inequality", Riffle[operands, fastLeaf["Symbol", #] & /@ heads]]],
        _, $falg["Infix"][head, operands]]]

(* f[args] and e[[indices]] *)
fastCall[left_] := Module[{part = $ft + 1 <= Length[$fk] && $fk[[$ft + 1]] === $tkOpenSquare, xs},
    If[ part,
        $ft += 2;
        xs = fastItems[$tkCloseSquare];
        If[! ($fk[[$ft]] === $tkCloseSquare && $fk[[$ft + 1]] === $tkCloseSquare), fastFail[]];
        $ft += 2;
        $falg["Infix"]["Part", Prepend[xs, left]],
        fastNext[];
        xs = fastItems[$tkCloseSquare];
        fastClose[$tkCloseSquare];
        $falg["Call"][left, xs]]]

(* s::tag, s::tag::tag, t::[a, ...] *)
fastMessageName[left_] := Module[{colons = $fe[[$ft]], first, second = Missing[]},
    fastNext[];
    If[ $fk[[$ft]] === $tkOpenSquare && $fs[[$ft]] === colons,
        fastNext[];
        Return[With[{xs = fastItems[$tkCloseSquare]}, fastClose[$tkCloseSquare];
            $falg["Call"][$falg["Call"][fastLeaf["Symbol", "TypeSpecifier"], {left}], xs]], Module]];
    first = fastTag[colons];
    If[ $fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastColonColon && ! fastLineEndQ[],
        With[{at = $fe[[$ft]]}, fastNext[]; second = fastTag[at]]];
    $falg["Infix"]["MessageName", Join[{left, first}, If[MissingQ[second], {}, {second}]]]]

(* the tag right after ::, a name or a string *)
fastTag[at_Integer] := If[ $fs[[$ft]] =!= at, fastFail[],
    Switch[ $fk[[$ft]],
        $tkName, With[{text = fastTokenText[]}, fastNext[]; fastLeaf["Tag", text]],
        $tkString, With[{text = fastTokenText[]}, fastNext[]; fastLeaf["String", text]],
        (* the grammar's tag is the name the blank begins with *)
        $tkBlank, fastGiveUp[],
        _, fastFail[]]]

(* an operand that may be left out: the expression of the levels above
   bound, if one can be read here, else Missing[] *)
fastOptional[bound_Integer] := With[{at = $ft},
    If[ fastLineEndQ[] || $fk[[$ft]] === $tkEnd,
        Missing[],
        Replace[Catch[fastExpression[bound, 0, False], $fastFail], $fastFail :> ($ft = at; Missing[]), {0}]]]

(* a ;; b ;; c, an operand left out All *)
fastSpan[left_, min_Integer] := Module[{all = fastLeaf["Symbol", "All"], b, c = None},
    fastNext[];
    b = fastSpanOperand[];
    If[ $fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastSemiSemi && ! fastLineEndQ[],
        fastNext[]; c = fastSpanOperand[]];
    $falg["Infix"]["Span", Join[{left, If[MissingQ[b], all, b]}, If[c === None, {}, {If[MissingQ[c], all, c]}]]]]

fastSpanOperand[] := If[$fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastSemiSemi, Missing[], fastOptional[$fastSpanOperand]]

(* a; b; ..., an operand left out Null *)
fastCompound[left_, min_Integer] := Module[{parts = Internal`Bag[]},
    While[ $fk[[$ft]] === $tkOperator && $fo[[$ft]] === $fastSemi && ! fastLineEndQ[],
        fastNext[];
        Internal`StuffBag[parts, Replace[fastOptional[$fastCompoundOperand], _Missing :> fastLeaf["Symbol", "Null"]]]];
    $falg["Infix"]["CompoundExpression", Prepend[Internal`BagPart[parts, All], left]]]

(* t /: lhs = rhs, t /: lhs := rhs, t /: lhs =. *)
fastTagSet[t_, min_Integer] := Module[{lhs},
    fastNext[];
    lhs = fastExpression[$fastTagLeft, 0, False];
    Which[
        fastLineEndQ[] || $fk[[$ft]] =!= $tkOperator, fastFail[],
        fastSpacedUnsetQ[], $ft += 2; $falg["Binary"]["TagUnset", t, lhs],
        $fo[[$ft]] === $fastColonEqual, fastNext[]; $falg["Ternary"]["TagSetDelayed", t, lhs, fastExpression[$fastTagRight, 0, False]],
        $fo[[$ft]] === $fastEqual, fastNext[]; $falg["Ternary"]["TagSet", t, lhs, fastExpression[$fastTagRight, 0, False]],
        $fo[[$ft]] === $fastEqualDot, fastNext[]; $falg["Binary"]["TagUnset", t, lhs],
        True, fastFail[]]]

End[]

EndPackage[]

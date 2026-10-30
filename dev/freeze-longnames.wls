#!/usr/bin/env wolframscript
(* Records how Wolfram 15's CodeParser reads each long name that is not a
   letter into Parser/Kernel/Languages/LongNameOperators.wl: the operators,
   infix, binary, prefix and postfix, each with the tag of its node and its
   precedence; the brackets; the integrals; the whitespace and newlines; and
   the tokens CodeParser does not read. Run it with Wolfram 15:
       wl -f dev/freeze-longnames.wls
   A precedence CodeParser lists for the operator itself is taken from its
   Precedence.wl; one of a class, the arrows say, is found by reading the
   operator beside operators whose precedence is known. *)

$ProgressReporting = False;
Needs["CodeParser`"];

root = ParentDirectory[DirectoryName[$InputFileName]];
outFile = FileNameJoin[{root, "Parser", "Kernel", "Languages", "LongNameOperators.wl"}];
generated = FileNameJoin[{$InstallationDirectory, "SystemFiles", "Components", "CodeParser", "Resources", "Generated"}];
names = DeleteCases[Get[FileNameJoin[{generated, "LongNames.wl"}]], Nothing];
precedenceText = ByteArrayToString[ReadByteArray[FileNameJoin[{generated, "Precedence.wl"}]], "UTF-8"];
precedence = Association[StringCases[precedenceText,
    "Precedence`" ~~ n : Shortest[__] ~~ " -> " ~~ v : DigitCharacter .. ~~ ",(* prec: " ~~ DigitCharacter .. ~~ ", assoc: Associativity`" ~~ a : WordCharacter .. :>
        (n -> {FromDigits[v], a})]];

strip[t_] := t /. a_Association :> KeyDrop[a, Source];
top[s_] := strip[CodeConcreteParse[s]][[2]];
token[n_] := CodeParser`LeafNode[Symbol["Token`LongName`" <> n], _, _];
escape[n_] := "\\[" <> n <> "]";
(* the head and tag of the one root of s, the token of n among its children *)
form[n_, s_] := With[{t = top[s]}, If[Length[t] === 1 && MatchQ[t[[1]], _[_, _List, _]] && MemberQ[t[[1, 2]], token[n]], {Head[t[[1]]], t[[1, 1]]}, None]];

alone = AssociationMap[top[escape[#]] &, names];
whitespace = Select[names, MatchQ[alone[#], {CodeParser`LeafNode[Whitespace, _, _]}] &];
newlines = Select[names, MatchQ[alone[#], {CodeParser`LeafNode[Token`Newline, _, _]}] &];
unsupported = Select[names, MatchQ[alone[#], {CodeParser`ErrorNode[Token`Error`UnsupportedToken, _, _]}] &];

infixForms = AssociationMap[form[#, "a " <> escape[#] <> " b"] &, names];
prefixForms = AssociationMap[form[#, escape[#] <> " a"] &, names];
postfixForms = AssociationMap[form[#, "a " <> escape[#]] &, names];

(* the brackets: an opener whose group a closer of its name ends *)
closerOf[n_] := StringReplace[n, {StartOfString ~~ "Left" -> "Right", StartOfString ~~ "Open" -> "Close"}];
groups = Cases[names, n_ /; MatchQ[prefixForms[n], {CodeParser`GroupMissingCloserNode, _}] :>
    With[{t = top[escape[n] <> "a" <> escape[closerOf[n]]]}, {n, closerOf[n], t[[1, 1]]}]];
calls = Cases[groups, {o_, c_, tag_} /; MatchQ[top["f" <> escape[o] <> "a" <> escape[c]], {CodeParser`CallNode[__]}] :> {o, c, tag}];

(* the integrals: a prefix operator, and with a \[DifferentialD] after its operand a PrefixBinaryNode *)
integrals = Cases[names, n_ /; MatchQ[top[escape[n] <> " f \\[DifferentialD] x"], {CodeParser`PrefixBinaryNode[__]}] :>
    {n, prefixForms[n][[2]], top[escape[n] <> " f \\[DifferentialD] x"][[1, 1]]}];

(* precedence: the operator's own, or that of a class, found by comparison *)
ownOrMissing[n_, kind_] := With[{v = Lookup[precedence, kind <> "`LongName`" <> n, Lookup[precedence, "LongName`" <> n, Missing[]]]}, v];
(* ASCII infix operators of known precedence, the level the syntax, WolframLanguage.ebnf, gives each *)
syntax = Get[FileNameJoin[{root, "Parser", "Kernel", "Languages", "WolframLanguageSyntax.wl"}]];
infixLevel[s_String] := Association[Apply[Rule, syntax["level"], {1}]][First[Cases[syntax["operator"], {s, level_, "InfixL" | "InfixR" | "InfixN", ___} :> level]]];
asciiRefs = Map[{#, infixLevel[#]} &, {"=", "//", "/.", "->", "/;", "~~", "|", "||", "&&", "===", "==", "+", "*", "/", ".", "**", "^", "<>", "@@", "@", "/*", "@*"}];
infixNames = Select[names, infixForms[#] =!= None &];
refs = Join[
    Map[{#[[1]], #[[2]], top["a " <> #[[1]] <> " b"][[1, 1]]} &, asciiRefs],
    Cases[infixNames, n_ /; ! MissingQ[ownOrMissing[n, "Infix"]] :> {escape[n], ownOrMissing[n, "Infix"][[1]], infixForms[n][[2]]}]];
relation[x_, tx_, r_, tr_] := Module[{t1 = top["a " <> x <> " b " <> r <> " c"][[1]], t2 = top["a " <> r <> " b " <> x <> " c"][[1]]},
    Switch[{t1[[1]] === tr && MatchQ[t1[[2, 1]], _[tx, ___]], t2[[1]] === tx && MatchQ[t2[[2, 1]], _[tr, ___]]},
        {True, False}, ">", {False, True}, "<", {True, True}, "=", {False, False}, "="]];
classValues = Union[Cases[Normal[precedence], (k_String /; StringStartsQ[k, "Class`"] -> {v_, _}) :> v]];
classOf[v_] := First[Cases[Normal[precedence], (c_String /; StringStartsQ[c, "Class`"] -> {v, a_}) :> {c, a}]];
infixPrecedence[n_] := Module[{x = escape[n], tx = infixForms[n][[2]], rels, lo, hi, eq, candidates},
    If[ ! MissingQ[ownOrMissing[n, "Infix"]], Return[ownOrMissing[n, "Infix"], Module]];
    rels = Map[{#[[2]], relation[x, tx, #[[1]], #[[3]]]} &, Select[refs, #[[1]] =!= x && #[[3]] =!= tx &]];
    eq = Union[Cases[rels, {p_, "="} :> p]];
    lo = Max[Cases[rels, {p_, ">"} :> p], -1];
    hi = Min[Cases[rels, {p_, "<"} :> p], 1000];
    candidates = If[eq =!= {}, eq, Select[classValues, lo < # < hi &]];
    If[ Length[candidates] === 1, Prepend[Rest[classOf[First[candidates]]], First[candidates]], {candidates, "?"}]];
infixPrecedences = AssociationMap[infixPrecedence, infixNames];
(* the union and the intersection operators, two classes no reference
   between them tells apart: a union operator binds looser than
   \[Intersection], an intersection one as tightly *)
Scan[Function[n, If[ First[infixPrecedences[n]] === {82, 84},
    infixPrecedences[n] = With[{v = If[n === "Intersection" || relation[escape[n], infixForms[n][[2]], "\\[Intersection]", Intersection] =!= "<", 84, 82]},
        Prepend[Rest[classOf[v]], v]]]], infixNames];
Scan[Function[n, If[ ! IntegerQ[First[infixPrecedences[n]]], Print["unresolved precedence: ", n, " ", infixPrecedences[n]]; Exit[1]]], infixNames];

record[n_, f_, p_] := {n, SymbolName[f[[1]]], f[[2]], p[[1]], p[[2]]};
operators = <|
    "Infix" -> Map[record[#, infixForms[#], infixPrecedences[#]] &, infixNames],
    "Prefix" -> Cases[names, n_ /; MatchQ[prefixForms[n], {CodeParser`PrefixNode, _}] :> record[n, prefixForms[n],
        Replace[ownOrMissing[n, "Prefix"], _Missing :> If[MemberQ[integrals[[All, 1]], n], Prepend[Rest[classOf[92]], 92], (Print["no precedence: ", n]; Exit[1])]]]],
    "Postfix" -> Cases[names, n_ /; MatchQ[postfixForms[n], {CodeParser`PostfixNode, _}] :> record[n, postfixForms[n],
        Replace[ownOrMissing[n, "Postfix"], _Missing :> (Print["no precedence: ", n]; Exit[1])]]],
    "Groups" -> groups,
    "Calls" -> calls,
    "Integrals" -> integrals,
    "Whitespace" -> whitespace,
    "Newlines" -> newlines,
    "Unsupported" -> unsupported|>;
(* the character each long name stands for, its escape in a string as
   CodeParser reads the string, kept when CodeParser reads the character
   as it reads the long name; CodeParser's own COMPATIBILITY names are
   none of the kernel's *)
characters = Association[Cases[Map[# -> CodeParser`FromNode[CodeParser`CodeParse["\"" <> escape[#] <> "\""][[2, 1]]] &,
        Select[names, ! StringStartsQ[#, "COMPATIBILITY"] &]],
    (k_ -> c_String) /; StringLength[c] === 1 && First[ToCharacterCode[c]] > 127 && (top[c] /. c -> escape[k]) === alone[k]]];
(* every symbol with its context, so that one CodeParser makes in System` is read into System` *)
shown[e_] := Block[{$ContextPath = {}, $Context = "Shown`"}, ToString[e, InputForm, CharacterEncoding -> "ASCII"]];
(* one entry a line *)
entriesText[l_List] := "{\n" <> StringRiffle[Map["        " <> shown[#] &, l], ",\n"] <> "\n    }";
entriesText[a_Association] := "<|\n" <> StringRiffle[KeyValueMap["        " <> shown[#1] <> " -> " <> shownValue[#2] &, a], ",\n"] <> "\n    |>";
(* the character the front end reads for each long name, recorded by
   dev/freeze-longname-characters.wls *)
frontEndCodes = Get[FileNameJoin[{root, "Parser", "Kernel", "Languages", "LongNameCharacters.wl"}]];
(* a character as its long name, as the kernel writes it, but where the front
   end reads that long name as another character, by its code, which every
   reader reads alike *)
shownValue[c_String] /; StringLength[c] === 1 := With[{text = shown[c], code = First[ToCharacterCode[c]]},
    If[StringMatchQ[text, "\"\\[" ~~ WordCharacter .. ~~ "]\""] && Lookup[frontEndCodes, StringTake[text, {4, -3}], None] =!= code,
        "\"" <> If[code > 65535, "\\|" <> IntegerString[code, 16, 6], "\\:" <> IntegerString[code, 16, 4]] <> "\"",
        text]];
shownValue[e_] := shown[e];
table = Append[operators, "Characters" -> KeyTake[characters, Union[Flatten[{Values[operators[[{"Infix", "Prefix", "Postfix"}]]][[All, All, 1]],
    operators["Groups"][[All, {1, 2}]], operators["Whitespace"], operators["Newlines"], operators["Unsupported"]}]]]];
text = StringJoin[
    "(* How Wolfram 15's CodeParser reads each long name of the Wolfram Language that is not a letter,\n",
    "   recorded by dev/freeze-longnames.wls. \"Infix\", \"Prefix\", \"Postfix\": {name, the node, its tag,\n",
    "   the precedence, its associativity}; \"Groups\", \"Calls\": {opener, closer, tag}; \"Integrals\":\n",
    "   {name, the prefix tag, the tag with a \\[DifferentialD]}; \"Characters\": the character of each name. *)\n\n",
    "<|\n", StringRiffle[KeyValueMap["    " <> shown[#1] <> " -> " <> entriesText[#2] &, table], ",\n"], "\n|>\n"];
With[{stream = OpenWrite[outFile, CharacterEncoding -> "UTF-8"]}, WriteString[stream, text]; Close[stream]];
Print[Length[operators["Infix"]], " infix, ", Length[operators["Prefix"]], " prefix, ", Length[operators["Postfix"]], " postfix, ",
    Length[groups], " groups, ", Length[calls], " calls, ", Length[integrals], " integrals, ", Length[whitespace], " whitespace, ",
    Length[newlines], " newlines, ", Length[unsupported], " unsupported, into ", outFile];

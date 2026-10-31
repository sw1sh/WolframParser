#!/usr/bin/env wolframscript
(* Writes the Wolfram Language's syntax, Parser/Kernel/Languages/WolframLanguage.ebnf, into
   Parser/Kernel/Languages/WolframLanguageSyntax.wl, which the reader loads in place of the grammar,
   since the reader loads no grammar reader: its declarations, as EBNFDeclarations reads them, and
   its token rules, compiled to regular expressions. Run it after a change to the grammar:
       wl -f dev/freeze-syntax.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
(* the parser core and the EBNF reader alone: the languages read the file this writes *)
Block[{Wolfram`Parser`Private`$ebnfOnly = True}, Get[FileNameJoin[{root, "Parser", "Kernel", "Parser.wl"}]]];
languages = FileNameJoin[{root, "Parser", "Kernel", "Languages"}];
outFile = FileNameJoin[{languages, "WolframLanguageSyntax.wl"}];
spec = File[FileNameJoin[{languages, "WolframLanguage.ebnf"}]];
declarations = EBNFDeclarations[spec];
If[! AssociationQ[declarations], Print["the grammar does not read: ", declarations]; Exit[1]];
tokens = Wolfram`Parser`EBNFPrivate`declaredTokenTrees[spec];
If[! AssociationQ[tokens], Print["the token rules do not compile: ", tokens]; Exit[1]];
syntax = Join[declarations, tokens];
shown[e_] := ToString[e, InputForm, CharacterEncoding -> "ASCII"];
(* a declaration's rows, one to a line; a rule's tree, one to a line *)
entry[key_, rows_List] := "    " <> shown[key] <> " -> {\n" <> StringRiffle[Map["        " <> shown[#] &, rows], ",\n"] <> "\n    }";
entry[key_, trees_Association] := "    " <> shown[key] <> " -> <|\n" <> StringRiffle[KeyValueMap["        " <> shown[#1] <> " -> " <> shown[#2] &, trees], ",\n"] <> "\n    |>";
text = StringJoin[
    "(* The Wolfram Language's syntax, WolframLanguage.ebnf: its declarations as EBNFDeclarations reads\n",
    "   them, each keyword with the fields of its declarations, in order, and its token rules compiled\n",
    "   to regular expressions, tokentrees for each rule %tokens names, tokenrules for those that refer\n",
    "   to themselves. Written by dev/freeze-syntax.wls; edit the grammar, not this file. *)\n\n",
    "<|\n", StringRiffle[KeyValueMap[entry, syntax], ",\n"], "\n|>\n"];
With[{stream = OpenWrite[outFile]}, WriteString[stream, text]; Close[stream]];
If[Get[outFile] =!= syntax, Print["the file does not read back as the syntax"]; Exit[1]];
Print[StringRiffle[KeyValueMap[ToString[Length[#2]] <> " " <> #1 &, syntax], ", "], " into ", outFile];

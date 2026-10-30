#!/usr/bin/env wolframscript
(* Writes the declarations of the Wolfram Language's syntax, Parser/Kernel/Languages/WolframLanguage.ebnf,
   as EBNFDeclarations reads them, into Parser/Kernel/Languages/WolframLanguageSyntax.wl, which the
   reader loads in place of the grammar: the reader loads no grammar reader. Run it after a change
   to the grammar:
       wl -f dev/freeze-syntax.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
(* the parser core and the EBNF reader alone: the languages read the file this writes *)
Block[{Wolfram`Parser`Private`$ebnfOnly = True}, Get[FileNameJoin[{root, "Parser", "Kernel", "Parser.wl"}]]];
languages = FileNameJoin[{root, "Parser", "Kernel", "Languages"}];
outFile = FileNameJoin[{languages, "WolframLanguageSyntax.wl"}];
declarations = EBNFDeclarations[File[FileNameJoin[{languages, "WolframLanguage.ebnf"}]]];
If[! AssociationQ[declarations], Print["the grammar does not read: ", declarations]; Exit[1]];
shown[e_] := ToString[e, InputForm, CharacterEncoding -> "ASCII"];
text = StringJoin[
    "(* The declarations of the Wolfram Language's syntax, WolframLanguage.ebnf, as EBNFDeclarations\n",
    "   reads them: each keyword with the fields of its declarations, in order. Written by\n",
    "   dev/freeze-syntax.wls; edit the grammar, not this file. *)\n\n",
    "<|\n", StringRiffle[KeyValueMap["    " <> shown[#1] <> " -> {\n" <> StringRiffle[Map["        " <> shown[#] &, #2], ",\n"] <> "\n    }" &, declarations], ",\n"], "\n|>\n"];
With[{stream = OpenWrite[outFile]}, WriteString[stream, text]; Close[stream]];
If[Get[outFile] =!= declarations, Print["the file does not read back as the declarations"]; Exit[1]];
Print[StringRiffle[KeyValueMap[ToString[Length[#2]] <> " " <> #1 &, declarations], ", "], " into ", outFile];

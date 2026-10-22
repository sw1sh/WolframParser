#!/usr/bin/env wolframscript
(* Records the character Wolfram 15 reads for each long name of the
   language into Parser/Kernel/Languages/LongNameCharacters.wl, name ->
   character code: of the characters CharacterName names with a long name
   of Languages/LongNames.wl, the one the kernel reads, which where two
   share a name is the one it writes as the name. A name no character has,
   or none the kernel writes as the name, is left out, as the kernel reads
   no character for it. Run it with Wolfram 15:
       wl -f dev/freeze-longname-characters.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
languages = FileNameJoin[{root, "Parser", "Kernel", "Languages"}];
outFile = FileNameJoin[{languages, "LongNameCharacters.wl"}];
longNames = Association[Thread[DeleteCases[Get[FileNameJoin[{languages, "LongNames.wl"}]], Nothing] -> True]];

writtenAsNameQ[n_Integer, name_String] := ToString[FromCharacterCode[n], InputForm, CharacterEncoding -> "ASCII"] === "\"\\[" <> name <> "]\""

named = GatherBy[Select[Table[{CharacterName[FromCharacterCode[n]], n}, {n, 0, 65535}], StringQ[First[#]] && KeyExistsQ[longNames, First[#]] &], First];
table = Map[Function[g, With[{codes = If[Length[g] === 1, g[[All, 2]], Select[g[[All, 2]], writtenAsNameQ[#, g[[1, 1]]] &]]},
    If[codes === {}, Nothing, g[[1, 1]] -> First[codes]]]], named];

text = StringJoin[
    "(* The character Wolfram 15 reads for each long name of the language, name -> character code,\n",
    "   recorded by dev/freeze-longname-characters.wls. *)\n\n<|\n",
    StringRiffle[Map["    " <> ToString[First[#], InputForm] <> " -> " <> ToString[Last[#]] &, table], ",\n"], "\n|>\n"];
With[{stream = OpenWrite[outFile, CharacterEncoding -> "UTF-8"]}, WriteString[stream, text]; Close[stream]];
Print[Length[table], " long names into ", outFile];

#!/usr/bin/env wolframscript
(* Records the class of each character code below 65536 that the Wolfram Language reader lexes
   by, as Wolfram 15's WhitespaceCharacter and the reader's tables give it, into
   Parser/Assets/WolframLanguageClasses.wxf: a ByteArray of 65536 classes, that of the code c at
   c + 1. The reader reads it in place of computing the table, so every kernel lexes by exactly
   Wolfram 15's classes. Run it with Wolfram 15 after a change to the reader's character tables:
       wl -f dev/freeze-classes.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
outFile = FileNameJoin[{root, "Parser", "Assets", "WolframLanguageClasses.wxf"}];
table = Wolfram`Parser`Languages`WolframLanguage`Private`fastClassesComputed[];
Export[outFile, ByteArray[table], "WXF"];
Print[Length[table], " classes into ", outFile, ", ", FileByteCount[outFile], " bytes"];

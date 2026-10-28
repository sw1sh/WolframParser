#!/usr/bin/env wolframscript
(* Records the class of each character code below 65536 that the Wolfram Language reader lexes
   by, as the reader's tables of operators, long names and their characters give it, into
   Parser/Kernel/Languages/WolframLanguageClasses.wl: the runs {class, length} of the table from
   code 0 up. The reader reads them in place of computing the table, so every kernel lexes by
   exactly Wolfram 15's classes. Run it with Wolfram 15 after a change to the reader's character
   tables:
       wl -f dev/freeze-classes.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
outFile = FileNameJoin[{root, "Parser", "Kernel", "Languages", "WolframLanguageClasses.wl"}];
table = Wolfram`Parser`Languages`WolframLanguage`Private`fastClassesComputed[];
runs = {First[#], Length[#]} & /@ Split[table];
text = StringJoin[
    "(* The class of each character code below 65536 that the Wolfram Language reader lexes by, as\n",
    "   runs {class, length} from code 0 up: the table fastClassesComputed gives, recorded by\n",
    "   dev/freeze-classes.wls on Wolfram ", First[StringSplit[$Version]], ". Do not edit it by hand. *)\n\n",
    "{\n", StringRiffle[Map[StringRiffle[Map[ToString[#, InputForm] &, #], ", "] &, Partition[runs, UpTo[12]]], ",\n"], "\n}\n"];
With[{stream = OpenWrite[outFile]}, WriteString[stream, text]; Close[stream]];
If[Join @@ Apply[ConstantArray, Get[outFile], {1}] =!= table, Print["the file does not read back as the table"]; Exit[1]];
Print[Length[runs], " runs of ", Length[table], " classes into ", outFile, ", ", FileByteCount[outFile], " bytes"];

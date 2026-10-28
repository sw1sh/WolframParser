#!/usr/bin/env wolframscript
(* Records the character Wolfram 15's front end reads for each long name of the language,
   Languages/LongNames.wl, into Parser/Kernel/Languages/LongNameCharacters.wl, name -> character
   code: the one character of the string "\[name]" an input cell reads, the front end parsing the
   text to boxes and the kernel making the boxes an expression, as dev/frontend-held.wls reads a
   source. A name no character has is left out. RawReturn and RawBackslash are the characters the
   kernel reads: the front end puts them in the text before it reads the string, the return made a
   newline and the backslash an escape of what follows, and the reader reads a raw return and a
   raw backslash as the kernel does. Run it with Wolfram 15's kernel, which starts its own front
   end:
       WolframKernel -script dev/freeze-longname-characters.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
languages = FileNameJoin[{root, "Parser", "Kernel", "Languages"}];
outFile = FileNameJoin[{languages, "LongNameCharacters.wl"}];
names = DeleteCases[Get[FileNameJoin[{languages, "LongNames.wl"}]], Nothing];

(* the expression an input cell holding s gives, held, or None *)
frontEndHeld[s_String] := With[{p = TimeConstrained[MathLink`CallFrontEnd[FrontEnd`UndocumentedTestFEParserPacket[s, False]], 10, $Aborted]},
    If[MatchQ[p, {BoxData[_], ___}], ToExpression[p[[1, 1]], StandardForm, HoldComplete], None]]

(* the code of the one character of the string a source of a long name gives *)
nameCode[name : "RawReturn" | "RawBackslash"] := heldCode[ToExpression["\"\\[" <> name <> "]\"", InputForm, HoldComplete]]
nameCode[name_String] := heldCode[frontEndHeld["\"\\[" <> name <> "]\""]]

heldCode[HoldComplete[s_String]] /; StringLength[s] === 1 := First[ToCharacterCode[s]]
heldCode[_] := None

table = SortBy[DeleteCases[UsingFrontEnd[Map[# -> nameCode[#] &, names]], _ -> None], Last];

text = StringJoin[
    "(* The character Wolfram 15's front end reads for each long name of the language, name -> character\n",
    "   code, recorded by dev/freeze-longname-characters.wls. *)\n\n<|\n",
    StringRiffle[Map["    " <> ToString[First[#], InputForm] <> " -> " <> ToString[Last[#]] &, table], ",\n"], "\n|>\n"];
With[{stream = OpenWrite[outFile, CharacterEncoding -> "UTF-8"]}, WriteString[stream, text]; Close[stream]];
Print[Length[table], " long names into ", outFile];

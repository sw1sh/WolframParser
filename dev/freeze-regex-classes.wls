#!/usr/bin/env wolframscript
(* Records what RegularExpression matches beyond the classes of CharacterClasses.wl, as Wolfram 15's
   regex matcher does, over every code point but the surrogates:
     Parser/Kernel/RegexProperties.wl  property -> {{first, last}, ...} runs of code points, or ->
                                       the name of the property before it with the same characters,
                                       for each general category \p{name} and \p{L&};
     Parser/Kernel/CaseFolding.wl      the sets of characters that a caseless regex takes for one
                                       another, each set's codes in order.
   Run it with Wolfram 15:
       wl -f dev/freeze-regex-classes.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
codes = Join[Range[0, 16^^D7FF], Range[16^^E000, 16^^10FFFF]];
characters = FromCharacterCode /@ codes;
codesOf[test_] := Pick[codes, test[characters]];
runs[cs_List] := Developer`ToPackedArray[Map[{First[#], Last[#]} &, Split[cs, #2 == #1 + 1 &]]];
hex[c_Integer] := IntegerString[c, 16];

(* --- the general categories --- *)
categories = {"L", "Lu", "Ll", "Lt", "Lm", "Lo", "L&", "M", "Mn", "Mc", "Me", "N", "Nd", "Nl", "No", "P", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
    "S", "Sm", "Sc", "Sk", "So", "Z", "Zs", "Zl", "Zp", "C", "Cc", "Cf", "Co", "Cn"};
propertyRuns = Association[Map[# -> runs[codesOf[Function[cs, StringMatchQ[cs, RegularExpression["\\p{" <> # <> "}"]]]]] &, categories]];
names = Keys[propertyRuns];
recorded = AssociationMap[Function[name, With[{same = SelectFirst[TakeWhile[names, # =!= name &], propertyRuns[#] === propertyRuns[name] &]},
    If[MissingQ[same], propertyRuns[name], same]]], names];
runLines[rs_List] := StringRiffle[Map[StringRiffle[Map[ToString[#, InputForm] &, #], ", "] &, Partition[rs, UpTo[8]]], ",\n    "];
entry[name_String -> rs_List] := ToString[name, InputForm] <> " -> {\n    " <> runLines[rs] <> "}";
entry[name_String -> same_String] := ToString[name, InputForm] <> " -> " <> ToString[same, InputForm];
write[file_String, text_String] := With[{stream = OpenWrite[file]}, WriteString[stream, text]; Close[stream]];
propertyFile = FileNameJoin[{root, "Parser", "Kernel", "RegexProperties.wl"}];
write[propertyFile, StringJoin[
    "(* What RegularExpression's \\p{name} matches, as Wolfram 15's regex matcher does: property ->\n",
    "   {{first, last}, ...} runs of code points over every code point but the surrogates, or -> the\n",
    "   name of the property before it with the same characters. Recorded by\n",
    "   dev/freeze-regex-classes.wls on Wolfram ", First[StringSplit[$Version]], ". Do not edit it by hand. *)\n\n",
    "<|\n", StringRiffle[entry /@ Normal[recorded], ",\n"], "\n|>\n"]];
read = Get[propertyFile];
If[AssociationMap[Function[name, Replace[read[name], same_String :> read[same]]], names] =!= propertyRuns, Print["the properties do not read back"]; Exit[1]];

(* --- caseless sets: among the characters with a case, and those they become --- *)
changed = Pick[Range[Length[codes]], MapThread[#1 =!= #2 || #1 =!= #3 &, {characters, ToUpperCase[characters], ToLowerCase[characters]}]];
cased = Union[Join[codes[[changed]],
    Cases[ToCharacterCode /@ Join[ToUpperCase[characters[[changed]]], ToLowerCase[characters[[changed]]]], {c_} :> c]]];
casedCharacters = FromCharacterCode /@ cased;
sets = Union[Map[Function[c, Pick[cased, StringMatchQ[casedCharacters, RegularExpression["(?i)\\x{" <> hex[c] <> "}"]]]], cased]];
sets = Select[sets, Length[#] > 1 &];
(* each code in one set: the sets a caseless regex makes are closed *)
If[! DuplicateFreeQ[Catenate[sets]], Print["a code is in two caseless sets"]; Exit[1]];
foldFile = FileNameJoin[{root, "Parser", "Kernel", "CaseFolding.wl"}];
write[foldFile, StringJoin[
    "(* The sets of characters that a caseless RegularExpression takes for one another, as Wolfram 15's\n",
    "   regex matcher does, each set's codes in order. Recorded by dev/freeze-regex-classes.wls on\n",
    "   Wolfram ", First[StringSplit[$Version]], ". Do not edit it by hand. *)\n\n",
    "{\n    ", StringRiffle[Map[ToString[#, InputForm] &, sets], ",\n    "], "\n}\n"]];
If[Get[foldFile] =!= sets, Print["the caseless sets do not read back"]; Exit[1]];
Print["regex classes: ", Length[names], " properties, ", Total[Length /@ Select[Values[recorded], ListQ]], " runs; ", Length[sets], " caseless sets of ",
    Length[Catenate[sets]], " characters"];

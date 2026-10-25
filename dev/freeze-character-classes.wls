#!/usr/bin/env wolframscript
(* Records the characters of the classes string patterns name, as Wolfram 15 matches them, as runs
   of code points over every code point but the surrogates, into Parser/Kernel/CharacterClasses.wl:
   an Association of class -> {{first, last}, ...}, or -> the name of the class before it that has
   the same characters. The classes:
     "letter"      LetterCharacter, which LetterQ takes as letters too
     "digit"       DigitCharacter, the decimal digits of every script
     "number"      what WordCharacter takes besides letters and digits, the other numerals
     "word"        WordCharacter: the letters, the digits and the other numerals
     "whitespace"  WhitespaceCharacter
     "punctuation" PunctuationCharacter
     "hexadecimal" HexadecimalCharacter
     "upper", "lower"  the characters UpperCaseQ and LowerCaseQ take
     "regex \d", "regex \w", "regex \s", "regex \h", "regex \v" and "regex [:name:]" for each
                   POSIX class: what RegularExpression's classes match
   Run it with Wolfram 15:
       wl -f dev/freeze-character-classes.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
codes = Join[Range[0, 16^^D7FF], Range[16^^E000, 16^^10FFFF]];
characters = FromCharacterCode /@ codes;
codesOf[test_] := Pick[codes, test[characters]];
runs[cs_List] := Developer`ToPackedArray[Map[{First[#], Last[#]} &, Split[cs, #2 == #1 + 1 &]]];

letters = codesOf[StringMatchQ[#, LetterCharacter] &];
digits = codesOf[StringMatchQ[#, DigitCharacter] &];
words = codesOf[StringMatchQ[#, WordCharacter] &];
If[Pick[codes, LetterQ /@ characters] =!= letters, Print["LetterQ and LetterCharacter differ"]; Exit[1]];
If[! SubsetQ[words, Join[letters, digits]], Print["WordCharacter does not take every letter and digit"]; Exit[1]];
posix = {"alpha", "digit", "alnum", "upper", "lower", "space", "blank", "punct", "xdigit", "cntrl", "print", "graph", "word"};
classes = Join[
    <|"letter" -> letters, "digit" -> digits, "number" -> Complement[words, letters, digits], "word" -> words,
      "whitespace" -> codesOf[StringMatchQ[#, WhitespaceCharacter] &], "punctuation" -> codesOf[StringMatchQ[#, PunctuationCharacter] &],
      "hexadecimal" -> codesOf[StringMatchQ[#, HexadecimalCharacter] &],
      "upper" -> codesOf[UpperCaseQ /@ # &], "lower" -> codesOf[LowerCaseQ /@ # &],
      "regex \\d" -> codesOf[StringMatchQ[#, RegularExpression["\\d"]] &], "regex \\w" -> codesOf[StringMatchQ[#, RegularExpression["\\w"]] &],
      "regex \\s" -> codesOf[StringMatchQ[#, RegularExpression["\\s"]] &], "regex \\h" -> codesOf[StringMatchQ[#, RegularExpression["\\h"]] &],
      "regex \\v" -> codesOf[StringMatchQ[#, RegularExpression["\\v"]] &]|>,
    Association[Map["regex [:" <> # <> ":]" -> codesOf[Function[cs, StringMatchQ[cs, RegularExpression["[[:" <> # <> ":]]"]]]] &, posix]]];
classRuns = runs /@ classes;
names = Keys[classRuns];
(* a class with the characters of one before it is recorded by that one's name *)
recorded = AssociationMap[Function[class, With[{same = SelectFirst[TakeWhile[names, # =!= class &], classRuns[#] === classRuns[class] &]},
    If[MissingQ[same], classRuns[class], same]]], names];

runLines[rs_List] := StringRiffle[Map[StringRiffle[Map[ToString[#, InputForm] &, #], ", "] &, Partition[rs, UpTo[8]]], ",\n    "];
entry[class_String -> rs_List] := ToString[class, InputForm] <> " -> {\n    " <> runLines[rs] <> "}";
entry[class_String -> same_String] := ToString[class, InputForm] <> " -> " <> ToString[same, InputForm];
file = FileNameJoin[{root, "Parser", "Kernel", "CharacterClasses.wl"}];
text = StringJoin[
    "(* The characters of the classes string patterns name, as Wolfram 15 matches them: class ->\n",
    "   {{first, last}, ...} runs of code points over every code point but the surrogates, or -> the\n",
    "   name of the class before it with the same characters. Recorded by\n",
    "   dev/freeze-character-classes.wls on Wolfram ", First[StringSplit[$Version]], ". Do not edit it by hand. *)\n\n",
    "<|\n", StringRiffle[entry /@ Normal[recorded], ",\n"], "\n|>\n"];
With[{stream = OpenWrite[file]}, WriteString[stream, text]; Close[stream]];
read = Get[file];
If[AssociationMap[Function[class, Replace[read[class], same_String :> read[same]]], names] =!= classRuns,
    Print["the file does not read back as the classes"]; Exit[1]];
Scan[Print[StringPadRight[#, 18], Replace[recorded[#], {same_String :> "= " <> same,
    rs_ :> ToString[Length[classes[#]]] <> " characters in " <> ToString[Length[rs]] <> " runs"}]] &, names];
Print[FileByteCount[file], " bytes into ", file];

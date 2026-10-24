#!/usr/bin/env wolframscript
(* Records the characters of the classes string patterns name, as Wolfram 15 matches them, as runs
   of code points over every code point but the surrogates, into Parser/Assets/CharacterClasses.wxf
   (class -> {{first, last}, ...}) and Parser/Assets/CharacterClasses.tsv (class<TAB>first<TAB>last,
   hexadecimal, the format of the kernel's data/wl15/characterclasses.tsv, which is made from it).
   The classes:
     "letter"      LetterCharacter, which LetterQ takes as letters too
     "digit"       DigitCharacter, the decimal digits of every script
     "number"      what WordCharacter takes besides letters and digits, the other numerals
     "whitespace"  WhitespaceCharacter
     "punctuation" PunctuationCharacter
     "hexadecimal" HexadecimalCharacter
     "upper", "lower"  the characters UpperCaseQ and LowerCaseQ take
     "regex \d", "regex \w", "regex \s" and "regex [:name:]" for each POSIX class: what
                   RegularExpression's classes match
   Run it with Wolfram 15:
       wl -f dev/freeze-character-classes.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
assets = FileNameJoin[{root, "Parser", "Assets"}];
codes = Join[Range[0, 16^^D7FF], Range[16^^E000, 16^^10FFFF]];
characters = FromCharacterCode /@ codes;
codesOf[test_] := Pick[codes, test[characters]];
runs[cs_List] := Developer`ToPackedArray[Map[{First[#], Last[#]} &, Split[cs, #2 == #1 + 1 &]]];

letters = codesOf[StringMatchQ[#, LetterCharacter] &];
digits = codesOf[StringMatchQ[#, DigitCharacter] &];
If[Pick[codes, LetterQ /@ characters] =!= letters, Print["LetterQ and LetterCharacter differ"]; Exit[1]];
posix = {"alpha", "digit", "alnum", "upper", "lower", "space", "blank", "punct", "xdigit", "cntrl", "print", "graph", "word"};
classes = Join[
    <|"letter" -> letters, "digit" -> digits, "number" -> Complement[codesOf[StringMatchQ[#, WordCharacter] &], letters, digits],
      "whitespace" -> codesOf[StringMatchQ[#, WhitespaceCharacter] &], "punctuation" -> codesOf[StringMatchQ[#, PunctuationCharacter] &],
      "hexadecimal" -> codesOf[StringMatchQ[#, HexadecimalCharacter] &],
      "upper" -> codesOf[UpperCaseQ /@ # &], "lower" -> codesOf[LowerCaseQ /@ # &],
      "regex \\d" -> codesOf[StringMatchQ[#, RegularExpression["\\d"]] &], "regex \\w" -> codesOf[StringMatchQ[#, RegularExpression["\\w"]] &],
      "regex \\s" -> codesOf[StringMatchQ[#, RegularExpression["\\s"]] &]|>,
    Association[Map["regex [:" <> # <> ":]" -> codesOf[Function[cs, StringMatchQ[cs, RegularExpression["[[:" <> # <> ":]]"]]]] &, posix]]];
classRuns = runs /@ classes;

Export[FileNameJoin[{assets, "CharacterClasses.wxf"}], classRuns, "WXF"];
hexadecimal[code_Integer] := IntegerString[code, 16, Max[4, IntegerLength[code, 16]]];
text = StringRiffle[Join[
    {"# The characters of each class as runs of code points: class<TAB>first<TAB>last, hexadecimal.",
     "# Recorded by Wolfram/Parser's dev/freeze-character-classes.wls on " <> $Version <> "."},
    Catenate[KeyValueMap[Function[{class, rs}, StringRiffle[{class, hexadecimal[#[[1]]], hexadecimal[#[[2]]]}, "\t"] & /@ rs], classRuns]]],
    "\n"] <> "\n";
With[{stream = OpenWrite[FileNameJoin[{assets, "CharacterClasses.tsv"}], CharacterEncoding -> "UTF-8"]}, WriteString[stream, text]; Close[stream]];
Scan[Print[StringPadRight[#, 18], Length[classes[#]], " characters in ", Length[classRuns[#]], " runs"] &, Keys[classes]];

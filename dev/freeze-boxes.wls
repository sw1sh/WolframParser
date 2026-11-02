#!/usr/bin/env wolframscript
(* Records the boxes Wolfram 15's front end makes of the forms of the box tests,
   FrontEnd`ReparseBoxStructurePacket's answers, into
   Parser/Tests/Languages/WolframLanguageBoxes.wlt, between its "BEGIN frozen" and
   "END frozen" lines, so the tests run on a kernel without a front end. The forms
   are those of the concrete syntax tree tests and the kinds the converter sends
   over PureMath's pages. Run it with Wolfram 15's kernel, which starts its own
   front end:
       WolframKernel -script dev/freeze-boxes.wls *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
tests = FileNameJoin[{root, "Parser", "Tests", "Languages"}];
testFile = FileNameJoin[{tests, "WolframLanguageBoxes.wlt"}];

(* the concrete tests' forms, the first of each entry of their $concreteTrees *)
concreteForms = Replace[
    Cases[
        ImportString[ByteArrayToString[ReadByteArray[FileNameJoin[{tests, "WolframLanguageConcrete.wlt"}]], "UTF-8"], {"Package", "HeldExpressions"}],
        HoldPattern[$concreteTrees = trees_List] :> First /@ trees, Infinity],
    {{forms_List, ___} :> forms, _ :> (Print["no $concreteTrees in the concrete tests"]; Exit[1])}];

(* the kinds of text the converter sends the front end *)
frontEndForms = {
    "SmoothNumberQ[12, 3]", "c[\"Product\", 1, {{1, 0}}]", "lower = {{0, 1}, {0, 0}}", "(t - c) . (t - p) == 0",
    (* runs of spaces and tabs, newlines and indents *)
    "f[a,   b]", "f[\n  x]", "Simplify[\n\tf[x] +\n\t\tg[x]\n]", "functor = <|\"a\" -> 1,\n   \"b\" -> 2|>",
    (* a token alone *)
    "(", "{", "[", "x", "1", "\"s\"",
    (* lone operators, stray closers, groups not closed *)
    "^", "*", ")", "] \[LessEqual] 1/2", "f[", "D[", "f[\"MinimizingTerms\",", "OrdinalForm[<code>OrdinalPlus",
    (* patterns and other compound tokens *)
    "g_?MatrixLieGroupQ", "MatchQ[x, _FinitelyPresentedGroup]", "f_1", "betti_k", "x_.", "#1 + #2 &", "%2",
    (* derivatives *)
    "y''[x] + y'[x]/x", "SturmLiouvilleForm[(1 - x^2) y''[x] - 2 x y'[x] + \\[Lambda] y[x] == 0, y, x, \\[Lambda]]",
    (* long names, in code and in strings *)
    "\\[Lambda] y[x]", "{\"\\[Bullet]\"}", "\"a\\\\[Bullet]\"", "\\[Alpha] + \\[NotALongName]",
    (* comments and dots *)
    "f[x] (* a comment *)",
    (* active linear syntax in a string, one token; the blank after a product of names written apart *)
    "\"\!\(\*StyleBox[\"prop\",\"TI\"]\)\"", "c[\"\!\(\*StyleBox[\"prop\",\"TI\"]\)\"]", "The expression ", "Further output of ", "f[a b ]", "(* line1\nline2 *)", "f[x] (* a\n  b *)", "(* a\n(* b *)\nc *)", "(* a +\n b *)\nx", "<|\"TermRanks\" -> {...}, \"FirstDifferential\" -> d1|>", "{z$1, \[Ellipsis], z$n}"
};

forms = DeleteDuplicates[Join[frontEndForms, concreteForms]];
answer[s_String] := MathLink`CallFrontEnd[FrontEnd`ReparseBoxStructurePacket[s]];
answers = UsingFrontEnd[{#, answer[#]} & /@ forms];

shown[e_] := Block[{$ContextPath = {"System`"}}, ToString[e, InputForm, CharacterEncoding -> "ASCII"]];
block = StringJoin["$frontEndBoxes = {\n", StringRiffle[Map["    {" <> shown[#[[1]]] <> ", " <> shown[#[[2]]] <> "}" &, answers], ",\n"], "\n};\n"];

text = ByteArrayToString[ReadByteArray[testFile], "UTF-8"];
If[ ! StringContainsQ[text, "(* BEGIN frozen" ~~ Shortest[___] ~~ "(* END frozen *)"],
    Print["no BEGIN frozen / END frozen lines in ", testFile]; Exit[1]];
updated = StringReplace[text,
    start : ("(* BEGIN frozen" ~~ Shortest[___] ~~ "*)\n") ~~ Shortest[___] ~~ end : "(* END frozen *)" :> start <> block <> end, 1];
With[{stream = OpenWrite[testFile, CharacterEncoding -> "UTF-8"]}, WriteString[stream, updated]; Close[stream]];
Print["froze the front end's boxes of ", Length[answers], " forms into ", testFile];

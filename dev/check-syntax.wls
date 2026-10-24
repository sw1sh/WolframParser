#!/usr/bin/env wolframscript
(* Checks WolframLanguageSyntaxQ and WolframLanguageSyntaxLength against Wolfram 15's SyntaxQ and
   SyntaxLength: on a list of forms that read and that do not, and on chunks of the paclet's files
   cut short, with a character taken out and with one put in. Run it with Wolfram 15:
       wl -f dev/check-syntax.wls [count]
   It prints how many agree, then each that does not, up to count (by default 20). *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];
Off[General::stop];
SeedRandom[20261025];
shown = Replace[Interpreter["Integer"][Last[$ScriptCommandLine, "20"]], Except[_Integer] -> 20];

forms = {"", " ", "a", "a + b c", "a + b)", "f[x", "f[x)", "a +", "1 + 2 * 3 + 4 }", "a\nb", "a\n)", "x = 1\n1 +", "a;", "(* c *)", "(* c",
    "\"abc", "a)b", "f[x]]", "a::_", "a::", "a::1", "a::b::c::", "f[x] ::=", "?a*=b", "f[1,]", "a \\[Foo] b", "\\[Foo]", "a\\[Foo] b", "x = a\\[Foo]",
    "a`", "x = a`", "a\\b", "f[x] : y", "x_ | y_ : 1", "x_ : y_ : 1", "x_. : 1", "a ~ b c", "a ~ b & ~ c", "i ~ s t, u", "<|a -> 1", "a //= f",
    "\\!\\(x\\^2\\)", "\\!\\(x", "\\(x", "a\\\nb", "a\\\n)", "f[\nx\n", "  (* c", "a\n\"abc", "a + \"abc", "a + (* c", "<<", "x = <<", "t/:a", "t/:a\n",
    "t/:", "1 + (2", "]", ")", "(* c *) )"};
text[file_String] := ByteArrayToString[ReadByteArray[file], "UTF-8"];
files = Catenate[FileNames["*.wl" | "*.wls", FileNameJoin[{root, #}], Infinity] & /@ {"Parser/Kernel", "dev"}];
chunks = RandomSample[Select[Catenate[StringSplit[text[#], "\n\n"] & /@ files], 2 < StringLength[#] < 300 &], UpTo[400]];
characters = Characters[")]},;+*[{(\"~@/:=.!#&|<>\\-^'_\n "];
mutated = DeleteDuplicates[Catenate[Function[b, Join[{b},
    Table[StringTake[b, k], {k, 1, StringLength[b] - 1, Max[1, Floor[StringLength[b] / 6]]}],
    Table[With[{k = RandomInteger[{1, StringLength[b]}]}, StringDrop[b, {k}]], {3}],
    Table[With[{k = RandomInteger[{1, StringLength[b] + 1}]}, StringInsert[b, RandomChoice[characters], k]], {5}]]] /@ chunks]];

sources = DeleteDuplicates[Join[forms, mutated]];
results = Map[{#, {SyntaxQ[#], SyntaxLength[#]}, {WolframLanguageSyntaxQ[#], WolframLanguageSyntaxLength[#]}} &, sources];
qDiffer = Select[results, #[[2, 1]] =!= #[[3, 1]] &];
lDiffer = Select[results, #[[2, 1]] === #[[3, 1]] && #[[2, 2]] =!= #[[3, 2]] &];

Print[Length[sources], " sources: SyntaxQ agrees on ", Length[sources] - Length[qDiffer], ", SyntaxLength on ",
    Length[sources] - Length[qDiffer] - Length[lDiffer], " of those"];
Scan[Print[ToString[StringTake[#[[1]], UpTo[160]], InputForm, CharacterEncoding -> "ASCII"], "   kernel ", #[[2]], "   ours ", #[[3]]] &,
    Take[Join[qDiffer, lDiffer], UpTo[shown]]];

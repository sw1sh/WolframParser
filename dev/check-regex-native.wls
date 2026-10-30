#!/usr/bin/env wolframscript
(* Holds the regexes of the engine of string patterns to the programs, through the C library's own
   regcomp and regexec, called by ForeignFunctionLoad: the native matcher a kernel runs a pattern's
   "Regex" with, on an ASCII string, where the program says a regex matches as it does. Over random
   patterns and ASCII strings it compiles each regex, takes its matches from the left as a kernel
   does, the next a byte after an empty one, and compares their spans and the text of each named
   group with the program's matches; and, where a regex finds a match wherever the program has one,
   whether there is one; over random patterns of string expressions, and over random regexes, the
   groups of a RegularExpression by their numbers. Run it with Wolfram 15:
       wl -f dev/check-regex-native.wls [cases] [seed]
   It prints what disagrees, then the counts. *)

$ProgressReporting = False;

root = ParentDirectory[DirectoryName[$InputFileName]];
PacletDirectoryLoad[FileNameJoin[{root, "Parser"}]];
Needs["Wolfram`Parser`"];

(* the arguments after the script's path, by wolframscript or by WolframKernel -script *)
arguments = If[$ScriptCommandLine =!= {}, Rest[$ScriptCommandLine], Replace[$CommandLine, {{___, "-script", _, rest___} :> {rest}, _ -> {}}]];
count = If[Length[arguments] >= 1, Interpreter["Integer"][arguments[[1]]], 3000];
seed = If[Length[arguments] >= 2, Interpreter["Integer"][arguments[[2]]], 1];
SeedRandom[seed];

(* --- the C library's regex, through a library of the installation, whose own libraries hold it --- *)

$compileType = {"RawPointer"::["UnsignedInteger8"], "RawPointer"::["UnsignedInteger8"], "CInt"} -> "CInt";
$library = SelectFirst[FileNames["*.dylib" | "*.so" | "*.so.*", FileNameJoin[{$InstallationDirectory, "SystemFiles", "Libraries", $SystemID}]],
    Head[ForeignFunctionLoad[#, "regcomp", $compileType]] === ForeignFunction &, None];
If[$library === None, Print["no library of the installation holds regcomp"]; Exit[1]];
regcomp = ForeignFunctionLoad[$library, "regcomp", $compileType];
regexec = ForeignFunctionLoad[$library, "regexec",
    {"RawPointer"::["UnsignedInteger8"], "RawPointer"::["UnsignedInteger8"], "CSizeT", "RawPointer"::["Integer64"], "CInt"} -> "CInt"];
cString[s_String] := RawMemoryExport[Append[ToCharacterCode[s], 0], "UnsignedInteger8"]

(* the compiled regex, REG_EXTENDED, or the status regcomp gives *)
compiled[regex_String] := With[{buffer = RawMemoryAllocate["UnsignedInteger8", 1024]},
    With[{status = regcomp[buffer, cString[regex], 1]}, If[status === 0, buffer, status]]]

(* The matches from the left, {start, end, groups} with a group {start, end} or None, the next
   searched from the end of each, a byte after an empty one; REG_STARTEND, 4, gives each search its
   range, and REG_NOTBOL, 1, keeps ^ from matching past the start. *)
nativeMatches[buffer_, s_String, groups_Integer] := Module[{text = cString[s], n = StringLength[s], positions = RawMemoryAllocate["Integer64", 2 (groups + 1)], offset = 0, out = {}, found},
    While[ offset <= n,
        RawMemoryWrite[positions, offset, 0]; RawMemoryWrite[positions, n, 1];
        found = regexec[buffer, text, groups + 1, positions, If[offset > 0, 5, 4]];
        If[found =!= 0, Break[]];
        With[{start = RawMemoryRead[positions, 0], end = RawMemoryRead[positions, 1]},
            AppendTo[out, {start, end, Table[With[{a = RawMemoryRead[positions, 2 g], b = RawMemoryRead[positions, 2 g + 1]}, If[a < 0, None, {a, b}]], {g, groups}]}];
            offset = If[end === start, start + 1, end]]];
    out]

(* --- random patterns and ASCII strings, special characters of brackets among them --- *)

$alphabet = {"a", "b", "1", " ", "-", "]", "^", "\\", "[", ".", "\n", "_", ",", "A", "\t"};
randomString[] := StringJoin[RandomChoice[$alphabet, RandomInteger[{0, 8}]]]
$lists = {{"a", "1"}, {"]", "a"}, {"-", "b"}, {"^"}, {"^", "-"}, {"\\", "]"}, {"[", "a"}, {"]", "^", "-", "\\", "["}};
leaf[] := RandomChoice[{4, 2, 3, 3, 1, 2} -> {
    RandomChoice[{"a", "b", "ab", "1", " ", "-", "]", "^", "\\", "[", ".", "a.b"}] &,
    RandomChoice[{Blank[], BlankSequence[], BlankNullSequence[]}] &,
    RandomChoice[{DigitCharacter, LetterCharacter, WordCharacter, WhitespaceCharacter, PunctuationCharacter, HexadecimalCharacter, Whitespace}] &,
    RandomChoice[$lists] &,
    RandomChoice[{StartOfString, EndOfString}] &,
    Except[RandomChoice[Join[$lists, {DigitCharacter, LetterCharacter, WhitespaceCharacter, "a", "^"}]]] &}][]
pattern[0] := leaf[]
pattern[d_Integer] := RandomChoice[{5, 5, 3, 2, 2, 1, 2} -> {
    leaf[] &, StringExpression[pattern[d - 1], pattern[d - 1]] &, Alternatives[pattern[d - 1], pattern[d - 1]] &,
    Repeated[pattern[d - 1]] &, RepeatedNull[pattern[d - 1]] &, Repeated[pattern[d - 1], RandomChoice[{{1, 2}, {2}, 2}]] &,
    Pattern[Evaluate[RandomChoice[{x, y}]], pattern[d - 1]] &}][]

(* random regexes of PCRE's syntax, those POSIX has no part of among them, which have no regex *)
$reCharacters = {"a", "b", "1", " ", "-", "\\.", "\\-", "\\n", "\\t", "_", "]", "\\^", "\\\\", "\\[", ",", "A"};
$reClasses = {".", "\\d", "\\w", "\\s", "\\D", "\\W", "\\S", "\\h", "\\v", "\\N", "[ab]", "[^ab]", "[a-c]", "[[:alpha:]]", "[[:upper:]]",
    "[[:lower:]]", "[\\d\\s]", "[^[:punct:]]", "\\p{Lu}", "\\p{L}", "\\P{L}", "\\p{Nd}", "[]a]", "[^]a]", "[a-]", "[\\^a]", "[\\]\\-^]", "[A-Za-z]"};
$reAnchors = {"^", "$", "\\b", "\\B", "\\A", "\\z", "\\Z"};
$reQuantifiers = {"*", "+", "?", "{2}", "{1,2}", "{0,1}", "{2,}", "*?", "+?", "*+"};
reAtom[0] := RandomChoice[{6, 4, 1} -> {RandomChoice[$reCharacters] &, RandomChoice[$reClasses] &, RandomChoice[$reAnchors] &}][]
reAtom[d_Integer] := RandomChoice[{8, 3, 2, 1, 1, 1, 1} -> {
    reAtom[0] &, "(" <> re[d - 1] <> ")" &, "(?:" <> re[d - 1] <> ")" &, "(?=" <> re[d - 1] <> ")" &, "(?>" <> re[d - 1] <> ")" &,
    "(?i:" <> re[d - 1] <> ")" &, "\\1" &}][]
rePiece[d_Integer] := With[{a = reAtom[d]}, If[RandomReal[] < 0.4 && ! MemberQ[$reAnchors, a], a <> RandomChoice[$reQuantifiers], a]]
re[d_Integer] := StringRiffle[Table[StringJoin[Table[rePiece[d], {RandomInteger[{1, 3}]}]], {RandomChoice[{6, 2, 1} -> {1, 2, 3}]}], "|"]

(* --- the cases --- *)

like = 0; finds = 0; regexLike = 0; regexFinds = 0; rejected = {}; differ = {};
Do[
    With[{p = If[OddQ[i], pattern[RandomInteger[{0, 3}]], RegularExpression[re[RandomInteger[{0, 2}]]]], s = randomString[]},
        With[{program = StringPatternProgram[p]},
            If[ ListQ[program["Regex"]] && (TrueQ[program["RegexLike"]] || TrueQ[program["RegexFinds"]]),
                With[{regex = program["Regex"][[1]], names = program["Regex"][[2]], buffer = compiled[program["Regex"][[1]]]},
                    If[ IntegerQ[buffer], AppendTo[rejected, {p, regex, buffer}],
                        With[{native = nativeMatches[buffer, s, Length[names]], ours = StringPatternMatches[s, {program}, "First"]},
                            If[ TrueQ[program["RegexLike"]],
                                like++; If[MatchQ[p, _RegularExpression], regexLike++];
                                With[{nativeSpans = native[[All, ;; 2]], oursSpans = ours[[All, ;; 2]],
                                        nativeNames = Map[Function[m, Association[MapThread[
                                            Function[{name, group}, If[MatchQ[name, _HoldComplete | _Integer], name -> If[group === None, "", StringTake[s, {group[[1]] + 1, group[[2]]}]], Nothing]],
                                            {names, m[[3]]}]]], native],
                                        oursNames = Map[Function[m, Association[Map[Replace[#, (Verbatim[HoldPattern][v_] -> text_) :> (HoldComplete[v] -> text)] &, m[[4]]]]], ours]},
                                    If[ nativeSpans =!= oursSpans || KeySort /@ nativeNames =!= KeySort /@ oursNames,
                                        AppendTo[differ, {p, s, regex, native, ours}]]],
                                finds++; If[MatchQ[p, _RegularExpression], regexFinds++];
                                If[(native =!= {}) =!= (ours =!= {}), AppendTo[differ, {p, s, regex, native, ours}]]]]]]]]],
    {i, count}];

Scan[Print["   regcomp rejects ", ToString[#[[2]], InputForm], " of ", ToString[#[[1]], InputForm], ": ", #[[3]]] &, Take[rejected, UpTo[10]]];
Scan[Print["   ", ToString[#[[1]], InputForm], " on ", ToString[#[[2]], InputForm], " as ", ToString[#[[3]], InputForm],
    "\n      native ", ToString[#[[4]], InputForm], "\n      ours   ", ToString[#[[5]], InputForm]] &, Take[differ, UpTo[20]]];
Print["regex native: ", count, " cases, seed ", seed, ", through ", FileNameTake[$library], ": ", like, " where a regex matches as the program does, ",
    finds, " where it finds a match where the program has one (of them ", regexLike, " and ", regexFinds, " of a RegularExpression); ", Length[differ], " differ, ",
    Length[rejected], " regexes regcomp rejects"];

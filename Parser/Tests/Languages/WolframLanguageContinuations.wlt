(* :Title: WolframLanguageContinuations.wlt - the line continuations a source holds *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Summary: the typed scan of a source's line continuations, fastContinuations, against the scan
   a character at a time that continuationSpans read them by before it: the same spans, in code,
   strings and comments, with returns, escapes and the end of the source; a source with a << or >>
   in code left to the scan; the typed scan being the one that runs; and the spans of the source
   information of Wolfram 15's documentation, 12 MB, where it is installed. Run via
   run-tests.wls. *)

ClearAll[$continuationCases]

(* {source, its spans} *)
$continuationCases = {
    (* in code: the \, the newline and the spaces and tabs after it *)
    {"a\\\nb", {{2, 3}}},
    {"f[a,\\\n  \t b]", {{5, 10}}},
    (* runs that follow one another are one span *)
    {"a\\\n\\\nb", {{2, 5}}},
    (* a return, a return and a newline *)
    {"a\\\rb", {{2, 3}}},
    {"a\\\r\nb", {{2, 4}}},
    (* a \ that escapes a \ before the newline continues nothing *)
    {"a\\\\\nb", {}},
    (* a \ at the very end of the source *)
    {"a\\", {}},
    (* in a string, only a run that reaches the end of the source *)
    {"x = \"ab\\\ncd\"", {}},
    {"\"abc\\\n", {{5, 6}}},
    {"\"abc\\\n  ", {{5, 8}}},
    {"\"a\\\"b\\\n", {{6, 7}}},
    (* in a comment none, nested comments and \( in them too; after the comment again *)
    {"(* a \\\n b *) c\\\nd", {{15, 16}}},
    {"(* (* \\( *) \\\n *) e\\\n f", {{20, 22}}},
    {"(* *) \"(*\" \\\n", {{12, 13}}},
    (* a comment's text inside a string is the string's *)
    {"\"(*\" a\\\nb *)", {{7, 8}}}
};

(* the scan a character at a time, which continuationSpans keeps for sources with << or >> *)
scanned[s_String] := Wolfram`Parser`Languages`WolframLanguage`Private`scannedContinuationSpans[s]
typed[s_String] := Wolfram`Parser`Languages`WolframLanguage`Private`typedContinuationSpans[s]
spans[s_String] := Wolfram`Parser`Languages`WolframLanguage`Private`continuationSpans[s]

VerificationTest[
    Select[$continuationCases, scanned[#[[1]]] =!= #[[2]] &],
    {},
    TestID -> "The scan a character at a time gives each case's spans"]

VerificationTest[
    Select[$continuationCases, typed[#[[1]]] =!= #[[2]] &],
    {},
    TestID -> "The typed scan gives each case's spans"]

VerificationTest[
    Select[$continuationCases, spans[#[[1]]] =!= #[[2]] &],
    {},
    TestID -> "continuationSpans gives each case's spans"]

(* << and >> in code, whose file names only the scan a character at a time reads *)
VerificationTest[
    {typed["Get << a\\\nb"], typed["x >> b\\\nc"], typed["\"<<\" a\\\nb"], typed["(* >> *) a\\\nb"]},
    {None, None, {{7, 8}}, {{11, 12}}},
    TestID -> "The typed scan leaves a source with << or >> in code to the scan"]

VerificationTest[
    {spans["Get << a\\\nb"], spans["x >> b\\\nc"]},
    {scanned["Get << a\\\nb"], scanned["x >> b\\\nc"]},
    TestID -> "continuationSpans reads a source with << or >> in code by the scan"]

(* the typed scan, not the declaration's Function evaluated, is the one that runs: the
   definition a compiler of typed code gave, or Compile's *)
VerificationTest[
    MatchQ[Wolfram`Parser`Languages`WolframLanguage`Private`fastContinuationsFunction,
        Wolfram`Parser`Languages`WolframLanguage`Private`fastContinuations | _CompiledFunction],
    True,
    TestID -> "The typed continuation scan is compiled"]

(* a long source of strings with escapes and continuations, against the scan *)
VerificationTest[
    With[{s = StringJoin[Table[{"f[\"a\\\"b\", ", ToString[k], ",\\\n  \"c\\\\\"]\n"}, {k, 2000}], "\"end\\\n"]},
        {Length[typed[s]], typed[s] === scanned[s]}],
    {2001, True},
    TestID -> "The typed scan of a long source gives the scan's spans"]

(* the source information of Wolfram 15's documentation, where it is installed: 12 MB, 403 runs *)
$sourceInformation = FileNameJoin[{$InstallationDirectory, "SystemFiles", "Components", "PacletTools", "DocumentationBuild", "Assets",
    "Data", "SystemSourceInfo", "SourceInformation.en.m"}];

VerificationTest[
    If[FileExistsQ[$sourceInformation],
        With[{s = ReadString[$sourceInformation]}, With[{t = typed[s]}, {Length[t], t === scanned[s]}]],
        {403, True}],
    {403, True},
    TestID -> "The typed scan of Wolfram 15's documentation source information gives the scan's 403 spans"]

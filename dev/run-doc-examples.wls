#!/usr/bin/env wolframscript
(* Run the ```wl cells of the doc sources the way the built page evaluates them,
   and hold every cell to the output rules of docs/DOC_GUIDE.md.

   Usage:
     wl -f dev/run-doc-examples.wls                        every page under docs/
     wl -f dev/run-doc-examples.wls docs/Symbols/Parse.md  the pages given
     wl -f dev/run-doc-examples.wls --write [page.md ...]  also rewrite the hints

   Each page evaluates top to bottom in one private context, as MarkdownToNotebook
   evaluates it. build.wls converts every page with "EvaluateSeparator" -> None, so
   state threads from a page's first cell to its last; a cell is parsed whole before
   any of it runs, so its symbols bind before its own Needs does; and the evaluation
   $ContextPath holds the frontmatter Context and ContextPath entries, the paclet's
   own context, System`, and every non-Private subcontext of those. A
   `#| eval: false` cell is a listing and is never evaluated.

   A cell is reported when
     message   it issues a message its <!-- => ... --> hint does not name, or does
               not issue one the hint names ("the message Sym::tag is issued and ...");
     aborted   it aborts, or runs past the per-cell time limit;
     echo      its output is its own input back, and the input reads a page symbol
               that has no value - a binding made nowhere, or made later;
     path      its output shows a path under $TemporaryDirectory, which differs on
               every machine (end the cell in ';');
     private   its output is a value that shows a Private` symbol the page's prose
               never names - implementation detail leaking into an example, to be
               shown through a summary box or a property, or not at all;
     wrong     its hint is not the output's InputForm, character for character;
     visual    its output is a summary box, a graphic, a Failure, a color, a link
               or a layout, and it carries a value hint;
     missing   its output is a value whose InputForm is at most 160 characters, and
               it carries no hint.
   A value that varies between runs - a timing, a random draw, a date, a fresh
   x$123 temporary - never carries a hint, and one whose InputForm passes 400
   characters needs none.

   With --write, a wrong or missing hint is rewritten from the output, and a value
   hint on a visual, long or varying output is removed; message hints are the
   author's and are left alone. Exits 1 when anything is reported - after --write,
   when anything --write could not settle remains. *)

$ProgressReporting = False

rootDir = ParentDirectory[DirectoryName[$InputFileName]]
PacletDirectoryLoad[FileNameJoin[{rootDir, "Parser"}]]
Needs["Wolfram`Parser`"]
(* build.wls warms the compiler before it converts anything; the first
   FunctionCompile of a session issues a one-time General::shdw, here rather than
   inside the first ParserCompile cell. *)
ParserCompile[ParseLiteral["x"]];

(* pages are read and written as exact UTF-8 bytes, so a rewrite changes nothing
   but the hints - not the final newline, not an encoding *)
readText[file_String] := ByteArrayToString[ReadByteArray[file], "UTF-8"]
writeText[file_String, text_String] := With[{s = OpenWrite[file, BinaryFormat -> True]},
    BinaryWrite[s, StringToByteArray[text, "UTF-8"]]; Close[s]]

args = Rest[$ScriptCommandLine]
write = MemberQ[args, "--write"]
pages = Replace[DeleteCases[args, "--write"], {
    {} :> Select[Sort @ FileNames["*.md", FileNameJoin[{rootDir, "docs"}], Infinity],
        StringStartsQ[StringTrim @ readText[#], "---"] && StringContainsQ[readText[#], "```wl"] &],
    files_ :> ExpandFileName /@ files}]

cellLimit = 600
valueHintMax = 160
longValue = 400

(* One record per ```wl cell: its code (option lines dropped), its options, the
   character span of its hint comment, and the hint. *)
pageCells[text_String] := Map[
    Function[span, Module[{lines, after, hint},
        lines = StringSplit[StringTake[text, {span[[1]] + 6, span[[2]] - 4}], "\n", All];
        after = StringTake[text, {span[[2]] + 1, Min[span[[2]] + 4000, StringLength[text]]}];
        hint = StringCases[after, StartOfString ~~ "\n\n<!-- => " ~~ h : Shortest[___] ~~ " -->" :> h, 1];
        <|
            "Code" -> StringRiffle[Select[lines, ! StringStartsQ[StringTrim[#], "#|"] &], "\n"],
            "Options" -> StringTrim /@ Select[lines, StringStartsQ[StringTrim[#], "#|"] &],
            "Line" -> StringCount[StringTake[text, span[[1]]], "\n"] + 1,
            "End" -> span[[2]],
            "Hint" -> If[hint === {}, None, First[hint]],
            "HintSpan" -> If[hint === {}, None,
                {span[[2]] + 1, span[[2]] + StringLength["\n\n<!-- => " <> First[hint] <> " -->"]}]
        |>]],
    StringPosition[text, RegularExpression["(?m)^```wl\\n[\\s\\S]*?\\n```$"]]]

(* MarkdownToNotebook's evaluation path: the frontmatter Context and ContextPath
   entries and the paclet's context, then System`, then every non-Private
   subcontext of those - a page with Context Wolfram`Parser` sees the bundled
   languages' symbols as the build does. *)
frontmatterContexts[text_String] := DeleteDuplicates @ DeleteCases[Flatten @ {
    StringCases[text, StartOfLine ~~ "Context:" ~~ Whitespace ~~ c : Except["\n"] .. :> StringTrim[c], 1],
    StringCases[text, StartOfLine ~~ "ContextPath:" ~~ Whitespace ~~ "[" ~~ c : Except["]" | "\n"] ... ~~ "]" :>
        StringTrim /@ StringSplit[c, ","], 1],
    "Wolfram`Parser`"}, "" | "System`"]

evaluationPath[ctxs_List] := DeleteDuplicates @ Join[ctxs, {"System`"},
    Flatten[Select[Contexts[# <> "*"], ! StringEndsQ[#, "Private`"] &] & /@ ctxs]]

messageHintQ[hint_] := StringQ[hint] && StringStartsQ[hint, "the message"]
shortName[name_String] := Last[StringSplit[name, "`"]]
hintMessages[hint_] := If[StringQ[hint],
    shortName /@ StringCases[hint, RegularExpression["[A-Za-z$][A-Za-z0-9$`]*::[A-Za-z0-9]+"]], {}]
issuedMessages[data_Association] := DeleteDuplicates @ Cases[
    Lookup[data, "MessagesExpressions", {}, Hold],
    HoldPattern[Message[MessageName[s_Symbol, t_String], ___]] :> SymbolName[Unevaluated[s]] <> "::" <> t,
    Infinity]

(* Results stay wrapped in HoldComplete from the moment they are produced, so
   reading one never evaluates it a second time. *)
heldForm[HoldComplete[x_]] := ToString[Unevaluated[x], InputForm, PageWidth -> Infinity, CharacterEncoding -> "ASCII"]

visualQ[rh_HoldComplete] := MatchQ[rh, HoldComplete[_ParserCombinator | _Failure | _Graphics | _Graphics3D |
        _Image | _Graph | _Grid | _Column | _Row | _Pane | _Panel | _Framed | _Style | _Labeled | _Legended |
        _Dataset | _DisplayForm | _TraditionalForm | _MatrixForm | _TableForm | _RawBoxes |
        _RGBColor | _GrayLevel | _Hue | _CMYKColor | _LABColor | _LCHColor | _CloudObject | _Hyperlink]] ||
    ! FreeQ[rh /. HoldComplete[x_] :> MakeBoxes[x, StandardForm],
        TagBox[_, "SummaryHead"] | _GraphicsBox | _Graphics3DBox | _GridBox | _DynamicModuleBox]

varyingCodeQ[code_String] := StringContainsQ[code,
    RegularExpression["\\b(Timing|AbsoluteTiming|RepeatedTiming|Random[A-Za-z]*|Now|Today|Date[A-Za-z]*|SessionTime|AbsoluteTime|CreateUUID)\\b"]]
varyingFormQ[s_String] := StringContainsQ[s, RegularExpression["[A-Za-z]\\$[0-9]+"]]

(* symbols of the page's own context that the held input reads but nothing defines *)
unboundPageSymbols[held_HoldComplete, ctx_String] := Select[
    DeleteDuplicates @ Cases[held, s_Symbol :> HoldComplete[s], {0, Infinity}, Heads -> True],
    Function[h, h /. HoldComplete[s_] :> (Context[Unevaluated[s]] === ctx &&
        OwnValues[s] === {} && DownValues[s] === {} && SubValues[s] === {} && UpValues[s] === {})]]

privateNames[s_String] := DeleteDuplicates @
    StringCases[s, RegularExpression["Private`([A-Za-z$][A-Za-z0-9$]*)"] -> "$1"]

runCell[cell_Association, ctx_String, prose_String] := Module[{code = cell["Code"], hint = cell["Hint"], data, rh, s, held,
        issued, named, issues = {}, newHint = cell["Hint"]},
    data = Block[{$Messages = {}},
        held = ToExpression[code, InputForm, HoldComplete];
        EvaluationData[TimeConstrained[
            If[ MatchQ[held, _HoldComplete],
                Module[{r = Null}, Do[r = Extract[held, k], {k, Length[held]}]; r],
                ToExpression[code]  (* a parse failure: run it for its message *)
            ],
            cellLimit, $TimedOut]]];
    rh = Lookup[data, "Result", Null, HoldComplete];
    issued = issuedMessages[data];
    named = hintMessages[hint];
    If[ Complement[issued, named] =!= {} || Complement[named, issued] =!= {},
        AppendTo[issues, {"message", "issued " <> ToString[issued] <> ", hint names " <> ToString[named]}]];
    s = heldForm[rh];
    Which[
        MatchQ[rh, HoldComplete[$Aborted | $TimedOut]],
            AppendTo[issues, {"aborted", s}],
        messageHintQ[hint] || rh === HoldComplete[Null] && hint === None,
            Null,
        rh === HoldComplete[Null],
            AppendTo[issues, {"wrong", "no output, but a hint"}]; newHint = None,
        MatchQ[held, HoldComplete[_]] && s === heldForm[held] && unboundPageSymbols[held, ctx] =!= {},
            AppendTo[issues, {"echo", "unbound " <> StringRiffle[heldForm /@ unboundPageSymbols[held, ctx], ", "]}],
        StringContainsQ[s, $TemporaryDirectory],
            AppendTo[issues, {"path", "output shows " <> $TemporaryDirectory}]; newHint = None,
        visualQ[rh],
            If[hint =!= None, AppendTo[issues, {"visual", rh /. HoldComplete[x_] :> Head[Unevaluated[x]]}]; newHint = None],
        varyingCodeQ[code] || varyingFormQ[s],
            If[hint =!= None, AppendTo[issues, {"wrong", "varying output, but a hint"}]; newHint = None],
        True,
            With[{leaked = Select[privateNames[s], ! StringContainsQ[prose, #] &]},
                If[leaked =!= {}, AppendTo[issues, {"private", StringRiffle[leaked, ", "]}]]];
            Which[
                StringLength[s] > longValue,
                    If[hint =!= None && hint =!= s, AppendTo[issues, {"wrong", "long value, hint differs"}]; newHint = None],
                hint === None,
                    If[StringLength[s] <= valueHintMax, AppendTo[issues, {"missing", s}]; newHint = s],
                hint =!= s,
                    AppendTo[issues, {"wrong", "hint " <> StringTake[hint, UpTo[120]] <> "\n        output " <> StringTake[s, UpTo[120]]}];
                    newHint = s
            ]
    ];
    <|"Issues" -> issues, "NewHint" -> newHint|>
]

rewrite[text_String, cells_List, results_List] := Fold[
    Function[{t, k}, With[{c = cells[[k]], h = results[[k]]["NewHint"]},
        Which[
            h === c["Hint"], t,
            c["HintSpan"] =!= None && h === None, StringReplacePart[t, "", c["HintSpan"]],
            c["HintSpan"] =!= None, StringReplacePart[t, "\n\n<!-- => " <> h <> " -->", c["HintSpan"]],
            True, StringInsert[t, "\n\n<!-- => " <> h <> " -->", c["End"] + 1]
        ]]],
    text,
    Reverse @ Range[Length[cells]]]

reported = 0
Scan[Function[page, Module[{text = readText[page], cells, live, ctxs, ctx, results, rest},
    cells = pageCells[text];
    live = Select[Range[Length[cells]], ! MemberQ[cells[[#]]["Options"], "#| eval: false"] &];
    ctxs = frontmatterContexts[text];
    Scan[Needs, ctxs];
    ctx = "DocPage" <> IntegerString[Hash[page], 36] <> "`";
    results = Table[<|"Issues" -> {}, "NewHint" -> c["Hint"]|>, {c, cells}];
    Block[{$Context = ctx, $ContextPath = evaluationPath[ctxs]},
        With[{prose = StringDelete[text, RegularExpression["(?ms)^```.*?^```$"]]},
            Scan[(results[[#]] = runCell[cells[[#]], ctx, prose]) &, live]]];
    If[write,
        writeText[page, rewrite[text, cells, results]];
        rest = DeleteCases[#, {"wrong" | "missing" | "visual" | "path", ___}] & /@ results[[All, "Issues"]],
        rest = results[[All, "Issues"]]
    ];
    With[{bad = Select[Transpose[{cells, rest}], #[[2]] =!= {} &]},
        reported += Total[Length /@ bad[[All, 2]]];
        Print[If[bad === {}, "PASS ", "FAIL "], FileNameDrop[page, FileNameDepth[rootDir]],
            " (", Length[live], " cells", If[write, ", hints rewritten", ""], ")"];
        Scan[Function[b,
            Scan[Print["    ", #[[1]], "  line ", b[[1]]["Line"], ": ",
                    StringTake[StringReplace[b[[1]]["Code"], "\n" -> " "], UpTo[70]], "\n        ", #[[2]]] &,
                b[[2]]]],
            bad]]
]], pages]

Print["run-doc-examples: ", reported, " issue(s) across ", Length[pages], " page(s)"]
Exit[If[reported > 0, 1, 0]]

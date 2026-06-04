#!/usr/bin/env wl
(* Build a single doc page to its .nb without rebuilding the whole docs/
   set (which would re-rasterise the LaTeX tutorials - broken headless).
   Usage: wl -f dev/build-one.wls docs/Symbols/ParseOperatorTable.md *)

Quiet @ UsingFrontEnd[CurrentValue[$FrontEnd, LightDark] = "Light"];

devDir    = DirectoryName[$InputFileName];
rootDir   = ParentDirectory[devDir];
pacletDir = FileNameJoin[{rootDir, "Parser"}];
PacletDirectoryLoad[pacletDir];
Get[FileNameJoin[{rootDir, "..", "..", "MarkdownToNotebook.wl"}]];
Needs["Wolfram`Parser`"];

subdir["Symbol"]   = {"Documentation", "English", "ReferencePages", "Symbols"};
subdir["Guide"]    = {"Documentation", "English", "Guides"};
subdir["TechNote"] = {"Documentation", "English", "Tutorials"};
subdir["Overview"] = {"Documentation", "English", "Tutorials"};

src = $ScriptCommandLine[[2]];
If[ ! AbsolutePathQ[src], src = FileNameJoin[{rootDir, src}]];

info = MarkdownToNotebook[src, "Association", "EvaluateSeparator" -> None];
tmpl = info["Template"];
base = FileBaseName[src];
dir  = FileNameJoin[Prepend[subdir[tmpl], pacletDir]];
Quiet @ CreateDirectory[dir, CreateIntermediateDirectories -> True];
out  = FileNameJoin[{dir, base <> ".nb"}];
MarkdownToNotebook[src, out, "EvaluateSeparator" -> None];
Print["built ", base, ".nb -> ", out];
Print["cells: ", Length @ Cases[Import[out, "Notebook"], _Cell, Infinity]];

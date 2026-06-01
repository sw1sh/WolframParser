#!/usr/bin/env wolframscript
(* Build the WolframParser paclet documentation from the structured
   markdown in docs/, writing each notebook into the standard paclet
   layout under Documentation/English/. Example outputs are cached
   with the built-in persistence framework. Also builds the paclet-
   repository submission notebook (ResourceDefinition). *)

(* Pin the front end appearance to Light up front: a headless session
   resolves the Automatic appearance to Dark, which would invert
   colours in any rasterised example output (the KaTeX showcase, the
   LaTeX render samples, ...) and leave the notebooks looking nothing
   like what the cloud / paclet viewer shows. *)
Quiet @ UsingFrontEnd[CurrentValue[$FrontEnd, LightDark] = "Light"]

pacletDir = DirectoryName[$InputFileName]

(* Register the dev paclet BEFORE Get-ing MarkdownToNotebook.wl - its
   own bootstrap (PacletFind["Wolfram/WolframParser"]) would otherwise
   fail and re-install the published version from the ResourceObject
   URL, shadowing our dev paclet's edits with stale code. *)
PacletDirectoryLoad[pacletDir]

Get[FileNameJoin[{pacletDir, "..", "..", "MarkdownToNotebook.wl"}]]
Needs["Wolfram`Parser`"]

subdir["Symbol"] = {"Documentation", "English", "ReferencePages", "Symbols"}
subdir["Guide"] = {"Documentation", "English", "Guides"}
subdir["TechNote"] = {"Documentation", "English", "Tutorials"}
subdir["Overview"] = {"Documentation", "English", "Tutorials"}

(* Tutorials thread state across sections (a parser built in one section is used
   in the next), so the whole notebook must evaluate in a single context.
   EvaluateSeparator -> None disables the per-heading context reset; the default
   Automatic clears those definitions at each heading, leaving later sections
   with unevaluated references. *)
buildDoc[srcFile_String] := Block[{info, tmpl, baseName, dir, out},
    info = MarkdownToNotebook[srcFile, "Association", "EvaluateSeparator" -> None];
    tmpl = info["Template"];
    baseName = FileBaseName[srcFile];
    dir = FileNameJoin[Prepend[subdir[tmpl], pacletDir]];
    Quiet @ CreateDirectory[dir, CreateIntermediateDirectories -> True];
    out = FileNameJoin[{dir, baseName <> ".nb"}];
    MarkdownToNotebook[srcFile, out, "EvaluateSeparator" -> None];
    Print["  ", FileNameTake[srcFile], " -> Documentation/English/", Last[subdir[tmpl]], "/", baseName, ".nb"]
]

Print["building WolframParser documentation"]
Scan[buildDoc, Sort @ FileNames["*.md", FileNameJoin[{pacletDir, "docs"}], Infinity]]

rd = FileNameJoin[{pacletDir, "ResourceDefinition.md"}]
If[ FileExistsQ[rd],
    MarkdownToNotebook[rd, FileNameJoin[{pacletDir, "ResourceDefinition.nb"}], "EvaluateSeparator" -> None];
    Print["  ResourceDefinition.md -> ResourceDefinition.nb"]
]

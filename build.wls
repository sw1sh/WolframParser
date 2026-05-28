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
Get[FileNameJoin[{pacletDir, "..", "..", "MarkdownToNotebook.wl"}]]

(* load the paclet so example cells resolve its symbols during evaluation *)
PacletDirectoryLoad[pacletDir]
Needs["Wolfram`Parser`"]

subdir["Symbol"] = {"Documentation", "English", "ReferencePages", "Symbols"}
subdir["Guide"] = {"Documentation", "English", "Guides"}
subdir["TechNote"] = {"Documentation", "English", "Tutorials"}
subdir["Overview"] = {"Documentation", "English", "Tutorials"}

buildDoc[srcFile_String] := Block[{info, tmpl, baseName, dir, out},
    info = MarkdownToNotebook[srcFile, "Association"];
    tmpl = info["Template"];
    baseName = FileBaseName[srcFile];
    dir = FileNameJoin[Prepend[subdir[tmpl], pacletDir]];
    Quiet @ CreateDirectory[dir, CreateIntermediateDirectories -> True];
    out = FileNameJoin[{dir, baseName <> ".nb"}];
    MarkdownToNotebook[srcFile, out];
    Print["  ", FileNameTake[srcFile], " -> Documentation/English/", Last[subdir[tmpl]], "/", baseName, ".nb"]
]

Print["building WolframParser documentation"]
Scan[buildDoc, Sort @ FileNames["*.md", FileNameJoin[{pacletDir, "docs"}], Infinity]]

rd = FileNameJoin[{pacletDir, "ResourceDefinition.md"}]
If[ FileExistsQ[rd],
    MarkdownToNotebook[rd, FileNameJoin[{pacletDir, "ResourceDefinition.nb"}]];
    Print["  ResourceDefinition.md -> ResourceDefinition.nb"]
]

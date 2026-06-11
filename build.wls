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

rootDir = DirectoryName[$InputFileName]
pacletDir = FileNameJoin[{rootDir, "Parser"}]

(* Register the dev paclet BEFORE Get-ing MarkdownToNotebook.wl - its
   own bootstrap (PacletFind["Wolfram/Parser"]) would otherwise
   fail and re-install the published version from the ResourceObject
   URL, shadowing our dev paclet's edits with stale code. *)
PacletDirectoryLoad[pacletDir]

Get[FileNameJoin[{rootDir, "..", "..", "MarkdownToNotebook.wl"}]]
Needs["Wolfram`Parser`"]

(* Load the Languages showcase (a sibling of the paclet) so its docs can build:
   its symbols span Languages`AST` / Languages`<Lang>` contexts, named in each
   page's ContextPath frontmatter, and must be in $Packages for MTN to resolve. *)
Get[FileNameJoin[{rootDir, "Languages", "init.wl"}]]

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
    (* Skip plain-markdown files with no YAML frontmatter (e.g. DOC_GUIDE.md,
       a house-style guide for authors, not a doc page). *)
    If[ ! StringStartsQ[StringTrim @ Import[srcFile, "Text"], "---"],
        Print["  (skip ", FileNameTake[srcFile], ": no frontmatter)"];
        Return[]
    ];
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
Scan[buildDoc, Sort @ FileNames["*.md", FileNameJoin[{rootDir, "docs"}], Infinity]]

rd = FileNameJoin[{rootDir, "docs", "ResourceDefinition.md"}]
If[ FileExistsQ[rd],
    MarkdownToNotebook[rd, FileNameJoin[{pacletDir, "ResourceDefinition.nb"}], "EvaluateSeparator" -> None];
    Print["  ResourceDefinition.md -> ResourceDefinition.nb"]
]

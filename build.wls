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

Get[FileNameJoin[{rootDir, "..", "..", "..", "MarkdownToNotebook.wl"}]]
Needs["Wolfram`Parser`"]
Needs["DocumentationBuild`"]
(* Needs["Wolfram`Parser`"] now also loads the bundled Languages front-ends
   (Parser/Kernel/Languages/, eager-loaded from Parser.wl), so their symbols are already
   in $Packages for MarkdownToNotebook to resolve the zoo docs. *)

(* Warm the Wolfram compiler once, up front and Quieted. The first
   FunctionCompile in a session autoloads the CompileUtilities` framework,
   whose SystemSymbolQ collides with GeneralUtilities`SystemSymbolQ and emits a
   one-time General::shdw as the framework's context joins the path. That
   shadow would otherwise fire inside the first ParserCompile example cell and
   be captured into the built notebook. Triggering the load here - outside any
   example cell - keeps the compilation examples clean, the same reason
   MarkdownToNotebook preloads the resource-framework packages before it starts
   capturing cell output. *)
Quiet @ ParserCompile[ParseLiteral["x"]]

(* Two-stage docs: MarkdownToNotebook writes AUTHORING notebooks into a source
   tree (srcDocDir), then DocumentationBuild turns them into the BUILT
   Documentation/ that ships in the paclet. The build stage is what produces the
   navigation Index + SearchIndex + SpellIndex; a raw M2N notebook has none, so an
   un-built paclet deploys as a lone landing page with no guide/symbol pages and no
   sidebar. build/ and Documentation/ are both gitignored. subdir is relative to a
   Documentation-level directory (no "Documentation" prefix), the shape
   DocumentationBuildNotebooks expects for its input and output. *)
srcDocDir  = FileNameJoin[{rootDir, "build", "DocSource"}]
destDocDir = FileNameJoin[{pacletDir, "Documentation"}]
If[DirectoryQ[srcDocDir], DeleteDirectory[srcDocDir, DeleteContents -> True]]

subdir["Symbol"] = {"English", "ReferencePages", "Symbols"}
subdir["Guide"] = {"English", "Guides"}
subdir["TechNote"] = {"English", "Tutorials"}
subdir["Overview"] = {"English", "Tutorials"}

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
    (* The Paclet resource-definition notebook (ResourceDefinition.md) is NOT a doc
       page - it is the submission artifact, built separately below with Automatic
       separator. buildDoc would otherwise emit a spurious, code-less copy under
       Documentation/English/Paclet/. *)
    If[ tmpl === "Paclet",
        Print["  (skip ", FileNameTake[srcFile], ": Paclet definition notebook, built separately)"];
        Return[]
    ];
    baseName = FileBaseName[srcFile];
    dir = FileNameJoin[Prepend[subdir[tmpl], srcDocDir]];
    Quiet @ CreateDirectory[dir, CreateIntermediateDirectories -> True];
    out = FileNameJoin[{dir, baseName <> ".nb"}];
    MarkdownToNotebook[srcFile, out, "EvaluateSeparator" -> None];
    (* Content-completeness guard: a page whose source carries ```wl code blocks
       but whose built notebook has NO Input/Code cells silently lost its examples
       - the classic case is a Template: Guide with runnable code, which the guide
       builder drops (the code belongs in a Template: TechNote tutorial). This is
       not a build error, so a page-count / error scan misses it; flag it loudly. *)
    If[ StringContainsQ[Import[srcFile, "Text"], "```wl"] &&
            FreeQ[Get[out], Cell[_, "Input" | "Code", ___]],
        Print["  !! WARNING: ", FileNameTake[srcFile], " (", tmpl,
              ") has ```wl code blocks but the built .nb has NO Input cells - the ",
              "template dropped them; a runnable page must be a TechNote, not a Guide."]
    ];
    Print["  ", FileNameTake[srcFile], " -> DocSource/English/", Last[subdir[tmpl]], "/", baseName, ".nb"]
]

Print["building WolframParser documentation (authoring notebooks)"]
Scan[buildDoc, Sort @ FileNames["*.md", FileNameJoin[{rootDir, "docs"}], Infinity]]

(* Stage 2: turn the authoring notebooks in srcDocDir into the paclet's built
   Documentation/. DocumentationBuildNotebooks fills in navigation / related
   links and writes English/Index + English/SearchIndex + English/SpellIndex -
   without this the deployed paclet renders only its landing page (no guide /
   symbol pages, no sidebar). "LinkBase" namespaces the paclet:Wolfram/Parser/...
   doc URIs so intra-paclet See-Also links resolve. Serial whole-tree build (the
   robust path); the "See Also link to unknown URI removed" warnings are benign
   (links to pages genuinely absent from the set). *)
Print["running DocumentationBuild: ", srcDocDir, " -> ", destDocDir]
If[DirectoryQ[destDocDir], DeleteDirectory[destDocDir, DeleteContents -> True]]
UsingFrontEnd @ DocumentationBuild`DocumentationBuildNotebooks[srcDocDir, destDocDir, "LinkBase" -> "Wolfram/Parser"]
Print["  built ", Length @ FileNames["*.nb", FileNameJoin[{destDocDir, "English"}], Infinity],
      " documentation notebooks (+ Index / SearchIndex / SpellIndex)"]

(* The ResourceDefinition is a showcase of INDEPENDENT examples (unlike the
   tutorials, which deliberately thread one grammar across sections), so build
   it with the default delimiter-respecting evaluation instead of overriding to
   None: EvaluateSeparator -> Automatic resets the example context at each
   heading and each `---` rule, so no example can accidentally depend on or
   pollute another. (None is the setting only the state-threading tutorials
   actually need; it was over-applied here.) The one multi-cell example (parens)
   is self-contained within a single cell, so the reset breaks nothing. *)
rd = FileNameJoin[{rootDir, "docs", "ResourceDefinition.md"}]
If[ FileExistsQ[rd],
    MarkdownToNotebook[rd, FileNameJoin[{pacletDir, "ResourceDefinition.nb"}], "EvaluateSeparator" -> Automatic];
    Print["  ResourceDefinition.md -> ResourceDefinition.nb"]
]

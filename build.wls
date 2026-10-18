#!/usr/bin/env wolframscript
(* Builds the Wolfram/Parser documentation with PacletPage's BuildPacletDocumentation: every page
   under docs/ becomes an authoring notebook under Parser/Documentation/English, and
   docs/ResourceDefinition.md becomes Parser/ResourceDefinition.nb, the definition the resource
   is deployed and submitted from. A page converts again only when its source, the paclet's code
   or the converter changed; a deploy builds the finished pages from these.

       wl -f build.wls               (or --no-cache: every example evaluated afresh)

   release.wls builds the same way before it publishes. *)

$ProgressReporting = False

Get[FileNameJoin[{DirectoryName[$InputFileName], "pacletpage.wl"}]]

result = BuildPacletDocumentation[$pacletDirectory, Sequence @@ $documentationOptions,
    "UseCache" -> ! MemberQ[$ScriptCommandLine, "--no-cache"],
    "Monitor" -> True
]
If[ ! AssociationQ[result], Exit[1]]
Print[Length[result["Notebooks"]], " pages", If[StringQ[result["Definition"]], " and the definition notebook", ""],
    ": ", Length[result["Converted"]], " converted, ", Length[result["Cached"]], " from the cache, ",
    Length[result["Evaluated"]], " with their examples evaluated afresh"]
If[ result["Failed"] =!= {}, Print["failed: ", result["Failed"]]; Exit[1]]

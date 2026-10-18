#!/usr/bin/env wolframscript
(* Submits Wolfram/Parser to the Wolfram Paclet Repository with PacletPage's SubmitPacletResource:
   the definition notebook's own check, a fresh PacletBuild checked to hold every documentation
   page and to load in a fresh kernel, then the submission under the version in PacletInfo.wl,
   which has to be newer than the repository's. The publisher, Wolfram, is nikm@wolfram.com's,
   the account it submits as. Build the documentation first, with build.wls or release.wls.

       wl -f submit.wls              (or --dry-run: everything but the submission) *)

$ProgressReporting = False

Get[FileNameJoin[{DirectoryName[$InputFileName], "pacletpage.wl"}]]

result = SubmitPacletResource[$pacletDirectory,
    "Account" -> "nikm@wolfram.com",
    "DryRun" -> MemberQ[$ScriptCommandLine, "--dry-run"]
]
If[ ! AssociationQ[result], Exit[1]]
Print[result["Name"], " ", result["Version"], ": ", If[TrueQ[result["Submitted"]], "submitted", "not submitted (dry run)"]]
Print["archive: ", result["Archive"], ", ", result["Pages"], " documentation pages"]
If[ KeyExistsQ[result, "Result"], Print["result: ", result["Result"]]]

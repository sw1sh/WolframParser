#!/usr/bin/env wolframscript
(* Releases Wolfram/Parser with PacletPage's PublishPacletPage, in one kernel and so one cloud
   account: builds the documentation as build.wls does, deploys the paclet resource, publishes the
   documentation site around it with the authoring notebooks as its sources, and checks the site.
   A release built from a commit alone is tagged v<version> on it, and the tag pushed.

       wl -f release.wls             (or --dry-run: the build and the resource, not deployed)

   The account is PACLETPAGE_ACCOUNT, by default the Wolfram Institute's. submit.wls submits the
   paclet to the Paclet Repository. *)

$ProgressReporting = False

Get[FileNameJoin[{DirectoryName[$InputFileName], "pacletpage.wl"}]]

account = Replace[Environment["PACLETPAGE_ACCOUNT"], Except[_String?(StringLength[#] > 0 &)] -> "wolframinstitute@wolframinstitute.org"]
result = PublishPacletPage[$pacletDirectory, "WolframParser",
    "Account" -> account,
    "DryRun" -> MemberQ[$ScriptCommandLine, "--dry-run"],
    "Monitor" -> True,
    "BuildOptions" -> $documentationOptions,
    "SiteOptions" -> {"FeedbackOptions" -> {"Domains" -> {"wolframinstitute.org", "wolfram.com"}}}
]
If[ ! AssociationQ[result], Exit[1]]
Print["documentation: ", Length[result["Build"]["Notebooks"]], " pages, failed ", result["Build"]["Failed"]]
Print["resource: ", result["Resource"]["Resource"], If[result["Resource"]["Deployed"], "", " (dry run)"]]
If[ AssociationQ[result["Site"]], Print["site: ", result["Site"]["Site"]]]
(* a release tagged v<version> on the commit it was built from, when it was built from a commit
   alone, without changes beside it *)
tagRelease[resource_Association] := With[{commit = resource["Commit"], tag = "v" <> resource["Version"]},
    If[ TrueQ[resource["Deployed"]] && StringQ[commit] && StringMatchQ[commit, RegularExpression["[0-9a-f]{40}"]],
        RunProcess[{"git", "-C", $repositoryDirectory, "tag", "-a", tag, commit, "-m", "Wolfram/Parser " <> resource["Version"]}];
        Print["tag: ", tag, If[MatchQ[RunProcess[{"git", "-C", $repositoryDirectory, "push", "origin", tag}], KeyValuePattern["ExitCode" -> 0]], " pushed", " not pushed"]],
        Print["tag: none, the release was not built from a commit alone"]
    ]
]
If[ AssociationQ[result["Check"]],
    Scan[Print["check failed: ", #["Check"], ": ", #["Detail"]] &, Select[Normal[result["Check"]["Checks"]], ! TrueQ[#["OK"]] &]];
    Print["check: ", If[TrueQ[result["Check"]["OK"]], "everything is reachable", "problems found"]];
    If[TrueQ[result["Check"]["OK"]], tagRelease[result["Resource"]]];
    Exit[If[TrueQ[result["Check"]["OK"]], 0, 1]]
]

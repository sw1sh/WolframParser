#!/usr/bin/env wolframscript
(* Submit the Wolfram/Parser paclet to the Wolfram Paclet Repository.

   The submission artifact is Parser/ResourceDefinition.nb, generated from
   docs/ResourceDefinition.md by build.wls - which also builds the paclet's
   Documentation/English notebooks that ship inside the paclet. Edit the
   markdown and rebuild, never the notebook, then run (either runtime works
   identically - there is no front end under -f in either, which is why the
   headless ScrapeResource -> ResourceSubmit path below replaces the old
   SubmitRepository call and its interactive version dialog):

       wl -f submit.wls            (or:  wolframscript -f submit.wls)

   Must be run from an account that owns the paclet's PublisherID - the "Wolfram"
   publisher, i.e. nikm@wolfram.com. A "version already exists" / "update already
   in process" error means a prior submit of this version is still being processed
   server-side - bump PacletInfo`Version and rebuild, or wait for it to publish.
*)

repoDir   = DirectoryName[$InputFileName]
pacletDir = FileNameJoin[{repoDir, "Parser"}]
nbFile    = FileNameJoin[{pacletDir, "ResourceDefinition.nb"}]

If[ ! FileExistsQ[nbFile],
    Print["FATAL: ", nbFile, " does not exist - run build.wls first."];
    Exit[1]
]

(* Register the working copy so the Check and the submission resolve
   Wolfram/Parser to this directory - with the Documentation/ build.wls
   produced - rather than any stale installed copy. *)
PacletDirectoryLoad[pacletDir]
Needs["DefinitionNotebookClient`"]
Needs["ResourceSystemClient`"]
(* PacletTools MUST be loaded before ScrapeResource: the Paclet scrape computes the
   relative paths of the Documentation extension via PacletTools`PacletExtensionFiles,
   and if that context is not loaded the call stays unevaluated -> FileNameSplit::fstr
   -> a $Failed lands in the scraped file listing, which the repository rejects
   (ResourceSubmit::apierr "disallowed symbols {System`$Failed}"). *)
Needs["PacletTools`"]

paclet    = PacletObject[File[pacletDir]]
version   = paclet["Version"]
publisher = paclet["PublisherID"]

If[ ! TrueQ[$CloudConnected], CloudConnect[] ]
If[ ! TrueQ[$CloudConnected],
    Print["FATAL: not cloud connected - CloudConnect[] with your Wolfram ID first."];
    Exit[1]
]
(* Set the active publisher explicitly. ResourceSubmit validates PublisherID
   against $PublisherID; without this it defaults to None and rejects the
   "Wolfram" option with ResourceSubmit::invparam. *)
$PublisherID = publisher

(* The connected account must own the publisher, or the repository answers "not authorized to
   use the given PublisherID" - after the whole build. A machine whose remembered login was
   overwritten by a CI script connects as the CI account without asking, so check up front. *)
owner = "nikm@wolfram.com"
If[ $WolframID =!= owner,
    Print["FATAL: connected as ", $WolframID, " but publisher ", publisher, " belongs to ", owner,
          " - CloudConnect[\"", owner, "\"] in a kernel first (RememberMe), then rerun."];
    Exit[1]
]
Print["submitting ", paclet["Name"], " ", version, " (publisher ", publisher,
      ", $PublisherID=", $PublisherID, ") as ", $WolframID]

(* Pre-submission Check first: the repository rejects a submission that still has
   Error-level issues, so bailing here is strictly cheaper. Warnings / Suggestions
   do not block - the remaining `Arguments/Module` Warning is a known CodeInspector
   false positive on the FunctionCompile code-gen helper (a held Module whose var
   list is spliced in at runtime). *)
check = UsingFrontEnd @ Block[{nb, r},
    nb = NotebookOpen[nbFile, Visible -> False];
    r  = DefinitionNotebookClient`CheckDefinitionNotebook[nb];
    NotebookClose[nb];
    r
]
issues = Normal[check]
Scan[Print["  [", #Level, "] ", #Tag] &, issues]
(* "NoPacletInfoFileCell" is expected here and NOT fatal: it fires because this
   markdown-built definition notebook has no file-manager cell listing PacletInfo.wl.
   The paclet (Kernel + built Documentation + Assets) is instead attached from the
   PacletDirectoryLoad'd directory that ScrapeResource reads below - which is why the
   scrape+submit path uploads the full paclet regardless. Bail only on OTHER errors. *)
fatal = Select[issues, #Level === "Error" && #Tag =!= "NoPacletInfoFileCell" &]
If[ fatal =!= {},
    Print["FATAL: the definition notebook has blocking errors; fix them before submitting."];
    Exit[1]
]

(* SubmitRepository[nb] cannot be scripted: it pops an interactive DialogInput
   version picker that has no front end under `wl -f` (DialogInput::ninit). The
   headless equivalent is to scrape the notebook into a ResourceObject and
   ResourceSubmit it directly with the version/publisher taken from PacletInfo -
   all inside UsingFrontEnd, which ResourceSubmit needs for the example notebook
   (else ResourceSubmit::enbdf). ScrapeResource emits harmless KeyDrop::invrl
   noise on an internal HintData lookup; the returned ResourceObject is valid. *)
(* Build the stage the scrape packs. ScrapeResource submits whatever Wolfram__Parser* it
   finds under Parser/build/ - the FULL paclet as PacletTools`PacletBuild makes it (source
   plus DocumentationBuild over the authoring notebooks; the definition notebook's Build
   button does the same). Deleting the stage was the earlier fix for a STALE stage being
   published under each new version, but it left the scrape packing the raw source, whose
   unbuilt documentation the repository's server-side step cannot digest (502 from
   SubmitResource, and a version record the paclet site never serves). Rebuilding the
   stage every time is the fix for both. *)
Needs["PacletTools`"]
buildDir = FileNameJoin[{pacletDir, "build"}]
Scan[
    If[DirectoryQ[#], DeleteDirectory[#, DeleteContents -> True], DeleteFile[#]] &,
    FileNames["Wolfram__Parser*", buildDir]
]
built = PacletTools`PacletBuild[pacletDir, buildDir]
If[ ! MatchQ[built, _Success],
    Print["FATAL: PacletBuild failed: ", built];
    Exit[1]
]
Print["built: ", FileNameTake[built["PacletArchive"]], " (",
      Round[FileByteCount[built["PacletArchive"]]/2^20, 0.1], " MB)"]

(* Scrape, check and submit inside ONE Block with the notebook still open: the scraped
   record is only fully resolvable while its notebook is open ("IncludeNotebookData" reads
   from it), so closing early puts $Failed into the request and the repository rejects it
   with "disallowed symbols". The artifact check therefore happens here, mid-block. *)
result = UsingFrontEnd @ Block[{nb, rtype, res, ro, pf},
    nb    = NotebookOpen[nbFile, Visible -> False];
    rtype = DefinitionNotebookClient`NotebookResourceType[nb];
    res   = Quiet[
        DefinitionNotebookClient`ScrapeResource[rtype, nb, "IncludeNotebookData" -> True],
        {KeyDrop::invrl}];
    (* The artifact the scrape produced must be the version being submitted. Publishing a
       mismatched pair is silent - the submission succeeds and the resource page shows the
       new version - and only surfaces later as a paclet nobody can install. *)
    pf = Replace[Lookup[First[res], "PacletFile", None], File[f_] :> f];
    Print["artifact: ", If[StringQ[pf], FileNameTake[pf], "(none)"]];
    If[ StringQ[pf] && ! StringContainsQ[FileNameTake[pf], version],
        NotebookClose[nb];
        Print["FATAL: artifact does not match PacletInfo version ", version, " - not submitting."];
        Exit[1]
    ];
    ro = ResourceObject[res];
    r  = ResourceSubmit[ro, "Version" -> version, PublisherID -> publisher];
    NotebookClose[nb];
    r
]

Print["=== RESULT ==="]
Print["head : ", Head[result]]
Print["value: ", ToString[Short[result, 25], InputForm]]
(* A successful ResourceSubmit returns Success["ResourceSubmission", <|...|>]
   (with "Message" -> "Your paclet resource is being published"), NOT a
   ResourceObject - match both so a real publish is not misreported as failure. *)
Which[
    MatchQ[result, _Success],
        Print["SUBMITTED - ", Lookup[Last[result], "Message", "submitted"], ":"];
        KeyValueMap[Print["  ", #1, ": ", #2] &, KeyDrop[Last[result], "Message"]],
    MatchQ[result, _ResourceObject],
        Print["submitted ", result["Name"], " ", result["Version"], ":"];
        Scan[Print["  ", #, ": ", ToString[Short[Quiet[result[#]], 6], InputForm]] &,
            {"UUID", "Version", "SubmissionID", "DocumentationLink"}],
    True,
        Print["SUBMISSION DID NOT SUCCEED (see value above)."];
        Exit[1]
]

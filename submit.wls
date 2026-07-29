#!/usr/bin/env wolframscript
(* Submit the Wolfram/Parser paclet to the Wolfram Paclet Repository.

   The submission artifact is Parser/ResourceDefinition.nb, generated from
   docs/ResourceDefinition.md by build.wls - which also builds the paclet's
   Documentation/English notebooks that ship inside the paclet. Edit the
   markdown and rebuild, never the notebook, then run:

       wl -f submit.wls            (or:  wolframscript -f submit.wls)
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

If[ ! TrueQ[$CloudConnected], CloudConnect[] ]
If[ ! TrueQ[$CloudConnected],
    Print["FATAL: not cloud connected - CloudConnect[] with your Wolfram ID first."];
    Exit[1]
]
Print["submitting Wolfram/Parser as ", $WolframID]

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
If[ MemberQ[Lookup[issues, "Level", Nothing], "Error"],
    Print["FATAL: the definition notebook has errors; fix them before submitting."];
    Exit[1]
]

result = UsingFrontEnd @ Block[{nb, r},
    nb = NotebookOpen[nbFile, Visible -> False];
    r  = DefinitionNotebookClient`SubmitRepository[nb];
    NotebookClose[nb];
    r
]
submission = FirstCase[result, _Success, Missing["NotFound"], Infinity]

If[ MatchQ[submission, _Success],
    Print["submitted:"];
    KeyValueMap[Print["  ", #1, ": ", #2] &, KeyDrop[Last[submission], "Message"]],
    Print["SUBMISSION DID NOT SUCCEED:"];
    Print[result];
    Exit[1]
]

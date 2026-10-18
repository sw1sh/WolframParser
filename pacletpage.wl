(* ::Package:: *)

(* What build.wls, release.wls and submit.wls share: PacletPage, from the checkout beside this
   one in AISkills or else from its published resource; the paclet's directory; and how its
   documentation is built. *)

$repositoryDirectory = DirectoryName[$InputFileName];
$pacletDirectory = FileNameJoin[{$repositoryDirectory, "Parser"}];

With[{checkout = FileNameJoin[{ParentDirectory[$repositoryDirectory], "PacletPage"}]},
    If[ FileExistsQ[FileNameJoin[{checkout, "PacletInfo.wl"}]],
        PacletDirectoryLoad[checkout],
        PacletInstall[ResourceObject["https://www.wolframcloud.com/obj/wolframinstitute/DeployedResources/Paclet/WolframInstitute/PacletPage"]]
    ]
];
Needs["WolframInstitute`PacletPage`"];

(* the pages are the markdown under docs/, and the definition is docs/ResourceDefinition.md. A
   page's sections share one context, so a grammar built in one section is used in the next; the
   definition's examples each run in a clean one. Pages convert on parallel kernels, as many as
   the processors and the memory allow. *)
$documentationOptions = {
    "Source" -> FileNameJoin[{$repositoryDirectory, "docs"}],
    "EvaluateSeparator" -> <|"Symbol" -> None, "Guide" -> None|>,
    "Parallel" -> True
};

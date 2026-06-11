#!/usr/bin/env wolframscript
(* Runner for Languages/Tests/*.wlt - loads the parser zoo, runs each suite,
   prints a per-file + overall summary, exits 0 / 1. Headless-safe like the
   paclet's own runner: $ProgressReporting=False (else TestReport's live panel
   never finalizes under `wl -f`) and each file in its own TimeConstrained. *)

$ProgressReporting = False;

dir = DirectoryName[$InputFileName];
PacletDirectoryLoad[FileNameJoin[{ParentDirectory[dir], "Parser"}]];
Get[FileNameJoin[{dir, "init.wl"}]];

files = Sort @ FileNames["*.wlt", FileNameJoin[{dir, "Tests"}]];
perFileTimeout = 120;

totalPass = 0;
totalFail = 0;

Scan[
    Function[f,
        Module[{rep, p, fl},
            rep = TimeConstrained[TestReport[f], perFileTimeout, $TimedOut];
            If[rep === $TimedOut,
                totalFail += 1;
                Print["  ", FileBaseName[f], ": *** TIMED OUT (>", perFileTimeout, "s) ***"]
                ,
                p = Length @ rep["TestsSucceededIndices"];
                fl = Length @ rep["TestsFailedIndices"];
                totalPass += p;
                totalFail += fl;
                Print["  ", FileBaseName[f], ": ", p, " / ", p + fl, If[fl > 0, "  (FAIL)", ""]];
                If[fl > 0,
                    Scan[
                        Function[idx,
                            Block[{r = rep["TestResults"][idx]},
                                Print["    FAILED: ", r["TestID"]];
                                Print["      expected: ", r["ExpectedOutput"]];
                                Print["      actual:   ", r["ActualOutput"]]
                            ]
                        ],
                        rep["TestsFailedIndices"]
                    ]
                ]
            ]
        ]
    ],
    files
];

Print[""];
Print["==== summary ====  ", totalPass, " / ", totalPass + totalFail, " pass"];
If[totalFail > 0, Exit[1], Exit[0]]

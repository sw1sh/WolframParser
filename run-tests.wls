#!/usr/bin/env wolframscript
(* Runner for Tests/*.wlt - loads the paclet, runs each suite, prints a
   per-file + overall summary, exits 0 / 1 based on outcome. *)

(* Two headless-only hazards this guards against:
   1. TestReport's live progress panel never finalizes under a headless
      `wl -f` run - it re-prints "Evaluating tests (N) / Elapsed time" forever.
      $ProgressReporting=False makes the run silent until the summary.
   2. A single aggregate TestReport over ALL files WEDGES (0% CPU, killed at
      ~11 min) when one test calls Abort[] - the Stress "500 unclosed braces"
      case does. Running each file in its OWN TimeConstrained[TestReport[...]]
      isolates that abort so the rest of the suite still completes. *)
$ProgressReporting = False

dir = DirectoryName[$InputFileName]
PacletDirectoryLoad[dir]
Needs["Wolfram`Parser`"]

files = Sort @ FileNames["*.wlt", FileNameJoin[{dir, "Tests"}]]
perFileTimeout = 300

totalPass = 0
totalFail = 0

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
]

Print[""]
Print["==== summary ====  ", totalPass, " / ", totalPass + totalFail, " pass"]
If[totalFail > 0, Exit[1], Exit[0]]

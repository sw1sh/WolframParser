#!/usr/bin/env wolframscript
(* Runner for tests.wlt - loads the paclet, runs TestReport on the
   .wlt file, prints a summary, exits 0 / 1 based on outcome. *)

dir = DirectoryName[$InputFileName]
PacletDirectoryLoad[dir]
Needs["Wolfram`Parser`"]

report = TestReport @ FileNames["*.wlt", FileNameJoin[{dir, "Tests"}]]

passed = Length @ report["TestsSucceededIndices"]
failed = Length @ report["TestsFailedIndices"]
total = passed + failed

If[ failed > 0,
    Print[""];
    Print["FAILED:"];
    Scan[
        Function[idx,
            Block[{r = report["TestResults"][idx]},
                Print["  ", r["TestID"]];
                Print["    expected: ", r["ExpectedOutput"]];
                Print["    actual:   ", r["ActualOutput"]]
            ]
        ],
        report["TestsFailedIndices"]
    ]
]

Print[""]
Print["==== summary ====  ", passed, " / ", total, " pass"]
If[failed > 0, Exit[1], Exit[0]]

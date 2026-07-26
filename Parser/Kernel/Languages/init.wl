(* ::Package:: *)

(* :Title: init.wl - load the parser-zoo language front-ends *)
(* :Summary:
    The standard AST vocabulary (LeafNode / ASTAlgebra / ToCodeParser /
    RecCell / SpannedToken / ...) now ships with the Wolfram/Parser paclet
    itself, in the Wolfram`Parser` context. This file only loads the example
    language front-ends, each in its own Wolfram`Parser`Languages` subcontext.
    The paclet must already be available (PacletDirectoryLoad the sibling
    Parser/ directory, or install it) before Get-ing this.

      PacletDirectoryLoad["/path/to/WolframParser/Parser"];
      Get["/path/to/WolframParser/Languages/init.wl"];
      CalculatorEval["1 + 2*3"]   (* 7 *)
*)

Needs["Wolfram`Parser`"];

With[{dir = DirectoryName[$InputFileName]},
    Scan[
        Get[FileNameJoin[{dir, # <> ".wl"}]] &,
        {"Calculator", "JSON", "Lisp", "Lambda", "Brainfuck", "OpenQASM"}]
];

Scan[Needs, {"Wolfram`Parser`Languages`Calculator`", "Wolfram`Parser`Languages`JSON`",
    "Wolfram`Parser`Languages`Lisp`", "Wolfram`Parser`Languages`Lambda`",
    "Wolfram`Parser`Languages`Brainfuck`", "Wolfram`Parser`Languages`OpenQASM`"}];

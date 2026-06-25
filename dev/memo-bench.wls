#!/usr/bin/env wl
(* Does packrat memoisation make the UN-overridden THF grammar linear, the
   way the Pratt override does? Compare three parsers on the same nested
   application chain g[n] = ( g[n-1] @ p ):
     1. current ordered-choice THF, no memo   (the blow-up)
     2. same grammar, with $parseMemo on       (packrat)
     3. the shipped Pratt override             (reference) *)

$ProgressReporting = False;
dir = ParentDirectory @ DirectoryName[$InputFileName];
PacletDirectoryLoad[FileNameJoin[{dir, "Parser"}]];
Needs["Wolfram`Parser`"];
P = "Wolfram`Parser`Private`";

ToExpression[P <> "ensureTptpParser"][];
ovThf = ToExpression[P <> "$tptpParsers"]["thf_formula"];        (* Pratt override *)
bnf   = Import[ToExpression[P <> "$tptpBnfURL"], "Text"];
curThf = EBNFParse[bnf]["thf_formula"];                          (* no override *)

memoParse[pc_, s_] := Block[{Wolfram`Parser`Private`$parseMemo = <||>}, Parse[pc, s]];

(* soundness: memo result == no-memo result on a case the plain grammar can do *)
small = "( ( a @ b ) @ c )";
Print["soundness (memo == plain): ",
   memoParse[curThf, small] === Parse[curThf, small]];

g[0] = "p"; g[k_] := g[k] = "(" <> g[k - 1] <> "@p)";
budget = 8;
Print[""];
Print["depth\tbytes\tno-memo\t\tpackrat\t\tPratt override"];
wall = False;
Do[
   Module[{src = g[k], ct, cr, mt, ot},
      ot = First @ AbsoluteTiming[Parse[ovThf, src]];
      mt = First @ AbsoluteTiming[memoParse[curThf, src]];
      If[! wall,
         {ct, cr} = AbsoluteTiming[TimeConstrained[Parse[curThf, src], budget, $TO]];
         If[cr === $TO, wall = True],
         ct = $TO];
      Print[k, "\t", StringLength[src], "\t",
         If[NumberQ[ct], N@Round[ct, 0.0001], ">" <> ToString[budget] <> " TO"], "\t\t",
         N@Round[mt, 0.000001], "\t\t", N@Round[ot, 0.000001]];
   ],
   {k, {3, 5, 7, 9, 12, 30, 80, 200}}
];

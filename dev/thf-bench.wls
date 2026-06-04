#!/usr/bin/env wl
(* (a) Verify + bench the ParseOperatorTable override of the THF connective
   grammar (wired into TPTP.wl) against the un-overridden grammar, both from
   the real TPTP BNF. *)

$ProgressReporting = False;
dir = ParentDirectory @ DirectoryName[$InputFileName];
PacletDirectoryLoad[FileNameJoin[{dir, "Parser"}]];
Needs["Wolfram`Parser`"];
P = "Wolfram`Parser`Private`";

(* the live, shipped override parser (ws-aware, with THF actions) *)
ToExpression[P <> "ensureTptpParser"][];
ovThf = ToExpression[P <> "$tptpParsers"]["thf_formula"];
Print["live override built."];

Print[""];
Print["== correctness: shipped override on THF formula bodies =="];
chk[s_] := Print["  ", s, "   =>   ", ParsePartial[ovThf, s][[1]]];
chk["p & q"];
chk["p | q & r"];
chk["p => q => r"];
chk["~ p & q"];
chk["( p | q ) & r"];
chk["f @ a @ b"];
chk["p <=> q"];
chk["a = b & p"];

(* comparison recogniser: same BNF, no override *)
bnf = Import[ToExpression[P <> "$tptpBnfURL"], "Text"];
curThf = EBNFParse[bnf]["thf_formula"];

Print[""];
Print["== timing: nested application chain  g[n] = ( g[n-1] @ p ) =="];
g[0] = "p"; g[k_] := g[k] = "(" <> g[k - 1] <> "@p)";
budget = 8;
Print["depth\tbytes\tcurrent (ordered-choice)\toverride (Pratt)"];
wall = False;
Do[
   Module[{src = g[k], ct, ot, cr},
      ot = First @ AbsoluteTiming[Parse[ovThf, src]];
      If[! wall,
         {ct, cr} = AbsoluteTiming[TimeConstrained[Parse[curThf, src], budget, $TO]];
         If[cr === $TO, wall = True],
         ct = $TO];
      Print[k, "\t", StringLength[src], "\t",
         If[NumberQ[ct], N@Round[ct, 0.0001], ">" <> ToString[budget] <> " TO"],
         "\t\t", N@Round[ot, 0.000001]];
   ],
   {k, {3, 5, 7, 9, 12, 30, 80}}
];

Print[""];
Print["== end-to-end: TPTPImport on thf() clauses =="];
Print["  ", TPTPImport["thf(c1, axiom, ( a & b ) => c)."]];
Print["  ", TPTPImport["thf(c2, axiom, p | q | r | s)."]];

#!/usr/bin/env wl
(* Prototype: reproduce the THF alternative-explosion under the current
   PEG/ParseRecursive engine, then show a Pratt binding-power climber stays
   linear on the identical inputs.

   The mini-language is the THF kernel that fumbles:
       unitary ::= '(' logic ')' | atom
       logic   ::= binary_tuple | unitary
       binary_tuple ::= or | and | apply        (tried in THIS order)
       or      ::= unitary '|' unitary
       and     ::= unitary '&' unitary
       apply   ::= unitary '@' unitary
   Every binary alternative shares the leading <unitary>, and <unitary> can
   be a parenthesised <logic> - so with no memo the leading operand is
   re-parsed once per alternative, recursively => O(3^depth).

   Test inputs (left-nested, connective is always the LAST-tried alt '@'):
       f[0] = "a"
       f[n] = "(" <> f[n-1] <> "@b)"
*)

$ProgressReporting = False;

dir = ParentDirectory @ DirectoryName[$InputFileName];
PacletDirectoryLoad[FileNameJoin[{dir, "Parser"}]];
Needs["Wolfram`Parser`"];

(* ---- grammar built from the current combinators ---- *)
ClearAll[atom, unitary, logic, binTuple, orF, andF, applyF];
atom     = ParseChoice[ParseLiteral["a"], ParseLiteral["b"]];
unitary  = ParseChoice[
              ParseBetween[ParseLiteral["("], ParseRecursive[logic], ParseLiteral[")"]],
              atom];
orF      = ParseSequence[ParseRecursive[unitary], ParseLiteral["|"], ParseRecursive[unitary]];
andF     = ParseSequence[ParseRecursive[unitary], ParseLiteral["&"], ParseRecursive[unitary]];
applyF   = ParseSequence[ParseRecursive[unitary], ParseLiteral["@"], ParseRecursive[unitary]];
binTuple = ParseChoice[orF, andF, applyF];
logic    = ParseChoice[binTuple, ParseRecursive[unitary]];

(* ---- input generator ---- *)
f[0] = "a";
f[n_] := f[n] = "(" <> f[n - 1] <> "@b)";

(* ---- Pratt climber on the same string ---- *)
lbp["@"] = 30; lbp["|"] = 10; lbp["&"] = 20; lbp[_] = 0;
prattParse[input_String] := Module[{toks = Characters[input], pos = 1, peek, adv, nud, expr},
   peek[] := If[pos <= Length[toks], toks[[pos]], EndOfString];
   adv[]  := pos++;
   nud[] := With[{t = peek[]},
      Which[
         t === "(", adv[]; With[{e = expr[0]}, If[peek[] =!= ")", Throw["no )"]]; adv[]; e],
         StringMatchQ[t, "a" | "b"], adv[]; t,
         True, Throw["bad nud: " <> ToString[t]]
      ]];
   expr[rbp_] := Module[{left = nud[], op},
      While[lbp[peek[]] > rbp,
         op = peek[]; adv[];
         left = op[left, expr[lbp[op]]]   (* left-assoc: recurse at lbp *)
      ];
      left];
   Catch[With[{r = expr[0]}, If[pos <= Length[toks], "leftover", r]]]
];

(* ---- bench ---- *)
budget = 15; (* seconds per combinator parse before we call it a timeout *)
Print[StringRiffle[{"depth", "bytes", "PEG (s)", "Pratt (s)", "speedup"}, "\t"]];
Print[StringRepeat["-", 56]];

hitWall = False;
Do[
   Module[{src = f[n], pegT, prT, pegRes, prRes, ratio},
      {prT, prRes} = AbsoluteTiming[prattParse[src]];
      If[! hitWall,
         {pegT, pegRes} = AbsoluteTiming[TimeConstrained[Parse[logic, src], budget, $TO]];
         If[pegRes === $TO, hitWall = True]
         ,
         pegT = $TO; pegRes = $TO
      ];
      ratio = If[NumberQ[pegT] && prT > 0, ToString@Round[pegT/prT], "-"];
      Print[StringRiffle[{
         ToString[n],
         ToString @ StringLength[src],
         If[pegRes === $TO, ">" <> ToString[budget] <> " TO", ToString@N[Round[pegT, 0.0001]]],
         ToString@N[Round[prT, 0.000001]],
         If[pegRes === $TO, "-", ratio <> "x"]
      }, "\t"]];
   ],
   {n, 1, 13}
];

Print[""];
Print["sample input f[4] = ", f[4]];
Print["Pratt result f[4] = ", prattParse[f[4]]];

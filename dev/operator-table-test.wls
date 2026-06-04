#!/usr/bin/env wl
(* Verify ParseOperatorTable: correctness across fixities + linear timing on
   the same left-nested inputs that blew up the PEG/ParseRecursive grammar. *)

$ProgressReporting = False;
dir = ParentDirectory @ DirectoryName[$InputFileName];
PacletDirectoryLoad[FileNameJoin[{dir, "Parser"}]];
Needs["Wolfram`Parser`"];

(* operator parsers: each RETURNS its combining function (ChainLeft convention) *)
op[lit_, head_] := ParseAction[ParseLiteral[lit], (head &)];

ClearAll[atom, unit, expr];
(* map the matched letter to a Symbol so result trees have symbol leaves *)
atom = ParseAction[
   ParseChoice @@ (ParseLiteral /@ {"a", "b", "c", "d"}),
   Symbol];
unit = ParseChoice[
   ParseBetween[ParseLiteral["("], ParseRecursive[expr], ParseLiteral[")"]],
   atom];
(* tightest-first: ? (postfix) , @ , ~ (prefix) , & , | , => (right) *)
expr = ParseOperatorTable[unit, {
   {{"Postfix", op["?", q]}},
   {{"InfixL",  op["@", app]}},
   {{"Prefix",  op["~", not]}},
   {{"InfixL",  op["&", and]}},
   {{"InfixL",  op["|", orr]}},
   {{"InfixR",  op["=>", imp]}}
}];

check[in_, want_] := Module[{got = Parse[expr, in]},
   Print[If[got === want, "  ok   ", "  FAIL "], in, "  =>  ", got,
         If[got === want, "", "   (wanted " <> ToString[want] <> ")"]]];

Print["== correctness =="];
check["a@b@c",      app[app[a, b], c]];          (* left assoc  *)
check["a=>b=>c",    imp[a, imp[b, c]]];          (* right assoc *)
check["a@b&c",      and[app[a, b], c]];          (* @ tighter than & *)
check["~a&b",       and[not[a], b]];             (* prefix tighter than & *)
check["~a=>b",      imp[not[a], b]];
check["a?@b",       app[q[a], b]];               (* postfix tightest *)
check["a&b|c=>d",   imp[orr[and[a, b], c], d]];  (* full precedence ladder *)
check["(a|b)&c",    and[orr[a, b], c]];          (* parens override *)

Print[""];
Print["== timing: left-nested f[n] = ( f[n-1] @ b ), the PEG blow-up input =="];
f[0] = "a"; f[k_] := f[k] = "(" <> f[k - 1] <> "@b)";
Print["depth\tbytes\tParseOperatorTable (s)"];
Do[
   Module[{src = f[k], t, r},
      {t, r} = AbsoluteTiming[Parse[expr, src]];
      Print[k, "\t", StringLength[src], "\t", N[Round[t, 0.000001]]];
   ],
   {k, {5, 10, 20, 50, 100, 200}}
];

Print[""];
Print["== timing: wide flat chain a@a@...@a (k operators, depth 1) =="];
Print["ops\tbytes\tParseOperatorTable (s)"];
Do[
   Module[{src = StringRiffle[ConstantArray["a", k], "@"], t},
      t = First @ AbsoluteTiming[Parse[expr, src]];
      Print[k, "\t", StringLength[src], "\t", N[Round[t, 0.000001]]];
   ],
   {k, {10, 100, 1000, 5000}}
];

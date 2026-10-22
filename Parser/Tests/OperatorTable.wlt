(* :Title: OperatorTable.wlt - ParseOperatorTable test suite *)
(* :Context: Wolfram`Parser` *)
(* :Summary:
    VerificationTest entries for ParseOperatorTable - the Pratt /
    binding-power-climbing operator-precedence combinator. Covers the
    constructor / normalisation, every fixity (InfixL, InfixR, Prefix,
    Postfix), multi-level precedence, parenthesised recursion, the
    ChainLeft / ChainRight equivalence, and the linear-time win on the
    left-nested input shape that makes an ordered-choice PEG grammar
    backtrack exponentially. Run via run-tests.wls.
*)

ClearAll[num, addOp, mulOp, calcUnit, calc, pow, lsym, lunit, logicExpr,
    fac, apOp, eUnit, eExpr]

(* --- arithmetic: * / tighter than + -, parens via ParseRecursive --- *)
num    = ParseAction[ParseRegex["[0-9]+"], FromDigits];
addOp  = ParseChoice[ParseAction[ParseLiteral["+"], (Plus &)],
                     ParseAction[ParseLiteral["-"], (Subtract &)]];
mulOp  = ParseChoice[ParseAction[ParseLiteral["*"], (Times &)],
                     ParseAction[ParseLiteral["/"], (Divide &)]];
calcUnit = ParseChoice[
    ParseBetween[ParseLiteral["("], ParseRecursive[calc], ParseLiteral[")"]],
    num];
calc   = ParseOperatorTable[calcUnit, {{{"InfixL", mulOp}}, {{"InfixL", addOp}}}];

(* --- right-associative power (inert head) --- *)
pow    = ParseOperatorTable[num, {{"InfixR", ParseAction[ParseLiteral["^"], (power &)]}}];

(* --- propositional logic: prefix ~, infix & |, right => --- *)
lsym   = ParseAction[ParseChoice @@ (ParseLiteral /@ {"p", "q", "r"}), Symbol];
lunit  = ParseChoice[
    ParseBetween[ParseLiteral["("], ParseRecursive[logicExpr], ParseLiteral[")"]],
    lsym];
logicExpr = ParseOperatorTable[lunit, {
    {{"Prefix", ParseAction[ParseLiteral["~"],  (Not &)]}},
    {{"InfixL", ParseAction[ParseLiteral["&"],  (And &)]}},
    {{"InfixL", ParseAction[ParseLiteral["|"],  (Or &)]}},
    {{"InfixR", ParseAction[ParseLiteral["=>"], (Implies &)]}}}];

(* --- postfix factorial (inert) --- *)
fac    = ParseOperatorTable[num, {
    {{"Postfix", ParseAction[ParseLiteral["!"], (fact &)]}},
    {{"InfixL",  ParseAction[ParseLiteral["+"], (plus &)]}}}];

(* --- left-nested apply chain: the PEG-blowup shape --- *)
apOp   = ParseAction[ParseLiteral["@"], (app &)];
eUnit  = ParseChoice[
    ParseBetween[ParseLiteral["("], ParseRecursive[eExpr], ParseLiteral[")"]],
    ParseAction[ParseChoice @@ (ParseLiteral /@ {"a", "b"}), Symbol]];
eExpr  = ParseOperatorTable[eUnit, {{"InfixL", apOp}}];
nest[0] = "a"; nest[k_] := nest[k] = "(" <> nest[k - 1] <> "@b)";


(* === constructor / normalisation === *)

VerificationTest[
    Head @ ParseOperatorTable[ParseLiteral["a"],
        {{"InfixL", ParseLiteral["+"]}}],
    ParserCombinator,
    TestID -> "ParseOperatorTable: returns a ParserCombinator"
]

VerificationTest[
    ParseOperatorTable[ParseLiteral["a"], {{"InfixL", ParseLiteral["+"]}}][[1]],
    "OperatorTable",
    TestID -> "ParseOperatorTable: type tag"
]

VerificationTest[
    (* a lone {fixity, opParser} level normalises to a singleton level *)
    ParseOperatorTable[ParseLiteral["a"], {{"InfixL", ParseLiteral["+"]}}][[2, 2]],
    {{{"InfixL", ParseLiteral["+"]}}},
    TestID -> "ParseOperatorTable: lone-spec level normalisation"
]


(* === associativity === *)

VerificationTest[
    Parse[calc, "1-2-3"],
    -4,
    TestID -> "ParseOperatorTable: InfixL is left-associative"
]

VerificationTest[
    Parse[pow, "2^3^2"],
    power[2, power[3, 2]],
    TestID -> "ParseOperatorTable: InfixR is right-associative"
]

VerificationTest[
    Parse[logicExpr, "p=>q=>r"],
    Implies[p, Implies[q, r]],
    TestID -> "ParseOperatorTable: InfixR connective nests right"
]


(* === precedence === *)

VerificationTest[
    Parse[calc, "1+2*3"],
    7,
    TestID -> "ParseOperatorTable: tighter level binds first"
]

VerificationTest[
    Parse[calc, "2*3+4*5"],
    26,
    TestID -> "ParseOperatorTable: precedence across both levels"
]

VerificationTest[
    Parse[logicExpr, "p|q&r"],
    Or[p, And[q, r]],
    TestID -> "ParseOperatorTable: & binds tighter than |"
]

VerificationTest[
    Parse[logicExpr, "p&q|r=>p"],
    Implies[Or[And[p, q], r], p],
    TestID -> "ParseOperatorTable: full precedence ladder"
]


(* === prefix / postfix === *)

VerificationTest[
    Parse[logicExpr, "~p&q"],
    And[Not[p], q],
    TestID -> "ParseOperatorTable: Prefix binds tighter than infix"
]

VerificationTest[
    Parse[fac, "3!+4!"],
    plus[fact[3], fact[4]],
    TestID -> "ParseOperatorTable: Postfix at tightest level"
]


(* === parentheses (recursion) === *)

VerificationTest[
    Parse[calc, "(1+2)*3"],
    9,
    TestID -> "ParseOperatorTable: parens override precedence"
]

VerificationTest[
    Parse[logicExpr, "~(p|q)"],
    Not[Or[p, q]],
    TestID -> "ParseOperatorTable: prefix over a parenthesised group"
]


(* === multiple operators per level === *)

VerificationTest[
    Parse[calc, "10-2+3"],
    11,
    TestID -> "ParseOperatorTable: same-level operators chain left"
]


(* === relation to ChainLeft / ChainRight === *)

VerificationTest[
    Parse[
        ParseOperatorTable[num, {{"InfixL", ParseAction[ParseLiteral["+"], (Plus &)]}}],
        "1+2+3"],
    Parse[ParseChainLeft[num, ParseAction[ParseLiteral["+"], (Plus &)]], "1+2+3"],
    TestID -> "ParseOperatorTable: single InfixL matches ParseChainLeft"
]


(* === linear time on the PEG-blowup shape === *)

VerificationTest[
    (* depth 12 left-nested apply chain - an ordered-choice grammar over
       or/and/apply would re-parse the shared operand ~3^12 times and time
       out; the climber parses it in one linear pass. *)
    Parse[eExpr, nest[12]],
    Nest[app[#, b] &, a, 12],
    TestID -> "ParseOperatorTable: deep left-nest parses (no backtrack blowup)"
]

VerificationTest[
    (* a wide flat apply chain stays linear too *)
    Parse[eExpr, StringRiffle[ConstantArray["a", 200], "@"]],
    Fold[app, ConstantArray[a, 200]],
    TestID -> "ParseOperatorTable: wide flat chain"
]


(* === flat n-ary chains ("InfixN") and ternary forms === *)

ClearAll[sumOp, relOp, sumTable, relTable, flatTable, tern, ternR]

(* a + b - c: "+" and "-" share the combining function, so they build one
   node; its operands and the operators' results come to the combine *)
sumOp[op_] := ParseAction[ParseLiteral[op], op &];
sumTable = ParseOperatorTable[num, {
    {{"InfixL", ParseAction[ParseLiteral["*"], (times &)]}},
    {{"InfixN", sumOp["+"], (sum[#1, #2] &)}, {"InfixN", sumOp["-"], (sum[#1, #2] &)}}}];

(* without a combine, a chain continues only across the same operator, and
   the operator's result is applied to the operands *)
flatTable = ParseOperatorTable[num, {
    {{"InfixN", ParseAction[ParseLiteral["&"], (and &)]}, {"InfixN", ParseAction[ParseLiteral["|"], (or &)]}}}];

tern  = ParseOperatorTable[num, {{"Ternary", ParseLiteral["?"], ParseAction[ParseLiteral[":"], (cond &)]}}];
ternR = ParseOperatorTable[num, {{"TernaryR", ParseLiteral["?"], ParseAction[ParseLiteral[":"], (cond &)]}}];

VerificationTest[
    Parse[sumTable, "1+2-3+4"],
    sum[{1, 2, 3, 4}, {"+", "-", "+"}],
    TestID -> "ParseOperatorTable: InfixN chain of two operators sharing a combine"]

VerificationTest[
    Parse[sumTable, "1+2*3-4"],
    sum[{1, times[2, 3], 4}, {"+", "-"}],
    TestID -> "ParseOperatorTable: InfixN operands bind tighter levels"]

VerificationTest[
    Parse[flatTable, "1&2&3|4|5&6"],
    and[or[and[1, 2, 3], 4, 5], 6],
    TestID -> "ParseOperatorTable: InfixN without combine chains one operator"]

VerificationTest[
    Parse[tern, "1?2:3?4:5"],
    cond[cond[1, 2, 3], 4, 5],
    TestID -> "ParseOperatorTable: Ternary is left-associative"]

VerificationTest[
    Parse[ternR, "1?2:3?4:5"],
    cond[1, 2, cond[3, 4, 5]],
    TestID -> "ParseOperatorTable: TernaryR is right-associative"]

(* a chain whose later operators may follow a newline, its first may not:
   the parser for the later ones, the spec's fourth element, reads them *)
ClearAll[nlTable];
nlTable = ParseOperatorTable[num, {
    {{"InfixN", sumOp["+"], (sum[#1, #2] &), ParseChoice[sumOp["+"], ParseAction[ParseLiteral["\n+"], "\n+" &]]}}}];

VerificationTest[
    {Parse[nlTable, "1+2\n+3+4"], ParsePartial[nlTable, "1\n+2"]},
    {sum[{1, 2, 3, 4}, {"+", "\n+", "+"}], {1, "\n+2"}},
    TestID -> "ParseOperatorTable: an InfixN chain reads its later operators with a parser of their own"]


(* an operand the table's FinalOperand test holds for ends the expression
   it begins; the operators around that expression still apply *)
VerificationTest[
    With[{t = ParseOperatorTable[ParseChoice[num, ParseAction[ParseLiteral["?"], (err &)]], {
            {{"InfixL", ParseAction[ParseLiteral["*"], (times &)]}},
            {{"InfixL", ParseAction[ParseLiteral["+"], (plus &)]}}}, "FinalOperand" -> (# === err &)]},
        {Parse[t, "1+?*2"], Parse[t, "1+2*3"]}],
    {times[plus[1, err], 2], plus[1, times[2, 3]]},
    TestID -> "ParseOperatorTable: a final operand takes no operator where it begins"]


(* === first-character dispatch === *)

VerificationTest[
    (* operators sharing a first character, an operator that begins with
       a regex (its first character unknown, so tried everywhere), and a
       prefix one: the dispatch only skips operators that cannot begin at
       the current character *)
    Parse[ParseOperatorTable[num, {
        {{"Prefix", ParseAction[ParseLiteral["-"], (neg &)]}},
        {{"InfixL", ParseAction[ParseLiteral["**"], (pow &)]}},
        {{"InfixL", ParseAction[ParseLiteral["*"], (times &)]}, {"InfixL", ParseAction[ParseRegex["[@#]"], (at &)]}},
        {{"InfixL", ParseAction[ParseLiteral["-"], (minus &)]}}}],
        "-1**2*3#4-5@6"],
    minus[at[times[pow[neg[1], 2], 3], 4], at[5, 6]],
    TestID -> "ParseOperatorTable: dispatch by first character keeps every match"]

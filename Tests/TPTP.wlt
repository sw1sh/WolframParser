(* :Title: TPTP.wlt - tests for the EBNFParse-driven TPTPImport in
   Wolfram`Parser`. *)

Needs["Wolfram`Parser`"]


(* ===== entry-point shape ===== *)

VerificationTest[
    Module[{r = TPTPImport["cnf(a, axiom, and(X, Y) = and(Y, X))."]},
        {Length[r["Axioms"]], MatchQ[r["Conjecture"], None]}
    ],
    {1, True},
    TestID -> "TPTP: inline cnf axiom"
]

VerificationTest[
    Module[{r = TPTPImport[
        "cnf(g, negated_conjecture, foo(sk) != sk)."]},
        Head[r["Conjecture"]]
    ],
    Equal,
    TestID -> "TPTP: negated_conjecture flips Unequal -> Equal"
]

VerificationTest[
    Module[{r = TPTPImport[
        "cnf(a1, axiom, and(X1, and(X2, X3)) = and(and(X1, X2), X3))."]},
        FreeQ[r["Axioms"], Missing]
    ],
    True,
    TestID -> "TPTP: variables resolve (no Missing)"
]

VerificationTest[
    Module[{r = TPTPImport[
        "cnf(g, negated_conjecture, sk_c1 != sk_c1)."]},
        FreeQ[ToString @ InputForm @ r["Conjecture"], "_c1"]
    ],
    True,
    TestID -> "TPTP: underscore in name canonicalised to camelCase"
]


(* ===== Boolean grammar ===== *)

VerificationTest[
    Module[{r = TPTPImport[
        "cnf(a, axiom, p(X) | q(X) | ~r(X))."]},
        {Head @ r["Axioms"][[1]], Length @ r["Axioms"][[1]]}
    ],
    {Or, 3},
    TestID -> "TPTP: multi-literal cnf disjunction"
]

VerificationTest[
    Head @ TPTPImport["fof(a, axiom, p(X) => q(X))."]["Axioms"][[1]],
    Implies,
    TestID -> "TPTP: fof => Implies"
]

VerificationTest[
    Module[{r = TPTPImport["fof(a, axiom, p & q & r)."]["Axioms"][[1]]},
        {Head[r], Length[r]}
    ],
    {And, 3},
    TestID -> "TPTP: fof & left-associative And"
]

VerificationTest[
    Head @ TPTPImport["fof(a, axiom, p <=> q)."]["Axioms"][[1]],
    Equivalent,
    TestID -> "TPTP: fof <=> Equivalent"
]

VerificationTest[
    MatchQ[
        TPTPImport["fof(a, axiom, p ~& q)."]["Axioms"][[1]],
        Not[_And]],
    True,
    TestID -> "TPTP: ~& shorthand -> Not[And[..]]"
]

VerificationTest[
    Module[{r = TPTPImport["fof(a, axiom, ? [X] : p(X))."]["Axioms"][[1]]},
        Head[r]
    ],
    Exists,
    TestID -> "TPTP: ? existential -> Exists"
]


(* ===== axiom shape ===== *)

VerificationTest[
    Module[{r = TPTPImport["fof(a, axiom, and(X, Y) = and(Y, X))."]},
        {Length[r["Axioms"]], MatchQ[r["Conjecture"], None]}
    ],
    {1, True},
    TestID -> "TPTP: fof free vars become universals"
]

VerificationTest[
    Module[{r = TPTPImport[
        "fof(comm, axiom, ! [X, Y] : (and(X, Y) = and(Y, X)))."]},
        {Length[r["Axioms"]], FreeQ[r["Axioms"], Missing]}
    ],
    {1, True},
    TestID -> "TPTP: fof top-level ForAll stripped"
]


(* ===== term-level coverage ===== *)

VerificationTest[
    TPTPImport["cnf(a, axiom, eq(a, 'hello world'))."]["Axioms"][[1, 2]],
    "hello world"[],
    TestID -> "TPTP: single-quoted atom with space"
]

VerificationTest[
    {TPTPImport["cnf(a, axiom, foo(42) = bar)."]["Axioms"][[1, 1, 1]],
     TPTPImport["cnf(a, axiom, foo(3.14) = bar)."]["Axioms"][[1, 1, 1]],
     TPTPImport["cnf(a, axiom, foo(3/4) = bar)."]["Axioms"][[1, 1, 1]]
    },
    {"42"[], "3.14"[], "3/4"[]},
    TestID -> "TPTP: numeric literals as String-headed 0-ary"
]

VerificationTest[
    Module[{r = TPTPImport[
        "cnf(a, axiom, eq(\"distinct1\", \"distinct2\"))."]},
        Head @ r["Axioms"][[1, 1]]
    ],
    "\"distinct1\"",
    TestID -> "TPTP: distinct object keeps surrounding quotes"
]

VerificationTest[
    {Head @ TPTPImport[
        "fof(a, axiom, $sum(2, 3) = 5)."]["Axioms"][[1, 1]],
     Head @ TPTPImport[
        "fof(a, axiom, $distinct(a, b, c))."]["Axioms"][[1]],
     TPTPImport["fof(a, axiom, $true)."]["Axioms"][[1]],
     TPTPImport["fof(a, axiom, $false)."]["Axioms"][[1]]
    },
    {"$sum", "$distinct", True, False},
    TestID -> "TPTP: $-defined forms ($true/$false to Booleans)"
]


(* ===== clause-head coverage ===== *)

VerificationTest[
    Module[{r = TPTPImport[
        "tpi(set, axiom, $set($timeout, 30)).\n" <>
        "cnf(a, axiom, foo(X) = X)."]},
        Length @ r["Axioms"]
    ],
    1,
    TestID -> "TPTP: tpi silently skipped"
]


(* ===== include resolution ===== *)

VerificationTest[
    Module[{tmpdir = CreateDirectory[], r},
        Export[FileNameJoin[{tmpdir, "ax.ax"}],
            "cnf(a1, axiom, mul(X, e) = X).\n", "Text"];
        Export[FileNameJoin[{tmpdir, "main.p"}],
            "include('ax.ax').\n" <>
            "cnf(g, negated_conjecture, mul(c, e) != c).\n",
            "Text"];
        r = TPTPImport[File @ FileNameJoin[{tmpdir, "main.p"}]];
        {Length @ r["Axioms"], Head @ r["Conjecture"]}
    ],
    {1, Equal},
    TestID -> "TPTP: include relative path"
]

VerificationTest[
    Module[{tmpdir = CreateDirectory[], r},
        Export[FileNameJoin[{tmpdir, "ax.ax"}],
            "cnf(a1, axiom, mul(X, e) = X).\n" <>
            "cnf(a2, axiom, mul(e, X) = X).\n" <>
            "cnf(a3, axiom, mul(inv(X), X) = e).\n", "Text"];
        Export[FileNameJoin[{tmpdir, "main.p"}],
            "include('ax.ax', [a1, a3]).\n", "Text"];
        r = TPTPImport[File @ FileNameJoin[{tmpdir, "main.p"}]];
        Length @ r["Axioms"]
    ],
    2,
    TestID -> "TPTP: include clause-name selector"
]


(* ===== file roundtrip ===== *)

VerificationTest[
    Module[{tmpdir = CreateDirectory[], r},
        Export[FileNameJoin[{tmpdir, "ag.p"}],
            "cnf(ax1, axiom, and(X1,and(X2,X3)) = and(and(X1,X2),X3)).\n" <>
            "cnf(ax2, axiom, and(X1,X2) = and(X2,X1)).\n" <>
            "cnf(ax3, axiom, and(X1,e) = X1).\n" <>
            "cnf(ax4, axiom, and(X1,inv(X1)) = e).\n" <>
            "cnf(goal, negated_conjecture, inv(inv(sk_c1)) != sk_c1).\n",
            "Text"];
        r = TPTPImport[File @ FileNameJoin[{tmpdir, "ag.p"}]];
        {Length[r["Axioms"]], MatchQ[r["Conjecture"], _Equal]}
    ],
    {4, True},
    TestID -> "TPTP: file roundtrip on abelian-group skeleton"
]


(* ===== SZS-output / derivation parsing ===== *)

szsBlock = "% SZS status Unsatisfiable for GRP001-4
% SZS output start CNFRefutation for GRP001-4
cnf(associativity, axiom, multiply(multiply(X,Y),Z) = multiply(X,multiply(Y,Z)), file('GRP001-4.p', associativity)).
cnf(left_identity, axiom, multiply(identity,X) = X, file('GRP001-4.p', left_identity)).
cnf(c7, plain, multiply(a,b) = c, inference(superposition, [status(thm)], [associativity, left_identity])).
cnf(c12, plain, $false, inference(cr, [status(thm)], [c7, prove_goal])).
% SZS output end CNFRefutation for GRP001-4
";

VerificationTest[
    Module[{r = TPTPImport[szsBlock, "SZS"]},
        {r["Status"], r["Problem"], r["OutputForm"], Length[r["Derivation"]]}
    ],
    {"Unsatisfiable", "GRP001-4", "CNFRefutation", 4},
    TestID -> "TPTP: SZS framing (status / problem / dataform / step count)"
]

VerificationTest[
    Module[{r = TPTPImport[szsBlock, "SZS"], step},
        step = SelectFirst[r["Derivation"], #["Name"] === "c7" &];
        {step["Rule"], step["Status"], step["Parents"]}
    ],
    {"superposition", "thm", {"associativity", "left_identity"}},
    TestID -> "TPTP: SZS inference rule / status / parents"
]

VerificationTest[
    Module[{r = TPTPImport[szsBlock, "SZS"]},
        {Last[r["Derivation"]]["Formula"], Last[r["Derivation"]]["Rule"]}
    ],
    {False, "cr"},
    TestID -> "TPTP: SZS empty clause $false -> False"
]

VerificationTest[
    Module[{r = TPTPImport[szsBlock, "SZS"], ax},
        ax = SelectFirst[r["Derivation"], #["Name"] === "associativity" &];
        {ax["Rule"], Head[ax["Formula"]], FreeQ[ax["Formula"], _Missing],
         ! FreeQ[ax["Formula"], "multiply"]}
    ],
    {"file", Equal, True, True},
    TestID -> "TPTP: SZS file source + parsed formula"
]

VerificationTest[
    Module[{r = TPTPImport[
        "cnf(c7, plain, p(a) != b, inference(resolution, [status(thm)], [3, 5])).", "SZS"]},
        {MissingQ[r["Status"]], Length[r["Derivation"]], r["Derivation"][[1]]["Parents"]}
    ],
    {True, 1, {"3", "5"}},
    TestID -> "TPTP: SZS bare-derivation fallback (no framing)"
]


(* ===== SZS-output emission (TPTPExport) + round-trip ===== *)

VerificationTest[
    Module[{r1 = TPTPImport[szsBlock, "SZS"], r2},
        r2 = TPTPImport[TPTPExport[r1], "SZS"];
        {r1["Status"], r1["Problem"], r1["OutputForm"]} ===
            {r2["Status"], r2["Problem"], r2["OutputForm"]} &&
        r1["Derivation"] === r2["Derivation"]
    ],
    True,
    TestID -> "TPTP: SZS read/emit round-trip (Import[Export[r]] === r)"
]

VerificationTest[
    Module[{txt = TPTPExport[TPTPImport[szsBlock, "SZS"]]},
        {StringContainsQ[txt, "% SZS status Unsatisfiable for GRP001-4"],
         StringContainsQ[txt, "inference(superposition, [status(thm)], [associativity, left_identity])"],
         StringContainsQ[txt, "$false"]}
    ],
    {True, True, True},
    TestID -> "TPTP: SZS emit renders framing + inference + empty clause"
]

VerificationTest[
    TPTPExport[<|"Derivation" -> {<|"Head" -> "cnf", "Name" -> "d", "Role" -> "plain",
        "Formula" -> Or["p"[Global`X_], "q"[Global`X_], Not["r"[Global`X_]]],
        "Rule" -> "split", "Status" -> "thm", "Parents" -> {"c1"}|>}|>],
    "cnf(d, plain, p(X) | q(X) | ~r(X), inference(split, [status(thm)], [c1])).\n",
    TestID -> "TPTP: SZS emit cnf disjunction with negative literal"
]

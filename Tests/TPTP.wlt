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

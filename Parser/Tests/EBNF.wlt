(* :Title: EBNF.wlt - tests for the BNF reader in Wolfram`Parser`. *)

Needs["Wolfram`Parser`"]

(* The TPTP BNF tests fetch the canonical grammar from TPTPWorld once
   per test run, then reuse the cached string across every test below
   so a flaky network doesn't multiply into N timeouts. *)
$tptpBnf = Import[
    "https://raw.githubusercontent.com/TPTPWorld/SyntaxBNF/master/SyntaxBNF-v9.2.1.4",
    "Text"]


(* ===== EBNFRules: BNF source -> structured rule list ===== *)

VerificationTest[
    EBNFRules["<greeting> ::= hello | bye"] // Length,
    1,
    TestID -> "EBNF: single rule extracted"
]

VerificationTest[
    EBNFRules["
        <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        <number> ::= <digit><digit>*
        <expr>   ::= <number> + <number>
    "] // Length,
    3,
    TestID -> "EBNF: three rules extracted, with non-terminals + repetition + literals"
]

VerificationTest[
    EBNFRules["<arrow> ::= ::- | :::"] // Length,
    1,
    TestID -> "EBNF: arrow-like literal tokens in rule body parse"
]


(* ===== EBNFParse: lower to Association[name -> parser] ===== *)

VerificationTest[
    Module[{g = EBNFParse["<greeting> ::= hello | bye"]},
        Parse[g["greeting"], "hello"]
    ],
    "hello",
    TestID -> "EBNF: parse via lowered rule (literal alternation)"
]

VerificationTest[
    Module[{g = EBNFParse["
        <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        <number> ::= <digit><digit>*
    "]},
        Parse[g["number"], "12345"]
    ],
    {"1", {"2", "3", "4", "5"}},
    TestID -> "EBNF: recursive non-terminal + `*` repetition lower correctly"
]

VerificationTest[
    Module[{g = EBNFParse["
        <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        <number> ::= <digit><digit>*
        <expr>   ::= <number> + <number>
    "]},
        Parse[g["expr"], "12 + 34"]
    ],
    {{"1", {"2"}}, "+", {"3", {"4"}}},
    TestID -> "EBNF: whitespace between literals/non-terminals tolerated automatically"
]


(* ===== TPTP coverage: the full grammar parses ===== *)

VerificationTest[
    Length @ EBNFRules @ $tptpBnf,
    354,
    TestID -> "EBNF: TPTPWorld SyntaxBNF-v9.2.1.4 parses to 354 rule records"
]

VerificationTest[
    Module[{bnf = $tptpBnf, parsers},
        (* Every TPTP lexical rule (lower_word, upper_word, integer,
           single_quoted, distinct_object, dollar_word, vline, star,
           plus, ..., and the regex-heavy sq_char / do_char /
           not_star_slash) auto-compiles from the BNF's `::-` and
           `:::` rule kinds.  No PrimitiveOverrides needed. *)
        parsers = EBNFParse[bnf];
        (* A minimal cnf clause from a real TPTP problem. The output is
           the raw parse tree; the formula slot contains the nested
           `{"p", {}}` because left-recursion elimination of
           `cnf_disjunction` produced a ParseMany whose zero-match
           continuation is `{}`. Going from the raw tree to the WL-term
           shape the handwritten TPTPImport returns is the semantic-
           action layer the lowering does not yet generate. *)
        Parse[parsers["cnf_annotated"], "cnf(test, axiom, p)."]
    ],
    {"cnf", "(", "test", ",", "axiom", ",", {"p", {}}, Null, ")."},
    TestID -> "EBNF: minimal cnf clause parses via auto-generated TPTP parser"
]

VerificationTest[
    Module[{g},
        g = EBNFParse[
            "<digit> ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
             <number> ::= <digit><digit>*",
            "Actions" -> <|
                "number" -> Function[FromDigits @ StringJoin[#1, StringJoin @ #2]]
            |>
        ];
        Parse[g["number"], "42"]
    ],
    42,
    TestID -> "EBNF: per-rule Actions lift parse tree to user-defined values"
]

VerificationTest[
    Module[{bnf, parsers, actions},
        bnf = "<TPTP_file>      ::= <cnf_annotated>*
<cnf_annotated>  ::= cnf(<name>, <role>, <atom>).
<name>           ::= <lower_word>
<role>           ::= <lower_word>
<atom>           ::= <lower_word>
<lower_word>     ::- <lower_alpha><alpha_numeric>*
<lower_alpha>    ::: [a-z]
<alpha_numeric>  ::: [a-zA-Z0-9_]";
        actions = <|
            "cnf_annotated" -> Function[<|
                "Head" -> "cnf", "Name" -> #3, "Role" -> #5, "Atom" -> #7
            |>],
            "TPTP_file" -> Function[Module[{cs = {##}},
                <|"Axioms" -> Map[#["Atom"] &,
                    Cases[cs, KeyValuePattern["Role" -> "axiom"]]]|>
            ]]
        |>;
        parsers = EBNFParse[bnf, "Actions" -> actions];
        Parse[parsers["TPTP_file"],
            "cnf(t1, axiom, p).cnf(t2, axiom, q).cnf(t3, hypothesis, r)."]
    ],
    <|"Axioms" -> {"p", "q"}|>,
    TestID -> "EBNF: Actions lift mini-TPTP parse to <|Axioms -> {...}|> shape"
]

VerificationTest[
    Module[{
        bnf = $tptpBnf,
        parsers, source
    },
        parsers = EBNFParse[bnf];
        (* A real-world TPTP problem: group axioms + a commutator
           definition + a conjecture. Five fof clauses with quantifiers,
           function application, and equality. The default `"Auto"`
           ChoiceMode falls back to longest-match for the rules whose
           alternatives have equal element counts (e.g. <fof_atomic_formula>
           with its three 1-element alts) - PEG-ordered first-match would
           commit to <fof_plain_atomic_formula> on the function-application
           term and miss the trailing `= rhs` parsed by
           <fof_defined_infix_formula>. The handwritten TPTPImport on the
           same input returns the lifted WL-term shape; this test just
           checks recognition (the next test plugs in actions to get the
           lifted shape). *)
        source = "fof(group_assoc, axiom, ! [X, Y, Z] : multiply(multiply(X, Y), Z) = multiply(X, multiply(Y, Z))).
fof(group_left_id, axiom, ! [X] : multiply(identity, X) = X).
fof(group_left_inv, axiom, ! [X] : multiply(inverse(X), X) = identity).
fof(commutator_def, axiom, ! [X, Y] : commutator(X, Y) = multiply(multiply(X, Y), multiply(inverse(X), inverse(Y)))).
fof(goal, conjecture, ! [X] : commutator(X, identity) = identity).";
        Length @ Parse[parsers["TPTP_file"], source]
    ],
    5,
    TestID -> "EBNF: five-clause group-theory TPTP problem parses via auto-generated parser"
]


(* ===== Closing the action-layer gap to TPTPImport ===== *)

(* The action map below mechanically lifts the auto-generated TPTP
   parser's raw parse tree to the same Wolfram-Language shape the
   handwritten TPTPImport returns: function application as
   `head[args...]`, Boolean operators as `And/Or/Not/Implies/...`,
   equality / disequality as `Equal/Unequal`, quantifiers as
   `ForAll/Exists`, cnf disjunctions as `Or[...]` (single literal
   stays bare), and the file partitioned into
   `<|"Includes", "Axioms", "Conjecture"|>`. Constants are emitted as
   `tok[]` (String-headed empty-arg compound) - same trick the
   handwritten parser uses so `Equal["a"[], "b"[]]` stays symbolic
   instead of eager-evaluating to `False`. *)

VerificationTest[
    Module[{
        bnf = $tptpBnf,
        binConn, rightList, quant, actions, parsers, source
    },
        binConn[op_String, x_, y_] := Switch[op,
            "<=>", Equivalent[x, y], "=>", Implies[x, y],
            "<=",  Implies[y, x],    "<~>", Xor[x, y],
            "~|",  Nor[x, y],        "~&", Nand[x, y]
        ];
        (* Right-recursive `<x> | <x>,<right>` flattener used by both
           fof_arguments and fof_variable_list. *)
        rightList[args__] := Module[{a = {args}},
            Switch[Length[a], 1, {a[[1]]}, 3, Prepend[a[[3]], a[[1]]]]
        ];
        (* ForAll / Exists are HoldAll, so a literal call holds the
           bound symbols unevaluated. Apply substitutes the captured
           vars/body before the head holds, and Quiet swallows the
           string-isn't-a-symbol warning emitted by ForAll::ivar. *)
        quant[q_, vs_, body_] := Quiet[
            Apply[If[q === "!", ForAll, Exists], {vs, body}],
            {ForAll::ivar, Exists::ivar}
        ];
        actions = <|
            "constant"  -> Function[#1[]],
            "functor"   -> Function[#1], "variable"  -> Function[#1],
            "fof_term"  -> Function[#1], "fof_function_term" -> Function[#1],
            "fof_plain_term" -> Function[Block[{a = {##}},
                Switch[Length[a], 1, a[[1]], 4, a[[1]] @@ a[[3]]]
            ]],
            "fof_arguments"  -> rightList,
            "fof_atomic_formula"         -> Function[#1],
            "fof_plain_atomic_formula"   -> Function[#1],
            "fof_defined_atomic_formula" -> Function[#1],
            "fof_defined_plain_formula"  -> Function[#1],
            "fof_defined_infix_formula"  -> Function[Equal[#1, #3]],
            "fof_infix_unary"            -> Function[Unequal[#1, #3]],
            "nonassoc_connective" -> Function[Block[{a = {##}},
                If[Length[a] === 1, a[[1]], StringJoin @@ a]
            ]],
            "fof_binary_nonassoc" -> Function[binConn[#2, #1, #3]],
            "fof_and_formula" -> Function[Block[{a = {##}},
                And @@ Join[{a[[1]], a[[3]]}, a[[4]][[All, 2]]]
            ]],
            "fof_or_formula" -> Function[Block[{a = {##}},
                Or @@ Join[{a[[1]], a[[3]]}, a[[4]][[All, 2]]]
            ]],
            "fof_binary_assoc"    -> Function[#1],
            "fof_binary_formula"  -> Function[#1],
            "fof_logic_formula"   -> Function[#1],
            "fof_unary_formula"   -> Function[Block[{a = {##}},
                Switch[Length[a], 1, a[[1]], 2, Not[a[[2]]]]
            ]],
            "fof_unit_formula"    -> Function[#1],
            "fof_unitary_formula" -> Function[Block[{a = {##}},
                Switch[Length[a], 1, a[[1]], 3, a[[2]]]
            ]],
            "fof_quantifier"      -> Function[#1],
            "fof_variable_list"   -> rightList,
            "fof_quantified_formula" -> Function[quant[#1, #3, #6]],
            "fof_formula" -> Function[#1],
            "cnf_literal" -> Function[Block[{a = {##}},
                Switch[Length[a], 1, a[[1]], 2, Not[a[[2]]], 4, Not[a[[3]]]]
            ]],
            "cnf_disjunction" -> Function[Block[{a = {##}},
                If[ Length[#2] === 0, #1,
                    Or @@ Prepend[#2[[All, 2]], #1]]
            ]],
            "cnf_formula" -> Function[Block[{a = {##}},
                Switch[Length[a], 1, a[[1]], 3, a[[2]]]
            ]],
            "cnf_annotated" -> Function[<|"Head" -> "cnf",
                "Name" -> #3, "Role" -> #5, "Formula" -> #7|>],
            "fof_annotated" -> Function[<|"Head" -> "fof",
                "Name" -> #3, "Role" -> #5, "Formula" -> #7|>],
            "tff_annotated" -> Function[<|"Head" -> "tff",
                "Name" -> #3, "Role" -> #5, "Formula" -> #7|>],
            "include" -> Function[<|"Head" -> "include", "File" -> #3|>],
            "TPTP_file" -> Function[Module[{cs = {##}}, <|
                "Includes" -> Cases[cs,
                    kv:KeyValuePattern["Head" -> "include"] :> kv["File"]],
                "Axioms" -> Cases[cs,
                    kv:KeyValuePattern["Role" -> "axiom" | "hypothesis"] :>
                        kv["Formula"]],
                "Conjecture" -> Module[{
                    c  = FirstCase[cs,
                        KeyValuePattern["Role" -> "conjecture"], None],
                    nc = FirstCase[cs,
                        KeyValuePattern["Role" -> "negated_conjecture"], None]},
                    Which[
                        c  =!= None, c["Formula"],
                        nc =!= None, Not[nc["Formula"]],
                        True, None
                    ]
                ]
            |>]]
        |>;
        parsers = EBNFParse[bnf, "Actions" -> actions];
        source = "fof(group_assoc, axiom, ! [X, Y, Z] : multiply(multiply(X, Y), Z) = multiply(X, multiply(Y, Z))).
fof(group_left_id, axiom, ! [X] : multiply(identity, X) = X).
fof(group_left_inv, axiom, ! [X] : multiply(inverse(X), X) = identity).
fof(goal, conjecture, ! [X] : multiply(X, identity) = X).";
        Parse[parsers["TPTP_file"], source]
    ],
    <|
        "Includes" -> {},
        "Axioms" -> {
            ForAll[{"X", "Y", "Z"},
                Equal[
                    "multiply"["multiply"["X", "Y"], "Z"],
                    "multiply"["X", "multiply"["Y", "Z"]]
                ]
            ],
            ForAll[{"X"},
                Equal["multiply"["identity"[], "X"], "X"]
            ],
            ForAll[{"X"},
                Equal["multiply"["inverse"["X"], "X"], "identity"[]]
            ]
        },
        "Conjecture" -> ForAll[{"X"},
            Equal["multiply"["X", "identity"[]], "X"]
        ]
    |>,
    SameTest -> (
        (* ForAll's HoldAll attribute makes a literal LHS reference
           hold the bound vars uninterpreted; ToString normalises both
           sides to a structural comparison and sidesteps the bound-
           var bookkeeping. *)
        ToString[#1, InputForm] === ToString[#2, InputForm] &
    ),
    TestID -> "EBNF: comprehensive TPTP action map produces TPTPImport-shaped output"
]

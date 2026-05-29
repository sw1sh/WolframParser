(* :Title: TPTP *)
(* :Context: Wolfram`Parser` *)
(* :Summary:
    Parse TPTP (Thousands of Problems for Theorem Provers) problem
    files into the canonical
        <|"Axioms" -> {phi1, phi2, ...}, "Conjecture" -> phi|>
    Wolfram Language shape.

    Implementation: drive the parser off the canonical TPTPWorld BNF
    (TPTPWorld/SyntaxBNF) via `EBNFParse`, then attach an "Actions"
    map that lifts the raw parse tree into the canonical shape. The
    grammar is fetched (versioned) from TPTPWorld's repo on first
    call and cached for the kernel session.

    Why this lives in WolframParser: the same machinery (`EBNFParse`
    + a per-rule action map) is what `EBNFParse` was built for. The
    TPTP grammar is the canonical real-world worked example. Shipping
    it here means the action map is one piece of the paclet, not a
    1000-line hand-rolled recursive-descent body in a separate
    repository.

    API (returns <|"Axioms" -> {...}, "Conjecture" -> phi|>):
        TPTPImport[File["path.p"]]
        TPTPImport["path.p"]
        TPTPImport["cnf(a, axiom, p(X))."]

    Function and predicate symbols come back as String-headed
    compounds (`"multiply"[X_, Y_]`, `"p"[X_]`) so a parsed TPTP
    symbol cannot collide with a user-level Wolfram Language binding.
    Variables come back as `Pattern[Symbol[name], Blank[]]` (so they
    render as `X_`). Quantifiers lift to `ForAll` / `Exists`; Boolean
    connectives to `And` / `Or` / `Not` / `Implies` / `Equivalent` /
    `Xor`; equational atoms to `Equal` / `Unequal`.

    include('path.ax') directives resolve recursively against the
    directory of the enclosing file, then the $TPTP and
    $TPTP/Problems env-var roots. The optional clause-name selector
    `include('p.ax', [a, b])` admits only the named clauses.

    The top-level universal quantifier of an axiom is stripped (the
    cnf default is universal closure); inner quantifiers stay as
    `ForAll` / `Exists`. `negated_conjecture` clauses are flipped via
    `Not` so the returned `Conjecture` is the positive goal.

    Design reference: docs/Tutorials/ParsingTPTP.md
*)

BeginPackage["Wolfram`Parser`"]

TPTPImport::usage =
    "TPTPImport[File[\"file.p\"]] | TPTPImport[\"... source ...\"] " <>
    "parses a TPTP problem and returns " <>
    "<|\"Axioms\" -> {phi1, ...}, \"Conjecture\" -> phi|>.  Function " <>
    "symbols come back as String-headed terms (\"and\"[X_, Y_] etc.); " <>
    "variables as Pattern[Symbol[name], Blank[]].  Handles cnf, fof, " <>
    "tff, tcf, thf clause heads plus `include` with optional " <>
    "clause-name selectors."

TPTPImport::badparse =
    "TPTP parse failed in `1`: `2`"

TPTPImport::badinclude =
    "Could not resolve TPTP include path `1` (searched relative to `2` " <>
    "and the $TPTP / $TPTP/Problems env-var roots)."

Begin["`TPTPPrivate`"]


(* ===== BNF + parser construction (memoized once per kernel) ===== *)

$tptpBnfURL =
    "https://raw.githubusercontent.com/TPTPWorld/SyntaxBNF/master/SyntaxBNF-v9.2.1.4"

ensureTptpParser[] := (
    $tptpParsers = EBNFParse[
        Import[$tptpBnfURL, "Text"],
        "Actions" -> Join[
            $tptpTermActions, $tptpConnActions, $tptpQuantActions,
            $tptpCnfActions, $tptpFileActions]
    ];
    $tptpParser = $tptpParsers["TPTP_file"];
    ensureTptpParser[] := $tptpParser;
    $tptpParser
)


(* ===== shared action helpers ===== *)

id = Function[#]

binConn[op_String, x_, y_] := Switch[op,
    "<=>", Equivalent[x, y],
    "=>",  Implies[x, y],
    "<=",  Implies[y, x],
    "<~>", Xor[x, y],
    "~|",  Not[Or[x, y]],
    "~&",  Not[And[x, y]]
]

rightList[args__] := Block[{a = {args}},
    Switch[Length[a],
        1, {a[[1]]},
        3, Prepend[a[[3]], a[[1]]]]
]

quant[q_, vs_, body_] := Quiet[
    Apply[If[q === "!", ForAll, Exists], {vs, body}],
    {ForAll::ivar, Exists::ivar}
]

(* Collapse underscores: `sk_c1` -> `skC1` (functor) or `SkC1`
   (variable). Underscores trip the Wolfram pattern parser (`_c1`
   reads as a Blank), so we canonicalise to camel-case. *)
canonName[s_String] := StringJoin @ MapIndexed[
    If[#2[[1]] === 1, ToLowerCase[#], Capitalize[#]] &,
    StringSplit[s, "_"]]

varCanonName[s_String] :=
    StringJoin @ Map[Capitalize, StringSplit[s, "_"]]

ensureVar[name_String] := Pattern[
    Evaluate @ Symbol["Global`" <> varCanonName[name]],
    Blank[]
]

unquoteSingle[s_String] := If[
    StringLength[s] >= 2 && StringTake[s, 1] === "'",
    StringTake[s, {2, -2}],
    s
]

dollarAtom[s_String] := Switch[s,
    "$true",  True,
    "$false", False,
    _,        s[]
]


(* ===== action maps ===== *)

(* Terms: terms lift to themselves; `f(args)` becomes "f"[args];
   `=`/`!=` become Equal / Unequal.  Numbers + distinct objects come
   back as String-headed 0-ary compounds for round-trip identity. *)
$tptpTermActions = <|
    "constant"                    -> Function[canonName[unquoteSingle[#]][]],
    "functor"                     -> Function[canonName[unquoteSingle[#]]],
    "variable"                    -> Function[ensureVar[#]],
    "defined_constant"            -> Function[dollarAtom[#]],
    "defined_functor"             -> id,
    "fof_term"                    -> id,
    "fof_function_term"           -> id,
    "fof_plain_term"              -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 4, a[[1]] @@ a[[3]]]]],
    "fof_defined_term"            -> id,
    "fof_defined_plain_term"      -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 4, a[[1]] @@ a[[3]]]]],
    "fof_arguments"               -> rightList,
    "fof_atomic_formula"          -> id,
    "fof_plain_atomic_formula"    -> id,
    "fof_defined_atomic_formula"  -> id,
    "fof_defined_plain_formula"   -> id,
    "fof_defined_infix_formula"   -> Function[Equal[#1, #3]],
    "fof_infix_unary"             -> Function[Unequal[#1, #3]],
    (* <number> ::= <integer> | <rational> | <real>; the leaf token
       rule wraps once into a String-headed 0-ary compound so the
       containing <number> just passes through. *)
    "integer"                     -> Function[#[]],
    "real"                        -> Function[#[]],
    "rational"                    -> Function[#[]],
    "number"                      -> id,
    "distinct_object"             -> Function[#[]],
    "defined_term"                -> id
|>

(* Boolean connectives: &, |, ~ lift to And / Or / Not. *)
$tptpConnActions = <|
    "nonassoc_connective" -> Function[Block[{a = {##}},
        If[Length[a] === 1, a[[1]], StringJoin @@ a]]],
    "fof_binary_nonassoc" -> Function[binConn[#2, #1, #3]],
    "fof_and_formula"     -> Function[Block[{a = {##}},
        And @@ Join[{a[[1]], a[[3]]}, a[[4]][[All, 2]]]]],
    "fof_or_formula"      -> Function[Block[{a = {##}},
        Or @@ Join[{a[[1]], a[[3]]}, a[[4]][[All, 2]]]]],
    "fof_unary_formula"   -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 2, Not[a[[2]]]]]]
|>

(* Quantifiers: ! / ? lift to ForAll / Exists. *)
$tptpQuantActions = <|
    "fof_quantifier"         -> id,
    "fof_variable_list"      -> rightList,
    "fof_quantified_formula" -> Function[quant[#1, #3, #6]],
    "fof_binary_assoc"       -> id,
    "fof_binary_formula"     -> id,
    "fof_logic_formula"      -> id,
    "fof_unit_formula"       -> id,
    "fof_unitary_formula"    -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 3, a[[2]]]]],
    "fof_formula"            -> id
|>

(* CNF: `|` literals.  Single literal stays bare; multi becomes Or.
   ~p / != stay as Not / Unequal. *)
$tptpCnfActions = <|
    "cnf_literal"     -> Function[Block[{a = {##}},
        Switch[Length[a],
            1, a[[1]],
            2, Not[a[[2]]],
            4, Not[a[[3]]]]]],
    "cnf_disjunction" -> Function[Block[{a = {##}},
        If[Length[#2] === 0, #1, Or @@ Prepend[#2[[All, 2]], #1]]]],
    "cnf_formula"     -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 3, a[[2]]]]]
|>

(* Tag each annotated clause with {Head, Name, Role, Formula}; tptpFile
   then partitions them.  Strip the top-level universal quantifier of
   axioms - cnf default is universal closure. *)
stripTopForAll[ForAll[_, body_]] := body
stripTopForAll[other_]            := other

annotated[head_String][args__] := Block[{a = {args}},
    <|"Head"    -> head,
      "Name"    -> ToString[a[[3]]],
      "Role"    -> ToString[a[[5]]],
      "Formula" -> stripTopForAll[a[[7]]]|>
]

(* TPTP_file action: partition annotated clauses into includes,
   {Name, Formula} axiom pairs, conjecture.  negated_conjecture flips
   through Not so the returned Conjecture is the positive goal. *)
tptpFile[cs__] := Block[
    {
        clauses = {cs},
        c, nc
    },
    c  = FirstCase[clauses, KeyValuePattern["Role" -> "conjecture"], None];
    nc = FirstCase[clauses, KeyValuePattern["Role" -> "negated_conjecture"], None];
    <|"Includes"   -> Cases[clauses,
                        kv : KeyValuePattern["Head" -> "include"] :> kv],
      "Axioms"     -> Cases[clauses,
                        kv : KeyValuePattern["Role" -> "axiom" | "hypothesis"] :>
                            <|"Name" -> kv["Name"], "Formula" -> kv["Formula"]|>],
      "Conjecture" -> Which[
          c  =!= None, c["Formula"],
          nc =!= None, Not[nc["Formula"]],
          True,        None]|>
]

$tptpFileActions = <|
    "cnf_annotated" -> annotated["cnf"],
    "fof_annotated" -> annotated["fof"],
    "tff_annotated" -> annotated["tff"],
    "tcf_annotated" -> annotated["tcf"],
    "thf_annotated" -> annotated["thf"],
    "tpi_annotated" -> Function[<|"Head" -> "tpi", "Role" -> "skipped"|>],
    "include"       -> Function[Block[{a = {##}},
        <|"Head"     -> "include",
          "File"     -> unquoteSingle[a[[3]]],
          "Selector" -> If[Length[a] >= 4 && AssociationQ[a[[4]]],
              a[[4]]["Selector"],
              All]|>]],
    "include_optionals" -> Function[Block[{a = {##}},
        If[Length[a] >= 2,
            <|"Selector" -> a[[2]]|>,
            <|"Selector" -> All|>]]],
    "formula_selection" -> Function[Block[{a = {##}},
        Switch[Length[a], 3, a[[2]], _, All]]],
    "name_list"     -> rightList,
    "TPTP_file"     -> tptpFile,
    "TPTP_input"    -> id
|>


(* ===== include resolution ===== *)

absolutePathQ[path_String] :=
    StringStartsQ[path, "/"] ||
    StringMatchQ[path, RegularExpression["^[A-Za-z]:.*"]]

resolveIncludePath[path_String, baseDir_String] := Block[
    {
        tptpRoot = Environment["TPTP"],
        candidates
    },
    candidates = Join[
        {path},
        If[absolutePathQ[path], {}, {FileNameJoin[{baseDir, path}]}],
        If[tptpRoot === $Failed || tptpRoot === None, {},
            {FileNameJoin[{tptpRoot, path}],
             FileNameJoin[{tptpRoot, "Problems", path}]}]];
    SelectFirst[candidates, FileExistsQ, $Failed]
]

expandIncludes[parsed_Association, baseDir_String] := Block[
    {extra},
    extra = Flatten @ Map[
        spec |-> includeAxioms[spec, baseDir],
        Lookup[parsed, "Includes", {}]];
    <|"Axioms"     -> Join[extra, parsed["Axioms"]],
      "Conjecture" -> parsed["Conjecture"]|>
]

includeAxioms[spec_Association, baseDir_String] := Block[
    {
        resolved = resolveIncludePath[spec["File"], baseDir],
        sub
    },
    If[ resolved === $Failed,
        Message[TPTPImport::badinclude, spec["File"], baseDir];
        Return[{}]
    ];
    sub = parseFileRaw[resolved];
    If[ !AssociationQ[sub], Return[{}] ];
    selectByName[
        expandIncludes[sub, DirectoryName[resolved]]["Axioms"],
        spec["Selector"]]
]

selectByName[axioms_List, All]              := axioms
selectByName[axioms_List, names_List]       :=
    Select[axioms, MemberQ[names, #["Name"]] &]
selectByName[axioms_List, _]                := axioms


(* ===== preprocessing: strip TPTP comments + tff type decls ===== *)

stripComments[text_String] := StringReplace[text,
    {
        RegularExpression["%[^\n]*"]                  -> "",
        RegularExpression["/\\*([^*]|\\*[^/])*\\*+/"] -> ""
    }
]

(* `tff(_, type, ...)` signature declarations are pure type info we
   drop before parsing so the post-parse partition stays simple. *)
stripTypeDecls[text_String] := StringReplace[text,
    RegularExpression["(tff|tcf|thf)\\([^,]*,\\s*type\\s*,[^.]*\\."] -> ""]


(* ===== entry points ===== *)

parseFileRaw[path_String] := Block[
    {text, parsed},
    ensureTptpParser[];
    text   = stripTypeDecls @ stripComments @ Import[path, "Text"];
    parsed = Quiet @ Parse[$tptpParser, StringTrim @ text];
    If[ FailureQ[parsed],
        Message[TPTPImport::badparse, path, parsed];
        Return[$Failed]
    ];
    parsed
]

parseTextRaw[text_String] := Block[
    {stripped, parsed},
    ensureTptpParser[];
    stripped = stripTypeDecls @ stripComments @ text;
    parsed   = Quiet @ Parse[$tptpParser, StringTrim @ stripped];
    If[ FailureQ[parsed],
        Message[TPTPImport::badparse, "(text)", parsed];
        Return[$Failed]
    ];
    parsed
]

flattenAxioms[parsed_Association] := <|
    "Axioms"     -> (Lookup[#, "Formula", #] & /@ parsed["Axioms"]),
    "Conjecture" -> parsed["Conjecture"]
|>

End[]


TPTPImport[File[path_String]] := Block[
    {raw = `TPTPPrivate`parseFileRaw[path]},
    If[ !AssociationQ[raw], Return[$Failed] ];
    `TPTPPrivate`flattenAxioms @ `TPTPPrivate`expandIncludes[raw,
        DirectoryName[AbsoluteFileName[path]]]
]

TPTPImport[s_String] /; FileExistsQ[s] && ! StringContainsQ[s,
        "cnf(" | "fof(" | "tff(" | "tcf(" | "thf(" | "ncf(" | "tpi("] :=
    TPTPImport[File[s]]

TPTPImport[text_String] := Block[
    {raw = `TPTPPrivate`parseTextRaw[text]},
    If[ !AssociationQ[raw], Return[$Failed] ];
    `TPTPPrivate`flattenAxioms @ `TPTPPrivate`expandIncludes[raw,
        Directory[]]
]


EndPackage[]

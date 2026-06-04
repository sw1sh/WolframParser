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
    "clause-name selectors.  TPTPImport[src, \"SZS\"] instead reads an " <>
    "SZS-output derivation, returning <|\"Status\" -> ..., \"Problem\" -> " <>
    "..., \"OutputForm\" -> ..., \"Derivation\" -> {<|\"Name\", \"Role\", " <>
    "\"Formula\", \"Rule\", \"Status\", \"Parents\"|>, ...}|>."

TPTPExport::usage =
    "TPTPExport[<|\"Status\" -> ..., \"OutputForm\" -> ..., \"Derivation\" -> " <>
    "{step1, ...}|>] renders an SZS-output derivation back to SZS-framed " <>
    "TPTP text - the inverse of TPTPImport[src, \"SZS\"].  Each step is an " <>
    "<|\"Head\", \"Name\", \"Role\", \"Formula\", \"Rule\", \"Status\", " <>
    "\"Parents\"|> record; inference steps re-render from their fields, " <>
    "other sources from the retained \"RawSource\"."

TPTPImport::badparse =
    "TPTP parse failed in `1`: `2`"

TPTPImport::badinclude =
    "Could not resolve TPTP include path `1` (searched relative to `2` " <>
    "and the $TPTP / $TPTP/Problems env-var roots)."

Begin["`Private`"]


(* ===== BNF + parser construction (memoized once per kernel) ===== *)

$tptpBnfURL =
    "https://raw.githubusercontent.com/TPTPWorld/SyntaxBNF/master/SyntaxBNF-v9.2.1.4"

ensureTptpParser[] := (
    $tptpParsers = EBNFParse[
        Import[$tptpBnfURL, "Text"],
        "PrimitiveOverrides" -> <|"thf_logic_formula" -> $thfLogicOverride|>,
        "Actions" -> Join[
            $tptpTermActions, $tptpConnActions, $tptpThfActions,
            $tptpQuantActions, $tptpCnfActions, $tptpFileActions]
    ];
    (* close the Pratt override's forward reference: thfUnitary$ now resolves
       to the lowered <thf_unitary_formula> parser at parse time. *)
    thfUnitary$ = $tptpParsers["thf_unitary_formula"];
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

(* ===== THF connectives via a Pratt operator table =====
   The published <thf_binary_assoc> ::= <thf_or_formula> | <thf_and_formula>
   | <thf_apply_formula> is an ordered choice whose three alternatives all
   begin with the shared <thf_unit_formula>. Lowered to a PEG, the leading
   operand is re-parsed once per alternative with no memo, and because each
   operand can itself be a parenthesised formula the cost is O(3^depth) -
   the THF blow-up the bench reports. Overriding <thf_logic_formula> with
   ParseOperatorTable replaces the cascade with one binding-power climb:
   the operand is parsed once, then the operators are consumed left to
   right. The operand is <thf_unitary_formula> (quantifier / atom / variable
   / parenthesised formula - alternatives distinguished by their first
   token, so a parenthesised operand is parsed once, not re-parsed per
   alternative the way <thf_unit_formula>'s unitary | unary | defined_infix
   would). Everything that <thf_unit_formula> adds on top - prefix ~, the
   = / != predicates - is lifted into the table instead. thfUnitary$ is a
   forward reference bound to the lowered <thf_unitary_formula> after
   EBNFParse returns (ParseRecursive looks it up lazily at parse time).
   Precedence, tightest first: @ (application), = / != , prefix ~ , & , | ,
   then the nonassoc connectives. *)

thfApply[f_, x_]   := f[x]            (* curried application: f @ x @ y -> f[x][y] *)
thfRevImplies[x_, y_] := Implies[y, x]
thfNor[x_, y_]     := Not[Or[x, y]]
thfNand[x_, y_]    := Not[And[x, y]]

(* TPTP is whitespace-liberal, so each connective consumes the optional
   whitespace on both sides; the (fn &) action discards the whitespace /
   token list and yields fn as the combining function. The operand parser
   (<thf_unit_formula>) is reached at a non-whitespace position because the
   preceding connective already ate the gap. *)
thfWs = ParseMany[ParseCharacter[WhitespaceCharacter]]
thfOp[lit_String, fn_] :=
    ParseAction[ParseSequence[thfWs, ParseLiteral[lit], thfWs], (fn &)]
(* `=` must not swallow the `=` of `=>`; guard with a not-followed-by. *)
thfOpNF[lit_String, after_String, fn_] := ParseAction[
    ParseSequence[thfWs, ParseLiteral[lit],
        ParseNotFollowedBy[ParseLiteral[after]], thfWs], (fn &)]

$thfLogicOverride := ParseOperatorTable[ParseRecursive[thfUnitary$], {
    {{"InfixL", thfOp["@", thfApply]}},
    {{"InfixL", thfOpNF["=", ">", Equal]}, {"InfixL", thfOp["!=", Unequal]}},
    {{"Prefix", thfOp["~", Not]}},
    {{"InfixL", thfOp["&", And]}},
    {{"InfixL", thfOp["|", Or]}},
    {   (* nonassoc connectives - longer tokens first so <=> beats <= *)
        {"InfixR", thfOp["<=>", Equivalent]},
        {"InfixR", thfOp["<~>", Xor]},
        {"InfixR", thfOp["=>",  Implies]},
        {"InfixR", thfOp["<=",  thfRevImplies]},
        {"InfixR", thfOp["~|",  thfNor]},
        {"InfixR", thfOp["~&",  thfNand]}
    }
}]

(* Minimal THF unit actions: enough for the connective / application /
   equality core to come back as clean WL terms. Quantifier / let / type
   bodies are not yet lifted - they pass through as raw parse trees. *)
$tptpThfActions = <|
    "thf_formula"         -> id,
    "thf_unit_formula"    -> id,
    "thf_unitary_formula" -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 3, a[[2]]]]],   (* ( logic ) -> logic *)
    "thf_atomic_formula"  -> id,
    "thf_plain_atomic"    -> id,
    "thf_defined_atomic"  -> id,
    "thf_system_atomic"   -> id,
    "thf_defined_term"    -> id,
    "thf_unitary_term"    -> Function[Block[{a = {##}},
        Switch[Length[a], 1, a[[1]], 3, a[[2]]]]],
    "thf_defined_infix"   -> Function[Equal[#1, #3]],
    "thf_unary_formula"   -> id,
    "thf_prefix_unary"    -> Function[Not[#2]],
    "thf_preunit_formula" -> id,
    "thf_infix_unary"     -> Function[Unequal[#1, #3]]
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
tptpFile[cs__] := Block[{
    clauses = {cs},
    c, nc
},
    c = FirstCase[clauses, KeyValuePattern["Role" -> "conjecture"], None];
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

resolveIncludePath[path_String, baseDir_String] := Block[{
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

expandIncludes[parsed_Association, baseDir_String] := Block[{extra},
    extra = Flatten @ Map[
        spec |-> includeAxioms[spec, baseDir],
        Lookup[parsed, "Includes", {}]];
    <|"Axioms"     -> Join[extra, parsed["Axioms"]],
      "Conjecture" -> parsed["Conjecture"]|>
]

includeAxioms[spec_Association, baseDir_String] := Block[{
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

parseFileRaw[path_String] := Block[{text, parsed},
    ensureTptpParser[];
    text = stripTypeDecls @ stripComments @ Import[path, "Text"];
    parsed = Quiet @ Parse[$tptpParser, StringTrim @ text];
    If[ FailureQ[parsed],
        Message[TPTPImport::badparse, path, parsed];
        Return[$Failed]
    ];
    parsed
]

parseTextRaw[text_String] := Block[{stripped, parsed},
    ensureTptpParser[];
    stripped = stripTypeDecls @ stripComments @ text;
    parsed = Quiet @ Parse[$tptpParser, StringTrim @ stripped];
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


(* ===== public entry points ===== *)

TPTPImport[File[path_String]] := Block[{raw = parseFileRaw[path]},
    If[ !AssociationQ[raw], Return[$Failed] ];
    flattenAxioms @ expandIncludes[raw, DirectoryName[AbsoluteFileName[path]]]
]

TPTPImport[s_String] /; FileExistsQ[s] && ! StringContainsQ[s,
        "cnf(" | "fof(" | "tff(" | "tcf(" | "thf(" | "ncf(" | "tpi("] :=
    TPTPImport[File[s]]

TPTPImport[text_String] := Block[{raw = parseTextRaw[text]},
    If[ !AssociationQ[raw], Return[$Failed] ];
    flattenAxioms @ expandIncludes[raw, Directory[]]
]


(* ===== SZS-output / derivation parsing ===== *)

(* The SZS status / output markers are TPTP *comments*, not part of the
   BNF, so the default importer's stripComments deletes them; the
   `inference(...)` source (the 4th annotated-formula field) it parses
   but discards.  `TPTPImport[src, "SZS"]` adds both back as a thin layer
   ON TOP of the existing parser: scan the SZS framing out-of-band,
   split the derivation into clauses (paren/quote aware), reparse each
   step's formula through the grammar, and lift the inference source into
   a {Rule, Status, Parents} record.  The base parser is untouched. *)

$tptpHeads = {"cnf", "fof", "tff", "tcf", "thf", "tpi"}

(* Split `str` on any single-char separator in `seps`, but only at
   paren/bracket depth 0 and outside single quotes - so a `.` inside a
   real number or a `,` inside a formula does not split.  Pieces are
   accumulated as a binary-nested char list (O(1) append) and rendered
   with StringJoin @ Flatten at each break, so the whole scan is O(n). *)
splitTopLevel[str_String, seps_List] := Block[{step, final},
    step[{out_, piece_, depth_, inq_}, c_] := Which[
        inq && c === "'",                {out, {piece, c}, depth, False},
        inq,                             {out, {piece, c}, depth, True},
        c === "'",                       {out, {piece, c}, depth, True},
        c === "(" || c === "[",          {out, {piece, c}, depth + 1, inq},
        c === ")" || c === "]",          {out, {piece, c}, depth - 1, inq},
        depth === 0 && MemberQ[seps, c], {Append[out, StringJoin @ Flatten @ {piece}], {}, depth, inq},
        True,                            {out, {piece, c}, depth, inq}
    ];
    final = Fold[step, {{}, {}, 0, False}, Characters[str]];
    DeleteCases[
        StringTrim /@ Append[final[[1]], StringJoin @ Flatten @ {final[[2]]}],
        ""
    ]
]

(* tokens of a parent list `[a, b, ...]` (outer brackets stripped) *)
szsTokens[s_String] := Select[
    splitTopLevel[
        StringReplace[StringTrim[s], {StartOfString ~~ "[" -> "", "]" ~~ EndOfString -> ""}],
        {","}
    ],
    # =!= "" &
]

(* lift an annotation source string into {Rule, Status, Parents};
   handles the canonical inference(rule, useful_info, parents) record and
   the file(...) / introduced(...) forms, plus a bare name / [list]
   dag-source.  Exotic general_term sources keep the raw string. *)
szsSource[src_String] := Block[{fn, inner, args, statusStr},
    fn = StringCases[src, StartOfString ~~ f : (WordCharacter ..) ~~ "(" :> f, 1];
    If[ fn === {},
        Return[<|"Rule" -> Missing["NoRule"], "Status" -> Missing["NoStatus"],
            "Parents" -> szsTokens[src], "RawSource" -> src|>]
    ];
    inner = StringTake[src, {First[First[StringPosition[src, "(", 1]]] + 1, -2}];
    args = splitTopLevel[inner, {","}];
    statusStr = StringCases[src, "status(" ~~ s : (WordCharacter ..) ~~ ")" :> s, 1];
    (* an `inference(rule, useful_info, parents)` record carries the real
       inference rule as its first argument; the bare functor "inference"
       is just the wrapper, so report the inner rule.  Other source forms
       (file, introduced, ...) report the functor itself. *)
    <|"Rule"      -> If[fn[[1]] === "inference" && Length[args] >= 1, args[[1]], fn[[1]]],
      "Status"    -> If[statusStr === {}, Missing["NoStatus"], statusStr[[1]]],
      "Parents"   -> If[Length[args] >= 3, szsTokens[Last[args]], {}],
      "RawSource" -> src|>
]

(* reparse one step's formula text through the grammar (as an axiom so it
   lands in "Axioms"), falling back to the raw string on a parse miss *)
szsFormula[fText_String] := Block[{raw},
    raw = Quiet @ parseTextRaw["cnf(szsStep, axiom, " <> fText <> ")."];
    If[ AssociationQ[raw] && Length[Lookup[raw, "Axioms", {}]] >= 1,
        raw["Axioms"][[1]]["Formula"],
        fText
    ]
]

szsClauseRecord[clause_String] := Block[{op, head, inner, fields},
    op = StringPosition[clause, "(", 1];
    If[ op === {}, Return[Missing["NotClause"]] ];
    head = StringTrim @ StringTake[clause, op[[1, 1]] - 1];
    If[ ! MemberQ[$tptpHeads, head], Return[Missing["NotClause"]] ];
    inner = StringTake[clause, {op[[1, 1]] + 1, -2}];
    fields = splitTopLevel[inner, {","}];
    If[ Length[fields] < 3, Return[Missing["BadClause"]] ];
    Join[
        <|"Head" -> head, "Name" -> fields[[1]], "Role" -> fields[[2]],
          "Formula" -> szsFormula[fields[[3]]]|>,
        If[ Length[fields] >= 4, szsSource[fields[[4]]], <||>]
    ]
]

(* scan the SZS status line and the SZS output start/end block (raw text,
   before comment stripping); fall back to the whole text as the
   derivation body when no output block is present. *)
szsScan[text_String] := Block[{st, blk},
    st = StringCases[text,
        "SZS status " ~~ s : (WordCharacter ..) ~~ " for " ~~ p : (Except[WhitespaceCharacter] ..) :> {s, p}, 1];
    blk = StringCases[text,
        "SZS output start " ~~ f : (WordCharacter ..) ~~ Shortest[___] ~~ "\n" ~~
            b : Shortest[___] ~~ "SZS output end" :> {f, b}, 1];
    <|"Status"     -> If[st === {}, Missing["NoStatus"], st[[1, 1]]],
      "Problem"    -> If[st === {}, Missing["NoProblem"], st[[1, 2]]],
      "OutputForm" -> If[blk === {}, Missing["NoOutputBlock"], blk[[1, 1]]],
      "Body"       -> If[blk === {}, text, blk[[1, 2]]]|>
]

szsImport[rawText_String] := Block[{scan, clauseStrs, deriv},
    ensureTptpParser[];
    scan = szsScan[rawText];
    clauseStrs = Select[
        splitTopLevel[stripComments[scan["Body"]], {"."}],
        clause |-> AnyTrue[$tptpHeads, StringStartsQ[clause, # ~~ ("(" | " " | "\t" | "\n")] &]
    ];
    deriv = DeleteMissing[szsClauseRecord /@ clauseStrs];
    <|"Status"     -> scan["Status"],
      "Problem"    -> scan["Problem"],
      "OutputForm" -> scan["OutputForm"],
      "Derivation" -> deriv|>
]

TPTPImport[File[path_String], "SZS"] := szsImport[Import[path, "Text"]]

TPTPImport[s_String, "SZS"] := szsImport[If[FileExistsQ[s], Import[s, "Text"], s]]


(* ===== SZS-output / derivation emission ===== *)

(* The inverse of TPTPImport[..., "SZS"]: render a derivation (the
   association that mode returns) back to SZS-framed TPTP text.
   formulaToTPTP is the inverse of the action map - it prints the
   parser's canonical term shape ("f"[...] functors, "c"[] constants,
   X_ variables, Equal/Unequal/And/Or/Not/.../ForAll/Exists). *)

tptpTerm[Verbatim[Pattern][v_Symbol, Verbatim[Blank][]]] := SymbolName[v]
tptpTerm[(h_String)[args___]] := With[{as = {args}},
    If[ as === {}, h, h <> "(" <> StringRiffle[tptpTerm /@ as, ", "] <> ")"]]
tptpTerm[s_Symbol] := SymbolName[s]
tptpTerm[x_] := ToString[x]

(* parenthesize a subformula only when it is a compound connective; Not
   binds tightly and stays bare (a parenthesized literal is not a valid
   cnf literal). *)
ftSub[x_] := If[
    MatchQ[x, _And | _Or | _Implies | _Equivalent | _Xor | _ForAll | _Exists],
    "(" <> formulaToTPTP[x] <> ")",
    formulaToTPTP[x]
]

formulaToTPTP[True]               := "$true"
formulaToTPTP[False]              := "$false"
formulaToTPTP[Equal[a_, b_]]      := tptpTerm[a] <> " = " <> tptpTerm[b]
formulaToTPTP[Unequal[a_, b_]]    := tptpTerm[a] <> " != " <> tptpTerm[b]
formulaToTPTP[Not[a_]]            := "~" <> ftSub[a]
formulaToTPTP[e_And]              := StringRiffle[ftSub /@ Apply[List, e], " & "]
formulaToTPTP[e_Or]               := StringRiffle[ftSub /@ Apply[List, e], " | "]
formulaToTPTP[Implies[a_, b_]]    := ftSub[a] <> " => " <> ftSub[b]
formulaToTPTP[Equivalent[a_, b_]] := ftSub[a] <> " <=> " <> ftSub[b]
formulaToTPTP[Xor[a_, b_]]        := ftSub[a] <> " <~> " <> ftSub[b]
formulaToTPTP[ForAll[vs_, b_]]    :=
    "! [" <> StringRiffle[tptpTerm /@ Flatten[{vs}], ", "] <> "] : " <> ftSub[b]
formulaToTPTP[Exists[vs_, b_]]    :=
    "? [" <> StringRiffle[tptpTerm /@ Flatten[{vs}], ", "] <> "] : " <> ftSub[b]
formulaToTPTP[atom_]              := tptpTerm[atom]

(* an inference step re-renders from its {Rule, Status, Parents} fields
   (round-trips); any other source is reproduced from its RawSource. *)
renderSource[step_Association] := Block[{
    rule = Lookup[step, "Rule", Missing[]],
    parents = Lookup[step, "Parents", {}],
    status = Lookup[step, "Status", Missing[]],
    raw = Lookup[step, "RawSource", Missing[]]
},
    Which[
        ! MissingQ[rule] && rule =!= "file" && Length[parents] > 0,
            ", inference(" <> rule <> ", [" <>
                If[MissingQ[status], "", "status(" <> status <> ")"] <>
                "], [" <> StringRiffle[parents, ", "] <> "])",
        ! MissingQ[raw],
            ", " <> raw,
        True,
            ""
    ]
]

renderClause[step_Association] := StringJoin[
    step["Head"], "(", step["Name"], ", ", step["Role"], ", ",
    formulaToTPTP[step["Formula"]], renderSource[step], ")."
]

TPTPExport[a_Association] := Block[{
    prob = Replace[Lookup[a, "Problem", Missing[]], _Missing -> "unknown"],
    form = Replace[Lookup[a, "OutputForm", Missing[]], _Missing -> "Derivation"],
    hasStatus = StringQ[Lookup[a, "Status", Missing[]]],
    hasForm = StringQ[Lookup[a, "OutputForm", Missing[]]]
},
    StringRiffle[
        Join[
            If[hasStatus, {"% SZS status " <> a["Status"] <> " for " <> prob}, {}],
            If[hasForm, {"% SZS output start " <> form <> " for " <> prob}, {}],
            renderClause /@ Lookup[a, "Derivation", {}],
            If[hasForm, {"% SZS output end " <> form <> " for " <> prob}, {}]
        ],
        "\n"
    ] <> "\n"
]


End[]

EndPackage[]

(* ::Package:: *)

(* :Title: OpenQASM.wl - OpenQASM 2.0 / 3.0, a real quantum-circuit DSL *)
(* :Context: Wolfram`Parser`Languages`OpenQASM` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The zoo's full-fledged language: a combinator grammar for the circuit-level
    subset of OpenQASM (both the 2.0 and 3.0 dialects). The same grammar runs
    two ways -

      OpenQASMAST["OPENQASM 3.0; qubit[2] q; h q[0]; cx q[0], q[1];"]
        -> standard AST (ContainerNode of CallNode/LeafNode statements)
      OpenQASMRead[...]
        -> a neutral circuit IR: <|"Version", "Includes", "Registers",
           "GateDefs", "Statements"|> as plain Wolfram data, dependency-free.

    Covered: the OPENQASM header, include, qreg/creg (v2) and qubit/bit (v3)
    registers, standard + parametrized + user-defined gates, the inv / pow /
    ctrl / negctrl modifiers, both measure syntaxes (`measure q -> c` and
    `c = measure q`), reset, barrier, gphase, physical qubits ($n), and angle
    expressions over pi / tau / euler. Anything outside the subset (classical
    types, control flow, def, timing) parses to an "Unsupported" record rather
    than failing the whole read. The IR is intentionally neutral so a
    QuantumFramework adapter could turn it into a QuantumCircuitOperator.
*)

BeginPackage["Wolfram`Parser`Languages`OpenQASM`", {"Wolfram`Parser`"}]

OpenQASMAST::usage  = "OpenQASMAST[\"src\"] parses OpenQASM 2.0/3.0 source to a standard AST (a ContainerNode of per-statement CallNode/LeafNode forms).";
OpenQASMRead::usage = "OpenQASMRead[\"src\"] reads OpenQASM 2.0/3.0 source to a neutral circuit IR: an Association with \"Version\", \"Includes\", \"Registers\", \"GateDefs\", and an ordered \"Statements\" list of gate / measure / reset / barrier / gphase records (plain Wolfram data, no QuantumFramework dependency).";
OpenQASMGrammar::usage = "OpenQASMGrammar[alg] builds the OpenQASM parser over the algebra alg.";
OpenQASMReadAlgebra::usage = "OpenQASMReadAlgebra is the algebra that reads OpenQASM to the neutral circuit IR.";

Begin["`Private`"]

(* ---------- shared helpers ---------- *)

(* whitespace skips spaces AND // line and /* block comments *)
ws := ParseMany[ParseChoice[
    ParseSome[ParseCharacter[WhitespaceCharacter]],
    ParseRegex["//[^\n]*"],
    ParseRegex["/\\*([^*]|\\*(?!/))*\\*/"]]]

tok[p_] := ParseAction[p ~~ ws, #1 &]
lit[s_] := tok @ ParseLiteral[s]
kw[s_]  := tok @ ParseRegex[s <> "(?![A-Za-z0-9_])"]   (* keyword, not a prefix of a longer ident *)

identTok := tok @ ParseRegex["[A-Za-z_][A-Za-z0-9_]*"]
intTok   := tok @ ParseRegex["[0-9]+"]
strTok   := tok @ ParseRegex["\"[^\"]*\""]

(* ---------- the grammar, over an algebra ---------- *)

OpenQASMGrammar[alg_] := Module[{expr, exprRef, statement, stmtRef, program,
    qubitRef, modifier, gateApply, gphase, measureV2, measureV3, gateDef,
    versionStmt, includeStmt, regDecl, resetStmt, barrierStmt, unsupportedStmt,
    exprUnit, neg, binop, num, const, qargList, paramList, modifiers, gateBody},

    expr = RecCell[];
    exprRef = RecRef[expr];
    statement = RecCell[];
    stmtRef = RecRef[statement];

    (* angle expressions: pi/tau/euler, numbers, the - + * / operators, exponent, parens *)
    num   = ParseAction[tok @ ParseRegex["[0-9]+\\.[0-9]+|[0-9]+"], alg["Num"]];
    const = ParseAction[tok @ ParseRegex["(pi|tau|euler)(?![A-Za-z0-9_])"], alg["Const"]];
    exprUnit = ParseChoice[
        ParseBetween[lit["("], exprRef, lit[")"]],
        num, const];
    neg[op_]   := ParseAction[lit[op], (Function[x, alg["Neg"][op, x]]) &];
    binop[op_] := ParseAction[(tok @ ParseLiteral[op]),
        (Function[{l, r}, alg["BinOp"][op, l, r]]) &];
    SetRec[expr, ParseOperatorTable[exprUnit, {
        {{"Prefix", neg["-"]}},
        {{"InfixR", binop["**"]}, {"InfixR", binop["^"]}},
        {{"InfixL", binop["*"]}, {"InfixL", binop["/"]}},
        {{"InfixL", binop["+"]}, {"InfixL", binop["-"]}}
    }]];

    (* qubit references: reg[i], reg, or $n (physical) *)
    qubitRef = ParseChoice[
        ParseAction[tok @ ParseRegex["\\$[0-9]+"], alg["Physical"]],
        ParseAction[identTok ~~ lit["["] ~~ intTok ~~ lit["]"],
            (alg["Indexed"][#1, #3]) &],
        ParseAction[identTok, alg["Whole"]]];

    (* a qubit-argument list: comma- OR whitespace-separated (the QF emitter writes
       `q[0] q[1]`; standard OpenQASM uses commas) *)
    qargList = ParseSepBy[qubitRef, ParseOptional[lit[","]]];
    paramList = ParseBetween[lit["("], ParseSepBy[exprRef, lit[","]], lit[")"]];

    (* gate modifiers: inv / pow(k) / ctrl[(n)] / negctrl[(n)], each followed by @ *)
    modifier = ParseAction[
        ParseChoice[
            ParseAction[kw["inv"], (alg["Mod"]["inv", Missing[]]) &],
            ParseAction[kw["pow"] ~~ lit["("] ~~ tok @ ParseRegex["-?[0-9]+"] ~~ lit[")"],
                (alg["Mod"]["pow", #3]) &],
            ParseAction[kw["ctrl"] ~~ ParseOptional[ParseBetween[lit["("], intTok, lit[")"]]],
                (alg["Mod"]["ctrl", #2]) &],
            ParseAction[kw["negctrl"] ~~ ParseOptional[ParseBetween[lit["("], intTok, lit[")"]]],
                (alg["Mod"]["negctrl", #2]) &]
        ] ~~ lit["@"], #1 &];
    modifiers = ParseMany[modifier];

    (* statements *)
    versionStmt = ParseAction[kw["OPENQASM"] ~~ tok @ ParseRegex["[0-9]+(\\.[0-9]+)?"] ~~ lit[";"],
        (alg["Version"][#2]) &];
    includeStmt = ParseAction[kw["include"] ~~ strTok ~~ lit[";"], (alg["Include"][#2]) &];

    regDecl = ParseChoice[
        ParseAction[kw["qreg"] ~~ identTok ~~ lit["["] ~~ intTok ~~ lit["]"] ~~ lit[";"],
            (alg["Reg"]["qubit", #2, #4]) &],
        ParseAction[kw["creg"] ~~ identTok ~~ lit["["] ~~ intTok ~~ lit["]"] ~~ lit[";"],
            (alg["Reg"]["bit", #2, #4]) &],
        ParseAction[kw["qubit"] ~~ ParseOptional[ParseBetween[lit["["], intTok, lit["]"]]] ~~ identTok ~~ lit[";"],
            (alg["Reg"]["qubit", #3, #2]) &],
        ParseAction[kw["bit"] ~~ ParseOptional[ParseBetween[lit["["], intTok, lit["]"]]] ~~ identTok ~~ lit[";"],
            (alg["Reg"]["bit", #3, #2]) &]];

    gateBody = ParseBetween[lit["{"], ParseMany[stmtRef], lit["}"]];
    gateDef = ParseAction[
        kw["gate"] ~~ identTok ~~ ParseOptional[ParseBetween[lit["("], ParseSepBy[identTok, lit[","]], lit[")"]]] ~~
            ParseSepBy[identTok, ParseOptional[lit[","]]] ~~ gateBody,
        (alg["GateDef"][#2, #3, #4, #5]) &];

    resetStmt   = ParseAction[kw["reset"] ~~ qargList ~~ lit[";"], (alg["Reset"][#2]) &];
    barrierStmt = ParseAction[kw["barrier"] ~~ ParseOptional[qargList] ~~ lit[";"], (alg["Barrier"][#2]) &];

    measureV2 = ParseAction[kw["measure"] ~~ qubitRef ~~ lit["->"] ~~ qubitRef ~~ lit[";"],
        (alg["Measure"][#2, #4]) &];
    measureV3 = ParseAction[qubitRef ~~ lit["="] ~~ kw["measure"] ~~ qubitRef ~~ lit[";"],
        (alg["Measure"][#4, #1]) &];

    gphase = ParseAction[modifiers ~~ kw["gphase"] ~~ lit["("] ~~ exprRef ~~ lit[")"] ~~ ParseOptional[qargList] ~~ lit[";"],
        (alg["GPhase"][#1, #4, #6]) &];
    gateApply = ParseAction[modifiers ~~ identTok ~~ ParseOptional[paramList] ~~ qargList ~~ lit[";"],
        (alg["Gate"][#1, #2, #3, #4]) &];

    (* recognized-but-unsupported constructs: capture the leading keyword and the
       rest of the statement (to a ; at depth 0, or a balanced { } block) *)
    unsupportedStmt = ParseAction[
        tok @ ParseRegex["(if|for|while|def|defcal|box|delay|let|input|output|const|int|uint|float|bool|angle|duration|stretch|array|return)(?![A-Za-z0-9_])"] ~~
            ParseChoice[
                ParseAction[ParseRegex["[^;{]*"] ~~ ParseBetween[lit["{"], ParseRegex["[^}]*"], lit["}"]], "" &],
                ParseAction[ParseRegex["[^;]*"] ~~ lit[";"], "" &]],
        (alg["Unsupported"][#1]) &];

    SetRec[statement, ParseChoice[versionStmt, includeStmt, regDecl, gateDef,
        resetStmt, barrierStmt, measureV2, measureV3, gphase, unsupportedStmt, gateApply]];

    program = ParseAction[ws ~~ ParseMany[stmtRef], (alg["Program"][#2]) &];
    program
];

(* ---------- the AST algebra (standard nodes) ---------- *)

leaf[kind_, s_] := LeafNode[kind, s, <||>]

qasmAstAlgebra = <|
    "Num"    -> (leaf[If[StringContainsQ[#, "."], "Real", "Integer"], #] &),
    "Const"  -> (leaf["Symbol", #] &),
    "Neg"    -> Function[{op, x}, PrefixNode[op, x, <||>]],
    "BinOp"  -> Function[{op, l, r}, BinaryNode[op, {l, r}, <||>]],
    "Physical" -> (leaf["Qubit", #] &),
    "Indexed"  -> Function[{nm, i}, CallNode[leaf["Register", nm], {leaf["Integer", i]}, <||>]],
    "Whole"    -> (leaf["Register", #] &),
    "Mod"    -> Function[{kind, arg}, If[MissingQ[arg], leaf["Modifier", kind], CallNode[leaf["Modifier", kind], {leaf["Integer", arg]}, <||>]]],
    "Version"  -> (CallNode[leaf["Keyword", "OPENQASM"], {leaf["Real", #]}, <||>] &),
    "Include"  -> (CallNode[leaf["Keyword", "include"], {leaf["String", #]}, <||>] &),
    "Reg"    -> Function[{kind, nm, sz}, CallNode[leaf["Keyword", kind], {leaf["Symbol", nm], leaf["Integer", sz]}, <||>]],
    "GateDef" -> Function[{nm, params, qubits, body},
        CallNode[leaf["Keyword", "gate"], {leaf["Symbol", nm],
            GroupNode["Params", If[MissingQ[params], {}, leaf["Symbol", #] & /@ params], <||>],
            GroupNode["Qubits", leaf["Symbol", #] & /@ qubits, <||>],
            GroupNode["Body", body, <||>]}, <||>]],
    "Gate"   -> Function[{mods, nm, params, qubits},
        modWrap[mods, CallNode[leaf["Gate", nm],
            Join[If[MissingQ[params], {}, params], qubits], <||>]]],
    "Measure" -> Function[{q, c}, CallNode[leaf["Keyword", "measure"], {q, c}, <||>]],
    "Reset"  -> (CallNode[leaf["Keyword", "reset"], #, <||>] &),
    "Barrier" -> (CallNode[leaf["Keyword", "barrier"], If[MissingQ[#], {}, #], <||>] &),
    "GPhase" -> Function[{mods, p, qubits}, modWrap[mods,
        CallNode[leaf["Keyword", "gphase"], Join[{p}, If[MissingQ[qubits], {}, qubits]], <||>]]],
    "Unsupported" -> (CallNode[leaf["Keyword", "unsupported"], {leaf["Symbol", #]}, <||>] &),
    "Program" -> (ContainerNode["String", #, <||>] &)
|>

modWrap[mods_, node_] := Fold[Function[{acc, m}, PrefixNode["@", {m, acc}, <||>]], node, Reverse[mods]]

(* ---------- the Read algebra (neutral circuit IR) ---------- *)

(* angle expressions evaluate to Wolfram values (pi -> Pi, ...) *)
constVal["pi"] = Pi
constVal["tau"] = 2 Pi
constVal["euler"] = E

(* Numbers go through Interpreter, never ToExpression - the input is grammar-
   validated, but Interpreter is type-safe and cannot evaluate injected code.
   Interpreter["Number"] keeps an integer exact, so pi/3 stays Pi/3. *)
toInt = Interpreter["Integer"]
toNum = Interpreter["Number"]

qasmReadAlgebra = <|
    "Num"    -> (toNum[#] &),
    "Const"  -> (constVal[#] &),
    "Neg"    -> ((-#2) &),
    "BinOp"  -> Function[{op, l, r}, Switch[op,
        "+", l + r, "-", l - r, "*", l*r, "/", l/r, "^" | "**", l^r]],
    "Physical" -> (<|"Physical" -> toInt[StringDrop[#, 1]]|> &),
    "Indexed"  -> Function[{nm, i}, <|"Register" -> nm, "Index" -> toInt[i]|>],
    "Whole"    -> (<|"Register" -> #|> &),
    "Mod"    -> Function[{kind, arg}, <|"Kind" -> kind, "Arg" -> If[MissingQ[arg], If[kind === "inv", Missing[], 1], toInt[arg]]|>],
    "Version"  -> (irVersion[Floor @ toNum[#]] &),
    "Include"  -> (irInclude[StringTake[#, {2, -2}]] &),
    "Reg"    -> Function[{kind, nm, sz}, irReg[<|"Kind" -> kind, "Name" -> nm, "Size" -> If[MissingQ[sz], 1, toInt[sz]]|>]],
    "GateDef" -> Function[{nm, params, qubits, body},
        irGateDef[<|"Name" -> nm, "Params" -> If[MissingQ[params], {}, params], "Qubits" -> qubits, "Body" -> body|>]],
    "Gate"   -> Function[{mods, nm, params, qubits},
        <|"Type" -> "Gate", "Modifiers" -> mods, "Name" -> nm, "Params" -> If[MissingQ[params], {}, params], "Qubits" -> qubits|>],
    "Measure" -> Function[{q, c}, <|"Type" -> "Measure", "Qubit" -> q, "Target" -> c|>],
    "Reset"  -> (<|"Type" -> "Reset", "Qubits" -> #|> &),
    "Barrier" -> (<|"Type" -> "Barrier", "Qubits" -> If[MissingQ[#], All, #]|> &),
    "GPhase" -> Function[{mods, p, qubits}, <|"Type" -> "GPhase", "Modifiers" -> mods, "Param" -> p, "Qubits" -> If[MissingQ[qubits], {}, qubits]|>],
    "Unsupported" -> (<|"Type" -> "Unsupported", "Keyword" -> #|> &),
    "Program" -> Function[stmts, <|
        "Version" -> FirstCase[stmts, irVersion[n_] :> n, 2],
        "Includes" -> Cases[stmts, irInclude[s_] :> s],
        "Registers" -> Cases[stmts, irReg[r_] :> r],
        "GateDefs" -> Cases[stmts, irGateDef[d_] :> d],
        "Statements" -> Cases[stmts, r_Association /; KeyExistsQ[r, "Type"]]
    |>]
|>

(* ---------- build parsers once, expose entry points ---------- *)

$astParser  = OpenQASMGrammar[qasmAstAlgebra]
$readParser = OpenQASMGrammar[qasmReadAlgebra]

OpenQASMAST[s_String] := Parse[$astParser, s]
OpenQASMRead[s_String] := Parse[$readParser, s]

End[]

EndPackage[]

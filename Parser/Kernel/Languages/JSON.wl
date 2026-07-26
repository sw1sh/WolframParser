(* ::Package:: *)

(* :Title: JSON.wl - RFC 8259 JSON, a recursive data grammar *)
(* :Context: Wolfram`Parser`Languages`JSON` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    A complete JSON reader. Stresses recursive data (objects/arrays nest
    through ParseRecursive), string escapes, and the number grammar. Two runs:

      JSONAST["[1, {\"a\": true}]"]  -> standard AST (GroupNode/BinaryNode/LeafNode)
      JSONImport["[1, {\"a\": true}]"] -> {1, <|"a" -> True|>}  (native WL value)

    Only escape-decoding and numeric-literal reading delegate to the kernel
    (ImportString[.., "RawJSON"] / Interpreter["Number"] on the matched token);
    the grammar structure - which is the point - is entirely combinators here.
*)

BeginPackage["Wolfram`Parser`Languages`JSON`", {"Wolfram`Parser`"}]

JSONAST::usage    = "JSONAST[\"json\"] parses JSON to a standard AST (a ContainerNode of GroupNode/BinaryNode/LeafNode)."
JSONImport::usage = "JSONImport[\"json\"] parses JSON to a native Wolfram value (Association / List / String / number / True|False|Null)."
JSONGrammar::usage = "JSONGrammar[alg] builds the JSON parser over the algebra alg."
JSONSemantic::usage = "JSONSemantic is the algebra that folds JSON to a native Wolfram value."

Begin["`Private`"]

unescapeJSON[raw_String]    := ImportString[raw, "RawJSON"]
readJSONNumber[s_String]    := Interpreter["Number"][s]

JSONGrammar[alg_] := Module[{ws, tok, str, num, bool, null, value, member, object, array},
    value = RecCell[];
    ws = ParseMany[ParseCharacter[WhitespaceCharacter]];
    tok[p_] := ParseAction[p ~~ ws, #1 &];

    str  = SpannedToken[ParseRegex["\"(\\\\.|[^\"\\\\])*\""], ws, alg["Str"]];
    num  = SpannedToken[ParseRegex["-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][-+]?[0-9]+)?"], ws, alg["Num"]];
    bool = SpannedToken[ParseChoice[ParseLiteral["true"], ParseLiteral["false"]], ws, alg["Bool"]];
    null = SpannedToken[ParseLiteral["null"], ws, (alg["Null"][] &)];

    member = ParseAction[
        str ~~ tok @ ParseLiteral[":"] ~~ RecRef[value],
        (alg["Member"][#1, #3]) &];
    object = ParseAction[
        tok @ ParseLiteral["{"] ~~ ParseSepBy[member, tok @ ParseLiteral[","]] ~~ tok @ ParseLiteral["}"],
        (alg["Object"][#2]) &];
    array = ParseAction[
        tok @ ParseLiteral["["] ~~ ParseSepBy[RecRef[value], tok @ ParseLiteral[","]] ~~ tok @ ParseLiteral["]"],
        (alg["Array"][#2]) &];

    SetRec[value, ParseChoice[str, num, object, array, bool, null]];

    ParseAction[ws ~~ RecRef[value], #2 &]
]

jsonAstAlgebra = <|
    "Str"    -> (LeafNode["String", #, <||>] &),
    "Num"    -> Function[s, LeafNode[If[StringContainsQ[s, "." | "e" | "E"], "Real", "Integer"], s, <||>]],
    "Bool"   -> (LeafNode["Boolean", #, <||>] &),
    "Null"   -> (LeafNode["Null", "null", <||>] &),
    "Member" -> Function[{k, v}, BinaryNode[":", {k, v}, <||>]],
    "Object" -> (GroupNode["Object", #, <||>] &),
    "Array"  -> (GroupNode["Array", #, <||>] &)
|>

JSONSemantic = <|
    "Str"    -> (unescapeJSON[#] &),
    "Num"    -> (readJSONNumber[#] &),
    "Bool"   -> (# === "true" &),
    "Null"   -> (Null &),
    "Member" -> Function[{k, v}, k -> v],
    "Object" -> (Association[#] &),
    "Array"  -> (# &)
|>

$astParser = JSONGrammar[jsonAstAlgebra]
$semParser = JSONGrammar[JSONSemantic]

JSONAST[s_String] := With[{r = Parse[$astParser, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

JSONImport[s_String] := Parse[$semParser, s]

End[]

EndPackage[]

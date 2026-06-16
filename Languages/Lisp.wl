(* ::Package:: *)

(* :Title: Lisp.wl - S-expressions, uniform recursive syntax *)
(* :Context: Wolfram`Parser`Languages`Lisp` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    An s-expression reader: atoms (symbols / numbers / strings), parenthesised
    lists, the quote reader macro ('x), and ;-to-end-of-line comments. The
    whole language is one self-similar rule, so it exercises ParseRecursive and
    comment-aware whitespace more than precedence. Two runs:

      LispAST["(+ 1 (max 2 3))"]  -> standard AST (CallNode/LeafNode, ' as PrefixNode)
      LispRead["(+ 1 (max 2 3))"] -> {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}}

    LispRead is the classic Lisp `read`: source becomes native nested Wolfram
    data (lists + LispSymbol wrappers) ready for a downstream evaluator.
*)

BeginPackage["Wolfram`Parser`Languages`Lisp`", {"Wolfram`Parser`"}]

LispAST::usage    = "LispAST[\"sexpr\"] parses one or more s-expressions to a standard AST (a ContainerNode of CallNode/LeafNode/PrefixNode)."
LispRead::usage   = "LispRead[\"sexpr\"] reads s-expressions to native nested Wolfram data (lists + LispSymbol[..]). Returns the single form, or the list of top-level forms."
LispSymbol::usage = "LispSymbol[\"name\"] is a read Lisp symbol (kept distinct from a Wolfram Symbol since Lisp names like + or list->vector are not Wolfram identifiers)."
LispGrammar::usage = "LispGrammar[alg] builds the Lisp reader over the algebra alg."
LispSemantic::usage = "LispSemantic is the algebra that reads Lisp to native Wolfram data."

Begin["`Private`"]

numberQ[s_String] := StringMatchQ[s, RegularExpression["[+-]?[0-9]+(\\.[0-9]+)?"]]

LispGrammar[alg_] := Module[{ws, tok, str, atom, quote, list, form},
    form = RecCell[];
    (* whitespace skips spaces AND ;-comments *)
    ws = ParseMany[ParseChoice[
        ParseSome[ParseCharacter[WhitespaceCharacter]],
        ParseRegex[";[^\n]*"]]];
    tok[p_] := ParseAction[p ~~ ws, #1 &];

    str = SpannedToken[ParseRegex["\"(\\\\.|[^\"\\\\])*\""], ws, alg["Str"]];
    atom = SpannedToken[ParseRegex["[^\\s()';\"]+"], ws,
        Function[s, If[numberQ[s], alg["Num"][s], alg["Sym"][s]]]];
    quote = ParseAction[
        tok @ ParseLiteral["'"] ~~ RecRef[form],
        (alg["Quote"][#2]) &];
    list = ParseAction[
        tok @ ParseLiteral["("] ~~ ParseMany[RecRef[form]] ~~ tok @ ParseLiteral[")"],
        (alg["List"][#2]) &];

    SetRec[form, ParseChoice[str, quote, list, atom]];
    ParseAction[ws ~~ ParseSome[RecRef[form]], (#2) &]
]

lispAstAlgebra = <|
    "Sym"   -> (LeafNode["Symbol", #, <||>] &),
    "Num"   -> Function[s, LeafNode[If[StringContainsQ[s, "."], "Real", "Integer"], s, <||>]],
    "Str"   -> (LeafNode["String", #, <||>] &),
    "Quote" -> (PrefixNode["'", #, <||>] &),
    "List"  -> Function[elems, If[elems === {},
        GroupNode["List", {}, <||>],
        CallNode[First[elems], Rest[elems], <||>]]]
|>

LispSemantic = <|
    "Sym"   -> (LispSymbol[#] &),
    "Num"   -> (Interpreter["Number"][#] &),
    "Str"   -> (ImportString[#, "RawJSON"] &),
    "Quote" -> Function[f, {LispSymbol["quote"], f}],
    "List"  -> Function[elems, elems]
|>

$astParser = LispGrammar[lispAstAlgebra]
$semParser = LispGrammar[LispSemantic]

LispAST[s_String] := With[{r = Parse[$astParser, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

LispRead[s_String] := With[{r = Parse[$semParser, s]},
    Which[FailureQ[r], r, Length[r] === 1, First[r], True, r]]

End[]

EndPackage[]

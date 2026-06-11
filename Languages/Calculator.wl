(* ::Package:: *)

(* :Title: Calculator.wl - arithmetic expressions, the simplest zoo grammar *)
(* :Context: Wolfram`Parser`Languages`Calculator` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    A four-function calculator with ^, unary minus, parentheses and bare
    identifiers. It is the canonical example of the zoo's design: one grammar
    (`CalculatorGrammar`) written over an abstract algebra, run two ways -

      CalculatorAST["1 + 2*3"]  -> standard AST  (ASTAlgebra)
      CalculatorEval["1 + 2*3"] -> 7             (CalculatorSemantic)

    Precedence (tightest first): parentheses, unary -, ^ (right assoc),
    * /, + -. Built with ParseOperatorTable, the library's Pratt /
    precedence-climbing combinator, so left-nested input stays linear where
    an ordered-choice PEG tower would backtrack.
*)

BeginPackage["Wolfram`Parser`Languages`Calculator`", {"Wolfram`Parser`"}]

CalculatorAST::usage  = "CalculatorAST[\"expr\"] parses an arithmetic expression to a standard AST (a ContainerNode of BinaryNode/PrefixNode/LeafNode)."
CalculatorEval::usage = "CalculatorEval[\"expr\"] parses and evaluates an arithmetic expression to a Wolfram value (numbers fold, identifiers stay symbolic)."
CalculatorGrammar::usage    = "CalculatorGrammar[alg] builds the calculator parser over the algebra alg (an Association of builder functions)."
CalculatorSemantic::usage   = "CalculatorSemantic is the algebra that folds the calculator to a numeric / symbolic Wolfram value."

Begin["`Private`"]

(* --- the grammar, parameterised over an algebra --- *)
CalculatorGrammar[alg_] := Module[{ws, tok, number, ident, unit, bin, pre, expr, top},
    expr = RecCell[];
    ws = ParseMany[ParseCharacter[WhitespaceCharacter]];
    tok[p_] := ParseAction[p ~~ ws, #1 &];

    (* SpannedToken records each leaf's source span (and eats trailing ws) *)
    number = SpannedToken[ParseRegex["[0-9]+\\.[0-9]+|[0-9]+"], ws,
        Function[s, alg["Leaf"][If[StringContainsQ[s, "."], "Real", "Integer"], s]]];

    ident = SpannedToken[ParseRegex["[A-Za-z][A-Za-z0-9]*"], ws,
        Function[s, alg["Leaf"]["Symbol", s]]];

    unit = ParseChoice[
        ParseBetween[tok @ ParseLiteral["("], RecRef[expr], tok @ ParseLiteral[")"]],
        number, ident];

    (* each operator parser yields the COMBINING FUNCTION the table folds *)
    bin[op_] := ParseAction[tok @ ParseLiteral[op],
        (Function[{l, r}, alg["Binary"][op, l, r]]) &];
    pre[op_] := ParseAction[tok @ ParseLiteral[op],
        (Function[x, alg["Prefix"][op, x]]) &];

    top = ParseOperatorTable[unit, {
        {{"Prefix", pre["-"]}},
        {{"InfixR", bin["^"]}},
        {{"InfixL", bin["*"]}, {"InfixL", bin["/"]}},
        {{"InfixL", bin["+"]}, {"InfixL", bin["-"]}}
    }];
    SetRec[expr, top];
    top
]

(* --- the meaningful (language-specific) algebra --- *)
CalculatorSemantic = <|
    "Leaf" -> Function[{kind, src}, Switch[kind,
        "Integer", FromDigits[src],
        "Real",    ToExpression[src],
        _,         Symbol[src]]],
    "Binary" -> Function[{op, l, r}, Switch[op,
        "+", l + r, "-", l - r, "*", l*r, "/", l/r, "^", l^r]],
    "Prefix" -> Function[{op, x}, If[op === "-", -x, x]]
|>

(* --- build each parser once at load --- *)
$astParser = CalculatorGrammar[ASTAlgebra]
$semParser = CalculatorGrammar[CalculatorSemantic]

CalculatorAST[s_String] := With[{r = Parse[$astParser, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

CalculatorEval[s_String] := Parse[$semParser, s]

End[]

EndPackage[]

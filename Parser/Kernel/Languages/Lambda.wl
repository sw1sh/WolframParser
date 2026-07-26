(* ::Package:: *)

(* :Title: Lambda.wl - the untyped lambda calculus *)
(* :Context: Wolfram`Parser`Languages`Lambda` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    Untyped lambda calculus: variables, abstraction (\x. body or the unicode
    \[Lambda]x. body, with \x y. b sugar for \x.\y.b), and application by
    juxtaposition (left-associative). It stresses binders and the application/
    abstraction precedence split - and unicode atoms (the interpreted parser
    handles \[Lambda]). Two runs:

      LambdaAST["\\x.\\y.x"]     -> standard AST (CallNode with a "lambda" head)
      LambdaEval["(\\x.\\y.x) a b"] -> a

    LambdaEval is the striking one: each abstraction becomes a real Wolfram
    Function and application is real Wolfram application, so the kernel does the
    beta-reduction for us - the parser literally compiles lambda terms to native
    closures.
*)

BeginPackage["Wolfram`Parser`Languages`Lambda`", {"Wolfram`Parser`"}]

LambdaAST::usage  = "LambdaAST[\"term\"] parses a lambda term to a standard AST (CallNode application, CallNode[lambda, {var, body}] abstraction, LeafNode variables)."
LambdaEval::usage = "LambdaEval[\"term\"] compiles a lambda term to a native Wolfram Function and lets the kernel beta-reduce; free variables stay symbolic."
LambdaGrammar::usage = "LambdaGrammar[alg] builds the lambda-calculus parser over the algebra alg."
LambdaSemantic::usage = "LambdaSemantic is the algebra that compiles lambda terms to native Wolfram closures."

Begin["`Private`"]

(* Compile \name. body to a native closure: rename the bound variable to a
   fresh symbol so application is real Wolfram beta-reduction and shadowing is
   safe. Apply (@@) forces both the parameter and the substituted body to
   evaluate before Function's HoldAll captures them. Because terms are built
   bottom-up, an inner binder has already replaced its own occurrences before
   an outer one runs, so `body /. Symbol[name] -> u` never captures a shadowed
   variable. *)
makeAbs[name_String, body_] := Module[{u}, Function @@ {u, body /. Symbol[name] -> u}]

foldApp[alg_, atoms_List] := Fold[Function[{f, x}, alg["App"][f, x]], First[atoms], Rest[atoms]]

LambdaGrammar[alg_] := Module[{ws, tok, name, var, lam, atom, app, term},
    term = RecCell[];
    ws = ParseMany[ParseCharacter[WhitespaceCharacter]];
    tok[p_] := ParseAction[p ~~ ws, #1 &];

    name = tok @ ParseRegex["[A-Za-z][A-Za-z0-9_]*"];
    var  = SpannedToken[ParseRegex["[A-Za-z][A-Za-z0-9_]*"], ws, alg["Var"]];

    (* #2 is the bound-name list, #4 the body; fold \x y. b into \x.\y. b *)
    lam = ParseAction[
        (tok @ ParseLiteral["\\"] | tok @ ParseLiteral["\[Lambda]"]) ~~
            ParseSome[name] ~~ tok @ ParseLiteral["."] ~~ RecRef[term],
        (Fold[Function[{acc, nm}, alg["Abs"][nm, acc]], #4, Reverse[#2]]) &];

    atom = ParseChoice[
        ParseAction[tok @ ParseLiteral["("] ~~ RecRef[term] ~~ tok @ ParseLiteral[")"], (#2) &],
        var];

    app  = ParseAction[ParseSome[atom], (foldApp[alg, {##}]) &];
    SetRec[term, ParseChoice[lam, app]];

    ParseAction[ws ~~ RecRef[term], #2 &]
]

lambdaAstAlgebra = <|
    "Var" -> (LeafNode["Symbol", #, <||>] &),
    "App" -> Function[{f, x}, CallNode[f, {x}, <||>]],
    "Abs" -> Function[{name, body},
        CallNode[LeafNode["Symbol", "\[Lambda]", <||>], {LeafNode["Symbol", name, <||>], body}, <||>]]
|>

LambdaSemantic = <|
    "Var" -> (Symbol[#] &),
    "App" -> Function[{f, x}, f[x]],
    "Abs" -> Function[{name, body}, makeAbs[name, body]]
|>

$astParser = LambdaGrammar[lambdaAstAlgebra]
$semParser = LambdaGrammar[LambdaSemantic]

LambdaAST[s_String] := With[{r = Parse[$astParser, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

LambdaEval[s_String] := Parse[$semParser, s]

End[]

EndPackage[]

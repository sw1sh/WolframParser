(* ::Package:: *)

(* :Title: Brainfuck.wl - an esoteric language that the parser also runs *)
(* :Context: Wolfram`Parser`Languages`Brainfuck` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The eight Brainfuck commands > < + - . , [ ] over a byte tape; every other
    character is a comment. Tiny lexically, but [ ] nests arbitrarily, so it
    exercises ParseRecursive and comment-skipping. The semantic algebra is the
    fun part: each command compiles to a Wolfram function machine -> machine, a
    sequence to their right-composition, and a loop to a NestWhile - so the
    parsed program IS an executable closure. Two runs:

      BrainfuckAST["+[>+]"]      -> standard AST (LeafNode commands, GroupNode["Loop", ..])
      BrainfuckRun["++++..."]    -> the program's output string

    BrainfuckRun["++++++[>++++++++++<-]>+++++.", ""] prints "A".
*)

BeginPackage["Wolfram`Parser`Languages`Brainfuck`", {"Wolfram`Parser`"}]

BrainfuckAST::usage = "BrainfuckAST[\"code\"] parses Brainfuck to a standard AST (a ContainerNode of LeafNode commands and GroupNode[\"Loop\", ..])."
BrainfuckRun::usage = "BrainfuckRun[\"code\"] or BrainfuckRun[\"code\", \"input\"] compiles Brainfuck to a Wolfram closure, runs it on a fresh byte tape, and returns the output string."
BrainfuckGrammar::usage = "BrainfuckGrammar[alg] builds the Brainfuck parser over the algebra alg."
BrainfuckSemantic::usage = "BrainfuckSemantic is the algebra that compiles Brainfuck to an executable machine -> machine closure."

Begin["`Private`"]

(* --- the executable machine, one Association threaded through closures --- *)
cell[m_]      := Lookup[m["tape"], m["ptr"], 0]
setCell[m_, v_] := <|m, "tape" -> <|m["tape"], m["ptr"] -> Mod[v, 256]|>|>

bfStep[">"] := Function[m, <|m, "ptr" -> m["ptr"] + 1|>]
bfStep["<"] := Function[m, <|m, "ptr" -> m["ptr"] - 1|>]
bfStep["+"] := Function[m, setCell[m, cell[m] + 1]]
bfStep["-"] := Function[m, setCell[m, cell[m] - 1]]
bfStep["."] := Function[m, <|m, "out" -> Append[m["out"], cell[m]]|>]
bfStep[","] := Function[m, If[m["in"] === {},
    setCell[m, 0],
    <|setCell[m, First[m["in"]]], "in" -> Rest[m["in"]]|>]]

bfLoop[body_] := Function[m, NestWhile[body, m, cell[#] != 0 &]]

BrainfuckGrammar[alg_] := Module[{junk, tok, simple, loop, item},
    item = RecCell[];
    junk = ParseRegex["[^><+.,\\[\\]-]*"];
    tok[p_] := ParseAction[p ~~ junk, #1 &];
    simple = SpannedToken[ParseRegex["[-><+.,]"], junk, alg["Op"]];
    loop   = ParseAction[
        tok @ ParseLiteral["["] ~~ ParseMany[RecRef[item]] ~~ tok @ ParseLiteral["]"],
        (alg["Loop"][#2]) &];
    SetRec[item, ParseChoice[simple, loop]];
    ParseAction[junk ~~ ParseMany[RecRef[item]], (alg["Seq"][#2]) &]
]

brainfuckAstAlgebra = <|
    "Op"   -> (LeafNode["Command", #, <||>] &),
    "Seq"  -> (# &),
    "Loop" -> (GroupNode["Loop", #, <||>] &)
|>

BrainfuckSemantic = <|
    "Op"   -> (bfStep[#] &),
    "Seq"  -> (RightComposition @@ # &),
    "Loop" -> (bfLoop[RightComposition @@ #] &)
|>

$astParser = BrainfuckGrammar[brainfuckAstAlgebra]
$semParser = BrainfuckGrammar[BrainfuckSemantic]

BrainfuckAST[s_String] := With[{r = Parse[$astParser, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

BrainfuckRun[code_String, input_String : ""] := With[{fn = Parse[$semParser, code]},
    If[FailureQ[fn], fn,
        FromCharacterCode @ Lookup[
            fn[<|"tape" -> <||>, "ptr" -> 0, "in" -> ToCharacterCode[input], "out" -> {}|>],
            "out"]]]

End[]

EndPackage[]

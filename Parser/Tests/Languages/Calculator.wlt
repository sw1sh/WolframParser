(* :Title: Calculator.wlt - calculator grammar tests *)
(* :Context: Wolfram`Parser`Languages`Calculator` *)
(* :Summary: precedence, associativity, parentheses, exact arithmetic, the
   symbolic fall-through, and the standard-AST shape. Run via run-tests.wls. *)

(* === semantics (the meaningful algebra) === *)
VerificationTest[CalculatorEval["1 + 2*3"], 7,
    TestID -> "calc: * binds tighter than +"]
VerificationTest[CalculatorEval["2^3^2"], 512,
    TestID -> "calc: ^ is right-associative"]
VerificationTest[CalculatorEval["1 - 2 - 3"], -4,
    TestID -> "calc: - is left-associative"]
VerificationTest[CalculatorEval["(1 + 2) * 3"], 9,
    TestID -> "calc: parentheses override precedence"]
VerificationTest[CalculatorEval["10/4"], 5/2,
    TestID -> "calc: division stays an exact rational"]
VerificationTest[CalculatorEval["-2^2"], 4,
    TestID -> "calc: unary minus binds tighter than ^ ((-2)^2)"]
VerificationTest[CalculatorEval["3*x - 2*x"], x,
    TestID -> "calc: identifiers stay symbolic and fold"]

(* === standard AST (the algebra-free output) === *)
VerificationTest[
    ASTStripSource @ CalculatorAST["1 + 2*3"],
    ContainerNode["String", {
        BinaryNode["+", {
            LeafNode["Integer", "1", <||>],
            BinaryNode["*", {LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>]
        }, <||>]}, <||>],
    TestID -> "calc: AST nests by precedence"]

VerificationTest[
    ASTStripSource @ CalculatorAST["-x"],
    ContainerNode["String", {PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>]}, <||>],
    TestID -> "calc: AST prefix minus"]

(* === source positions ({{line, col}, {line, col}}, CodeParser convention) === *)
VerificationTest[
    CalculatorAST["1+2"],
    ContainerNode["String", {
        BinaryNode["+", {
            LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>],
            LeafNode["Integer", "2", <|"Source" -> {{1, 3}, {1, 4}}|>]
        }, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>],
    TestID -> "calc: AST carries line/column Source, composites span their children"]

VerificationTest[
    Cases[CalculatorAST["1 +\n2"], LeafNode["Integer", "2", m_] :> m["Source"], Infinity],
    {{{2, 1}, {2, 2}}},
    TestID -> "calc: Source tracks column across a newline"]

(* === failure === *)
VerificationTest[Head @ CalculatorEval["1 +"], Failure,
    TestID -> "calc: incomplete input is a Failure"]

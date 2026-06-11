(* :Title: Brainfuck.wlt - Brainfuck tests *)
(* :Context: Wolfram`Parser`Languages`Brainfuck` *)
(* :Summary: the parser-as-compiler runs real programs (a loop that prints
   "A", an echo via ",", the canonical hello world), comments are ignored,
   and the standard-AST shape nests loops. Run via run-tests.wls. *)

(* === run the compiled closure (the meaningful algebra) === *)
VerificationTest[BrainfuckRun["++++++[>++++++++++<-]>+++++."], "A",
    TestID -> "bf: loop multiplies 6*10+5 = 65 = 'A'"]
VerificationTest[BrainfuckRun[",.", "Q"], "Q",
    TestID -> "bf: , reads input, . writes it (echo)"]
VerificationTest[
    BrainfuckRun["++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."],
    "Hello World!\n",
    TestID -> "bf: canonical hello world"]

(* === standard AST (the algebra-free output) === *)
VerificationTest[
    ASTStripSource @ BrainfuckAST["x+y"],
    ContainerNode["String", {LeafNode["Command", "+", <||>]}, <||>],
    TestID -> "bf: non-command characters are comments"]

VerificationTest[
    ASTStripSource @ BrainfuckAST["[>]"],
    ContainerNode["String", {
        GroupNode["Loop", {LeafNode["Command", ">", <||>]}, <||>]}, <||>],
    TestID -> "bf: loop AST nests its body in a GroupNode"]

VerificationTest[Head @ BrainfuckRun["[+"], Failure,
    TestID -> "bf: unbalanced bracket is a Failure"]

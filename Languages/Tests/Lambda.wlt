(* :Title: Lambda.wlt - untyped lambda calculus tests *)
(* :Context: Wolfram`Parser`Languages`Lambda` *)
(* :Summary: application/abstraction, the K and S-ish combinators, Church
   numeral application, capture-safe shadowing, and the standard-AST shape.
   Run via run-tests.wls. *)

(* === beta-reduction via native closures (the meaningful algebra) === *)
VerificationTest[LambdaEval["(\\x.x) y"], y,
    TestID -> "lambda: identity"]
VerificationTest[LambdaEval["(\\x.\\y.x) a b"], a,
    TestID -> "lambda: K combinator keeps the first argument"]
VerificationTest[LambdaEval["(\\x.\\y.y) a b"], b,
    TestID -> "lambda: K* keeps the second argument"]
VerificationTest[LambdaEval["(\\f.\\x.f (f x)) g y"], g[g[y]],
    TestID -> "lambda: Church-2 applies its function twice"]
VerificationTest[LambdaEval["(\\x.\\x.x) a b"], b,
    TestID -> "lambda: inner binder shadows the outer (capture-safe)"]
VerificationTest[LambdaEval["(\\x y.x) p q"], p,
    TestID -> "lambda: multi-binder sugar \\x y. = \\x.\\y."]

(* === standard AST (the algebra-free output) === *)
VerificationTest[
    ASTStripSource @ LambdaAST["\\x.x"],
    ContainerNode["String", {
        CallNode[LeafNode["Symbol", "\[Lambda]", <||>],
            {LeafNode["Symbol", "x", <||>], LeafNode["Symbol", "x", <||>]}, <||>]}, <||>],
    TestID -> "lambda: abstraction AST is a CallNode headed by lambda"]

VerificationTest[
    ASTStripSource @ LambdaAST["f x"],
    ContainerNode["String", {
        CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Symbol", "x", <||>]}, <||>]}, <||>],
    TestID -> "lambda: application AST is a CallNode"]

VerificationTest[Head @ LambdaEval["\\x."], Failure,
    TestID -> "lambda: missing body is a Failure"]

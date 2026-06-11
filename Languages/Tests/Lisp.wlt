(* :Title: Lisp.wlt - s-expression reader tests *)
(* :Context: Wolfram`Parser`Languages`Lisp` *)
(* :Summary: atoms, nesting, the quote reader macro, comments, multiple
   top-level forms, and the standard-AST shape. Run via run-tests.wls. *)

(* === read to native data (the meaningful algebra) === *)
VerificationTest[LispRead["(+ 1 2)"], {LispSymbol["+"], 1, 2},
    TestID -> "lisp: flat list reads to nested data"]
VerificationTest[LispRead["(+ 1 (max 2 3))"], {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}},
    TestID -> "lisp: nested list"]
VerificationTest[LispRead["'(a b)"], {LispSymbol["quote"], {LispSymbol["a"], LispSymbol["b"]}},
    TestID -> "lisp: quote reader macro expands to (quote ..)"]
VerificationTest[LispRead["3.5"], 3.5,
    TestID -> "lisp: real atom"]
VerificationTest[LispRead["(a) ; comment\n(b)"], {{LispSymbol["a"]}, {LispSymbol["b"]}},
    TestID -> "lisp: comments skipped, two top-level forms"]
VerificationTest[LispRead["()"], {},
    TestID -> "lisp: empty list"]

(* === standard AST (the algebra-free output) === *)
VerificationTest[
    ASTStripSource @ LispAST["(f x)"],
    ContainerNode["String", {
        CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Symbol", "x", <||>]}, <||>]}, <||>],
    TestID -> "lisp: list AST is a CallNode (head + args)"]

VerificationTest[
    ASTStripSource @ LispAST["'x"],
    ContainerNode["String", {PrefixNode["'", LeafNode["Symbol", "x", <||>], <||>]}, <||>],
    TestID -> "lisp: quote AST is a PrefixNode"]

VerificationTest[Head @ LispRead["(a b"], Failure,
    TestID -> "lisp: unbalanced parens is a Failure"]

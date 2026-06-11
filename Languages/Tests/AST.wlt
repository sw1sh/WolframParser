(* :Title: AST.wlt - standard AST vocabulary tests *)
(* :Context: Wolfram`Parser` *)
(* :Summary: the shared algebra builders, the container/leaf predicates, and
   the best-effort projection onto CodeParser-exact nodes. Run via run-tests.wls. *)

VerificationTest[ASTAlgebra["Binary"]["+", a, b], BinaryNode["+", {a, b}, <||>],
    TestID -> "ast: Binary builder"]
VerificationTest[ASTAlgebra["Leaf"]["Integer", "7"], LeafNode["Integer", "7", <||>],
    TestID -> "ast: Leaf builder"]
VerificationTest[ASTAlgebra["Call"][h, {x, y}], CallNode[h, {x, y}, <||>],
    TestID -> "ast: Call builder"]

VerificationTest[ASTContainer[{LeafNode["Integer", "1", <||>]}],
    ContainerNode["String", {LeafNode["Integer", "1", <||>]}, <||>],
    TestID -> "ast: ASTContainer wraps a list of forms"]
VerificationTest[ASTContainer[LeafNode["Integer", "1", <||>]],
    ContainerNode["String", {LeafNode["Integer", "1", <||>]}, <||>],
    TestID -> "ast: ASTContainer wraps a single form"]

VerificationTest[ASTLeafQ[LeafNode["x", "y", <||>]], True,
    TestID -> "ast: ASTLeafQ on a leaf"]
VerificationTest[ASTNodeQ[GroupNode["Paren", {}, <||>]], True,
    TestID -> "ast: ASTNodeQ on a group"]
VerificationTest[ASTNodeQ[42], False,
    TestID -> "ast: ASTNodeQ rejects a non-node"]

(* projection onto CodeParser`-exact nodes, mapping the operator descriptor *)
VerificationTest[
    ToCodeParser[
        BinaryNode["+", {LeafNode["Integer", "1", <||>], LeafNode["Integer", "2", <||>]}, <||>],
        <|"+" -> Plus|>],
    CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>],
        {CodeParser`LeafNode[Integer, "1", <||>], CodeParser`LeafNode[Integer, "2", <||>]}, <||>],
    TestID -> "ast: ToCodeParser maps a binary op to its Wolfram symbol"]

VerificationTest[
    ASTStripSource[BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]],
    BinaryNode["+", {LeafNode["Integer", "1", <||>]}, <||>],
    TestID -> "ast: ASTStripSource clears every Source"]

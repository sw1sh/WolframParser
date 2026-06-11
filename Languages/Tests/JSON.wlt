(* :Title: JSON.wlt - JSON grammar tests *)
(* :Context: Wolfram`Parser`Languages`JSON` *)
(* :Summary: scalars, nesting, escapes, exact vs real numbers, empty
   collections, and the standard-AST shape. Run via run-tests.wls. *)

(* === native import (the meaningful algebra) === *)
VerificationTest[JSONImport["42"], 42,
    TestID -> "json: bare integer"]
VerificationTest[JSONImport["-3.5e2"], -350.,
    TestID -> "json: real with exponent"]
VerificationTest[JSONImport["[1, 2, 3]"], {1, 2, 3},
    TestID -> "json: array -> List"]
VerificationTest[JSONImport["{\"a\": 1, \"b\": [true, null]}"],
    <|"a" -> 1, "b" -> {True, Null}|>,
    TestID -> "json: object -> Association, nested array"]
VerificationTest[JSONImport["\"a\\nb\""], "a\nb",
    TestID -> "json: string escape decoded"]
VerificationTest[JSONImport["{}"], <||>,
    TestID -> "json: empty object"]
VerificationTest[JSONImport["[]"], {},
    TestID -> "json: empty array"]

(* === standard AST (the algebra-free output) === *)
VerificationTest[
    ASTStripSource @ JSONAST["[1, true]"],
    ContainerNode["String", {
        GroupNode["Array", {
            LeafNode["Integer", "1", <||>],
            LeafNode["Boolean", "true", <||>]
        }, <||>]}, <||>],
    TestID -> "json: array AST"]

VerificationTest[
    ASTStripSource @ JSONAST["{\"k\": 2}"],
    ContainerNode["String", {
        GroupNode["Object", {
            BinaryNode[":", {LeafNode["String", "\"k\"", <||>], LeafNode["Integer", "2", <||>]}, <||>]
        }, <||>]}, <||>],
    TestID -> "json: object member AST keeps the raw quoted key"]

VerificationTest[Head @ JSONImport["{bad}"], Failure,
    TestID -> "json: malformed input is a Failure"]

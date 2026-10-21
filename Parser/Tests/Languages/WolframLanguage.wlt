(* :Title: WolframLanguage.wlt - Wolfram Language grammar tests *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Summary: each form below read by WolframLanguageHeld, against what
   Wolfram 15's ImportString[s, {"WL", "HeldExpressions"}] gives for it
   (recorded once from the kernel, then frozen here); how a source splits
   into its top-level expressions; the grammar reading the zoo's own
   sources as the kernel does; the standard AST; and failures. Run via
   run-tests.wls. *)

ClearAll[$wlCases, $wlZoo]

(* {source, the list of held expressions Wolfram 15 reads from it} *)
$wlCases = {
    {"-a b", List[HoldComplete[Times[Times[-1, a], b]]]},
    {"-a/b", List[HoldComplete[Times[Times[-1, a], Power[b, -1]]]]},
    {"a/b c", List[HoldComplete[Times[Times[a, Power[b, -1]], c]]]},
    {"a b/c", List[HoldComplete[Times[a, Times[b, Power[c, -1]]]]]},
    {"-2 a", List[HoldComplete[Times[-2, a]]]},
    {"- 2", List[HoldComplete[-2]]},
    {"-(2)", List[HoldComplete[-2]]},
    {"-a^2", List[HoldComplete[Times[-1, Power[a, 2]]]]},
    {"a - b + c", List[HoldComplete[Plus[a, Times[-1, b], c]]]},
    {"a - -b", List[HoldComplete[Plus[a, Times[-1, Times[-1, b]]]]]},
    {"!a && b", List[HoldComplete[And[Not[a], b]]]},
    {"a.b.c", List[HoldComplete[Dot[a, b, c]]]},
    {"a**b**c", List[HoldComplete[NonCommutativeMultiply[a, b, c]]]},
    {"x_:0", List[HoldComplete[Optional[Pattern[x, Blank[]], 0]]]},
    {"x:_", List[HoldComplete[Pattern[x, Blank[]]]]},
    {"x:a_:0", List[HoldComplete[Optional[Pattern[x, Pattern[a, Blank[]]], 0]]]},
    {"a|b|c", List[HoldComplete[Alternatives[a, b, c]]]},
    {"a~f~b~g~c", List[HoldComplete[g[f[a, b], c]]]},
    {"f@g@x", List[HoldComplete[f[g[x]]]]},
    {"x//f//g", List[HoldComplete[g[f[x]]]]},
    {"a;;b", List[HoldComplete[Span[a, b]]]},
    {";;", List[HoldComplete[Span[1, All]]]},
    {"a;;", List[HoldComplete[Span[a, All]]]},
    {"a;;b;;c", List[HoldComplete[Span[a, b, c]]]},
    {";;;;2", List[HoldComplete[Span[1, All, 2]]]},
    {"a;;;;c", List[HoldComplete[Span[a, All, c]]]},
    {"a;b;", List[HoldComplete[CompoundExpression[a, b, Null]]]},
    {"a;;b+1", List[HoldComplete[Span[a, Plus[b, 1]]]]},
    {"a<b<=c", List[HoldComplete[Inequality[a, Less, b, LessEqual, c]]]},
    {"a<b<c", List[HoldComplete[Less[a, b, c]]]},
    {"a==b==c", List[HoldComplete[Equal[a, b, c]]]},
    {"a===b=!=c", List[HoldComplete[UnsameQ[SameQ[a, b], c]]]},
    {"f'[x]", List[HoldComplete[Derivative[1][f][x]]]},
    {"f''", List[HoldComplete[Derivative[2][f]]]},
    {"a::b::c", List[HoldComplete[MessageName[a, "b", "c"]]]},
    {"x_?f[y]", List[HoldComplete[PatternTest[Pattern[x, Blank[]], f][y]]]},
    {"f[a][b][[1]]", List[HoldComplete[Part[f[a][b], 1]]]},
    {"a=b=c", List[HoldComplete[Set[a, Set[b, c]]]]},
    {"a:=b", List[HoldComplete[SetDelayed[a, b]]]},
    {"t/:a=b", List[HoldComplete[TagSet[t, a, b]]]},
    {"x=.", List[HoldComplete[Unset[x]]]},
    {"a->b->c", List[HoldComplete[Rule[a, Rule[b, c]]]]},
    {"a/.b/.c", List[HoldComplete[ReplaceAll[ReplaceAll[a, b], c]]]},
    {"a//.b", List[HoldComplete[ReplaceRepeated[a, b]]]},
    {"a&", List[HoldComplete[Function[a]]]},
    {"#+1&", List[HoldComplete[Function[Plus[Slot[1], 1]]]]},
    {"#1 ##2 #a", List[HoldComplete[Times[Slot[1], SlotSequence[2], Slot["a"]]]]},
    {"%%%", List[HoldComplete[Out[-3]]]},
    {"%3", List[HoldComplete[Out[3]]]},
    {"x_.", List[HoldComplete[Optional[Pattern[x, Blank[]]]]]},
    {"f@@x", List[HoldComplete[Apply[f, x]]]},
    {"f@@@x", List[HoldComplete[MapApply[f, x]]]},
    {"f/@g/@x", List[HoldComplete[Map[f, Map[g, x]]]]},
    {"a<>b<>c", List[HoldComplete[StringJoin[a, b, c]]]},
    {"a^b^c", List[HoldComplete[Power[a, Power[b, c]]]]},
    {"a!", List[HoldComplete[Factorial[a]]]},
    {"a!!", List[HoldComplete[Factorial2[a]]]},
    {"!!a", List[HoldComplete[Not[Not[a]]]]},
    {"a++", List[HoldComplete[Increment[a]]]},
    {"++a", List[HoldComplete[PreIncrement[a]]]},
    {"a--b", List[HoldComplete[Times[Decrement[a], b]]]},
    {"a@*b@*c", List[HoldComplete[Composition[a, b, c]]]},
    {"a/*b/*c", List[HoldComplete[RightComposition[a, b, c]]]},
    {"1.5`10", List[HoldComplete[1.5`10.]]},
    {"2^^101", List[HoldComplete[5]]},
    {"1*^3", List[HoldComplete[1000]]},
    {"\"s\\n\"", List[HoldComplete["s\n"]]},
    {"a\\[Rule]b", List[HoldComplete[Rule[a, b]]]},
    {"f[x_]/;x>0:=1", List[HoldComplete[SetDelayed[Condition[f[Pattern[x, Blank[]]], Greater[x, 0]], 1]]]},
    {"{a,,b}", List[HoldComplete[List[a, Null, b]]]},
    {"f[,]", List[HoldComplete[f[Null, Null]]]},
    {"<|a->1|>", List[HoldComplete[Association[Rule[a, 1]]]]},
    {"a + b // f", List[HoldComplete[f[Plus[a, b]]]]},
    {"a = b // f", List[HoldComplete[Set[a, f[b]]]]},
    {"f@x + 1", List[HoldComplete[Plus[f[x], 1]]]},
    {"a||b&&c", List[HoldComplete[Or[a, And[b, c]]]]},
    {"x|->x+1", List[HoldComplete[Function[x, Plus[x, 1]]]]},
    {"a<->b", List[HoldComplete[TwoWayRule[a, b]]]},
    {"-1^2", List[HoldComplete[Times[-1, Power[1, 2]]]]},
    {"-a!", List[HoldComplete[Times[-1, Factorial[a]]]]},
    {"a b c", List[HoldComplete[Times[a, b, c]]]},
    {"2x y", List[HoldComplete[Times[2, x, y]]]},
    {"a*b*c", List[HoldComplete[Times[a, b, c]]]},
    {"a*-b", List[HoldComplete[Times[a, Times[-1, b]]]]},
    {"(a b) c", List[HoldComplete[Times[Times[a, b], c]]]},
    {"a (b c)", List[HoldComplete[Times[a, Times[b, c]]]]},
    {"+a", List[HoldComplete[Plus[a]]]},
    {"+1", List[HoldComplete[Plus[1]]]},
    {"a=-1", List[HoldComplete[Set[a, -1]]]},
    {"1/2", List[HoldComplete[Times[1, Power[2, -1]]]]},
    {"a^-1", List[HoldComplete[Power[a, -1]]]},
    {"-x^2", List[HoldComplete[Times[-1, Power[x, 2]]]]},
    {"a-b-c", List[HoldComplete[Plus[a, Times[-1, b], Times[-1, c]]]]},
    {"a.b+c", List[HoldComplete[Plus[Dot[a, b], c]]]},
    {"x:a|b", List[HoldComplete[Pattern[x, Alternatives[a, b]]]]},
    {"a:b:c", List[HoldComplete[Optional[Pattern[a, b], c]]]},
    {"_:0", List[HoldComplete[Optional[Blank[], 0]]]},
    {"p:_|_", List[HoldComplete[Pattern[p, Alternatives[Blank[], Blank[]]]]]},
    {"a_b:c", List[HoldComplete[Optional[Pattern[a, Blank[b]], c]]]},
    {"#&@x", List[HoldComplete[Function[Slot[1]][x]]]},
    {"f[[1,2]]", List[HoldComplete[Part[f, 1, 2]]]},
    {"f[[1]][[2]]", List[HoldComplete[Part[Part[f, 1], 2]]]},
    {"a[[1;;2]]", List[HoldComplete[Part[a, Span[1, 2]]]]},
    {"Integer::foo", List[HoldComplete[MessageName[Integer, "foo"]]]},
    {"a::b::\"c\"", List[HoldComplete[MessageName[a, "b", "c"]]]},
    {"x>>f", List[HoldComplete[Put[x, "f"]]]},
    {"<<f", List[HoldComplete[Get["f"]]]},
    {"a~~b~~c", List[HoldComplete[StringExpression[a, b, c]]]},
    {"a~~(b~~c)", List[HoldComplete[StringExpression[a, StringExpression[b, c]]]]},
    {"a+(b+c)", List[HoldComplete[Plus[a, Plus[b, c]]]]},
    {"a@b[c]", List[HoldComplete[a[b[c]]]]},
    {"a'b", List[HoldComplete[Times[Derivative[1][a], b]]]},
    {"a /; b /; c", List[HoldComplete[Condition[Condition[a, b], c]]]},
    {"a :> b /; c", List[HoldComplete[RuleDelayed[a, Condition[b, c]]]]},
    {"f[x]&[1]", List[HoldComplete[Function[f[x]][1]]]},
    {"a^b'", List[HoldComplete[Power[a, Derivative[1][b]]]]},
    {"f'[x]^2", List[HoldComplete[Power[Derivative[1][f][x], 2]]]},
    {"a\\[Function]b", List[HoldComplete[Function[a, b]]]},
    {"x\\[Element]y", List[HoldComplete[Element[x, y]]]},
    {"\\[Alpha]\\[Beta] x", List[HoldComplete[Times[\[Alpha]\[Beta], x]]]},
    {"a\\[Equal]b", List[HoldComplete[Equal[a, b]]]},
    {"16^^ff.8", List[HoldComplete[255.5`]]},
    {"2.5`20 x", List[HoldComplete[Times[2.5`20., x]]]},
    {"1``10", List[HoldComplete[1.`10.]]},
    {"#name", List[HoldComplete[Slot["name"]]]},
    {"##", List[HoldComplete[SlotSequence[1]]]},
    {"%", List[HoldComplete[Out[]]]},
    {"%%", List[HoldComplete[Out[-2]]]},
    {"f::usage = \"text\"", List[HoldComplete[Set[MessageName[f, "usage"], "text"]]]},
    {"t::[a, b]", List[HoldComplete[TypeSpecifier[t][a, b]]]},
    {"x >>> f", List[HoldComplete[PutAppend[x, "f"]]]},
    {"<<Foo`", List[HoldComplete[Get["Foo`"]]]},
    {"t /: f[t] := 1", List[HoldComplete[TagSetDelayed[t, f[t], 1]]]},
    {"t /: f[t] =.", List[HoldComplete[TagUnset[t, f[t]]]]},
    {"a /@ b @@ c", List[HoldComplete[Map[a, Apply[b, c]]]]},
    {"Integer[[1]]", List[HoldComplete[Part[Integer, 1]]]},
    {"f[x_.]", List[HoldComplete[f[Optional[Pattern[x, Blank[]]]]]]},
    {"x__Integer", List[HoldComplete[Pattern[x, BlankSequence[Integer]]]]},
    {"_h", List[HoldComplete[Blank[h]]]},
    {"x:_:0", List[HoldComplete[Optional[Pattern[x, Blank[]], 0]]]},
    {"a ;; b ;; c", List[HoldComplete[Span[a, b, c]]]},
    {"f[a;; , 1]", List[HoldComplete[f[Span[a, All], 1]]]},
    {"{;;}", List[HoldComplete[List[Span[1, All]]]]},
    {"(a; b)", List[HoldComplete[CompoundExpression[a, b]]]},
    {"a\n+ b", List[HoldComplete[a], HoldComplete[Plus[b]]]},
    {"{a\n+ b}", List[HoldComplete[List[Plus[a, b]]]]}
};

(* === forms: precedence, flat chains, minus and quotients, patterns, spans === *)
Scan[
    Function[c, VerificationTest[WolframLanguageHeld[c[[1]]], c[[2]], TestID -> "wl: " <> c[[1]]]],
    $wlCases]

(* === a source: newlines end expressions outside brackets, comments are whitespace === *)
VerificationTest[
    WolframLanguageHeld["a = 1;\n(* c *)\nb\n\nc;\nd +\n e\nf (* x *)\n(* y *)"],
    {HoldComplete[a = 1;], HoldComplete[b], HoldComplete[c;], HoldComplete[d + e], HoldComplete[f]},
    TestID -> "wl: statements split at newlines, not after an operator"]
VerificationTest[
    WolframLanguageHeld["f[x_] :=\n\tModule[{y = x},\n\t\ty (* (* nested *) comment *) + 1\n\t]\n"],
    {HoldComplete[f[x_] := Module[{y = x}, y + 1]]},
    TestID -> "wl: newlines inside brackets, nested comments"]
VerificationTest[WolframLanguageHeld[""], {}, TestID -> "wl: empty source"]

(* === the zoo's own sources read as the kernel reads them === *)
$wlZoo = FileNames["*.wl", FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages"}]];
Scan[
    Function[f, With[{s = Import[f, "Text"]},
        VerificationTest[WolframLanguageHeld[s], ImportString[s, {"WL", "HeldExpressions"}],
            TestID -> "wl: reads " <> FileNameTake[f]]]],
    $wlZoo]

(* === standard AST === *)
VerificationTest[
    ASTStripSource @ WolframLanguageAST["f[x_] := a - b c"],
    ContainerNode["String", {
        BinaryNode["SetDelayed", {
            CallNode[LeafNode["Symbol", "f", <||>], {LeafNode["Blank", "x_", <||>]}, <||>],
            InfixNode["Plus", {
                LeafNode["Symbol", "a", <||>],
                PrefixNode["Minus", InfixNode["Times", {LeafNode["Symbol", "b", <||>], LeafNode["Symbol", "c", <||>]}, <||>], <||>]
            }, <||>]
        }, <||>]}, <||>],
    TestID -> "wl: AST names operators by their heads"]
VerificationTest[
    WolframLanguageAST["a +\n  b"][[2, 1, 3, "Source"]],
    {{1, 1}, {2, 4}},
    TestID -> "wl: AST spans cross lines"]
VerificationTest[
    ASTStripSource @ WolframLanguageAST["a < b <= c"],
    ContainerNode["String", {InfixNode["Inequality", {
        LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "Less", <||>], LeafNode["Symbol", "b", <||>],
        LeafNode["Symbol", "LessEqual", <||>], LeafNode["Symbol", "c", <||>]}, <||>]}, <||>],
    TestID -> "wl: AST of a mixed relation chain"]

(* === failures === *)
VerificationTest[FailureQ[WolframLanguageHeld["a = 1\nb = (c"]], True, TestID -> "wl: an unclosed bracket fails"]
VerificationTest[
    WolframLanguageHeld["a = 1\nb c)\nd"]["Position"],
    10,
    TestID -> "wl: a failure points into the statement that cannot be read"]
VerificationTest[
    WolframLanguageHeld["a +"]["Expected"],
    "<expression>",
    TestID -> "wl: a missing operand is named"]

#!/usr/bin/env wolframscript
(* Records what Wolfram 15's CodeParser`CodeConcreteParse gives for the
   forms of the concrete syntax tree tests into
   Parser/Tests/Languages/WolframLanguageConcrete.wlt, between its
   "BEGIN frozen" and "END frozen" lines, so the tests run on a kernel
   without CodeParser. Run it with Wolfram 15 after changing the forms:
       wl -f dev/freeze-concrete.wls
   The container's SyntaxIssues, diagnostics WolframLanguageConcrete does
   not give, are left out. *)

$ProgressReporting = False;
Needs["CodeParser`"];

root = ParentDirectory[DirectoryName[$InputFileName]];
testFile = FileNameJoin[{root, "Parser", "Tests", "Languages", "WolframLanguageConcrete.wlt"}];

(* each form's tree, Source dropped *)
forms = {
    "a", "f[x]", "f [x]", "f[]", "f[ ]", "f[\n]", "f[a, b, c]", "f[x, ]", "f[ , x]", "f[,]", "f[x ,]", "{a, ,b}", "{a,b,}", "{ }",
    "f[x][y]", "a[[1]]", "a[[1, 2]]", "{a, b}[[1]]", "a::[b]", "<||>", "<|a -> 1|>", "<|\n|>", "(a\n)", "{\n}", "f[a\n,\nb]",
    "a + b - c", "a - -b", "a + -b", "a b c", "a*b c", "a b*c", "-a b", "2 -a", "-a^b", "a^-b", "a^b^c", "a/b/c", "a + b * c ^ d",
    "a(*c*)b", "(a\nb)", "a.b.c", "a. b", "1.2.3", "a ** b ** c", "a<>b<>c", "a@*b@*c", "a/*b",
    "a<b<=c", "a == b", "a != b", "a==b===c", "a === b =!= c", "a&&!b", "a || b", "!a!", "!!a", "a!!", "a!!b", "a!=!b",
    "x_", "x_h", "x__", "x___h", "_", "__", "___", "_h", "___h", "_.", "x_.", "x_:0", "x:_:0", "_:0", "x:a:b", "x:(_|_)", "x:_.",
    "a_?b", "x_Integer?Positive", "f[x_?NumericQ]", "a|b|c", "x_ /; y", "f[x_] := y /; z", "f[x_:y]", "_h..", "x__..",
    "#", "#2", "#name", "#\"n\"", "##", "##2", "#1&[x]", "%", "%%", "%%%", "%3",
    "a -> b -> c", "a :> b", "{a->b, c:>d}", "a /. b -> c", "a //. b", "a = b = c", "a := b", "a ^= b", "a ^:= b", "a += b", "a -= b",
    "a *= b", "a /= b", "a =.", "a = .", "a=.5", "a =\n.", "t/:a=b", "t/:a:=b", "t/:a=.", "a /: b\n = c",
    "a|->b", "f@g@x", "a // f // g", "f /@ x", "a//@b", "f@@g@@x", "f@@@x", "a~f~b~g~c", "a ~f\n~ b", "f'", "f'''", "f'[x]", "a''[x]",
    "a++", "a--", "++a", "--a", "a ++ b", "a & b", "f[x]&", "{a&, b}", "a..", "a...",
    "a;;b", ";;", "a;;", ";;b", "a;;b;;c", "a;;;;c", "a ;; ;; b", "a;; ", "a;;\n", "f[x ;; y]",
    "a;b;", "a; ", "a;\n", "a; \nb", "a;(*c*)\nb", "Hold[a; ]", "a ; b ; ", "a;;;", "a;;;b", "a; b\n; c",
    "a::b", "a::b::c", "a::\"b\"", "a::b[c]", "a::b\n::c", "<<file", "<< \"f\"", "<<a`b`", "a>>b", "a >> \"b\"", "a>>>b",
    "a\nb", "a\n+b", "a + b\n + c", "a + b\n - c", "a*b\nc", "a b\nc", "a b\n*c", "a == b\n < c", "a.b\n.c", "{a\n+b}",
    "f[x]\n[y]", "a (*c*)\nb", "a\n\nb", "(*c*)\na", "a(*c*)", "f(*c*)[x]", "f[(*c*)x]", "(* (* *) *)", "a\r\nb", "\ta", " a", "a \n", "",
    "16^^ff", "2*^3", "1*^-3", "1.5*^3", "1.5``10", "1`", "1`20", "1.5`-3", ".5", "1.", "0.", "00", "123456789012345678901234567890",
    "\"a\\\"b\"", "\"a\nb\"", "\"\\n\"", "\"\\[Alpha]\"", "\"(*a*)\"", "\"c\\\nd\"", "\"a\tb\"", "(*\t\n*)",
    "\\[Alpha]x", "a \\[Element] b", "a \\[Rule] b", "a\\[Times]b", "x \\[Function] y", "a \\[DirectedEdge] b", "a \\[Equal] b",
    "$x", "a`b", "`a", "a`b`c", "Function[x, x]&", "f[n_Integer?Positive] := n f[n - 1]; f[0] = 1; f[20]"
};

(* whole containers, Source included *)
containerForms = {
    "f[x_] := x^2 (* c *)\n", "a; \nb", "a b", "f[x, ]", ";;b", "{1, 2}[[1]]", "a\r\nb", "\ta\tb", "x\n(* a\n b *)\n\n",
    "\"a\nb\" (*\t*)", "\"c\\\nd\"", "\\[Alpha]b \\[Rule] c", "a +\n  b"
};

dropIssues[c_] := MapAt[KeyDrop[#, CodeParser`SyntaxIssues] &, c, 3]
noSource[t_] := t /. a_Association :> KeyDrop[a, CodeParser`Source]
shown[e_] := Block[{$ContextPath = {"System`"}}, ToString[e, InputForm, CharacterEncoding -> "ASCII"]]
entries[list_, f_] := StringRiffle[Map["    {" <> shown[#] <> ", " <> shown[f[#]] <> "}" &, list], ",\n"]

block = StringJoin[
    "$concreteTrees = {\n", entries[forms, noSource[dropIssues[CodeConcreteParse[#]]] &], "\n};\n\n",
    "$concreteContainers = {\n", entries[containerForms, dropIssues[CodeConcreteParse[#]] &], "\n};\n"];

text = ByteArrayToString[ReadByteArray[testFile], "UTF-8"];
If[ ! StringContainsQ[text, "(* BEGIN frozen" ~~ Shortest[___] ~~ "(* END frozen *)"],
    Print["no BEGIN frozen / END frozen lines in ", testFile]; Exit[1]];
updated = StringReplace[text,
    start : ("(* BEGIN frozen" ~~ Shortest[___] ~~ "*)\n") ~~ Shortest[___] ~~ end : "(* END frozen *)" :> start <> block <> end, 1];
With[{stream = OpenWrite[testFile, CharacterEncoding -> "UTF-8"]}, WriteString[stream, updated]; Close[stream]];
Print["froze ", Length[forms], " trees and ", Length[containerForms], " containers into ", testFile];

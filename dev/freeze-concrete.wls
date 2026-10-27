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
    "a *= b", "a /= b", "a //= f //= g", "a =.", "a = .", "a=.5", "a =\n.", "t/:a=b", "t/:a:=b", "t/:a=.", "a /: b\n = c",
    "a|->b", "f@g@x", "a // f // g", "f /@ x", "a//@b", "f@@g@@x", "f@@@x", "a~f~b~g~c", "a ~f\n~ b", "f'", "f'''", "f'[x]", "a''[x]",
    "a++", "a--", "++a", "--a", "a ++ b", "a & b", "f[x]&", "{a&, b}", "a..", "a...",
    "a;;b", ";;", "a;;", ";;b", "a;;b;;c", "a;;;;c", "a ;; ;; b", "a;; ", "a;;\n", "f[x ;; y]",
    "a ;; b ;; c ;; d", "a ;; b ;; ;; c ;; d", "a;;b;;c;;", ";; ;; ;;", "f[a ;; b ;;]", "a ;; !b", "a ;; !!b", "a ;; b ;; !c", "a ;; !b ;; c",
    "a ;; !b && c", "a ;; \\[Not]b", "a ;; \\[Minus]b", "a ;; \\[Sum]b", "a ;; b * !c", "a ;; -> b", "a ;; != b", "a ;; ++b", "a ;; - b",
    "a;b;", "a; ", "a;\n", "a; \nb", "a;(*c*)\nb", "Hold[a; ]", "a ; b ; ", "a;;;", "a;;;b", "a; b\n; c",
    "a; !b", "a; -> b", "a; != b", "a; - b",
    "a::b", "a::b::c", "a::\"b\"", "a::b[c]", "a::b\n::c", "<<file", "<< \"f\"", "<<a`b`", "a>>b", "a >> \"b\"", "a>>>b",
    "<<a\\b", "<<a!b", "<<a*b?c", "<<a\\[Alpha]b", "<<a\\:0041b", "x >> a\\b", "<<a\\ b",
    "a\nb", "a\n+b", "a + b\n + c", "a + b\n - c", "a*b\nc", "a b\nc", "a b\n*c", "a == b\n < c", "a.b\n.c", "{a\n+b}",
    "f[x]\n[y]", "a (*c*)\nb", "a\n\nb", "(*c*)\na", "a(*c*)", "f(*c*)[x]", "f[(*c*)x]", "(* (* *) *)", "a\r\nb", "\ta", " a", "a \n", "",
    "16^^ff", "2*^3", "1*^-3", "1.5*^3", "1.5``10", "1`", "1`20", "1.5`-3", ".5", "1.", "0.", "00", "123456789012345678901234567890",
    "\"a\\\"b\"", "\"a\nb\"", "\"\\n\"", "\"\\[Alpha]\"", "\"(*a*)\"", "\"c\\\nd\"", "\"a\tb\"", "(*\t\n*)",
    "\\[Alpha]x", "a \\[Element] b", "a \\[Rule] b", "a\\[Times]b", "x \\[Function] y", "a \\[DirectedEdge] b", "a \\[Equal] b",
    "$x", "a`b", "`a", "a`b`c", "Function[x, x]&", "f[n_Integer?Positive] := n f[n - 1]; f[0] = 1; f[20]"
};

(* source that is not Wolfram Language: an operand left out, a group not
   closed, a closer that closes none, error tokens, syntax errors *)
errorForms = {
    "a +", "a + ", "a +\n", "-", "!", "a =", "a = = b", "a * * b", "&&a", "@a", "a//", "x_:", "x:", "a ~f~", "a.b.", "f[;]", "(;)",
    "?a", "a\n=b", "a + )", "f[a +]", "a; b +", "a;; b +", "f[a, b +]",
    "f[x", "f[x,", "f[", "{a, b", "(a", "<|a", "f[[1]", "a[[1", "f[g[x", "{a, {b", "(a + (b", "(\n", "f[x ", "f[x (* c *)",
    "f[x)", "(a]", "{a)", "(a]b", "(a]+b", "{a, (b]}", "f[(a]]", "[a)", "{(a + b]}", "{(a + b]", "f[a (b + c]]", "(a + b]c + d)", "(a]b]c)", "{f[a)}",
    "f[x]]", "a)", ")", "]", "}", "|>", "a]b", "f[x]\n]", "(* a *) ]", "f[a, ] ]",
    "\"abc", "\"abc\ndef", "(* abc", "x \"abc", "f[x, \"abc", "f[x (* abc", "1``", "16^^", "1*^", "2^^3", "37^^1", "1.5``",
    "??a", "a ?? b", "x + ??", "x + ?? b", "x + ?? + y", "?? + y", "f[??, a]", "f[a ??]", "f[a, ??]", "f[a ?? b]",
    "\\[Foo]", "\\[Alpha", "\\:00", "a \\", "a\\[Foo]b", "{\\[Foo], 1}", "f[a, \\]", "`", "a``b", "a`1", "1`2`3", "x + a` b", "f[a`, b]",
    "a ~f", "a ~ b", "a ~f~ b ~g", "a /: b", "a /: b c", "a /: ??", "f[x]:y", "1:2", "x_.:0", "(x_):0", "#:0", "x_:1:2",
    "a::", "a::1", "a::b::", "a :: b", "a::??", "a::\"b", "<<", "<< ", "a >>", "<<\"a", "a >> \"b", "<<a\\[b",
    "a,b", ",", ",a", "a,", "a,\nb", "a\n,b", "a, b\n, c", "{,}", "{a,,b}", "f[a,, ]",
    "a;;b;;", "a;;;;", "a; ;b", "a; ;", "a; ??", "a; )", "a; \"abc", "a;; ??", "f[a; )]", "#\"a", "a ;; !", "a ;; ++", "f[a ;; !]", "a ;; b ;; !", "a;!", "a; ++", "f[a;!]", "=[b]", "a=[b, c]", "x = =[b]", "(* a \\*) b", "(* ::Package:: \\*)"
};

(* long names that are no letters: operators, brackets, integrals,
   whitespace and newlines, and what CodeParser does not read *)
longNameForms = {
    (* operators, spelled as long names and as their characters *)
    "a \\[RightArrow] b \\[LeftArrow] c", "a \\[Union] b \\[Intersection] c", "a + b \\[PlusMinus] c", "a \\[Minus] b + c", "\\[Minus] a",
    "a \\[InvisibleTimes] b c", "a \\[Element] b \\[Subset] c", "a < b \\[LessLess] c", "a \\[Cross] b \\[Cross] c", "\\[Not] a && b",
    "a \\[Implies] b \\[Implies] c", "a\\[Transpose]\\[Conjugate]", "\\[ForAll] x", "a \\[Divides] b", "a \\[Divide] b / c",
    "a \\[Therefore] b \\[Therefore] c", "a \\[Because] b \\[Because] c", "\\[Sum] a + b", "a \\[CircleTimes] \\[CircleTimes] b", "\\[Sqrt] 2 x",
    "a\[RightTriangle]b", "a\[VerticalTilde]b", "a \[Times] b \[CenterDot] c", "\[Not]a", "a\[Transpose]", "\\[Del] f", "a\[Rule]b\[RuleDelayed]c",
    (* brackets and calls *)
    "\\[LeftAngleBracket]a, b\\[RightAngleBracket]", "\\[LeftFloor]x\\[RightFloor]", "\\[LeftCeiling]x\\[RightCeiling]", "\\[LeftBracketingBar]x\\[RightBracketingBar]",
    "\\[LeftDoubleBracketingBar]x\\[RightDoubleBracketingBar]", "\\[LeftAssociation]a -> 1\\[RightAssociation]", "\\[OpenCurlyQuote]a\\[CloseCurlyQuote]",
    "\\[OpenCurlyDoubleQuote]a\\[CloseCurlyDoubleQuote]", "\\[LeftDoubleBracket]a\\[RightDoubleBracket]", "f\\[LeftDoubleBracket]1, 2\\[RightDoubleBracket]",
    "\[LeftAngleBracket]a\[RightAngleBracket]", "f\[LeftDoubleBracket]1\[RightDoubleBracket]", "\[LeftFloor]x\[RightFloor] + 1",
    (* brackets left open, and closers that close none *)
    "\\[LeftAngleBracket]a", "{a\\[RightAngleBracket]}", "\\[LeftCeiling]a]", "f[\\[LeftFloor]a\\[RightFloor]]", "a\\[RightFloor]", "(a\\[RightCeiling])",
    (* integrals *)
    "\\[Integral] f", "\\[Integral]f g\\[DifferentialD]x", "a \\[DifferentialD] x", "\\[Integral] f \\[DifferentialD] x + 1", "\\[ContourIntegral] f \\[DifferentialD] z",
    "\\[Integral]\\[Integral] f \\[DifferentialD] x \\[DifferentialD] y", "\[Integral]f\[DifferentialD]x",
    (* whitespace, newlines and the invisible comma *)
    "a\\[InvisibleSpace]b", "a\\[NonBreakingSpace]b", "a\[NonBreakingSpace]b", "a\\[IndentingNewLine]b", "a\[LineSeparator]b", "f[a\\[InvisibleComma]b]", "a\\[InvisibleComma]b",
    (* what CodeParser does not read *)
    "\\[PartialD]", "\\[PartialD] a", "\\[Limit] x", "a \\[DiscreteShift] b",
    (* letters *)
    "\\[Alpha]\\[Beta]", "\[Alpha]\[Beta] \[Element] \[DoubleStruckCapitalR]", "\\[FormalX] + \\[DoubleStruckCapitalR]"
};

(* whole containers, Source included *)
containerForms = {
    "f[x_] := x^2 (* c *)\n", "a; \nb", "a b", "f[x, ]", ";;b", "{1, 2}[[1]]", "a\r\nb", "\ta\tb", "x\n(* a\n b *)\n\n",
    "\"a\nb\" (*\t*)", "\"c\\\nd\"", "\\[Alpha]b \\[Rule] c", "a +\n  b",
    "\[LeftAngleBracket]a\[RightAngleBracket] \\[Element] b\[NonBreakingSpace]\n",
    (* line continuations: in a token, before one, at the end *)
    "a\\\nb", "a \\\n b", "a\\\n  + b", "ab\\\ncd\\\nef", "a\\\n", "\\\n", "\\\n\\\n a", "a\\\r\nb", "a \\\n\n b", "a \\\n (* c *) b",
    "\"a\" \\\n \"b\"", "\"a\\\nb\" \\\n c", "f[x, \\\n]", "a+\\\n+b", "x_\\\nInteger", "1\\\n.5", "<< \\\nfile", "(* a\\\nb *)",
    (* what CodeParser reads again: an open group or token, up to its chunk *)
    "f[x\ny = 1", "f[x\ng[y]", "{1,\n2\n\nf[3]", "f[x \n", "(* abc\n", "\"abc\n", "a = 1\nb = (c", "f[x\nBegin[\"a`\"]",
    "f[x\\\n", "\"abc\\\n", "\"a\\\nb\\\n"
};

dropIssues[c_] := MapAt[KeyDrop[#, CodeParser`SyntaxIssues] &, c, 3]
noSource[t_] := t /. a_Association :> KeyDrop[a, CodeParser`Source]
shown[e_] := Block[{$ContextPath = {"System`"}}, ToString[e, InputForm, CharacterEncoding -> "ASCII"]]
entries[list_, f_] := StringRiffle[Map["    {" <> shown[#] <> ", " <> shown[f[#]] <> "}" &, list], ",\n"]

block = StringJoin[
    "$concreteTrees = {\n", entries[Join[forms, errorForms, longNameForms], noSource[dropIssues[CodeConcreteParse[#]]] &], "\n};\n\n",
    "$concreteContainers = {\n", entries[containerForms, dropIssues[CodeConcreteParse[#]] &], "\n};\n"];

text = ByteArrayToString[ReadByteArray[testFile], "UTF-8"];
If[ ! StringContainsQ[text, "(* BEGIN frozen" ~~ Shortest[___] ~~ "(* END frozen *)"],
    Print["no BEGIN frozen / END frozen lines in ", testFile]; Exit[1]];
updated = StringReplace[text,
    start : ("(* BEGIN frozen" ~~ Shortest[___] ~~ "*)\n") ~~ Shortest[___] ~~ end : "(* END frozen *)" :> start <> block <> end, 1];
With[{stream = OpenWrite[testFile, CharacterEncoding -> "UTF-8"]}, WriteString[stream, updated]; Close[stream]];
Print["froze ", Length[forms] + Length[errorForms] + Length[longNameForms], " trees and ", Length[containerForms], " containers into ", testFile];

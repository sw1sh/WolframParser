(* :Title: ABC.wlt - ABC tests *)
(* :Context: Wolfram`Parser`Languages`ABC` *)
(* :Summary: the examples of the ABC specification 1.06, published contest solutions on
   their samples, the K:-)M 2009 calling rule, the machine's errors and the standard AST.
   Run via run-tests.wls. *)

(* === the specification's examples === *)
VerificationTest[ABCRun["print 1 + 2\nprint 2 - 1\nprint 1 - 2\nprint 3 * 4\nprint 15 / 6\nprint 15 % 6"],
    {3, 1, 0, 12, 2, 3},
    TestID -> "abc: arithmetic on non-negative integers, subtraction stopping at 0"]
VerificationTest[ABCRun["print 10 - 2\nstop\nprint 2 - 10"], {8},
    TestID -> "abc: nothing after stop prints"]
VerificationTest[{ABCRun["print b - a + 10", {4, 7}], ABCRun["print b - a + 10", {7, 4}]}, {{10}, {13}},
    TestID -> "abc: the first parameter is the top of the stack"]
VerificationTest[ABCRun["print b - a\nprint a - b", {7, 4}], {3, 3},
    TestID -> "abc: every calculation numbers its own parameters"]
VerificationTest[ABCRun["print d + b\na = 1 - 1\nd = a + b", {2}], {4},
    TestID -> "abc: named calculations form one namespace, defined anywhere"]
VerificationTest[ABCRun["a = b + c\nprint a(1,2) - a", {1, 1}], {1},
    TestID -> "abc: a call pushes its arguments and pops them after"]
VerificationTest[ABCRun["f = f(t-1) * t + (1 - t)\nprint f(10)"], {3628800},
    TestID -> "abc: * skips its left operand when its right one is 0, ending the recursion"]
VerificationTest[ABCRun["print 1 + 2 * 3 * 0"], {1},
    TestID -> "abc: lazy multiplication keeps precedence (the 2008 machine printed 3)"]
VerificationTest[ABCRun["a = 1\na = 2\nprint a"], {1},
    TestID -> "abc: a calculation defined twice keeps its first definition"]
VerificationTest[ABCRun["print Max\nmax = A - b + B", {3, 8}], {8},
    TestID -> "abc: names are case insensitive"]
VerificationTest[Head @ ABCRun["PRINT 1"], Failure, {ABCRun::syntax},
    TestID -> "abc: keywords are written as the grammar writes them"]
VerificationTest[ABCRun["  \n\n  print 1  \n   \n\tprint 2\t\r\n\n  "], {1, 2},
    TestID -> "abc: spaces and tabs are ignored and blank lines skipped, around lines and at the ends"]
VerificationTest[{Head @ ABCAST["print a b"], Head @ ABCAST["print 1 2"], Head @ ABCAST["print(1)"]}, {Failure, Failure, Failure},
    TestID -> "abc: names and numbers are tokens, and print needs a space after it"]
VerificationTest[ABCRun["print a - b + b", "3 8"], {8},
    TestID -> "abc: the inputs can be a string of numbers"]

(* === published solutions on their samples === *)
VerificationTest[ABCRun["print a%2+a/2%2*10+a/4%2*100+a/8%2*1000+a/16%2*10000+a/32%2*100000+a/64%2*1000000+a/128%2*10000000+a/256%2*100000000+a/512%2*1000000000", "5"],
    {101}, TestID -> "abc: 210/1, EACP 2008 (V. Sbitnev)"]
VerificationTest[ABCRun["is=is(a,b+1)*((1-(b-a/2))-(1-a%b))+(b-a/2)\nsimp=(simp(a,b+1)+is(b,2))*(1-(b-a))\nprint simp(a,2)", "5"],
    {3}, TestID -> "abc: pi/1, EACP 2008 (N. Murzin)"]
VerificationTest[ABCRun["print (((h%12)*3600+43200-m*660)%43200)/11", "17 18"],
    {556}, TestID -> "abc: clock/2, EACP 2008 (N. Glazyrin)"]
VerificationTest[
    ABCRun["y = a - a + x + x(b)\nx = a - b\neq = 1 - y\nlt = 1 - x(a+1, b)\nfib_fast = f1 - f1 + f0 * eq(0,n) + f1 * eq(1,n) + fib_fast(f0 + f1, f1, n-1) * lt(1,n)\nfib = fib_fast(1, 0)\nprint fib", #] & /@ {"0", "1", "10", "30"},
    {{0}, {1}, {55}, {832040}}, TestID -> "abc: the fast Fibonacci of the classic examples"]

(* === the K:-)M 2009 calls, which walk down the stack === *)
VerificationTest[
    With[{sum = "n = 0\nm = 1 - (1 - x)\ns = (s(n(1,1) + x - 1) + y) * m\nprint s"},
        {ABCRun[sum, {3, 10, 20, 30}, "Calls" -> "Advance"], ABCRun[sum, {3, 10, 20, 30}]}],
    {{60}, {15}}, TestID -> "abc: an Advance call reuses the stack below the caller; a Push call does not"]
VerificationTest[
    {ABCRun["n = 0\nprint a + n(1, 1)", {5, 6, 7}, "Calls" -> "Advance"], ABCRun["n = 0\nprint a + n(1, 1)", {5, 6, 7}]},
    {{7}, {5}}, TestID -> "abc: an Advance call with more arguments than parameters drops the extra cells"]
VerificationTest[
    With[{root = "pow = pow(b, e - 1) * b * (1 - (1 - e)) + (1 - e)\nfits = 1 - (pow(l, k) - n)\nroot = root(l + 1, n, k) * fits(l + 1, k, n) + l * (1 - fits(l + 1, k, n))\nprint root(0, n, k)"},
        {ABCRun[root, "100 2", "Calls" -> "Advance"], ABCRun[root, "100 2"]}],
    {{10}, {10}}, TestID -> "abc: with no more arguments than parameters, Advance and Push calls agree"]
VerificationTest[
    {ABCRun["n = 0\nprint n(1, 1, 1)", {4}, "Calls" -> "Advance"], ABCRun["n = 0\nprint a + n(1, 1, 1)", {4}, "Calls" -> "Advance"][[1]]},
    {{0}, "ABCStack"}, TestID -> "abc: an Advance call pops an empty stack without error, and leaves it empty"]

(* === the machine's errors === *)
VerificationTest[ABCRun["a = b + 1\nb = a + 1\nprint a"][[1]], "ABCCycle",
    TestID -> "abc: calculations that depend on each other have no value"]
VerificationTest[ABCRun["print 1 / 0"][[1]], "ABCDivision", TestID -> "abc: division by zero"]
VerificationTest[{#[[1]], #["Output"]} & @ ABCRun["print a\nprint a + b", {7}], {"ABCStack", {7}},
    TestID -> "abc: a parameter below the bottom of the stack stops the run, keeping what printed"]
VerificationTest[ABCRun["print f(1)"][[1]], "ABCName", TestID -> "abc: a call to no calculation"]
VerificationTest[ABCRun["f = f(1)\nprint f", "MaxDepth" -> 50][[1]], "ABCDepth",
    TestID -> "abc: calls nested past MaxDepth"]
VerificationTest[ABCRun["print 2 * 3", "MaxNumber" -> 5][[1]], "ABCOverflow",
    TestID -> "abc: a result above MaxNumber"]
VerificationTest[{ABCRun["a = 1\nprint a", "Mode" -> 1][[1]], ABCRun["a = 1\nprint a", "Mode" -> 2]},
    {"ABCMode", {1}}, TestID -> "abc: named calculations need mode 2"]
VerificationTest[Head @ ABCRun["print"], Failure, {ABCRun::syntax},
    TestID -> "abc: print needs an expression"]

(* === the grammar the specification publishes, read by EBNFParse === *)
VerificationTest[
    {StringStartsQ[ABCBNF, "<Program>    ::   [<NL>] <Line> [<NL>] [<NL> Program]"],
        Sort[First /@ EBNFRules[ABCBNF, "Dialect" -> "Classic"]]},
    {True, Sort[{"Program", "Line", "NamedCalc", "StopOp", "PrintOp", "Calc", "CalcList", "OP", "Name",
        "SymbolList", "Symbol", "Letter", "DigitList", "Digit", "NL", "SP"}]},
    TestID -> "abc: ABCBNF is the published grammar, sixteen rules in the classic dialect"]
VerificationTest[Parse[ABCGrammar[ABCSemantic], "print 1 + 2 * 3 * 0 - 4 / 2 % 3"],
    {{"print", {"-", {"+", 1, {"*", {"*", 2, 3}, 0}}, {"%", {"/", 4, 2}, 3}}}},
    TestID -> "abc: the grammar sets no precedence; * / % bind before + -, each left to right"]

(* === the plain data and the standard AST === *)
VerificationTest[Parse[ABCGrammar[ABCSemantic], "x = 1\nprint X(2) * 3\nstop"],
    {{"define", "x", 1}, {"print", {"*", {"call", "x", {2}}, 3}}, {"stop"}},
    TestID -> "abc: the semantic algebra builds plain data"]
VerificationTest[
    ASTStripSource @ ABCAST["print a(1) - b"],
    ContainerNode["String", {CallNode[LeafNode["Keyword", "print", <||>], {
        BinaryNode["-", {CallNode[LeafNode["Symbol", "a", <||>], {LeafNode["Integer", "1", <||>]}, <||>],
            LeafNode["Symbol", "b", <||>]}, <||>]}, <||>]}, <||>],
    TestID -> "abc: a line is a CallNode headed by its keyword"]

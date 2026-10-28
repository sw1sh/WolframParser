(* :Title: WolframLanguage.wlt - Wolfram Language grammar tests *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Summary: each form below read by WolframLanguageHeld, against what
   Wolfram 15's ImportString[s, {"WL", "HeldExpressions"}] gives for it
   (recorded once from the kernel, then frozen here), or, where a notebook's
   input cell reads it otherwise, what the cell gives (recorded with
   dev/frontend-held.wls); how a source splits
   into its top-level expressions; the grammar reading the zoo's own
   sources as the kernel does; the standard AST; failures; and the
   statements WolframLanguageHeldNext reads one at a time, against the parts
   of Wolfram 15's ToExpression[s, InputForm, HoldComplete]. Run via
   run-tests.wls. *)

ClearAll[$wlCases, $wlZoo]

(* {source, the list of held expressions Wolfram 15 reads from it, as a notebook does} *)
$wlCases = {
    {"-a b", List[HoldComplete[Times[Times[-1, a], b]]]},
    {"-a/b", List[HoldComplete[Times[Times[-1, a], Power[b, -1]]]]},
    {"a/b c", List[HoldComplete[Times[Times[a, Power[b, -1]], c]]]},
    {"a b/c", List[HoldComplete[Times[a, Times[b, Power[c, -1]]]]]},
    {"-2 a", List[HoldComplete[Times[-2, a]]]},
    {"- 2", List[HoldComplete[-2]]},
    (* a minus folds into a number written right after it, and takes anything else whole, a
       number in parentheses and a product too, as a notebook reads it *)
    {"-(2)", List[HoldComplete[Times[-1, 2]]]},
    {"a - (2)", List[HoldComplete[Plus[a, Times[-1, 2]]]]},
    {"x^-(2)", List[HoldComplete[Power[x, Times[-1, 2]]]]},
    {"a - b c", List[HoldComplete[Plus[a, Times[-1, Times[b, c]]]]]},
    {"a - 2 b", List[HoldComplete[Plus[a, Times[-1, Times[2, b]]]]]},
    {"a + -2 b", List[HoldComplete[Plus[a, Times[-2, b]]]]},
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
    {"{a\n+ b}", List[HoldComplete[List[Plus[a, b]]]]},
    {"0.1`20", List[HoldComplete[0.1`20.]]},
    {"1``10", List[HoldComplete[1.`10.]]},
    {"1.5``3", List[HoldComplete[1.5`3.1760912590556813]]},
    {"1.5`", List[HoldComplete[1.5`]]},
    {"12.`", List[HoldComplete[12.`]]},
    {"1.5`50*^3", List[HoldComplete[1500.`50.]]},
    {"16^^ff.8`20", List[HoldComplete[255.5`24.082399653118497]]},
    {"16^^ff.8``5", List[HoldComplete[255.5`8.427990817750356]]},
    {"2^^101*^2", List[HoldComplete[20]]},
    {"2^^1.1*^2", List[HoldComplete[6.`]]},
    {"36^^zz.z", List[HoldComplete[1295.9722222222222`]]},
    {"2*^-3", List[HoldComplete[Rational[1, 500]]]},
    {"2.*^-3", List[HoldComplete[0.002`]]},
    {"1.5*^-3", List[HoldComplete[0.0015`]]},
    {"1.23456789012345678", List[HoldComplete[1.23456789012345678`17.0915149772127]]},
    {"123456789012345678.", List[HoldComplete[1.23456789012345678`17.0915149772127*^17]]},
    {"0.10000000000000000000", List[HoldComplete[0.1`19.]]},
    {"1.2345678901234567", List[HoldComplete[1.2345678901234567`]]},
    {"0.00000000000000000001234", List[HoldComplete[1.234`*^-20]]},
    {"9.99999999999999999", List[HoldComplete[9.99999999999999999`18.]]},
    {"1.5*^400", List[HoldComplete[1.5`15.954589770191005*^400]]},
    {"1.5*^-400", List[HoldComplete[0.`]]},
    {"0``10", List[HoldComplete[0``10.]]},
    {"0.`10", List[HoldComplete[0.`]]},
    {"-1.5`20", List[HoldComplete[-1.5`20.]]},
    {"x - 0.1`20", List[HoldComplete[Plus[x, -0.1`20.]]]},
    {"\"a\\\"b\"", List[HoldComplete["a\"b"]]},
    {"\"a\\\\b\"", List[HoldComplete["a\\b"]]},
    {"\"\\n\\t\\r\\b\\f\"", List[HoldComplete["\n\t\r\b\f"]]},
    {"\"\\101\\60\"", List[HoldComplete["A\\60"]]},
    {"\"\\.41\\.e9\"", List[HoldComplete["A\[EAcute]"]]},
    {"\"\\:03b1\\:00e9\"", List[HoldComplete["\[Alpha]\[EAcute]"]]},
    {"\"\\|01f600\"", List[HoldComplete["\|01f600"]]},
    {"\"\\[Alpha]\\[Rule]\\[LongEqual]\"", List[HoldComplete["\[Alpha]\[Rule]\[LongEqual]"]]},
    {"\"ab\\\ncd\"", List[HoldComplete["abcd"]]},
    {"\"a\\qb\"", List[HoldComplete["a\\qb"]]},
    {"\"\\<x\\>\"", List[HoldComplete["x"]]},
    {"\"\\!\\(x\\)\"", List[HoldComplete["\!\(x\)"]]},
    {"\"\\[NotAName]\"", List[HoldComplete["\\[NotAName]"]]},
    {"\"\\[LeftAngleBracket]\\[Intersection]\\[RawSpace]\"", List[HoldComplete["\[LeftAngleBracket]\[Intersection] "]]},
    {"\"\\[CJKUnifiedIdeograph4E00]\"", List[HoldComplete["\\[CJKUnifiedIdeograph4E00]"]]},
    (* the long names of characters past U+FFFF, and those the front end reads that the kernel does not *)
    {"\"\\[FormalScriptA]\\[FormalScriptCapitalZ]\"", List[HoldComplete["\[FormalScriptA]\[FormalScriptCapitalZ]"]]},
    {"\"\\[COMPATIBILITYNoBreak]\\[COMPATIBILITYKanjiSpace]\\[AutoSpace]\"", List[HoldComplete["\:f3a2\:3000\:f35f"]]},
    (* a space past ASCII that no long name has is a letter; the ideographic space, the front end's
       \[AutoSpace], \[COMPATIBILITYNoBreak]'s character and the discretionary separators are spaces *)
    {"x\:2000y\:202fz\:0085w", List[HoldComplete[x\:2000y\:202fz\:0085w]]},
    {"x\:3000y\:f3a2z\:f35fw\:f76ev", List[HoldComplete[x y z w v]]},
    {"x\\[COMPATIBILITYKanjiSpace]y\\[DiscretionaryLineSeparator]z", List[HoldComplete[x y z]]},
    {"f[x\\[COMPATIBILITYKanjiSpace],\\[COMPATIBILITYNoBreak]y]", List[HoldComplete[f[x, y]]]},
    {"\"\\777\"", List[HoldComplete["\:01ff"]]},
    {"\"x\\\\\"", List[HoldComplete["x\\"]]},
    {"f::\"tag\"", List[HoldComplete[MessageName[f, "tag"]]]},
    {"<<\"a\\\\b.m\"", List[HoldComplete[Get["a\\b.m"]]]},
    {"<<a\\b.m", List[HoldComplete[Get["a\\b.m"]]]},
    {"<<a!b*c?", List[HoldComplete[Get["a!b*c?"]]]},
    {"<<a\\[Alpha]\\:0041", List[HoldComplete[Get["a\[Alpha]A"]]]},
    {"x >> a\\b", List[HoldComplete[Put[x, "a\\b"]]]},
    {"ab\\\ncd", List[HoldComplete[abcd]]},
    {"12\\\n  34", List[HoldComplete[1234]]},
    {"x_\\\nInteger", List[HoldComplete[x_Integer]]},
    {"a:\\\n=b", List[HoldComplete[a := b]]},
    {"a\\\n+ b", List[HoldComplete[a + b]]},
    {"1\\\n.5\\\n", List[HoldComplete[1.5]]},
    (* a query that does not begin its statement reads the expression after it, all that binds more
       tightly than ;, a word of one token its text, and ?? a word of one token, as a notebook reads
       them; one that begins its statement, which a notebook answers itself, the words after it; a ?
       after a ; is a pattern test of the compound *)
    {"a; ? b", List[HoldComplete[PatternTest[CompoundExpression[a, Null], b]]]},
    {"a;?b", List[HoldComplete[PatternTest[CompoundExpression[a, Null], b]]]},
    {"a; ?b; c", List[HoldComplete[CompoundExpression[PatternTest[CompoundExpression[a, Null], b], c]]]},
    {"x = ?a = b", List[HoldComplete[Set[x, Set[Information["a", Rule[LongForm, False]], b]]]]},
    {"f[?a >> b]", List[HoldComplete[f[Put[Information["a", Rule[LongForm, False]], "b"]]]]},
    {"a ;; ? b", List[HoldComplete[Span[a, Information["b", Rule[LongForm, False]]]]]},
    {"x::?a b", List[HoldComplete[MessageName[x, Information[Times[a, b], Rule[LongForm, False]]]]]},
    {"?Plot*", List[HoldComplete[Information["Plot*", Rule[LongForm, False]]]]},
    {"??x\ty z", List[HoldComplete[Information["x y z", Rule[LongForm, True]]]]},
    {"f[?x, ? \"y\" z]", List[HoldComplete[f[Information["x", Rule[LongForm, False]], Information[Times["y", z], Rule[LongForm, False]]]]]},
    {"f[a, ?b c]", List[HoldComplete[f[a, Information[Times[b, c], Rule[LongForm, False]]]]]},
    {"x = ?a b", List[HoldComplete[Set[x, Information[Times[a, b], Rule[LongForm, False]]]]]},
    {"x = ??a", List[HoldComplete[Set[x, Information["a", Rule[LongForm, True]]]]]},
    {"x = ?a; b", List[HoldComplete[CompoundExpression[Set[x, Information["a", Rule[LongForm, False]]], b]]]},
    {"f[? a + b]", List[HoldComplete[f[Information[Plus[a, b], Rule[LongForm, False]]]]]},
    {"f[?a//b]", List[HoldComplete[f[Information[b[a], Rule[LongForm, False]]]]]},
    {"f[?a&]", List[HoldComplete[f[Information[Function[a], Rule[LongForm, False]]]]]},
    {"f[?a?b]", List[HoldComplete[f[Information[PatternTest[a, b], Rule[LongForm, False]]]]]},
    {"f[?-a]", List[HoldComplete[f[Information[Times[-1, a], Rule[LongForm, False]]]]]},
    {"f[?<<a]", List[HoldComplete[f[Information[Get["a"], Rule[LongForm, False]]]]]},
    {"f[?a', b]", List[HoldComplete[f[Information[Derivative[1][a], Rule[LongForm, False]], b]]]},
    {"f[?(a)]", List[HoldComplete[f[Information[a, Rule[LongForm, False]]]]]},
    {"f[?a_]", List[HoldComplete[f[Information["a_", Rule[LongForm, False]]]]]},
    {"f[?#]", List[HoldComplete[f[Information["#", Rule[LongForm, False]]]]]},
    {"<|a ->? 1|>", List[HoldComplete[Association[Rule[a, Information["1", Rule[LongForm, False]]]]]]},
    {"a?b c", List[HoldComplete[Times[PatternTest[a, b], c]]]},
    {"a.5", List[HoldComplete[Times[a, 0.5]]]},
    {"1.5.2", List[HoldComplete[Times[1.5, 0.2]]]},
    {"f[x].5", List[HoldComplete[Times[f[x], 0.5]]]},
    {"a. 5", List[HoldComplete[Dot[a, 5]]]},
    {"a.b5", List[HoldComplete[Dot[a, b5]]]},
    {"x //= f //= g", List[HoldComplete[ApplyTo[x, ApplyTo[f, g]]]]},
    {"f[#\"key\"]&", List[HoldComplete[Function[f[Slot["key"]]]]]},
    {"a = .; b =\n.", List[HoldComplete[CompoundExpression[Unset[a], Unset[b]]]]},
    {"a=.5", List[HoldComplete[Set[a, 0.5]]]},
    {"t /: a = .", List[HoldComplete[TagUnset[t, a]]]},
    {"a[[1]\n ]", List[HoldComplete[Part[a, 1]]]},
    {"\"a\\\r\nb\"", List[HoldComplete["a\nb"]]},
    {"a\nNull\nb", List[HoldComplete[a], HoldComplete[b]]},
    (* f @ x is the call wherever it stands, as a notebook reads it, where Wolfram 15's kernel
       splices it into a flat chain of f *)
    {"a <> StringJoin @ b + Plus @ c", List[HoldComplete[Plus[StringJoin[a, StringJoin[b]], Plus[c]]]]},
    {"a b Times@c", List[HoldComplete[Times[a, b, Times[c]]]]},
    {"a <> (StringJoin @ b)", List[HoldComplete[StringJoin[a, StringJoin[b]]]]},
    {"a \\[CircleTimes] b \\[CircleTimes] c", List[HoldComplete[CircleTimes[a, b, c]]]},
    {"x \\[Distributed] d", List[HoldComplete[Distributed[x, d]]]},
    {"a < b \\[LessFullEqual] c", List[HoldComplete[Inequality[a, Less, b, LessFullEqual, c]]]},
    {"a \\[VectorLess] b \\[VectorLess] c", List[HoldComplete[VectorLess[List[a, b, c]]]]},
    {"a \\[VectorLess] b < c", List[HoldComplete[Developer`VectorInequality[a, VectorLess, b, Less, c]]]},
    {"a \\[NotEqual] b \\[LessSlantEqual] c", List[HoldComplete[Inequality[a, Unequal, b, LessEqual, c]]]},
    {"a + b \\[Minus] c", List[HoldComplete[Plus[a, b, Times[-1, c]]]]},
    {"\\[Minus] a", List[HoldComplete[Times[-1, a]]]},
    {"a \\[Divides] b \\[Divides] c", List[HoldComplete[Divisible[c, b, a]]]},
    {"a \\[ImplicitPlus] b \\[ImplicitPlus] c", List[HoldComplete[Plus[Plus[a, b], c]]]},
    {"f \\[InvisibleApplication] g \\[InvisibleApplication] x", List[HoldComplete[f[g[x]]]]},
    (* \[Application] nests to the left, as a notebook reads it, where Wolfram 15's kernel makes one node *)
    {"a \\[Application] b \\[Application] c", List[HoldComplete[Application[Application[a, b], c]]]},
    {"a + b \\[Application] c \\[Application] d", List[HoldComplete[Plus[a, Application[Application[b, c], d]]]]},
    {"a \\[Element] b \\[Element] c", List[HoldComplete[Element[a, b, c]]]},
    {"a\\[HermitianConjugate]", List[HoldComplete[ConjugateTranspose[a]]]},
    {"\\[Sqrt] a b", List[HoldComplete[Times[Sqrt[a], b]]]},
    {"a \\[Sqrt] b", List[HoldComplete[Times[a, Sqrt[b]]]]},
    {"a \\[Not] b", List[HoldComplete[Times[a, Not[b]]]]},
    {"\\[LeftFloor]x\\[RightFloor]", List[HoldComplete[Floor[x]]]},
    {"\\[LeftAngleBracket]a, b\\[RightAngleBracket]", List[HoldComplete[AngleBracket[a, b]]]},
    {"f\\[LeftDoubleBracket]1, 2\\[RightDoubleBracket]", List[HoldComplete[Part[f, 1, 2]]]},
    {"f[a\\[InvisibleComma]b]", List[HoldComplete[f[a, b]]]},
    {"a\\[NonBreakingSpace]b", List[HoldComplete[Times[a, b]]]},
    {"a\[CircleTimes]b", List[HoldComplete[CircleTimes[a, b]]]},
    {"a\[Divides]b", List[HoldComplete[Divisible[b, a]]]},
    {"\[LeftCeiling]x\[RightCeiling]", List[HoldComplete[Ceiling[x]]]},
    {"a\[InvisibleSpace]b", List[HoldComplete[Times[a, b]]]},
    {"a;\\[IndentingNewLine]b", List[HoldComplete[CompoundExpression[a, Null]], HoldComplete[b]]},
    {"a\:f3a3b", List[HoldComplete[a], HoldComplete[b]]},
    {"f[a\\[IndentingNewLine]b]", List[HoldComplete[f[Times[a, b]]]]},
    {"a +\\[IndentingNewLine]b", List[HoldComplete[Plus[a, b]]]},
    {"a\\[NewLine]b", List[HoldComplete[a], HoldComplete[b]]},
    {"a\\[LineSeparator]b", List[HoldComplete[a], HoldComplete[b]]},
    {"a\[ParagraphSeparator]b", List[HoldComplete[a], HoldComplete[b]]},
    {"a\rb", List[HoldComplete[a], HoldComplete[b]]},
    {"a = 1;\r\nb = 2\r\n", List[HoldComplete[CompoundExpression[Set[a, 1], Null]], HoldComplete[Set[b, 2]]]}
};

(* === forms: precedence, flat chains, minus and quotients, patterns, spans,
   numbers with their marks, strings with their escapes === *)
Scan[
    Function[c, VerificationTest[WolframLanguageHeld[c[[1]]], c[[2]], TestID -> "wl: " <> c[[1]]]],
    $wlCases]

(* === integrals as a notebook reads them, by the reader and by the grammar: k signs of one kind
   and an operand whose factors end in k differentials, no other factor one and none in
   parentheses, are head of the factors before them and the k variables, the last first; any other
   operand is no Wolfram Language, which the rows of $Failed hold. Recorded from Wolfram 15's front
   end with dev/frontend-held.wls === *)
$wlIntegrals = {
    {"-\\[Integral] x \\[DifferentialD]x", List[HoldComplete[Times[-1, Integrate[x, x]]]]},
    {"\\[CapitalDifferentialD] x", List[HoldComplete[CapitalDifferentialD[x]]]},
    {"\\[CapitalDifferentialD]x", List[HoldComplete[CapitalDifferentialD[x]]]},
    {"\\[ContourIntegral] x \\[DifferentialD] x", List[HoldComplete[ContourIntegral[x, x]]]},
    {"\\[ContourIntegral] x \\[DifferentialD]x", List[HoldComplete[ContourIntegral[x, x]]]},
    {"\\[ContourIntegral] x \\[DifferentialD]x \\[DifferentialD]y", $Failed},
    {"\\[ContourIntegral]\\[Integral] x \\[DifferentialD]x \\[DifferentialD]y", $Failed},
    {"\\[DifferentialD]  x", List[HoldComplete[DifferentialD[x]]]},
    {"\\[DifferentialD] (x)", List[HoldComplete[DifferentialD[x]]]},
    {"\\[DifferentialD] x", List[HoldComplete[DifferentialD[x]]]},
    {"\\[DifferentialD] x \\[DifferentialD] y", List[HoldComplete[Times[DifferentialD[x], DifferentialD[y]]]]},
    {"\\[DifferentialD] x^2", List[HoldComplete[DifferentialD[Power[x, 2]]]]},
    {"\\[DifferentialD](x)", List[HoldComplete[DifferentialD[x]]]},
    {"\\[DifferentialD]\\[DifferentialD]x", List[HoldComplete[DifferentialD[DifferentialD[x]]]]},
    {"\\[DifferentialD]f[x]", List[HoldComplete[DifferentialD[f[x]]]]},
    {"\\[DifferentialD]x", List[HoldComplete[DifferentialD[x]]]},
    {"\\[DifferentialD]x \\[DifferentialD]y", List[HoldComplete[Times[DifferentialD[x], DifferentialD[y]]]]},
    {"\\[DifferentialD]x^2", List[HoldComplete[DifferentialD[Power[x, 2]]]]},
    {"\\[Integral] (x \\[DifferentialD]x)", List[HoldComplete[Integrate[x, x]]]},
    {"\\[Integral] -x \\[DifferentialD]x", List[HoldComplete[Integrate[Times[-1, x], x]]]},
    {"\\[Integral] \\[ContourIntegral] x \\[DifferentialD]x", $Failed},
    {"\\[Integral] \\[DifferentialD] x", List[HoldComplete[Integrate[1, x]]]},
    {"\\[Integral] \\[DifferentialD]x", List[HoldComplete[Integrate[1, x]]]},
    {"\\[Integral] \\[Integral] x \\[DifferentialD]y", $Failed},
    {"\\[Integral] f[x] \\[DifferentialD]x + 1", List[HoldComplete[Plus[Integrate[f[x], x], 1]]]},
    {"\\[Integral] x", $Failed},
    {"\\[Integral] x + y \\[DifferentialD]x", $Failed},
    {"\\[Integral] x / 2 \\[DifferentialD]x", List[HoldComplete[Integrate[Times[x, Power[2, -1]], x]]]},
    {"\\[Integral] x Sin[x] \\[DifferentialD]x", List[HoldComplete[Integrate[Times[x, Sin[x]], x]]]},
    {"\\[Integral] x \\[CapitalDifferentialD]x", List[HoldComplete[Integrate[x, x]]]},
    {"\\[Integral] x \\[DifferentialD] \\[DifferentialD]x", List[HoldComplete[Integrate[x, DifferentialD[x]]]]},
    {"\\[Integral] x \\[DifferentialD] x \\[DifferentialD] y", $Failed},
    {"\\[Integral] x \\[DifferentialD] x y", $Failed},
    {"\\[Integral] x \\[DifferentialD](x^2)", List[HoldComplete[Integrate[x, Power[x, 2]]]]},
    {"\\[Integral] x \\[DifferentialD]x + y \\[DifferentialD]y", List[HoldComplete[Plus[Integrate[x, x], Times[y, DifferentialD[y]]]]]},
    {"\\[Integral] x \\[DifferentialD]x / 2", $Failed},
    {"\\[Integral] x \\[DifferentialD]x ;", List[HoldComplete[CompoundExpression[Integrate[x, x], Null]]]},
    {"\\[Integral] x \\[DifferentialD]x \\[DifferentialD]x", $Failed},
    {"\\[Integral] x \\[DifferentialD]x \\[DifferentialD]y", $Failed},
    {"\\[Integral] x \\[DifferentialD]x \\[DifferentialD]y \\[DifferentialD]z", $Failed},
    {"\\[Integral] x \\[DifferentialD]x \\[Integral] y \\[DifferentialD]y", $Failed},
    {"\\[Integral] x \\[DifferentialD]x y", $Failed},
    {"\\[Integral] x y \\[DifferentialD]x z", $Failed},
    {"\\[Integral] x^2 \\[DifferentialD]x \\[DifferentialD]y", $Failed},
    {"\\[Integral] x^2 \\[DifferentialD]x^2", List[HoldComplete[Integrate[Power[x, 2], Power[x, 2]]]]},
    {"\\[Integral](\\[Integral] x \\[DifferentialD]x) \\[DifferentialD]y", List[HoldComplete[Integrate[Integrate[x, x], y]]]},
    {"\\[Integral]\\[ContourIntegral] x \\[DifferentialD]x \\[DifferentialD]y", $Failed},
    {"\\[Integral]\\[Integral] x", $Failed},
    {"\\[Integral]\\[Integral] x \\[DifferentialD]x", $Failed},
    {"\\[Integral]\\[Integral] x \\[DifferentialD]x + 1", $Failed},
    {"\\[Integral]\\[Integral] x \\[DifferentialD]x \\[DifferentialD]y \\[DifferentialD]z", $Failed},
    {"\\[Integral]\\[Integral] x y \\[DifferentialD] x \\[DifferentialD] y", List[HoldComplete[Integrate[Times[x, y], y, x]]]},
    {"\\[Integral]\\[Integral] x y \\[DifferentialD]x \\[DifferentialD]y", List[HoldComplete[Integrate[Times[x, y], y, x]]]},
    {"\\[Integral]\\[Integral] x^2 \\[DifferentialD]x^2 \\[DifferentialD]y^2", List[HoldComplete[Integrate[Power[x, 2], Power[y, 2], Power[x, 2]]]]},
    {"\\[Integral]\\[Integral]\\[Integral] x \\[DifferentialD]x \\[DifferentialD]y \\[DifferentialD]z", List[HoldComplete[Integrate[x, z, y, x]]]},
    {"\\[Integral]\\[Integral]f\\[DifferentialD]x\\[DifferentialD]y", List[HoldComplete[Integrate[f, y, x]]]},
    {"\\[Integral]f g\\[DifferentialD]x", List[HoldComplete[Integrate[Times[f, g], x]]]},
    {"\\[Integral]f\\[DifferentialD]x\\[DifferentialD]y", $Failed},
    {"\\[Integral]x\\[DifferentialD]x", List[HoldComplete[Integrate[x, x]]]},
    {"a \\[DifferentialD] x", List[HoldComplete[Times[a, DifferentialD[x]]]]},
    {"a \\[DifferentialD]x", List[HoldComplete[Times[a, DifferentialD[x]]]]},
    {"a \\[Integral] x \\[DifferentialD]x", List[HoldComplete[Times[a, Integrate[x, x]]]]},
    {"f[\\[DifferentialD] x]", List[HoldComplete[f[DifferentialD[x]]]]},
    {"f[\\[DifferentialD]x]", List[HoldComplete[f[DifferentialD[x]]]]},
    {"x\\[DifferentialD]y", List[HoldComplete[Times[x, DifferentialD[y]]]]},
    {"\\[Integral] f g \\[DifferentialD] x", List[HoldComplete[Integrate[Times[f, g], x]]]},
    {"\\[ContourIntegral] f \\[DifferentialD] x", List[HoldComplete[ContourIntegral[f, x]]]},
    {"\\[Integral] f", $Failed}
};
Scan[
    Function[c, VerificationTest[
        If[ c[[2]] === $Failed,
            {WolframLanguageSyntaxQ[c[[1]]], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageSyntaxQ[c[[1]]]]},
            {WolframLanguageHeld[c[[1]]], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageHeld[c[[1]]]]}],
        If[c[[2]] === $Failed, {False, False}, {c[[2]], c[[2]]}],
        TestID -> "wl integral, reader and grammar: " <> c[[1]]]],
    $wlIntegrals]

(* === spans, by the reader and by the grammar: the ;; after the second operand takes a third
   only where one begins after it; there, and after a span of three, a ;; begins a span of its
   own, the spans a product, as Wolfram 15 and CodeParser read them === *)
$wlSpans = {
    {"a ;; b ;;", List[HoldComplete[Times[Span[a, b], Span[1, All]]]]},
    {"a ;; ;;", List[HoldComplete[Times[Span[a, All], Span[1, All]]]]},
    {";; ;;", List[HoldComplete[Times[Span[1, All], Span[1, All]]]]},
    {"a ;; b ;; c ;; d", List[HoldComplete[Times[Span[a, b, c], Span[1, d]]]]},
    {"a ;; b ;; ;; c", List[HoldComplete[Times[Span[a, b], Span[1, All, c]]]]},
    {"a ;; b ;; c ;; d ;; e ;; f", List[HoldComplete[Times[Span[a, b, c], Span[1, d, e], Span[1, f]]]]},
    {"f[a ;; b ;;]", List[HoldComplete[f[Times[Span[a, b], Span[1, All]]]]]},
    {"x * a ;; b ;; c ;; d", List[HoldComplete[Times[Span[Times[x, a], b, c], Span[1, d]]]]},
    {"(a ;; b ;; c) ;; d", List[HoldComplete[Span[Span[a, b, c], d]]]},
    (* after a ;;, as a notebook reads it, a line break is whitespace, but for one before another
       ;; where the first has no operand before it; Wolfram 15's kernel ends the statement *)
    {"a ;; b ;;\nc", List[HoldComplete[Span[a, b, c]]]},
    {"a;;\nb", List[HoldComplete[Span[a, b]]]},
    {";;\nb", List[HoldComplete[Span[1, b]]]},
    {"a;;\n;;", List[HoldComplete[Times[Span[a, All], Span[1, All]]]]},
    {"a;;\n;;b;;c", List[HoldComplete[Times[Span[a, All, b], Span[1, c]]]]},
    {"a;;b;;\n;;", List[HoldComplete[Times[Span[a, b], Span[1, All], Span[1, All]]]]},
    {"a;;\nb;;\nc", List[HoldComplete[Span[a, b, c]]]},
    {"a;;\n\n(* c *)\nb", List[HoldComplete[Span[a, b]]]},
    {";;\n;;b", List[HoldComplete[Span[1, All]], HoldComplete[Span[1, b]]]},
    {"a;;;;\n;;", List[HoldComplete[Times[Span[a, All], Span[1, All]]], HoldComplete[Span[1, All]]]},
    {"a;;b\n;;c", List[HoldComplete[Span[a, b]], HoldComplete[Span[1, c]]]},
    {"a;;\n;\nb", List[HoldComplete[CompoundExpression[Span[a, All], Null]], HoldComplete[b]]},
    {"a;;\n+b", List[HoldComplete[Span[a, Plus[b]]]]},
    {"a\n;;\n;;", List[HoldComplete[a], HoldComplete[Span[1, All]], HoldComplete[Span[1, All]]]},
    {"a+\n;;\n;;", List[HoldComplete[Plus[a, Span[1, All]]], HoldComplete[Span[1, All]]]},
    {"x = ;;\n;;", List[HoldComplete[Set[x, Span[1, All]]], HoldComplete[Span[1, All]]]},
    {"a!;;\n;;", List[HoldComplete[Times[Span[Factorial[a], All], Span[1, All]]]]},
    {"a; ;;\n;;", List[HoldComplete[Times[Span[CompoundExpression[a, Null], All], Span[1, All]]]]},
    (* a prefix operator after ;; begins the span's operand, as in any other operand and as
       CodeParser reads it; Wolfram 15 ends the span there and multiplies, (a ;; All)*(!b), but
       for -, +, ++, -- and << [W15 bug] *)
    {"a ;; !b", List[HoldComplete[Span[a, Not[b]]]]},
    {"a ;; !!b", List[HoldComplete[Span[a, Not[Not[b]]]]]},
    {"a ;; \\[Not]b", List[HoldComplete[Span[a, Not[b]]]]},
    {"a ;; \\[Minus]b", List[HoldComplete[Span[a, Times[-1, b]]]]},
    {"a ;; \\[Sum]b", List[HoldComplete[Span[a, Sum[b]]]]},
    {"a ;; b ;; !c", List[HoldComplete[Span[a, b, Not[c]]]]},
    {"a ;; !b ;; c", List[HoldComplete[Span[a, Not[Span[b, c]]]]]},
    {"a ;; !b && c", List[HoldComplete[And[Span[a, Not[b]], c]]]},
    {"a ;; b * !c ;; d", List[HoldComplete[Span[a, Times[b, Not[Span[c, d]]]]]]},
    {"a ;; -> b", List[HoldComplete[Rule[Span[a, All], b]]]}
};
Scan[
    Function[c, VerificationTest[
        {WolframLanguageHeld[c[[1]]], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageHeld[c[[1]]]]},
        {c[[2]], c[[2]]},
        TestID -> "wl span, reader and grammar: " <> c[[1]]]],
    $wlSpans]

(* === free-form input, by the reader and by the grammar, as a notebook reads it: =[ and its text
   to the first ], the ] of a \[Name] too, is FreeformEvaluate of the text from its first character
   that is no whitespace to the end of its line, a space where nothing is left, an operand like
   any other; an operator that ends in =, but //= and ^:=, ends before a =[. CodeParser has no
   free-form input === *)
$wlFreeform = {
    {"=[b]", List[HoldComplete[FreeformEvaluate["b"]]]},
    {"=[ b ]", List[HoldComplete[FreeformEvaluate["b "]]]},
    {"=[]", List[HoldComplete[FreeformEvaluate[" "]]]},
    {"=[\n]", List[HoldComplete[FreeformEvaluate[" "]]]},
    {"=[ b\n]", List[HoldComplete[FreeformEvaluate["b"]]]},
    {"=[\tb\t]", List[HoldComplete[FreeformEvaluate["b\t"]]]},
    {"=[\[Alpha]]", List[HoldComplete[FreeformEvaluate["\[Alpha]"]]]},
    {"a==[b]", List[HoldComplete[Set[a, FreeformEvaluate["b"]]]]},
    {"a===[b]", List[HoldComplete[Equal[a, FreeformEvaluate["b"]]]]},
    {"a=!=[b]", List[HoldComplete[Set[a, Not[FreeformEvaluate["b"]]]]]},
    {"a+=[b]", List[HoldComplete[Plus[a, FreeformEvaluate["b"]]]]},
    {"a:=[b]", List[HoldComplete[Pattern[a, FreeformEvaluate["b"]]]]},
    {"a!=[b]", List[HoldComplete[Times[Factorial[a], FreeformEvaluate["b"]]]]},
    {"a<=[b]<=[c]", List[HoldComplete[Less[a, FreeformEvaluate["b"], FreeformEvaluate["c"]]]]},
    {"a// =[b]", List[HoldComplete[FreeformEvaluate["b"][a]]]},
    {"a=[b, c]", List[HoldComplete[Times[a, FreeformEvaluate["b, c"]]]]},
    {"a =[b] c", List[HoldComplete[Times[a, FreeformEvaluate["b"], c]]]},
    {"x = =[b]", List[HoldComplete[Set[x, FreeformEvaluate["b"]]]]},
    {"x=[b]=5", List[HoldComplete[Set[Times[x, FreeformEvaluate["b"]], 5]]]},
    {"=[b]^2", List[HoldComplete[Power[FreeformEvaluate["b"], 2]]]},
    {"f[=[b]]", List[HoldComplete[f[FreeformEvaluate["b"]]]]},
    {"=[(* c *)]", List[HoldComplete[FreeformEvaluate["(* c *)"]]]},
    {"=[\"a\"]", List[HoldComplete[FreeformEvaluate["\"a\""]]]},
    {"a == b", List[HoldComplete[Equal[a, b]]]}
};
Scan[
    Function[c, VerificationTest[
        {WolframLanguageHeld[c[[1]]], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageHeld[c[[1]]]]},
        {c[[2]], c[[2]]},
        TestID -> "wl free-form, reader and grammar: " <> c[[1]]]],
    $wlFreeform]
VerificationTest[
    Map[{WolframLanguageSyntaxQ[#], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageSyntaxQ[#]]} &,
        {"=[\\[Alpha]]", "=[b\nc]", "a//=[b]", "a^:=[b]"}],
    ConstantArray[{False, False}, 4],
    TestID -> "wl free-form: no Wolfram Language where its text ends at a long name's ], goes on to a second line, or follows //= or ^:="]

(* === character escapes, by the reader and by the grammar: a \:xxxx, \.xx or \|xxxxxx outside a
   string and a comment is its character, a letter of a name or a file, an operator, as Wolfram
   15 reads it; a file's name holds letters past ASCII === *)
$wlEscapes = {
    {"a\\:03b1b", List[HoldComplete[a\[Alpha]b]]},
    {"a\\.41b", List[HoldComplete[aAb]]},
    {"a \\:2192 b", List[HoldComplete[RightArrow[a, b]]]},
    {"a\\|00002Bb", List[HoldComplete[Plus[a, b]]]},
    {"\\:0028a\\:0029", List[HoldComplete[a]]},
    {"\"x\\:0022y\"", List[HoldComplete["x\"y"]]},
    {"(* \\:03b1 *) a", List[HoldComplete[a]]},
    {"=[\\|0003b1]", List[HoldComplete[FreeformEvaluate["\[Alpha]"]]]},
    {"<<a\\|0003b1b", List[HoldComplete[Get["a\[Alpha]b"]]]},
    {"<<a\[Alpha]b", List[HoldComplete[Get["a\[Alpha]b"]]]},
    (* in a comment a backslash before an opening paren takes it, so that it opens none, and a star
       after a backslash ends it, as a notebook reads it *)
    {"(* ::Package:: \\*)", List[]},
    {"(* a \\\\*) b", List[HoldComplete[b]]},
    {"(* a \\ *) b", List[HoldComplete[b]]},
    {"(* C:\\temp\\ *) 1", List[HoldComplete[1]]},
    {"(* \\(* *) x", List[HoldComplete[x]]},
    (* a file's name holds a bracket to its ], brackets nested, or to the end of the source, and an
       operator's character ends it, as a notebook reads it *)
    {"<<b[c]", List[HoldComplete[Get["b[c]"]]]},
    {"<<b[[c]]d", List[HoldComplete[Get["b[[c]]d"]]]},
    {"<<b[c", List[HoldComplete[Get["b[c"]]]},
    {"<<a\\", List[HoldComplete[Get["a\\"]]]},
    {"<<a\\ b", List[HoldComplete[Times[Get["a\\"], b]]]},
    {"<<a+b", List[HoldComplete[Plus[Get["a"], b]]]},
    {"<<a@b", List[HoldComplete[Get["a"][b]]]},
    {"f[<<a+b]", List[HoldComplete[f[Plus[Get["a"], b]]]]},
    {"f[<<a, x >> b]", List[HoldComplete[f[Get["a"], Put[x, "b"]]]]},
    (* after >> or >>> a file alone, else all that follows an expression, as a notebook reads it: a
       file where the end, a newline outside brackets, ;, , or a closer comes after it *)
    {"x >> a b", List[HoldComplete[Put[x, Times[a, b]]]]},
    {"x >> a+b", List[HoldComplete[Put[x, Plus[a, b]]]]},
    {"x >>> a+b", List[HoldComplete[PutAppend[x, Plus[a, b]]]]},
    {"x >> a = b", List[HoldComplete[Put[x, Set[a, b]]]]},
    {"x >> a // f", List[HoldComplete[Put[x, f[a]]]]},
    {"x >> a//f", List[HoldComplete[Put[x, "a//f"]]]},
    {"x >> \"f\" b", List[HoldComplete[Put[x, Times["f", b]]]]},
    {"x >> a (* c *)", List[HoldComplete[Put[x, "a"]]]},
    {"x >> a\n b", List[HoldComplete[Put[x, "a"]], HoldComplete[b]]},
    {"f[x >> a\n b]", List[HoldComplete[f[Put[x, Times[a, b]]]]]},
    {"<|k -> x >> a|>", List[HoldComplete[Association[Put[Rule[k, x], "a"]]]]}
};
VerificationTest[
    FailureQ[WolframLanguageHeld["(* a \\*) b *)"]],
    True,
    TestID -> "wl: a star after a backslash ends a comment, as a notebook reads it, so a *) after it closes none"]
Scan[
    Function[c, VerificationTest[
        {WolframLanguageHeld[c[[1]]], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageHeld[c[[1]]]]},
        {c[[2]], c[[2]]},
        TestID -> "wl escape, reader and grammar: " <> c[[1]]]],
    $wlEscapes]

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
    WolframLanguageAST["ab\\\ncd +\\\n e"],
    ContainerNode["String", {InfixNode["Plus", {
        LeafNode["Symbol", "abcd", <|"Source" -> {{1, 1}, {2, 3}}|>], LeafNode["Symbol", "e", <|"Source" -> {{2, 5}, {3, 3}}|>]},
        <|"Source" -> {{1, 1}, {3, 3}}|>]}, <|"Source" -> {{1, 1}, {3, 3}}|>],
    TestID -> "wl: AST reads line continuations, its spans in the source"]
VerificationTest[
    ASTStripSource @ WolframLanguageAST["a < b <= c"],
    ContainerNode["String", {InfixNode["Inequality", {
        LeafNode["Symbol", "a", <||>], LeafNode["Symbol", "Less", <||>], LeafNode["Symbol", "b", <||>],
        LeafNode["Symbol", "LessEqual", <||>], LeafNode["Symbol", "c", <||>]}, <||>]}, <||>],
    TestID -> "wl: AST of a mixed relation chain"]

(* === failures === *)
wlStop[f_Failure] := {f["Position"], f["Incomplete"]};
VerificationTest[FailureQ[WolframLanguageHeld["a = 1\nb = (c"]], True, TestID -> "wl: an unclosed bracket fails"]
VerificationTest[
    WolframLanguageHeld["a = 1\nb c)\nd"]["Position"],
    11,
    TestID -> "wl: a failure points just past the token reading stopped at"]
VerificationTest[
    wlStop[WolframLanguageHeld["a +"]],
    {4, True},
    TestID -> "wl: a source that ends before its expression does is incomplete"]

(* where reading stops, and whether the source ends too early, as Wolfram 15's ToExpression
   reports them: ToExpression::sntxi, or the caret of ToExpression::sntx, past the leading
   whitespace its message leaves out; dev/check-failure-positions.wls checks more against the
   kernel *)
$wlFailures = {
    {"f[x", {4, True}},
    {"f[x)", {5, False}},
    {"a + * b", {6, False}},
    {")", {2, False}},
    {"a b )", {6, False}},
    {"{1, 2", {6, True}},
    {"a +", {4, True}},
    {"f[x]]", {6, False}},
    {"a]", {3, False}},
    {"x : : y", {6, False}},
    {"a = = b", {6, False}},
    {"a ~ b ~", {8, True}},
    {"a \"b c", {7, True}},
    {"a (* note", {10, True}},
    {"a[[1]&]", {7, False}},
    {"a[[1, 2]", {9, True}},
    {"(a + b", {7, True}},
    {"f[x, ", {6, True}},
    {"{a, b}}", {8, False}},
    {"a + b)", {7, False}},
    {"<|a -> 1", {9, True}},
    {"a -> ", {6, True}},
    {"f @", {4, True}},
    {"a // ", {6, True}},
    {"a := ", {6, True}},
    {"a \\[Rle] b", {3, False}},
    {"x + \\", {6, True}},
    {"  a + * b", {8, False}},
    {"f[a, b]]", {9, False}},
    {"{a, {b, c}", {11, True}},
    {"f[x_] := (x + 1", {16, True}},
    {"a /. {x -> 1", {13, True}},
    {"Module[{x}, x", {14, True}},
    {"a @@ ", {6, True}},
    {"\"abc\" <> ", {10, True}},
    {"g[x] /; ", {9, True}},
    {"f[x_ /; x > 0] := x ^", {22, True}},
    {"a && || b", {8, False}},
    {"a == == b", {8, False}},
    {"#1 + &", {7, False}},
    {"a[[1]] [[2]", {12, True}},
    (* a prefix operator after ;; or ; begins an operand that is not left out *)
    {"a ;; !", {7, True}},
    {"a ;; b ;; ++", {13, True}},
    {"a;!", {4, True}},
    {"a; ++", {6, True}},
    (* free-form input to its first ]: a ] after it closes nothing *)
    {"a + =[b", {8, True}},
    {"=[b]]", {6, False}},
    (* a failure after a character escape is placed in the source as written *)
    {"a\\:03b1 +", {10, True}}
};
Scan[
    Function[c, VerificationTest[wlStop[WolframLanguageHeld[c[[1]]]], c[[2]], TestID -> "wl failure: " <> c[[1]]]],
    $wlFailures]
VerificationTest[
    wlStop[WolframLanguageHeld["a = \\\n(b"]],
    {9, True},
    TestID -> "wl: a failure past a line continuation points into the source as written"]
VerificationTest[
    {wlStop[WolframLanguageHeld["x\\"]], wlStop[WolframLanguageHeld["\"abc"]],
     wlStop[WolframLanguageHeld["(* note"]]},
    {{3, True}, {5, True}, {8, True}},
    TestID -> "wl: a source ending in a line continuation, a string or a comment is incomplete"]
VerificationTest[
    wlStop[WolframLanguageHeld["?Plo_t*"]],
    {8, True},
    TestID -> "wl: a failure of the grammar tells an incomplete source too"]
VerificationTest[
    {wlStop[WolframLanguageHeld["f[x)\n\"abc"]], wlStop[WolframLanguageHeld["a )\nb \\!"]]},
    {{5, False}, {4, False}},
    TestID -> "wl: reading stops at a statement that cannot be read, before a token that cannot be one"]

(* --- statements one at a time --- *)

(* the parts WolframLanguageHeldNext gives a source, read from 1 to EndOfFile, a failure as
   {"Failure", its position, whether the source ends too early, where its line begins} *)
wlParts[s_String] := Module[{pos = 1, r, out = {}},
    While[ ListQ[r = WolframLanguageHeldNext[s, pos]],
        If[FailureQ[First[r]], AppendTo[out, {"Failure", r[[1]]["Position"], r[[1]]["Incomplete"], r[[2]]}]; Break[]];
        AppendTo[out, First[r]]; pos = r[[2]]];
    out]

(* {source, its parts as Wolfram 15's ToExpression[source, InputForm, HoldComplete] gives them, but for
   the Null it reads each blank line, the LF of a CRLF and each line of a comment alone as, which
   only part statements [W15 bug]; a statement that is Null is one *)
$wlStatementCases = {
    {"\n\na", {HoldComplete[a]}},
    {"a\n\nb", {HoldComplete[a], HoldComplete[b]}},
    {"a\n", {HoldComplete[a]}},
    {"a\n\n", {HoldComplete[a]}},
    {"", {}},
    {" ", {}},
    {"\n\n", {}},
    {"(* c *)\n(* d *)", {}},
    {"a\n(* c *)\n", {HoldComplete[a]}},
    {"a\n(* x\ny *)\nb", {HoldComplete[a], HoldComplete[b]}},
    {"a\r\n\r\nb", {HoldComplete[a], HoldComplete[b]}},
    {"a\r\rb", {HoldComplete[a], HoldComplete[b]}},
    {"a;\n\nb", {HoldComplete[CompoundExpression[a, Null]], HoldComplete[b]}},
    {"a\nb\n\nc\n", {HoldComplete[a], HoldComplete[b], HoldComplete[c]}},
    {"f[\n\n1]", {HoldComplete[f[1]]}},
    {"a\\\n\nb", {HoldComplete[a], HoldComplete[b]}},
    {"a\\\nb\nc", {HoldComplete[ab], HoldComplete[c]}},
    {"a\\[NewLine]\\[NewLine]b", {HoldComplete[a], HoldComplete[b]}},
    {"Null", {HoldComplete[Null]}},
    {"x\n\n?a*=b\n\ny\n", {HoldComplete[x], HoldComplete[Set[Information["a*", LongForm -> False], b]], HoldComplete[y]}}
};
Scan[
    Function[c, VerificationTest[wlParts[c[[1]]], c[[2]], TestID -> "wl next: " <> ToString[c[[1]], InputForm]]],
    $wlStatementCases]

(* {source, its parts up to the failure, which is the one WolframLanguageHeld gives} *)
$wlStatementFailures = {
    {"x = 1\n\n1 +", {HoldComplete[x = 1], {"Failure", 11, True, 7}}},
    {"a\n)", {HoldComplete[a], {"Failure", 4, False, 3}}},
    {"a )\nb", {{"Failure", 4, False, 1}}},
    {"a; b )\nc", {{"Failure", 7, False, 1}}},
    {"a\n\"abc", {HoldComplete[a], {"Failure", 7, True, 3}}},
    {"a\nb \\!", {HoldComplete[a], {"Failure", 5, False, 3}}},
    {"a )\nb \\!", {{"Failure", 4, False, 1}}},
    {"a = \\\n(b", {{"Failure", 9, True, 1}}},
    {"?a*=b )", {{"Failure", 8, False, 1}}},
    {"?a*=b\n)", {HoldComplete[Set[Information["a*", LongForm -> False], b]], {"Failure", 8, False, 7}}}
};
Scan[
    Function[c, VerificationTest[
        {wlParts[c[[1]]], wlStop[WolframLanguageHeld[c[[1]]]]},
        {c[[2]], c[[2, -1, 2 ;; 3]]},
        TestID -> "wl next failure: " <> ToString[c[[1]], InputForm]]],
    $wlStatementFailures]
VerificationTest[
    {WolframLanguageHeldNext["a\nbb\nc", 4], WolframLanguageHeldNext["a", 2]},
    {{HoldComplete[c], 7, <|"Warnings" -> {}|>}, EndOfFile},
    TestID -> "wl next: from a position no call gave, the statement whose line begins after it"]
VerificationTest[
    WolframLanguageHeldNext["wlNextFirst\nwlNextSecond", 1]; Names["*`wlNextSecond"],
    {},
    TestID -> "wl next: the names of a statement are made only when it is read"]
VerificationTest[
    Module[{pos = 1, r, out = {}},
        Block[{$Context = "WLNextTest`", $ContextPath = {"System`"}},
            While[ ListQ[r = WolframLanguageHeldNext["Begin[\"WLNextTest`Inner`\"]\nnamed\nEnd[]\nother", pos]],
                If[MatchQ[First[r], HoldComplete[_Symbol]], AppendTo[out, Context @@ First[r]], ReleaseHold[First[r]]];
                pos = r[[2]]]];
        out],
    {"WLNextTest`Inner`", "WLNextTest`"},
    TestID -> "wl next: a statement's names are made in the contexts of the moment it is read"]

(* the warnings WolframLanguageHeldNext gives a source, read from 1 up to a failure, those of the
   failure last *)
wlWarnings[s_String] := Module[{pos = 1, r, out = {}},
    While[ ListQ[r = WolframLanguageHeldNext[s, pos]],
        If[FailureQ[First[r]], out = Join[out, r[[1]]["Warnings"]]; Break[]];
        out = Join[out, r[[3, "Warnings"]]]; pos = r[[2]]];
    out]

(* {source, the Syntax warnings Wolfram 15's ToExpression gives as it reads it, each {tag} or {tag, argument}} *)
$wlWarningCases = {
    {"f[1,]", {{"com"}}},
    {"{,}", {{"com"}, {"com"}}},
    {"f[1,,2]", {{"com"}}},
    {"f[\\[InvisibleComma]]", {{"com"}, {"com"}}},
    {"<|a -> 1,|>", {{"com"}}},
    {"a\\[LeftDoubleBracket]1,\\[RightDoubleBracket]", {{"com"}}},
    {"\\[LeftAngleBracket]a,\\[RightAngleBracket]", {{"com"}}},
    {"f[1,", {{"com"}}},
    {"f[1, /b]", {{"com"}}},
    {"f[1, +2]", {}},
    {"f[1,]\nf[2,]", {{"com"}, {"com"}}},
    {"x = 1\nf[1,]\n1 +", {{"com"}}},
    {"a \\[Foo] b", {{"sntufn", "Foo"}}},
    {"f[x,\\[Foo]]", {{"sntufn", "Foo"}}},
    {"\\[Alpha", {{"sntufn", "Alpha"}}},
    {"(* \\[Foo] *) a", {}},
    {"\"a\\qb\"", {{"stresc", "q"}}},
    {"\"\\[Alpha]\\q\\w\"", {{"stresc", "q"}, {"stresc", "w"}}},
    {"\"\\8\"", {}},
    {"\"\\12\"", {{"sntoct1"}}},
    {"\"\\.1\"", {{"sntoct2"}}},
    {"\"\\:12\"", {{"snthex"}}},
    {"\"\\|12\"", {{"snthex32"}}},
    {"\"a\\[Foo]b\"", {{"sntufn", "Foo"}}},
    {"\"\\[Al-pha]\"", {{"sntufn", "Al"}}},
    {"\"\\[Foo\"", {{"sntunc", "Foo"}}},
    {"\"\\[FormalScriptA]\\[COMPATIBILITYKanjiSpace]\"", {}},
    {"x = \"a\\[Foo", {{"sntufn", "Foo"}}},
    {"x = 1; \"\\[\"", {{"sntmsng", "x = 1; \"\\[\""}}},
    {"{\"\\q\",}", {{"stresc", "q"}, {"com"}}},
    {"f[\"\\q\", 1 +", {{"stresc", "q"}}}
};
Scan[
    Function[c, VerificationTest[wlWarnings[c[[1]]], c[[2]], TestID -> "wl next warnings: " <> ToString[c[[1]], InputForm]]],
    $wlWarningCases]
VerificationTest[
    {WolframLanguageHeldNext["f[1,]", 1], WolframLanguageHeldNext["f[1,", 1][[1]]["Warnings"]},
    {{HoldComplete[f[1, Null]], 6, <|"Warnings" -> {{"com"}}|>}, {{"com"}}},
    TestID -> "wl next: a statement carries its warnings, a failure under its Warnings key"]

(* --- a plain source's program --- *)

(* the parts of a source's program, each statement built alone by the reader's build pass, None
   where it has no program *)
wlProgramParts[s_String] := With[{p = WolframLanguageProgram[s]},
    If[ p === None, None,
        With[{codes = p[[1]], prog = p[[2]], d = p[[3]], m = p[[3, 2]]},
            With[{kinds = d[[4 ;; 3 + m]], marks = d[[4 + m ;; 3 + 2 m]], texts = MapThread[FromCharacterCode[codes[[#1 ;; #2 - 1]]] &, {d[[4 + 2 m ;; 3 + 3 m]], d[[4 + 3 m ;; 3 + 4 m]]}]},
                Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fcodes = codes},
                    Map[If[#[[1]] === 0, HoldComplete[Null],
                        First[Wolfram`Parser`Languages`WolframLanguage`Private`fastBuild[prog[[3 #[[1]] ;; 3 #[[2]] + 2]], kinds[[#[[3]] ;; #[[4]]]], texts[[#[[3]] ;; #[[4]]]], marks[[#[[3]] ;; #[[4]]]]]]] &,
                        Partition[d[[4 + 4 m ;;]], 4]]]]]]]

(* the instructions the parser reads of a source, each {code, a, b} *)
wlInstructions[s_String] := With[{sym = Symbol["Wolfram`Parser`Languages`WolframLanguage`Private`" <> #] &, padded = Join[ToCharacterCode[s], {0, 0, 0}]},
    With[{prog = sym["fastParseTokens"][sym["fastLexFunction"] @@ Prepend[sym /@ {"$fastClasses", "$fastOp1", "$fastOp2Flat", "$fastOp3Table", "$fastLongOpTable", "$fastSpecial"}, padded], padded]},
        Partition[prog[[3 ;; 3 prog[[2]] + 2]], 3]]]

Scan[
    Function[c, VerificationTest[wlProgramParts[c[[1]]], If[StringContainsQ[c[[1]], "\\\n"], None, c[[2]]], TestID -> "wl program: " <> ToString[c[[1]], InputForm]]],
    $wlStatementCases]
VerificationTest[
    Union[WolframLanguageProgram /@ Join[$wlStatementFailures[[All, 1]], Select[$wlWarningCases, #[[2]] =!= {} &][[All, 1]]]],
    {None},
    TestID -> "wl program: a source that does not read whole, or that gives a warning, has none"]
VerificationTest[
    MatchQ[#, {_List, _List, _List}] & /@ (WolframLanguageProgram /@ {"f[1, +2]", "(* \\[Foo] *) a", "\"\\8\"",
        "{\"\\[Alpha]\\[FormalScriptA]\", \"\\[COMPATIBILITYNoBreak]\\[ \\101\\.41\\:0041\\n\"}"}),
    {True, True, True, True},
    TestID -> "wl program: a source that reads whole with no warning has one"]
VerificationTest[
    With[{private = "Wolfram`Parser`Languages`WolframLanguage`Private`"},
        Sort[Keys[Symbol[private <> "$fastLongNameOps"]]] === Sort[Keys[Symbol[private <> "longNameCharacters"][]]]],
    True,
    TestID -> "wl program: the lexer's long names are those a string decodes, as the typed escape scan reads them by the lexer's table"]
VerificationTest[
    WolframLanguageProgram["x = 1\n\ny = x + 1"][[3]],
    {0, 5, 2, 1, 3, 1, 1, 3, 0, 1, 0, 0, 1, 1, 5, 8, 12, 16, 2, 6, 9, 13, 17, 1, 4, 1, 2, 5, 10, 3, 5},
    TestID -> "wl program: the leaves' kinds, marks, starts and ends, and a row for each statement"]
VerificationTest[
    {WolframLanguageProgram[""], WolframLanguageProgram["{}"][[3]]},
    {{{}, {0, 0}, {0, 0, 0}}, {0, 0, 1, 1, 2, 1, 0}},
    TestID -> "wl program: a source with no statement has no parts; a statement with no leaf ends its leaves before they begin"]
VerificationTest[
    With[{flat = Wolfram`Parser`Languages`WolframLanguage`Private`flatProgram, s = "x = 1\n\ny = x + 1"},
        With[{f = flat[s], p = WolframLanguageProgram[s]},
            {Developer`PackedArrayQ[f], f === Join[{0, Length[p[[2]]]}, p[[2]], p[[3]], p[[1]]], flat[""], flat["f[1,]"]}]],
    {True, True, {0, 2, 0, 0, 0, 0, 0}, None},
    TestID -> "wl program: flat, the program, its parts and the source's codes in one array"]
VerificationTest[
    Developer`PackedArrayQ /@ WolframLanguageProgram["f[x_] := x^2\n\ng[1]"],
    {True, True, True},
    TestID -> "wl program: its codes, instructions and parts are packed"]
VerificationTest[
    Cases[wlInstructions[#], {11, a_, _} :> a] & /@ {"f[1,]", "{,}", "f[\\[InvisibleComma]]", "<|a -> 1,|>", "x[[1,]]", "a; b;", "f[a; , 1]"},
    {{1}, {1, 1}, {1, 1}, {1}, {1}, {0}, {0}},
    TestID -> "wl: the Null a comma leaves is marked, a semicolon's is not"]
VerificationTest[
    Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$heldNextStates = {}},
        WolframLanguageProgram["wlProgramName"]; {Wolfram`Parser`Languages`WolframLanguage`Private`$heldNextStates, Names["*`wlProgramName"]}],
    {{}, {}},
    TestID -> "wl program: nothing is kept for a call after it, and no name is made"]

(* --- linear syntax --- *)

(* {the text of a group, the boxes Wolfram 15's ToExpression["\\(" <> text <> "\\)", InputForm, HoldComplete] gives} *)
$wlLinearCases = {
    {"x\\^2", HoldComplete[SuperscriptBox["x", "2"]]},
    {"a + b c", HoldComplete[RowBox[{"a", "+", RowBox[{"b", "c"}]}]]},
    {"\\(a + b\\) c", HoldComplete[RowBox[{RowBox[{"a", "+", "b"}], "c"}]]},
    {"a\\ b", HoldComplete[RowBox[{"a", " ", "b"}]]},
    {"f[x]", HoldComplete[RowBox[{"f", "[", "x", "]"}]]},
    {"\"s\"", HoldComplete["\"s\""]},
    {"\\[Alpha]", HoldComplete["\[Alpha]"]},
    {"", HoldComplete[""]},
    {"\\*RowBox[{\"a\"}]", HoldComplete[RowBox[{"a"}]]},
    {"x\\_y\\%z", HoldComplete[SubsuperscriptBox["x", "y", "z"]]},
    {"\\@x\\%3", HoldComplete[RadicalBox["x", "3"]]},
    {"TraditionalForm\\`x", HoldComplete[FormBox["x", TraditionalForm]]},
    {"a; b", HoldComplete[RowBox[{"a", ";", "b"}]]},
    {"x\\&y", HoldComplete[OverscriptBox["x", "y"]]},
    {"1.5", HoldComplete["1.5"]},
    {"x\\^2\\^3", HoldComplete[SuperscriptBox["x", SuperscriptBox["2", "3"]]]},
    {"x\\^\\(2 + y\\)", HoldComplete[SuperscriptBox["x", RowBox[{"2", "+", "y"}]]]},
    {"f[x, y]", HoldComplete[RowBox[{"f", "[", RowBox[{"x", ",", "y"}], "]"}]]},
    {"x_", HoldComplete["x_"]},
    {"#1", HoldComplete["#1"]},
    {"x\\/y\\/z", HoldComplete[FractionBox[FractionBox["x", "y"], "z"]]},
    {"-x", HoldComplete[RowBox[{"-", "x"}]]},
    {"a\\tb", HoldComplete[RowBox[{"a", "\t", "b"}]]},
    {"12ab", HoldComplete[RowBox[{"12", "ab"}]]},
    {"\\@", HoldComplete[SqrtBox[""]]},
    {"x\\^", HoldComplete[SuperscriptBox["x", ""]]},
    {"\\^x", HoldComplete[SuperscriptBox["", "x"]]},
    {"<|a->1|>", HoldComplete[RowBox[{"\[LeftAssociation]", RowBox[{"a", "->", "1"}], "\[RightAssociation]"}]]},
    {"a\\[InvisibleSpace]b", HoldComplete[RowBox[{"a", "\[InvisibleSpace]", "b"}]]},
    {"a[[1]]", HoldComplete[RowBox[{"a", "[", RowBox[{"[", "1", "]"}], "]"}]]},
    {"a // f // g", HoldComplete[RowBox[{RowBox[{"a", "//", "f"}], "//", "g"}]]},
    {"a + b - c", HoldComplete[RowBox[{"a", "+", "b", "-", "c"}]]},
    {"a = b = c", HoldComplete[RowBox[{"a", "=", RowBox[{"b", "=", "c"}]}]]},
    {"f[x_] := x", HoldComplete[RowBox[{RowBox[{"f", "[", "x_", "]"}], ":=", "x"}]]},
    {"-a - b", HoldComplete[RowBox[{RowBox[{"-", "a"}], "-", "b"}]]},
    {"\\@x\\^2", HoldComplete[SqrtBox[SuperscriptBox["x", "2"]]]},
    {"x\\&y\\^z", HoldComplete[SuperscriptBox[OverscriptBox["x", "y"], "z"]]},
    {"x\\_y\\+z", HoldComplete[SubscriptBox["x", UnderscriptBox["y", "z"]]]},
    {"x\\^-1", HoldComplete[SuperscriptBox["x", RowBox[{"-", "1"}]]]},
    {"f[x\\^2]\\^3", HoldComplete[SuperscriptBox[RowBox[{"f", "[", SuperscriptBox["x", "2"], "]"}], "3"]]},
    {"\\[Sum]\\+\\(i = 1\\)\\%n i", HoldComplete[RowBox[{UnderoverscriptBox["\[Sum]", RowBox[{"i", "=", "1"}], "n"], "i"}]]},
    {"a\\ \\ b", HoldComplete[RowBox[{"a", " ", " ", "b"}]]},
    {"x\\+y\\%z", HoldComplete[UnderoverscriptBox["x", "y", "z"]]},
    {"x\\&y\\%z", HoldComplete[UnderoverscriptBox["x", "z", "y"]]},
    {"a \\(b\\) c", HoldComplete[RowBox[{"a", "b", "c"}]]}
};
Scan[
    Function[c, VerificationTest[WolframLanguageHeld["\\(" <> c[[1]] <> "\\)"], {c[[2]]}, TestID -> "wl linear: " <> ToString[c[[1]], InputForm]]],
    $wlLinearCases]

(* a group read as input, LinearBoxes of its boxes, and MakeExpression of them what Wolfram 15 reads from it *)
VerificationTest[
    Map[Function[s, With[{r = WolframLanguageHeld[s]}, {r, Cases[r, LinearBoxes[b_] :> MakeExpression[b, StandardForm], Infinity]}]],
        {"\\!\\(\\*RowBox[{\"a\", \"+\", \"b\"}]\\)", "\\!\\(a \\[CirclePlus] b\\)", "\\!\\(x\\^2\\)", "\\!\\(\\*FractionBox[\"1\", \"2\"]\\)"}],
    {{{HoldComplete[LinearBoxes[RowBox[{"a", "+", "b"}]]]}, {HoldComplete[a + b]}},
     {{HoldComplete[LinearBoxes[RowBox[{"a", "\[CirclePlus]", "b"}]]]}, {HoldComplete[CirclePlus[a, b]]}},
     {{HoldComplete[LinearBoxes[SuperscriptBox["x", "2"]]]}, {HoldComplete[x^2]}},
     {{HoldComplete[LinearBoxes[FractionBox["1", "2"]]]}, {HoldComplete[1/2]}}},
    TestID -> "wl linear: a group read as input is LinearBoxes of its boxes"]
VerificationTest[
    {WolframLanguageHeld["f[\\!\\(x\\^2\\)] + 1"], WolframLanguageHeld["\\!\\(x\\)\\!\\(y\\)"], WolframLanguageHeld["{\\(a\\), 1}"]},
    {{HoldComplete[f[LinearBoxes[SuperscriptBox["x", "2"]]] + 1]}, {HoldComplete[LinearBoxes["x"] LinearBoxes["y"]]}, {HoldComplete[{"a", 1}]}},
    TestID -> "wl linear: a group is an operand"]
VerificationTest[
    {wlStop[WolframLanguageHeld["\\!\\(x"]], WolframLanguageHeldNext["a = 1\n\\!\\(x\\^2\\)", 7]},
    {{6, True}, {HoldComplete[LinearBoxes[SuperscriptBox["x", "2"]]], 17, <|"Warnings" -> {}|>}},
    TestID -> "wl linear: a group not closed is incomplete; a statement of one reads one at a time"]

(* a colon after a pattern gives its default, and only there; a tilde's operands read as a notebook reads them *)
VerificationTest[
    WolframLanguageHeld /@ {"x_ | y_ : 1", "x_ : y_ : 1", "f[x:_:1]"},
    {{HoldComplete[x_ | (y_ : 1)]}, {HoldComplete[x_ : (y_ : 1)]}, {HoldComplete[f[x_ : 1]]}},
    TestID -> "wl: a colon after a pattern is its default"]
VerificationTest[
    {Map[{WolframLanguageSyntaxQ[#], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageSyntaxQ[#]]} &,
        {"x >> b[c", "x >>> b[c", "f[a::\"b]"}],
     WolframLanguageHeld /@ {"x >> b[c]", "x >> b[c].m", "<<b[c"}},
    {{{False, False}, {False, False}, {False, False}}, {{HoldComplete[Put[x, "b[c]"]]}, {HoldComplete[Put[x, "b[c].m"]]}, {HoldComplete[Get["b[c"]]}}},
    TestID -> "wl: after >> a file's [ is closed, as a notebook reads x >> b[c; a string not closed after :: runs to the end"]
(* a query that begins its statement reads as Wolfram 15's kernel reads it, which a notebook answers
   itself: after a name's letter the words, to an operator, an operator that is a prefix one too
   beginning a factor after them; after anything else the rest of the line *)
VerificationTest[
    WolframLanguageHeld /@ {"?*)a", "?<<a", "?}a", "?@@%3", "?*a b+c", "?`a+b", "?  [a", "?*a ", "?a+b", "?a-b", "?a b+c", "?$a+b", "?a*=b", "?a//b"},
    List /@ {HoldComplete[Information["*)a", Rule[LongForm, False]]],
        HoldComplete[Information["<<a", Rule[LongForm, False]]],
        HoldComplete[Information["}a", Rule[LongForm, False]]],
        HoldComplete[Information["@@%3", Rule[LongForm, False]]],
        HoldComplete[Information["*a b+c", Rule[LongForm, False]]],
        HoldComplete[Information["`a+b", Rule[LongForm, False]]],
        HoldComplete[Information["[a", Rule[LongForm, False]]],
        HoldComplete[Information["*a", Rule[LongForm, False]]],
        HoldComplete[Times[Information["a", Rule[LongForm, False]], Plus[b]]],
        HoldComplete[Times[Information["a", Rule[LongForm, False]], Times[-1, b]]],
        HoldComplete[Times[Information["a b", Rule[LongForm, False]], Plus[c]]],
        HoldComplete[Times[Information["$a", Rule[LongForm, False]], Plus[b]]],
        HoldComplete[Set[Information["a*", Rule[LongForm, False]], b]],
        HoldComplete[b[Information["a", Rule[LongForm, False]]]]},
    TestID -> "wl query: one that begins its statement reads as Wolfram 15's kernel reads it"]
VerificationTest[
    {WolframLanguageSyntaxQ["?a!"], WolframLanguageHeld /@ {"16^^ff..", "16^^ff..;;", "16^^ff.f", "16^^ff."}},
    {False, {{HoldComplete[Repeated[255]]}, {HoldComplete[Span[Repeated[255], All]]}, {HoldComplete[255.9375]}, {HoldComplete[255.]}}},
    TestID -> "wl: a factorial after a query that begins its statement is none; a based number's point is not before another"]
VerificationTest[
    WolframLanguageSyntaxQ /@ {"f[??a b]", "f[?a*]", "a?b?c", "a ? b ? c", "(a?b)?c"},
    {False, False, False, False, True},
    TestID -> "wl: a ?? that does not begin its statement takes a word alone; a ? after a pattern test is no Wolfram Language"]
VerificationTest[
    {WolframLanguageSyntaxQ /@ {"a ~ b & ~ c", "a ~ f! ~ b", "a ~ f' ~ b", "a ~ f.. ~ b"}, WolframLanguageHeld /@ {"a ~ f++ ~ b", "a ~ (f&) ~ b", "a ~ b ~ c ~ d ~ e"}},
    {{False, False, False, False}, {{HoldComplete[Increment[f][a, b]]}, {HoldComplete[Function[f][a, b]]}, {HoldComplete[d[b[a, c], e]]}}},
    TestID -> "wl: a tilde's function binds more tightly than ~; tildes group to the left"]
VerificationTest[
    wlStop /@ (WolframLanguageHeld /@ {"f[x] : 1", "x_. : 1", "a ~ b c", "a ~ b"}),
    {{7, False}, {6, False}, {8, True}, {6, True}},
    TestID -> "wl failure: a colon after no pattern; a tilde with no second"]

(* << after an operand on its line is a factor, as the kernel reads it *)
VerificationTest[
    WolframLanguageHeld /@ {"a<<b", "f[a<<b]", "a<<b + 1", "2<<b.m", "a\n<<b"},
    {{HoldComplete[a Get["b"]]}, {HoldComplete[f[a Get["b"]]]}, {HoldComplete[a Get["b"] + 1]}, {HoldComplete[2 Get["b.m"]]}, {HoldComplete[a], HoldComplete[Get["b"]]}},
    TestID -> "wl: << after an operand is a factor"]
VerificationTest[
    WolframLanguageHeldNext["a<<b\nc", 1],
    {HoldComplete[a Get["b"]], 6, <|"Warnings" -> {}|>},
    TestID -> "wl next: << after an operand is a factor"]

(* a real is the machine real nearest its digits, as Wolfram 15's ToExpression and a notebook read
   it, where N of the exact value can be a bit away; the digits of FullForm tell machine reals apart
   that SameQ takes for one *)
VerificationTest[
    Map[ToString[FullForm[First[First[WolframLanguageHeld[#]]]]] &, {"0.00000000000000000001234", "1.234*^-20", "2.2250738585072014*^-308", "0.3", "7.*^-300", "0.000000001234"}],
    {"1.234`*^-20", "1.234`*^-20", "2.2250738585072014`*^-308", "0.3`", "7.`*^-300", "1.234`*^-9"},
    TestID -> "wl number: a real is the machine real nearest its digits"]

(* a minus folds into an integer or a real right after it, not into a rational, as a notebook reads -1*^-3 *)
VerificationTest[
    WolframLanguageHeld /@ {"-1*^-3", "a - 2*^-1", "-16^^f*^-1", "-1.5*^-3", "-2*^3"},
    {{HoldComplete[Times[-1, Rational[1, 1000]]]}, {HoldComplete[Plus[a, Times[-1, Rational[1, 5]]]]}, {HoldComplete[Times[-1, Rational[15, 16]]]},
     {HoldComplete[-0.0015]}, {HoldComplete[-2000]}},
    TestID -> "wl: a minus folds into an integer or a real, not a rational"]

(* a unary plus is its own call, in a chain of Plus too, as a notebook reads it *)
VerificationTest[
    WolframLanguageHeld /@ {"+b", "+b - 1", "a + +b", "(+a) + b", "a - +b", "x + +y z", "a >+ b - c"},
    {{HoldComplete[Plus[b]]}, {HoldComplete[Plus[Plus[b], -1]]}, {HoldComplete[Plus[a, Plus[b]]]}, {HoldComplete[Plus[Plus[a], b]]},
     {HoldComplete[Plus[a, Times[-1, Plus[b]]]]}, {HoldComplete[Plus[x, Times[Plus[y], z]]]}, {HoldComplete[Greater[a, Plus[Plus[b], Times[-1, c]]]]}},
    TestID -> "wl: a unary plus is its own call, in a chain of Plus too"]

(* a slot's name is read as a name is, $, contexts and long names in it; ## takes digits only *)
VerificationTest[
    WolframLanguageHeld /@ {"#$name", "#a$b", "#a`b", "#`a", "##abc", "#\\[Alpha]"},
    {{HoldComplete[Slot["$name"]]}, {HoldComplete[Slot["a$b"]]}, {HoldComplete[Slot["a`b"]]}, {HoldComplete[Slot["`a"]]},
     {HoldComplete[Times[SlotSequence[1], abc]]}, {HoldComplete[Slot["\[Alpha]"]]}},
    TestID -> "wl: a slot's name is a name"]
VerificationTest[
    WolframLanguageSyntaxLength /@ {"#a`", "x = #a`", "f[#a`]"},
    {3, 4, 2},
    TestID -> "wl syntax: a slot's malformed name makes no slot"]

(* the reader's character classes, read from WolframLanguageClasses.wl, are the table Wolfram 15 computes *)
VerificationTest[
    {Wolfram`Parser`Languages`WolframLanguage`Private`$fastClasses === Wolfram`Parser`Languages`WolframLanguage`Private`fastClassesComputed[],
     Developer`PackedArrayQ[Wolfram`Parser`Languages`WolframLanguage`Private`$fastClasses]},
    {True, True},
    TestID -> "wl: the character class file is the table Wolfram 15 computes"]

(* {a number's text, Wolfram 15's value of it}: the subnormal machine real nearest it, zero where
   that is nearer, past the greatest machine real the value at machine precision, a zero of a
   precision exact where it is an integer's, and an integer before a mark with no precision its
   value as a machine real *)
$wlNumberCases = {
    {"1.*^-310", 1.*^-310},
    {"5.*^-324", 5.*^-324},
    {"3.*^-324", 5.*^-324},
    {"2.*^-324", 0.},
    {"2^^1.*^-1074", 5.*^-324},
    {"2.2250738585072013*^-308", 2.2250738585072014*^-308},
    {"1.*^-1000000", 0.},
    {"1.*^1355718576299609", 1.`15.954589770191005*^1355718576299609},
    {"1.7976931348623158*^308", 1.7976931348623157*^308},
    {"0`", 0.},
    {"0`10", 0},
    {"0.`10", 0.},
    {"108`", 108.},
    {"108`*^2", 10800.},
    {"007`", 7.},
    {"108.`", 108.},
    {"16^^ff`", 255.},
    {"713`*^316", 7.13`15.954589770191005*^318},
    {"92615557861408081889`*^-327", 9.261555786140807*^-308},
    {"0*^279617642866175", 0},
    {"1.*^-1355718576299610", Underflow[]},
    {"8^^6.`14", 6.`12.64325981788721}
};
Scan[
    Function[c, VerificationTest[
        With[{v = First[First[WolframLanguageHeld[c[[1]]]]]}, {v, MachineNumberQ[v], Precision[v]}],
        {c[[2]], MachineNumberQ[c[[2]]], Precision[c[[2]]]},
        TestID -> "wl number: " <> c[[1]]]],
    $wlNumberCases]
VerificationTest[
    MachineNumberQ[First[First[WolframLanguageHeld[#]]]] & /@ {"36^^q.au24lt7bgdl1", "36^^q.au24lt7bgdl1*^1", "16^^fffffffffffffff.", "16^^ffffffffffffffff.",
        "8^^1234567012345670123.", "8^^12345670123456701234.", "2^^1" <> StringRepeat["0", 52] <> ".", "2^^1" <> StringRepeat["0", 53] <> "."},
    {False, True, True, False, True, False, True, False},
    TestID -> "wl number: a machine real holds Floor[53 / Log2[b]] + 2 digits of base b, 53 of base 2, never fewer than 17 with a power of the base"]

(* SyntaxQ and SyntaxLength as Wolfram 15 gives them for each source *)
$wlSyntaxCases = {
    {"", False, 0},
    {"a =[b] c", True, 8},
    {"<<a|b", True, 5},
    {"f[<<]", False, 2},
    {"a + =[b", False, 5},
    {"=[b", False, 3},
    {" ", True, 1},
    {"a", True, 1},
    {"a + b c", True, 7},
    {"a + b)", False, 5},
    {"f[x", False, 5},
    {"f[x)", False, 3},
    {"a +", False, 5},
    {"a\nb", True, 3},
    {"a\n)", False, 2},
    {"x = 1\n1 +", False, 11},
    {"(* c *)", True, 7},
    {"(* c", False, 4},
    {"\"abc", False, 4},
    {"  (* c", False, 3},
    {"a + \"abc", False, 5},
    {"a\n\"abc", False, 2},
    {"a)b", False, 1},
    {"f[x]]", False, 4},
    {"]", False, 0},
    {"a::", False, 2},
    {"a::1", True, 4},
    {"a::b::c::", False, 7},
    {"f[x] ::=", False, 5},
    {"       A ::= A", False, 9},
    {"?a*=b", True, 5},
    {"f[1,]", True, 5},
    {"a \\[Foo] b", False, 2},
    {"\\[Foo]", False, 6},
    {"x = a\\[Foo]", False, 4},
    {"a`", False, 2},
    {"x = a`", False, 4},
    {"a\\b", False, 1},
    {"f[x] : y", False, 5},
    {"x_ : 1", True, 6},
    {"x_ | y_ : 1", True, 11},
    {"x_. : 1", False, 4},
    {"a ~ b c", False, 9},
    {"a ~ b & ~ c", False, 13},
    {"i ~ s t, u", False, 7},
    {"<|a -> 1", False, 10},
    {"\\!\\(x\\^2\\)", True, 10},
    {"\\!\\(x", False, 7},
    {"a\\\nb", True, 4},
    {"a\\\n)", False, 3},
    {"f[\nx\n", False, 7},
    {"<<", False, 2},
    {"x = <<", False, 4},
    {"t/:a", False, 4},
    {"t/:a\n", False, 4},
    {"t/:", False, 5},
    {"1 + (2", False, 8},
    {"(* c *) )", False, 8},
    {"0``", False, 1},
    {"1.5``", False, 3},
    {"f[1``]", False, 3},
    {"1``-", False, 1},
    {"1```", False, 1},
    {"1``+.5", True, 6},
    {"1``-3", True, 5}
};
Scan[
    Function[c, VerificationTest[{WolframLanguageSyntaxQ[c[[1]]], WolframLanguageSyntaxLength[c[[1]]]}, Rest[c], TestID -> "wl syntax: " <> ToString[c[[1]], InputForm]]],
    $wlSyntaxCases]
VerificationTest[
    WolframLanguageSyntaxQ["aNameOnlyChecked + 1"]; Names["*`aNameOnlyChecked"],
    {},
    TestID -> "wl syntax: checking a source makes none of its names"]

(* where a token is two, the reader splits it and reads on, with no grammar: the words of a query
   that end inside an operator, a message name's tag and a blank in one token *)
VerificationTest[
    {WolframLanguageHeld["?a*=b"], WolframLanguageHeld["??a*=b"], WolframLanguageHeld["?a*:=b"], WolframLanguageHeld["?x`*"]},
    {{HoldComplete[Information["a*", LongForm -> False] = b]}, {HoldComplete[Information["a*", LongForm -> True] = b]},
     {HoldComplete[Information["a*", LongForm -> False] := b]}, {HoldComplete[Information["x`*", LongForm -> False]]}},
    TestID -> "wl: the words of a query that end inside a token, the token split there"]

(* === message names, as a notebook reads them: after each ::, a word of one token, a name, a
   number, a blank, a slot or a %, is its text, a string its value; a group, a prefix operator and
   its operand, and a name or a blank with a colon after it, the pattern, are the expression; each
   :: adds a part. Wolfram 15's kernel takes names and strings alone, two at most === *)
$wlMessageNames = {
    {"a::b_", List[HoldComplete[MessageName[a, "b_"]]]},
    {"a::b_c", List[HoldComplete[MessageName[a, "b_c"]]]},
    {"f[a::b_]", List[HoldComplete[f[MessageName[a, "b_"]]]]},
    {"x = a::b_ + 1", List[HoldComplete[Set[x, Plus[MessageName[a, "b_"], 1]]]]},
    {"a::_", List[HoldComplete[MessageName[a, "_"]]]},
    {"a::b::_", List[HoldComplete[MessageName[a, "b", "_"]]]},
    {"x_::_h", List[HoldComplete[MessageName[Pattern[x, Blank[]], "_h"]]]},
    {"a::1", List[HoldComplete[MessageName[a, "1"]]]},
    {"a::1.5", List[HoldComplete[MessageName[a, "1.5"]]]},
    {"a::1a", List[HoldComplete[Times[MessageName[a, "1"], a]]]},
    {"a::2^c", List[HoldComplete[Power[MessageName[a, "2"], c]]]},
    {"a::#", List[HoldComplete[MessageName[a, "#"]]]},
    {"a::%", List[HoldComplete[MessageName[a, "%"]]]},
    {"a:: b", List[HoldComplete[MessageName[a, "b"]]]},
    {"a::b::c::d::e", List[HoldComplete[MessageName[a, "b", "c", "d", "e"]]]},
    {"x::y::1", List[HoldComplete[MessageName[x, "y", "1"]]]},
    {"a::(b)", List[HoldComplete[MessageName[a, b]]]},
    {"a::(b)c", List[HoldComplete[Times[MessageName[a, b], c]]]},
    {"a::{b}", List[HoldComplete[MessageName[a, List[b]]]]},
    {"a::(b::c)", List[HoldComplete[MessageName[a, MessageName[b, "c"]]]]},
    {"a::b::(c::d)", List[HoldComplete[MessageName[a, "b", MessageName[c, "d"]]]]},
    {"a::-b", List[HoldComplete[MessageName[a, Times[-1, b]]]]},
    {"a::-b+c", List[HoldComplete[Plus[MessageName[a, Times[-1, b]], c]]]},
    {"a::!b&&c", List[HoldComplete[And[MessageName[a, Not[b]], c]]]},
    {"a::b::-c", List[HoldComplete[MessageName[a, "b", Times[-1, c]]]]},
    {"a::<<c", List[HoldComplete[MessageName[a, Get["c"]]]]},
    {"a::?b", List[HoldComplete[MessageName[a, Information["b", Rule[LongForm, False]]]]]},
    {"a::b:c", List[HoldComplete[MessageName[a, Pattern[b, c]]]]},
    {"a::b:c+d", List[HoldComplete[MessageName[a, Pattern[b, Plus[c, d]]]]]},
    {"a::b:c:d", List[HoldComplete[MessageName[a, Optional[Pattern[b, c], d]]]]},
    {"a::b_:c", List[HoldComplete[MessageName[a, Optional[Pattern[b, Blank[]], c]]]]},
    {"a::b:_", List[HoldComplete[MessageName[a, Pattern[b, Blank[]]]]]},
    {"a::b:=c", List[HoldComplete[SetDelayed[MessageName[a, "b"], c]]]},
    {"a::b c::d", List[HoldComplete[Times[MessageName[a, "b"], MessageName[c, "d"]]]]},
    {"a::b[[1]]", List[HoldComplete[Part[MessageName[a, "b"], 1]]]},
    {"a::b!", List[HoldComplete[Factorial[MessageName[a, "b"]]]]},
    {"a::b~c~d", List[HoldComplete[c[MessageName[a, "b"], d]]]},
    (* a string not closed right after a ::: a word of its text to the end of the source *)
    {"a::\"b", List[HoldComplete[MessageName[a, "\"b"]]]},
    {"a::\"b c", List[HoldComplete[MessageName[a, "\"b c"]]]},
    {"a::b::\"c", List[HoldComplete[MessageName[a, "b", "\"c"]]]},
    {"x = a::\"b", List[HoldComplete[Set[x, MessageName[a, "\"b"]]]]}
};
Scan[
    Function[c, VerificationTest[
        {WolframLanguageHeld[c[[1]]], Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$fastHeldReader = False}, WolframLanguageHeld[c[[1]]]]},
        {c[[2]], c[[2]]},
        TestID -> "wl message name, reader and grammar: " <> c[[1]]]],
    $wlMessageNames]

(* a . after __ or ___ is a token of its own, a Dot or the start of a number, and after a single _
   an Optional's; right after a ., a prefix operator begins an operand, as a notebook reads it,
   where Wolfram 15's kernel reads none for one that is infix or postfix too *)
VerificationTest[
    With[{sources = {"__._", "x__.y", "__.1", "__..", "___.a", "_._", "x_.y", "f[x__.]"}},
        {WolframLanguageHeld /@ Most[sources], WolframLanguageSyntaxQ[Last[sources]]}],
    {List /@ (ToExpression[#, InputForm, HoldComplete] & /@ {"__._", "x__.y", "__.1", "__..", "___.a", "_._", "x_.y"}), False},
    TestID -> "wl: a . after __ or ___ is a Dot or a number, after a single _ an Optional's"]
VerificationTest[
    WolframLanguageHeld /@ {"a . -b", "a.!b", "a . ++b", "a.\\[PlusMinus]b", "b . - c", "a.b.!c", "a.!b.c", "a . \\[Sqrt]b"},
    List /@ {HoldComplete[Dot[a, Times[-1, b]]], HoldComplete[Dot[a, Not[b]]], HoldComplete[Dot[a, PreIncrement[b]]], HoldComplete[Dot[a, PlusMinus[b]]],
        HoldComplete[Dot[b, Times[-1, c]]], HoldComplete[Dot[a, b, Not[c]]], HoldComplete[Dot[a, Not[Dot[b, c]]]], HoldComplete[Dot[a, Sqrt[b]]]},
    TestID -> "wl: right after a ., a prefix operator begins an operand"]

(* the words of a query that reach a backslash past the last token the lexer read end there, each
   entry returning at once *)
VerificationTest[
    Map[Function[s, MatchQ[TimeConstrained[{WolframLanguageSyntaxQ[s], WolframLanguageSyntaxLength[s], WolframLanguageHeld[s]}, 5, $Aborted], {_, _, _}]],
        {"?\\[\n??/:", "?\\[Foo]16^^ff].5", "??\t@@\\[Foo]", "?a\\["}],
    {True, True, True, True},
    TestID -> "wl: the words of a query end at a backslash the tokens do not reach"]

VerificationTest[
    {Take[WolframLanguageHeldNext["?a*=b\na::b_", 1], 2], Take[WolframLanguageHeldNext["?a*=b\na::b_", 7], 2]},
    {{HoldComplete[Information["a*", LongForm -> False] = b], 7}, {HoldComplete[MessageName[a, "b_"]], 12}},
    TestID -> "wl: one statement at a time, the tokens that are two split too"]

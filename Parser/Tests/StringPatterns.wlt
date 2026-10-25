(* The engine of string patterns, Wolfram`Parser`StringPatterns`, held to Wolfram 15's own String
   functions: the texts of the matches as StringCases gives them, their spans as StringPosition
   gives them, the rules that matched and the names they bound. *)

Needs["Wolfram`Parser`"]

(* the matches of the patterns from the left, in the mode "First", "Each" or "Overlapping" *)
engineMatches[s_String, patterns_List, mode_String] := StringPatternMatches[s, StringPatternProgram /@ patterns, mode]
(* the texts of the matches, as StringCases takes them *)
engineCases[s_String, p_] := Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, engineMatches[s, Flatten[{p}], "Each"]]
(* the value of the right side of the rule that made the match, its names bound to their text *)
ruleValue[rules_List, m_List] := Replace[Extract[rules, m[[3]], Hold], Hold[(Rule | RuleDelayed)[_, rhs_]] :> ReleaseHold[ReplaceAll[Hold[rhs], m[[4]]]]]
engineRuleCases[s_String, rules_List] := Map[ruleValue[rules, #] &, engineMatches[s, First /@ rules, "Each"]]
(* the text with each match replaced by its rule's value, as StringReplace takes the matches *)
engineReplace[s_String, rules_List] := With[{matches = engineMatches[s, First /@ rules, "First"]},
    StringJoin[Riffle[
        Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, Partition[Join[{0}, Catenate[Map[Take[#, 2] &, matches]], {StringLength[s]}], 2]],
        Map[ruleValue[rules, #] &, matches]]]]
(* the spans of the matches, at every start *)
enginePosition[s_String, p_] := Map[{#[[1]] + 1, #[[2]]} &, engineMatches[s, Flatten[{p}], "Overlapping"]]
(* whether the whole string matches *)
engineMatchQ[s_String, p_] := engineMatches[s, {StartOfString ~~ p ~~ EndOfString}, "First"] =!= {}

VerificationTest[
    {engineRuleCases["abc", {"a" -> "1", "ab" -> "2"}], engineCases["abc", "a" | "ab"], engineRuleCases["aXbXc", {"X" | "Xb" -> "_"}]},
    {StringCases["abc", {"a" -> "1", "ab" -> "2"}], StringCases["abc", "a" | "ab"], StringCases["aXbXc", "X" | "Xb" -> "_"]},
    TestID -> "string patterns: the rules and the alternatives in the order given, the first that matches taken"
]

VerificationTest[
    {engineRuleCases["<a><b>", {"<" ~~ Shortest[x__] ~~ ">" :> x}], engineRuleCases["<a><b>", {"<" ~~ x__ ~~ ">" :> x}]},
    {StringCases["<a><b>", "<" ~~ Shortest[x__] ~~ ">" :> x], StringCases["<a><b>", "<" ~~ x__ ~~ ">" :> x]},
    TestID -> "string patterns: a repeat the longest first, or the shortest in Shortest"
]

VerificationTest[
    {engineRuleCases["abcabc", {x : ("a" | "b") .. :> x}], engineCases["aaa", ""], engineCases["a1b22c", DigitCharacter ..]},
    {StringCases["abcabc", x : ("a" | "b") .. :> x], StringCases["aaa", ""], StringCases["a1b22c", DigitCharacter ..]},
    TestID -> "string patterns: a named repeat, an empty match a character after another"
]

VerificationTest[
    {engineRuleCases["hello world", {WordBoundary ~~ x : LetterCharacter ~~ ___ :> x}], engineRuleCases["a1b2", {x_ ~~ y_ /; DigitQ[y] :> {x, y}}],
     engineRuleCases["a1b2", {x_?LetterQ :> x}]},
    {StringCases["hello world", WordBoundary ~~ x : LetterCharacter ~~ ___ :> x], StringCases["a1b2", x_ ~~ y_ /; DigitQ[y] :> {x, y}],
     StringCases["a1b2", x_?LetterQ :> x]},
    TestID -> "string patterns: a word boundary, a condition and a test checked on what matched"
]

VerificationTest[
    {engineRuleCases["abab", {x__ ~~ x__ :> x}], engineRuleCases["ab\ncd", {StartOfLine ~~ x_ :> x}], engineRuleCases["ab\ncd", {x_ ~~ EndOfLine :> x}]},
    {StringCases["abab", x__ ~~ x__ :> x], StringCases["ab\ncd", StartOfLine ~~ x_ :> x], StringCases["ab\ncd", x_ ~~ EndOfLine :> x]},
    TestID -> "string patterns: a name twice matches the same text, the starts and ends of lines"
]

VerificationTest[
    engineCases["a -1.5 2. .5 +3 1e5 12", NumberString],
    StringCases["a -1.5 2. .5 +3 1e5 12", NumberString],
    TestID -> "string patterns: NumberString"
]

VerificationTest[
    {engineCases["Try-me.wl!", Except[WordCharacter | "-" | "." | "/"]],
     engineRuleCases["x $a$ y $$b$$", {"$$" ~~ m : Shortest[__] ~~ "$$" :> "[" <> m <> "]", "$" ~~ m : Shortest[Except["$"] ..] ~~ "$" :> "(" <> m <> ")"}]},
    {StringCases["Try-me.wl!", Except[WordCharacter | "-" | "." | "/"]],
     StringCases["x $a$ y $$b$$", {"$$" ~~ m : Shortest[__] ~~ "$$" :> "[" <> m <> "]", "$" ~~ m : Shortest[Except["$"] ..] ~~ "$" :> "(" <> m <> ")"}]},
    TestID -> "string patterns: Except of a class, shortest repeats among rules"
]

VerificationTest[
    {enginePosition["aaa", "a" ~~ "a"], engineRuleCases["one two three", {w : LetterCharacter .. /; StringLength[w] > 3 :> ToUpperCase[w]}],
     engineCases["a,b;c", Except[{",", ";"}] ..], engineRuleCases["k=1, j=22", {(a : LetterCharacter) ~~ "=" ~~ (b : DigitCharacter ..) :> a -> b}]},
    {StringPosition["aaa", "a" ~~ "a"], StringCases["one two three", w : LetterCharacter .. /; StringLength[w] > 3 :> ToUpperCase[w]],
     StringCases["a,b;c", Except[{",", ";"}] ..], StringCases["k=1, j=22", (a : LetterCharacter) ~~ "=" ~~ (b : DigitCharacter ..) :> a -> b]},
    TestID -> "string patterns: overlapping spans, a condition on a repeat, Except of characters, two names"
]

VerificationTest[
    {engineCases["\\[ x \\]", "\\" ~~ ("[" | "]")], engineCases["x1y2", {"x", "y"} ~~ DigitCharacter], engineCases["abc", _], enginePosition["h\[EAcute]llo", "l" ..],
     engineCases["one two  three", Except[WhitespaceCharacter] ..], engineCases["a, b,c", "," ~~ Whitespace ...]},
    {StringCases["\\[ x \\]", "\\" ~~ ("[" | "]")], StringCases["x1y2", {"x", "y"} ~~ DigitCharacter], StringCases["abc", _], StringPosition["h\[EAcute]llo", "l" ..],
     StringCases["one two  three", Except[WhitespaceCharacter] ..], StringCases["a, b,c", "," ~~ Whitespace ...]},
    TestID -> "string patterns: characters, a list of characters, any character, whitespace"
]

VerificationTest[
    {engineMatchQ["abc", "a" ~~ __], engineMatchQ["abc", "b" ~~ __], engineMatchQ["2024", Repeated[DigitCharacter, {4, 4}]],
     engineMatchQ["abc123", LetterCharacter .. ~~ DigitCharacter ..], engineMatchQ["abc12x", LetterCharacter .. ~~ DigitCharacter ..]},
    {StringMatchQ["abc", "a" ~~ __], StringMatchQ["abc", "b" ~~ __], StringMatchQ["2024", Repeated[DigitCharacter, {4, 4}]],
     StringMatchQ["abc123", LetterCharacter .. ~~ DigitCharacter ..], StringMatchQ["abc12x", LetterCharacter .. ~~ DigitCharacter ..]},
    TestID -> "string patterns: a whole string matched between its start and its end"
]

(* the classes beyond ASCII: the decimal digits of every script, the other numerals word characters,
   the letters of every script *)
$classCharacters = FromCharacterCode /@ {16^^0663, 16^^0969, 16^^0E53, 16^^FF11, 16^^1D7D1, 16^^00B2, 16^^2163, 16^^00E9, 16^^03B1, 16^^1D4B6};

VerificationTest[
    Map[Function[c, Select[$classCharacters, engineMatchQ[#, c] &]], {DigitCharacter, WordCharacter, LetterCharacter}],
    Map[Function[c, Select[$classCharacters, StringMatchQ[#, c] &]], {DigitCharacter, WordCharacter, LetterCharacter}],
    TestID -> "string patterns: digits, word characters and letters beyond ASCII are Wolfram 15's"
]

(* every whitespace and hexadecimal character Wolfram 15 takes, of the codes below 65536 *)
VerificationTest[
    Map[Function[c, Flatten[Position[StringPatternProgram[c]["ClassCodes"], 1]] - 1 === Select[Range[0, 65535], StringMatchQ[FromCharacterCode[#], c] &]],
        {WhitespaceCharacter, HexadecimalCharacter, PunctuationCharacter, DigitCharacter}],
    {True, True, True, True},
    TestID -> "string patterns: the codes of a class are Wolfram 15's, whitespace and hexadecimal digits too"
]

VerificationTest[
    With[{s = StringJoin[FromCharacterCode /@ Range[0, 12300]]}, {engineCases[s, WhitespaceCharacter ..], engineCases[s, PunctuationCharacter ~~ DigitCharacter]}],
    With[{s = StringJoin[FromCharacterCode /@ Range[0, 12300]]}, {StringCases[s, WhitespaceCharacter ..], StringCases[s, PunctuationCharacter ~~ DigitCharacter]}],
    TestID -> "string patterns: runs of classes in a text of many scripts"
]

(* what a kernel asks of a program to choose how to match *)
VerificationTest[
    With[{p = StringPatternProgram[DigitCharacter ..]}, {p["Program"] =!= None, p["RegexLike"], p["RegexFinds"], MatchQ[p["Class"], {_, 1, Infinity}], MatchQ[p["Run"], {_, 1}], p["ClassCodes"]}],
    {True, True, True, True, True, None},
    TestID -> "string patterns: a repeat of a class, as a regex matches it and a run of the class"
]

(* a repeat of more than one character may give characters to a later part, where a regex's
   leftmost longest match takes them: "a"... ~~ "ab"... ~~ "b" matches "aab" of "aabb", a regex all *)
VerificationTest[
    {StringPatternProgram["a"... ~~ "ab"... ~~ "b"]["RegexLike"], engineCases["aabb", "a"... ~~ "ab"... ~~ "b"], StringPatternProgram[DigitCharacter .. ~~ "a"..]["RegexLike"],
     StringPatternProgram["<" ~~ __ ~~ ">"]["RegexLike"]},
    {False, StringCases["aabb", "a"... ~~ "ab"... ~~ "b"], True, True},
    TestID -> "string patterns: a regex does not match as a repeat of more than one character does"
]

VerificationTest[
    {StringPatternProgram["a" | "ab"]["RegexLike"], StringPatternProgram["a" | "ab"]["RegexFinds"], StringPatternProgram[x__ ~~ x__]["RegexFinds"],
     StringPatternProgram[Shortest["a" ..]]["RegexLike"], StringPatternProgram["a" ...]["RegexFinds"], StringPatternProgram["a" ~~ "b"]["Class"]},
    {False, True, False, False, False, None},
    TestID -> "string patterns: what a regex does not match as the program does"
]

VerificationTest[
    With[{codes = StringPatternProgram[WhitespaceCharacter]["ClassCodes"]}, {Length[codes], Developer`PackedArrayQ[codes], codes[[{33, 161, 66}]]}],
    {65536, True, {1, 1, 0}},
    TestID -> "string patterns: the table of the codes of a class of one character"
]

VerificationTest[
    {StringPatternProgram[RegularExpression["a+"]]["Program"], StringPatternProgram[f[x]]["RegexLike"], StringPatternMatches["ab", {StringPatternProgram[RegularExpression["a"]]}, "Each"]},
    {None, False, None},
    TestID -> "string patterns: a pattern with a part that no program has"
]

VerificationTest[
    {StringPatternMatches["a1b", StringPatternProgram[x : DigitCharacter], "Each"], StringPatternMatches["", StringPatternProgram["a" ...], "Overlapping"]},
    {{{1, 2, 1, {HoldPattern[x] -> "1"}}}, {{0, 0, 1, {}}}},
    TestID -> "string patterns: a match is its start, its end, its program and the names it bound"
]

VerificationTest[
    {engineRuleCases["b", {"x"... -> 1, ___ -> 2}], engineRuleCases["ab", {"x"... -> 1, "y"... -> 2, "a" -> 3}], engineCases["ab", {"x"..., "a"}], engineCases["ab", "x"... | "a"]},
    {StringCases["b", {"x"... -> 1, ___ -> 2}], StringCases["ab", {"x"... -> 1, "y"... -> 2, "a" -> 3}], StringCases["ab", {"x"..., "a"}], StringCases["ab", "x"... | "a"]},
    TestID -> "string patterns: in a list, the next pattern is tried where one matched nothing"
]

VerificationTest[
    {enginePosition["aaa", {"a", "aa"}], enginePosition["b", {"x"..., ___}], enginePosition["aaa", "a" | "aa"]},
    {StringPosition["aaa", {"a", "aa"}], StringPosition["b", {"x"..., ___}], StringPosition["aaa", "a" | "aa"]},
    TestID -> "string patterns: overlapping, every pattern of a list that matches at a start"
]

VerificationTest[
    {engineReplace["ab", {"x"... -> "1", "a" -> "2"}], engineReplace["ab", {"a" -> "1", "x"... -> "2"}], engineReplace["a1b22", {DigitCharacter .. -> "#"}]},
    {StringReplace["ab", {"x"... -> "1", "a" -> "2"}], StringReplace["ab", {"a" -> "1", "x"... -> "2"}], StringReplace["a1b22", DigitCharacter .. -> "#"]},
    TestID -> "string patterns: StringReplace takes the first rule that matches, a character later after an empty match"
]

VerificationTest[
    {engineCases["abc", ___ ..], engineCases["ab", ("x"...) ..], engineCases["ab", Repeated["x"..., {2, 3}]], engineCases["aab", ("a"...) ..], engineCases["aab", Shortest[("a"...) ..]]},
    {StringCases["abc", ___ ..], StringCases["ab", ("x"...) ..], StringCases["ab", Repeated["x"..., {2, 3}]], StringCases["aab", ("a"...) ..], StringCases["aab", Shortest[("a"...) ..]]},
    TestID -> "string patterns: a repeat of a part that matches nothing"
]

VerificationTest[
    {engineCases["ca\[EAcute].1", Except[LetterCharacter, __]], engineCases["abcb", Except["b", _ ~~ _]], engineCases["b", Except["a", ___]], engineCases["ab", Except["a", ""]],
     engineMatchQ["x", "x" ~~ Except["a", ___]], StringPatternProgram[Except["ab", __]]["Program"]},
    {StringCases["ca\[EAcute].1", Except[LetterCharacter, __]], StringCases["abcb", Except["b", _ ~~ _]], StringCases["b", Except["a", ___]], StringCases["ab", Except["a", ""]],
     StringMatchQ["x", "x" ~~ Except["a", ___]], None},
    TestID -> "string patterns: Except[c, p] is p after a character that c does not match"
]

VerificationTest[
    {engineCases["abcd", ("a" ~~ __)?(# =!= "c" &)], engineCases["ab", ("ab")?(# == "ab" &)], engineCases["abcd", (_ ~~ _)?(# =!= "b" &)], engineRuleCases["ab1c", {(x : __)?LetterQ :> x}]},
    {StringCases["abcd", ("a" ~~ __)?(# =!= "c" &)], StringCases["ab", ("ab")?(# == "ab" &)], StringCases["abcd", (_ ~~ _)?(# =!= "b" &)], StringCases["ab1c", (x : __)?LetterQ :> x]},
    TestID -> "string patterns: a test of each character that a pattern matched"
]

VerificationTest[
    {engineRuleCases["b", {(x : "a") | "b" :> {x}}], engineRuleCases["ab", {(x : "a") | (y : "b") :> {x, y}}], engineRuleCases["b", {Condition[(x : "a") | "b", x == ""] :> {x}}],
     engineRuleCases["ab", {(x : "a") :> {x, y}, (y : "b") :> {x, y}}]},
    {StringCases["b", (x : "a") | "b" :> {x}], StringCases["ab", (x : "a") | (y : "b") :> {x, y}], StringCases["b", Condition[(x : "a") | "b", x == ""] :> {x}],
     StringCases["ab", {(x : "a") :> {x, y}, (y : "b") :> {x, y}}]},
    TestID -> "string patterns: a name that took no part in a match is bound to the empty string"
]

VerificationTest[
    {enginePosition["_a b", WordBoundary], enginePosition["a_b", WordBoundary], enginePosition["\[EAcute]_", WordBoundary]},
    {StringPosition["_a b", WordBoundary], StringPosition["a_b", WordBoundary], StringPosition["\[EAcute]_", WordBoundary]},
    TestID -> "string patterns: a word boundary is a regex's, _ a word character"
]

(* Wolfram 15 warns that the pattern of a name's later occurrence is ignored: StringExpression::cond *)
VerificationTest[
    {engineCases["bc", ((x : "a") | "b") ~~ (x : "c")], engineCases["aa", ((x : "a") | "b") ~~ (x : "c")], engineCases["aa", (x : "c") | ((x : "a") ~~ (x : "b"))],
     engineCases["ab", x : ((x : "a") | "b")], engineCases["aa", (x : _) ~~ (x : _?DigitQ)]},
    Quiet[{StringCases["bc", ((x : "a") | "b") ~~ (x : "c")], StringCases["aa", ((x : "a") | "b") ~~ (x : "c")], StringCases["aa", (x : "c") | ((x : "a") ~~ (x : "b"))],
     StringCases["ab", x : ((x : "a") | "b")], StringCases["aa", (x : _) ~~ (x : _?DigitQ)]}, {StringExpression::cond}],
    TestID -> "string patterns: a name again on the way a match goes matches the text it matched first"
]

VerificationTest[
    {engineCases["aa", Repeated["a"..., {2}]], engineCases["\n", Repeated[Except[DigitCharacter, ___], {2}]], engineCases["ba", ((x : "a") | "b") ..],
     engineMatchQ["ba", ((x : "a") | "b") ..], engineCases["cbca", ("c" ~~ ((x : "a") | "b")) ..], engineRuleCases["bab", {("b" | (x : "a")) .. :> x}]},
    {StringCases["aa", Repeated["a"..., {2}]], StringCases["\n", Repeated[Except[DigitCharacter, ___], {2}]], StringCases["ba", ((x : "a") | "b") ..],
     StringMatchQ["ba", ((x : "a") | "b") ..], StringCases["cbca", ("c" ~~ ((x : "a") | "b")) ..], StringCases["bab", ("b" | (x : "a")) .. :> x]},
    TestID -> "string patterns: a repeat takes its least count, empty or not, its names the text of the first time round"
]

VerificationTest[
    {engineCases["12.5", Shortest[NumberString]], engineCases["a  b", Shortest["a" ~~ Whitespace]], engineCases["  ", Shortest[Whitespace]]},
    {StringCases["12.5", Shortest[NumberString]], StringCases["a  b", Shortest["a" ~~ Whitespace]], StringCases["  ", Shortest[Whitespace]]},
    TestID -> "string patterns: Shortest makes every repeat in it shortest, not those of NumberString"
]

VerificationTest[
    {StringPatternProgram[StartOfString ..]["Program"], StringPatternProgram[Repeated[EndOfLine, {1, 2}]]["Program"], StringPatternProgram[WordBoundary ...]["Program"],
     engineCases["a\na", (StartOfLine ~~ "a") ..]},
    {None, None, None, StringCases["a\na", (StartOfLine ~~ "a") ..]},
    TestID -> "string patterns: an anchor is no pattern to repeat"
]

VerificationTest[
    {StringPatternProgram["a" ~~ DigitCharacter ..]["Regex"], StringPatternProgram[x : DigitCharacter ~~ "." ~~ DigitCharacter ..]["Regex"],
     StringPatternProgram["x" ~~ RegularExpression["(a)(b)"]]["Regex"], StringPatternProgram[RegularExpression["a|b"]]["Regex"]},
    {{"a([[:digit:]])+", {None}}, {"([[:digit:]])\\.([[:digit:]])+", {HoldComplete[x], None}}, {"x(a)(b)", {1, 2}}, {"(a|b)", {None}}},
    TestID -> "string patterns: the regex of a pattern and a name for each of its groups"
]

(* a bracket as POSIX reads one: ] first, - last, ^ not first, a backslash a character as any other *)
VerificationTest[
    Map[StringPatternProgram[#]["Regex"][[1]] &, {{"]", "a"}, {"-", "a"}, {"^"}, {"^", "-"}, {"\\", "]"}, Except[{"]", "a"}], Except["^"], Except[DigitCharacter]}],
    {"[]a]", "[a-]", "\\^", "[-^]", "[]\\]", "[^]a]", "[^^]", "[^[:digit:]]"},
    TestID -> "string patterns: a bracket expression as POSIX reads one"
]

VerificationTest[
    {StringPatternProgram[x_ ~~ x_]["Regex"], StringPatternProgram[x : (x : "a")]["Regex"], StringPatternProgram[(StartOfString | "a") ..]["Regex"],
     StringPatternProgram[Shortest["a" ..]]["Regex"]},
    {None, None, None, None},
    TestID -> "string patterns: no regex for a name twice, an anchor in a repeat or a shortest repeat"
]

(* a class is data, codeIn[spec], from which the table of any class of one character is made *)
VerificationTest[
    With[{codes = Join[Range[0, 16^^D7FF], Range[16^^E000, 16^^FFFF]]},
        Map[Function[p, Pick[codes, StringPatternProgram[p]["ClassCodes"][[codes + 1]], 1] === Select[codes, StringMatchQ[FromCharacterCode[#], p] &]],
            {Except[DigitCharacter], {"a", "b", DigitCharacter}, Except[{"a", "1"}], Except[WhitespaceCharacter | "x"]}]],
    {True, True, True, True},
    TestID -> "string patterns: the codes of any class of one character, a union, an Except and a range"
]

VerificationTest[
    {StringPatternProgram[{"a", "b", "c"}]["Program"], StringPatternProgram[Except[DigitCharacter | "x"]]["Program"]},
    {Wolfram`Parser`StringPatterns`Private`characterClass[Wolfram`Parser`StringPatterns`Private`codeIn[{"Codes", {97, 98, 99}}]],
     Wolfram`Parser`StringPatterns`Private`characterClass[Wolfram`Parser`StringPatterns`Private`codeIn[{"Not", {"Union", {{"Codes", {120}}, {"Named", "digit"}}}}]]},
    TestID -> "string patterns: a class as data, the characters of a union one set of codes"
]

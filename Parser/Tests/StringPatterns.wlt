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

(* DigitCharacter is 0 to 9 alone, as DigitQ is, and WordCharacter a letter or one of them, where
   Wolfram 15 matches the decimal digits of every script and numbers such as superscript 2 [W15 bug];
   a regex's \d keeps Wolfram 15's digits *)
VerificationTest[
    With[{s = "a\:0663b12\.b2c\.bd3\:ff13x\:0966_"},
        {engineCases[s, DigitCharacter], engineCases[s, WordCharacter], engineCases[s, DigitCharacter ..], engineCases[s, NumberString],
         engineCases[s, RegularExpression["\\d"]] === StringCases[s, RegularExpression["\\d"]]}],
    {{"1", "2", "3"}, {"a", "b", "1", "2", "c", "3", "x"}, {"12", "3"}, {"12", "3"}, True},
    TestID -> "string patterns: DigitCharacter is 0 to 9, WordCharacter a letter or one of them"]

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

(* the classes beyond ASCII: the letters of every script, Wolfram 15's; DigitCharacter 0 to 9 alone and
   WordCharacter a letter or one of them, where Wolfram 15 takes the decimal digits of every script and
   other numerals too [W15 bug] *)
$classCharacters = FromCharacterCode /@ {16^^0663, 16^^0969, 16^^0E53, 16^^FF11, 16^^1D7D1, 16^^00B2, 16^^2163, 16^^00E9, 16^^03B1, 16^^1D4B6};

VerificationTest[
    Map[Function[c, Select[$classCharacters, engineMatchQ[#, c] &]], {DigitCharacter, WordCharacter, LetterCharacter}],
    {{}, Select[$classCharacters, StringMatchQ[#, LetterCharacter] &], Select[$classCharacters, StringMatchQ[#, LetterCharacter] &]},
    TestID -> "string patterns: letters beyond ASCII are Wolfram 15's, and digits are 0 to 9, word characters letters or digits"
]

(* every whitespace and hexadecimal character Wolfram 15 takes, of the codes below 65536, and the digits
   DigitQ takes *)
VerificationTest[
    Append[Map[Function[c, Flatten[Position[StringPatternProgram[c]["ClassCodes"], 1]] - 1 === Select[Range[0, 65535], StringMatchQ[FromCharacterCode[#], c] &]],
        {WhitespaceCharacter, HexadecimalCharacter, PunctuationCharacter}],
        Flatten[Position[StringPatternProgram[DigitCharacter]["ClassCodes"], 1]] - 1 === Select[Range[0, 65535], DigitQ[FromCharacterCode[#]] &]],
    {True, True, True, True},
    TestID -> "string patterns: the codes of a class are Wolfram 15's, whitespace and hexadecimal digits too"
]

VerificationTest[
    With[{s = StringJoin[FromCharacterCode /@ Range[0, 12300]]}, {engineCases[s, WhitespaceCharacter ..], engineCases[s, PunctuationCharacter ~~ DigitCharacter]}],
    With[{s = StringJoin[FromCharacterCode /@ Range[0, 12300]]}, {StringCases[s, WhitespaceCharacter ..], StringCases[s, PunctuationCharacter ~~ CharacterRange["0", "9"]]}],
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
    {StringPatternProgram[RegularExpression["\\((?R)?\\)"]]["Program"], StringPatternProgram[f[x]]["RegexLike"], StringPatternMatches["ab", {StringPatternProgram[RegularExpression["(a)(?(1)b|c)"]]}, "Each"]},
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

(* a class is data, codeIn[spec], from which the table of any class of one character is made; Wolfram
   15's matches with DigitCharacter 0 to 9 alone, as the engine's is *)
VerificationTest[
    With[{codes = Join[Range[0, 16^^D7FF], Range[16^^E000, 16^^FFFF]]},
        Map[Function[p, Pick[codes, StringPatternProgram[p]["ClassCodes"][[codes + 1]], 1] ===
            Select[codes, StringMatchQ[FromCharacterCode[#], p /. DigitCharacter -> CharacterRange["0", "9"]] &]],
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

(* the typed matcher matches as the programs' interpreter, the reference, does *)
VerificationTest[
    With[{patterns = {{"a" ~~ DigitCharacter ..}, {x : ("a" | "b") ..}, {"<" ~~ Shortest[x__] ~~ ">"}, {"x"..., "a"}, {"a", "aa"}, {x_ ~~ y_ /; DigitQ[y]},
            {("a" ~~ __)?(# =!= "c" &)}, {x__ ~~ x__}, {WordBoundary ~~ x : LetterCharacter ~~ ___}, {StartOfLine ~~ x_}, {NumberString},
            {Except[LetterCharacter, __]}, {((x : "a") | "b") ..}, {Shortest[("a"...) ..]}, {Repeated[Except[DigitCharacter, ___], {2}]},
            {w : LetterCharacter .. /; StringLength[w] > 3}, {(x : "a") | "b"}, {"ab" | "a", "b" ...}, {(y : StartOfString) | (y_)}},
          texts = {"", "a1b22 ab<a><b>", "abab hello world", "ab\ncd -1.5 2. .5", "ca\[EAcute].1 ba aab one two three \:0663\:0663.5 \|01d7d1"}},
        Select[Tuples[{patterns, texts, {"First", "Each", "Overlapping", "All"}}], Function[c,
            StringPatternMatches[c[[2]], StringPatternProgram /@ c[[1]], c[[3]]] =!= StringPatternMatches[c[[2]], StringPatternProgram /@ c[[1]], c[[3]], Method -> "Interpreter"]]]],
    {},
    TestID -> "string patterns: the typed matcher matches as the programs' interpreter does"
]

(* a name that occurs twice, bound at an anchor to the empty text, is {} *)
VerificationTest[
    {engineRuleCases["a_A", {(y : StartOfString) | (y_) :> {y}}], engineRuleCases["a", {(y : StartOfString) :> {y}}]},
    {StringCases["a_A", (y : StartOfString) | (y_) :> {y}], StringCases["a", (y : StartOfString) :> {y}]},
    TestID -> "string patterns: a name twice bound to the empty text is {}"
]

(* every way each pattern matches at each start, as Overlaps -> All takes them *)
VerificationTest[
    Map[Function[c, Map[StringTake[c[[1]], {#[[1]] + 1, #[[2]]}] &, engineMatches[c[[1]], Flatten[{c[[2]]}], "All"]]],
        {{"abc", __}, {"aaa", Shortest["a" ..]}, {"ab", "a" | "ab"}, {"aaa", ("a" | "aa") ..}, {"abab", {"ab", "a" ~~ __}}, {"ab", "" | "a"}, {"abcabc", "a" ~~ Shortest[___] ~~ "c"}}],
    {StringCases["abc", __, Overlaps -> All], StringCases["aaa", Shortest["a" ..], Overlaps -> All], StringCases["ab", "a" | "ab", Overlaps -> All],
     StringCases["aaa", ("a" | "aa") .., Overlaps -> All], StringCases["abab", {"ab", "a" ~~ __}, Overlaps -> All], StringCases["ab", "" | "a", Overlaps -> All],
     StringCases["abcabc", "a" ~~ Shortest[___] ~~ "c", Overlaps -> All]},
    TestID -> "string patterns: every way each pattern matches at each start, as Overlaps -> All takes them"
]

VerificationTest[
    {Map[ruleValue[{x__ ~~ y__ :> {x, y}}, #] &, engineMatches["abc", {x__ ~~ y__}, "All"]], Map[{#[[1]] + 1, #[[2]]} &, engineMatches["abc", {__}, "All"]],
     Length[engineMatches["aaa", {"a" ..}, "All"]]},
    {StringCases["abc", x__ ~~ y__ :> {x, y}, Overlaps -> All], StringPosition["abc", __, Overlaps -> All], StringCount["aaa", "a" .., Overlaps -> All]},
    TestID -> "string patterns: the names, the spans and the count of every way"
]

(* a literal "" is tried after the other alternatives, before them in Shortest *)
VerificationTest[
    {engineCases["ab", "" | "a"], engineCases["abc", "" | "x" | "b"], engineCases["abb", "a" ~~ ("" | "b") ~~ "b"], engineCases["ab", ("" | "a") ..],
     engineCases["ab", Shortest["" | "a"]], engineCases["ba", ("a" ...) | "b"], engineRuleCases["ab", {x : ("" | "a") :> {x}}], engineReplace["abc", {"" | "b" -> "-"}]},
    {StringCases["ab", "" | "a"], StringCases["abc", "" | "x" | "b"], StringCases["abb", "a" ~~ ("" | "b") ~~ "b"], StringCases["ab", ("" | "a") ..],
     StringCases["ab", Shortest["" | "a"]], StringCases["ba", ("a" ...) | "b"], StringCases["ab", x : ("" | "a") :> {x}], StringReplace["abc", "" | "b" -> "-"]},
    TestID -> "string patterns: a literal \"\" tried after the other alternatives, before them in Shortest"
]

(* the records of the matches, the same from the typed matcher and the interpreter *)
VerificationTest[
    With[{r = StringPatternRecords["a1b22", StringPatternProgram /@ {x : DigitCharacter .., (y : "a") | "b"}, "Each"]},
        {r, Developer`PackedArrayQ[r["Records"]],
         Select[{{x : DigitCharacter .., y_}, {(x : "a") | "b"}, {((x : "a") | "b") ..}, {x_ ~~ x_}, {"a" ~~ __}}, Function[ps,
            StringPatternRecords["a1b22 ab", StringPatternProgram /@ ps, "All"] =!= StringPatternRecords["a1b22 ab", StringPatternProgram /@ ps, "All", Method -> "Interpreter"]]]}],
    {<|"Records" -> {{0, 1, 2, 0, 1}, {1, 2, 1, 1, 2}, {2, 3, 2, -1, -1}, {3, 5, 1, 3, 5}}, "Sides" -> {{{HoldPattern[x], False}}, {{HoldPattern[y], False}}}|>, True, {}},
    TestID -> "string patterns: the records of the matches, packed, the same from the typed matcher and the interpreter"
]

(* every way as Wolfram 15 counts them: alternatives one class where it makes them one, a character
   or a class but the hexadecimal one, those inside alternatives taken with them, a part in Shortest
   apart; an empty iteration of a repeat of at most max, or the first of one with a name, a way of
   its own; a repeat with a name and no least going on past none in place of its first *)
VerificationTest[
    Map[Function[c, Map[StringTake[c[[1]], {#[[1]] + 1, #[[2]]}] &, engineMatches[c[[1]], {c[[2]]}, "All"]]],
        {{"A", LetterCharacter | WordCharacter}, {"c", HexadecimalCharacter | LetterCharacter}, {"2", _ | WordCharacter}, {"b", ("a" | LetterCharacter) | "b"},
         {"a", Shortest[Whitespace] | (LetterCharacter | "a")}, {"", Repeated["a" ..., {0, 2}]}, {"", (y : EndOfString) ..}, {"a", ("a" ...) ..},
         {"-", PunctuationCharacter | Shortest[PunctuationCharacter]}, {"ab", ((x : "a") | "b") ...}, {"b", Shortest[((x : "a") | "b") ...]}}],
    {StringCases["A", LetterCharacter | WordCharacter, Overlaps -> All], StringCases["c", HexadecimalCharacter | LetterCharacter, Overlaps -> All],
     StringCases["2", _ | WordCharacter, Overlaps -> All], StringCases["b", ("a" | LetterCharacter) | "b", Overlaps -> All],
     StringCases["a", Shortest[Whitespace] | (LetterCharacter | "a"), Overlaps -> All], StringCases["", Repeated["a" ..., {0, 2}], Overlaps -> All],
     StringCases["", (y : EndOfString) .., Overlaps -> All], StringCases["a", ("a" ...) .., Overlaps -> All],
     StringCases["-", PunctuationCharacter | Shortest[PunctuationCharacter], Overlaps -> All], StringCases["ab", ((x : "a") | "b") ..., Overlaps -> All],
     StringCases["b", Shortest[((x : "a") | "b") ...], Overlaps -> All]},
    TestID -> "string patterns: every way as Wolfram 15 counts the ways of alternatives and of empty iterations"
]

(* the programs of regular expressions, matched as Wolfram 15 matches them: the texts, each match's
   groups as "$n" takes them, and every way of each *)
regexAnswers[s_String, re_String] := With[{p = StringPatternProgram[RegularExpression[re]]},
    With[{e = StringPatternMatches[s, {p}, "Each"], a = StringPatternMatches[s, {p}, "All"]},
        {Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, e], Map[Cases[#[[4]], (_Integer -> t_) :> t] &, e], Map[StringTake[s, {#[[1]] + 1, #[[2]]}] &, a]}]]
nativeAnswers[s_String, re_String, n_Integer] := {StringCases[s, RegularExpression[re]], StringCases[s, RuleDelayed @@ {RegularExpression[re], Table["$" <> ToString[k], {k, n}]}],
    StringCases[s, RegularExpression[re], Overlaps -> All]}
VerificationTest[
    Select[{{"xaabcd aab", "(\\w)+", 1}, {"ab ab", "(a)?b", 1}, {"12-345 6", "(\\d+)-(\\d+)", 2}, {"foo bar foobar", "\\bfoo\\b", 0}, {"a\nb\n", "(?m)^\\w$", 0},
        {"a\nb", "a.b|(?s)a.b", 0}, {"\[EAcute]\[CapitalEAcute] ab", "\\p{Lu}|[[:lower:]]+", 0}, {"aAbB", "(?i)ab", 0}, {"xad xbcd", "(?<=a|bc)d", 0}, {"aab", "(?>a+)ab|a++b", 0},
        {"abc abd", "ab(?=c)|ab(?!c)", 0}, {"aa ab", "(a)\\1", 1}, {"a.b*c", "\\Q.*\\E|\\.", 0}, {"abc", "a{,2}|\\x{62}", 0}, {"a b", "(?=a)?\\w", 0}},
        Function[c, regexAnswers[c[[1]], c[[2]]] =!= nativeAnswers @@ c]],
    {},
    TestID -> "string patterns: regular expressions matched as Wolfram 15 matches them, their groups and every way"
]

(* a backreference of any case in a caseless regex, and in its own group the group's text of the
   time round before, none the first time, the group atomic; what a program declines, by name *)
VerificationTest[
    Select[{{"aAaA", "(?i)(a)\\1", 1}, {"b_a", "(\\1)?[^a]|1+(?!b)", 1}, {"aba", "(a|b\\1)+", 1}, {"k\:212akK", "(?i)(k)\\1", 1}, {"abAB ABab", "(?i)(ab)\\1", 1},
        {"aaba", "(a\\1)", 1}, {"xx", "(x\\1?)+", 1}, {"aA", "(a)(?i)\\1", 1}, {"aA", "(?i:(a))\\1", 1}, {"\:00df\:1e9e", "(?i)(\:00df)\\1", 1}, {"aAAa", "(?i)(a)\\1+", 1},
        {"aab", "(a{1,2}|\\1)ab", 1}, {"aab", "((a{1,2})\\1?)ab", 2}, {"aab", "((a{1,2})\\2?)ab", 2}, {"\\t", "(\\t\\1?|)", 1}, {"\:00c9\:00e9B", "([[:alpha:]]{1,2}|\\1)", 1}},
        Function[c, regexAnswers[c[[1]], c[[2]]] =!= nativeAnswers @@ c]],
    {},
    TestID -> "string patterns: a backreference of any case in a caseless regex, and in its own group the time round before"
]
VerificationTest[
    StringPatternProgram[#]["Declined"] & /@ {RegularExpression["\\((?R)?\\)"], RegularExpression["(?(1)a|b)"], RegularExpression["(?|a)"], RegularExpression["(*FAIL)"],
        RegularExpression["\\Ga"], RegularExpression["(?<=a+)b"], RegularExpression["(a?)++"], RegularExpression["\\p{Greek}"], RegularExpression["a{2,1}"],
        RegularExpression["(?i)(a)\\1"], "a" ~~ DigitCharacter},
    {"recursion", "a conditional group", "a branch reset", "a verb", "\\G", "a lookbehind of no fixed length", "a possessive repeat of a part that may match nothing",
     "\\p{Greek}, a script or no property", "a regex Wolfram 15 does not take", None, None},
    TestID -> "string patterns: what a program declines, by name"
]

(* a regex's groups in the records after its names, each named by its number; a lookaround matched
   by the interpreter, as the typed matcher would *)
VerificationTest[
    {StringPatternRecords["ab12", {StringPatternProgram[RegularExpression["([a-z]+)(\\d+)?"]]}, "Each"],
     StringPatternMatches["ab12", {StringPatternProgram[RegularExpression["([a-z]+)(\\d+)?"]]}, "Each"],
     StringPatternMatches["xab", {StringPatternProgram[RegularExpression["(?<=a)b"]]}, "Each"] === StringPatternMatches["xab", {StringPatternProgram[RegularExpression["(?<=a)b"]]}, "Each", Method -> "Interpreter"]},
    {<|"Records" -> {{0, 4, 1, 0, 2, 2, 4}}, "Sides" -> {{{1, False}, {2, False}}}|>, {{0, 4, 1, {1 -> "ab", 2 -> "12"}}}, True},
    TestID -> "string patterns: a regex's groups in the records and the rules, each by its number"
]

(* the later occurrences of a name whose own pattern the matcher ignores, of which Wolfram 15 warns,
   StringExpression::cond: on a match's way, not a blank, each once, an occurrence in the name's own
   pattern among them *)
VerificationTest[
    Map[StringPatternProgram[#]["IgnoredRestrictions"] &,
        {(x : "a") ~~ (x : "a"), ((x : "a") | (x : "b")) ~~ ((x : "a") | (x : "b")), (x : "a") ~~ (x : _), (x : "a") ~~ x__, (x : "a") ~~ (x : Except["b"]),
         (x : "a") | (x : "b"), x : (x : "a"), (x : "ab") ~~ ((x : DigitCharacter) | (x : DigitCharacter))}],
    {{HoldForm[x : "a"]}, {HoldForm[x : "a"], HoldForm[x : "b"]}, {}, {}, {HoldForm[x : Except["b"]]}, {}, {HoldForm[x : "a"]},
     {HoldForm[x : DigitCharacter], HoldForm[x : DigitCharacter]}},
    TestID -> "string patterns: the restrictions the matcher ignores, of which Wolfram 15 warns"
]

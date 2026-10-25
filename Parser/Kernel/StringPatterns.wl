(* ::Package:: *)

(* :Title: StringPatterns.wl - string patterns matched as Wolfram 15 matches them *)
(* :Context: Wolfram`Parser`StringPatterns` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The engine of string patterns. A pattern such as "a" ~~ DigitCharacter .. becomes a program,
    which is matched by backtracking over the string's characters as Wolfram 15 matches the
    pattern [WL 15.0.0]: the alternatives and the rules in the order given, the first that
    matches taken; repeats the longest first, or the shortest in Shortest; a name that occurs
    twice matches the same text both times; a condition and a test checked when their part has
    matched, the names in them bound to what matched. The classes of characters are Wolfram 15's,
    as the paclet records them in CharacterClasses.wl. A pattern that a regular expression means also
    gives that regex, a POSIX extended one, for a host's native matcher, the C library's regcomp and
    regexec. A kernel builds StringMatchQ, StringCases, StringReplace, StringSplit and the rest of the
    String functions of patterns on it.

    It loads with the paclet, or alone, with no more of the paclet than CharacterClassRuns.wl, as a
    kernel loads it at its first string pattern:

        Get[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "StringPatterns.wl"}]]
*)

(* the characters of the classes, which the paclet's core reads too, where it has not *)
If[DownValues[Wolfram`Parser`Private`characterClassRuns] === {}, Get[FileNameJoin[{DirectoryName[$InputFileName], "CharacterClassRuns.wl"}]]];

BeginPackage["Wolfram`Parser`StringPatterns`"]

StringPatternProgram::usage = "StringPatternProgram[patt] gives the program of the string pattern patt, an object whose properties \
are \"Pattern\", \"Program\", \"Regex\", \"RegexLike\", \"RegexFinds\", \"Class\", \"Run\" and \"ClassCodes\"."
StringPatternMatches::usage = "StringPatternMatches[s, {prog1, prog2, ...}, mode] gives the matches of the programs progi in the \
string s from the left, each {start, end, k, rules}: progk matched the characters after start up to end, rules binding its names to \
their text. The mode is \"First\", \"Each\" or \"Overlapping\"."

Begin["`Private`"]


(* ::Section:: *)
(*Programs*)

(* A pattern becomes a program first:

    literal[{code, ...}]                these characters
    characterClass[test]                a character whose code passes the test
    sequence[{p, ...}]                  each after the other
    alternatives[{p, ...}]              the first that matches
    repeat[p, min, max, longest]        p from min to max times
    named[HoldComplete[x], p]           p, x bound to what it matched
    backreference[HoldComplete[x]]      the text x matched
    tested[p, f]                        p, if f of each character it matched is True
    conditioned[p, HoldComplete[test], names]
                                        p, if the test is True, the names of p that took no
                                        part in the match bound as in a rule's right side
    excluding[test, p]                  p, after a character whose code fails the test
    builtIn[name, p]                    p, the program of Wolfram 15's pattern name, which
                                        Shortest leaves as it is
    anchor[name]                        StartOfString, EndOfString, StartOfLine, EndOfLine or
                                        WordBoundary

   A match runs the program from a position with a continuation, which gets the position after
   the part and the names bound so far, and gives the match or $noMatch to make the part try its
   next way. *)

(* The object holds the program, None if the pattern has parts that no program has, its regex,
   and what a kernel asks of it to choose how to match: whether a regex matches as the program
   does, or finds a match where it has one, and the class of a pattern of one character class. *)
(* The properties come before the program is made: the left side of a definition of them is
   evaluated, and a_Association, a string pattern too, would be made a program. *)
StringPatternProgram[a_Association]["ClassCodes"] := Replace[a["Class"], {{test_, 1, 1} :> classCodes[test], _ -> None}]
StringPatternProgram[a_Association]["Properties"] := Append[Keys[a], "ClassCodes"]
StringPatternProgram[a_Association][property_String] := Lookup[a, property, Missing["NotAvailable", property]]

StringPatternProgram[pattern : Except[_Association]] := With[{p = stringProgram[pattern]},
    StringPatternProgram[<|"Pattern" -> pattern, "Program" -> p, "Regex" -> regexOf[pattern],
        "RegexLike" -> (p =!= None && regexLikeQ[p]), "RegexFinds" -> (p =!= None && regexFindsQ[p]),
        "Class" -> programClass[p], "Run" -> programRun[p]|>]]

StringPatternProgram /: MakeBoxes[program : StringPatternProgram[a_Association], form : (StandardForm | TraditionalForm)] :=
    BoxForm`ArrangeSummaryBox[
        StringPatternProgram, program, None,
        {
            BoxForm`SummaryItem[{"Pattern: ", a["Pattern"]}],
            BoxForm`SummaryItem[{"Has a program: ", a["Program"] =!= None}]
        },
        {
            BoxForm`SummaryItem[{"Program: ", a["Program"]}],
            BoxForm`SummaryItem[{"Regex: ", a["Regex"]}],
            BoxForm`SummaryItem[{"Regex like: ", a["RegexLike"]}],
            BoxForm`SummaryItem[{"Regex finds: ", a["RegexFinds"]}],
            BoxForm`SummaryItem[{"Class: ", a["Class"]}],
            BoxForm`SummaryItem[{"Run: ", a["Run"]}]
        },
        form
    ]

(* the program of a pattern, or None if it has parts that no program has *)
stringProgram[pattern_] := Catch[backreferenced[program[pattern]], program]

(* A pattern of one character class, or a repeat of one, matches a whole string whose characters
   all pass the class's test, as many as the repeat allows: it is tested on the codes, with no
   program run. {test, min, max} for the program p of one character class, or a repeat of one, or
   None. *)
programClass[p_] := Replace[p, {
    characterClass[test_] :> {test, 1, 1},
    repeat[characterClass[test_], min_, max_, _] :> {test, min, max},
    _ -> None
}]

(* A greedy repeat of one character class, as many as there are: of a text, StringCases finds each
   run of its characters that is long enough. {test, min} for the program p of a repeat of one
   character class, from min times on, as many as it can, or None. *)
programRun[p_] := Replace[p, {repeat[characterClass[test_], min_Integer, Infinity, True] :> {test, min}, _ -> None}]

(* the program of a string pattern, or a Throw of None, tagged program *)
program[s_String] := literal[ToCharacterCode[s]]
program[Verbatim[Verbatim][s_String]] := literal[ToCharacterCode[s]]
program[Verbatim[Blank][]] := characterClass[anyCharacterQ]
program[Verbatim[BlankSequence][]] := repeat[characterClass[anyCharacterQ], 1, Infinity, True]
program[Verbatim[BlankNullSequence][]] := repeat[characterClass[anyCharacterQ], 0, Infinity, True]
(* the same name in a name's own part matches nothing [WL 15.0.0] *)
program[Verbatim[Pattern][x_Symbol, p_]] := named[HoldComplete[x], ReplaceAll[program[p], named[HoldComplete[x], _] -> alternatives[{}]]]
program[p_StringExpression] := sequence[program /@ List @@ p]
program[p_Alternatives] := alternativesProgram[program /@ List @@ p]
program[p_List] := alternativesProgram[program /@ p]
program[Verbatim[Repeated][p_]] := repeatOf[program[p], 1, Infinity]
program[Verbatim[Repeated][p_, max_Integer]] := repeatOf[program[p], 1, max]
program[Verbatim[Repeated][p_, {n_Integer}]] := repeatOf[program[p], n, n]
program[Verbatim[Repeated][p_, {min_Integer, max : _Integer | Infinity}]] := repeatOf[program[p], min, max]
program[Verbatim[RepeatedNull][p_]] := repeatOf[program[p], 0, Infinity]
program[Verbatim[RepeatedNull][p_, max_Integer]] := repeatOf[program[p], 0, max]
program[Verbatim[Shortest][p_]] := shortest[program[p]]
program[Verbatim[Longest][p_]] := program[p]
program[Verbatim[PatternTest][p_, f_]] := tested[program[p], f]
program[Verbatim[Condition][p_, test_]] := With[{inner = program[p]}, conditioned[inner, HoldComplete[test], programNames[inner]]]
(* Except takes a pattern of one character: Except[c, p] is p where a character that c does not
   match comes first [WL 15.0.0] *)
program[Verbatim[Except][c_]] := With[{inner = program[c]},
    If[singleCharacterQ[inner], With[{test = classTest[inner]}, characterClass[Function[code, ! test[code]]]], Throw[None, program]]]
program[Verbatim[Except][c_, p_]] := With[{inner = program[c]}, If[singleCharacterQ[inner], excluding[classTest[inner], program[p]], Throw[None, program]]]
program[HoldPattern[CharacterRange[a_String, b_String]]] := With[{low = First[ToCharacterCode[a]], high = First[ToCharacterCode[b]]},
    characterClass[Function[code, low <= code <= high]]]
program[DigitCharacter] := characterClass[digitCodeQ]
program[LetterCharacter] := characterClass[letterCodeQ]
program[WordCharacter] := characterClass[wordCodeQ]
program[WhitespaceCharacter] := characterClass[whitespaceCodeQ]
program[PunctuationCharacter] := characterClass[punctuationCodeQ]
program[HexadecimalCharacter] := characterClass[hexadecimalCodeQ]
program[Whitespace] := repeat[characterClass[whitespaceCodeQ], 1, Infinity, True]
program[NumberString] := builtIn[NumberString, program[StringExpression[
    Repeated[{"+", "-"}, {0, 1}],
    Alternatives[StringExpression[DigitCharacter .., Repeated[StringExpression[".", RepeatedNull[DigitCharacter]], {0, 1}]], StringExpression[".", DigitCharacter ..]]
]]]
program[anchorName : StartOfString | EndOfString | StartOfLine | EndOfLine | WordBoundary] := anchor[anchorName]
program[_] := Throw[None, program]

(* a repeat of p, the longest first; an anchor is no pattern to repeat [WL 15.0.0] *)
repeatOf[p_, min_, max_] := If[MatchQ[p, _anchor], Throw[None, program], repeat[p, min, max, True]]

(* Alternatives of single characters are one class, so that a repeat of them goes along the string
   without backtracking. *)
alternativesProgram[{p_}] := p
alternativesProgram[parts_List] := If[AllTrue[parts, singleCharacterQ],
    characterClass[With[{tests = classTest /@ parts}, Function[code, AnyTrue[tests, Function[test, test[code]]]]]],
    alternatives[parts]
]

(* Every repeat in Shortest is shortest, those inside another too, but not those of a pattern of
   Wolfram 15's own, such as NumberString [WL 15.0.0]. *)
shortest[repeat[p_, min_, max_, _]] := repeat[shortest[p], min, max, False]
shortest[(head : sequence | alternatives)[parts_List]] := head[shortest /@ parts]
shortest[named[x_, p_]] := named[x, shortest[p]]
shortest[tested[p_, f_]] := tested[shortest[p], f]
shortest[conditioned[p_, test_, names_]] := conditioned[shortest[p], test, names]
shortest[excluding[test_, p_]] := excluding[test, shortest[p]]
shortest[p_] := p

(* whether a program matches exactly one character *)
singleCharacterQ[_characterClass] := True
singleCharacterQ[literal[{_}]] := True
singleCharacterQ[_] := False

(* the test of the code of the one character that a program matches *)
classTest[characterClass[test_]] := test
classTest[literal[{c_}]] := Function[code, code === c]

(* the names of a program, each HoldComplete[x], with how many times each occurs *)
programNames[p_] := Counts[Cases[p, named[x_, _] | backreference[x_] :> x, {0, Infinity}]]

(* A name that occurs again after it on the way a match goes, not in another alternative, matches
   there the text it matched, whatever its own pattern there [WL 15.0.0]: that occurrence is a
   backreference. referenced[p, seen] gives p so and the names seen once it is past. *)
backreferenced[p_] := First[referenced[p, {}]]
referenced[named[x_, p_], seen_List] := If[MemberQ[seen, x],
    {backreference[x], seen},
    With[{inner = referenced[p, seen]}, {named[x, First[inner]], Union[Last[inner], {x}]}]]
referenced[sequence[parts_List], seen_List] := Module[{now = seen},
    {sequence[Map[Function[part, With[{r = referenced[part, now]}, now = Last[r]; First[r]]], parts]], now}]
referenced[alternatives[parts_List], seen_List] := With[{rs = Map[referenced[#, seen] &, parts]},
    {alternatives[Map[First, rs]], Union[seen, Union @@ Map[Last, rs]]}]
referenced[repeat[p_, min_, max_, longest_], seen_List] := With[{r = referenced[p, seen]}, {repeat[First[r], min, max, longest], Last[r]}]
referenced[tested[p_, f_], seen_List] := With[{r = referenced[p, seen]}, {tested[First[r], f], Last[r]}]
referenced[conditioned[p_, test_, names_], seen_List] := With[{r = referenced[p, seen]}, {conditioned[First[r], test, names], Last[r]}]
referenced[excluding[t_, p_], seen_List] := With[{r = referenced[p, seen]}, {excluding[t, First[r]], Last[r]}]
referenced[builtIn[name_, p_], seen_List] := With[{r = referenced[p, seen]}, {builtIn[name, First[r]], Last[r]}]
referenced[p_, seen_List] := {p, seen}

(* A regex's match is the leftmost longest, a pattern's the first by the order of its parts: the
   first of its alternatives, its repeats the longest first and only then the parts after them. A
   regex has no shortest repeat, and the matches of the C library's skip empty ones. A regex matches
   as the program does if it has no alternatives of more than a character, no repeat of more than
   one character, which may give characters to a later part and so make a longer match, no
   shortest repeat, no name twice and no empty match. It finds a match where the program has one if
   it has no name twice, whose texts must be the same, and no empty match, which the regex search
   passes over. *)
regexLikeQ[p_] := ! nullableQ[p] && FreeQ[p, _alternatives | repeat[_, _, _, False] | repeat[Except[_?singleCharacterQ], _, _, _] | _backreference] &&
    DuplicateFreeQ[Cases[p, named[x_, _] :> x, {0, Infinity}]]
regexFindsQ[p_] := ! nullableQ[p] && FreeQ[p, _backreference] && DuplicateFreeQ[Cases[p, named[x_, _] :> x, {0, Infinity}]]

(* whether a program may match no characters *)
nullableQ[literal[codes_]] := codes === {}
nullableQ[_characterClass] := False
nullableQ[sequence[parts_]] := AllTrue[parts, nullableQ]
nullableQ[alternatives[parts_]] := AnyTrue[parts, nullableQ]
nullableQ[repeat[p_, min_, _, _]] := min === 0 || nullableQ[p]
nullableQ[named[_, p_]] := nullableQ[p]
nullableQ[tested[p_, _] | conditioned[p_, _, _]] := nullableQ[p]
nullableQ[excluding[_, p_] | builtIn[_, p_]] := nullableQ[p]
nullableQ[_anchor | _backreference] := True


(* ::Section:: *)
(*Regular expressions*)

(* A pattern as a POSIX extended regular expression where one means the same, for a host's native
   matcher, the C library's regcomp and regexec, run on a string's UTF-8 bytes: {regex, names}, the
   names an entry for each group the regex opens, in order, HoldComplete[x] for the pattern's name
   x, i for the ith group of a RegularExpression, None for a group of no name; None for a pattern
   with no regex. *)
regexOf[pattern_] := If[regexTakesQ[pattern], Catch[translated[pattern], regexOf], None]

(* whether a regex can take the pattern: no name twice, whose texts a regex's groups do not tie
   together as the pattern does [WL 15.0.0], and no anchor in a repeat, which the C library's
   regexec does not find where it should *)
regexTakesQ[pattern_] := DuplicateFreeQ[Cases[pattern, Verbatim[Pattern][x_, _] :> HoldComplete[x], {0, Infinity}]] &&
    FreeQ[pattern, (Verbatim[Repeated] | Verbatim[RepeatedNull])[q_ /; ! FreeQ[q, StartOfString | EndOfString], ___]]

translated[s_String] := If[StringContainsQ[s, FromCharacterCode[0]], Throw[None, regexOf], {escaped[s], {}}]
translated[Verbatim[Blank][]] := {".", {}}
translated[Verbatim[BlankSequence][]] := {".+", {}}
translated[Verbatim[BlankNullSequence][]] := {".*", {}}
translated[Verbatim[Pattern][x_Symbol, p_]] := With[{inner = translated[p]}, {"(" <> First[inner] <> ")", Prepend[Last[inner], HoldComplete[x]]}]
translated[p_StringExpression] := joined[translated /@ List @@ p, ""]
translated[p_Alternatives] := grouped[joined[translated /@ List @@ p, "|"], ""]
translated[Verbatim[Repeated][p_]] := grouped[translated[p], "+"]
translated[Verbatim[RepeatedNull][p_]] := grouped[translated[p], "*"]
translated[Verbatim[Repeated][p_, {min_Integer, max_Integer}]] := grouped[translated[p], "{" <> ToString[min] <> "," <> ToString[max] <> "}"]
translated[Verbatim[Repeated][p_, {min_Integer, Infinity}]] := grouped[translated[p], "{" <> ToString[min] <> ",}"]
translated[Verbatim[Repeated][p_, max_Integer]] := grouped[translated[p], "{1," <> ToString[max] <> "}"]
translated[Verbatim[Longest][p_]] := translated[p]
translated[chars : {__String}] /; AllTrue[chars, StringLength[#] === 1 &] := {bracketed[chars, False], {}}
translated[HoldPattern[CharacterRange[a_String, b_String]]] /; StringLength[a] === StringLength[b] === 1 && Max[ToCharacterCode[a <> b]] < 128 :=
    {bracketed[CharacterRange[a, b], False], {}}
translated[Verbatim[Except][chars : {__String}]] /; AllTrue[chars, StringLength[#] === 1 &] := {bracketed[chars, True], {}}
translated[Verbatim[Except][c_String]] /; StringLength[c] === 1 := {bracketed[{c}, True], {}}
translated[Verbatim[Except][c_Symbol]] := With[{class = regexClass[c]},
    {"[^" <> StringTake[First[class], {2, -2}] <> "]", {}} /; MatchQ[class, {_String?(StringMatchQ[#, "[[:" ~~ __ ~~ ":]]"] &), {}}]
]
(* A regex of alternatives is a group of no name, so that what stands around it, StartOfString ~~
   RegularExpression["a|b"] among them, takes all of them [WL 15.0.0]; POSIX has no group that
   captures nothing. A backreference counts the group, so a regex with one is left as it is. *)
translated[RegularExpression[re_String]] := With[{regex = {posixRegex[re], Range[regexGroupCount[re]]}},
    If[StringContainsQ[re, "|"] && ! StringContainsQ[re, "\\" ~~ DigitCharacter], grouped[regex, ""], regex]
]
translated[c_Symbol] := Replace[regexClass[c], None :> Throw[None, regexOf]]
translated[_] := Throw[None, regexOf]

(* The classes in the C locale are of ASCII; a byte above 127, part of a character beyond ASCII,
   counts as a letter. Digits are a class, not the range 0-9, which the system's regexes compare by
   collation, at twice the time. *)
$nonASCII = "[^" <> FromCharacterCode[1] <> "-" <> FromCharacterCode[127] <> "]"

$classes = <|
    DigitCharacter -> {"[[:digit:]]", {}}, LetterCharacter -> {"([[:alpha:]]|" <> $nonASCII <> ")", {None}},
    WhitespaceCharacter -> {"[[:space:]]", {}}, WordCharacter -> {"([[:alnum:]]|" <> $nonASCII <> ")", {None}},
    PunctuationCharacter -> {"[[:punct:]]", {}}, HexadecimalCharacter -> {"[[:xdigit:]]", {}},
    StartOfString -> {"^", {}}, EndOfString -> {"$", {}}, Whitespace -> {"[[:space:]]+", {}},
    NumberString -> {"[+-]?([[:digit:]]+([.][[:digit:]]*)?|[.][[:digit:]]+)", {None, None}}
|>

(* {regex, names} of a named class of characters, or None *)
regexClass[c_Symbol] := Lookup[$classes, c, None]

(* the regexes joined by the separator, with their names in order *)
joined[parts_List, separator_String] := {StringRiffle[First /@ parts, separator], Catenate[Last /@ parts]}

(* the regex in a group of no name, then the suffix *)
grouped[{regex_String, names_List}, suffix_String] := {"(" <> regex <> ")" <> suffix, Prepend[names, None]}

(* s with the characters that a regex reads specially escaped *)
escaped[s_String] := StringReplace[s, $regexEscapes]
$regexEscapes = Function[c, c -> "\\" <> c] /@ Characters[".[]{}()\\*+?^$|"]

(* Characters in a bracket expression, as POSIX reads one, where a backslash is a character as any
   other: ] first, - last, ^ anywhere but first, and [ before ^ and -, where no : . or = follows it;
   a ^ alone escaped outside a bracket; [^...] for negated. *)
bracketed[chars_List, negated_] := With[{set = DeleteDuplicates[chars]},
    With[{middle = Join[DeleteCases[set, "]" | "-" | "^" | "["], Intersection[set, {"["}]]},
        Which[
            ! negated && set === {"^"}, "\\^",
            ! negated && ! MemberQ[set, "]"] && middle === {} && MemberQ[set, "^"], "[" <> If[MemberQ[set, "-"], "-", ""] <> "^]",
            True, StringJoin["[", If[negated, "^", ""], Intersection[set, {"]"}], middle, Intersection[set, {"^"}], Intersection[set, {"-"}], "]"]]]]

(* The escapes of Perl's syntax that POSIX names otherwise; the groups of a RegularExpression, each
   a "(" that is not escaped, not in a bracket expression, and not "(?" of PCRE, which a POSIX
   regex does not have. *)
posixRegex[re_String] := StringReplace[re, {"\\d" -> "[[:digit:]]", "\\s" -> "[[:space:]]", "\\w" -> "[[:alnum:]_]", "\\D" -> "[^[:digit:]]", "\\S" -> "[^[:space:]]", "\\W" -> "[^[:alnum:]_]"}]

regexGroupCount[re_String] := Replace[Fold[regexScanned, {0, "Normal"}, Characters[re]], {{count_, "Open"} :> count + 1, {count_, _} :> count}]

(* the groups counted and the state of the scan of a regex after a character; in a bracket
   expression a "]" first, after "^" or not, is a character, and [:class:], [.symbol.] and
   [=class=] end at their own "]" *)
regexScanned[{count_, "Open"}, "?"] := {count, "Normal"}
regexScanned[{count_, "Open"}, c_] := regexScanned[{count + 1, "Normal"}, c]
regexScanned[{count_, "Normal"}, "\\"] := {count, "Escape"}
regexScanned[{count_, "Normal"}, "("] := {count, "Open"}
regexScanned[{count_, "Normal"}, "["] := {count, "BracketFirst"}
regexScanned[{count_, "Normal" | "Escape"}, _] := {count, "Normal"}
regexScanned[{count_, "BracketFirst"}, "^"] := {count, "BracketCaret"}
regexScanned[{count_, "BracketFirst" | "BracketCaret"}, "]"] := {count, "Bracket"}
regexScanned[{count_, "BracketFirst" | "BracketCaret" | "Bracket"}, "["] := {count, "BracketOpen"}
regexScanned[{count_, "Bracket"}, "]"] := {count, "Normal"}
regexScanned[{count_, "BracketFirst" | "BracketCaret" | "Bracket"}, _] := {count, "Bracket"}
regexScanned[{count_, "BracketOpen"}, ":" | "." | "="] := {count, "Class"}
regexScanned[{count_, "BracketOpen"}, c_] := regexScanned[{count, "Bracket"}, c]
regexScanned[{count_, "Class"}, ":" | "." | "="] := {count, "ClassEnd"}
regexScanned[{count_, "ClassEnd"}, "]"] := {count, "Bracket"}
regexScanned[{count_, "Class" | "ClassEnd"}, _] := {count, "Class"}


(* ::Section:: *)
(*Characters*)

(* The classes are Wolfram 15's [WL 15.0.0], as the paclet records them: the codes below 65536 of
   a class are a table, by code + 1, made the first time, 1 for each code of the class; those
   above are its runs. *)
recordedRuns[class_String] := With[{runs = Wolfram`Parser`Private`characterClassRuns[class]}, If[ListQ[runs], runs, {}]]

classTable[class_String] := classTable[class] = Module[{table = ConstantArray[0, 65536]},
    Scan[Function[run, If[First[run] < 65536, table[[First[run] + 1 ;; Min[Last[run], 65535] + 1]] = 1]], recordedRuns[class]];
    table]

classAbove[class_String] := classAbove[class] = Cases[recordedRuns[class], {low_, high_} /; high >= 65536 :> {Max[low, 65536], high}]

(* whether the code is of the class *)
classCodeQ[class_String, code_Integer] := If[code < 65536,
    classTable[class][[code + 1]] === 1,
    AnyTrue[classAbove[class], Function[run, First[run] <= code <= Last[run]]]]

anyCharacterQ[_Integer] := True
digitCodeQ[code_Integer] := 48 <= code <= 57 || (code > 127 && classCodeQ["digit", code])
letterCodeQ[code_Integer] := 65 <= code <= 90 || 97 <= code <= 122 || (code > 127 && classCodeQ["letter", code])
wordCodeQ[code_Integer] := 48 <= code <= 57 || 65 <= code <= 90 || 97 <= code <= 122 || (code > 127 && classCodeQ["word", code])
whitespaceCodeQ[code_Integer] := classCodeQ["whitespace", code]
punctuationCodeQ[code_Integer] := classCodeQ["punctuation", code]
hexadecimalCodeQ[code_Integer] := classCodeQ["hexadecimal", code]
(* a word boundary is between a character of a regex's \w, the word characters and _, and one not [WL 15.0.0] *)
regexWordCodeQ[code_Integer] := 48 <= code <= 57 || 65 <= code <= 90 || 97 <= code <= 122 || code === 95 || (code > 127 && classCodeQ["regex \\w", code])

(* A named class has a table of all its codes below 65536, so that many characters are tested at
   once: the packed table, by code + 1, 1 or 0, or None for another test. *)
classCodes[digitCodeQ] := classTable["digit"]
classCodes[letterCodeQ] := classTable["letter"]
classCodes[wordCodeQ] := classTable["word"]
classCodes[whitespaceCodeQ] := classTable["whitespace"]
classCodes[punctuationCodeQ] := classTable["punctuation"]
classCodes[hexadecimalCodeQ] := classTable["hexadecimal"]
classCodes[anyCharacterQ] := classCodes[anyCharacterQ] = ConstantArray[1, 65536]
classCodes[_] := None


(* ::Section:: *)
(*Matching*)

(* The subject of a match: subject[codes, length, text] of the string. $noMatch stands for no
   match: a part has no more ways to match. *)

(* the code of the character after position i *)
codeAt[subject[codes_, _, _], i_Integer] := Extract[codes, i + 1]

(* the text between positions i and j *)
substring[subject[_, _, text_], {i_Integer, j_Integer}] := StringTake[text, {i + 1, j}]

(* matched[p, z, i, bindings, k] matches the program p at position i of the subject z, then gives
   k[j, bindings] for the position j after it, or $noMatch *)
matched[literal[codes_List], subject[all_, n_, _], i_Integer, b_, k_] := If[i + Length[codes] <= n && Take[all, {i + 1, i + Length[codes]}] === codes,
    k[i + Length[codes], b],
    $noMatch
]
matched[characterClass[test_], z : subject[_, n_, _], i_Integer, b_, k_] := If[i < n && TrueQ[test[codeAt[z, i]]], k[i + 1, b], $noMatch]
matched[sequence[{}], _subject, i_Integer, b_, k_] := k[i, b]
matched[sequence[{p_, rest___}], z_subject, i_Integer, b_, k_] := matched[p, z, i, b, Function[{j, c}, matched[sequence[{rest}], z, j, c, k]]]
matched[alternatives[parts_List], z_subject, i_Integer, b_, k_] := firstMatch[Function[p, matched[p, z, i, b, k]], parts]
matched[repeat[p : _characterClass | literal[{_}], min_, max_, longest_], z_subject, i_Integer, b_, k_] := With[{run = runLength[classTest[p], z, i, max]},
    If[run < min, $noMatch, firstMatch[Function[count, k[i + count, b]], If[longest, Range[run, min, -1], Range[min, run]]]]
]
matched[repeat[p_, min_, max_, longest_], z_subject, i_Integer, b_, k_] := repeated[{p, min, max, longest}, z, 0, i, b, k]
(* A name bound before, the first time round a repeat, matches the text it matched then; one that
   took no part then, None, matches no more. *)
matched[named[x_, p_], z_subject, i_Integer, b_, k_] := If[KeyExistsQ[b, x],
    matched[backreference[x], z, i, b, k],
    matched[p, z, i, b, Function[{j, c}, k[j, Append[c, x -> {i, j}]]]]
]
matched[backreference[x_], subject[codes_, n_, _], i_Integer, b_, k_] := With[{span = Lookup[b, x]},
    If[ListQ[span] && i + Last[span] - First[span] <= n && Take[codes, {i + 1, i + Last[span] - First[span]}] === Take[codes, {First[span] + 1, Last[span]}],
        k[i + Last[span] - First[span], b],
        $noMatch
    ]
]
matched[builtIn[_, p_], z_subject, i_Integer, b_, k_] := matched[p, z, i, b, k]
matched[tested[p_, f_], z_subject, i_Integer, b_, k_] := matched[p, z, i, b, Function[{j, c},
    If[AllTrue[Characters[substring[z, {i, j}]], Function[character, TrueQ[f[character]]]], k[j, c], $noMatch]]]
matched[conditioned[p_, test_HoldComplete, names_], z_subject, i_Integer, b_, k_] := matched[p, z, i, b, Function[{j, c},
    If[TrueQ[boundValue[test, z, c, names]], k[j, c], $noMatch]]]
matched[excluding[test_, p_], z : subject[_, n_, _], i_Integer, b_, k_] := If[i < n && ! TrueQ[test[codeAt[z, i]]], matched[p, z, i, b, k], $noMatch]
matched[anchor[name_], z_subject, i_Integer, b_, k_] := If[anchorQ[name, z, i], k[i, b], $noMatch]

(* A repeat of more than single characters, repeated[{p, min, max, longest}, z, count, i, bindings,
   k] after count of them: one more p, the longest way first, then none. Once min of them are
   there, a p that matches nothing ends the repeat. A name of p is the text it matched the first
   time round; one that took no part then matches no more [WL 15.0.0]. *)
repeated[spec : {p_, min_, max_, longest_}, z_subject, count_Integer, i_Integer, b_, k_] := With[
    {
        more = Function[Null, If[count < max, matched[p, z, i, b, Function[{j, c}, If[j === i && count + 1 >= min,
            k[j, c],
            repeated[spec, z, count + 1, j, If[count === 0, Join[c, AssociationThread[Complement[Keys[programNames[p]], Keys[c]] -> None]], c], k]]]], $noMatch]],
        done = Function[Null, If[count >= min, k[i, b], $noMatch]]
    },
    firstMatch[Function[way, way[]], If[longest, {more, done}, {done, more}]]
]

(* the first f[item] that is not $noMatch, or $noMatch *)
firstMatch[f_, items_List] := Catch[
    Scan[Function[item, With[{result = f[item]}, If[result =!= $noMatch, Throw[result, firstMatch]]]], items];
    $noMatch,
    firstMatch
]

(* how many characters from position i pass the test, max at most *)
runLength[test_, subject[codes_, n_, _], i_Integer, max_] := LengthWhile[Take[codes, {i + 1, Min[n, i + max]}], Function[code, TrueQ[test[code]]]]

(* whether the anchor holds at position i *)
anchorQ[StartOfString, _subject, i_Integer] := i === 0
anchorQ[EndOfString, subject[_, n_, _], i_Integer] := i === n
(* a line starts after a newline, but not after one that ends the string, as a regex's ^ [WL 15.0.0] *)
anchorQ[StartOfLine, z : subject[_, n_, _], i_Integer] := i === 0 || (i < n && codeAt[z, i - 1] === 10)
anchorQ[EndOfLine, z : subject[_, n_, _], i_Integer] := i === n || codeAt[z, i] === 10
anchorQ[WordBoundary, z : subject[_, n_, _], i_Integer] := (i > 0 && regexWordCodeQ[codeAt[z, i - 1]]) =!= (i < n && regexWordCodeQ[codeAt[z, i]])

(* the value of a held test, each name bound to the text it matched, or to "" if it took no part *)
boundValue[held_HoldComplete, z_subject, b_, names_Association] := ReleaseHold[ReplaceAll[held, bindingRules[z, b, names, "Condition"]]]

(* A rule for each of the names, from the name to the text it matched. In a test, a name that took
   no part is bound to "". On a rule's right side so is a name that occurs once; one that occurs more
   than once is bound to {} where it matched nothing or took no part [WL 15.0.0]. *)
bindingRules[z_subject, b_Association, names_Association, use_String] := With[{bound = Select[b, ListQ]},
    KeyValueMap[Function[{name, occurrences}, Replace[name, HoldComplete[x_] :> (HoldPattern[x] -> With[
            {text = If[KeyExistsQ[bound, name], substring[z, bound[name]], ""]},
            If[use === "Rule" && occurrences > 1 && text === "", {}, text]])]],
        names]]


(* ::Section:: *)
(*Matches*)

(* The matches from the left. Only the positions where some program can start are tried: those of
   the characters that can come first in each, when they are known, else all of them. At a position,
   in the mode
     "First"        the first of the programs that matches there, as StringReplace and StringSplit
                    take them;
     "Each"         the programs in turn, the next tried there after one that matches nothing, as
                    StringCases and StringCount take them [WL 15.0.0];
     "Overlapping"  every program that matches there, as StringPosition takes them.
   After a match that is not empty, "First" and "Each" go on at its end; else a character later. *)
StringPatternMatches[s_String, programs : {___StringPatternProgram}, mode : "First" | "Each" | "Overlapping"] := With[
    {ps = Map[#["Program"] &, programs]},
    If[MemberQ[ps, None], None, programMatches[s, ps, mode]]]
StringPatternMatches[s_String, program_StringPatternProgram, mode : "First" | "Each" | "Overlapping"] := StringPatternMatches[s, {program}, mode]

programMatches[s_String, programs_List, mode_String] := With[{z = subject[ToCharacterCode[s], StringLength[s], s], names = programNames /@ programs},
    Replace[
        Reap[Fold[Function[{next, i}, If[i < next, next, matchesAt[mode, programs, names, z, i]]], 0, startPositions[programs, z]], matchesAt],
        {{_, {matches_List}} :> matches, _ -> {}}
    ]
]

(* matchesAt[mode, programs, names, z, i] sows the matches at position i, tagged matchesAt, so
   collecting them copies none, and gives the position the next match may start at *)
matchesAt["First", programs_List, names_List, z_subject, i_Integer] := With[
    {result = firstMatch[Function[k, programMatch[programs, names, k, z, i]], Range[Length[programs]]]},
    If[result === $noMatch,
        i + 1,
        Sow[result, matchesAt];
        If[Extract[result, 2] === i, i + 1, Extract[result, 2]]
    ]
]
matchesAt["Each", programs_List, names_List, z_subject, i_Integer] := Catch[
    Do[With[{result = programMatch[programs, names, k, z, i]},
        If[result =!= $noMatch, Sow[result, matchesAt]; If[Extract[result, 2] =!= i, Throw[Extract[result, 2], matchesAt]]]], {k, Length[programs]}];
    i + 1,
    matchesAt
]
matchesAt["Overlapping", programs_List, names_List, z_subject, i_Integer] := (
    Do[With[{result = programMatch[programs, names, k, z, i]}, If[result =!= $noMatch, Sow[result, matchesAt]]], {k, Length[programs]}];
    i + 1
)

(* the match of the kth program at position i, {i, end, k, rules}, or $noMatch *)
programMatch[programs_List, names_List, k_Integer, z_subject, i_Integer] :=
    matched[Extract[programs, k], z, i, <||>, Function[{j, b}, {i, j, k, bindingRules[z, b, Extract[names, k], "Rule"]}]]

(* the positions where one of the programs may start a match *)
startPositions[programs_List, subject[codes_, n_, _]] := With[{sets = firstCodes /@ programs},
    If[MemberQ[sets, All], Range[0, n], Flatten[Position[codes, Alternatives @@ Union @@ sets, {1}, Heads -> False]] - 1]
]

(* the codes that a match of the program may start with, or All if any *)
firstCodes[literal[{c_, ___}]] := {c}
firstCodes[sequence[{p_, ___}]] := If[nullableQ[p], All, firstCodes[p]]
firstCodes[alternatives[parts_List]] := With[{sets = firstCodes /@ parts}, If[MemberQ[sets, All], All, Union @@ sets]]
firstCodes[repeat[p_, min_, _, _]] := If[min === 0, All, firstCodes[p]]
firstCodes[named[_, p_]] := firstCodes[p]
firstCodes[tested[p_, _] | conditioned[p_, _, _]] := firstCodes[p]
firstCodes[excluding[_, p_] | builtIn[_, p_]] := firstCodes[p]
firstCodes[_] := All


End[]

EndPackage[]

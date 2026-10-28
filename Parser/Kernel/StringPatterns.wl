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

(* The characters of the classes, which the paclet's core reads too, where it has not, and the typed
	matcher. A file that Begins a context of its own is read with System` alone on the context path:
	a symbol of a context on the caller's path, such as Global`, would stand for one of the file's of
	the same name. *)
Block[{$ContextPath = {"System`"}},
	If[DownValues[Wolfram`Parser`Private`characterClassRuns] === {}, Get[FileNameJoin[{DirectoryName[$InputFileName], "CharacterClassRuns.wl"}]]];
	Get[FileNameJoin[{DirectoryName[$InputFileName], "StringPatternsVM.wl"}]]];

BeginPackage["Wolfram`Parser`StringPatterns`"]

StringPatternProgram::usage = "StringPatternProgram[patt] gives the program of the string pattern patt, an object whose properties \
are \"Pattern\", \"Program\", \"Ways\", \"Regex\", \"RegexLike\", \"RegexFinds\", \"Class\", \"Run\", \"IgnoredRestrictions\", \"Declined\" and \"ClassCodes\"."
StringPatternMatches::usage = "StringPatternMatches[s, {prog1, prog2, ...}, mode] gives the matches of the programs progi in the \
string s from the left, each {start, end, k, rules}: progk matched the characters after start up to end, rules binding its names to \
their text. The mode is \"First\", \"Each\", \"Overlapping\" or \"All\"."
StringPatternRecords::usage = "StringPatternRecords[s, {prog1, prog2, ...}, mode] gives the matches of StringPatternMatches as an \
association: \"Records\", a packed array of rows {start, end, k, then the start and end of each name of progk}, and \"Sides\", for \
each program the left side of each name's rule and whether the name occurs more than once."
Options[StringPatternMatches] = {Method -> Automatic}
Options[StringPatternRecords] = {Method -> Automatic}

Begin["`Private`"]


(* ::Section:: *)
(*Programs*)

(* A pattern becomes a program first:

	literal[{code, ...}]                these characters
	characterClass[codeIn[spec]]        a character of the class spec, data (see Characters)
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
	anchor[name]                        StartOfString, EndOfString, StartOfLine, EndOfLine,
										WordBoundary, or of a regex "EndOrFinalNewline" or
										"NotWordBoundary"
	regular[p]                          p, the program of a RegularExpression, and its parts:
										capture, captured, lookahead, lookbehind and atomic, as
										RegularExpressions.wl makes them

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

StringPatternProgram[pattern : Except[_Association]] := Block[{$merged = False, $declined = None}, With[{p = stringProgram[pattern]},
	StringPatternProgram[<|"Pattern" -> pattern, "Program" -> p, "Ways" -> If[$merged, Block[{$oneClass = False}, stringProgram[pattern]], p], "Regex" -> regexOf[pattern],
		"RegexLike" -> (p =!= None && regexLikeQ[p]), "RegexFinds" -> (p =!= None && regexFindsQ[p]),
		"Class" -> programClass[p], "Run" -> programRun[p], "IgnoredRestrictions" -> ignoredRestrictions[pattern],
		"Declined" -> If[p === None, Replace[$declined, None -> "a form no program has"], None]|>]]]

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

$regexFrontEnd = FileNameJoin[{DirectoryName[$InputFileName], "RegularExpressions.wl"}]
regexFrontEnd[] := regexFrontEnd[] = Block[{$ContextPath = {"System`"}}, Get[$regexFrontEnd]]

(* The later occurrences x : p of a name on a match's way, p not a blank, whose p the matcher
	ignores, matching the text of the first occurrence: each held, in the order of the pattern.
	Wolfram 15 warns of each, StringExpression::cond, once for each pattern it compiles [WL 15.0.0].
	An occurrence inside the name's own pattern is one of them. restrictionsSeen[p, seen] gives them
	and the names seen once p is past, as backreferenced marks the occurrences. *)
ignoredRestrictions[pattern_] := First[restrictionsSeen[pattern, {}]]
restrictionsSeen[named : Verbatim[Pattern][x_Symbol, p_], seen_List] := If[MemberQ[seen, HoldComplete[x]],
	{If[MatchQ[p, Verbatim[Blank][] | Verbatim[BlankSequence][] | Verbatim[BlankNullSequence][]], {}, {HoldForm[named]}], seen},
	With[{r = restrictionsSeen[p, Union[seen, {HoldComplete[x]}]]}, {First[r], Union[Last[r], {HoldComplete[x]}]}]]
restrictionsSeen[p_StringExpression, seen_List] := Fold[
	Function[{acc, part}, With[{r = restrictionsSeen[part, Last[acc]]}, {Join[First[acc], First[r]], Last[r]}]], {{}, seen}, List @@ p]
restrictionsSeen[p : _Alternatives | _List, seen_List] := With[{rs = Map[restrictionsSeen[#, seen] &, List @@ p]},
	{Catenate[Map[First, rs]], Union[seen, Union @@ Map[Last, rs]]}]
restrictionsSeen[(Verbatim[Repeated] | Verbatim[RepeatedNull] | Verbatim[Shortest] | Verbatim[Longest] | Verbatim[PatternTest] | Verbatim[Condition])[p_, ___], seen_List] :=
	restrictionsSeen[p, seen]
restrictionsSeen[Verbatim[Except][_, p_], seen_List] := restrictionsSeen[p, seen]
restrictionsSeen[_, seen_List] := {{}, seen}

(* the program of a string pattern, or a Throw of None, tagged program *)
program[s_String] := literal[ToCharacterCode[s]]
program[Verbatim[Verbatim][s_String]] := ownPart[literal[ToCharacterCode[s]]]
program[Verbatim[Blank][]] := characterClass[codeIn["Any"]]
program[Verbatim[BlankSequence][]] := repeat[characterClass[codeIn["Any"]], 1, Infinity, True]
program[Verbatim[BlankNullSequence][]] := repeat[characterClass[codeIn["Any"]], 0, Infinity, True]
(* the same name in a name's own part matches nothing [WL 15.0.0] *)
program[Verbatim[Pattern][x_Symbol, p_]] := named[HoldComplete[x], ReplaceAll[program[p], named[HoldComplete[x], _] -> alternatives[{}]]]
program[p_StringExpression] := sequence[program /@ List @@ p]
program[p_Alternatives] := alternativesProgram[program /@ alternativesParts[p]]
program[p_List] := alternativesProgram[program /@ p]
program[Verbatim[Repeated][p_]] := repeatOf[program[p], 1, Infinity]
program[Verbatim[Repeated][p_, max_Integer]] := repeatOf[program[p], 1, max]
program[Verbatim[Repeated][p_, {n_Integer}]] := repeatOf[program[p], n, n]
program[Verbatim[Repeated][p_, {min_Integer, max : _Integer | Infinity}]] := repeatOf[program[p], min, max]
program[Verbatim[RepeatedNull][p_]] := repeatOf[program[p], 0, Infinity]
program[Verbatim[RepeatedNull][p_, max_Integer]] := repeatOf[program[p], 0, max]
program[Verbatim[Shortest][p_]] := ownPart[shortest[program[p]]]
program[Verbatim[Longest][p_]] := ownPart[program[p]]
program[Verbatim[PatternTest][p_, f_]] := tested[program[p], f]
program[Verbatim[Condition][p_, test_]] := With[{inner = program[p]}, conditioned[inner, HoldComplete[test], programNames[inner]]]
(* Except takes a pattern of one character: Except[c, p] is p where a character that c does not
	match comes first [WL 15.0.0] *)
program[Verbatim[Except][c_]] := With[{inner = Block[{$oneClass = True}, program[c]]},
	If[singleCharacterQ[inner], characterClass[codeIn[{"Not", classSpec[inner]}]], declined["an Except of more than one character"]]]
program[Verbatim[Except][c_, p_]] := With[{inner = Block[{$oneClass = True}, program[c]]},
	If[singleCharacterQ[inner], excluding[classTest[inner], program[p]], declined["an Except of more than one character"]]]
program[HoldPattern[CharacterRange[a_String, b_String]]] := characterClass[codeIn[{"Range", First[ToCharacterCode[a]], First[ToCharacterCode[b]]}]]
program[DigitCharacter] := characterClass[codeIn[{"Named", "digit"}]]
program[LetterCharacter] := characterClass[codeIn[{"Named", "letter"}]]
program[WordCharacter] := characterClass[codeIn[{"Named", "word"}]]
program[WhitespaceCharacter] := characterClass[codeIn[{"Named", "whitespace"}]]
program[PunctuationCharacter] := characterClass[codeIn[{"Named", "punctuation"}]]
program[HexadecimalCharacter] := characterClass[codeIn[{"Named", "hexadecimal"}]]
program[Whitespace] := repeat[characterClass[codeIn[{"Named", "whitespace"}]], 1, Infinity, True]
program[NumberString] := builtIn[NumberString, program[StringExpression[
	Repeated[{"+", "-"}, {0, 1}],
	Alternatives[StringExpression[DigitCharacter .., Repeated[StringExpression[".", RepeatedNull[DigitCharacter]], {0, 1}]], StringExpression[".", DigitCharacter ..]]
]]]
program[anchorName : StartOfString | EndOfString | StartOfLine | EndOfLine | WordBoundary] := anchor[anchorName]
(* a RegularExpression's program, made by the regex front end, which is read when one is first met *)
program[RegularExpression[re_String]] := (regexFrontEnd[]; regular[regexProgram[re]])
program[p_] := declined["a " <> ToString[Head[p], InputForm] <> " in a string pattern"]

(* What has no program: a Throw of None, tagged program, what it is in $declined, which
	StringPatternProgram gives as its "Declined". *)
declined[what_String] := ($declined = what; Throw[None, program])
$declined = None

(* a repeat of p, the longest first; an anchor is no pattern to repeat [WL 15.0.0] *)
repeatOf[p_, min_, max_] := If[MatchQ[p, _anchor], declined["a repeat of an anchor"], repeat[p, min, max, True]]

(* Alternatives of single characters are one class, so that a repeat of them goes along the string
	without backtracking. In the program of every way, the "Ways" of the object, they are one class
	only where Wolfram 15 makes them one, each a character or a class of its own but the hexadecimal
	one, and are otherwise each a way of its own, as Overlaps -> All counts them [WL 15.0.0];
	$merged records a class the two programs make apart. Alternatives are tried in the order they
	are written, a literal "" among them, as the patterns of a list are, where Wolfram 15 tries a
	literal "" after the others, and in Shortest before them [W15 bug]. *)
$oneClass = True
alternativesProgram[{p_}] := p
alternativesProgram[parts_List] := Which[
	$oneClass && AllTrue[parts, singleCharacterQ],
		If[! AllTrue[parts, bracketPartQ], $merged = True]; characterClass[codeIn[unionSpec[classSpec /@ parts]]],
	! $oneClass && AllTrue[parts, bracketPartQ], characterClass[codeIn[unionSpec[classSpec /@ parts]]],
	True, alternatives[parts]]

(* the parts of alternatives inside alternatives, in the order given, which Wolfram 15 takes as one
	alternatives [WL 15.0.0] *)
alternativesParts[p_Alternatives] := Catenate[Map[Function[part, If[Head[part] === Alternatives, alternativesParts[part], {part}]], List @@ p]]

(* A part of one character that Wolfram 15 keeps apart, in Verbatim, Shortest or Longest: in the
	program of every way, never one class with the alternatives beside it [WL 15.0.0] *)
ownPart[q_] := If[bracketPartQ[q], If[$oneClass, $merged = True; q, alternatives[{q}]], q]

bracketPartQ[literal[{_}]] := True
bracketPartQ[characterClass[codeIn[{"Named", "digit" | "letter" | "word" | "whitespace" | "punctuation"}]]] := True
bracketPartQ[_] := False

(* the union of classes, those of characters one *)
unionSpec[specs_List] := With[{codes = Cases[specs, {"Codes", c_} :> c], others = DeleteCases[specs, {"Codes", _}]},
	Which[
		others === {}, {"Codes", Union @@ codes},
		codes === {} && Length[others] === 1, First[others],
		codes === {}, {"Union", others},
		True, {"Union", Prepend[others, {"Codes", Union @@ codes}]}]]

(* Every repeat in Shortest is shortest, those inside another too and those of NumberString, the
	shortest match the pattern has, where Wolfram 15 leaves NumberString's longest [W15 bug]. *)
shortest[repeat[p_, min_, max_, _]] := repeat[shortest[p], min, max, False]
shortest[sequence[parts_List]] := sequence[shortest /@ parts]
shortest[alternatives[parts_List]] := alternatives[shortest /@ parts]
shortest[named[x_, p_]] := named[x, shortest[p]]
shortest[tested[p_, f_]] := tested[shortest[p], f]
shortest[conditioned[p_, test_, names_]] := conditioned[shortest[p], test, names]
shortest[excluding[test_, p_]] := excluding[test, shortest[p]]
shortest[builtIn[name_, p_]] := builtIn[name, shortest[p]]
shortest[p_regular] := p
shortest[p_] := p

(* whether a program matches exactly one character *)
singleCharacterQ[_characterClass] := True
singleCharacterQ[literal[{_}]] := True
singleCharacterQ[_] := False

(* the test of the code of the one character that a program matches, and its class as data *)
classTest[characterClass[test_]] := test
classTest[literal[{c_}]] := codeIn[{"Codes", {c}}]
classSpec[characterClass[codeIn[spec_]]] := spec
classSpec[literal[{c_}]] := {"Codes", {c}}

(* the names of a program, each HoldComplete[x], with how many times each occurs, then the groups
	of its regexes in order, each group[n], once *)
programNames[p_] := Join[Counts[Cases[p, named[x_, _] | backreference[x_] :> x, {0, Infinity}]],
	AssociationThread[Map[group, Union[Cases[p, capture[n_, _] :> n, {0, Infinity}]]] -> 1]]

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
regexLikeQ[p_] := ! nullableQ[p] && FreeQ[p, _alternatives | repeat[_, _, _, False] | repeat[Except[_?singleCharacterQ], _, _, _] | _backreference | _regular] &&
	DuplicateFreeQ[Cases[p, named[x_, _] :> x, {0, Infinity}]]
regexFindsQ[p_] := ! nullableQ[p] && FreeQ[p, _backreference | _regular] && DuplicateFreeQ[Cases[p, named[x_, _] :> x, {0, Infinity}]]

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
nullableQ[(regular | atomic)[p_] | capture[_, p_]] := nullableQ[p]
nullableQ[_captured | _lookahead | _lookbehind] := True


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

(* A class of characters is data, so that a host builds its tables from it, and codeIn[spec] the
	test of a code:
	"Any"                     every character
	{"Named", class}          a class the paclet records: "digit", "letter", "word",
								"whitespace", "punctuation", "hexadecimal", or a class of a
								regex, "regex \w" the word characters and _ of a word boundary
								among them [WL 15.0.0]
	{"Codes", {code, ...}}    these characters
	{"Range", low, high}      the codes from low to high
	{"Union", {spec, ...}}    a character of one of them
	{"Not", spec}             a character not of it
	{"Fold", spec}            a character of it, or one a caseless regex takes for one of it *)
codeIn["Any"][_Integer] := True
(* DigitCharacter is 0 to 9 alone, as DigitQ is and its reference page says, and WordCharacter a
	letter, as LetterQ takes one, or one of them; Wolfram 15 matches every decimal digit and some
	other numbers too, as superscript 2 and one half [W15 bug 477554]. The regex classes keep
	Wolfram 15's digits, as PCRE's \d does. *)
codeIn[{"Named", "digit"}][code_Integer] := 48 <= code <= 57
codeIn[{"Named", "letter"}][code_Integer] := 65 <= code <= 90 || 97 <= code <= 122 || (code > 127 && classCodeQ["letter", code])
codeIn[{"Named", "word"}][code_Integer] := 48 <= code <= 57 || 65 <= code <= 90 || 97 <= code <= 122 || (code > 127 && classCodeQ["letter", code])
codeIn[{"Named", "regex \\w"}][code_Integer] := 48 <= code <= 57 || 65 <= code <= 90 || 97 <= code <= 122 || code === 95 || (code > 127 && classCodeQ["regex \\w", code])
codeIn[{"Named", class_String}][code_Integer] := classCodeQ[class, code]
codeIn[{"Codes", codes_List}][code_Integer] := MemberQ[codes, code]
codeIn[{"Range", low_Integer, high_Integer}][code_Integer] := low <= code <= high
codeIn[{"Union", specs_List}][code_Integer] := AnyTrue[specs, Function[spec, codeIn[spec][code]]]
codeIn[{"Not", spec_}][code_Integer] := ! codeIn[spec][code]
codeIn[{"Fold", spec_}][code_Integer] := AnyTrue[caselessSet[code], codeIn[spec]]

(* The sets of characters a caseless regex takes for one another, from CaseFolding.wl beside this
	file, read by Get alone when one is first asked for; and a character's set *)
$caseFoldingFile = FileNameJoin[{DirectoryName[$InputFileName], "CaseFolding.wl"}]
caselessSets[] := caselessSets[] = Replace[Get[$caseFoldingFile], Except[_List] -> {}]
caselessMap[] := caselessMap[] = Association[Catenate[Map[Function[set, Map[# -> set &, set]], caselessSets[]]]]
caselessSet[c_Integer] := Lookup[caselessMap[], c, {c}]

(* The codes below 65536 of a class, so that many characters are tested at once: the packed table,
	by code + 1, 1 or 0, made once; None for a test that is no class. *)
classCodes[codeIn[spec_]] := specTable[spec]
classCodes[_] := None

specTable[spec_] := specTable[spec] = Developer`ToPackedArray[tableOf[spec]]
tableOf["Any"] := ConstantArray[1, 65536]
tableOf[{"Named", "digit"}] := tableOf[{"Range", 48, 57}]
tableOf[{"Named", "word"}] := tableOf[{"Union", {{"Range", 48, 57}, {"Named", "letter"}}}]
tableOf[{"Named", class_String}] := classTable[class]
tableOf[{"Codes", codes_List}] := Module[{table = ConstantArray[0, 65536]}, table[[Select[codes, 0 <= # < 65536 &] + 1]] = 1; table]
tableOf[{"Range", low_Integer, high_Integer}] := Module[{table = ConstantArray[0, 65536]},
	If[Max[low, 0] <= Min[high, 65535], table[[Max[low, 0] + 1 ;; Min[high, 65535] + 1]] = 1]; table]
tableOf[{"Union", specs_List}] := If[specs === {}, ConstantArray[0, 65536], Unitize[Total[specTable /@ specs]]]
tableOf[{"Not", spec_}] := 1 - specTable[spec]
tableOf[{"Fold", spec_}] := Module[{table = ConstantArray[0, 65536]},
	Scan[Function[run, If[run[[1]] < 65536, table[[run[[1]] + 1 ;; Min[run[[2]], 65535] + 1]] = 1]], specRuns[{"Fold", spec}]]; table]


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
(* A repeat of a regex's backreference matches once where its group holds nothing, and where the
	group holds none, once if it may repeat no time, else not at all [WL 15.0.0] *)
matched[repeat[p : captured[n_, ___], min_, max_, longest_], z_subject, i_Integer, b_, k_] := With[{span = Lookup[b, group[n]]},
	Which[
		! ListQ[span], If[min === 0, k[i, b], $noMatch],
		span[[1]] === span[[2]], k[i, b],
		True, repeated[{p, min, max, longest}, z, 0, i, b, k]]]
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
matched[regular[p_], z_subject, i_Integer, b_, k_] := matched[p, z, i, b, k]
(* a regex's group holds what it matched last; a backreference to one that holds nothing matches
	nothing; a lookaround's first way alone, the groups it set kept where it is positive; an atomic
	part's first way alone *)
matched[capture[n_, p_], z_subject, i_Integer, b_, k_] := matched[p, z, i, b, Function[{j, c}, k[j, Append[c, group[n] -> {i, j}]]]]
matched[captured[n_, caseless_ : False], subject[codes_, len_, _], i_Integer, b_, k_] := With[{span = Lookup[b, group[n]]},
	If[ListQ[span] && i + span[[2]] - span[[1]] <= len && sameText[Take[codes, {i + 1, i + span[[2]] - span[[1]]}], Take[codes, {span[[1]] + 1, span[[2]]}], caseless],
		k[i + span[[2]] - span[[1]], b],
		$noMatch
	]
]
(* two texts' codes the same, or of any case each of the same caseless set *)
sameText[x_List, y_List, False] := x === y
sameText[x_List, y_List, True] := x === y || Map[caselessFold, x] === Map[caselessFold, y]
caselessFold[c_Integer] := First[caselessSet[c]]
matched[lookahead[p_, positive_], z_subject, i_Integer, b_, k_] := With[{r = matched[p, z, i, b, Function[{j, c}, {c}]]},
	Which[r === $noMatch, If[positive, $noMatch, k[i, b]], positive, k[i, First[r]], True, $noMatch]]
matched[lookbehind[branches_List, positive_], z_subject, i_Integer, b_, k_] := With[
	{r = firstMatch[Function[branch, If[i >= First[branch], matched[Last[branch], z, i - First[branch], b, Function[{j, c}, If[j === i, {c}, $noMatch]]], $noMatch]], branches]},
	Which[r === $noMatch, If[positive, $noMatch, k[i, b]], positive, k[i, First[r]], True, $noMatch]]
matched[atomic[p_], z_subject, i_Integer, b_, k_] := With[{r = matched[p, z, i, b, Function[{j, c}, {j, c}]]}, If[r === $noMatch, $noMatch, k[r[[1]], r[[2]]]]]

(* A repeat of more than single characters, repeated[{p, min, max, longest}, z, count, i, bindings,
	k] after count of them: one more p, the longest way first, then none. A p that matches nothing
	may end the repeat (emptyEnds). A name of p is the text it matched the first time round; one that
	took no part then matches no more [WL 15.0.0]. Where p has a name and the repeat no least, none
	in place of the first is not the end: the rest go on, as after a first that took no part. *)
repeated[spec : {p_, min_, max_, longest_}, z_subject, count_Integer, i_Integer, b_, k_] := With[
	{
		more = Function[Null, If[count < max, matched[p, z, i, b, Function[{j, c}, If[j === i && emptyEnds[spec, count],
			k[j, c],
			repeated[spec, z, count + 1, j, If[count === 0, Join[c, AssociationThread[Complement[Keys[programNames[p]], Keys[c]] -> None]], c], k]]]], $noMatch]],
		done = Function[Null, Which[
			count === 0 && min === 0 && ! FreeQ[p, _named], repeated[spec, z, 1, i, Join[b, AssociationThread[Complement[Keys[programNames[p]], Keys[b]] -> None]], k],
			count >= min, k[i, b],
			True, $noMatch]]
	},
	firstMatch[Function[way, way[]], If[longest, {more, done}, {done, more}]]
]

(* Whether an iteration that matches nothing ends a repeat after count of them: never in a repeat
	of at most max, each iteration of which is a part of its own; in a repeat of any number, once its
	least are there, but where its pattern has a name, whose first iteration is a part of its own,
	only after that one, once all but one of its least are there [WL 15.0.0]. *)
emptyEnds[{p_, min_, max_, _}, count_Integer] := max === Infinity && If[FreeQ[p, _named], count + 1 >= min, count >= Max[1, min - 1]]

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
anchorQ[WordBoundary, z : subject[_, n_, _], i_Integer] := With[{word = codeIn[{"Named", "regex \\w"}]}, (i > 0 && word[codeAt[z, i - 1]]) =!= (i < n && word[codeAt[z, i]])]
(* a regex's $ and \Z: the end, or before a newline that ends the text; \B *)
anchorQ["EndOrFinalNewline", z : subject[_, n_, _], i_Integer] := i === n || (i === n - 1 && codeAt[z, i] === 10)
anchorQ["NotWordBoundary", z_subject, i_Integer] := ! anchorQ[WordBoundary, z, i]

(* the value of a held test, each name bound to the text it matched, or to "" if it took no part *)
boundValue[held_HoldComplete, z_subject, b_, names_Association] := ReleaseHold[ReplaceAll[held, bindingRules[z, b, names, "Condition"]]]

(* A rule for each of the names, from the name to the text it matched. In a test, a name that took
	no part is bound to "". On a rule's right side so is a name that occurs once; one that occurs more
	than once is bound to {} where it matched nothing or took no part [WL 15.0.0]. *)
bindingRules[z_subject, b_Association, names_Association, use_String] := With[{bound = Select[b, ListQ]},
	KeyValueMap[Function[{name, occurrences}, With[{text = If[KeyExistsQ[bound, name], substring[z, bound[name]], ""]},
			Replace[name, {HoldComplete[x_] :> (HoldPattern[x] -> If[use === "Rule" && occurrences > 1 && text === "", {}, text]), group[n_] :> (n -> text)}]]],
		names]]


(* ::Section:: *)
(*Matches*)

(* The matches from the left. Only the positions where some program can start are tried: those of
	the characters that can come first in each, when they are known, else all of them. At a position,
	in the mode
	"First"        the first of the programs that matches there, as StringReplace and StringSplit
					take them;
	"Each"         the same, as StringCases and StringCount take them;
	"Overlapping"  every program that matches there, as StringPosition takes them, an empty match
					once, the program that has it tried there again for a match not empty;
	"All"          every way each program matches there, in the order its parts try them, the
					same text as often as it matches, as Overlaps -> All takes them [WL 15.0.0].
	After a match that is not empty, "First" and "Each" go on at its end; after an empty one, which
	they take once, they try the same place again for a match that is not empty, and go on at its
	end, else a character later, as PCRE2 and Perl go on through a text. Wolfram 15's StringCases
	tries the next pattern of a list after an empty match, an empty one again too, and its
	StringReplace goes on a character later [W15 bug]. *)
(* The typed matcher matches them, unless Method -> "Interpreter", the programs' interpreter, the
	reference it is held to. *)
StringPatternMatches[s_String, programs : {___StringPatternProgram}, mode : "First" | "Each" | "Overlapping" | "All", OptionsPattern[]] := With[
	{ps = modePrograms[programs, mode]},
	Which[
		MemberQ[ps, None], None,
		interpretedQ[ps, OptionValue[Method]], With[{z = textSubject[s], names = programNames /@ ps},
			Map[Function[m, {m[[1]], m[[2]], m[[3]], bindingRules[z, m[[4]], names[[m[[3]]]], "Rule"]}], programMatches[z, ps, mode]]],
		True, vmMatches[s, ps, mode]]]
StringPatternMatches[s_String, program_StringPatternProgram, mode : "First" | "Each" | "Overlapping" | "All", opts : OptionsPattern[]] :=
	StringPatternMatches[s, {program}, mode, opts]

(* The matches as records, for a host that binds the names itself: each {start, end, k, then the
	start and end of each name of program k}, a name that took no part -1 and -1, one that took
	none the first time round a repeat -2 and -1, -1 and -1 past the program's names; and each name's
	left side, with whether it occurs more than once, as the rules of StringPatternMatches take them. *)
StringPatternRecords[s_String, programs : {___StringPatternProgram}, mode : "First" | "Each" | "Overlapping" | "All", OptionsPattern[]] := With[
	{ps = modePrograms[programs, mode]},
	Which[
		MemberQ[ps, None], None,
		interpretedQ[ps, OptionValue[Method]], With[{names = programNames /@ ps},
			<|"Records" -> programRecords[programMatches[textSubject[s], ps, mode], names], "Sides" -> Map[nameSides, names]|>],
		True, With[{r = vmRecords[s, ps, mode]}, <|"Records" -> r[[2]], "Sides" -> r[[1]]["Sides"]|>]]]
StringPatternRecords[s_String, program_StringPatternProgram, mode : "First" | "Each" | "Overlapping" | "All", opts : OptionsPattern[]] :=
	StringPatternRecords[s, {program}, mode, opts]

textSubject[s_String] := subject[ToCharacterCode[s], StringLength[s], s]

(* whether the interpreter matches the programs, by the method *)
interpretedQ[programs_List, method_] := method === "Interpreter"

(* the programs a mode matches: every way of each in the mode "All" *)
modePrograms[programs_List, "All"] := Map[#["Ways"] &, programs]
modePrograms[programs_List, _String] := Map[#["Program"] &, programs]

(* the matches of the programs by their interpreter, each {start, end, k, bindings} *)
programMatches[z_subject, programs_List, mode_String] := Replace[
	Reap[Fold[Function[{next, i}, If[i < next, next, matchesAt[mode, programs, z, i]]], 0, startPositions[programs, z]], matchesAt],
	{{_, {matches_List}} :> matches, _ -> {}}
]

(* matchesAt[mode, programs, z, i] sows the matches at position i, tagged matchesAt, so collecting
	them copies none, and gives the position the next match may start at *)
matchesAt["First" | "Each", programs_List, z_subject, i_Integer] := With[
	{result = firstMatch[Function[k, programMatch[programs, k, z, i, False]], Range[Length[programs]]]},
	Which[
		result === $noMatch, i + 1,
		Extract[result, 2] > i, Sow[result, matchesAt]; Extract[result, 2],
		True,
			Sow[result, matchesAt];
			With[{again = firstMatch[Function[k, programMatch[programs, k, z, i, True]], Range[Length[programs]]]},
				If[again === $noMatch, i + 1, Sow[again, matchesAt]; Extract[again, 2]]]]
]
(* every program's match at a place: the first empty one, then the program's match there that is not
	empty, and after it only those that are not *)
matchesAt["Overlapping", programs_List, z_subject, i_Integer] := (
	Fold[Function[{empty, k}, With[{result = programMatch[programs, k, z, i, empty]},
		Which[
			result === $noMatch, empty,
			empty || Extract[result, 2] > i, Sow[result, matchesAt]; empty,
			True,
				Sow[result, matchesAt];
				With[{again = programMatch[programs, k, z, i, True]}, If[again =!= $noMatch, Sow[again, matchesAt]]];
				True]]], False, Range[Length[programs]]];
	i + 1
)
(* every way: a match is sown where the program ends and taken for none there, so that its parts
	try their next ways *)
matchesAt["All", programs_List, z_subject, i_Integer] := (
	Do[With[{k = k}, matched[Extract[programs, k], z, i, <||>, Function[{j, b}, Sow[{i, j, k, b}, matchesAt]; $noMatch]]], {k, Length[programs]}];
	i + 1
)

(* the match of the kth program at position i, {i, end, k, bindings}, or $noMatch: one that is not
	empty, where nonEmpty is True *)
programMatch[programs_List, k_Integer, z_subject, i_Integer, nonEmpty_] := matched[Extract[programs, k], z, i, <||>,
	If[nonEmpty, Function[{j, b}, If[j === i, $noMatch, {i, j, k, b}]], Function[{j, b}, {i, j, k, b}]]]

(* the records of the interpreter's matches, the spans of each program's names, as the typed
	matcher gives them *)
programRecords[matches_List, names_List] := With[{most = Max[0, Length /@ names]},
	Developer`ToPackedArray[Map[
		Function[m, Join[Take[m, 3], Flatten[PadRight[
			Map[Function[x, Replace[Lookup[m[[4]], x, Missing[]], {span : {_Integer, _Integer} :> span, None -> {-2, -1}, _ -> {-1, -1}}]], Keys[names[[m[[3]]]]]],
			most, {{-1, -1}}]]]],
		matches]]]

(* the left side of each name's rule, and whether the name occurs more than once *)
nameSides[names_Association] := KeyValueMap[Function[{name, occurrences}, {Replace[name, {HoldComplete[v_] :> HoldPattern[v], group[n_] :> n}], occurrences > 1}], names]

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
firstCodes[(regular | atomic)[p_] | capture[_, p_]] := firstCodes[p]
firstCodes[_] := All


(* ::Section:: *)
(*The typed matcher*)

(* The bytecode of a list of programs, made once for them: the code, the pool, the classes' specs,
	among them {"Test", t} for the passing characters of the tth PatternTest, made for each text,
	the tests, the conditions, each {HoldComplete[test], the names of its part}, the program table's
	start in the pool, the most names of a program, the registers, and each program's names. *)
(* the bytecode of the programs, kept for the 256 lists of programs matched last *)
vmBytecode[programs_List] := Lookup[$vmBytecodes, Key[programs],
	With[{bc = bytecodeOf[programs]}, $vmBytecodes = Append[If[Length[$vmBytecodes] >= 256, Rest[$vmBytecodes], $vmBytecodes], programs -> bc]; bc]]
$vmBytecodes = <||>

bytecodeOf[programs_List] := Block[
	{$ins = <||>, $pc = 0, $pool = {}, $specs = {}, $specIndex = <||>, $tests = {}, $conditions = {}, $registers = 0, $nameIndex = <||>, $foldTable = 0,
	table = {}, allNames = {}, maxNames = 0, registers = 1},
	Do[
		With[{p = programs[[k]], names = programNames[programs[[k]]]},
			$nameIndex = AssociationThread[Keys[names] -> Range[Length[names]]];
			$registers = 3 Length[names];
			With[{entry = $pc},
				generate[p]; vmEmit[8];
				AppendTo[table, {entry, Length[names], If[nullableQ[p], 0, Replace[firstSpec[p], {None -> 0, spec_ :> vmClassIndex[spec]}]], 0}]];
			maxNames = Max[maxNames, Length[names]]; registers = Max[registers, $registers];
			AppendTo[allNames, names]],
		{k, Length[programs]}];
	With[{tableAt = vmPoolAdd[Flatten[table]]},
		With[{bc = <|"Code" -> Developer`ToPackedArray[Flatten[Values[$ins]]], "Pool" -> Developer`ToPackedArray[Join[$pool, {0}]], "Specs" -> $specs,
				"Tests" -> $tests, "Conditions" -> $conditions, "Table" -> tableAt, "MaxNames" -> maxNames, "Registers" -> registers,
				"Names" -> allNames, "Sides" -> Map[nameSides, allNames]|>},
			If[$tests === {}, Append[bc, "Classes" -> specsClasses[$specs]], bc]]]]

(* the assembler, on the bytecode being made: an instruction, at the next position, so that the
	instructions are in the order of their positions; an operand set later, constants, a class's index *)
vmEmit[op_, a_ : 0, b_ : 0, c_ : 0, d_ : 0] := ($ins[$pc] = {op, a, b, c, d}; $pc++; $pc - 1)
vmOperand[at_, slot_, v_] := ($ins[at] = ReplacePart[$ins[at], slot + 1 -> v])
vmPoolAdd[values_List] := With[{at = Length[$pool] + 1}, $pool = Join[$pool, values]; at]
vmPoolSet[at_, values_List] := ($pool[[at ;; at + Length[values] - 1]] = values)
vmClassIndex[spec_] := Lookup[$specIndex, Key[spec], ($specs = Append[$specs, spec]; $specIndex[spec] = Length[$specs])]
vmNameBase[x_] := 3 ($nameIndex[x] - 1)

(* the code of a program's part *)
generate[literal[{}]] := Null
generate[literal[{c_}]] := vmEmit[1, c]
generate[literal[codes_List]] := vmEmit[2, vmPoolAdd[codes], Length[codes]]
generate[characterClass[codeIn[spec_]]] := vmEmit[3, vmClassIndex[spec]]
generate[sequence[parts_List]] := Scan[generate, parts]
generate[alternatives[{}]] := vmEmit[7]
generate[alternatives[{p_}]] := generate[p]
generate[alternatives[parts_List]] := Module[{jumps = {}, split},
	Do[ If[ j < Length[parts],
			split = vmEmit[5]; vmOperand[split, 1, $pc];
			generate[parts[[j]]]; AppendTo[jumps, vmEmit[6]];
			vmOperand[split, 2, $pc],
			generate[parts[[j]]]],
		{j, Length[parts]}];
	Scan[vmOperand[#, 1, $pc] &, jumps]]
generate[repeat[p : _characterClass | literal[{_}], min_, max_, longest_]] :=
	vmEmit[4, vmClassIndex[classSpec[p]], min, If[max === Infinity, -1, max], Boole[longest]]
generate[repeat[p : captured[n_, ___], min_, max_, longest_]] := With[{check = vmEmit[25, vmNameBase[group[n]], min]},
	repeatCode[p, min, max, longest]; vmOperand[check, 3, $pc]]
generate[repeat[p_, min_, max_, longest_]] := repeatCode[p, min, max, longest]
repeatCode[p_, min_, max_, longest_] := Module[{e = vmPoolAdd[ConstantArray[0, 11]], r = $registers, loop, iteration, done, poison, names = Keys[programNames[p]]},
	$registers += 2;
	poison = vmPoolAdd[Map[vmNameBase, names]];
	vmEmit[13, e]; loop = vmEmit[14, e]; iteration = vmEmit[15, e]; generate[p]; vmEmit[16, e]; done = vmEmit[17, e];
	vmPoolSet[e, {r, min, If[max === Infinity, -1, max], Boole[longest], loop, iteration, done, $pc, poison, Length[names], Boole[! FreeQ[p, _named]]}]]
generate[named[x_, p_]] := With[{base = vmNameBase[x]}, With[{open = vmEmit[10, base]}, generate[p]; vmEmit[11, base]; vmOperand[open, 2, $pc]]]
generate[backreference[x_]] := vmEmit[12, vmNameBase[x]]
generate[tested[p_, f_]] := With[{t = $registers}, $registers += 1; AppendTo[$tests, f];
	vmEmit[19, t]; generate[p]; vmEmit[20, t, vmClassIndex[{"Test", Length[$tests]}]]]
generate[conditioned[p_, test_, names_]] := (generate[p]; AppendTo[$conditions, {test, names}]; vmEmit[21, Length[$conditions]])
generate[excluding[codeIn[spec_], p_]] := (vmEmit[18, vmClassIndex[spec]]; generate[p])
generate[builtIn[_, p_]] := generate[p]
generate[anchor[name_]] := vmEmit[9, Replace[name, {StartOfString -> 1, EndOfString -> 2, StartOfLine -> 3, EndOfLine -> 4, WordBoundary -> 5, "EndOrFinalNewline" -> 6, "NotWordBoundary" -> 7}],
	If[MatchQ[name, WordBoundary | "NotWordBoundary"], vmClassIndex[{"Named", "regex \\w"}], 0]]
generate[regular[p_]] := generate[p]
generate[capture[n_, p_]] := With[{base = vmNameBase[group[n]]}, vmEmit[22, base]; generate[p]; vmEmit[11, base]]
generate[captured[n_]] := vmEmit[12, vmNameBase[group[n]]]
generate[captured[n_, True]] := vmEmit[12, vmNameBase[group[n]], 0, 1, foldTable[]]

(* the caseless sets in the pool, made once for the programs, {count, then each code and the first
	of its set}, in order of the codes; and those pairs *)
foldTable[] := If[$foldTable === 0, $foldTable = vmPoolAdd[Prepend[Flatten[caselessFolds[]], Length[caselessFolds[]]]], $foldTable]
caselessFolds[] := caselessFolds[] = SortBy[Catenate[Map[Function[set, Map[{#, First[set]} &, set]], caselessSets[]]], First]
(* A regex's assertion or atomic part: its choices above a barrier that the matcher cuts back to
	where the part holds, a register keeping the depth of the choices below; kinds 1 to 5 positive
	and negative lookahead, positive and negative lookbehind of len characters, and atomic. A
	lookbehind of branches is one of them that holds, or none of them. *)
assertionCode[kind_Integer, p_, len_Integer : 0] := Module[{r = $registers, open},
	$registers += 1;
	open = vmEmit[23, kind, r, len]; generate[p]; vmEmit[24, r]; vmOperand[open, 4, $pc]]
generate[lookahead[p_, positive_]] := assertionCode[If[positive, 1, 2], p]
generate[lookbehind[{{len_, p_}}, positive_]] := assertionCode[If[positive, 3, 4], p, len]
generate[lookbehind[branches_List, True]] /; Length[branches] > 1 := generate[alternatives[Map[lookbehind[{#}, True] &, branches]]]
generate[lookbehind[branches_List, False]] /; Length[branches] > 1 := Scan[generate[lookbehind[{#}, False]] &, branches]
generate[atomic[p_]] := assertionCode[5, p]

(* the class of the characters a match of a program may begin with, or None if any *)
firstSpec[literal[{c_, ___}]] := {"Codes", {c}}
firstSpec[characterClass[codeIn[spec_]]] := spec
firstSpec[sequence[parts_List]] := Module[{specs = {}, done = False},
	Do[If[! done, With[{f = firstSpec[part]}, If[f === None, Return[None, Module]]; AppendTo[specs, f]; If[! nullableQ[part], done = True]]], {part, parts}];
	If[done, unionSpec[specs], None]]
firstSpec[alternatives[parts_List]] := With[{fs = firstSpec /@ parts}, If[parts === {} || MemberQ[fs, None], None, unionSpec[fs]]]
firstSpec[repeat[p_, min_, _, _]] := If[min === 0, None, firstSpec[p]]
firstSpec[(named | builtIn)[_, p_]] := firstSpec[p]
firstSpec[tested[p_, _] | conditioned[p_, _, _] | excluding[_, p_]] := firstSpec[p]
firstSpec[(regular | atomic)[p_] | capture[_, p_]] := firstSpec[p]
firstSpec[_] := None

(* the runs of the codes of a class, sorted and apart, over every code point *)
specRuns["Any"] := {{0, 1114111}}
specRuns[{"Named", "digit"}] := {{48, 57}}
specRuns[{"Named", "word"}] := mergedRuns[Join[{{48, 57}}, recordedRuns["letter"]]]
specRuns[{"Named", class_String}] := recordedRuns[class]
specRuns[{"Codes", codes_List}] := codeRuns[codes]
specRuns[{"Range", low_Integer, high_Integer}] := If[Max[low, 0] <= Min[high, 1114111], {{Max[low, 0], Min[high, 1114111]}}, {}]
specRuns[{"Union", specs_List}] := mergedRuns[Catenate[specRuns /@ specs]]
specRuns[{"Not", spec_}] := With[{runs = mergedRuns[specRuns[spec]]},
	Select[Partition[Join[{0}, Flatten[Map[{#[[1]] - 1, #[[2]] + 1} &, runs]], {1114111}], 2], #[[1]] <= #[[2]] &]]
specRuns[{"Fold", spec_}] := mergedRuns[Join[specRuns[spec], codeRuns[Catenate[Select[caselessSets[], Function[set, AnyTrue[set, codeIn[spec]]]]]]]]

codeRuns[codes_List] := Map[{First[#], Last[#]} &, Split[Union[codes], #2 == #1 + 1 &]]

mergedRuns[runs_List] := If[runs === {}, {}, Fold[Function[{acc, run}, If[run[[1]] <= acc[[-1, 2]] + 1, ReplacePart[acc, -1 -> {acc[[-1, 1]], Max[acc[[-1, 2]], run[[2]]]}], Append[acc, run]]],
	{First[#]}, Rest[#]] &[SortBy[runs, First]]]

(* A class's data in the matcher, made from its runs alone, with no table of every code: the four
	words of 32 bits of its codes below 128, then {count, first, last, ...} of its runs, which the
	matcher searches for a code past ASCII. *)
classData[spec_] := classData[spec] = runsData[specRuns[spec]]
runsData[runs_List] := Developer`ToPackedArray[Join[asciiWords[runs], {Length[runs]}, Flatten[runs]]]
asciiWords[runs_List] := Module[{table = ConstantArray[0, 128]},
	Scan[Function[run, If[run[[1]] <= 127, table[[run[[1]] + 1 ;; Min[run[[2]], 127] + 1]] = 1]], runs];
	Partition[table, 32] . $bitValues]
$bitValues = Developer`ToPackedArray[2^Range[0, 31]]

(* the classes of a bytecode for a text: each spec's data, a test's that of the text's characters it
	passes; with no test, the same for every text, kept for the 1024 lists of specs met last *)
specsClasses[specs_List] := Lookup[$specsClasses, Key[specs],
	With[{classes = classesOf[<|"Specs" -> specs, "Tests" -> {}|>, {}]},
		$specsClasses = Append[If[Length[$specsClasses] >= 1024, Rest[$specsClasses], $specsClasses], specs -> classes]; classes]]
$specsClasses = <||>
vmClasses[bc_Association, codes_List] := If[bc["Tests"] === {}, bc["Classes"], classesOf[bc, codes]]
classesOf[bc_Association, codes_List] := With[{data = Map[
		Replace[#, {{"Test", t_} :> runsData[codeRuns[Select[Union[codes], TrueQ[bc["Tests"][[t]][FromCharacterCode[#]]] &]]], spec_ :> classData[spec]}] &,
		bc["Specs"]]},
	Developer`ToPackedArray[Join[{Length[data]}, Most[FoldList[Plus, Length[data] + 2, Length /@ data]], Catenate[data]]]]

$vmModes = <|"First" -> 1, "Each" -> 2, "Overlapping" -> 3, "All" -> 4|>

(* The matches of the programs in s by the typed matcher, {bytecode, records}, the records each
	{start, end, k, then the start and end of each name} in a packed array: each condition the
	matcher stops at evaluated here, the matcher then called again from its state. *)
vmRecords[s_String, programs_List, mode_String] := Module[{bc = vmBytecode[programs], codes = Developer`ToPackedArray[ToCharacterCode[s]], classes, params, out, state = {}, records = {},
		z, width, rest, condition, k, spans, st, maxNames},
	z = subject[codes, Length[codes], s]; classes = vmClasses[bc, codes]; maxNames = bc["MaxNames"];
	params = Developer`ToPackedArray[{$vmModes[mode], 0, Length[programs], maxNames, bc["Registers"], bc["Table"]}];
	While[ True,
		out = vmFunction[bc["Code"], bc["Pool"], classes, codes, params, Developer`ToPackedArray[state]];
		width = out[[3]];
		records = If[records === {}, Partition[out[[4 ;; 3 + out[[2]] width]], width], Join[records, Partition[out[[4 ;; 3 + out[[2]] width]], width]]];
		If[out[[1]] =!= 2, Break[]];
		rest = Drop[out, 3 + out[[2]] width];
		condition = rest[[1]]; k = rest[[2]]; spans = Partition[rest[[3 ;; 2 + 2 maxNames]], 2];
		st = rest[[4 + 2 maxNames ;; 3 + 2 maxNames + rest[[3 + 2 maxNames]]]];
		state = Append[st, Boole[TrueQ[conditionValue[bc, k, condition, spans, z]]]]];
	{bc, Developer`ToPackedArray[records]}]

(* the matches of the programs in s by the typed matcher, as programMatches gives them, each
	name's rule made from its record *)
vmMatches[s_String, programs_List, mode_String] := With[{r = vmRecords[s, programs, mode], z = textSubject[s]},
	Map[Function[record, {record[[1]], record[[2]], record[[3]], vmRules[r[[1]], record[[3]], Partition[record[[4 ;;]], 2], z]}], r[[2]]]]

(* the bindings of program k's names by their spans, a span {-2, _} None *)
vmBindings[bc_, k_Integer, spans_List] := Association[MapThread[
	Function[{name, span}, Which[span[[1]] >= 0, name -> span, span[[1]] === -2, name -> None, True, Nothing]],
	{Keys[bc["Names"][[k]]], Take[spans, Length[bc["Names"][[k]]]]}]]

conditionValue[bc_, k_Integer, condition_Integer, spans_List, z_subject] := With[{c = bc["Conditions"][[condition]]},
	boundValue[c[[1]], z, vmBindings[bc, k, spans], c[[2]]]]

(* the rules of a match's names, each name's text from the codes; one that occurs more than once
	and matched nothing or took no part is {}, as bindingRules gives it *)
vmRules[bc_, k_Integer, spans_List, subject[codes_, _, _]] := MapThread[
	Function[{side, span}, Rule[side[[1]], With[{text = If[span[[1]] >= 0, FromCharacterCode[codes[[span[[1]] + 1 ;; span[[2]]]]], ""]},
		If[side[[2]] && text === "", {}, text]]]],
	{bc["Sides"][[k]], Take[spans, Length[bc["Sides"][[k]]]]}]


End[]

EndPackage[]

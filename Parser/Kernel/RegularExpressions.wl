(* ::Package:: *)

(* :Title: RegularExpressions.wl - the programs of regular expressions *)
(* :Context: Wolfram`Parser`StringPatterns`Private` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	The front end of RegularExpression for the engine of string patterns: the text of a regex, as
	Wolfram 15 matches it [WL 15.0.0], a PCRE regex with Unicode classes, made the engine's program.
	StringPatterns.wl reads this file when it first meets a RegularExpression.
*)

Begin["Wolfram`Parser`StringPatterns`Private`"]

(* The program of a regex, or a Throw of None, tagged program, for a regex that Wolfram 15 does not
	take or that has a part no program has: recursion, a conditional group, a branch reset, a verb, a
	callout, \G, \K, \C, \X, a script of \p, a possessive repeat of a part that may match nothing,
	whose ways Wolfram 15's matcher counts as it repeats, or a lookbehind of no fixed length. A
	backreference in the group it refers to holds the group's text of the time round before, and
	none the first time, and the group is atomic. Its regex matches with the options Wolfram 15 gives every RegularExpression: a newline is
	\n alone, "." no newline, ^ and $ the ends of the text, $ also before a newline that ends it, the
	classes of characters Unicode's.

	The parts it makes, beside those of a string pattern:
	capture[n, p]                 p, the nth group set to what it matched, each time it matches
	captured[n]                   the text the nth group holds; no match where it holds none
	captured[n, True]             that text in any case: each character one of the same
									caseless set as the group's
	lookahead[p, positive]        nothing, where p matches from here, or where it does not
	lookbehind[{{len, p}, ...}, positive]
									nothing, where one of the p, of len characters, ends here, or
									where none does
	atomic[p]                     p, its first way alone *)
regexProgram[re_String] := Block[{$re = ToCharacterCode[re], $at = 1, $caseless = False, $multiline = False, $dotAll = False, $extended = False,
		$groups = 0, $groupNames = <||>, $references = {}},
	With[{p = regexAlternation[]},
		If[$at <= Length[$re], regexFails[]];
		If[AnyTrue[$references, # > $groups &], regexFails[]];
		p]]

(* no program: a regex Wolfram 15 does not take, or a part no program has *)
regexFails[] := declined["a regex Wolfram 15 does not take"]
regexFails[what_String] := declined[what]

(* the code here, and past it *)
regexPeek[] := If[$at <= Length[$re], $re[[$at]], None]
regexPeek[d_Integer] := If[$at + d <= Length[$re], $re[[$at + d]], None]
regexNext[] := If[$at <= Length[$re], $at++; $re[[$at - 1]], regexFails[]]
regexAhead[s_String] := With[{cs = ToCharacterCode[s]}, $at + Length[cs] - 1 <= Length[$re] && $re[[$at ;; $at + Length[cs] - 1]] === cs]
regexSkip[s_String] := If[regexAhead[s], $at += StringLength[s]; True, False]

(* In (?x), white space and a # comment are nothing. Wolfram 15 closes the group it puts a regex in
	after the regex's text, so a comment that runs to the end, or a \Q with no \E, takes that ) in,
	and the regex is none [WL 15.0.0]. *)
regexSpace[] := If[$extended,
	While[ $at <= Length[$re] && (MemberQ[{32, 9, 10, 11, 12, 13}, $re[[$at]]] || $re[[$at]] === 35),
		If[ $re[[$at]] === 35,
			While[$at <= Length[$re] && $re[[$at]] =!= 10, $at++];
			If[$at > Length[$re], regexFails[]],
			$at++]]]

(* alternatives, each a sequence of parts: the first that matches, as written *)
regexAlternation[] := Module[{branches = {regexBranch[]}},
	While[regexPeek[] === 124, $at++; AppendTo[branches, regexBranch[]]];
	regexAlternatives[branches]]

regexAlternatives[{p_}] := p
regexAlternatives[parts_List] := If[$oneClass && AllTrue[parts, singleCharacterQ],
	$merged = True; characterClass[codeIn[unionSpec[classSpec /@ parts]]],
	alternatives[parts]]

regexBranch[] := Module[{parts = {}, piece},
	regexSpace[];
	While[ $at <= Length[$re] && ! MemberQ[{124, 41}, $re[[$at]]],
		piece = regexPiece[];
		If[piece =!= Nothing, AppendTo[parts, piece]];
		regexSpace[]];
	regexSequence[parts]]

(* the characters of literals one after another are one literal *)
regexSequence[parts_List] := With[{joined = SequenceReplace[parts, ls : {literal[_], literal[_] ..} :> literal[Catenate[First /@ ls]]]},
	Replace[joined, {{} -> literal[{}], {p_} :> p, ps_ :> sequence[ps]}]]

(* a part and the repeat after it *)
regexPiece[] := Module[{atom = regexAtom[], q},
	If[atom === Nothing, Return[Nothing, Module]];
	regexSpace[];
	While[ (q = regexQuantifier[]) =!= None,
		atom = If[MatchQ[atom, _anchor | _lookahead | _lookbehind], assertionRepeat[atom, q],
			Replace[q, {
				{min_, max_, "Possessive"} :> If[nullableQ[atom], regexFails["a possessive repeat of a part that may match nothing"], atomic[repeat[atom, min, max, True]]],
				{min_, max_, greedy_} :> repeat[atom, min, max, greedy]}]];
		regexSpace[]];
	atom]

(* A repeated assertion matches nothing, so its repeat is how often it is tried: never for {0},
	once or not for a least of none, the assertion first unless the repeat is the shortest, and
	once otherwise [WL 15.0.0] *)
assertionRepeat[a_, {0, 0, _}] := literal[{}]
assertionRepeat[a_, {0, _, False}] := alternatives[{literal[{}], a}]
assertionRepeat[a_, {0, _, "Possessive"}] := atomic[alternatives[{a, literal[{}]}]]
assertionRepeat[a_, {0, _, _}] := alternatives[{a, literal[{}]}]
assertionRepeat[a_, _] := a

(* *, +, ?, {n}, {n,}, {n,m}, then ? for the shortest first, or + for the first way alone; None if
	none is here. A { that does not open a repeat is a character. *)
regexQuantifier[] := Module[{min, max, saved = $at},
	Switch[ regexPeek[],
		42, $at++; {min, max} = {0, Infinity},
		43, $at++; {min, max} = {1, Infinity},
		63, $at++; {min, max} = {0, 1},
		123, $at++;
			min = regexNumber[];
			Which[
				min === None, $at = saved; Return[None, Module],
				regexSkip["}"], max = min,
				regexSkip[","], max = Replace[regexNumber[], None -> Infinity]; If[! regexSkip["}"], $at = saved; Return[None, Module]],
				True, $at = saved; Return[None, Module]];
			If[max < min, regexFails[]],
		_, Return[None, Module]];
	Which[regexSkip["?"], {min, max, False}, regexSkip["+"], {min, max, "Possessive"}, True, {min, max, True}]]

regexNumber[] := Module[{start = $at},
	While[$at <= Length[$re] && 48 <= $re[[$at]] <= 57, $at++];
	If[$at === start, None, FromDigits[$re[[start ;; $at - 1]] - 48]]]

(* a character, a class, a group, an escape or an anchor *)
regexAtom[] := With[{c = regexNext[]},
	Switch[ c,
		40, regexGroup[],
		91, regexClassProgram[],
		46, characterClass[codeIn[If[$dotAll, "Any", {"Not", {"Codes", {10}}}]]],
		94, anchor[If[$multiline, StartOfLine, StartOfString]],
		36, anchor[If[$multiline, EndOfLine, "EndOrFinalNewline"]],
		92, regexEscape[],
		42 | 43 | 63, regexFails[],
		123, $at--; If[regexQuantifier[] =!= None, regexFails[], $at++; regexCharacter[c]],
		_, regexCharacter[c]]]

(* a character, of its case and the others in a caseless regex *)
regexCharacter[c_Integer] := If[$caseless, With[{set = caselessSet[c]}, If[Length[set] > 1, characterClass[codeIn[{"Codes", set}]], literal[{c}]]], literal[{c}]]

(* ( opens a group: capturing, named, of no capture, a lookaround, atomic, a comment, or options *)
regexGroup[] := Module[{p, n, name, flags},
	Which[
		regexSkip["?#"], While[regexPeek[] =!= 41, regexNext[]]; $at++; Nothing,
		regexSkip["?:"], regexGrouped[regexClosed[regexAlternation[]]],
		regexSkip["?="], lookahead[regexClosed[regexAlternation[]], True],
		regexSkip["?!"], lookahead[regexClosed[regexAlternation[]], False],
		regexSkip["?<="], regexLookbehind[regexClosed[regexAlternation[]], True],
		regexSkip["?<!"], regexLookbehind[regexClosed[regexAlternation[]], False],
		regexSkip["?>"], atomic[regexClosed[regexAlternation[]]],
		regexSkip["?P="], regexReference[Lookup[$groupNames, regexName[{41}], regexFails[]]],
		regexSkip["?P<"] || regexSkip["?<"] || regexSkip["?'"],
			name = regexName[{62, 39}];
			If[KeyExistsQ[$groupNames, name], regexFails[]];
			n = ++$groups; $groupNames[name] = n;
			regexCapture[n],
		regexPeek[] === 63, $at++; regexOptions[],
		regexPeek[] === 42, regexFails["a verb"],
		True, n = ++$groups; regexCapture[n]]]

(* the nth group, open while its parts are read; one that holds a backreference to itself is
	atomic, as Wolfram 15's matcher makes it, its choices given up once it matches [WL 15.0.0] *)
regexCapture[n_Integer] := With[{p = regexClosed[regexAlternation[]]}, If[FreeQ[p, captured[n, ___]], capture[n, p], atomic[capture[n, p]]]]

(* A group of an assertion alone is a group, which a repeat repeats, where the assertion's own
	repeat is how often it is tried [WL 15.0.0] *)
regexGrouped[p : _anchor | _lookahead | _lookbehind] := sequence[{p}]
regexGrouped[p_] := p

(* the end of a group: its options last no further *)
SetAttributes[regexClosed, HoldFirst];
regexClosed[e_] := Block[{$caseless = $caseless, $multiline = $multiline, $dotAll = $dotAll, $extended = $extended},
	With[{p = e}, If[regexNext[] =!= 41, regexFails[]]; p]]

(* (?imsx-imsx) for the rest of the group, (?imsx-imsx: ...) for its own alone *)
regexOptions[] := Module[{on = True, c, options = {$caseless, $multiline, $dotAll, $extended}},
	With[{c1 = regexPeek[], c2 = regexPeek[1]},
		Which[
			MemberQ[{82, 38}, c1] || (IntegerQ[c1] && 48 <= c1 <= 57) || (MemberQ[{43, 45}, c1] && IntegerQ[c2] && 48 <= c2 <= 57) || (c1 === 80 && c2 === 62),
				regexFails["recursion"],
			c1 === 40, regexFails["a conditional group"],
			c1 === 124, regexFails["a branch reset"],
			c1 === 67, regexFails["a callout"]]];
	While[ True,
		c = regexNext[];
		Switch[ c,
			105, options[[1]] = on, 109, options[[2]] = on, 115, options[[3]] = on, 120, options[[4]] = on,
			45, If[! on, regexFails[]]; on = False,
			41, {$caseless, $multiline, $dotAll, $extended} = options; Return[Nothing, Module],
			58, Return[Block[{$caseless = options[[1]], $multiline = options[[2]], $dotAll = options[[3]], $extended = options[[4]]},
				With[{p = regexGrouped[regexAlternation[]]}, If[regexNext[] =!= 41, regexFails[]]; p]], Module],
			_, regexFails[]]]]

regexName[ends_List] := Module[{start = $at},
	While[$at <= Length[$re] && ! MemberQ[ends, $re[[$at]]], $at++];
	If[$at > Length[$re] || $at === start, regexFails[]];
	$at++;
	FromCharacterCode[$re[[start ;; $at - 2]]]]

(* A lookbehind's branches each of a fixed number of characters, which may differ from branch to
	branch [WL 15.0.0] *)
regexLookbehind[p_, positive_] := lookbehind[Map[Function[branch, With[{len = fixedLength[branch]}, If[len === None, regexFails["a lookbehind of no fixed length"], {len, branch}]]],
	Replace[p, {alternatives[parts_] :> parts, other_ :> {other}}]], positive]

fixedLength[literal[codes_]] := Length[codes]
fixedLength[_characterClass] := 1
fixedLength[sequence[parts_]] := With[{ls = fixedLength /@ parts}, If[MemberQ[ls, None], None, Total[ls]]]
fixedLength[alternatives[parts_]] := With[{ls = Union[fixedLength /@ parts]}, If[MatchQ[ls, {_Integer}], First[ls], None]]
fixedLength[repeat[p_, n_Integer, n_Integer, _]] := Replace[fixedLength[p], len_Integer :> n len]
fixedLength[(capture[_, p_]) | atomic[p_]] := fixedLength[p]
fixedLength[_anchor | _lookahead | _lookbehind] := 0
fixedLength[_] := None

(* an escape: a class, an anchor, a backreference, \Q...\E, or a character *)
regexEscape[] := With[{c = regexNext[]},
	Switch[ c,
		100, regexSpecClass[{"Named", "regex \\d"}], 68, regexSpecClass[{"Not", {"Named", "regex \\d"}}],
		119, regexSpecClass[{"Named", "regex \\w"}], 87, regexSpecClass[{"Not", {"Named", "regex \\w"}}],
		115, regexSpecClass[{"Named", "regex \\s"}], 83, regexSpecClass[{"Not", {"Named", "regex \\s"}}],
		104, regexSpecClass[{"Named", "regex \\h"}], 72, regexSpecClass[{"Not", {"Named", "regex \\h"}}],
		118, regexSpecClass[{"Named", "regex \\v"}], 86, regexSpecClass[{"Not", {"Named", "regex \\v"}}],
		78, characterClass[codeIn[{"Not", {"Codes", {10}}}]],
		82, atomic[alternatives[{literal[{13, 10}], characterClass[codeIn[{"Codes", {10, 11, 12, 13, 133, 8232, 8233}}]]}]],
		112, regexSpecClass[regexProperty[]], 80, regexSpecClass[{"Not", regexProperty[]}],
		98, anchor[WordBoundary], 66, anchor["NotWordBoundary"],
		65, anchor[StartOfString], 122, anchor[EndOfString], 90, anchor["EndOrFinalNewline"],
		81, regexQuoted[],
		69, Nothing,
		103, regexReference[regexGroupNumber[]],
		107, regexReference[regexNamed[]],
		_?(49 <= # <= 57 &), $at--; regexDigitEscape[],
		_, regexCharacter[regexEscapedCode[c]]]]

regexSpecClass[spec_] := characterClass[codeIn[spec]]

(* \Q...\E: the characters between, as they are *)
regexQuoted[] := Module[{start = $at},
	While[$at <= Length[$re] && ! regexAhead["\\E"], $at++];
	With[{cs = $re[[start ;; $at - 1]]}, If[! regexSkip["\\E"], regexFails[]]; regexSequence[regexCharacter /@ cs]]]

(* \1 to \9 a backreference; \10 and on one where that many groups have opened, else octal *)
regexDigitEscape[] := Module[{start = $at, n},
	n = regexNumber[];
	If[n < 10 || n <= $groups, regexReference[n],
		$at = start; regexCharacter[regexOctal[3]]]]

regexReference[n_Integer] := (If[n < 1, regexFails[]]; AppendTo[$references, n]; If[$caseless, captured[n, True], captured[n]])

(* \g{n}, \gn, \g{-n}, \g{name} *)
regexGroupNumber[] := Module[{braced = regexSkip["{"], negative, n, name},
	negative = regexSkip["-"];
	n = regexNumber[];
	Which[
		n =!= None, If[braced && ! regexSkip["}"], regexFails[]]; If[negative, $groups - n + 1, n],
		braced && ! negative, name = regexName[{125}]; Lookup[$groupNames, name, regexFails[]],
		True, regexFails[]]]

(* \k<name>, \k'name', \k{name} *)
regexNamed[] := With[{open = regexNext[]},
	Lookup[$groupNames, regexName[Switch[open, 60, {62}, 39, {39}, 123, {125}, _, regexFails[]]], regexFails[]]]

(* the code of an escaped character: \a \e \f \n \r \t, \cX, \x.., \o{..}, \0.., or the character
	itself if it is not a letter or a digit *)
regexEscapedCode[c_Integer] := Switch[ c,
	97, 7, 101, 27, 102, 12, 110, 10, 114, 13, 116, 9,
	99, BitXor[ToCharacterCode[ToUpperCase[FromCharacterCode[regexNext[]]]][[1]], 64],
	120, regexHex[],
	111, If[! regexSkip["{"], regexFails[]]; With[{v = regexDigits[8, Infinity]}, If[! regexSkip["}"], regexFails[]]; v],
	48, $at--; regexOctal[3],
	71, regexFails["\\G"], 75, regexFails["\\K"], 67, regexFails["\\C"], 88, regexFails["\\X"],
	_?(48 <= # <= 57 || 65 <= # <= 90 || 97 <= # <= 122 &), regexFails[],
	_, c]

regexHex[] := If[regexSkip["{"], With[{v = regexDigits[16, Infinity]}, If[! regexSkip["}"] || v > 1114111, regexFails[]]; v], Replace[regexDigits[16, 2], None -> 0]]
regexOctal[most_Integer] := Replace[regexDigits[8, most], None -> 0]
regexDigits[base_Integer, most_] := Module[{start = $at, values = {}, d},
	While[ $at <= Length[$re] && Length[values] < most && (d = digitValue[$re[[$at]]]) < base, AppendTo[values, d]; $at++];
	If[values === {}, None, FromDigits[values, base]]]
digitValue[c_Integer] := Which[48 <= c <= 57, c - 48, 65 <= c <= 70, c - 55, 97 <= c <= 102, c - 87, True, 99]

(* \p{name}, \p{^name}, \pL: a general category, as the regex classes record it *)
regexProperty[] := Module[{name, negated = False},
	If[ regexSkip["{"],
		negated = regexSkip["^"]; name = regexName[{125}],
		name = FromCharacterCode[{regexNext[]}]];
	If[! MemberQ[$regexProperties, name], regexFails["\\p{" <> name <> "}, a script or no property"]];
	If[negated, {"Not", {"Named", "regex \\p{" <> name <> "}"}}, {"Named", "regex \\p{" <> name <> "}"}]]
$regexProperties = {"L", "Lu", "Ll", "Lt", "Lm", "Lo", "L&", "M", "Mn", "Mc", "Me", "N", "Nd", "Nl", "No", "P", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
	"S", "Sm", "Sc", "Sk", "So", "Z", "Zs", "Zl", "Zp", "C", "Cc", "Cf", "Co", "Cn"}

(* [...]: its characters, ranges, escaped classes and POSIX classes, or none of them after ^; in a
	caseless regex its characters of every case, and those of [:lower:] and [:upper:] *)
regexClassProgram[] := Module[{negated = regexSkip["^"], items = {}, first = True, item, low, high},
	While[ True,
		If[$at > Length[$re], regexFails[]];
		If[regexPeek[] === 93 && ! first, $at++; Break[]];
		first = False;
		item = regexClassItem[];
		If[ MatchQ[item, _Integer] && regexPeek[] === 45 && regexPeek[1] =!= 93 && regexPeek[1] =!= None,
			$at++; low = item; high = regexClassItem[];
			If[! IntegerQ[high] || high < low, regexFails[]];
			AppendTo[items, {"Range", low, high}],
			AppendTo[items, Replace[item, c_Integer :> {"Codes", {c}}]]]];
	With[{spec = unionSpec[If[$caseless, Map[Replace[#, s : {"Codes" | "Range", ___} :> {"Fold", s}] &, items], items]]},
		regexSpecClass[If[negated, {"Not", spec}, spec]]]]

(* a character of a class, its code, or a class *)
regexClassItem[] := With[{c = regexNext[]},
	Which[
		c === 91 && regexAhead[":"], regexPosix[],
		c === 92, With[{e = regexNext[]},
			Switch[ e,
				100, {"Named", "regex \\d"}, 68, {"Not", {"Named", "regex \\d"}},
				119, {"Named", "regex \\w"}, 87, {"Not", {"Named", "regex \\w"}},
				115, {"Named", "regex \\s"}, 83, {"Not", {"Named", "regex \\s"}},
				104, {"Named", "regex \\h"}, 72, {"Not", {"Named", "regex \\h"}},
				118, {"Named", "regex \\v"}, 86, {"Not", {"Named", "regex \\v"}},
				112, regexProperty[], 80, {"Not", regexProperty[]},
				98, 8,
				_?(48 <= # <= 57 &), $at--; regexOctal[3],
				_, regexEscapedCode[e]]],
		True, c]]

regexPosix[] := Module[{negated, name},
	$at++;
	negated = regexSkip["^"];
	name = regexName[{58}];
	If[! regexSkip["]"] || ! MemberQ[{"alpha", "digit", "alnum", "upper", "lower", "space", "blank", "punct", "xdigit", "cntrl", "print", "graph", "word"}, name], regexFails[]];
	With[{spec = If[$caseless && MemberQ[{"upper", "lower"}, name], {"Union", {{"Named", "regex [:upper:]"}, {"Named", "regex [:lower:]"}}}, {"Named", "regex [:" <> name <> ":]"}]},
		If[negated, {"Not", spec}, spec]]]

End[]

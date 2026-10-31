(* :Package: Wolfram`Parser`
	:Title:   Read a BNF / EBNF grammar file using the Wolfram`Parser` core

	The input is a grammar in the style the TPTP project publishes
	(TPTPWorld/SyntaxBNF), with rules of the shape:

		<name>     ::= <alt1> | <alt2> | ...
		<name>     :== ...   (semantic rules - same shape as ::=)
		<name>     ::- ...   (token-level rules - same shape; lowering optional)
		<name>     ::: ...   (character-class rules - same shape; lowering optional)

	The BNF itself is parsed by a grammar built out of Wolfram`Parser`
	combinators - the same library this paclet exposes. No regex
	StringCases, no AppendTo, no hand-cracked line scanning: a literal
	demonstration that the combinator core is enough to parse its own
	meta-grammar.

	A second dialect, "Classic", reads the BNF of many language reports:
	`<name> ::=` or `<name> ::`, terminals in quotes, `[...]` optional,
	`{...}` repeated, `(...)` grouped, and `"a" | ... | "z"` for a range of
	characters - the grammar the ABC language's specification publishes -
	`&x` and `!x`, where x must follow, or must not, taking nothing, and
	`x - y`, x where y does not match, as ISO EBNF writes an exception.
	Its comments are Wolfram Language comments, and a line that begins
	with % is a declaration, as a parser generator's are, which
	EBNFDeclarations gives.

	The output of `EBNFParse[File[path]]` / `EBNFParse[source]` is an
	`Association[name -> ParserCombinator]` covering every rule in the
	file. The caller wires up lexical primitives (rules whose body is a
	`:::` regex-style char class, or `::-` token construction) by
	passing `"PrimitiveOverrides" -> <|name -> ParserCombinator|>`. *)

BeginPackage["Wolfram`Parser`"]

EBNFParse::usage =
	"EBNFParse[source] reads a BNF grammar from a string and returns " <>
	"an Association of rule names to ParserCombinators. " <>
	"EBNFParse[File[path]] reads from a file."

EBNFRules::usage =
	"EBNFRules[source] returns the list of raw EBNFRule[name, kind, " <>
	"alts] structures parsed from `source`, without lowering them to " <>
	"ParserCombinators, and in the classic dialect an EBNFDeclaration[keyword, fields] " <>
	"for each declaration. Useful for inspecting the parsed grammar shape. " <>
	"EBNFRules[File[path]] reads from a file."

EBNFDeclarations::usage =
	"EBNFDeclarations[source] gives the declarations of a grammar in the classic dialect, " <>
	"its lines that begin with %, as an Association of each keyword with the fields of its " <>
	"declarations in order, a list for each: <|keyword -> {{field, ...}, ...}, ...|>. A field " <>
	"is a quoted terminal or a word, as a string, or an integer. " <>
	"EBNFDeclarations[File[path]] reads from a file."

Begin["`EBNFPrivate`"]


(* ::Section:: *)
(*The BNF grammar, expressed in our own combinators*)

space          = ParseCharacter[" " | "\t" | "\n" | "\r"]
ws             = ParseMany[space]
commentBody    = ParseMany[ParseCharacter[_ ? (# =!= "\n" &)]]
comment        = ParseAction[
	ParseLiteral["%"] ~~ commentBody ~~ ParseOptional[ParseLiteral["\n"]],
	Null &
]
wsc            = ParseMany[ParseChoice[ParseAction[space, Null &], comment]]

identFirstChar = ParseCharacter[LetterCharacter | "_"]
identRestChar  = ParseCharacter[LetterCharacter | DigitCharacter | "_"]

ident = ParseAction[
	identFirstChar ~~ ParseMany[identRestChar],
	StringJoin[#1, StringJoin @ #2] &
]

nonTerm = ParseAction[
	ParseLiteral["<"] ~~ ident ~~ ParseLiteral[">"],
	NonTerm[#2] &
]

arrow = ParseChoice[
	ParseLiteral["::="],
	ParseLiteral[":=="],
	ParseLiteral["::-"],
	ParseLiteral[":::"]
]

(* Literal token in the RHS - everything that isn't a non-terminal, the
	`|` separator, or the postfix `*`. Splits letter / non-letter runs
	so adjacent BNF text like `tpi(` becomes two literals (`tpi`, `(`),
	each of which the TPTP source may surround with whitespace. *)

literalIsLetterChar = (StringMatchQ[#, LetterCharacter | DigitCharacter] || # === "_" || # === "$") &

literalLetters = ParseAction[
	ParseSome[ParseCharacter[_ ? literalIsLetterChar]],
	Lit[StringJoin[{##}]] &
]

(* `<`, `>`, `*` are deliberately NOT reserved: the BNF body can contain
	bare `<`, `>`, `*` literals (e.g. `<subtype_sign> ::= <<`, the `?*`
	in `<type_quantifier> ::= !> | ?*`). PEG ordering tries the longer
	matches first - a valid `<name>` is consumed as a non-terminal, and
	a `<name>*` is consumed as a Rep before bare punctuation runs are
	tried - so bare `<`/`>`/`*` only reach `literalPunct` when nothing
	richer matches. *)
literalPunctReserved = {" ", "\t", "\n", "\r", "|", "%"}

literalIsPunctChar = (
	! MemberQ[literalPunctReserved, #] && ! literalIsLetterChar[#]
) &

(* literalPunct is greedy, but each char is guarded by a lookahead
	that the cursor is not at the start of a valid `<name>` non-terminal.
	That stops the run at the `<` of `(<name>` so `(` becomes a 1-char
	literal and `<name>` is consumed by `nonTerm`. The `<=>` connective
	form (BNF source `<` `=` `>`, no ident between `<` and `>`) still
	merges into one literal because `<=...` is not a valid nonTerm. *)
literalPunct = ParseAction[
	ParseSome[
		ParseAction[
			ParseNotFollowedBy[nonTerm] ~~ ParseCharacter[_ ? literalIsPunctChar],
			#2 &
		]
	],
	Lit[StringJoin[{##}]] &
]

(* A single RHS element: a non-terminal (optionally postfixed `*`), or
	a literal run. Tried in PEG order. *)
ruleStartLookahead = ParseAction[
	nonTerm ~~ wsc ~~ arrow,
	Null &
]

rawElt = ParseChoice[
	ParseAction[
		nonTerm ~~ ws ~~ ParseLiteral["*"],
		Rep["Many", #1] &
	],
	nonTerm,
	literalLetters,
	literalPunct
]

(* An RHS element is rawElt provided we are not at the start of the next
	rule (otherwise the parser would greedily eat the next rule's LHS as
	a literal element of this rule's body). *)
elt = ParseAction[
	ParseNotFollowedBy[ruleStartLookahead] ~~ rawElt,
	#2 &
]

(* An alternation sequence: zero or more elements separated by ws. Zero
	is allowed because the TPTP grammar has rules whose body is empty
	(`<nothing> ::=`) - the empty alternative matches the empty string. *)
altSeq = ParseAction[
	ParseMany[ParseAction[elt ~~ wsc, #1 &]],
	{##} &
]

pipe = ParseAction[ParseLiteral["|"] ~~ wsc, Null &]

altsRule = ParseSepBy1[altSeq, pipe]

ruleP = ParseAction[
	nonTerm ~~ wsc ~~ arrow ~~ wsc ~~ altsRule,
	With[{name = #1[[1]], kind = #3, body = #5},
		EBNFRule[name, kind, body]
	] &
]

grammarP = ParseAction[wsc ~~ ParseMany[ParseAction[ruleP ~~ wsc, #1 &]], #2 &]


(* ===== the classic dialect =====

	`<name> ::= ...` or `<name> :: ...`; terminals in double or single quotes,
	with \n \r \t escapes; non-terminals as `<name>` or a bare name; `[...]`
	optional, `{...}` repeated, `(...)` grouped; `&x` and `!x` a lookahead,
	where the element x must follow, or must not, which takes nothing; `x - y`
	x where the element y does not match, which binds more tightly than a
	sequence, as ISO EBNF's exception does; and an
	alternative that is only `...` between two one-character terminals stands
	for the characters between them, as in `"a" | ... | "z"`. Whitespace, newlines included,
	separates elements; a rule ends where the next `<name> ::` begins.
	A comment, nested as in the Wolfram Language, is whitespace. Between
	rules, % begins a declaration: a keyword, then the fields up to the end
	of the line, each a quoted terminal, an integer, or a word of other
	characters but whitespace, quotes and a parenthesis. *)

classicComment = ParseAction[
	ParseLiteral["(*"] ~~
		ParseMany[ParseChoice[
			ParseSome[ParseCharacter[_ ? (# =!= "*" && # =!= "(" && # =!= "\n" &)]],
			ParseLiteral["\n"],
			ParseRecursive[classicComment],
			ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[")"]],
			ParseLiteral["("]
		]] ~~
		ParseLiteral["*)"],
	Null &
]

classicWs = ParseMany[ParseChoice[space, classicComment]]

classicArrow = ParseChoice[ParseLiteral["::="], ParseLiteral["::"]]

classicName = ParseChoice[nonTerm, ParseAction[ident, NonTerm[#] &]]

classicRuleStart = ParseAction[classicName ~~ classicWs ~~ classicArrow, Null &]

classicEscaped = ParseAction[
	ParseLiteral["\\"] ~~ ParseCharacter[_],
	Replace[#2, {"n" -> "\n", "r" -> "\r", "t" -> "\t"}] &
]

classicQuoted[q_String] := ParseAction[
	ParseLiteral[q] ~~
		ParseMany[ParseChoice[classicEscaped, ParseCharacter[_ ? (# =!= q && # =!= "\\" && # =!= "\n" &)]]] ~~
		ParseLiteral[q],
	Lit[StringJoin[#2]] &
]

classicLiteral = ParseChoice[classicQuoted["\""], classicQuoted["'"]]

classicGroup[open_String, close_String, wrap_] := ParseAction[
	ParseLiteral[open] ~~ classicWs ~~ ParseRecursive[classicAlts] ~~ ParseLiteral[close],
	wrap[#3] &
]

(* &x and !x: what must follow, or must not, taken by neither *)
classicLookahead = ParseAction[
	ParseCharacter["&" | "!"] ~~ classicWs ~~ ParseRecursive[classicElt],
	If[#1 === "&", Ahead[#3], NotAhead[#3]] &
]

classicElt = ParseChoice[
	classicLookahead,
	classicLiteral,
	classicGroup["[", "]", Opt],
	classicGroup["{", "}", Rep["ManyAlts", #] &],
	classicGroup["(", ")", Group],
	ParseAction[ParseLiteral["..."], EBNFEllipsis &],
	classicName
]

(* x - y: x where y does not match *)
classicTerm = ParseAction[
	classicElt ~~ ParseOptional[ParseAction[classicWs ~~ ParseLiteral["-"] ~~ classicWs ~~ classicElt, #4 &]],
	If[MissingQ[#2], #1, ButNot[#1, #2]] &
]

classicSeq = ParseAction[
	ParseMany[ParseAction[ParseNotFollowedBy[classicRuleStart] ~~ classicTerm ~~ classicWs, #2 &]],
	{##} &
]

classicAlts = ParseAction[
	ParseSepBy1[classicSeq, ParseAction[ParseLiteral["|"] ~~ classicWs, Null &]],
	characterRanges[{##}] &
]

(* "a" | ... | "z": the alternatives from a to z *)
characterRanges[alts_List] := alts //. {pre___, {Lit[a_String]}, {EBNFEllipsis}, {Lit[b_String]}, post___} /;
	StringLength[a] === 1 && StringLength[b] === 1 :> {pre, {CharRange[a, b]}, post}

classicRuleP = ParseAction[
	classicName ~~ classicWs ~~ classicArrow ~~ classicWs ~~ classicAlts,
	EBNFRule[#1[[1]], #3, #5] &
]

(* a declaration: % and its keyword, then its fields to the end of the line *)
classicLineWs = ParseMany[ParseChoice[ParseCharacter[" " | "\t"], classicComment]]

classicWordCharacter = ParseCharacter[_ ? (! StringMatchQ[#, WhitespaceCharacter | "\"" | "'" | "("] &)]

classicField = ParseChoice[
	ParseAction[classicLiteral, First],
	ParseAction[
		ParseOptional[ParseLiteral["-"]] ~~ ParseSome[ParseCharacter[DigitCharacter]] ~~ ParseNotFollowedBy[classicWordCharacter],
		Function[{sign, digits, end}, If[MissingQ[sign], 1, -1] FromDigits[StringJoin[digits]]]
	],
	ParseAction[ParseSome[classicWordCharacter], StringJoin]
]

classicDeclaration = ParseAction[
	ParseLiteral["%"] ~~ ident ~~ classicLineWs ~~ ParseMany[ParseAction[classicField ~~ classicLineWs, #1 &]] ~~
		ParseChoice[ParseCharacter["\n" | "\r"], ParseNotFollowedBy[ParseCharacter[_]]],
	EBNFDeclaration[#2, #4] &
]

classicGrammarP = ParseAction[classicWs ~~ ParseMany[ParseAction[ParseChoice[classicRuleP, classicDeclaration] ~~ classicWs, #1 &]], #2 &]


(* ::Section:: *)
(*Lowering*)

(* What the lowering skips between elements, and what is set while lowering one
	rule: the characters the skip matches (None when the default whitespace
	skips any), whether the rule is matched without skipping, and the grammar,
	for what an element can begin with. *)
$ebnfSkip = ParseMany[ParseCharacter[WhitespaceCharacter]]
$ebnfSkipChars = None
$ebnfContiguous = False
$ebnfGram = <||>
$ebnfVisiting = {}
$ebnfTokenText = <||>

(* whether the skip goes before an element: never inside a contiguous rule, and
	not before an element that can begin with a character the skip would take,
	so that whitespace a grammar writes out keeps its meaning *)
skipBeforeQ[elt_] := ! TrueQ[$ebnfContiguous] && ! startsWithSkipQ[elt]

startsWithSkipQ[_] /; $ebnfSkipChars === None := False
startsWithSkipQ[Lit[s_String]] := StringLength[s] > 0 && StringMatchQ[StringTake[s, 1], $ebnfSkipChars]
startsWithSkipQ[CharRange[a_String, b_String]] := AnyTrue[CharacterRange[a, b], StringMatchQ[#, $ebnfSkipChars] &]
startsWithSkipQ[NonTerm[name_String]] := If[ MemberQ[$ebnfVisiting, name], False,
	Block[{$ebnfVisiting = Append[$ebnfVisiting, name]}, AnyTrue[Lookup[$ebnfGram, name, {}], altStartsWithSkipQ]]
]
startsWithSkipQ[(Opt | Group)[alts_List] | Rep["ManyAlts", alts_List]] := AnyTrue[alts, altStartsWithSkipQ]
startsWithSkipQ[Rep["Many", inner_]] := startsWithSkipQ[inner]
startsWithSkipQ[_] := False

altStartsWithSkipQ[{first_, ___}] := startsWithSkipQ[first]
altStartsWithSkipQ[_] := False

(* one repetition of a repeated element, with the skip before it when it goes there *)
repetition[elt_, lowered_] := If[ skipBeforeQ[elt], ParseAction[$ebnfSkip ~~ lowered, #2 &], lowered]

lowerElt[Opt[alts_List], symMap_, overrides_] := ParseOptional[lowerBody[alts, symMap, overrides]]

lowerElt[Group[alts_List], symMap_, overrides_] := lowerBody[alts, symMap, overrides]

lowerElt[CharRange[a_String, b_String], _, _] := ParseCharacter[Alternatives @@ CharacterRange[a, b]]

lowerElt[Ahead[elt_], symMap_, overrides_] := ParseLookahead[lowerElt[elt, symMap, overrides]]

lowerElt[NotAhead[elt_], symMap_, overrides_] := ParseNotFollowedBy[lowerElt[elt, symMap, overrides]]

lowerElt[ButNot[elt_, exception_], symMap_, overrides_] :=
	ParseAction[ParseNotFollowedBy[lowerElt[exception, symMap, overrides]] ~~ lowerElt[elt, symMap, overrides], #2 &]

lowerElt[Lit[s_String], _, _] := ParseLiteral[s]

lowerElt[NonTerm[name_String], symMap_, overrides_] :=
	Which[
		KeyExistsQ[overrides, name],
			overrides[name],
		(* inside a token, a token is its text, not what its action makes of it *)
		TrueQ[$ebnfContiguous] && KeyExistsQ[$ebnfTokenText, name],
			With[{sym = $ebnfTokenText[name]}, ParseRecursive[sym]],
		KeyExistsQ[symMap, name],
			With[{sym = symMap[name]}, ParseRecursive[sym]],
		True,
			ParseFail["No parser bound for non-terminal: " <> name]
	]

(* Each iteration of a ParseMany has to consume any whitespace that
	sits between the previous match and this one - the lowering of an
	alternative sequence inserts ws BETWEEN elements but not at the
	start, so a bare ParseMany would stop at the first ws of the
	continuation. Prepend a ws-consumer per iteration. *)
lowerElt[Rep["Many", inner_], symMap_, overrides_] :=
	ParseMany[repetition[inner, lowerElt[inner, symMap, overrides]]]

(* ManyAlts holds a list-of-alt-bodies (each alt body is a list of
	elements). Emitted by the left-recursion-elimination rewrite for
	the repeating tail of an originally-left-recursive rule. *)
lowerElt[Rep["ManyAlts", altsList_List], symMap_, overrides_] :=
	ParseMany[repetition[Rep["ManyAlts", altsList], lowerBody[altsList, symMap, overrides]]]

(* Lower one alternative sequence - lowered elements separated by an
	optional-whitespace parser, then drop the whitespace pieces from the
	result list. The empty case (e.g. the body of `<nothing>` or the
	second alternative of `<annotations>`) lowers to ParseSucceed[Null]
	so the rule matches the empty string. *)
lowerSeq[{}, _, _] := ParseSucceed[Null]

lowerSeq[{single_}, symMap_, overrides_] :=
	lowerElt[single, symMap, overrides]

lowerSeq[elts_List, symMap_, overrides_] := Module[{parts},
	(* a lookahead takes nothing, and gives the sequence's value nothing *)
	parts = Join @@ MapIndexed[
		Function[{elt, i},
			If[ First[i] > 1 && skipBeforeQ[elt],
				{{$ebnfSkip, False}, {lowerElt[elt, symMap, overrides], ! MatchQ[elt, _Ahead | _NotAhead]}},
				{{lowerElt[elt, symMap, overrides], ! MatchQ[elt, _Ahead | _NotAhead]}}
			]
		],
		elts
	];
	With[{keep = Flatten @ Position[parts[[All, 2]], True]},
		ParseAction[ParseSequence @@ parts[[All, 1]], Function[{##}[[keep]]]]
	]
]

(* The combinator used to fold lowered alternatives. `ChoiceLongest`
	(POSIX longest-match) is the right semantics for grammars that
	factor their alternatives across multiple rule levels - TPTP's
	`<fof_atomic_formula> ::= <fof_plain_atomic_formula> | <fof_defined_atomic_formula>`
	is the canonical case: both alternatives can consume the same
	leading function-application term, but only the second reaches the
	trailing `= rhs` of `<fof_defined_infix_formula>`. PEG `Choice`
	commits to the first match and never reaches the equality form.

	Three modes, set via the `"ChoiceMode"` option on `EBNFParse`:
	- "PEG"     PEG-ordered (first match wins).  Fast.
	- "Longest" Always try every alt, pick the one that consumes
				the most input.  Correct for ambiguous grammars but
				~30x slower on TPTP-scale rules.
	- "Auto"    (default) Hybrid: when a rule's alts have *equal
				element counts*, sortAltsLongestFirst can't pick a
				winner statically, so use ChoiceLongest for that
				rule.  When lengths differ (the common case), the
				longest-prefix alt is unambiguous and PEG with
				longest-first is both fast and correct. *)
$choiceMode = "Auto"

chooseCombinator[alts_List] :=
	Switch[$choiceMode,
		"PEG",     ParseChoice,
		"Longest", ParseChoiceLongest,
		_,         (* "Auto": if ANY two alts share a length, the
					longest-alt-first sort can't fully disambiguate,
					so fall back to POSIX longest-match. This catches
					`<cnf_literal>` (lengths 4, 2, 1, 1 - the two
					1-elt alts tie) and `<nonassoc_connective>` while
					leaving simple alternation rules like
					`<TPTP_input> ::= <annotated_formula> | <include>`
					in fast PEG order when only one alt at each
					length applies. *)
					If[ Length[Union[Length /@ alts]] === Length[alts],
						ParseChoice, ParseChoiceLongest
					]
	]

lowerBody[alts_List, symMap_, overrides_] :=
	Switch[Length[alts],
		0, ParseFail["empty rule body"],
		1, lowerSeq[First[alts], symMap, overrides],
		_, chooseCombinator[alts] @@
			(lowerSeq[#, symMap, overrides] & /@ alts)
	]


(* ===== Left-recursion elimination =====

	A directly left-recursive rule

		A ::= A r1 | A r2 | ... | b1 | b2 | ...

	is rewritten before lowering to the PEG-friendly equivalent

		A ::= b1 (r1 | r2 | ...)* | b2 (r1 | r2 | ...)* | ...

	The right-tail (r_i) of every recursive alt becomes the repeated
	body of a ParseMany. The non-recursive alts (b_j) stay as the
	leftmost prefix; each b_j gets a copy of the tail-repetition
	appended.

	This handles the eleven directly-left-recursive rules in TPTP's
	SyntaxBNF (cnf_disjunction, fof_or_formula, fof_and_formula, the
	thf_* and tff_* connective and xprod_type rules). Indirect /
	mutually-left-recursive grammars need Paull's algorithm, which is
	not (yet) applied here. *)

rewriteLeftRecursive[name_String, alts_List] :=
	Block[{recursive, nonRecursive},
		recursive = Cases[alts, {NonTerm[name], rest___} :> {rest}];
		nonRecursive = Cases[alts, {first_, ___} /; first =!= NonTerm[name]];
		Which[
			Length[recursive] === 0,
				alts,
			Length[nonRecursive] === 0,
				(* Pure left recursion with no base case - emit a fail. *)
				{{Lit["<unreachable left recursion: " <> name <> ">"]}},
			True,
				Append[#, Rep["ManyAlts", recursive]] & /@ nonRecursive
		]
	]


(* ===== Longest-alternative-first reordering =====

	PEG `ParseChoice` commits to the first alternative that matches, so
	given two alts that share a common prefix - e.g.

		<fof_plain_term> ::= <constant> | <functor>(<fof_arguments>)

	the shorter alt (`<constant>`, which also matches just `p`) would
	always win and the function-application form would never be reached.
	Sorting alts longest-first is a left-factoring approximation: the
	longer match is tried first; if it fails to commit (e.g. no `(`
	after the functor), PEG backtracks to the shorter alt. *)

(* Use Ordering for a stable sort - SortBy is *unstable* in Mathematica,
	which would reorder equal-length alts arbitrarily. For TPTP's
	`<nonassoc_connective> ::= <=> | => | <= | ...` an unstable sort
	may put `<=` before `<=>`, in which case PEG commits to the prefix
	match and `<=>` never parses. Stable descending-by-length keeps the
	original ordering between alts of the same length, so the BNF
	author's "more-specific-first" ordering is preserved. *)
sortAltsLongestFirst[alts_List] := alts[[Ordering[-Length /@ alts]]]


(* ::Section:: *)
(*Public entry points*)

(* ===== Token / char-class rule compilation =====

	`::-` and `:::` rules use regex-style bodies (`[a-z]`, `[+-]`,
	`(<x>|<y>)`, `<x>*`, `<x>+`) at the *character* level - the brackets
	and parens are meta, not literal, and adjacent elements have no
	whitespace between them. The structured token tree the main BNF
	parser produces for `::=` rules tokenizes `[a-z]` for THAT context,
	so reusing it would lose the char-class shape.

	Instead, we reconstruct the original body string from the structured
	tokens (the reconstruction is exact because every Lit / NonTerm /
	Rep maps to its original source) and run a second parser - the
	`regexParser` below - on that string. The second parser is itself
	built out of `Parse*` combinators (same library this paclet exposes);
	its action functions return *ParserCombinator values* instead of
	strings, so the regex source compiles directly to the target parser.

	This is the same "use the combinator core to parse its own meta-
	grammar" pattern the BNF parser uses, just applied to a different
	meta-grammar (regex syntax instead of BNF rule shapes). *)

reconstructBody[alts_List] :=
	StringRiffle[reconstructAlt /@ alts, "|"]

reconstructAlt[elts_List] :=
	StringJoin[reconstructElt /@ elts]

reconstructElt[Lit[s_String]]            := s
reconstructElt[NonTerm[n_String]]        := "<" <> n <> ">"
reconstructElt[Rep["Many", inner_]]      := reconstructElt[inner] <> "*"

(* The regex meta-grammar's action functions look up non-terminal
	references in these two Block-scoped maps. *)
regexSymMap   = <||>
regexOverrides = <||>

regexLookupRef[name_String] :=
	Which[
		KeyExistsQ[regexOverrides, name],
			regexOverrides[name],
		KeyExistsQ[regexSymMap, name],
			With[{sym = regexSymMap[name]}, ParseRecursive[sym]],
		True,
			ParseFail["No parser bound for non-terminal: " <> name]
	]

(* The regex meta-grammar, built with Parse* combinators. Each piece's
	action returns a ParserCombinator value (the compiled target parser
	for that sub-expression). *)

regexMetaChar = "|" | "*" | "+" | "?" | "(" | ")" | "[" | "]" | "<" | "{" | "\\"
regexCharNotMeta = ParseCharacter[_ ? (! MatchQ[#, regexMetaChar] &)]

(* `\nnn` octal char-code escape, `\n`/`\r`/`\t`/`\\`/`\'`/`\"` named
	escape, or any other `\X` as the literal X. Used both outside and
	inside char classes (so `[\40-\41]` and `\n` both compile). *)
ccOctalDigit = ParseCharacter[CharacterRange["0", "7"]]

ccOctalEscapeChar = ParseAction[
	ParseLiteral["\\"] ~~ ccOctalDigit ~~ ParseMany[ccOctalDigit],
	FromCharacterCode[ToExpression["8^^" <> #2 <> StringJoin[#3]]] &
]

ccNamedEscapeChar = ParseAction[
	ParseLiteral["\\"] ~~ ParseCharacter[_],
	Replace[#2, {"n" -> "\n", "r" -> "\r", "t" -> "\t"}] &
]

(* a "char-class char": one resolved character.  Used as the endpoint
	of a range `c-c` and as a standalone item.

	Inside `[...]`, regex metas like `|`, `*`, `+`, `?`, `(`, `)`, `<`,
	`{`, `.`, `$` lose their meta meaning - the class-terminator `]`,
	the escape introducer `\`, and the range delimiter `-` are the only
	chars that retain syntactic role. `^` is meta only at the *start*
	of the class (handled at `regexCharClass`); inside an item it's a
	literal `^`. So a per-class-context "not meta" parser is strictly
	more permissive than the outside-class form, which lets `[|]`,
	`[*]`, `[+-]`, etc. compile to one-char alternatives. *)
ccCharNotMeta = ParseCharacter[_ ? (# =!= "]" && # =!= "\\" && # =!= "-" &)]

ccChar = ParseChoice[
	ccOctalEscapeChar,
	ccNamedEscapeChar,
	ccCharNotMeta
]

regexCharClassRangeItem = ParseAction[
	ccChar ~~ ParseLiteral["-"] ~~ ccChar,
	CharacterRange[#1, #3] &
]

regexCharClassItem = ParseChoice[regexCharClassRangeItem, ccChar]

(* char class with optional leading `^` for negation - `[^x]` becomes
	`ParseCharacter[_?(! StringMatchQ[#, x] &)]` so it matches anything
	*except* the listed set.

	Range items resolve to a List of chars via CharacterRange; single
	items are bare strings. Flatten[parts] coalesces both shapes into
	one flat char list, which Apply[Alternatives, ...] turns into the
	one-of pattern the ParseCharacter wants. *)
regexCharClass = ParseAction[
	ParseLiteral["["] ~~ ParseOptional[ParseLiteral["^"]] ~~
		ParseSome[regexCharClassItem] ~~ ParseLiteral["]"],
	With[{
		neg = ! MissingQ[#2],
		chars = Flatten[#3]
	},
		With[{pat = If[Length[chars] === 1, chars[[1]], Apply[Alternatives, chars]]},
			If[ neg,
				ParseCharacter[_?(! StringMatchQ[#, pat] &)],
				ParseCharacter[pat]
			]
		]
	] &
]

(* Outside a char class: bare `.` is the regex any-char metacharacter
	(so `<printable_char> ::: .` matches any single char); a backslash
	escape resolves the same way the char-class form does; everything
	else is a one-character literal. *)
regexDot = ParseAction[ParseLiteral["."], ParseCharacter[_] &]

regexEscape = ParseAction[
	ccOctalEscapeChar | ccNamedEscapeChar,
	ParseLiteral[#] &
]

regexLiteralChar = ParseAction[regexCharNotMeta, ParseLiteral[#] &]

regexRefName = ParseAction[
	ParseCharacter[LetterCharacter | "_"] ~~
		ParseMany[ParseCharacter[LetterCharacter | DigitCharacter | "_"]],
	StringJoin[#1, StringJoin @ #2] &
]

regexNonTermRef = ParseAction[
	(ParseLiteral["<"] ~~ regexRefName ~~ ParseLiteral[">"]) |
		(ParseLiteral["{"] ~~ regexRefName ~~ ParseLiteral["}"]),
	regexLookupRef[#2] &
]

(* Forward reference for the recursive parenthesised group. *)
regexParenGroup = ParseAction[
	ParseLiteral["("] ~~ ParseRecursive[regexBodyRef] ~~ ParseLiteral[")"],
	#2 &
]

regexAtom = ParseChoice[
	regexCharClass,
	regexParenGroup,
	regexNonTermRef,
	regexEscape,
	regexDot,
	regexLiteralChar
]

(* atom followed by optional postfix *, +, ? - returns the wrapped
	ParserCombinator joined back into a string-yielding parser. *)
regexEltWithPostfix = ParseAction[
	regexAtom ~~ ParseOptional[ParseCharacter["*" | "+" | "?"]],
	Switch[#2,
		"*",
			ParseAction[ParseMany[#1], StringJoin @ {##} &],
		"+",
			ParseAction[ParseSome[#1], StringJoin @ {##} &],
		"?",
			ParseAction[ParseOptional[#1], If[MissingQ[#], "", #] &],
		_,
			#1
	] &
]

(* A sequence of elements with no separator; the result is a parser
	that concatenates the per-element matches into one string. The
	empty case is ParseSucceed[""] (matches the empty string). *)
regexSeq = ParseAction[
	ParseMany[regexEltWithPostfix],
	With[{elts = {##}},
		Switch[Length[elts],
			0,
				ParseSucceed[""],
			1,
				elts[[1]],
			_,
				ParseAction[ParseSequence @@ elts, StringJoin @ {##} &]
		]
	] &
]

regexBody = ParseAction[
	ParseSepBy1[regexSeq, ParseLiteral["|"]],
	With[{alts = {##}},
		If[Length[alts] === 1, alts[[1]], ParseChoice @@ alts]
	] &
]

regexBodyRef := ParseRecursive[regexBody]

(* compile a `::-` / `:::` rule body to a target parser by running the
	regex meta-grammar on the reconstructed body string. The Parse call
	has to run inside the Block (not in its init list), because Block's
	init RHSs evaluate in the OUTER scope - regexSymMap / regexOverrides
	would still hold their outer values when Parse was running. *)
regexCompile[body_String, sm_Association, ov_Association] :=
	Block[{regexSymMap = sm, regexOverrides = ov},
		With[{r = Parse[regexBody, body]},
			If[ FailureQ[r],
				ParseFail["regex body did not compile: " <> body],
				r
			]
		]
	]


(* ::Section:: *)
(*Public entry points*)

(* Parse the BNF source via the combinator grammar above and return the
	raw rule list. Useful for tests and inspection. *)
Options[EBNFRules] = {"Dialect" -> "TPTP"}

EBNFRules[source_String, OptionsPattern[]] :=
	Parse[If[OptionValue["Dialect"] === "Classic", classicGrammarP, grammarP], source]
EBNFRules[File[path_String], opts : OptionsPattern[]] := EBNFRules[Import[path, "Text"], opts]

EBNFDeclarations[source_String] := With[{rules = EBNFRules[source, "Dialect" -> "Classic"]},
	If[FailureQ[rules], rules, GroupBy[Cases[rules, EBNFDeclaration[keyword_, fields_] :> {keyword, fields}], First -> Last]]
]
EBNFDeclarations[File[path_String]] := EBNFDeclarations[Import[path, "Text"]]

Options[EBNFParse] = {
	"PrimitiveOverrides" -> <||>,
	"Actions" -> <||>,
	"ChoiceMode" -> "Auto",
	"Dialect" -> "TPTP",
	"Whitespace" -> Automatic,
	"Tokens" -> {},
	"Spans" -> {}
}

(* the text a token matched: the characters in its parse tree, in order *)
tokenText[parts___] := StringJoin[Cases[DeleteCases[{parts}, _Missing, Infinity], _String, Infinity]]

(* a rule whose action is also handed the {start, end} character span it matched *)
spanned[parser_, action_] := ParseAction[
	ParsePosition[] ~~ parser ~~ ParsePosition[],
	Function[{start, value, end}, If[ListQ[value], action @@ Append[value, {start, end}], action[value, {start, end}]]]
]

EBNFParse[source_String, OptionsPattern[]] :=
	Block[{rules, structuredGram, tokenGram, overrides, actions, allNames, symMap, parsers, tokens, spans, contiguous,
			$choiceMode = OptionValue["ChoiceMode"], $ebnfSkip = $ebnfSkip, $ebnfSkipChars = None, $ebnfGram = <||>,
			$ebnfTokenText = <||>
	},
		overrides = OptionValue["PrimitiveOverrides"];
		actions   = OptionValue["Actions"];
		tokens    = OptionValue["Tokens"];
		spans     = OptionValue["Spans"];
		If[ OptionValue["Whitespace"] =!= Automatic,
			$ebnfSkipChars = OptionValue["Whitespace"];
			$ebnfSkip = ParseMany[ParseCharacter[$ebnfSkipChars]]
		];
		rules = EBNFRules[source, "Dialect" -> OptionValue["Dialect"]];
		If[ FailureQ[rules],
			Return[rules]
		];
		(* `::=` and `:==` rules carry the structured body; `::-` and
			`:::` rules carry regex-style bodies that the regexCompile
			pass walks character by character.

			When the same name has BOTH a `::=` and a `:==` definition
			(e.g. <fof_plain_atomic_formula>, <formula_role>), prefer
			`::=` - per the TPTP README, `::=` is the syntactic form
			and `:==` adds semantic constraints over the same shape.
			For parsing, the syntactic form is the right tree. *)
		structuredGram = Join[
			Association @ Cases[rules,
				EBNFRule[name_, ":==", body_] :> (name -> body)
			],
			Association @ Cases[rules,
				EBNFRule[name_, "::=" | "::", body_] :> (name -> body)
			]
		];
		tokenGram = Association @ Cases[rules,
			EBNFRule[name_, "::-" | ":::", body_] :> (name -> reconstructBody[body])
		];
		(* Apply direct-left-recursion elimination before lowering, so the
			PEG ordering of the lowered ParseChoice doesn't commit to a
			non-recursive alt and miss the recursive form. *)
		structuredGram = AssociationMap[
			Function[name, rewriteLeftRecursive[name, structuredGram[name]]],
			Keys[structuredGram]
		];
		(* Then sort each rule's alts longest-first so a shared-prefix
			alt pair like `<constant> | <functor>(<fof_arguments>)` tries
			the longer (and more specific) form before the bare prefix. *)
		structuredGram = sortAltsLongestFirst /@ structuredGram;
		$ebnfGram = structuredGram;
		(* a token is matched character by character, and so is every rule it reaches *)
		contiguous = FixedPoint[
			Union[#, Cases[Lookup[structuredGram, #, {}], NonTerm[n_String] :> n, Infinity]] &,
			Intersection[tokens, Keys[structuredGram]]
		];
		allNames = Union[Keys[structuredGram], Keys[tokenGram]];
		(* the rules' symbols live here, not in the caller's $Context *)
		symMap = AssociationMap[Function[Unique["Wolfram`Parser`EBNFPrivate`ebnfRule$"]], allNames];
		$ebnfTokenText = AssociationMap[Function[Unique["Wolfram`Parser`EBNFPrivate`ebnfToken$"]], Intersection[tokens, Keys[structuredGram]]];
		parsers = Association[
			Join[
				KeyValueMap[
					Function[{name, body},
						name -> Block[{$ebnfContiguous = MemberQ[contiguous, name]},
							finishRule[name, lowerBody[body, symMap, overrides], actions, spans]
						]
					],
					structuredGram
				],
				KeyValueMap[
					Function[{name, bodyStr},
						name -> applyAction[
							Quiet @ Check[
								regexCompile[bodyStr, symMap, overrides],
								ParseFail["Could not compile " <> name <> " body: " <> bodyStr]
							],
							actions, name
						]
					],
					tokenGram
				]
			]
		];
		(* Bind each rule's parser to its allocated symbol; the
			ParseRecursive[sym] references resolve at parse time. Use
			Evaluate on the LHS so Set sees the actual Symbol value, not
			the held lookup expression. *)
		KeyValueMap[
			Function[{name, sym}, Set[Evaluate[sym], parsers[name]]],
			symMap
		];
		parsers
	]

(* Wrap a per-rule parser with the user's action function when one is
	provided. The action receives the rule's parsed value via the
	normal ParseAction convention - splatted args when the parser
	yielded a List, a single arg when it yielded a scalar - and returns
	whatever WL shape the user wants. Without an action, the parser
	passes through unchanged. *)
applyAction[parser_, actions_Association, name_String] :=
	If[ KeyExistsQ[actions, name],
		ParseAction[parser, actions[name]],
		parser
	]

(* A token's value is the text it matched, and an AST node its action builds from
	that text carries the token's source span; a rule in "Spans" hands its action
	the span it matched after its values; any other rule takes its action as is. *)
finishRule[name_String, parser_, actions_Association, spans_List] := Which[
	KeyExistsQ[$ebnfTokenText, name],
		With[{sym = $ebnfTokenText[name]},
			Set[sym, ParseAction[parser, tokenText]];
			SpannedToken[ParseRecursive[sym], ParseSucceed[Null], Lookup[actions, name, Identity]]
		],
	MemberQ[spans, name] && KeyExistsQ[actions, name],
		spanned[parser, actions[name]],
	True,
		applyAction[parser, actions, name]
]

EBNFParse[File[path_String], opts : OptionsPattern[]] :=
	EBNFParse[Import[path, "Text"], opts]


(* ::Section:: *)
(*Token rules as regular expressions*)

(* The token rules of a classic grammar, compiled for a reader that takes each as a PEG reads it:
   alternatives in order, the first that matches taken; an option and a repetition taking all
   they can and giving none back; & and ! looking ahead, taking nothing; x - y, x where y does
   not match. A rule's tree is the one Wolfram`Parser`Private`tokenTreeParser takes:
   {"Regex", piece, ...}, a regular expression that matches what that part of the rule matches
   and no more, its pieces strings and {"Class", name}, a class the reader gives; the nodes of
   sequences, choices, options, repetitions and lookaheads; and {"Rule", name} for a rule that
   refers to itself, whose tree "Rules" gives. A regular expression stands for as much of a rule
   as has no lookahead, so that a reader can match it in a window of its input: its choices are
   atomic and its repetitions possessive, as a PEG's; characters that are alternatives next to
   one another are one class, and a class repeated among other alternatives a run of it.
   The classes are the names the grammar leaves undefined: a list of code ranges, a set of
   characters the rules' classes are made of; a string, a regular expression taken as it is; or
   Automatic, a class the reader gives. <|"Tokens" -> <|name -> tree, ...|>, "Rules" ->
   <|name -> tree, ...|>|>, or a Failure. *)
tokenTrees[rules_List, names_List, classes_Association] := Catch[Block[
	{$tokenRules = Association[Cases[rules, EBNFRule[n_String, _, alts_List] :> (n -> alts)]], $tokenClasses = classes, $tokenSelf},
	$tokenSelf = Select[Keys[$tokenRules], MemberQ[reachableTokenRules[{#}, False], #] &];
	<|
		"Tokens" -> AssociationMap[finalTokenTree[ruleBodyTree[#]] &, names],
		"Rules" -> AssociationMap[finalTokenTree[ruleBodyTree[#]] &, Intersection[$tokenSelf, reachableTokenRules[names, True]]]
	|>
], tokenTrees]

tokenFailure[template_String, args___] := Throw[Failure["EBNFToken", <|"MessageTemplate" -> template, "MessageParameters" -> {args}|>], tokenTrees]

(* the rules a rule's body names, and those they name in turn, the rules themselves among them or not *)
reachableTokenRules[names_List, withThem_] := With[{named = Cases[#, NonTerm[n_String] /; KeyExistsQ[$tokenRules, n] && ! KeyExistsQ[$tokenClasses, n] :> n, Infinity] &},
	FixedPoint[Union[#, named[Lookup[$tokenRules, #, {}]]] &, If[withThem, Union[names], Union[named[Lookup[$tokenRules, names, {}]]]]]
]

ruleBodyTree[name_String] := If[ KeyExistsQ[$tokenRules, name], tokenBodyTree[$tokenRules[name]], tokenFailure["No rule or class `1`.", name]]

(* While compiling, a part is tokenClass[ranges], one character of a set of code ranges;
   tokenRegex[pieces], a regular expression; or a tree node of parts. *)
tokenRegexQ[_tokenClass | _tokenRegex] := True
tokenRegexQ[_] := False

tokenPieces[tokenRegex[pieces_List]] := pieces
tokenPieces[tokenClass[ranges_List]] := {classRegexOf[ranges]}

(* a part as the reader's tree: strings next to one another joined *)
finalTokenTree[part_?tokenRegexQ] := Prepend[joinedPieces[tokenPieces[part]], "Regex"]
finalTokenTree[{"Rule", name_String}] := {"Rule", name}
finalTokenTree[{head_String, parts___}] := Prepend[finalTokenTree /@ {parts}, head]
joinedPieces[pieces_List] := Map[If[StringQ[First[#]], StringJoin[#], Splice[#]] &, Split[pieces, StringQ[#1] && StringQ[#2] &]]

tokenEltTree[Lit[s_String]] := If[ StringLength[s] === 1,
	tokenClass[{{First[ToCharacterCode[s]], First[ToCharacterCode[s]]}}],
	tokenRegex[{StringJoin[regexCharacter /@ Characters[s]]}]
]
tokenEltTree[CharRange[a_String, b_String]] := tokenClass[{{First[ToCharacterCode[a]], First[ToCharacterCode[b]]}}]
tokenEltTree[NonTerm[name_String]] := Which[
	KeyExistsQ[$tokenClasses, name], Replace[$tokenClasses[name], {
		ranges : {{_Integer, _Integer} ...} :> tokenClass[ranges],
		r_String :> tokenRegex[{"(?:" <> r <> ")"}],
		Automatic :> tokenRegex[{"(?:", {"Class", name}, ")"}],
		other_ :> tokenFailure["The class `1` is `2`, not code ranges, a regular expression or Automatic.", name, other]
	}],
	MemberQ[$tokenSelf, name], {"Rule", name},
	True, ruleBodyTree[name]
]
tokenEltTree[Opt[alts_List]] := With[{part = tokenBodyTree[alts]},
	If[tokenRegexQ[part], tokenRegex[Join[tokenAtom[part], {"?+"}]], {"Optional", part}]
]
tokenEltTree[Group[alts_List]] := tokenBodyTree[alts]
tokenEltTree[Rep["ManyAlts", alts_List]] := tokenRepetition[tokenBodyTree[alts]]
tokenEltTree[Rep["Many", inner_]] := tokenRepetition[tokenEltTree[inner]]
tokenEltTree[Ahead[elt_]] := {"Ahead", tokenEltTree[elt]}
tokenEltTree[NotAhead[elt_]] := {"NotAhead", tokenEltTree[elt]}
tokenEltTree[ButNot[elt_, exception_]] := With[{part = tokenEltTree[elt], not = tokenEltTree[exception]},
	If[ MatchQ[part, _tokenClass] && MatchQ[not, _tokenClass],
		tokenClass[rangesWithout[First[part], First[not]]],
		{"Sequence", {"NotAhead", not}, part}
	]
]
tokenEltTree[other_] := tokenFailure["A token rule cannot hold `1`.", other]

(* a repetition: of a regular expression, a possessive one; of a choice, each class among its
   alternatives a run of the class *)
tokenRepetition[part_?tokenRegexQ] := tokenRegex[Join[tokenAtom[part], {"*+"}]]
tokenRepetition[{"Choice", alts___}] := {"Many", {"Choice", Sequence @@ Map[If[MatchQ[#, _tokenClass], tokenRegex[Join[tokenPieces[#], {"++"}]], #] &, {alts}]}}
tokenRepetition[part_] := {"Many", part}

(* a part as one atom of a regular expression: a class is one, anything else is grouped *)
tokenAtom[part_tokenClass] := tokenPieces[part]
tokenAtom[part_tokenRegex] := Join[{"(?:"}, tokenPieces[part], {")"}]

(* a sequence: the parts that are regular expressions next to one another one regular expression *)
tokenSeqTree[{}] := tokenRegex[{""}]
tokenSeqTree[elts_List] := With[{parts = joinedRuns[tokenEltTree /@ elts, tokenRegex[Join @@ (tokenPieces /@ #)] &]},
	If[Length[parts] === 1, First[parts], Prepend[parts, "Sequence"]]
]

(* choices: those that are regular expressions next to one another one atomic choice, and of
   those, characters next to one another one class *)
tokenBodyTree[{alt_List}] := tokenSeqTree[alt]
tokenBodyTree[alts_List] := With[{parts = joinedRuns[tokenSeqTree /@ alts, regexChoice]},
	If[Length[parts] === 1, First[parts], Prepend[parts, "Choice"]]
]

regexChoice[parts_List] := With[{classes = joinedClasses[parts]},
	If[ Length[classes] === 1, First[classes], tokenRegex[Join[{"(?>"}, Flatten[Riffle[tokenPieces /@ classes, {{"|"}}], 1], {")"}]]]
]
joinedClasses[parts_List] := Map[
	If[MatchQ[#, {__tokenClass}], tokenClass[Join @@ #[[All, 1]]], Splice[#]] &,
	Split[parts, MatchQ[#1, _tokenClass] && MatchQ[#2, _tokenClass] &]
]

(* runs of parts that are regular expressions, each of two or more made one by join *)
joinedRuns[parts_List, join_] := Map[
	Which[Length[#] === 1, First[#], tokenRegexQ[First[#]], join[#], True, Splice[#]] &,
	Split[parts, tokenRegexQ[#1] && tokenRegexQ[#2] &]
]

(* code ranges merged, and those of a set without those of another *)
mergedRanges[ranges_List] := Fold[
	If[ #1 =!= {} && #2[[1]] <= #1[[-1, 2]] + 1, ReplacePart[#1, {-1, 2} -> Max[#1[[-1, 2]], #2[[2]]]], Append[#1, #2]] &,
	{}, SortBy[ranges, First]
]
rangesWithout[ranges_List, without_List] := Fold[
	Function[{rs, w}, Catenate[Map[Function[r, Select[{{r[[1]], Min[r[[2]], w[[1]] - 1]}, {Max[r[[1]], w[[2]] + 1], r[[2]]}}, #[[1]] <= #[[2]] &]], rs]]],
	mergedRanges[ranges], mergedRanges[without]
]

(* a set of characters as a class, or as the class of those it leaves out, whichever is shorter:
   every character any one, and none a match of nothing *)
$lastCharacterCode = 1114111
classRegexOf[ranges_List] := With[{merged = mergedRanges[ranges]},
	With[{in = classBody[merged], out = classBody[rangesWithout[{{0, $lastCharacterCode}}, merged]]},
		Which[
			merged === {}, "(?!)",
			out === "", "(?s:.)",
			StringLength[out] < StringLength[in], "[^" <> out <> "]",
			True, "[" <> in <> "]"
		]
	]
]
classBody[ranges_List] := StringJoin[Map[If[#[[1]] === #[[2]], classCharacter[#[[1]]], classCharacter[#[[1]]] <> "-" <> classCharacter[#[[2]]]] &, ranges]]
classCharacter[code_Integer] := If[ 32 < code < 127 && ! MemberQ[ToCharacterCode["]\\^-["], code],
	FromCharacterCode[code],
	"\\x{" <> IntegerString[code, 16] <> "}"
]

(* a character of a literal in a regular expression *)
regexCharacter[c_String] := With[{code = First[ToCharacterCode[c]]},
	Which[
		StringMatchQ[c, RegularExpression["[A-Za-z0-9]"]], c,
		32 <= code < 127 && StringContainsQ["\\^$.|?*+()[]{}", c], "\\" <> c,
		32 <= code < 127, c,
		True, "\\x{" <> IntegerString[code, 16] <> "}"
	]
]


End[]
EndPackage[]

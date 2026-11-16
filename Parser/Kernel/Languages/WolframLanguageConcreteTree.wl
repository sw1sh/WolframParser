(* ::Package:: *)

(* :Title: WolframLanguageConcreteTree.wl - the concrete tree of a source, from the reader's tokens and program *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	The concrete tree WolframLanguageConcrete gives, and CodeConcreteParse and CodeParse with it, built
	from the lexer's tokens and the parser's program of WolframLanguageFast.wl in one pass. WolframLanguage.wl
	loads this file at the first concrete tree asked for, so a program that only reads, as a kernel
	starting does, loads none of it. It begins its private context alone and names no package to need:
	the contexts it uses are loaded by then, in a kernel under its own names. *)

Begin["Wolfram`Parser`Languages`WolframLanguage`Private`"]

(* ::Section:: *)
(*The concrete tree of a source the reader reads whole*)

(* The children of the ContainerNode WolframLanguageConcrete gives of a source, built from the
	lexer's tokens and the parser's program in one pass, as the concrete grammar of WolframLanguage.wl
	builds them: each node's operators, brackets and commas the tokens between its operands; the
	whitespace, newlines and comments between two tokens in the smallest node that holds both; and
	the tokens CodeParser makes up, Token`Fake`ImplicitTimes and the others, where the grammar puts
	them. A source the reader does not read whole, one with line continuations or character escapes,
	and one with a form this does not build give None, and the grammar reads them. *)

(* where this does not build a source: the grammar reads it; $fastConcreteWhy says why, for the checks *)
fastFallback[] := fastFallback["unbuilt form"]
fastFallback[why_String] := ($fastConcreteWhy = why; Throw[None, fastConcrete])

fastConcrete::usage = "fastConcrete[s] gives the children of the ContainerNode of the source s as the concrete grammar reads them, built from the reader's tokens and program, or None for a source this does not build."
fastConcrete[s_String] := Catch[
	If[ StringContainsQ[s, "\\"] && readSource[s][[2]] =!= None, fastFallback["line continuation or character escape"]];
	With[{codes = ToCharacterCode[s]},
		With[{padded = paddedCodes[codes]},
			With[{split = splitParse[lexedCodes[padded], padded]},
				If[ parseStatus[Last[split]] =!= 0, fastFallback["the reader stops in it"]];
				concreteBuilt[codes, First[split], programInstructions[Last[split]]]
			]
		]
	],
	fastConcrete
]

(* An item is {node, its first token, its last token, the character after the text it takes}; a token
	CodeParser makes up is {leaf, 0, 0, 0}. A prefix operator's item carries its operand's fifth, so
	that a chain of Plus reads a - b as the - between a and b. *)
concreteBuilt[codes_List, lexed_List, instructions_List] := Block[
	{$cCodes = codes, $cCount = lexed[[2]], $cKinds, $cStarts, $cEnds, $cDepth, $cGaps, $cLast = 0, $cNodes = <||>, $cNodeCount = 0,
	 stack = {}, statements = {}, relations = {}},
	$cKinds = Take[lexed[[3 ;; ;; 5]], $cCount];
	$cStarts = Take[lexed[[5 ;; ;; 5]], $cCount];
	$cEnds = Take[lexed[[6 ;; ;; 5]], $cCount];
	$cDepth = Most[Accumulate[Prepend[Replace[$cKinds, {10 | 12 | 14 | 16 -> 1, 11 | 13 | 15 | 17 -> -1, _ -> 0}, {1}], 0]]];
	(* the trivia between each token and the next, all read at once *)
	$cGaps = gapsLeaves[FromCharacterCode[Table[$cCodes[[$cEnds[[k]] ;; $cStarts[[k + 1]] - 1]], {k, $cCount - 1}]]];
	Scan[
		Function[step, With[{code = step[[1]], a = step[[2]], b = step[[3]]},
			Switch[code,
				1, stack = {{concreteLeafOf[a, b], b, b, $cEnds[[b]]}, stack}; $cLast = Max[$cLast, b],
				25,
					(* a statement after the first that begins with an operator a chain takes: CodeParser
						reads it on, past the newline, as the front end does not *)
					If[ statements =!= {} && $cKinds[[a]] === 9 && KeyExistsQ[$concreteInfixForms, concreteTokenText[a]], fastFallback["statement begins with an infix operator"]];
					statements = {First[stack], statements}; stack = Last[stack],
				6, relations = {a, relations},
				7, stack = concreteStep[7, a, b, stack]; relations = Nest[Last, relations, a - 1],
				_, stack = concreteStep[code, a, b, stack]
			]
		]],
		Partition[instructions, 3]
	];
	resolvedTree[containerChildren[Reverse[linkedItems[statements]]]]
]

(* A node is kept in $cNodes and its item holds concreteRef[its number], so that no step carries a
	subtree whose size grows with the source; the tree is made once, at the end, each node with its
	children made before it. *)
newNode[shell_] := ($cNodeCount++; $cNodes[$cNodeCount] = shell; concreteRef[$cNodeCount])
resolvedTree[e_] := e /. concreteRef[i_Integer] :> resolvedTree[$cNodes[i]]

(* the text of token t and the leaf of an operator, a bracket or a comma *)
concreteTokenText[t_Integer] := FromCharacterCode[$cCodes[[$cStarts[[t]] ;; $cEnds[[t]] - 1]]]
operatorLeafOf[t_Integer] := Switch[$cKinds[[t]],
	9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18, tokenLeaf[concreteTokenText[t]],
	_, fastFallback["operatorLeafOf 1"]
]

(* the leaf of token t, of the leaf kind of the parser's program *)
concreteLeafOf[kind_Integer, t_Integer] := With[{text = concreteTokenText[t]},
	Switch[kind,
		1, concreteLeaf[Symbol, text],
		2, concreteBlank[text],
		3 | 4, concreteLeaf[concreteNumberKind[text], text],
		5 | 8 | 100, concreteLeaf[String, text],
		6, If[StringStartsQ[text, "##"], slotNode["##", missingIfEmpty[StringDrop[text, 2]]], slotNode["#", missingIfEmpty[StringDrop[text, 1]]]],
		7, Which[text === "%", tokenLeaf["%"], StringMatchQ[text, "%" ~~ DigitCharacter ..], outNode["%", StringDrop[text, 1]], True, concreteLeaf[Token`PercentPercent, text]],
		_, fastFallback["concreteLeafOf 1"]
	]
]
missingIfEmpty[""] := Missing[]
missingIfEmpty[s_String] := s

concreteBlank[text_String] := Replace[
	StringCases[text, RegularExpression["^([^_]*)(___|__|_\\.|_)(.*)$"] :> {"$1", "$2", "$3"}],
	{{{name_, underscores_, head_}} :> blankNode[missingIfEmpty[name], underscores, missingIfEmpty[head]], _ :> fastFallback["concreteBlank 1"]}
]

(* The whitespace, newlines and comments of the text between two tokens, each a leaf as the grammar
	makes it: a blank a leaf of each character, a comment with the comments in it one; a character
	no trivia is no source this builds *)
triviaLeaves[from_Integer, to_Integer] := If[from >= to, {}, gapLeaves[$cCodes[[from ;; to - 1]]]]
gapLeaves[gap_List] := Module[{i = 1, n = Length[gap], out = {}, depth, j},
	While[ i <= n,
		Which[
			gap[[i]] === 40 && i < n && gap[[i + 1]] === 42,
				depth = 1; j = i + 2;
				While[ j <= n && depth > 0,
					Which[
						gap[[j]] === 40 && j < n && gap[[j + 1]] === 42, depth++; j += 2,
						gap[[j]] === 42 && j < n && gap[[j + 1]] === 41, depth--; j += 2,
						True, j++
					]
				];
				If[depth > 0, fastFallback["gapLeaves 1"]];
				out = {out, concreteLeaf[Token`Comment, FromCharacterCode[gap[[i ;; j - 1]]]]}; i = j,
			gap[[i]] === 13 && i < n && gap[[i + 1]] === 10, out = {out, concreteLeaf[Token`Newline, "\r\n"]}; i += 2,
			gap[[i]] === 10 || gap[[i]] === 13, out = {out, concreteLeaf[Token`Newline, FromCharacterCode[gap[[i]]]]}; i++,
			gap[[i]] === 32 || gap[[i]] === 9, out = {out, concreteLeaf[Whitespace, FromCharacterCode[gap[[i]]]]}; i++,
			True, fastFallback["gapLeaves 2"]
		]
	];
	Flatten[out]
]

(* The trivia of many gaps at once: one without a comment by the pattern of its characters, each a
	leaf made once; one with a comment by gapLeaves *)
$gapLeafRules := $gapLeafRules = {
	"\r\n" -> concreteLeaf[Token`Newline, "\r\n"], "\n" -> concreteLeaf[Token`Newline, "\n"], "\r" -> concreteLeaf[Token`Newline, "\r"],
	" " -> concreteLeaf[Whitespace, " "], "\t" -> concreteLeaf[Whitespace, "\t"], _ -> $gapUnread
}
gapsLeaves[texts_List] := With[{plain = StringCases[texts, $gapLeafRules]},
	MapThread[
		Which[
			#1 === "", {},
			StringContainsQ[#1, "(*"], gapLeaves[ToCharacterCode[#1]],
			MemberQ[#2, $gapUnread], fastFallback["gapsLeaves 1"],
			True, #2
		] &,
		{texts, plain}
	]
]

(* the trivia between the end of a piece and the start of the next: the gap read before where the two
	are tokens side by side, else read now *)
gapBetween[from_Integer, lastToken_Integer, to_Integer] := If[
	lastToken < $cCount && from === $cEnds[[lastToken]] && to === $cStarts[[lastToken + 1]], $cGaps[[lastToken]], triviaLeaves[from, to]
]

(* the trivia a token CodeParser makes up at the end of a node takes after the token before it: on
	the source's top level the whitespace and comments up to a newline, in brackets all of it *)
trailingTriviaEnd[t_Integer, from_Integer] := With[{to = If[t < $cCount, $cStarts[[t + 1]], Length[$cCodes] + 1]},
	If[ $cDepth[[t]] > 0 || $cKinds[[t]] === 10 || $cKinds[[t]] === 12 || $cKinds[[t]] === 14 || $cKinds[[t]] === 16, to,
		from + Total[StringLength[#[[2]]] & /@ TakeWhile[triviaLeaves[from, to], ! MatchQ[#, CodeParser`LeafNode[Token`Newline, _, _]] &]]
	]
]

(* A node's children from its pieces in order, {"Item", item}, {"Token", t} and {"Fake", leaf}, the
	trivia between two pieces in it: a token made up after the trivia before the piece after it, and
	at the node's end after the trivia it takes. {children, first token, last token, end}. *)
assembledPieces[pieces_List] := Module[{out = {}, pos = None, first = None, last = None, end = None, n = Length[pieces], piece, start},
	Do[
		piece = pieces[[i]];
		Switch[piece[[1]],
			"Item",
				start = $cStarts[[piece[[2, 2]]]];
				If[pos =!= None, out = {out, gapBetween[pos, last, start]}];
				out = {out, piece[[2, 1]]};
				If[first === None, first = piece[[2, 2]]]; last = piece[[2, 3]]; pos = piece[[2, 4]]; end = pos,
			"Token",
				start = $cStarts[[piece[[2]]]];
				If[pos =!= None, out = {out, gapBetween[pos, last, start]}];
				out = {out, operatorLeafOf[piece[[2]]]};
				If[first === None, first = piece[[2]]]; last = piece[[2]]; pos = $cEnds[[piece[[2]]]]; end = pos,
			"Fake",
				If[ pos =!= None,
					With[{to = If[i < n, pieceStart[pieces[[i + 1]]], trailingTriviaEnd[last, pos]]},
						out = {out, triviaLeaves[pos, to]}; pos = to; end = to
					]
				];
				out = {out, piece[[2]]}
		],
		{i, n}
	];
	{Flatten[out], first, last, end}
]
pieceStart[{"Item", item_}] := $cStarts[[item[[2]]]]
pieceStart[{"Token", t_}] := $cStarts[[t]]
pieceStart[{"Fake", _}] := fastFallback["pieceStart 1"]

(* The pieces of a node of the items from its first token to its last, in one pass: the tokens no item
	holds before each item, and a made-up token first of all where it begins the node, else after the
	token the parser read before it *)
piecesOf[items_List, first_Integer, last_Integer] := Module[{t = first, n = Length[items], nextReal},
	Replace[
		Reap[
			Do[
				With[{it = items[[i]]},
					If[ it[[2]] === 0,
						nextReal = SelectFirst[items[[i + 1 ;;]], #[[2]] =!= 0 &, {0, last + 1}][[2]];
						If[i > 1 && t <= last && t < nextReal, Sow[{"Token", t}]; t++];
						Sow[{"Fake", it[[1]]}],
						While[t < it[[2]], Sow[{"Token", t}]; t++];
						Sow[{"Item", it}];
						t = it[[3]] + 1
					]
				],
				{i, n}
			];
			While[t <= last, Sow[{"Token", t}]; t++]
		][[2]],
		{{pieces_List} :> pieces, _ -> {}}
	]
]

(* ::Subsection:: *)
(*The nodes*)

(* the node CodeParser makes of an operator spelled s: {its node's head, its tag}, by the syntax's
	operators and the long names CodeParser reads *)
$concreteInfixForms := $concreteInfixForms = Join[
	AssociationThread[$minusSpellings -> Table[{CodeParser`InfixNode, Plus}, Length[$minusSpellings]]],
	Association @ Catenate @ Map[
		Function[row, Map[# -> {If[row["Form"] === "InfixN", CodeParser`InfixNode, CodeParser`BinaryNode], concreteHead[row]} &, spellings[row["Spelling"]]]],
		Select[$syntaxOperators, MemberQ[{"InfixN", "InfixL", "InfixR", "Optional"}, #["Form"]] && #["Spelling"] =!= "" &]
	],
	Association @ Catenate @ Map[
		Function[r, Map[# -> {Symbol["CodeParser`" <> r[[2]]], Replace[r[[3]], t_String :> Symbol["System`" <> t]]} &, longNameSpellings[r[[1]]]]],
		Select[$longNameTable["Infix"], ! KeyExistsQ[$asciiLongNames, #[[1]]] && #[[3]] =!= CodeParser`Comma &]
	]
]
$concretePrefixTags := $concretePrefixTags = Join[
	Association @ Catenate @ Map[Function[row, Map[# -> concreteHead[row] &, spellings[row["Spelling"]]]], Select[$syntaxOperators, #["Form"] === "Prefix" &]],
	Association @ Catenate @ Map[Function[r, Map[# -> Replace[r[[3]], t_String :> Symbol["System`" <> t]] &, longNameSpellings[r[[1]]]]], Select[$longNameTable["Prefix"], ! KeyExistsQ[$asciiLongNames, #[[1]]] &]]
]
$concretePostfixTags := $concretePostfixTags = Join[
	Association @ Catenate @ Map[Function[row, Map[# -> concreteHead[row] &, spellings[row["Spelling"]]]], Select[$syntaxOperators, #["Form"] === "Postfix" &]],
	Association @ Catenate @ Map[Function[r, Map[# -> Replace[r[[3]], t_String :> Symbol["System`" <> t]] &, longNameSpellings[r[[1]]]]], $longNameTable["Postfix"]]
]

$concreteTagPattern = RegularExpression["[A-Za-z$`][A-Za-z0-9$`]*|\"(?:[^\"\\\\]|\\\\.)*\""]

fakeItem[token_] := {concreteLeaf[token, ""], 0, 0, 0}

(* a node of the items, the tokens between them its operators: its first token the first item's,
	less one for each made-up token before it, and its last the last item's, more one for each after *)
nodeItem[head_, tag_, items_List] := nodeItem[head, tag, items, Identity]
nodeItem[head_, tag_, items_List, withFakes_] := nodeOfPieces[head, tag, withFakes[nodePieces[items]]]
nodeOfPieces[head_, tag_, pieces_List] := Module[{built = assembledPieces[pieces]},
	$cLast = Max[$cLast, built[[3]]];
	{newNode[head[tag, built[[1]], <||>]], built[[2]], built[[3]], built[[4]]}
]
nodePieces[items_List] := Module[{reals = Select[items, #[[2]] =!= 0 &]},
	If[reals === {}, fastFallback["nodePieces 1"]];
	piecesOf[items, First[reals][[2]] - LengthWhile[items, #[[2]] === 0 &], Last[reals][[3]] + LengthWhile[Reverse[items], #[[2]] === 0 &]]
]

(* a chain or a binary operator: its node and tag by its operators' spellings, all of one; a Plus
	reads a - b as - between a and b, the prefix minus the parser made of it undone; a Times without
	an operator between two operands has Token`Fake`ImplicitTimes between them *)
infixItem[items0_List] := Module[{items = items0, pieces, forms},
	items = Prepend[
		Table[
			With[{it = items[[i]]},
				If[ Length[it] >= 5 && it[[5, 1]] === "Prefix" && it[[2]] === items[[i - 1]][[3]] + 1 && MemberQ[$minusSpellings, concreteTokenText[it[[2]]]], it[[5, 2]], it]
			],
			{i, 2, Length[items]}
		],
		First[items]
	];
	pieces = piecesOf[items, First[items][[2]], Last[items][[3]]];
	forms = DeleteDuplicates[Lookup[$concreteInfixForms, Cases[pieces, {"Token", t_} :> concreteTokenText[t]], fastFallback["infixItem 1"]]];
	Which[
		forms === {} || Length[forms] === 1 && forms[[1, 2]] === Times, nodeOfPieces[CodeParser`InfixNode, Times, implicitTimes[pieces]],
		Length[forms] === 1, nodeOfPieces[forms[[1, 1]], forms[[1, 2]], pieces],
		True, fastFallback["infixItem 2"]
	]
]
$minusSpellings = {"-", "\\[Minus]", FromCharacterCode[8722]}

implicitTimes[pieces_List] := Catenate @ MapThread[
	If[#1[[1]] === "Item" && #2[[1]] === "Item", {#1, {"Fake", concreteLeaf[Token`Fake`ImplicitTimes, ""]}}, {#1}] &,
	{pieces, Append[Rest[pieces], {"End"}]}
]

prefixItem[stack_List] := With[{x = First[stack]},
	With[{op = x[[2]] - 1},
		If[op < 1 || $cKinds[[op]] =!= 9, fastFallback["prefixItem 1"]];
		With[{built = assembledPieces[{{"Token", op}, {"Item", x}}]},
			{{newNode[CodeParser`PrefixNode[Lookup[$concretePrefixTags, concreteTokenText[op], fastFallback["prefixItem 2"]], built[[1]], <||>]], op, built[[3]], built[[4]], {"Prefix", x}}, Last[stack]}
		]
	]
]

postfixItem[stack_List] := With[{x = First[stack]},
	With[{op = x[[3]] + 1},
		If[op > $cCount || $cKinds[[op]] =!= 9, fastFallback["postfixItem 1"]];
		$cLast = Max[$cLast, op];
		With[{text = concreteTokenText[op], built = assembledPieces[{{"Item", x}, {"Token", op}}]},
			If[ StringStartsQ[text, "="] && StringEndsQ[text, "."],
				(* =., the = and the . its leaves, trivia between *)
				{{newNode[CodeParser`BinaryNode[Unset, Join[Most[built[[1]]], {tokenLeaf["="]}, gapLeaves[ToCharacterCode[StringTake[text, {2, -2}]]], {tokenLeaf["."]}], <||>]], x[[2]], op, $cEnds[[op]]}, Last[stack]},
				{{newNode[CodeParser`PostfixNode[Lookup[$concretePostfixTags, text, fastFallback["postfixItem 2"]], built[[1]], <||>]], x[[2]], op, $cEnds[[op]]}, Last[stack]}
			]
		]
	]
]

derivativeItem[n_Integer, stack_List] := With[{x = First[stack]},
	With[{primes = x[[3]] + 1},
		If[primes > $cCount || $cKinds[[primes]] =!= 19 || $cEnds[[x[[3]]]] =!= $cStarts[[primes]], fastFallback["derivativeItem 1"]];
		$cLast = Max[$cLast, primes];
		{{newNode[Nest[CodeParser`PostfixNode[Derivative, {#, concreteLeaf[Token`SingleQuote, "'"]}, <||>] &, x[[1]], n]], x[[2]], primes, $cEnds[[primes]]}, Last[stack]}
	]
]

(* f[a, b]: the call's group, its arguments in a Comma node where there are two or more *)
callItem[items_List] := With[{h = First[items], args = Rest[items]},
	With[{open = h[[3]] + 1, close = If[args === {}, h[[3]] + 2, Last[args][[3]] + 1]},
		If[close > $cCount || $cKinds[[open]] =!= 12 || $cKinds[[close]] =!= 13, fastFallback["callItem 1"]];
		With[{group = groupNodeItem[CodeParser`GroupSquare, open, args, close]},
			{newNode[CodeParser`CallNode[Join[{h[[1]]}, triviaLeaves[h[[4]], $cStarts[[open]]]], group[[1]], <||>]], h[[2]], close, $cEnds[[close]]}
		]
	]
]

(* f[[a]]: a call of a square group of a square group *)
partItem[items_List] := With[{h = First[items], args = Rest[items]},
	With[{outer = h[[3]] + 1, inner = h[[3]] + 2, innerClose = Last[args][[3]] + 1},
		If[innerClose + 1 > $cCount || $cKinds[[outer]] =!= 12 || $cKinds[[inner]] =!= 12 || $cKinds[[innerClose]] =!= 13 || $cKinds[[innerClose + 1]] =!= 13,
			fastFallback["partItem 1"]];
		With[{group = groupNodeItem[CodeParser`GroupSquare, outer, {groupNodeItem[CodeParser`GroupSquare, inner, args, innerClose]}, innerClose + 1]},
			{newNode[CodeParser`CallNode[Join[{h[[1]]}, triviaLeaves[h[[4]], $cStarts[[outer]]]], group[[1]], <||>]], h[[2]], innerClose + 1, $cEnds[[innerClose + 1]]}
		]
	]
]

(* a group of expressions between commas, one left out among them, is an error CodeParser marks: the
	grammar reads it *)
groupNodeItem[tag_, open_Integer, items_List, close_Integer] /; MemberQ[items[[All, 2]], 0] := fastFallback["groupNodeItem 1"]
groupNodeItem[tag_, open_Integer, items_List, close_Integer] := With[
	{built = assembledPieces[Join[{{"Token", open}}, If[Length[items] > 1, {{"Item", nodeItem[CodeParser`InfixNode, CodeParser`Comma, items]}}, {"Item", #} & /@ items], {{"Token", close}}]]},
	$cLast = Max[$cLast, close];
	{newNode[CodeParser`GroupNode[tag, built[[1]], <||>]], open, close, $cEnds[[close]]}
]

$groupKinds = <|"List" -> {List, 14, 15}, "Association" -> {Association, 16, 17}, "Paren" -> {CodeParser`GroupParen, 10, 11}|>
groupKindOf[a_Integer] := Which[
	a === $fastParenHead, $groupKinds["Paren"],
	KeyExistsQ[$groupKinds, $fastHeadNames[[a]]], $groupKinds[$fastHeadNames[[a]]],
	True, fastFallback["groupKindOf 1"]
]

concreteGroupItem[a_Integer, items_List] := With[{kind = groupKindOf[a]},
	With[{open = First[items][[2]] - 1, close = Last[items][[3]] + 1},
		If[open < 1 || close > $cCount || $cKinds[[open]] =!= kind[[2]] || $cKinds[[close]] =!= kind[[3]], fastFallback["concreteGroupItem 1"]];
		groupNodeItem[kind[[1]], open, items, close]
	]
]

(* {}: its opener the first token of its kind after all read so far that its closer follows; an
	opener the empty group is inside, as in {{}, a}, comes before it unread *)
emptyGroupItem[a_Integer] := With[{kind = groupKindOf[a]},
	With[{open = SelectFirst[Range[$cLast + 1, $cCount - 1], $cKinds[[#]] === kind[[2]] && $cKinds[[# + 1]] === kind[[3]] &, fastFallback["emptyGroupItem 1"]]},
		groupNodeItem[kind[[1]], open, {}, open + 1]
	]
]

(* t::[a, ...]: a call of a type-specifier group, whose opener is the one leaf "::[", as CodeParser
	reads it, whether the lexer read it as one token or as "::" and "[" side by side *)
typeSpecifierItem[items_List] := With[{h = First[items], args = Rest[items]},
	With[{colons = h[[3]] + 1},
		With[{bracket = If[colons <= $cCount && concreteTokenText[colons] === "::[", colons, colons + 1]},
			If[ bracket > $cCount || bracket > colons && (concreteTokenText[colons] =!= "::" || concreteTokenText[bracket] =!= "[" || $cEnds[[colons]] =!= $cStarts[[bracket]]),
				fastFallback["typeSpecifierItem 1"]];
			With[{close = If[args === {}, bracket + 1, Last[args][[3]] + 1]},
				If[close > $cCount || $cKinds[[close]] =!= 13 || MemberQ[args[[All, 2]], 0], fastFallback["typeSpecifierItem 2"]];
				With[{built = assembledPieces[Join[{{"Token", bracket}}, If[Length[args] > 1, {{"Item", nodeItem[CodeParser`InfixNode, CodeParser`Comma, args]}}, {"Item", #} & /@ args], {{"Token", close}}]]},
					$cLast = Max[$cLast, close];
					{
						newNode[CodeParser`CallNode[
							Join[{h[[1]]}, triviaLeaves[h[[4]], $cStarts[[colons]]]],
							newNode[CodeParser`GroupNode[CodeParser`GroupTypeSpecifier, Prepend[Rest[built[[1]]], CodeParser`LeafNode[Token`ColonColonOpenSquare, "::[", <||>]], <||>]],
							<||>
						]],
						h[[2]], close, $cEnds[[close]]
					}
				]
			]
		]
	]
]

concreteStep[code_Integer, a_Integer, b_Integer, stack_List] := Switch[code,
	2, prefixItem[stack],
	3, postfixItem[stack],
	4 | 21, With[{t = linkedTop[stack, 2]}, {infixItem[t[[1]]], t[[2]]}],
	5, With[{t = linkedTop[stack, b]}, {infixItem[t[[1]]], t[[2]]}],
	7, With[{t = linkedTop[stack, a]}, {infixItem[t[[1]]], t[[2]]}],
	23, With[{t = linkedTop[stack, 2]}, {nodeItem[CodeParser`BinaryNode, Pattern, t[[1]]], t[[2]]}],
	8, With[{t = linkedTop[stack, a + 1]}, {callItem[t[[1]]], t[[2]]}],
	9, If[ b === 0, {emptyGroupItem[a], stack}, With[{t = linkedTop[stack, b]}, {concreteGroupItem[a, t[[1]]], t[[2]]}]],
	10, With[{t = linkedTop[stack, a + 1]}, {partItem[t[[1]]], t[[2]]}],
	11, {fakeItem[Token`Fake`ImplicitNull], stack},
	12, {fakeItem[Token`Fake`ImplicitAll], stack},
	13, {fakeItem[Token`Fake`ImplicitOne], stack},
	15, With[{t = linkedTop[stack, a + 1]}, {typeSpecifierItem[t[[1]]], t[[2]]}],
	14, With[{t = linkedTop[stack, a]},
		(* a::b, each tag a name or a whole string, as CodeParser's; any other the grammar reads *)
		If[ ! AllTrue[Rest[t[[1]]], #[[2]] > 0 && StringMatchQ[concreteTokenText[#[[2]]], $concreteTagPattern] &], fastFallback["concreteStep 1"]];
		{nodeItem[CodeParser`InfixNode, MessageName, t[[1]]], t[[2]]}
	],
	16, derivativeItem[a, stack],
	17, With[{t = linkedTop[stack, 3]}, {nodeItem[CodeParser`TernaryNode, CodeParser`TernaryTilde, t[[1]]], t[[2]]}],
	18, With[{t = linkedTop[stack, a]}, {nodeItem[If[a === 2, CodeParser`BinaryNode, CodeParser`TernaryNode], Span, t[[1]]], t[[2]]}],
	19, With[{t = linkedTop[stack, a]}, {nodeItem[CodeParser`InfixNode, CompoundExpression, t[[1]]], t[[2]]}],
	20, If[ a === 1 || a === 0,
		With[{t = linkedTop[stack, 3]}, {nodeItem[CodeParser`TernaryNode, If[a === 1, TagSetDelayed, TagSet], t[[1]]], t[[2]]}],
		fastFallback["concreteStep 2"]
	],
	22, With[{x = First[stack]},
		If[x[[2]] < 2 || $cKinds[[x[[2]] - 1]] =!= 9, fastFallback["concreteStep 3"]];
		With[{built = assembledPieces[{{"Token", x[[2]] - 1}, {"Item", x}}]},
			{{newNode[CodeParser`PrefixNode[Get, built[[1]], <||>]], x[[2]] - 1, built[[3]], built[[4]]}, Last[stack]}
		]
	],
	_, fastFallback["program code " <> IntegerString[code]]
]

(* the source's statements and the trivia before, between and after them *)
containerChildren[items_List] := Module[{pos = 1, last = 0, out = {}},
	Scan[(out = {out, If[last === 0, triviaLeaves[pos, $cStarts[[#[[2]]]]], gapBetween[pos, last, $cStarts[[#[[2]]]]]], #[[1]]}; pos = #[[4]]; last = #[[3]]) &, items];
	Flatten[{out, triviaLeaves[pos, Length[$cCodes] + 1]}]
]

End[]

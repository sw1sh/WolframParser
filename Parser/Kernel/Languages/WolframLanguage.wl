(* ::Package:: *)

(* :Title: WolframLanguage.wl - the Wolfram Language, read by a grammar of its own *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	InputForm Wolfram Language - the text of a .wl or .m package - in one
	grammar over an algebra, run two ways:

		WolframLanguageAST["f[x_] := x^2"]  -> standard AST (CallNode/InfixNode/BinaryNode/LeafNode ...)
		WolframLanguageHeld["f[x_] := x^2"] -> {HoldComplete[f[x_] := x^2]}

	WolframLanguageHeld gives what ImportString[code, {"WL", "HeldExpressions"}]
	gives: each top-level expression, held. Outside brackets a newline ends an
	expression wherever the expression could end; comments are whitespace.

	The binding powers are CodeParser's published precedences
	(Resources/Generated/Precedence.wl of the CodeParser paclet, MIT); the
	levels of the ParseOperatorTable are generated from them. Flat operators
	(a + b - c, a < b <= c, a.b.c) are its "InfixN" chains and a ~f~ b its
	"Ternary". The forms whose operands are optional or are not expressions
	(a ;; b, a; b;, t /: lhs = rhs, a::tag, x >> file) are postfix operators
	whose own parser reads those operands from tables of the tighter levels.

		WolframLanguageConcrete["f[x_] := x^2"] -> the concrete syntax tree
			CodeParser`CodeConcreteParse gives, in CodeParser's own nodes

	The concrete tree keeps every character, so it has a parser of its own,
	built of the same tokens and precedences: each value it reads carries the
	trivia after it, which the node around it takes, and its node builders
	are CodeParser's.
*)

BeginPackage["Wolfram`Parser`Languages`WolframLanguage`", {"Wolfram`Parser`"}]

WolframLanguageAST::usage      = "WolframLanguageAST[\"code\"] parses Wolfram Language source to a standard AST: a ContainerNode of its top-level expressions, of CallNode / InfixNode / BinaryNode / PrefixNode / PostfixNode / TernaryNode / GroupNode / LeafNode, each operator named by the head it stands for (\"Plus\", \"SetDelayed\", ...)."
WolframLanguageHeld::usage     = "WolframLanguageHeld[\"code\"] parses Wolfram Language source to the list of its top-level expressions, each in HoldComplete, as ImportString[code, {\"WL\", \"HeldExpressions\"}] gives them."
WolframLanguageHeldNext::usage = "WolframLanguageHeldNext[\"code\", pos] reads the statement of code whose line begins at pos, 1 or the position the call before gave, as the kernel's ToExpression reads its statements one at a time: {HoldComplete[statement], next, <|\"Warnings\" -> warnings|>}, next where the line of the next one begins, warnings the syntax warnings the kernel gives as it reads the statement, the names of the statement made only now; HoldComplete[Null] for a line end with no statement before it; {Failure[...], pos} where the statement cannot be read, its warnings under its \"Warnings\" key; EndOfFile past the last."
WolframLanguageProgram::usage  = "WolframLanguageProgram[\"code\"] gives the program the compiled reader makes of code, where code reads whole with no line continuation and no syntax warning: {codes, prog, parts}, the character codes of code, the instructions of all its statements, {status, n, then n instructions of three integers}, and {0, leaves, rows, then each leaf's kind, its mark, its first character and the character after its last, then a row for each part WolframLanguageHeldNext reads of code, {first instruction, last, first leaf, last} for a statement and {0, 0, 0, 0} for a Null}, packed arrays of integers; None for any other code."
WolframLanguageSyntaxQ::usage  = "WolframLanguageSyntaxQ[\"code\"] gives True where code is Wolfram Language source the kernel's reader reads without a syntax error, as SyntaxQ does, and False where it does not, by the lexer and the parser alone: no expression is built and no name made, but for a statement only the grammar reads."
WolframLanguageSyntaxLength::usage = "WolframLanguageSyntaxLength[\"code\"] gives the number of characters from the start of code that read as Wolfram Language, as SyntaxLength does: the length of code where it all reads, the characters before the place where reading stops, and a number past the length of code where code ends before its expression does, by the lexer and the parser alone."
WolframLanguageGrammar::usage  = "WolframLanguageGrammar[alg] builds the Wolfram Language parser over the algebra alg, an Association with the keys of ASTAlgebra; the parser gives the list of the top-level expressions."
WolframLanguageConcrete::usage = "WolframLanguageConcrete[\"code\"] parses Wolfram Language source to its concrete syntax tree, as CodeParser`CodeConcreteParse gives it: a ContainerNode of the top-level expressions and the whitespace, newlines and comments around them, in CodeParser's own nodes, every character of the source in a leaf. Source that is not Wolfram Language reads as CodeParser reads it, into its error nodes: nothing fails."
LinearBoxes::usage             = "LinearBoxes[boxes] stands for the linear syntax \\!\\(...\\) in what WolframLanguageHeld and WolframLanguageHeldNext read, boxes the boxes of its \\(...\\), where the kernel's reader gives MakeExpression[boxes, StandardForm]."
WolframLanguageSemantic::usage = "WolframLanguageSemantic is the algebra that builds each expression held: its builders give <|\"Expr\" -> HoldComplete[expr], \"Literal\" -> .., \"Chain\" -> ..|>, the flags telling a number literal and a product, into which a minus folds."

Begin["`Private`"]

(* ::Section:: *)
(*Precedence: CodeParser's published table*)

(* The value CodeParser's Resources/Generated/Precedence.wl gives each
	operator this grammar reads, under the name it has there. A higher
	value binds more tightly. *)
$codeParserPrecedence = <|
	"ColonColon" -> 184, "Infix`Question" -> 178, "Call" -> 176, "Postfix`PlusPlus" -> 174,
	"Prefix`PlusPlus" -> 172, "AtStar" -> 170, "SlashStar" -> 168, "At" -> 165, "Tilde" -> 162,
	"SlashAt" -> 161, "Postfix`Bang" -> 158, "SingleQuote" -> 154, "LessGreater" -> 152, "Caret" -> 151,
	"StarStar" -> 132, "Dot" -> 126, "Prefix`Minus" -> 124, "Slash" -> 122, "Star" -> 108,
	"Infix`Plus" -> 86, "SemiSemi" -> 80, "LongName`DirectedEdge" -> 79, "Class`Inequality" -> 76,
	"EqualEqualEqual" -> 70, "Class`SetRelations" -> 68, "Prefix`Bang" -> 64, "AmpAmp" -> 62,
	"BarBar" -> 58, "DotDot" -> 44, "Bar" -> 42, "Fake`PatternColon" -> 40, "Fake`OptionalColon" -> 38,
	"TildeTilde" -> 36, "SlashSemi" -> 34, "LessMinusGreater" -> 33, "MinusGreater" -> 31,
	"SlashDot" -> 28, "PlusEqual" -> 27, "Amp" -> 24, "SlashSlashEqual" -> 21, "SlashSlash" -> 18, "SlashColon" -> 11,
	"Equal" -> 9, "GreaterGreater" -> 6, "Semi" -> 4
|>

(* specs: {{precedence name, operator spec}, ...}; the levels of those
	binding more tightly than min, tightest first, in the order given *)
levelsAbove[specs_List, min_Integer] :=
	Map[Last, SortBy[
		GatherBy[Select[specs, precedenceValue[First[#]] > min &], precedenceValue[First[#]] &],
		-precedenceValue[#[[1, 1]]] &], {2}]

(* a precedence given by its name in CodeParser's table, or as its value *)
precedenceValue[name_String] := $codeParserPrecedence[name]
precedenceValue[value_Integer] := value

(* ::Section:: *)
(*Tokens*)

(* Every operator spelt in ASCII. An operator token is the longest one
	there: - is not read where ->, -- or -= is. *)
$operatorSpellings = {
	">>>", "===", "=!=", "//@", "//.", "//=", "@@@", "^:=", "...", "|->", "<->", "->", ":>", ":=", "^=", "/:",
	"=.", "==", "!=", "<=", ">=", "&&", "||", "<>", "/@", "@@", "@*", "/*", "//", "/.", "/;", "..", "::",
	"++", "--", "+=", "-=", "*=", "/=", ";;", "~~", "**", "!!", "<<", ">>", "<|", "|>", "+", "-", "*",
	"/", "^", "=", "<", ">", "!", "&", "@", "?", ":", ";", ".", "'", "~", "|"
}

(* The operators also written as a long name or as its character. *)
$longNameOperators = <|
	"->" -> {"\\[Rule]", "\:f522"}, ":>" -> {"\\[RuleDelayed]", "\:f51f"}, "*" -> {"\\[Times]", "\:00d7"},
	"==" -> {"\\[Equal]", "\:f431", "\\[LongEqual]", "\:f7d9"}, "!=" -> {"\\[NotEqual]", "\:2260"},
	"<=" -> {"\\[LessEqual]", "\:2264"}, ">=" -> {"\\[GreaterEqual]", "\:2265"}, "&&" -> {"\\[And]", "\:2227"},
	"||" -> {"\\[Or]", "\:2228"}, "!" -> {"\\[Not]", "\:00ac"}, "|->" -> {"\\[Function]", "\:f4a1"},
	"<->" -> {"\\[TwoWayRule]", "\:f120"}, "DirectedEdge" -> {"\\[DirectedEdge]", "\:f3d5"},
	"UndirectedEdge" -> {"\\[UndirectedEdge]", "\:f3d4"}, "Element" -> {"\\[Element]", "\:2208"}
|>

$operatorLongNames  = Select[Flatten[Values[$longNameOperators]], StringStartsQ[#, "\\["] &]
$operatorCharacters = Select[Flatten[Values[$longNameOperators]], StringLength[#] === 1 &]

(* one spelling of an operator, not followed by what would make it a longer
	one of all; one of those cutQ gives True for is none right before a [. The
	held grammar's cut, as a notebook reads it, is an operator that ends in =,
	but //= and ^:=: the = and the [ begin free-form input. CodeParser has no
	free-form input, so the concrete grammar cuts none. *)
longest[s_String] := longest[s, $operatorSpellings, freeformCutQ]
longest[s_String, all_List] := longest[s, all, False &]
longest[s_String, all_List, cutQ_] := With[{more = Select[all, StringStartsQ[#, s] && # =!= s &]},
	If[ more === {} && ! cutQ[s],
		ParseLiteral[s],
		ParseAction[ParseLiteral[s] ~~ ParseNotFollowedBy[ParseChoice @@ Join[
			If[cutQ[s], {ParseLiteral["["]}, {}],
			Map[If[ cutQ[#],
				ParseLiteral[StringDrop[#, StringLength[s]]] ~~ ParseNotFollowedBy[ParseLiteral["["]],
				ParseLiteral[StringDrop[#, StringLength[s]]]] &, more]]], s &]
	]]

freeformCutQ[s_String] := StringEndsQ[s, "="] && ! MemberQ[{"//=", "^:="}, s]

spellings[op_String] := Prepend[Lookup[$longNameOperators, op, {}], op]

(* a parser's pieces joined into the text it read *)
text[p_] := ParseAction[p, Function[StringJoin[Cases[Flatten[{##}], _String]]]]

nameCharacterQ[c_String] := First[ToCharacterCode[c]] > 127 && ! MemberQ[$operatorCharacters, c] && ! StringMatchQ[c, WhitespaceCharacter]

(* a letter past ASCII: a long name that is a letter of the language, or
	a character past ASCII that is no operator's, bracket's or
	whitespace's *)
$letter = ParseChoice[
	ParseAction[ParseLookahead[ParseLiteral["\\["]] ~~ ParseCondition[ParseRegex["\\\\\\[[A-Za-z0-9]+]"], letterNameQ], #2 &],
	ParseCharacter[_?concreteNameCharacterQ]]

(* a name: letters, digits, $ and ` context marks; not beginning with a
	digit. The loop after the first run of ASCII is entered only at a
	letter past ASCII. *)
$name = ParseCondition[text[ParseChoice[ParseRegex["[A-Za-z$`][A-Za-z0-9$`]*"], $letter] ~~
	ParseMany[ParseAction[ParseLookahead[ParseCharacter[_?nameContinuesQ]] ~~ ParseChoice[ParseRegex["[A-Za-z0-9$`]+"], $letter], #2 &]]], contextMarksQ]

(* a name's context marks, as the reader's lexer takes them: none at its end, none before another or
	before a digit *)
contextMarksQ[s_String] := ! StringEndsQ[s, "`"] && StringFreeQ[s, "``" | ("`" ~~ DigitCharacter)]

nameContinuesQ[c_String] := c === "\\" || First[ToCharacterCode[c]] > 127 || StringMatchQ[c, LetterCharacter | DigitCharacter | "$" | "`"]

$digits = ParseRegex["[0-9]+"]

(* 12, 1.5, .5, 1. (not before another .), 16^^ff.8, 16^^.8, 1.5`20, 1``10, 2*^-3; a base no
	number has, or a digit its base has not, is none *)
$number = ParseCondition[text[
	ParseChoice[
		$digits ~~ ParseOptional[ParseChoice[
			ParseLiteral["^^"] ~~ ParseRegex["[0-9a-zA-Z]+(\\.(?!\\.)[0-9a-zA-Z]*)?|\\.[0-9a-zA-Z]+"],
			ParseLiteral["."] ~~ ParseNotFollowedBy[ParseLiteral["."]] ~~ ParseOptional[$digits]]],
		ParseLiteral["."] ~~ $digits]
	~~ ParseOptional[ParseLiteral["`"] ~~ ParseOptional[ParseLiteral["`"]] ~~ ParseOptional[ParseRegex["[-+]?([0-9]+\\.?[0-9]*|\\.[0-9]+)"]]]
	~~ ParseOptional[ParseLiteral["*^"] ~~ ParseRegex["[-+]?[0-9]+"]]], baseDigitsQ]

(* whether the file after >> closes its brackets, as a notebook reads x >> b[c: a string's are its
	characters *)
closedBracketsQ[s_String] := StringStartsQ[s, "\""] || StringCount[s, "["] <= StringCount[s, "]"]

(* whether a number's text has a base of 2 to 36, if any, and only digits of its base after it *)
baseDigitsQ[s_String] := StringFreeQ[s, "^^"] || With[{parts = StringSplit[s, "^^", 2]},
	With[{base = FromDigits[parts[[1]]], digits = ToLowerCase[First[StringCases[parts[[2]], StartOfString ~~ d : RegularExpression["[0-9a-zA-Z.]*"] :> d], ""]]},
		2 <= base <= 36 && AllTrue[ToCharacterCode[StringDelete[digits, "."]], If[# <= 57, # - 48, # - 87] < base &]]]

numberKind[s_String] := If[StringFreeQ[s, "." | "`"], "Integer", "Real"]

(* runs of plain characters, then any escaped one *)
$string = text[ParseLiteral["\""] ~~ ParseMany[ParseChoice[
	ParseRegex["[^\"\\\\]+"],
	ParseLiteral["\\"] ~~ ParseCharacter[_]]] ~~ ParseLiteral["\""]]

(* _, __, ___, then an optional head, or after a single _ a .: after __ or ___ a . is a token of
	its own, a Dot or the start of a number *)
$blank = text[ParseChoice[
	ParseLiteral["___"] ~~ ParseOptional[$name],
	ParseLiteral["__"] ~~ ParseOptional[$name],
	ParseLiteral["_"] ~~ ParseOptional[ParseChoice[ParseLiteral["."], $name]]]]

$slot = ParseAction[ParseLookahead[ParseLiteral["#"]] ~~ ParseChoice[text[ParseLiteral["#"] ~~ $string], ParseRegex["##[0-9]*|#([0-9]+|[A-Za-z$`][A-Za-z0-9$`]*)?"]], #2 &]

(* what a ? or ?? asks about: words of letters, digits and the * and @
	of a name pattern, the spaces and tabs between them too *)
$informationWord = text[ParseSome[ParseChoice[ParseRegex["[A-Za-z0-9$`*@]+"], $letter]]]
$informationName = text[$informationWord ~~ ParseMany[ParseRegex["[ \t]+"] ~~ $informationWord]]

$out = ParseAction[ParseLookahead[ParseLiteral["%"]] ~~ ParseRegex["%+[0-9]*"], #2 &]

(* free-form input, as a notebook reads it: =[ and its text to the first ], the ] of a \[Name]
	too, the text on one line after any blank ones *)
$freeform = ParseRegex["=\\[[ \\t\\r\\n]*[^\\]\\r\\n]*(?:[\\r\\n][ \\t\\r\\n]*)?\\]"]

(* the file of << and >>: a string, or the characters of a path or a
	context, a letter past ASCII and a \ among them, \[Name] one
	character; and one whose \[ is not closed *)
$fileCharacters = "(?:[A-Za-z0-9$`_./~:!*?-]|(?![\\x00-\\x7F])\\p{L}|\\\\\\[[A-Za-z0-9]+\\]|\\\\(?!\\[))"
(* a bracket in a file's name to its ], brackets nested, or to the end of the source, as a notebook
	reads it *)
$fileBracket = "(\\[(?:[^\\[\\]]|(?-1))*(?:\\]|\\z))"
$file = ParseChoice[$string, ParseRegex["(?:" <> $fileCharacters <> "|" <> $fileBracket <> ")++"]]
$unterminatedFile = ParseRegex[$fileCharacters <> "*\\\\\\[[A-Za-z0-9]*+(?!\\])"]

(* a comment, the comments nested in it too; with escapes a backslash before an opening paren takes
	it, so that it opens none, as a notebook reads it, where CodeParser's opens one *)
commentParser[escapes_ : False] := With[{comment = RecCell[]},
	SetRec[comment, ParseLiteral["(*"] ~~ ParseMany[ParseChoice @@ Join[
		{RecRef[comment]},
		If[TrueQ[escapes], {ParseRegex["[^(*\\\\]+"], ParseRegex["\\\\\\(?"]}, {ParseRegex["[^(*]+"]}],
		{ParseLiteral["("] ~~ ParseNotFollowedBy[ParseLiteral["*"]],
		ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[")"]]}]] ~~ ParseLiteral["*)"]];
	RecRef[comment]]

(* ::Section:: *)
(*The grammar, parameterised over an algebra*)

(* Outside brackets, the whitespace after an operand or a postfix operator
	stops at a newline, which ends the expression if it can end there;
	after an infix or prefix operator, inside brackets and between
	expressions it takes newlines too. *)
WolframLanguageGrammar[alg_] := grammar[alg]["Program"]

(* <|"Program" -> the parser of a whole source, "Statement" -> that of one
	top-level expression and the whitespace after it, "Expression" -> that of
	the expression alone|> *)
grammar[alg_] := Module[{space, wsLine, wsAll, nested, top, statement},
	space = ParseChoice[
		ParseCharacter[" " | "\t" | "\f"],
		ParseLiteral["\\\n"], ParseLiteral["\\\r\n"],
		commentParser[True],
		ParseChoice @@ (ParseLiteral /@ $longWhitespace)];
	wsLine = ParseMany[space];
	wsAll = ParseMany[ParseChoice[ParseCharacter["\n" | "\r"], ParseChoice @@ (ParseLiteral /@ $heldNewlines), space]];
	nested = RecCell[];
	SetRec[nested, expressionParser[alg, wsAll, wsAll, nested]];
	top = expressionParser[alg, wsLine, wsAll, nested];
	statement = ParseAction[top ~~ wsAll, #1 &];
	<|"Program" -> ParseAction[wsAll ~~ ParseMany[statement], #2 &], "Statement" -> statement, "Expression" -> top|>
]

(* The expression parser whose operands and postfix operators are followed
	by the whitespace ws; brackets hold expressions of nested. *)
expressionParser[alg_, ws_, wsAll_, nested_] := Module[
	{after, operator, postfixOperator, leaf, nullLeaf, symbolLeaf, blankLeaf, otherUnits, plainUnit, unit, patternUnit,
	items, comma, call, part, messageName, word, messageOperand, messagePattern, derivative, span, spans, bareSpan, bareSpans, spanStart, compound, tagSet, put,
	binary, prefix, postfix, flat, plus, relation, relationOp, implicit, specs, table, information, dot, setOperator, unset,
	longOperator, longPostfixOperator, longSpecs, longGroups, longCalls, integrals, integrandOperand, divisible,
	patternRight, spanOperand, compoundOperand, tagLeft, tagRight, prefixAhead, prefixedTable, putRight},

	after[p_, w_] := ParseAction[p ~~ w, #1 &];
	operator[op_String] := after[ParseChoice @@ (longest /@ spellings[op]), wsAll];
	postfixOperator[op_String] := after[longest[op], ws];
	leaf[p_, kind_] := SpannedToken[p, ws, alg["Leaf"][kind, #] &];
	nullLeaf[x_Missing] := alg["Leaf"]["Symbol", "Null"];
	nullLeaf[x_] := x;

	(* --- operands --- *)
	symbolLeaf = SpannedToken[ParseAction[$name ~~ ParseNotFollowedBy[ParseLiteral["_"]], #1 &], ws, alg["Leaf"]["Symbol", #] &];
	blankLeaf = SpannedToken[text[ParseOptional[$name] ~~ $blank], ws, alg["Leaf"]["Blank", #] &];
	(* a long name, as it is spelt or as its character *)
	longOperator[name_String] := after[ParseChoice @@ (ParseLiteral /@ longNameSpellings[name]), wsAll];
	longPostfixOperator[name_String] := after[ParseChoice @@ (ParseLiteral /@ longNameSpellings[name]), ws];
	comma = after[ParseChoice @@ (ParseLiteral /@ Prepend[longNameSpellings["InvisibleComma"], ","]), wsAll];
	(* comma-separated expressions up to the closing bracket, a closer of
		its spellings; an empty one is Null *)
	items[close_String] := items[{close}];
	items[closes_List] := ParseChoice[
		ParseAction[ParseLookahead[ParseChoice @@ (ParseLiteral /@ closes)], {} &],
		ParseAction[ParseSepBy[ParseOptional[RecRef[nested]], comma], Function[nullLeaf /@ {##}]]];

	patternRight = RecCell[]; spanOperand = RecCell[]; compoundOperand = RecCell[]; tagLeft = RecCell[]; tagRight = RecCell[];
	integrandOperand = RecCell[]; spans = RecCell[]; bareSpans = RecCell[]; prefixAhead = RecCell[]; putRight = RecCell[];
	messageOperand = RecCell[]; messagePattern = RecCell[];

	(* \[LeftFloor] x \[RightFloor] and the other brackets of long names *)
	longGroups = Map[Function[g,
		ParseAction[longOperator[g[[1]]] ~~ items[longNameSpellings[g[[2]]]] ~~ longPostfixOperator[g[[2]]],
			alg["Group"][SymbolName[g[[3]]], #2] &]], Select[$longNameTable["Groups"], #[[1]] =!= "LeftDoubleBracket" &]];
	(* f \[LeftDoubleBracket] i \[RightDoubleBracket], a part *)
	longCalls = ParseAction[longOperator["LeftDoubleBracket"] ~~ items[longNameSpellings["RightDoubleBracket"]] ~~ longPostfixOperator["RightDoubleBracket"],
		Function[{open, indices, close}, Function[e, alg["Infix"]["Part", Prepend[indices, e]]]]];
	(* \[Integral] f \[DifferentialD] x: the operand read whole, a differential
		in it a factor like any other; \[Integral]'s Integrate of a product that
		ends in one, by integralOf, and an integral round a contour its head of
		the operand *)
	integrals = Map[Function[row, ParseAction[
			ParseCondition[
				ParseAction[ParseSome[longOperator[row[[1]]]] ~~ RecRef[integrandOperand], Function[With[{parts = {##}}, integrand[Length[Flatten[{Most[parts]}]], Last[parts]]]]],
				integrandQ[#[[1]], #[[2]]] &],
			Function[r, integralOf[alg, SymbolName[row[[3]]], r[[2]], r[[1]]]]]],
		$longNameTable["Integrals"]];

	(* a name, or n:patt: the name binds its pattern wherever it stands;
		within the pattern a : is Optional's *)
	patternUnit = ParseAction[symbolLeaf ~~ ParseOptional[ParseAction[operator[":"] ~~ RecRef[patternRight], #2 &]],
		Function[{name, pattern}, If[MissingQ[pattern], name, alg["Binary"]["Pattern", name, pattern]]]];
	(* ;; b and ;; at the start: Span[1, ...] *)
	spanStart = ParseAction[bareSpan, Function[f, f[alg["Leaf"]["Integer", "1"]]]];
	(* ?name and ??name, the query Information["name", LongForm -> ...] of
		the words after it, a tab among them a space, or of a string *)
	information = ParseAction[ParseChoice[ParseLiteral["??"], ParseLiteral["?"]] ~~ ParseRegex["[ \t]*"] ~~
			ParseChoice[$string, ParseAction[$informationName, "\"" <> StringReplace[#, "\t" -> " "] <> "\"" &]] ~~ ws,
		Function[{query, spaces, name, w}, alg["Call"][alg["Leaf"]["Symbol", "Information"], {alg["Leaf"]["String", name],
			alg["Binary"]["Rule", alg["Leaf"]["Symbol", "LongForm"], alg["Leaf"]["Symbol", If[query === "??", "True", "False"]]]}]]];
	otherUnits = ParseChoice[
		blankLeaf,
		ParseAction[ParseLookahead[ParseCharacter[DigitCharacter | "."]] ~~ SpannedToken[$number, ws, alg["Leaf"][numberKind[#], #] &], #2 &],
		leaf[$string, "String"],
		leaf[$slot, "Slot"],
		leaf[$out, "Out"],
		ParseAction[after[ParseLiteral["("], wsAll] ~~ RecRef[nested] ~~ after[ParseLiteral[")"], ws],
			alg["Group"]["Paren", {#2}] &],
		ParseAction[after[ParseLiteral["{"], wsAll] ~~ items["}"] ~~ after[ParseLiteral["}"], ws],
			alg["Group"]["List", #2] &],
		ParseAction[after[ParseLiteral["<|"], wsAll] ~~ items["|>"] ~~ after[ParseLiteral["|>"], ws],
			alg["Group"]["Association", #2] &],
		ParseAction[operator["<<"] ~~ leaf[$file, "File"], alg["Prefix"]["Get", #2] &],
		leaf[$freeform, "Freeform"],
		spanStart, information, Sequence @@ longGroups, Sequence @@ integrals];
	plainUnit = ParseChoice[symbolLeaf, otherUnits];
	unit = ParseChoice[patternUnit, otherUnits];

	(* --- postfix operators that read operands of their own --- *)
	call = ParseAction[after[longest["["], wsAll] ~~ ParseNotFollowedBy[ParseLiteral["["]] ~~ items["]"] ~~ after[ParseLiteral["]"], ws],
		Function[{open, look, args, close}, Function[h, alg["Call"][h, args]]]];
	(* e[[i, ...]]: a call whose one argument is a bracket of square
		brackets, trivia between them too *)
	part = ParseAction[after[ParseLiteral["["], wsAll] ~~ after[ParseLiteral["["], wsAll] ~~ items["]"] ~~ after[ParseLiteral["]"], wsAll] ~~ after[ParseLiteral["]"], ws],
		Function[{open, open2, indices, close, close2}, Function[e, alg["Infix"]["Part", Prepend[indices, e]]]]];
	(* a word of one token after a ::, a name, a blank, a number, a slot or a %, is its text *)
	word = leaf[text[ParseChoice[
			ParseOptional[$name] ~~ $blank,
			$name,
			ParseAction[ParseLookahead[ParseCharacter[DigitCharacter | "."]] ~~ $number, #2 &],
			$slot, $out]], "Tag"];
	messageName = ParseChoice[
		(* t::[a, ...], a type with parameters *)
		ParseAction[ParseLiteral["::"] ~~ after[ParseLiteral["["], wsAll] ~~ items["]"] ~~ after[ParseLiteral["]"], ws],
			Function[{colons, open, args, close}, Function[t,
				alg["Call"][alg["Call"][alg["Leaf"]["Symbol", "TypeSpecifier"], {t}], args]]]],
		(* as a notebook reads it, an operand after each ::, the parts one message name *)
		ParseAction[ParseSome[ParseAction[after[ParseLiteral["::"], wsAll] ~~ RecRef[messageOperand], #2 &]],
			Function[With[{parts = {##}}, Function[s, alg["Infix"]["MessageName", Prepend[parts, s]]]]]]];
	derivative = ParseAction[ParseLookahead[ParseLiteral["'"]] ~~ ParseRegex["'+"] ~~ ws,
		Function[{look, primes, w}, Function[f, alg["Call"][
			alg["Call"][alg["Leaf"]["Symbol", "Derivative"], {alg["Leaf"]["Integer", ToString[StringLength[primes]]]}], {f}]]]];
	(* a ;; b ;; c: All where the operand after the first ;; is left out, but for one a prefix
		operator begins, the ;; after b only with an operand after it, and a ;; after the span the
		beginning of a span of its own, the spans a product. After a ;;, as a notebook reads it, a
		line break is whitespace, but for one before another ;; where the first has no operand
		before it: spans after an operand, bareSpans after none *)
	With[{operand = ParseAction[ParseNotFollowedBy[ParseLiteral[";;"]] ~~ RecRef[spanOperand], #2 &],
			all = alg["Leaf"]["Symbol", "All"], one = alg["Leaf"]["Integer", "1"],
			semi = after[longest[";;"], wsAll],
			bareSemi = after[longest[";;"], ParseChoice[ParseAction[wsAll ~~ ParseNotFollowedBy[ParseLiteral[";;"]], Null &], ws]]},
		With[{
				rest = ParseChoice[
					(* b, then ;; and c; a ;; after either begins a span of its own *)
					ParseAction[operand ~~ ParseOptional[ParseAction[semi ~~ operand, #2 &]] ~~
							ParseOptional[ParseAction[ParseLookahead[ParseLiteral[";;"]] ~~ RecRef[spans], #2 &]],
						Function[{b, c, next}, {b, c, next}]],
					(* b left out, then ;; and c, a ;; after c beginning a span of its own *)
					ParseAction[bareSemi ~~ operand ~~ ParseOptional[ParseAction[ParseLookahead[ParseLiteral[";;"]] ~~ RecRef[spans], #2 &]],
						Function[{s, c, next}, {Missing[], c, next}]],
					(* b left out, but where a prefix operator begins it, and a ;; after the first beginning a span of its own *)
					ParseAction[ParseNotFollowedBy[RecRef[prefixAhead]] ~~ ParseOptional[ParseAction[ParseLookahead[ParseLiteral[";;"]] ~~ RecRef[bareSpans], #2 &]],
						Function[{look, next}, {Missing[], Missing[], next}]]],
				value = Function[{a, b, c, next}, Prepend[If[MissingQ[next], {}, next[one]],
					alg["Infix"]["Span", Join[{a, If[MissingQ[b], all, b]}, If[MissingQ[c], {}, {c}]]]]]},
			SetRec[spans, ParseAction[semi ~~ rest, Function[{s, r}, Function[a, value[a, r[[1]], r[[2]], r[[3]]]]]]];
			SetRec[bareSpans, ParseAction[bareSemi ~~ rest, Function[{s, r}, Function[a, value[a, r[[1]], r[[2]], r[[3]]]]]]]];
		span = ParseAction[RecRef[spans], Function[f, Function[a, Replace[f[a], {{s_} :> s, l_ :> alg["Infix"]["Times", l]}]]]];
		bareSpan = ParseAction[RecRef[bareSpans], Function[f, Function[a, Replace[f[a], {{s_} :> s, l_ :> alg["Infix"]["Times", l]}]]]]
	];
	(* a; b; c, an operand left out Null, but for one a prefix operator begins; a ? or a ;; after a ;
		is a pattern test or a span of the compound, as a notebook reads a; ?b and a; ;; *)
	compound = ParseAction[ParseSome[ParseAction[postfixOperator[";"] ~~
			ParseChoice[ParseAction[ParseLookahead[RecRef[prefixAhead]] ~~ RecRef[compoundOperand], #2 &],
				ParseAction[ParseNotFollowedBy[ParseChoice[RecRef[prefixAhead], ParseLiteral["?"], ParseLiteral[";;"]]] ~~ ParseOptional[RecRef[compoundOperand]], #2 &],
				ParseAction[ParseLookahead[ParseChoice[ParseLiteral["?"], ParseLiteral[";;"]]], Missing[] &]], {#2} &]],
		Function[With[{parts = nullLeaf /@ Map[First, {##}]}, Function[a, alg["Infix"]["CompoundExpression", Prepend[parts, a]]]]]];
	(* the = of a set, before a number its . begins too, not the = of free-form input; and = then
		a . not a number's, trivia between them, an unset *)
	setOperator = after[ParseLiteral["="] ~~
		ParseNotFollowedBy[ParseChoice[ParseLiteral["="] ~~ ParseNotFollowedBy[ParseLiteral["["]], ParseLiteral["!="] ~~ ParseNotFollowedBy[ParseLiteral["["]],
			ParseLiteral["["], ParseLiteral["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter]]]], wsAll];
	unset = after[ParseLiteral["="] ~~ ParseNotFollowedBy[ParseChoice[ParseLiteral["="], ParseLiteral["!="]]] ~~ wsAll ~~
		ParseLiteral["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter | "."]], ws];
	tagSet = ParseAction[operator["/:"] ~~ RecRef[tagLeft] ~~ ParseChoice[
			ParseAction[unset, {"TagUnset"} &],
			ParseAction[operator[":="] ~~ RecRef[tagRight], {"TagSetDelayed", #2} &],
			ParseAction[setOperator ~~ RecRef[tagRight], {"TagSet", #2} &]],
		Function[{slash, lhs, rest}, Function[t, If[First[rest] === "TagUnset",
			alg["Binary"]["TagUnset", t, lhs],
			alg["Ternary"][First[rest], t, lhs, Last[rest]]]]]];
	(* >> or >>> and a file alone, else, as a notebook reads it, the expression after it: a file
		where the end, a newline, ;, , or a closer follows it *)
	put = ParseAction[ParseChoice[operator[">>>"], operator[">>"]] ~~ ParseChoice[
			ParseAction[leaf[ParseCondition[$file, closedBracketsQ], "File"] ~~ ParseLookahead[ParseChoice[ParseRegex["\\z"], ParseRegex["[\\n\\r;,)\\]}]"], ParseLiteral["|>"]]], #1 &],
			RecRef[putRight]],
		Function[{o, file}, Function[x, alg["Binary"][If[o === ">>>", "PutAppend", "Put"], x, file]]]];

	(* --- operators whose parser gives the combining function --- *)
	binary[op_String, head_String] := ParseAction[operator[op], Function[o, Function[{l, r}, alg["Binary"][head, l, r]]]];
	prefix[op_String, head_String] := ParseAction[operator[op], Function[o, Function[x, alg["Prefix"][head, x]]]];
	postfix[op_String, head_String] := ParseAction[postfixOperator[op], Function[o, Function[x, alg["Postfix"][x, head]]]];
	flat[head_String] := Function[{operands, ops}, alg["Infix"][head, operands]];
	(* a + b - c: one sum, each term after a - negated *)
	plus = Function[{operands, signs}, alg["Infix"]["Plus", Prepend[
		MapThread[If[#2 === "-", alg["Prefix"]["Minus", #1], #1] &, {Rest[operands], signs}], First[operands]]]];
	(* a < b < c is Less[a, b, c]; a < b <= c is Inequality[a, Less, b, LessEqual, c] *)
	relation = Function[{operands, heads}, relationValue[alg, operands, heads]];
	divisible = Function[{operands, ops}, alg["Infix"]["Divisible", Reverse[operands]]];
	relationOp[op_String, head_String] := ParseAction[operator[op], head &];
	(* a b: a product where an operand follows an operand *)
	implicit = ParseAction[ParseLookahead[ParseChoice[
			ParseCharacter[LetterCharacter | DigitCharacter | "$" | "`" | "\"" | "_" | "#" | "%" | "(" | "{"],
			ParseLiteral["<|"], ParseLiteral["=["],
			ParseLiteral["."] ~~ ParseCharacter[DigitCharacter],
			$letter,
			ParseLookahead[ParseCharacter[_?prefixOnlyStartQ]] ~~ ParseChoice @@ (ParseLiteral /@ Catenate[longNameSpellings /@ $prefixOnlyNames])]],
		"*" &];
	(* a . not before a digit, which begins a number *)
	dot = after[ParseAction[longest["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter]], #1 &], wsAll];

	specs = {
		{"ColonColon", {"Postfix", messageName}},
		{"Infix`Question", {"InfixL", binary["?", "PatternTest"]}},
		{"Call", {"Postfix", part}},
		{"Call", {"Postfix", call}},
		{"Postfix`PlusPlus", {"Postfix", postfix["++", "Increment"]}},
		{"Postfix`PlusPlus", {"Postfix", postfix["--", "Decrement"]}},
		{"Prefix`PlusPlus", {"Prefix", prefix["++", "PreIncrement"]}},
		{"Prefix`PlusPlus", {"Prefix", prefix["--", "PreDecrement"]}},
		{"AtStar", {"InfixN", operator["@*"], flat["Composition"]}},
		{"SlashStar", {"InfixN", operator["/*"], flat["RightComposition"]}},
		{"At", {"InfixR", ParseAction[operator["@"], Function[o, Function[{l, r}, alg["Call"][l, {r}]]]]}},
		{"Tilde", {"Ternary", operator["~"], ParseAction[operator["~"], Function[o, Function[{l, m, r}, alg["Call"][m, {l, r}]]]]}},
		{"SlashAt", {"InfixR", binary["/@", "Map"]}},
		{"SlashAt", {"InfixR", binary["//@", "MapAll"]}},
		{"SlashAt", {"InfixR", binary["@@", "Apply"]}},
		{"SlashAt", {"InfixR", binary["@@@", "MapApply"]}},
		{"Postfix`Bang", {"Postfix", postfix["!", "Factorial"]}},
		{"Postfix`Bang", {"Postfix", postfix["!!", "Factorial2"]}},
		{"SingleQuote", {"Postfix", derivative}},
		{"LessGreater", {"InfixN", operator["<>"], flat["StringJoin"]}},
		{"Caret", {"InfixR", binary["^", "Power"]}},
		{"StarStar", {"InfixN", operator["**"], flat["NonCommutativeMultiply"]}},
		{"Dot", {"InfixN", dot, flat["Dot"]}},
		{"Prefix`Minus", {"Prefix", prefix["-", "Minus"]}},
		{"Prefix`Minus", {"Prefix", prefix["+", "Plus"]}},
		{"Slash", {"InfixL", binary["/", "Divide"]}},
		{"Star", {"InfixN", operator["*"], flat["Times"]}},
		{"Star", {"InfixN", implicit, flat["Times"]}},
		{"Infix`Plus", {"InfixN", operator["+"], plus}},
		{"Infix`Plus", {"InfixN", operator["-"], plus}},
		{"SemiSemi", {"Postfix", span}},
		{"LongName`DirectedEdge", {"InfixR", binary["DirectedEdge", "DirectedEdge"]}},
		{"LongName`DirectedEdge", {"InfixR", binary["UndirectedEdge", "UndirectedEdge"]}},
		{"Class`Inequality", {"InfixN", relationOp["==", "Equal"], relation}},
		{"Class`Inequality", {"InfixN", relationOp["!=", "Unequal"], relation}},
		{"Class`Inequality", {"InfixN", relationOp["<=", "LessEqual"], relation}},
		{"Class`Inequality", {"InfixN", relationOp[">=", "GreaterEqual"], relation}},
		{"Class`Inequality", {"InfixN", relationOp["<", "Less"], relation}},
		{"Class`Inequality", {"InfixN", relationOp[">", "Greater"], relation}},
		{"EqualEqualEqual", {"InfixN", operator["==="], flat["SameQ"]}},
		{"EqualEqualEqual", {"InfixN", operator["=!="], flat["UnsameQ"]}},
		{"Class`SetRelations", {"InfixN", operator["Element"], flat["Element"]}},
		{"Prefix`Bang", {"Prefix", prefix["!", "Not"]}},
		{"Prefix`Bang", {"Prefix", ParseAction[operator["!!"], Function[o, Function[x, alg["Prefix"]["Not", alg["Prefix"]["Not", x]]]]]}},
		{"AmpAmp", {"InfixN", operator["&&"], flat["And"]}},
		{"BarBar", {"InfixN", operator["||"], flat["Or"]}},
		{"DotDot", {"Postfix", postfix["..", "Repeated"]}},
		{"DotDot", {"Postfix", postfix["...", "RepeatedNull"]}},
		{"Bar", {"InfixN", operator["|"], flat["Alternatives"]}},
		{"Fake`OptionalColon", {"InfixL", binary[":", "Optional"]}},
		{"TildeTilde", {"InfixN", operator["~~"], flat["StringExpression"]}},
		{"SlashSemi", {"InfixL", binary["/;", "Condition"]}},
		{"LessMinusGreater", {"InfixR", binary["<->", "TwoWayRule"]}},
		{"MinusGreater", {"InfixR", binary["->", "Rule"]}},
		{"MinusGreater", {"InfixR", binary[":>", "RuleDelayed"]}},
		{"SlashDot", {"InfixL", binary["/.", "ReplaceAll"]}},
		{"SlashDot", {"InfixL", binary["//.", "ReplaceRepeated"]}},
		{"PlusEqual", {"InfixR", binary["+=", "AddTo"]}},
		{"PlusEqual", {"InfixR", binary["-=", "SubtractFrom"]}},
		{"PlusEqual", {"InfixR", binary["*=", "TimesBy"]}},
		{"PlusEqual", {"InfixR", binary["/=", "DivideBy"]}},
		{"Amp", {"Postfix", postfix["&", "Function"]}},
		{"SlashSlashEqual", {"InfixR", binary["//=", "ApplyTo"]}},
		{"SlashSlash", {"InfixL", ParseAction[operator["//"], Function[o, Function[{l, r}, alg["Call"][r, {l}]]]]}},
		{"SlashColon", {"Postfix", tagSet}},
		{"Equal", {"Postfix", ParseAction[unset, Function[o, Function[x, alg["Postfix"][x, "Unset"]]]]}},
		{"Equal", {"InfixR", ParseAction[setOperator, Function[o, Function[{l, r}, alg["Binary"]["Set", l, r]]]]}},
		{"Equal", {"InfixR", binary[":=", "SetDelayed"]}},
		{"Equal", {"InfixR", binary["^=", "UpSet"]}},
		{"Equal", {"InfixR", binary["^:=", "UpSetDelayed"]}},
		{"Equal", {"InfixR", binary["|->", "Function"]}},
		{"GreaterGreater", {"Postfix", put}},
		{"Semi", {"Postfix", compound}}
	};

	longSpecs = Join[
		Map[Function[row, With[{name = row[[1]], head = heldLongHead[row]}, {row[[4]], Which[
			row[[3]] === CodeParser`InfixInequality, {"InfixN", ParseAction[longOperator[name], head &], relation},
			name === "Minus", {"InfixN", ParseAction[longOperator[name], "-" &], plus},
			name === "ImplicitPlus", {"InfixL", ParseAction[longOperator[name], Function[o, Function[{l, r}, alg["Binary"]["Plus", l, r]]]]},
			name === "Divides", {"InfixN", longOperator[name], divisible},
			name === "InvisibleApplication", {"InfixR", ParseAction[longOperator[name], Function[o, Function[{l, r}, alg["Call"][l, {r}]]]]},
			row[[2]] === "InfixNode", {"InfixN", longOperator[name], flat[head]},
			True, {If[row[[5]] === "Right", "InfixR", "InfixL"], ParseAction[longOperator[name], Function[o, Function[{l, r}, alg["Binary"][head, l, r]]]]}]}]],
			$heldLongInfix],
		Map[{#[[4]], {"Prefix", With[{head = heldLongHead[#]}, ParseAction[longOperator[#[[1]]], Function[o, Function[x, alg["Prefix"][head, x]]]]]}} &, $heldLongPrefix],
		Map[{#[[4]], {"Postfix", With[{head = heldLongHead[#]}, ParseAction[longPostfixOperator[#[[1]]], Function[o, Function[x, alg["Postfix"][x, head]]]]]}} &,
			$longNameTable["Postfix"]],
		{{"Call", {"Postfix", longCalls}}}];
	specs = Join[specs, longSpecs];

	table[u_, min_Integer] := ParseOperatorTable[u, levelsAbove[specs, min]];
	(* the operators that bind more tightly than min, and the prefix ones of any precedence *)
	prefixedTable[u_, min_Integer] := ParseOperatorTable[u, levelsAbove[Select[specs, #[[2, 1]] === "Prefix" || precedenceValue[First[#]] > min &], -1]];
	(* what begins an operand with an operator: a prefix operator, a << or an integral *)
	SetRec[prefixAhead, ParseChoice @@ Join[Cases[specs, {_, {"Prefix", p_}} :> p], {operator["<<"]}, longOperator /@ $longNameTable["Integrals"][[All, 1]]]];
	SetRec[integrandOperand, table[unit, $integralPrecedence]];
	SetRec[patternRight, table[plainUnit, $codeParserPrecedence["Fake`PatternColon"]]];
	SetRec[putRight, table[unit, $codeParserPrecedence["GreaterGreater"]]];
	(* a span's operand: what binds more tightly than ;;, and a prefix operator of any precedence,
		as in any other operand, its operand all that binds more tightly than it, as CodeParser reads
		it [W15 bug] *)
	With[{lows = Select[specs, #[[2, 1]] === "Prefix" && precedenceValue[First[#]] <= $codeParserPrecedence["SemiSemi"] &]},
		SetRec[spanOperand, table[ParseChoice[
				Sequence @@ Map[Function[s, ParseAction[s[[2, 2]] ~~ prefixedTable[unit, precedenceValue[First[s]]], #1[#2] &]], lows], unit],
			$codeParserPrecedence["SemiSemi"]]]];
	(* a message name's operand, as a notebook reads it: a name or a blank with a colon after it the
		pattern, its default too; a string its value; a word of one token its text; else a group, a
		<< and its file, a query, or a prefix operator and its operand, all that binds more tightly
		than it *)
	SetRec[messagePattern, table[ParseChoice[patternUnit, blankLeaf], $codeParserPrecedence["Fake`OptionalColon"] - 1]];
	SetRec[messageOperand, ParseChoice[
		ParseAction[ParseLookahead[ParseChoice[ParseOptional[$name] ~~ $blank, $name] ~~ ParseRegex["[ \t]*"] ~~ ParseLiteral[":"] ~~
			ParseNotFollowedBy[ParseCharacter[":" | "=" | ">"]]] ~~ RecRef[messagePattern], #2 &],
		leaf[$string, "String"],
		(* a string not closed, as a notebook reads a::"b: a word of its text to the end of the source *)
		leaf[ParseRegex["\"(?:[^\"\\\\]|\\\\[\\s\\S])*\\z"], "Tag"],
		word,
		ParseAction[ParseLookahead[ParseChoice[ParseLiteral["("], ParseLiteral["{"], ParseLiteral["<|"], ParseLiteral["<<"], ParseLiteral["?"]]] ~~ otherUnits, #2 &],
		Sequence @@ Map[Function[s, ParseAction[s[[2, 2]] ~~ prefixedTable[unit, precedenceValue[First[s]]], #1[#2] &]],
			Select[specs, #[[2, 1]] === "Prefix" &]]]];
	SetRec[compoundOperand, table[unit, $codeParserPrecedence["Semi"]]];
	SetRec[tagLeft, table[unit, $codeParserPrecedence["Equal"]]];
	SetRec[tagRight, table[unit, $codeParserPrecedence["Equal"] - 1]];
	table[unit, 0]
]

(* Long-named operators: their spellings are listed under the operator's
	own name rather than an ASCII one. *)
spellings[op : "DirectedEdge" | "UndirectedEdge" | "Element"] := $longNameOperators[op]

(* ::Section:: *)
(*The held algebra*)

held[e_HoldComplete] := <|"Expr" -> e, "Literal" -> False|>

(* HoldComplete[h], {HoldComplete[a], ...} -> HoldComplete[h[a, ...]]: up to three arguments by
	one rule, more by joining them *)
heldCall[HoldComplete[h_], {}] := HoldComplete[h[]]
heldCall[HoldComplete[h_], {HoldComplete[a_]}] := HoldComplete[h[a]]
heldCall[HoldComplete[h_], {HoldComplete[a_], HoldComplete[b_]}] := HoldComplete[h[a, b]]
heldCall[HoldComplete[h_], {HoldComplete[a_], HoldComplete[b_], HoldComplete[c_]}] := HoldComplete[h[a, b, c]]
heldCall[HoldComplete[h_], args_List] :=
	Replace[Join @@ Prepend[args, HoldComplete[]], HoldComplete[a___] :> HoldComplete[h[a]]]

(* A symbol from its name, held: the one place the grammar asks the
	kernel's reader for an expression. Nothing else makes a symbol without
	evaluating it, since Symbol[name] gives the symbol's value; the name is
	one the grammar has read whole, and it is read under HoldComplete. A
	kernel with a primitive that interns a name gives it here instead. *)
heldName[name_String] := ToExpression[name, InputForm, HoldComplete]

heldSymbol[name_String] := heldSymbol[name] = heldName["System`" <> name]

symbolCall[name_String, args_List] := heldCall[heldSymbol[name], args]

(* -x, as a notebook reads it: a number literal right after the minus, an integer or a real, folds
	it in, anything else, a product, a rational as 1*^-3 is and a number in parentheses too, is
	Times[-1, x] *)
negated[x_Association] := negatedHeld[x["Expr"], If[x["Literal"], 1, 0]]

(* the same of a held expression, its mark 1 for a number literal *)
negatedHeld[HoldComplete[n : (_Integer | _Real)], 1] := With[{m = -n}, HoldComplete[m]]
negatedHeld[e_HoldComplete, _] := Replace[e, HoldComplete[x_] :> HoldComplete[Times[-1, x]]]

(* x_h, __, x___., ...: the name before the underscores, their count, and
	the head or the . after them *)
blankExpression::usage = "blankExpression[s] gives the pattern of the blank text s, x_h, __, x___. and the like, held."
blankExpression[s_String] := With[{underscores = StringPosition[s, "_"]},
	{name = StringTake[s, First[First[underscores]] - 1], count = Length[underscores], head = StringDrop[s, First[Last[underscores]]]},
	If[head === ".", heldCall[heldSymbol["Optional"], {namedBlank[name, count, ""]}], namedBlank[name, count, head]]
]

namedBlank::usage = "namedBlank[name, count, head] gives the blank of count underscores and the head, \"\" for none, named name, \"\" \
for none, held."
namedBlank["", count_Integer, head_String] := headBlank[count, head]
namedBlank[name_String, count_Integer, head_String] := heldCall[heldSymbol["Pattern"], {heldName[name], headBlank[count, head]}]

headBlank::usage = "headBlank[count, head] gives the blank of count underscores and the head, \"\" for none, held."
headBlank[count_Integer, ""] := $heldBlanks[[count]]
headBlank[count_Integer, head_String] := heldCall[heldSymbol[$blankNames[[count]]], {heldName[head]}]

$blankNames = {"Blank", "BlankSequence", "BlankNullSequence"}
$heldBlanks := $heldBlanks = symbolCall[#, {}] & /@ $blankNames

slotExpression::usage = "slotExpression[s] gives the slot of the text s, #, #2, ##, #name or #\"name\", held."
slotExpression[s_String] /; StringStartsQ[s, "#\""] := symbolCall["Slot", {HoldComplete @@ {stringValue[StringDrop[s, 1]]}}]
slotExpression[s_String] := symbolCall[If[StringStartsQ[s, "##"], "SlotSequence", "Slot"], {slotArgument[StringDelete[s, "#"]]}]

slotArgument::usage = "slotArgument[rest] gives the argument of a slot of the text rest after its #s, held: 1 for none, a number, or a \
name."
slotArgument[""] := HoldComplete[1]
slotArgument[rest_String] /; StringMatchQ[rest, DigitCharacter ..] := HoldComplete @@ {FromDigits[rest]}
slotArgument[rest_String] := HoldComplete @@ {longNamesRead[rest]}

(* a name's text, each long name in it that is a letter its character *)
longNamesRead[s_String] := If[ StringFreeQ[s, "\\["], s,
	StringReplace[s, "\\[" ~~ name : (LetterCharacter | DigitCharacter) .. ~~ "]" /; KeyExistsQ[longNameCharacters[], name] :> longNameCharacters[][name]]]

(* %: Out[]; %%: Out[-2]; %3: Out[3] *)
outExpression::usage = "outExpression[s] gives the Out of the text s, %, %% or %3, held."
outExpression[s_String] := symbolCall["Out", outArguments[StringCount[s, "%"], StringDelete[s, "%"]]]

outArguments::usage = "outArguments[count, digits] gives the arguments of the Out of count %s and the digits after them, held."
outArguments[_Integer, digits_String] /; digits =!= "" := {HoldComplete @@ {FromDigits[digits]}}
outArguments[1, ""] := {}
outArguments[count_Integer, ""] := {HoldComplete @@ {-count}}

(* ::Section:: *)
(*Numbers*)

(* The value of a number's text: b^^digits in base b, a . for a real, a `
	and its precision or a `` and its accuracy, in digits of the base, and
	*^e for a power of the base. A real without a mark is a machine real,
	unless its digits are more than a machine real holds; it then keeps
	the accuracy its digits give [WL 15.0.0]. *)
numberValue::usage = "numberValue[s] gives the value of the number text s."
numberValue[s_String] := Which[
	DigitQ[s],
		FromDigits[s],
	StringFreeQ[s, "^" | "*" | "`"],
		decimalValue[s],
	True,
		markedNumberValue[s]
]

(* a real of digits and a point alone: the machine real nearest its value, or, with more digits
	than a machine real holds, its value at the accuracy its digits give, as markedNumberValue reads
	one with no mark *)
decimalValue::usage = "decimalValue[s] gives the value of the text s of digits and a point."
decimalValue[s_String] := pointValue[StringSplit[s, ".", All]]

pointValue::usage = "pointValue[{whole, fraction}] gives the value of the digits whole, a point and the digits fraction."
pointValue[{whole_String, fraction_String, ___String}] := With[{digits = whole <> fraction},
	{exact = FromDigits[digits] / 10^StringLength[fraction]},
	If[significantDigits[digits, 10], SetAccuracy[exact, StringLength[fraction]], machineReal[exact]]
]

(* A number's text with a base, a power of the base or a mark: the base before ^^, the power after
	*^, the mark, a ` of a precision or a `` of an accuracy, and its digits, and the digits before
	and after the point, valued as numberValue says. *)
markedNumberValue::usage = "markedNumberValue[s] gives the value of the number text s that has a base, a power of the base or a mark."
markedNumberValue[s_String] := With[
	{base = If[StringContainsQ[s, "^^"], FromDigits[First[StringSplit[s, "^^"]]], 10], unbased = Last[StringSplit[s, "^^"]]},
	{exponent = If[StringContainsQ[unbased, "*^"], signedValue[Last[StringSplit[unbased, "*^"]]], 0]},
	markedValue[base, exponent, numberMark[First[StringSplit[unbased, "*^"]]], StringContainsQ[s, "*^"]]
]

numberMark::usage = "numberMark[text] gives {the digits of the number text before its mark, the mark None, \"Precision\" or \"Accuracy\", \
the text of the mark's digits}."
numberMark[text_String] := Replace[StringPosition[text, "`", 1], {
	{} :> {text, None, ""},
	{{at_Integer, _Integer}} :> If[StringTake[text, {at, Min[at + 1, StringLength[text]]}] === "``",
		{StringTake[text, at - 1], "Accuracy", StringDrop[text, at + 1]},
		{StringTake[text, at - 1], "Precision", StringDrop[text, at]}
	]
}]

markedValue::usage = "markedValue[base, exponent, {digits, mark, markText}, powered] gives the value of the digits text of the base, the \
power exponent of the base, and the mark, powered True where the text has a *^."
markedValue[base_Integer, exponent_, {text_String, mark_, markText_String}, powered_] := With[
	{whole = First[StringSplit[text, ".", All]], fraction = If[StringContainsQ[text, "."], StringSplit[text, ".", All][[2]], ""]},
	{digits = FromDigits[whole <> fraction, base], scale = exponent - StringLength[fraction], point = StringContainsQ[text, "."]},
	Which[
		mark === None && !point,
			If[digits === 0, 0, digits base^scale],
		mark === "Accuracy",
			accurateValue[digits, base, scale, signedValue[markText]],
		(* a zero of a precision: an integer one exact [WL 15.0.0] *)
		mark === "Precision" && markText =!= "" && digits === 0,
			If[point, 0., 0],
		mark === "Precision" && markText =!= "",
			With[{precision = digitsInBase[signedValue[markText], base]}, SetPrecision[scaledValue[digits, base, scale, Max[precision, 0]], precision]],
		mark === None && significantDigits[whole <> fraction, base, powered],
			longValue[digits, base, scale, StringLength[fraction] - exponent],
		True,
			machineValue[digits, base, scale]
	]
]

(* "-12", "3.5", ".5" -> the exact value *)
signedValue[t_String] := With[{unsigned = StringDelete[t, "+" | "-"]},
	If[StringStartsQ[t, "-"], -1, 1] * If[StringContainsQ[unsigned, "."],
		With[{parts = StringSplit[unsigned, ".", All]}, FromDigits[parts[[1]] <> parts[[2]]] / 10^StringLength[parts[[2]]]],
		FromDigits[unsigned]]]

(* a count of digits of the base, in decimal digits, by the bits they are [WL 15.0.0] *)
digitsInBase[n_, 10] := n
digitsInBase[n_, base_Integer] := N[n] Log2[N[base]] Log10[2.]

(* more digits than a machine real holds: of base b, Floor[53 / Log2[b]] + 2 of them, 17 decimal
	ones, but the 53 of base 2, and with a power of the base never fewer than 17 [WL 15.0.0] *)
significantDigits[digits_String, base_Integer, scaled_ : False] := With[{count = StringLength[StringDelete[digits, StartOfString ~~ "0" ..]]},
	count > If[TrueQ[scaled], Max[17, machineDigits[base]], machineDigits[base]]]
machineDigits[base_Integer] := Which[base === 10, 17, base === 2, 53, True, Floor[53 / Log2[base]] + 2]

(* digits times the base to the power scale at the accuracy of a digits of the base: exactly made
	where the power is small enough to make, else at the precision Wolfram 15 counts in bits, zero
	at the accuracy where the value is below it [WL 15.0.0] *)
accurateValue[digits_Integer, base_Integer, scale_Integer, a_] := If[ Abs[scale] <= 10000, SetAccuracy[digits base^scale, digitsInBase[a, base]],
	With[{p = bitsPrecision[digits, base, scale, a]}, If[p <= 0, SetAccuracy[0, digitsInBase[a, base]], SetPrecision[scaledValue[digits, base, scale, p], p]]]]

(* a number of no mark with more digits than a machine real holds, digits times the base to the
	power scale, a digits of the base after its point: at the precision Wolfram 15 counts in bits
	[WL 15.0.0] *)
longValue[digits_Integer, base_Integer, scale_Integer, a_] := With[{p = bitsPrecision[digits, base, scale, a]}, SetPrecision[scaledValue[digits, base, scale, p], p]]

(* the precision, in decimal digits, of digits times the base to the power scale at the accuracy of
	a digits of the base: the bits of the accuracy and of the value's magnitude [WL 15.0.0] *)
bitsPrecision[digits_Integer, base_Integer, scale_Integer, a_] := (a Log2[N[base]] + (N[Log2[digits]] + scale Log2[N[base]])) Log10[2.]

(* Digits times the base to the power scale: exact where the power is small enough to make, else
	at a working precision, wp digits of the value kept through the power. A power past
	$MaxNumber overflows, as the kernel's reader's does. *)
scaledValue[digits_Integer, base_Integer, scale_Integer, wp_] := If[ Abs[scale] <= 10000, digits base^scale,
	N[digits, wp + 10] N[base, wp + 10 + Log10[N[Abs[scale]]]]^scale]

(* the decimal exponent of digits times the base to the power scale *)
magnitude[digits_Integer, base_Integer, scale_Integer] := If[digits === 0, -Infinity, N[Log10[digits]] + scale N[Log10[base]]]

(* a real with no precision of its own, digits times the base to the power scale: the machine
	real nearest it, zero where it is too small for one, and the value at machine precision where it
	is too large; below $MinNumber an underflow [WL 15.0.0] *)
machineValue[0, _Integer, _Integer] := 0.
machineValue[digits_Integer, base_Integer, scale_Integer] := If[ Abs[scale] <= 10000, machineReal[digits base^scale],
	With[{m = magnitude[digits, base, scale]},
		(* by its difference, as a comparison of machine reals takes ones near each other for equal *)
		Which[m - N[Log10[$MinNumber]] < 0, Underflow[], m < -400, 0., m <= 400, machineReal[digits base^scale], True, N[scaledValue[digits, base, scale, 20]]]]]

(* The machine real nearest an exact value, as Wolfram 15's ToExpression and a notebook read one: by
	the power of 2 at or below it, from the bits of its numerator and denominator, its 53 bits rounded
	to the nearest, halves to even, where N of the exact value can be a bit away, as N[1234/10^23]
	is. Below the least normal one the subnormal nearest it, by its multiple of the least
	subnormal, zero where that is nearer, and past the greatest the value at machine precision
	[WL 15.0.0]. *)
machineReal[x_] := Which[
	x == 0, 0.,
	Abs[x] > $MaxMachineNumber, N[x],
	Abs[x] >= 2^-1022, nearestMachineReal[x],
	True, With[{k = Round[Abs[x] 2^1074]}, If[k === 0, 0., Quiet[N[Sign[x] k / 2^1074], General::munfl]]]]

nearestMachineReal::usage = "nearestMachineReal[x] gives the machine real nearest the exact value x, at least the least normal one."
nearestMachineReal[x_] := With[{a = Abs[x]},
	{bits = BitLength[Numerator[a]] - BitLength[Denominator[a]]},
	{exponent = If[a < 2^bits, bits - 1, bits]},
	Sign[x] roundedMachineReal[Round[a 2^(52 - exponent)], exponent]
]

roundedMachineReal::usage = "roundedMachineReal[m, e] gives the machine real of the 53-bit mantissa m and the exponent e, a mantissa \
rounded up to 2^53 the next power of 2."
roundedMachineReal[m_Integer, e_Integer] := If[m === 2^53, N[2^(e + 1)], N[m 2^(e - 52)]]

(* ::Section:: *)
(*Strings*)

(* The characters of a string's text: its escapes decoded, an unknown one
	kept as written [WL 15.0.0]. A \ before a return or a newline continues
	the line, the newline after a return staying. *)
stringValue[s_String] := With[{inner = StringTake[s, {2, -2}]},
	If[StringFreeQ[inner, "\\"], inner, StringReplace[inner, $escapes]]]

$escapes = {
	"\\\r" -> "", "\\\n" -> "", "\\<" -> "", "\\>" -> "",
	"\\\\" -> "\\", "\\\"" -> "\"", "\\n" -> "\n", "\\t" -> "\t", "\\r" -> "\r", "\\b" -> "\b", "\\f" -> "\f", "\\ " -> " ",
	"\\" ~~ digits : Repeated[CharacterRange["0", "7"], {3}] :> FromCharacterCode[FromDigits[digits, 8]],
	"\\." ~~ digits : Repeated[HexadecimalCharacter, {2}] :> FromCharacterCode[FromDigits[digits, 16]],
	"\\:" ~~ digits : Repeated[HexadecimalCharacter, {4}] :> FromCharacterCode[FromDigits[digits, 16]],
	"\\|" ~~ digits : Repeated[HexadecimalCharacter, {6}] :> FromCharacterCode[FromDigits[digits, 16]],
	"\\[" ~~ name : (LetterCharacter | DigitCharacter) .. ~~ "]" /; KeyExistsQ[longNameCharacters[], name] :> longNameCharacters[][name],
	(* the escapes of linear box syntax *)
	"\\!" -> "\:f7c1", "\\(" -> "\:f7c9", "\\)" -> "\:f7c0", "\\*" -> "\:f7c8", "\\@" -> "\:f7c2", "\\^" -> "\:f7c6",
	"\\_" -> "\:f7ca", "\\%" -> "\:f7c5", "\\&" -> "\:f7c7", "\\+" -> "\:f7cb", "\\/" -> "\:f7cc", "\\`" -> "\:f7cd"
}

(* the character of each long name, "Alpha" -> the letter alpha, as
	Wolfram 15 reads it (Languages/LongNameCharacters.wl, recorded by
	dev/freeze-longname-characters.wls), read at the first long name a
	string holds *)
longNameCharacters[] := longNameCharacters[] = Map[FromCharacterCode, Get[FileNameJoin[{$languagesDirectory, "LongNameCharacters.wl"}]]]

(* a leaf's expression, held *)
heldLeafValue["Integer" | "Real", s_String] := HoldComplete @@ {numberValue[s]}
heldLeafValue["String", s_String] := HoldComplete @@ {stringValue[s]}
heldLeafValue["Symbol", s_String] := heldName[s]
heldLeafValue["Blank", s_String] := blankExpression[s]
heldLeafValue["Slot", s_String] := slotExpression[s]
heldLeafValue["Out", s_String] := outExpression[s]
heldLeafValue["Tag", s_String] := HoldComplete[s]
heldLeafValue["File", s_String] := HoldComplete @@ {If[StringStartsQ[s, "\""], stringValue[s], fileValue[s]]}
heldLeafValue["Boxes", s_String] := linearHeld[s]
(* =[text] is FreeformEvaluate["text"], its escapes decoded, as those of a file are, and, as a
	notebook reads it, from its first character that is no whitespace to the end of its line, a
	space where nothing is left *)
heldLeafValue["Freeform", s_String] := symbolCall["FreeformEvaluate", {HoldComplete @@ {freeformText[fileValue[StringTake[s, {3, -2}]]]}}]

freeformText[s_String] := Replace[StringReplace[s, {StartOfString ~~ (" " | "\t" | "\n" | "\r") .. -> "", ("\n" | "\r") ~~ ___ ~~ EndOfString -> ""}], "" -> " "]

heldLeaf["Integer" | "Real", s_String] := <|"Expr" -> heldLeafValue["Integer", s], "Literal" -> True|>
heldLeaf[kind_String, s_String] := held[heldLeafValue[kind, s]]

(* ::Section:: *)
(*Linked lists*)

(* A linked list is {first, rest}, the empty one {}: a step of a loop that puts an item on one
	neither copies it nor writes over it. *)
linkedItems::usage = "linkedItems[list] gives the items of the linked list {first, {second, ... {}}}, the first first."
linkedItems[list_List] := First /@ Most[NestWhileList[Last, list, # =!= {} &]]

(* ::Section:: *)
(*Linear syntax*)

(* The boxes of linear syntax as Wolfram 15's reader reads them: a \( to its \) its boxes, a \!
	before it LinearBoxes of them, all held. Inside, \^ \_ \% \& \+ \/ \@ \` build the boxes they
	name from the box on either side, \( \) group, \* reads the input after it, and the rest is
	rows of tokens, nested as their concrete syntax tree nests them. *)
linearHeld::usage = "linearHeld[s] gives the boxes of the linear syntax s, \\(...\\) or \\!\\(...\\), held."
linearHeld[s_String] := With[{interpret = StringStartsQ[s, "\\!"]},
	{inner = StringTake[s, {If[interpret, 5, 3], If[StringEndsQ[s, "\\)"], -3, -1]}]},
	ReplaceAll[HoldComplete @@ {If[interpret, LinearBoxes[linearGroup[inner]], linearGroup[inner]]}, linearInput[HoldComplete[e_]] :> e]
]

(* the boxes of a group's text: a form's, after its \`, else its row's *)
linearGroup::usage = "linearGroup[s] gives the boxes of the text s of a group: a form's, after its \\`, else its row's."
linearGroup[s_String] := With[{pieces = linearPieces[s]},
	Replace[FirstPosition[pieces, {"Form"}, {0}, {1}], {
		{0} :> linearRow[pieces],
		{form_Integer} :> FormBox[linearRow[Drop[pieces, form]], linearForm[Take[pieces, form - 1]]]
	}]
]

(* the pieces of a group's text: {"Text", t}, {"Box", boxes}, {"Op", o} for a box operator, and
	{"Form"}; a newline or a tab in the text is whitespace, and \  \t \n are their boxes. The text is
	read an escape or a character at a time, the state {where it goes on, the pieces read, a linked
	list, the text not yet a piece}. *)
linearPieces::usage = "linearPieces[s] gives the pieces of the text s of a group of linear syntax."
linearPieces[s_String] := With[{characters = Characters[s]},
	Reverse @ linkedItems @ textFlushed @ NestWhile[
		linearPieceStep[characters, #] &,
		{1, {}, ""},
		First[#] <= Length[characters] &
	]
]

textFlushed::usage = "textFlushed[{at, pieces, text}] gives the pieces with the text as a piece of its own, where there is any."
textFlushed[{_Integer, pieces_List, ""}] := pieces
textFlushed[{_Integer, pieces_List, text_String}] := {{"Text", text}, pieces}

linearPieceStep::usage = "linearPieceStep[characters, {at, pieces, text}] gives the state after the escape or the character at at."
linearPieceStep[characters_List, {at_Integer, pieces_List, text_String}] /; characters[[at]] === "\\" && at < Length[characters] :=
	linearEscapeStep[characters, at, characters[[at + 1]], pieces, text]
linearPieceStep[characters_List, {at_Integer, pieces_List, text_String}] :=
	{at + 1, pieces, text <> If[MemberQ[{"\n", "\r", "\t"}, characters[[at]]], " ", characters[[at]]]}

linearEscapeStep::usage = "linearEscapeStep[characters, at, c, pieces, text] gives the state after the escape \\c at at."
linearEscapeStep[characters_List, at_Integer, "(", pieces_List, text_String] := With[{close = groupClose[characters, at + 2]},
	{
		First[close],
		{{"Box", linearGroup[StringJoin[Take[characters, {at + 2, If[Last[close] === 0, First[close] - 3, Length[characters]]}]]]}, textFlushed[{at, pieces, text}]},
		""
	}
]
linearEscapeStep[_List, at_Integer, ")" | "!", pieces_List, text_String] := {at + 2, pieces, text}
linearEscapeStep[_List, at_Integer, op : "^" | "_" | "%" | "&" | "+" | "/" | "@", pieces_List, text_String] :=
	{at + 2, {{"Op", op}, textFlushed[{at, pieces, text}]}, ""}
linearEscapeStep[_List, at_Integer, "`", pieces_List, text_String] := {at + 2, {{"Form"}, textFlushed[{at, pieces, text}]}, ""}
linearEscapeStep[characters_List, at_Integer, "*", pieces_List, text_String] := With[{star = linearStar[characters, at + 2]},
	{Last[star], {{"Box", First[star]}, textFlushed[{at, pieces, text}]}, ""}
]
linearEscapeStep[_List, at_Integer, " ", pieces_List, text_String] := {at + 2, {{"Box", " "}, textFlushed[{at, pieces, text}]}, ""}
linearEscapeStep[_List, at_Integer, "t", pieces_List, text_String] := {at + 2, {{"Box", "\t"}, textFlushed[{at, pieces, text}]}, ""}
linearEscapeStep[_List, at_Integer, "n", pieces_List, text_String] := {at + 2, {{"Box", "\n"}, textFlushed[{at, pieces, text}]}, ""}
linearEscapeStep[_List, at_Integer, c_String, pieces_List, text_String] := {at + 2, pieces, text <> "\\" <> c}

(* where the group whose text begins at from closes: {past its \), how many \( are left open} *)
groupClose::usage = "groupClose[characters, from] gives {where reading goes on after the \\) that closes the group from from on, how \
many groups are left open there}."
groupClose[characters_List, from_Integer] := NestWhile[groupScanStep[characters, #] &, {from, 1}, First[#] <= Length[characters] && Last[#] > 0 &]

groupScanStep::usage = "groupScanStep[characters, {at, depth}] gives the scan's place and the depth of the groups after the character, or \
the escape, at at."
groupScanStep[characters_List, {at_Integer, depth_Integer}] /; characters[[at]] === "\\" && at < Length[characters] :=
	{at + 2, depth + Switch[characters[[at + 1]], "(", 1, ")", -1, _, 0]}
groupScanStep[_List, {at_Integer, depth_Integer}] := {at + 1, depth}

(* \* and the input after it, a string or a name and its brackets: the boxes it gives, held where
	they are no string, and where the text goes on *)
linearStar::usage = "linearStar[characters, from] gives {the boxes of the input after a \\* from from on, where the text goes on}."
linearStar[characters_List, start_Integer] := With[{from = start + LengthWhile[Drop[characters, start - 1], # === " " &]},
	{end = starEnd[characters, from]},
	{starBoxes[StringJoin[Take[characters, {from, end - 1}]]], end}
]

starEnd::usage = "starEnd[characters, from] gives where the input of a \\* from from on ends: past a string, or past a name and its \
brackets."
starEnd[characters_List, from_Integer] /; from <= Length[characters] && characters[[from]] === "\"" := 1 + NestWhile[
	If[characters[[#]] === "\\", # + 2, # + 1] &,
	from + 1,
	# <= Length[characters] && characters[[#]] =!= "\"" &
]
starEnd[characters_List, from_Integer] := NestWhile[
	bracketsEnd[characters, #] &,
	from + LengthWhile[Drop[characters, from - 1], LetterQ[#] || DigitQ[#] || # === "$" || # === "`" &],
	# <= Length[characters] && characters[[#]] === "[" &
]

bracketsEnd::usage = "bracketsEnd[characters, from] gives where the brackets that open at from close, strings in them read whole."
bracketsEnd[characters_List, from_Integer] := First @ NestWhile[
	bracketScanStep[characters, #] &,
	bracketScanStep[characters, {from, 0, False}],
	First[#] <= Length[characters] && (Last[#] || #[[2]] =!= 0) &
]

bracketScanStep::usage = "bracketScanStep[characters, {at, depth, quoted}] gives the scan's place, the depth of the brackets and whether \
it is in a string, after the character at at."
bracketScanStep[characters_List, {at_Integer, depth_Integer, True}] := {at + If[characters[[at]] === "\\", 2, 1], depth, characters[[at]] =!= "\""}
bracketScanStep[characters_List, {at_Integer, depth_Integer, False}] := Switch[characters[[at]],
	"\"",
		{at + 1, depth, True},
	"[",
		{at + 1, depth + 1, False},
	"]",
		{at + 1, depth - 1, False},
	_,
		{at + 1, depth, False}
]

starBoxes::usage = "starBoxes[text] gives the boxes of the input text of a \\*: a string it reads as, held input, else the text."
starBoxes[text_String] := Replace[WolframLanguageHeld[text], {
	{HoldComplete[x_String]} :> x,
	{held_HoldComplete} :> linearInput[held],
	_ :> text
}]

(* the form before a \`: the symbol a name names, else its boxes *)
linearForm::usage = "linearForm[pieces] gives the form the pieces before a \\` name."
linearForm[pieces_List] := With[{boxes = linearRow[pieces]},
	If[StringQ[boxes] && StringMatchQ[boxes, (LetterCharacter | "$") ~~ (WordCharacter | "$" | "`") ...],
		Replace[WolframLanguageHeld[boxes], {{HoldComplete[x_Symbol]} :> linearInput[HoldComplete[x]], _ :> boxes}],
		boxes
	]
]

(* the boxes of a row's pieces: its box operators folded, inside each bracket first, then the rest *)
linearRow::usage = "linearRow[pieces] gives the boxes of the row of the pieces."
linearRow[pieces_List] := linearPlain @ linearFoldBrackets @ Catenate[linearRowTokens /@ pieces]

linearRowTokens::usage = "linearRowTokens[piece] gives the tokens of a text piece, and any other piece itself."
linearRowTokens[{"Text", text_String}] := linearTextTokens[text]
linearRowTokens[piece_List] := {piece}

(* the tokens of a row's text, {"Tok", text, kind, the whitespace before it}, by the lexer *)
linearTextTokens::usage = "linearTextTokens[t] gives the tokens of the text t, {\"Tok\", text, kind, the whitespace before it}."
linearTextTokens[t_String] := With[{codes = ToCharacterCode[t]},
	textTokens[t, codes, lexedCodes[paddedCodes[codes]]]
]

textTokens::usage = "textTokens[t, codes, lexed] gives the tokens of the text t of the codes, by the lexer's tokens lexed of them."
textTokens[t_String, _List, lexed_List] /; lexerStatus[lexed] =!= 0 := If[StringTrim[t] === "", {}, {{"Tok", StringTrim[t], 1, If[StringStartsQ[t, " "], " ", ""]}}]
textTokens[_String, codes_List, lexed_List] := Table[
	{
		"Tok",
		FromCharacterCode @ Take[codes, {tokenStart[lexed, t], tokenEnd[lexed, t] - 1}],
		tokenKind[lexed, t],
		FromCharacterCode @ Take[codes, {If[t === 1, 1, tokenEnd[lexed, t - 1]], tokenStart[lexed, t] - 1}]
	},
	{t, tokenCount[lexed] - 1}
]

(* the kinds of token that open and close a bracket, and those of an atom *)
$linearOpenKinds = {10, 12, 14, 16}
$linearCloseKinds = {11, 13, 15, 17}
$linearAtomKinds = {1, 2, 3, 4, 5, 6, 7, 8, 19}

(* a token that may be a prefix operator *)
linearPrefixQ::usage = "linearPrefixQ[token] is True for a token that may be a prefix operator."
linearPrefixQ[{"Tok", t_String, 9, _String}] := MemberQ[{"-", "+", "!", "++", "--"}, t]
linearPrefixQ[_] := False

linearOpenerQ::usage = "linearOpenerQ[token] is True for a token that opens a bracket."
linearOpenerQ[{"Tok", _String, kind_Integer, _String}] := MemberQ[$linearOpenKinds, kind]
linearOpenerQ[_] := False

linearCloserQ::usage = "linearCloserQ[token] is True for a token that closes a bracket."
linearCloserQ[{"Tok", _String, kind_Integer, _String}] := MemberQ[$linearCloseKinds, kind]
linearCloserQ[_] := False

(* where the bracket that token i of ts opens closes, or the last token *)
linearClose::usage = "linearClose[ts, i] gives the token of ts that closes the bracket token i opens, or the last token."
linearClose[ts_List, i_Integer] := Replace[
	FirstPosition[Accumulate[Boole[linearOpenerQ[#]] - Boole[linearCloserQ[#]] & /@ Drop[ts, i - 1]], 0, {Length[ts] - i + 1}],
	{k_Integer} :> i + k - 1
]

(* the last token of the operand a box operator takes from token i on, prefixes before it where
	they may be: an atom, a bracketed group or a box, then the brackets of its call; i - 1 where
	none begins there *)
linearPrimaryEnd::usage = "linearPrimaryEnd[ts, i, prefixes] gives the last token of the operand that begins at token i of ts, prefix \
operators before it where prefixes is True, or i - 1 where none does."
linearPrimaryEnd[ts_List, start_Integer, prefixes_ : False] := With[
	{first = If[TrueQ[prefixes], start + LengthWhile[Drop[ts, start - 1], linearPrefixQ], start]},
	Replace[linearOperandEnd[ts, first], {None :> start - 1, end_Integer :> linearCallsEnd[ts, end]}]
]

linearOperandEnd::usage = "linearOperandEnd[ts, i] gives the last token of the atom, the bracketed group or the box at token i of ts, or \
None."
linearOperandEnd[ts_List, i_Integer] /; i > Length[ts] := None
linearOperandEnd[ts_List, i_Integer] /; MatchQ[ts[[i]], {"Box", _}] := i
linearOperandEnd[ts_List, i_Integer] /; MatchQ[ts[[i]], {"Tok", _String, kind_Integer /; MemberQ[$linearAtomKinds, kind], _String}] :=
	NestWhile[# + 1 &, i, atomGoesOnQ[ts, #] &]
linearOperandEnd[ts_List, i_Integer] /; MatchQ[ts[[i]], {"Tok", _String, 10 | 14 | 16, _String}] := linearClose[ts, i]
linearOperandEnd[_List, _Integer] := None

atomGoesOnQ::usage = "atomGoesOnQ[ts, i] is True where the atom that token i of ts ends goes on with the name or the blank that touches it."
atomGoesOnQ[ts_List, i_Integer] := And[
	i < Length[ts],
	MatchQ[ts[[i + 1]], {"Tok", _String, 1 | 2, ""}],
	!MatchQ[ts[[i]], {"Tok", _String, 3 | 4, _String}]
]

linearCallsEnd::usage = "linearCallsEnd[ts, end] gives the last token of the brackets of the calls after token end of ts, or end."
linearCallsEnd[ts_List, end_Integer] := NestWhile[
	linearClose[ts, # + 1] &,
	end,
	# < Length[ts] && MatchQ[ts[[# + 1]], {"Tok", _String, 12, _String}] &
]

(* the box operators inside each bracket folded, then those around them *)
linearFoldBrackets::usage = "linearFoldBrackets[ts] gives the tokens and boxes of ts, the box operators inside each bracket folded, then \
those around them."
linearFoldBrackets[ts_List] := linearFold @ Catenate @ Reverse @ linkedItems @ Last @ NestWhile[
	bracketsStep[ts, #] &,
	{1, {}},
	First[#] <= Length[ts] &
]

bracketsStep::usage = "bracketsStep[ts, {i, parts}] gives the place after token i of ts, a bracket's whole, and the parts read, a linked \
list, with its own."
bracketsStep[ts_List, {i_Integer, parts_List}] /; linearOpenerQ[ts[[i]]] := With[{j = linearClose[ts, i]},
	{j + 1, {Prepend[bracketInside[ts, i, j], ts[[i]]], parts}}
]
bracketsStep[ts_List, {i_Integer, parts_List}] := {i + 1, {{ts[[i]]}, parts}}

bracketInside::usage = "bracketInside[ts, i, j] gives the tokens of the bracket from token i to token j of ts after its opener, folded."
bracketInside[ts_List, i_Integer, j_Integer] /; j > i && linearCloserQ[ts[[j]]] := Append[linearFoldBrackets[Take[ts, {i + 1, j - 1}]], ts[[j]]]
bracketInside[ts_List, i_Integer, j_Integer] := linearFoldBrackets[Take[ts, {i + 1, j}]]

(* The box operators of a row folded into the boxes they build, by precedence: \& and \+ the
	tightest, then \_, \^, the prefix \@ and, the loosest, \/. The scripts and \@ read to the
	right, \/ to the left; \% gives the third box of the script or root before it. Each reader takes
	the tokens and a place and gives {the boxes it reads, the place after them}. *)
linearFold::usage = "linearFold[ts] gives the tokens and boxes of the row ts, its box operators folded into the boxes they build."
linearFold[ts_List] := Reverse @ linkedItems @ Last @ NestWhile[foldStep[ts, #] &, {1, {}}, First[#] <= Length[ts] &]

foldStep::usage = "foldStep[ts, {i, items}] gives the place after the token, or the boxes of the operators, at token i of ts, and the \
items read, a linked list, with them."
foldStep[ts_List, {i_Integer, items_List}] /; boxOperatorAtQ[ts, i] := With[{read = linearFraction[ts, i]},
	{Max[Last[read], i + 1], {{"Box", First[read]}, items}}
]
foldStep[ts_List, {i_Integer, items_List}] := {i + 1, {ts[[i]], items}}

boxOperatorAtQ::usage = "boxOperatorAtQ[ts, i] is True where a box operator's boxes begin at token i of ts."
boxOperatorAtQ[ts_List, i_Integer] := Or[
	MatchQ[ts[[i]], {"Op", _}],
	i < Length[ts] && MatchQ[ts[[i]], {"Tok", _String, 9, _String}] && MatchQ[ts[[i + 1]], {"Op", _}],
	!linearPrefixQ[ts[[i]]] && With[{end = linearPrimaryEnd[ts, i]}, end >= i && end < Length[ts] && MatchQ[ts[[end + 1]], {"Op", _}]]
]

linearOpQ::usage = "linearOpQ[ts, i, o] is True where token i of ts is the box operator o."
linearOpQ[ts_List, i_Integer, o_String] := i <= Length[ts] && ts[[i]] === {"Op", o}

linearOperand::usage = "linearOperand[ts, i] gives the operand of a box operator at token i of ts: its boxes, an operator's text, or \
\"\" for none."
linearOperand[ts_List, i_Integer] := With[{end = linearPrimaryEnd[ts, i, True]},
	Which[
		end >= i,
			{linearPlain[Take[ts, {i, end}]], end + 1},
		i <= Length[ts] && MatchQ[ts[[i]], {"Tok", _String, 9, _String}],
			{linearLeaf[ts[[i, 2]]], i + 1},
		True,
			{"", i}
	]
]

linearScript::usage = "linearScript[ts, i] gives an operand with the over- and underscripts after it."
linearScript[ts_List, i_Integer] := scriptAfter[ts, linearOperand[ts, i]]

scriptAfter::usage = "scriptAfter[ts, {b, i}] gives the boxes b with the \\& or \\+ script at token i of ts, and its \\% limit."
scriptAfter[ts_List, {b_, i_Integer}] /; linearOpQ[ts, i, "&"] || linearOpQ[ts, i, "+"] := scriptLimits[ts, b, ts[[i, 2]], linearScript[ts, i + 1]]
scriptAfter[_List, read_List] := read

scriptLimits::usage = "scriptLimits[ts, b, k, {x, i}] gives the boxes b with the script x of the operator k, \\& over and \\+ under, and \
the \\% one at token i of ts on the other side."
scriptLimits[ts_List, b_, k_String, {x_, i_Integer}] /; linearOpQ[ts, i, "%"] := With[{y = linearScript[ts, i + 1]},
	{If[k === "&", UnderoverscriptBox[b, First[y], x], UnderoverscriptBox[b, x, First[y]]], Last[y]}
]
scriptLimits[_List, b_, k_String, {x_, i_Integer}] := {If[k === "&", OverscriptBox[b, x], UnderscriptBox[b, x]], i}

linearSub::usage = "linearSub[ts, i] gives a script with the subscripts after it."
linearSub[ts_List, i_Integer] := subAfter[ts, linearScript[ts, i]]

subAfter::usage = "subAfter[ts, {b, i}] gives the boxes b with the \\_ subscript at token i of ts, and its \\% superscript."
subAfter[ts_List, {b_, i_Integer}] /; linearOpQ[ts, i, "_"] := subLimits[ts, b, linearSub[ts, i + 1]]
subAfter[_List, read_List] := read

subLimits::usage = "subLimits[ts, b, {x, i}] gives the boxes b with the subscript x and the \\% superscript at token i of ts."
subLimits[ts_List, b_, {x_, i_Integer}] /; linearOpQ[ts, i, "%"] := With[{y = linearSub[ts, i + 1]}, {SubsuperscriptBox[b, x, First[y]], Last[y]}]
subLimits[_List, b_, {x_, i_Integer}] := {SubscriptBox[b, x], i}

linearSup::usage = "linearSup[ts, i] gives a subscript with the superscript after it."
linearSup[ts_List, i_Integer] := supAfter[ts, linearSub[ts, i]]

supAfter::usage = "supAfter[ts, {b, i}] gives the boxes b with the \\^ superscript at token i of ts."
supAfter[ts_List, {b_, i_Integer}] /; linearOpQ[ts, i, "^"] := With[{x = linearRoot[ts, i + 1]}, {SuperscriptBox[b, First[x]], Last[x]}]
supAfter[_List, read_List] := read

linearRoot::usage = "linearRoot[ts, i] gives the root of a \\@ at token i of ts, else a superscript."
linearRoot[ts_List, i_Integer] /; linearOpQ[ts, i, "@"] := rootAfter[ts, linearRoot[ts, i + 1]]
linearRoot[ts_List, i_Integer] := linearSup[ts, i]

rootAfter::usage = "rootAfter[ts, {x, i}] gives the square root of x, or its root of the \\% index at token i of ts."
rootAfter[ts_List, {x_, i_Integer}] /; linearOpQ[ts, i, "%"] := With[{index = linearRoot[ts, i + 1]}, {RadicalBox[x, First[index]], Last[index]}]
rootAfter[_List, {x_, i_Integer}] := {SqrtBox[x], i}

linearFraction::usage = "linearFraction[ts, i] gives the roots from token i of ts, each \\/ between them a fraction, read to the left."
linearFraction[ts_List, i_Integer] := NestWhile[fractionStep[ts, #] &, linearRoot[ts, i], linearOpQ[ts, Last[#], "/"] &]

fractionStep::usage = "fractionStep[ts, {b, i}] gives the fraction of b over the root after the \\/ at token i of ts."
fractionStep[ts_List, {b_, i_Integer}] := With[{denominator = linearRoot[ts, i + 1]}, {FractionBox[b, First[denominator]], Last[denominator]}]

(* the boxes of a row with no box operator left: its concrete syntax tree, the box of each name
	that stands for one in its place *)
linearPlain::usage = "linearPlain[ts] gives the boxes of the tokens and boxes ts, a row with no box operator left."
linearPlain[{}] := ""
linearPlain[{{"Box", boxes_}}] := boxes
linearPlain[ts_List] := With[{keys = MapIndexed[linearKey, ts]},
	{boxes = Association[Cases[Transpose[{keys, ts}], {key_String, {"Box", b_}} :> key -> b]]},
	linearItems @ DeleteCases[
		linearCST[#, boxes] & /@ Replace[WolframLanguageConcrete[StringJoin[MapThread[linearText, {keys, ts}]]], CodeParser`ContainerNode[_, children_, _] :> children],
		Nothing
	]
]

linearKey::usage = "linearKey[item, {i}] gives the name that stands for the box item i of a row in its text, None for a token."
linearKey[{"Box", _}, {i_Integer}] := "zzLinearBox" <> ToString[i] <> "zz"
linearKey[_, _] := None

linearText::usage = "linearText[key, item] gives the text of an item of a row: a box's name, a token's whitespace and text."
linearText[key_String, _] := " " <> key <> " "
linearText[None, {"Tok", t_String, _Integer, before_String}] := before <> t

linearItems::usage = "linearItems[items] gives the boxes of a row's items: \"\" for none, one alone, more in a RowBox."
linearItems[{}] := ""
linearItems[{one_}] := one
linearItems[items_List] := RowBox[items]

(* a node of a concrete syntax tree as boxes: a call's brackets in its row, a pattern's or a slot's
	leaves one string, whitespace other than spaces, tabs and newlines kept *)
linearCST[CodeParser`LeafNode[kind_, t_String, _], boxes_] := Which[
	(MatchQ[kind, Whitespace | Token`Newline | Token`Comment] && StringMatchQ[t, (" " | "\t" | "\n" | "\r") ...]) ||
		StringStartsQ[ToString[kind], "Token`Fake`"] || t === "", Nothing,
	KeyExistsQ[boxes, t], boxes[t],
	True, linearLeaf[t]]
linearCST[CodeParser`CompoundNode[_, children_List, _], boxes_] := With[{parts = linearCST[#, boxes] & /@ children},
	If[AllTrue[parts, StringQ], StringJoin[parts], RowBox[parts]]]
linearCST[CodeParser`CallNode[{head_}, CodeParser`GroupNode[_, children_List, _], _], boxes_] :=
	RowBox[DeleteCases[Prepend[linearCST[#, boxes] & /@ children, linearCST[head, boxes]], Nothing]]
linearCST[_[_, children_List, _], boxes_] := With[{items = DeleteCases[linearCST[#, boxes] & /@ children, Nothing]},
	Which[items === {}, Nothing, Length[items] === 1, items[[1]], True, RowBox[items]]]

(* a token's text as a box: its long names their characters, <| and |> theirs *)
linearLeaf["<|"] = "\[LeftAssociation]"
linearLeaf["|>"] = "\[RightAssociation]"
linearLeaf[t_String] := If[StringFreeQ[t, "\\["], t,
	StringReplace[t, "\\[" ~~ name : (LetterCharacter | DigitCharacter) .. ~~ "]" /; KeyExistsQ[longNameCharacters[], name] :> longNameCharacters[][name]]]

(* the file a name of << or >> gives: its long names and its \: and \.
	escapes decoded, another \ kept *)
fileValue[s_String] := If[StringFreeQ[s, "\\"], s, StringReplace[s, {
	"\\." ~~ digits : Repeated[HexadecimalCharacter, {2}] :> FromCharacterCode[FromDigits[digits, 16]],
	"\\:" ~~ digits : Repeated[HexadecimalCharacter, {4}] :> FromCharacterCode[FromDigits[digits, 16]],
	"\\[" ~~ name : (LetterCharacter | DigitCharacter) .. ~~ "]" /; KeyExistsQ[longNameCharacters[], name] :> longNameCharacters[][name]}]]

expressions[xs_List] := Map[#["Expr"] &, xs]


(* ::Section:: *)
(*Long names the held grammar reads*)

(* the long-name operators of no ASCII operator's spellings: the infix ones
	but the invisible comma, which is a comma, and the prefix ones but the
	integrals, which are units of their own *)
$heldLongInfix := $heldLongInfix = Select[$longNameTable["Infix"], ! KeyExistsQ[$asciiLongNames, #[[1]]] && #[[3]] =!= CodeParser`Comma &]
$heldLongPrefix := $heldLongPrefix = Select[$longNameTable["Prefix"],
	! KeyExistsQ[$asciiLongNames, #[[1]]] && ! MemberQ[$longNameTable["Integrals"][[All, 1]], #[[1]]] &]
$integralPrecedence := $integralPrecedence = First[Cases[$longNameTable["Prefix"], {"Integral", _, _, p_Integer, _} :> p]]

(* the head the kernel gives a long-name operator: its tag's, a relation's
	the kernel's symbol for it, and \[HermitianConjugate] ConjugateTranspose *)
heldLongHead[row_List] := Which[
	row[[3]] === CodeParser`InfixInequality, Lookup[$relationHeads, row[[1]], row[[1]]],
	row[[1]] === "HermitianConjugate", "ConjugateTranspose",
	True, SymbolName[row[[3]]]]
$relationHeads = <|"NotEqual" -> "Unequal", "LessSlantEqual" -> "LessEqual", "GreaterSlantEqual" -> "GreaterEqual",
	"Equal" -> "Equal", "LongEqual" -> "Equal"|>

(* An integral as a notebook reads it: k signs of one kind, as \[Integral]\[Integral], and an operand
	whose factors end in k differentials, \[DifferentialD] x or \[CapitalDifferentialD] x, no other
	factor one and none in parentheses: head of the factors before them, 1 where there are none, and
	the k variables, the last first, so \[Integral]\[Integral] f \[DifferentialD]x \[DifferentialD]y
	is Integrate[f, y, x] and \[ContourIntegral] f \[DifferentialD]x ContourIntegral[f, x]; any other
	operand is no Wolfram Language. Held, from the expression, a product's differentials marked; as
	nodes, the standard tree's, of each sign in turn, of a Times node whose last operand is a
	differential's, which the call keeps. *)
integrandQ[k_Integer, f_Association] := Which[
	MatchQ[f["Expr"], HoldComplete[_?differentialHeadQ[_]]], k === 1,
	KeyExistsQ[f, "Differentials"], With[{d = f["Differentials"]}, With[{n = LengthWhile[Reverse[d], TrueQ]}, n === k && FreeQ[Drop[d, -n], True]]],
	True, False]
integrandQ[_Integer, _] := True
integralOf[alg_, head_String, f_Association, k_Integer] := held[integralHeld[head, f["Expr"], k]]
integralOf[alg_, head_String, f_, k_Integer] := Nest[integralNode[alg, head, #] &, f, k]
integralHeld[head_String, e_HoldComplete, k_Integer] := With[{factors = Replace[e, {
		HoldComplete[t_[fs___]] /; MatchQ[Unevaluated[t], Times] :> List @@ (HoldComplete /@ HoldComplete[fs]),
		_ :> {e}}]},
	With[{rest = Drop[factors, -k], vars = Replace[Take[factors, -k], HoldComplete[_[x_]] :> HoldComplete[x], {1}]},
		symbolCall[head, Join[{Switch[Length[rest], 0, HoldComplete[1], 1, First[rest], _, symbolCall["Times", rest]]}, Reverse[vars]]]]]
integralNode[alg_, head_String, f_] := Replace[f, {
	PrefixNode["DifferentialD" | "CapitalDifferentialD", _, _] :> alg["Call"][alg["Leaf"]["Symbol", "Integrate"], {alg["Leaf"]["Integer", "1"], f}],
	InfixNode["Times", {g__, d : PrefixNode["DifferentialD" | "CapitalDifferentialD", _, _]}, _] :>
		alg["Call"][alg["Leaf"]["Symbol", "Integrate"], {Replace[{g}, {{one_} :> one, factors_ :> alg["Infix"]["Times", factors]}], d}],
	_ :> alg["Prefix"][If[head === "Integrate", "Integral", head], f]}]

SetAttributes[differentialHeadQ, HoldFirst]
differentialHeadQ[d_] := MatchQ[Unevaluated[d], DifferentialD | CapitalDifferentialD]

(* A chain of relations as the kernel reads it: one of a single relation
	that relation of the operands, of the vector ones of their list; one of
	several Inequality, or VectorInequality once a vector relation is among
	them, a chain of relations of the one kind and then of the other made
	one operand of what follows. *)
$vectorRelations = <|"VectorLess" -> True, "VectorGreater" -> True, "VectorLessEqual" -> True, "VectorGreaterEqual" -> True|>
$neutralRelations = <|"Equal" -> True, "Unequal" -> True, "Less" -> True, "Greater" -> True, "LessEqual" -> True, "GreaterEqual" -> True|>
vectorAffinity[head_String] := Which[KeyExistsQ[$vectorRelations, head], True, KeyExistsQ[$neutralRelations, head], None, True, False]

relationValue[alg_, operands_List, heads_List] := Module[{processed = {First[operands]}, affinity = None, a},
	Do[
		a = vectorAffinity[heads[[i]]];
		If[ a =!= None && affinity =!= None && a =!= affinity,
			processed = {simplifiedRelation[alg, processed, affinity], heads[[i]], operands[[i + 1]]},
			processed = Join[processed, {heads[[i]], operands[[i + 1]]}]];
		If[a =!= None, affinity = a],
		{i, Length[heads]}];
	simplifiedRelation[alg, processed, affinity]]

simplifiedRelation[alg_, processed_List, affinity_] := With[{rators = processed[[2 ;; -2 ;; 2]], rands = processed[[1 ;; -1 ;; 2]]},
	Which[
		Length[Union[rators]] === 1 && KeyExistsQ[$vectorRelations, First[rators]],
			alg["Call"][alg["Leaf"]["Symbol", First[rators]], {alg["Group"]["List", rands]}],
		Length[Union[rators]] === 1, alg["Infix"][First[rators], rands],
		affinity === True,
			alg["Call"][alg["Leaf"]["Symbol", "Developer`VectorInequality"], Riffle[rands, alg["Leaf"]["Symbol", #] & /@ rators]],
		True, alg["Infix"]["Inequality", Riffle[rands, alg["Leaf"]["Symbol", #] & /@ rators]]]]

(* a/b is Times[a, Power[b, -1]] *)
binaryHeld["Divide", l_, r_] := symbolCall["Times", {l, symbolCall["Power", {r, HoldComplete[-1]}]}]
binaryHeld[op_String, l_, r_] := symbolCall[op, {l, r}]

WolframLanguageSemantic = <|
	"Leaf"    -> Function[{kind, s}, heldLeaf[kind, s]],
	(* a unary plus stays a call of Plus, as a notebook reads it *)
	"Prefix"  -> Function[{op, x}, If[op === "Minus", held[negated[x]], held[symbolCall[op, {x["Expr"]}]]]],
	"Postfix" -> Function[{x, op}, held[symbolCall[op, {x["Expr"]}]]],
	"Binary"  -> Function[{op, l, r}, held[binaryHeld[op, l["Expr"], r["Expr"]]]],
	(* a product marks which of its factors are differentials, none in parentheses, for an integral *)
	"Infix"   -> Function[{op, xs}, If[op === "Times",
		Append[held[symbolCall[op, expressions[xs]]], "Differentials" -> Map[! TrueQ[#["Paren"]] && MatchQ[#["Expr"], HoldComplete[_?differentialHeadQ[_]]] &, xs]],
		held[symbolCall[op, expressions[xs]]]]],
	"Ternary" -> Function[{op, a, b, c}, held[symbolCall[op, expressions[{a, b, c}]]]],
	"Call"    -> Function[{h, args}, held[heldCall[h["Expr"], expressions[args]]]],
	(* parentheses make a number literal no longer one, so that -(2) is Times[-1, 2], as a notebook
		reads it *)
	"Group"   -> Function[{kind, xs}, If[kind === "Paren",
		Append[First[xs], {"Literal" -> False, "Paren" -> True}],
		held[symbolCall[kind, expressions[xs]]]]]
|>

(* ::Section:: *)
(*The concrete syntax tree*)

(* The tree CodeParser`CodeConcreteParse gives: CodeParser's nodes, each
	operator named by its tag and its token, and every character of the
	source in a leaf, whitespace, newlines and comments among them. Trivia
	sits in the smallest node around it. A value read here is item[node,
	the trivia after it]; a node made of values holds each one's trivia
	after it, but for the last's, which follows the node. A token for what
	was left out (Token`Fake`ImplicitNull, ...) comes after the trivia
	before it.

	What is not Wolfram Language reads as CodeParser reads it, and nothing
	fails: an operand left out is Token`Error`ExpectedOperand, a group not
	closed a GroupMissingCloserNode, a closer that closes no group around it
	Token`Error`UnexpectedCloser, text that is no token an ErrorNode of the
	kind CodeParser gives it, and a ~ without its second ~, a /: without its
	= and a : after what is neither a name nor a pattern a SyntaxErrorNode.
	An error token is the whole of an expression it begins. *)

kids[item[node_, trivia_List]] := Prepend[trivia, node]

(* head[tag, children], the node of the value last its last child *)
concreteNode[head_, tag_, children_List, item[node_, trivia_List]] := item[head[tag, Append[children, node], <||>], trivia]

(* first, then each step[gap, operator, operand]: the trivia before the
	operator that its operand's own does not cover, the operator's leaves,
	the operand *)
stepsItem[head_, tag_, first_item, steps_List] := With[{n = Length[steps]},
	concreteNode[head, tag,
		Join[kids[first], Catenate[Table[Join[steps[[i, 1]], steps[[i, 2]], If[i < n, kids[steps[[i, 3]]], {}]], {i, n}]]],
		steps[[n, 3]]]]

concreteLeaf[kind_, s_String] := CodeParser`LeafNode[kind, s, <||>]

implicitItem[token_] := item[concreteLeaf[token, ""], {}]

errorItem[token_] := item[CodeParser`ErrorNode[token, "", <||>], {}]

errorTokenItem[token_, s_String, trivia_List] := item[CodeParser`ErrorNode[token, s, <||>], trivia]

(* an error token of the source, which no operator takes for its left operand *)
finalOperandQ[item[node_, _]] := errorTokenQ[node]
finalOperandQ[_] := False

errorTokenQ[CodeParser`ErrorNode[token_, _, _]] := ! MatchQ[token, Token`Error`ExpectedOperand | Token`Error`PrefixImplicitNull]
errorTokenQ[_] := False

(* commas after an error token, which takes none *)
commaAfterErrorQ[item[CodeParser`InfixNode[CodeParser`Comma, {first_, ___}, _], _]] := errorTokenQ[first]
commaAfterErrorQ[_] := False

(* CodeParser names a token by its characters, -> Token`MinusGreater, and
	a long name or its character by the name, Token`LongName`Rule *)
$tokenCharacterNames = <|
	"+" -> "Plus", "-" -> "Minus", "*" -> "Star", "/" -> "Slash", "^" -> "Caret", "<" -> "Less", ">" -> "Greater",
	"=" -> "Equal", ":" -> "Colon", ";" -> "Semi", "." -> "Dot", "!" -> "Bang", "@" -> "At", "|" -> "Bar", "&" -> "Amp",
	"?" -> "Question", "~" -> "Tilde", "'" -> "SingleQuote", "_" -> "Under", "#" -> "Hash", "%" -> "Percent", "," -> "Comma",
	"[" -> "OpenSquare", "]" -> "CloseSquare", "{" -> "OpenCurly", "}" -> "CloseCurly", "(" -> "OpenParen", ")" -> "CloseParen"
|>

tokenSymbol[s_String] := tokenSymbol[s] = Symbol["Token`" <> Which[
	StringStartsQ[s, "\\["], "LongName`" <> StringTake[s, {3, -2}],
	StringLength[s] === 1 && ! KeyExistsQ[$tokenCharacterNames, s], "LongName`" <> CharacterName[s],
	True, StringJoin[Lookup[$tokenCharacterNames, Characters[s]]]]]

tokenLeaf[s_String] := concreteLeaf[tokenSymbol[s], s]

(* the long names of ASCII operators, which their specs read *)
$asciiLongNames := $asciiLongNames = AssociationThread[StringTake[$operatorLongNames, {3, -2}] -> True]

(* =. is = then ., trivia between; ?? is a token of its own *)
$concreteSpellings = Append[DeleteCases[$operatorSpellings, "=."], "??"]

(* a . or a ` makes a real, an exponent below 0 on an integer a rational *)
concreteNumberKind[s_String] := Which[StringContainsQ[s, "." | "`"], Real, StringContainsQ[s, "*^-"], Rational, True, Integer]

(* ::Section:: *)
(*Concrete tokens*)

$languagesDirectory = DirectoryName[$InputFileName]

(* The long names of the Wolfram Language, as CodeParser lists them
	(Resources/Generated/LongNames.wl of the CodeParser paclet,
	github.com/WolframResearch/codeparser, MIT), read at their first use. *)
$longNames := $longNames = Association[Thread[DeleteCases[Get[FileNameJoin[{$languagesDirectory, "LongNames.wl"}]], Nothing] -> True]]

(* How CodeParser reads each long name that is not a letter
	(Languages/LongNameOperators.wl, recorded from Wolfram 15 by
	dev/freeze-longnames.wls), read at its first use: the operators, the
	brackets, the integrals, whitespace, newlines and the tokens it does not
	read. *)
$longNameTable := $longNameTable = Get[FileNameJoin[{$languagesDirectory, "LongNameOperators.wl"}]]

(* a long name's spellings: \[Name], and its character *)
longNameSpellings[name_String] := DeleteMissing[{"\\[" <> name <> "]", Lookup[$longNameTable["Characters"], name, Missing[]]}]

$nonLetterNames := $nonLetterNames = AssociationThread[Union[StringTake[$operatorLongNames, {3, -2}],
	Catenate[Lookup[$longNameTable, {"Infix", "Prefix", "Postfix"}]][[All, 1]], Flatten[$longNameTable["Groups"][[All, {1, 2}]]],
	$longNameTable["Integrals"][[All, 1]], $longNameTable["Whitespace"], $longNameTable["Newlines"], $longNameTable["Unsupported"]] -> True]
$nonLetterCharacters := $nonLetterCharacters = AssociationThread[Union[$operatorCharacters,
	DeleteMissing[Lookup[$longNameTable["Characters"], Keys[$nonLetterNames], Missing[]]]] -> True]

(* a long name that is a letter: the language's, and none of those *)
letterNameQ[s_String] := With[{n = StringTake[s, {3, -2}]}, KeyExistsQ[$longNames, n] && ! KeyExistsQ[$nonLetterNames, n]]

(* a character past ASCII that is a letter: no operator's, bracket's or whitespace's *)
concreteNameCharacterQ[c_String] := nameCharacterQ[c] && ! KeyExistsQ[$nonLetterCharacters, c]

(* a letter past ASCII: a long name that is one, or a character past
	ASCII that is not an operator's nor whitespace *)
$concreteLetter = ParseChoice[
	ParseAction[ParseLookahead[ParseLiteral["\\["]] ~~ ParseCondition[ParseRegex["\\\\\\[[A-Za-z0-9]+]"], letterNameQ], #2 &],
	ParseCharacter[_?concreteNameCharacterQ]]

(* A name: parts of letters, digits and $, each beginning with a letter or
	$, joined by single `s, a ` before the first naming a context relative
	to the current one: a`b, `a. The loop after the first run of ASCII is
	entered only at a letter past ASCII or a `. *)
nameMoreQ[c_String] := c === "\\" || c === "`" || First[ToCharacterCode[c]] > 127
$namePartStart = ParseChoice[ParseRegex["[A-Za-z$]"], $concreteLetter]
$concreteName = text[
	ParseChoice[
		ParseRegex["[A-Za-z$][A-Za-z0-9$]*(`[A-Za-z$][A-Za-z0-9$]*)*"],
		ParseRegex["`[A-Za-z$][A-Za-z0-9$]*(`[A-Za-z$][A-Za-z0-9$]*)*"],
		ParseOptional[ParseLiteral["`"]] ~~ $concreteLetter ~~ ParseRegex["[A-Za-z0-9$]*"]] ~~
	ParseMany[ParseAction[ParseLookahead[ParseCharacter[_?nameMoreQ]] ~~
		ParseChoice[$concreteLetter ~~ ParseRegex["[A-Za-z0-9$]*"], ParseLiteral["`"] ~~ $namePartStart ~~ ParseRegex["[A-Za-z0-9$]*"]], #2 &]]]

(* a name with a ` after it that no part follows: CodeParser's
	Token`Error`ExpectedLetterlike, up to the ` *)
$letterlikeError = text[ParseOptional[$concreteName] ~~ ParseLiteral["`"] ~~ ParseNotFollowedBy[$namePartStart]]

(* A number's text, as far as a number could go: digits, or b^^digits, a
	fraction, then a precision or accuracy and an exponent. *)
$signedDigits = ParseOptional[ParseCharacter["-" | "+"]] ~~ ParseChoice[
	$digits ~~ ParseOptional[ParseLiteral["."] ~~ ParseOptional[$digits]],
	ParseLiteral["."] ~~ $digits]
$numberText = text[
	ParseChoice[
		$digits ~~ ParseOptional[ParseChoice[
			ParseLiteral["^^"] ~~ ParseRegex["[0-9a-zA-Z]*"] ~~ ParseOptional[ParseLiteral["."] ~~ ParseNotFollowedBy[ParseLiteral["."]] ~~ ParseRegex["[0-9a-zA-Z]*"]],
			ParseLiteral["."] ~~ ParseNotFollowedBy[ParseLiteral["."]] ~~ ParseOptional[$digits]]],
		ParseLiteral["."] ~~ $digits]
	~~ ParseOptional[ParseLiteral["`"] ~~ ParseOptional[ParseLiteral["`"]] ~~ ParseOptional[$signedDigits]]
	~~ ParseOptional[ParseLiteral["*^"] ~~ ParseOptional[ParseOptional[ParseCharacter["-" | "+"]] ~~ $digits]]]

(* A number's text is CodeParser's Token`Error`Number where its base is
	not 2 to 36, a digit is not one of the base's, or a ^^, a `` or a *^ has
	nothing after it. *)
numberTextValidQ[s_String] := Module[{body = s, parts, base},
	If[ StringContainsQ[body, "*^"],
		parts = StringSplit[body, "*^", All];
		If[ ! StringMatchQ[Last[parts], RegularExpression["[-+]?[0-9]+"]], Return[False, Module]];
		body = First[parts]];
	If[ StringContainsQ[body, "``"] && Last[StringSplit[body, "``", All]] === "", Return[False, Module]];
	body = First[StringSplit[body, "`", All]];
	If[ StringContainsQ[body, "^^"],
		parts = StringSplit[body, "^^", All];
		base = FromDigits[First[parts]];
		If[ ! (2 <= base <= 36) || StringDelete[Last[parts], "."] === "", Return[False, Module]];
		If[ ! AllTrue[Characters[ToLowerCase[StringDelete[Last[parts], "."]]], digitValue[#] < base &], Return[False, Module]]];
	True]

digitValue[c_String] := With[{n = First[ToCharacterCode[c]]}, If[n <= 57, n - 48, n - 87]]

(* a string or a comment the source does not close: the rest of the source *)
$unterminatedString = ParseRegex["\"(?s:.*)"]
$unterminatedComment = ParseRegex["\\(\\*(?s:.*)"]

(* a \ that begins no letter: a long name not the language's, a \[ not
	closed, a \: \. \| short of its digits, or a \ and the character after
	it, none at the end: CodeParser's Token`Error`UnhandledCharacter *)
$unhandledCharacter = text[ParseChoice[
	ParseCondition[ParseRegex["\\\\\\[[A-Za-z0-9]+]"], ! KeyExistsQ[$longNames, StringTake[#, {3, -2}]] &],
	ParseLiteral["\\["] ~~ ParseRegex["[A-Za-z0-9]*"] ~~ ParseNotFollowedBy[ParseLiteral["]"]],
	ParseLiteral["\\:"] ~~ ParseRegex["[0-9a-fA-F]{0,3}"] ~~ ParseNotFollowedBy[ParseCharacter[HexadecimalCharacter]],
	ParseLiteral["\\."] ~~ ParseRegex["[0-9a-fA-F]?"] ~~ ParseNotFollowedBy[ParseCharacter[HexadecimalCharacter]],
	ParseLiteral["\\|"] ~~ ParseRegex["[0-9a-fA-F]{0,5}"] ~~ ParseNotFollowedBy[ParseCharacter[HexadecimalCharacter]],
	ParseLiteral["\\"] ~~ ParseNotFollowedBy[ParseCharacter["[" | ":" | "." | "|" | "\n" | "\r"]] ~~ ParseOptional[ParseCharacter[_]]]]

(* a character that can begin a leaf, and one that can begin a name *)
leafStartQ[c_String] := StringContainsQ["_#%{<(\"`$\\.0123456789", c] || nameStartQ[c] || KeyExistsQ[$prefixOnlyCharacters, c]
nameStartQ[c_String] := c === "$" || c === "`" || c === "\\" || StringMatchQ[c, LetterCharacter] || concreteNameCharacterQ[c]

(* the long names that begin an operand and are no operator after one: the
	prefix operators that are not infix too, the openers of brackets and the
	integrals; and the characters among their spellings *)
$prefixOnlyNames := $prefixOnlyNames = Union[
	Complement[$longNameTable["Prefix"][[All, 1]], $longNameTable["Infix"][[All, 1]]], $longNameTable["Groups"][[All, 1]], $longNameTable["Integrals"][[All, 1]]]
$prefixOnlyCharacters := $prefixOnlyCharacters = AssociationThread[DeleteMissing[Lookup[$longNameTable["Characters"], $prefixOnlyNames, Missing[]]] -> True]
prefixOnlyStartQ[c_String] := c === "\\" || KeyExistsQ[$prefixOnlyCharacters, c]
(* a character that can begin a long name: a \ or one past ASCII *)
longNameStartQ[c_String] := c === "\\" || First[ToCharacterCode[c]] > 127

(* the spellings of the closers, each to the label a group it closes has in the scope *)
$closerLabels := $closerLabels = Join[<|"]" -> "]", ")" -> ")", "}" -> "}", "|>" -> "|>"|>,
	Association[Catenate[Map[Function[c, Thread[longNameSpellings[c] -> c]], Union[$longNameTable["Groups"][[All, 2]]]]]]]
closerStartQ[c_String] := StringContainsQ["])}|\\", c] || KeyExistsQ[$closerLabels, c]

(* whitespace and newlines in long names, and their characters *)
$longWhitespace := $longWhitespace = Catenate[longNameSpellings /@ $longNameTable["Whitespace"]]
$longNewlines := $longNewlines = Catenate[longNameSpellings /@ $longNameTable["Newlines"]]
(* the long names the kernel reads as newlines, written out or as their characters: those
	CodeParser calls newlines but the two discretionary separators, which the kernel reads as
	no token *)
$heldNewlineNames := $heldNewlineNames = DeleteCases[$longNameTable["Newlines"], "DiscretionaryLineSeparator" | "DiscretionaryParagraphSeparator"]
$heldNewlines := $heldNewlines = Catenate[longNameSpellings /@ $heldNewlineNames]
$lineTriviaStarts := $lineTriviaStarts = AssociationThread[Union[{" ", "\t", "(", "\\"}, Select[$longWhitespace, StringLength[#] === 1 &]] -> True]
$allTriviaStarts := $allTriviaStarts = Join[$lineTriviaStarts, AssociationThread[Union[{"\n", "\r"}, Select[$longNewlines, StringLength[#] === 1 &]] -> True]]
lineTriviaStartQ[c_String] := KeyExistsQ[$lineTriviaStarts, c]
allTriviaStartQ[c_String] := KeyExistsQ[$allTriviaStarts, c]

(* a control character, which no token holds *)
strayCharacterQ[c_String] := With[{n = First[ToCharacterCode[c]]}, (n < 32 && ! MemberQ[{9, 10, 12, 13}, n]) || n === 127]

$blankHeads = <|"_" -> Blank, "__" -> BlankSequence, "___" -> BlankNullSequence|>
$patternBlankHeads = <|"_" -> CodeParser`PatternBlank, "__" -> CodeParser`PatternBlankSequence,
	"___" -> CodeParser`PatternBlankNullSequence, "_." -> CodeParser`PatternOptionalDefault|>

(* x_h: the name, the underscores, the head; _. takes no head *)
blankNode[name_, underscores_String, head_] := With[{blank = If[MissingQ[head],
		tokenLeaf[underscores],
		CodeParser`CompoundNode[$blankHeads[underscores], {tokenLeaf[underscores], concreteLeaf[Symbol, head]}, <||>]]},
	If[MissingQ[name], blank, CodeParser`CompoundNode[$patternBlankHeads[underscores], {concreteLeaf[Symbol, name], blank}, <||>]]]

(* what a : makes an Optional of: a pattern; after anything else but a
	name it is a SyntaxErrorNode *)
patternLikeQ[item[node_, _]] := MatchQ[node,
	CodeParser`CompoundNode[CodeParser`PatternBlank | CodeParser`PatternBlankSequence | CodeParser`PatternBlankNullSequence | Blank | BlankSequence | BlankNullSequence, _, _] |
	CodeParser`LeafNode[Token`Under | Token`UnderUnder | Token`UnderUnderUnder, _, _] |
	CodeParser`BinaryNode[Pattern, _, _]]

(* #, #2, #name, #"name", ##, ##2 *)
slotNode[hash_String, _Missing] := tokenLeaf[hash]
slotNode["#", s_String] := CodeParser`CompoundNode[Slot,
	{tokenLeaf["#"], concreteLeaf[If[StringMatchQ[s, DigitCharacter ..], Integer, String], s]}, <||>]
slotNode["##", s_String] := CodeParser`CompoundNode[SlotSequence, {tokenLeaf["##"], concreteLeaf[Integer, s]}, <||>]

(* %, %3; %% and more are one token *)
outNode["%", _Missing] := tokenLeaf["%"]
outNode["%", s_String] := CodeParser`CompoundNode[Out, {tokenLeaf["%"], concreteLeaf[Integer, s]}, <||>]

(* ::Section:: *)
(*Groups*)

(* A group closed: a GroupNode. One its source leaves open, at the end of
	the source or at the closer of a group around it: a
	GroupMissingCloserNode, the trivia after its last child outside it, and
	marked to be read again if it is open at the end. *)
groupItem[tag_, open_String, lead_List, children_List, {"Closed", close_String, trivia_List}] :=
	item[CodeParser`GroupNode[tag, Join[{tokenLeaf[open]}, lead, Catenate[kids /@ children], {tokenLeaf[close]}], <||>], trivia]
groupItem[tag_, open_String, lead_List, children_List, {end_String}] :=
	With[{all = Join[{tokenLeaf[open]}, lead, Catenate[kids /@ children]]}, With[{n = trailingTriviaCount[all]},
		item[CodeParser`GroupMissingCloserNode[tag, Drop[all, -n], If[end === "End", <|unterminated -> True|>, <||>]], Take[all, -n]]]]

trailingTriviaCount[all_List] := Module[{n = 0}, While[n < Length[all] && triviaLeafQ[all[[-n - 1]]], n++]; n]

triviaLeafQ[CodeParser`LeafNode[Whitespace | Token`Newline | Token`Comment, _, _]] := True
triviaLeafQ[_] := False

(* a ;; b ;; c: a middle left out is Token`Fake`ImplicitAll; a span the ;; after it begins makes
	the two a product, one InfixNode of Times for all the spans *)
spanItem[a_item, semis_item, middle_, third_, next_] := With[{
		span = stepsItem[If[MissingQ[third], CodeParser`BinaryNode, CodeParser`TernaryNode], Span, a,
			Join[{step[{}, kids[semis], If[MissingQ[middle], implicitItem[Token`Fake`ImplicitAll], middle]]}, If[MissingQ[third], {}, {third}]]]},
	If[MissingQ[next], span, spanProduct[span, next]]]

spanProduct[first_item, item[CodeParser`InfixNode[Times, children_List, _], trivia_List]] :=
	concreteNode[CodeParser`InfixNode, Times, Join[kids[first], {concreteLeaf[Token`Fake`ImplicitTimes, ""]}, Most[children]], item[Last[children], trivia]]
spanProduct[first_item, next_item] := stepsItem[CodeParser`InfixNode, Times, first, {step[{}, {concreteLeaf[Token`Fake`ImplicitTimes, ""]}, next]}]

(* The concrete expression parser: operands and postfix operators are
	followed by the trivia ws, other operators by wsAll; brackets hold
	expressions of nested. Outside brackets, a newline ends an expression
	where it can end, but for a chain of one operator (a + b, a; b, a::b,
	a == b, ...), the ~ ~ of a ~f~ b and the = of t /: lhs = rhs, which
	continue past it as CodeParser's do. <|"Expression" -> the parser,
	"Children" -> that of what a group or the source holds between its
	ends|>. *)
concreteParser[ws_, wsAll_, nested_] := Module[
	{operatorItem, op, postOp, symbolItem, blankItem, numberItem, stringItem, slotItem, outItem, fileItem, getItem,
	letterlikeItem, unterminatedStringItem, unterminatedCommentItem, unsupportedItem, unhandledItem, strayItem, expectedOperand,
	errorToken, leafAhead, operandAhead, scopedCloser, strayCloser, children, groupEnd, group, commaStep, commaExpression,
	call, typeSpecifier, tag, colons, messageName, tilde, spanOperandItem, spanTail, spanStart,
	semiStep, compound, equalDot, unset, tagSet, put, patternUnit, otherUnits, plainUnit, unit, errorUnits,
	binary, prefix, postfix, optionalColon, chain, flat, dotOperator, implicitTimes, inequality, plus, times, specs, table,
	expression, gap, patternRight, spanOperand, compoundOperand, tagLeft, tagRight, tildeOperand, spanStartCell,
	longOp, longPrefix, longPostfix, longBinary, longSpecs, longGroups, longCalls, groupOf, callOf, commaOperator, commaAhead,
	closerAhead, differentialAhead, integralItem, integrandOperand, implicitTimesFirst, prefixAhead, prefixedTable},

	patternRight = RecCell[]; spanOperand = RecCell[]; compoundOperand = RecCell[]; tagLeft = RecCell[]; tagRight = RecCell[];
	tildeOperand = RecCell[]; spanStartCell = RecCell[]; integrandOperand = RecCell[]; prefixAhead = RecCell[];
	(* the trivia before a chain's later operator that its operand's own
		does not cover: none where an operand takes all trivia after it *)
	gap = If[ws === wsAll, ParseSucceed[{}], wsAll];

	(* an operator in any of its spellings, then the trivia w: item[token, trivia] *)
	operatorItem[s_String, w_] := ParseChoice @@ Map[
		Function[spelling, ParseAction[longest[spelling, $concreteSpellings] ~~ w, item[tokenLeaf[#1], #2] &]],
		spellings[s]];
	op[s_String] := operatorItem[s, wsAll];
	postOp[s_String] := operatorItem[s, ws];
	(* a long name, in either spelling, then the trivia w *)
	longOp[name_String, w_] := ParseChoice @@ Map[
		Function[spelling, ParseAction[ParseLiteral[spelling] ~~ w, item[tokenLeaf[#1], #2] &]],
		longNameSpellings[name]];

	(* --- operands --- *)
	symbolItem = ParseAction[$concreteName ~~ ParseNotFollowedBy[ParseCharacter["_" | "`"]] ~~ ws, item[concreteLeaf[Symbol, #1], #3] &];
	blankItem = ParseAction[ParseOptional[$concreteName] ~~ ParseChoice[
			ParseAction[ParseLiteral["_."], {"_.", Missing[]} &],
			ParseAction[ParseChoice[ParseLiteral["___"], ParseLiteral["__"], ParseLiteral["_"]] ~~ ParseOptional[$concreteName], {#1, #2} &]] ~~ ws,
		Function[{name, blank, t}, item[blankNode[name, blank[[1]], blank[[2]]], t]]];
	numberItem = ParseAction[ParseLookahead[ParseCharacter[DigitCharacter | "."]] ~~ $numberText ~~ ws,
		If[numberTextValidQ[#2], item[concreteLeaf[concreteNumberKind[#2], #2], #3], errorTokenItem[Token`Error`Number, #2, #3]] &];
	stringItem = ParseAction[$string ~~ ws, item[concreteLeaf[String, #1], #2] &];
	slotItem = ParseAction[ParseChoice[
			ParseAction[ParseLiteral["##"] ~~ ParseOptional[$digits], slotNode],
			ParseAction[ParseLiteral["#"] ~~ ParseOptional[ParseChoice[$digits, $string, $concreteName]], slotNode]] ~~ ws,
		item[#1, #2] &];
	outItem = ParseAction[ParseChoice[
			ParseAction[ParseRegex["%%+"], concreteLeaf[Token`PercentPercent, #] &],
			ParseAction[ParseLiteral["%"] ~~ ParseOptional[$digits], outNode]] ~~ ws,
		item[#1, #2] &];

	(* --- error tokens, each the whole of an expression it begins --- *)
	letterlikeItem = ParseAction[$letterlikeError ~~ ws, errorTokenItem[Token`Error`ExpectedLetterlike, #1, #2] &];
	unterminatedStringItem = ParseAction[ParseNotFollowedBy[$string] ~~ $unterminatedString ~~ ws, errorTokenItem[Token`Error`UnterminatedString, #2, #3] &];
	unterminatedCommentItem = ParseAction[$unterminatedComment ~~ ws, errorTokenItem[Token`Error`UnterminatedComment, #1, #2] &];
	unsupportedItem = ParseAction[ParseChoice @@ (ParseLiteral /@ Prepend[Catenate[longNameSpellings /@ $longNameTable["Unsupported"]], "??"]) ~~ ws,
		errorTokenItem[Token`Error`UnsupportedToken, #1, #2] &];
	unhandledItem = ParseAction[$unhandledCharacter ~~ ws, errorTokenItem[Token`Error`UnhandledCharacter, #1, #2] &];
	strayItem = ParseAction[ParseCharacter[_?strayCharacterQ] ~~ ws, errorTokenItem[Token`Error`UnhandledCharacter, #1, #2] &];
	errorUnits = ParseChoice[letterlikeItem, unterminatedStringItem, unterminatedCommentItem, unsupportedItem, unhandledItem, strayItem];
	errorToken = ParseChoice[ParseCondition[numberItem, finalOperandQ], errorUnits];
	(* where no operand begins: an operand left out *)
	expectedOperand = ParseAction[ParseSucceed[Null], errorItem[Token`Error`ExpectedOperand] &];

	(* what can begin an operand, as CodeParser tells one: a token that is
		no error, an opener, a prefix operator *)
	leafAhead = ParseLookahead[ParseCharacter[_?leafStartQ]] ~~ ParseChoice[
		ParseCharacter["_" | "#" | "%" | "{"], ParseLiteral["<|"],
		ParseLiteral["("] ~~ ParseNotFollowedBy[ParseLiteral["*"]],
		ParseRegex["[A-Za-z$][A-Za-z0-9$]*"] ~~ ParseNotFollowedBy[ParseCharacter[_?nameMoreQ]],
		ParseLookahead[ParseCharacter[_?nameStartQ]] ~~ $concreteName ~~ ParseNotFollowedBy[ParseLiteral["`"]],
		ParseLookahead[ParseCharacter[DigitCharacter | "."]] ~~ ParseCondition[$numberText, numberTextValidQ],
		ParseLookahead[ParseLiteral["\""]] ~~ $string,
		ParseLookahead[ParseCharacter[_?prefixOnlyStartQ]] ~~ ParseChoice @@ (ParseLiteral /@ Catenate[longNameSpellings /@ $prefixOnlyNames])];
	(* what begins an operand: a leaf, a [, a ;; and a prefix operator, a -, + or ! only as one, not
		as ->, != or += *)
	operandAhead = ParseLookahead[ParseChoice[leafAhead, ParseCharacter["["], RecRef[prefixAhead], ParseLiteral[";;"],
		ParseLookahead[ParseCharacter[_?longNameStartQ]] ~~ ParseChoice @@ (ParseLiteral /@ Catenate[longNameSpellings /@ $longNameTable["Prefix"][[All, 1]]])]];

	(* --- groups --- *)
	(* the closer of a group around, or one that closes none:
		Token`Error`UnexpectedCloser *)
	closerAhead = ParseLookahead[ParseCharacter[_?closerStartQ]] ~~ ParseChoice @@ (ParseLiteral /@ Keys[$closerLabels]);
	scopedCloser = ParseLookahead[ParseCharacter[_?closerStartQ]] ~~ ParseChoice @@ KeyValueMap[
		Function[{c, label}, ParseLiteral[c] ~~ ParseCondition[ParseScope[], MemberQ[#, label] &]], $closerLabels];
	strayCloser = ParseAction[ParseLookahead[ParseCharacter[_?closerStartQ]] ~~ ParseChoice @@ KeyValueMap[Function[{c, label},
		ParseAction[ParseLiteral[c] ~~ ParseCondition[ParseScope[], ! MemberQ[#, label] &] ~~ wsAll, errorTokenItem[Token`Error`UnexpectedCloser, #1, #3] &]],
		$closerLabels], #2 &];
	(* an expression, or expressions between commas, any of them left out:
		Token`Error`PrefixImplicitNull first, Token`Error`InfixImplicitNull
		after a comma; after a comma an expression is all but a closer, a
		comma and the end, an error token too *)
	commaOperator = ParseChoice[op[","], longOp["InvisibleComma", wsAll]];
	commaAhead = ParseChoice @@ (ParseLiteral /@ Prepend[longNameSpellings["InvisibleComma"], ","]);
	commaStep[e_] := ParseAction[commaOperator ~~ ParseOptional[ParseAction[ParseLookahead[ParseCharacter[_]] ~~ ParseNotFollowedBy[ParseChoice[closerAhead, commaAhead]] ~~ e, #3 &]],
		step[{}, kids[#1], If[MissingQ[#2], errorItem[Token`Error`InfixImplicitNull], #2]] &];
	commaExpression[e_, g_] := ParseAction[
		ParseChoice[ParseAction[ParseLookahead[commaAhead], errorItem[Token`Error`PrefixImplicitNull] &], e] ~~
		ParseOptional[ParseAction[commaStep[e] ~~ ParseMany[ParseAction[g ~~ commaStep[e], ReplacePart[#2, 1 -> #1] &]], Prepend[#2, #1] &]],
		If[MissingQ[#2], #1, stepsItem[CodeParser`InfixNode, CodeParser`Comma, #1, #2]] &];
	(* what a group or the source holds between its ends: expressions,
		closers that close no group around, and an error token that begins
		an expression alone, no comma after it *)
	children[e_, g_] := ParseMany[ParseAction[ParseLookahead[ParseCharacter[_]] ~~ ParseNotFollowedBy[scopedCloser] ~~
		ParseChoice[strayCloser, ParseCondition[commaExpression[e, g], ! commaAfterErrorQ[#] &], errorToken] ~~ wsAll,
		Function[{at, notCloser, child, trivia}, item[child[[1]], Join[child[[2]], trivia]]]]];
	groupEnd[closes_List] := ParseChoice[
		ParseAction[ParseChoice @@ (ParseLiteral /@ closes) ~~ ws, {"Closed", #1, #2} &],
		ParseAction[ParseNotFollowedBy[ParseCharacter[_]], {"End"} &],
		ParseAction[ParseSucceed[Null], {"Closer"} &]];
	(* a group: an opener, what it holds with its closer's label in the
		scope, and its closer *)
	groupOf[opens_List, label_String, closes_List, tag_] := ParseAction[
		ParseChoice @@ Map[If[# === "(", ParseAction[ParseLiteral["("] ~~ ParseNotFollowedBy[ParseLiteral["*"]], "(" &], ParseLiteral[#]] &, opens] ~~ wsAll ~~
			ParseScoped[label, children[RecRef[nested], ParseSucceed[{}]]] ~~ groupEnd[closes],
		Function[{o, lead, cs, end}, groupItem[tag, o, lead, cs, end]]];
	group[open_String, close_String, tag_] := groupOf[{open}, close, {close}, tag];
	(* a call: the group after an operand, its head *)
	callOf[opens_List, label_String, closes_List, tag_] := ParseAction[
		ParseChoice @@ (ParseLiteral /@ opens) ~~ wsAll ~~ ParseScoped[label, children[RecRef[nested], ParseSucceed[{}]]] ~~ groupEnd[closes],
		Function[{o, lead, cs, end}, Function[h, With[{g = groupItem[tag, o, lead, cs, end]},
			item[CodeParser`CallNode[kids[h], First[g], <||>], Last[g]]]]]];
	longGroups = Map[groupOf[longNameSpellings[#[[1]]], #[[2]], longNameSpellings[#[[2]]], #[[3]]] &, $longNameTable["Groups"]];
	longCalls = Map[{"Call", {"Postfix", callOf[longNameSpellings[#[[1]]], #[[2]], longNameSpellings[#[[2]]], #[[3]]]}} &, $longNameTable["Calls"]];
	fileItem = ParseChoice[
		ParseAction[$unterminatedFile ~~ ws, errorTokenItem[Token`Error`UnterminatedFileString, #1, #2] &],
		ParseAction[$file ~~ ws, item[concreteLeaf[String, #1], #2] &],
		unterminatedStringItem,
		ParseAction[ParseSucceed[Null], errorItem[Token`Error`ExpectedFile] &]];
	getItem = ParseAction[op["<<"] ~~ fileItem, concreteNode[CodeParser`PrefixNode, Get, kids[#1], #2] &];

	(* --- postfix operators that read operands of their own --- *)
	call = callOf[{"["}, "]", {"]"}, CodeParser`GroupSquare];
	(* t::[a, ...], a type with parameters *)
	typeSpecifier = callOf[{"::["}, "]", {"]"}, CodeParser`GroupTypeSpecifier];
	(* a::b::c, each tag right after its ::, a name or a string *)
	tag = ParseChoice[
		ParseAction[ParseChoice[$string, $concreteName] ~~ ws, item[concreteLeaf[String, #1], #2] &],
		unterminatedStringItem,
		ParseAction[ParseSucceed[Null] ~~ ws, errorTokenItem[Token`Error`ExpectedTag, "", #2] &]];
	colons = ParseAction[ParseLiteral["::"] ~~ ParseNotFollowedBy[ParseLiteral["["]], tokenLeaf["::"] &];
	messageName = ParseAction[colons ~~ tag ~~ ParseMany[ParseAction[gap ~~ colons ~~ tag, step[#1, {#2}, #3] &]],
		Function[{c, first, rest}, Function[s, stepsItem[CodeParser`InfixNode, MessageName, s, Prepend[rest, step[{}, {c}, first]]]]]];
	tilde = ParseAction[op["~"] ~~ RecRef[tildeOperand] ~~ ParseOptional[ParseAction[gap ~~ op["~"] ~~ RecRef[tildeOperand], step[#1, kids[#2], #3] &]],
		Function[{o1, m, second}, Function[l, If[MissingQ[second],
			concreteNode[CodeParser`SyntaxErrorNode, SyntaxError`ExpectedTilde, Join[kids[l], kids[o1]], m],
			stepsItem[CodeParser`TernaryNode, CodeParser`TernaryTilde, l, {step[{}, kids[o1], m], second}]]]]];
	(* a ;; b ;; c: the operand after the first ;; left out but for one a prefix operator begins,
		the ;; after b only with an operand after it, and a ;; after the span the beginning of a
		span of its own *)
	spanOperandItem = ParseAction[ParseNotFollowedBy[ParseLiteral[";;"]] ~~ operandAhead ~~ RecRef[spanOperand], #3 &];
	spanTail = ParseAction[postOp[";;"] ~~
			ParseChoice[ParseAction[ParseLookahead[RecRef[prefixAhead]] ~~ spanOperandItem, #2 &],
				ParseAction[ParseNotFollowedBy[RecRef[prefixAhead]] ~~ ParseOptional[spanOperandItem], #2 &]] ~~
			ParseOptional[ParseAction[postOp[";;"] ~~ spanOperandItem, step[{}, kids[#1], #2] &]] ~~
			ParseOptional[ParseAction[ParseLookahead[ParseLiteral[";;"]] ~~ RecRef[spanStartCell], #2 &]],
		Function[{semis, middle, third, next}, Function[a, spanItem[a, semis, middle, third, next]]]];
	(* a; b; c: an operand left out is Token`Fake`ImplicitNull *)
	semiStep = ParseAction[postOp[";"] ~~ ParseOptional[ParseAction[operandAhead ~~ RecRef[compoundOperand], #2 &]],
		step[{}, kids[#1], If[MissingQ[#2], implicitItem[Token`Fake`ImplicitNull], #2]] &];
	compound = ParseAction[semiStep ~~ ParseMany[ParseAction[gap ~~ semiStep, ReplacePart[#2, 1 -> #1] &]],
		Function[{first, rest}, Function[a, stepsItem[CodeParser`InfixNode, CompoundExpression, a, Prepend[rest, first]]]]];
	(* =. : the = then the ., trivia between, the . not a number's *)
	equalDot = ParseAction[op["="] ~~ ParseLiteral["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter | "."]] ~~ ws,
		step[{}, kids[#1], item[tokenLeaf["."], #4]] &];
	unset = ParseAction[equalDot, Function[s, Function[a, stepsItem[CodeParser`BinaryNode, Unset, a, {s}]]]];
	tagSet = ParseAction[op["/:"] ~~ RecRef[tagLeft] ~~ ParseOptional[ParseAction[gap ~~ ParseChoice[
			ParseAction[op[":="] ~~ RecRef[tagRight], {TagSetDelayed, step[{}, kids[#1], #2]} &],
			ParseAction[equalDot, {TagUnset, #} &],
			ParseAction[op["="] ~~ RecRef[tagRight], {TagSet, step[{}, kids[#1], #2]} &]], {#1, #2} &]],
		Function[{slash, lhs, rest}, Function[t, If[MissingQ[rest],
			concreteNode[CodeParser`SyntaxErrorNode, SyntaxError`ExpectedSet, Join[kids[t], kids[slash]], lhs],
			stepsItem[CodeParser`TernaryNode, rest[[2, 1]], t, {step[{}, kids[slash], lhs], ReplacePart[rest[[2, 2]], 1 -> rest[[1]]]}]]]]];
	put[s_String, head_] := ParseAction[op[s] ~~ fileItem,
		Function[{o, file}, Function[x, stepsItem[CodeParser`BinaryNode, head, x, {step[{}, kids[o], file]}]]]];

	(* an integral: its integrand, then a \[DifferentialD] after it makes
		a PrefixBinaryNode, as \[Integral] f \[DifferentialD] x does *)
	differentialAhead = ParseChoice @@ (ParseLiteral /@ Catenate[longNameSpellings /@ {"DifferentialD", "CapitalDifferentialD"}]);
	integralItem = ParseChoice @@ Map[Function[r, ParseAction[
			longOp[r[[1]], wsAll] ~~ ParseScoped["Integrand", RecRef[integrandOperand]] ~~
				ParseOptional[ParseAction[ParseLookahead[differentialAhead] ~~ RecRef[integrandOperand], #2 &]],
			Function[{o, f, d}, If[MissingQ[d],
				concreteNode[CodeParser`PrefixNode, r[[2]], kids[o], f],
				concreteNode[CodeParser`PrefixBinaryNode, r[[3]], Join[kids[o], kids[f]], d]]]]],
		$longNameTable["Integrals"]];

	(* --- the operands of the table --- *)

	(* x:patt, the name binding its pattern; within the pattern a : is
		Optional's *)
	patternUnit = ParseAction[symbolItem ~~ ParseOptional[ParseAction[op[":"] ~~ RecRef[patternRight], step[{}, kids[#1], #2] &]],
		Function[{name, s}, If[MissingQ[s], name, stepsItem[CodeParser`BinaryNode, Pattern, name, {s}]]]];
	(* ;; b and ;; at the start: Token`Fake`ImplicitOne before it *)
	spanStart = ParseAction[spanTail, #[implicitItem[Token`Fake`ImplicitOne]] &];
	SetRec[spanStartCell, spanStart];
	otherUnits = ParseChoice[
		blankItem, numberItem, stringItem, slotItem, outItem,
		group["(", ")", CodeParser`GroupParen], group["{", "}", List], group["<|", "|>", Association],
		group["[", "]", CodeParser`GroupSquare], getItem, spanStart, Sequence @@ longGroups, integralItem];
	plainUnit = ParseChoice[symbolItem, otherUnits, errorUnits, expectedOperand];
	unit = ParseChoice[patternUnit, otherUnits, errorUnits, expectedOperand];

	(* --- operators whose parser gives the combining function --- *)
	binary[s_String, head_] := ParseAction[op[s], Function[o, Function[{l, r}, stepsItem[CodeParser`BinaryNode, head, l, {step[{}, kids[o], r]}]]]];
	prefix[s_String, head_] := ParseAction[op[s], Function[o, Function[x, concreteNode[CodeParser`PrefixNode, head, kids[o], x]]]];
	postfix[s_String, head_] := ParseAction[postOp[s], Function[o, Function[x, concreteNode[CodeParser`PostfixNode, head, kids[x], o]]]];
	longBinary[name_String, head_] := ParseAction[longOp[name, wsAll], Function[o, Function[{l, r}, stepsItem[CodeParser`BinaryNode, head, l, {step[{}, kids[o], r]}]]]];
	longPrefix[name_String, head_] := ParseAction[longOp[name, wsAll], Function[o, Function[x, concreteNode[CodeParser`PrefixNode, head, kids[o], x]]]];
	longPostfix[name_String, head_] := ParseAction[longOp[name, ws], Function[o, Function[x, concreteNode[CodeParser`PostfixNode, head, kids[x], o]]]];
	optionalColon = ParseAction[op[":"], Function[o, Function[{l, r}, stepsItem[
		If[patternLikeQ[l], CodeParser`BinaryNode, CodeParser`SyntaxErrorNode], If[patternLikeQ[l], Optional, SyntaxError`ExpectedSymbol],
		l, {step[{}, kids[o], r]}]]]];
	(* a chain of one head, its later operators past a newline *)
	chain[head_] := Function[{operands, operators}, stepsItem[CodeParser`InfixNode, head, First[operands],
		MapThread[Append, {operators, Rest[operands]}]]];
	flat[operator_, combine_] := {"InfixN", ParseAction[operator, step[{}, kids[#]] &], combine, ParseAction[gap ~~ operator, step[#1, kids[#2]] &]};
	dotOperator = ParseAction[ParseLiteral["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter | "."]] ~~ wsAll, item[tokenLeaf["."], #3] &];
	(* a b: a product where an operand follows an operand on its line *)
	implicitTimes = ParseAction[ParseLookahead[leafAhead], step[{}, {concreteLeaf[Token`Fake`ImplicitTimes, ""]}] &];
	(* in an integrand, a product does not begin at its \[DifferentialD] *)
	implicitTimesFirst = ParseAction[ParseLookahead[leafAhead] ~~
			ParseNotFollowedBy[differentialAhead ~~ ParseCondition[ParseScope[], MatchQ[#, {___, "Integrand"}] &]],
		step[{}, {concreteLeaf[Token`Fake`ImplicitTimes, ""]}] &];
	inequality = chain[CodeParser`InfixInequality];
	plus = chain[Plus];
	times = chain[Times];

	specs = {
		{"ColonColon", {"Postfix", messageName}},
		{"Infix`Question", {"InfixL", binary["?", PatternTest]}},
		{"Call", {"Postfix", call}},
		{"Call", {"Postfix", typeSpecifier}},
		{"Postfix`PlusPlus", {"Postfix", postfix["++", Increment]}},
		{"Postfix`PlusPlus", {"Postfix", postfix["--", Decrement]}},
		{"Prefix`PlusPlus", {"Prefix", prefix["++", PreIncrement]}},
		{"Prefix`PlusPlus", {"Prefix", prefix["--", PreDecrement]}},
		{"AtStar", flat[op["@*"], chain[Composition]]},
		{"SlashStar", flat[op["/*"], chain[RightComposition]]},
		{"At", {"InfixR", binary["@", CodeParser`BinaryAt]}},
		{"Tilde", {"Postfix", tilde}},
		{"SlashAt", {"InfixR", binary["/@", Map]}},
		{"SlashAt", {"InfixR", binary["//@", MapAll]}},
		{"SlashAt", {"InfixR", binary["@@", Apply]}},
		{"SlashAt", {"InfixR", binary["@@@", MapApply]}},
		{"Postfix`Bang", {"Postfix", postfix["!", Factorial]}},
		{"Postfix`Bang", {"Postfix", postfix["!!", Factorial2]}},
		{"SingleQuote", {"Postfix", postfix["'", Derivative]}},
		{"LessGreater", flat[op["<>"], chain[StringJoin]]},
		{"Caret", {"InfixR", binary["^", Power]}},
		{"StarStar", flat[op["**"], chain[NonCommutativeMultiply]]},
		{"Dot", flat[dotOperator, chain[Dot]]},
		{"Prefix`Minus", {"Prefix", prefix["-", Minus]}},
		{"Prefix`Minus", {"Prefix", prefix["+", Plus]}},
		{"Slash", {"InfixL", binary["/", Divide]}},
		{"Star", flat[op["*"], times]},
		{"Star", {"InfixN", implicitTimesFirst, times, implicitTimes}},
		{"Infix`Plus", flat[op["+"], plus]},
		{"Infix`Plus", flat[op["-"], plus]},
		{"SemiSemi", {"Postfix", spanTail}},
		{"LongName`DirectedEdge", {"InfixR", binary["DirectedEdge", DirectedEdge]}},
		{"LongName`DirectedEdge", {"InfixR", binary["UndirectedEdge", UndirectedEdge]}},
		{"Class`Inequality", flat[op["=="], inequality]},
		{"Class`Inequality", flat[op["!="], inequality]},
		{"Class`Inequality", flat[op["<="], inequality]},
		{"Class`Inequality", flat[op[">="], inequality]},
		{"Class`Inequality", flat[op["<"], inequality]},
		{"Class`Inequality", flat[op[">"], inequality]},
		{"EqualEqualEqual", flat[op["==="], chain[SameQ]]},
		{"EqualEqualEqual", flat[op["=!="], chain[UnsameQ]]},
		{"Class`SetRelations", flat[op["Element"], chain[Element]]},
		{"Prefix`Bang", {"Prefix", prefix["!", Not]}},
		{"Prefix`Bang", {"Prefix", prefix["!!", CodeParser`PrefixNot2]}},
		{"AmpAmp", flat[op["&&"], chain[And]]},
		{"BarBar", flat[op["||"], chain[Or]]},
		{"DotDot", {"Postfix", postfix["..", Repeated]}},
		{"DotDot", {"Postfix", postfix["...", RepeatedNull]}},
		{"Bar", flat[op["|"], chain[Alternatives]]},
		{"Fake`OptionalColon", {"InfixR", optionalColon}},
		{"TildeTilde", flat[op["~~"], chain[StringExpression]]},
		{"SlashSemi", {"InfixL", binary["/;", Condition]}},
		{"LessMinusGreater", {"InfixR", binary["<->", TwoWayRule]}},
		{"MinusGreater", {"InfixR", binary["->", Rule]}},
		{"MinusGreater", {"InfixR", binary[":>", RuleDelayed]}},
		{"SlashDot", {"InfixL", binary["/.", ReplaceAll]}},
		{"SlashDot", {"InfixL", binary["//.", ReplaceRepeated]}},
		{"PlusEqual", {"InfixR", binary["+=", AddTo]}},
		{"PlusEqual", {"InfixR", binary["-=", SubtractFrom]}},
		{"PlusEqual", {"InfixR", binary["*=", TimesBy]}},
		{"PlusEqual", {"InfixR", binary["/=", DivideBy]}},
		{"Amp", {"Postfix", postfix["&", Function]}},
		{"SlashSlashEqual", {"InfixR", binary["//=", ApplyTo]}},
		{"SlashSlash", {"InfixL", binary["//", CodeParser`BinarySlashSlash]}},
		{"SlashColon", {"Postfix", tagSet}},
		{"Equal", {"Postfix", unset}},
		{"Equal", {"InfixR", binary["=", Set]}},
		{"Equal", {"InfixR", binary[":=", SetDelayed]}},
		{"Equal", {"InfixR", binary["^=", UpSet]}},
		{"Equal", {"InfixR", binary["^:=", UpSetDelayed]}},
		{"Equal", {"InfixR", binary["|->", Function]}},
		{"GreaterGreater", {"Postfix", put[">>", Put]}},
		{"GreaterGreater", {"Postfix", put[">>>", PutAppend]}},
		{"Semi", {"Postfix", compound}}
	};
	(* the long-name operators CodeParser reads, those of no ASCII operator
		above, at their precedences *)
	longSpecs = Join[
		Map[{#[[4]], If[#[[2]] === "InfixNode",
				flat[longOp[#[[1]], wsAll], chain[#[[3]]]],
				{If[#[[5]] === "Right", "InfixR", "InfixL"], longBinary[#[[1]], #[[3]]]}]} &,
			Select[$longNameTable["Infix"], ! KeyExistsQ[$asciiLongNames, #[[1]]] && #[[3]] =!= CodeParser`Comma &]],
		Map[{#[[4]], {"Prefix", longPrefix[#[[1]], #[[3]]]}} &,
			Select[$longNameTable["Prefix"], ! KeyExistsQ[$asciiLongNames, #[[1]]] && ! MemberQ[$longNameTable["Integrals"][[All, 1]], #[[1]]] &]],
		Map[{#[[4]], {"Postfix", longPostfix[#[[1]], #[[3]]]}} &, $longNameTable["Postfix"]],
		longCalls];
	specs = Join[specs, longSpecs];

	table[u_, min_Integer] := ParseOperatorTable[u, levelsAbove[specs, min], "FinalOperand" -> finalOperandQ];
	(* the operators that bind more tightly than min, and the prefix ones of any precedence *)
	prefixedTable[u_, min_Integer] := ParseOperatorTable[u,
		levelsAbove[Select[specs, #[[2, 1]] === "Prefix" || precedenceValue[First[#]] > min &], -1], "FinalOperand" -> finalOperandQ];
	(* what begins an operand with an operator: a prefix operator, a << or an integral *)
	SetRec[prefixAhead, ParseChoice @@ Join[Cases[specs, {_, {"Prefix", p_}} :> p], {op["<<"]}, longOp[#, wsAll] & /@ $longNameTable["Integrals"][[All, 1]]]];
	SetRec[patternRight, table[plainUnit, $codeParserPrecedence["Fake`PatternColon"]]];
	(* a span's operand: what binds more tightly than ;;, and a prefix operator of any precedence,
		as in any other operand, its operand all that binds more tightly than it, as CodeParser reads
		it [W15 bug] *)
	With[{lows = Select[specs, #[[2, 1]] === "Prefix" && precedenceValue[First[#]] <= $codeParserPrecedence["SemiSemi"] &]},
		SetRec[spanOperand, table[ParseChoice[
				Sequence @@ Map[Function[s, ParseAction[s[[2, 2]] ~~ prefixedTable[unit, precedenceValue[First[s]]], #1[#2] &]], lows], unit],
			$codeParserPrecedence["SemiSemi"]]]];
	SetRec[compoundOperand, table[unit, $codeParserPrecedence["Semi"]]];
	SetRec[tagLeft, table[unit, $codeParserPrecedence["Equal"]]];
	SetRec[tagRight, table[unit, $codeParserPrecedence["Equal"] - 1]];
	SetRec[tildeOperand, table[unit, $codeParserPrecedence["Tilde"]]];
	(* an integrand binds as tightly as the integral's prefix operator *)
	SetRec[integrandOperand, table[unit, First[Cases[$longNameTable["Prefix"], {"Integral", _, _, p_Integer, _} :> p]]]];
	expression = table[unit, 0];
	<|"Expression" -> expression, "Children" -> children[expression, gap]|>
]

(* ::Section:: *)
(*The source of each node*)

(* CodeParser's LineColumn convention: Source -> {{line, column} a node
	starts at, {line, column} just past it}. A leaf's is found from the text
	of the leaves before it, a token for what was left out taking no room;
	a node's runs from its first leaf to its last. The container lists
	where the tokens are that hold a line continuation, outside a string
	and inside one, and the strings and comments holding a newline or a
	tab. A leaf that holds a line continuation is marked continuedBy, the
	length of the one it begins with its value; a continuation at the end
	of the source, in no leaf, is listed where the source ends. *)
withSource[CodeParser`ContainerNode[kind_, children_List, meta_], continuedAtEnd_ : False] := Module[
	{at = {1, 1}, marks = <|"SimpleLineContinuations" -> {}, "ComplexLineContinuations" -> {}, "EmbeddedNewlines" -> {}, "EmbeddedTabs" -> {}|>,
	placed, leaf, placedChildren},
	leaf[head_, k_, s_String, m_] := With[{start = at},
		at = advanced[at, s];
		Scan[(marks[#] = Append[marks[#], start]) &, Union[tokenMarks[k, StringDrop[s, Lookup[m, continuedBy, 0]]],
			If[KeyExistsQ[m, continuedBy], {"SimpleLineContinuations"}, {}]]];
		head[k, s, Append[KeyDrop[m, continuedBy], CodeParser`Source -> {start, at}]]];
	placed[CodeParser`LeafNode[k_, s_String, m_]] := leaf[CodeParser`LeafNode, k, s, m];
	placed[CodeParser`ErrorNode[k_, s_String, m_]] := leaf[CodeParser`ErrorNode, k, s, m];
	placed[CodeParser`CallNode[head_List, group_, m_]] := With[{h = placed /@ head, g = placed[group]},
		CodeParser`CallNode[h, g, Append[m, CodeParser`Source -> {sourceOf[First[h]][[1]], sourceOf[g][[2]]}]]];
	placed[node_[tag_, kids_List, m_]] := With[{c = placed /@ kids},
		node[tag, c, Append[m, CodeParser`Source -> {sourceOf[First[c]][[1]], sourceOf[Last[c]][[2]]}]]];
	placedChildren = placed /@ children;
	If[continuedAtEnd, marks["SimpleLineContinuations"] = Append[marks["SimpleLineContinuations"], at]];
	CodeParser`ContainerNode[kind, placedChildren, Join[meta, Select[marks, # =!= {} &],
		If[placedChildren === {}, <||>, <|CodeParser`Source -> {{1, 1}, at}|>]]]
]

sourceOf[node_] := node[[-1, Key[CodeParser`Source]]]

(* the {line, column} just past the text s, begun at {line, column} *)
advanced[{line_, column_}, s_String] := With[{breaks = StringCount[s, "\r\n" | "\n" | "\r"]},
	If[ breaks === 0,
		{line, column + StringLength[s]},
		{line + breaks, 1 + StringLength[Last[StringSplit[s, "\r\n" | "\n" | "\r", All]]]}]]

(* the container's lists a token's own text puts it in: a string's
	escaped newline is a complex line continuation, its newline not
	escaped and a comment's newline are embedded *)
tokenMarks[String | Token`Error`UnterminatedString, s_String] := With[{plain = StringDelete[s, "\\" ~~ _]},
	Join[
		If[StringContainsQ[s, "\\\n" | "\\\r"] && MemberQ[StringCases[s, "\\" ~~ c_ :> c], "\n" | "\r"], {"ComplexLineContinuations"}, {}],
		If[StringContainsQ[plain, "\n" | "\r"], {"EmbeddedNewlines"}, {}],
		If[StringContainsQ[s, "\t"], {"EmbeddedTabs"}, {}]]]
tokenMarks[Token`Comment | Token`Error`UnterminatedComment, s_String] := Join[
	If[StringContainsQ[s, "\n" | "\r"], {"EmbeddedNewlines"}, {}],
	If[StringContainsQ[s, "\t"], {"EmbeddedTabs"}, {}]]
tokenMarks[_, _String] := {}

(* ::Section:: *)
(*Line continuations*)

(* A \ before a newline, outside a string, a comment and the file name
	of << or >>, continues the line: CodeParser reads the source as though
	the \, the newline and the spaces and tabs after it were not there.
	Their text is in the token they fall in, else in the token after them,
	and at the end of the source in none, there a string's too. The spans
	{first, last} of them in s, those that follow one another one. *)
continuationSpans[s_String] := Module[{c = ToCharacterCode[s], n, i = 1, depth = 0, inString = False, spans = {}, runEnd},
	n = Length[c];
	(* the last character of the continuations from j on, j - 1 if none begins there *)
	runEnd[j_Integer] := Module[{k = j},
		While[k < n && c[[k]] === 92 && (c[[k + 1]] === 10 || c[[k + 1]] === 13),
			k += If[c[[k + 1]] === 13 && k + 2 <= n && c[[k + 2]] === 10, 3, 2];
			While[k <= n && MemberQ[{32, 9, 11, 12}, c[[k]]], k++]];
		k - 1];
	While[i <= n,
		Which[
			inString, Which[
				c[[i]] === 92 && runEnd[i] === n, AppendTo[spans, {i, n}]; i = n + 1,
				c[[i]] === 92, i += 2,
				c[[i]] === 34, inString = False; i++,
				True, i++],
			depth > 0, Which[
				c[[i]] === 40 && i < n && c[[i + 1]] === 42, depth++; i += 2,
				c[[i]] === 42 && i < n && c[[i + 1]] === 41, depth--; i += 2,
				c[[i]] === 92 && i < n && c[[i + 1]] === 40, i += 2,
				True, i++],
			c[[i]] === 34, inString = True; i++,
			c[[i]] === 40 && i < n && c[[i + 1]] === 42, depth = 1; i += 2,
			c[[i]] === 60 && i < n && c[[i + 1]] === 60, i = fileNameEnd[c, i + 2] + 1,
			c[[i]] === 62 && i < n && c[[i + 1]] === 62, i = fileNameEnd[c, If[i + 2 <= n && c[[i + 2]] === 62, i + 3, i + 2]] + 1,
			c[[i]] === 92 && runEnd[i] >= i, AppendTo[spans, {i, runEnd[i]}]; i = spans[[-1, 2]] + 1,
			(* a \ and the character it escapes *)
			c[[i]] === 92, i += 2,
			True, i++]];
	spans]

$alphanumericCodes = AssociationThread[Join[Range[48, 57], Range[65, 90], Range[97, 122]] -> True]
(* the characters of a file name but its \ *)
$fileCharacterCodes = Join[$alphanumericCodes, AssociationThread[ToCharacterCode["$`_./~:!*?-"] -> True]]

lineContinuations[s_String] := If[StringContainsQ[s, "\\\n" | "\\\r"], continuationSpans[s], {}]

(* the positions in s of the characters read without its line continuations *)
keptPositions[s_String, spans_List] := Complement[Range[StringLength[s]], Catenate[Range @@@ spans]]

(* ::Section:: *)
(*Character escapes*)

(* A \:xxxx, \.xx or \|xxxxxx outside a string and a comment is the character its hexadecimal
	digits name, as Wolfram 15's reader reads it before it reads tokens: a letter of a name or of a
	file, an operator, a bracket. The spans {first, last} of them in s, each with its character. *)
escapeSpans[s_String] := Module[{c = ToCharacterCode[s], n, i = 1, depth = 0, inString = False, escapes = {}, width = 0, code = 0},
	n = Length[c];
	While[i <= n,
		Which[
			inString, Which[c[[i]] === 92, i += 2, c[[i]] === 34, inString = False; i++, True, i++],
			depth > 0, Which[
				c[[i]] === 40 && i < n && c[[i + 1]] === 42, depth++; i += 2,
				c[[i]] === 42 && i < n && c[[i + 1]] === 41, depth--; i += 2,
				c[[i]] === 92 && i < n && c[[i + 1]] === 40, i += 2,
				True, i++],
			c[[i]] === 34, inString = True; i++,
			c[[i]] === 40 && i < n && c[[i + 1]] === 42, depth = 1; i += 2,
			c[[i]] === 92 && i < n && (width = Switch[c[[i + 1]], 58, 4, 46, 2, 124, 6, _, 0]) > 0 && i + 1 + width <= n &&
				AllTrue[c[[i + 2 ;; i + 1 + width]], KeyExistsQ[$hexadecimalCodes, #] &] &&
				(code = FromDigits[FromCharacterCode[c[[i + 2 ;; i + 1 + width]]], 16]) <= 1114111,
				AppendTo[escapes, {{i, i + 1 + width}, FromCharacterCode[code]}]; i += 2 + width,
			(* a \ and the character it escapes *)
			c[[i]] === 92, i += 2,
			True, i++]];
	escapes]

$hexadecimalCodes = AssociationThread[Join[Range[48, 57], Range[65, 70], Range[97, 102]] -> True]

(* the last character of the spaces and the file name of << or >> from j0 on in the codes c, a
	letter past ASCII one of its characters *)
fileNameEnd[c_List, j0_Integer] := Module[{j = j0, n = Length[c]},
	While[j <= n && (c[[j]] === 32 || c[[j]] === 9), j++];
	While[j <= n && (KeyExistsQ[$fileCharacterCodes, c[[j]]] || c[[j]] === 92 || (c[[j]] > 127 && LetterQ[FromCharacterCode[c[[j]]]])),
		If[ c[[j]] === 92 && j < n && c[[j + 1]] === 91,
			j += 2; While[j <= n && KeyExistsQ[$alphanumericCodes, c[[j]]], j++]; If[j <= n && c[[j]] === 93, j++, Break[]],
			j++]];
	j - 1]

characterEscapes[s_String] := If[StringContainsQ[s, "\\:" | "\\." | "\\|"], escapeSpans[s], {}]

(* s as the readers read it, without its line continuations and with each character escape its
	character, and the positions in s of its characters, None where they are all of s's *)
readSource[s_String] /; !StringContainsQ[s, "\\"] := {s, None}
readSource[s_String] := With[{spans = lineContinuations[s], escapes = characterEscapes[s]},
	If[ spans === {} && escapes === {}, {s, None},
		With[{edits = SortBy[Join[Thread[{spans, ""}], escapes], #[[1, 1]] &]},
			{StringReplacePart[s, edits[[All, 2]], edits[[All, 1]]],
			Complement[Range[StringLength[s]], Catenate[Range @@@ Join[spans, Map[{#[[1]] + 1, #[[2]]} &, escapes[[All, 1]]]]]]}]]]

(* offsets into the source read without its line continuations made
	offsets into the source: a node begins where the continuations before
	its first character do, and ends past its last character *)
continuedOffsets[tree_, kept_List] := With[{at = Function[o, If[o === 1, 1, kept[[o - 1]] + 1]]},
	tree /. (a_Association /; MatchQ[Lookup[a, "Source"], {_Integer, _Integer}]) :> Append[a, "Source" -> Map[at, a["Source"]]]]

(* a failure at a character of the source read without its line
	continuations, placed at that character of the source *)
continuedFailure[f_Failure, kept_List, s_String] := With[{at = f["Position"]},
	If[ IntegerQ[at],
		With[{p = If[at <= Length[kept], kept[[at]], StringLength[s] + 1]},
			Failure[f[[1]], Join[f[[2]], <|"Position" -> p, "MessageParameters" -> Append[Lookup[f[[2]], "MessageParameters", <||>], "Position" -> p]|>]]],
		f]]

(* the leaves of a tree read from s without its line continuations, each
	given its text in s: kept is the positions in s of the characters read *)
continuedLeaves[children_List, s_String, kept_List] := Module[{p = 0, leaf, walked},
	leaf[head_, k_, t_String, m_] := If[t === "", head[k, t, m],
		With[{first = kept[[p + 1]], last = kept[[p + StringLength[t]]], from = If[p === 0, 1, kept[[p]] + 1]},
			p += StringLength[t];
			If[ from === first && last - first + 1 === StringLength[t],
				head[k, t, m],
				head[k, StringTake[s, {from, last}], Append[m, continuedBy -> first - from]]]]];
	walked[CodeParser`LeafNode[k_, t_String, m_]] := leaf[CodeParser`LeafNode, k, t, m];
	walked[CodeParser`ErrorNode[k_, t_String, m_]] := leaf[CodeParser`ErrorNode, k, t, m];
	walked[CodeParser`CallNode[head_List, group_, m_]] := With[{h = walked /@ head}, CodeParser`CallNode[h, walked[group], m]];
	walked[node_[tag_, kids_List, m_]] := node[tag, walked /@ kids, m];
	walked /@ children]

(* ::Section:: *)
(*What CodeParser reads again*)

(* Of a group the source leaves open at its end, and of a string or a
	comment it does not close, CodeParser keeps what lies on the lines of
	the first chunk of its own: up to the last line, but blank ones, before
	a line that begins an annotation comment, a directive or a definition.
	The group keeps the leaves in that span, its children's too; the token
	the text there. The rest of the source is in neither (Error.wl of the
	CodeParser paclet, MIT). *)
$chunkPattern = RegularExpression["(?m)(" <> "^\\(\\* *:.*$" <> ")|(" <>
	"^(BeginPackage|Begin|Needs|End|EndPackage|Clear|ClearAll|SetOptions|SetAttributes|System`Private`NewContextPath|System`Private`RestoreContextPath|Protect|Unprotect|Package|PackageImport|PackageScope|PackageExport|Get|SetDelayed|UpSetDelayed|TagSetDelayed)\\[.*$" <>
	")|(" <> "^[a-zA-Z$].*(:?\\=).*$" <> ")"]

reparsed[tree_, s_String] := If[
	FreeQ[tree, Token`Error`UnterminatedString | Token`Error`UnterminatedComment] &&
		! MemberQ[tree, CodeParser`GroupMissingCloserNode[_, _, m_ /; TrueQ[m[unterminated]]], Infinity],
	tree,
	readAgain[tree, StringSplit[s, "\r\n" | "\n" | "\r", All]]]

readAgain[CodeParser`ErrorNode[tok : Token`Error`UnterminatedString | Token`Error`UnterminatedComment, _, meta_], lines_] :=
	With[{b = chunkEnd[meta[CodeParser`Source], lines]},
		CodeParser`ErrorNode[tok, StringRiffle[Prepend[Rest[b[[2]]], StringDrop[First[b[[2]]], b[[1, 1, 2]] - 1]], "\n"],
			<|CodeParser`Source -> First[b]|>]]
readAgain[n : (CodeParser`LeafNode | CodeParser`ErrorNode)[_, _String, _], _] := n
readAgain[CodeParser`CallNode[head_List, group_, meta_], lines_] :=
	CodeParser`CallNode[readAgain[#, lines] & /@ head, readAgain[group, lines], meta]
readAgain[node_[tag_, children_List, meta_], lines_] := With[{c = readAgain[#, lines] & /@ children},
	If[ TrueQ[meta[unterminated]],
		With[{b = First[chunkEnd[meta[CodeParser`Source], lines]]},
			node[tag, Cases[c, (CodeParser`LeafNode | CodeParser`ErrorNode)[_, _, m_ /; sourceWithinQ[b, m[CodeParser`Source]]], Infinity],
				<|CodeParser`Source -> b|>]],
		node[tag, c, meta]]]
readAgain[CodeParser`ContainerNode[kind_, children_List, meta_], lines_] := CodeParser`ContainerNode[kind, readAgain[#, lines] & /@ children, meta]

(* {the span from where the source begins to the end of its chunk's last
	line, but blank ones, the lines of the chunk up to that one} *)
chunkEnd[{start_, end_}, lines_List] := Module[{chunk = First[Split[lines[[start[[1]] ;; end[[1]]]], ! StringMatchQ[#2, $chunkPattern] &]], last},
	last = Length[chunk];
	While[chunk[[last]] === "", last--];
	{{start, {start[[1]] + last - 1, StringLength[chunk[[last]]] + 1}}, Take[chunk, last]}]

(* a span within a span, by CodeParser's line and column test *)
sourceWithinQ[span_, {a_, b_}] := positionWithinQ[span, a] && positionWithinQ[span, b]
positionWithinQ[{{l1_, c1_}, {l2_, c2_}}, {l_, c_}] := Which[
	! (l1 <= l <= l2), False,
	l == l1 == l2, c1 <= c <= c2,
	l == l1, c1 <= c,
	l == l2, c <= c2,
	True, True]

(* <|"Program" -> the parser of a whole source, the children of its
	ContainerNode, "Statement" -> that of the source's children|> *)
concreteGrammar[] := Module[{comment, spaces, newline, lineTrivia, allTrivia, nested, top, statement},
	comment = ParseAction[text[commentParser[]], {concreteLeaf[Token`Comment, #]} &];
	spaces = ParseChoice[
		ParseAction[ParseRegex["[ \t]+"], Function[s, concreteLeaf[Whitespace, #] & /@ Characters[s]]],
		ParseAction[ParseChoice @@ (ParseLiteral /@ $longWhitespace), {concreteLeaf[Whitespace, #]} &]];
	newline = ParseChoice[
		ParseAction[ParseRegex["\r\n|\n|\r"], {concreteLeaf[Token`Newline, #]} &],
		ParseAction[ParseChoice @@ (ParseLiteral /@ $longNewlines), {concreteLeaf[Token`Newline, #]} &]];
	(* each looked for only at a character that can begin it *)
	lineTrivia = ParseAction[ParseMany[ParseAction[ParseLookahead[ParseCharacter[_?lineTriviaStartQ]] ~~ ParseChoice[spaces, comment], #2 &]],
		Function[Catenate[{##}]]];
	allTrivia = ParseAction[ParseMany[ParseAction[ParseLookahead[ParseCharacter[_?allTriviaStartQ]] ~~ ParseChoice[spaces, newline, comment], #2 &]],
		Function[Catenate[{##}]]];
	nested = RecCell[];
	SetRec[nested, concreteParser[allTrivia, allTrivia, nested]["Expression"]];
	top = concreteParser[lineTrivia, allTrivia, nested]["Children"];
	statement = ParseAction[top, Function[Catenate[kids /@ {##}]]];
	<|"Program" -> ParseAction[allTrivia ~~ top, Function[{lead, items}, Join[lead, Catenate[kids /@ items]]]],
		"Statement" -> statement|>
]

(* ::Section:: *)
(*The parsers, each built once*)

(* Each parser is built at its first use: building the grammar takes longer than loading the
	paclet. *)
$astGrammar := $astGrammar = grammar[ASTAlgebra]
$heldGrammar := $heldGrammar = grammar[WolframLanguageSemantic]

(* Each reads a source with line continuations without them and with its
	character escapes their characters: the held expressions need nothing
	more, the nodes are given their places in the source, and so is a
	failure. *)
WolframLanguageAST[s_String] := With[{read = readSource[s]},
	If[ read[[2]] === None,
		With[{r = parsed[$astGrammar, s]}, If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]],
		With[{r = parsed[$astGrammar, read[[1]]], kept = read[[2]]},
			If[FailureQ[r], continuedFailure[r, kept, s], ASTAddSource[continuedOffsets[ASTContainer[r], kept], s]]]]]

(* The held expressions, read by the reader of WolframLanguageFast.wl, which
	reads the source in one pass over its tokens and fails where the
	kernel's reader stops. With $fastHeldReader False the grammar reads it,
	as the checks of the reader against the grammar do. *)
$fastHeldReader = True

WolframLanguageHeld[s_String] := With[{read = readSource[s]},
	With[{clean = read[[1]], kept = read[[2]]},
		With[{fast = If[TrueQ[$fastHeldReader], fastHeld[clean], None]},
			Which[
				ListQ[fast], DeleteCases[fast, HoldComplete[Null]],
				FailureQ[fast], If[kept === None, fast, continuedFailure[fast, kept, s]],
				True, With[{r = grammarFailure[parsed[$heldGrammar, clean], StringLength[clean]]},
					Which[! FailureQ[r], DeleteCases[expressions[r], HoldComplete[Null]], kept === None, r, True, continuedFailure[r, kept, s]]]]]]]

(* a failure of the grammar, which reads only the source the fast reader does not take: the
	source ending too early where it stops past its end *)
grammarFailure[f_Failure, length_Integer] := Failure[f[[1]], Append[f[[2]], "Incomplete" -> TrueQ[f["Position"] > length]]]
grammarFailure[other_, _] := other

$concreteGrammar := $concreteGrammar = concreteGrammar[]

WolframLanguageConcrete[s_String] := With[{spans = lineContinuations[s]},
	If[ spans === {},
		With[{r = parsed[$concreteGrammar, s]},
			If[FailureQ[r], r, reparsed[withSource[CodeParser`ContainerNode[String, r, <||>]], s]]],
		With[{r = parsed[$concreteGrammar, StringReplacePart[s, "", spans]], kept = keptPositions[s, spans]},
			If[ FailureQ[r],
				continuedFailure[r, kept, s],
				reparsed[withSource[CodeParser`ContainerNode[String, continuedLeaves[r, s, kept], <||>], spans[[-1, 2]] === StringLength[s]], s]]]]]

(* a file's text read as UTF-8, its container a File one naming it *)
WolframLanguageConcrete[File[f_String]] := With[{bytes = ReadByteArray[f]},
	With[{r = WolframLanguageConcrete[If[ByteArrayQ[bytes], ByteArrayToString[bytes, "UTF-8"], ""]]},
		If[FailureQ[r], r, CodeParser`ContainerNode[File, r[[2]], Append[r[[3]], "FileName" -> ExpandFileName[f]]]]]]

(* A source stops being read at the first statement that cannot be; that
	statement read alone says where and why, which the source's own failure
	(the end of input expected at the statement's start) does not. *)
parsed[g_Association, s_String] := With[{r = Parse[g["Program"], s]},
	If[FailureQ[r] && r["Expected"] === "<end of input>", statementFailure[g, s, r["Position"]], r]]

statementFailure[g_Association, s_String, start_Integer] := With[{r = ParsePartial[g["Statement"], StringDrop[s, start - 1]]},
	If[FailureQ[r],
		parseFailure[r["Position"] + start - 1, expectedLabel[r["Expected"]], r["Found"]],
		(* the statement is read, then something that cannot follow it *)
		With[{at = StringLength[s] - StringLength[Last[r]] + 1},
			parseFailure[at, "<operator, newline or end of input>", StringTake[s, {at}]]]]]

(* where an operand was expected, the alternatives that could begin one are
	named as that *)
expectedLabel[e_List] /; MemberQ[e, "regex /[A-Za-z$`][A-Za-z0-9$`]*/"] := "<expression>"
expectedLabel[e_] := e

parseFailure[pos_Integer, expected_, found_] := Failure["ParseError", <|
	"MessageTemplate" -> "Parse failed at position `Position`: expected `Expected`, found `Found`.",
	"MessageParameters" -> <|"Position" -> pos, "Expected" -> expected, "Found" -> found|>,
	"Position" -> pos, "Expected" -> expected, "Found" -> found|>]

End[]

EndPackage[]

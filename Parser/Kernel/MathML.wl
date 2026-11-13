(* ::Package:: *)

(* :Title: MathML.wl - MathML text to boxes and to expressions *)
(* :Context: Wolfram`Parser` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	Reads MathML as Wolfram 15 does: MathMLBoxes gives the boxes XML`MathML`MathMLToBoxes gives,
	MathMLHeld the expression of ImportString[text, {"MathML", "HeldExpression"}], and MathMLImport
	the elements of ImportString[text, {"MathML", element}].

	The text is read by the XML grammar of Languages/XML.ebnf (XMLRead), and its entities are those
	of Languages/MathMLEntities.tsv. The element tree is then mapped to boxes by rules. A row of
	MathML, an mrow or the children of an element that takes a row, is a sequence of tokens: it is
	grouped as a notebook groups typed input, by the paclet's reader of the Wolfram Language
	(WolframLanguageBoxes), with f(x) read as the application TraditionalForm takes it for. The
	expression is read from the same sequence by WolframLanguageHeld. Content MathML is first made
	an expression, which is then typeset in TraditionalForm, as Wolfram 15 does. *)

BeginPackage["Wolfram`Parser`"]

MathMLBoxes::usage = "MathMLBoxes[\"mathml\"] gives the boxes of MathML text, presentation or content, as XML`MathML`MathMLToBoxes and Developer`MathMLToBoxes give them: FormBox[TagBox[boxes, \"MathMLPresentationTag\", AutoDelete -> True], TraditionalForm], or $Failed for text that is not well-formed XML. MathMLBoxes[xml] takes symbolic XML, an XMLElement or an XMLObject[\"Document\"][...]."
MathMLHeld::usage = "MathMLHeld[\"mathml\"] gives the expression of MathML text in HoldComplete, as ImportString[mathml, {\"MathML\", \"HeldExpression\"}] gives it: its boxes read in TraditionalForm. Boxes that do not read give an ErrorBox around them. MathMLHeld[xml] takes symbolic XML."
MathMLExpression::usage = "MathMLExpression[\"mathml\"] gives the expression of MathML text, evaluated, as XML`MathML`MathMLToExpression gives it, and $Failed where its boxes do not read. MathMLExpression[xml] takes symbolic XML."
MathMLImport::usage = "MathMLImport[\"mathml\", element] gives an element of MathML text as ImportString[mathml, {\"MathML\", element}] gives it: \"Boxes\", \"Expression\", \"HeldExpression\", \"XMLElement\", \"XMLObject\" or \"Elements\". MathMLImport[\"mathml\"] gives the boxes."

MathMLBoxes::prserr = "`1`"
MathMLBoxes::nfprserr = "Entity '`1`' was not found."
MathMLBoxes::incrt = "The MathML has the root tag \"`1`\" instead of the tag \"math\"."
MathMLBoxes::unkntag = "The tag \"`1`\" is not a MathML element that can stand here."
MathMLBoxes::unknstrc = "`1` is not a valid MathML structure."
MathMLBoxes::msngargs = "The element `1` has fewer children than it takes."
MathMLBoxes::bmml = "The `1`, `2`, occurred without a surrounding XML tag."
MathMLBoxes::nmmlr = "The root element `2` is not an element of MathML."

Begin["`MathMLPrivate`"]

Needs["Wolfram`Parser`Languages`XML`"]
Needs["Wolfram`Parser`Languages`WolframLanguage`"]

(* ::Section:: *)
(*The document: entities, namespaces and whitespace as Wolfram 15 reads them*)

$mathmlDirectory = FileNameJoin[{DirectoryName[$InputFileName], "Languages"}]

readText[file_String] := ByteArrayToString[ReadByteArray[file], "UTF-8"]

(* the entities of MathML, read at their first use: each line a name, a tab, and the codes of its characters *)
$mathmlEntities := $mathmlEntities = Association[Map[
	Function[line, With[{fields = StringSplit[line, "\t"]},
		First[fields] -> FromCharacterCode[Map[FromDigits, StringSplit[Last[fields], " "]]]
	]],
	StringSplit[readText[FileNameJoin[{$mathmlDirectory, "MathMLEntities.tsv"}]], "\n"]
]]

$xmlns = "http://www.w3.org/2000/xmlns/"
$xmlNamespace = "http://www.w3.org/XML/1998/namespace"

(* every function reports under MathMLBoxes, the one the others read through; a kernel that reads MathML by this
   reader names in $messageHeads the symbol each of its messages is issued under, by tag; nmmlr has the root and
   its name, bmml the kind of what stands bare and its value, as the messages of Wolfram 15.0 have *)
$messageHeads = <||>
note[tag_String, args___] := With[{head = Lookup[$messageHeads, tag, MathMLBoxes]}, Message[MessageName[head, tag], args]; Null]

(* the document of a text: XMLObject["Document"][prolog, element, epilog], or $Failed *)
document[text_String] := Catch[
	With[{xml = XMLRead[StringDelete[text, StartOfString ~~ "\:feff"], "Entities" -> $mathmlEntities]},
		If[ FailureQ[xml], failed[xml["Message"]]];
		Replace[xml, XMLObject["Document"][prolog_, root_, epilog_] :> (
			If[ MemberQ[prolog, XMLObject["Declaration"][___, "Version" -> Except["1.0"], ___]], failed["XML version 1.0 is the one read."]];
			If[ MemberQ[prolog, XMLObject["Doctype"][___, "InternalSubset" -> _, ___]], failed["An internal subset of a document type is not read."]];
			Scan[note["nfprserr", #] &, DeleteDuplicates[missingEntities[root]]];
			XMLObject["Document"][
				Cases[prolog, XMLObject["Comment"][_]],
				normalElement[root, <|"xml" -> $xmlNamespace|>, True, False],
				Cases[epilog, XMLObject["Comment"][_]],
				(* a document that names its type counts as checked against it *)
				Sequence @@ If[MemberQ[prolog, XMLObject["Doctype"][___]], {"Valid" -> True}, {}]
			]
		)]
	],
	document
]

failed[reason_] := (note["prserr", reason]; Throw[$Failed, document])

missingEntities[xml_] := Catenate[Cases[xml, s_String :> StringCases[s, "\[EntityStart]" ~~ name : Except["\[EntityEnd]"] .. ~~ "\[EntityEnd]" :> name], Infinity]]

(* An element as ImportString's "XMLElement" has it: the name without its prefix; a namespace
   declaration of the root under the prefix it declares and one of another element under the
   namespace of declarations; an attribute with a prefix under {namespace, name}; text with its
   runs of whitespace one space and none at its ends, unless xml:space keeps it; comments and
   processing instructions left out. *)
normalElement[XMLElement[name_String, attributes_List, content_List], scope_Association, root_, preserve_] := Module[
	{declared, inner, keep},
	declared = Association[Cases[attributes, (key_String -> value_) /; StringStartsQ[key, "xmlns:"] :> (StringDrop[key, 6] -> value)]];
	inner = Join[scope, declared];
	keep = Replace[Lookup[attributes, "xml:space", None], {"preserve" -> True, "default" -> False, _ -> preserve}];
	XMLElement[
		localName[name, inner],
		Map[normalAttribute[#, inner, root] &, attributes],
		DeleteCases[
			Replace[joinedText[DeleteCases[content, _XMLObject[___]]], {
				child_XMLElement :> normalElement[child, inner, False, keep],
				text_String :> wolframCharacters[If[keep, text, StringTrim[StringReplace[text, (" " | "\t" | "\n" | "\r") .. -> " "], " "]]]
			}, {1}],
			""
		]
	]
]

(* text on both sides of a comment is one text *)
joinedText[content_List] := Map[If[StringQ[First[#]], StringJoin[#], Splice[#]] &, SplitBy[content, StringQ]]

(* the characters Wolfram 15 reads otherwise than Unicode has them, read at their first use: each line of
   MathMLCharacters.tsv a code and the code read for it *)
$wolframCodes := $wolframCodes = Association[Map[
	Function[line, With[{fields = StringSplit[line, "\t"]}, FromDigits[First[fields]] -> FromDigits[Last[fields]]]],
	StringSplit[readText[FileNameJoin[{$mathmlDirectory, "MathMLCharacters.tsv"}]], "\n"]
]]

wolframCharacters[text_String] := If[ Max[ToCharacterCode[text], 0] < 8203, text,
	FromCharacterCode[Map[Lookup[$wolframCodes, #, #] &, ToCharacterCode[text]]]
]

localName[name_String, scope_Association] := Replace[StringSplit[name, ":", 2], {
	{prefix_, local_} :> If[KeyExistsQ[scope, prefix], local, failed["The prefix '" <> prefix <> "' has not been mapped to any URI."]],
	_ :> name
}]

normalAttribute[key_String -> value_String, scope_Association, root_] := Which[
	key === "xmlns", If[root, key, {$xmlns, key}] -> value,
	StringStartsQ[key, "xmlns:"], If[root, StringDrop[key, 6], {$xmlns, StringDrop[key, 6]}] -> value,
	StringContainsQ[key, ":"],
		Replace[StringSplit[key, ":", 2], {prefix_, local_} :>
			If[KeyExistsQ[scope, prefix], {scope[prefix], local} -> value, failed["The prefix '" <> prefix <> "' has not been mapped to any URI."]]],
	True, key -> value
]

(* ::Section:: *)
(*Rows: a sequence of tokens grouped as a notebook groups input*)

(* An item of a row is token[text], a token of the Wolfram Language as it is written; space[box],
   which a notebook reads as whitespace; or atom[box, held], a box that stands where a name can,
   with its expression in HoldComplete, or $unread where it has none. *)

(* the tokens of a text: its leaves as a notebook groups it *)
lexed[text_String] := lexed[text] = With[{boxes = If[spaceTextQ[text], text, WolframLanguageBoxes[text]]},
	If[ FailureQ[boxes] || ! FreeQ[boxes, _Failure], {token[text]},
		Map[If[spaceTextQ[#], space[#], token[#]] &, DeleteCases[leaves[boxes], ""]]
	]
]

leaves[box_String] := {box}
leaves[RowBox[parts_List]] := Catenate[Map[leaves, parts]]
leaves[other_] := {other}

$spaceCharacters = {" ", "\t", "\n", "\[NonBreakingSpace]", "\[InvisibleSpace]", "\[VeryThinSpace]", "\[ThinSpace]", "\[MediumSpace]", "\[ThickSpace]",
	"\[NegativeVeryThinSpace]", "\[NegativeThinSpace]", "\[NegativeMediumSpace]", "\[NegativeThickSpace]", "\[NoBreak]", "\[AlignmentMarker]",
	"\[IndentingNewLine]", "\:f3a2"}
spaceTextQ[text_String] := text =!= "" && StringMatchQ[text, (Alternatives @@ $spaceCharacters) ..]

(* what a token is to the reader: a name or a string, a number, or neither *)
tokenKind[text_String] := tokenKind[text] = Replace[heldToken[text], {
	HoldComplete[_Symbol] -> "Name",
	HoldComplete[_String] -> "String",
	HoldComplete[_Integer | _Real | _Rational | _Complex] :> If[StringStartsQ[text, DigitCharacter | "."], "Number", "Name"],
	_ -> "Operator"
}]

(* a token read alone, in the context of the caller *)
heldToken[text_String] := Replace[WolframLanguageHeld[text], {{held_HoldComplete} :> held, _ -> $unread}]

(* how each item is spelled for the reader: a name or an atom by its place, the rest as written;
   an opening parenthesis right after a name or an atom, no whitespace between, and the parenthesis
   that closes it, as the brackets of an application. forced are the places of parentheses that apply
   whatever stands before them, apart those of the items with whitespace before them. *)
spelled[items_List, forced_List : {}, apart_List : {}] := Module[{kinds, words, calls},
	kinds = Map[Replace[#, {token[t_] :> tokenKind[t], _atom -> "Atom"}] &, items];
	calls = callBrackets[items, kinds, forced, apart];
	words = MapIndexed[
		Function[{item, i}, Which[
			MemberQ[calls[[1]], First[i]], "[",
			MemberQ[calls[[2]], First[i]], "]",
			signQ[item], bigOperator[item],
			MatchQ[kinds[[First[i]]], "Name" | "String" | "Atom"], "p" <> ToString[First[i]],
			True, First[item]
		]],
		items
	];
	StringRiffle[words, " "]
]

(* a sum, a product or an integral sign with its limits stands where the sign alone does *)
$bigOperators = {"\[Sum]", "\[Product]", "\[Integral]", "\[ContourIntegral]"}
bigOperator[atom[(UnderscriptBox | OverscriptBox | UnderoverscriptBox | SubscriptBox | SuperscriptBox | SubsuperscriptBox)[sign_String, __], _]] := sign
bigOperator[atom[SubscriptBox[sign_String, _], _quantified]] := sign
bigOperator[_] := None
bigOperatorQ[item_] := MemberQ[$bigOperators, bigOperator[item]] || MatchQ[item, atom[_, _quantified]]
signQ[item_] := MatchQ[item, atom[_, _limits | _quantified]]

(* the places of the parentheses that apply what stands before them, and of those that close them *)
callBrackets[items_List, kinds_List, forced_List, apart_List] := Module[{stack = {}, opens = {}, closes = {}},
	Do[
		Replace[items[[i]], {
			token["("] :> (stack = {{i, MemberQ[forced, i] || (i > 1 && ! MemberQ[apart, i] && headQ[items[[i - 1]], kinds[[i - 1]]])}, stack}),
			token[")"] :> If[stack =!= {},
				If[stack[[1, 2]], opens = {opens, stack[[1, 1]]}; closes = {closes, i}];
				stack = stack[[2]]
			]
		}],
		{i, Length[items]}
	];
	{Flatten[opens], Flatten[closes]}
]

headQ[_token, "Name"] := True
headQ[atom[_, _limits | _quantified], _] := False
headQ[atom[box_, _], _] := ! MatchQ[box, _Cell | _GridBox | _FractionBox | _SqrtBox | _RadicalBox]
headQ[_, _] := False

groupedSource[source_String] := groupedSource[source] = WolframLanguageBoxes[source]

heldSource[source_String] := heldSource[source] = Block[{$Context = "Wolfram`Parser`MathMLPrivate`Slots`", $ContextPath = {"System`"}},
	Replace[WolframLanguageHeld[source], {{held_HoldComplete} :> held, _ -> $unread}]
]

(* The box of a row. The items that are not whitespace are spelled and read, and each leaf of the
   boxes that come back is the item at its place, each run of whitespace between two of them the
   whitespace items that stand there. *)
rowBox[{}] := ""
rowBox[{item_}] := itemBox[item]
rowBox[items_List] := Module[{solid, gaps, grouped, place = 0, result, all = items},
	solid = Flatten[Position[items, _token | _atom, {1}, Heads -> False]];
	If[ solid === {}, Return[RowBox[Map[itemBox, items]]]];
	(* the whitespace items before the first solid one, between each two, and after the last *)
	gaps = Map[Map[itemBox, items[[#[[1]] + 1 ;; #[[2]] - 1]]] &, Partition[Join[{0}, solid, {Length[items] + 1}], 2, 1]];
	grouped = groupedSource[spelled[items[[solid]], {}, Flatten[Position[Differences[solid], Except[1], {1}, Heads -> False]] + 1]];
	If[ Count[grouped, _String, {0, Infinity}] =!= 2 Length[solid] - 1 && Length[solid] > 1, Return[RowBox[Map[itemBox, items]]]];
	(* the items go by a variable: written into the function, a # of theirs would be its slot *)
	result = placed[grouped, Function[If[OddQ[++place], itemBox[all[[solid[[(place + 1) / 2]]]]], Splice[gaps[[place / 2 + 1]]]]]];
	result = Replace[Flatten[{First[gaps], result, Last[gaps]}], {{one_} :> one, several_ :> RowBox[several]}];
	result
]

placed[_String, next_] := next[]
placed[RowBox[parts_List], next_] := Replace[Map[placed[#, next] &, parts], {{one_} :> one, several_ :> integrand[RowBox[several]]}]

(* an integral sign takes its integrand and the differential after it as one row *)
integrand[RowBox[{sign_, body__, differential : RowBox[{"\[DifferentialD]", _}]}]] /; integralQ[sign] := RowBox[{sign, RowBox[{body, differential}]}]
integrand[box_] := box

integralQ["\[Integral]" | "\[ContourIntegral]"] := True
integralQ[(SubsuperscriptBox | UnderoverscriptBox | SubscriptBox | UnderscriptBox)["\[Integral]" | "\[ContourIntegral]", __]] := True
integralQ[_] := False

itemBox[token[text_]] := text
itemBox[space[box_]] := box
itemBox[atom[box_, _]] := box

(* ::Section:: *)
(*The expression of a row*)

(* The expression of a row in HoldComplete, read from the spelling its box was grouped from, each
   name and atom then put at its place; $unread where the reader does not take the row or one of
   its atoms has no expression. *)
rowHeld[{}] := HoldComplete[Null]
rowHeld[items_List] := Module[{places = Flatten[Position[items, _token | _atom, {1}, Heads -> False]], solid, source, held, values, forced, apart},
	solid = items[[places]];
	(* the items with whitespace before them *)
	apart = Flatten[Position[Differences[places], Except[1], {1}, Heads -> False]] + 1;
	(* an application sign before a parenthesis: the parenthesis applies *)
	forced = Flatten[Position[Partition[solid, 2, 1], {token["\[InvisibleApplication]"], token["("]}, {1}, Heads -> False]];
	solid = Delete[solid, Map[List, forced]];
	apart = Map[# - Count[forced, f_ /; f < #] &, apart];
	forced = forced - Range[0, Length[forced] - 1];
	If[ solid === {}, Return[HoldComplete[Null]]];
	source = spelled[solid, forced, apart];
	held = heldSource[source];
	If[ held === $unread, Return[$unread]];
	held = limited[held, Cases[solid, item_ /; MatchQ[item, atom[_, _limits]] || MatchQ[item, token[Alternatives @@ $bigOperators]]]];
	held = quantifiers[held, Cases[solid, atom[_, _quantified] | token["\[ForAll]" | "\[Exists]"]]];
	If[ held === $unread, Return[$unread]];
	values = Association[MapIndexed[
		Function[{item, i}, Replace[item, {
			token[text_] /; MatchQ[tokenKind[text], "Name" | "String"] :> ("p" <> ToString[First[i]] -> heldToken[text]),
			big_atom /; signQ[big] -> Nothing,
			atom[_, value_] :> ("p" <> ToString[First[i]] -> value),
			_ -> Nothing
		}]],
		solid
	]];
	If[ MemberQ[values, $unread], Return[$unread]];
	traditional[filled[held, values]]
]

(* The sums, products and integrals of an expression, in the order their signs stand in the row, each
   given the limits its sign carries: a sum over i = a to b its iterator {i, a, b}, an integral in x from a to b
   {x, a, b} in place of x. *)
limited[held_HoldComplete, signs_List] := Module[{positions = Sort[Position[held, (Sum | Product | Integrate)[___]]], result = held},
	(* integral signs one after another are one integral in several variables, each with the limits of its sign *)
	If[ Length[positions] === 1 && Length[signs] > 1 && MatchQ[signs, {atom[_, limits[_HoldComplete, _HoldComplete]] ..}] &&
			MatchQ[Extract[held, First[positions], HoldComplete], HoldComplete[Integrate[_, variables__]] /; Length[HoldComplete[variables]] === Length[signs]],
		Return[ReplacePart[held, First[positions] -> Replace[Extract[held, First[positions], HoldComplete],
			HoldComplete[Integrate[body_, variables__]] :> With[
				{ranges = MapThread[Replace[{#1, #2}, {HoldComplete[v_], atom[_, limits[HoldComplete[lower_], HoldComplete[upper_]]]} :> HoldComplete[{v, lower, upper}]] &,
					{List @@ Map[HoldComplete, HoldComplete[variables]], signs}]},
				With[{joined = Join @@ ranges}, Replace[joined, HoldComplete[r__] :> inert[Integrate[body, r]]]]
			]]] /. inert[value_] :> value]
	];
	If[ Length[positions] =!= Length[signs] || FreeQ[signs, _limits], Return[held]];
	Do[
		Replace[signs[[k]], atom[_, limits[lower_, upper_]] :> (
			If[ lower === $unread || upper === $unread, Return[$unread, Module]];
			result = ReplacePart[result, positions[[k]] -> limitedOne[Extract[result, positions[[k]], HoldComplete], lower, upper]] /. inert[value_] :> value
		)],
		{k, Length[signs], 1, -1}
	];
	(* a sum of a sum is one sum over both ranges, the outer first *)
	result //. (head : Sum | Product)[(head : Sum | Product)[body_, innerRange__], outerRange__] :> head[body, outerRange, innerRange]
]

limitedOne[HoldComplete[Integrate[body_, variable_]], HoldComplete[lower_], HoldComplete[upper_]] := inert[Integrate[body, {variable, lower, upper}]]
limitedOne[HoldComplete[(head : Sum | Product)[body_]], HoldComplete[variable_ = lower_], HoldComplete[upper_]] := inert[head[body, {variable, lower, upper}]]
limitedOne[HoldComplete[(head : Sum | Product)[body_]], HoldComplete[variable_], None] := inert[head[body, variable]]
limitedOne[HoldComplete[(head : Sum | Product)[body_]], HoldComplete[variable_Symbol], HoldComplete[upper_]] := inert[head[body, {variable, upper}]]
limitedOne[HoldComplete[other_], _, _] := inert[other]

(* the quantifiers of an expression, in the order their signs stand, each given the variables its sign carries *)
quantifiers[$unread, _] := $unread
quantifiers[held_HoldComplete, signs_List] := Module[{positions = Sort[Position[held, (ForAll | Exists)[_]]], result = held},
	If[ Length[positions] =!= Length[signs] || FreeQ[signs, _quantified], Return[held]];
	Do[
		Replace[signs[[k]], atom[_, quantified[_, variables_List]] :> (
			If[ MemberQ[variables, $unread], Return[$unread, Module]];
			result = ReplacePart[result, positions[[k]] -> Replace[{Extract[result, positions[[k]], HoldComplete], Join @@ variables},
				{HoldComplete[head_[body_]], HoldComplete[v___]} :> inert[head[v, body]]]] /. inert[value_] :> value
		)],
		{k, Length[signs], 1, -1}
	];
	result
]

(* the slots of an expression replaced by what stands there, each still held *)
filled[held_HoldComplete, values_Association] := spliced[held /. slot_Symbol /; slotQ[slot] :>
	RuleCondition[With[{name = SymbolName[Unevaluated[slot]]}, Lookup[values, name, heldToken[name]]]]]

SetAttributes[slotQ, HoldAllComplete]
slotQ[slot_Symbol] := Context[slot] === "Wolfram`Parser`MathMLPrivate`Slots`"
slotQ[_] := False

(* ::Section:: *)
(*TraditionalForm: the names it reads as functions*)

$traditionalHeads = <|
	"sin" -> Sin, "cos" -> Cos, "tan" -> Tan, "cot" -> Cot, "sec" -> Sec, "csc" -> Csc,
	"sinh" -> Sinh, "cosh" -> Cosh, "tanh" -> Tanh, "coth" -> Coth, "sech" -> Sech, "csch" -> Csch,
	"arcsin" -> ArcSin, "arccos" -> ArcCos, "arctan" -> ArcTan, "arccot" -> ArcCot, "arcsec" -> ArcSec, "arccsc" -> ArcCsc,
	"arcsinh" -> ArcSinh, "arccosh" -> ArcCosh, "arctanh" -> ArcTanh, "arccoth" -> ArcCoth, "arcsech" -> ArcSech, "arccsch" -> ArcCsch,
	"log" -> Log, "ln" -> Log, "max" -> Max, "min" -> Min, "gcd" -> GCD, "lcm" -> LCM, "det" -> Det, "arg" -> Arg,
	"erf" -> Erf, "erfc" -> Erfc, "sgn" -> Sign, "tr" -> Tr, "\[CapitalGamma]" -> Gamma, "\[Zeta]" -> Zeta
|>

$inverses = <|Sin -> ArcSin, Cos -> ArcCos, Tan -> ArcTan, Cot -> ArcCot, Sec -> ArcSec, Csc -> ArcCsc,
	Sinh -> ArcSinh, Cosh -> ArcCosh, Tanh -> ArcTanh, Coth -> ArcCoth, Sech -> ArcSech, Csch -> ArcCsch|>

(* a function with a power is the power of its value, with the power -1 its inverse; a logarithm with a subscript has that base *)
scripted[held_HoldComplete] := held /. {
	HoldPattern[Power[head_Symbol /; traditionalHeadQ[head], -1][arguments___]] /; KeyExistsQ[$inverses, $traditionalHeads[SymbolName[Unevaluated[head]]]] :>
		RuleCondition[With[{to = $inverses[$traditionalHeads[SymbolName[Unevaluated[head]]]]}, traditionalHeld[to[arguments]]]],
	HoldPattern[Power[head_Symbol /; traditionalHeadQ[head], power_][arguments___]] :> traditionalHeld[Power[head[arguments], power]],
	HoldPattern[Subscript[head_Symbol /; logQ[head], base_][arguments___]] :> traditionalHeld[Log[base, arguments]],
	HoldPattern[Subscript[head_Symbol /; besselQ[head], order_][arguments___]] :> traditionalHeld[BesselJ[order, arguments]]
} // unwrapTraditional

SetAttributes[{logQ, besselQ}, HoldAllComplete]
logQ[head_Symbol] := Context[head] =!= "System`" && SymbolName[Unevaluated[head]] === "log"
besselQ[head_Symbol] := Context[head] =!= "System`" && SymbolName[Unevaluated[head]] === "J"

traditional[held_HoldComplete] := scripted[held] /. {
	(head_Symbol /; traditionalHeadQ[head])[arguments___] :> RuleCondition[traditionalCall[HoldComplete[head], HoldComplete[arguments]]]
} //. HoldComplete[before___, traditionalHeld[inner_], after___] :> HoldComplete[before, inner, after] // unwrapTraditional
traditional[other_] := other

SetAttributes[traditionalHeadQ, HoldAllComplete]
traditionalHeadQ[head_Symbol] := Context[head] =!= "System`" && (KeyExistsQ[$traditionalHeads, SymbolName[Unevaluated[head]]] || SymbolName[Unevaluated[head]] === "exp")
traditionalHeadQ[_] := False

SetAttributes[traditionalHeld, HoldAllComplete]
traditionalCall[HoldComplete[head_], HoldComplete[arguments___]] := With[{name = SymbolName[Unevaluated[head]]},
	If[ name === "exp",
		traditionalHeld[Power[E, arguments]],
		With[{to = $traditionalHeads[name]}, traditionalHeld[to[arguments]]]
	]
]

unwrapTraditional[held_HoldComplete] := held //. traditionalHeld[inner_] :> inner

(* ::Section:: *)
(*Attributes: styles, lengths and colors*)

attribute[attributes_List, name_String] := Lookup[Cases[attributes, _[_String, _]], name, None]

number[text_String] := Replace[heldToken[text], {HoldComplete[n_Integer | n_Real] :> n, _ -> None}]

$namedColors = <|"black" -> {0, 0, 0}, "silver" -> {192, 192, 192}, "gray" -> {128, 128, 128}, "white" -> {255, 255, 255}, "maroon" -> {128, 0, 0},
	"red" -> {255, 0, 0}, "purple" -> {128, 0, 128}, "fuchsia" -> {255, 0, 255}, "green" -> {0, 128, 0}, "lime" -> {0, 255, 0}, "olive" -> {128, 128, 0},
	"yellow" -> {255, 255, 0}, "navy" -> {0, 0, 128}, "blue" -> {0, 0, 255}, "teal" -> {0, 128, 128}, "aqua" -> {0, 255, 255}|>

color[text_String] := Which[
	KeyExistsQ[$namedColors, ToLowerCase[text]], RGBColor @@ N[$namedColors[ToLowerCase[text]] / 255],
	StringMatchQ[text, "#" ~~ Repeated[HexadecimalCharacter, {6}]], RGBColor @@ N[Map[FromDigits[#, 16] &, StringPartition[StringDrop[text, 1], 2]] / 255],
	StringMatchQ[text, "#" ~~ Repeated[HexadecimalCharacter, {3}]], RGBColor @@ N[Map[FromDigits[#, 16] &, Characters[StringDrop[text, 1]]] / 15],
	True, None
]

$namedSpaces = <|"veryverythinmathspace" -> 1, "verythinmathspace" -> 2, "thinmathspace" -> 3, "mediummathspace" -> 4, "thickmathspace" -> 5,
	"verythickmathspace" -> 6, "veryverythickmathspace" -> 7|>

(* a length in ems; a number alone is taken as it is *)
ems[text_String] := Which[
	KeyExistsQ[$namedSpaces, text], N[$namedSpaces[text] / 18],
	StringStartsQ[text, "negative"], 0,
	True, Replace[StringCases[text, StartOfString ~~ n : (("-" | "+" | "") ~~ (DigitCharacter | ".") ..) ~~ unit : (LetterCharacter ... | "%") ~~ EndOfString :> {n, unit}], {
		{{n_, unit_}} :> With[{value = signed[n]},
			If[ value === None, 0,
				Replace[unit, {"" -> value, "em" :> N[value], "ex" :> value 6. / 11, "px" :> value / 11., "pt" :> value / 10.56, "in" :> value 72 / 10.56,
					"cm" :> value 72 / 2.54 / 10.56, "mm" :> value 72 / 25.4 / 10.56, "pc" :> value / 126.72, "%" :> value / 100., _ -> 0}]
			]
		],
		_ -> 0
	}]
]

signed[text_String] := Which[
	StringStartsQ[text, "-"], Replace[number[StringDrop[text, 1]], n : Except[None] :> -n],
	StringStartsQ[text, "+"], number[StringDrop[text, 1]],
	True, number[text]
]

(* a font size in points *)
points[text_String] := Replace[text, {
	"big" -> 18, "small" -> 9, "normal" -> 12,
	_ :> Replace[StringCases[text, StartOfString ~~ n : (DigitCharacter | ".") .. ~~ unit : (LetterCharacter ... | "%") ~~ EndOfString :> {number[n], unit}], {
		{{n : Except[None], "pt"}} :> N[n], {{n : Except[None], "em"}} :> n 10.56, {{n : Except[None], "%"}} :> n 10.56 / 100, {{n : Except[None], ""}} :> n, _ -> None
	}]
}]

$variants = <|
	"normal" -> {"Times", "Plain", "Plain"}, "bold" -> {"Times", "Bold", "Plain"}, "italic" -> {"Times", "Plain", "Italic"},
	"bold-italic" -> {"Times", "Bold", "Italic"}, "double-struck" -> {"Times", "Plain", "Plain"}, "script" -> {"Times", "Plain", "Plain"},
	"fraktur" -> {"Times", "Plain", "Plain"}, "bold-fraktur" -> {"Times", "Bold", "Plain"}, "bold-script" -> {"Times", "Bold", "Plain"},
	"sans-serif" -> {"Helvetica", "Plain", "Plain"}, "bold-sans-serif" -> {"Helvetica", "Bold", "Plain"},
	"sans-serif-italic" -> {"Helvetica", "Plain", "Italic"}, "sans-serif-bold-italic" -> {"Helvetica", "Bold", "Italic"},
	"monospace" -> {"Times", "Plain", "Plain"}
|>

(* the letters of an alphabet: the codes of its a and of its A *)
$alphabets = <|"double-struck" -> {63206, 63396}, "script" -> {63154, 63344}, "bold-script" -> {63154, 63344}, "fraktur" -> {63180, 63370}, "bold-fraktur" -> {63180, 63370}|>

lettered[text_String, variant_] := If[ KeyExistsQ[$alphabets, variant] && StringLength[text] === 1,
	With[{code = First[ToCharacterCode[text]], starts = $alphabets[variant]},
		Which[
			KeyExistsQ[$letterlike, {StringDelete[variant, "bold-"], text}], FromCharacterCode[$letterlike[{StringDelete[variant, "bold-"], text}]],
			97 <= code <= 122, FromCharacterCode[starts[[1]] + code - 97],
			65 <= code <= 90, FromCharacterCode[starts[[2]] + code - 65],
			True, text
		]
	],
	text
]

(* the script and Gothic letters Unicode has among its letterlike symbols *)
$letterlike = <|{"script", "B"} -> 8492, {"script", "E"} -> 8496, {"script", "F"} -> 8497, {"script", "H"} -> 8459, {"script", "I"} -> 8464,
	{"script", "L"} -> 8466, {"script", "M"} -> 8499, {"script", "R"} -> 8475, {"script", "e"} -> 8495, {"script", "g"} -> 8458, {"script", "o"} -> 8500,
	{"fraktur", "C"} -> 8493, {"fraktur", "H"} -> 8460, {"fraktur", "I"} -> 8465, {"fraktur", "R"} -> 8476, {"fraktur", "Z"} -> 8488|>

(* the style options the attributes of a token or of an mstyle give, in the order Wolfram 15 writes them *)
styleOptions[attributes_List] := Module[{variant, family, weight, slant, size, fore, back},
	variant = attribute[attributes, "mathvariant"];
	{family, weight, slant} = If[variant === None, {None, None, None}, Lookup[$variants, variant, {"Times", "Plain", "Plain"}]];
	family = Replace[attribute[attributes, "fontfamily"], None -> family];
	weight = Replace[attribute[attributes, "fontweight"], {"bold" -> "Bold", "normal" -> "Plain", _ -> weight}];
	slant = Replace[attribute[attributes, "fontstyle"], {"italic" -> "Italic", "normal" -> "Plain", _ -> slant}];
	size = Replace[Replace[attribute[attributes, "mathsize"], None :> attribute[attributes, "fontsize"]], s_String :> points[s]];
	fore = Replace[Replace[attribute[attributes, "mathcolor"], None :> attribute[attributes, "color"]], s_String :> color[s]];
	back = Replace[attribute[attributes, "mathbackground"], {"transparent" -> transparent, s_String :> color[s]}];
	DeleteCases[{
		FontFamily -> family, FontSize -> size, FontWeight -> weight, FontSlant -> slant, FontColor -> fore, Background -> back
	}, _ -> None] /. transparent -> None
]

styled[box_, {}] := box
styled[box_, options_List] := StyleBox[box, Sequence @@ options]

(* ::Section:: *)
(*Presentation elements*)

$tokenElements = {"mi", "mn", "mo", "mtext", "ms", "mspace", "mglyph"}
$presentationElements = Join[$tokenElements, {"mrow", "mfrac", "msqrt", "mroot", "mstyle", "merror", "mpadded", "mphantom", "mfenced", "menclose",
	"msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts", "mtable", "mlabeledtr", "mtr", "mtd", "maligngroup", "malignmark",
	"none"}]

presentationQ[XMLElement[name_String, __]] := MemberQ[$presentationElements, name]
presentationQ[_] := False

text[content_List] := StringJoin[Cases[content, _String]]

(* The items an element gives the row it stands in. An element of one kind, presentation or content,
   within one of another, or within one of neither, carries the tag of its kind. *)
$kind = None

items[element_XMLElement] := With[{its = kind[element], outer = $kind},
	Block[{$kind = its}, If[its === None || its === outer, own[element], tagged[own[element], its, element]]]
]

tagged[row_List, tag_, element_] := With[{box = rowBox[row]},
	If[ row === {} || box === "" || untaggedQ[element], row, {atom[TagBox[box, tag, AutoDelete -> True], rowHeld[row]]}]
]

(* the elements whose boxes carry no tag: those with nothing in them that give a box all the same *)
untaggedQ[XMLElement["mrow" | "msqrt" | "maligngroup" | "malignmark", _, {}]] := True
untaggedQ[_] := False

own[XMLElement["mrow", _, {}]] := {token["\[Placeholder]"]}
own[XMLElement["mrow", _, content_List]] := Catenate[Map[items, applied[content]]]

(* an application sign before a parenthesis of the same row is left out: the parenthesis applies *)
applied[content_List] := content //. {
	{before___, XMLElement["mo", _, {"\[InvisibleApplication]"}], open : XMLElement["mo", _, {"("}], after___} :> {before, open, after},
	(* an invisible multiplication between two children, neither a bracket that faces it, is the space of a product *)
	{before___, left : Except[XMLElement["mo", _, {"\[InvisibleTimes]" | ")" | "]" | "}"}]], XMLElement["mo", attributes_, {"\[InvisibleTimes]"}],
			right : Except[XMLElement["mo", _, {"\[InvisibleTimes]" | "(" | "[" | "{"}]], after___} :>
		{before, left, XMLElement["mo", attributes, {" "}], right, after}
}

own[XMLElement[name : "mi" | "mn" | "mo", attributes_, content_List]] := With[
	{options = Join[styleOptions[attributes], If[name === "mo", operatorOptions[attributes], {}]],
		tokens = If[name === "mo", operatorTokens, lexed][lettered[text[content], attribute[attributes, "mathvariant"]]]},
	If[ options === {} || tokens === {}, tokens, {styledAtom[tokens, options]}]
]

(* an operator whose text is operator characters alone is one token, as it is written *)
operatorTokens[text_String] := With[{tokens = lexed[text]},
	If[ Length[tokens] > 1 && AllTrue[tokens, MatchQ[#, token[t_] /; tokenKind[t] === "Operator"] &], {token[text]}, tokens]
]

(* how an operator stretches and where its limits go *)
operatorOptions[attributes_List] := Join[
	Replace[attribute[attributes, "stretchy"], {"false" -> {SpanMinSize -> 1, SpanMaxSize -> 1}, "true" -> {SpanMinSize -> 0, SpanMaxSize -> Infinity}, _ -> {}}],
	Replace[attribute[attributes, "minsize"], {s_String :> Replace[number[s], {None -> {}, n_ :> {SpanMinSize -> n}}], _ -> {}}],
	Replace[attribute[attributes, "maxsize"], {s_String :> Replace[number[s], {None -> {}, n_ :> {SpanMaxSize -> n}}], _ -> {}}],
	Replace[attribute[attributes, "movablelimits"], {"true" -> {LimitsPositioning -> True}, _ -> {}}]
]

styledAtom[tokens_List, options_List] := atom[styled[rowBox[tokens], options], rowHeld[tokens]]

own[XMLElement["mtext", attributes_, content_List]] := With[{string = text[content], options = styleOptions[attributes]},
	Which[
		string === "", {},
		spaceTextQ[string] && StringLength[string] === 1, {space[styled[StyleBox[string, "Text"], options]]},
		True, {atom[styled[Cell[string, "Text"], options], With[{s = string}, HoldComplete[TextCell[s, "Text"]]]]}
	]
]

own[XMLElement["ms", attributes_, content_List]] := With[
	{options = styleOptions[attributes], tokens = lexed[
		Replace[attribute[attributes, "lquote"], None -> "\""] <> text[content] <> Replace[attribute[attributes, "rquote"], None -> "\""]]},
	If[ options === {}, tokens, {styledAtom[tokens, options]}]
]

own[XMLElement["mspace", attributes_, {}]] := {space[AdjustmentBox[
	Replace[attribute[attributes, "linebreak"], {"newline" -> "\n", "nobreak" -> "\[NoBreak]", "indentingnewline" -> "\[IndentingNewLine]", _ -> "\[InvisibleSpace]"}],
	BoxMargins -> {
		{0, Replace[attribute[attributes, "width"], {None -> 0, s_String :> ems[s]}]},
		{Replace[attribute[attributes, "depth"], {None -> 0, s_String :> tall[ems[s]]}], Replace[attribute[attributes, "height"], {None -> 0, s_String :> tall[ems[s]]}]}
	}
]]}

tall[0] := 0
tall[length_] := length 11 / 6.

own[XMLElement["maligngroup" | "malignmark", _, {}]] := {space["\[AlignmentMarker]"]}
own[XMLElement["none", _, {}]] := {token["None"]}

(* semantics: its first child, and with it a MathML annotation, which Wolfram 15 keeps beside it *)
(* An annotation in the Wolfram Language holds the boxes the MathML was written from, and they are taken in place
   of its reading. The text is read, not evaluated: it counts where it is boxes and what boxes hold. *)
own[XMLElement["semantics", _, {_XMLElement, ___, XMLElement["annotation", {___, "encoding" -> "Mathematica", ___}, {code_String}], ___}]] /;
		annotated[code] =!= None := Replace[annotated[code], {HoldComplete[text_String] :> lexed[text], HoldComplete[box_] :> With[{read = notebookBoxes[box]}, {atom[read, boxHeld[read]]}]}]

annotated[code_String] := annotated[code] = Replace[WolframLanguageHeld[code], {{held_HoldComplete} /; inertQ[held] :> held, _ -> None}]

$inertHeads = {List, Rule, RuleDelayed, Function, Slot, DirectedInfinity, RGBColor, GrayLevel, Offset, Scaled, Cell, TextData, BoxData}

inertQ[HoldComplete[_String | _Integer | _Real]] := True
inertQ[HoldComplete[symbol_Symbol]] := Context[Unevaluated[symbol]] === "System`"
inertQ[HoldComplete[Function[___]]] := True
inertQ[HoldComplete[head_Symbol[arguments___]]] := (MemberQ[$inertHeads, Unevaluated[head]] || StringEndsQ[SymbolName[Unevaluated[head]], "Box"]) &&
	Context[Unevaluated[head]] === "System`" && AllTrue[List @@ Map[HoldComplete, HoldComplete[arguments]], inertQ]
inertQ[_] := False

(* The expression of boxes that come whole, as TraditionalForm reads them: a template by the function of its name,
   a fraction a quotient, a grid its rows, a row read as a row of MathML is. *)
boxHeld[TemplateBox[{}, name_String, ___]] := If[ Names["System`" <> name] === {}, $unread, heldToken["System`" <> name]]
boxHeld[TemplateBox[{body_, variable_, point_}, "Limit2Arg", ___]] := combine[Map[boxHeld, {body, variable, point}], Limit[slot[1], slot[2] -> slot[3]]]
boxHeld[TemplateBox[{body_, variable_, point_, direction_, _}, "LimitWithSuperscript", ___]] :=
	combine[Map[boxHeld, {body, variable, point, direction}], Limit[slot[1], slot[2] -> slot[3], Direction -> slot[4]]]
boxHeld[TemplateBox[{sequence_}, name_String, ___]] /; StringEndsQ[name, "Seq"] && Names["System`" <> StringDrop[name, -3]] =!= {} :=
	With[{all = commaHeld[sequence], head = Symbol["System`" <> StringDrop[name, -3]]},
		If[ MemberQ[all, $unread], $unread, With[{joined = Join @@ all}, head @@@ HoldComplete[joined]]]
	]
boxHeld[TemplateBox[arguments_List, name_String, ___]] := With[{held = Map[boxHeld, arguments]},
	If[ MemberQ[held, $unread] || Names["System`" <> name] === {}, $unread,
		With[{head = Symbol["System`" <> name], all = Join @@ held}, head @@@ HoldComplete[all]]
	]
]
boxHeld[TagBox[box_, HoldForm, ___]] := combine[{boxHeld[box]}, HoldForm[slot[1]]]
boxHeld[TagBox[GridBox[{{"\[Piecewise]", GridBox[{cases___, {default_, TagBox["True", "PiecewiseDefault", ___]}}, ___]}}, ___], "Piecewise", ___]] :=
	combine[{boxHeld[GridBox[{cases}]], boxHeld[default]}, Piecewise[slot[1], slot[2]]]
boxHeld[TagBox[_, Function[{}, value_], ___]] := HoldComplete[value]
boxHeld[TagBox[_, Function[value_], ___]] := HoldComplete[value]
boxHeld[TagBox[SuperscriptBox[function_, _], InverseFunction, ___]] := combine[{boxHeld[function]}, InverseFunction[slot[1]]]
boxHeld[TagBox[GridBox[{{"\[Piecewise]", GridBox[cases_List, ___]}}, ___], "Piecewise", ___]] := combine[{boxHeld[GridBox[cases]]}, Piecewise[slot[1]]]
boxHeld[TagBox[box_, ___]] := boxHeld[box]
boxHeld[(StyleBox | AdjustmentBox | FrameBox | ButtonBox | InterpretationBox)[box_, ___]] := boxHeld[box]
boxHeld[Cell[text_String, style_String, ___]] := HoldComplete[TextCell[text, style]]
boxHeld[box_String] := rowHeld[lexed[box]]
boxHeld[RowBox[parts_List]] := rowHeld[Catenate[Map[boxItems, parts]]]
boxHeld[FractionBox[numerator_, denominator_, ___]] := fractionHeld[numerator, denominator, boxHeld[numerator], boxHeld[denominator]]
boxHeld[SqrtBox[body_, ___]] := combine[{boxHeld[body]}, Sqrt[slot[1]]]
boxHeld[RadicalBox[body_, index_, ___]] := combine[{boxHeld[body], boxHeld[index]}, Power[slot[1], Times[1, Power[slot[2], -1]]]]
boxHeld[SuperscriptBox[base_, script_String, ___]] /; KeyExistsQ[$primes, script] := With[{n = $primes[script]}, combine[{boxHeld[base]}, Derivative[n][slot[1]]]]
boxHeld[SuperscriptBox[base_, TagBox[RowBox[{"(", orders_, ")"}], Derivative, ___], ___]] :=
	With[{all = commaHeld[orders], function = boxHeld[base]},
		If[ MemberQ[all, $unread] || function === $unread, $unread, With[{joined = Join @@ all}, combine[{Derivative @@@ HoldComplete[joined], function}, slot[1][slot[2]]]]]
	]
boxHeld[SuperscriptBox[base_, script_, ___]] := combine[{boxHeld[base], boxHeld[script]}, Power[slot[1], slot[2]]]
boxHeld[SubscriptBox[sign_String, lower_, ___]] /; MemberQ[$bigOperators, sign] := limits[boxHeld[lower], None]
boxHeld[UnderscriptBox[sign_String, lower_, ___]] /; MemberQ[$bigOperators, sign] := limits[boxHeld[lower], None]
boxHeld[(SubsuperscriptBox | UnderoverscriptBox)[sign_String, lower_, upper_, ___]] /; MemberQ[$bigOperators, sign] := limits[boxHeld[lower], boxHeld[upper]]
boxHeld[SubscriptBox[quantifier : "\[ForAll]" | "\[Exists]", variables_, ___]] := quantified[quantifier, commaHeld[variables]]
boxHeld[SubscriptBox[base_, script_, ___]] := With[{all = Prepend[commaHeld[script], boxHeld[base]]},
	If[ MemberQ[all, $unread], $unread, With[{joined = Join @@ all}, Subscript @@@ HoldComplete[joined]]]
]
boxHeld[SubsuperscriptBox[base_, lower_, upper_, ___]] := combine[Map[boxHeld, {base, lower, upper}], Power[Subscript[slot[1], slot[2]], slot[3]]]
boxHeld[GridBox[rows_List, ___]] := With[{values = Map[boxHeld, rows, {2}]},
	If[ MemberQ[values, $unread, {2}], $unread, spliced[HoldComplete[values] /. List -> inertList] /. inertList -> List]
]
boxHeld[_] := $unread

(* the expressions of the parts of a box between its commas *)
commaHeld[RowBox[parts_List]] /; MemberQ[parts, ","] := Map[boxHeld[Replace[#, {{one_} :> one, several_ :> RowBox[several]}]] &, DeleteCases[SplitBy[parts, # === "," &], {","}]]
commaHeld[box_] := {boxHeld[box]}

boxItems[box_String] := lexed[box]
boxItems[RowBox[parts_List]] := Catenate[Map[boxItems, parts]]
boxItems[box_] := {atom[box, boxHeld[box]]}

own[XMLElement["semantics", _, {main_XMLElement, annotations___}]] := With[
	{first = items[main], other = FirstCase[{annotations},
		XMLElement["annotation-xml", {___, "encoding" -> "MathML-Content" | "MathML-Presentation", ___}, {inner_XMLElement}] :> inner]},
	Which[
		MissingQ[other], first,
		(* the presentation stands first, whichever of the two the annotation is *)
		contentQ[main] && presentationQ[other], With[{shown = items[other]}, {atom[TagBox[rowBox[shown], "AnnotationsTagWrapper"[rowBox[first]], AutoDelete -> True], rowHeld[shown]]}],
		True, {atom[TagBox[rowBox[first], "AnnotationsTagWrapper"[Block[{$beside = True}, rowBox[items[other]]]], AutoDelete -> True], rowHeld[first]]}
	]
]
own[XMLElement["annotation", _, _]] := {}
own[XMLElement["annotation-xml", _, {inner_XMLElement}]] := items[inner]

own[XMLElement["maction", _, {only_XMLElement}]] := With[{row = items[only]}, {atom[ButtonBox[rowBox[row]], rowHeld[row]]}]

own[element : XMLElement[name_String, attributes_, content_List]] := Which[
	contentQ[element], {contentAtom[element]},
	True, Replace[structure[name, attributes, content], {
		None :> unknown[element],
		result_List :> result,
		result_ :> {result}
	}]
]
items[string_String] := (note["bmml", "string", string]; lexed["\"" <> string <> "\""])

(* what Wolfram 15 makes of an element it does not know, or one with the wrong children: name(children) *)
unknown[element : XMLElement[name_String, _, {}]] := (note["unkntag", name]; lexed[name])
unknown[element : XMLElement[name_String, _, content_List]] := (
	note["unknstrc", element];
	Join[lexed[name], {token["("]}, Riffle[Map[argument, content], token[","]], {token[")"]}]
)

(* a child as one item of a row *)
argument[string_String] := Replace[lexed[string], {{one_} :> one, several_ :> atom[rowBox[several], rowHeld[several]]}]
argument[element_] := Replace[items[element], {{one_} :> one, several_ :> atom[rowBox[several], rowHeld[several]]}]

(* the box and the expression of the row a child gives *)
part[element_] := With[{row = items[element]}, {rowBox[row], rowHeld[row]}]
partBox[element_] := rowBox[items[element]]

(* the children of an element that takes a row *)
inferred[content_List] := items[XMLElement["mrow", {}, content]]
inferred[{}] := {}

(* the expression built of the expressions of parts, $unread where one is *)
SetAttributes[combine, HoldRest]
combine[parts_List, template_] := If[ MemberQ[parts, $unread], $unread,
	Fold[Function[{held, i}, held /. slot[i] :> RuleCondition[parts[[i]]]], HoldComplete[template], Range[Length[parts]]] //. HoldComplete[before___, HoldComplete[inner_], after___] :> HoldComplete[before, inner, after] // spliced
]

SetAttributes[inert, HoldAllComplete]

spliced[held_HoldComplete] := Module[{result = held, position},
	While[(position = FirstPosition[result, _HoldComplete, None, {1, Infinity}, Heads -> True]) =!= None,
		result = ReplacePart[result, position -> Extract[result, Append[position, 1], inert]] /. inert[value_] :> value;
	];
	result
]

structure["mfrac", attributes_, {numerator_, denominator_}] := With[{n = part[numerator], d = part[denominator]},
	atom[
		FractionBox[First[n], First[d], Sequence @@ Replace[attribute[attributes, "linethickness"], {
			None -> {}, "thin" -> {FractionLine -> 0.5}, "medium" -> {FractionLine -> 1.}, "thick" -> {FractionLine -> 2.},
			s_String :> Replace[StringCases[s, StartOfString ~~ n0 : (DigitCharacter | ".") .. ~~ unit : LetterCharacter ... ~~ EndOfString :> {number[n0], unit}],
				{{{value : Except[None], ""}} :> {FractionLine -> value}, {{value : Except[None], _}} :> {FractionLine -> N[value]}, _ -> {}}]
		}]],
		fractionHeld[First[n], First[d], Last[n], Last[d]]
	]
]

(* a quotient; of two differentials a derivative; a product over a denominator one product *)
fractionHeld[RowBox[{"\[DifferentialD]", of_}], RowBox[{"\[DifferentialD]", by_}], _, _] := combine[{boxHeld[of], boxHeld[by]}, Dt[slot[1], {slot[2]}]]
fractionHeld[RowBox[{SuperscriptBox["\[DifferentialD]", order_], of_}], RowBox[{"\[DifferentialD]", SuperscriptBox[by_, order_]}], _, _] :=
	combine[{boxHeld[of], boxHeld[by], boxHeld[order]}, Dt[slot[1], {slot[2], slot[3]}]]
fractionHeld[RowBox[{"\[PartialD]", of_}], RowBox[{"\[PartialD]", by_}], _, _] := combine[{boxHeld[of], boxHeld[by]}, D[slot[1], {slot[2]}]]
fractionHeld[Except[RowBox[{"(", __}]], _, HoldComplete[Times[factors__]], HoldComplete[denominator_]] := HoldComplete[Times[factors, Power[denominator, -1]]]
fractionHeld[_, _, numerator_, denominator_] := combine[{numerator, denominator}, Times[slot[1], Power[slot[2], -1]]]

structure["msqrt", _, content_List] := With[{row = inferred[content]},
	atom[SqrtBox[rowBox[row]], combine[{rowHeld[row]}, Sqrt[slot[1]]]]
]

structure["mroot", _, {base_, index_}] := With[{b = part[base], i = part[index]},
	atom[RadicalBox[First[b], First[i]], combine[{Last[b], Last[i]}, Power[slot[1], Times[1, Power[slot[2], -1]]]]]
]

structure["mstyle", attributes_, content : {__}] := With[{row = inferred[content], options = Join[styleOptions[attributes], mstyleOptions[attributes]]},
	If[ options === {}, row, {atom[restyled[rowBox[row], options], rowHeld[row]]}]
]

(* a style around a style is one style, the inner settings before the outer ones they do not give *)
restyled[StyleBox[box_, inner___Rule], outer_List] := StyleBox[box, inner, Sequence @@ DeleteCases[outer, HoldPattern[key_ -> _] /; MemberQ[Keys[{inner}], key]]]
restyled[box_, options_List] := styled[box, options]

mstyleOptions[attributes_List] := Join[
	If[ attribute[attributes, "mathbackground"] === None, Replace[attribute[attributes, "background"], {s_String :> Replace[color[s], {None -> {}, c_ :> {Background -> c}}], _ -> {}}], {}],
	Replace[attribute[attributes, "scriptsizemultiplier"], {s_String :> Replace[number[s], {None -> {}, n_ :> {ScriptSizeMultipliers -> N[n]}}], _ -> {}}],
	Replace[attribute[attributes, "displaystyle"], {"true" -> {GridBoxOptions -> {AllowScriptLevelChange -> False}}, "false" -> {GridBoxOptions -> {AllowScriptLevelChange -> True}}, _ -> {}}],
	Replace[attribute[attributes, "scriptlevel"], {
		s_String /; StringMatchQ[s, DigitCharacter ..] :> {ScriptLevel -> FromDigits[s]},
		s_String /; StringMatchQ[s, "-" ~~ DigitCharacter ..] :> {ScriptLevel -> 0},
		_ -> {}
	}]
]

structure["mphantom", _, content : {__}] := With[{row = inferred[content]}, space[StyleBox[rowBox[row], ShowContents -> False]]]
structure["merror", _, content : {__}] := With[{row = inferred[content]}, atom[ErrorBox[rowBox[row]], $unread]]
structure["mpadded", attributes_, content : {__}] := With[{row = inferred[content], length = Function[name, Replace[attribute[attributes, name], {None -> 0, s_String :> ems[s]}]]},
	atom[AdjustmentBox[rowBox[row], BoxMargins -> {{length["lspace"], length["width"]}, {tall[length["depth"]], tall[length["height"]]}}], rowHeld[row]]
]

$encloseMargins = {2.7741796875, 3.50009765625}

structure["menclose", attributes_, content : {_}] := With[{row = inferred[content], sides = Function[{left, right},
		{BoxFrame -> {{left, right}, {0, 1}}, FrameMargins -> {{$encloseMargins[[1]], right $encloseMargins[[1]]}, {$encloseMargins[[2]], $encloseMargins[[2]]}}}]},
	Replace[attribute[attributes, "notation"], {
		None | "longdiv" :> atom[FrameBox[rowBox[row], Sequence @@ sides[1, 0]], rowHeld[row]],
		"actuarial" :> atom[FrameBox[rowBox[row], Sequence @@ sides[0, 1]], rowHeld[row]],
		"radical" :> atom[SqrtBox[rowBox[row]], combine[{rowHeld[row]}, Sqrt[slot[1]]]],
		_ -> None
	}]
]
structure["mtd", _, content_List] := inferred[content]

structure["mfenced", attributes_, content_List] := Module[{open, close, separators, between},
	open = Replace[attribute[attributes, "open"], None -> "("];
	close = Replace[attribute[attributes, "close"], None -> ")"];
	{open, close} = Replace[{open, close}, {"|", "|"} -> {"\[LeftBracketingBar]", "\[RightBracketingBar]"}];
	separators = Replace[attribute[attributes, "separators"], {None -> {","}, s_String :> Characters[StringDelete[s, " "]]}];
	between = Table[If[separators === {}, {}, lexed[separators[[Min[i, Length[separators]]]]]], {i, Max[Length[content] - 1, 0]}];
	Join[lexed[open], Catenate[Riffle[Map[items, content], between]], lexed[close]]
]

scriptHeld[base_, script_, HoldComplete[head_]] := combine[{base, script}, head[slot[1], slot[2]]]

(* a script that is a sequence with commas gives each of its parts *)
commaParts[element_] := With[{row = items[element]},
	If[ MemberQ[row, token["," | "\[InvisibleComma]"]],
		Map[rowHeld, DeleteCases[SplitBy[row, MatchQ[token["," | "\[InvisibleComma]"]]], {token["," | "\[InvisibleComma]"]}]],
		{rowHeld[row]}
	]
]

structure["msub", attributes_, {base_}] := (note["msngargs", "msub"]; structure["msub", attributes, {base, XMLElement["mi", {}, {"\[Placeholder]"}]}])
structure["msub", attributes_, {base_, script_}] := With[{b = part[base], s = partBox[script], subscripts = commaParts[script]},
	atom[
		shifted[SubscriptBox[First[b], s], attribute[attributes, "subscriptshift"], 1],
		If[ MatchQ[First[b], "\[ForAll]" | "\[Exists]"], quantified[First[b], subscripts],
		If[ MemberQ[$bigOperators, First[b]], limits[rowHeld[items[script]], None],
		If[ MemberQ[subscripts, $unread] || Last[b] === $unread, $unread,
			With[{all = Join[HoldComplete @@ {Last[b]}, HoldComplete @@ subscripts]}, spliced[Subscript @@@ HoldComplete[all]]]
		]]]
	]
]

shifted[box_, None, _] := box
shifted[box_, length_String, place_] := StyleBox[box, ScriptBaselineShifts -> ReplacePart[{Automatic, Automatic}, place -> tall[ems[length]]]]

$superscriptHeads = <|"*" -> SuperStar, "+" -> SuperPlus, "\[Dagger]" -> SuperDagger, "-" -> SuperMinus|>
$primes = <|"\[Prime]" -> 1, "\[DoublePrime]" -> 2, "\[Prime]\[Prime]" -> 2, "\[Prime]\[Prime]\[Prime]" -> 3|>

structure["msup", attributes_, {base_}] := (note["msngargs", "msup"]; structure["msup", attributes, {base, XMLElement["mi", {}, {"\[Placeholder]"}]}])
structure["msup", attributes_, {base_, script_}] := Module[{b = part[base], row = items[script], s, held},
	(* primes next to one another are one token *)
	row = row //. {before___, token[p1_String], token[p2_String], after___} /; StringMatchQ[p1 <> p2, "\[Prime]" ..] :> {before, token[p1 <> p2], after};
	s = rowBox[row];
	held = Which[
		MatchQ[s, _String] && KeyExistsQ[$primes, s], With[{n = $primes[s]}, combine[{Last[b]}, Derivative[n][slot[1]]]],
		MatchQ[s, _String] && KeyExistsQ[$superscriptHeads, s], With[{head = $superscriptHeads[s]}, combine[{Last[b]}, head[slot[1]]]],
		s === "T", combine[{Last[b]}, Transpose[slot[1]]],
		MatchQ[s, RowBox[{"(", _, ")"}]], boxHeld[SuperscriptBox[First[b], TagBox[s, Derivative]]],
		True, combine[{Last[b], rowHeld[row]}, Power[slot[1], slot[2]]]
	];
	atom[shifted[SuperscriptBox[First[b], If[MatchQ[s, RowBox[{"(", _, ")"}]], TagBox[s, Derivative], s]], attribute[attributes, "superscriptshift"], 2], held]
]

structure["msubsup", attributes_, {base_, sub_}] := (note["msngargs", "msubsup"]; structure["msubsup", attributes, {base, sub, XMLElement["mi", {}, {"\[Placeholder]"}]}])
structure["msubsup", _, {base_, sub_, super_}] := With[{b = part[base], lower = part[sub], upper = part[super]},
	atom[SubsuperscriptBox[First[b], First[lower], First[upper]],
		If[ MemberQ[$bigOperators, First[b]], limits[Last[lower], Last[upper]], combine[{Last[b], Last[lower], Last[upper]}, Power[Subscript[slot[1], slot[2]], slot[3]]]]]
]

$overAccents = <|"^" -> OverHat, "~" -> OverTilde, "\[RightVector]" -> OverVector, "." -> OverDot, "_" -> OverBar|>
$underAccents = <|"_" -> UnderBar|>

diacritical[attributes_, name_String] := Replace[attribute[attributes, name], {"true" -> {DiacriticalPositioning -> True}, "false" -> {DiacriticalPositioning -> False}, _ -> {}}]

structure["munder", attributes_, {base_}] := (note["msngargs", "munder"]; structure["munder", attributes, {base, XMLElement["mi", {}, {"\[Placeholder]"}]}])
structure["munder", attributes_, {base_, script_}] := With[{b = part[base], s = part[script]},
	atom[UnderscriptBox[First[b], First[s], Sequence @@ diacritical[attributes, "accentunder"]],
		Which[
			MemberQ[$bigOperators, First[b]], limits[Last[s], None],
			KeyExistsQ[$underAccents, First[s]], With[{head = $underAccents[First[s]]}, combine[{Last[b]}, head[slot[1]]]],
			True, scriptHeld[Last[b], Last[s], HoldComplete[Underscript]]
		]]
]

structure["mover", attributes_, {base_}] := (note["msngargs", "mover"]; structure["mover", attributes, {base, XMLElement["mi", {}, {"\[Placeholder]"}]}])
structure["mover", attributes_, {base_, script_}] := With[{b = part[base], s = part[script]},
	atom[OverscriptBox[First[b], First[s], Sequence @@ diacritical[attributes, "accent"]],
		Which[
			First[s] === "\[DoubleDot]", combine[{Last[b]}, OverDot[slot[1], 2]],
			KeyExistsQ[$overAccents, First[s]], With[{head = $overAccents[First[s]]}, combine[{Last[b]}, head[slot[1]]]],
			True, scriptHeld[Last[b], Last[s], HoldComplete[Overscript]]
		]]
]

structure["munderover", attributes_, {base_, under_}] := (note["msngargs", "munderover"]; structure["munderover", attributes, {base, under, XMLElement["mi", {}, {"\[Placeholder]"}]}])
structure["munderover", _, {base_, under_, over_}] := With[{b = part[base], lower = part[under], upper = part[over]},
	atom[UnderoverscriptBox[First[b], First[lower], First[upper]],
		If[ MemberQ[$bigOperators, First[b]], limits[Last[lower], Last[upper]], combine[{Last[b], Last[lower], Last[upper]}, Underoverscript[slot[1], slot[2], slot[3]]]]]
]

(* a table: its rows, each the boxes of its cells *)
structure["mtable", attributes_, rows : {XMLElement["mtr" | "mlabeledtr", _, _] ..}] := Module[{cells, grid, options},
	cells = Map[
		Replace[#, {XMLElement[_, _, {}] :> {{"mtr", HoldComplete[mtr]}}, XMLElement[_, _, row_List] :> Map[With[{r = cellRow[#]}, {rowBox[r], rowHeld[r]}] &, row]}] &,
		rows
	];
	options = tableOptions[attributes];
	grid = GridBox[
		Map[Replace[#, {{{"mtr", _}} -> "mtr", row_List :> row[[All, 1]]}] &, cells],
		Sequence @@ DeleteCases[options, HoldPattern[GridBaseline -> _]]
	];
	If[ MemberQ[rows, XMLElement[_, _, {}]], note["unkntag", "mtr"]];
	atom[
		Replace[Cases[options, HoldPattern[GridBaseline -> _]], {{} -> grid, baseline_ :> StyleBox[grid, Sequence @@ baseline]}],
		With[{values = Map[#[[All, 2]] &, cells]},
			If[ MemberQ[values, $unread, {2}], $unread, spliced[HoldComplete[values] /. List -> inertList] /. inertList -> List]
		]
	]
]

cellRow[XMLElement["mtd", _, content_List]] := inferred[content]
cellRow[other_] := items[other]

words[None] := {}
words[text_String] := StringSplit[text]

(* a list of settings as a grid takes them: the last one repeated *)
repeated[{}] := {}
repeated[{one_}] := {{one}}
repeated[several_List] := Append[Most[several], {Last[several]}]

tableOptions[attributes_List] := Module[{columns, rows, frame, rowLines, columnLines},
	columns = Map[Replace[#, {"left" -> Left, "right" -> Right, _ -> Center}] &, words[attribute[attributes, "columnalign"]]];
	rows = Map[Replace[#, {"top" -> Top, "bottom" -> Bottom, "center" -> Center, "axis" -> Axis, _ -> Baseline}] &, words[attribute[attributes, "rowalign"]]];
	frame = attribute[attributes, "frame"];
	rowLines = words[attribute[attributes, "rowlines"]];
	columnLines = words[attribute[attributes, "columnlines"]];
	Join[
		If[ columns === {} && rows === {}, {},
			{GridBoxAlignment -> {"Columns" -> repeated[Replace[columns, {} -> {Center}]], "Rows" -> repeated[Replace[rows, {} -> {Baseline}]]}}],
		If[ attribute[attributes, "rowspacing"] === None && attribute[attributes, "columnspacing"] === None, {},
			{GridBoxSpacings -> {
				"Columns" -> Join[{Offset[0.4 0.7]}, repeated[Map[Offset[ems[#] 0.7] &, Replace[words[attribute[attributes, "columnspacing"]], {} -> {"0.8em"}]]], {Offset[0.4 0.7]}],
				"Rows" -> Join[{Offset[0.2]}, repeated[Map[Offset[ems[#] 11 / 6 0.4] &, Replace[words[attribute[attributes, "rowspacing"]], {} -> {"1.0ex"}]]], {Offset[0.2]}]
			}}],
		If[ frame === None && rowLines === {} && columnLines === {}, {},
			With[{edge = Replace[frame, {"solid" -> True, "dashed" -> AbsoluteThickness[0.5], _ -> False}], line = Function[Replace[#, {"solid" -> True, "dashed" -> AbsoluteThickness[0.5], _ -> False}]]},
				{GridBoxDividers -> {
					"Columns" -> dividers[edge, Map[line, columnLines]],
					"Rows" -> dividers[edge, Map[line, rowLines]]
				}}
			]
		],
		Replace[attribute[attributes, "equalcolumns"], {"true" -> {ColumnsEqual -> True}, _ -> {}}],
		Replace[attribute[attributes, "equalrows"], {"true" -> {RowsEqual -> True}, _ -> {}}],
		Replace[attribute[attributes, "displaystyle"], {"true" -> {AllowScriptLevelChange -> False}, _ -> {}}],
		Replace[attribute[attributes, "align"], {"axis" -> {GridBaseline -> Axis}, "top" -> {GridBaseline -> Top}, "bottom" -> {GridBaseline -> Bottom},
			"center" -> {GridBaseline -> Center}, "baseline" -> {GridBaseline -> Baseline}, _ -> {}}]
	]
]

dividers[False, {}] := {{False}}
dividers[edge_, {}] := {edge, {False}, edge}
dividers[edge_, lines_List] := Join[{edge}, Most[lines], {{Last[lines]}}, {edge}]

structure[_, _, _] := None

(* ::Section:: *)
(*Content elements*)

(* A content element is first an expression, held, and its boxes are that expression typeset in TraditionalForm
   by the kernel's MakeBoxes, as Wolfram 15 makes them; its expression is then read back from the boxes. *)

$contentHeads = <|
	"plus" -> Plus, "times" -> Times, "power" -> Power, "divide" -> Divide, "abs" -> Abs, "factorial" -> Factorial, "quotient" -> Quotient, "rem" -> Mod,
	"gcd" -> GCD, "lcm" -> LCM, "max" -> Max, "min" -> Min, "floor" -> Floor, "ceiling" -> Ceiling, "conjugate" -> Conjugate, "arg" -> Arg, "real" -> Re,
	"imaginary" -> Im, "eq" -> Equal, "neq" -> Unequal, "lt" -> Less, "gt" -> Greater, "leq" -> LessEqual, "geq" -> GreaterEqual, "equivalent" -> Congruent,
	"approx" -> TildeEqual, "and" -> And, "or" -> Or, "xor" -> Xor, "not" -> Not, "implies" -> Implies, "ln" -> Log, "exp" -> Exp,
	"sin" -> Sin, "cos" -> Cos, "tan" -> Tan, "sec" -> Sec, "csc" -> Csc, "cot" -> Cot, "sinh" -> Sinh, "cosh" -> Cosh, "tanh" -> Tanh, "sech" -> Sech,
	"csch" -> Csch, "coth" -> Coth, "arcsin" -> ArcSin, "arccos" -> ArcCos, "arctan" -> ArcTan, "arcsec" -> ArcSec, "arccsc" -> ArcCsc, "arccot" -> ArcCot,
	"arcsinh" -> ArcSinh, "arccosh" -> ArcCosh, "arctanh" -> ArcTanh, "arcsech" -> ArcSech, "arccsch" -> ArcCsch, "arccoth" -> ArcCoth,
	"determinant" -> Det, "transpose" -> Transpose, "inverse" -> InverseFunction, "selector" -> Part, "vectorproduct" -> Cross, "scalarproduct" -> Dot,
	"union" -> Union, "intersect" -> Intersection, "in" -> Element, "notin" -> NotElement, "subset" -> SubsetEqual, "prsubset" -> Subset,
	"notsubset" -> NotSubsetEqual, "notprsubset" -> NotSubset, "setdiff" -> Backslash, "compose" -> Composition, "ident" -> Identity,
	"mean" -> Mean, "sdev" -> StandardDeviation, "variance" -> Variance, "median" -> Median, "divergence" -> Div, "grad" -> Grad, "curl" -> Curl,
	"laplacian" -> Laplacian, "root" -> Sqrt, "minus" -> Minus, "tendsto" -> Rule
|>

(* the heads Wolfram 15 keeps in a context of its own *)
$contentSymbols = <|"factorof" -> "Divides", "card" -> "Cardinality", "cartesianproduct" -> "CartesianProduct", "domain" -> "Domain", "codomain" -> "Codomain",
	"image" -> "Image", "naturalnumbers" -> "Naturals"|>

$contentConstants = <|"pi" -> HoldComplete[Pi], "exponentiale" -> HoldComplete[E], "imaginaryi" -> HoldComplete[I], "eulergamma" -> HoldComplete[EulerGamma],
	"infinity" -> HoldComplete[Infinity], "true" -> HoldComplete[True], "false" -> HoldComplete[False], "notanumber" -> HoldComplete[Indeterminate],
	"emptyset" :> heldToken["\[EmptySet]"], "integers" -> HoldComplete[Integers], "reals" -> HoldComplete[Reals], "rationals" -> HoldComplete[Rationals],
	"complexes" -> HoldComplete[Complexes], "primes" -> HoldComplete[Primes]|>

$contentContainers = {"ci", "cn", "csymbol", "apply", "reln", "fn", "lambda", "interval", "list", "set", "vector", "matrix", "matrixrow", "piecewise", "piece", "otherwise",
	"declare", "bvar", "lowlimit", "uplimit", "degree", "logbase", "condition", "domainofapplication", "momentabout", "sep", "log", "diff", "partialdiff", "int", "sum",
	"product", "limit", "forall", "exists", "moment", "outerproduct", "mode"}

contentQ[XMLElement[name_String, __]] := KeyExistsQ[$contentHeads, name] || KeyExistsQ[$contentSymbols, name] || KeyExistsQ[$contentConstants, name] || MemberQ[$contentContainers, name]
contentQ[_] := False

mathmlSymbol[name_String] := heldToken["XML`MathML`Symbols`" <> name]

(* the content kept beside a presentation by semantics is typeset and left as the kernel makes it, but where it is a row of one box *)
$beside = False
kernelBoxes[boxes_] := Replace[boxes, RowBox[{only_}] :> only]

contentAtom[element_] := With[{held = expression[element]},
	If[ held === None,
		Replace[unknownContent[element], several_List :> atom[rowBox[several], rowHeld[several]]],
		With[{boxes = If[$beside, kernelBoxes, notebookBoxes][Replace[held, HoldComplete[e_] :> MakeBoxes[e, TraditionalForm]]]},
			atom[boxes, boxHeld[boxes]]]
	]
]

(* Boxes as a notebook keeps them, which is how Wolfram 15 gives them: a grid's settings of rows and columns as
   GridBoxAlignment, GridBoxSpacings and GridBoxItemSize, the options of a grid and of a tag in the order of their
   names, no SyntaxForm; the boxes within a template as they are. *)
notebookBoxes[TemplateBox[arguments_, name_, options___]] := TemplateBox[arguments, name, Sequence @@ DeleteCases[{options}, HoldPattern[SyntaxForm -> _]]]
notebookBoxes[GridBox[rows_List, options___]] := GridBox[Map[notebookBoxes, rows, {2}], Sequence @@ SortBy[gridOptions[{options}], PadRight[ToCharacterCode[ToString[First[#]]], 60] &]]
notebookBoxes[TagBox[box_, tag_, options___]] := TagBox[notebookBoxes[box], tag, Sequence @@ SortBy[DeleteCases[{options}, HoldPattern[SyntaxForm -> _]], PadRight[ToCharacterCode[ToString[First[#]]], 60] &]]
notebookBoxes[(head : FractionBox | SqrtBox | RadicalBox | SuperscriptBox | SubscriptBox | SubsuperscriptBox | UnderscriptBox | OverscriptBox | UnderoverscriptBox | StyleBox | FormBox)[
		arguments___]] := head @@ Map[notebookBoxes, {arguments}]
notebookBoxes[RowBox[{only_}]] := notebookBoxes[only]
notebookBoxes[parts_List] := Map[notebookBoxes, parts]
notebookBoxes[RowBox[parts_List]] := RowBox[Map[notebookBoxes, parts]]
notebookBoxes[box_] := box

gridOptions[options_List] := Module[{old = Association[Cases[options, HoldPattern[(key : RowSpacings | ColumnSpacings | RowAlignments | ColumnAlignments | ColumnWidths) -> value_] :> (key -> value)]], rest},
	rest = DeleteCases[options, HoldPattern[(RowSpacings | ColumnSpacings | RowAlignments | ColumnAlignments | ColumnWidths) -> _]];
	Join[rest,
		If[ KeyExistsQ[old, ColumnAlignments] || KeyExistsQ[old, RowAlignments],
			{GridBoxAlignment -> {"Columns" -> {{First[Flatten[{Lookup[old, ColumnAlignments, Center]}]]}}, "Rows" -> {{First[Flatten[{Lookup[old, RowAlignments, Baseline]}]]}}}}, {}],
		If[ KeyExistsQ[old, ColumnWidths], {GridBoxItemSize -> {"Columns" -> {{old[ColumnWidths]}}, "Rows" -> {{1.}}}}, {}],
		If[ KeyExistsQ[old, ColumnSpacings] || KeyExistsQ[old, RowSpacings],
			{GridBoxSpacings -> {
				"Columns" -> {Offset[0.4 0.7], {Offset[0.7 Lookup[old, ColumnSpacings, 0.8]]}, Offset[0.4 0.7]},
				"Rows" -> {Offset[0.2], {Offset[0.4 Lookup[old, RowSpacings, 1]]}, Offset[0.2]}}}, {}]
	]
]

(* an application Wolfram 15 does not read is its operator's name applied to its children, a bound variable as what it holds *)
unapplied[XMLElement["apply" | "reln", _, {XMLElement[name_String, _, {}], rest___}]] :=
	XMLElement[name, {}, Replace[{rest}, XMLElement["bvar", _, {v_}] :> v, {1}]]
unapplied[element_] := element

(* an element applied that is no element of content MathML is an unknown tag, as it is alone; any other content that
   does not read is an unknown structure *)
unknownContent[element : XMLElement["apply" | "reln", _, {head : XMLElement[name_String, _, {}], ___}]] /; ! contentQ[head] :=
	Replace[unapplied[element], XMLElement[_, _, content_List] :> (
		note["unkntag", name];
		Join[lexed[name], {token["("]}, Riffle[Map[argument, content], token[","]], {token[")"]}]
	)]
unknownContent[element_] := unknown[unapplied[element]]

(* the expression of an element in HoldComplete, or None where it is not one Wolfram 15 reads *)
expression[XMLElement[name_String, _, {}]] /; KeyExistsQ[$contentConstants, name] := $contentConstants[name]
expression[XMLElement["log", _, {}]] := None
expression[XMLElement["list" | "set", _, {}]] := HoldComplete[{}]
expression[XMLElement[name_String, _, {}]] /; KeyExistsQ[$contentHeads, name] := With[{head = $contentHeads[name]}, HoldComplete[head]]
expression[XMLElement[name_String, _, {}]] /; KeyExistsQ[$contentSymbols, name] := mathmlSymbol[$contentSymbols[name]]

expression[XMLElement["ci" | "csymbol", _, {text_String}]] := Replace[rowHeld[lexed[text]], $unread -> None]
expression[XMLElement["ci" | "csymbol", _, {child_XMLElement}]] := embedded[child]
expression[XMLElement["fn", _, {child_XMLElement}]] := expression[child]

(* an element of the other kind, or one that is no expression: its boxes, kept as they are *)
embedded[element_] := With[{row = items[element]}, With[{box = rowBox[row]}, HoldComplete[RawBoxes[box]]]]

operand[XMLElement["semantics", _, {main_ ? contentQ, ___}]] := operand[main]
operand[element_XMLElement] := If[ contentQ[element], Replace[expression[element], None :> embedded[element]], embedded[element]]
operand[text_String] := Replace[rowHeld[lexed[text]], $unread :> With[{t = text}, HoldComplete[t]]]

expression[XMLElement["cn", attributes_, content_List]] := numeral[Replace[attribute[attributes, "type"], None -> "real"], Replace[attribute[attributes, "base"], {None -> 10, b_String :> FromDigits[b]}], content]

digits[text_String, 10] := Replace[signedHeld[StringTrim[text]], $unread -> None]
digits[text_String, base_Integer] := With[{t = ToLowerCase[StringTrim[text]]},
	If[ StringMatchQ[t, (DigitCharacter | LetterCharacter) ..] && Max[ToCharacterCode[t] /. c_ /; c >= 97 :> c - 39] - 48 < base,
		With[{n = FromDigits[t, base]}, HoldComplete[n]],
		If[ StringMatchQ[t, (DigitCharacter | LetterCharacter) ... ~~ "." ~~ (DigitCharacter | LetterCharacter) ...],
			Replace[heldToken[ToString[base] <> "^^" <> t], $unread -> None],
			None
		]
	]
]

(* a number with its sign: -n is the number, +n the number *)
signedHeld[text_String] := Which[
	StringStartsQ[text, "-"], Replace[rowHeld[lexed[StringDrop[text, 1]]], {HoldComplete[n : _Integer | _Real | _Rational] :> With[{m = -n}, HoldComplete[m]], HoldComplete[e_] :> HoldComplete[-e]}],
	StringStartsQ[text, "+"], rowHeld[lexed[StringDrop[text, 1]]],
	True, rowHeld[lexed[text]]
]

numeral["integer" | "real", base_, {text_String}] := digits[text, base]
numeral["constant", _, {text_String}] := Replace[rowHeld[lexed[text]], $unread -> None]
(* a fraction in lowest terms is the rational number, any other the quotient as it is written *)
numeral["rational", base_, {n_String, XMLElement["sep", _, {}], d_String}] := Replace[{digits[n, base], digits[d, base]}, {
	{HoldComplete[p_Integer], HoldComplete[q_Integer]} /; q > 1 && GCD[p, q] === 1 :> With[{r = p / q}, HoldComplete[r]],
	{p_, q_} :> pair[p, q, HoldComplete[Divide[slot[1], slot[2]]]]
}]
(* a complex number of machine reals is the number, any other the sum as it is written *)
numeral["complex-cartesian", base_, {re_String, XMLElement["sep", _, {}], im_String}] := Replace[{digits[re, base], digits[im, base]}, {
	{HoldComplete[x_Real], HoldComplete[y : _Integer | _Real | _Rational]} :> With[{z = Complex[x, y]}, HoldComplete[z]],
	{x_, y_} :> pair[x, y, HoldComplete[Plus[slot[1], Times[slot[2], I]]]]
}]
numeral["complex-polar", base_, {r_String, XMLElement["sep", _, {}], angle_String}] := pair[digits[r, base], digits[angle, base], HoldComplete[Times[slot[1], Power[E, Times[slot[2], I]]]]]
numeral["e-notation", base_, {m_String, XMLElement["sep", _, {}], e_String}] := pair[digits[m, base], digits[e, base], HoldComplete[Times[slot[1], Power[10, slot[2]]]]]
numeral[_, _, _] := None

pair[None, _, _] := None
pair[_, None, _] := None
pair[first_, second_, HoldComplete[template_]] := combine[{first, second}, template]

(* the children of an apply after its operator: the qualifiers, by name, and the arguments *)
qualifiers[children_List] := GroupBy[Cases[children, XMLElement[name : "bvar" | "lowlimit" | "uplimit" | "degree" | "logbase" | "condition" | "interval" | "domainofapplication" | "momentabout", _, _]], First]
arguments[children_List] := DeleteCases[children, XMLElement["bvar" | "lowlimit" | "uplimit" | "degree" | "logbase" | "condition" | "domainofapplication" | "momentabout", _, _]]

inner[XMLElement[_, _, {child_}]] := operand[child]
inner[_] := None

(* f[a, b, ...] of held parts *)
applied[None, _] := None
applied[HoldComplete[head_], {}] := HoldComplete[head[]]
applied[head_HoldComplete, parts_List] := If[ MemberQ[parts, None], None,
	With[{all = Join @@ parts}, Replace[head, HoldComplete[h_] :> (h @@@ HoldComplete[all])]]
]

expression[XMLElement["apply" | "reln", _, {XMLElement[name_String, attributes_, {}], rest___}]] /; ! KeyExistsQ[$contentConstants, name] := operation[name, attributes, {rest}]
expression[XMLElement["apply" | "reln", _, {head_XMLElement, rest___}]] := applied[operand[head], Map[operand, {rest}]]

operation["minus", _, {a_, b_}] := applied[HoldComplete[Subtract], {operand[a], operand[b]}]
operation["root", _, children_List] := With[{q = qualifiers[children], args = arguments[children]},
	If[ Length[args] =!= 1, None,
		If[ KeyExistsQ[q, "degree"], pair[operand[First[args]], inner[First[q["degree"]]], HoldComplete[Power[slot[1], Divide[1, slot[2]]]]], applied[HoldComplete[Sqrt], {operand[First[args]]}]]
	]
]
operation["log", _, children_List] := With[{q = qualifiers[children], args = arguments[children]},
	If[ Length[args] =!= 1, None,
		pair[If[KeyExistsQ[q, "logbase"], inner[First[q["logbase"]]], HoldComplete[10]], operand[First[args]], HoldComplete[Log[slot[1], slot[2]]]]
	]
]
operation["selector", _, {a_}] := operand[a]
operation["list" | "set", _, children_List] := applied[HoldComplete[{}], Map[operand, children]]
operation["tendsto", _, children_List] /; Length[children] =!= 2 := None
operation[name : "forall" | "exists", _, {a_, b_}] /; FreeQ[{a, b}, XMLElement["bvar", __]] :=
	applied[Replace[name, {"forall" -> HoldComplete[ForAll], "exists" -> HoldComplete[Exists]}], {operand[a], operand[b]}]
operation["mode", _, children_List] := applied[heldToken["System`Mode"], Map[operand, children]]
operation["exp", _, {a_}] := pair[HoldComplete[E], operand[a], HoldComplete[Power[slot[1], slot[2]]]]
operation["outerproduct", _, {a_, b_}] := pair[operand[a], operand[b], HoldComplete[Outer[Times, slot[1], slot[2]]]]
operation["moment", _, children_List] := With[{q = qualifiers[children], args = arguments[children]},
	With[{degree = If[KeyExistsQ[q, "degree"], inner[First[q["degree"]]], HoldComplete[1]]},
		Which[
			Length[args] =!= 1, None,
			KeyExistsQ[q, "momentabout"], applied[mathmlSymbol["Moment"], {operand[First[args]], inner[First[q["momentabout"]]], degree}],
			True, pair[operand[First[args]], degree, HoldComplete[CentralMoment[slot[1], slot[2]]]]
		]
	]
]

(* a bound variable, with its degree where it has one *)
variable[XMLElement["bvar", _, {v_}]] := operand[v]
variable[XMLElement["bvar", _, {v_, XMLElement["degree", _, {d_}]}]] := pair[operand[v], operand[d], HoldComplete[{slot[1], slot[2]}]]
variable[_] := None

operation["diff", _, children_List] := With[{q = qualifiers[children], args = arguments[children]},
	Which[
		Length[args] =!= 1, None,
		! KeyExistsQ[q, "bvar"], applied[HoldComplete[Derivative[1]], {operand[First[args]]}],
		True, pair[operand[First[args]], variable[First[q["bvar"]]], HoldComplete[Dt[slot[1], slot[2]]]]
	]
]
operation["partialdiff", _, {XMLElement["list", _, orders_List], function_}] :=
	applied[applied[HoldComplete[Derivative], Map[operand, orders]], {operand[function]}]
operation["partialdiff", _, {function_}] := applied[HoldComplete[Derivative[1]], {operand[function]}]
operation["partialdiff", _, children_List] := With[{q = qualifiers[children], args = DeleteCases[arguments[children], XMLElement["degree", __]]},
	If[ Length[args] =!= 1 || ! KeyExistsQ[q, "bvar"], None, applied[HoldComplete[D], Prepend[Map[variable, q["bvar"]], operand[First[args]]]]]
]

(* the range a sum, a product or an integral runs over: {variable, low, high}, or the variable alone *)
range[q_Association] := Which[
	! KeyExistsQ[q, "bvar"] || Length[q["bvar"]] =!= 1, None,
	KeyExistsQ[q, "lowlimit"] && KeyExistsQ[q, "uplimit"],
		applied[HoldComplete[List], {variable[First[q["bvar"]]], inner[First[q["lowlimit"]]], inner[First[q["uplimit"]]]}],
	KeyExistsQ[q, "interval"] && MatchQ[First[q["interval"]], XMLElement[_, _, {_, _}]],
		applied[HoldComplete[List], Prepend[Map[operand, First[q["interval"]][[3]]], variable[First[q["bvar"]]]]],
	KeyExistsQ[q, "condition"] || KeyExistsQ[q, "domainofapplication"], None,
	True, variable[First[q["bvar"]]]
]

operation[name : "int" | "sum" | "product", _, children_List] := With[{q = qualifiers[children], args = DeleteCases[arguments[children], XMLElement["interval", __]]},
	If[ Length[args] =!= 1, None,
		pair[operand[First[args]], range[q], Replace[name, {"int" -> HoldComplete[Integrate[slot[1], slot[2]]], "sum" -> HoldComplete[Sum[slot[1], slot[2]]], "product" -> HoldComplete[Product[slot[1], slot[2]]]}]]
	]
]

operation["limit", _, children_List] := With[{q = qualifiers[children], args = arguments[children]},
	Which[
		Length[args] =!= 1 || ! KeyExistsQ[q, "bvar"], None,
		KeyExistsQ[q, "lowlimit"], applied[HoldComplete[Limit], {operand[First[args]], pair[variable[First[q["bvar"]]], inner[First[q["lowlimit"]]], HoldComplete[slot[1] -> slot[2]]]}],
		MatchQ[Lookup[q, "condition"], {XMLElement[_, _, {XMLElement["apply", _, {XMLElement["tendsto", _, {}], _, _}]}]}],
			Replace[First[q["condition"]], XMLElement[_, _, {XMLElement["apply", _, {XMLElement["tendsto", way_, {}], v_, point_}]}] :>
				applied[HoldComplete[Limit], Join[
					{operand[First[args]], pair[operand[v], operand[point], HoldComplete[slot[1] -> slot[2]]]},
					Replace[attribute[way, "type"], {"above" -> {HoldComplete[Direction -> -1]}, "below" -> {HoldComplete[Direction -> 1]}, _ -> {}}]
				]]],
		True, None
	]
]

operation[name : "forall" | "exists", _, children_List] := With[{q = qualifiers[children], args = arguments[children], head = Replace[name, {"forall" -> HoldComplete[ForAll], "exists" -> HoldComplete[Exists]}]},
	If[ Length[args] =!= 1 || ! KeyExistsQ[q, "bvar"], None,
		With[{variables = Map[variable, q["bvar"]],
				body = If[KeyExistsQ[q, "condition"], pair[inner[First[q["condition"]]], operand[First[args]], HoldComplete[Implies[slot[1], slot[2]]]], operand[First[args]]]},
			applied[head, Append[variables, body]]
		]
	]
]

operation[name_String, _, children_List] /; KeyExistsQ[$contentHeads, name] := With[{head = $contentHeads[name]}, applied[HoldComplete[head], Map[operand, children]]]
operation[name_String, _, children_List] /; KeyExistsQ[$contentSymbols, name] := applied[mathmlSymbol[$contentSymbols[name]], Map[operand, children]]
operation[_, _, _] := None

expression[XMLElement["lambda", _, children : {XMLElement["bvar", _, {_}] .., body_}]] :=
	applied[HoldComplete[Function], {applied[HoldComplete[List], Map[variable, Most[children]]], operand[body]}]

expression[XMLElement["interval", attributes_, {a_, b_}]] /; attribute[attributes, "closure"] === None := applied[HoldComplete[Interval], {operand[a], operand[b]}]

expression[XMLElement["list" | "set", _, children_List]] := applied[HoldComplete[List], Map[listPart, children]]
listPart[XMLElement["bvar" | "condition", _, {child_}]] := operand[child]
listPart[child_] := operand[child]

expression[XMLElement["vector", _, children : {__}]] := applied[HoldComplete[List], Map[applied[HoldComplete[List], {operand[#]}] &, children]]
expression[XMLElement["matrix", _, rows_List]] := applied[HoldComplete[List], Map[operand, rows]]
expression[XMLElement["matrixrow", _, children : {__}]] := applied[HoldComplete[List], Map[operand, children]]

expression[XMLElement["piecewise", _, children : {__}]] := With[{cases = Map[piece, children]},
	If[ MemberQ[cases, None], None, applied[HoldComplete[Piecewise], {applied[HoldComplete[List], cases]}]]
]
piece[XMLElement["piece", _, {value_, condition_}]] := applied[HoldComplete[List], {operand[value], operand[condition]}]
piece[XMLElement["piece", _, _]] := HoldComplete[{Null, Null}]
piece[XMLElement["otherwise", _, {value_}]] := applied[HoldComplete[List], {operand[value], HoldComplete[True]}]
piece[_] := None
expression[XMLElement["piece" | "otherwise", _, children : {__}]] := applied[HoldComplete[List], Map[operand, children]]

expression[_] := None

(* ::Section:: *)
(*The whole: math, its tag and its form*)

kind[element_] := Which[presentationQ[element], "MathMLPresentationTag", contentQ[element], "MathMLContentTag", True, None]

(* {boxes, held} of a document's root: the child of math, or its children as a row *)
converted[root : XMLElement[name_String, _, content_List]] := Module[{children, row, box, held},
	children = If[name === "math", content, note["incrt", name]; {root}];
	row = Block[{$kind = None}, Replace[children, {{} -> {}, {only_} :> items[only], several_ :> items[XMLElement["mrow", {}, several]]}]];
	box = rowBox[row];
	held = rowHeld[row];
	{
		FormBox[box, TraditionalForm],
		If[ held === $unread, ErrorBox[FormBox[ErrorBox[untag[box]], TraditionalForm]], held]
	}
]

untag[TagBox[box_, "MathMLPresentationTag" | "MathMLContentTag", ___]] := box
untag[box_] := box

(* ::Section:: *)
(*The functions*)

symbolicDocument[xml : XMLObject["Document"][_, _XMLElement, _, ___]] := xml
symbolicDocument[element_XMLElement] := XMLObject["Document"][{}, element, {}]

read[text_String] := document[text]
read[xml_] := symbolicDocument[xml]

$symbolic = _XMLElement | XMLObject["Document"][_, _XMLElement, _, ___]

(* {boxes, held} of a source, or $Failed where it is no document *)
both[source_] := Replace[read[source], {
	(* a root that is no element of MathML is not read *)
	XMLObject["Document"][_, root : XMLElement[Except["math"], __], _, ___] /; kind[root] === None :> (note["nmmlr", root, First[root]]; $Failed),
	XMLObject["Document"][_, root_, _, ___] :> converted[root],
	_ -> $Failed
}]

MathMLBoxes[source : _String | $symbolic] := Replace[both[source], {boxes_, _} :> boxes]

MathMLHeld[source : _String | $symbolic] := Replace[both[source], {{_, held_} :> held, _ -> HoldComplete[$Failed]}]

MathMLExpression[source : _String | $symbolic] := Replace[both[source], {{_, held_HoldComplete} :> ReleaseHold[held], _ -> $Failed}]

$importElements = {"Boxes", "Expression", "HeldExpression", "Summary", "XMLElement", "XMLObject"}

MathMLImport[source_String] := MathMLImport[source, "Boxes"]
MathMLImport[source_String, "Elements"] := $importElements
MathMLImport[source_String, "Boxes"] := MathMLBoxes[source]
MathMLImport[source_String, "Summary"] := Dataset[<|"Format" -> "MathML"|>]
MathMLImport[source_String, "HeldExpression"] := MathMLHeld[source]
(* boxes that do not read are given as they are, in their ErrorBox *)
MathMLImport[source_String, "Expression"] := Replace[both[source], {{_, held_HoldComplete} :> ReleaseHold[held], {_, unread_} :> unread}]
MathMLImport[source_String, "XMLObject"] := read[source]
MathMLImport[source_String, "XMLElement"] := Replace[read[source], XMLObject["Document"][_, root_, _, ___] :> root]

End[]
EndPackage[]

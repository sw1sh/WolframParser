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
WolframLanguageGrammar::usage  = "WolframLanguageGrammar[alg] builds the Wolfram Language parser over the algebra alg, an Association with the keys of ASTAlgebra; the parser gives the list of the top-level expressions."
WolframLanguageConcrete::usage = "WolframLanguageConcrete[\"code\"] parses Wolfram Language source to its concrete syntax tree, as CodeParser`CodeConcreteParse gives it: a ContainerNode of the top-level expressions and the whitespace, newlines and comments around them, in CodeParser's own nodes, every character of the source in a leaf. Source that is not Wolfram Language reads as CodeParser reads it, into its error nodes: nothing fails."
WolframLanguageSemantic::usage = "WolframLanguageSemantic is the algebra that builds each expression held: its builders give <|\"Expr\" -> HoldComplete[expr], \"Literal\" -> .., \"Chain\" -> ..|>, the flags telling a number literal and a product, into which a minus folds."

Begin["`Private`"]

(* --- precedence: CodeParser's published table --- *)

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

(* --- tokens --- *)

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
   one of all *)
longest[s_String] := longest[s, $operatorSpellings]
longest[s_String, all_List] := With[{more = Select[all, StringStartsQ[#, s] && # =!= s &]},
    If[ more === {},
        ParseLiteral[s],
        ParseAction[ParseLiteral[s] ~~ ParseNotFollowedBy[ParseChoice @@ (ParseLiteral[StringDrop[#, StringLength[s]]] & /@ more)], s &]
    ]]

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
$name = text[ParseChoice[ParseRegex["[A-Za-z$`][A-Za-z0-9$`]*"], $letter] ~~
    ParseMany[ParseAction[ParseLookahead[ParseCharacter[_?nameContinuesQ]] ~~ ParseChoice[ParseRegex["[A-Za-z0-9$`]+"], $letter], #2 &]]]

nameContinuesQ[c_String] := c === "\\" || First[ToCharacterCode[c]] > 127 || StringMatchQ[c, LetterCharacter | DigitCharacter | "$" | "`"]

$digits = ParseRegex["[0-9]+"]

(* 12, 1.5, .5, 1. (not before another .), 16^^ff.8, 1.5`20, 1``10, 2*^-3 *)
$number = text[
    ParseChoice[
        $digits ~~ ParseOptional[ParseChoice[
            ParseLiteral["^^"] ~~ ParseRegex["[0-9a-zA-Z]+(\\.[0-9a-zA-Z]*)?"],
            ParseLiteral["."] ~~ ParseNotFollowedBy[ParseLiteral["."]] ~~ ParseOptional[$digits]]],
        ParseLiteral["."] ~~ $digits]
    ~~ ParseOptional[ParseLiteral["`"] ~~ ParseOptional[ParseLiteral["`"]] ~~ ParseOptional[ParseRegex["[-+]?([0-9]+\\.?[0-9]*|\\.[0-9]+)"]]]
    ~~ ParseOptional[ParseLiteral["*^"] ~~ ParseRegex["[-+]?[0-9]+"]]]

numberKind[s_String] := If[StringFreeQ[s, "." | "`"], "Integer", "Real"]

(* runs of plain characters, then any escaped one *)
$string = text[ParseLiteral["\""] ~~ ParseMany[ParseChoice[
    ParseRegex["[^\"\\\\]+"],
    ParseLiteral["\\"] ~~ ParseCharacter[_]]] ~~ ParseLiteral["\""]]

(* _, __, ___, then an optional . or a head *)
$blank = text[ParseChoice[ParseLiteral["___"], ParseLiteral["__"], ParseLiteral["_"]] ~~ ParseOptional[ParseChoice[ParseLiteral["."], $name]]]

$slot = ParseAction[ParseLookahead[ParseLiteral["#"]] ~~ ParseChoice[text[ParseLiteral["#"] ~~ $string], ParseRegex["##?([0-9]+|[A-Za-z][A-Za-z0-9]*)?"]], #2 &]

(* what a ? or ?? asks about: words of letters, digits and the * and @
   of a name pattern, the spaces and tabs between them too *)
$informationWord = text[ParseSome[ParseChoice[ParseRegex["[A-Za-z0-9$`*@]+"], $letter]]]
$informationName = text[$informationWord ~~ ParseMany[ParseRegex["[ \t]+"] ~~ $informationWord]]

$out = ParseAction[ParseLookahead[ParseLiteral["%"]] ~~ ParseRegex["%+[0-9]*"], #2 &]

(* the file of << and >>: a string, or the characters of a path or a
   context, a \ among them, \[Name] one character; and one whose \[ is
   not closed *)
$fileCharacters = "(?:[A-Za-z0-9$`_./~:!*?-]|\\\\\\[[A-Za-z0-9]+\\]|\\\\(?!\\[))"
$file = ParseChoice[$string, ParseRegex[$fileCharacters <> "+"]]
$unterminatedFile = ParseRegex[$fileCharacters <> "*\\\\\\[[A-Za-z0-9]*+(?!\\])"]

(* a comment, the comments nested in it too *)
commentParser[] := With[{comment = RecCell[]},
    SetRec[comment, ParseLiteral["(*"] ~~ ParseMany[ParseChoice[
        RecRef[comment],
        ParseRegex["[^(*]+"],
        ParseLiteral["("] ~~ ParseNotFollowedBy[ParseLiteral["*"]],
        ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[")"]]]] ~~ ParseLiteral["*)"]];
    RecRef[comment]]

(* --- the grammar, parameterised over an algebra --- *)

(* Outside brackets, the whitespace after an operand or a postfix operator
   stops at a newline, which ends the expression if it can end there;
   after an infix or prefix operator, inside brackets and between
   expressions it takes newlines too. *)
WolframLanguageGrammar[alg_] := grammar[alg]["Program"]

(* <|"Program" -> the parser of a whole source, "Statement" -> that of one
   top-level expression and the whitespace after it|> *)
grammar[alg_] := Module[{space, wsLine, wsAll, nested, top, statement},
    space = ParseChoice[
        ParseCharacter[" " | "\t" | "\r" | "\f"],
        ParseLiteral["\\\n"], ParseLiteral["\\\r\n"],
        commentParser[],
        ParseChoice @@ (ParseLiteral /@ $longWhitespace)];
    wsLine = ParseMany[space];
    wsAll = ParseMany[ParseChoice[ParseCharacter["\n"], space]];
    nested = RecCell[];
    SetRec[nested, expressionParser[alg, wsAll, wsAll, nested]];
    top = expressionParser[alg, wsLine, wsAll, nested];
    statement = ParseAction[top ~~ wsAll, #1 &];
    <|"Program" -> ParseAction[wsAll ~~ ParseMany[statement], #2 &], "Statement" -> statement|>
]

(* The expression parser whose operands and postfix operators are followed
   by the whitespace ws; brackets hold expressions of nested. *)
expressionParser[alg_, ws_, wsAll_, nested_] := Module[
    {after, operator, postfixOperator, leaf, nullLeaf, symbolLeaf, blankLeaf, otherUnits, plainUnit, unit, patternUnit,
     items, comma, call, part, messageName, tag, derivative, span, spanStart, compound, tagSet, put,
     binary, prefix, postfix, flat, plus, relation, relationOp, implicit, specs, table, information, dot, setOperator, unset,
     longOperator, longPostfixOperator, longSpecs, longGroups, longCalls, integrals, integrandOperand, differentialAhead, divisible,
     patternRight, spanOperand, compoundOperand, tagLeft, tagRight},

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
    integrandOperand = RecCell[];

    (* \[LeftFloor] x \[RightFloor] and the other brackets of long names *)
    longGroups = Map[Function[g,
        ParseAction[longOperator[g[[1]]] ~~ items[longNameSpellings[g[[2]]]] ~~ longPostfixOperator[g[[2]]],
            alg["Group"][SymbolName[g[[3]]], #2] &]], Select[$longNameTable["Groups"], #[[1]] =!= "LeftDoubleBracket" &]];
    (* f \[LeftDoubleBracket] i \[RightDoubleBracket], a part *)
    longCalls = ParseAction[longOperator["LeftDoubleBracket"] ~~ items[longNameSpellings["RightDoubleBracket"]] ~~ longPostfixOperator["RightDoubleBracket"],
        Function[{open, indices, close}, Function[e, alg["Infix"]["Part", Prepend[indices, e]]]]];
    (* \[Integral] f \[DifferentialD] x: its integrand, then the differential
       after it; Integrate[f, x], and for an integral round a contour its
       head of the product of both *)
    differentialAhead = ParseLookahead[ParseChoice @@ (ParseLiteral /@ Catenate[longNameSpellings /@ {"DifferentialD", "CapitalDifferentialD"}])];
    integrals = Map[Function[row, ParseAction[
            longOperator[row[[1]]] ~~ ParseScoped["Integrand", RecRef[integrandOperand]] ~~ ParseOptional[ParseAction[differentialAhead ~~ RecRef[integrandOperand], #2 &]],
            Function[{o, f, d}, Which[
                MissingQ[d], alg["Prefix"][SymbolName[row[[2]]], f],
                row[[3]] === Integrate, integralOf[alg, f, d],
                True, alg["Prefix"][SymbolName[row[[2]]], alg["Infix"]["Times", {f, d}]]]]]],
        $longNameTable["Integrals"]];

    (* a name, or n:patt: the name binds its pattern wherever it stands;
       within the pattern a : is Optional's *)
    patternUnit = ParseAction[symbolLeaf ~~ ParseOptional[ParseAction[operator[":"] ~~ RecRef[patternRight], #2 &]],
        Function[{name, pattern}, If[MissingQ[pattern], name, alg["Binary"]["Pattern", name, pattern]]]];
    (* ;; b and ;; at the start: Span[1, ...] *)
    spanStart = ParseAction[span, Function[f, f[alg["Leaf"]["Integer", "1"]]]];
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
    tag = ParseChoice[leaf[$string, "String"], leaf[$name, "Tag"]];
    messageName = ParseChoice[
        (* t::[a, ...], a type with parameters *)
        ParseAction[ParseLiteral["::"] ~~ after[ParseLiteral["["], wsAll] ~~ items["]"] ~~ after[ParseLiteral["]"], ws],
            Function[{colons, open, args, close}, Function[t,
                alg["Call"][alg["Call"][alg["Leaf"]["Symbol", "TypeSpecifier"], {t}], args]]]],
        ParseAction[ParseLiteral["::"] ~~ tag ~~ ParseOptional[ParseAction[ParseLiteral["::"] ~~ tag, #2 &]],
            Function[{colons, first, second}, Function[s,
                alg["Infix"]["MessageName", Join[{s, first}, If[MissingQ[second], {}, {second}]]]]]]];
    derivative = ParseAction[ParseLookahead[ParseLiteral["'"]] ~~ ParseRegex["'+"] ~~ ws,
        Function[{look, primes, w}, Function[f, alg["Call"][
            alg["Call"][alg["Leaf"]["Symbol", "Derivative"], {alg["Leaf"]["Integer", ToString[StringLength[primes]]]}], {f}]]]];
    (* a ;; b ;; c, each operand optional: All where it is left out *)
    With[{operand = ParseOptional[ParseAction[ParseNotFollowedBy[ParseLiteral[";;"]] ~~ RecRef[spanOperand], #2 &]],
          all = alg["Leaf"]["Symbol", "All"]},
        span = ParseAction[postfixOperator[";;"] ~~ operand ~~ ParseOptional[ParseAction[postfixOperator[";;"] ~~ operand, {#2} &]],
            Function[{semis, b, c}, Function[a, alg["Infix"]["Span",
                Join[{a, If[MissingQ[b], all, b]}, If[MissingQ[c], {}, {If[MissingQ[First[c]], all, First[c]]}]]]]]]
    ];
    compound = ParseAction[ParseSome[ParseAction[postfixOperator[";"] ~~ ParseOptional[RecRef[compoundOperand]], {#2} &]],
        Function[With[{parts = nullLeaf /@ Map[First, {##}]}, Function[a, alg["Infix"]["CompoundExpression", Prepend[parts, a]]]]]];
    (* the = of a set, before a number its . begins too; and = then a .
       not a number's, trivia between them, an unset *)
    setOperator = after[ParseLiteral["="] ~~
        ParseNotFollowedBy[ParseChoice[ParseLiteral["="], ParseLiteral["!="], ParseLiteral["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter]]]], wsAll];
    unset = after[ParseLiteral["="] ~~ ParseNotFollowedBy[ParseChoice[ParseLiteral["="], ParseLiteral["!="]]] ~~ wsAll ~~
        ParseLiteral["."] ~~ ParseNotFollowedBy[ParseCharacter[DigitCharacter | "."]], ws];
    tagSet = ParseAction[operator["/:"] ~~ RecRef[tagLeft] ~~ ParseChoice[
            ParseAction[unset, {"TagUnset"} &],
            ParseAction[operator[":="] ~~ RecRef[tagRight], {"TagSetDelayed", #2} &],
            ParseAction[setOperator ~~ RecRef[tagRight], {"TagSet", #2} &]],
        Function[{slash, lhs, rest}, Function[t, If[First[rest] === "TagUnset",
            alg["Binary"]["TagUnset", t, lhs],
            alg["Ternary"][First[rest], t, lhs, Last[rest]]]]]];
    put = ParseAction[ParseChoice[operator[">>>"], operator[">>"]] ~~ leaf[$file, "File"],
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
            ParseLiteral["<|"],
            ParseLiteral["."] ~~ ParseCharacter[DigitCharacter],
            $letter,
            ParseLookahead[ParseCharacter[_?prefixOnlyStartQ]] ~~ ParseChoice @@ (ParseLiteral /@ Catenate[longNameSpellings /@ $prefixOnlyNames])]] ~~
            ParseNotFollowedBy[differentialAhead ~~ ParseCondition[ParseScope[], MatchQ[#, {___, "Integrand"}] &]],
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
        {"At", {"InfixR", ParseAction[operator["@"], Function[o, Function[{l, r}, atCall[alg, l, r]]]]}},
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
            name === "InvisibleApplication", {"InfixR", ParseAction[longOperator[name], Function[o, Function[{l, r}, atCall[alg, l, r]]]]},
            (* \[Application] a chain of one node, as the kernel reads it *)
            row[[2]] === "InfixNode" || name === "Application", {"InfixN", longOperator[name], flat[head]},
            True, {If[row[[5]] === "Right", "InfixR", "InfixL"], ParseAction[longOperator[name], Function[o, Function[{l, r}, alg["Binary"][head, l, r]]]]}]}]],
            $heldLongInfix],
        Map[{#[[4]], {"Prefix", With[{head = heldLongHead[#]}, ParseAction[longOperator[#[[1]]], Function[o, Function[x, alg["Prefix"][head, x]]]]]}} &, $heldLongPrefix],
        Map[{#[[4]], {"Postfix", With[{head = heldLongHead[#]}, ParseAction[longPostfixOperator[#[[1]]], Function[o, Function[x, alg["Postfix"][x, head]]]]]}} &,
            $longNameTable["Postfix"]],
        {{"Call", {"Postfix", longCalls}}}];
    specs = Join[specs, longSpecs];

    table[u_, min_Integer] := ParseOperatorTable[u, levelsAbove[specs, min]];
    SetRec[integrandOperand, table[unit, $integralPrecedence]];
    SetRec[patternRight, table[plainUnit, $codeParserPrecedence["Fake`PatternColon"]]];
    SetRec[spanOperand, table[unit, $codeParserPrecedence["SemiSemi"]]];
    SetRec[compoundOperand, table[unit, $codeParserPrecedence["Semi"]]];
    SetRec[tagLeft, table[unit, $codeParserPrecedence["Equal"]]];
    SetRec[tagRight, table[unit, $codeParserPrecedence["Equal"] - 1]];
    table[unit, 0]
]

(* Long-named operators: their spellings are listed under the operator's
   own name rather than an ASCII one. *)
spellings[op : "DirectedEdge" | "UndirectedEdge" | "Element"] := $longNameOperators[op]

(* --- the held algebra --- *)

held[e_HoldComplete] := <|"Expr" -> e, "Literal" -> False, "Chain" -> False|>

(* HoldComplete[h], {HoldComplete[a], ...} -> HoldComplete[h[a, ...]] *)
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

(* -x: a number literal folds the minus in, a product takes -1 as its
   first factor, anything else is Times[-1, x] *)
negated[x_Association] := Which[
    x["Literal"], Replace[x["Expr"], HoldComplete[n_] :> With[{m = -n}, HoldComplete[m]]],
    x["Chain"],   Replace[x["Expr"], HoldComplete[_[a___]] :> HoldComplete[Times[-1, a]]],
    True,         Replace[x["Expr"], HoldComplete[e_] :> HoldComplete[Times[-1, e]]]]

(* x_h, __, x___., ...: the name before the underscores, their count, and
   the head or the . after them *)
blankExpression[s_String] := Module[{name, rest, underscores, head, blank, named},
    name = StringTake[s, First[First[StringPosition[s, "_", 1]]] - 1];
    rest = StringDrop[s, StringLength[name]];
    underscores = StringLength[First[StringCases[rest, StartOfString ~~ ("_" ..), 1]]];
    head = StringDrop[rest, underscores];
    blank = symbolCall[{"Blank", "BlankSequence", "BlankNullSequence"}[[underscores]],
        If[head === "" || head === ".", {}, {heldName[head]}]];
    named = If[name === "", blank, symbolCall["Pattern", {heldName[name], blank}]];
    If[head === ".", symbolCall["Optional", {named}], named]
]

slotExpression[s_String] /; StringStartsQ[s, "#\""] := symbolCall["Slot", {HoldComplete @@ {stringValue[StringDrop[s, 1]]}}]
slotExpression[s_String] := With[{rest = StringDelete[s, "#"]},
    symbolCall[If[StringStartsQ[s, "##"], "SlotSequence", "Slot"],
        {Which[rest === "", HoldComplete[1], StringMatchQ[rest, DigitCharacter ..], HoldComplete @@ {FromDigits[rest]}, True, HoldComplete @@ {rest}]}]]

(* %: Out[]; %%: Out[-2]; %3: Out[3] *)
outExpression[s_String] := With[{count = StringCount[s, "%"], digits = StringDelete[s, "%"]},
    symbolCall["Out", Which[
        digits =!= "", {HoldComplete @@ {FromDigits[digits]}},
        count === 1, {},
        True, {HoldComplete @@ {-count}}]]]

(* --- numbers --- *)

(* The value of a number's text: b^^digits in base b, a . for a real, a `
   and its precision or a `` and its accuracy, in digits of the base, and
   *^e for a power of the base. A real without a mark is a machine real,
   unless its digits are more than a machine real holds; it then keeps
   the accuracy its digits give [WL 15.0.0]. *)
numberValue[s_String] := Module[{base = 10, text = s, exponent = 0, mark = None, markText = "", int, frac, exact},
    If[ StringContainsQ[text, "^^"],
        {base, text} = {FromDigits[First[StringSplit[text, "^^"]]], Last[StringSplit[text, "^^"]]}];
    If[ StringContainsQ[text, "*^"],
        {text, exponent} = {First[StringSplit[text, "*^"]], signedValue[Last[StringSplit[text, "*^"]]]}];
    If[ StringContainsQ[text, "`"],
        With[{at = First[First[StringPosition[text, "`", 1]]]},
            {mark, markText} = If[StringTake[text, {at, Min[at + 1, StringLength[text]]}] === "``",
                {"Accuracy", StringDrop[text, at + 1]},
                {"Precision", StringDrop[text, at]}];
            text = StringTake[text, at - 1]]];
    {int, frac} = If[StringContainsQ[text, "."], StringSplit[text, ".", All][[{1, 2}]], {text, ""}];
    exact = FromDigits[int <> frac, base] * base^(exponent - StringLength[frac]);
    Which[
        mark === None && ! StringContainsQ[text, "."], exact,
        mark === "Accuracy", SetAccuracy[exact, digitsInBase[signedValue[markText], base]],
        mark === "Precision" && markText =!= "" && exact == 0, 0.,
        mark === "Precision" && markText =!= "", SetPrecision[exact, digitsInBase[signedValue[markText], base]],
        mark === None && significantDigits[int <> frac, base], SetAccuracy[exact, digitsInBase[StringLength[frac] - exponent, base]],
        True, machineReal[exact]]
]

(* "-12", "3.5", ".5" -> the exact value *)
signedValue[t_String] := With[{unsigned = StringDelete[t, "+" | "-"]},
    If[StringStartsQ[t, "-"], -1, 1] * If[StringContainsQ[unsigned, "."],
        With[{parts = StringSplit[unsigned, ".", All]}, FromDigits[parts[[1]] <> parts[[2]]] / 10^StringLength[parts[[2]]]],
        FromDigits[unsigned]]]

(* a count of digits of the base, in decimal digits *)
digitsInBase[n_, 10] := n
digitsInBase[n_, base_Integer] := N[n Log10[base]]

(* more digits than a machine real holds: 17 decimal ones [WL 15.0.0] *)
significantDigits[digits_String, base_Integer] := With[{count = StringLength[StringDelete[digits, StartOfString ~~ "0" ..]]},
    If[base === 10, count > 17, N[count Log10[base]] > 18.5]]

(* the machine real nearest the value; below the least one, zero *)
machineReal[x_] := If[x != 0 && Abs[x] < $MinMachineNumber, 0., N[x]]

(* --- strings --- *)

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

heldLeaf["Integer" | "Real", s_String] :=
    <|"Expr" -> HoldComplete @@ {numberValue[s]}, "Literal" -> True, "Chain" -> False|>
heldLeaf["String", s_String] := held[HoldComplete @@ {stringValue[s]}]
heldLeaf["Symbol", s_String] := held[heldName[s]]
heldLeaf["Blank", s_String] := held[blankExpression[s]]
heldLeaf["Slot", s_String] := held[slotExpression[s]]
heldLeaf["Out", s_String] := held[outExpression[s]]
heldLeaf["Tag", s_String] := held[HoldComplete[s]]
heldLeaf["File", s_String] := held[HoldComplete @@ {If[StringStartsQ[s, "\""], stringValue[s], fileValue[s]]}]

(* the file a name of << or >> gives: its long names and its \: and \.
   escapes decoded, another \ kept *)
fileValue[s_String] := If[StringFreeQ[s, "\\"], s, StringReplace[s, {
    "\\." ~~ digits : Repeated[HexadecimalCharacter, {2}] :> FromCharacterCode[FromDigits[digits, 16]],
    "\\:" ~~ digits : Repeated[HexadecimalCharacter, {4}] :> FromCharacterCode[FromDigits[digits, 16]],
    "\\[" ~~ name : (LetterCharacter | DigitCharacter) .. ~~ "]" /; KeyExistsQ[longNameCharacters[], name] :> longNameCharacters[][name]}]]

expressions[xs_List] := Map[#["Expr"] &, xs]

(* f @ x, the call; a name's held call marked with the name and x, as the
   kernel reads x for it where the name is the head of the flat chain it
   stands in: a <> StringJoin @ b is StringJoin[a, b] *)
atCall[alg_, l_, r_] := With[{c = alg["Call"][l, {r}]},
    If[AssociationQ[c] && AssociationQ[l] && MatchQ[l["Expr"], HoldComplete[_Symbol]], Append[c, "At" -> {l["Expr"], r}], c]]

(* --- long names the held grammar reads --- *)

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

(* Integrate[f, x] of an integrand and its differential \[DifferentialD] x *)
integralOf[alg_, f_, d_] := If[ AssociationQ[d],
    Replace[d["Expr"], {HoldComplete[_[x_]] :> held[symbolCall["Integrate", {f["Expr"], HoldComplete[x]}]], _ :> alg["Prefix"]["Integrate", f]}],
    alg["Call"][alg["Leaf"]["Symbol", "Integrate"], {f, d}]]

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

(* the operands of a flat chain, each name @ x whose name is the chain's
   head read as x *)
$atSpliceHeads = AssociationThread[{"Composition", "RightComposition", "StringJoin", "NonCommutativeMultiply", "Dot", "Times", "Plus",
    "And", "Or", "Alternatives", "StringExpression"} -> True]
spliced[op_String, xs_List] := If[ KeyExistsQ[$atSpliceHeads, op],
    Map[If[KeyExistsQ[#, "At"] && First[#["At"]] === heldSymbol[op], Last[#["At"]], #] &, xs],
    xs]

WolframLanguageSemantic = <|
    "Leaf"    -> Function[{kind, s}, heldLeaf[kind, s]],
    "Prefix"  -> Function[{op, x}, held[If[op === "Minus", negated[x], symbolCall[op, {x["Expr"]}]]]],
    "Postfix" -> Function[{x, op}, held[symbolCall[op, {x["Expr"]}]]],
    (* a/b is Times[a, Power[b, -1]] *)
    "Binary"  -> Function[{op, l, r}, held[If[op === "Divide",
        symbolCall["Times", {l["Expr"], symbolCall["Power", {r["Expr"], HoldComplete[-1]}]}],
        symbolCall[op, {l["Expr"], r["Expr"]}]]]],
    "Infix"   -> Function[{op, xs}, Append[held[symbolCall[op, expressions[spliced[op, xs]]]], "Chain" -> op === "Times"]],
    "Ternary" -> Function[{op, a, b, c}, held[symbolCall[op, expressions[{a, b, c}]]]],
    "Call"    -> Function[{h, args}, held[heldCall[h["Expr"], expressions[args]]]],
    (* parentheses keep a number literal one, and make a product a factor *)
    "Group"   -> Function[{kind, xs}, If[kind === "Paren",
        Append[KeyDrop[First[xs], "At"], "Chain" -> False],
        held[symbolCall[kind, expressions[xs]]]]]
|>

(* --- the concrete syntax tree --- *)

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

(* --- concrete tokens --- *)

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

(* --- groups --- *)

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

(* a ;; b ;; c: a middle left out is Token`Fake`ImplicitAll *)
spanItem[a_item, semis_item, spanRest[middle_, third_]] := With[{
        steps = {step[{}, kids[semis], If[MissingQ[middle], implicitItem[Token`Fake`ImplicitAll], middle]]}},
    Which[
        MissingQ[third], stepsItem[CodeParser`BinaryNode, Span, a, steps],
        MatchQ[third, _step], stepsItem[CodeParser`TernaryNode, Span, a, Append[steps, third]],
        (* a ;; b ;; with nothing after: a span, then one beginning at the second ;; *)
        True, stepsItem[CodeParser`InfixNode, Times, stepsItem[CodeParser`BinaryNode, Span, a, steps],
            {step[{}, {concreteLeaf[Token`Fake`ImplicitTimes, ""]}, third]}]]]

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
     call, typeSpecifier, tag, colons, messageName, tilde, spanOperandItem, spanThird, spanTail, spanStart,
     semiStep, compound, equalDot, unset, tagSet, put, patternUnit, otherUnits, plainUnit, unit, errorUnits,
     binary, prefix, postfix, optionalColon, chain, flat, dotOperator, implicitTimes, inequality, plus, times, specs, table,
     expression, gap, patternRight, spanOperand, compoundOperand, tagLeft, tagRight, tildeOperand, spanStartCell,
     longOp, longPrefix, longPostfix, longBinary, longSpecs, longGroups, longCalls, groupOf, callOf, commaOperator, commaAhead,
     closerAhead, differentialAhead, integralItem, integrandOperand, implicitTimesFirst},

    patternRight = RecCell[]; spanOperand = RecCell[]; compoundOperand = RecCell[]; tagLeft = RecCell[]; tagRight = RecCell[];
    tildeOperand = RecCell[]; spanStartCell = RecCell[]; integrandOperand = RecCell[];
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
    operandAhead = ParseLookahead[ParseChoice[leafAhead, ParseCharacter["[" | "-" | "+" | "!"], ParseLiteral["<<"], ParseLiteral[";;"],
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
    (* a ;; b ;; c: the ;; after b only with an operand after it *)
    spanOperandItem = ParseAction[ParseNotFollowedBy[ParseLiteral[";;"]] ~~ operandAhead ~~ RecRef[spanOperand], #3 &];
    spanThird = ParseChoice[
        ParseAction[postOp[";;"] ~~ spanOperandItem, step[{}, kids[#1], #2] &],
        ParseAction[ParseLookahead[ParseLiteral[";;"]] ~~ RecRef[spanStartCell], #2 &]];
    spanTail = ParseAction[postOp[";;"] ~~ ParseChoice[
            ParseAction[spanOperandItem ~~ ParseOptional[spanThird], spanRest[#1, #2] &],
            ParseAction[ParseOptional[spanThird], spanRest[Missing[], #] &]],
        Function[{semis, rest}, Function[a, spanItem[a, semis, rest]]]];
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
    SetRec[patternRight, table[plainUnit, $codeParserPrecedence["Fake`PatternColon"]]];
    SetRec[spanOperand, table[unit, $codeParserPrecedence["SemiSemi"]]];
    SetRec[compoundOperand, table[unit, $codeParserPrecedence["Semi"]]];
    SetRec[tagLeft, table[unit, $codeParserPrecedence["Equal"]]];
    SetRec[tagRight, table[unit, $codeParserPrecedence["Equal"] - 1]];
    SetRec[tildeOperand, table[unit, $codeParserPrecedence["Tilde"]]];
    (* an integrand binds as tightly as the integral's prefix operator *)
    SetRec[integrandOperand, table[unit, First[Cases[$longNameTable["Prefix"], {"Integral", _, _, p_Integer, _} :> p]]]];
    expression = table[unit, 0];
    <|"Expression" -> expression, "Children" -> children[expression, gap]|>
]

(* --- the source of each node --- *)

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

(* --- line continuations --- *)

(* A \ before a newline, outside a string, a comment and the file name
   of << or >>, continues the line: CodeParser reads the source as though
   the \, the newline and the spaces and tabs after it were not there.
   Their text is in the token they fall in, else in the token after them,
   and at the end of the source in none, there a string's too. The spans
   {first, last} of them in s, those that follow one another one. *)
continuationSpans[s_String] := Module[{c = ToCharacterCode[s], n, i = 1, depth = 0, inString = False, spans = {}, runEnd, fileEnd},
    n = Length[c];
    (* the last character of the continuations from j on, j - 1 if none begins there *)
    runEnd[j_Integer] := Module[{k = j},
        While[k < n && c[[k]] === 92 && (c[[k + 1]] === 10 || c[[k + 1]] === 13),
            k += If[c[[k + 1]] === 13 && k + 2 <= n && c[[k + 2]] === 10, 3, 2];
            While[k <= n && MemberQ[{32, 9, 11, 12}, c[[k]]], k++]];
        k - 1];
    (* the last character of the spaces and the file name from j on *)
    fileEnd[j0_Integer] := Module[{j = j0},
        While[j <= n && (c[[j]] === 32 || c[[j]] === 9), j++];
        While[j <= n && (KeyExistsQ[$fileCharacterCodes, c[[j]]] || c[[j]] === 92),
            If[ c[[j]] === 92 && j < n && c[[j + 1]] === 91,
                j += 2; While[j <= n && KeyExistsQ[$alphanumericCodes, c[[j]]], j++]; If[j <= n && c[[j]] === 93, j++, Break[]],
                j++]];
        j - 1];
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
                True, i++],
            c[[i]] === 34, inString = True; i++,
            c[[i]] === 40 && i < n && c[[i + 1]] === 42, depth = 1; i += 2,
            c[[i]] === 60 && i < n && c[[i + 1]] === 60, i = fileEnd[i + 2] + 1,
            c[[i]] === 62 && i < n && c[[i + 1]] === 62, i = fileEnd[If[i + 2 <= n && c[[i + 2]] === 62, i + 3, i + 2]] + 1,
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

(* offsets into the source read without its line continuations made
   offsets into the source: a node begins where the continuations before
   its first character do, and ends past its last character *)
continuedOffsets[tree_, kept_List] := With[{at = Function[o, If[o === 1, 1, kept[[o - 1]] + 1]]},
    tree /. (a_Association /; MatchQ[Lookup[a, "Source"], {_Integer, _Integer}]) :> Append[a, "Source" -> Map[at, a["Source"]]]]

(* a failure at a character of the source read without its line
   continuations, placed at that character of the source *)
continuedFailure[f_Failure, kept_List, s_String] := With[{at = f["Position"]},
    If[IntegerQ[at], parseFailure[If[at <= Length[kept], kept[[at]], StringLength[s] + 1], f["Expected"], f["Found"]], f]]

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

(* --- what CodeParser reads again --- *)

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

(* --- build each parser once, at its first use: building the grammar
   takes longer than loading the paclet --- *)
$astGrammar := $astGrammar = grammar[ASTAlgebra]
$heldGrammar := $heldGrammar = grammar[WolframLanguageSemantic]

(* Each reads a source with line continuations without them: the held
   expressions need nothing more, the nodes are given their places in the
   source, and so is a failure. *)
WolframLanguageAST[s_String] := With[{spans = lineContinuations[s]},
    If[ spans === {},
        With[{r = parsed[$astGrammar, s]}, If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]],
        With[{r = parsed[$astGrammar, StringReplacePart[s, "", spans]], kept = keptPositions[s, spans]},
            If[FailureQ[r], continuedFailure[r, kept, s], ASTAddSource[continuedOffsets[ASTContainer[r], kept], s]]]]]

(* The held expressions read first by the reader of WolframLanguageFast.wl,
   which reads the grammar's source in one pass over its tokens; source it
   does not take the grammar reads. *)
$fastHeldReader = True

WolframLanguageHeld[s_String] := With[{spans = lineContinuations[s]},
    With[{clean = If[spans === {}, s, StringReplacePart[s, "", spans]]},
        With[{fast = If[TrueQ[$fastHeldReader], fastHeld[clean], None]},
            If[ ListQ[fast],
                DeleteCases[fast, HoldComplete[Null]],
                With[{r = parsed[$heldGrammar, clean]},
                    Which[! FailureQ[r], DeleteCases[expressions[r], HoldComplete[Null]], spans === {}, r, True, continuedFailure[r, keptPositions[s, spans], s]]]]]]]

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

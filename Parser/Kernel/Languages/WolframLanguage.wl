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
*)

BeginPackage["Wolfram`Parser`Languages`WolframLanguage`", {"Wolfram`Parser`"}]

WolframLanguageAST::usage      = "WolframLanguageAST[\"code\"] parses Wolfram Language source to a standard AST: a ContainerNode of its top-level expressions, of CallNode / InfixNode / BinaryNode / PrefixNode / PostfixNode / TernaryNode / GroupNode / LeafNode, each operator named by the head it stands for (\"Plus\", \"SetDelayed\", ...)."
WolframLanguageHeld::usage     = "WolframLanguageHeld[\"code\"] parses Wolfram Language source to the list of its top-level expressions, each in HoldComplete, as ImportString[code, {\"WL\", \"HeldExpressions\"}] gives them."
WolframLanguageGrammar::usage  = "WolframLanguageGrammar[alg] builds the Wolfram Language parser over the algebra alg, an Association with the keys of ASTAlgebra; the parser gives the list of the top-level expressions."
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
    "SlashDot" -> 28, "PlusEqual" -> 27, "Amp" -> 24, "SlashSlash" -> 18, "SlashColon" -> 11,
    "Equal" -> 9, "GreaterGreater" -> 6, "Semi" -> 4
|>

(* specs: {{precedence name, operator spec}, ...}; the levels of those
   binding more tightly than min, tightest first, in the order given *)
levelsAbove[specs_List, min_Integer] :=
    Map[Last, SortBy[
        GatherBy[Select[specs, $codeParserPrecedence[First[#]] > min &], $codeParserPrecedence[First[#]] &],
        -$codeParserPrecedence[#[[1, 1]]] &], {2}]

(* --- tokens --- *)

(* Every operator spelt in ASCII. An operator token is the longest one
   there: - is not read where ->, -- or -= is. *)
$operatorSpellings = {
    ">>>", "===", "=!=", "//@", "//.", "@@@", "^:=", "...", "|->", "<->", "->", ":>", ":=", "^=", "/:",
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

(* one spelling of an operator, not followed by what would make it a longer one *)
longest[s_String] := With[{more = Select[$operatorSpellings, StringStartsQ[#, s] && # =!= s &]},
    If[ more === {},
        ParseLiteral[s],
        ParseAction[ParseLiteral[s] ~~ ParseNotFollowedBy[ParseChoice @@ (ParseLiteral[StringDrop[#, StringLength[s]]] & /@ more)], s &]
    ]]

spellings[op_String] := Prepend[Lookup[$longNameOperators, op, {}], op]

(* a parser's pieces joined into the text it read *)
text[p_] := ParseAction[p, Function[StringJoin[Cases[Flatten[{##}], _String]]]]

nameCharacterQ[c_String] := First[ToCharacterCode[c]] > 127 && ! MemberQ[$operatorCharacters, c] && ! StringMatchQ[c, WhitespaceCharacter]

(* a letter past ASCII: a long name that is not an operator's, or a
   character *)
$letter = ParseChoice[
    ParseAction[ParseLookahead[ParseLiteral["\\["]] ~~ ParseNotFollowedBy[ParseChoice @@ (ParseLiteral /@ $operatorLongNames)] ~~
        ParseRegex["\\\\\\[[A-Za-z0-9]+]"], #3 &],
    ParseCharacter[_?nameCharacterQ]]

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

$slot = ParseAction[ParseLookahead[ParseLiteral["#"]] ~~ ParseRegex["##?([0-9]+|[A-Za-z][A-Za-z0-9]*)?"], #2 &]

$out = ParseAction[ParseLookahead[ParseLiteral["%"]] ~~ ParseRegex["%+[0-9]*"], #2 &]

(* the file of << and >>: a string, or the characters of a path or a context *)
$file = ParseChoice[$string, ParseRegex["[A-Za-z0-9$`_./~:-]+"]]

(* --- the grammar, parameterised over an algebra --- *)

(* Outside brackets, the whitespace after an operand or a postfix operator
   stops at a newline, which ends the expression if it can end there;
   after an infix or prefix operator, inside brackets and between
   expressions it takes newlines too. *)
WolframLanguageGrammar[alg_] := grammar[alg]["Program"]

(* <|"Program" -> the parser of a whole source, "Statement" -> that of one
   top-level expression and the whitespace after it|> *)
grammar[alg_] := Module[{comment, space, wsLine, wsAll, nested, top, statement},
    comment = RecCell[];
    SetRec[comment, ParseLiteral["(*"] ~~ ParseMany[ParseChoice[
        RecRef[comment],
        ParseRegex["[^(*]+"],
        ParseLiteral["("] ~~ ParseNotFollowedBy[ParseLiteral["*"]],
        ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[")"]]]] ~~ ParseLiteral["*)"]];
    space = ParseChoice[
        ParseCharacter[" " | "\t" | "\r" | "\f"],
        ParseLiteral["\\\n"], ParseLiteral["\\\r\n"],
        RecRef[comment]];
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
     binary, prefix, postfix, flat, plus, relation, relationOp, implicit, specs, table,
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
    comma = after[ParseLiteral[","], wsAll];
    (* comma-separated expressions up to the closing bracket; an empty one is Null *)
    items[close_String] := ParseChoice[
        ParseAction[ParseLookahead[ParseLiteral[close]], {} &],
        ParseAction[ParseSepBy[ParseOptional[RecRef[nested]], comma], Function[nullLeaf /@ {##}]]];

    patternRight = RecCell[]; spanOperand = RecCell[]; compoundOperand = RecCell[]; tagLeft = RecCell[]; tagRight = RecCell[];

    (* a name, or n:patt: the name binds its pattern wherever it stands;
       within the pattern a : is Optional's *)
    patternUnit = ParseAction[symbolLeaf ~~ ParseOptional[ParseAction[operator[":"] ~~ RecRef[patternRight], #2 &]],
        Function[{name, pattern}, If[MissingQ[pattern], name, alg["Binary"]["Pattern", name, pattern]]]];
    (* ;; b and ;; at the start: Span[1, ...] *)
    spanStart = ParseAction[span, Function[f, f[alg["Leaf"]["Integer", "1"]]]];
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
        spanStart];
    plainUnit = ParseChoice[symbolLeaf, otherUnits];
    unit = ParseChoice[patternUnit, otherUnits];

    (* --- postfix operators that read operands of their own --- *)
    call = ParseAction[after[longest["["] ~~ ParseNotFollowedBy[ParseLiteral["["]], wsAll] ~~ items["]"] ~~ after[ParseLiteral["]"], ws],
        Function[{open, args, close}, Function[h, alg["Call"][h, args]]]];
    part = ParseAction[after[ParseLiteral["[["], wsAll] ~~ items["]]"] ~~ after[ParseLiteral["]]"], ws],
        Function[{open, indices, close}, Function[e, alg["Infix"]["Part", Prepend[indices, e]]]]];
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
    tagSet = ParseAction[operator["/:"] ~~ RecRef[tagLeft] ~~ ParseChoice[
            ParseAction[operator[":="] ~~ RecRef[tagRight], {"TagSetDelayed", #2} &],
            ParseAction[operator["="] ~~ RecRef[tagRight], {"TagSet", #2} &],
            ParseAction[postfixOperator["=."], {"TagUnset"} &]],
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
    relation = Function[{operands, heads}, If[Length[Union[heads]] === 1,
        alg["Infix"][First[heads], operands],
        alg["Infix"]["Inequality", Riffle[operands, alg["Leaf"]["Symbol", #] & /@ heads]]]];
    relationOp[op_String, head_String] := ParseAction[operator[op], head &];
    (* a b: a product where an operand follows an operand *)
    implicit = ParseAction[ParseLookahead[ParseChoice[
        ParseCharacter[LetterCharacter | DigitCharacter | "$" | "`" | "\"" | "_" | "#" | "%" | "(" | "{"],
        ParseLiteral["<|"],
        $letter]], "*" &];

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
        {"Dot", {"InfixN", operator["."], flat["Dot"]}},
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
        {"Class`SetRelations", {"InfixL", binary["Element", "Element"]}},
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
        {"SlashSlash", {"InfixL", ParseAction[operator["//"], Function[o, Function[{l, r}, alg["Call"][r, {l}]]]]}},
        {"SlashColon", {"Postfix", tagSet}},
        {"Equal", {"InfixR", binary["=", "Set"]}},
        {"Equal", {"InfixR", binary[":=", "SetDelayed"]}},
        {"Equal", {"InfixR", binary["^=", "UpSet"]}},
        {"Equal", {"InfixR", binary["^:=", "UpSetDelayed"]}},
        {"Equal", {"InfixR", binary["|->", "Function"]}},
        {"Equal", {"Postfix", postfix["=.", "Unset"]}},
        {"GreaterGreater", {"Postfix", put}},
        {"Semi", {"Postfix", compound}}
    };

    table[u_, min_Integer] := ParseOperatorTable[u, levelsAbove[specs, min]];
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
   kept as written [WL 15.0.0]. *)
stringValue[s_String] := With[{inner = StringTake[s, {2, -2}]},
    If[StringFreeQ[inner, "\\"], inner, StringReplace[inner, $escapes]]]

$escapes = {
    "\\\r\n" -> "", "\\\n" -> "", "\\<" -> "", "\\>" -> "",
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

(* the character of each long name, "Alpha" -> the letter alpha, built at
   the first long name a string holds *)
longNameCharacters[] := longNameCharacters[] = Association[Select[
    Table[With[{c = FromCharacterCode[n]}, CharacterName[c] -> c], {n, 0, 65535}],
    StringQ[First[#]] &]]

heldLeaf["Integer" | "Real", s_String] :=
    <|"Expr" -> HoldComplete @@ {numberValue[s]}, "Literal" -> True, "Chain" -> False|>
heldLeaf["String", s_String] := held[HoldComplete @@ {stringValue[s]}]
heldLeaf["Symbol", s_String] := held[heldName[s]]
heldLeaf["Blank", s_String] := held[blankExpression[s]]
heldLeaf["Slot", s_String] := held[slotExpression[s]]
heldLeaf["Out", s_String] := held[outExpression[s]]
heldLeaf["Tag", s_String] := held[HoldComplete[s]]
heldLeaf["File", s_String] := held[HoldComplete @@ {If[StringStartsQ[s, "\""], stringValue[s], s]}]

expressions[xs_List] := Map[#["Expr"] &, xs]

WolframLanguageSemantic = <|
    "Leaf"    -> Function[{kind, s}, heldLeaf[kind, s]],
    "Prefix"  -> Function[{op, x}, held[If[op === "Minus", negated[x], symbolCall[op, {x["Expr"]}]]]],
    "Postfix" -> Function[{x, op}, held[symbolCall[op, {x["Expr"]}]]],
    (* a/b is Times[a, Power[b, -1]] *)
    "Binary"  -> Function[{op, l, r}, held[If[op === "Divide",
        symbolCall["Times", {l["Expr"], symbolCall["Power", {r["Expr"], HoldComplete[-1]}]}],
        symbolCall[op, {l["Expr"], r["Expr"]}]]]],
    "Infix"   -> Function[{op, xs}, Append[held[symbolCall[op, expressions[xs]]], "Chain" -> op === "Times"]],
    "Ternary" -> Function[{op, a, b, c}, held[symbolCall[op, expressions[{a, b, c}]]]],
    "Call"    -> Function[{h, args}, held[heldCall[h["Expr"], expressions[args]]]],
    (* parentheses keep a number literal one, and make a product a factor *)
    "Group"   -> Function[{kind, xs}, If[kind === "Paren",
        Append[First[xs], "Chain" -> False],
        held[symbolCall[kind, expressions[xs]]]]]
|>

(* --- build each parser once, at its first use: building the grammar
   takes longer than loading the paclet --- *)
$astGrammar := $astGrammar = grammar[ASTAlgebra]
$heldGrammar := $heldGrammar = grammar[WolframLanguageSemantic]

WolframLanguageAST[s_String] := With[{r = parsed[$astGrammar, s]},
    If[FailureQ[r], r, ASTAddSource[ASTContainer[r], s]]]

WolframLanguageHeld[s_String] := With[{r = parsed[$heldGrammar, s]},
    If[FailureQ[r], r, expressions[r]]]

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

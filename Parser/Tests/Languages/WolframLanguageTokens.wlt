(* :Title: WolframLanguageTokens.wlt - the tokens of Wolfram Language text *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Summary: WolframLanguageTokens: the kinds of token and what each covers, every
   character of a source in exactly one token on the paclet's own files and on text
   that is no Wolfram Language, the tokens of the reader's lexer on text that is, and
   the positions. Run via run-tests.wls. *)

ClearAll[wlPrivate, wlKindTexts, wlCoveredQ, wlCorpus, wlBroken, wlLexerSpans, wlTokenSpans, wlSourceSame]

wlPrivate[name_String] := Symbol["Wolfram`Parser`Languages`WolframLanguage`Private`" <> name]

(* the kind and the text of each token *)
wlKindTexts[s_String, opts___] := Map[{#["Kind"], #["Text"]} &, WolframLanguageTokens[s, opts]]

(* every character of s is in exactly one token: the texts joined are s, and the rows begin at
   its first character, end at its last and each begins after the one before ends *)
wlCoveredQ[s_String] := With[{tokens = WolframLanguageTokens[s], rows = WolframLanguageTokens[s, "Rows"]},
    StringJoin[Lookup[tokens, "Text", {}]] === s && Length[tokens] === Length[rows] && Or[
        s === "" && rows === {},
        s =!= "" && rows[[1, 2]] === 1 && rows[[-1, 3]] === StringLength[s] && Rest[rows[[All, 2]]] === Most[rows[[All, 3]]] + 1 &&
            Min[rows[[All, 3]] - rows[[All, 2]]] >= 0 && Developer`PackedArrayQ[rows]
    ]
]

(* ===== the kinds ===== *)

VerificationTest[
    WolframLanguageTokens["f[x]"],
    {
        <|"Kind" -> "Symbol", "Text" -> "f", "Start" -> 1, "End" -> 1, "Line" -> 1, "Column" -> 1, "Depth" -> 0, "Context" -> False|>,
        <|"Kind" -> "Open", "Text" -> "[", "Start" -> 2, "End" -> 2, "Line" -> 1, "Column" -> 2, "Depth" -> 1, "Operator" -> "[", "Partner" -> 4|>,
        <|"Kind" -> "Symbol", "Text" -> "x", "Start" -> 3, "End" -> 3, "Line" -> 1, "Column" -> 3, "Depth" -> 1, "Context" -> False|>,
        <|"Kind" -> "Close", "Text" -> "]", "Start" -> 4, "End" -> 4, "Line" -> 1, "Column" -> 4, "Depth" -> 1, "Operator" -> "]", "Partner" -> 2|>
    },
    TestID -> "tokens: a call, each token an association"]

VerificationTest[
    wlKindTexts["f[x_Integer, y__, _.] := {x, 2.5`10, \"a\\nb\"} (* c (* d *) *)\n"],
    {{"Symbol", "f"}, {"Open", "["}, {"PatternName", "x"}, {"Blank", "_"}, {"Symbol", "Integer"}, {"Operator", ","}, {"Whitespace", " "},
        {"PatternName", "y"}, {"Blank", "__"}, {"Operator", ","}, {"Whitespace", " "}, {"Blank", "_."}, {"Close", "]"}, {"Whitespace", " "},
        {"Operator", ":="}, {"Whitespace", " "}, {"Open", "{"}, {"Symbol", "x"}, {"Operator", ","}, {"Whitespace", " "}, {"Number", "2.5`10"},
        {"Operator", ","}, {"Whitespace", " "}, {"String", "\"a\\nb\""}, {"Close", "}"}, {"Whitespace", " "}, {"Comment", "(* c (* d *) *)"},
        {"Newline", "\n"}},
    TestID -> "tokens: names, patterns, numbers, strings, brackets, a nested comment, whitespace and a newline"]

VerificationTest[
    wlKindTexts["#1 + ##2 & @ #name; %% + %3; f'[x]; a`b`c"],
    {{"Slot", "#1"}, {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", " "}, {"Slot", "##2"}, {"Whitespace", " "}, {"Operator", "&"},
        {"Whitespace", " "}, {"Operator", "@"}, {"Whitespace", " "}, {"Slot", "#name"}, {"Operator", ";"}, {"Whitespace", " "}, {"Out", "%%"},
        {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", " "}, {"Out", "%3"}, {"Operator", ";"}, {"Whitespace", " "}, {"Symbol", "f"},
        {"Operator", "'"}, {"Open", "["}, {"Symbol", "x"}, {"Close", "]"}, {"Operator", ";"}, {"Whitespace", " "}, {"Symbol", "a`b`c"}},
    TestID -> "tokens: slots, outs, a derivative's primes and a name with context marks"]

VerificationTest[
    Lookup[WolframLanguageTokens["a`b + c + \\[Alpha]x"], "Context", Missing[]],
    {True, Missing[], Missing[], Missing[], False, Missing[], Missing[], Missing[], False},
    TestID -> "tokens: a symbol tells whether it has a context mark"]

VerificationTest[
    Map[{#["Kind"], #["Text"], Lookup[#, "Operator", None], Lookup[#, "LongName", False]} &,
        WolframLanguageTokens["a\\[Rule]b->c\[Rule]d\\[Element]e"]],
    {{"Symbol", "a", None, False}, {"Operator", "\\[Rule]", "->", True}, {"Symbol", "b", None, False}, {"Operator", "->", "->", False},
        {"Symbol", "c", None, False}, {"Operator", "\[Rule]", "->", False}, {"Symbol", "d", None, False},
        {"Operator", "\\[Element]", "\\[Element]", True}, {"Symbol", "e", None, False}},
    TestID -> "tokens: an operator's name is its ASCII spelling however it is written, its long name where it has none"]

VerificationTest[
    wlKindTexts["a::usage = \"u\"; a::b_ ; Message[f::tag, 1]"][[{1, 2, 3, 10, 11, 12, 18, 19, 20}]],
    {{"Symbol", "a"}, {"Operator", "::"}, {"String", "usage"}, {"Symbol", "a"}, {"Operator", "::"}, {"String", "b_"}, {"Symbol", "f"},
        {"Operator", "::"}, {"String", "tag"}},
    TestID -> "tokens: the tag of a message is a string"]

VerificationTest[
    wlKindTexts["<< Foo`Bar`; x >> out.txt; \\!\\(x\\^2\\) + \\(y\\) ; y =[free form]"],
    {{"Operator", "<<"}, {"Whitespace", " "}, {"String", "Foo`Bar`"}, {"Operator", ";"}, {"Whitespace", " "}, {"Symbol", "x"},
        {"Whitespace", " "}, {"Operator", ">>"}, {"Whitespace", " "}, {"String", "out.txt"}, {"Operator", ";"}, {"Whitespace", " "},
        {"LinearSyntax", "\\!\\(x\\^2\\)"}, {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", " "}, {"LinearSyntax", "\\(y\\)"},
        {"Whitespace", " "}, {"Operator", ";"}, {"Whitespace", " "}, {"Symbol", "y"}, {"Whitespace", " "}, {"FreeForm", "=[free form]"}},
    TestID -> "tokens: a file is a string, linear syntax and free-form input one token each"]

VerificationTest[
    wlKindTexts["a\\[NonBreakingSpace] \tb\r\nc\rd\\[IndentingNewLine]e"],
    {{"Symbol", "a"}, {"Whitespace", "\\[NonBreakingSpace] \t"}, {"Symbol", "b"}, {"Newline", "\r\n"}, {"Symbol", "c"}, {"Newline", "\r"},
        {"Symbol", "d"}, {"Newline", "\\[IndentingNewLine]"}, {"Symbol", "e"}},
    TestID -> "tokens: a run of whitespace is one token, each line break one, long names among them"]

VerificationTest[
    wlKindTexts["s = \"a\\[Alpha]\\n\\:03b1 \\.41\\101\\|01f600\\q\\\"b\"", "StringEscapes" -> True],
    {{"Symbol", "s"}, {"Whitespace", " "}, {"Operator", "="}, {"Whitespace", " "}, {"String", "\"a"}, {"StringEscape", "\\[Alpha]"},
        {"StringEscape", "\\n"}, {"StringEscape", "\\:03b1"}, {"String", " "}, {"StringEscape", "\\.41"}, {"StringEscape", "\\101"},
        {"StringEscape", "\\|01f600"}, {"StringEscape", "\\q"}, {"StringEscape", "\\\""}, {"String", "b\""}},
    TestID -> "tokens: with StringEscapes a string is its escapes and the text between them"]

VerificationTest[
    wlKindTexts["\"a\\:03b\" \"b\\", "StringEscapes" -> True],
    {{"String", "\"a"}, {"StringEscape", "\\:"}, {"String", "03b\""}, {"Whitespace", " "}, {"String", "\"b"}, {"StringEscape", "\\"}},
    TestID -> "tokens: an escape cut short is a backslash and a character, or a backslash alone at the end"]

(* ===== brackets ===== *)

VerificationTest[
    Map[{#["Text"], #["Depth"], Lookup[#, "Partner", None]} &, WolframLanguageTokens["f[{a, (b)}][[1]]"]],
    {{"f", 0, None}, {"[", 1, 11}, {"{", 2, 10}, {"a", 2, None}, {",", 2, None}, {" ", 2, None}, {"(", 3, 9}, {"b", 3, None}, {")", 3, 7},
        {"}", 2, 3}, {"]", 1, 2}, {"[", 1, 16}, {"[", 2, 15}, {"1", 2, None}, {"]", 2, 13}, {"]", 1, 12}},
    TestID -> "tokens: an opener and its closer are each other's partners, at the depth of what they hold"]

VerificationTest[
    Map[{#["Kind"], #["Text"], #["Depth"], #["Partner"]} &, Select[WolframLanguageTokens["f[(a] + {b) + c]"], KeyExistsQ[#, "Partner"] &]],
    {{"Open", "[", 1, 5}, {"Open", "(", 2, 0}, {"Close", "]", 1, 2}, {"Open", "{", 1, 0}, {"Close", ")", 1, 0}, {"Close", "]", 1, 0}},
    TestID -> "tokens: a closer takes the nearest opener of its kind; a bracket with none has partner 0"]

VerificationTest[
    Map[{#["Kind"], #["Operator"], #["Partner"]} &,
        Select[WolframLanguageTokens["<|a -> \\[LeftFloor]x\\[RightFloor], b -> m\\[LeftDoubleBracket]1\\[RightDoubleBracket]|>"], KeyExistsQ[#, "Partner"] &]],
    {{"Open", "<|", 19}, {"Open", "\\[LeftFloor]", 8}, {"Close", "\\[RightFloor]", 6}, {"Open", "\\[LeftDoubleBracket]", 18},
        {"Close", "\\[RightDoubleBracket]", 16}, {"Close", "|>", 1}},
    TestID -> "tokens: an association's brackets and the long-name brackets are openers and closers"]

(* ===== text that is no Wolfram Language ===== *)

VerificationTest[
    Map[{#["Kind"], #["Text"], Lookup[#, "Incomplete", False]} &, WolframLanguageTokens["g[\"abc"]],
    {{"Symbol", "g", False}, {"Open", "[", False}, {"String", "\"abc", True}},
    TestID -> "tokens: a string not closed is a string to the end, incomplete"]

VerificationTest[
    Map[{#["Kind"], #["Text"], Lookup[#, "Incomplete", False]} &, WolframLanguageTokens["a (* b (* c *) d"]],
    {{"Symbol", "a", False}, {"Whitespace", " ", False}, {"Comment", "(* b (* c *) d", True}},
    TestID -> "tokens: a comment not closed is a comment to the end, incomplete"]

VerificationTest[
    Map[{#["Kind"], #["Text"], Lookup[#, "Incomplete", False]} &, WolframLanguageTokens["a + \\(x\\^"]],
    {{"Symbol", "a", False}, {"Whitespace", " ", False}, {"Operator", "+", False}, {"Whitespace", " ", False}, {"LinearSyntax", "\\(x\\^", True}},
    TestID -> "tokens: linear syntax not closed is one token to the end, incomplete"]

VerificationTest[
    wlKindTexts["a + \\[Alp + \\[Nonesuch] b"],
    {{"Symbol", "a"}, {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", " "}, {"Error", "\\[Alp"}, {"Whitespace", " "}, {"Operator", "+"},
        {"Whitespace", " "}, {"Error", "\\[Nonesuch]"}, {"Whitespace", " "}, {"Symbol", "b"}},
    TestID -> "tokens: a long name half typed, and one no character has, are errors, and the tokens after them are read"]

VerificationTest[
    wlKindTexts["x = Sys` + a``b; y\\q \\"],
    {{"Symbol", "x"}, {"Whitespace", " "}, {"Operator", "="}, {"Whitespace", " "}, {"Error", "Sys`"}, {"Whitespace", " "}, {"Operator", "+"},
        {"Whitespace", " "}, {"Error", "a``b"}, {"Operator", ";"}, {"Whitespace", " "}, {"Symbol", "y"}, {"Error", "\\q"}, {"Whitespace", " "},
        {"Error", "\\"}},
    TestID -> "tokens: a name with a context mark out of place and a stray backslash are errors"]

VerificationTest[
    wlKindTexts["1 + 99^^zz + 2^^102 \.01 3"],
    {{"Number", "1"}, {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", " "}, {"Error", "99^^zz"}, {"Whitespace", " "}, {"Operator", "+"},
        {"Whitespace", " "}, {"Error", "2^^102"}, {"Whitespace", " "}, {"Error", "\.01"}, {"Whitespace", " "}, {"Number", "3"}},
    TestID -> "tokens: a number of a base no number has, a digit its base has not and a stray character are errors"]

VerificationTest[
    WolframLanguageTokens /@ {"", " ", "\n"},
    {{}, {<|"Kind" -> "Whitespace", "Text" -> " ", "Start" -> 1, "End" -> 1, "Line" -> 1, "Column" -> 1, "Depth" -> 0|>},
        {<|"Kind" -> "Newline", "Text" -> "\n", "Start" -> 1, "End" -> 1, "Line" -> 1, "Column" -> 1, "Depth" -> 0|>}},
    TestID -> "tokens: the empty text has none"]

wlBroken = {"\"", "\"abc", "\"abc\\", "(*", "(* a (* b *)", "*)", "f[", "f[x", "f[x,", "]", ")", "}", "|>", "<|", "{(])}", "\\", "\\[", "\\[Al",
    "\\[Alpha", "\\[]", "\\[Nonesuch]", "\\(", "\\(x", "\\!\\(", "\\!", "\\)", "a`", "`", "``", "a`1", "a``b", "#a`", "x_a`", "_`", "x__.", "::", "a::",
    "a::\"b", "a:: b", "<<", "<< ", "<<\"f", ">>", "x >>", "x >> \\[Foo]", "=[", "y =[a\nb\nc", "16^^", "16^^g", "40^^1", "1`", "1``", "1*^",
    "\:00a7", "a \:00a7 b", "\[Alpha]\:00a7", "\.00", "a\.00b", "'", "''", "%", "#", "##", "#\"", "#\"a", "a ~", "a /: b", "?", "?? x", "a\\\n", "\\\n",
    "\\\n\\\n", "a\\\r\nb", "\"a\\\nb", "(* \\\n", "\\:", "\\:03b", "\\:03b1", "\\.4", "\\|01f60", "\\:zzzz", "f[\\:005b]", "\|01f600", "\"\|01f600",
    "(\r\n", "\r", "\r\r\n\n", "a\tb\fc", "f @@@ g /@ h //. i /; j", "a.b..c...d", "x=.1", "x=.;y=!=z", "a b\\[InvisibleComma]c\\[InvisibleSpace]d",
    "\\[LeftDoubleBracket", "\\[RightDoubleBracket]]", "\[LeftFloor]x", "x\[RightFloor]", "\"a\" \"b\" \"c", "(* a *) (* b", "f[\"a\", (* c *) \"b",
    StringRepeat["(", 500], StringRepeat["]", 500], StringRepeat["\\q", 500], StringRepeat["a` ", 500], StringRepeat["(*", 300],
    StringRepeat["\"a\" \\ ", 800] <> "x >> y :: z"}

VerificationTest[
    Select[wlBroken, !wlCoveredQ[#] &],
    {},
    TestID -> "tokens: every character of each of the texts that are no Wolfram Language is in exactly one token, and no message is issued"]

VerificationTest[
    Select[Flatten[Table[StringTake[#, k], {k, StringLength[#]}] & /@
        {"f[x_Integer?EvenQ, opts : OptionsPattern[]] := Module[{y = x^2, s = \"a\\[Alpha]\\\"b\"}, (* note *) y /. {a_ :> a + 1}] /; x > 0\n",
            "g::usage = \"g[x] gives \\!\\(x\\^2\\).\";\nh = <|\"k\" -> #1 & /@ {1.5`20, 16^^ff}, k2 :> x\\[LeftDoubleBracket]1\\[RightDoubleBracket]|> << file`\n"}],
        !wlCoveredQ[#] &],
    {},
    TestID -> "tokens: every prefix of a source, as a source is typed, gives tokens that hold each of its characters"]

(* ===== the paclet's own files ===== *)

wlCorpus := wlCorpus = Select[FileNames["*", FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel"}], Infinity], !DirectoryQ[#] &]

VerificationTest[
    Length[wlCorpus] >= 40,
    True,
    TestID -> "tokens: the corpus is every file under the paclet's Kernel directory"]

VerificationTest[
    Select[wlCorpus, !wlCoveredQ[ByteArrayToString[ReadByteArray[#], "UTF-8"]] &],
    {},
    TestID -> "tokens: every character of each file under the paclet's Kernel directory is in exactly one token"]

(* a source cut at a place and with a character changed is text as it is typed: the same holds *)
VerificationTest[
    BlockRandom[
        SeedRandom[83];
        With[{source = ByteArrayToString[ReadByteArray[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages", "WolframLanguageTokens.wl"}]], "UTF-8"],
                characters = Characters["\"\\[](){}`_#%'~^<>|&*(;:.,\n\t \[Alpha]"]},
            Count[
                Table[
                    With[{from = RandomInteger[{1, StringLength[source] - 3000}], count = RandomInteger[{1, 20}]},
                        With[{piece = StringTake[source, {from, from + RandomInteger[{1, 3000}]}]},
                            StringReplacePart[piece, RandomChoice[characters, count],
                                Map[{#, #} &, Sort[RandomSample[Range[StringLength[piece]], Min[count, StringLength[piece]]]]][[;; count]]]
                        ]
                    ],
                    {120}
                ],
                text_ /; !wlCoveredQ[text]
            ]
        ]
    ],
    0,
    TestID -> "tokens: pieces of a source with characters changed at random give tokens that hold each of their characters"]

(* the tokens of the reader's lexer, on a source it reads to its end: what is no whitespace, newline
   or comment begins and ends where the lexer's tokens do, a pattern's name, blank and head one *)
wlLexerSpans[s_String] := With[{lexed = wlPrivate["lexedCodes"][wlPrivate["paddedCodes"][ToCharacterCode[s]]]},
    If[wlPrivate["lexerStatus"][lexed] === 0, Most[Partition[Drop[lexed, 2], 5][[All, {3, 4}]]], $Failed]
]
wlTokenSpans[s_String] := With[{rows = Select[WolframLanguageTokens[s, "Rows"], !MemberQ[{12, 13, 14}, First[#]] &]},
    Map[{#[[1, 2]], #[[-1, 3]] + 1} &, Split[rows, MatchQ[{First[#1], First[#2]}, {2, 3} | {3, 1}] && #1[[3]] + 1 === #2[[2]] &]]
]

VerificationTest[
    Select[Select[wlCorpus, StringEndsQ[#, ".wl"] &],
        Function[file, With[{s = ByteArrayToString[ReadByteArray[file], "UTF-8"]},
            StringFreeQ[s, "\\\n"] && wlLexerSpans[s] =!= wlTokenSpans[s]]]],
    {},
    TestID -> "tokens: on the paclet's sources the tokens are the reader's lexer's, where they begin and where they end"]

VerificationTest[
    Select[Select[wlCorpus, StringEndsQ[#, ".wl"] &],
        Function[file, MemberQ[WolframLanguageTokens[ByteArrayToString[ReadByteArray[file], "UTF-8"], "Rows"],
            {17, __} | {_, _, _, _, _, _, _, _, _?OddQ} | {10 | 11, _, _, _, _, _, 0, _, _}]]],
    {},
    TestID -> "tokens: the paclet's sources have no error, nothing incomplete and no bracket without its partner"]

(* the source as the lexer reads it is the readers', and so are the positions in the source of its
   characters, which the readers keep as runs *)
wlSourceSame[s_String] := With[{read = wlPrivate["readSource"][s], mine = wlPrivate["tokenSource"][s, ToCharacterCode[s]]},
    ToCharacterCode[First[read]] === Normal[First[mine]] && wlKeptPositions[read[[2]]] === Replace[mine[[2]], kept_List :> Normal[kept]]
]
wlKeptPositions[None] := None
wlKeptPositions[kept_] := Normal[wlPrivate["keptAt"][kept, Range[wlPrivate["keptCount"][kept]]]]

VerificationTest[
    Select[Join[ByteArrayToString[ReadByteArray[#], "UTF-8"] & /@ Select[wlCorpus, StringEndsQ[#, ".wl"] &],
        {"a\\:03b1 + \"\\:03b1\" (* \\:03b1 *) \\.41\\|01F600 \\:zzzz \\\n b", "x\\\r\n  y \\\n\\\n z\"\\\n\"", "\\\n", "a\\\n", "\\\na", "f[\\\n]\\\n",
            "\\|110000 \\|10ffff \\.4", "(* \\( \\:0041 *) \\:0041 \"\\\"\\:0041\" \\:0041"}],
        !wlSourceSame[#] &] // Length,
    0,
    TestID -> "tokens: the line continuations and the character escapes are read as the readers read them"]

(* ===== positions ===== *)

VerificationTest[
    Map[{#["Text"], #["Start"], #["End"], #["Line"], #["Column"]} &, WolframLanguageTokens["ab +\n  \"c\nd\" e\r\nf"]],
    {{"ab", 1, 2, 1, 1}, {" ", 3, 3, 1, 3}, {"+", 4, 4, 1, 4}, {"\n", 5, 5, 1, 5}, {"  ", 6, 7, 2, 1}, {"\"c\nd\"", 8, 12, 2, 3}, {" ", 13, 13, 3, 3},
        {"e", 14, 14, 3, 4}, {"\r\n", 15, 16, 3, 5}, {"f", 17, 17, 4, 1}},
    TestID -> "tokens: Start and End are the first and last characters, Line and Column the first character's"]

VerificationTest[
    With[{s = "f[\[Alpha], \"\|01f600\"] + x\n\|01d4d0 = 1"},
        Map[StringTake[s, {#["Start"], #["End"]}] === #["Text"] &, WolframLanguageTokens[s]]],
    {True ..},
    SameTest -> MatchQ,
    TestID -> "tokens: StringTake of the source from Start to End is the token's text"]

VerificationTest[
    Map[{#["Text"], #["Start"], #["End"], #["Column"]} &, WolframLanguageTokens["\"\|01f600\" + \|01d4d0x\ny \|01d4d0", "Offsets" -> "UTF16"]],
    {{"\"\|01f600\"", 1, 4, 1}, {" ", 5, 5, 5}, {"+", 6, 6, 6}, {" ", 7, 7, 7}, {"\|01d4d0x", 8, 10, 8}, {"\n", 11, 11, 11}, {"y", 12, 12, 1},
        {" ", 13, 13, 2}, {"\|01d4d0", 14, 15, 3}},
    TestID -> "tokens: with Offsets UTF16 a character past 65535 counts as two"]

VerificationTest[
    wlKindTexts["a +\\\n  b; 12\\\n34 + \\:03b1x"],
    {{"Symbol", "a"}, {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", "\\\n  "}, {"Symbol", "b"}, {"Operator", ";"}, {"Whitespace", " "},
        {"Number", "12\\\n34"}, {"Whitespace", " "}, {"Operator", "+"}, {"Whitespace", " "}, {"Symbol", "\\:03b1x"}},
    TestID -> "tokens: a line continuation between tokens is whitespace, one in a number is in it, and a character escape is a letter of its name"]

(* ===== rows ===== *)

VerificationTest[
    WolframLanguageTokens["f[x_] := \"a", "Rows"],
    {{1, 1, 1, 1, 1, 0, 0, 0, 0}, {10, 2, 2, 1, 2, 1, 5, 360, 0}, {2, 3, 3, 1, 3, 1, 0, 0, 0}, {3, 4, 4, 1, 4, 1, 0, 0, 0}, {11, 5, 5, 1, 5, 1, 2, 361, 0},
        {13, 6, 6, 1, 6, 0, 0, 0, 0}, {9, 7, 8, 1, 7, 0, 0, 14, 0}, {13, 9, 9, 1, 9, 0, 0, 0, 0}, {5, 10, 11, 1, 10, 0, 0, 0, 1}},
    TestID -> "tokens: the rows, nine integers for each token"]

VerificationTest[
    With[{data = WolframLanguageTokens["f[a`b_] := \\[Alpha] -> \"s", "Data"], tokens = WolframLanguageTokens["f[a`b_] := \\[Alpha] -> \"s"]},
        {Keys[data], data["Columns"], Developer`PackedArrayQ[data["Rows"]],
            data["Kinds"][[data["Rows"][[All, 1]]]] === Lookup[tokens, "Kind"],
            Map[If[# === 0, None, data["Operators"][[#]]] &, data["Rows"][[All, 8]]] === Lookup[tokens, "Operator", None],
            Map[BitAnd[#, data["Flags"]["Incomplete"]] > 0 &, data["Rows"][[All, 9]]] === Lookup[tokens, "Incomplete", False],
            Map[BitAnd[#, data["Flags"]["LongName"]] > 0 &, data["Rows"][[All, 9]]] === Lookup[tokens, "LongName", False],
            Pick[Map[BitAnd[#, data["Flags"]["Context"]] > 0 &, data["Rows"][[All, 9]]], data["Rows"][[All, 1]], 2]}
    ],
    {{"Columns", "Kinds", "Operators", "Flags", "Rows"}, {"Kind", "Start", "End", "Line", "Column", "Depth", "Partner", "Operator", "Flags"}, True, True,
        True, True, True, {True}},
    TestID -> "tokens: the data names what the integers of the rows stand for"]

VerificationTest[
    {WolframLanguageTokens[x], WolframLanguageTokens["a", "Nonesuch"]},
    {HoldPattern[WolframLanguageTokens[x]], HoldPattern[WolframLanguageTokens["a", "Nonesuch"]]},
    SameTest -> MatchQ,
    TestID -> "tokens: what is no string, and a form it has not, stay as they are"]

(* ===== many stops ===== *)

(* the text read again after a stop is a window of it: the tokens are those of the whole text read
   again at each stop *)
VerificationTest[
    With[{s = StringRepeat["f[x_, \"s\"] := {x, 1.5} (* c *) \\q a::b << file` \[Alpha] ` g[\"t\"]\n", 60] <> "\"open"},
        With[{rows = Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$tokenWindow = 10^9}, WolframLanguageTokens[s, "Rows"]]},
            Map[Function[window, Block[{Wolfram`Parser`Languages`WolframLanguage`Private`$tokenWindow = window}, WolframLanguageTokens[s, "Rows"]] === rows],
                {128, 512, 4096}]
        ]
    ],
    {True, True, True},
    TestID -> "tokens: a text of many stops read by windows has the tokens it has read whole at each stop"]

(* ===== the typed code ===== *)

(* the typed functions are declarations a compiler of typed code takes; evaluated as they are, with
   no compiler, they give what they give compiled *)
VerificationTest[
    With[{s = "f[x_h, \"a\\n\"] := (* c *) {\\[Alpha], a::b} \\q ]\n\\:03b1"},
        With[{codes = Developer`ToPackedArray[ToCharacterCode[s]]},
            With[{tokens = wlPrivate["lexerTokens"][codes],
                    arguments = Function[tokens, {wlPrivate["paddedCodes"][codes], wlPrivate["$fastClasses"], tokens, wlPrivate["$fastLongOpTable"],
                        wlPrivate["$tokenGroups"], wlPrivate["tokenParameters"][True]}]},
                {Head /@ {wlPrivate["$fastTokenRowsDeclaration"], wlPrivate["$fastTokenGroupsDeclaration"], wlPrivate["$fastTokenEscapesDeclaration"]},
                    wlPrivate["evaluatedDeclaration"][wlPrivate["$fastTokenRowsDeclaration"],
                        {wlPrivate["$lexLongNameDeclaration"], wlPrivate["$lexCommentDeclaration"]}] @@ arguments[tokens] ===
                        wlPrivate["fastTokenRowsFunction"] @@ arguments[tokens],
                    wlPrivate["evaluatedDeclaration"][wlPrivate["$fastTokenGroupsDeclaration"], {}][{1, 2, 0, -2, 3, -1, -3}, 12] ===
                        wlPrivate["fastTokenGroupsFunction"][{1, 2, 0, -2, 3, -1, -3}, 12],
                    wlPrivate["evaluatedDeclaration"][wlPrivate["$fastTokenEscapesDeclaration"], {}][codes] === wlPrivate["fastTokenEscapesFunction"][codes]}
            ]
        ]
    ],
    {{FunctionDeclaration, FunctionDeclaration, FunctionDeclaration}, True, True, True},
    TestID -> "tokens: the typed rows, brackets and escapes evaluated as they are give what they give compiled"]

(* :Title: WolframLanguageReaderBounds.wlt - the reader's arrays hold any source *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Summary: the typed lexer and parser write the tokens, the program and the frames with plain
   stores into arrays of a size fixed before the read: n + 1 tokens for n codes, 8 instructions a
   token and 16 besides, 4 frames a token and 64 besides. A copy of the typed functions as plain
   functions, its arrays lists of the same sizes and each store checked, so that a store past an array
   stops the read and fails the test, reads sources built to come close to each bound and counts what
   each needs at its most: the tokens, the longest program and the deepest frames. Run via
   run-tests.wls. *)

ClearAll[boundsRead, $boundsContext, $boundsDepth, $boundsLength, boundsStoreHeld, boundsStore, boundsReader, boundsMeasure, $boundsCases, $boundsResults]

$boundsContext = "Wolfram`Parser`Languages`WolframLanguage`Private`";

(* each typed function the read calls as a plain function, under a name of its own: its unchecked
   block and arrays made a body and lists, the calls of the others made calls of their copies, and
   in the parser the deepest frame and the longest program kept, whether the read ends or stops *)
$boundsDepth = 0;
$boundsLength = 0;

(* a checked store: a[[i]] = v where i is in a, and the read stopped where it is not *)
SetAttributes[{boundsStoreHeld, boundsStore}, HoldAll];
boundsStore[a_, i_, v_] := With[{k = i, x = v}, If[1 <= k <= Length[a], a[[k]] = x, Throw[{k, Length[a]}, "ReaderBoundsOverrun"]]];
boundsReader[] := boundsReader[] = With[{names = {"fastLex", "lexLongName", "lexComment", "lexQuoted", "lexFile", "lexNumber", "lexSlot",
        "lexBlank", "lexBoxes", "fastParse", "fastLed"}},
    With[{renames = Thread[(Symbol[$boundsContext <> #] & /@ names) -> (Symbol[$boundsContext <> "bounds" <> #] & /@ names)]},
        Scan[
            Function[name, With[{f = Symbol[$boundsContext <> "$" <> name <> "Declaration"][[2, 1]]},
                With[{g = Fold[ReplaceAll, f, {
                        {HoldPattern[Native`UncheckedBlock[e_]] :> e},
                        {HoldPattern[Native`UncheckedArray[v_, len_]] :> ConstantArray[v, len]},
                        {HoldPattern[Set[Part[a_Symbol, i_], v_]] :> boundsStoreHeld[a, i, v]},
                        Append[renames, boundsStoreHeld -> boundsStore],
                        If[ name === "fastParse",
                            With[{sp = Symbol[$boundsContext <> "sp"], on = Symbol[$boundsContext <> "on"]},
                                {HoldPattern[Increment[sp]] :> (sp++; If[sp > $boundsDepth, $boundsDepth = sp]), HoldPattern[Increment[on]] :> (on++; If[on > $boundsLength, $boundsLength = on])}
                            ],
                            {}
                        ]
                    }]},
                    ToExpression[$boundsContext <> "bounds" <> name, InputForm, Function[s, s = g, HoldFirst]]
                ]
            ]],
            names
        ];
        True
    ]
];

(* the codes, tokens, instructions and frames a read of s needs, and the store past an array, {position, length}, that stopped it, or None *)
boundsMeasure[s_String] := Module[{tables = Symbol[$boundsContext <> "$fastProgramTables"], codes = Join[ToCharacterCode[s], {0, 0, 0}], lexed = {0, 0}, overrun},
    boundsReader[];
    $boundsDepth = 0;
    $boundsLength = 0;
    overrun = Catch[boundsRead[codes, tables, lexed]; None, "ReaderBoundsOverrun"];
    <|"Source" -> s, "Codes" -> StringLength[s], "Tokens" -> lexed[[2]], "Instructions" -> $boundsLength, "Frames" -> $boundsDepth, "Overrun" -> overrun|>
];

SetAttributes[boundsRead, HoldRest];
boundsRead[codes_, tables_, lexed_] := Module[{program},
    lexed = Symbol[$boundsContext <> "boundsfastLex"][codes, Sequence @@ tables[[1 ;; 6]]];
    program = Symbol[$boundsContext <> "boundsfastParse"][lexed, Symbol[$boundsContext <> "boundsfastLed"][lexed, Sequence @@ tables[[7 ;; 9]]],
        Sequence @@ tables[[10 ;; 16]], codes, tables[[1]]]
];

(* sources built to come close to each bound: a token a character, the most instructions a token
   (runs of ;;), the most frames a token (runs of prefix operators), and deep brackets and chains *)
$boundsCases = {
    StringRepeat[";;", 60], StringRepeat[";", 60], "a" <> StringRepeat[";;b", 40], StringRepeat["{a;;,f[;;],-!x'}", 10],
    StringRepeat["-!", 30] <> "x", StringRepeat["- ", 60] <> "x", StringRepeat["+-", 30] <> "x", StringRepeat["!", 60] <> "x",
    StringRepeat["(", 60] <> "x" <> StringRepeat[")", 60], StringRepeat["{", 60] <> StringRepeat["}", 60], StringRepeat["f[", 60] <> StringRepeat["]", 60],
    StringRepeat["-(", 40] <> "x" <> StringRepeat[")", 40], StringRepeat["{-!(", 20] <> "x" <> StringRepeat[")}", 20], "a" <> StringRepeat["[[1]]", 30],
    StringRiffle[Table["a", 40], "^"], StringRiffle[Table["-a", 40], "^"], StringRiffle[Table["a", 40], "="], StringRiffle[Table["f", 40], "@"],
    StringRiffle[Table["a", 60], " "], StringRepeat["#&", 40], StringRepeat["a++", 40], StringRepeat["t/:a=b;", 20], StringRiffle[Table["a", 31], "~f~"]
};

$boundsResults := $boundsResults = boundsMeasure /@ $boundsCases;

VerificationTest[
    Select[$boundsResults, ! (#Overrun === None && #Tokens <= #Codes + 1 && #Instructions <= 8 #Tokens + 16 && #Frames <= 4 #Tokens + 64) &],
    {},
    TestID -> "Reader bounds: no source needs more tokens, instructions or frames than the arrays hold, and no store goes past one"
]

VerificationTest[
    {
        Max[#Tokens / #Codes & /@ $boundsResults] > 1,
        Max[N[#Instructions / #Tokens] & /@ $boundsResults] >= 2.9,
        Max[N[#Frames / #Tokens] & /@ $boundsResults] >= 1.9
    },
    {True, True, True},
    TestID -> "Reader bounds: the sources come close to each bound, a token a character, 3 instructions and 2 frames a token"
]

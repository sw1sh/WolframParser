(* :Title: WolframLanguageChunks.wlt - a huge source lexed and parsed a window at a time *)
(* :Context: Wolfram`Parser`Languages`WolframLanguage` *)
(* :Summary: WolframLanguageChunks.wl lexes a source of more than 2^20 codes a window of codes at a
   time and parses it a window of statements at a time. Its tokens and program are the ones the typed
   lexer and parser give of the whole source at once: here with windows of a few codes and tokens, so
   that nearly every line ends one, on sources built to cut where a token reads its neighbours, on
   the paclet's own sources and on sources that do not read; and a large source is read in windows,
   not at once. Run via run-tests.wls. *)

ClearAll[chunksPrivate, chunksSame, chunksCases, chunksSources, chunksCalls]

chunksPrivate[name_String] := Symbol["Wolfram`Parser`Languages`WolframLanguage`Private`" <> name]

Block[{$ContextPath = {"Wolfram`Parser`Languages`WolframLanguage`", "Wolfram`Parser`", "System`"}, $Context = "Global`"},
    Get[FileNameJoin[{chunksPrivate["$languagesDirectory"], "WolframLanguageChunks.wl"}]]
];

(* the widths, in codes and in tokens, at which the windows of s give what the whole gives, or {}:
   the program only of tokens the lexer reads to the end, as the reader parses no others *)
chunksSame[s_String] := With[{padded = chunksPrivate["paddedCodes"][ToCharacterCode[s]]},
    With[{lexed = chunksPrivate["windowLexed"][padded]},
        Join[
            Select[{8, 23, 64}, chunksPrivate["chunkedLexed"][padded, #] =!= lexed &],
            If[ First[lexed] =!= 0, {},
                With[{program = chunksPrivate["windowProgram"][lexed, padded]},
                    Select[{2, 5, 17}, chunksPrivate["chunkedProgram"][lexed, padded, #] =!= program &]
                ]
            ]
        ]
    ]
]

(* a token that reads the one before it or after it, across a line: a message name, a slot, a
   number and a dot, ?, <<, a string and a comment over lines, returns, brackets and operators open at
   a line's end, ; and ;; *)
chunksCases = {
    "a::\nb", "a::b\nc::d", "a :: b\nc", "a\n:: b", "#\nx", "#a\n#b", "?a\nb", "??a*\nb\nc", "<<file\nx", "1.\n5", "1.5\n.5", "a\n.5",
    "x_\n.y", "x\n_y", "\"multi\nline\nstring\"\nx", "(* a\ncomment *)\nx\n(* b *)", "a\r\nb\r\nc", "f[x,\ny]\nz", "a +\nb\nc", "f\n[x]",
    "a\n-b\n!c\n+d", "a;\nb;\n\nc", "{1,\n2}\n{3}", "a;;\nb;;c\n;;", "\\[Alpha]\n\\[Beta]", "a\n\n\n\nb", "  a\n  b  \n", "%\n%%\n%3", "x'\ny''",
    "1`2\n3``4", "2^^101\n16^^ff", "a // f\nb @@ g\nc /@ h", "\\[Integral] f \\[DifferentialD]x\ny", "x = 1;\n\n(* c *)\ny",
    "f[x_] := x^2\ng[y_] := y + 1\nh = 3", "{a\nb", "a +\n", "\"open\nx", "(* open\nx", "a\n]\nb"
};

VerificationTest[
    Select[chunksCases, chunksSame[#] =!= {} &],
    {},
    TestID -> "chunks: windows of a few codes and tokens give the whole source's tokens and program, across lines that read their neighbours"]

chunksSources = Select[FileNames["*.wl", FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel"}], Infinity],
    FileByteCount[#] < 60000 &];

VerificationTest[
    Select[chunksSources, chunksSame[ByteArrayToString[ReadByteArray[#], "UTF-8"]] =!= {} &],
    {},
    TestID -> "chunks: on the paclet's sources, windows of a few codes and tokens give the whole source's tokens and program"]

(* the windows the typed lexer and parser read, in codes and in tokens, while the windows of the
   source at width read it *)
chunksCalls[s_String, width_Integer, tokenWidth_Integer] := Module[{codes = {}, tokens = {}, padded, lexed, same},
    padded = chunksPrivate["paddedCodes"][ToCharacterCode[s]];
    With[{lex = chunksPrivate["windowLexed"], parse = chunksPrivate["windowProgram"]},
        Internal`InheritedBlock[{lex, parse},
            DownValues[lex] = Prepend[DownValues[lex], HoldPattern[lex[x_List]] /; (AppendTo[codes, Length[x] - 3]; False) :> Null];
            DownValues[parse] = Prepend[DownValues[parse], HoldPattern[parse[l_List, _]] /; (AppendTo[tokens, l[[2]]]; False) :> Null];
            lexed = chunksPrivate["chunkedLexed"][padded, width];
            same = chunksPrivate["chunkedProgram"][lexed, padded, tokenWidth] === parse[lexed, padded];
            {Length[padded] - 3, Max[codes], Length[codes] > 1, lexed[[2]], Max[Most[tokens]], Length[tokens] > 2, same}
        ]
    ]
]

VerificationTest[
    MatchQ[
        chunksCalls[ByteArrayToString[ReadByteArray[FileNameJoin[{chunksPrivate["$languagesDirectory"], "WolframLanguage.wl"}]], "UTF-8"], 4096, 2000],
        {n_, c_, True, t_, w_, True, True} /; c <= 4096 && c < n && w < t
    ],
    True,
    TestID -> "chunks: a large source is lexed and parsed in windows, none of them the whole, to the same program"]

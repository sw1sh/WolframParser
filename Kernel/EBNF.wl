(* :Package: Wolfram`Parser`EBNF`
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

   The output of `EBNFParseFile[path]` / `EBNFParseString[source]` is an
   `Association[name -> ParserCombinator]` covering every rule in the
   file. The caller wires up lexical primitives (rules whose body is a
   `:::` regex-style char class, or `::-` token construction) by
   passing `"PrimitiveOverrides" -> <|name -> ParserCombinator|>`. *)

BeginPackage["Wolfram`Parser`EBNF`", {"Wolfram`Parser`"}]

EBNFParse::usage =
    "EBNFParse[source] reads a BNF grammar from a string and returns " <>
    "an Association of rule names to ParserCombinators. " <>
    "EBNFParse[File[path]] reads from a file.";

EBNFRules::usage =
    "EBNFRules[source] returns the list of raw EBNFRule[name, kind, " <>
    "alts] structures parsed from `source`, without lowering them to " <>
    "ParserCombinators. Useful for inspecting the parsed grammar shape. " <>
    "EBNFRules[File[path]] reads from a file.";

Begin["`Private`"]


(* ===== the BNF grammar, expressed in our own combinators ===== *)

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

alts = ParseSepBy1[altSeq, pipe]

ruleP = ParseAction[
    nonTerm ~~ wsc ~~ arrow ~~ wsc ~~ alts,
    With[{name = #1[[1]], kind = #3, body = #5},
        EBNFRule[name, kind, body]
    ] &
]

grammarP = ParseAction[wsc ~~ ParseMany[ParseAction[ruleP ~~ wsc, #1 &]], #2 &]


(* ===== Lowering ===== *)

ws$lowered := ParseMany[ParseCharacter[WhitespaceCharacter]]

lowerElt[Lit[s_String], _, _] := ParseLiteral[s]

lowerElt[NonTerm[name_String], symMap_, overrides_] :=
    Which[
        KeyExistsQ[overrides, name],
            overrides[name],
        KeyExistsQ[symMap, name],
            With[{sym = symMap[name]}, ParseRecursive[sym]],
        True,
            ParseFail["No parser bound for non-terminal: " <> name]
    ]

lowerElt[Rep["Many", inner_], symMap_, overrides_] :=
    ParseMany[lowerElt[inner, symMap, overrides]]

(* Lower one alternative sequence - lowered elements separated by an
   optional-whitespace parser, then drop the whitespace pieces from the
   result list. The empty case (e.g. the body of `<nothing>` or the
   second alternative of `<annotations>`) lowers to ParseSucceed[Null]
   so the rule matches the empty string. *)
lowerSeq[{}, _, _] := ParseSucceed[Null]

lowerSeq[{single_}, symMap_, overrides_] :=
    lowerElt[single, symMap, overrides]

lowerSeq[elts_List, symMap_, overrides_] :=
    ParseAction[
        ParseSequence @@ Riffle[
            lowerElt[#, symMap, overrides] & /@ elts,
            ws$lowered
        ],
        Function[{##}[[Range[1, Length[{##}], 2]]]]
    ]

lowerBody[alts_List, symMap_, overrides_] :=
    Switch[Length[alts],
        0, ParseFail["empty rule body"],
        1, lowerSeq[First[alts], symMap, overrides],
        _, ParseChoice @@ (lowerSeq[#, symMap, overrides] & /@ alts)
    ]


(* ===== Public entry points ===== *)

(* Parse the BNF source via the combinator grammar above and return the
   raw rule list. Useful for tests and inspection. *)
EBNFRules[source_String] := Parse[grammarP, source]
EBNFRules[File[path_String]] := EBNFRules[Import[path, "Text"]]

Options[EBNFParse] = {"PrimitiveOverrides" -> <||>}

EBNFParse[source_String, OptionsPattern[]] :=
    Block[{rules, gram, overrides, symMap, parsers},
        overrides = OptionValue["PrimitiveOverrides"];
        rules = EBNFRules[source];
        If[ MatchQ[rules, _ParseError],
            Return[rules]
        ];
        (* Only `::=` and `:==` rules auto-lower; `::-` and `:::` rules
           describe tokens / character classes that the caller supplies. *)
        gram = Association @ Cases[rules,
            EBNFRule[name_, "::=" | ":==", body_] :> (name -> body)
        ];
        symMap = AssociationMap[Function[Unique["ebnfRule$"]], Keys[gram]];
        parsers = Association @ KeyValueMap[
            Function[{name, body},
                name -> lowerBody[body, symMap, overrides]
            ],
            gram
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

EBNFParse[File[path_String], opts : OptionsPattern[]] :=
    EBNFParse[Import[path, "Text"], opts]


End[]
EndPackage[]

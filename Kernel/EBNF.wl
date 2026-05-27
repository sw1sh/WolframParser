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

   The output of `EBNFParseFile[path]` / `EBNFParseString[source]` is an
   `Association[name -> ParserCombinator]` covering every rule in the
   file. The caller wires up lexical primitives (rules whose body is a
   `:::` regex-style char class, or `::-` token construction) by
   passing `"PrimitiveOverrides" -> <|name -> ParserCombinator|>`. *)

BeginPackage["Wolfram`Parser`"]

EBNFParse::usage =
    "EBNFParse[source] reads a BNF grammar from a string and returns " <>
    "an Association of rule names to ParserCombinators. " <>
    "EBNFParse[File[path]] reads from a file.";

EBNFRules::usage =
    "EBNFRules[source] returns the list of raw EBNFRule[name, kind, " <>
    "alts] structures parsed from `source`, without lowering them to " <>
    "ParserCombinators. Useful for inspecting the parsed grammar shape. " <>
    "EBNFRules[File[path]] reads from a file.";

Begin["`EBNFPrivate`"]


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

(* Each iteration of a ParseMany has to consume any whitespace that
   sits between the previous match and this one - the lowering of an
   alternative sequence inserts ws BETWEEN elements but not at the
   start, so a bare ParseMany would stop at the first ws of the
   continuation. Prepend a ws-consumer per iteration. *)
lowerElt[Rep["Many", inner_], symMap_, overrides_] :=
    ParseMany[
        ParseAction[
            ws$lowered ~~ lowerElt[inner, symMap, overrides],
            #2 &
        ]
    ]

(* ManyAlts holds a list-of-alt-bodies (each alt body is a list of
   elements). Emitted by the left-recursion-elimination rewrite for
   the repeating tail of an originally-left-recursive rule. *)
lowerElt[Rep["ManyAlts", altsList_List], symMap_, overrides_] :=
    ParseMany[
        ParseAction[
            ws$lowered ~~ lowerBody[altsList, symMap, overrides],
            #2 &
        ]
    ]

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

sortAltsLongestFirst[alts_List] := SortBy[alts, -Length[#] &]


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
        (* Apply direct-left-recursion elimination before lowering, so the
           PEG ordering of the lowered ParseChoice doesn't commit to a
           non-recursive alt and miss the recursive form. *)
        gram = AssociationMap[
            Function[name, rewriteLeftRecursive[name, gram[name]]],
            Keys[gram]
        ];
        (* Then sort each rule's alts longest-first so a shared-prefix
           alt pair like `<constant> | <functor>(<fof_arguments>)` tries
           the longer (and more specific) form before the bare prefix. *)
        gram = sortAltsLongestFirst /@ gram;
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

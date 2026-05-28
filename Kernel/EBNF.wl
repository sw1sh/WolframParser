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

(* The combinator used to fold lowered alternatives. `ChoiceLongest`
   (POSIX longest-match) is the right semantics for grammars that
   factor their alternatives across multiple rule levels - TPTP's
   `<fof_atomic_formula> ::= <fof_plain_atomic_formula> | <fof_defined_atomic_formula>`
   is the canonical case: both alternatives can consume the same
   leading function-application term, but only the second reaches the
   trailing `= rhs` of `<fof_defined_infix_formula>`. PEG `Choice`
   commits to the first match and never reaches the equality form.

   Three modes, set via the `"ChoiceMode"` option on `EBNFParse`:
     - "PEG"     PEG-ordered (first match wins).  Fast.
     - "Longest" Always try every alt, pick the one that consumes
                 the most input.  Correct for ambiguous grammars but
                 ~30x slower on TPTP-scale rules.
     - "Auto"    (default) Hybrid: when a rule's alts have *equal
                 element counts*, sortAltsLongestFirst can't pick a
                 winner statically, so use ChoiceLongest for that
                 rule.  When lengths differ (the common case), the
                 longest-prefix alt is unambiguous and PEG with
                 longest-first is both fast and correct. *)
$choiceMode = "Auto"

chooseCombinator[alts_List] :=
    Switch[$choiceMode,
        "PEG",     ParseChoice,
        "Longest", ParseChoiceLongest,
        _,         (* "Auto": if ANY two alts share a length, the
                     longest-alt-first sort can't fully disambiguate,
                     so fall back to POSIX longest-match. This catches
                     `<cnf_literal>` (lengths 4, 2, 1, 1 - the two
                     1-elt alts tie) and `<nonassoc_connective>` while
                     leaving simple alternation rules like
                     `<TPTP_input> ::= <annotated_formula> | <include>`
                     in fast PEG order when only one alt at each
                     length applies. *)
                   If[ Length[Union[Length /@ alts]] === Length[alts],
                       ParseChoice, ParseChoiceLongest]
    ]

lowerBody[alts_List, symMap_, overrides_] :=
    Switch[Length[alts],
        0, ParseFail["empty rule body"],
        1, lowerSeq[First[alts], symMap, overrides],
        _, chooseCombinator[alts] @@
            (lowerSeq[#, symMap, overrides] & /@ alts)
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

(* Use Ordering for a stable sort - SortBy is *unstable* in Mathematica,
   which would reorder equal-length alts arbitrarily. For TPTP's
   `<nonassoc_connective> ::= <=> | => | <= | ...` an unstable sort
   may put `<=` before `<=>`, in which case PEG commits to the prefix
   match and `<=>` never parses. Stable descending-by-length keeps the
   original ordering between alts of the same length, so the BNF
   author's "more-specific-first" ordering is preserved. *)
sortAltsLongestFirst[alts_List] := alts[[Ordering[-Length /@ alts]]]


(* ===== Public entry points ===== *)

(* ===== Token / char-class rule compilation =====

   `::-` and `:::` rules use regex-style bodies (`[a-z]`, `[+-]`,
   `(<x>|<y>)`, `<x>*`, `<x>+`) at the *character* level - the brackets
   and parens are meta, not literal, and adjacent elements have no
   whitespace between them. The structured token tree the main BNF
   parser produces for `::=` rules tokenizes `[a-z]` for THAT context,
   so reusing it would lose the char-class shape.

   Instead, we reconstruct the original body string from the structured
   tokens (the reconstruction is exact because every Lit / NonTerm /
   Rep maps to its original source) and run a second parser - the
   `regexParser` below - on that string. The second parser is itself
   built out of `Parse*` combinators (same library this paclet exposes);
   its action functions return *ParserCombinator values* instead of
   strings, so the regex source compiles directly to the target parser.

   This is the same "use the combinator core to parse its own meta-
   grammar" pattern the BNF parser uses, just applied to a different
   meta-grammar (regex syntax instead of BNF rule shapes). *)

reconstructBody[alts_List] :=
    StringRiffle[reconstructAlt /@ alts, "|"]

reconstructAlt[elts_List] :=
    StringJoin[reconstructElt /@ elts]

reconstructElt[Lit[s_String]]            := s
reconstructElt[NonTerm[n_String]]        := "<" <> n <> ">"
reconstructElt[Rep["Many", inner_]]      := reconstructElt[inner] <> "*"

(* The regex meta-grammar's action functions look up non-terminal
   references in these two Block-scoped maps. *)
regexSymMap   = <||>
regexOverrides = <||>

regexLookupRef[name_String] :=
    Which[
        KeyExistsQ[regexOverrides, name],
            regexOverrides[name],
        KeyExistsQ[regexSymMap, name],
            With[{sym = regexSymMap[name]}, ParseRecursive[sym]],
        True,
            ParseFail["No parser bound for non-terminal: " <> name]
    ]

(* The regex meta-grammar, built with Parse* combinators. Each piece's
   action returns a ParserCombinator value (the compiled target parser
   for that sub-expression). *)

regexMetaChar = "|" | "*" | "+" | "?" | "(" | ")" | "[" | "]" | "<" | "{" | "\\"
regexCharNotMeta = ParseCharacter[_ ? (! MatchQ[#, regexMetaChar] &)]

(* `\nnn` octal char-code escape, `\n`/`\r`/`\t`/`\\`/`\'`/`\"` named
   escape, or any other `\X` as the literal X. Used both outside and
   inside char classes (so `[\40-\41]` and `\n` both compile). *)
ccOctalDigit = ParseCharacter[CharacterRange["0", "7"]]

ccOctalEscapeChar = ParseAction[
    ParseLiteral["\\"] ~~ ccOctalDigit ~~ ParseMany[ccOctalDigit],
    FromCharacterCode[ToExpression["8^^" <> #2 <> StringJoin @ #3]] &
]

ccNamedEscapeChar = ParseAction[
    ParseLiteral["\\"] ~~ ParseCharacter[_],
    Replace[#2, {"n" -> "\n", "r" -> "\r", "t" -> "\t"}] &
]

(* a "char-class char": one resolved character.  Used as the endpoint
   of a range `c-c` and as a standalone item.

   Inside `[...]`, regex metas like `|`, `*`, `+`, `?`, `(`, `)`, `<`,
   `{`, `.`, `$` lose their meta meaning - the class-terminator `]`,
   the escape introducer `\`, and the range delimiter `-` are the only
   chars that retain syntactic role. `^` is meta only at the *start*
   of the class (handled at `regexCharClass`); inside an item it's a
   literal `^`. So a per-class-context "not meta" parser is strictly
   more permissive than the outside-class form, which lets `[|]`,
   `[*]`, `[+-]`, etc. compile to one-char alternatives. *)
ccCharNotMeta = ParseCharacter[_ ? (# =!= "]" && # =!= "\\" && # =!= "-" &)]

ccChar = ParseChoice[
    ccOctalEscapeChar,
    ccNamedEscapeChar,
    ccCharNotMeta
]

regexCharClassRangeItem = ParseAction[
    ccChar ~~ ParseLiteral["-"] ~~ ccChar,
    CharacterRange[#1, #3] &
]

regexCharClassItem = ParseChoice[regexCharClassRangeItem, ccChar]

(* char class with optional leading `^` for negation - `[^x]` becomes
   `ParseCharacter[_?(! StringMatchQ[#, x] &)]` so it matches anything
   *except* the listed set.

   Range items resolve to a List of chars via CharacterRange; single
   items are bare strings. Flatten[parts] coalesces both shapes into
   one flat char list, which Apply[Alternatives, ...] turns into the
   one-of pattern the ParseCharacter wants. *)
regexCharClass = ParseAction[
    ParseLiteral["["] ~~ ParseOptional[ParseLiteral["^"]] ~~
        ParseSome[regexCharClassItem] ~~ ParseLiteral["]"],
    With[{
        neg = ! MissingQ[#2],
        chars = Flatten[#3]
    },
        With[{pat = If[Length[chars] === 1, chars[[1]], Apply[Alternatives, chars]]},
            If[ neg,
                ParseCharacter[_?(! StringMatchQ[#, pat] &)],
                ParseCharacter[pat]
            ]
        ]
    ] &
]

(* Outside a char class: bare `.` is the regex any-char metacharacter
   (so `<printable_char> ::: .` matches any single char); a backslash
   escape resolves the same way the char-class form does; everything
   else is a one-character literal. *)
regexDot = ParseAction[ParseLiteral["."], ParseCharacter[_] &]

regexEscape = ParseAction[
    ccOctalEscapeChar | ccNamedEscapeChar,
    ParseLiteral[#] &
]

regexLiteralChar = ParseAction[regexCharNotMeta, ParseLiteral[#] &]

regexRefName = ParseAction[
    ParseCharacter[LetterCharacter | "_"] ~~
        ParseMany[ParseCharacter[LetterCharacter | DigitCharacter | "_"]],
    StringJoin[#1, StringJoin @ #2] &
]

regexNonTermRef = ParseAction[
    (ParseLiteral["<"] ~~ regexRefName ~~ ParseLiteral[">"]) |
        (ParseLiteral["{"] ~~ regexRefName ~~ ParseLiteral["}"]),
    regexLookupRef[#2] &
]

(* Forward reference for the recursive parenthesised group. *)
regexParenGroup = ParseAction[
    ParseLiteral["("] ~~ ParseRecursive[regexBodyRef] ~~ ParseLiteral[")"],
    #2 &
]

regexAtom = ParseChoice[
    regexCharClass,
    regexParenGroup,
    regexNonTermRef,
    regexEscape,
    regexDot,
    regexLiteralChar
]

(* atom followed by optional postfix *, +, ? - returns the wrapped
   ParserCombinator joined back into a string-yielding parser. *)
regexEltWithPostfix = ParseAction[
    regexAtom ~~ ParseOptional[ParseCharacter["*" | "+" | "?"]],
    Switch[#2,
        "*", ParseAction[ParseMany[#1], StringJoin @ {##} &],
        "+", ParseAction[ParseSome[#1], StringJoin @ {##} &],
        "?", ParseAction[ParseOptional[#1], If[MissingQ[#], "", #] &],
        _,   #1
    ] &
]

(* A sequence of elements with no separator; the result is a parser
   that concatenates the per-element matches into one string. The
   empty case is ParseSucceed[""] (matches the empty string). *)
regexSeq = ParseAction[
    ParseMany[regexEltWithPostfix],
    With[{elts = {##}},
        Switch[Length[elts],
            0, ParseSucceed[""],
            1, elts[[1]],
            _, ParseAction[ParseSequence @@ elts, StringJoin @ {##} &]
        ]
    ] &
]

regexBody = ParseAction[
    ParseSepBy1[regexSeq, ParseLiteral["|"]],
    With[{alts = {##}},
        If[Length[alts] === 1, alts[[1]], ParseChoice @@ alts]
    ] &
]

regexBodyRef := ParseRecursive[regexBody]

(* compile a `::-` / `:::` rule body to a target parser by running the
   regex meta-grammar on the reconstructed body string. The Parse call
   has to run inside the Block (not in its init list), because Block's
   init RHSs evaluate in the OUTER scope - regexSymMap / regexOverrides
   would still hold their outer values when Parse was running. *)
regexCompile[body_String, sm_Association, ov_Association] :=
    Block[{regexSymMap = sm, regexOverrides = ov},
        With[{r = Parse[regexBody, body]},
            If[ MatchQ[r, _ParseError],
                ParseFail["regex body did not compile: " <> body],
                r
            ]
        ]
    ]


(* ===== Public entry points ===== *)

(* Parse the BNF source via the combinator grammar above and return the
   raw rule list. Useful for tests and inspection. *)
EBNFRules[source_String] := Parse[grammarP, source]
EBNFRules[File[path_String]] := EBNFRules[Import[path, "Text"]]

Options[EBNFParse] = {
    "PrimitiveOverrides" -> <||>,
    "Actions" -> <||>,
    "ChoiceMode" -> "Auto"
}

EBNFParse[source_String, OptionsPattern[]] :=
    Block[{rules, structuredGram, tokenGram, overrides, actions, allNames, symMap, parsers,
            $choiceMode = OptionValue["ChoiceMode"]},
        overrides = OptionValue["PrimitiveOverrides"];
        actions   = OptionValue["Actions"];
        rules = EBNFRules[source];
        If[ MatchQ[rules, _ParseError],
            Return[rules]
        ];
        (* `::=` and `:==` rules carry the structured body; `::-` and
           `:::` rules carry regex-style bodies that the regexCompile
           pass walks character by character.

           When the same name has BOTH a `::=` and a `:==` definition
           (e.g. <fof_plain_atomic_formula>, <formula_role>), prefer
           `::=` - per the TPTP README, `::=` is the syntactic form
           and `:==` adds semantic constraints over the same shape.
           For parsing, the syntactic form is the right tree. *)
        structuredGram = Join[
            Association @ Cases[rules,
                EBNFRule[name_, ":==", body_] :> (name -> body)],
            Association @ Cases[rules,
                EBNFRule[name_, "::=", body_] :> (name -> body)]
        ];
        tokenGram = Association @ Cases[rules,
            EBNFRule[name_, "::-" | ":::", body_] :> (name -> reconstructBody[body])
        ];
        (* Apply direct-left-recursion elimination before lowering, so the
           PEG ordering of the lowered ParseChoice doesn't commit to a
           non-recursive alt and miss the recursive form. *)
        structuredGram = AssociationMap[
            Function[name, rewriteLeftRecursive[name, structuredGram[name]]],
            Keys[structuredGram]
        ];
        (* Then sort each rule's alts longest-first so a shared-prefix
           alt pair like `<constant> | <functor>(<fof_arguments>)` tries
           the longer (and more specific) form before the bare prefix. *)
        structuredGram = sortAltsLongestFirst /@ structuredGram;
        allNames = Union[Keys[structuredGram], Keys[tokenGram]];
        symMap = AssociationMap[Function[Unique["ebnfRule$"]], allNames];
        parsers = Association[
            Join[
                KeyValueMap[
                    Function[{name, body},
                        name -> applyAction[lowerBody[body, symMap, overrides], actions, name]
                    ],
                    structuredGram
                ],
                KeyValueMap[
                    Function[{name, bodyStr},
                        name -> applyAction[
                            Quiet @ Check[
                                regexCompile[bodyStr, symMap, overrides],
                                ParseFail["Could not compile " <> name <> " body: " <> bodyStr]
                            ],
                            actions, name
                        ]
                    ],
                    tokenGram
                ]
            ]
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

(* Wrap a per-rule parser with the user's action function when one is
   provided. The action receives the rule's parsed value via the
   normal ParseAction convention - splatted args when the parser
   yielded a List, a single arg when it yielded a scalar - and returns
   whatever WL shape the user wants. Without an action, the parser
   passes through unchanged. *)
applyAction[parser_, actions_Association, name_String] :=
    If[ KeyExistsQ[actions, name],
        ParseAction[parser, actions[name]],
        parser
    ]

EBNFParse[File[path_String], opts : OptionsPattern[]] :=
    EBNFParse[Import[path, "Text"], opts]


End[]
EndPackage[]

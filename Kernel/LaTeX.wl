(* :Title: LaTeX/Math.wl - a LaTeX math parser built on Wolfram`Parser` *)
(* :Context: Wolfram`Parser`LaTeX` *)
(* :Summary:
    A first cut of a LaTeX math-mode parser. Two purposes:

    (a) Exercise the Wolfram`Parser` combinator core on a real grammar.
        LaTeX math has the gnarly things that StringExpression can't
        reach: nested braces, optional command arguments, font-style
        commands, big operators with sub/superscripts.

    (b) Give MarkdownToNotebook a path off ImportString[s, "TeX"] -
        which drops styling and fails on common forms. The output is a
        box expression suitable to wrap in a Cell[BoxData[...],
        "InlineFormula"].

    Scope of v0.2.5:
      - identifiers, numbers, single-character symbols
      - +, -, *, / (math precedence)
      - super/sub-script (^ and _) with brace groups
      - braces {...} as recursive subgroups
      - font-style commands \mathbb, \mathcal, \mathfrak, \mathbf
      - \frac, \sqrt, \sum, \int, \prod
      - common Greek letter macros

    Out of scope: environments (matrix, align, cases), custom macros,
    text-mode embedding. The grammar's modular - adding these is a
    matter of adding productions.
*)

BeginPackage["Wolfram`Parser`LaTeX`", {"Wolfram`Parser`"}]

LaTeXMathParse::usage = "LaTeXMathParse[texSource] parses LaTeX math notation and returns a box expression. Returns a ParseError on failure."

LaTeXMathParser::usage = "LaTeXMathParser is the underlying ParserCombinator. Use it via Parse[LaTeXMathParser, source] when you want the same parser applied to many inputs."


Begin["`Private`"]


(* === lexical ===
   Math mode treats whitespace as non-significant, so we strip it
   after each token. *)

ws = ParseMany[ParseCharacter[WhitespaceCharacter]]

token[p_] := ParseAction[p ~~ ws, #1 &]

literal[s_String] := token[ParseLiteral[s]]


(* === character classes used by identifiers / numbers === *)

letter = ParseCharacter[LetterCharacter]
digit = ParseCharacter[DigitCharacter]


(* === numbers === *)

intLit = ParseAction[ParseSome[digit], StringJoin]

decLit = ParseAction[
    intLit ~~ ParseLiteral["."] ~~ intLit,
    StringJoin[##] &
]

(* Numbers stay as bare strings - no MakeBoxes wrap, which would add
   a precision tick on decimals. The box renderer treats numeric
   strings inline as numbers. *)
numberAtom = ParseAction[token[decLit | intLit], #1 &]


(* === bare identifier (single letter, italic by math convention) === *)

identAtom = ParseAction[
    token[letter],
    StyleBox[#, "TI"] &
]


(* === command (\name, optional [bracketed] arg, any number of {braced} args) === *)

commandName = ParseAction[
    ParseLiteral["\\"] ~~ ParseSome[letter],
    Function[{slash, name}, StringJoin[slash, Apply[StringJoin, {name}]]]
]

(* recursive ties - need to look up the production at parse time *)
bracedArgRef = ParseRecursive[bracedArg]
bracketedArgRef = ParseRecursive[bracketedArg]
exprRef = ParseRecursive[expr]

(* Argument forms: optional [arg], then any number of {arg}s. Drop the
   trailing whitespace's value with #1, #2, #3 (skipping the 4th). *)
commandAtom = ParseAction[
    commandName ~~ Optional[bracketedArgRef] ~~ ParseMany[bracedArgRef] ~~ ws,
    dispatchCommand[#1, #2, #3] &
]

bracedArg = ParseBetween[literal["{"], exprRef, literal["}"]]
bracketedArg = ParseBetween[literal["["], exprRef, literal["]"]]


(* === command dispatch table ===
   Each handler takes (optArg, reqArgs_List) and returns a box.
   Add a handler to extend the parser. *)

dispatchCommand[name_String, opt_, req_List] :=
    Block[{handler = commandHandlers[name]},
        If[ MissingQ[handler],
            (* unknown command - emit the name verbatim followed by its args *)
            RowBox[Prepend[req, name]],
            handler[opt, req]
        ]
    ]

commandHandlers[_String] := Missing["NotFound"]


(* === named characters for \mathbb / \mathcal / \mathfrak ===
   Each is constructed at load time via ToExpression, which parses the
   literal "\[DoubleStruckCapitalR]" form into a single named character.
   Doing this in source directly with string concatenation runs afoul
   of the WL tokenizer (which sees "\[DoubleStruckCapital" as a
   partial-and-unterminated named-character escape). *)

namedChar[prefix_String, letter_String] :=
    ToExpression["\"\\[" <> prefix <> letter <> "]\""]

doubleStruckChars = Association @ Map[
    Function[c, c -> namedChar["DoubleStruckCapital", c]],
    CharacterRange["A", "Z"]
]

scriptCapitalChars = Association @ Map[
    Function[c, c -> namedChar["ScriptCapital", c]],
    CharacterRange["A", "Z"]
]

gothicCapitalChars = Association @ Map[
    Function[c, c -> namedChar["GothicCapital", c]],
    CharacterRange["A", "Z"]
]

(* font-style handler: if arg is a single ASCII upper-case letter and we
   have a named-character for it, emit the named character; otherwise
   wrap in a StyleBox.

   Single-letter args reach us wrapped as StyleBox[letter, "TI"] (the
   default math-italic dressing applied by identAtom), so unwrap that
   before the lookup. *)

styleHandler[lookup_, fontOpt_] :=
    Function[{opt, req},
        Block[{
            arg = If[Length[req] >= 1, First[req], ""],
            letter
        },
            letter = Replace[arg, StyleBox[s_String, "TI"] :> s];
            If[ MatchQ[letter, _String] && StringLength[letter] === 1 && KeyExistsQ[lookup, letter],
                lookup[letter],
                StyleBox[arg, fontOpt]
            ]
        ]
    ]

commandHandlers["\\mathbb"]   = styleHandler[doubleStruckChars, FontWeight -> "Bold"]
commandHandlers["\\mathcal"]  = styleHandler[scriptCapitalChars, FontVariations -> {}]
commandHandlers["\\mathfrak"] = styleHandler[gothicCapitalChars, FontVariations -> {}]
commandHandlers["\\mathbf"]   = Function[{opt, req}, StyleBox[First[req, ""], FontWeight -> "Bold"]]
commandHandlers["\\boldsymbol"] = commandHandlers["\\mathbf"]
commandHandlers["\\mathrm"]   = Function[{opt, req}, StyleBox[First[req, ""], FontSlant -> "Plain"]]


(* === fractions, roots === *)

commandHandlers["\\frac"] = Function[{opt, req},
    If[ Length[req] >= 2, FractionBox[req[[1]], req[[2]]], "\\frac" ]
]

commandHandlers["\\sqrt"] = Function[{opt, req},
    If[ Length[req] === 1,
        If[ MissingQ[opt], SqrtBox[req[[1]]], RadicalBox[req[[1]], opt] ],
        "\\sqrt"
    ]
]


(* === big operators and named symbols === *)

(* Bare-symbol commands: each emits a single Unicode character. *)
namedSymbolChars = <|
    "\\sum"     -> "\[Sum]",          "\\int"   -> "\[Integral]",
    "\\prod"    -> "\[Product]",      "\\oint"  -> "\[ContourIntegral]",
    "\\infty"   -> "\[Infinity]",     "\\pi"    -> "\[Pi]",
    "\\cdot"    -> "\[CenterDot]",    "\\times" -> "\[Times]",
    "\\pm"      -> "\[PlusMinus]",    "\\mp"    -> "\[MinusPlus]",
    "\\cup"     -> "\[Union]",        "\\cap"   -> "\[Intersection]",
    "\\subset"  -> "\[Subset]",       "\\supset" -> "\[Superset]",
    "\\subseteq" -> "\[SubsetEqual]", "\\supseteq" -> "\[SupersetEqual]",
    "\\in"      -> "\[Element]",      "\\notin" -> "\[NotElement]",
    "\\to"      -> "\[Rule]",         "\\rightarrow" -> "\[RightArrow]",
    "\\leftarrow" -> "\[LeftArrow]",  "\\Rightarrow" -> "\[DoubleRightArrow]",
    "\\mapsto"  -> "\[Function]",
    "\\leq"     -> "\[LessEqual]",    "\\le"    -> "\[LessEqual]",
    "\\geq"     -> "\[GreaterEqual]", "\\ge"    -> "\[GreaterEqual]",
    "\\neq"     -> "\[NotEqual]",     "\\equiv" -> "\[Congruent]",
    "\\approx"  -> "\[TildeTilde]",   "\\sim"   -> "\[Tilde]",
    "\\forall"  -> "\[ForAll]",       "\\exists" -> "\[Exists]",
    "\\land"    -> "\[And]",          "\\lor"   -> "\[Or]",
    "\\neg"     -> "\[Not]",
    "\\partial" -> "\[PartialD]",     "\\nabla" -> "\[Del]",
    "\\emptyset" -> "\[EmptySet]"
|>

Scan[
    Function[name,
        commandHandlers[name] = Function[{opt, req}, namedSymbolChars[name]]
    ],
    Keys[namedSymbolChars]
]


(* === Greek letter macros ===
   The escapes below resolve at *load* time to single named characters
   (\[Alpha] etc.), since they're typed directly into the source. *)

greekChars = <|
    "\\alpha" -> "\[Alpha]",   "\\beta"  -> "\[Beta]",
    "\\gamma" -> "\[Gamma]",   "\\delta" -> "\[Delta]",
    "\\epsilon" -> "\[CurlyEpsilon]",
    "\\zeta" -> "\[Zeta]",     "\\eta"   -> "\[Eta]",
    "\\theta" -> "\[Theta]",   "\\iota"  -> "\[Iota]",
    "\\kappa" -> "\[Kappa]",   "\\lambda" -> "\[Lambda]",
    "\\mu" -> "\[Mu]",         "\\nu"    -> "\[Nu]",
    "\\xi" -> "\[Xi]",         "\\rho"   -> "\[Rho]",
    "\\sigma" -> "\[Sigma]",   "\\tau"   -> "\[Tau]",
    "\\phi" -> "\[Phi]",       "\\chi"   -> "\[Chi]",
    "\\psi" -> "\[Psi]",       "\\omega" -> "\[Omega]",
    "\\Gamma" -> "\[CapitalGamma]",   "\\Delta" -> "\[CapitalDelta]",
    "\\Theta" -> "\[CapitalTheta]",   "\\Lambda" -> "\[CapitalLambda]",
    "\\Xi" -> "\[CapitalXi]",         "\\Sigma" -> "\[CapitalSigma]",
    "\\Phi" -> "\[CapitalPhi]",       "\\Psi"   -> "\[CapitalPsi]",
    "\\Omega" -> "\[CapitalOmega]"
|>

Scan[
    Function[name,
        commandHandlers[name] = Function[{opt, req}, greekChars[name]]
    ],
    Keys[greekChars]
]


(* === precedence stratification: atom < factor < term < expr === *)

(* parenthesised subexpression: emits the parens as part of the box so
   they render visually, unlike `{...}` which is structural-only. *)
parenAtom = ParseAction[
    literal["("] ~~ ParseRecursive[expr] ~~ literal[")"],
    RowBox[{"(", #2, ")"}] &
]

atom = ParseChoice[numberAtom, commandAtom, parenAtom, bracedArgRef, identAtom]

(* Unary minus is intentionally NOT in atom / factor - it would
   greedily absorb `x + 1`'s binary `+` as a juxtaposed `+ 1` factor.
   Instead it's hoisted to expr (next section) where it can only
   appear at the start of a subexpression (top-level or inside a
   brace). *)

subscript = ParseAction[literal["_"] ~~ (bracedArgRef | atom), #2 &]
superscript = ParseAction[literal["^"] ~~ (bracedArgRef | atom), #2 &]

factor = ParseAction[
    atom ~~ Optional[subscript] ~~ Optional[superscript],
    Function[{base, sub, sup},
        Which[
            ! MissingQ[sub] && ! MissingQ[sup], SubsuperscriptBox[base, sub, sup],
            ! MissingQ[sub],                    SubscriptBox[base, sub],
            ! MissingQ[sup],                    SuperscriptBox[base, sup],
            True,                                base
        ]
    ]
]

(* term is a juxtaposition of factors - the way LaTeX writes implicit
   multiplication (`2x`, `\sum x_i`, `\sin x`, `\frac{a}{b}c`) - emitted
   as a RowBox with no inter-element operator. Explicit `\cdot` /
   `\times` produce a visible product symbol; explicit `/` produces a
   FractionBox of the two adjacent factors. *)

mulSep = ParseAction[
    literal["\\cdot"] | literal["\\times"],
    Function[op, "\[Times]"]
]

term = ParseAction[
    ParseSome[factor],
    If[Length[{##}] === 1, #1, RowBox[{##}]] &
]

addOp = ParseAction[
    literal["+"] | literal["-"],
    Function[op, Function[{a, b}, RowBox[{a, op, b}]]]
]

sumExpr = ParseChainLeft[term, addOp]

(* relation: zero-or-one =, !=, <, >, <=, >= chains, lowest precedence. *)
relOp = ParseAction[
    literal["="] | literal["\\neq"] | literal["<"] | literal[">"] |
        literal["\\leq"] | literal["\\geq"] | literal["\\le"] | literal["\\ge"],
    Function[op, Function[{a, b},
        RowBox[{a, Switch[op,
            "\\neq", "\[NotEqual]",
            "\\leq" | "\\le", "\[LessEqual]",
            "\\geq" | "\\ge", "\[GreaterEqual]",
            _, op
        ], b}]
    ]]
]

relExpr = ParseChainLeft[sumExpr, relOp]

(* expr: allow an optional leading unary minus at the very start of a
   subexpression. Recursive calls (parens, braces) re-enter expr and
   so admit the same form. *)
expr = ParseAction[
    Optional[literal["-"]] ~~ relExpr,
    Function[{sign, body}, If[MissingQ[sign], body, RowBox[{"-", body}]]]
]


(* === top-level entry === *)

LaTeXMathParser := ParseAction[ws ~~ expr, #2 &]

LaTeXMathParse[source_String] := Parse[LaTeXMathParser, source]


End[]

EndPackage[]

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

(* Fallback atom for non-ASCII characters that aren't LetterCharacter
   but DO carry math meaning (Unicode math symbols like \[PartialD],
   \[Del], \[Infinity], \[Pi]; also accented letters that StringMatchQ
   doesn't class as LetterCharacter). Defined via a function predicate
   because StringExpression's Except doesn't accept Alternatives in
   that role. *)
unicodeReservedQ = MemberQ[{
    " ", "\t", "\n", "\r",
    "\\", "{", "}", "[", "]", "(", ")",
    "|", "&", "$", "^", "_", "~",
    ",", ";", ":", "+", "-", "=",
    "<", ">", "*", "/", "?", "!", "#", ".",
    "`", "'", "\""
}, #] &

unicodeAtom = ParseAction[
    token[ParseCharacter[_?(! unicodeReservedQ[#] &)]],
    StyleBox[#, "TI"] &
]


(* === command (\name, optional [bracketed] arg, any number of {braced} args) ===
   A command name is a backslash followed by either one-or-more letters
   (\frac, \mathbb, \alpha, ...) OR a single non-letter character
   (\{, \}, \,, \;, \$, \%, \&, \#, \_, the escaped punctuation /
   spacing commands). *)

commandName = ParseChoice[
    ParseAction[
        ParseLiteral["\\"] ~~ ParseSome[letter],
        Function[{slash, name}, StringJoin[slash, Apply[StringJoin, {name}]]]
    ],
    ParseAction[
        ParseLiteral["\\"] ~~ ParseCharacter[
            "{" | "}" | "$" | "%" | "&" | "#" | "_" | "," | ";" | ":" | " " | "!" |
                "'" | "." | "`" | "\"" | "="
        ],
        Function[{slash, c}, slash <> c]
    ]
]

(* recursive ties - need to look up the production at parse time *)
bracedArgRef = ParseRecursive[bracedArg]
bracketedArgRef = ParseRecursive[bracketedArg]
exprRef = ParseRecursive[expr]

(* Argument forms: optional [arg], then any number of {arg}s. Drop the
   trailing whitespace's value with #1, #2, #3 (skipping the 4th). *)
(* commandAtom must not swallow \begin / \end - those are environment
   delimiters handled by environmentAtom. The leading NotFollowedBy
   guard returns Null (consumes nothing), so the dispatch args shift to
   #2 / #3 / #4. *)
(* commandAtom must not swallow the env-delimiter forms \begin{...},
   \end{...}, or \cr (row break). But user macros like \endExp or
   \crfoo are fine - the env-delimiter guard is keyed on the *exact*
   shapes "\begin" / "\end" followed (possibly past whitespace) by
   "{", and "\cr" followed by a non-letter. *)
commandAtom = ParseAction[
    ParseNotFollowedBy[
        ParseAction[ParseLiteral["\\begin"] ~~ ws ~~ ParseLiteral["{"], Null &] |
        ParseAction[ParseLiteral["\\end"] ~~ ws ~~ ParseLiteral["{"], Null &] |
        ParseAction[ParseLiteral["\\cr"] ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &]
    ] ~~
        commandName ~~ Optional[bracketedArgRef] ~~ ParseMany[bracedArgRef] ~~ ws,
    dispatchCommand[#2, #3, #4] &
]

(* A braced arg is normally an expression, but \pmb{=}, \stackrel{?}{=},
   \overset?, etc. put a bare operator inside the braces. Allow that as
   a second alternative - just emit the operator glyph. *)
(* A braced group is anything between { and }, modeled here as a
   topRow (which already chains expressions, accepts leading ops, bare
   ? / ! / *, line breaks, $ toggles), plus a final empty-group escape
   hatch for the literal {}. *)
bracedArg = ParseBetween[
    literal["{"],
    ParseChoice[ParseRecursive[topRow], ParseSucceed[""]],
    literal["}"]
]
bracketedArg = ParseBetween[literal["["], ParseRecursive[topRow], literal["]"]]


(* === environments: \begin{name} cells \end{name} ===
   Rows are separated by \\, columns by &; each cell is a mathRow.
   Renders as a GridBox wrapped in the delimiters the environment name
   implies (pmatrix -> (), bmatrix -> [], vmatrix -> | |, cases -> {,
   plain matrix / align / aligned / array -> bare grid). The optional
   {colspec} after \begin{array}{cc} is consumed and ignored. *)

envName = ParseAction[
    literal["{"] ~~ ParseSome[ParseCharacter[LetterCharacter | "*"]] ~~ literal["}"],
    StringJoin[#2] &
]

(* Row separators: \\, \\[1ex] (optional length spec), or \cr.
   The bracketed length is consumed and ignored. *)
rowSep = ParseAction[
    (literal["\\\\"] | literal["\\cr"]) ~~ Optional[bracketedArgRef] ~~ ws,
    Null &
]
colSep = ParseAction[literal["&"], Null &]

(* Inside an environment, a cell may start with a relation or sign -
   align / cases / CD all do this ("a &= 1", "& =b+c-d", "&\text{if }").
   cellLeadingOp parses one such bare operator as a standalone token so
   the rest of the cell can then be a normal mathRow. *)
cellLeadingOp = ParseAction[
    literal["="] | literal["+"] | literal["-"] |
        literal["<"] | literal[">"] |
        literal["\\neq"] | literal["\\equiv"] |
        literal["\\leq"] | literal["\\geq"] | literal["\\le"] | literal["\\ge"] |
        literal["\\to"] | literal["\\mapsto"] |
        literal["\\sim"] | literal["\\approx"] |
        literal["\\in"] | literal["\\notin"] | literal["\\mid"] |
        literal["\\subset"] | literal["\\subseteq"] |
        literal["\\supset"] | literal["\\supseteq"],
    Switch[#1,
        "\\neq", "\[NotEqual]", "\\equiv", "\[Congruent]",
        "\\leq" | "\\le", "\[LessEqual]", "\\geq" | "\\ge", "\[GreaterEqual]",
        "\\to", "\[Rule]", "\\mapsto", "\[Function]",
        "\\sim", "\[Tilde]", "\\approx", "\[TildeTilde]",
        "\\in", "\[Element]", "\\notin", "\[NotElement]", "\\mid", "\[VerticalSeparator]",
        "\\subset", "\[Subset]", "\\subseteq", "\[SubsetEqual]",
        "\\supset", "\[Superset]", "\\supseteq", "\[SupersetEqual]",
        _, #1] &
]

(* Single-char tokens that can appear bare in a math row, in any
   context: as the only thing in a braced group (\stackrel{?}{=},
   \textcolor{#0f0}), the lone trailing/leading operator in a matrix
   cell (`1+`, `^3`), or sprinkled through expressions (~ for TeX
   no-break space, . at end of sentences, / inside file paths).
   These are tried only AFTER expr, so balanced absAtom / parenAtom
   / chained sumExpr still wins on inputs like `|x|`, `(x)`, `a+b` -
   only the unbalanced / leading-op leftovers fall through here.
   Closing delimiters ) and ] are NOT here - they'd break parenAtom /
   bracketAtom by stealing the close from the recursive inner row. *)
puncToken = ParseAction[
    literal["?"] | literal["!"] | literal["*"] | literal["#"] |
        literal["~"] | literal["."] | literal["|"] | literal["/"] |
        literal["+"] | literal["-"] | literal["="] |
        literal["<"] | literal[">"] |
        literal["^"] | literal["_"] |
        literal["`"] | literal["'"] | literal["\""],
    #1 &
]

(* Tokens valid ONLY at the outermost top level - intentionally
   unbalanced closing delimiters from `\left. + a \right)` etc. They
   are kept out of puncToken so they don't leak into parenAtom's inner
   row. *)
outerPuncToken = ParseAction[
    literal[")"] | literal["]"],
    #1 &
]
matrixCell = ParseChoice[
    ParseAction[
        cellLeadingOp ~~ Optional[ParseRecursive[mathRow]],
        If[MissingQ[#2], #1, RowBox[{#1, #2}]] &
    ],
    ParseRecursive[mathRow],
    ParseSucceed[""]
]
matrixRow  = ParseSepBy[matrixCell, colSep]
matrixBody = ParseSepBy[matrixRow, rowSep]

environmentAtom = ParseAction[
    ParseLiteral["\\begin"] ~~ ws ~~ envName ~~ ws ~~ Optional[bracedArgRef] ~~
        matrixBody ~~ ParseLiteral["\\end"] ~~ ws ~~ envName,
    buildEnv[#3, #6] &
]

buildEnv[name_String, rows_List] :=
    Module[{width, padded, grid},
        width = Max[Length /@ rows, 1];
        padded = Map[PadRight[#, width, ""] &, rows];
        grid = GridBox[padded];
        Switch[name,
            "pmatrix" | "pmatrix*", RowBox[{"(", grid, ")"}],
            "bmatrix" | "bmatrix*", RowBox[{"[", grid, "]"}],
            "Bmatrix" | "Bmatrix*", RowBox[{"{", grid, "}"}],
            "vmatrix" | "vmatrix*", RowBox[{"|", grid, "|"}],
            "Vmatrix" | "Vmatrix*", RowBox[{"\[DoubleVerticalBar]", grid, "\[DoubleVerticalBar]"}],
            "cases" | "dcases" | "rcases" | "drcases",
                RowBox[{"{", GridBox[padded, ColumnAlignments -> Left]}],
            (* matrix / matrix* / smallmatrix / array / align(ed)(at) /
               equation / gather(ed) / split / multline / eqnarray / CD
               all render as a bare grid - they exist in TeX only to
               control numbering, alignment, or surrounding whitespace,
               none of which is meaningful for a doc-math renderer. *)
            _, grid
        ]
    ]


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
commandHandlers["\\mathscr"]  = styleHandler[scriptCapitalChars, FontVariations -> {}]
commandHandlers["\\mathfrak"] = styleHandler[gothicCapitalChars, FontVariations -> {}]
commandHandlers["\\mathbf"]   = Function[{opt, req}, StyleBox[First[req, ""], FontWeight -> "Bold"]]
commandHandlers["\\boldsymbol"] = commandHandlers["\\mathbf"]
commandHandlers["\\pmb"]      = commandHandlers["\\mathbf"]
commandHandlers["\\mathrm"]   = Function[{opt, req}, StyleBox[First[req, ""], FontSlant -> "Plain"]]
commandHandlers["\\mathit"]   = Function[{opt, req}, StyleBox[First[req, ""], FontSlant -> "Italic"]]
commandHandlers["\\mathsf"]   = Function[{opt, req}, StyleBox[First[req, ""], FontFamily -> "SansSerif"]]
commandHandlers["\\mathtt"]   = Function[{opt, req}, StyleBox[First[req, ""], FontFamily -> "Courier"]]
commandHandlers["\\operatorname"] = commandHandlers["\\mathrm"]

(* \text{...}: upright text. The arg comes through the math grammar
   (so a multi-letter run is a RowBox of italic letters); re-style the
   whole thing upright. An approximation - good enough for doc math. *)
commandHandlers["\\text"]   = Function[{opt, req}, StyleBox[First[req, ""], FontSlant -> "Plain"]]
commandHandlers["\\textrm"] = commandHandlers["\\text"]
commandHandlers["\\textbf"] = Function[{opt, req}, StyleBox[First[req, ""], FontWeight -> "Bold", FontSlant -> "Plain"]]
commandHandlers["\\textit"] = Function[{opt, req}, StyleBox[First[req, ""], FontSlant -> "Italic"]]
commandHandlers["\\texttt"] = Function[{opt, req}, StyleBox[First[req, ""], FontFamily -> "Courier", FontSlant -> "Plain"]]


(* === accents ===
   Each is a command with one required arg; renders as an OverscriptBox
   with the accent glyph on top. \overline / \underline / the wide
   accents span their whole argument. *)

accentHandler[glyph_] := Function[{opt, req}, OverscriptBox[First[req, ""], glyph]]

commandHandlers["\\hat"]      = accentHandler["^"]
commandHandlers["\\widehat"]  = accentHandler["^"]
commandHandlers["\\tilde"]    = accentHandler["~"]
commandHandlers["\\widetilde"] = accentHandler["~"]
commandHandlers["\\bar"]      = accentHandler["_"]
commandHandlers["\\vec"]      = accentHandler["\[RightVector]"]
commandHandlers["\\dot"]      = accentHandler["."]
commandHandlers["\\ddot"]     = accentHandler[".."]
commandHandlers["\\check"]    = accentHandler["\[Hacek]"]
commandHandlers["\\breve"]    = accentHandler["\[Breve]"]
commandHandlers["\\acute"]    = accentHandler[FromCharacterCode[180]]
commandHandlers["\\grave"]    = accentHandler[FromCharacterCode[96]]
commandHandlers["\\mathring"] = accentHandler["\[SmallCircle]"]
commandHandlers["\\overrightarrow"] = accentHandler["\[RightArrow]"]
commandHandlers["\\overleftarrow"]  = accentHandler["\[LeftArrow]"]
commandHandlers["\\overline"] = accentHandler["_"]

commandHandlers["\\underline"] = Function[{opt, req}, UnderscriptBox[First[req, ""], "_"]]

(* over/under braces - the optional label rides above/below the brace. *)
commandHandlers["\\overbrace"]  = Function[{opt, req}, OverscriptBox[First[req, ""], "\[OverBrace]"]]
commandHandlers["\\underbrace"] = Function[{opt, req}, UnderscriptBox[First[req, ""], "\[UnderBrace]"]]


(* === fractions, roots, binomials === *)

fracHandler = Function[{opt, req},
    If[ Length[req] >= 2, FractionBox[req[[1]], req[[2]]], "\\frac" ]
]

commandHandlers["\\frac"]  = fracHandler
commandHandlers["\\tfrac"] = fracHandler
commandHandlers["\\dfrac"] = fracHandler
commandHandlers["\\cfrac"] = fracHandler

(* \stackrel{top}{rel}: render `top` set above `rel`. *)
commandHandlers["\\stackrel"] = Function[{opt, req},
    If[ Length[req] >= 2, OverscriptBox[req[[2]], req[[1]]], "\\stackrel" ]
]
commandHandlers["\\overset"]  = commandHandlers["\\stackrel"]
commandHandlers["\\underset"] = Function[{opt, req},
    If[ Length[req] >= 2, UnderscriptBox[req[[2]], req[[1]]], "\\underset" ]
]

commandHandlers["\\binom"] = Function[{opt, req},
    If[ Length[req] >= 2,
        RowBox[{"(", GridBox[{{req[[1]]}, {req[[2]]}}], ")"}],
        "\\binom"
    ]
]
commandHandlers["\\tbinom"] = commandHandlers["\\binom"]
commandHandlers["\\dbinom"] = commandHandlers["\\binom"]

commandHandlers["\\sqrt"] = Function[{opt, req},
    If[ Length[req] === 1,
        If[ MissingQ[opt], SqrtBox[req[[1]]], RadicalBox[req[[1]], opt] ],
        "\\sqrt"
    ]
]

(* modular-arithmetic notations - PAdic uses \pmod a lot. *)
commandHandlers["\\pmod"] = Function[{opt, req},
    RowBox[{"(", StyleBox["mod", FontSlant -> "Plain"], " ", First[req, ""], ")"}]
]
commandHandlers["\\bmod"] = Function[{opt, req}, StyleBox["mod", FontSlant -> "Plain"]]
commandHandlers["\\mod"]  = Function[{opt, req},
    RowBox[{StyleBox["mod", FontSlant -> "Plain"], " ", First[req, ""]}]
]


(* === structural no-ops ===
   Commands that exist for TeX's typesetting needs (numbering, line
   breaking, hint to spacing engine) but carry no semantic information
   for a doc-math renderer. We accept them and emit nothing. *)

noopHandler = Function[{opt, req}, ""]

Scan[
    (commandHandlers[#] = noopHandler) &,
    {"\\limits", "\\nolimits", "\\displaylimits",
     "\\nonumber", "\\notag", "\\tag", "\\eqno", "\\leqno",
     "\\hline", "\\hdashline", "\\cline",
     "\\newline", "\\linebreak", "\\nolinebreak",
     "\\nobreak", "\\allowbreak", "\\noindent", "\\indent", "\\displaybreak",
     "\\smallskip", "\\medskip", "\\bigskip", "\\strut", "\\mathstrut",
     "\\phantom", "\\hphantom", "\\vphantom",
     "\\rule", "\\raisebox", "\\colorbox", "\\fcolorbox",
     "\\htmlId", "\\htmlClass", "\\htmlStyle", "\\htmlData",
     "\\includegraphics", "\\def", "\\renewcommand", "\\newcommand", "\\gdef",
     "\\kern", "\\mkern", "\\hskip", "\\mskip", "\\hspace", "\\vspace",
     "\\thinspace", "\\negthinspace", "\\medspace", "\\negmedspace",
     "\\thickspace", "\\negthickspace",
     "\\enspace", "\\quad", (* \quad already in namedSymbolChars - this no-ops if no handler hit *)
     "\\textstyle", "\\displaystyle", "\\scriptstyle", "\\scriptscriptstyle",
     "\\tiny", "\\scriptsize", "\\footnotesize", "\\small", "\\normalsize",
     "\\large", "\\Large", "\\LARGE", "\\huge", "\\Huge",
     "\\it", "\\bf", "\\rm", "\\sf", "\\tt", "\\sl", "\\em"}
]

(* Re-pin entries that the no-op scan above would have stomped: \quad,
   \qquad, \tag-with-arg need their previous semantics. (Scan runs after
   namedSymbolChars setup, so \quad's space-glyph handler was just
   replaced by noopHandler - put it back.) *)
commandHandlers["\\quad"]  = Function[{opt, req}, namedSymbolChars["\\quad"]]
commandHandlers["\\qquad"] = Function[{opt, req}, namedSymbolChars["\\qquad"]]


(* === math-atom classification ===
   \mathop / \mathrel / \mathbin / \mathord / \mathopen / \mathclose /
   \mathpunct only affect spacing classification in TeX. For rendering,
   we just emit the argument unchanged. Same for \smash and \boxed (a
   visual box that we drop). *)

identArgHandler = Function[{opt, req}, First[req, ""]]

Scan[
    (commandHandlers[#] = identArgHandler) &,
    {"\\mathop", "\\mathrel", "\\mathbin", "\\mathord",
     "\\mathopen", "\\mathclose", "\\mathpunct", "\\mathinner",
     "\\smash", "\\boxed", "\\fbox", "\\mbox", "\\hbox",
     "\\underleftarrow", "\\underrightarrow", "\\underleftrightarrow"}
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
    "\\emptyset" -> "\[EmptySet]",
    "\\colon"   -> ":",               "\\mid"   -> "\[VerticalSeparator]",
    "\\cong"    -> "\[TildeFullEqual]", "\\propto" -> "\[Proportional]",
    "\\ll"      -> "\[LessLess]",      "\\gg"    -> "\[GreaterGreater]",
    "\\setminus" -> "\[Backslash]",   "\\circ"  -> "\[SmallCircle]",
    "\\oplus"   -> "\[CirclePlus]",   "\\otimes" -> "\[CircleTimes]",
    "\\langle"  -> "\[LeftAngleBracket]", "\\rangle" -> "\[RightAngleBracket]",
    "\\lfloor"  -> "\[LeftFloor]",    "\\rfloor" -> "\[RightFloor]",
    "\\lceil"   -> "\[LeftCeiling]",  "\\rceil" -> "\[RightCeiling]",
    "\\ldots"   -> "\[Ellipsis]",     "\\dots"  -> "\[Ellipsis]",
    "\\cdots"   -> "\[CenterEllipsis]", "\\vdots" -> "\[VerticalEllipsis]",
    "\\ddots"   -> "\[DescendingEllipsis]",
    "\\aleph"   -> "\[Aleph]",        "\\hbar"  -> "\[HBar]",
    "\\Re"      -> "\[GothicCapitalR]", "\\Im"  -> "\[GothicCapitalI]",
    "\\{"       -> "{",               "\\}"     -> "}",
    "\\$"       -> "$",               "\\%"     -> "%",
    "\\&"       -> "&",               "\\#"     -> "#",
    "\\_"       -> "_",               "\\ "     -> " ",
    "\\quad"    -> "\[NonBreakingSpace]\[NonBreakingSpace]",
    "\\qquad"   -> "\[NonBreakingSpace]\[NonBreakingSpace]\[NonBreakingSpace]\[NonBreakingSpace]",
    (* extra binary operators *)
    "\\div"     -> "\[Divide]",        "\\ast"   -> "\[Star]",
    "\\star"    -> "\[FivePointedStar]", "\\bullet" -> "\[Bullet]",
    "\\ominus"  -> "\[CircleMinus]",   "\\odot"  -> "\[CircleDot]",
    "\\oslash"  -> "\[CircleTimes]",   "\\wedge" -> "\[Wedge]",
    "\\vee"     -> "\[Vee]",           "\\sqcap" -> "\[SquareIntersection]",
    "\\sqcup"   -> "\[SquareUnion]",   "\\uplus" -> "\[UnionPlus]",
    "\\amalg"   -> "\[Coproduct]",     "\\dagger" -> "\[Dagger]",
    "\\ddagger" -> "\[DoubleDagger]",  "\\wr"    -> "\[Wolf]",
    (* big operators *)
    "\\bigcup"  -> "\[Union]",         "\\bigcap" -> "\[Intersection]",
    "\\bigoplus" -> "\[CirclePlus]",   "\\bigotimes" -> "\[CircleTimes]",
    "\\bigsqcup" -> "\[SquareUnion]",  "\\bigvee" -> "\[Vee]",
    "\\bigwedge" -> "\[Wedge]",        "\\coprod" -> "\[Coproduct]",
    (* extra relations *)
    "\\simeq"   -> "\[TildeEqual]",    "\\doteq" -> "\[DotEqual]",
    "\\prec"    -> "\[Precedes]",      "\\succ"  -> "\[Succeeds]",
    "\\preceq"  -> "\[PrecedesEqual]", "\\succeq" -> "\[SucceedsEqual]",
    "\\ni"      -> "\[ReverseElement]", "\\propto" -> "\[Proportional]",
    "\\parallel" -> "\[DoubleVerticalBar]", "\\perp" -> "\[Perpendicular]",
    "\\asymp"   -> "\[CupCap]",
    "\\vdash"   -> "\[RightTee]",      "\\dashv" -> "\[LeftTee]",
    "\\models"  -> "\[DoubleRightTee]", "\\sqsubseteq" -> "\[SquareSubsetEqual]",
    "\\sqsupseteq" -> "\[SquareSupersetEqual]",
    (* arrows *)
    "\\gets"        -> "\[LeftArrow]",
    "\\leftrightarrow" -> "\[LeftRightArrow]",
    "\\Leftarrow"   -> "\[DoubleLeftArrow]",
    "\\Leftrightarrow" -> "\[DoubleLeftRightArrow]",
    "\\uparrow"     -> "\[UpArrow]",   "\\downarrow" -> "\[DownArrow]",
    "\\updownarrow" -> "\[UpDownArrow]",
    "\\Uparrow"     -> "\[DoubleUpArrow]", "\\Downarrow" -> "\[DoubleDownArrow]",
    "\\longrightarrow" -> "\[LongRightArrow]",
    "\\longleftarrow"  -> "\[LongLeftArrow]",
    "\\longleftrightarrow" -> "\[LongLeftRightArrow]",
    "\\Longrightarrow" -> "\[DoubleLongRightArrow]",
    "\\Longleftarrow"  -> "\[DoubleLongLeftArrow]",
    "\\Longleftrightarrow" -> "\[DoubleLongLeftRightArrow]",
    "\\hookrightarrow" -> "\[RightArrow]", "\\hookleftarrow" -> "\[LeftArrow]",
    "\\longmapsto"  -> "\[Function]",  "\\implies" -> "\[DoubleLongRightArrow]",
    "\\impliedby"   -> "\[DoubleLongLeftArrow]", "\\iff" -> "\[DoubleLongLeftRightArrow]",
    "\\rightsquigarrow" -> "\[RightArrow]",
    (* logic / misc symbols *)
    "\\nexists" -> "\[NotExists]",     "\\top" -> "\[UpTee]",
    "\\bot"     -> "\[DownTee]",       "\\therefore" -> "\[Therefore]",
    "\\because" -> "\[Because]",       "\\angle" -> "\[Angle]",
    "\\triangle" -> "\[EmptyUpTriangle]", "\\square" -> "\[EmptySquare]",
    "\\diamond" -> "\[Diamond]",       "\\flat" -> "\[Flat]",
    "\\sharp"   -> "\[Sharp]",         "\\natural" -> "\[Natural]",
    "\\clubsuit" -> "\[ClubSuit]",     "\\spadesuit" -> "\[SpadeSuit]",
    "\\heartsuit" -> "\[HeartSuit]",   "\\diamondsuit" -> "\[DiamondSuit]",
    "\\surd"    -> "\[Sqrt]",          "\\ell" -> "\[ScriptL]",
    "\\Re"      -> "\[GothicCapitalR]", "\\Im" -> "\[GothicCapitalI]",
    "\\wp"      -> "\[WeierstrassP]",   "\\Finv" -> "\[FinalSigma]",
    "\\complement" -> "\[NotElement]", "\\degree" -> "\[Degree]",
    "\\prime"   -> "\[Prime]",         "\\backslash" -> "\[Backslash]",
    "\\lnot"    -> "\[Not]",           "\\lor" -> "\[Or]", "\\land" -> "\[And]",
    "\\gtrsim"  -> "\[GreaterTilde]",  "\\lesssim" -> "\[LessTilde]",
    "\\ne"      -> "\[NotEqual]",      "\\notni" -> "\[NotReverseElement]"
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

(* Named function operators (\sin, \log, \max, ...) render upright. *)
functionNames = {
    "sin", "cos", "tan", "cot", "sec", "csc",
    "sinh", "cosh", "tanh", "arcsin", "arccos", "arctan",
    "log", "ln", "lg", "exp",
    "max", "min", "sup", "inf", "lim", "limsup", "liminf",
    "det", "dim", "ker", "gcd", "lcm", "deg", "arg", "mod", "hom",
    "Pr", "tr", "rank"
}

Scan[
    Function[nm,
        commandHandlers["\\" <> nm] =
            Function[{opt, req}, StyleBox[nm, FontSlant -> "Plain"]]
    ],
    functionNames
]


(* === precedence stratification: atom < factor < term < expr === *)

(* parenthesised subexpression: emits the parens as part of the box so
   they render visually, unlike `{...}` which is structural-only. Inner
   is topRow so `(x \\ y)` and `(a, b $c$ d)` survive - real-world TeX
   does sometimes put a row break or math toggle inside delimited
   groups. The recursive inner ROW must be topRow (not outerRow) so
   the closing ) is still available for our literal[")"] to consume,
   rather than being eaten as outerPuncToken. *)
parenAtom = ParseAction[
    literal["("] ~~ ParseRecursive[topRow] ~~ literal[")"],
    RowBox[{"(", #2, ")"}] &
]

bracketAtom = ParseAction[
    literal["["] ~~ ParseRecursive[topRow] ~~ literal["]"],
    RowBox[{"[", #2, "]"}] &
]

(* absolute-value / norm bars: |expr| renders the bars visibly. The
   inner is the relation-free sumExpr so a stray | terminates it. *)
absAtom = ParseAction[
    literal["|"] ~~ ParseRecursive[sumExpr] ~~ literal["|"],
    RowBox[{"|", #2, "|"}] &
]

atom = ParseChoice[
    numberAtom, environmentAtom, commandAtom, parenAtom, bracketAtom, absAtom,
    bracedArgRef, identAtom, unicodeAtom
]

(* A postfix is _x, ^y, or a run of primes - each tagged so factor can
   accept them in any order and any number (`x_i^2`, `x^2_i`, `f'`,
   `x'^2_3`, `f_2'` all occur in real LaTeX). primes fold into the
   superscript. *)
postfix = ParseChoice[
    ParseAction[literal["_"] ~~ (bracedArgRef | atom), {"sub", #2} &],
    ParseAction[literal["^"] ~~ (bracedArgRef | atom), {"sup", #2} &],
    ParseAction[
        ParseSome[literal["'"]],
        {"sup", StringJoin[ConstantArray["\[Prime]", Length[{##}]]]} &
    ]
]

factor = ParseAction[
    atom ~~ ParseMany[postfix],
    Function[{base, posts},
        Module[{sub, sups},
            sub = FirstCase[posts, {"sub", v_} :> v, Missing[]];
            sups = Cases[posts, {"sup", v_} :> v];
            With[{sup = Which[
                    Length[sups] === 0, Missing[],
                    Length[sups] === 1, First[sups],
                    True, RowBox[sups]
            ]},
                Which[
                    ! MissingQ[sub] && ! MissingQ[sup], SubsuperscriptBox[base, sub, sup],
                    ! MissingQ[sub],                    SubscriptBox[base, sub],
                    ! MissingQ[sup],                    SuperscriptBox[base, sup],
                    True,                                base
                ]
            ]
        ]
    ]
]

(* rowJoin: concatenate two boxes into a single flat RowBox, splicing
   any existing RowBox operands so chains stay flat
   (`RowBox[{a, b, c}]`, not nested pairs). *)
rowParts[RowBox[l_List]] := l
rowParts[x_] := {x}
rowJoin[a_, b_] := RowBox[Join[rowParts[a], rowParts[b]]]
rowJoin[a_, mid_, b_] := RowBox[Join[rowParts[a], {mid}, rowParts[b]]]

(* mulOp joins adjacent factors. PEG-ordered: explicit `/` builds a
   FractionBox, explicit `*` / `\cdot` / `\times` a visible product,
   and (the final fallback) ParseSucceed gives juxtaposition - LaTeX's
   implicit multiplication (`2x`, `\sum x_i`, `\sin x`). *)
mulOp = ParseChoice[
    ParseAction[literal["/"], Function[op, Function[{a, b}, FractionBox[a, b]]]],
    ParseAction[
        literal["*"] | literal["\\cdot"] | literal["\\times"],
        Function[op, Function[{a, b}, rowJoin[a, "\[Times]", b]]]
    ],
    ParseAction[ParseSucceed[Null], Function[op, Function[{a, b}, rowJoin[a, b]]]]
]

factorChain = ParseChainLeft[factor, mulOp]

(* term: an optional leading unary +/- on the factor chain. The sign
   lives here (not at the atom level) so binary +/- between terms is
   consumed by addOp first; the unary form only fires when a term
   starts fresh (top-level, after a relation, after `(`, etc.). *)
term = ParseAction[
    Optional[literal["+"] | literal["-"]] ~~ factorChain,
    Function[{sign, body}, If[MissingQ[sign], body, rowJoin[sign, body]]]
]

addOp = ParseAction[
    literal["+"] | literal["-"],
    Function[op, Function[{a, b}, rowJoin[a, op, b]]]
]

sumExpr = ParseChainLeft[term, addOp]

(* relation: =, !=, <, >, <=, >=, etc., lowest precedence. *)
relOp = ParseAction[
    literal["="] | literal["\\neq"] | literal["\\equiv"] |
        literal["<"] | literal[">"] |
        literal["\\leq"] | literal["\\geq"] | literal["\\le"] | literal["\\ge"] |
        literal["\\subset"] | literal["\\subseteq"] |
        literal["\\supset"] | literal["\\supseteq"] |
        literal["\\in"] | literal["\\notin"] |
        literal["\\to"] | literal["\\mapsto"] | literal["\\sim"] | literal["\\approx"] |
        literal["\\mid"],
    Function[op, Function[{a, b},
        rowJoin[a, Switch[op,
            "\\neq", "\[NotEqual]",
            "\\equiv", "\[Congruent]",
            "\\leq" | "\\le", "\[LessEqual]",
            "\\geq" | "\\ge", "\[GreaterEqual]",
            "\\subset", "\[Subset]",
            "\\subseteq", "\[SubsetEqual]",
            "\\supset", "\[Superset]",
            "\\supseteq", "\[SupersetEqual]",
            "\\in", "\[Element]",
            "\\notin", "\[NotElement]",
            "\\to", "\[Rule]",
            "\\mapsto", "\[Function]",
            "\\sim", "\[Tilde]",
            "\\approx", "\[TildeTilde]",
            "\\mid", "\[VerticalSeparator]",
            _, op
        ], b]
    ]]
]

expr = ParseChainLeft[sumExpr, relOp]

(* mathRow: a top-level sequence of expr's separated by literal
   punctuation (`,` `:` `;`) - the separators that appear in sets,
   tuples, "such that" clauses, and function-argument lists but carry
   no algebraic precedence. Each renders inline (comma / semicolon get
   a trailing thin space for readability). *)
mathToken = ParseChoice[
    expr,
    ParseAction[literal[","], "," <> "\[ThinSpace]" &],
    ParseAction[literal[";"], "; " &],
    ParseAction[literal[":"], " : " &],
    ParseRecursive[puncToken]
]

mathRow = ParseAction[
    ParseSome[mathToken],
    If[Length[{##}] === 1, #1, RowBox[{##}]] &
]

(* topRow: like mathRow, but additionally tolerates the things that
   are valid at the document level but NOT inside a matrix cell:
   - `\\` and `\\[1ex]` and `\cr` (line breaks outside an environment)
   - `$ ... $` (math-mode toggles - a no-op for us since we're already
     parsing math; nests harmlessly inside \tag{$+$x}, \text{$a<b$})
   - `\hline` / `\hdashline` / `\newline` would also live here but they
     already match commandAtom via the noop handlers above. *)
linebreakToken = ParseAction[
    (literal["\\\\"] | literal["\\cr"]) ~~ Optional[bracketedArgRef] ~~ ws,
    "" &
]
dollarToken = ParseAction[literal["$"], "" &]

topToken = ParseChoice[
    mathToken,
    ParseRecursive[cellLeadingOp],
    ParseRecursive[puncToken],
    linebreakToken,
    dollarToken
]

topRow = ParseAction[
    ParseSome[topToken],
    If[Length[{##}] === 1, #1, RowBox[{##}]] &
]

(* outerRow is topRow + outerPuncToken; used ONLY as the LaTeXMathParser
   entry point so that unbalanced ) and ] from \left./\right)-style
   inputs render as bare characters at the document level. outerPuncToken
   is kept OUT of topRow because the recursive inner rows in parenAtom /
   bracketAtom / bracketedArg need to leave the literal close delimiter
   for their own literal["]"] / literal[")"] to consume. *)
outerToken = ParseChoice[topToken, ParseRecursive[outerPuncToken]]

outerRow = ParseAction[
    ParseSome[outerToken],
    If[Length[{##}] === 1, #1, RowBox[{##}]] &
]


(* === top-level entry === *)

LaTeXMathParser := ParseAction[ws ~~ outerRow, #2 &]

(* Delimiter-sizing macros are dropped before parsing - we render the
   bare delimiter and don't model size. Two different strategies for
   the two families:

   \left and \right always have a *matching pair* in the source - if we
   keep the delimiter character, parenAtom / bracketAtom / absAtom pick
   it up naturally. So we strip JUST the macro prefix, leaving the
   delimiter (e.g. \left( -> ().

   \big / \bigl / \bigr / \Big / \bigg / \Bigg and friends are NOT
   guaranteed to come in matched pairs (e.g. \big( without a \big) in
   the same group breaks any balanced-paren parser). Strip the macro
   AND the delimiter together (the next char or \macro). This loses the
   visual but keeps the input parseable. The negative lookahead
   (?![a-zA-Z]) keeps `\bigcup` etc. from being mangled. *)
preprocessLaTeX[s_String] :=
    StringReplace[s, {
        RegularExpression["\\\\(left|right)\\s*\\."] -> "",
        RegularExpression["\\\\(left|right)(?![a-zA-Z])"] -> "",
        RegularExpression[
            "\\\\(bigl|bigr|biggl|biggr|Bigl|Bigr|Biggl|Biggr|bigm|Bigm|biggm|Biggm|big|Big|bigg|Bigg)\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|.])"
        ] -> "",
        RegularExpression[
            "\\\\(bigl|bigr|biggl|biggr|Bigl|Bigr|Biggl|Biggr|bigm|Bigm|biggm|Biggm|big|Big|bigg|Bigg)(?![a-zA-Z])"
        ] -> ""
    }]

LaTeXMathParse[source_String] := Parse[LaTeXMathParser, preprocessLaTeX[source]]


End[]

EndPackage[]

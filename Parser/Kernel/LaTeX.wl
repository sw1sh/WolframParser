(* :Title: LaTeX/Math.wl - a LaTeX math parser built on Wolfram`Parser` *)
(* :Context: Wolfram`Parser` *)
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

BeginPackage["Wolfram`Parser`"]

LaTeXMathParse::usage = "LaTeXMathParse[texSource] parses LaTeX math notation and returns a box expression. Returns a Failure[\"ParseError\", ...] on failure."

LaTeXMathParser::usage = "LaTeXMathParser is the underlying ParserCombinator. Use it via Parse[LaTeXMathParser, source] when you want the same parser applied to many inputs."

LaTeXMathStyle::usage = "LaTeXMathStyle[boxes] restyles LaTeXMathParse output into a Computer-Modern look, matching LaTeX/MaTeX: italic letters become their math-italic (cmmi) codepoints in an installed Latin Modern Math font and \\mathbb letters render in the MSBM10 blackboard font, with everything wrapped in the chosen family. With no font it auto-detects the best installed CM font (Latin Modern Math > Latin Modern Roman > CMU Serif) and returns the boxes unchanged if none is found. LaTeXMathStyle[boxes, font] forces a specific family."


Begin["`LaTeXPrivate`"]


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
    token[ParseCharacter[_ ? (! unicodeReservedQ[#] &)]],
    StyleBox[#, "TI"] &
]

(* unicodeAtom italicises EVERY non-reserved char as a math variable, but only
   plain Latin/Greek letters should be italic.  A pasted SYMBOL (∂ ⇒ ∞ ×) or a
   PRE-STYLED letter (blackboard ℝ, math-alphanumeric 𝐀, fraktur 𝔊) must render
   upright to match its \macro form (\partial, \mathbb{R}, ...) - else typing
   \partial and pasting ∂ disagree.  uprightUnicodeSymbols (a post-parse pass in
   LaTeXMathParse, NOT in the grammar, so it leaves Hash[LaTeXMathParser] and
   the compiled asset untouched) unwraps those back to bare glyphs.  No effect
   on the ASCII path: there every StyleBox[_,"TI"] holds a plain letter.
   Pre-styled = the two Unicode blocks that already encode their own style. *)
preStyledLetterQ[c_String] := With[{cc = First @ ToCharacterCode[c]},
    (16^^1D400 <= cc <= 16^^1D7FF) || (16^^2100 <= cc <= 16^^214F)]
bareUnicodeAtomQ[c_String] := StringLength[c] == 1 && (! LetterQ[c] || preStyledLetterQ[c])
uprightUnicodeSymbols[boxes_] := boxes /. StyleBox[s_String, "TI"] /; bareUnicodeAtomQ[s] :> s


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
                "'" | "." | "`" | "\"" | "=" | "|"
        ],
        Function[{slash, c}, slash <> c]
    ]
]

(* recursive ties - need to look up the production at parse time *)
bracedArgRef = ParseRecursive[bracedArg]
bracketedArgRef = ParseRecursive[bracketedArg]
exprRef = ParseRecursive[expr]
(* postfix is defined far below (it needs atom); tie it lazily so the
   bare-token productions here can carry scripts (issue #26). *)
postfixRef = ParseRecursive[postfix]

(* Argument forms: optional [arg], then any number of {arg}s. Drop the
   trailing whitespace's value with #1, #2, #3 (skipping the 4th). *)
(* commandAtom must not swallow \begin / \end - those are environment
   delimiters handled by environmentAtom. The leading NotFollowedBy
   guard returns Null (consumes nothing), so the dispatch args shift to
   #2 / #3 / #4. *)
(* commandAtom must not swallow the env-delimiter forms \begin{...},
   \end{...}, the \cr row break, or the \right that closes a
   leftRightAtom. The guard is keyed on the *exact* shapes so user
   macros like \endExp, \crfoo, or \rightarrow are unaffected:
   - \begin / \end: only blocked when followed (past ws) by {
   - \cr / \right: only blocked when followed by a non-letter *)
(* `wsBeforeArg` lets `\sqrt {a b}` (or `\frac { a } { b }`) parse: TeX
   accepts whitespace between a command and its `[...]` / `{...}` args,
   so a strict no-whitespace rule misses real-world inputs. We allow
   intervening whitespace between command name and each arg slot, then
   re-add a final ws consumer at the end. *)
wsBeforeArg = ParseAction[ws ~~ bracedArgRef, #2 &]
wsBeforeOpt = ParseAction[ws ~~ bracketedArgRef, #2 &]

(* The closing bracket commands \rangle / \rceil / \rfloor / \rvert /
   \rVert are guarded out of commandAtom (like \right and \cr) so a
   matchfix bracket atom's inner row stops at them instead of swallowing
   them as standalone glyphs.  Unmatched closers are picked up by
   outerPuncToken (mapped to their glyph), and the \left...\right path
   matches them via literal[] (not commandAtom), so this guard doesn't
   break \left\rangle. *)
commandAtom = ParseAction[
    ParseNotFollowedBy[
        ParseAction[ParseLiteral["\\begin"] ~~ ws ~~ ParseLiteral["{"], Null &] |
        ParseAction[ParseLiteral["\\end"] ~~ ws ~~ ParseLiteral["{"], Null &] |
        ParseAction[ParseLiteral["\\cr"]     ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &] |
        ParseAction[ParseLiteral["\\right"]  ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &] |
        ParseAction[ParseLiteral["\\rangle"] ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &] |
        ParseAction[ParseLiteral["\\rceil"]  ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &] |
        ParseAction[ParseLiteral["\\rfloor"] ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &] |
        ParseAction[ParseLiteral["\\rVert"]  ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &] |
        ParseAction[ParseLiteral["\\rvert"]  ~~ ParseNotFollowedBy[ParseCharacter[LetterCharacter]], Null &]
    ] ~~
        commandName ~~ Optional[wsBeforeOpt] ~~ ParseMany[wsBeforeArg] ~~ ws,
    dispatchCommand[#2, #3, #4] &
]

(* A braced arg is normally an expression, but \pmb{=}, \stackrel{?}{=},
   \overset?, etc. put a bare operator inside the braces. Allow that as
   a second alternative - just emit the operator glyph. *)
(* A braced group is anything between { and }, modeled here as a
   topRow (which already chains expressions, accepts leading ops, bare
   ? / ! / *, line breaks, $ toggles), plus a final empty-group escape
   hatch for the literal {}. *)
(* A braced arg's inner content uses outerRow (NOT topRow) so bare
   single delimiters like `[`, `]`, `(`, `)` survive - `\genfrac{[}{]}...`
   in particular has braces wrapping a single bare bracket char, which
   topRow's strict bracketAtom rejects.  outerRow includes
   outerPuncToken which accepts those bare closers. *)
bracedArg = ParseBetween[
    literal["{"],
    ParseChoice[ParseRecursive[outerRow], ParseSucceed[""]],
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
(* `~` in TeX = non-breaking space.  KaTeX renders it as a visible
   space; we emit `\[NonBreakingSpace]` so the FE shows whitespace
   instead of a tilde glyph. *)
tildeToken = ParseAction[literal["~"], "\[NonBreakingSpace]" &]

(* `|` (a bare bar - bra-ket separator, "divides", set-builder, conditional)
   is pinned to fixed size (fixedFence, defined below) so it doesn't stretch to
   a tall sibling; LaTeX keeps an un-\left'd bar fixed.
   A bare punctuation token can itself carry scripts: TeX attaches ^ / _ to
   whatever single token precedes them, delimiter or not, so `\langle 1|^{2}`
   superscripts the closing bar (issue #26).  attachScripts with no trailing
   scripts reduces to the bare glyph, so existing behaviour is unchanged. *)
puncToken = ParseAction[
    ParseChoice[
        ParseAction[literal["|"], fixedFence["|"] &],
        ParseAction[
            literal["?"] | literal["!"] | literal["*"] | literal["#"] |
                literal["."] | literal["/"] |
                literal["+"] | literal["-"] | literal["="] |
                literal["<"] | literal[">"] |
                literal["^"] | literal["_"] |
                literal["`"] | literal["'"] | literal["\""],
            #1 &
        ]
    ] ~~ ParseMany[postfixRef],
    attachScripts[#1, #2] &
] | tildeToken

(* Tokens valid ONLY at the outermost top level - intentionally
   unbalanced delimiters: the closing `)` `]` from `\left. + a \right)`,
   and the OPENING `(` `[` left behind by an unmatched `\big(` (e.g.
   `x^{\big(}`).  They are kept out of puncToken so they don't leak into
   parenAtom's / bracketAtom's inner row - balanced `(x)` / `[x]` still
   win via expr (tried first); only a genuinely unmatched delimiter
   falls through to here and renders as a bare glyph. *)
(* The trailing ParseMany[postfixRef] lets a script attach to an unmatched
   closer - `|0\rangle^{\otimes 10}` puts the power on the \rangle glyph,
   exactly where TeX puts it (issue #26). *)
outerPuncToken = ParseAction[
    ParseChoice[
        ParseAction[literal[")"] | literal["]"] | literal["("] | literal["["], #1 &],
        (* unmatched closing bracket commands (guarded out of commandAtom)
           render as their bare glyph here, like an unmatched ) / ] *)
        (* fixedFence (defined below, evaluated lazily): a bare closer doesn't
           stretch to a tall sibling - e.g. the \rangle in the ket
           `\lvert\psi\rangle` next to a fraction. *)
        ParseAction[literal["\\rangle"], fixedFence["\[RightAngleBracket]"] &],
        ParseAction[literal["\\rceil"],  fixedFence["\[RightCeiling]"] &],
        ParseAction[literal["\\rfloor"], fixedFence["\[RightFloor]"] &],
        ParseAction[literal["\\rVert"],  fixedFence["\[DoubleVerticalBar]"] &],
        ParseAction[literal["\\rvert"],  fixedFence["|"] &]
    ] ~~ ParseMany[postfixRef],
    attachScripts[#1, #2] &
]
(* matrix cells use a slightly looser row that accepts the closing
   delimiters ) and ] as bare tokens, so `3\times)` or `[a]` typo
   trailers don't abort the cell. The closes are kept OUT of `mathRow`
   itself so the recursive inner row of parenAtom / bracketAtom still
   has a ) / ] available for its literal close to consume. *)
cellPuncToken = ParseAction[
    (literal[")"] | literal["]"]) ~~ ParseMany[postfixRef],
    attachScripts[#1, #2] &
]

cellRow = ParseAction[
    ParseSome[ParseChoice[mathToken, ParseRecursive[cellPuncToken]]],
    If[Length[{##}] === 1, #1, RowBox[{##}]] &
]

(* cellRow is tried BEFORE the cellLeadingOp form because cellLeadingOp
   would greedily match \le (= \leq alias) at the start of \left,
   stealing the \left from the leftRightAtom path. Now \left(...)
   reaches leftRightAtom via cellRow's normal expr -> atom chain, and
   the cellLeadingOp form only kicks in when a true leading operator
   like = / \neq / + appears that cellRow's expr can't open with. *)
matrixCell = ParseChoice[
    ParseRecursive[cellRow],
    ParseAction[
        cellLeadingOp ~~ Optional[ParseRecursive[cellRow]],
        If[MissingQ[#2], #1, RowBox[{#1, #2}]] &
    ],
    ParseSucceed[""]
]
matrixRow  = ParseSepBy[matrixCell, colSep]
matrixBody = ParseSepBy[matrixRow, rowSep]

(* `\begin{matrix*}[l] ... \end{matrix*}` and the `array{c|r}`-style
   column-spec arg appear AFTER the `\begin{name}`. The braced
   arg captures `{c|r}`; the bracketed arg captures `[l]` / `[r]` for
   matrix* / pmatrix* alignment. Both are consumed and dropped - we
   render every alignment-variant as a default-aligned grid. *)
environmentAtom = ParseAction[
    ParseLiteral["\\begin"] ~~ ws ~~ envName ~~ ws ~~
        Optional[bracedArgRef] ~~ ws ~~ Optional[bracketedArgRef] ~~
        matrixBody ~~ ParseLiteral["\\end"] ~~ ws ~~ envName,
    buildEnv[#3, #8] &
]

(* True for a row that carries no content: empty, or every cell is the
   empty-string the `ParseSucceed[""]` fallback emits. *)
emptyMatrixRowQ[row_List] := MatchQ[row, {} | {(""|" ") ...}]

buildEnv[name_String, rowsIn_List] :=
    Module[{rows = rowsIn, width, padded, grid},
        (* A trailing `\\` before `\end{...}` makes ParseSepBy parse one
           more (empty) row. LaTeX/KaTeX tolerate the trailing separator
           and render NO extra row, so drop trailing all-empty rows -
           but never drop the last surviving row (an all-empty matrix
           should still be a 1x1 empty grid, not nothing). *)
        While[Length[rows] > 1 && emptyMatrixRowQ[Last[rows]],
            rows = Most[rows]
        ];
        width = Max[Length /@ rows, 1];
        padded = Map[PadRight[#, width, ""] &, rows];
        grid = GridBox[padded];
        Switch[name,
            "pmatrix" | "pmatrix*", RowBox[{"(", grid, ")"}],
            "bmatrix" | "bmatrix*", RowBox[{"[", grid, "]"}],
            "Bmatrix" | "Bmatrix*", RowBox[{"{", grid, "}"}],
            "vmatrix" | "vmatrix*", RowBox[{"\[LeftBracketingBar]", grid, "\[RightBracketingBar]"}],
            "Vmatrix" | "Vmatrix*", RowBox[{"\[LeftDoubleBracketingBar]", grid, "\[RightDoubleBracketingBar]"}],
            "cases" | "dcases" | "rcases" | "drcases",
                RowBox[{"{", GridBox[padded, ColumnAlignments -> Left]}],
            (* align / aligned / split / eqnarray / alignat / flalign:
               TeX alternates right- then left-aligned columns so the
               relation (the part after each `&`, e.g. `&= b`) lines up
               down the block.  PadRight cycles {Right, Left} to the
               column count. Without this the cells center and the `=`
               signs drift. *)
            "align" | "align*" | "aligned" | "split" |
            "eqnarray" | "eqnarray*" | "alignat" | "alignat*" |
            "alignedat" | "flalign" | "flalign*",
                GridBox[padded, ColumnAlignments -> PadRight[{}, width, {Right, Left}]],
            (* matrix / matrix* / smallmatrix / array / gather(ed) /
               equation / multline / CD render as a plain centred grid -
               they exist in TeX only for numbering or surrounding
               whitespace, not column alignment. *)
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

(* Use the Unicode mathematical-alphanumeric blocks directly - WL's
   named-character coverage is incomplete (no `\[Gothicz]`, no
   `\[DoubleStruck0]`, etc.). The Unicode spec has some letters in
   their classical math symbol homes (ℂ ℍ ℕ ℙ ℚ ℝ ℤ in U+2102
   etc.) and the rest in the SMP block U+1D400+; we patch in the
   exceptions so every A-Z maps to *some* glyph. *)

(* U+1D538 + i is double-struck-capital-{A+i}, with exceptions for
   C, H, N, P, Q, R, Z which live in the legacy Letterlike Symbols
   block (U+2102, 210D, 2115, 2119, 211A, 211D, 2124). *)
$dblExceptions = <|
    "C" -> 16^^2102, "H" -> 16^^210D, "N" -> 16^^2115,
    "P" -> 16^^2119, "Q" -> 16^^211A, "R" -> 16^^211D,
    "Z" -> 16^^2124
|>
doubleStruckChars = Association @ Join[
    Map[Function[c,
        c -> FromCharacterCode[
            Lookup[$dblExceptions, c, 16^^1D538 + ToCharacterCode[c][[1]] - 65]
        ]], CharacterRange["A", "Z"]],
    Map[Function[c,
        c -> FromCharacterCode[16^^1D552 + ToCharacterCode[c][[1]] - 97]],
        CharacterRange["a", "z"]],
    Map[Function[c,
        c -> FromCharacterCode[16^^1D7D8 + ToCharacterCode[c][[1]] - 48]],
        CharacterRange["0", "9"]]
]

(* U+1D49C + i is mathematical-script-{A+i}, with exceptions for
   B, E, F, H, I, L, M, R = legacy letterlike block. *)
$scrUpperExceptions = <|
    "B" -> 16^^212C, "E" -> 16^^2130, "F" -> 16^^2131,
    "H" -> 16^^210B, "I" -> 16^^2110, "L" -> 16^^2112,
    "M" -> 16^^2133, "R" -> 16^^211B
|>
$scrLowerExceptions = <|
    "e" -> 16^^212F, "g" -> 16^^210A, "o" -> 16^^2134
|>
scriptCapitalChars = Association @ Join[
    Map[Function[c,
        c -> FromCharacterCode[
            Lookup[$scrUpperExceptions, c, 16^^1D49C + ToCharacterCode[c][[1]] - 65]
        ]], CharacterRange["A", "Z"]],
    Map[Function[c,
        c -> FromCharacterCode[
            Lookup[$scrLowerExceptions, c, 16^^1D4B6 + ToCharacterCode[c][[1]] - 97]
        ]], CharacterRange["a", "z"]]
]

(* U+1D504 + i is fraktur-{A+i}, with exceptions C, H, I, R, Z. *)
$frkUpperExceptions = <|
    "C" -> 16^^212D, "H" -> 16^^210C, "I" -> 16^^2111,
    "R" -> 16^^211C, "Z" -> 16^^2128
|>
gothicCapitalChars = Association @ Join[
    Map[Function[c,
        c -> FromCharacterCode[
            Lookup[$frkUpperExceptions, c, 16^^1D504 + ToCharacterCode[c][[1]] - 65]
        ]], CharacterRange["A", "Z"]],
    Map[Function[c,
        c -> FromCharacterCode[16^^1D51E + ToCharacterCode[c][[1]] - 97]],
        CharacterRange["a", "z"]]
]

(* font-style handler: if arg is a single ASCII upper-case letter and we
   have a named-character for it, emit the named character; otherwise
   wrap in a StyleBox.

   Single-letter args reach us wrapped as StyleBox[letter, "TI"] (the
   default math-italic dressing applied by identAtom), so unwrap that
   before the lookup. *)

(* Per-letter font-switch handler: for each ASCII upper-case letter in
   the arg that has a named-character variant in `lookup`, replace
   it with the variant; non-letter atoms (digits, punctuation, Greek)
   pass through with the outer `fontOpt` styling so we don't lose them
   entirely. This way `\mathscr{ABC123\omega}` becomes script-A +
   script-B + script-C + 123 + ω (the digits and Greek can't be
   script-ified, but they shouldn't be dropped). *)
styleHandler[lookup_, fontOpt_] :=
    Function[{opt, req},
        Block[{arg = If[Length[req] >= 1, First[req], ""]},
            arg /. {
                StyleBox[s_String, "TI"] /; StringLength[s] === 1 &&
                    KeyExistsQ[lookup, s] :> lookup[s],
                s_String /; StringLength[s] === 1 &&
                    KeyExistsQ[lookup, s] :> lookup[s]
            }
        ]
    ]

commandHandlers["\\mathbb"]   = styleHandler[doubleStruckChars, FontWeight -> "Bold"]
commandHandlers["\\mathcal"]  = styleHandler[scriptCapitalChars, FontVariations -> {}]
commandHandlers["\\mathscr"]  = styleHandler[scriptCapitalChars, FontVariations -> {}]
commandHandlers["\\mathfrak"] = styleHandler[gothicCapitalChars, FontVariations -> {}]
(* Strip the default per-letter "TI" (math-italic) styling from the
   arg before applying the font-switch macro's own style.  Without this,
   `\mathbf{ab}` renders as bold-italic (StyleBox wraps a RowBox of
   italic letters in a bold-only outer style); KaTeX renders \mathbf
   as upright bold, \mathrm as upright, \mathsf as upright sans-serif. *)
(* Drop the per-letter math-italic dressing AND coalesce the resulting
   bare-string runs in any RowBox into a single string.  The notebook
   FE renders a RowBox of consecutive strings with a small gap between
   each child, so `\text{abc}` parsed into RowBox[{"a", "b", "c"}]
   would display as `a b c` (visible spaces).  Joining to RowBox[{"abc"}]
   - or just "abc" if only one piece remains - renders as the tight
   "abc" KaTeX gives.  Done as a single bottom-up pass (Replace at
   level Infinity, not ReplaceRepeated) so the RowBox unwrap doesn't
   cycle with parent re-application. *)
(* `Split` groups adjacent strings into runs (sub-lists), but
   non-string elements end up as singleton sub-lists too.  Map the
   merge over the splits and then `Catenate` (= flatten one level)
   so non-string singletons unwrap correctly - otherwise the RowBox
   ends up with literal `{OverscriptBox[...]}` children (a List
   wrapping a box), which the FE renders as `{box}` with visible
   braces around the inner expression. *)
mergeRowStrings[parts_List] := Module[{merged},
    merged = Catenate @ Map[
        If[Length[#] > 1 && VectorQ[#, StringQ], {StringJoin @@ #}, #] &,
        Split[parts, StringQ[#1] && StringQ[#2] &]
    ];
    If[Length[merged] === 1, First[merged], RowBox[merged]]
]
stripItalic[e_] := Replace[
    e //. StyleBox[s_String, "TI"] :> s,
    RowBox[parts_List] :> mergeRowStrings[parts],
    {0, Infinity}
]

commandHandlers["\\mathbf"]   = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontWeight -> "Bold", FontSlant -> "Plain"]
]
(* `\boldsymbol` / `\pmb` are bold-ITALIC (poor man's bold preserves
   the math-italic styling and just adds weight). KaTeX renders
   `\pmb{\mu}` as bold italic mu, NOT upright bold. Keep the inner
   TI italic dressing intact and only add Bold. *)
commandHandlers["\\boldsymbol"] = Function[{opt, req},
    StyleBox[First[req, ""], FontWeight -> "Bold"]
]
commandHandlers["\\pmb"]      = commandHandlers["\\boldsymbol"]
commandHandlers["\\mathrm"]   = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontSlant -> "Plain"]
]
commandHandlers["\\mathit"]   = Function[{opt, req},
    StyleBox[First[req, ""], FontSlant -> "Italic"]
]
commandHandlers["\\mathsf"]   = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontFamily -> "Helvetica", FontSlant -> "Plain"]
]
commandHandlers["\\mathtt"]   = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontFamily -> "Courier", FontSlant -> "Plain"]
]
commandHandlers["\\operatorname"] = commandHandlers["\\mathrm"]
(* `\operatorname*` is the limits-form variant: same upright styling
   as `\operatorname`, but sub/superscripts should attach as
   under/over limits in display mode.  Preprocessed to a synthetic
   name `\operatornamestar` (since the grammar's command name doesn't
   accept a `*` suffix), then handled here. *)
commandHandlers["\\operatornamestar"] = commandHandlers["\\mathrm"]

(* \text{...}: upright text. The arg comes through the math grammar
   (so a multi-letter run is a RowBox of italic letters); re-style the
   whole thing upright. An approximation - good enough for doc math. *)
(* `\text{abc}` switches to text mode: the contents are NOT math
   (no per-letter italic, no inter-letter math spacing).  Strip the
   inner StyleBox[c, "TI"] dressing that identAtom puts on letters
   so the output is upright text - matching KaTeX's behaviour where
   `\text{def}` renders as upright "def", not as italic "d e f". *)
commandHandlers["\\text"]   = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontSlant -> "Plain"]
]
commandHandlers["\\textrm"] = commandHandlers["\\text"]
commandHandlers["\\textbf"] = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontWeight -> "Bold", FontSlant -> "Plain"]
]
commandHandlers["\\textit"] = Function[{opt, req}, StyleBox[First[req, ""], FontSlant -> "Italic"]]
commandHandlers["\\texttt"] = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontFamily -> "Courier", FontSlant -> "Plain"]
]
commandHandlers["\\textsf"] = Function[{opt, req},
    StyleBox[stripItalic @ First[req, ""], FontFamily -> "Helvetica", FontSlant -> "Plain"]
]
commandHandlers["\\textnormal"] = commandHandlers["\\text"]
commandHandlers["\\emph"]       = commandHandlers["\\textit"]
(* \mathnormal / \mathsfit / \mathchoice: math-style variants that map
   to one of our existing styles, or pass through unchanged. *)
commandHandlers["\\mathnormal"] = identArgHandler
commandHandlers["\\mathsfit"]   = commandHandlers["\\mathsf"]
(* \mathchoice{display}{text}{script}{scriptscript}: TeX picks one of
   the four based on current math style. We render the `display` arg
   unconditionally, which is the conservative read in a doc-math
   context where styles aren't tracked. *)
commandHandlers["\\mathchoice"] = Function[{opt, req}, First[req, ""]]

(* \not: prefix that puts a slash through the next relation. The right
   way to render this for known relations is the precomposed negated
   Unicode glyph (≠, ≱, ⊄, ...) - StrikeThrough on a StyleBox doesn't
   actually slash the glyph in most rendering paths.  Fall back to
   StyleBox/StrikeThrough only for relations we don't have a precomposed
   form for.  Lookup keys are the rendered glyph the inner command
   resolved to (so `\not\leq` works regardless of \le-vs-\leq alias). *)
$notMap = <|
    "=" -> "\[NotEqual]",
    "<" -> "\[NotLess]",
    ">" -> "\[NotGreater]",
    "\[LessEqual]" -> "\[NotLessEqual]",
    "\[GreaterEqual]" -> "\[NotGreaterEqual]",
    "\[Element]" -> "\[NotElement]",
    "\[ReverseElement]" -> "\[NotReverseElement]",
    "\[Subset]" -> "\[NotSubset]",
    "\[Superset]" -> "\[NotSuperset]",
    "\[SubsetEqual]" -> "\[NotSubsetEqual]",
    "\[SupersetEqual]" -> "\[NotSupersetEqual]",
    "\[Congruent]" -> "\[NotCongruent]",
    "\[Tilde]" -> "\[NotTilde]",
    "\[TildeTilde]" -> "\[NotTildeTilde]",
    "\[TildeEqual]" -> "\[NotTildeEqual]",
    "\[TildeFullEqual]" -> "\[NotTildeFullEqual]",
    "\[Precedes]" -> "\[NotPrecedes]",
    "\[Succeeds]" -> "\[NotSucceeds]",
    "\[Exists]" -> "\[NotExists]"
|>
commandHandlers["\\not"] = Function[{opt, req},
    With[{a = First[req, ""]},
        Which[
            (* Precomposed Unicode for the common negated relations
               (≠, ⊄, ⊀, ...) - the typesetter actually renders them
               with a single solid stroke, which is what readers see
               in math. *)
            StringQ[a] && KeyExistsQ[$notMap, a], $notMap[a],
            (* Generic case: overlay the arg with `/` via negative
               horizontal margin.  FontVariations -> StrikeThrough
               renders as a barely-visible horizontal line in math
               mode, so it loses the "negation" affordance.  The
               AdjustmentBox approach gives a heavy diagonal slash
               crossing the glyph, matching KaTeX's visual. *)
            True, RowBox[{
                AdjustmentBox[a, BoxMargins -> {{0, -0.5}, {0, 0}}],
                "/"
            }]
        ]
    ]
]


(* === accents ===
   Each is a command with one required arg; renders as an OverscriptBox
   with the accent glyph on top. \overline / \underline / the wide
   accents span their whole argument. *)

(* When the accented base is a multi-token run (\widehat{xy},
   \overline{AB}), the FE gives it loose inter-letter math spacing
   inside the OverscriptBox, so the construct renders wider than LaTeX
   (\widehat{xy} ~1.35, \overline{AB} ~1.16).  Suppress that spacing on
   a RowBox base with AutoSpacing -> False; single-glyph bases are
   untouched. *)
accentBase[RowBox[p_List]] := If[
    AllTrue[p, MatchQ[#, StyleBox[_String, "TI"] | _String] &],
    StyleBox[RowBox[p], AutoSpacing -> False],  (* pure letter/char run *)
    RowBox[p]                                    (* has operators: keep spacing *)
]
accentBase[b_] := b
accentHandler[glyph_] := Function[{opt, req}, OverscriptBox[accentBase[First[req, ""]], glyph]]

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
(* Overscript "_" renders a line above the base.  (`\[OverBar]` would
   be the ideal sized overbar but is not a valid WL character; the
   slight width overshoot from "_" is accepted.) *)
commandHandlers["\\overline"] = accentHandler["_"]

commandHandlers["\\underline"] = Function[{opt, req}, UnderscriptBox[First[req, ""], "_"]]

(* over/under braces - the optional label rides above/below the brace. *)
commandHandlers["\\overbrace"]  = Function[{opt, req}, OverscriptBox[First[req, ""], "\[OverBrace]"]]
commandHandlers["\\underbrace"] = Function[{opt, req}, UnderscriptBox[First[req, ""], "\[UnderBrace]"]]
commandHandlers["\\overbracket"]  = Function[{opt, req}, OverscriptBox[First[req, ""], "\[OverBracket]"]]
commandHandlers["\\underbracket"] = Function[{opt, req}, UnderscriptBox[First[req, ""], "\[UnderBracket]"]]
(* `\overgroup` / `\undergroup` are KaTeX's stretchy
   parenthesis-style brace variants - use the same OverBrace/UnderBrace
   glyphs as a close visual approximation. *)
commandHandlers["\\overgroup"]   = commandHandlers["\\overbrace"]
commandHandlers["\\undergroup"]  = commandHandlers["\\underbrace"]
commandHandlers["\\overlinesegment"]  = commandHandlers["\\overline"]
commandHandlers["\\underlinesegment"] = commandHandlers["\\underline"]
(* stretchy over-arrows / over-harpoons *)
commandHandlers["\\overleftrightarrow"] = accentHandler["\[LeftRightArrow]"]
commandHandlers["\\overleftharpoon"]    = accentHandler["\[LeftArrow]"]
commandHandlers["\\overrightharpoon"]   = accentHandler["\[RightArrow]"]
(* \utilde: under-tilde companion to \tilde (over-tilde). *)
commandHandlers["\\utilde"] = Function[{opt, req}, UnderscriptBox[First[req, ""], "~"]]


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

(* \binom{n}{k}: the WL Binomial typesetting template (TemplateBox[..,"Binomial"]),
   not a hand-built parenthesized GridBox - so it renders as the standard binomial
   coefficient and round-trips to Binomial[n, k] under ToExpression. *)
commandHandlers["\\binom"] = Function[{opt, req},
    If[ Length[req] >= 2,
        TemplateBox[{req[[1]], req[[2]]}, "Binomial"],
        "\\binom"
    ]
]
commandHandlers["\\tbinom"] = commandHandlers["\\binom"]
commandHandlers["\\dbinom"] = commandHandlers["\\binom"]

(* Custom helpers the `\over` / `\atop` / `\brace` / `\brack` infix
   rewrites emit. `\atopfrac` = stacked numerator over denominator with
   no horizontal rule; `\bracefrac` / `\brackfrac` wrap that stack in
   curly / square delimiters. *)
commandHandlers["\\atopfrac"] = Function[{opt, req},
    If[Length[req] >= 2, GridBox[{{req[[1]]}, {req[[2]]}}], "\\atopfrac"]
]
commandHandlers["\\bracefrac"] = Function[{opt, req},
    If[Length[req] >= 2,
        RowBox[{"{", GridBox[{{req[[1]]}, {req[[2]]}}], "}"}],
        "\\bracefrac"]
]
commandHandlers["\\brackfrac"] = Function[{opt, req},
    If[Length[req] >= 2,
        RowBox[{"[", GridBox[{{req[[1]]}, {req[[2]]}}], "]"}],
        "\\brackfrac"]
]

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

(* TeX style / size switches take no args, but our greedy command
   parser will eat any `{...}` that happens to follow.  If we drop
   the brace content (noopHandler), constructs like `\displaystyle{x}`
   silently lose `x`.  Re-emit the consumed groups verbatim instead;
   for the no-following-brace case this still emits "". *)
styleScopeHandler = Function[{opt, req},
    Which[
        Length[req] === 0, "",
        Length[req] === 1, First[req],
        True, RowBox[req]
    ]
]

Scan[
    (commandHandlers[#] = noopHandler) &,
    {"\\limits", "\\nolimits", "\\displaylimits",
     "\\nonumber", "\\notag", "\\eqno", "\\leqno",
     "\\hline", "\\hdashline", "\\cline",
     "\\newline", "\\linebreak", "\\nolinebreak",
     "\\nobreak", "\\allowbreak", "\\noindent", "\\indent", "\\displaybreak",
     "\\smallskip", "\\medskip", "\\bigskip", "\\strut", "\\mathstrut",
     "\\phantom", "\\hphantom", "\\vphantom",
     "\\rule", "\\includegraphics", "\\def", "\\renewcommand", "\\newcommand", "\\gdef",
     "\\kern", "\\mkern", "\\hskip", "\\mskip", "\\hspace", "\\vspace",
     "\\quad" (* \quad already in namedSymbolChars - this no-ops if no handler hit *)
    }
]

(* Positive TeX spacing primitives render as visible space - KaTeX
   shows them (e.g. the thin space before `dx` in `\int x\,dx`), so
   dropping them, as we used to, loses real horizontal spacing.  Map to
   the named-space glyphs whose widths line up with TeX's 3/4/5-eighteenths
   of an em. *)
commandHandlers["\\,"]          = Function[{opt, req}, "\[ThinSpace]"]
commandHandlers["\\thinspace"]  = commandHandlers["\\,"]
commandHandlers["\\:"]          = Function[{opt, req}, "\[MediumSpace]"]
commandHandlers["\\>"]          = commandHandlers["\\:"]
commandHandlers["\\medspace"]   = commandHandlers["\\:"]
commandHandlers["\\;"]          = Function[{opt, req}, "\[ThickSpace]"]
commandHandlers["\\thickspace"] = commandHandlers["\\;"]
commandHandlers["\\enspace"]    = Function[{opt, req}, "\[ThickSpace]"]

(* Negative TeX spaces - the named negative-space glyphs DO kern cleanly in the
   FE (verified: letters pull together, no visible artifact), the negative
   mirror of \, \: \; above.  KaTeX renders \! as a real -3mu kern (e.g. the
   tightened d in \!\!\int, or \left( \! ... \! \right) hugging). *)
commandHandlers["\\!"]             = Function[{opt, req}, "\[NegativeThinSpace]"]
commandHandlers["\\negthinspace"]  = commandHandlers["\\!"]
commandHandlers["\\negmedspace"]   = Function[{opt, req}, "\[NegativeMediumSpace]"]
commandHandlers["\\negthickspace"] = Function[{opt, req}, "\[NegativeThickSpace]"]

Scan[
    (commandHandlers[#] = styleScopeHandler) &,
    {"\\textstyle", "\\displaystyle", "\\scriptstyle", "\\scriptscriptstyle",
     "\\it", "\\bf", "\\rm", "\\sf", "\\tt", "\\sl", "\\em"}
]

(* TeX size switches.  The body comes via the greedy `{...}` arg the
   command parser pulls (just like \displaystyle above); wrap it in
   a StyleBox with an absolute pt size proportional to KaTeX's
   sizing ratios assuming a 24pt base (matching our rasteriser).
   When the switch lacks a following brace, req is empty and we
   emit "" - same as the old noopHandler did. *)
sizeHandler[pt_] := Function[{opt, req},
    Which[
        Length[req] === 0, "",
        Length[req] === 1, StyleBox[First[req], FontSize -> pt],
        True, StyleBox[RowBox[req], FontSize -> pt]
    ]
]
commandHandlers["\\tiny"]         = sizeHandler[12]
commandHandlers["\\scriptsize"]   = sizeHandler[17]
commandHandlers["\\footnotesize"] = sizeHandler[20]
commandHandlers["\\small"]        = sizeHandler[22]
commandHandlers["\\normalsize"]   = sizeHandler[24]
commandHandlers["\\large"]        = sizeHandler[29]
commandHandlers["\\Large"]        = sizeHandler[35]
commandHandlers["\\LARGE"]        = sizeHandler[42]
commandHandlers["\\huge"]         = sizeHandler[50]
commandHandlers["\\Huge"]         = sizeHandler[60]

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
     "\\smash", "\\mbox", "\\hbox",
     (* \mathrlap / \mathllap / \mathclap render their arg with zero
        horizontal advance - r/l/c picks alignment. For doc-math we drop
        the layout trick and emit the arg unchanged. *)
     "\\mathrlap", "\\mathllap", "\\mathclap", "\\rlap", "\\llap", "\\clap",
     "\\underleftarrow", "\\underrightarrow", "\\underleftrightarrow"}
]

(* `\boxed{X}` / `\fbox{X}`: KaTeX renders these with an actual visible
   rectangular frame around the contents - dropping the box loses the
   semantic emphasis (boxed = "this is the boxed result").  Use FrameBox
   so the FE actually draws the frame. *)
commandHandlers["\\boxed"] = Function[{opt, req}, FrameBox[First[req, ""]]]
commandHandlers["\\fbox"]  = commandHandlers["\\boxed"]

(* `\tag{X}`: KaTeX renders the equation tag as `(X)` to the right of
   the formula.  We used to noop it (TeX itself uses tags for cross-
   reference numbering, not visual content), but visually the
   parenthesised label DOES show up on the page, so emit it. *)
commandHandlers["\\tag"] = Function[{opt, req},
    RowBox[{"(", First[req, ""], ")"}]
]

(* HTML / styling extension macros: KaTeX's `\htmlId{id}{body}`,
   `\htmlClass{cls}{body}`, `\htmlStyle{css}{body}`, `\htmlData{key}{body}`,
   `\colorbox{color}{body}`, `\fcolorbox{frame}{bg}{body}` - all 2-3
   arg, with the LAST arg being the visible content. We drop the
   styling metadata and emit just the content. \raisebox{offset}{body}
   similarly: drop offset, keep body. *)
(* `\rule[lift]{width}{height}`: KaTeX renders a filled black
   rectangle of the given dimensions.  Parse TeX length units (em, ex,
   pt, in, cm, mm) to points and emit a GraphicsBox with a Black
   Rectangle so the FE actually draws a visible rule.  No unit, or
   an unparseable arg, falls back to "" - same as the old noop. *)
texLengthToPt[s_String] := Module[{m},
    m = StringCases[StringTrim[s],
        StartOfString ~~ num:NumberString ~~ unit:LetterCharacter.. ~~ EndOfString :> {num, unit},
        1];
    If[ m === {}, Missing[],
        With[{n = ToExpression[m[[1, 1]]], u = m[[1, 2]]},
            n * Switch[u,
                "em", 12,  "ex", 6,
                "pt", 1,   "bp", 1,
                "in", 72,  "cm", 28.35, "mm", 2.835,
                "px", 0.75,
                "mu", 1,
                _, 1
            ]
        ]
    ]
]
commandHandlers["\\rule"] = Function[{opt, req},
    With[{w = If[Length[req] >= 1, texLengthToPt @ nameOfArg @ req[[1]], Missing[]],
          h = If[Length[req] >= 2, texLengthToPt @ nameOfArg @ req[[2]], Missing[]]},
        If[ NumberQ[w] && NumberQ[h] && w > 0 && h > 0,
            (* FrameBox with explicit ImageSize and a Black background
               renders as a filled rectangle in the FE.  GraphicsBox
               doesn't render correctly inside an inline math context
               (the box gets serialised as code, not drawn). *)
            FrameBox["", ImageSize -> {w, h},
                Background -> Black, FrameStyle -> None],
            ""
        ]
    ]
]

(* \kern{len} / \hspace{len} / \mkern{len} / \mskip{len} / \hskip{len}:
   KaTeX renders explicit horizontal whitespace of the given amount.
   We approximate with a SPACE-only StyleBox sized by FontSize - the
   effect is visible inter-element space, even if not perfectly to
   length spec. *)
spacingHandler = Function[{opt, req},
    With[{pt = texLengthToPt @ nameOfArg @ First[req, "0pt"]},
        If[ NumberQ[pt] && pt > 0,
            (* Use AdjustmentBox to insert a precise horizontal offset *)
            AdjustmentBox[" ", BoxMargins -> {{pt / 2, pt / 2}, {0, 0}}],
            " "
        ]
    ]
]
commandHandlers["\\kern"]   = spacingHandler
commandHandlers["\\mkern"]  = spacingHandler
commandHandlers["\\hskip"]  = spacingHandler
commandHandlers["\\mskip"]  = spacingHandler
commandHandlers["\\hspace"] = spacingHandler
commandHandlers["\\vspace"] = Function[{opt, req}, ""]  (* vertical, drop *)

commandHandlers["\\htmlId"]    = Function[{opt, req}, Last[req, ""]]
commandHandlers["\\htmlClass"] = Function[{opt, req}, Last[req, ""]]
(* `\htmlStyle{css}{body}`: parse the CSS arg for `color:<value>` and
   render the body in that colour.  Other CSS properties (background,
   font-weight, ...) are dropped - we only pick up the visible-text
   colour, since that's what the KaTeX corpus exercises.  Unknown
   colour values fall back to plain body. *)
commandHandlers["\\htmlStyle"] = Function[{opt, req},
    Module[{cssText, body, colorMatch},
        body = Last[req, ""];
        cssText = If[Length[req] >= 2, nameOfArg[First[req]], ""];
        colorMatch = StringCases[cssText,
            RegularExpression["color\\s*:\\s*([#a-zA-Z0-9]+)"] :> "$1", 1];
        If[ colorMatch =!= {},
            colorBody[body, First[colorMatch]],
            body
        ]
    ]
]
commandHandlers["\\htmlData"]  = Function[{opt, req}, Last[req, ""]]
(* `\colorbox{bg}{body}`: KaTeX wraps body with a coloured background.
   FrameBox with Background -> resolved colour matches the visual. *)
commandHandlers["\\colorbox"]  = Function[{opt, req},
    If[Length[req] >= 2,
        With[{c = resolveColor[req[[1]]]},
            If[MissingQ[c], Last[req, ""],
                FrameBox[Last[req, ""], Background -> c, FrameStyle -> None]
            ]
        ],
        Last[req, ""]
    ]
]
(* `\fcolorbox{frame}{bg}{body}`: framed background. *)
commandHandlers["\\fcolorbox"] = Function[{opt, req},
    If[Length[req] >= 3,
        With[{fc = resolveColor[req[[1]]], bc = resolveColor[req[[2]]]},
            FrameBox[Last[req, ""],
                Background -> If[MissingQ[bc], White, bc],
                FrameStyle -> If[MissingQ[fc], Black, fc]
            ]
        ],
        FrameBox @ Last[req, ""]
    ]
]
commandHandlers["\\raisebox"]  = Function[{opt, req}, Last[req, ""]]
(* \phantom / \hphantom / \vphantom take their arg as INVISIBLE space
   the same width/height. Emit "" (the contents shouldn't render). *)
commandHandlers["\\phantom"]  = Function[{opt, req}, ""]
commandHandlers["\\hphantom"] = commandHandlers["\\phantom"]
commandHandlers["\\vphantom"] = commandHandlers["\\phantom"]

(* === colors ===
   KaTeX `\color{name}{body}` and `\textcolor{name}{body}` accept a
   CSS / dvips color name (or a #RRGGBB hex) and apply that colour
   to the body. We map known names to RGBColor / GrayLevel and wrap
   the body in StyleBox[body, FontColor -> ...] so the notebook FE
   actually renders the colour - matching KaTeX's visible output.
   Unknown names fall back to dropping the colour. *)
$colorMap = <|
    "red" -> Red, "orange" -> Orange, "yellow" -> Yellow,
    "green" -> Green, "blue" -> Blue, "purple" -> Purple, "pink" -> Pink,
    "gray" -> Gray, "grey" -> Gray, "black" -> Black, "white" -> White,
    "magenta" -> Magenta, "cyan" -> Cyan, "olive" -> RGBColor[0.5, 0.5, 0],
    "teal" -> RGBColor[0, 0.5, 0.5], "lime" -> RGBColor[0.75, 1, 0],
    "violet" -> RGBColor[0.93, 0.51, 0.93],
    "maroon" -> RGBColor[0.5, 0, 0], "navy" -> RGBColor[0, 0, 0.5],
    "brown" -> Brown,
    (* dvips-style capitalised names KaTeX accepts on top of CSS *)
    "Red" -> Red, "Orange" -> Orange, "Yellow" -> Yellow,
    "Green" -> Green, "Blue" -> Blue, "Purple" -> Purple,
    "Black" -> Black, "White" -> White, "Magenta" -> Magenta,
    "Cyan" -> Cyan, "Brown" -> Brown, "Gray" -> Gray,
    "RoyalBlue" -> RGBColor[0.25, 0.41, 0.88],
    "ForestGreen" -> RGBColor[0.13, 0.55, 0.13],
    "BrickRed" -> RGBColor[0.7, 0.13, 0.13],
    "OliveGreen" -> RGBColor[0.33, 0.42, 0.18],
    "MidnightBlue" -> RGBColor[0.1, 0.1, 0.44],
    "BurntOrange" -> RGBColor[0.8, 0.34, 0],
    "Turquoise" -> RGBColor[0.25, 0.88, 0.82],
    "Goldenrod" -> RGBColor[0.85, 0.65, 0.13],
    "Lavender" -> RGBColor[0.9, 0.9, 0.98],
    "SkyBlue" -> RGBColor[0.53, 0.81, 0.92]
|>

(* Resolve a colour name (or `#RRGGBB`) to a WL colour, or Missing[]
   if we can't.  The name arrives as the parser's box tree for the
   arg - typically RowBox[{StyleBox["b", "TI"], StyleBox["l", "TI"],
   ...}] from the math-mode tokenisation of "blue".  Flatten the
   box tree, drop every StyleBox dressing, and string-join the leaves. *)
nameOfArg[a_] := StringJoin @@ Cases[
    {a} //. StyleBox[s_, ___] :> s,
    _String, Infinity
]
resolveColor[a_] := Module[{n = nameOfArg[a]},
    Which[
        StringStartsQ[n, "#"] && StringLength[n] === 7,
            RGBColor @@ (
                FromDigits[#, 16] / 255. & /@
                    StringPartition[StringDrop[n, 1], 2]),
        StringStartsQ[n, "#"] && StringLength[n] === 4,
            (* shorthand #rgb -> #rrggbb *)
            RGBColor @@ (
                FromDigits[# <> #, 16] / 255. & /@
                    Characters[StringDrop[n, 1]]),
        KeyExistsQ[$colorMap, n], $colorMap[n],
        True, Missing["UnknownColor", n]
    ]
]

colorBody[body_, name_] := Module[{c = resolveColor[name]},
    If[MissingQ[c], body, StyleBox[body, FontColor -> c]]
]

commandHandlers["\\color"]      = Function[{opt, req},
    If[Length[req] >= 2, colorBody[req[[2]], req[[1]]], Last[req, ""]]
]
commandHandlers["\\textcolor"]  = Function[{opt, req},
    If[Length[req] >= 2, colorBody[req[[2]], req[[1]]], Last[req, ""]]
]
(* KaTeX color shortcuts: `\red{x}`, `\blue{x}`, etc. take one arg
   and wrap it in the named colour.  Use the same lookup map. *)
Scan[
    Function[name,
        commandHandlers["\\" <> name] = Function[{opt, req},
            colorBody[First[req, ""], name]
        ]
    ],
    Keys[$colorMap]
]

(* === strike-through / cancel ===
   \sout, \cancel, \bcancel, \xcancel all visually score out the
   argument; render the arg with `FontVariations -> {"StrikeThrough" -> True}`.
   The struck-through glyph captures the semantic intent (the bit being
   cancelled) better than dropping the macro. *)
strikeHandler = Function[{opt, req},
    StyleBox[First[req, ""], FontVariations -> {"StrikeThrough" -> True}]
]
Scan[
    (commandHandlers[#] = strikeHandler) &,
    {"\\sout", "\\cancel", "\\bcancel", "\\xcancel"}
]

(* `\pod{X}` -> `(X)` (parenthesised remainder annotation, used after
   modular-arithmetic expressions like `a ≡ b \pod{n}`). The visually-
   distinct `\mod` / `\bmod` already live above. *)
commandHandlers["\\pod"] = Function[{opt, req}, RowBox[{"(", First[req, ""], ")"}]]
commandHandlers["\\pmod"] = Function[{opt, req},
    RowBox[{"(", StyleBox["mod", FontSlant -> "Plain"], " ",
        First[req, ""], ")"}]
]

(* `\underbar{X}` is a Plain-TeX alias for `\underline{X}` - same render. *)
commandHandlers["\\underbar"] = commandHandlers["\\underline"]

(* Split a flat box / RowBox-parts list at each `$lineBreakMark`,
   returning one entry per line: a bare box for a single-token line,
   a RowBox for a multi-token line, "" for an empty line.  Shared by
   \substack and the top-level applyLineBreaks pass. *)
lineBreakSegments[body_] := Module[{parts},
    parts = Replace[body, {RowBox[p_List] :> p, x_ :> {x}}];
    Replace[
        SequenceSplit[parts, {$lineBreakMark}],
        {
            {} :> "",
            {one_} :> one,
            many_List :> RowBox[many]
        },
        {1}
    ]
]

(* Sized delimiters from \big / \Big / \bigg / \Bigg (and their l/r/m
   variants).  preprocessLaTeX rewrites `\Big(` -> `\xbigII{(}` etc.,
   routing the delimiter here so we can scale it.  KaTeX grows the
   delimiter ~1.2 / 1.8 / 2.4 / 3.0x of the SURROUNDING text size.
   FontSize -> r Inherited multiplies the inherited font size, so the
   delimiter stays r times its neighbours under any viewer zoom and
   still resolves inside a standalone Rasterize (issue #27).  Do NOT
   swap this back to Magnification: that is an absolute screen-zoom
   setting, not a relative scale, so under a zoomed viewer the glyph
   stays pinned at e.g. 1.2x absolute and renders SMALLER than the
   scaled-up body text.  FontSize -> Scaled[r] is also wrong - it
   resolves against the window/canvas and explodes a standalone
   Rasterize.  The `.` null delimiter never reaches here - dropped
   upstream. *)
$xbigRatio = <|"I" -> 1.2, "II" -> 1.8, "III" -> 2.4, "IV" -> 3.0|>
Scan[
    Function[lvl,
        commandHandlers["\\xbig" <> lvl] = Function[{opt, req},
            With[{d = First[req, ""]},
                If[d === "", "", StyleBox[d, FontSize -> $xbigRatio[lvl] Inherited]]
            ]
        ]
    ],
    {"I", "II", "III", "IV"}
]

(* `\substack{a\\b\\c}`: small vertical stack used under summation /
   product limits.  Render as a single-column GridBox, one row per
   `\\`-separated segment. *)
commandHandlers["\\substack"] = Function[{opt, req},
    With[{rows = lineBreakSegments[First[req, ""]]},
        GridBox[List /@ rows]
    ]
]

(* `\Set{ x | x > 0 }` / `\Braket{ x | y }`: KaTeX set-builder macros.
   Render as braced/angled content, with the inner `|` preserved
   verbatim.  The handler just wraps with `{...}` or `<...|...>`. *)
commandHandlers["\\Set"]    = Function[{opt, req},
    RowBox[{"{", First[req, ""], "}"}]
]
commandHandlers["\\Braket"] = Function[{opt, req},
    RowBox[{"\[LeftAngleBracket]", First[req, ""], "\[RightAngleBracket]"}]
]

(* `\phase{angle}`: phase / angle notation, render as `\[Angle] angle`. *)
commandHandlers["\\phase"] = Function[{opt, req},
    RowBox[{"\[Angle]", First[req, ""]}]
]
(* `\angl{X}` / `\angln{X}`: KaTeX-specific angle macros.  `\angl` puts
   an angle bracket before, `\angln` also draws the underbar. *)
commandHandlers["\\angl"]  = Function[{opt, req},
    RowBox[{"\[Angle]", First[req, ""]}]
]
commandHandlers["\\angln"] = Function[{opt, req},
    UnderscriptBox[RowBox[{"\[Angle]", First[req, ""]}], "_"]
]

(* `\vcenter{box}`: vertical centring trick; we just emit the arg. *)
commandHandlers["\\vcenter"] = identArgHandler

(* `\genfrac` is the most general TeX fraction primitive:
   `\genfrac<left-delim><right-delim>{thickness}{style}{num}{denom}`
   - the first two args are single-token delimiters (often `.` for none),
   the next two are layout hints we drop, and the final two are the
   fraction parts.  Render as `delim num/denom delim`. *)
commandHandlers["\\genfrac"] = Function[{opt, req},
    With[{n = Length[req]},
        Which[
            n >= 6,
                RowBox[{
                    Replace[req[[1]], "." -> Nothing],
                    FractionBox[req[[5]], req[[6]]],
                    Replace[req[[2]], "." -> Nothing]
                }],
            n >= 5, FractionBox[req[[4]], req[[5]]],
            n >= 4, FractionBox[req[[3]], req[[4]]],
            True, "\\genfrac"
        ]
    ]
]

(* Text-mode accent macros that get dragged into math via `\text{...}`.
   Each takes a single (often un-braced) argument; treat as accents. *)
commandHandlers["\\H"] = accentHandler[FromCharacterCode[733]]   (* double acute U+02DD *)
commandHandlers["\\r"] = accentHandler["\[SmallCircle]"]
commandHandlers["\\i"] = Function[{opt, req}, "\[DotlessI]"]
commandHandlers["\\j"] = Function[{opt, req}, "\[DotlessJ]"]
commandHandlers["\\u"] = accentHandler["\[Breve]"]
commandHandlers["\\v"] = accentHandler["\[Hacek]"]
(* Punct-name accents: TeX text-mode `\'a` -> á, `\`a` -> à, etc.
   Render as the letter with the accent glyph above. *)
commandHandlers["\\'"]   = accentHandler[FromCharacterCode[180]]   (* acute *)
commandHandlers["\\`"]   = accentHandler[FromCharacterCode[96]]    (* grave *)
commandHandlers["\\\""] = accentHandler[FromCharacterCode[168]]    (* diaeresis *)
commandHandlers["\\."]   = accentHandler["."]                       (* dot *)
commandHandlers["\\="]   = accentHandler["_"]                       (* macron *)
commandHandlers["\\~"]   = accentHandler["~"]                       (* tilde *)

(* Extensible arrows: `\xrightarrow[below]{above}` and friends. KaTeX
   renders these as a long arrow with the optional `[below]` annotation
   beneath it and the required `{above}` annotation above. We approximate
   with `UnderoverscriptBox[arrow, below, above]`, which is the closest
   one-shot box analogue in WL. *)
xarrowHandler[arrow_String] := Function[{opt, req},
    With[{above = First[req, ""], below = If[opt === Null || MissingQ[opt], "", opt]},
        UnderoverscriptBox[arrow, below, above]
    ]
]
commandHandlers["\\xrightarrow"]            = xarrowHandler["\[LongRightArrow]"]
commandHandlers["\\xleftarrow"]             = xarrowHandler["\[LongLeftArrow]"]
commandHandlers["\\xRightarrow"]            = xarrowHandler["\[DoubleLongRightArrow]"]
commandHandlers["\\xLeftarrow"]             = xarrowHandler["\[DoubleLongLeftArrow]"]
commandHandlers["\\xleftrightarrow"]        = xarrowHandler["\[LongLeftRightArrow]"]
commandHandlers["\\xLeftrightarrow"]        = xarrowHandler["\[DoubleLongLeftRightArrow]"]
commandHandlers["\\xhookleftarrow"]         = xarrowHandler["\[LongLeftArrow]"]
commandHandlers["\\xhookrightarrow"]        = xarrowHandler["\[LongRightArrow]"]
commandHandlers["\\xmapsto"]                = xarrowHandler["\[Function]"]
commandHandlers["\\xrightharpoonup"]        = xarrowHandler["\[RightArrow]"]
commandHandlers["\\xrightharpoondown"]      = xarrowHandler["\[RightArrow]"]
commandHandlers["\\xleftharpoonup"]         = xarrowHandler["\[LeftArrow]"]
commandHandlers["\\xleftharpoondown"]       = xarrowHandler["\[LeftArrow]"]
commandHandlers["\\xrightleftharpoons"]     = xarrowHandler["\[Equilibrium]"]
commandHandlers["\\xleftrightharpoons"]     = xarrowHandler["\[Equilibrium]"]
commandHandlers["\\xrightequilibrium"]      = xarrowHandler["\[Equilibrium]"]
commandHandlers["\\xleftequilibrium"]       = xarrowHandler["\[ReverseEquilibrium]"]
commandHandlers["\\xrightleftarrows"]       = xarrowHandler["\[LeftRightArrow]"]
commandHandlers["\\xtwoheadrightarrow"]     = xarrowHandler["\[LongRightArrow]"]
commandHandlers["\\xtwoheadleftarrow"]      = xarrowHandler["\[LongLeftArrow]"]
commandHandlers["\\xtofrom"]                = xarrowHandler["\[LeftRightArrow]"]
(* Capital `\Overrightarrow` variant - KaTeX uses both. *)
commandHandlers["\\Overrightarrow"]         = commandHandlers["\\overrightarrow"]

(* \verb|text|: TeX's verbatim macro. The delimiter is the first char
   after \verb (here we only see it post-tokenisation, where the arg
   already arrived as one braced run). Render as monospace. *)
commandHandlers["\\verb"] = Function[{opt, req},
    StyleBox[First[req, ""], FontFamily -> "Courier"]
]

(* Wide-accent companions: \widecheck, \widebreve, \widering. *)
commandHandlers["\\widecheck"] = accentHandler["\[Hacek]"]
commandHandlers["\\widebreve"] = accentHandler["\[Breve]"]


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
    "\\|"       -> "\[DoubleVerticalBar]",
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
    "\\ni"      -> "\[ReverseElement]",
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
    "\\hookrightarrow" -> "\:21aa", "\\hookleftarrow" -> "\:21a9",
    "\\longmapsto"  -> "\[Function]",  "\\implies" -> "\[DoubleLongRightArrow]",
    "\\impliedby"   -> "\[DoubleLongLeftArrow]", "\\iff" -> "\[DoubleLongLeftRightArrow]",
    "\\rightsquigarrow" -> "\:21dd",   "\\leadsto" -> "\:21dd",
    (* diagonal arrows *)
    "\\nearrow"  -> "\[UpperRightArrow]", "\\searrow" -> "\[LowerRightArrow]",
    "\\swarrow"  -> "\[LowerLeftArrow]",  "\\nwarrow" -> "\[UpperLeftArrow]",
    (* harpoons (LaTeX \...harpoon... = Wolfram vector glyphs) *)
    "\\leftharpoonup"     -> "\[LeftVector]",   "\\leftharpoondown"   -> "\[DownLeftVector]",
    "\\rightharpoonup"    -> "\[RightVector]",  "\\rightharpoondown"  -> "\[DownRightVector]",
    "\\rightleftharpoons" -> "\[Equilibrium]",  "\\leftrightharpoons" -> "\[ReverseEquilibrium]",
    (* two-headed / dashed arrows (no Wolfram named char - raw Unicode) *)
    "\\twoheadrightarrow" -> "\:21a0", "\\twoheadleftarrow" -> "\:219e",
    "\\dashrightarrow"    -> "\:21e2", "\\dashleftarrow"    -> "\:21e0",
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
    "\\wp"      -> "\[WeierstrassP]",   "\\Finv" -> "\[FinalSigma]",
    "\\complement" -> "\[NotElement]", "\\degree" -> "\[Degree]",
    "\\prime"   -> "\[Prime]",         "\\backslash" -> "\[Backslash]",
    "\\lnot"    -> "\[Not]",
    "\\gtrsim"  -> "\[GreaterTilde]",  "\\lesssim" -> "\[LessTilde]",
    "\\ne"      -> "\[NotEqual]",      "\\notni" -> "\[NotReverseElement]",
    (* dotless variants and other plain-TeX letter macros *)
    "\\imath"   -> "\[DotlessI]",      "\\jmath" -> "\[DotlessJ]",
    (* KaTeX's literal logo. We emit "KaTeX" as plain text rather than
       try to typeset the slanted Kₐ form - the visual fidelity isn't
       worth the layout cost. *)
    "\\KaTeX"   -> "KaTeX",
    "\\LaTeX"   -> "LaTeX",
    "\\TeX"     -> "TeX",
    (* extras KaTeX corpus exercises - skip ones WL doesn't ship a
       named char for (\beth, \gimel, \daleth, \backepsilon). *)
    "\\digamma" -> "\[Digamma]",
    "\\nothing" -> "\[EmptySet]",
    "\\mho"     -> "\[Mho]",
    (* multi-integrals *)
    "\\iint"    -> "\[Integral]\[Integral]",
    "\\iiint"   -> "\[Integral]\[Integral]\[Integral]",
    "\\oiint"   -> "\[ContourIntegral]\[ContourIntegral]",
    "\\oiiint"  -> "\[ContourIntegral]\[ContourIntegral]\[ContourIntegral]",
    "\\intop"   -> "\[Integral]",
    (* delimiter aliases used as `\lvert` / `\rvert` *)
    "\\lvert"   -> "|",          "\\rvert"   -> "|",
    "\\lVert"   -> "\[DoubleVerticalBar]", "\\rVert" -> "\[DoubleVerticalBar]",
    (* miscellaneous symbols - some have no WL named character so we
       use Unicode literals (FromCharacterCode handles them either way). *)
    "\\maltese" -> FromCharacterCode[10016],   (* MALTESE CROSS U+2720 *)
    "\\pounds"  -> "\[Sterling]",
    "\\textdollar" -> "$",
    "\\minuso"  -> "\[CircleMinus]",
    (* \varepsilon variant *)
    "\\varepsilon" -> "\[Epsilon]",
    "\\varphi"     -> "\[CurlyPhi]",
    "\\varrho"     -> "\[CurlyRho]",
    "\\varsigma"   -> "\[FinalSigma]",
    "\\vartheta"   -> "\[CurlyTheta]",
    "\\varpi"      -> "\[CurlyPi]",
    "\\varkappa"   -> "\[CurlyKappa]"
|>

Scan[
    Function[name,
        commandHandlers[name] = Function[{opt, req}, namedSymbolChars[name]]
    ],
    Keys[namedSymbolChars]
]

(* A standalone fence command - `\lvert` / `\rangle` used WITHOUT
   \left...\right, as in the bra-ket `\lvert\psi\rangle` - emits a FIXED-size
   glyph (like parenAtom / matchfixAtom), so it won't stretch to a tall sibling
   such as a fraction in the same row.  `\left\langle...` takes the stretchy
   delimGlyph path instead, so it is unaffected.  fixedFence is defined below;
   the handler bodies evaluate lazily, so the forward reference is fine. *)
Scan[
    Function[name,
        commandHandlers[name] = Function[{opt, req}, fixedFence[namedSymbolChars[name]]]
    ],
    {"\\langle", "\\rangle", "\\lvert", "\\rvert", "\\lVert", "\\rVert",
     "\\lceil", "\\rceil", "\\lfloor", "\\rfloor"}
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

(* Lowercase Greek renders math-italic to match the standard math-mode
   convention (`\alpha` displays as italic α, not upright); uppercase
   Greek stays upright (TeX convention). The names with "Capital" in
   their NumericValue go upright, lowercase get TI. *)
Scan[
    Function[name,
        commandHandlers[name] = With[{
            glyph = greekChars[name],
            isUpper = StringMatchQ[name, "\\" ~~ ("A"|"B"|"C"|"D"|"E"|"F"|"G"|"H"|"I"|"J"|"K"|"L"|"M"|"N"|"O"|"P"|"Q"|"R"|"S"|"T"|"U"|"V"|"W"|"X"|"Y"|"Z") ~~ ___]
        },
            Function[{opt, req},
                If[isUpper, glyph, StyleBox[glyph, "TI"]]
            ]
        ]
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

(* True when a factor is a named function operator (`\sin`, `\log`,
   `\lim`, ...), possibly carrying scripts (`\log_2`, `\sin^2`) or
   sitting at the right edge of a juxtaposition chain (`2\sin`).  Used
   to insert TeX's thin function-application space between the operator
   and its argument (`\sin x` -> sin + thinspace + x), which the FE's
   plain juxtaposition omits. *)
funcAtomQ[StyleBox[n_String, FontSlant -> "Plain"]] := MemberQ[functionNames, n]
funcAtomQ[(SubscriptBox | SuperscriptBox | SubsuperscriptBox)[base_, ___]] := funcAtomQ[base]
funcAtomQ[RowBox[parts_List]] := parts =!= {} && funcAtomQ[Last[parts]]
funcAtomQ[_] := False


(* === precedence stratification: atom < factor < term < expr === *)

(* parenthesised subexpression: emits the parens as part of the box so
   they render visually, unlike `{...}` which is structural-only. Inner
   is topRow so `(x \\ y)` and `(a, b $c$ d)` survive - real-world TeX
   does sometimes put a row break or math toggle inside delimited
   groups. The recursive inner ROW must be topRow (not outerRow) so
   the closing ) is still available for our literal[")"] to consume,
   rather than being eaten as outerPuncToken. *)
(* A bare fence (one the user typed directly, not via \left...\right) is
   FIXED-size in LaTeX - it never grows to its content.  The front end, though,
   auto-stretches a bracket character to the tallest thing in its RowBox, so a
   bare `(x)` sitting in a row with a matrix or fraction balloons to the row
   height.  SpanMaxSize -> 1 pins the glyph to its natural size, matching
   LaTeX.  \left...\right and matrix fences are emitted WITHOUT this, so they
   still stretch. *)
fixedFence[c_] := StyleBox[c, SpanMaxSize -> 1]

parenAtom = ParseAction[
    literal["("] ~~ ParseRecursive[topRow] ~~ literal[")"],
    RowBox[{fixedFence["("], #2, fixedFence[")"]}] &
]

bracketAtom = ParseAction[
    literal["["] ~~ ParseRecursive[topRow] ~~ literal["]"],
    RowBox[{fixedFence["["], #2, fixedFence["]"]}] &
]

(* \left X content \right Y - any X, Y delimiter pair, including the
   mismatched forms TeX permits (\left(...\right]) and the null-delim
   form \left. and \right. (which we render as the empty string). The
   inner content is topRow so line breaks / math toggles survive. *)
delimMacro = ParseChoice[
    literal["("], literal[")"], literal["["], literal["]"],
    literal["|"], literal["<"], literal[">"], literal["."], literal["/"],
    literal["\\{"], literal["\\}"],
    literal["\\langle"], literal["\\rangle"],
    literal["\\lceil"],  literal["\\rceil"],
    literal["\\lfloor"], literal["\\rfloor"],
    literal["\\lvert"],  literal["\\rvert"],
    literal["\\lVert"],  literal["\\rVert"],
    literal["\\|"], literal["\\backslash"], literal["\\uparrow"],
    literal["\\downarrow"], literal["\\updownarrow"],
    literal["\\Uparrow"], literal["\\Downarrow"], literal["\\Updownarrow"]
]

delimGlyph["."] = ""
delimGlyph["\\{"] = "{"
delimGlyph["\\}"] = "}"
delimGlyph["\\langle"]  = "\[LeftAngleBracket]"
delimGlyph["\\rangle"]  = "\[RightAngleBracket]"
delimGlyph["\\lceil"]   = "\[LeftCeiling]"
delimGlyph["\\rceil"]   = "\[RightCeiling]"
delimGlyph["\\lfloor"]  = "\[LeftFloor]"
delimGlyph["\\rfloor"]  = "\[RightFloor]"
delimGlyph["\\lvert"]   = "|"
delimGlyph["\\rvert"]   = "|"
delimGlyph["\\lVert"]   = "\[DoubleVerticalBar]"
delimGlyph["\\rVert"]   = "\[DoubleVerticalBar]"
delimGlyph["\\|"]       = "\[DoubleVerticalBar]"
delimGlyph["\\backslash"] = "\\"
delimGlyph["\\uparrow"]     = "\[UpArrow]"
delimGlyph["\\downarrow"]   = "\[DownArrow]"
delimGlyph["\\updownarrow"] = "\[UpDownArrow]"
delimGlyph["\\Uparrow"]     = "\[DoubleUpArrow]"
delimGlyph["\\Downarrow"]   = "\[DoubleDownArrow]"
delimGlyph["\\Updownarrow"] = "\[DoubleUpDownArrow]"
delimGlyph[s_String] := s

(* \left|..\right| and \left\|..\right\| use the matchfix bracketing-bar
   characters (distinct left vs right), which hug and stretch like LaTeX;
   every other delimiter keeps the symmetric glyph delimGlyph returns. *)
barDelimL[g_] := g /. {"|" -> "\[LeftBracketingBar]", "\[DoubleVerticalBar]" -> "\[LeftDoubleBracketingBar]"}
barDelimR[g_] := g /. {"|" -> "\[RightBracketingBar]", "\[DoubleVerticalBar]" -> "\[RightDoubleBracketingBar]"}
leftRightAtom = ParseAction[
    ParseLiteral["\\left"] ~~ ws ~~ delimMacro ~~ ws ~~
        ParseRecursive[topRow] ~~
        ParseLiteral["\\right"] ~~ ws ~~ delimMacro,
    With[{l = barDelimL[delimGlyph[#3]], r = barDelimR[delimGlyph[#8]]},
        RowBox[Select[{l, #5, r}, # =!= "" &]]
    ] &
]

(* absolute-value / norm bars: |expr| renders the bars visibly. The
   inner is the relation-free sumExpr so a stray | terminates it. *)
(* Emit the front end's matchfix bracketing-bar characters, not a plain
   "|": \[LeftBracketingBar] / \[RightBracketingBar] are *delimiters*, so
   the FE hugs them to the content the way LaTeX does and stretches them
   to tall content - exactly what ToBoxes[Abs[x], TraditionalForm] emits.
   A plain "|" instead gets the FE's looser relation/separator spacing.
   (An earlier version pulled plain bars in with negative AdjustmentBox
   margins, but that kern landed asymmetrically on "|" and made the proper
   bracket characters below overlap their content.) *)
(* Italic correction.  An italic glyph leans right, so its ink sits flush
   against a following closing delimiter while the opener has a wide gap to the
   ink - `|x|` then reads as pushed toward the right bar (an upright `|2|` is
   already symmetric).  When the content ends in an italic letter, insert a
   1-mu VeryThinSpace before the closer, exactly as TeX's italic correction
   does; upright content is left untouched. *)
endsItalicQ[StyleBox[_, "TI", ___]] := True
endsItalicQ[RowBox[parts_List]] := parts =!= {} && endsItalicQ[Last[parts]]
endsItalicQ[_] := False
italicCorr[content_] := If[endsItalicQ[content], "\[VeryThinSpace]", Nothing]

absAtom = ParseAction[
    literal["|"] ~~ ParseRecursive[sumExpr] ~~ literal["|"],
    RowBox[{"\[LeftBracketingBar]", #2, italicCorr[#2], "\[RightBracketingBar]"}] &
]
(* No matchfix normAtom for `\|...\|`: unlike `|`, `\|` is also a valid
   standalone atom (-> double-bar glyph), so a matchfix inner sumExpr
   greedily swallows the closing `\|` as a juxtaposed glyph and the
   atom never closes.  `\|v\|` therefore renders as the plain row
   ‖ v ‖ (correct content, just not kerned).  The NAMED bracket pairs
   below don't have that problem - their open/close tokens differ. *)

(* Matchfix bracket pairs with distinct open/close commands.  Inner is
   `topRow` (like parenAtom) so a comma list lives INSIDE the brackets
   - `\langle a, b \rangle` is one group, not the loose tokens ⟨a , b⟩
   with the bracket bound to one operand.  Works because the closers
   (\rangle/\rceil/...) are guarded out of commandAtom above, so the
   inner row stops at them and the matchfix `literal` closer matches.
   The fences are matchfix delimiter characters, so the FE spaces and
   grows them correctly with no kern.  Tried before commandAtom so a
   matched pair wins; an unmatched OPENER falls through to the bare-glyph
   command path (openers are not guarded). *)
matchfixAtom[openTok_, closeTok_, og_, cg_] := ParseAction[
    literal[openTok] ~~ ParseRecursive[topRow] ~~ literal[closeTok],
    RowBox[{fixedFence[og], #2, italicCorr[#2], fixedFence[cg]}] &
]
angleAtom = matchfixAtom["\\langle", "\\rangle", "\[LeftAngleBracket]", "\[RightAngleBracket]"]
ceilAtom  = matchfixAtom["\\lceil",  "\\rceil",  "\[LeftCeiling]", "\[RightCeiling]"]
floorAtom = matchfixAtom["\\lfloor", "\\rfloor", "\[LeftFloor]", "\[RightFloor]"]
lvertAtom = matchfixAtom["\\lvert",  "\\rvert",  "\[LeftBracketingBar]", "\[RightBracketingBar]"]
lVertAtom = matchfixAtom["\\lVert",  "\\rVert",  "\[LeftDoubleBracketingBar]", "\[RightDoubleBracketingBar]"]

atom = ParseChoice[
    numberAtom, environmentAtom, leftRightAtom,
    angleAtom, ceilAtom, floorAtom, lVertAtom, lvertAtom,
    commandAtom,
    parenAtom, bracketAtom, absAtom,
    bracedArgRef, identAtom, unicodeAtom
]

(* TeX's _ / ^ take ANY single token as the script - including a bare
   sign / relation / punctuation character: `\sigma_-`, `x_+`, `a^-`,
   `x_*` (issue #26).  Delimiter characters stay excluded: a closing
   ) / ] / | right after ^ or _ must remain available as the enclosing
   group's own closer. *)
scriptCharAtom = ParseAction[
    token[ParseCharacter[
        "+" | "-" | "*" | "/" | "=" | "<" | ">" | "!" | "?" | "."
    ]],
    #1 &
]

(* A postfix is _x, ^y, or a run of primes - each tagged so factor can
   accept them in any order and any number (`x_i^2`, `x^2_i`, `f'`,
   `x'^2_3`, `f_2'` all occur in real LaTeX). primes fold into the
   superscript. *)
postfix = ParseChoice[
    ParseAction[literal["_"] ~~ (bracedArgRef | atom | scriptCharAtom), {"sub", #2} &],
    ParseAction[literal["^"] ~~ (bracedArgRef | atom | scriptCharAtom), {"sup", #2} &],
    (* Primes fold into a superscript.  Use the precomposed \[DoublePrime]
       (single tight glyph ″) for 2 marks instead of two concatenated
       \[Prime] glyphs, which render wider/looser than LaTeX (x'' was
       ~1.12).  No valid precomposed triple-prime char exists, so 3+
       marks stay as repeated \[Prime]. *)
    ParseAction[
        ParseSome[literal["'"]],
        {"sup", Switch[Length[{##}],
            1, "\[Prime]",
            2, "\[DoublePrime]",
            _, StringJoin[ConstantArray["\[Prime]", Length[{##}]]]
        ]} &
    ]
]

(* Combine a base box with the postfix scripts collected after it
   ({"sub"|"sup", box} pairs).  Shared by factor and the bare-token
   paths (puncToken / outerPuncToken / cellPuncToken, issue #26); an
   empty posts list returns the base unchanged. *)
attachScripts[base_, posts_List] := Module[{sub, sups},
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

factor = ParseAction[
    atom ~~ ParseMany[postfix],
    Function[{base, posts}, attachScripts[base, posts]]
]

(* rowJoin: concatenate two boxes into a single flat RowBox, splicing
   any existing RowBox operands so chains stay flat
   (`RowBox[{a, b, c}]`, not nested pairs). *)
rowParts[RowBox[l_List]] := l
rowParts[x_] := {x}
rowJoin[a_, b_] := RowBox[Join[rowParts[a], rowParts[b]]]
rowJoin[a_, mid_, b_] := RowBox[Join[rowParts[a], {mid}, rowParts[b]]]

(* mulOp joins adjacent factors. PEG-ordered: explicit `/` stays as a
   visible slash (KaTeX renders `a/b` inline, NOT as a stacked
   FractionBox - that's what `\frac{a}{b}` is for). Explicit `*` /
   `\cdot` / `\times` build a visible product, and (the final
   fallback) ParseSucceed gives juxtaposition - LaTeX's implicit
   multiplication (`2x`, `\sum x_i`, `\sin x`). *)
mulOp = ParseChoice[
    ParseAction[literal["/"], Function[op, Function[{a, b}, rowJoin[a, "/", b]]]],
    (* Distinct glyphs: `\cdot` is ·, `\times` is ×, `*` is the
       asterisk operator. KaTeX renders all three differently. *)
    ParseAction[literal["\\cdot"],
        Function[op, Function[{a, b}, rowJoin[a, "\[CenterDot]", b]]]],
    ParseAction[literal["\\times"],
        Function[op, Function[{a, b}, rowJoin[a, "\[Times]", b]]]],
    ParseAction[literal["*"],
        Function[op, Function[{a, b}, rowJoin[a, "*", b]]]],
    ParseAction[ParseSucceed[Null], Function[op, Function[{a, b},
        (* function application gets a thin space (\sin x); other
           juxtaposition (2x, x_i a) stays tight *)
        If[funcAtomQ[a], rowJoin[a, "\[ThinSpace]", b], rowJoin[a, b]]]]]
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
    (* `,` keeps a thin space after - list-separator look in
       `(a, b, c)`.  `;` and `:` emit the bare glyph; both classify
       as relations in TeX math so the FE inserts the right gap. *)
    ParseAction[literal[","], "," <> "\[ThinSpace]" &],
    ParseAction[literal[";"], ";" &],
    ParseAction[literal[":"], ":" &],
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
(* A distinct sentinel for `\\` / `\cr` line breaks, kept separate from
   the `""` that empty groups / spacing no-ops emit.  Carrying it as its
   own marker lets applyLineBreaks (post-parse) tell a genuine line
   break apart from incidental empty strings and stack the segments into
   a GridBox.  The marker never survives to output - applyLineBreaks
   removes every occurrence. *)
linebreakToken = ParseAction[
    (literal["\\\\"] | literal["\\cr"]) ~~ Optional[bracketedArgRef] ~~ ws,
    $lineBreakMark &
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
(* Walk forward from `pos` (1-indexed) skipping whitespace, then read
   one TeX argument: either a balanced `{...}` group (handles nested
   braces), a `\command` token, or a single non-brace character.
   Returns {argString, newPos}, or Missing[] if at end of input. *)
readArgToken[s_String, pos0_Integer] := Module[{
    n = StringLength[s], pos = pos0, ch, depth, start
},
    While[pos <= n && StringMatchQ[StringTake[s, {pos, pos}], WhitespaceCharacter],
        pos++
    ];
    If[pos > n, Return[Missing[]]];
    ch = StringTake[s, {pos, pos}];
    Which[
        (* balanced brace group *)
        ch === "{",
            depth = 1; start = pos; pos++;
            While[pos <= n && depth > 0,
                Switch[StringTake[s, {pos, pos}],
                    "{", depth++,
                    "}", depth--
                ];
                pos++
            ];
            If[depth =!= 0, Missing[], {StringTake[s, {start, pos - 1}], pos}],
        (* `\command` (letters) or single-char escape *)
        ch === "\\",
            start = pos; pos++;
            If[pos <= n && StringMatchQ[StringTake[s, {pos, pos}], LetterCharacter],
                While[pos <= n && StringMatchQ[StringTake[s, {pos, pos}], LetterCharacter],
                    pos++
                ],
                pos++
            ];
            {StringTake[s, {start, pos - 1}], pos},
        (* single non-brace character *)
        True,
            {ch, pos + 1}
    ]
]

(* `\frac{a}{b}` already has braces; wrap the unbraced shape. *)
ensureBraced[a_String] :=
    If[StringStartsQ[a, "{"], a, "{" <> a <> "}"]

(* readArgToken returns the arg as a literal substring; when it's a
   brace group, that substring is opaque and shorthand commands inside
   it won't have run through expandShorthand yet (the outer walker
   already jumped past).  Recurse into the contents so nested cases
   like `\overbrace{... \vec E ...}` get their inner accents braced. *)
expandShorthandInArg[a_String] := If[
    StringStartsQ[a, "{"] && StringEndsQ[a, "}"],
    "{" <> expandShorthand[StringTake[a, {2, StringLength[a] - 1}]] <> "}",
    a
]

(* Walk `s` left-to-right; whenever we see one of the registered
   short-arg command names, consume its required arg(s) (each a brace
   group, \command, or single char) and rewrite with explicit braces
   so the grammar's brace-only commandAtom sees a uniform shape. *)
$twoArgShortNames = {
    "frac", "tfrac", "dfrac", "cfrac",
    "binom", "tbinom", "dbinom",
    "overset", "underset", "stackrel",
    (* 2-arg styling commands accept single-token args too:
       `\colorbox{teal}{body}`, `\colorbox{teal}x`, `\color{red}{body}`,
       `\color{red}x`, `\textcolor{red}{body}`, `\textcolor{red}x`. *)
    "color", "textcolor", "colorbox"
}

$oneArgShortNames = {
    "sqrt",
    "hat", "widehat", "tilde", "widetilde", "bar", "vec",
    "dot", "ddot", "check", "breve", "acute", "grave", "mathring",
    "overline", "underline", "underbar",
    "overrightarrow", "overleftarrow",
    "overbrace", "underbrace",
    "mathbb", "mathcal", "mathfrak", "mathbf", "mathrm",
    "mathit", "mathsf", "mathsfit", "mathnormal", "mathtt", "mathscr",
    "boldsymbol", "pmb",
    "text", "textrm", "textbf", "textit", "texttt", "textsf",
    "textnormal", "emph",
    "operatorname",
    (* `\operatorname*` is preprocessed to this synthetic name in
       preprocessLaTeX so the bare-arg form `\operatornamestar x` is
       brace-wrapped just like `\operatorname x`. *)
    "operatornamestar",
    "smash", "boxed",
    "cancel", "bcancel", "xcancel", "sout",
    "pod", "pmod",
    "not"
}

$shortNameRegex = RegularExpression[
    "\\\\(" <> StringRiffle[Join[$twoArgShortNames, $oneArgShortNames], "|"] <>
    ")(?![a-zA-Z])"
]

(* Skip past an optional `[...]` bracketed arg (with balanced-bracket
   awareness for nested cases like `\sqrt[\sqrt[2]{4}]{16}`).  Returns
   `{"[...]", newPos}`, or `{"", pos}` if no `[` is next. *)
skipBracketedOpt[s_String, pos0_Integer] := Module[{
    n = StringLength[s], pos = pos0, depth, start
},
    While[pos <= n && StringMatchQ[StringTake[s, {pos, pos}], WhitespaceCharacter],
        pos++
    ];
    If[pos > n || StringTake[s, {pos, pos}] =!= "[",
        Return[{"", pos0}]
    ];
    depth = 1; start = pos; pos++;
    While[pos <= n && depth > 0,
        Switch[StringTake[s, {pos, pos}],
            "[", depth++,
            "]", depth--
        ];
        pos++
    ];
    {StringTake[s, {start, pos - 1}], pos}
]

expandShorthand[s_String] := Module[{
    n = StringLength[s], pos = 1, out = "",
    rel, abs, name, after, opt, a1, a2
},
    While[pos <= n,
        (* StringPosition[s, patt, 1] returns the FIRST occurrence in
           the whole string, not the first one at-or-after `pos`. Search
           the remainder explicitly so the loop advances past earlier
           matches we already processed. *)
        rel = StringPosition[StringTake[s, {pos, n}], $shortNameRegex,
            1, IgnoreCase -> False];
        If[ rel === {},
            out = out <> StringTake[s, {pos, n}]; pos = n + 1,
            Module[{p = First[rel]},
                abs = {p[[1]] + pos - 1, p[[2]] + pos - 1};
                out = out <> StringTake[s, {pos, abs[[1]] - 1}];
                name = StringTake[s, {abs[[1]] + 1, abs[[2]]}];   (* strip leading \ *)
                (* Preserve a `[...]` optional arg (e.g. `\sqrt[3]{27}`)
                   - the parser still reads it via `Optional[bracketedArgRef]`,
                   so we just skip past it without brace-wrapping. *)
                {opt, after} = skipBracketedOpt[s, abs[[2]] + 1];
                Which[
                    MemberQ[$twoArgShortNames, name],
                        a1 = readArgToken[s, after];
                        If[ a1 === Missing[],
                            out = out <> StringTake[s, {abs[[1]], n}]; pos = n + 1,
                            a2 = readArgToken[s, a1[[2]]];
                            If[ a2 === Missing[],
                                out = out <> "\\" <> name <> opt <>
                                    expandShorthandInArg @ ensureBraced[a1[[1]]];
                                pos = a1[[2]],
                                out = out <> "\\" <> name <> opt <>
                                    expandShorthandInArg @ ensureBraced[a1[[1]]] <>
                                    expandShorthandInArg @ ensureBraced[a2[[1]]];
                                pos = a2[[2]]
                            ]
                        ],
                    MemberQ[$oneArgShortNames, name],
                        a1 = readArgToken[s, after];
                        If[ a1 === Missing[],
                            out = out <> StringTake[s, {abs[[1]], n}]; pos = n + 1,
                            out = out <> "\\" <> name <> opt <>
                                expandShorthandInArg @ ensureBraced[a1[[1]]];
                            pos = a1[[2]]
                        ]
                ]
            ]
        ]
    ];
    out
]

(* TeX text-mode accents: `\'a`, `\"a`, `\.a`, `\`a`, `\=a`, `\~a`,
   `\^a` (and `\H{a}`, `\r{a}`, `\u{a}`, `\v{a}` letter variants
   handled by the letter-name shorthand pass). The next char (or `\i`
   / `\j`) is the accented letter. Rewrite to braced form so the
   accent handlers we registered above receive a proper arg. The
   StringExpression form is used because WL's regex-replacement
   string syntax has no clean way to put a literal `\` before a `$n`
   capture marker - `"\\$1"` makes `$1` literal, `"\\\\$1"` doubles
   the backslash. The pattern form names the captures directly. *)
$textAccentChars = "'" | "`" | "\"" | "." | "=" | "~" | "^"
$textAccentArg = ("\\" ~~ LetterCharacter ..) |
    ("\\" ~~ Except[LetterCharacter]) |
    Except["{" | "}" | WhitespaceCharacter]

(* Inside `\text{...}` only: substitute TeX's text-mode typographic
   conventions to Unicode - smart quotes, en/em-dashes, ellipsis.
   Outside `\text` these chars carry math meaning (`'` is prime, `-`
   is binary minus, ...) and are left alone. *)
(* Substitute typographic shorthand inside `\text{...}`. Use
   StringExpression with a lookbehind via `Except["\\"]` so we
   don't touch `\'`, `\``, `\"` etc. - those are text-mode accent
   commands the next pass picks up.

   Also convert each space to `~` (NBSP) so the math parser's ws
   consumer doesn't drop it - but ONLY when the space isn't part of
   a `\ ` (backslash-space) command; that's a literal-space escape
   and replacing the space breaks the accent-shorthand pass. *)
textModeSubstitute[s_String] := StringReplace[
    StringReplace[s,
        (* lookbehind via Except["\\"] - skip the space if it
           follows a backslash (then it's the `\ ` command, not a
           plain inter-word space). *)
        {a:Except["\\"] ~~ " " :> a <> "~",
         StartOfString ~~ " " :> "~"}
    ],
    {
    "---" -> "\[LongDash]",                  (* em-dash U+2014 *)
    "--"  -> "\[Dash]",                       (* en-dash U+2013 *)
    (* `` and '' opening/closing double quotes - and `, ' single
       quotes - only when NOT preceded by a backslash (which would
       mean they're a `\'` accent command, not a quote). *)
    a:Except["\\"] ~~ "``" :> a <> FromCharacterCode[8220],
    StartOfString ~~ "``" :> FromCharacterCode[8220],
    a:Except["\\"] ~~ "''" :> a <> FromCharacterCode[8221],
    StartOfString ~~ "''" :> FromCharacterCode[8221],
    a:Except["\\"] ~~ "`"  :> a <> FromCharacterCode[8216],
    StartOfString ~~ "`"  :> FromCharacterCode[8216],
    a:Except["\\"] ~~ "'"  :> a <> FromCharacterCode[8217],
    StartOfString ~~ "'"  :> FromCharacterCode[8217]
}]

(* Walk the source, find each `\text{...}` region (with balanced
   braces), apply textModeSubstitute inside. *)
applyTextModeSubstitutions[s_String] := Module[{
    n = StringLength[s], pos = 1, out = "", match, inner, after, depth, start
},
    While[pos <= n,
        match = StringPosition[StringTake[s, {pos, n}],
            RegularExpression["\\\\text(?:bf|it|tt|sf|rm|normal)?\\s*\\{"],
            1, IgnoreCase -> False];
        If[ match === {},
            out = out <> StringTake[s, {pos, n}]; pos = n + 1,
            Module[{p = First[match], absStart, braceStart},
                absStart = p[[1]] + pos - 1;
                braceStart = p[[2]] + pos - 1;   (* the `{` *)
                out = out <> StringTake[s, {pos, braceStart}];
                (* find matching close brace *)
                depth = 1; start = braceStart + 1; pos = start;
                While[pos <= n && depth > 0,
                    Switch[StringTake[s, {pos, pos}],
                        "{", depth++,
                        "}", depth--
                    ];
                    pos++
                ];
                If[depth =!= 0,
                    out = out <> StringTake[s, {start, n}]; pos = n + 1,
                    inner = StringTake[s, {start, pos - 2}];
                    out = out <> textModeSubstitute[inner] <> "}";
                ]
            ]
        ]
    ];
    out
]

(* Plain-TeX infix fractions: `{a \over b}` = `\frac{a}{b}`,
   `{a \atop b}` = vertical stack with no rule, `{a \brace b}` and
   `{a \brack b}` add curly / square delim wraps, `{a \above1.0pt b}`
   uses an explicit rule thickness.  KaTeX renders all of these as
   visible fractions / stacks; we'd otherwise leave `\over` etc as
   literal text in the output.

   Rewrite at the source level: walk each brace group, look for one of
   the infix tokens at the group's TOP level (skip nested braces), and
   if found, split the group content into num / denom and rewrite as
   the corresponding command.  Only the first match per group is
   rewritten (matching Plain TeX semantics - a single infix per group). *)
$infixFracMap = <|
    "\\over"  -> Function[{n, d}, "\\frac{" <> n <> "}{" <> d <> "}"],
    (* \atop, \brace, \brack: use direct \atopfrac / \bracefrac /
       \brackfrac shapes (custom commands we register below); they
       produce GridBox-based renders without the bare-delim
       brace-arg parsing issue that \genfrac{[}{]} would hit. *)
    "\\atop"  -> Function[{n, d}, "\\atopfrac{" <> n <> "}{" <> d <> "}"],
    "\\brace" -> Function[{n, d}, "\\bracefrac{" <> n <> "}{" <> d <> "}"],
    "\\brack" -> Function[{n, d}, "\\brackfrac{" <> n <> "}{" <> d <> "}"]
|>

(* Walk the source, find each balanced `{...}` group, see if it
   contains an infix-fraction token at TOP level (not nested in
   another `{...}`), and rewrite if so. Recurse so nested groups
   inside numerator / denominator get their own pass. *)
rewriteInfixFractions[s_String] := Module[{
    n = StringLength[s], pos = 1, out = "",
    depth, start, contents, infixPos, infixName, num, den, j, recursed
},
    While[pos <= n,
        If[ StringTake[s, {pos, pos}] =!= "{",
            out = out <> StringTake[s, {pos, pos}]; pos++,
            (* find matching close brace at the same depth *)
            depth = 1; start = pos + 1; j = start;
            While[j <= n && depth > 0,
                Switch[StringTake[s, {j, j}],
                    "{", depth++, "}", depth--
                ];
                j++
            ];
            If[depth =!= 0,  (* unbalanced - emit rest as-is and stop *)
                out = out <> StringTake[s, {pos, n}]; pos = n + 1,
                contents = StringTake[s, {start, j - 2}];
                (* find an infix token at TOP-level of `contents`
                   (depth tracker over `contents`). Use first hit only. *)
                Module[{cd = 0, ci = 1, cn = StringLength[contents], hit = Missing[]},
                    While[ci <= cn && MissingQ[hit],
                        Switch[StringTake[contents, {ci, ci}],
                            "{", cd++,
                            "}", cd--
                        ];
                        If[ cd === 0,
                            KeyValueMap[
                                Function[{key, fn},
                                    If[ MissingQ[hit] &&
                                            StringLength[contents] - ci + 1 >= StringLength[key] &&
                                            StringTake[contents, {ci, ci + StringLength[key] - 1}] === key &&
                                            (* boundary check: next char isn't a letter
                                               (so \overrightarrow isn't matched as \over) *)
                                            With[{afterPos = ci + StringLength[key]},
                                                afterPos > cn ||
                                                ! StringMatchQ[StringTake[contents, {afterPos, afterPos}], LetterCharacter]
                                            ],
                                        hit = {ci, key, fn}
                                    ]
                                ],
                                $infixFracMap
                            ]
                        ];
                        ci++
                    ];
                    If[ MissingQ[hit],
                        (* no infix - recurse into contents and emit *)
                        recursed = rewriteInfixFractions[contents];
                        out = out <> "{" <> recursed <> "}";
                        pos = j,
                        (* found infix - split, recurse each side *)
                        infixPos = hit[[1]];
                        infixName = hit[[2]];
                        num = StringTrim @ StringTake[contents, {1, infixPos - 1}];
                        den = StringTrim @ StringTake[contents,
                            {infixPos + StringLength[infixName], cn}];
                        out = out <> "{" <>
                            hit[[3]][rewriteInfixFractions[num], rewriteInfixFractions[den]] <>
                            "}";
                        pos = j
                    ]
                ]
            ]
        ]
    ];
    out
]

(* Plain-TeX font switches `\rm`/`\it`/`\bf`/`\sf`/`\tt` were
   noopHandlers - they just dropped on the floor. KaTeX renders them
   as font-style switches affecting the rest of the current group.
   Approximate: rewrite `\rm <word>` to `\mathrm{<word>}` etc., where
   <word> is up to the next whitespace, brace, or cell separator.
   Handles the common `\rm rm`, `\bf bf`, `\text{\it it}` patterns. *)
$oldFontMap = <|
    "rm" -> "mathrm", "it" -> "mathit", "bf" -> "mathbf",
    "sf" -> "mathsf", "tt" -> "mathtt"
|>
$oldFontRegex = RegularExpression[
    "\\\\(rm|it|bf|sf|tt)(?![a-zA-Z])\\s*([a-zA-Z0-9]+|\\\\[a-zA-Z]+)"
]
rewriteOldFontSwitches[s_String] :=
    StringReplace[s, $oldFontRegex :>
        "\\math$1{$2}"
    ]

(* `\begin{CD}...\end{CD}`: commutative-diagram environment with the
   `@`-prefixed arrow syntax (`@>label>`, `@<label<`, `@VlabelV`,
   `@AlabelA`, `@|`, `@=`, `@.`).  We approximate: rename `CD` to
   `matrix`, then globally collapse each `@`-spec to a Unicode arrow
   glyph (labels dropped). `@` is rare outside CD context so the
   global pass is safe in practice. *)
rewriteCDEnv[s_String] := StringReplace[
    StringReplace[s, {
        "\\begin{CD}" -> "\\begin{matrix}",
        "\\end{CD}"   -> "\\end{matrix}"
    }],
    {
        (* Empty / bare-arrow forms first so they don't steal labelled
           variants below.  Labelled variants use \xrightarrow /
           \xleftarrow / OverscriptBox to keep the label visible. *)
        RegularExpression["@>>>"]              -> "\[LongRightArrow]",
        RegularExpression["@<<<"]              -> "\[LongLeftArrow]",
        (* `@>X>>` -> label X above the right arrow *)
        RegularExpression["@>([^>]+)>>"]       :> ("\\xrightarrow{" <> "$1" <> "}"),
        (* `@>>X>` -> label X below the right arrow *)
        RegularExpression["@>>([^>]+)>"]       :> ("\\xrightarrow[" <> "$1" <> "]{}"),
        (* `@<X<<` -> label X above the left arrow *)
        RegularExpression["@<([^<]+)<<"]       :> ("\\xleftarrow{" <> "$1" <> "}"),
        (* `@<<X<` -> label X below the left arrow *)
        RegularExpression["@<<([^<]+)<"]       :> ("\\xleftarrow[" <> "$1" <> "]{}"),
        (* bare arrows with no label *)
        RegularExpression["@>>"]               -> "\[LongRightArrow]",
        RegularExpression["@<<"]               -> "\[LongLeftArrow]",
        RegularExpression["@>"]                -> "\[LongRightArrow]",
        RegularExpression["@<"]                -> "\[LongLeftArrow]",
        (* vertical arrows with labels: V<label>V (right), VV<label>V or
           V<label>VV (left).  We don't have a vertical-arrow-with-side-
           label box, so just stack the label above using OverscriptBox. *)
        RegularExpression["@VV([^V]+)V"]       :> ("\\overset{" <> "$1" <> "}{\\downarrow}"),
        RegularExpression["@AA([^A]+)A"]       :> ("\\overset{" <> "$1" <> "}{\\uparrow}"),
        RegularExpression["@V([^V]+)VV"]       :> ("\\overset{" <> "$1" <> "}{\\downarrow}"),
        RegularExpression["@A([^A]+)AA"]       :> ("\\overset{" <> "$1" <> "}{\\uparrow}"),
        RegularExpression["@V([^V]+)V"]        :> ("\\overset{" <> "$1" <> "}{\\downarrow}"),
        RegularExpression["@A([^A]+)A"]        :> ("\\overset{" <> "$1" <> "}{\\uparrow}"),
        (* bare vertical arrows *)
        RegularExpression["@VV"]               -> "\[DownArrow]",
        RegularExpression["@AA"]               -> "\[UpArrow]",
        RegularExpression["@V"]                -> "\[DownArrow]",
        RegularExpression["@A"]                -> "\[UpArrow]",
        "@|" -> "\[DoubleVerticalBar]",
        "@=" -> "=",
        "@." -> ""
    }
]

(* Catch any `\over` that survived the brace-walker (e.g. `1\over2`
   appearing directly between matrix cell separators, with no
   enclosing braces).  Limited to single-token operands - just enough
   for the corpus cases that show up.  Order: must run AFTER
   rewriteInfixFractions so we only see leftovers. *)
(* `\\over(?![a-zA-Z])` ensures we don't slice `\overrightarrow` /
   `\overline` / etc. into `\over` + suffix.  Same lookahead for
   `\atop`. *)
rewriteBareOver[s_String] :=
    StringReplace[s, {
        RegularExpression["([a-zA-Z0-9])\\s*\\\\over(?![a-zA-Z])\\s*([a-zA-Z0-9])"] :>
            "\\frac{$1}{$2}",
        RegularExpression["([a-zA-Z0-9])\\s*\\\\atop(?![a-zA-Z])\\s*([a-zA-Z0-9])"] :>
            "\\atopfrac{$1}{$2}"
    }]

(* `\above<dim>` is a custom-thickness variant of `\over`; FractionBox
   has no thickness knob so drop the dimension and treat as `\over`.
   Similarly `\abovewithdelims<l><r><dim>` and `\atopwithdelims<l><r>`
   - discard the delimiters and the dimen, keep the structure.  Done
   as a pre-pass before rewriteInfixFractions so the existing infix
   walker handles the result.  Dimen format covers the common units. *)
rewriteAboveAtopVariants[s_String] :=
    StringReplace[s, {
        (* \abovewithdelims <l><r><dim> -> \over, losing delims+dim *)
        RegularExpression[
            "\\\\abovewithdelims\\s*(?:\\\\[a-zA-Z]+|.)\\s*(?:\\\\[a-zA-Z]+|.)\\s*[0-9.]+\\s*(?:pt|em|ex|mm|cm|in|bp|pc|dd|cc|sp|mu)"
        ] -> "\\over",
        (* \atopwithdelims <l><r> -> \atop, losing delims *)
        RegularExpression[
            "\\\\atopwithdelims\\s*(?:\\\\[a-zA-Z]+|.)\\s*(?:\\\\[a-zA-Z]+|.)"
        ] -> "\\atop",
        (* \above <dim> -> \over, losing dim *)
        RegularExpression["\\\\above\\s*[0-9.]+\\s*(?:pt|em|ex|mm|cm|in|bp|pc|dd|cc|sp|mu)"] -> "\\over"
    }]

(* `\def\NAME<params>{body}` support.  Scan source for definitions,
   capture a parameter template (`#1#2...`), strip the definitions,
   then expand each `\NAME{a}{b}` call site by substituting args into
   the body.  Iterates a few times so a body that calls another user
   macro settles.  Parameter templates are minimal: just `#1#2...`
   with no inter-parameter delimiters (the common KaTeX-corpus form).

   defs[name] = {arity, body}; body holds literal `#1`/`#2`/... slots. *)
extractDefs[s_String] := Module[
    {n = StringLength[s], pos = 1, defs = <||>, out = "",
     j, depth, name, start, body, k, end, arity, ch},
    While[pos <= n,
        If[ StringTake[s, {pos, Min[pos + 4, n]}] === "\\def\\",
            j = pos + 5;
            start = j;
            While[j <= n && StringMatchQ[StringTake[s, {j, j}], LetterCharacter], j++];
            name = StringTake[s, {start, j - 1}];
            (* Parameter template: count `#1#2...#N` (must be sequential). *)
            arity = 0;
            While[ j + 1 <= n && StringTake[s, {j, j}] === "#" &&
                   StringTake[s, {j + 1, j + 1}] === ToString[arity + 1],
                arity++; j += 2
            ];
            While[j <= n && StringMatchQ[StringTake[s, {j, j}], WhitespaceCharacter], j++];
            If[j <= n && StringTake[s, {j, j}] === "{" && name =!= "",
                depth = 1; k = j + 1; end = k;
                While[end <= n && depth > 0,
                    ch = StringTake[s, {end, end}];
                    Switch[ch, "{", depth++, "}", depth--];
                    end++
                ];
                If[ depth === 0,
                    body = StringTake[s, {k, end - 2}];
                    defs[name] = {arity, body};
                    pos = end,
                    out = out <> StringTake[s, {pos, n}]; pos = n + 1
                ],
                out = out <> StringTake[s, {pos, j - 1}];
                pos = j
            ],
            out = out <> StringTake[s, {pos, pos}]; pos++
        ]
    ];
    {defs, out}
]

(* Substitute `#i` placeholders in body with the corresponding arg. *)
substituteMacroBody[body_String, args_List] := Module[{out = body},
    Do[
        out = StringReplace[out, "#" <> ToString[i] -> args[[i]]],
        {i, Length[args]}
    ];
    out
]

(* One-shot expansion of a single macro by name through the whole string.
   Hand-walked so we can pull `arity` balanced `{...}` arguments after
   each `\NAME` call site.  For arity-0 macros this degenerates to
   pure replacement; for parametric ones it grabs the args, substitutes,
   and emits the expanded text. *)
expandOneMacro[s_String, name_String, arity_Integer, body_String] := Module[
    {n = StringLength[s], pos = 1, out = "", nameLen = StringLength[name],
     after, j, k, depth, args, argStart, expanded, ch, abort},
    While[pos <= n,
        If[ pos + nameLen <= n &&
            StringTake[s, {pos, pos + nameLen}] === "\\" <> name &&
            (pos + nameLen + 1 > n ||
             !StringMatchQ[StringTake[s, {pos + nameLen + 1, pos + nameLen + 1}], LetterCharacter]),
            after = pos + nameLen + 1;
            j = after; args = {}; abort = False;
            Do[
                While[j <= n && StringMatchQ[StringTake[s, {j, j}], WhitespaceCharacter], j++];
                If[ j > n || StringTake[s, {j, j}] =!= "{",
                    abort = True; Break[]
                ];
                depth = 1; k = j + 1; argStart = k;
                While[k <= n && depth > 0,
                    ch = StringTake[s, {k, k}];
                    Switch[ch, "{", depth++, "}", depth--];
                    k++
                ];
                If[ depth =!= 0, abort = True; Break[]];
                AppendTo[args, StringTake[s, {argStart, k - 2}]];
                j = k,
                {arity}
            ];
            If[ abort,
                out = out <> StringTake[s, {pos, pos}]; pos++,
                expanded = If[arity === 0, body, substituteMacroBody[body, args]];
                out = out <> expanded;
                pos = j
            ],
            out = out <> StringTake[s, {pos, pos}]; pos++
        ]
    ];
    out
]

(* Iterate macro expansion to a small fixed point. *)
expandUserMacros[s_String, defs_Association] := Module[{cur = s, prev, n = 8},
    While[n > 0,
        prev = cur;
        KeyValueMap[
            Function[{name, spec},
                cur = expandOneMacro[cur, name, spec[[1]], spec[[2]]]
            ],
            defs
        ];
        If[cur === prev, n = 0, n--]
    ];
    cur
]

applyUserDefs[s_String] := Module[{defs, stripped},
    {defs, stripped} = extractDefs[s];
    expandUserMacros[stripped, defs]
]

(* TeX `\color{X}` switches the current group's color for the
   REST of the group - it's a scoping switch, not a 2-arg command.
   Our grammar treats it as zero/one/two-arg form via the greedy
   command parser, which loses the scope.  Walk every balanced
   `{...}`, find the first top-level `\color{...}`, and rewrite
   `{prefix \color{X} suffix}` to
   `{prefix \textcolor{X}{recurse(suffix)}}`.  Recurse on the
   suffix so multiple `\color` switches in the same group chain
   correctly (`\color{red}red\color{blue}blue` -> red text then
   blue text). *)
rewriteScopedColor[s_String] := Module[{
    n = StringLength[s], pos = 1, out = "",
    depth, start, contents, j, ch, rewritten, colorPos, colorEnd, colorArg,
    argStart, argDepth, k, prefix, suffix
},
    While[pos <= n,
        If[ StringTake[s, {pos, pos}] =!= "{",
            out = out <> StringTake[s, {pos, pos}]; pos++,
            depth = 1; start = pos + 1; j = start;
            While[j <= n && depth > 0,
                Switch[StringTake[s, {j, j}], "{", depth++, "}", depth--];
                j++
            ];
            If[ depth =!= 0,
                out = out <> StringTake[s, {pos, n}]; pos = n + 1,
                contents = StringTake[s, {start, j - 2}];
                (* Look for the leftmost top-level `\color{...}` inside
                   contents.  Top-level means depth-0 (not nested in
                   another `{...}`). *)
                colorPos = 0;
                Module[{cd = 0, ci = 1, cn = StringLength[contents], hit = 0},
                    While[ci <= cn && hit === 0,
                        ch = StringTake[contents, {ci, ci}];
                        Switch[ch, "{", cd++, "}", cd--];
                        If[ cd === 0 && ci + 6 <= cn &&
                            StringTake[contents, {ci, ci + 6}] === "\\color{",
                            hit = ci
                        ];
                        ci++
                    ];
                    colorPos = hit
                ];
                If[ colorPos === 0,
                    out = out <> "{" <> rewriteScopedColor[contents] <> "}";
                    pos = j,
                    (* find matching } of the `\color{...}` arg *)
                    argStart = colorPos + 7; (* after `\color{` *)
                    argDepth = 1; k = argStart;
                    While[k <= StringLength[contents] && argDepth > 0,
                        ch = StringTake[contents, {k, k}];
                        Switch[ch, "{", argDepth++, "}", argDepth--];
                        k++
                    ];
                    If[ argDepth =!= 0,
                        (* malformed; emit as-is *)
                        out = out <> "{" <> rewriteScopedColor[contents] <> "}";
                        pos = j,
                        colorArg = StringTake[contents, {argStart, k - 2}];
                        prefix = StringTake[contents, {1, colorPos - 1}];
                        suffix = StringTake[contents,
                            {k, StringLength[contents]}];
                        rewritten = prefix <> "\\textcolor{" <> colorArg <>
                            "}{" <> rewriteScopedColor[suffix] <> "}";
                        out = out <> "{" <> rewriteScopedColor[rewritten] <> "}";
                        pos = j
                    ]
                ]
            ]
        ]
    ];
    out
]

(* TeX scopes size and style switches (\Huge, \rm, \displaystyle, ...)
   to the enclosing brace group: `{\Huge body more body}` means
   "the rest of THIS group is huge".  Our grammar treats those
   switches as ordinary commands that eat exactly one `{...}` arg.
   So `{\Huge body}` becomes `\Huge` (no arg -> "") followed by
   `body` (loose) and the size silently dropped.  Pre-scan: find
   every `{<sizeOrStyleSwitch> <rest>}` and rewrite to
   `{<switch>{<rest>}}` so the switch ends up with a single
   brace-group arg carrying the whole rest of the group. *)
$scopedSwitchNames = {
    "tiny", "scriptsize", "footnotesize", "small", "normalsize",
    "large", "Large", "LARGE", "huge", "Huge",
    "textstyle", "displaystyle", "scriptstyle", "scriptscriptstyle",
    "it", "bf", "rm", "sf", "tt", "sl", "em"
}
$scopedSwitchRegex = RegularExpression[
    "\\\\(" <> StringRiffle[$scopedSwitchNames, "|"] <> ")(?![a-zA-Z])"
]
rewriteGroupScopedSwitches[s_String] := Module[{
    n = StringLength[s], pos = 1, out = "",
    depth, start, contents, j, m, sname, before, after, inner
},
    While[pos <= n,
        If[ StringTake[s, {pos, pos}] =!= "{",
            out = out <> StringTake[s, {pos, pos}]; pos++,
            depth = 1; start = pos + 1; j = start;
            While[j <= n && depth > 0,
                Switch[StringTake[s, {j, j}], "{", depth++, "}", depth--];
                j++
            ];
            If[ depth =!= 0,
                out = out <> StringTake[s, {pos, n}]; pos = n + 1,
                contents = StringTake[s, {start, j - 2}];
                m = Null;
                Module[{
                    trimmed = StringDelete[contents,
                        StartOfString ~~ WhitespaceCharacter ...],
                    hit, restPos
                },
                    hit = StringPosition[trimmed, $scopedSwitchRegex, 1];
                    If[ hit =!= {} && First[hit][[1]] === 1,
                        sname = StringTake[trimmed, First[hit]];
                        restPos = First[hit][[2]] + 1;
                        inner = StringTrim @ StringDrop[trimmed, First[hit][[2]]];
                        If[ inner === "",
                            (* nothing to wrap; leave alone *)
                            out = out <> "{" <> rewriteGroupScopedSwitches[contents] <> "}";
                            pos = j,
                            out = out <> "{" <> sname <> "{" <>
                                rewriteGroupScopedSwitches[inner] <> "}}";
                            pos = j
                        ],
                        out = out <> "{" <> rewriteGroupScopedSwitches[contents] <> "}";
                        pos = j
                    ]
                ]
            ]
        ]
    ];
    out
]

preprocessLaTeX[s_String] :=
    expandShorthand @
    StringReplace[#,
        "\\" ~~ c:$textAccentChars ~~ WhitespaceCharacter ... ~~
            x:$textAccentArg :> "\\" <> c <> "{" <> x <> "}"
    ] &@
    applyTextModeSubstitutions @
    rewriteBareOver @
    rewriteInfixFractions @
    rewriteAboveAtopVariants @
    rewriteOldFontSwitches @
    rewriteCDEnv @
    applyUserDefs @
    (* The grammar's commandName matches `\` + letters or `\` + one
       punctuation char, so `\operatorname*` would parse as the
       command `\operatorname` followed by a bare `*` and the `*`
       leaks into the surrounding row.  Rewrite to a synthetic name
       with the `*` absorbed; commandHandlers["\\operatornamestar"]
       picks it up. *)
    StringReplace[#, RegularExpression["\\\\operatorname\\*"] -> "\\operatornamestar"] &@
    (* TeX-form unbraced length args: `\kern1em`, `\mkern18mu`,
       `\hskip 3pt`, `\rule{2em}{1em}` already has braces and is
       fine.  Wrap the dimension in braces so the command parser
       grabs it as the required arg instead of leaving `1em` as
       loose literal text. *)
    StringReplace[#,
        RegularExpression[
            "\\\\(kern|mkern|hskip|mskip|hspace|vspace)\\s*" <>
            "(-?[0-9]*\\.?[0-9]+\\s*(?:pt|em|ex|mm|cm|in|bp|pc|dd|cc|sp|mu))"
        ] :> ("\\" <> "$1" <> "{" <> "$2" <> "}")
    ] &@
    (* `\verb<delim>content<delim>` and `\verb*<delim>content<delim>`
       are verbatim macros - the next non-letter, non-space, non-asterisk
       character after `\verb` or `\verb*` becomes the delimiter, and
       content is read raw until the matching delimiter.  Approximate
       by rewriting to `\texttt{content}`.  Only handle a fixed set
       of common delimiters (`|`, `!`, `+`, `=`, `/`) - the
       space-delimited form would interact with whitespace-stripping
       elsewhere, so we leave it as a literal.  Done as a preprocess
       so the rest of the pipeline sees a regular `\texttt{...}`. *)
    StringReplace[#, {
        RegularExpression["\\\\verb\\*([|!+=/])([^|!+=/]*?)\\1"] :>
            ("\\texttt{" <> "$2" <> "}"),
        RegularExpression["\\\\verb([|!+=/])([^|!+=/]*?)\\1"] :>
            ("\\texttt{" <> "$2" <> "}")
    }] &@
    (* TeX size / style switches scope to the END of the current
       brace group, but our grammar treats them as commands that
       eat just ONE following `{...}` arg.  Rewrite `{\Huge body}`
       to `{\Huge{body}}` so the switch ends up with a single
       brace-group argument carrying the whole rest of the group. *)
    rewriteGroupScopedSwitches @
    rewriteScopedColor @
    StringReplace[s, {
        (* \big / \Big / \bigg / \Bigg (+ l/r/m variants) are
           delimiter-SIZING macros.  Keep the delimiter AND its size:
           rewrite `\Big(` -> `\xbigII{(}`, routed to the sized-delimiter
           handler (ratios 1.2 / 1.8 / 2.4 / 3.0).  `\middle` keeps its
           delimiter unsized.  The `.` null delimiter maps to nothing.
           An unmatched opener like `\big(` alone in a script renders via
           the grammar's bare-delimiter fallback (outerPuncToken); a
           matched `\bigl( .. \bigr)` becomes two sized standalone
           glyphs around the content.  Longer macro names backtrack
           correctly because the delimiter class excludes letters. *)
        RegularExpression[
            "\\\\(?:big|bigl|bigr|bigm|Big|Bigl|Bigr|Bigm|bigg|biggl|biggr|biggm|Bigg|Biggl|Biggr|Biggm|middle)\\s*\\."
        ] -> "",
        RegularExpression[
            "\\\\(?:big|bigl|bigr|bigm)\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|/])"
        ] -> "\\xbigI{$1}",
        RegularExpression[
            "\\\\(?:Big|Bigl|Bigr|Bigm)\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|/])"
        ] -> "\\xbigII{$1}",
        RegularExpression[
            "\\\\(?:bigg|biggl|biggr|biggm)\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|/])"
        ] -> "\\xbigIII{$1}",
        RegularExpression[
            "\\\\(?:Bigg|Biggl|Biggr|Biggm)\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|/])"
        ] -> "\\xbigIV{$1}",
        RegularExpression[
            "\\\\middle\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|/])"
        ] -> "$1",
        RegularExpression[
            "\\\\(?:big|bigl|bigr|bigm|Big|Bigl|Bigr|Bigm|bigg|biggl|biggr|biggm|Bigg|Biggl|Biggr|Biggm|middle)(?![a-zA-Z])"
        ] -> ""
    }]

(* Post-process: the big-operator characters (Σ, Π, ∫, ∮, ∐, ⋃, ⋂, ⋁,
   ⋀, ⨁, ⨂, ⨆, ∏) render with their `_low`/`^hi` indices STACKED in
   display-style math (KaTeX default). The parser turns
   `\sum_{i=0}^n` into `SubsuperscriptBox[Σ, i=0, n]` which places
   the indices to the right - matching `\nolimits` behaviour but not
   what KaTeX shows on screen. Convert to `UnderoverscriptBox` so
   the FE stacks them. *)
(* Integrals (∫ ∮ ∬ ...) stack their bounds above/below here too.  TeX/KaTeX
   default to side bounds (\nolimits) for the integral family, but stacked
   bounds read better in this paclet's display output, so the integral glyphs
   are included.  The multi-integral strings (\iint -> two glyphs, etc.) are
   listed explicitly since the rule matches the SubsuperscriptBox base string. *)
$bigOpChars = {
    "\[Sum]", "\[Product]",
    "\[Coproduct]", "\[Union]", "\[Intersection]", "\[Vee]", "\[Wedge]",
    "\[CirclePlus]", "\[CircleTimes]", "\[SquareUnion]",
    "\[Integral]", "\[ContourIntegral]",
    "\[Integral]\[Integral]", "\[Integral]\[Integral]\[Integral]",
    "\[ContourIntegral]\[ContourIntegral]", "\[ContourIntegral]\[ContourIntegral]\[ContourIntegral]"
}

(* Chars that get used as the "decoration" overscript for `\overbrace`,
   `\overrightarrow`, `\overline`, `\overbracket`, `\overgroup`,
   `\overlinesegment`, the various `\overharpoon` variants - and their
   under-prefixed siblings. When the parser sees `\overbrace{X}^Y`,
   it produces `SuperscriptBox[OverscriptBox[X, deco], Y]` - which
   the FE renders as Y as a normal post-superscript NEXT TO the brace,
   not as a label ABOVE the brace. KaTeX puts Y above the decoration;
   convert to nested OverscriptBox so the label stacks. *)
$overDecoChars = {
    "\[OverBrace]", "\[OverBracket]",
    "\[RightArrow]", "\[LeftArrow]", "\[LeftRightArrow]",
    "\[LongRightArrow]", "\[LongLeftArrow]", "\[LongLeftRightArrow]",
    "_"
}
$underDecoChars = {
    "\[UnderBrace]", "\[UnderBracket]",
    "\[RightArrow]", "\[LeftArrow]", "\[LeftRightArrow]",
    "~", "_"
}

(* Named operators that stack their bounds in display style, exactly
   like the big-op chars: \lim, \max, \sup, \det, ... (but NOT \sin,
   \cos, \log, ... which keep side scripts).  These reach the box tree
   as StyleBox[name, FontSlant -> "Plain"] from the upright-operator
   handler; promote their Sub/Super/Subsuper to Under/Over/Underover so
   `\lim_{x\to0}` stacks the bound underneath instead of trailing it to
   the side (which rendered ~2x too wide vs. real LaTeX). *)
$limitsOpNames = {
    "lim", "limsup", "liminf", "max", "min", "sup", "inf",
    "det", "gcd", "Pr", "arg", "injlim", "projlim",
    "varlimsup", "varliminf", "varinjlim", "varprojlim"
}
limitsOpQ[StyleBox[n_String, FontSlant -> "Plain"]] := MemberQ[$limitsOpNames, n]
limitsOpQ[_] := False

bigOpDisplayLimits[boxes_] := boxes //. {
    SubsuperscriptBox[c_String /; MemberQ[$bigOpChars, c], lo_, hi_] :>
        UnderoverscriptBox[c, lo, hi],
    SubscriptBox[c_String /; MemberQ[$bigOpChars, c], lo_] :>
        UnderscriptBox[c, lo],
    SuperscriptBox[c_String /; MemberQ[$bigOpChars, c], hi_] :>
        OverscriptBox[c, hi],
    (* limits-operator names: same stacking promotion *)
    SubsuperscriptBox[op_ /; limitsOpQ[op], lo_, hi_] :> UnderoverscriptBox[op, lo, hi],
    SubscriptBox[op_ /; limitsOpQ[op], lo_] :> UnderscriptBox[op, lo],
    SuperscriptBox[op_ /; limitsOpQ[op], hi_] :> OverscriptBox[op, hi],
    (* `\overbrace{X}^Y`: stack Y above the brace above X. *)
    SuperscriptBox[OverscriptBox[x_, deco_String], hi_] /;
        MemberQ[$overDecoChars, deco] :>
            OverscriptBox[OverscriptBox[x, deco], hi],
    (* `\underbrace{X}_Y`: stack Y below the brace below X. *)
    SubscriptBox[UnderscriptBox[x_, deco_String], lo_] /;
        MemberQ[$underDecoChars, deco] :>
            UnderscriptBox[UnderscriptBox[x, deco], lo]
}

(* Math-mode comma is `,` + thin space, which reads as a list/tuple
   separator (`(a, b, c)`).  But inside a numeric grouping like
   `1,000,000` (or its `\!`-bridged variant) the thin space looks
   like literal whitespace between digit runs.  Walk every RowBox and
   drop the thin space whenever the comma sits between digit-only
   runs - skipping any empty-string siblings between them so the
   `\!` no-op doesn't break the detection. *)
$commaThinSpace = "," <> FromCharacterCode[8201]
digitRunQ[s_String] := s =!= "" && StringMatchQ[s, DigitCharacter ..]

(* Bare digit-run check: pure decimal token, not a RowBox or anything
   styled.  Used to detect `1,000,000`-style numeric groupings; we
   stay conservative because `\{1, 2\}` (set literal) also has digit
   siblings around the comma but should KEEP the thin space. *)
bareDigitRunQ[s_String] := s =!= "" && StringMatchQ[s, DigitCharacter ..]
bareDigitRunQ[_] := False

(* Empty-string children get inserted by no-op handlers (e.g. `\!`,
   `\,`) and end up wrapped in a sibling RowBox like
   `RowBox[{"", "000"}]`.  Unwrap any RowBox whose only non-empty
   child is a single element, and drop bare "" entries from larger
   RowBoxes, so neighbour-based postprocessors (digit-comma below,
   bigOpDisplayLimits above) see contiguous tokens. *)
stripEmptyRowChildren[boxes_] := boxes //. {
    RowBox[{a_, ""}] :> a,
    RowBox[{"", a_}] :> a,
    RowBox[parts_List] /; MemberQ[parts, ""] :>
        With[{filtered = DeleteCases[parts, ""]},
            If[Length[filtered] === 1, First[filtered], RowBox[filtered]]
        ]
}

(* Detect digit-run, comma-thinspace, digit-run, ... patterns in a
   RowBox and collapse them into a SINGLE string token
   "1,000,000". Done as one string because the FE inserts visible
   gaps around standalone "," tokens in math context (it treats them
   as list punctuation), even if our string has no embedded space. *)
collapseDigitCommaRun[parts_List] := Module[
    {n = Length[parts], i = 1, out = {}, start, joined, k},
    While[i <= n,
        If[ StringQ[parts[[i]]] && bareDigitRunQ[parts[[i]]],
            (* try to grow a digit, "," <thin>, digit, ... run *)
            start = i; k = i;
            While[ k + 2 <= n &&
                   parts[[k + 1]] === $commaThinSpace &&
                   StringQ[parts[[k + 2]]] && bareDigitRunQ[parts[[k + 2]]],
                k += 2
            ];
            If[ k > start,
                joined = StringJoin @ Table[
                    If[ OddQ[m - start + 1], parts[[m]], "," ],
                    {m, start, k}
                ];
                AppendTo[out, joined],
                AppendTo[out, parts[[i]]]
            ];
            i = k + 1,
            AppendTo[out, parts[[i]]]; i++
        ]
    ];
    out
]

suppressCommaSpaceBetweenDigits[boxes_] := boxes //. {
    RowBox[parts_List] /; AnyTrue[parts, # === $commaThinSpace &] :>
        With[{collapsed = collapseDigitCommaRun[parts]},
            If[Length[collapsed] === 1, First[collapsed], RowBox[collapsed]]
        ]
}

(* Commas inside sub/superscripts (`a_{i,j}`, `x^{m,n}`) should hug -
   KaTeX sets a tight comma at script size.  Our math comma carries a
   trailing thin space (right for a top-level tuple `(a, b, c)`), which
   at script size reads as a wide gap.  Strip the thin space from comma
   tokens that live inside a script argument only; top-level tuples keep
   their spacing.  (//. reaches a fixed point in one rewrite since the
   strip is idempotent.) *)
tightenScriptCommas[boxes_] := boxes //. {
    SubscriptBox[b_, s_] :> SubscriptBox[b, s /. $commaThinSpace -> ","],
    SuperscriptBox[b_, s_] :> SuperscriptBox[b, s /. $commaThinSpace -> ","],
    SubsuperscriptBox[b_, s1_, s2_] :>
        SubsuperscriptBox[b, s1 /. $commaThinSpace -> ",", s2 /. $commaThinSpace -> ","]
}

(* Convert top-level / nested `\\` line breaks (carried as
   $lineBreakMark) into a stacked single-column GridBox, so multi-line
   display math like the BoldSymbol corpus case renders on separate
   lines instead of running together.  Bottom-up via //. so a RowBox
   that becomes a GridBox doesn't re-trigger.  A trailing `\\` leaves a
   final empty segment; drop it (LaTeX tolerates the trailing
   separator), mirroring buildEnv's trailing-row handling. *)
applyLineBreaks[boxes_] := boxes //. {
    RowBox[parts_List] /; MemberQ[parts, $lineBreakMark] :>
        Module[{rows = lineBreakSegments[RowBox[parts]]},
            While[Length[rows] > 1 && MatchQ[Last[rows], "" | " "],
                rows = Most[rows]
            ];
            If[Length[rows] === 1, First[rows], GridBox[List /@ rows]]
        ]
}

(* ===== precompiled-parser asset =====
   ParserCompile[LaTeXMathParser, Method -> "PEGVM"] is shipped as a paclet
   Asset (<|"Hash" -> Hash[LaTeXMathParser], "Parser" -> compiled|>). On
   first use LaTeXMathParse loads it IF the stored hash matches the current
   grammar's hash - so a stale asset (grammar changed since it was built) is
   ignored and we fall back to the interpreter. Rebuild with
   BuildLaTeXParserAsset[]. *)

$latexDir = DirectoryName[$InputFileName]

compiledLatexAssetPath[] := Module[{p},
    p = Quiet @ Check[
        PacletObject["Wolfram/Parser"]["AssetLocation", "CompiledLaTeXParser"], $Failed];
    If[StringQ[p] && FileExistsQ[p], p,
        FileNameJoin[{ParentDirectory[$latexDir], "Assets", "LaTeXMathParserCompiled.wxf"}]]]

(* memoised: the compiled parser when the asset is present and current,
   else $Failed (interpretive fallback). The asset stores only the grammar
   hash and the PEG-VM instruction data; the runnable "Code" is rebuilt
   here with the current pegCodeFn, so changes to the VM/codegen never
   staleify a shipped asset - only a grammar change (caught by the hash)
   invalidates it. *)
$compiledLatexCache = "unset"   (* cache var (not a memoised downvalue, so it can be reset without deleting the definition) *)
loadCompiledLatexParser[] := (
    If[$compiledLatexCache === "unset",
        $compiledLatexCache = Module[{path = compiledLatexAssetPath[], stored, lpc = LaTeXMathParser},
            If[StringQ[path] && FileExistsQ[path],
                stored = Quiet @ Check[Uncompress[Import[path]], $Failed];
                If[AssociationQ[stored] && stored["Hash"] === Hash[lpc],
                    ParserCombinator[lpc[[1]], lpc[[2]],
                        Append[lpc[[3]], "Code" -> Wolfram`Parser`Private`pegCodeFn[stored["Data"]]]],
                    $Failed],
                $Failed]]];
    $compiledLatexCache)

activeLatexParser[] := With[{c = loadCompiledLatexParser[]}, If[c === $Failed, LaTeXMathParser, c]]

(* build (or rebuild) the asset from the current grammar: just the grammar
   hash + the PEG-VM instruction data (Prog/Classes/ClassPats/Spec),
   Compress'd (the tables are large but compress well). *)
BuildLaTeXParserAsset[] := Module[{data, path},
    data = Wolfram`Parser`Private`pegCompile[LaTeXMathParser];
    path = FileNameJoin[{ParentDirectory[$latexDir], "Assets", "LaTeXMathParserCompiled.wxf"}];
    If[! DirectoryQ[DirectoryName[path]], CreateDirectory[DirectoryName[path]]];
    Export[path, Compress[<|"Hash" -> Hash[LaTeXMathParser], "Data" -> data|>], "WXF"];
    $compiledLatexCache = "unset";   (* reset cache so the next call reloads *)
    path]

(* The PEGVM-compiled parser lowers char classes (LetterCharacter, the
   unicodeReservedQ predicate behind unicodeAtom) to ASCII-only ranges, so a
   raw non-ASCII atom - Unicode Greek (alpha, the variant forms epsilon/theta/
   phi), math symbols (\[DoubleRightArrow], \[PartialD], \[Ellipsis]),
   math-alphanumerics, accented or CJK letters - makes the whole parse fail
   even though the *interpreted* grammar (identAtom / unicodeAtom) handles it.
   So route any input carrying a non-ASCII codepoint to the interpreter; the
   common pure-ASCII case keeps the fast compiled path.  (A faithful PEGVM
   Unicode char-class lowering would let this fall away.) *)
$nonASCIIQ = StringContainsQ[#, RegularExpression["[^\\x00-\\x7F]"]] &
latexParserFor[pre_String] := If[$nonASCIIQ[pre], LaTeXMathParser, activeLatexParser[]]

(* === Dirac bra/ket -> system Ket/Bra/BraKet templates ===
   The active Dirac delimiters come out as StyleBox[char, SpanMaxSize -> 1]
   (fixedFence), which never engage the front end's stretchy-delimiter
   machinery, so bars/angles draw at nominal glyph height and sit detached.
   Rewrite them to the self-contained system templates (TemplateBox[{...},
   "Ket"|"Bra"|"BraKet"]), which render full-height and stretchy on the stock
   Default.nb stylesheet with no extra load. The reliable Dirac marker is a
   SpanMaxSize *angle*: ket, bra, braket and the expectation <X> all carry one,
   while abs / norm / set-builder / conditional never do - so anchoring on the
   angle leaves those untouched. *)
$diracBar  = "|" | "\[LeftBracketingBar]" | "\[RightBracketingBar]"
$diracLAng = "\[LeftAngleBracket]" | "<"
$diracRAng = "\[RightAngleBracket]" | ">"
$diracBareBar = "\[LeftBracketingBar]" | "\[RightBracketingBar]"
$diracSpacer = "\[ThinSpace]" | "\[VeryThinSpace]" | "\[MediumSpace]" |
    "\[ThickSpace]" | "\[NegativeThinSpace]" | "\[NegativeVeryThinSpace]" |
    "\[NegativeMediumSpace]" | "\[NegativeThickSpace]" | " "
$diracBarSB  = StyleBox[$diracBar,  SpanMaxSize -> 1, ___]
$diracLAngSB = StyleBox[$diracLAng, SpanMaxSize -> 1, ___]
$diracRAngSB = StyleBox[$diracRAng, SpanMaxSize -> 1, ___]
$diracNoDelim = Except[$diracBarSB | $diracLAngSB | $diracRAngSB | $diracBareBar | $diracSpacer]
(* a Dirac delimiter, bare or carrying a script (a closing bar/angle picks up a
   power or label via the #26 grammar fix, e.g. `<1|^2`, `|psi>_{AB}`) *)
diracSpanAngleQ[e_] := MatchQ[e, $diracLAngSB | $diracRAngSB |
    (SubscriptBox | SuperscriptBox | SubsuperscriptBox)[$diracLAngSB | $diracRAngSB, ___]]
diracBarQ[e_] := MatchQ[e, $diracBarSB | $diracBareBar |
    (SubscriptBox | SuperscriptBox | SubsuperscriptBox)[$diracBarSB, ___]]
diracNormalize[RowBox[{}]] := ""
diracNormalize[RowBox[{e_}]] := e
diracNormalize[o_] := o

(* flatten nested rows and drop spacing glyphs, but only inside a row that holds
   BOTH a Dirac angle and a bar - i.e. an actual bra/ket. An inner product
   <a,b> or an expectation <X> (angle, no bar), and abs / norm / set-builder /
   conditional, stay untouched. *)
$diracFlatten = RowBox[{p___, RowBox[{q___}], r___}] /;
    AnyTrue[{p, q, r}, diracSpanAngleQ] && AnyTrue[{p, q, r}, diracBarQ] :> RowBox[{p, q, r}]
$diracStripSpace = RowBox[l_List] /;
    (AnyTrue[l, diracSpanAngleQ] && AnyTrue[l, diracBarQ] && MemberQ[l, $diracSpacer]) :>
        RowBox[DeleteCases[l, $diracSpacer]]

(* sandwich + braket before ket/bra *)
$diracRules = {
    RowBox[{pre___, $diracLAngSB, a:$diracNoDelim.., $diracBareBar, mid:$diracNoDelim.., $diracBareBar, b:$diracNoDelim.., $diracRAngSB, post___}] :>
        RowBox[{pre, TemplateBox[{diracNormalize[RowBox[{a}]]}, "Bra"], mid, TemplateBox[{diracNormalize[RowBox[{b}]]}, "Ket"], post}],
    RowBox[{pre___, $diracLAngSB, a:$diracNoDelim.., $diracBarSB, b:$diracNoDelim.., $diracRAngSB, post___}] :>
        RowBox[{pre, TemplateBox[{diracNormalize[RowBox[{a}]], diracNormalize[RowBox[{b}]]}, "BraKet"], post}],
    (* ket / bra carrying a script on the closing delimiter: a power on the
       ket (`|0>^{\otimes n}`) or a subsystem label on it (`|\psi>_{AB}`), and
       likewise a script on a bra's closing bar (`<1|^2`). The #26 grammar fix
       puts the script on the delimiter; lift it onto the whole template. *)
    RowBox[{pre___, $diracBarSB, x:$diracNoDelim.., (h:SuperscriptBox|SubscriptBox)[$diracRAngSB, scr_], post___}] :>
        RowBox[{pre, h[TemplateBox[{diracNormalize[RowBox[{x}]]}, "Ket"], scr], post}],
    RowBox[{pre___, $diracBarSB, x:$diracNoDelim.., $diracRAngSB, post___}] :>
        RowBox[{pre, TemplateBox[{diracNormalize[RowBox[{x}]]}, "Ket"], post}],
    RowBox[{pre___, $diracLAngSB, x:$diracNoDelim.., (h:SuperscriptBox|SubscriptBox)[$diracBarSB, scr_], post___}] :>
        RowBox[{pre, h[TemplateBox[{diracNormalize[RowBox[{x}]]}, "Bra"], scr], post}],
    RowBox[{pre___, $diracLAngSB, x:$diracNoDelim.., $diracBarSB, post___}] :>
        RowBox[{pre, TemplateBox[{diracNormalize[RowBox[{x}]]}, "Bra"], post}]
}
$diracCollapse = RowBox[{e:(_TemplateBox | _SuperscriptBox | _SubscriptBox)}] :> e

(* force the amplitude modulus bars to full span, but only when they wrap a
   Dirac template, so a plain |x| keeps its bare bars *)
$diracModBarSpan = 1.9
$diracModulusRule = RowBox[{first:$diracBareBar, mid__, last:$diracBareBar}] /;
    ! FreeQ[{mid}, TemplateBox[_, "Ket" | "Bra" | "BraKet"]] :>
    RowBox[{StyleBox[first, SpanMinSize -> $diracModBarSpan], mid, StyleBox[last, SpanMinSize -> $diracModBarSpan]}]

diracTemplates[boxes_] := Module[{b = boxes},
    b = b //. $diracFlatten;
    b = b //. $diracStripSpace;
    b = b //. $diracRules;
    b = b //. $diracCollapse;
    b /. $diracModulusRule
]

LaTeXMathParse[source_String] := Module[
    {pre = preprocessLaTeX[source], r},
    r = Parse[latexParserFor[pre], pre];
    If[FailureQ[r], r,
        (* `/. $lineBreakMark -> ""` is a safety net: a stray marker not
           inside a RowBox (e.g. the whole input was just `\\`) would
           otherwise leak the private symbol into output. *)
        diracTemplates @ uprightUnicodeSymbols @ suppressCommaSpaceBetweenDigits @ tightenScriptCommas @
            stripEmptyRowChildren @ applyLineBreaks @ bigOpDisplayLimits[r] /. $lineBreakMark -> ""
    ]
]


(* === LaTeXMathStyle: give parser output a Computer-Modern look ===
   The parser is font-agnostic - identifiers are tagged StyleBox[_, "TI"] (the
   FE's default Times-based math italic).  This restyles that into the
   Computer-Modern look LaTeX/MaTeX produces.  An OpenType *math* font (Latin
   Modern Math) carries the cmmi math-italic letterforms at the
   math-alphanumeric codepoints, not via FontSlant, so for it each italic letter
   is remapped to its codepoint; a text font (Latin Modern Roman / CMU Serif)
   just gets FontSlant -> Italic.  Double-struck \mathbb has its own font: when
   MSBM10.otf is installed (AMS msbm converted to OpenType, see dev/
   make-msbm-otf.py) blackboard letters render in it to match real LaTeX. *)
$cmFontDirs := {FileNameJoin[{$HomeDirectory, "Library", "Fonts"}], "/Library/Fonts", "/System/Library/Fonts"}
(* memoized - installed fonts don't change within a session *)
detectMathFont[] := detectMathFont[] = Which[
    FileNames["latinmodern-math*" | "lmmath*", $cmFontDirs] =!= {}, "Latin Modern Math",
    FileNames["lmroman*" | "latinmodern*", $cmFontDirs] =!= {}, "Latin Modern Roman",
    FileNames["cmun*", $cmFontDirs] =!= {}, "CMU Serif",
    True, None]
detectMSBMFont[] := detectMSBMFont[] = If[FileNames["MSBM10.otf", $cmFontDirs] =!= {}, "MSBM10", None]

mathItalicChar[c_String] := With[{cc = First @ ToCharacterCode[c]},
    FromCharacterCode @ Which[
        cc == 104, 16^^210E,                                      (* h -> Planck constant *)
        97 <= cc <= 122, cc + (16^^1D44E - 97),                   (* a-z *)
        65 <= cc <= 90, cc + (16^^1D434 - 65),                    (* A-Z *)
        16^^03B1 <= cc <= 16^^03C9, cc + (16^^1D6FC - 16^^03B1),  (* alpha-omega *)
        True, cc]]
toMathItalicStr[s_String] := StringJoin[mathItalicChar /@ Characters[s]]
dblStruckCharQ[c_String] := With[{cc = First @ ToCharacterCode[c]},
    MemberQ[{16^^2102, 16^^210D, 16^^2115, 16^^2119, 16^^211A, 16^^211D, 16^^2124}, cc] ||
    (16^^1D538 <= cc <= 16^^1D56B) || (16^^1D7D8 <= cc <= 16^^1D7E1)]

LaTeXMathStyle[f_Failure, ___] := f
LaTeXMathStyle[$Failed, ___] := $Failed
LaTeXMathStyle[boxes_] := LaTeXMathStyle[boxes, detectMathFont[]]
LaTeXMathStyle[boxes_, None] := boxes
LaTeXMathStyle[boxes_, font_String] := Module[
    {useMI = StringContainsQ[font, "Math"], msbm = detectMSBMFont[], r},
    r = boxes /. {
        StyleBox[c_, "TBI", rest___] :> StyleBox[c, FontWeight -> Bold, FontSlant -> Italic, rest],
        StyleBox[c_, "TB", rest___] :> StyleBox[c, FontWeight -> Bold, rest],
        StyleBox[c_String, "TI", rest___] :>
            If[useMI, StyleBox[toMathItalicStr[c], rest], StyleBox[c, FontSlant -> Italic, rest]],
        StyleBox[c_, "TI", rest___] :> StyleBox[c, FontSlant -> Italic, rest],
        StyleBox[c_, "TR", rest___] :> StyleBox[c, rest]
    };
    If[msbm =!= None,
        r = r /. s_String /; s =!= "" && AllTrue[Characters[s], dblStruckCharQ] :>
            StyleBox[s, FontFamily -> msbm]];
    StyleBox[r, FontFamily -> font]
]


End[]

EndPackage[]

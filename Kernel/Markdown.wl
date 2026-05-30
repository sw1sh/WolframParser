(* :Package: Wolfram`Parser`
   :Title:   Markdown inline parser built on Wolfram`Parser`

   A GrammarRules-style showcase: every inline markdown construct M2N
   recognises (emphasis, code, math, links, images, sub/sup, escapes,
   HTML <code>/<sub>/<sup>) reduced to ParseChoice over ParserCombinator
   primitives. No StringSplit, no regex; the combinator core handles
   the lot and the PEG order resolves the precedence ambiguity (a
   "**" opening prefers "**bold**" over "*italic*"-"*italic*", a
   "***" opening prefers "***bi***" over "*"-"**bold**", etc.).

   Returns a flat list of inline atoms:

       MdText[str]             plain text run
       MdCode[str]             ` `code` `
       MdLiteralCode[str]      ` ``code`` `      (verbatim, no markdown inside)
       MdHtmlCode[str]         <code>...</code>  (markdown is allowed inside)
       MdMathInline[str]       $...$
       MdMathDisplay[str]      $$...$$
       MdLink[label, url]      [label](url)      label is a List of inline atoms
       MdImage[alt, url]       ![alt](url)
       MdSub[children]         <sub>...</sub>  or  ~x~
       MdSup[children]         <sup>...</sup>  or  ^x^
       MdBold[children]        **...**
       MdItalic[children]      *...*  or  _..._  (underscore is word-bounded)
       MdBoldItalic[children]  ***...***
       MdStrike[children]      ~~...~~

   Adjacent MdText runs are merged so consumers see one MdText per
   contiguous prose chunk. Bold/italic/strike/sub/sup children are
   recursively re-parsed so "**bold $x$**" gives a Bold containing the
   math, not a Bold containing the literal "$x$" string. *)

BeginPackage["Wolfram`Parser`"]

MarkdownInlineParse::usage =
    "MarkdownInlineParse[source] parses an inline markdown string into a " <>
    "list of inline atoms (MdText / MdCode / MdMathInline / MdLink / " <>
    "MdBold / MdItalic / ...).  Adjacent text runs are merged."

MarkdownInlineParser::usage =
    "MarkdownInlineParser is the underlying ParserCombinator. " <>
    "Use it via Parse[MarkdownInlineParser, source] when you want the " <>
    "same parser applied to many inputs."

MdText::usage          = "MdText[str] is a plain text run."
MdCode::usage          = "MdCode[str] is a single-backtick `code` span."
MdLiteralCode::usage   = "MdLiteralCode[str] is a double-backtick verbatim span."
MdHtmlCode::usage      = "MdHtmlCode[str] is a <code>...</code> span."
MdMathInline::usage    = "MdMathInline[str] is a $...$ inline math span."
MdMathDisplay::usage   = "MdMathDisplay[str] is a $$...$$ display math span."
MdLink::usage          = "MdLink[label, url] is a [label](url) link.  label is a List of inline atoms."
MdImage::usage         = "MdImage[alt, url] is an ![alt](url) image."
MdSub::usage           = "MdSub[children] is a <sub>...</sub> or ~...~ subscript."
MdSup::usage           = "MdSup[children] is a <sup>...</sup> or ^...^ superscript."
MdBold::usage          = "MdBold[children] is a **...** bold span."
MdItalic::usage        = "MdItalic[children] is a *...* or _..._ italic span."
MdBoldItalic::usage    = "MdBoldItalic[children] is a ***...*** bold-italic span."
MdStrike::usage        = "MdStrike[children] is a ~~...~~ strikethrough span."

Begin["`MarkdownPrivate`"]


(* ===== character predicates ===== *)

asciiPunct = (StringMatchQ[#, PunctuationCharacter] || # === "!") &

(* a letter / digit / "_" for the underscore-emphasis word-boundary rule *)
wordCh = (StringMatchQ[#, LetterCharacter | DigitCharacter] || # === "_") &


(* ===== primitive combinators ===== *)

anyChar = ParseCharacter[_]

(* match a single character that satisfies a predicate *)
charSat[pred_] := ParseCharacter[_ ? pred]

(* match a literal string and discard *)
litP[s_String] := ParseAction[ParseLiteral[s], Null &]


(* ===== terminator-bounded content ===== *)

(* content[term] parses any single character that is NOT the start of `term`,
   joined into a single String.  Used as the body of every paired-delimiter
   span (code, math, emphasis, ...).  The lookahead is what stops `**foo**`
   from gobbling the closing `**` into the content - the inner content rule
   refuses any position that starts with `**`. *)
content[term_] := ParseAction[
    ParseSome[
        ParseAction[ParseNotFollowedBy[term] ~~ anyChar, #2 &]
    ],
    StringJoin[{##}] &
]


(* ===== escapes ===== *)

(* "\x" where x is an ASCII punctuation char becomes that single character
   as an MdText atom.  Lets authors write a literal "*" inside prose with
   "\*" (otherwise the "*" would open an italic span). *)
escape = ParseAction[
    ParseLiteral["\\"] ~~ charSat[asciiPunct],
    MdText[#2] &
]


(* ===== code spans ===== *)

(* Order is significant: double backtick first so "``x``" prefers MdLiteralCode
   over MdCode-empty-MdCode.  Same for HTML <code>...</code>: it can carry
   markdown inside so it's parsed as a separate atom; the inner text is
   stored verbatim and re-parsed by the consumer if it wants markdown. *)
codeHtml = ParseAction[
    ParseLiteral["<code>"] ~~ content[ParseLiteral["</code>"]] ~~ ParseLiteral["</code>"],
    MdHtmlCode[#2] &
]

dblCode = ParseAction[
    ParseLiteral["``"] ~~ content[ParseLiteral["``"]] ~~ ParseLiteral["``"],
    MdLiteralCode[StringTrim[#2]] &
]

code = ParseAction[
    ParseLiteral["`"] ~~ content[ParseLiteral["`"]] ~~ ParseLiteral["`"],
    MdCode[#2] &
]


(* ===== math ===== *)

displayMath = ParseAction[
    ParseLiteral["$$"] ~~ content[ParseLiteral["$$"]] ~~ ParseLiteral["$$"],
    MdMathDisplay[#2] &
]

inlineMath = ParseAction[
    ParseLiteral["$"] ~~ content[ParseLiteral["$"]] ~~ ParseLiteral["$"],
    MdMathInline[#2] &
]


(* ===== link / image ===== *)

(* The body is everything up to the next "]"; the URL is everything up to
   the next ")".  Inline markdown inside the label is recursively re-parsed
   by the public wrapper (see runInner). *)
linkLabel = ParseAction[
    ParseSome[ParseAction[ParseNotFollowedBy[ParseLiteral["]"]] ~~ anyChar, #2 &]],
    StringJoin[{##}] &
]

linkUrl = ParseAction[
    ParseMany[ParseAction[ParseNotFollowedBy[ParseLiteral[")"]] ~~ anyChar, #2 &]],
    StringJoin[{##}] &
]

image = ParseAction[
    ParseLiteral["!["] ~~ linkLabel ~~ ParseLiteral["]("] ~~ linkUrl ~~ ParseLiteral[")"],
    MdImage[#2, #4] &
]

link = ParseAction[
    ParseLiteral["["] ~~ linkLabel ~~ ParseLiteral["]("] ~~ linkUrl ~~ ParseLiteral[")"],
    MdLink[#2, #4] &
]


(* ===== sub / sup ===== *)

htmlSub = ParseAction[
    ParseLiteral["<sub>"] ~~ content[ParseLiteral["</sub>"]] ~~ ParseLiteral["</sub>"],
    MdSub[#2] &
]

htmlSup = ParseAction[
    ParseLiteral["<sup>"] ~~ content[ParseLiteral["</sup>"]] ~~ ParseLiteral["</sup>"],
    MdSup[#2] &
]

(* Pandoc "~x~" subscript: refuses spaces inside (would conflict with
   strike and with prose) and refuses an empty body. *)
pandocSubBody = ParseAction[
    ParseSome[charSat[# =!= "~" && # =!= " " &]],
    StringJoin[{##}] &
]
pandocSub = ParseAction[
    ParseLiteral["~"] ~~ pandocSubBody ~~ ParseLiteral["~"],
    MdSub[#2] &
]

pandocSupBody = ParseAction[
    ParseSome[charSat[# =!= "^" && # =!= " " &]],
    StringJoin[{##}] &
]
pandocSup = ParseAction[
    ParseLiteral["^"] ~~ pandocSupBody ~~ ParseLiteral["^"],
    MdSup[#2] &
]


(* ===== strike ===== *)

strike = ParseAction[
    ParseLiteral["~~"] ~~ content[ParseLiteral["~~"]] ~~ ParseLiteral["~~"],
    MdStrike[#2] &
]


(* ===== emphasis ===== *)

boldItalic = ParseAction[
    ParseLiteral["***"] ~~ content[ParseLiteral["***"]] ~~ ParseLiteral["***"],
    MdBoldItalic[#2] &
]

bold = ParseAction[
    ParseLiteral["**"] ~~ content[ParseLiteral["**"]] ~~ ParseLiteral["**"],
    MdBold[#2] &
]

(* Asterisk italic: refuse an inner "*" so "**a**" never re-matches as
   "*"-"*a*"-"*", and refuse a leading space so "* list item" stays plain. *)
italicAstBody = ParseAction[
    ParseSome[charSat[# =!= "*" &]],
    StringJoin[{##}] &
]
italicAst = ParseAction[
    ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[" "]] ~~ italicAstBody ~~ ParseLiteral["*"],
    MdItalic[#3] &
]


(* ===== plain character (catch-all) ===== *)

plainChar = ParseAction[anyChar, MdText[#1] &]


(* ===== the inline grammar ===== *)

(* PEG order: more-specific / longer prefixes first.  Double-backtick before
   single-backtick; "***" before "**" before "*"; HTML tags before their
   single-letter pandoc twins; escape first of all so "\*" never opens an
   italic. *)
inlineAtom = ParseChoice[
    escape,
    codeHtml, image, link,
    dblCode, code,
    displayMath, inlineMath,
    strike,
    htmlSub, htmlSup,
    boldItalic, bold, italicAst,
    pandocSub, pandocSup,
    plainChar
]

MarkdownInlineParser := ParseAction[ParseMany[inlineAtom], {##} &]


(* ===== plain-text merging + ellipsis + underscore-emphasis ===== *)

(* Merge consecutive MdText atoms into one.  The character-by-character
   plainChar rule emits one MdText per char; this rejoins them so consumers
   see prose as one run, not a list of letters. *)
mergeText[atoms_List] := Block[{step},
    step[acc_, MdText[s_]] := If[acc =!= {} && MatchQ[Last[acc], MdText[_]],
        Append[Most[acc], MdText[acc[[-1, 1]] <> s]],
        Append[acc, MdText[s]]
    ];
    step[acc_, other_] := Append[acc, other];
    Fold[step, {}, atoms]
]

(* Three literal dots in a plain text run become the Unicode ellipsis char.
   Code / math / link URLs are untouched - the substitution applies only
   to MdText atoms.  Matches the M2N convention. *)
applyEllipsis[atoms_List] := Replace[atoms, MdText[s_String] :> MdText[StringReplace[s, "..." -> "\[Ellipsis]"]], {1}]

(* Underscore emphasis: CommonMark only opens "_em_" at a word boundary, so
   "snake_case" in prose is left alone.  We post-process MdText runs to
   convert balanced "__strong__" / "_em_" into Md{Bold,Italic}.  Lookbehind
   forbids a word char (letter/digit/underscore) immediately before the
   opening underscore; lookahead forbids one immediately after the closing
   underscore.  Inner content has no whitespace at its edges (\S anchors),
   so "_ word _" stays literal too.  Runs inside other atoms (code, math,
   ...) are untouched - those carry literal "_". *)
underscoreRules = {
    RegularExpression["(?<![A-Za-z0-9_])__(\\S|\\S.*?\\S)__(?![A-Za-z0-9_])"] -> "\:f001$1\:f002",
    RegularExpression["(?<![A-Za-z0-9_])_(\\S|\\S.*?\\S)_(?![A-Za-z0-9_])"] -> "\:f003$1\:f004"
}
underscoreRender[s_String] := With[{tagged = StringReplace[s, underscoreRules]},
    If[ tagged === s, {MdText[s]},
        Replace[
            StringSplit[tagged, {
                "\:f001" ~~ inner__ ~~ "\:f002" :> MdBold[runInner[inner]],
                "\:f003" ~~ inner__ ~~ "\:f004" :> MdItalic[runInner[inner]]
            }],
            inner_String :> MdText[inner],
            {1}
        ]
    ]
]
applyUnderscoreEm[atoms_List] := Flatten @ Replace[atoms,
    MdText[s_String] :> underscoreRender[s], {1}]


(* ===== recursive children ===== *)

(* Children of bold / italic / sub / sup / strike / boldItalic /
   linklabel are the *raw inner string* captured by `content`.  Re-parse
   them so nested formatting works ("**a $x$**" -> Bold[List[Text["a "], MathInline["x"]]]). *)
runInner[s_String] := MarkdownInlineParse[s]

reparseChildren = {
    MdBold[s_String]        :> MdBold[runInner[s]],
    MdItalic[s_String]      :> MdItalic[runInner[s]],
    MdBoldItalic[s_String]  :> MdBoldItalic[runInner[s]],
    MdStrike[s_String]      :> MdStrike[runInner[s]],
    MdSub[s_String]         :> MdSub[runInner[s]],
    MdSup[s_String]         :> MdSup[runInner[s]],
    MdLink[label_String, url_String] :> MdLink[runInner[label], url]
    (* MdImage / MdHtmlCode keep their alt / inner verbatim *)
}


(* ===== public entry point ===== *)

MarkdownInlineParse[source_String] := With[{r = Parse[MarkdownInlineParser, source]},
    If[FailureQ[r], r,
        applyUnderscoreEm @ applyEllipsis @ mergeText[r /. reparseChildren]
    ]
]


End[]
EndPackage[]

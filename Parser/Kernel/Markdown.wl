(* :Package: Wolfram`Parser`
   :Title:   Markdown inline parser built on Wolfram`Parser`

   A GrammarRules-style showcase: every inline markdown construct M2N
   recognises (emphasis, code, math, links, images, sub/sup, escapes,
   HTML <code>/<sub>/<sup>) reduced to ParseChoice over ParserCombinator
   primitives.  No StringSplit, no regex hand-tuning; the combinator core
   handles the lot and the PEG order resolves the precedence ambiguity (a
   "**" opening prefers "**bold**" over "*italic*"-"*italic*", a "***"
   opening prefers "***bi***" over "*"-"**bold**", etc.).

   Returns a flat list of inline atoms shaped as Associations with a
   "Type" discriminator, matching the convention M2N's block-level
   parser uses (<|"Type" -> "Heading", "Level" -> 2, "Text" -> ...|>
   etc.):

       <|"Type" -> "Text",         "Text" -> str|>           plain text run
       <|"Type" -> "Code",         "Code" -> str|>           ` `code` `
       <|"Type" -> "LiteralCode",  "Code" -> str|>           ` ``code`` ` (verbatim)
       <|"Type" -> "HtmlCode",     "Code" -> str|>           <code>...</code>
       <|"Type" -> "MathInline",   "Math" -> str|>           $...$
       <|"Type" -> "MathDisplay",  "Math" -> str|>           $$...$$
       <|"Type" -> "Link",         "Label" -> [atoms], "Url" -> str|>
       <|"Type" -> "Image",        "Alt"   -> str,     "Url" -> str|>
       <|"Type" -> "Sub",          "Children" -> [atoms]|>   <sub>...</sub> | ~x~
       <|"Type" -> "Sup",          "Children" -> [atoms]|>   <sup>...</sup> | ^x^
       <|"Type" -> "Bold",         "Children" -> [atoms]|>   **...** | __...__
       <|"Type" -> "Italic",       "Children" -> [atoms]|>   *...*   | _..._
       <|"Type" -> "BoldItalic",   "Children" -> [atoms]|>   ***...***
       <|"Type" -> "Strike",       "Children" -> [atoms]|>   ~~...~~

   Adjacent "Text" runs are merged so consumers see one run per
   contiguous prose chunk.  Bold/italic/strike/sub/sup/link children are
   recursively re-parsed so "**bold $x$**" gives a Bold whose Children
   are [Text["bold "], MathInline["x"]], not a Bold holding the literal
   "$x$" string. *)

BeginPackage["Wolfram`Parser`"]

MarkdownInlineParse::usage =
    "MarkdownInlineParse[source] parses an inline markdown string into a " <>
    "list of inline-atom Associations.  Each atom carries a \"Type\" " <>
    "discriminator (\"Text\", \"Code\", \"Bold\", \"Italic\", \"Link\", " <>
    "...) plus payload keys.  Adjacent text runs are merged."

MarkdownInlineParser::usage =
    "MarkdownInlineParser is the underlying ParserCombinator. " <>
    "Use it via Parse[MarkdownInlineParser, source] when you want the " <>
    "same parser applied to many inputs."

MarkdownParse::usage =
    "MarkdownParse[source] parses a whole markdown document into an " <>
    "Association <|\"Metadata\" -> <|...|>, \"Blocks\" -> [...]|>.  " <>
    "Mirrors the shape M2N's litParse uses, so each block is a typed " <>
    "Association (Heading / Code / Separator / Prose / ...).  " <>
    "Block-level Prose carries raw inline source; pass it through " <>
    "MarkdownInlineParse to get the inline-atom list."

MarkdownParser::usage =
    "MarkdownParser is the underlying ParserCombinator for the whole-" <>
    "document grammar.  Parse[MarkdownParser, source] runs it directly."

Begin["`MarkdownPrivate`"]


(* ===== atom constructors (shape conventions in one place) ===== *)

text[s_]        := <|"Type" -> "Text",        "Text" -> s|>
codeAtom[s_]    := <|"Type" -> "Code",        "Code" -> s|>
litCode[s_]     := <|"Type" -> "LiteralCode", "Code" -> s|>
htmlCode[s_]    := <|"Type" -> "HtmlCode",    "Code" -> s|>
mathIn[s_]      := <|"Type" -> "MathInline",  "Math" -> s|>
mathDis[s_]     := <|"Type" -> "MathDisplay", "Math" -> s|>
link[lbl_, u_]  := <|"Type" -> "Link",        "Label" -> lbl, "Url" -> u|>
image[a_, u_]   := <|"Type" -> "Image",       "Alt"   -> a,   "Url" -> u|>
sub[c_]         := <|"Type" -> "Sub",         "Children" -> c|>
sup[c_]         := <|"Type" -> "Sup",         "Children" -> c|>
bold[c_]        := <|"Type" -> "Bold",        "Children" -> c|>
italic[c_]      := <|"Type" -> "Italic",      "Children" -> c|>
boldItalic[c_]  := <|"Type" -> "BoldItalic",  "Children" -> c|>
strike[c_]      := <|"Type" -> "Strike",      "Children" -> c|>


(* ===== character predicates ===== *)

asciiPunct = (StringMatchQ[#, PunctuationCharacter] || # === "!") &


(* ===== primitive combinators ===== *)

anyChar = ParseCharacter[_]

charSat[pred_] := ParseCharacter[_ ? pred]


(* ===== terminator-bounded content ===== *)

(* content[term] parses any single character that is NOT the start of `term`,
   joined into a single String.  Used as the body of every paired-delimiter
   span (code, math, emphasis, ...).  The lookahead is what stops `**foo**`
   from gobbling the closing `**` into the content - the inner content rule
   refuses any position that starts with `term`. *)
content[term_] := ParseAction[
    ParseSome[ParseAction[ParseNotFollowedBy[term] ~~ anyChar, #2 &]],
    StringJoin[{##}] &
]


(* ===== escapes ===== *)

(* "\x" where x is an ASCII punctuation char becomes that single character as
   a Text atom.  Lets authors write a literal "*" inside prose with "\*"
   (otherwise the "*" would open an italic span). *)
escape = ParseAction[
    ParseLiteral["\\"] ~~ charSat[asciiPunct],
    text[#2] &
]


(* ===== code spans ===== *)

(* Order is significant: HTML <code> before backticks, double backtick before
   single backtick. *)
codeHtml = ParseAction[
    ParseLiteral["<code>"] ~~ content[ParseLiteral["</code>"]] ~~ ParseLiteral["</code>"],
    htmlCode[#2] &
]

dblCode = ParseAction[
    ParseLiteral["``"] ~~ content[ParseLiteral["``"]] ~~ ParseLiteral["``"],
    litCode[StringTrim[#2]] &
]

code = ParseAction[
    ParseLiteral["`"] ~~ content[ParseLiteral["`"]] ~~ ParseLiteral["`"],
    codeAtom[#2] &
]


(* ===== math ===== *)

displayMath = ParseAction[
    ParseLiteral["$$"] ~~ content[ParseLiteral["$$"]] ~~ ParseLiteral["$$"],
    mathDis[#2] &
]

inlineMath = ParseAction[
    ParseLiteral["$"] ~~ content[ParseLiteral["$"]] ~~ ParseLiteral["$"],
    mathIn[#2] &
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

imageP = ParseAction[
    ParseLiteral["!["] ~~ linkLabel ~~ ParseLiteral["]("] ~~ linkUrl ~~ ParseLiteral[")"],
    image[#2, #4] &
]

linkP = ParseAction[
    ParseLiteral["["] ~~ linkLabel ~~ ParseLiteral["]("] ~~ linkUrl ~~ ParseLiteral[")"],
    link[#2, #4] &
]


(* ===== sub / sup ===== *)

htmlSub = ParseAction[
    ParseLiteral["<sub>"] ~~ content[ParseLiteral["</sub>"]] ~~ ParseLiteral["</sub>"],
    sub[#2] &
]

htmlSup = ParseAction[
    ParseLiteral["<sup>"] ~~ content[ParseLiteral["</sup>"]] ~~ ParseLiteral["</sup>"],
    sup[#2] &
]

(* Pandoc "~x~" subscript: refuses spaces and empty body so it doesn't fire
   on prose. *)
pandocSubBody = ParseAction[
    ParseSome[charSat[# =!= "~" && # =!= " " &]],
    StringJoin[{##}] &
]
pandocSub = ParseAction[
    ParseLiteral["~"] ~~ pandocSubBody ~~ ParseLiteral["~"],
    sub[#2] &
]

pandocSupBody = ParseAction[
    ParseSome[charSat[# =!= "^" && # =!= " " &]],
    StringJoin[{##}] &
]
pandocSup = ParseAction[
    ParseLiteral["^"] ~~ pandocSupBody ~~ ParseLiteral["^"],
    sup[#2] &
]


(* ===== strike ===== *)

strikeP = ParseAction[
    ParseLiteral["~~"] ~~ content[ParseLiteral["~~"]] ~~ ParseLiteral["~~"],
    strike[#2] &
]


(* ===== emphasis ===== *)

boldItalicP = ParseAction[
    ParseLiteral["***"] ~~ content[ParseLiteral["***"]] ~~ ParseLiteral["***"],
    boldItalic[#2] &
]

boldP = ParseAction[
    ParseLiteral["**"] ~~ content[ParseLiteral["**"]] ~~ ParseLiteral["**"],
    bold[#2] &
]

italicAstBody = ParseAction[
    ParseSome[charSat[# =!= "*" &]],
    StringJoin[{##}] &
]
italicAst = ParseAction[
    ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[" "]] ~~ italicAstBody ~~ ParseLiteral["*"],
    italic[#3] &
]


(* ===== plain character (catch-all) ===== *)

plainChar = ParseAction[anyChar, text[#1] &]


(* ===== the inline grammar ===== *)

(* PEG order: more-specific / longer prefixes first.  Double-backtick before
   single-backtick; "***" before "**" before "*"; HTML tags before their
   single-letter pandoc twins; escape first of all so "\*" never opens an
   italic. *)
inlineAtom = ParseChoice[
    escape,
    codeHtml, imageP, linkP,
    dblCode, code,
    displayMath, inlineMath,
    strikeP,
    htmlSub, htmlSup,
    boldItalicP, boldP, italicAst,
    pandocSub, pandocSup,
    plainChar
]

MarkdownInlineParser := ParseAction[ParseMany[inlineAtom], {##} &]


(* ===== post-process: type-discriminated dispatch ===== *)

textQ[a_] := AssociationQ[a] && a["Type"] === "Text"

(* Merge consecutive Text atoms into one.  The character-by-character
   plainChar rule emits one Text atom per char; this rejoins them so
   consumers see prose as one run, not a list of letters. *)
mergeText[atoms_List] := Block[{step},
    step[acc_, a_ ? textQ] := If[ acc =!= {} && textQ[Last[acc]],
        Append[Most[acc], text[Last[acc]["Text"] <> a["Text"]]],
        Append[acc, a]
    ];
    step[acc_, other_] := Append[acc, other];
    Fold[step, {}, atoms]
]

(* Three literal dots in a plain text run become the Unicode ellipsis
   char.  Code / math / link URLs are untouched - the substitution applies
   only to Text atoms.  Matches the M2N convention. *)
applyEllipsis[atoms_List] := Replace[atoms,
    a_ ? textQ :> text[StringReplace[a["Text"], "..." -> "\[Ellipsis]"]], {1}]

(* Underscore emphasis: CommonMark only opens "_em_" at a word boundary, so
   "snake_case" in prose is left alone.  The grammar doesn't try to express
   the lookbehind/lookahead rules; instead a post-pass scans each Text run
   with two regexes anchored by word-boundary lookarounds.  Captured bodies
   get sentinel-wrapped (private-use codepoints that no real markdown
   source ships), then a StringSplit turns each wrapped run into a
   Bold/Italic atom whose body is itself re-parsed. *)
underscoreRules = {
    RegularExpression["(?<![A-Za-z0-9_])__(\\S|\\S.*?\\S)__(?![A-Za-z0-9_])"] -> "\:f001$1\:f002",
    RegularExpression["(?<![A-Za-z0-9_])_(\\S|\\S.*?\\S)_(?![A-Za-z0-9_])"]   -> "\:f003$1\:f004"
}
underscoreRender[s_String] := With[{tagged = StringReplace[s, underscoreRules]},
    If[ tagged === s, {text[s]},
        Replace[
            StringSplit[tagged, {
                "\:f001" ~~ inner__ ~~ "\:f002" :> bold[runInner[inner]],
                "\:f003" ~~ inner__ ~~ "\:f004" :> italic[runInner[inner]]
            }],
            inner_String :> text[inner],
            {1}
        ]
    ]
]
applyUnderscoreEm[atoms_List] := Flatten @ Replace[atoms,
    a_ ? textQ :> underscoreRender[a["Text"]], {1}]


(* ===== recursive children ===== *)

(* Children of bold / italic / sub / sup / strike / boldItalic and the
   label of a link are the *raw inner string* captured by `content`.
   Re-parse them so nested formatting works ("**a $x$**" -> Bold whose
   Children include the inline math).  Image alt and HtmlCode bodies stay
   verbatim. *)
runInner[s_String] := MarkdownInlineParse[s]

reparseChildren[atoms_List] := Replace[atoms, {
    a_Association /; MemberQ[{"Bold", "Italic", "BoldItalic", "Strike", "Sub", "Sup"}, a["Type"]] &&
        StringQ[a["Children"]] :>
        Append[a, "Children" -> runInner[a["Children"]]],
    a_Association /; a["Type"] === "Link" && StringQ[a["Label"]] :>
        Append[a, "Label" -> runInner[a["Label"]]]
}, {1}]


(* ===== public entry point ===== *)

MarkdownInlineParse[source_String] := With[{r = Parse[MarkdownInlineParser, source]},
    If[ FailureQ[r], r,
        applyUnderscoreEm @ applyEllipsis @ mergeText @ reparseChildren[r]
    ]
]


(* ===========================================================================
   Block-level parser: MarkdownParse
   ===========================================================================
   Mirrors the output shape of M2N's litParse:
       <|"Metadata" -> <|key -> val|>,
         "Blocks"   -> [block, ...]
       |>
   with block Associations carrying a "Type" discriminator + payload keys:
       <|"Type" -> "Heading",   "Level" -> n,           "Text" -> str|>
       <|"Type" -> "Code",      "Lang"  -> str,         "Code" -> str, "Options" -> <|...|>|>
       <|"Type" -> "Separator"|>
       <|"Type" -> "Prose",     "Text"  -> str|>

   First-pass coverage: frontmatter, headings, code fences (with #|
   options), thematic breaks, and prose paragraphs.  Lists / tables /
   blockquotes / math blocks / fenced divs are TODO and currently fall
   into the Prose catch-all. *)


(* ===== line-level primitives ===== *)

newline       = ParseLiteral["\n"]
notNewline    = charSat[# =!= "\n" &]
restOfLine    = ParseAction[ParseMany[notNewline], StringJoin[{##}] &]
eatNewline    = ParseAction[ParseOptional[newline], Null &]
blankLine     = ParseAction[ParseMany[charSat[# === " " || # === "\t" &]] ~~ newline, Null &]
blankLines    = ParseMany[blankLine]


(* ===== frontmatter =====
   "---" on a line, then "key: value" lines, then "---".  Returns an
   Association.  An empty frontmatter (missing the leading "---") yields
   <||> and consumes nothing. *)

fmDelim     = ParseAction[ParseLiteral["---"] ~~ restOfLine ~~ newline, Null &]
fmEntryLine = ParseAction[
    ParseNotFollowedBy[ParseLiteral["---"]] ~~ restOfLine ~~ newline,
    #2 &
]

parseFmValue[v_String] := With[{tr = StringTrim[v]},
    Which[
        StringStartsQ[tr, "[" ] && StringEndsQ[tr, "]"],
            StringTrim /@ StringSplit[StringTake[tr, {2, -2}], ","],
        StringMatchQ[tr, "\"" ~~ ___ ~~ "\""] || StringMatchQ[tr, "'" ~~ ___ ~~ "'"],
            StringTake[tr, {2, -2}],
        True, tr
    ]
]

parseFmEntries[lines_List] := Association @ DeleteCases[
    Map[
        Function[ln,
            With[{m = StringCases[ln, StartOfString ~~ k : Shortest[__] ~~ ":" ~~ v___ ~~ EndOfString :> {StringTrim[k], v}, 1]},
                If[ m === {}, Nothing, First[m][[1]] -> parseFmValue[First[m][[2]]]]
            ]
        ],
        lines
    ],
    Nothing
]

frontmatter = ParseAction[
    fmDelim ~~ ParseMany[fmEntryLine] ~~ fmDelim,
    parseFmEntries[#2] &
]

emptyFrontmatter = ParseAction[ParseSucceed[<||>], #1 &]
frontmatterOpt = ParseChoice[frontmatter, emptyFrontmatter]


(* ===== headings =====
   "#"+ space rest-of-line.  Level = number of #s (1..6 per CommonMark,
   but accept any count). *)

hashes = ParseAction[ParseSome[ParseLiteral["#"]], Length[{##}] &]
heading = ParseAction[
    hashes ~~ ParseLiteral[" "] ~~ restOfLine ~~ newline,
    <|"Type" -> "Heading", "Level" -> #1, "Text" -> StringTrim[#3]|> &
]


(* ===== thematic break =====
   "---" / "***" / "___" - three or more on a line, alone.  Frontmatter's
   "---" is already eaten by the frontmatter parser, so any "---" reaching
   the block grammar is a thematic break. *)

separatorLine = ParseAction[
    ParseChoice[
        ParseLiteral["---"] ~~ ParseMany[ParseLiteral["-"]],
        ParseLiteral["***"] ~~ ParseMany[ParseLiteral["*"]],
        ParseLiteral["___"] ~~ ParseMany[ParseLiteral["_"]]
    ] ~~ ParseMany[charSat[# === " " || # === "\t" &]] ~~ newline,
    <|"Type" -> "Separator"|> &
]


(* ===== code fence =====
   "```" + optional lang word, then lines of content, then "```".  The
   first body lines may carry "#| key: value" options that go into
   "Options".  M2N also recognises tilde fences and indented code; this
   first cut handles backtick fences only. *)

fenceOpen = ParseAction[
    ParseLiteral["```"] ~~ restOfLine ~~ newline,
    StringTrim[#2] &
]
fenceClose = ParseAction[
    ParseLiteral["```"] ~~ restOfLine ~~ newline,
    Null &
]
fenceContentLine = ParseAction[
    ParseNotFollowedBy[ParseLiteral["```"]] ~~ restOfLine ~~ newline,
    #2 &
]

parseFenceOption[ln_String] := With[{
    m = StringCases[StringTrim[ln],
        StartOfString ~~ "#|" ~~ Whitespace... ~~ k : Shortest[__] ~~ ":" ~~ v___ ~~ EndOfString :>
            StringTrim[k] -> StringTrim[v], 1]
},
    If[m === {}, Nothing, First[m]]
]

splitFenceOptions[lines_List] := Block[{opts = {}, body = lines, kv},
    While[ body =!= {} && StringStartsQ[StringTrim[First[body]], "#|"],
        kv = parseFenceOption[First[body]];
        If[kv =!= Nothing, AppendTo[opts, kv]];
        body = Rest[body]
    ];
    {Association[opts], body}
]

codeFence = ParseAction[
    fenceOpen ~~ ParseMany[fenceContentLine] ~~ fenceClose,
    With[{lang = #1, lines = #2, split = splitFenceOptions[#2]},
        <|"Type" -> "Code",
          "Lang" -> lang,
          "Code" -> StringRiffle[Last[split], "\n"],
          "Options" -> First[split]|>
    ] &
]


(* ===== prose paragraph =====
   One or more non-blank lines that don't start with a block-opener.
   Joined with " " so a soft-wrapped paragraph reads as one Prose Text. *)

proseLine = ParseAction[
    ParseNotFollowedBy[ParseChoice[
        ParseLiteral["#"], ParseLiteral["```"],
        ParseLiteral["---"], ParseLiteral["***"], ParseLiteral["___"]
    ]] ~~ restOfLine ~~ newline,
    #2 &
]
prose = ParseAction[
    ParseSome[proseLine],
    <|"Type" -> "Prose", "Text" -> StringTrim @ StringRiffle[{##}, " "]|> &
]


(* ===== block grammar ===== *)

block = ParseChoice[heading, codeFence, separatorLine, prose]

documentBody = ParseAction[
    ParseMany[ParseAction[blankLines ~~ block, #2 &]] ~~ blankLines,
    #1 &
]

MarkdownParser := ParseAction[
    frontmatterOpt ~~ documentBody,
    <|"Metadata" -> #1, "Blocks" -> #2|> &
]


(* ===== public entry point =====
   Auto-appends a final newline if the source is missing one - the line-
   based rules above all consume a trailing newline, so a no-trailing-
   newline file would fail their last block. *)

MarkdownParse[source_String] := Parse[
    MarkdownParser,
    If[StringEndsQ[source, "\n"], source, source <> "\n"]
]


End[]
EndPackage[]

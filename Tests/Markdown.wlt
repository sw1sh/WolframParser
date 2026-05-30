(* :Title: Markdown inline-parser tests

   Exercises every inline construct MarkdownInlineParse handles, mirroring
   the cases M2N.md already documents (escapes, code/math, links/images,
   sub/sup, emphasis, recursion) plus edge cases (unclosed delimiters,
   adjacent-run merging, word-boundary underscores, ellipsis). *)

Needs["Wolfram`Parser`"]


(* ===== plain text + adjacent-run merging ===== *)

VerificationTest[
    MarkdownInlineParse["hello world"],
    {MdText["hello world"]},
    TestID -> "plain text is one MdText"
]

VerificationTest[
    MarkdownInlineParse[""],
    {},
    TestID -> "empty source -> empty list"
]

VerificationTest[
    MarkdownInlineParse["a `x` b `y` c"],
    {MdText["a "], MdCode["x"], MdText[" b "], MdCode["y"], MdText[" c"]},
    TestID -> "text runs between code spans are coalesced"
]


(* ===== escapes ===== *)

VerificationTest[
    MarkdownInlineParse["a\\*b"],
    {MdText["a*b"]},
    TestID -> "backslash-star is a literal star"
]

VerificationTest[
    MarkdownInlineParse["price: \\$5"],
    {MdText["price: $5"]},
    TestID -> "backslash-dollar suppresses math"
]

VerificationTest[
    MarkdownInlineParse["\\[CircleTimes\\]"],
    {MdText["[CircleTimes]"]},
    TestID -> "backslash-bracket is a literal bracket"
]


(* ===== code spans ===== *)

VerificationTest[
    MarkdownInlineParse["`Range[5]`"],
    {MdCode["Range[5]"]},
    TestID -> "single backtick -> MdCode"
]

VerificationTest[
    MarkdownInlineParse["``x``"],
    {MdLiteralCode["x"]},
    TestID -> "double backtick -> MdLiteralCode"
]

VerificationTest[
    MarkdownInlineParse["`` `nested` ``"],
    {MdLiteralCode["`nested`"]},
    TestID -> "double backtick wraps a literal single-backtick run"
]

VerificationTest[
    MarkdownInlineParse["<code>[Range]()[n]</code>"],
    {MdHtmlCode["[Range]()[n]"]},
    TestID -> "<code> wrapper carries its inner markdown verbatim"
]


(* ===== math ===== *)

VerificationTest[
    MarkdownInlineParse["$x + y$"],
    {MdMathInline["x + y"]},
    TestID -> "single-dollar -> MdMathInline"
]

VerificationTest[
    MarkdownInlineParse["$$x = y$$"],
    {MdMathDisplay["x = y"]},
    TestID -> "double-dollar -> MdMathDisplay"
]

VerificationTest[
    MarkdownInlineParse["see $\\sqrt{x}$ here"],
    {MdText["see "], MdMathInline["\\sqrt{x}"], MdText[" here"]},
    TestID -> "math inside prose"
]


(* ===== links + images ===== *)

VerificationTest[
    MarkdownInlineParse["[label](https://example.com)"],
    {MdLink[{MdText["label"]}, "https://example.com"]},
    TestID -> "[label](url) -> MdLink with parsed label"
]

VerificationTest[
    MarkdownInlineParse["[`Range`](paclet:ref/Range)"],
    {MdLink[{MdCode["Range"]}, "paclet:ref/Range"]},
    TestID -> "code-styled link label"
]

VerificationTest[
    MarkdownInlineParse["[Range]()"],
    {MdLink[{MdText["Range"]}, ""]},
    TestID -> "empty url is preserved (inferred-link convention)"
]

VerificationTest[
    MarkdownInlineParse["![diagram](img/flow.png)"],
    {MdImage["diagram", "img/flow.png"]},
    TestID -> "![alt](url) -> MdImage"
]


(* ===== sub / sup ===== *)

VerificationTest[
    MarkdownInlineParse["H<sub>2</sub>O"],
    {MdText["H"], MdSub[{MdText["2"]}], MdText["O"]},
    TestID -> "HTML <sub>"
]

VerificationTest[
    MarkdownInlineParse["e<sup>x</sup>"],
    {MdText["e"], MdSup[{MdText["x"]}]},
    TestID -> "HTML <sup>"
]

VerificationTest[
    MarkdownInlineParse["x~i~"],
    {MdText["x"], MdSub[{MdText["i"]}]},
    TestID -> "Pandoc ~x~ subscript"
]

VerificationTest[
    MarkdownInlineParse["e^2^"],
    {MdText["e"], MdSup[{MdText["2"]}]},
    TestID -> "Pandoc ^x^ superscript"
]

VerificationTest[
    MarkdownInlineParse["~~struck~~"],
    {MdStrike[{MdText["struck"]}]},
    TestID -> "~~text~~ is strikethrough, not double-subscript"
]


(* ===== emphasis: asterisks ===== *)

VerificationTest[
    MarkdownInlineParse["*italic*"],
    {MdItalic[{MdText["italic"]}]},
    TestID -> "*x* -> MdItalic"
]

VerificationTest[
    MarkdownInlineParse["**bold**"],
    {MdBold[{MdText["bold"]}]},
    TestID -> "**x** -> MdBold"
]

VerificationTest[
    MarkdownInlineParse["***both***"],
    {MdBoldItalic[{MdText["both"]}]},
    TestID -> "***x*** -> MdBoldItalic"
]

VerificationTest[
    MarkdownInlineParse["a *b* c"],
    {MdText["a "], MdItalic[{MdText["b"]}], MdText[" c"]},
    TestID -> "italic inside prose"
]


(* ===== emphasis: underscores (word-bounded) ===== *)

VerificationTest[
    MarkdownInlineParse["_em_"],
    {MdItalic[{MdText["em"]}]},
    TestID -> "_x_ -> MdItalic (children re-parsed)"
]

VerificationTest[
    MarkdownInlineParse["__strong__"],
    {MdBold[{MdText["strong"]}]},
    TestID -> "__x__ -> MdBold (children re-parsed)"
]

VerificationTest[
    MarkdownInlineParse["snake_case_name"],
    {MdText["snake_case_name"]},
    TestID -> "underscore between word chars stays literal (CommonMark intraword)"
]

(* Per CommonMark: in "_file_name_" the opening "_" is at a space->letter
   boundary (left-flanking only, can open); the middle "_" is letter->letter
   (both-flanking, cannot close); the closing "_" is letter->space
   (right-flanking only, can close).  Result: one italic span whose body
   contains the internal underscore. *)
VerificationTest[
    MarkdownInlineParse["see _file_name_ here"],
    {MdText["see "], MdItalic[{MdText["file_name"]}], MdText[" here"]},
    TestID -> "underscores around identifier with internal _ form one italic per CommonMark"
]


(* ===== recursion: child of one span is re-parsed as inline ===== *)

VerificationTest[
    MarkdownInlineParse["**bold $x$**"],
    {MdBold[{MdText["bold "], MdMathInline["x"]}]},
    TestID -> "bold containing math is re-parsed"
]

VerificationTest[
    MarkdownInlineParse["*italic `code`*"],
    {MdItalic[{MdText["italic "], MdCode["code"]}]},
    TestID -> "italic containing code is re-parsed"
]

VerificationTest[
    MarkdownInlineParse["~~bold $y$~~"],
    {MdStrike[{MdText["bold "], MdMathInline["y"]}]},
    TestID -> "strike containing math is re-parsed"
]

VerificationTest[
    MarkdownInlineParse["***`f[x]`***"],
    {MdBoldItalic[{MdCode["f[x]"]}]},
    TestID -> "bold-italic containing code is re-parsed"
]


(* ===== mixed prose ===== *)

VerificationTest[
    MarkdownInlineParse["a *b* and `c` and $d$ and **e**"],
    {
        MdText["a "],
        MdItalic[{MdText["b"]}],
        MdText[" and "],
        MdCode["c"],
        MdText[" and "],
        MdMathInline["d"],
        MdText[" and "],
        MdBold[{MdText["e"]}]
    },
    TestID -> "italic + code + math + bold mixed in prose"
]


(* ===== unclosed delimiters fall back to literal ===== *)

VerificationTest[
    MarkdownInlineParse["a *b without close"],
    {MdText["a *b without close"]},
    TestID -> "unclosed * stays literal"
]

VerificationTest[
    MarkdownInlineParse["x **bold but no close"],
    {MdText["x **bold but no close"]},
    TestID -> "unclosed ** stays literal"
]

VerificationTest[
    MarkdownInlineParse["see `code without close"],
    {MdText["see `code without close"]},
    TestID -> "unclosed ` stays literal"
]


(* ===== ellipsis ===== *)

VerificationTest[
    MarkdownInlineParse["wait..."],
    {MdText["wait\[Ellipsis]"]},
    TestID -> "literal ... in prose -> Unicode ellipsis"
]

VerificationTest[
    MarkdownInlineParse["`Range[1, ...]`"],
    {MdCode["Range[1, ...]"]},
    TestID -> "... inside code stays as three dots"
]


(* ===== precedence sanity ===== *)

VerificationTest[
    MarkdownInlineParse["``a`b``"],
    {MdLiteralCode["a`b"]},
    TestID -> "double-backtick wins over two adjacent single-backticks"
]

VerificationTest[
    MarkdownInlineParse["$$x$$"],
    {MdMathDisplay["x"]},
    TestID -> "double-dollar wins over two adjacent single-dollars"
]

VerificationTest[
    MarkdownInlineParse["~~~x~~~"],
    {MdStrike[{MdText["~x"]}], MdText["~"]},
    TestID -> "~~~ is parsed as ~~ ... ~~ first"
]

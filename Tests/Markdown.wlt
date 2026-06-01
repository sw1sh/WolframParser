(* :Title: Markdown inline-parser tests

   Each atom is an Association with a "Type" discriminator + payload keys
   ({"Type" -> "Text", "Text" -> ...} / {"Type" -> "Bold", "Children" ->
   ...} / ...) - same shape M2N's block-level parser uses. *)

Needs["Wolfram`Parser`"]

t[s_]            := <|"Type" -> "Text",         "Text" -> s|>
c[s_]            := <|"Type" -> "Code",         "Code" -> s|>
lc[s_]           := <|"Type" -> "LiteralCode",  "Code" -> s|>
hc[s_]           := <|"Type" -> "HtmlCode",     "Code" -> s|>
mi[s_]           := <|"Type" -> "MathInline",   "Math" -> s|>
md[s_]           := <|"Type" -> "MathDisplay",  "Math" -> s|>
lnk[lbl_, u_]    := <|"Type" -> "Link",         "Url" -> u, "Label" -> lbl|>
img[a_, u_]      := <|"Type" -> "Image",        "Alt"  -> a, "Url" -> u|>
sb[ch_]          := <|"Type" -> "Sub",          "Children" -> ch|>
sp[ch_]          := <|"Type" -> "Sup",          "Children" -> ch|>
b[ch_]           := <|"Type" -> "Bold",         "Children" -> ch|>
i[ch_]           := <|"Type" -> "Italic",       "Children" -> ch|>
bi[ch_]          := <|"Type" -> "BoldItalic",   "Children" -> ch|>
st[ch_]          := <|"Type" -> "Strike",       "Children" -> ch|>


(* ===== plain text + adjacent-run merging ===== *)

VerificationTest[
    MarkdownInlineParse["hello world"],
    {t["hello world"]},
    TestID -> "plain text is one Text atom"
]

VerificationTest[
    MarkdownInlineParse[""],
    {},
    TestID -> "empty source -> empty list"
]

VerificationTest[
    MarkdownInlineParse["a `x` b `y` c"],
    {t["a "], c["x"], t[" b "], c["y"], t[" c"]},
    TestID -> "text runs between code spans are coalesced"
]


(* ===== escapes ===== *)

VerificationTest[
    MarkdownInlineParse["a\\*b"],
    {t["a*b"]},
    TestID -> "backslash-star is a literal star"
]

VerificationTest[
    MarkdownInlineParse["price: \\$5"],
    {t["price: $5"]},
    TestID -> "backslash-dollar suppresses math"
]

VerificationTest[
    MarkdownInlineParse["\\[CircleTimes\\]"],
    {t["[CircleTimes]"]},
    TestID -> "backslash-bracket is a literal bracket"
]


(* ===== code spans ===== *)

VerificationTest[
    MarkdownInlineParse["`Range[5]`"],
    {c["Range[5]"]},
    TestID -> "single backtick -> Code"
]

VerificationTest[
    MarkdownInlineParse["``x``"],
    {lc["x"]},
    TestID -> "double backtick -> LiteralCode"
]

VerificationTest[
    MarkdownInlineParse["`` `nested` ``"],
    {lc["`nested`"]},
    TestID -> "double backtick wraps a literal single-backtick run"
]

VerificationTest[
    MarkdownInlineParse["<code>[Range]()[n]</code>"],
    {hc["[Range]()[n]"]},
    TestID -> "<code> wrapper carries its inner markdown verbatim"
]


(* ===== math ===== *)

VerificationTest[
    MarkdownInlineParse["$x + y$"],
    {mi["x + y"]},
    TestID -> "single-dollar -> MathInline"
]

VerificationTest[
    MarkdownInlineParse["$$x = y$$"],
    {md["x = y"]},
    TestID -> "double-dollar -> MathDisplay"
]

VerificationTest[
    MarkdownInlineParse["see $\\sqrt{x}$ here"],
    {t["see "], mi["\\sqrt{x}"], t[" here"]},
    TestID -> "math inside prose"
]


(* ===== links + images ===== *)

VerificationTest[
    MarkdownInlineParse["[label](https://example.com)"],
    {lnk[{t["label"]}, "https://example.com"]},
    TestID -> "[label](url) -> Link with parsed label"
]

VerificationTest[
    MarkdownInlineParse["[`Range`](paclet:ref/Range)"],
    {lnk[{c["Range"]}, "paclet:ref/Range"]},
    TestID -> "code-styled link label"
]

VerificationTest[
    MarkdownInlineParse["[Range]()"],
    {lnk[{t["Range"]}, ""]},
    TestID -> "empty url is preserved (inferred-link convention)"
]

VerificationTest[
    MarkdownInlineParse["![diagram](img/flow.png)"],
    {img["diagram", "img/flow.png"]},
    TestID -> "![alt](url) -> Image"
]


(* ===== sub / sup ===== *)

VerificationTest[
    MarkdownInlineParse["H<sub>2</sub>O"],
    {t["H"], sb[{t["2"]}], t["O"]},
    TestID -> "HTML <sub>"
]

VerificationTest[
    MarkdownInlineParse["e<sup>x</sup>"],
    {t["e"], sp[{t["x"]}]},
    TestID -> "HTML <sup>"
]

VerificationTest[
    MarkdownInlineParse["x~i~"],
    {t["x"], sb[{t["i"]}]},
    TestID -> "Pandoc ~x~ subscript"
]

VerificationTest[
    MarkdownInlineParse["e^2^"],
    {t["e"], sp[{t["2"]}]},
    TestID -> "Pandoc ^x^ superscript"
]

VerificationTest[
    MarkdownInlineParse["~~struck~~"],
    {st[{t["struck"]}]},
    TestID -> "~~text~~ is strikethrough, not double-subscript"
]


(* ===== emphasis: asterisks ===== *)

VerificationTest[
    MarkdownInlineParse["*italic*"],
    {i[{t["italic"]}]},
    TestID -> "*x* -> Italic"
]

VerificationTest[
    MarkdownInlineParse["**bold**"],
    {b[{t["bold"]}]},
    TestID -> "**x** -> Bold"
]

VerificationTest[
    MarkdownInlineParse["***both***"],
    {bi[{t["both"]}]},
    TestID -> "***x*** -> BoldItalic"
]

VerificationTest[
    MarkdownInlineParse["a *b* c"],
    {t["a "], i[{t["b"]}], t[" c"]},
    TestID -> "italic inside prose"
]


(* ===== emphasis: underscores (word-bounded) ===== *)

VerificationTest[
    MarkdownInlineParse["_em_"],
    {i[{t["em"]}]},
    TestID -> "_x_ -> Italic (children re-parsed)"
]

VerificationTest[
    MarkdownInlineParse["__strong__"],
    {b[{t["strong"]}]},
    TestID -> "__x__ -> Bold (children re-parsed)"
]

VerificationTest[
    MarkdownInlineParse["snake_case_name"],
    {t["snake_case_name"]},
    TestID -> "underscore between word chars stays literal (CommonMark intraword)"
]

VerificationTest[
    MarkdownInlineParse["see _file_name_ here"],
    {t["see "], i[{t["file_name"]}], t[" here"]},
    TestID -> "underscores around identifier with internal _ form one italic per CommonMark"
]


(* ===== recursion: child of one span is re-parsed as inline ===== *)

VerificationTest[
    MarkdownInlineParse["**bold $x$**"],
    {b[{t["bold "], mi["x"]}]},
    TestID -> "bold containing math is re-parsed"
]

VerificationTest[
    MarkdownInlineParse["*italic `code`*"],
    {i[{t["italic "], c["code"]}]},
    TestID -> "italic containing code is re-parsed"
]

VerificationTest[
    MarkdownInlineParse["~~bold $y$~~"],
    {st[{t["bold "], mi["y"]}]},
    TestID -> "strike containing math is re-parsed"
]

VerificationTest[
    MarkdownInlineParse["***`f[x]`***"],
    {bi[{c["f[x]"]}]},
    TestID -> "bold-italic containing code is re-parsed"
]


(* ===== mixed prose ===== *)

VerificationTest[
    MarkdownInlineParse["a *b* and `c` and $d$ and **e**"],
    {t["a "], i[{t["b"]}], t[" and "], c["c"], t[" and "], mi["d"], t[" and "], b[{t["e"]}]},
    TestID -> "italic + code + math + bold mixed in prose"
]


(* ===== unclosed delimiters fall back to literal ===== *)

VerificationTest[
    MarkdownInlineParse["a *b without close"],
    {t["a *b without close"]},
    TestID -> "unclosed * stays literal"
]

VerificationTest[
    MarkdownInlineParse["x **bold but no close"],
    {t["x **bold but no close"]},
    TestID -> "unclosed ** stays literal"
]

VerificationTest[
    MarkdownInlineParse["see `code without close"],
    {t["see `code without close"]},
    TestID -> "unclosed ` stays literal"
]


(* ===== ellipsis ===== *)

VerificationTest[
    MarkdownInlineParse["wait..."],
    {t["wait\[Ellipsis]"]},
    TestID -> "literal ... in prose -> Unicode ellipsis"
]

VerificationTest[
    MarkdownInlineParse["`Range[1, ...]`"],
    {c["Range[1, ...]"]},
    TestID -> "... inside code stays as three dots"
]


(* ===== precedence sanity ===== *)

VerificationTest[
    MarkdownInlineParse["``a`b``"],
    {lc["a`b"]},
    TestID -> "double-backtick wins over two adjacent single-backticks"
]

VerificationTest[
    MarkdownInlineParse["$$x$$"],
    {md["x"]},
    TestID -> "double-dollar wins over two adjacent single-dollars"
]

VerificationTest[
    MarkdownInlineParse["~~~x~~~"],
    {st[{t["~x"]}], t["~"]},
    TestID -> "~~~ is parsed as ~~ ... ~~ first"
]


(* ===== block-level: MarkdownParse =====

   Each block is an Association with a "Type" discriminator + payload
   keys; the whole document is <|"Metadata" -> <|...|>, "Blocks" -> [...]|>.
   First-pass coverage: frontmatter, headings, code fences with #|
   options, separators, prose paragraphs. *)

h[lvl_, s_]                  := <|"Type" -> "Heading",   "Level" -> lvl, "Text" -> s|>
sep                          := <|"Type" -> "Separator"|>
pr[s_]                       := <|"Type" -> "Prose",     "Text" -> s|>
cb[lang_, codeStr_, opts_]   := <|"Type" -> "Code",      "Lang" -> lang, "Code" -> codeStr, "Options" -> opts|>
doc[meta_, blocks_]          := <|"Metadata" -> meta,    "Blocks" -> blocks|>


VerificationTest[
    MarkdownParse[""],
    doc[<||>, {}],
    TestID -> "empty source -> empty doc"
]

VerificationTest[
    MarkdownParse["# Title\n"],
    doc[<||>, {h[1, "Title"]}],
    TestID -> "single heading, no frontmatter"
]

VerificationTest[
    MarkdownParse["# A\n\n## B\n\n### C\n"],
    doc[<||>, {h[1, "A"], h[2, "B"], h[3, "C"]}],
    TestID -> "three headings, increasing level"
]

VerificationTest[
    MarkdownParse["A paragraph.\n"],
    doc[<||>, {pr["A paragraph."]}],
    TestID -> "single-line prose"
]

VerificationTest[
    MarkdownParse["Line one.\nLine two.\nLine three.\n"],
    doc[<||>, {pr["Line one. Line two. Line three."]}],
    TestID -> "soft-wrapped paragraph joins lines with space"
]

VerificationTest[
    MarkdownParse["# Title\n\nIntro.\n\n## Section\n\nMore.\n"],
    doc[<||>, {h[1, "Title"], pr["Intro."], h[2, "Section"], pr["More."]}],
    TestID -> "mixed headings and prose"
]

VerificationTest[
    MarkdownParse["before\n\n---\n\nafter\n"],
    doc[<||>, {pr["before"], sep, pr["after"]}],
    TestID -> "thematic break (---) between prose"
]

VerificationTest[
    MarkdownParse["```wl\n1 + 1\n```\n"],
    doc[<||>, {cb["wl", "1 + 1", <||>]}],
    TestID -> "code fence with lang, no options"
]

VerificationTest[
    MarkdownParse["```\nbare\n```\n"],
    doc[<||>, {cb["", "bare", <||>]}],
    TestID -> "code fence with no lang"
]

VerificationTest[
    MarkdownParse["```wl\n#| eval: true\n#| screenshot: false\n1 + 1\n```\n"],
    doc[<||>, {cb["wl", "1 + 1", <|"eval" -> "true", "screenshot" -> "false"|>]}],
    TestID -> "code fence with #| options"
]

VerificationTest[
    MarkdownParse["---\nTemplate: TechNote\nName: Demo\n---\n\n# T\n"],
    doc[<|"Template" -> "TechNote", "Name" -> "Demo"|>, {h[1, "T"]}],
    TestID -> "frontmatter then a heading"
]

VerificationTest[
    MarkdownParse["---\nKeywords: [foo, bar, baz]\n---\n\nText.\n"],
    doc[<|"Keywords" -> {"foo", "bar", "baz"}|>, {pr["Text."]}],
    TestID -> "frontmatter [list] value"
]

VerificationTest[
    MarkdownParse["---\nTemplate: TechNote\nName: Demo\n---\n\n# T\n\nA para.\n\n```wl\n#| eval: true\n1+1\n```\n"],
    doc[
        <|"Template" -> "TechNote", "Name" -> "Demo"|>,
        {h[1, "T"], pr["A para."], cb["wl", "1+1", <|"eval" -> "true"|>]}
    ],
    TestID -> "full document: frontmatter + heading + prose + fenced code with options"
]

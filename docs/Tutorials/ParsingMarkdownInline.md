---
Template: TechNote
Name: ParsingMarkdownInline
Title: A Markdown Inline Parser in Parser Combinators
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/ParsingMarkdownInline
Keywords: [markdown, inline parser, ParserCombinator, ParseChoice, ParseNotFollowedBy, ParseAction, recursion, PEG, MarkdownInlineParse, MarkdownParse, Association]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingGrammarRules, DesignAndCompilationStrategy, LaTeXMathParserImplementation]
---

## What this note covers

[MarkdownInlineParse]() is a parser for inline markdown - the inside-a-paragraph constructs of CommonMark: emphasis (`*italic*`, `**bold**`, `***both***`, `~~strike~~`), code spans (`` `code` ``, ` ``literal`` `, `<code>...</code>`), inline math (`$...$`, `$$...$$`), links (`[label](url)`), images (`![alt](url)`), HTML and Pandoc sub/sup (`<sub>x</sub>`, `H~2~O`, `e^2^`), backslash escapes (`\*`, `\$`, `\\`), and underscore emphasis with CommonMark word-boundary rules (`_em_`, `__strong__`, but not `snake_case`).

It returns a flat list of inline atoms; each atom is an [Association]() with a `"Type"` discriminator plus payload keys - the same convention [MarkdownParse]() and M2N's block-level parser use, so downstream code can pattern-match on `"Type"` uniformly across both layers.

The whole grammar is **~75 lines** of [ParseChoice]() / [ParseAction]() / [ParseNotFollowedBy]() over the <code>Wolfram\`Parser\`</code> primitives. No [StringSplit](), no regex hand-tuning, no per-rule iteration. The PEG order in one [ParseChoice]() resolves the precedence ambiguities (`**bold**` wins over `*italic*` opened twice; `***both***` wins over `*`-`**both**`-`*`).

This note has three parts:

1. **The AST** - what `MarkdownInlineParse` returns.
2. **The grammar** - line-by-line walkthrough of the combinator chain.
3. **Recursion and post-processing** - how nested emphasis (`**bold $x$**`) gets re-parsed and how the CommonMark word-boundary rules for underscore emphasis fall out as a small post-pass.

---

## Part 1 - The AST

<code>MarkdownInlineParse[source]</code> returns a [List]() of inline atoms. Each atom is an [Association]() with a `"Type"` discriminator and per-shape payload keys:

| `"Type"`        | Other keys                | Markdown form                |
|-----------------|---------------------------|------------------------------|
| `"Text"`        | `"Text" -> str`           | plain text run               |
| `"Code"`        | `"Code" -> str`           | `` `code` ``                 |
| `"LiteralCode"` | `"Code" -> str`           | ` ``code`` ` (verbatim)      |
| `"HtmlCode"`    | `"Code" -> str`           | `<code>...</code>`           |
| `"MathInline"`  | `"Math" -> str`           | `$x$`                        |
| `"MathDisplay"` | `"Math" -> str`           | `$$x$$`                      |
| `"Link"`        | `"Label" -> [atoms]`, `"Url" -> str` | `[label](url)`    |
| `"Image"`       | `"Alt" -> str`, `"Url" -> str`       | `![alt](url)`     |
| `"Sub"`         | `"Children" -> [atoms]`   | `<sub>x</sub>` or `~x~`      |
| `"Sup"`         | `"Children" -> [atoms]`   | `<sup>x</sup>` or `^x^`      |
| `"Bold"`        | `"Children" -> [atoms]`   | `**x**` or `__x__`           |
| `"Italic"`      | `"Children" -> [atoms]`   | `*x*` or `_x_`               |
| `"BoldItalic"`  | `"Children" -> [atoms]`   | `***x***`                    |
| `"Strike"`      | `"Children" -> [atoms]`   | `~~x~~`                      |

The `"Children"` / `"Label"` for spans are themselves [List]()s of inline atoms (the body was re-parsed), so `**bold $x$**` lands as `<|"Type" -> "Bold", "Children" -> {<|"Type" -> "Text", "Text" -> "bold "|>, <|"Type" -> "MathInline", "Math" -> "x"|>}|>`. Adjacent `"Text"` atoms are coalesced so consumers see one run per contiguous prose chunk, never one atom per character.

Using [Association]()s with a `"Type"` key instead of a sum-type-headed expression matches the convention M2N's block-level parser uses (`<|"Type" -> "Heading", "Level" -> n, "Text" -> str|>` etc.), so downstream code reading the parse tree can pattern-match on `atom["Type"]` uniformly across the inline and block layers without learning two AST shapes.

Plain prose comes out as a single `"Text"` atom:

```wl
MarkdownInlineParse["plain text"]
```

Mixed prose, emphasis, math, and code:

```wl
MarkdownInlineParse["**bold $x$** and `code`"]
```

A link with a code-styled label demonstrates recursive label parsing - the label itself is a list of inline atoms:

```wl
MarkdownInlineParse["[`Range`](paclet:ref/Range)"]
```

---

## Part 2 - The grammar

The whole parser lives in [examples/WolframParser/Kernel/Markdown.wl](https://github.com/sw1sh/WolframParser/blob/main/Kernel/Markdown.wl). The grammar is one big [ParseChoice]() and lots of small [ParseAction]() arms.

### The bounded-content helper

Every paired-delimiter span needs to consume "everything until the closing delimiter". The trick is [ParseNotFollowedBy](): at each position, refuse to consume a character if the next characters would form the closing delimiter.

```wl
content[term_] := ParseAction[
    ParseSome[ParseAction[ParseNotFollowedBy[term] ~~ anyChar, #2 &]],
    StringJoin[{##}] &
]
```

Reading the body: `anyChar` is <code>[ParseCharacter]()[_]</code>; <code>[ParseNotFollowedBy]()[term]</code> is a zero-width assertion that the next characters do *not* start `term`. Their sequence consumes one char only when `term` doesn't start there. [ParseSome]() iterates the assertion-plus-char until [ParseNotFollowedBy]() fires, at which point [ParseSome]() stops and the outer [ParseAction]() joins the accumulated chars into a string.

<code>content[[ParseLiteral]()["**"]]</code> matches `"foo $x$"` and stops cleanly at the `**` of `"foo $x$**"` - which is exactly the bound a `**foo $x$**` body needs.

### Paired spans

Every paired span is a literal-open / `content[close]` / literal-close trio. The grammar reads a few private helper constructors (`text`, `codeAtom`, `mathIn`, `bold`, ...) that each build the corresponding `"Type"`-tagged [Association]() - keeping the AST construction in one place so the grammar arms stay readable.

Inline code:

```wl
code = ParseAction[
    ParseLiteral["`"] ~~ content[ParseLiteral["`"]] ~~ ParseLiteral["`"],
    codeAtom[#2] &
]
```

Inline math:

```wl
inlineMath = ParseAction[
    ParseLiteral["$"] ~~ content[ParseLiteral["$"]] ~~ ParseLiteral["$"],
    mathIn[#2] &
]
```

Bold:

```wl
boldP = ParseAction[
    ParseLiteral["**"] ~~ content[ParseLiteral["**"]] ~~ ParseLiteral["**"],
    bold[#2] &
]
```

The `#2 &` arm takes the second result (the content; the first is the open literal, the third is the close) and wraps it in the appropriate atom constructor.

### Escapes and the plain-character catch-all

A backslash followed by ASCII punctuation collapses to that punctuation, so `\*` becomes a literal `*` instead of opening an italic span:

```wl
escape = ParseAction[
    ParseLiteral["\\"] ~~ charSat[asciiPunct],
    text[#2] &
]
```

After every other alternative has had a chance, the catch-all `plainChar` consumes one character and wraps it in a `"Text"` atom:

```wl
plainChar = ParseAction[anyChar, text[#1] &]
```

[ParseSome]() over the outer [ParseChoice]() iterates this until the input is exhausted; the post-process step `mergeText` coalesces consecutive `"Text"` atoms so prose comes out as one run, not one atom per character.

### Links and images

The label can contain markdown itself, but capturing it character-by-character at the top level would be wrong (we'd lose the structure). Instead capture the raw label *string* during parse and re-parse it after:

```wl
linkP = ParseAction[
    ParseLiteral["["] ~~ linkLabel ~~ ParseLiteral["]("] ~~ linkUrl ~~ ParseLiteral[")"],
    link[#2, #4] &
]
```

`linkLabel` is <code>[ParseSome]()[[ParseNotFollowedBy]()[[ParseLiteral]()["]"]] ~~ anyChar]</code> joined to a string - similar to `content[]`, but the body is "any character that isn't `]`". `linkUrl` is the same shape with `)`. The `link[#2, #4]` action stores them; recursive re-parsing of the label happens in Part 3.

`imageP` is the same with a leading `!`, listed first in the [ParseChoice]() so `![` opens an image and not a link with `!` prefix.

### PEG ordering: longer prefixes first

The full alternation:

```wl
inlineAtom = ParseChoice[
    escape,                                                                 (* \x      *)
    codeHtml, imageP, linkP,                                                (* HTML / [ / ![ *)
    dblCode, code,                                                          (* ``  `   *)
    displayMath, inlineMath,                                                (* $$  $   *)
    strikeP,                                                                (* ~~      *)
    htmlSub, htmlSup,                                                       (* <sub> <sup> *)
    boldItalicP, boldP, italicAst,                                          (* *** ** *  *)
    pandocSub, pandocSup,                                                   (* ~  ^    *)
    plainChar                                                               (* fallback *)
]
```

Within each opening-character family the longest opener comes first:

- ` `` ` before `` ` `` so `` `` `x` `` `` matches one `"LiteralCode"`, not three nested `"Code"` spans.
- `$$` before `$` so `$$x$$` is one `"MathDisplay"`, not two empty `"MathInline"`s.
- `***` before `**` before `*` so `***x***` is one `"BoldItalic"`, not `*`-`**x**`-`*`.
- `<sub>` before `~` so the HTML form wins when both are syntactically possible (`<sub>` carrying a `~` inside).

These are the standard PEG-prefix rules. None of them require a lookahead or a special action - just ordering the [ParseChoice]() arms longer-first.

### Word-bounded asterisk italic

`*italic*` opens at any `*` not followed by a space (so `* list item` stays plain) and closes at the next `*` that isn't part of a doubled `**`. Both rules fall out of the alternative-order plus a single body restriction:

```wl
italicAstBody = ParseAction[ParseSome[charSat[# =!= "*" &]], StringJoin[{##}] &]
italicAst = ParseAction[
    ParseLiteral["*"] ~~ ParseNotFollowedBy[ParseLiteral[" "]] ~~ italicAstBody ~~ ParseLiteral["*"],
    italic[#3] &
]
```

The body forbids `*` so `**bold**` never re-matches as `*`-`*bold*`-`*` after `bold` has been tried; the no-leading-space lookahead keeps `* list item` from being parsed as `*` opening italic.

---

## Part 3 - Recursion and post-processing

The combinator grammar produces a "raw" tree where the `"Children"` / `"Label"` of bold / italic / strike / sub / sup / link atoms are still the captured body **strings**, not re-parsed inline-atom lists. Three small post-processing passes finish the job:

### Recursive children

```wl
reparseChildren[atoms_List] := Replace[atoms, {
    a_Association /; MemberQ[{"Bold", "Italic", "BoldItalic", "Strike", "Sub", "Sup"}, a["Type"]] &&
        StringQ[a["Children"]] :>
        Append[a, "Children" -> runInner[a["Children"]]],
    a_Association /; a["Type"] === "Link" && StringQ[a["Label"]] :>
        Append[a, "Label" -> runInner[a["Label"]]]
}, {1}]

runInner[s_String] := MarkdownInlineParse[s]
```

`runInner` calls the public entry point on the captured body string, so the full grammar applies to the body too. That's how `**bold $x$**` ends up as `<|"Type" -> "Bold", "Children" -> {<|"Type" -> "Text", "Text" -> "bold "|>, <|"Type" -> "MathInline", "Math" -> "x"|>}|>` rather than `<|"Type" -> "Bold", "Children" -> "bold $x$"|>`.

### Adjacent-text merging

The catch-all `plainChar` emits one `"Text"` atom per character. After parsing finishes:

```wl
mergeText[atoms_List] := Block[{step},
    step[acc_, a_ ? textQ] := If[acc =!= {} && textQ[Last[acc]],
        Append[Most[acc], text[Last[acc]["Text"] <> a["Text"]]],
        Append[acc, a]
    ];
    step[acc_, other_] := Append[acc, other];
    Fold[step, {}, atoms]
]
```

[Fold]() coalesces consecutive `"Text"` atoms into one. The non-`"Text"` atoms break the run, which is exactly the segmentation a downstream consumer wants.

### Underscore emphasis (CommonMark word boundaries)

Underscore emphasis is the one rule that *isn't* trivially expressible as a paired delimiter, because `snake_case` must NOT open italic but `see _em_ there` must. CommonMark says: a `_` can open emphasis only if it's left-flanking AND (not right-flanking OR preceded by punctuation). Equivalently for our purposes: a `_` opens / closes at a word boundary (start of string, end of string, or adjacent to a non-word character).

The grammar doesn't try to express the lookbehind/lookahead rules; instead a post-pass scans each `"Text"` run with two regular expressions:

```wl
underscoreRules = {
    RegularExpression["(?<![A-Za-z0-9_])__(\\S|\\S.*?\\S)__(?![A-Za-z0-9_])"] -> "\:f001$1\:f002",
    RegularExpression["(?<![A-Za-z0-9_])_(\\S|\\S.*?\\S)_(?![A-Za-z0-9_])"]   -> "\:f003$1\:f004"
}
```

The captured bodies get sentinel-wrapped, then a [StringSplit]() turns each wrapped run into a `"Bold"` / `"Italic"` atom whose body is itself re-parsed (so a `_x **bold** y_` italic still re-parses its body). The sentinels are private-use Unicode codepoints that no real markdown source ships, so they never collide with prose.

Because this pass scans only `"Text"` atoms, an underscore inside a `"Code"` (`snake_case`) or `"MathInline"` (`x_i`) atom is left alone - the literal underscores in code and math always survive.

---

## Part 4 - The full document parser

[MarkdownInlineParse]() handles inline constructs only.  [MarkdownParse]() (in the same package) wraps it with a block-level grammar that also handles whole-document structure:

- **Frontmatter** - the `---` delimited YAML-ish header at the top of every M2N source document. Parsed to an [Association]() of metadata; the bracketed list syntax (`Keywords: [foo, bar]`) becomes a [List]() of strings, quoted scalars are unquoted.
- **Headings** - `#`, `##`, ... up to any depth. Level is the count of `#`s; the trailing text is captured raw and can be inline-parsed by the caller.
- **Code fences** - <code>``` </code>+`lang` openings, optional `#|` option lines at the top of the fence, then the body, then the closing <code>```</code>. Options end up as an [Association]() under the block's `"Options"` key, matching the shape M2N has used for years.
- **Thematic breaks** - `---` / `***` / `___` on a line of their own.
- **Prose paragraphs** - one or more non-blank lines that don't start a block; soft-wrapped lines join with `" "`.

```wl
MarkdownParse["---\nTemplate: TechNote\nName: Demo\n---\n\n# Title\n\nA paragraph.\n\n```wl\n#| eval: true\n1+1\n```\n"]
```

The result mirrors M2N's `litParse` shape exactly:

```wl
<|"Metadata" -> <|"Template" -> "TechNote", "Name" -> "Demo"|>,
  "Blocks"   -> {
      <|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>,
      <|"Type" -> "Prose", "Text" -> "A paragraph."|>,
      <|"Type" -> "Code", "Lang" -> "wl", "Code" -> "1+1", "Options" -> <|"eval" -> "true"|>|>
  }|>
```

Lists, tables, blockquotes, math blocks (`$$ ... $$` on a line), and fenced `:::` divs aren't yet covered by the combinator grammar - they currently fall into the prose catch-all and are slated for a follow-up tutorial as they land.

---

## Why this matters

[MarkdownInlineParse]() was a hand-rolled [StringSplit]() cascade in [MarkdownToNotebook]() until the parser combinator core matured enough to express the whole grammar declaratively. The end result is shorter (~75 lines vs ~120), correct on every regression case (56 [VerificationTest]()s in [Tests/Markdown.wlt](https://github.com/sw1sh/WolframParser/blob/main/Tests/Markdown.wlt)), and provably handles the PEG-precedence rules without per-position bookkeeping. It's the smallest non-trivial showcase of <code>Wolfram\`Parser\`</code> against real-world syntax beyond LaTeX math and TPTP - the same primitives, a wholly different domain.

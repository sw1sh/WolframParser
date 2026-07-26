---
Template: Symbol
Name: MarkdownInlineParse
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MarkdownInlineParse
Keywords: [markdown, inline, emphasis, code span, link, image, math, subscript, superscript, CommonMark, AST]
SeeAlso: [MarkdownInlineParser, MarkdownParse, MarkdownParser, Parse, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MarkdownInlineParse]()[*source*]</code> parses inline markdown *source* (a [String]() — the span-level content of a single paragraph) into a flat [List]() of inline-atom [Association]()s, each carrying a `"Type"` discriminator (`"Text"`, `"Bold"`, `"Italic"`, `"Code"`, `"Link"`, `"MathInline"`, …) plus per-shape payload keys.

## Details & Options

- The result is a flat [List]() of [Association]()s. Prose runs are `<|"Type" -> "Text", "Text" -> str|>`; emphasis is `"Bold"` / `"Italic"` / `"BoldItalic"`; code is `"Code"` / `"LiteralCode"` / `"HtmlCode"`; math is `"MathInline"` / `"MathDisplay"`; the paired references are `"Link"` and `"Image"`; and `"Sub"` / `"Sup"` / `"Strike"` cover the remaining spans.
- A span's body — the `"Children"` of an emphasis / sub / sup / strike atom, or the `"Label"` of a link — is itself a [List]() of inline atoms, because the captured body is re-parsed recursively. So `**bold $x$**` nests a `"MathInline"` atom inside the `"Bold"`.
- Adjacent `"Text"` atoms are merged, so a contiguous prose run is one atom, not one atom per character.
- Overlapping openers resolve by PEG order, longest first: `***` before `**` before `*`, double backtick before single, `$$` before `$`, and the HTML `<sub>` / `<sup>` before their single-character Pandoc twins.
- Underscore emphasis follows CommonMark word-boundary rules: `_em_` opens emphasis at a word boundary, but an underscore between word characters (`snake_case`) stays literal.
- A literal `...` inside a `"Text"` run becomes the Unicode ellipsis character; `...` inside a code span or math span is left verbatim.
- A backslash before ASCII punctuation (`\*`, `\$`) yields that punctuation as literal text rather than opening a span.
- An unclosed delimiter is not an error — the opener and its trailing text stay as literal `"Text"`.
- [MarkdownInlineParse]() handles inline constructs only. Whole-document structure (frontmatter, headings, code fences, thematic breaks, paragraph splitting) is [MarkdownParse]()'s job; feed a document's `"Prose"` block text through this function to resolve its spans.
- [MarkdownInlineParse]() is the wrapper around the [MarkdownInlineParser]() combinator: it runs [Parse]() and then merges text runs, applies the ellipsis and underscore-emphasis passes, and re-parses span children. On a parse failure it returns the [Failure]() object unchanged.

The grammar and its post-processing passes are walked through in the [Markdown inline parser tutorial](paclet:Wolfram/Parser/tutorial/ParsingMarkdownInline).

## Basic Examples

Plain prose is a single `"Text"` atom:

```wl
MarkdownInlineParse["plain text"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "plain text"|>} -->

<!-- #| annotation: 26.07.26: Design review - replaces the hand-rolled StringSplit cascade MarkdownToNotebook used for inline markdown with a declarative ParseChoice grammar over the ParserCombinator primitives; PEG ordering resolves the emphasis-precedence ambiguities without per-position bookkeeping. The post-processing (text merge, ellipsis, underscore emphasis, recursive children) lives in this wrapper, not in the combinator. Alternative representation considered: sum-type expression heads instead of "Type"-keyed Associations - the Association shape was kept so inline and block ASTs pattern-match the same way. -->

Emphasis and code spans become their own atoms, with the surrounding prose in `"Text"` runs:

```wl
MarkdownInlineParse["**bold** and `code`"]
```

<!-- => {<|"Type" -> "Bold", "Children" -> {<|"Type" -> "Text", "Text" -> "bold"|>}|>, <|"Type" -> "Text", "Text" -> " and "|>, <|"Type" -> "Code", "Code" -> "code"|>} -->

A link's label is parsed recursively — here it is a code span, not plain text:

```wl
MarkdownInlineParse["[`Range`](paclet:ref/Range)"]
```

<!-- => {<|"Type" -> "Link", "Url" -> "paclet:ref/Range", "Label" -> {<|"Type" -> "Code", "Code" -> "Range"|>}|>} -->

## Scope

### Nested emphasis

A span's children are re-parsed, so inline math inside a bold run nests as its own atom:

```wl
MarkdownInlineParse["**bold $x$**"]
```

<!-- => {<|"Type" -> "Bold", "Children" -> {<|"Type" -> "Text", "Text" -> "bold "|>, <|"Type" -> "MathInline", "Math" -> "x"|>}|>} -->

---

Three asterisks resolve longest-first, so `***…***` is one `"BoldItalic"` rather than an italic wrapping a bold:

```wl
MarkdownInlineParse["***both***"]
```

<!-- => {<|"Type" -> "BoldItalic", "Children" -> {<|"Type" -> "Text", "Text" -> "both"|>}|>} -->

### Underscore emphasis and word boundaries

An underscore between word characters is intraword and stays literal, so an identifier is one `"Text"` run:

```wl
MarkdownInlineParse["snake_case_name"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "snake_case_name"|>} -->

---

At a word boundary the same underscore opens emphasis:

```wl
MarkdownInlineParse["see _em_ here"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "see "|>, <|"Type" -> "Italic", "Children" -> {<|"Type" -> "Text", "Text" -> "em"|>}|>, <|"Type" -> "Text", "Text" -> " here"|>} -->

### Sub, super, and strike

An HTML `<sub>` becomes a `"Sub"` atom between the surrounding text:

```wl
MarkdownInlineParse["H<sub>2</sub>O"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "H"|>, <|"Type" -> "Sub", "Children" -> {<|"Type" -> "Text", "Text" -> "2"|>}|>, <|"Type" -> "Text", "Text" -> "O"|>} -->

---

A `~~…~~` run is strikethrough, not a doubled subscript:

```wl
MarkdownInlineParse["~~struck~~"]
```

<!-- => {<|"Type" -> "Strike", "Children" -> {<|"Type" -> "Text", "Text" -> "struck"|>}|>} -->

### Images and math

`![alt](url)` is an `"Image"` atom carrying its alt text and URL:

```wl
MarkdownInlineParse["![alt](img.png)"]
```

<!-- => {<|"Type" -> "Image", "Alt" -> "alt", "Url" -> "img.png"|>} -->

---

Doubled dollars are display math, distinct from the single-dollar `"MathInline"` form:

```wl
MarkdownInlineParse["$$x$$"]
```

<!-- => {<|"Type" -> "MathDisplay", "Math" -> "x"|>} -->

## Properties and Relations

Consecutive prose is coalesced, so mixed content alternates one span atom with one merged text run:

```wl
MarkdownInlineParse["a *b* and `c` and $d$"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "a "|>, <|"Type" -> "Italic", "Children" -> {<|"Type" -> "Text", "Text" -> "b"|>}|>, <|"Type" -> "Text", "Text" -> " and "|>, <|"Type" -> "Code", "Code" -> "c"|>, <|"Type" -> "Text", "Text" -> " and "|>, <|"Type" -> "MathInline", "Math" -> "d"|>} -->

---

The ellipsis pass rewrites `...` in prose to a single Unicode character:

```wl
MarkdownInlineParse["wait..."]
```

<!-- => {<|"Type" -> "Text", "Text" -> "wait…"|>} -->

---

Inside a code span the three dots are kept verbatim — post-processing touches only `"Text"` atoms:

```wl
MarkdownInlineParse["`Range[1, ...]`"]
```

<!-- => {<|"Type" -> "Code", "Code" -> "Range[1, ...]"|>} -->

## Possible Issues

An unclosed delimiter does not fail — the opener stays as literal text:

```wl
MarkdownInlineParse["a *b without close"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "a *b without close"|>} -->

---

Block markers are not inline syntax, so a leading `#` is plain text, not a heading — use [MarkdownParse]() for document structure:

```wl
MarkdownInlineParse["# Heading"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "# Heading"|>} -->

## Neat Examples

A bold-italic span whose whole body is a code span re-parses the body, so the `"BoldItalic"` holds one `"Code"` child:

```wl
MarkdownInlineParse["***`f[x]`***"]
```

<!-- => {<|"Type" -> "BoldItalic", "Children" -> {<|"Type" -> "Code", "Code" -> "f[x]"|>}|>} -->

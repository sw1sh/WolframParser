---
Template: Symbol
Name: MarkdownParse
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MarkdownParse
Keywords: [markdown, document, block, frontmatter, heading, code fence, prose, AST, CommonMark]
SeeAlso: [MarkdownParser, MarkdownInlineParse, MarkdownInlineParser, Parse, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MarkdownParse]()[*source*]</code> parses a whole markdown document *source* (a [String]()) into an [Association]() of its frontmatter (under the `"Metadata"` key) and an ordered list of typed block [Association]()s (under `"Blocks"`) — headings, code fences, thematic breaks, and prose paragraphs.

## Details & Options

- The result is a two-key [Association](): `"Metadata"` holds the parsed frontmatter, `"Blocks"` holds the document body as an ordered [List]() of block [Association]()s.
- Every block is a `"Type"`-discriminated [Association](): a heading is `<|"Type" -> "Heading", "Level" -> n, "Text" -> str|>`, a code fence is `<|"Type" -> "Code", "Lang" -> str, "Code" -> str, "Options" -> <|…|>|>`, a thematic break is `<|"Type" -> "Separator"|>`, and a paragraph is `<|"Type" -> "Prose", "Text" -> str|>`.
- A heading's `"Level"` is the count of leading `#` characters; the trailing text is captured raw.
- Frontmatter is the `---`-delimited header at the top of the document, parsed to an [Association](). A bracketed value (`Keywords: [a, b]`) becomes a [List]() of strings and a quoted scalar is unquoted; a document with no frontmatter gets `"Metadata" -> <||>`.
- A code fence's leading `#|` option lines are collected into its `"Options"` [Association](); the remaining lines are the `"Code"`.
- A `"Prose"` block's `"Text"` is the raw inline markdown, with soft-wrapped lines joined by a space. Pass it to [MarkdownInlineParse]() to resolve the inline spans (emphasis, code, links, math).
- [MarkdownParse]() covers frontmatter, headings, code fences, thematic breaks, and prose paragraphs. Lists, tables, blockquotes, standalone math blocks, and fenced `:::` divs are not yet block constructs and currently fall into the `"Prose"` catch-all.
- [MarkdownParse]() appends a trailing newline to *source* if it lacks one, so a document without a final newline still parses. The underlying [MarkdownParser]() combinator does not add it.
- <code>[MarkdownParse]()[*source*]</code> is <code>[Parse]()[[MarkdownParser](), *source*]</code> once the trailing newline is in place — the same document [Association]() either way.

## Basic Examples

A one-heading, one-paragraph document parses to a heading block and a prose block:

```wl
MarkdownParse["# Title\n\nA paragraph.\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>, <|"Type" -> "Prose", "Text" -> "A paragraph."|>}|> -->

<!-- #| annotation: 26.07.26: Design review - MarkdownParse returns a "Type"-discriminated Association AST (Metadata + typed Blocks) rather than emitting Cell/box expressions directly the way ImportString[…, "Markdown"] and MarkdownToNotebook's earlier StringSplit cascade did; the block and inline layers share the same <|"Type" -> …|> shape so one pattern-match style reads both. Block coverage is a first pass (frontmatter, headings, fences, breaks, prose); lists/tables/blockquotes fall to Prose until they land. -->

The heading `"Level"` is the number of leading `#` characters:

```wl
MarkdownParse["### Section\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 3, "Text" -> "Section"|>}|> -->

## Scope

Frontmatter becomes the `"Metadata"` association, and the body follows:

```wl
MarkdownParse["---\nTemplate: Symbol\nName: Demo\n---\n\n# T\n"]
```

<!-- => <|"Metadata" -> <|"Template" -> "Symbol", "Name" -> "Demo"|>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "T"|>}|> -->

---

A bracketed frontmatter value parses to a [List]() of strings:

```wl
MarkdownParse["---\nKeywords: [foo, bar, baz]\n---\n\nText.\n"]
```

<!-- => <|"Metadata" -> <|"Keywords" -> {"foo", "bar", "baz"}|>, "Blocks" -> {<|"Type" -> "Prose", "Text" -> "Text."|>}|> -->

---

A code fence keeps its language tag, body, and `#|` options separate:

```wl
MarkdownParse["```wl\n#| eval: true\n1 + 1\n```\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Code", "Lang" -> "wl", "Code" -> "1 + 1", "Options" -> <|"eval" -> "true"|>|>}|> -->

---

A `---` line between paragraphs is a thematic break, not frontmatter:

```wl
MarkdownParse["before\n\n---\n\nafter\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Prose", "Text" -> "before"|>, <|"Type" -> "Separator"|>, <|"Type" -> "Prose", "Text" -> "after"|>}|> -->

---

Soft-wrapped lines join into a single prose block with spaces:

```wl
MarkdownParse["Line one.\nLine two.\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Prose", "Text" -> "Line one. Line two."|>}|> -->

## Properties and Relations

Block prose is left as raw inline source; [MarkdownInlineParse]() resolves the spans inside it. Take the first block's text:

```wl
MarkdownParse["This has **bold** text.\n"]["Blocks"][[1]]["Text"]
```

<!-- => "This has **bold** text." -->

---

Feeding that raw text to [MarkdownInlineParse]() splits it into inline atoms, so the two layers compose:

```wl
MarkdownInlineParse[MarkdownParse["This has **bold** text.\n"]["Blocks"][[1]]["Text"]]
```

<!-- => {<|"Type" -> "Text", "Text" -> "This has "|>, <|"Type" -> "Bold", "Children" -> {<|"Type" -> "Text", "Text" -> "bold"|>}|>, <|"Type" -> "Text", "Text" -> " text."|>} -->

---

[MarkdownParse]() supplies the trailing newline the line-based grammar needs, so a source without one still parses:

```wl
MarkdownParse["# Title"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>}|> -->

---

With the newline already present, [MarkdownParse]() and the raw [MarkdownParser]() combinator agree exactly:

```wl
MarkdownParse["# Title\n"] === Parse[MarkdownParser, "# Title\n"]
```

<!-- => True -->

## Possible Issues

Constructs the block grammar does not yet cover fall into the prose catch-all. A bullet list is currently one prose paragraph, not a list block:

```wl
MarkdownParse["- one\n- two\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Prose", "Text" -> "- one - two"|>}|> -->

---

An empty source is a document with empty metadata and no blocks:

```wl
MarkdownParse[""]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {}|> -->

## Neat Examples

A full page-shaped source — frontmatter, heading, prose, and a code fence — parses to the metadata plus one block per construct:

```wl
MarkdownParse["---\nName: Demo\n---\n\n# Title\n\nProse here.\n\n```wl\n1+1\n```\n"]
```

<!-- => <|"Metadata" -> <|"Name" -> "Demo"|>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>, <|"Type" -> "Prose", "Text" -> "Prose here."|>, <|"Type" -> "Code", "Lang" -> "wl", "Code" -> "1+1", "Options" -> <||>|>}|> -->

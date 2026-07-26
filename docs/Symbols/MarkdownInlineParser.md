---
Template: Symbol
Name: MarkdownInlineParser
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MarkdownInlineParser
Keywords: [markdown, inline, parser combinator, reusable parser, raw atoms, ParserCombinator, ParseChoice]
SeeAlso: [MarkdownInlineParse, MarkdownParser, MarkdownParse, Parse, ParserCombinator, ParseChoice, ParseAction]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MarkdownInlineParser]()</code> is the [ParserCombinator]() implementing the inline-markdown grammar — the reusable parser object behind [MarkdownInlineParse]().

<code>[Parse]()[MarkdownInlineParser, *source*]</code> runs that grammar on the [String]() *source*, returning the raw [List]() of inline atoms — before the text-merging, ellipsis, underscore-emphasis, and recursive-child passes that [MarkdownInlineParse]() adds.

## Details & Options

- [MarkdownInlineParser]() is an ordinary [ParserCombinator]() value: <code>[Head]()[MarkdownInlineParser]</code> is [ParserCombinator]() and its combinator type is `"Action"` — a [ParseMany]() over one big [ParseChoice]() of the span rules, wrapped in a [ParseAction]().
- The raw grammar emits the atoms exactly as the [ParseChoice]() arms produce them: one `"Text"` atom per plain character (the runs are *not* merged), and a span's `"Children"` / a link's `"Label"` left as the raw captured [String](), *not* re-parsed into a child atom list.
- The ellipsis rewrite and the CommonMark underscore-emphasis rule are wrapper post-passes with no grammar arm, so the raw object leaves `...` as three characters and `_em_` as four literal `"Text"` atoms.
- Being a [ParserCombinator](), it is callable via a [SubValues]() rule: <code>[MarkdownInlineParser]()[*source*]</code> is <code>[Parse]()[MarkdownInlineParser, *source*]</code>.
- The object serves any number of inputs and composes with the `Parse*` constructors and [ParserCompile]() like any other parser.
- For merged text runs, recursively parsed span children, and the ellipsis / underscore-emphasis conveniences, use [MarkdownInlineParse](), which wraps this object with those passes.

## Basic Examples

[MarkdownInlineParser]() is a parser object — a [ParserCombinator]() — not a function to call directly:

```wl
MarkdownInlineParser
```

<!-- => ParserCombinator[Action, …] summary box (combinator Type "Action") -->

<!-- #| annotation: 26.07.26: Design review - MarkdownInlineParser is the raw ParseMany[ParseChoice[…]] grammar; the four post-passes (adjacent-text merge, ellipsis, underscore emphasis, recursive children) are deliberately kept OUT of the combinator so the object stays a pure grammar that composes and compiles. Underscore emphasis in particular has no grammar arm at all - it is a regex post-pass in the wrapper - which is why the raw object emits one Text atom per character and leaves span children as raw strings. MarkdownInlineParse is the entry point that layers those passes on top. -->

Its head is [ParserCombinator](), the wrapper every parser normalises to:

```wl
Head[MarkdownInlineParser]
```

<!-- => ParserCombinator -->

Run raw, plain prose comes back as one `"Text"` atom per character — the runs are not yet merged:

```wl
Parse[MarkdownInlineParser, "hi"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "h"|>, <|"Type" -> "Text", "Text" -> "i"|>} -->

## Scope

A span's body is captured but not re-parsed, so a bold run's `"Children"` is the raw string, not an atom list:

```wl
Parse[MarkdownInlineParser, "**bold**"]
```

<!-- => {<|"Type" -> "Bold", "Children" -> "bold"|>} -->

---

Likewise a link's `"Label"` is the raw captured string at this stage:

```wl
Parse[MarkdownInlineParser, "[`Range`](u)"]
```

<!-- => {<|"Type" -> "Link", "Label" -> "`Range`", "Url" -> "u"|>} -->

---

Underscore emphasis is a wrapper-only rule, so the raw grammar treats `_em_` as literal characters:

```wl
Parse[MarkdownInlineParser, "_em_"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "_"|>, <|"Type" -> "Text", "Text" -> "e"|>, <|"Type" -> "Text", "Text" -> "m"|>, <|"Type" -> "Text", "Text" -> "_"|>} -->

## Properties and Relations

The wrapper [MarkdownInlineParse]() runs this object and then merges text, re-parses children, and applies the emphasis passes. Compare the raw children string above with the resolved atom list:

```wl
MarkdownInlineParse["**bold**"]
```

<!-- => {<|"Type" -> "Bold", "Children" -> {<|"Type" -> "Text", "Text" -> "bold"|>}|>} -->

---

Running the same underscore source through the wrapper applies the CommonMark rule and yields an `"Italic"`:

```wl
MarkdownInlineParse["_em_"]
```

<!-- => {<|"Type" -> "Italic", "Children" -> {<|"Type" -> "Text", "Text" -> "em"|>}|>} -->

---

As a [ParserCombinator]() the object is callable, so applying it is the same as running it with [Parse]():

```wl
MarkdownInlineParser["**x**"] === Parse[MarkdownInlineParser, "**x**"]
```

<!-- => True -->

## Possible Issues

The raw output is intentionally unprocessed — one atom per character, span children left as strings, no ellipsis or underscore emphasis. For the merged, recursively parsed atom list most callers want, use [MarkdownInlineParse]() rather than the combinator directly:

```wl
MarkdownInlineParse["hi"]
```

<!-- => {<|"Type" -> "Text", "Text" -> "hi"|>} -->

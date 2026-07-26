---
Template: Symbol
Name: MarkdownParser
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MarkdownParser
Keywords: [markdown, document, parser combinator, block, reusable parser, ParserCombinator]
SeeAlso: [MarkdownParse, MarkdownInlineParser, MarkdownInlineParse, Parse, ParserCombinator, ParserCompile]
RelatedGuides: [WolframParser]
---

## Usage

<code>[MarkdownParser]()</code> is the [ParserCombinator]() implementing the block-level markdown-document grammar — the reusable parser object behind [MarkdownParse]().

<code>[Parse]()[MarkdownParser, *source*]</code> runs that grammar on the [String]() *source*, returning the same document [Association]() as [MarkdownParse]() — the frontmatter under `"Metadata"` and the typed block list under `"Blocks"`.

## Details & Options

- [MarkdownParser]() is an ordinary [ParserCombinator]() value: <code>[Head]()[MarkdownParser]</code> is [ParserCombinator]() and its combinator type is `"Action"` (a [ParseAction]() wrapping the block grammar).
- The grammar is optional frontmatter followed by a sequence of blocks — heading, code fence, thematic break, or prose — the same block shapes [MarkdownParse]() documents.
- Being a [ParserCombinator](), it is callable via a [SubValues]() rule: <code>[MarkdownParser]()[*source*]</code> is <code>[Parse]()[MarkdownParser, *source*]</code>.
- One object serves any number of inputs. Bind it once and run it repeatedly, rather than reconstructing a parser per call.
- As a [ParserCombinator]() it can be composed with the `Parse*` constructors and lowered with [ParserCompile]() like any other parser.
- The line-based grammar expects *source* to end in a newline; [MarkdownParser]() does not add one. [MarkdownParse]() is the one-shot wrapper that appends a trailing newline (if missing) and then calls [Parse](), so it accepts input the raw object would reject.
- With a trailing newline present, <code>[Parse]()[MarkdownParser, *source*]</code> and <code>[MarkdownParse]()[*source*]</code> return the identical [Association]().

## Basic Examples

[MarkdownParser]() is a parser object — a [ParserCombinator]() — not a function to call directly:

```wl
MarkdownParser
```

<!-- => ParserCombinator[Action, …] summary box (combinator Type "Action") -->

<!-- #| annotation: 26.07.26: Design review - the block grammar is exposed as a first-class ParserCombinator so it can be inspected, composed, and compiled (ParserCompile), not merely invoked; MarkdownParse is the thin one-shot entry point (trailing-newline fix-up, then Parse). Splitting the reusable object from the convenience function mirrors the Parse-vs-compiled-parser split used across the paclet. -->

Its head is [ParserCombinator](), the wrapper every parser in the library normalises to:

```wl
Head[MarkdownParser]
```

<!-- => ParserCombinator -->

Run it with [Parse]() against a document string ending in a newline:

```wl
Parse[MarkdownParser, "# Title\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>}|> -->

## Scope

A [ParserCombinator]() is callable, so <code>[MarkdownParser]()[*source*]</code> runs it too:

```wl
MarkdownParser["## Sub\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 2, "Text" -> "Sub"|>}|> -->

---

The same object applies to many inputs — here mapped over two documents, keeping only their blocks:

```wl
(Parse[MarkdownParser, #]["Blocks"] &) /@ {"# A\n", "B.\n"}
```

<!-- => {{<|"Type" -> "Heading", "Level" -> 1, "Text" -> "A"|>}, {<|"Type" -> "Prose", "Text" -> "B."|>}} -->

## Properties and Relations

With a trailing newline in place, running the object equals calling [MarkdownParse]():

```wl
Parse[MarkdownParser, "# Title\n"] === MarkdownParse["# Title\n"]
```

<!-- => True -->

---

[MarkdownParse]() adds the trailing newline the grammar needs; the raw object does not, so the same newline-less source succeeds through the wrapper:

```wl
MarkdownParse["# Title"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>}|> -->

## Possible Issues

Run directly on a source with no trailing newline, [MarkdownParser]() leaves the final line unconsumed and [Parse]() reports a `"ParseError"`:

```wl
Parse[MarkdownParser, "# Title"]
```

<!-- => Failure["ParseError", <|…, "Position" -> 1, "Expected" -> "<end of input>", "Found" -> "#"|>] -->

Append a newline, or use [MarkdownParse](), which does it for you:

```wl
Parse[MarkdownParser, "# Title" <> "\n"]
```

<!-- => <|"Metadata" -> <||>, "Blocks" -> {<|"Type" -> "Heading", "Level" -> 1, "Text" -> "Title"|>}|> -->

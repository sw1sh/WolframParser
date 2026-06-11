---
Template: Symbol
Name: ParsePosition
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ParsePosition
Keywords: [parser, position, source, span, offset]
SeeAlso: [ParseSequence, ParseAction, SpannedToken, ASTAddSource]
RelatedGuides: [WolframParser, ParserZoo]
---

## Usage

<code>[ParsePosition]()[]</code> is the zero-width [ParserCombinator]() that yields the current 1-based character position and consumes nothing.

Bracketing a sub-parser, `ParsePosition[] ~~ p ~~ ParsePosition[]`, captures the source span *p* covers - the start position, *p*'s value, then the end (one past the last character).

## Details & Options

- `ParsePosition[]` is *zero-width*: it matches at every position, succeeds always, and advances the cursor by nothing - like [ParseSucceed]() with the cursor offset as its value. It is a built-in parser, not a combinator over other parsers.
- The position is a 1-based character offset into the input. The *end* position a closing `ParsePosition[]` reports is *one past* the last character the bracketed parser consumed, so `end - start` is exactly the number of characters matched.
- Bracketing yields a `{start, value, end}` shape: the leading `ParsePosition[]` contributes *start*, the inner parser its *value*, the trailing `ParsePosition[]` the *end*. Inside a [ParseSequence]() those three become successive elements; reshape with [ParseAction]().
- This is the primitive behind source tracking. [SpannedToken]() uses `ParsePosition[]` to record each leaf's offset span, and [ASTAddSource]() turns those offsets into `{{startLine, startColumn}, {endLine, endColumn}}` pairs - [CodeParser]()'s LineColumn convention.

## Basic Examples

`ParsePosition[]` is a built-in parser like [ParseSucceed]() - it carries no children:

```wl
ParsePosition[]
```

<!-- => ParserCombinator["Position", {}, <||>] -->

Bracket a number parser to capture the span it covers - start `1`, the matched text, end `4` (one past the last digit):

```wl
Parse[ParseSequence[ParsePosition[], ParseRegex["[0-9]+"], ParsePosition[]], "123"]
```

<!-- => {1, "123", 4} -->

Because it consumes nothing, a `ParsePosition[]` *after* a whitespace skip reports the position the next token actually starts at. Reshape with [ParseAction]() to keep just the `{start, value, end}` triple:

```wl
ws = ParseMany[ParseCharacter[WhitespaceCharacter]];
spanned = ParseAction[
    ws ~~ ParsePosition[] ~~ ParseRegex["[0-9]+"] ~~ ParsePosition[],
    Function[{skip, s, v, e}, {s, v, e}]];
Parse[spanned, "  123"]
```

<!-- => {3, "123", 6} -->

The start jumped to `3`, past the two leading spaces.

## Properties and Relations

`ParsePosition[]` is the engine support that lets a parse value carry *where it came from*. The source-tracking chain stacks three pieces:

- [ParsePosition]() yields a raw character offset and consumes nothing - the primitive.
- [SpannedToken]() brackets a token with two `ParsePosition[]`s, builds the leaf, and stamps the captured `{start, end}` offset span onto it.
- [ASTAddSource]() fills every composite node's span by spanning its children, then converts every offset span to a `{{line, column}, {line, column}}` pair against the source string.

[SpannedToken]() is exactly this bracketing pattern, packaged - it wraps `ParsePosition[] ~~ token ~~ ParsePosition[]` and excludes trailing whitespace from the span:

```wl
Parse[
    SpannedToken[ParseRegex["[0-9]+"], ParseMany[ParseCharacter[WhitespaceCharacter]],
        Function[s, LeafNode["Integer", s, <||>]]],
    "42   "
]
```

<!-- => LeafNode["Integer", "42", <|"Source" -> {1, 3}|>] -->

The span is `{1, 3}` - the `"42"` only, not the trailing spaces.

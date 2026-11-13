---
Template: Symbol
Name: WolframLanguageTokens
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/WolframLanguageTokens
Keywords: [Wolfram Language, tokens, lexer, tokenizer, syntax coloring, syntax highlighting, editor, incomplete input, bracket matching, parser zoo]
SeeAlso: [WolframLanguageBoxes, WolframLanguageConcrete, WolframLanguageSyntaxQ, WolframLanguageSyntaxLength, WolframLanguageHeld, SyntaxQ]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[WolframLanguageTokens]()[*code*]</code> gives the tokens of the Wolfram Language text *code* in order, each character of *code* in exactly one token.

<code>[WolframLanguageTokens]()[*code*, "Rows"]</code> gives the tokens as a packed array of integers, one row for each token.

<code>[WolframLanguageTokens]()[*code*, "Data"]</code> gives the rows with the names their integers stand for.

## Details & Options

- `WolframLanguageTokens` is made for an editor that colors text as it is typed: it reads any text, gives no failure and issues no message, and its tokens join back to *code* exactly.
- The tokens are those of the compiled lexer that [WolframLanguageHeld]() and [WolframLanguageSyntaxQ]() read with, and between them the whitespace, the newlines and the comments that the lexer passes over.
- Each token is an [Association]() with these keys:

| Key | Value |
|---|---|
| `"Kind"` | the kind of token, one of the strings below |
| `"Text"` | the characters of the token, as they are in *code* |
| `"Start"`, `"End"` | the positions of its first and last character, the first character of *code* at 1 |
| `"Line"`, `"Column"` | the line and the column of its first character, both from 1 |
| `"Depth"` | the number of brackets open around it; for an opener and a closer, the depth of what they hold |
| `"Operator"` | for an operator, an opener and a closer: the operator's name |
| `"Partner"` | for an opener and a closer: the index of the token that closes or opens it, 0 where there is none |
| `"Context"` | for a symbol: whether its name has a context mark |
| `"LongName"` | [True]() for a token written with a long name, such as `\[Rule]`; absent otherwise |
| `"Incomplete"` | [True]() for a token that *code* ends in before it closes; absent otherwise |

- The kinds, and the text each covers:

| Kind | Text |
|---|---|
| `"Symbol"` | a name, its context marks and the long names of its letters included: `x`, `` a`b ``, `\[Alpha]1`; also the head of a blank |
| `"PatternName"` | the name before a blank: the `x` of `x_` and of `x__h` |
| `"Blank"` | `_`, `__`, `___` or `_.` |
| `"Number"` | an integer or a real with its base, its precision or accuracy mark and its exponent: `16^^ff`, `` 1.5`20*^3 `` |
| `"String"` | a string with its quotes; the file name after `<<`, `>>` or `>>>`; the tag after `::` |
| `"StringEscape"` | with `"StringEscapes" -> True`, an escape inside a string: `\n`, `\"`, `\[Alpha]`, `\:03b1`, `\.41`, `\101`, `\|01f600` |
| `"Slot"` | `#`, `#2`, `##`, `##2`, `#name` or `#"name"` |
| `"Out"` | `%`, `%%` or `%3` |
| `"Operator"` | an operator, the comma and the primes of a derivative among them |
| `"Open"`, `"Close"` | a bracket: `(`, `[`, `{`, `<|` and their closers, and the long-name brackets such as `\[LeftDoubleBracket]` and `\[LeftFloor]` |
| `"Comment"` | a comment from its `(*` to its `*)`, the comments nested in it included |
| `"Whitespace"` | a run of spaces and tabs, the long names that are spaces among them; a line continuation between two tokens |
| `"Newline"` | one line break: a newline, a return, or a return and a newline together |
| `"LinearSyntax"` | linear syntax from `\(` or `\!\(` to the `\)` that closes it |
| `"FreeForm"` | free-form input, `=[` to its `]` |
| `"Error"` | characters that no token has: a character that begins none, a long name that is half typed or that no character has, a name with a context mark out of place, a number with a base or a digit it cannot have, a stray backslash |

- An operator's name is its ASCII spelling, however it is written: `->`, `\[Rule]` and the character of that long name all have the name `"->"`. An operator with no ASCII spelling has its long name, such as `"\\[Element]"`.
- A string, a comment, linear syntax or free-form input that *code* does not close is one token to the end of *code*, with `"Incomplete" -> True`.
- After an error the tokens are read on from the character after it.
- A closer takes the nearest opener of its kind that is still open, and the openers after that one are left with no partner. Two square brackets of a part are two openers.
- Positions count characters as [StringTake]() does, so <code>[StringTake]()[*code*, {*start*, *end*}]</code> is the token's text. For an editor that counts from 0 with the end excluded, a token is from *start* - 1 to *end*.
- A line ends at a newline, at a return and a newline together, and at a return alone.
- A line continuation or a character escape such as `\:03b1` inside a name or a number is part of that token.
- With the form `"Rows"`, each row is {*kind*, *start*, *end*, *line*, *column*, *depth*, *partner*, *operator*, *flags*}: the kind and the operator are positions in the lists of kinds and operators that the form `"Data"` gives, and the flags are the sum of 1 for incomplete, 2 for a context mark and 4 for a long name. The form `"Data"` gives an [Association]() with the keys `"Columns"`, `"Kinds"`, `"Operators"`, `"Flags"` and `"Rows"`.
- The following options can be given:

| Option | Default | |
|---|---|---|
| `"StringEscapes"` | [False]() | whether the escapes of a string are tokens of their own |
| `"Offsets"` | `"Characters"` | what `"Start"`, `"End"` and `"Column"` count: `"Characters"`, or `"UTF16"` for UTF-16 code units, as a browser's strings count |

- The tokens tell what the lexer reads and nothing about meaning: whether a symbol has a definition, is a System symbol or is a local variable of a scoping construct is not among them.

## Basic Examples

The tokens of a call:

```wl
WolframLanguageTokens["f[x]"]
```

The kind and the text of each token of a definition, whitespace and a comment among them:

```wl
Lookup[WolframLanguageTokens["f[x_] := x^2 (* square *)"], {"Kind", "Text"}]
```

The same tokens as rows of integers:

```wl
WolframLanguageTokens["f[x_] := x^2 (* square *)", "Rows"]
```

## Scope

A pattern is its name, its blank and its head:

```wl
Lookup[WolframLanguageTokens["x_Integer + y__ + _."], {"Kind", "Text"}]
```

A symbol tells whether its name has a context mark:

```wl
Lookup[WolframLanguageTokens["Developer`PackedArrayQ[list]"], {"Text", "Context"}, None]
```

<!-- => {{"Developer`PackedArrayQ", True}, {"[", None}, {"list", False}, {"]", None}} -->

An operator has one name however it is written:

```wl
Lookup[WolframLanguageTokens["a -> b \\[Rule] c"], {"Text", "Operator"}, None]
```

<!-- => {{"a", None}, {" ", None}, {"->", "->"}, {" ", None}, {"b", None}, {" ", None}, {"\\[Rule]", "->"}, {" ", None}, {"c", None}} -->

An opener and its closer name each other:

```wl
Lookup[WolframLanguageTokens["f[{a}]"], {"Text", "Depth", "Partner"}, None]
```

<!-- => {{"f", 0, None}, {"[", 1, 6}, {"{", 2, 5}, {"a", 2, None}, {"}", 2, 3}, {"]", 1, 2}} -->

The tag of a message and the file of a `<<` are strings:

```wl
Lookup[WolframLanguageTokens["f::usage; << Tools`"], {"Kind", "Text"}]
```

The line and the column of each token of two lines:

```wl
Lookup[WolframLanguageTokens["a +\n  b"], {"Text", "Line", "Column"}]
```

<!-- => {{"a", 1, 1}, {" ", 1, 2}, {"+", 1, 3}, {"\n", 1, 4}, {"  ", 2, 1}, {"b", 2, 3}} -->

## Options

### "StringEscapes"

A string is one token:

```wl
Lookup[WolframLanguageTokens["\"a\\n\\[Alpha]b\""], {"Kind", "Text"}]
```

<!-- => {{"String", "\"a\\n\\[Alpha]b\""}} -->

With `"StringEscapes" -> True` its escapes are tokens of their own:

```wl
Lookup[WolframLanguageTokens["\"a\\n\\[Alpha]b\"", "StringEscapes" -> True], {"Kind", "Text"}]
```

<!-- => {{"String", "\"a"}, {"StringEscape", "\\n"}, {"StringEscape", "\\[Alpha]"}, {"String", "b\""}} -->

### "Offsets"

A character past 65535 is one character:

```wl
Lookup[WolframLanguageTokens["\"\|01f600\" + x"], {"Text", "Start", "End"}]
```

<!-- => {{"\"\|01f600\"", 1, 3}, {" ", 4, 4}, {"+", 5, 5}, {" ", 6, 6}, {"x", 7, 7}} -->

With `"Offsets" -> "UTF16"` it counts as two, as it does in a browser's string:

```wl
Lookup[WolframLanguageTokens["\"\|01f600\" + x", "Offsets" -> "UTF16"], {"Text", "Start", "End"}]
```

<!-- => {{"\"\|01f600\"", 1, 4}, {" ", 5, 5}, {"+", 6, 6}, {" ", 7, 7}, {"x", 8, 8}} -->

## Applications

Text as it is typed, with a string that is not closed yet:

```wl
Lookup[WolframLanguageTokens["Print[\"hello"], {"Kind", "Text", "Incomplete"}, False]
```

<!-- => {{"Symbol", "Print", False}, {"Open", "[", False}, {"String", "\"hello", True}} -->

A long name half typed is an error, and the tokens after it are read:

```wl
Lookup[WolframLanguageTokens["a + \\[Alp + b"], {"Kind", "Text"}]
```

A bracket with no partner has the partner 0:

```wl
Lookup[Select[WolframLanguageTokens["f[(a] + b)"], KeyExistsQ[#, "Partner"] &], {"Text", "Partner"}]
```

<!-- => {{"[", 5}, {"(", 0}, {"]", 2}, {")", 0}} -->

## Properties and Relations

The texts of the tokens join to the source, whatever it is:

```wl
StringJoin[Lookup[WolframLanguageTokens["f[\"a (* b \\[Alp ]} `"], "Text"]]
```

<!-- => "f[\"a (* b \\[Alp ]} `" -->

[StringTake]() from a token's start to its end gives its text:

```wl
StringTake["f[x_] := x^2", {#Start, #End}] & /@ WolframLanguageTokens["f[x_] := x^2"]
```

<!-- => {"f", "[", "x", "_", "]", " ", ":=", " ", "x", "^", "2"} -->

The form `"Data"` names what the integers of the rows stand for:

```wl
data = WolframLanguageTokens["f[x] -> 1", "Data"];
```

```wl
data["Columns"]
```

<!-- => {"Kind", "Start", "End", "Line", "Column", "Depth", "Partner", "Operator", "Flags"} -->

The kinds, a row's first integer a position among them:

```wl
data["Kinds"]
```

The kind of each row:

```wl
data["Kinds"][[data["Rows"][[All, 1]]]]
```

<!-- => {"Symbol", "Open", "Symbol", "Close", "Whitespace", "Operator", "Whitespace", "Number"} -->

The tokens tell nothing of whether a source reads, which [WolframLanguageSyntaxQ]() tells. A source that ends in an operator does not read:

```wl
WolframLanguageSyntaxQ["a +"]
```

<!-- => False -->

Its tokens are a symbol, whitespace and an operator:

```wl
Lookup[WolframLanguageTokens["a +"], "Kind"]
```

<!-- => {"Symbol", "Whitespace", "Operator"} -->

## Possible Issues

The two square brackets of a part are two tokens, each with its own partner:

```wl
Lookup[WolframLanguageTokens["a[[1]]"], {"Text", "Partner"}, None]
```

<!-- => {{"a", None}, {"[", 6}, {"[", 5}, {"1", None}, {"]", 3}, {"]", 2}} -->

A string that is not closed takes the rest of the text, the code after it too:

```wl
Lookup[WolframLanguageTokens["f[\"a, b]\ng[c]"], {"Kind", "Text"}]
```

<!-- => {{"Symbol", "f"}, {"Open", "["}, {"String", "\"a, b]\ng[c]"}} -->

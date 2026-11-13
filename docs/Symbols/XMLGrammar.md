---
Template: Symbol
Name: XMLGrammar
Context: Wolfram`Parser`Languages`XML`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/XMLGrammar
Keywords: [XML, grammar, parser, EBNF, EBNFParse, ParserCombinator, actions]
SeeAlso: [XMLRead, XMLEBNF, EBNFParse, Parse, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[XMLGrammar]()[*entities*]</code> builds the XML parser, from the grammar [XMLEBNF](), read by [EBNFParse](), with the *entities* an [Association]() of names to their text.

## Details & Options

- The value of the parser is <code>{*prolog*, *element*, *epilog*}</code>, the parts of the document [XMLRead]() gives.
- [EBNFParse]() reads the grammar with `"Dialect" -> "Classic"` and `"ChoiceMode" -> "PEG"`, and skips nothing between a rule's elements, as the whitespace of XML is written out in the grammar.
- The rules the grammar's `%tokens` lines name are compiled to regular expressions and bound as the grammar's primitives; the other rules are combinators, and their actions build the tree.
- Where the text breaks a constraint the grammar does not state, an element's value holds a marker that [XMLRead]() turns into a [Failure]().

## Basic Examples

The parser:

```wl
XMLGrammar[<||>]
```

It runs with [Parse]():

```wl
Parse[XMLGrammar[<||>], "<a>t</a>"]
```

<!-- => {{}, XMLElement["a", {}, {"t"}], {}} -->

## Scope

The entities the parser knows beyond the five of XML:

```wl
Parse[XMLGrammar[<|"e" -> "E"|>], "<a>&e;&amp;</a>"]
```

<!-- => {{}, XMLElement["a", {}, {"E&"}], {}} -->

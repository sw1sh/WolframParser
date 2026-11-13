---
Template: Symbol
Name: XMLEBNF
Context: Wolfram`Parser`Languages`XML`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/XMLEBNF
Keywords: [XML, EBNF, BNF, grammar, PEG, W3C, EBNFParse, parser generator]
SeeAlso: [XMLGrammar, XMLRead, EBNFParse, EBNFRules, EBNFDeclarations, MermaidEBNF, ABCBNF]
RelatedGuides: [WolframParser]
---

## Usage

[XMLEBNF]() is the grammar of XML 1.0 as the W3C Recommendation publishes it, a string in the classic dialect of [EBNFParse]().

## Details & Options

- The grammar is `XML.ebnf`, beside the front end: the productions of "Extensible Markup Language (XML) 1.0 (Fifth Edition)" under their published names, stated as one PEG. Where two alternatives of the Recommendation begin alike, as an empty-element tag and a start tag do, they are one rule that reads the shared part once.
- `<Document>` is the start rule: a prolog, the root element, and what follows it.
- Its `%tokens` lines name the rules matched as regular expressions, names, whitespace and runs of text, and its `%class` lines the ranges of characters the Recommendation gives by code.
- The constraints a grammar cannot state, an end tag naming its start tag, an attribute given once, are the front end's, [XMLRead]().

## Basic Examples

The grammar:

```wl
XMLEBNF
```

The rule of an element:

```wl
Select[StringSplit[XMLEBNF, "\n"], StringStartsQ["<Element>"]]
```

<!-- => {"<Element>       ::= \"<\" <Name> { <S> <Attribute> } [ <S> ] ( \"/>\" | \">\" <Content> <ETag> )"} -->

## Scope

The number of rules, read by [EBNFRules]():

```wl
Count[EBNFRules[XMLEBNF, "Dialect" -> "Classic"], _[_, "::=", _]]
```

<!-- => 56 -->

The token rules it declares, read by [EBNFDeclarations]():

```wl
EBNFDeclarations[XMLEBNF]["tokens"]
```

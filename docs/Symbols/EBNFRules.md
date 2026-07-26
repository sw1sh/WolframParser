---
Template: Symbol
Name: EBNFRules
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/EBNFRules
Keywords: [ebnf, bnf, grammar, rules, meta-grammar, inspection, parse tree, syntaxbnf]
SeeAlso: [EBNFParse, Parse, ParseAction, ParserCombinator, TPTPImport]
RelatedGuides: [WolframParser]
---

## Usage

<code>[EBNFRules]()[*source*]</code> parses a BNF / EBNF grammar from the string *source* and returns the list of raw rule records, without lowering them to parsers.

<code>[EBNFRules]()[[File]()[*path*]]</code> reads the grammar from a file.

## Details & Options

- Each record has the form `EBNFRule[name, kind, body]`: *name* is the rule's non-terminal name, *kind* is the arrow string, and *body* is the list of alternatives. `EBNFRule` and the body markers below are internal heads in the package's private `` Wolfram`Parser`EBNFPrivate` `` context.
- *kind* is one of `"::="` (syntactic), `":=="` (semantic), `"::-"` (token construction), or `":::"` (character class) — the four arrows the grammar notation distinguishes.
- Each alternative in *body* is a list of elements: `Lit[s]` for a literal token, `NonTerm[name]` for a non-terminal reference, and `Rep["Many", elt]` for a postfix-`*` repetition.
- Rules are returned in source order.
- [EBNFParse]() calls [EBNFRules]() internally and then lowers each record to a [ParserCombinator](). [EBNFRules]() stops before lowering, so it is the way to inspect a parsed grammar's shape — rule count, names, and kinds — without building parsers.
- Left-recursion elimination and longest-first alternative sorting are applied by [EBNFParse]() during lowering, not by [EBNFRules](); the records reflect the grammar exactly as written.

## Basic Examples

The raw record of a one-rule grammar:

```wl
EBNFRules["<greeting> ::= hello | bye"]
```

<!-- => {EBNFRule["greeting", "::=", {{Lit["hello"]}, {Lit["bye"]}}]} -->

<!-- #| annotation: 26.07.26: Design review - EBNFRules is the pre-lowering inspection point of the EBNF pipeline: it returns the grammar's own structure (one EBNFRule per rule, bodies as Lit/NonTerm/Rep markers), not an AST of any parsed input. The record heads live in a private context on purpose - they are an internal intermediate representation that EBNFParse consumes, kept minimal rather than promoted to a public node zoo. It exists so a caller can count rules, read names and arrow kinds, and diff a vendored grammar (e.g. TPTP SyntaxBNF) across versions without paying for lowering; positioned against a parser generator's internal grammar table, this simply exposes that table as ordinary Wolfram Language data. -->

---

The result is one record per rule; here a three-rule grammar yields three:

```wl
Length @ EBNFRules["
    <digit>  ::= 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
    <number> ::= <digit><digit>*
    <expr>   ::= <number> + <number>
"]
```

<!-- => 3 -->

---

The first field of each record is the rule name:

```wl
EBNFRules["
    <digit>  ::= 0 | 1
    <number> ::= <digit><digit>*
"][[All, 1]]
```

<!-- => {"digit", "number"} -->

---

The second field is the arrow kind — one grammar exercising all four the notation distinguishes:

```wl
EBNFRules["<a> ::= x
<b> :== y
<c> ::- z
<d> ::: w"][[All, 2]]
```

<!-- => {"::=", ":==", "::-", ":::"} -->

## Scope

The third field is the list of alternatives; each element is a `Lit`, `NonTerm`, or `Rep` marker — here a non-terminal reference followed by a `*` repetition:

```wl
EBNFRules["<number> ::= <digit><digit>*"][[1, 3]]
```

<!-- => {{NonTerm["digit"], Rep["Many", NonTerm["digit"]]}} -->

---

Read the grammar from a file with [File]():

```wl
gpath = FileNameJoin[{$TemporaryDirectory, "greeting.bnf"}];
Export[gpath, "<greeting> ::= hello | bye", "Text"];
EBNFRules[File[gpath]][[1, 1]]
```

<!-- => "greeting" -->

## Properties and Relations

[EBNFParse]() lowers exactly these rules; the keys of its result are the names [EBNFRules]() lists:

```wl
Keys @ EBNFParse["<digit> ::= 0 | 1
                  <number> ::= <digit><digit>*"]
```

<!-- => {"digit", "number"} -->

---

[EBNFRules]() reads the whole published TPTP grammar without lowering it, which is how the parser tracks the spec — [Parsing BNF Grammars](paclet:Wolfram/Parser/tutorial/ParsingBNFGrammars) walks that construction, and [TPTPImport]() is the finished consumer.

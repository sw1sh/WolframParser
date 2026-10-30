---
Template: Symbol
Name: EBNFDeclarations
Context: Wolfram`Parser`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/EBNFDeclarations
Keywords: [ebnf, bnf, grammar, declarations, directives, precedence, operator table, syntax, wolfram language syntax]
SeeAlso: [EBNFRules, EBNFParse, ParseOperatorTable, ABCBNF]
RelatedGuides: [WolframParser]
---

## Usage

<code>[EBNFDeclarations]()[*source*]</code> gives the declarations of the grammar *source* in the classic dialect, as an [Association]() of each keyword with the fields of its declarations.

<code>[EBNFDeclarations]()[[File]()[*path*]]</code> reads the grammar from a file.

## Details & Options

- A declaration is a line of the grammar that begins with `%`, as a parser generator's are: `%` and a keyword, then fields up to the end of the line. Declarations stand between rules.
- A field is a quoted terminal, an integer, or a word of the characters other than whitespace, quotes and parentheses. A terminal or a word gives a string, an integer an [Integer]().
- The result has the form `<|keyword -> {{field, ...}, ...}, ...|>`: a list of fields for each declaration of a keyword, in the order the grammar gives them, and the keywords in the order of their first declaration.
- Wolfram Language comments, nested as there, can stand between rules and declarations and after a declaration's fields.
- The program that reads the declarations gives them their meaning. [EBNFParse]() lowers the rules and reads past the declarations.
- The Wolfram Language's own syntax, `Kernel/Languages/WolframLanguage.ebnf` in the paclet, declares its precedence levels, its operator tokens and its operators this way, and the paclet's reader takes its operator tables from those declarations.

## Basic Examples

The declarations of a small grammar:

```wl
EBNFDeclarations["%level Times 108
%level Plus 86
%operator \"*\" Times InfixN
%operator \"+\" Plus InfixN
<sum> ::= <product> { \"+\" <product> }"]
```

<!-- => <|"level" -> {{"Times", 108}, {"Plus", 86}}, "operator" -> {{"*", "Times", "InfixN"}, {"+", "Plus", "InfixN"}}|> -->

---

The fields of one keyword's declarations, in order:

```wl
EBNFDeclarations["%level Times 108
%level Plus 86"]["level"]
```

<!-- => {{"Times", 108}, {"Plus", 86}} -->

## Scope

A comment can follow a declaration's fields, and a word can hold a context mark:

```wl
EBNFDeclarations["%level Infix`Plus 86 (* a + b *)"]
```

<!-- => <|"level" -> {{"Infix`Plus", 86}}|> -->

---

A declaration with no fields gives an empty list:

```wl
EBNFDeclarations["%start
<a> ::= \"x\""]
```

<!-- => <|"start" -> {{}}|> -->

---

A grammar with no declaration gives an empty [Association]():

```wl
EBNFDeclarations["<a> ::= \"x\""]
```

<!-- => <||> -->

---

Read the grammar from a file with [File]():

```wl
EBNFDeclarations[File[Export[FileNameJoin[{$TemporaryDirectory, "levels.bnf"}], "%level Times 108\n<a> ::= \"x\"", "Text"]]]
```

<!-- => <|"level" -> {{"Times", 108}}|> -->

## Properties and Relations

[EBNFRules]() in the classic dialect gives a record for each declaration among the rules, in the order of the grammar:

```wl
EBNFRules["%start a
<a> ::= \"x\"", "Dialect" -> "Classic"]
```

<!-- => {Wolfram`Parser`EBNFPrivate`EBNFDeclaration["start", {"a"}], Wolfram`Parser`EBNFPrivate`EBNFRule["a", "::=", {{Wolfram`Parser`EBNFPrivate`Lit["x"]}}]} -->

---

[EBNFParse]() lowers the rules alone; the keys of its result are the rule names:

```wl
Keys[EBNFParse["%start a
<a> ::= \"x\"", "Dialect" -> "Classic"]]
```

<!-- => {"a"} -->

## Neat Examples

The Wolfram Language's syntax, as the paclet declares it: its precedence levels, its operator tokens, the long names of its operators and its operators:

```wl
wlSyntax = EBNFDeclarations[File[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages", "WolframLanguage.ebnf"}]]]
```

---

How many declarations of each keyword it holds:

```wl
Length /@ wlSyntax
```

<!-- => <|"level" -> 45, "token" -> 4, "longname" -> 15, "operator" -> 75|> -->

---

The declaration of `->`: its spelling, the level it binds at, its form and the head it makes:

```wl
Select[wlSyntax["operator"], First[#] === "->" &]
```

<!-- => {{"->", "MinusGreater", "InfixR", "Rule"}} -->

---

The value of that level:

```wl
Select[wlSyntax["level"], First[#] === "MinusGreater" &]
```

<!-- => {{"MinusGreater", 31}} -->

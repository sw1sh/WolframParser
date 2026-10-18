---
Template: Symbol
Name: ABCGrammar
Context: Wolfram`Parser`Languages`ABC`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ABCGrammar
Keywords: [ABC, grammar, algebra, operator precedence, parser zoo]
SeeAlso: [ABCBNF, ABCSemantic, ABCAST, ABCRun, EBNFParse]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingABC, ParserZoo]
---

## Usage

<code>[ABCGrammar]()[*alg*]</code> builds the ABC parser over the algebra *alg*, an [Association]() of builder functions, from the grammar the ABC specification publishes.

## Details & Options

- The grammar is [ABCBNF](), the one the ABC specification publishes, read by [EBNFParse]() in its classic dialect; *alg* gives each rule its value. The grammar is run over different algebras: [ABCSemantic]() builds the plain data [ABCRun]() executes, and [ASTAlgebra]() with three statement builders gives the tree of [ABCAST]().
- *alg* supplies `"Leaf"` (with a kind, `"Integer"`, `"Symbol"` or `"Keyword"`, and the source text), `"Binary"` (an operator and two operands), `"Call"` (the name's leaf and the argument list), `"Print"` (the keyword's leaf and the expression), `"Stop"` (the keyword's leaf), `"Define"` (the name's leaf and the expression) and `"Program"` (the list of statements).
- The specification's prose supplies what the grammar leaves out. Spaces and tabs are skipped between elements, but not before the space `<SP>` that `print` requires, nor inside names and numbers, the grammar's tokens. Names are case insensitive; the keywords are written in lower case, as the grammar writes them.
- `<Calc> <OP> <Calc>` sets no precedence, so a calculation's operands and operators are combined `*` `/` `%` before `+` `-`, each left to right.
- Statements are separated by line breaks, and blank lines are allowed anywhere. Read as a PEG, the published `<Program>` ends after its first line, its optional `<NL>` taking every newline; [ABCGrammar]() reads it with its last two elements swapped, which describes the same programs.

## Basic Examples

The parser over the semantic algebra:

```wl
ABCGrammar[ABCSemantic]
```

It parses a program to plain data:

```wl
Parse[ABCGrammar[ABCSemantic], "max = a - b + b\nprint max"]
```

<!-- => {{"define", "max", {"+", {"-", "a", "b"}, "b"}}, {"print", "max"}} -->

## Scope

An algebra of your own gives the program another meaning. This one writes it back as normalized source, names as they were written:

```wl
printer = <|
    "Leaf" -> Function[{kind, src}, src],
    "Binary" -> Function[{op, l, r}, "(" <> l <> " " <> op <> " " <> r <> ")"],
    "Call" -> Function[{head, args}, head <> "(" <> StringRiffle[args, ", "] <> ")"],
    "Print" -> Function[{keyword, e}, "print " <> e],
    "Stop" -> Function[keyword, "stop"],
    "Define" -> Function[{n, e}, n <> " = " <> e],
    "Program" -> Function[lines, StringRiffle[lines, "\n"]]
|>;
```

The parenthesization shows the precedence the grammar gives each operator:

```wl
Parse[ABCGrammar[printer], "print a%2+a/2%2*10"]
```

<!-- => "print ((a % 2) + (((a / 2) % 2) * 10))" -->

## Properties & Relations

[ABCAST]() is the grammar over [ASTAlgebra](), with the statements as nodes:

```wl
ASTStripSource @ ABCAST["stop"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Keyword", "stop", <||>], {}, <||>]}, <||>] -->

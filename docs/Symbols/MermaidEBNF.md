---
Template: Symbol
Name: MermaidEBNF
Context: Wolfram`Parser`Languages`Mermaid`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/MermaidEBNF
Keywords: [Mermaid, EBNF, BNF, grammar, PEG, Jison, EBNFParse, parser generator]
SeeAlso: [MermaidGrammar, EBNFParse, EBNFRules, MermaidRead, ABCBNF]
RelatedGuides: [WolframParser]
RelatedTutorials: [MermaidDiagrams, ParserZoo, ParsingBNFGrammars]
---
## Usage

[MermaidEBNF]() is the grammar of Mermaid diagrams, a string in the classic dialect of [EBNFParse]().

## Details & Options

- Mermaid publishes its syntax as Jison files, one for each diagram type, each a lexer with start conditions and an LALR grammar over its tokens. [MermaidEBNF]() states the same syntax as one PEG: a lexer state is the rule that reads the text of that state, and a token the lexer tries first is the alternative written first.
- The grammar is five files beside the front end, joined: `Mermaid.ebnf`, a diagram and the tokens every type shares, and `MermaidFlowchart.ebnf`, `MermaidSequence.ebnf`, `MermaidState.ebnf` and `MermaidClass.ebnf`.
- `<Mermaid>` is the start rule: an optional front matter, then `<Flowchart>`, `<Sequence>`, `<State>` or `<Class>`. `<Any>`, any one character, is bound by [MermaidGrammar]().
- [MermaidGrammar]() reads it with `"Dialect" -> "Classic"`, `"ChoiceMode" -> "PEG"`, spaces and tabs as `"Whitespace"`, and its keywords, names, texts and arrows as `"Tokens"`.

## Basic Examples

The grammar:

```wl
MermaidEBNF
```

The rules a flowchart begins with:

```wl
Select[StringSplit[MermaidEBNF, "\n"], StringStartsQ["<Flowchart>" | "<FlowHeader>" | "<FlowChain>" | "<FlowNode>"]]
```

## Scope

The number of rules, read by [EBNFRules]():

```wl
Length[EBNFRules[MermaidEBNF, "Dialect" -> "Classic"]]
```

<!-- => 166 -->

The rule for the arrow of a flowchart link, lowered by [EBNFParse]() as a token:

```wl
arrows = EBNFParse[MermaidEBNF, "Dialect" -> "Classic", "ChoiceMode" -> "PEG", "Tokens" -> {"Arrow"}];
```

It reads a long dotted arrow with a circle at its start:

```wl
Parse[arrows["Arrow"], "o-..->"]
```

<!-- => "o-..->" -->

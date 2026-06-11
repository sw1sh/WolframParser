---
Template: Symbol
Name: LispSemantic
Context: Wolfram`Parser`Languages`Lisp`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LispSemantic
Keywords: [lisp, algebra, semantic, read, builder functions, native data, parser zoo]
SeeAlso: [LispRead, LispGrammar, LispAST, LispSymbol, ASTAlgebra]
RelatedGuides: [ParserZoo]
---

## Usage

[LispSemantic]() is the algebra - an [Association]() of builder functions - that reads the Lisp parse to native nested Wolfram data.

## Details & Options

- `LispSemantic` is the meaningful, language-specific algebra the Lisp reader runs over: each builder maps a parsed construct straight to a Wolfram value. The neutral alternative is the internal AST algebra, reached through [LispAST](), which builds a standard syntax tree instead.
- It is a plain [Association]() with five keys: `"Sym"`, `"Num"`, `"Str"`, `"Quote"`, and `"List"`. [LispGrammar]()'s semantic actions look up these keys, so the algebra *is* the language's meaning - swap it and the same grammar reads to something else.
- `"Sym"` wraps a name in a [LispSymbol](); `"Num"` folds digits with [ToExpression](); `"Str"` reads a quoted token through JSON with [ImportString]() so escapes are honored.
- `"List"` is the identity on its element list - a Lisp list is just a Wolfram [List](). `"Quote"` conses `LispSymbol["quote"]` onto the quoted form, giving the two-element list a downstream evaluator dispatches on.
- [LispRead]() is just [LispGrammar]()`[LispSemantic]` packaged as a function (unwrapping a single top-level form). To get the standard tree for the same grammar, use [LispAST]() instead.

## Basic Examples

The algebra is an [Association]() of builder functions, keyed by form role:

```wl
Keys[LispSemantic]
```

<!-- => {"Sym", "Num", "Str", "Quote", "List"} -->

The `"Sym"` builder wraps a name in a [LispSymbol](), so a non-Wolfram name survives:

```wl
LispSemantic["Sym"]["list->vector"]
```

<!-- => LispSymbol["list->vector"] -->

The `"Num"` builder folds matched digits to a Wolfram number:

```wl
LispSemantic["Num"]["42"]
```

<!-- => 42 -->

The `"List"` builder is the identity - a Lisp list is just a Wolfram list:

```wl
LispSemantic["List"][{1, 2, 3}]
```

<!-- => {1, 2, 3} -->

## Scope

The `"Quote"` builder conses `LispSymbol["quote"]` onto the quoted form:

```wl
LispSemantic["Quote"]["x"]
```

<!-- => {LispSymbol["quote"], "x"} -->

The `"Str"` builder reads a quoted token through JSON, so escapes are interpreted:

```wl
LispSemantic["Str"]["\"hi\""]
```

<!-- => "hi" -->

## Properties and Relations

`LispSemantic` is the algebra that drives [LispRead]() - running [LispGrammar]() over it reads an input string to data:

```wl
LispGrammar[LispSemantic]["(+ 1 2)"]
```

<!-- => {{LispSymbol["+"], 1, 2}} -->

It is one of a pair. The neutral AST algebra shares the same builder-key protocol but builds nodes rather than data; reach it through [LispAST]():

```wl
LispAST["(+ 1 2)"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Symbol", "+", <|"Source" -> {{1, 2}, {1, 3}}|>], {LeafNode["Integer", "1", <|"Source" -> {{1, 4}, {1, 5}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 6}, {1, 7}}|>]}, <|"Source" -> {{1, 2}, {1, 7}}|>]}, <|"Source" -> {{1, 2}, {1, 7}}|>] -->

## Neat Examples

Because the algebra is a plain [Association](), a single key can be overridden to retarget the reader. Reading symbols to bare Wolfram strings instead of [LispSymbol]() wrappers, while every other rule stays put:

```wl
twist = <|LispSemantic, "Sym" -> Function[s, s]|>;
LispGrammar[twist]["(a b c)"]
```

<!-- => {{"a", "b", "c"}} -->

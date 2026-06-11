---
Template: Symbol
Name: JSONSemantic
Context: Wolfram`Parser`Languages`JSON`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/JSONSemantic
Keywords: [JSON, algebra, semantic, parser zoo, fold, builder functions]
SeeAlso: [JSONGrammar, JSONImport, JSONAST, ASTAlgebra, Association]
RelatedGuides: [ParserZoo]
---

## Usage

[JSONSemantic]() is the algebra that folds JSON to a native Wolfram value - an [Association]() of builder functions keyed by production name (`"Str"`, `"Num"`, `"Bool"`, `"Null"`, `"Member"`, `"Object"`, `"Array"`).

## Details & Options

- An *algebra* is the data half of the parser-zoo design: a grammar is written once over abstract builders, and the algebra supplies them. [JSONGrammar]() takes an algebra; `JSONSemantic` is the one that yields native Wolfram values.
- `JSONGrammar[JSONSemantic]` is the parser that [JSONImport]() runs. Each builder is called by the matching grammar action: `"Object"` wraps members in an [Association](), `"Array"` is the identity on the list of elements, `"Member"` makes a [Rule]() from key and value.
- `"Str"` decodes JSON string escapes (delegating to [ImportString]() with `"RawJSON"`), `"Num"` reads the numeric literal, `"Bool"` maps `"true"` to [True](), and `"Null"` produces [Null]().
- Swap `JSONSemantic` for a tree-building algebra and the *same* [JSONGrammar]() emits a [GroupNode]() / [BinaryNode]() / [LeafNode]() syntax tree instead - that mode is [JSONAST](). The grammar is untouched; only the algebra differs. Compare with [ASTAlgebra](), the neutral algebra the rest of the zoo shares.

## Basic Examples

`JSONSemantic` is keyed by production name:

```wl
Keys[JSONSemantic]
```

<!-- => {"Str", "Num", "Bool", "Null", "Member", "Object", "Array"} -->

The `"Object"` builder wraps a member list in an [Association]():

```wl
JSONSemantic["Object"][{"a" -> 1, "b" -> 2}]
```

<!-- => <|"a" -> 1, "b" -> 2|> -->

The `"Member"` builder makes a [Rule]() from a key and a value:

```wl
JSONSemantic["Member"]["a", 1]
```

<!-- => "a" -> 1 -->

## Scope

The `"Str"` builder decodes JSON escapes - `\n` in the source token becomes a real newline:

```wl
JSONSemantic["Str"]["\"a\\nb\""]
```

<!-- => "a\nb" -->

The `"Num"` builder reads exponent notation:

```wl
JSONSemantic["Num"]["1e3"]
```

<!-- => 1000 -->

The `"Bool"` builder maps the literal text to [True]() or [False]():

```wl
JSONSemantic["Bool"]["true"]
```

<!-- => True -->

## Properties and Relations

`JSONSemantic` is what makes [JSONImport]() native. Folding a parsed object yields an [Association]():

```wl
JSONImport["{\"a\": 1, \"b\": 2}"]
```

<!-- => <|"a" -> 1, "b" -> 2|> -->

Feeding the *same* [JSONGrammar]() a tree algebra instead gives structure, not value - the [JSONAST]() mode:

```wl
JSONAST["{\"a\": 1, \"b\": 2}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"a\"", <|"Source" -> {{1, 2}, {1, 5}}|>], LeafNode["Integer", "1", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>], BinaryNode[":", {LeafNode["String", "\"b\"", <|"Source" -> {{1, 10}, {1, 13}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 15}, {1, 16}}|>]}, <|"Source" -> {{1, 10}, {1, 16}}|>]}, <|"Source" -> {{1, 2}, {1, 16}}|>]}, <|"Source" -> {{1, 2}, {1, 16}}|>] -->

## Neat Examples

Because an algebra is just an [Association]() of functions, it is plain inspectable data - the `"Array"` builder is simply the identity on the parsed element list:

```wl
JSONSemantic["Array"][{1, 2, 3}]
```

<!-- => {1, 2, 3} -->

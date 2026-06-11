---
Template: Symbol
Name: JSONImport
Context: Wolfram`Parser`Languages`JSON`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/JSONImport
Keywords: [JSON, import, parser zoo, RFC 8259, association, semantic algebra]
SeeAlso: [JSONAST, JSONGrammar, JSONSemantic, Import, ImportString]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[JSONImport]()[*json*]</code> parses the JSON string *json* to a native Wolfram value - an [Association](), [List](), [String](), number, or one of [True]() / [False]() / [Null]().

## Details & Options

- `JSONImport` is the *semantic* mode of the JSON grammar: it runs [JSONGrammar]() over [JSONSemantic](), the algebra that folds each production directly to a Wolfram value. There is no intermediate tree.
- A JSON object becomes an [Association](), a JSON array becomes a [List](), a JSON string becomes a [String]() (with escapes decoded), `true` / `false` / `null` become [True]() / [False]() / [Null]().
- [JSONAST]() runs the *same* [JSONGrammar]() over a different algebra and returns the [GroupNode]() / [BinaryNode]() / [LeafNode]() syntax tree instead. One grammar, two algebras.
- The grammar covers RFC 8259 JSON. Only escape decoding and the numeric-literal reading delegate to the kernel ([ImportString]() with `"RawJSON"`, and [ToExpression]() on a regex-validated token); the object / array / member structure is all combinators.
- On a duplicate key the *last* value wins, matching [Association]() semantics.
- Input that does not parse to completion returns a [Failure]() (see [Parse]()).

## Basic Examples

An object becomes an [Association](), an array a [List]():

```wl
JSONImport["{\"a\": [1, true]}"]
```

<!-- => <|"a" -> {1, True}|> -->

`true` / `false` / `null` map onto [True]() / [False]() / [Null]():

```wl
JSONImport["null"]
```

<!-- => Null -->

A bare number reads as a Wolfram number:

```wl
JSONImport["3.14"]
```

<!-- => 3.14 -->

## Scope

Objects and arrays nest to any depth:

```wl
JSONImport["{\"name\": \"Ann\", \"age\": 30, \"tags\": [\"x\", \"y\"]}"]
```

<!-- => <|"name" -> "Ann", "age" -> 30, "tags" -> {"x", "y"}|> -->

The empty object is an empty [Association](); the empty array is an empty [List]():

```wl
JSONImport["{}"]
```

<!-- => <||> -->

```wl
JSONImport["[]"]
```

<!-- => {} -->

A string escape is decoded - `\n` in the source becomes a real newline character:

```wl
JSONImport["\"a\\nb\""]
```

<!-- => "a\nb" -->

Exponential notation reads as a [Real]():

```wl
JSONImport["1.5e2"]
```

<!-- => 150. -->

## Properties and Relations

`JSONImport` agrees with the kernel's own [ImportString]() over `"RawJSON"`:

```wl
JSONImport["{\"a\": 1, \"b\": [true, null]}"] === ImportString["{\"a\": 1, \"b\": [true, null]}", "RawJSON"]
```

<!-- => True -->

The same source through [JSONAST]() is a syntax tree, not a value - structure instead of meaning:

```wl
JSONAST["{\"a\": [1, true]}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"a\"", <|"Source" -> {{1, 2}, {1, 5}}|>], GroupNode["Array", {LeafNode["Integer", "1", <|"Source" -> {{1, 8}, {1, 9}}|>], LeafNode["Boolean", "true", <|"Source" -> {{1, 11}, {1, 15}}|>]}, <|"Source" -> {{1, 8}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>]}, <|"Source" -> {{1, 2}, {1, 15}}|>] -->

On a repeated key, the last binding wins, as with any [Association]():

```wl
JSONImport["{\"a\": 1, \"a\": 2}"]
```

<!-- => <|"a" -> 2|> -->

## Possible Issues

A truncated array is an honest [Failure](), reporting how far it parsed and what it expected next:

```wl
JSONImport["[1, 2"]
```

<!-- => Failure["ParseError", <|"Position" -> 6, "Expected" -> {"]"}, "Found" -> "<end of input>"|>] -->

JSON object keys must be quoted strings; a bare identifier key does not parse:

```wl
JSONImport["{a: 1}"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> {"}"}, "Found" -> "a"|>] -->

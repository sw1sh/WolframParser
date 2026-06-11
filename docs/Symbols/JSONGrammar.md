---
Template: Symbol
Name: JSONGrammar
Context: Wolfram`Parser`Languages`JSON`
ContextPath: [Wolfram`Parser`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/JSONGrammar
Keywords: [JSON, grammar, algebra, parser zoo, ParserCombinator, RFC 8259]
SeeAlso: [JSONSemantic, JSONImport, JSONAST, ParserCombinator, ASTAlgebra, Parse]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[JSONGrammar]()[*alg*]</code> builds the RFC 8259 JSON parser, a [ParserCombinator](), parameterized over the algebra *alg* - an [Association]() of builder functions its semantic actions call.

## Details & Options

- `JSONGrammar` is the *one* grammar behind both JSON modes. The grammar structure - objects, arrays, members, the string and number tokens - is fixed; *alg* decides what each production *builds*.
- Hand it [JSONSemantic]() and it folds JSON to a native Wolfram value; that parser is what [JSONImport]() runs. Hand it the tree-building algebra and it emits the [GroupNode]() / [BinaryNode]() / [LeafNode]() syntax tree; that parser is what [JSONAST]() runs. One grammar, two algebras.
- *alg* must supply the builders the actions call: `"Str"`, `"Num"`, `"Bool"`, `"Null"`, `"Member"`, `"Object"`, `"Array"`. [JSONSemantic]() is one such algebra.
- The returned [ParserCombinator]() runs on a string the usual way: <code>*parser*[*input*]</code>, equivalently <code>[Parse]()[*parser*, *input*]</code>.
- Object and array recursion is wired through the recursion cells of the parser zoo ([RecCell](), [RecRef](), [SetRec]()), so a value may nest inside an array inside an object to any depth.

## Basic Examples

`JSONGrammar` over [JSONSemantic]() is a [ParserCombinator]():

```wl
Head[JSONGrammar[JSONSemantic]]
```

<!-- => ParserCombinator -->

Run it on a string to fold JSON to a native value:

```wl
JSONGrammar[JSONSemantic]["[1, 2, 3]"]
```

<!-- => {1, 2, 3} -->

That is exactly what [JSONImport]() does:

```wl
JSONImport["[1, 2, 3]"]
```

<!-- => {1, 2, 3} -->

## Scope

The grammar is recursive: a value may be an object whose member is itself an object:

```wl
JSONGrammar[JSONSemantic]["{\"a\": {\"b\": 1}}"]
```

<!-- => <|"a" -> <|"b" -> 1|>|> -->

Feeding the same grammar a tree-building algebra gives the standard AST instead. That mode is exposed as [JSONAST]() - the same [JSONGrammar]() over a node-builder algebra:

```wl
JSONAST["{\"a\": {\"b\": 1}}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"a\"", <|"Source" -> {{1, 2}, {1, 5}}|>], GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"b\"", <|"Source" -> {{1, 8}, {1, 11}}|>], LeafNode["Integer", "1", <|"Source" -> {{1, 13}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>]}, <|"Source" -> {{1, 8}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>]}, <|"Source" -> {{1, 2}, {1, 14}}|>] -->

## Properties and Relations

The two modes are the *same* grammar with different builders. The semantic algebra folds an object to an [Association]():

```wl
JSONGrammar[JSONSemantic]["{\"a\": 1}"]
```

<!-- => <|"a" -> 1|> -->

while the tree mode pairs the key leaf and the value leaf in a `":"` [BinaryNode]() under a `"Object"` [GroupNode]():

```wl
JSONAST["{\"a\": 1}"]
```

<!-- => ContainerNode["String", {GroupNode["Object", {BinaryNode[":", {LeafNode["String", "\"a\"", <|"Source" -> {{1, 2}, {1, 5}}|>], LeafNode["Integer", "1", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>]}, <|"Source" -> {{1, 2}, {1, 8}}|>] -->

## Possible Issues

The parser returned by `JSONGrammar` reports a [Failure]() on input it cannot finish, just like [Parse]() - here a JSON object with an unquoted key:

```wl
JSONGrammar[JSONSemantic]["{a: 1}"]
```

<!-- => Failure["ParseError", <|"Position" -> 2, "Expected" -> {"}"}, "Found" -> "a"|>] -->

---
Template: Guide
Name: ParserZoo
Title: The Parser Zoo - language front-ends over a shared algebra
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`Languages`JSON`, Wolfram`Parser`Languages`Lisp`, Wolfram`Parser`Languages`Lambda`, Wolfram`Parser`Languages`Brainfuck`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/guide/ParserZoo
Description: A showcase suite that battle-tests Wolfram/Parser by building a spread of language front-ends - calculator, JSON, Lisp, lambda calculus, Brainfuck - each grammar written once over a shared algebra and run two ways: with the language's meaningful actions, or with the shared ASTAlgebra to get a standard, CodeParser-shaped syntax tree.
Keywords: [parser zoo, language front-ends, AST, algebra, calculator, JSON, Lisp, lambda calculus, Brainfuck]
RelatedGuides: [WolframParser]
---

## Abstract

The *parser zoo* is a spread of language front-ends built on <code>Wolfram\`Parser\`</code> - a [CalculatorAST]() calculator, a [JSONImport]() reader, a [LispRead]() s-expression reader, a [LambdaEval]() lambda-calculus interpreter, and a [BrainfuckRun]() Brainfuck runner - chosen to stress different corners of the library: operator precedence, recursive data, binders, comment-aware whitespace, and an esoteric language the parser also *runs*. The one big idea is that each grammar is written **once** over an abstract *algebra* - an [Association]() of builder functions its semantic actions call - then run two ways. Hand the grammar the language's **meaningful** actions and it yields a useful value: a number, a native Wolfram expression, a program's output. Hand it the shared [ASTAlgebra]() and the same grammar yields a standard, language-neutral syntax tree modelled on Wolfram's own [CodeParser]() shape. That is the whole point: *meaningful language-specific parse actions, but without which a standard AST*. The grammar is untouched; only the algebra is swapped.

## The standard AST

The neutral node vocabulary is core <code>Wolfram\`Parser\`</code> (the languages live in their own subcontexts, <code>Wolfram\`Parser\`Languages\`Calculator\`</code> and friends). Every node is a 3-slot triple `Head[descriptor, children, <|meta|>]` mirroring [CodeParser](), but the operator descriptors stay language-native strings (`"+"`, `":"`, `"'"`) instead of being forced into Wolfram symbols, so the *same* vocabulary serves a calculator, JSON, Lisp, the lambda calculus, and Brainfuck alike.

- [LeafNode]() a terminal - a literal or identifier, keeping its source text
- [CallNode]() an application or call; the head is itself a node
- [PrefixNode]() a prefix-operator application
- [PostfixNode]() a postfix-operator application
- [BinaryNode]() a binary-operator application
- [InfixNode]() a flat n-ary operator chain
- [TernaryNode]() a ternary-operator application
- [GroupNode]() a delimited group (`"Paren"`, `"Array"`, `"Object"`, `"Loop"`, ...)
- [ContainerNode]() the root node wrapping every top-level form
- [ErrorNode]() a syntax-error token

The pieces that make the dual-algebra design work:

- [ASTAlgebra]() the [Association]() of builder functions that emit the standard nodes; hand it to any grammar in place of the language's own algebra
- [ASTContainer]() wrap a list of top-level forms in a [ContainerNode]() root
- [ToCodeParser]() project a neutral tree onto [CodeParser]()-exact nodes, mapping operator descriptors to Wolfram symbols

Every node also carries a `"Source"` span in its metadata - a [CodeParser]() line-column pair `{{startLine, startColumn}, {endLine, endColumn}}`. That comes from a three-part source-position toolkit, also core <code>Wolfram\`Parser\`</code>: [ParsePosition]() is the zero-width primitive that reads the cursor offset, [SpannedToken]() brackets each leaf with two `ParsePosition[]`s to record its offset span, and [ASTAddSource]() spans the composites over their children and converts every offset to the `{line, column}` pair above.

Running [CalculatorGrammar]() over [ASTAlgebra]() gives a tree that nests by precedence - `*` binds tighter than `+` - and every node carries its source span:

```wl
CalculatorAST["1 + 2*3"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], BinaryNode["*", {LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>], LeafNode["Integer", "3", <|"Source" -> {{1, 7}, {1, 8}}|>]}, <|"Source" -> {{1, 5}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>]}, <|"Source" -> {{1, 1}, {1, 8}}|>] -->

A leaf spans its own text; a composite spans its children. A multi-line input makes that visible - the addition's span runs from line 1 to line 2:

```wl
CalculatorAST["1 +\n2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{2, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 1}, {2, 2}}|>]}, <|"Source" -> {{1, 1}, {2, 2}}|>] -->

The neutral nodes project onto Wolfram's own shape with [ToCodeParser](), which maps each operator descriptor to a Wolfram symbol (`"+"` to [Plus]()):

```wl
ToCodeParser[CalculatorAST["1+2"], <|"+" -> Plus|>]
```

<!-- => CodeParser`ContainerNode["String", {CodeParser`CallNode[CodeParser`LeafNode[Symbol, Plus, <||>], {CodeParser`LeafNode[Integer, "1", <|"Source" -> {{1, 1}, {1, 2}}|>], CodeParser`LeafNode[Integer, "2", <|"Source" -> {{1, 3}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>]}, <|"Source" -> {{1, 1}, {1, 4}}|>] -->

## Languages

Each language exposes the same pair of entry points - an `XxxAST` standard-AST mode and a meaningful run - plus the `XxxGrammar`/`XxxSemantic` algebra pair behind them. The grammar is shared; the two entry points differ only in which algebra they feed it.

### Calculator

A four-function calculator with `^`, unary minus, parentheses and bare identifiers, built with the library's [ParseOperatorTable]() so left-nested input stays linear. It stresses operator precedence and associativity.

- [CalculatorAST]() parse to a standard AST of [BinaryNode]() / [PrefixNode]() / [LeafNode]()
- [CalculatorEval]() run the same grammar to a number (identifiers stay symbolic)
- [CalculatorGrammar]() the grammar, parameterised over an algebra
- [CalculatorSemantic]() the algebra that folds to a numeric / symbolic value

### JSON

A complete RFC 8259 reader. Objects and arrays nest through recursion, and the grammar exercises string escapes and the number grammar; only escape-decoding and numeric reading delegate to the kernel.

- [JSONAST]() parse to a standard AST of [GroupNode]() / [BinaryNode]() / [LeafNode]()
- [JSONImport]() run the same grammar to a native [Association]() / [List]() / value
- [JSONGrammar]() the grammar, parameterised over an algebra
- [JSONSemantic]() the algebra that folds to a native Wolfram value

```wl
JSONImport["{\"a\": [1, true]}"]
```

<!-- => <|"a" -> {1, True}|> -->

### Lisp

An s-expression reader: atoms, parenthesised lists, the quote reader macro (`'x`), and `;`-to-end-of-line comments. The whole language is one self-similar rule, so it leans on recursion and comment-aware whitespace.

- [LispAST]() parse to a standard AST of [CallNode]() / [LeafNode](), with `'` as a [PrefixNode]()
- [LispRead]() the classic Lisp `read` - source becomes nested data plus [LispSymbol]() wrappers
- [LispSymbol]() a read Lisp symbol, kept distinct from a Wolfram [Symbol]() (names like `+` or `list->vector` are not Wolfram identifiers)
- [LispGrammar]() the grammar, parameterised over an algebra
- [LispSemantic]() the algebra that reads to native Wolfram data

```wl
LispRead["(+ 1 (max 2 3))"]
```

<!-- => {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}} -->

### Lambda calculus

The untyped lambda calculus: variables, abstraction (`\x. body` or the unicode `\[Lambda]x. body`, with `\x y. b` sugar for `\x.\y.b`), and application by juxtaposition. It stresses binders and the application/abstraction precedence split.

- [LambdaAST]() parse to a standard AST - a [CallNode]() application, a [CallNode]() abstraction headed by a lambda, [LeafNode]() variables
- [LambdaEval]() compile each abstraction to a native Wolfram [Function]() and let the kernel beta-reduce
- [LambdaGrammar]() the grammar, parameterised over an algebra
- [LambdaSemantic]() the algebra that compiles to native Wolfram closures

[LambdaEval]() is the striking one: a Church numeral `\f.\x.f (f x)` applied to `g` and `y` reduces to `g[g[y]]` because the kernel does the substitution:

```wl
LambdaEval["(\\f.\\x.f (f x)) g y"]
```

<!-- => g[g[y]] -->

### Brainfuck

The eight Brainfuck commands over a byte tape, where every other character is a comment. Tiny lexically, but `[ ]` nests arbitrarily, so it exercises recursion and comment-skipping - and the parser also *runs* it: each command compiles to a `machine -> machine` closure, a sequence to their right-composition, a loop to a [NestWhile]().

- [BrainfuckAST]() parse to a standard AST of [LeafNode]() commands and <code>[GroupNode]()["Loop", ...]</code>
- [BrainfuckRun]() compile to a Wolfram closure, run it on a fresh byte tape, and return the output string
- [BrainfuckGrammar]() the grammar, parameterised over an algebra
- [BrainfuckSemantic]() the algebra that compiles to an executable closure

```wl
BrainfuckRun["++++++[>++++++++++<-]>+++++."]
```

<!-- => "A" -->

## Building your own front-end

To add a language, write the grammar builder once - a function `fooGrammar[alg_]` whose every semantic action calls into `alg[...]` rather than building a concrete value - then define the two algebras it runs over. Model it on [CalculatorGrammar](): feed it [ASTAlgebra]() for the standard tree, feed it your own `FooSemantic` for the meaningful value.

For recursion, do not point a [ParseRecursive]() at a [Module]()-local symbol; it can be garbage-collected once the builder returns, silently breaking the recursion. Use the recursion-cell helpers instead, which wrap a stable global symbol the way the paclet's own EBNF front-end does:

- [RecCell]() allocate a recursion cell - a stable symbol for a self- or mutually-recursive production
- [RecRef]() reference a cell as a [ParseRecursive]() target, before or after its parser is set
- [SetRec]() give a cell its parser

The BuildingLanguageFrontEnds tech note walks through this end to end, including the battle-testing findings - how [ParseAction]() auto-splats a list-valued result, why a recursion target should be a [ParseChoice]() of concrete alternatives rather than a nullable-prefixed production, and how [ParsePosition]() / [SpannedToken]() / [ASTAddSource]() thread source spans onto the standard nodes.

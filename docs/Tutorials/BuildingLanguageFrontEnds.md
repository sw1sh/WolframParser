---
Template: TechNote
Name: BuildingLanguageFrontEnds
Title: Building Language Front-Ends
Context: Wolfram`Parser`
ContextPath: [Wolfram`Parser`Languages`Calculator`, Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/BuildingLanguageFrontEnds
Keywords: [parser zoo, algebra, front-end, AST, recursion cell, semantic actions]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingTPTP, PrattVsPEG]
---

## What this note covers

A *language front-end* is the part of a tool that turns source text into something the rest of the tool can work with - a syntax tree to inspect and rewrite, or a value to evaluate. The paclet ships a "parser zoo" (`Languages/`) that builds exactly these front-ends - a calculator, JSON, Lisp, the lambda calculus, Brainfuck - on a single design idea. This note teaches that idea by building a small calculator front-end end to end, and the techniques generalize to every language in the zoo.

The idea is *one grammar, two algebras*. The grammar is written **once**, parameterized over an **algebra**: an [Association]() of builder functions that the grammar's semantic actions call. Run that one grammar over the standard [ASTAlgebra]() and you get a language-neutral syntax tree. Run the *same* grammar over a meaningful algebra and you get a value - a number, a native Wolfram expression, a program's output. The grammar never changes; only the algebra is swapped. That is what lets a front-end produce a clean inspectable tree *and* a useful result without writing two parsers.

This note builds up one running calculator grammar - a function `calc[alg]` - near the top, then reuses and extends it section by section: first to emit a tree, then to evaluate to a number, then to show how recursion is wired safely. A closing `## Gotchas` section distills the sharp edges the zoo ran into while battle-testing the library.

---

## The core idea: a grammar over an algebra

An algebra is just an [Association]() whose values are builder functions. The standard one is [ASTAlgebra](), defined in `Wolfram`Parser``. Its `"Binary"` entry builds a [BinaryNode]() - the neutral, [CodeParser]()-shaped node for a binary-operator application:

```wl
ASTAlgebra["Binary"]["+", a, b]
```

<!-- => BinaryNode["+", {a, b}, <||>] -->

The node is a 3-slot `Head[descriptor, children, <|meta|>]` triple, exactly like Wolfram's own [CodeParser]() output - but the operator descriptor stays a language-native string (`"+"`), not a Wolfram symbol. [ASTAlgebra]() has a builder for each standard node shape: `"Leaf"`, `"Prefix"`, `"Binary"`, `"Infix"`, `"Call"`, `"Group"`, and so on.

A grammar that wants to be algebra-parametric never writes `BinaryNode[...]` directly. It writes `alg["Binary"][op, l, r]` and lets the caller decide what that means. Hand it [ASTAlgebra]() and the call builds a [BinaryNode](); hand it a numeric algebra and the same call computes `l + r`. That single indirection - actions call `alg[...]` instead of a fixed head - is the whole design.

---

## Building the calculator grammar

Here is the running grammar for this note: a four-function calculator with `*` `/` `+` `-`, unary minus, parentheses, integer literals, and bare identifiers. It is defined **once**, as a builder `calc[alg]`, and every later section reuses it.

Two helpers carry their weight. `ws` skips trailing whitespace, and `tok` wraps a parser so it consumes that whitespace after matching - a token recognizer that does not care about surrounding spaces. Literals and number / identifier regexes all go through `tok`, so `"1 + 2"` and `"1+2"` parse the same.

Precedence is *data*, not structure: [ParseOperatorTable]() takes the operand parser *unit* and a list of precedence levels, tightest-binding first. Each operator parser returns the **combining function** the table folds - a unary [Function]() for a prefix operator, a binary one for an infix operator - which is where the algebra enters. Parentheses re-enter the table through a recursion cell ([RecCell]() / [RecRef]() / [SetRec](), covered in detail below).

```wl
calc[alg_] := Module[{ws, tok, number, ident, unit, bin, pre, expr},
    expr = RecCell[];
    ws = ParseMany[ParseCharacter[WhitespaceCharacter]];
    tok[p_] := ParseAction[p ~~ ws, #1 &];
    number = ParseAction[
        tok @ ParseRegex["[0-9]+"],
        Function[s, alg["Leaf"]["Integer", s]]];
    ident = ParseAction[
        tok @ ParseRegex["[A-Za-z][A-Za-z0-9]*"],
        Function[s, alg["Leaf"]["Symbol", s]]];
    unit = ParseChoice[
        ParseBetween[tok @ ParseLiteral["("], RecRef[expr], tok @ ParseLiteral[")"]],
        number, ident];
    bin[op_] := ParseAction[tok @ ParseLiteral[op],
        (Function[{l, r}, alg["Binary"][op, l, r]]) &];
    pre[op_] := ParseAction[tok @ ParseLiteral[op],
        (Function[x, alg["Prefix"][op, x]]) &];
    SetRec[expr, ParseOperatorTable[unit, {
        {{"Prefix", pre["-"]}},
        {{"InfixL", bin["*"]}, {"InfixL", bin["/"]}},
        {{"InfixL", bin["+"]}, {"InfixL", bin["-"]}}
    }]];
    RecRef[expr]
]
```

<!-- => Null -->

Every semantic action - the [Function]() inside each [ParseAction]() - calls `alg[...]`. `number` calls `alg["Leaf"]["Integer", s]`, `bin[op]` returns a function that calls `alg["Binary"][op, l, r]`, and `pre[op]` returns one that calls `alg["Prefix"][op, x]`. Nothing in `calc` commits to what a "Leaf", "Binary", or "Prefix" *is*. That is decided entirely by the algebra passed in.

A note on the operator parsers: [ParseOperatorTable]() expects each *opParser* to **return its combining function**, not the operator string. That is the extra `&` in `bin` and `pre` - `(Function[{l, r}, ...]) &` is a function that, when the operator token matches, *returns* the binary builder. The table then applies that builder to the operands it has parsed.

---

## Running it two ways

Now the payoff. The grammar above is a builder; feeding it an algebra produces a [ParserCombinator](), which is callable directly on input - `parser["input"]` is exactly [Parse]()[*parser*, *input*].

Hand `calc` the standard [ASTAlgebra]() and parse `"1 + 2*3"`. The result is a syntax tree, nested by precedence - `*` binds tighter than `+`, so the multiplication sits inside the addition's right child:

```wl
calc[ASTAlgebra]["1 + 2*3"]
```

<!-- => BinaryNode["+", {LeafNode["Integer", "1", <||>], BinaryNode["*", {LeafNode["Integer", "2", <||>], LeafNode["Integer", "3", <||>]}, <||>]}, <||>] -->

Unary minus routes through the algebra's `"Prefix"` builder, and a bare identifier becomes a `"Symbol"` [LeafNode]() - the literal text is kept, uninterpreted:

```wl
calc[ASTAlgebra]["-x"]
```

<!-- => PrefixNode["-", LeafNode["Symbol", "x", <||>], <||>] -->

Now define a tiny **semantic algebra**: the same three keys the grammar calls, but each builder produces a *value* instead of a node. `"Leaf"` turns an integer literal into a number (and an identifier into a [Symbol]()); `"Binary"` does the arithmetic; `"Prefix"` negates.

```wl
mathAlg = <|
    "Leaf" -> Function[{kind, src},
        If[kind === "Integer", FromDigits[src], Symbol[src]]],
    "Binary" -> Function[{op, l, r},
        Switch[op, "+", l + r, "-", l - r, "*", l*r, "/", l/r]],
    "Prefix" -> Function[{op, x}, -x]
|>
```

<!-- => <|"Leaf" -> Function[{kind, src}, If[kind === "Integer", FromDigits[src], Symbol[src]]], "Binary" -> Function[{op, l, r}, Switch[op, "+", l + r, "-", l - r, "*", l*r, "/", l/r]], "Prefix" -> Function[{op, x}, -x]|> -->

Run the *same* `calc` grammar over `mathAlg` on the *same* input. No tree this time - the actions fold straight to a number as the parse proceeds:

```wl
calc[mathAlg]["1 + 2*3"]
```

<!-- => 7 -->

Parentheses, precedence, and unary minus all still hold, because they live in the grammar, not the algebra:

```wl
calc[mathAlg]["2*(3 + 4)"]
```

<!-- => 14 -->

Same grammar, swapped algebra: a tree front-end and an evaluator from a single source. This is precisely the split the zoo's [CalculatorAST]() (over [ASTAlgebra]()) and [CalculatorEval]() (over [CalculatorSemantic]()) ship - the only difference is that the shipped grammar also handles real literals and `^`.

---

## Recursion the safe way

The calculator's parenthesis rule is recursive: a parenthesized group contains an expression, which may itself contain another parenthesized group. The library expresses self-reference with [ParseRecursive](), which holds a **symbol** and looks up the symbol's value at parse time. That indirection is what lets `unit` refer to the whole expression grammar before the grammar is finished being built.

The trap is *which* symbol. [ParseRecursive]()[*sym*] keeps only *sym*; the actual parser lives in the symbol's value. If *sym* is a [Module]()-local, the only live reference to it once `calc` returns is the one held inside [ParseRecursive]() - and a [Module]()-local with a single reference can be **garbage-collected**. When it is, the recursion silently breaks: a parenthesized group drops its body, a nested form never parses. Worse, *when* the collection happens depends on unrelated load order, so the same grammar can work in one session and fail in another. That is a miserable bug to chase.

The fix is the [RecCell]() / [RecRef]() / [SetRec]() trio from `Wolfram`Parser``. [RecCell]() allocates a fresh global [Unique]() symbol kept un-evaluated inside a [HoldFirst]() wrapper, so it never gets collected; [RecRef]()[*cell*] is the [ParseRecursive]() reference to it; [SetRec]()[*cell*, *parser*] gives the cell its parser. That is the `expr = RecCell[]` / `RecRef[expr]` / `SetRec[expr, ...]` wiring already in `calc` above. The same `Unique[]`-per-rule pattern is what the paclet's own EBNF front-end uses internally.

Here is the pattern on its own, as small as it gets - a parser for balanced nested parentheses that returns the nesting depth. The recursion cell `nest` refers to itself through [RecRef](), and [ParseMany]() lets a group hold any number of inner groups:

```wl
depthParser = Module[{nest},
    nest = RecCell[];
    SetRec[nest, ParseAction[
        ParseLiteral["("] ~~ ParseMany[RecRef[nest]] ~~ ParseLiteral[")"],
        Function[{l, inner, r}, 1 + Max[Append[inner, 0]]]]];
    RecRef[nest]
]
```

<!-- => ParserCombinator summary box, Type: "Recursive", Arity: 1 -->

The action receives three pieces - the `"("`, the list of inner depths from the [ParseMany](), and the `")"`. The body adds one for the current pair and takes the deepest child (or `0` if there are none). Fully nested input is as deep as it is wide:

```wl
depthParser["((()))"]
```

<!-- => 3 -->

Siblings do not add depth - two pairs side by side inside one outer pair is depth 2:

```wl
depthParser["(()())"]
```

<!-- => 2 -->

```wl
depthParser["()"]
```

<!-- => 1 -->

The key takeaways: a [ParseRecursive]() target must outlive the builder, so use [RecCell]() rather than a raw [Module]()-local symbol; and recurse through a [ParseChoice]() of concrete alternatives (or a fixed-prefix sequence like the `"("`-led rule here), never through a production that starts with a nullable parser - see the `## Gotchas` below.

---

## Gotchas

These are the library behaviors the parser zoo ran into. Each one is cheap to avoid once you know it is there.

**[ParseAction]() auto-splats a list-valued result.** [ParseAction]()[*p*, *f*] calls *f* `@@` *value* when *p*'s value is a [List](), and `f[value]` otherwise. That is what makes a sequence `a ~~ b ~~ c` arrive as `f[va, vb, vc]` - convenient - but it also silently splats a sub-result you wanted to keep whole, like the list from a [ParseMany](). Two clean ways to keep a list intact: consume it as one *positional* element of an enclosing sequence (`a ~~ items ~~ b` with `#2` reading `items` untouched), or collect it right at the [ParseMany]() with `{##}`:

```wl
Parse[ParseAction[ParseMany[ParseLiteral["a"]], {##} &], "aaa"]
```

<!-- => {"a", "a", "a"} -->

A corollary: keep the action's arity in sync with the sequence length. A length-3 sequence applied through a 2-argument [Function]() *silently drops the third element* rather than erroring, so use a variadic `{##}` when you do not want to commit to a fixed count.

**Keep recursion targets stable, and non-nullable-prefixed.** Two rules, both from the recursion section. The [ParseRecursive]() target must be a stable global symbol ([RecCell]()), not a [Module]()-local that can be garbage-collected. And the target should be a [ParseChoice]() of concrete alternatives, or a rule that starts with a real token - never a production beginning with a nullable parser (a [ParseMany]() or a `*`-quantified regex) followed by the real content. Re-entering at a nullable prefix was observed to match empty and bail out instead of recursing.

**Source positions: a gotcha that became a feature.** A semantic action receives parse *values*, not cursor positions - so a bare grammar like the `calc` above, whose actions only ever call `alg[...]` on values, leaves every node's metadata empty. The minimal grammar in this note still does exactly that:

```wl
calc[ASTAlgebra]["1"]
```

<!-- => LeafNode["Integer", "1", <||>] -->

What closed the gap was engine support that threads the cursor through to the actions, plus two helpers built on it. [ParsePosition]() is the zero-width primitive that reads the current character offset and consumes nothing; [SpannedToken]() brackets a token between two `ParsePosition[]`s, builds the leaf, and stamps the captured `{start, end}` offset span onto it (trailing whitespace excluded); [ASTAddSource]() then fills every composite node's span by spanning its children and converts every offset to a `{{line, column}, {line, column}}` pair - [CodeParser]()'s LineColumn convention. The shipped [CalculatorAST]() wires its leaf recognizers through [SpannedToken]() and finishes with [ASTAddSource](), so its nodes *do* carry spans:

```wl
CalculatorAST["1 + 2"]
```

<!-- => ContainerNode["String", {BinaryNode["+", {LeafNode["Integer", "1", <|"Source" -> {{1, 1}, {1, 2}}|>], LeafNode["Integer", "2", <|"Source" -> {{1, 5}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>]}, <|"Source" -> {{1, 1}, {1, 6}}|>] -->

The honest gaps remain: a [SpannedToken]() leaf gets its span from the source text it matched, and a composite gets the convex hull of its children's spans, but a *synthesized* leaf the grammar conjures with no matched text has nothing to span - and a [GroupNode]() spans only its content, since the delimiters are consumed structurally, not stamped. So treat `Source` as present-and-trustworthy where a token backs it, and absent otherwise, rather than assuming every node is annotated.

The top-level [Parse]() failure carries a position independently of any of this - an incomplete expression is an honest [Failure]() that reports how far it got and what it expected:

```wl
calc[ASTAlgebra]["1 +"]
```

<!-- => Failure["ParseError", <|"Position" -> 4, "Expected" -> {"(", "regex /[0-9]+/", "regex /[A-Za-z][A-Za-z0-9]*/"}, "Found" -> "<end of input>"|>] -->

---

## Where to go from here

The calculator is the simplest front-end in the zoo; the same `grammar[alg]` design scales to recursive data, binders, and even an executable esoteric language. Each language ships an `XxxGrammar` builder, an AST run, and a meaningful run, and the per-language reference pages walk through what each one stresses:

- [JSONGrammar]() - recursive data, string escapes, the number grammar; the AST run emits [GroupNode]() / [BinaryNode]() / [LeafNode](), the meaningful run native [Association]() / [List]().
- [LispGrammar]() - one uniform self-similar rule, the quote reader macro, and `;` comments; recursion through a single [ParseChoice]().
- [BrainfuckGrammar]() - esoteric lexing and arbitrarily nested loops, whose semantic algebra compiles each command to a `machine -> machine` closure so the parsed program *runs*.
- [LambdaGrammar]() - binders and the application / abstraction precedence split, whose meaningful run produces a native closure the kernel beta-reduces.

For the bigger picture - how every grammar in the zoo is one algebra-parameterized builder run two ways - see the parser zoo guide. For a production-scale front-end built the same way from a published grammar file, see the *Parsing TPTP* tech note.

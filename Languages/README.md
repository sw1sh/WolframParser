# Languages - a parser zoo for battle-testing `Wolfram/Parser`

A spread of grammars built on the parser-combinator library, from a four
function calculator to the lambda calculus, chosen to exercise different
corners of the library: operator precedence, recursive data, binders,
whitespace/comment handling, and an esoteric language the parser also *runs*.

Each grammar is written **once** over an abstract algebra and run two ways:

- with the language's **meaningful** actions, producing a useful value (a
  number, a native Wolfram expression, a program's output);
- with the **AST** algebra, producing a standard, language-neutral syntax
  tree modelled on Wolfram's own [`CodeParser`](paclet:CodeParser) output.

That is the whole point: *meaningful language-specific parse actions, but
without which a standard AST*. The grammar is untouched; only the algebra
is swapped.

## Quick start

```wl
PacletDirectoryLoad["/path/to/WolframParser/Parser"];
Get["/path/to/WolframParser/Languages/init.wl"];

CalculatorEval["1 + 2*3"]          (* 7                                    *)
CalculatorAST["1 + 2*3"]           (* ContainerNode[.. BinaryNode["+", ..] *)

JSONImport["{\"a\": [1, true]}"]   (* <|"a" -> {1, True}|>                 *)
LispRead["(+ 1 (max 2 3))"]        (* {LispSymbol["+"], 1, {LispSymbol["max"], 2, 3}} *)
LambdaEval["(\\x.\\y.x) a b"]      (* a                                    *)
BrainfuckRun["++++++[>++++++++++<-]>+++++."]  (* "A"                       *)
```

Run the test suite with `wl -f Languages/run-tests.wls` (53 tests).

## The languages

| File | What it stresses | `XxxAST` (standard AST) | meaningful run |
|------|------------------|-------------------------|----------------|
| [Calculator.wl](Calculator.wl) | operator precedence / associativity via `ParseOperatorTable` | `BinaryNode`/`PrefixNode`/`LeafNode` | `CalculatorEval` -> a number, identifiers stay symbolic |
| [JSON.wl](JSON.wl) | recursive data, string escapes, the number grammar | `GroupNode`/`BinaryNode`/`LeafNode` | `JSONImport` -> native `Association`/`List`/... |
| [Lisp.wl](Lisp.wl) | uniform recursion, the quote reader macro, `;` comments | `CallNode`/`LeafNode`, `'` as `PrefixNode` | `LispRead` -> nested data + `LispSymbol[..]` |
| [Lambda.wl](Lambda.wl) | binders, the application/abstraction precedence split, unicode (`\[Lambda]`) | `CallNode` headed by lambda | `LambdaEval` -> a native closure the kernel beta-reduces |
| [Brainfuck.wl](Brainfuck.wl) | esoteric lexing, arbitrarily nested loops, comments | `LeafNode` commands + `GroupNode["Loop", ..]` | `BrainfuckRun` -> compiles to a `machine -> machine` closure and runs it |

The shared vocabulary and algebra live in [AST.wl](AST.wl).

## The design: one grammar, two algebras

A grammar builder takes an `alg` (an `Association` of builder functions its
actions call) and returns a parser:

```wl
CalculatorGrammar[alg_] := Module[{...},
    number = ParseAction[tok @ ParseRegex["..."],
        Function[s, alg["Leaf"]["Integer", s]]];      (* actions call alg[...] *)
    bin[op_] := ParseAction[tok @ ParseLiteral[op],
        (Function[{l, r}, alg["Binary"][op, l, r]]) &];
    ...
]
```

Feed it `ASTAlgebra` (from `AST.wl`) and `alg["Binary"]["+", l, r]` builds
`BinaryNode["+", {l, r}, <||>]`; feed it `CalculatorSemantic` and the same call
computes `l + r`. The standard nodes (`LeafNode`, `CallNode`, `BinaryNode`,
`InfixNode`, `PrefixNode`, `PostfixNode`, `TernaryNode`, `GroupNode`,
`ContainerNode`) are the `CodeParser` shape - a 3-slot
`Head[descriptor, children, <|meta|>]` - but the operator descriptors stay
language-native strings (`"+"`, `":"`, `"'"`) instead of being forced into
Wolfram symbols. `ToCodeParser[tree, opmap]` projects onto `CodeParser`-exact
nodes (`"+" -> Plus`) for Wolfram-like grammars.

## Adding a language

1. `` BeginPackage["Wolfram`Parser`Languages`Foo`", {"Wolfram`Parser`", "Wolfram`Parser`"}] ``.
2. Write `fooGrammar[alg_] := Module[{...}, ...]` referencing `alg[...]` in
   every action. For recursion, allocate a cell with `RecCell[]`, reference it
   with `RecRef[cell]`, and give it its parser with `SetRec[cell, parser]`.
3. Define `fooAST` (maps your algebra keys onto the standard nodes) and
   `fooSemantic` (maps them onto meaningful values).
4. Expose `FooAST[s]` (wrap the result in `ASTContainer`) and a meaningful
   entry point. Add a `Tests/Foo.wlt`, list `"Foo"` in `init.wl`.

## What battle-testing surfaced

These are the library behaviours the zoo ran into - useful to know when
building any grammar, and candidate sharp edges to file down.

### `ParseAction` auto-splats a list-valued result

`ParseAction[p, f]` calls `f @@ value` when `p`'s value is a `List`, else
`f[value]`. That is convenient for `a ~~ b ~~ c` (you get `f[va, vb, vc]`),
but it silently *splats* a sub-result that is itself a meaningful list - e.g.
the list from a `ParseSepBy`/`ParseMany` you wanted to pass whole. Two clean
ways to keep a list intact:

- consume it as a positional element of an enclosing sequence, so it is one
  argument among several (`a ~~ items ~~ b` with `(g[#2]) &` - `items` is `#2`,
  untouched), or
- collect right at the `ParseMany` with `{##}`: `(alg["Seq"][{##}]) &`.

The zoo uses the positional form for delimited collections throughout.

### `ParseRecursive` targets must be stable symbols, not `Module`-locals

A `ParseRecursive[sym]` only holds `sym` (a symbol) - its parser lives in the
symbol's value. If `sym` is a `Module`-local, it can be garbage-collected once
the builder returns (the only live reference is held inside `ParseRecursive`),
and the recursion silently fails: a loop drops its opener, a nested value never
parses. The failure even depends on unrelated load order, which is a nasty way
to find a bug. The fix (and the reason for `RecCell`/`RecRef`/`SetRec` in
`AST.wl`) is to make the target a fresh global `Unique` symbol kept
un-evaluated inside a `HoldFirst` wrapper - the same `Unique[]`-per-rule wiring
the paclet's own EBNF front-end uses. The library could offer this directly so
hand-written recursive grammars don't have to.

### Keep a recursion target non-nullable-prefixed

Make the `ParseRecursive` target a `ParseChoice` of concrete alternatives, not
a production that starts with a nullable parser (`ParseMany`/`ParseRegex["..*"]`
then the real content). Re-entering at a nullable prefix was observed to match
empty and bail rather than recurse. Recursing through a `ParseChoice` (as Lisp,
JSON, Lambda and Brainfuck now all do) is reliable.

### Source positions (the finding that became a feature)

Actions receive parse *values*, not positions, so at first the standard AST
nodes carried empty `<||>` metadata - no `Source`, the one piece of `CodeParser`
parity the library could not reach. The battle-test paid off here: it motivated
a small core primitive, `ParsePosition`, a zero-width parser that yields the
current offset. With it the zoo captures spans without any change to the action
contract: `SpannedToken` brackets a leaf token (`ParsePosition[] ~~ token ~~
ParsePosition[]`) to record its offset span, and `ASTAddSource` spans the
composites from their children and converts every offset to a
`{{startLine, startColumn}, {endLine, endColumn}}` pair - exactly `CodeParser`'s
LineColumn convention. So `CalculatorAST["12 +\n  x"]` now reports the `+` node
as `{{1, 1}, {2, 4}}`, spanning across the newline. Two honest gaps remain:
group nodes span their *content* (the delimiters are not folded in), and a
synthesized leaf (a lambda binder's bound variable) has no `Source` because no
token in the source produced it - only parsed tokens carry spans.

### Minor

- `` Internal`StringToDouble `` returned unevaluated under a headless `wl` kernel;
  `ToExpression` on a regex-validated numeric token is the portable choice.
- The library ships **no** generic AST: an action-free parser yields nested
  plain lists of strings (sequence -> list, choice -> pass-through, terminal
  -> string). The standard node vocabulary here is imposed on top, which is
  exactly what made the dual-algebra design worth testing.

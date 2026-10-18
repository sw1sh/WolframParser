---
Template: Symbol
Name: ABCRun
Context: Wolfram`Parser`Languages`ABC`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/ABCRun
Keywords: [ABC, Arithmetic Branchless Calculator, esoteric language, interpreter, stack machine, EACP 2008, parser zoo]
SeeAlso: [ABCAST, ABCGrammar, ABCSemantic, ABCBNF, BrainfuckRun, Parse]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingABC, ParserZoo]
---

## Usage

<code>[ABCRun]()[*program*]</code> runs the ABC source string *program* on an empty stack and gives the list of numbers it prints.

<code>[ABCRun]()[*program*, *inputs*]</code> runs *program* with *inputs*, a list of non-negative integers or a string of them, on the stack, the first input on top.

## Details & Options

- ABC is the language of the Arithmetic Branchless Calculator, made at Ural State University for teaching and used in the contests EACP 2008 and K:-)M 2009. A program is lines of `print` *expression*, `stop`, and *name* `=` *expression*. Names are case insensitive, keywords are written in lower case, and spaces matter only after `print`. The program is read by [ABCGrammar](), which [EBNFParse]() generates from the grammar the specification publishes, [ABCBNF]().
- Numbers are non-negative integers: `-` stops at `0`, `/` and `%` are [Quotient]() and [Mod](). `*` `/` `%` bind tighter than `+` `-`, all left associative.
- A name that names no calculation is a parameter, read from the stack. In each calculation, and in each `print`, the first parameter to appear is the top of the stack, the next the element below, and so on. The stack is only read, never popped, by a `print`.
- A named calculation is evaluated when a `print` needs it, on the stack as it is, and numbers its own parameters. A name defined twice keeps its first definition. A calculation that needs itself, with no call in between, has no value.
- *name*`(`*a*, *b*, …`)` calls a calculation: the arguments go on the stack, *a* on top, while it runs. `*` evaluates its right operand first and does not evaluate its left operand when the right one is `0`, which is how a recursion stops. Every operator evaluates its right operand first.
- After the first `stop`, nothing prints.
- A run that fails gives a [Failure](), whose `"Output"` holds what printed before and whose `"Line"` is the statement that failed: `"ABCStack"` for a parameter below the bottom of the stack, `"ABCDivision"`, `"ABCCycle"`, `"ABCName"` for a call to no calculation, `"ABCDepth"`, `"ABCOverflow"` and `"ABCMode"`. A program that does not parse gives the [Failure]() of [Parse]() and the message ABCRun::syntax.
- To see the structure of *program* rather than run it, use [ABCAST](), which runs the same grammar, [ABCGrammar](), over a neutral node-building algebra.
- The following options can be given:

| Option | Default | Description |
|---|---|---|
| `"Mode"` | `3` | the machine's mode: `1` allows `print` and `stop`, `2` named calculations, `3` calls |
| `"Calls"` | `"Push"` | how a call places its arguments: `"Push"`, the rule of EACP 2008, or `"Advance"`, the rule of K:-)M 2009 |
| `"MaxNumber"` | [Infinity]() | the largest number a result may be |
| `"MaxDepth"` | `2000` | how deep calls may nest |

- With `"Calls" -> "Push"`, a call pushes its arguments, the last first, and pops them after. With `"Calls" -> "Advance"`, a call moves the top of the stack up by the smaller of the callee's parameter count and the argument count, writes the arguments from the top down, over what was there, and after the call pops as many elements as it had arguments; popping an empty stack is not an error. A call with no more arguments than parameters works as with `"Push"`; one with more drops the extra elements from the stack, so a function can walk down the stack, reading arbitrarily deep.

## Basic Examples

The largest of two inputs, from the classic examples: `a - b` is `0` when `a` is not larger, so adding `b` back gives the maximum:

```wl
ABCRun["max = a - b + b\nprint max", {3, 8}]
```

<!-- => {8} -->

The factorial: when `t` is `0`, the product does not evaluate the recursive call, and the term `1 - t` gives `1`:

```wl
ABCRun["fact = fact(t - 1) * t + (1 - t)\nprint fact", {10}]
```

<!-- => {3628800} -->

## Scope

The inputs can be a string of numbers, as a contest gave them:

```wl
ABCRun["print a - b + b", "3 8"]
```

<!-- => {8} -->

Each `print` numbers its own parameters, so both lines read `7` as their first parameter:

```wl
ABCRun["print b - a\nprint a - b", {7, 4}]
```

<!-- => {3, 3} -->

Named calculations form one namespace and can be defined after the line that uses them:

```wl
ABCRun["print d + b\na = 1 - 1\nd = a + b", {2}]
```

<!-- => {4} -->

Nothing prints after `stop`:

```wl
ABCRun["print 10 - 2\nstop\nprint 2 - 10"]
```

<!-- => {8} -->

A call's arguments are on top of the stack while it runs; the same calculation without a call reads the stack as it is:

```wl
ABCRun["a = b + c\nprint a(1, 2) - a", {1, 1}]
```

<!-- => {1} -->

`"Mode"` limits what a program may use; a named calculation needs mode `2`:

```wl
ABCRun["a = 1\nprint a", "Mode" -> 1]
```

### Options

With `"Calls" -> "Advance"`, a function walks down the stack. This one, from K:-)M 2009, sums as many elements as the top of the stack says:

```wl
stackSum = "n = 0\nm = 1 - (1 - x)\ns = (s(n(1,1) + x - 1) + y) * m\nprint s"
```

<!-- => "n = 0\nm = 1 - (1 - x)\ns = (s(n(1,1) + x - 1) + y) * m\nprint s" -->

```wl
ABCRun[stackSum, {3, 10, 20, 30}, "Calls" -> "Advance"]
```

<!-- => {60} -->

With the default `"Push"` calls, `n(1,1)` drops nothing, and each recursive call reads its caller's `x` as its `y`:

```wl
ABCRun[stackSum, {3, 10, 20, 30}]
```

<!-- => {15} -->

`"MaxNumber"` makes a larger result an overflow:

```wl
ABCRun["print 70000 * 70000", "MaxNumber" -> 2^32 - 1]
```

## Properties & Relations

The same source through [ABCAST]() describes the program instead of running it:

```wl
ABCAST["print a - b + b"]
```

<!-- => ContainerNode["String", {CallNode[LeafNode["Keyword", "print", <|"Source" -> {{1, 1}, {1, 6}}|>], {BinaryNode["+", {BinaryNode["-", {LeafNode["Symbol", "a", <|"Source" -> {{1, 7}, {1, 8}}|>], LeafNode["Symbol", "b", <|"Source" -> {{1, 11}, {1, 12}}|>]}, <|"Source" -> {{1, 7}, {1, 12}}|>], LeafNode["Symbol", "b", <|"Source" -> {{1, 15}, {1, 16}}|>]}, <|"Source" -> {{1, 7}, {1, 16}}|>]}, <|"Source" -> {{1, 1}, {1, 16}}|>]}, <|"Source" -> {{1, 1}, {1, 16}}|>] -->

[ABCGrammar]() over [ABCSemantic]() gives the program as the plain data `ABCRun` executes:

```wl
Parse[ABCGrammar[ABCSemantic], "print a - b + b"]
```

<!-- => {{"print", {"+", {"-", "a", "b"}, "b"}}} -->

## Possible Issues

A parameter that reads below the bottom of the stack stops the run; the [Failure]() keeps what printed before it:

```wl
ABCRun["print a\nprint a + b", {7}]
```

The first line printed before the second failed:

```wl
ABCRun["print a\nprint a + b", {7}]["Output"]
```

<!-- => {7} -->

Calculations that need each other, with no call in between, have no value:

```wl
ABCRun["a = b + 1\nb = a + 1\nprint a"]
```

A recursion without an exit stops at `"MaxDepth"`:

```wl
ABCRun["f = f(1)\nprint f", "MaxDepth" -> 100]
```

## Neat Examples

The fast Fibonacci of the classic examples carries the last two numbers as arguments, so the 30th takes thirty calls:

```wl
ABCRun["y = a - a + x + x(b)\nx = a - b\neq = 1 - y\nlt = 1 - x(a+1, b)\nfib_fast = f1 - f1 + f0 * eq(0,n) + f1 * eq(1,n) + fib_fast(f0 + f1, f1, n-1) * lt(1,n)\nfib = fib_fast(1, 0)\nprint fib", {30}]
```

<!-- => {832040} -->

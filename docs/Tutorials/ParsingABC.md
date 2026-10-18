---
Template: TechNote
Name: ParsingABC
Title: Parsing and Running ABC, the Language of the Ural Contests
Context: Wolfram`Parser`Languages`ABC`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/ParsingABC
Keywords: [ABC, Arithmetic Branchless Calculator, EACP 2008, K:-)M 2009, Club of Merry Machinists, Ural State University, esoteric language, stack machine, contest problems, BNF, EBNFParse]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserZoo, ParsingBNFGrammars, BuildingLanguageFrontEnds]
---

## What this note covers

ABC is an esoteric language made at Ural State University for teaching: problems that must be solved in unusual ways widen a student's view, and in ABC every problem is one. It is functional, with no side effects, and runs on a stack machine, the *Arithmetic Branchless Calculator*. Its specification, version 1.06 of 24 April 2008, and the problems of the two contests that used it were published on a page by E. M. Krokhalev, [cs.usu.edu.ru/langs/abc](https://web.archive.org/web/20240820091751/http://cs.usu.edu.ru/langs/abc/).

EACP 2008, a system-programming competition, planned a *Coding* battle on the machine. It was played at the start of RuCTF 2008, on build 778 of the machine, written by Baklanovsky, and the players were also to find bugs in it: the organizers had planted two, and the players found two more. K:-)M 2009, the *Club of Merry Machinists*, used the machine again, with a new rule for calls.

This note parses and runs every program the page published: the examples of the specification, the classic examples, and the solutions contestants published, each on its problem's samples. The problems no one published a solution for are given with their samples, and five problems of 2009 get solutions written for this note.

[ABCRun]() parses a program with [ABCGrammar]() over [ABCSemantic]() and runs it on the ABC machine, with the inputs on its stack, the first on top; it gives the list of numbers the program prints. [ABCAST]() gives the program's standard syntax tree instead. [ABCGrammar]() is not written by hand: [EBNFParse]() generates it from the grammar the specification publishes.

## The grammar

The specification gives the language's syntax as a BNF grammar, and [ABCBNF]() is that grammar as published:

```wl
ABCBNF
```

[EBNFParse]() reads it in its classic dialect, with `::` arrows, quoted terminals, `[...]` for an optional part and `"a" | ... | "z"` for a range of characters, and lowers every rule to a parser:

```wl
abcRules = EBNFParse[ABCBNF, "Dialect" -> "Classic"];
```

`<Digit>` reads one digit:

```wl
Parse[abcRules["Digit"], "7"]
```

<!-- => "7" -->

The prose around the grammar says what it leaves out, and [ABCGrammar]() supplies it. Spaces and tabs are ignored between elements, except the space `<SP>` that `print` requires, and names and numbers are tokens, matched without skipping. `<Calc> <OP> <Calc>` sets no precedence, so a calculation's operands and operators are combined `*` `/` `%` before `+` `-`, each left to right. And read as a PEG, `<Program>` would end after its first line, its optional `<NL>` taking every newline; [ABCGrammar]() reads it with its last two elements swapped, which describes the same programs. The result, over [ABCSemantic](), is the plain data [ABCRun]() executes:

```wl
Parse[ABCGrammar[ABCSemantic], "max = a - b + b\nprint max"]
```

<!-- => {{"define", "max", {"+", {"-", "a", "b"}, "b"}}, {"print", "max"}} -->

## The language

A program is lines, each one of three statements:

- `print` *expression* computes the expression and prints its value. It needs a space after `print`; anywhere else spaces and tabs are ignored.
- `stop` ends the program: nothing after it prints.
- *name* `=` *expression* names a calculation, from mode 2.

An expression is numbers, names, the operators `+` `-` `*` `/` `%`, parentheses, and, from mode 3, calls *name*`(`*arguments*`)`. `*` `/` `%` bind tighter than `+` `-`. Names are case insensitive; the keywords are written in lower case, as the grammar writes them. The machine runs in mode 1, 2 or 3, each adding to the one before, and each problem of EACP 2008 said which mode it is solved in.

Numbers are non-negative integers, and the arithmetic stays there: a subtraction that would go below `0` gives `0`, and `/` and `%` are the integer quotient and remainder:

```wl
ABCRun["print 1 + 2\nprint 2 - 1\nprint 1 - 2\nprint 3 * 4\nprint 15 / 6\nprint 15 % 6"]
```

<!-- => {3, 1, 0, 12, 2, 3} -->

Nothing prints after the first `stop`:

```wl
ABCRun["print 10 - 2\nstop\nprint 2 - 10"]
```

<!-- => {8} -->

### Parameters

A name that names no calculation is a *parameter*. Its value is on the machine's stack: the first parameter to appear in a calculation is the top of the stack, the second the element below it, and so on. Here `b` appears first, so it is the top, `4`, and `a` the `7` below; `4 - 7` stops at `0`:

```wl
ABCRun["print b - a + 10", {4, 7}]
```

<!-- => {10} -->

With the stack the other way round, `7 - 4 + 10`:

```wl
ABCRun["print b - a + 10", {7, 4}]
```

<!-- => {13} -->

Every calculation numbers its own parameters, so both of these lines read `7` as their first parameter:

```wl
ABCRun["print b - a\nprint a - b", {7, 4}]
```

<!-- => {3, 3} -->

### Named calculations

From mode 2 a calculation can be named. Names form one namespace, so a calculation may be defined after the line that uses it, and it is computed only when a `print` needs it, on the stack as it is, numbering its own parameters. Here `a` and `d` are calculations and `b` a parameter, in `d` as in the `print`:

```wl
ABCRun["print d + b\na = 1 - 1\nd = a + b", {2}]
```

<!-- => {4} -->

A calculation that needs itself has no value:

```wl
ABCRun["a = b + 1\nb = a + 1\nprint a"]
```

### Calls

From mode 3 a calculation can be called. Its arguments go on the stack, the first on top, while it runs, and come off after. `a(1, 2)` adds `1` and `2`; the `a` after it adds the two `1`s on the stack:

```wl
ABCRun["a = b + c\nprint a(1, 2) - a", {1, 1}]
```

<!-- => {1} -->

Recursion needs a way out, and `*` gives it. Every operator evaluates its right operand first, and when the right operand of `*` is `0`, it does not evaluate its left operand at all. The factorial of the specification calls itself until `t` is `0`, where the product is skipped and `1 - t` gives `1`:

```wl
ABCRun["f = f(t-1) * t + (1 - t)\nprint f(10)"]
```

<!-- => {3628800} -->

## The classic examples

The page published solutions of four classic problems, two of them for the Fibonacci numbers. The number after a problem's name is the number of inputs it takes.

### max/2

The larger of two numbers. `a - b` is `0` unless `a` is larger, so adding `b` back gives the larger of the two:

```wl
maxProgram = StringRiffle[{
    "max = a - b + b",
    "print max"
}, "\n"]
```

<!-- => "max = a - b + b\nprint max" -->

The larger of `3` and `8`:

```wl
ABCRun[maxProgram, {3, 8}]
```

<!-- => {8} -->

The same with the inputs the other way round:

```wl
ABCRun[maxProgram, {8, 3}]
```

<!-- => {8} -->

### fact/1

The factorial, a calculation that calls itself on the input:

```wl
factProgram = StringRiffle[{
    "fact = fact(t - 1) * t + (1 - t)",
    "print fact"
}, "\n"]
```

<!-- => "fact = fact(t - 1) * t + (1 - t)\nprint fact" -->

The factorials of `0` to `6`, each run printing one number:

```wl
Table[ABCRun[factProgram, {n}], {n, 0, 6}]
```

<!-- => {{1}, {1}, {2}, {6}, {24}, {120}, {720}} -->

### fib/1

The Fibonacci numbers, with `fib(0) = 0` and `fib(1) = 1`. `x` is `a - b`, so `leq = 1 - x` is `1` when `a <= b`; `y`, the sum of `x` both ways round, is `0` only when `a = b`, which makes `eq` a test of equality. `fib` adds its two predecessors while `n` is at least `2`, and gives `1` for `n = 1` and `0` for `n = 0`:

```wl
fibProgram = StringRiffle[{
    "y   = a - a + x + x(b)",
    "x   = a - b",
    "eq  = 1 - y",
    "leq = 1 - x",
    "fib = fib(n-1) * leq(1) + fib(n-2) * leq(2) + eq(1)",
    "print fib"
}, "\n"]
```

<!-- => "y   = a - a + x + x(b)\nx   = a - b\neq  = 1 - y\nleq = 1 - x\nfib = fib(n-1) * leq(1) + fib(n-2) * leq(2) + eq(1)\nprint fib" -->

The first ten Fibonacci numbers:

```wl
Table[ABCRun[fibProgram, {n}], {n, 0, 9}]
```

<!-- => {{0}, {1}, {1}, {2}, {3}, {5}, {8}, {13}, {21}, {34}} -->

That version calls itself twice at every step. The faster one carries the last two numbers as arguments; `f1 - f1` at its start only fixes the order of its parameters, `f1` first:

```wl
fibFastProgram = StringRiffle[{
    "y   = a - a + x + x(b)",
    "x   = a - b",
    "eq  = 1 - y",
    "lt  = 1 - x(a+1, b)",
    "fib_fast = f1 - f1 + f0 * eq(0,n) + f1 * eq(1,n) + fib_fast(f0 + f1, f1, n-1) * lt(1,n)",
    "fib = fib_fast(1, 0)",
    "print fib"
}, "\n"]
```

It reaches the 30th in thirty calls:

```wl
ABCRun[fibFastProgram, {30}]
```

<!-- => {832040} -->

### gcd/2

The greatest common divisor, by Euclid's algorithm; `nul(a)` adds nothing, but makes `a` the first parameter:

```wl
gcdProgram = StringRiffle[{
    "nul = 0",
    "eq  = 1 - ((a-b) + (b-a))",
    "gcd = nul(a) + b*eq(0) + gcd(b%a)*(1-eq(0))",
    "print gcd"
}, "\n"]
```

<!-- => "nul = 0\neq  = 1 - ((a-b) + (b-a))\ngcd = nul(a) + b*eq(0) + gcd(b%a)*(1-eq(0))\nprint gcd" -->

The greatest common divisor of `12` and `18`:

```wl
ABCRun[gcdProgram, {12, 18}]
```

<!-- => {6} -->

## EACP 2008

The problems of EACP 2008 gave the inputs on the stack, the first on top, and took the numbers printed, one per `print`. Each problem below has its samples and the solutions published with it, run on those samples; the authors are named as on the page.

### isdiv/2

Given two numbers, print `1` if one divides the other and `0` otherwise, in mode 2. The sample `5 10` gives `1`. Two solutions were published:

```wl
isdiv = {
    "4hz (D. Kosolobov, M. Rubinchik)" -> "print ((a/b)*b+1-a)+(a-a+((b/a)*a+1-b) ) - (1-((a-b)+(b-a)) )",
    "SiBears" -> StringRiffle[{
        "print (1-(1-((1-a%b) + (1-b%a))))*(1-(1-a))*(1-(1-b)) + (1-a) + (1-b) - 2*(1-a-b)",
        "stop"
    }, "\n"]
};
```

Both give `1` on the sample:

```wl
#1 -> ABCRun[#2, "5 10"] & @@@ isdiv
```

<!-- => {"4hz (D. Kosolobov, M. Rubinchik)" -> {1}, "SiBears" -> {1}} -->

### 210/1

Print the number whose decimal digits are the binary digits of the input, at most `1023`, in mode 1: `5` gives `101`. Fourteen solutions were published. Each is one `print` of the ten binary digits, each the input divided by a power of two, modulo `2`, scaled by a power of ten; two of them build the number in Horner's form:

```wl
binary = {
    "D. Simonov" -> "print a%2+((a/2)%2)*10+((a/4)%2)*100+((a/8)%2)*1000+((a/16)%2)*10000+((a/32)%2)*100000+((a/64)%2)*1000000+((a/128)%2)*10000000+((a/256)%2)*100000000+((a/512)%2)*1000000000",
    "A. Chekanov" -> "print (((((((((a/512 - a/1024*2)*10 + (a/256 - a/512*2))*10 + (a/128 - a/256*2))*10 + (a/64 - a/128*2))*10 + (a/32 - a/64*2))*10 + (a/16 - a/32*2))*10 + (a/8 - a/16*2))*10 + (a/4 - a/8*2))*10 + (a/2 - a/4*2))*10 + a%2",
    "S. Ionov" -> "print ((((((((((a / 512) % 2) * 10 + ((a / 256) % 2)) * 10 + ((a / 128) % 2)) * 10 + ((a / 64) % 2)) * 10 + ((a / 32) % 2)) * 10 + ((a / 16) % 2)) * 10 + ((a / 8) % 2)) * 10 + ((a / 4) % 2)) * 10 + ((a / 2) % 2)) * 10 + (a % 2)",
    "keva" -> "print ((a/512)%2)*1000000000+((a/256)%2)*100000000+((a/128)%2)*10000000+((a/64)%2)*1000000+((a/32)%2)*100000+((a/16)%2)*10000+((a/8)%2)*1000+((a/4)%2)*100+((a/2)%2)*10+(a%2)*1",
    "A. Khanov, E. Shmakov" -> "print 1000000000*((a/512)%2)+100000000*((a/256)%2)+10000000*((a/128)%2)+1000000*((a/64)%2)+100000*((a/32)%2)+10000*((a/16)%2)+1000*((a/8)%2)+100*((a/4)%2)+10*((a/2)%2)+a%2",
    "N. Glazyrin" -> "print a%2+((a/2)%2)*10+((a/4)%2)*100+((a/8)%2)*1000+((a/16)%2)*10000+((a/32)%2)*100000+((a/64)%2)*1000000+((a/128)%2)*10000000+((a/256)%2)*100000000+((a/512)%2)*1000000000",
    "4hz (D. Kosolobov, M. Rubinchik)" -> "print a%2+(a%4/2*10)+(a%8/4*100)+(a%16/8*1000)+(a%32/16*10000)+(a%64/32*100000)+(a%128/64*1000000)+(a%256/128*10000000)+(a%512/256*100000000)+(a%1024/512*1000000000)",
    "V. Sbitnev" -> "print a%2 + a/2%2*10 + a/4%2*100 + a/8%2*1000 + a/16%2*10000 + a/32%2*100000 + a/64%2*1000000 + a/128%2*10000000 + a/256%2*100000000 + a/512%2*1000000000",
    "M. Snarsky" -> "print x/1%2*1+x/2%2*10+x/4%2*100+x/8%2*1000+x/16%2*10000+x/32%2*100000+x/64%2*1000000+x/128%2*10000000+x/256%2*100000000+x/512%2*1000000000",
    "I. Mikhailov, E. Pavlyuk, M. Panachev, A. Khozov" -> "print (((b/512)%2)*1000000000+((b/256)%2)*100000000+((b/128)%2)*10000000+((b/64)%2)*1000000+((b/32)%2)*100000+((b/16)%2)*10000+((b/8)%2)*1000+((b/4)%2)*100+((b/2)%2)*10+(b%2))",
    "K. Plotnikov" -> "print (a%2) + (a/2%2)*10 + (a/4%2)*100 + (a/8%2)*1000 + (a/16%2)*10000 + (a/32%2)*100000 + (a/64%2) * 1000000 + (a/128%2) * 10000000 + (a/256%2)*100000000 + (a/512%2) * 1000000000",
    "SiBears" -> StringRiffle[{
        "print (1 - (1 - a % 1024/512)) * 1000000000 + (1 - (1 - a % 512/256)) * 100000000 + (1 - (1 - a % 256/128)) * 10000000 + (1 - (1 - a % 128/64)) * 1000000 + (1 - (1 - a % 64/32)) * 100000 + (1 - (1 - a % 32/16)) * 10000 + (1 - (1 - a % 16/8)) * 1000 + (1 - (1 - a % 8/4)) * 100 + (1 - (1 - a % 4/2)) * 10 + (1 - (1 - a % 2))",
        "stop"
    }, "\n"],
    "A. Mushnikov" -> "print a%2+a/2%2*10+a/4%2*100+a/8%2*1000+a/16%2*10000+a/32%2*100000+a/64%2*1000000+a/128%2*10000000+a/256%2*100000000+a/512%2*1000000000",
    "expl0it" -> "print a % 2 + 10*(a%4/2) + 100*(a%8/4) + 1000*(a%16/8) + 10000*(a%32/16) + 100000*(a%64/32) + 1000000*(a%128/64) + 10000000*(a%256/128) + 100000000*(a%512/256) + 1000000000*(a%1024/512)"
};
```

Every one of them gives `101` on the sample:

```wl
#1 -> ABCRun[#2, "5"] & @@@ binary
```

All fourteen agree with [IntegerDigits]() on every input up to `1023`; on every 50th of them:

```wl
And @@ Flatten @ Table[ABCRun[code, {n}] === {FromDigits[IntegerDigits[n, 2]]}, {code, Values[binary]}, {n, 0, 1023, 50}]
```

<!-- => True -->

### pi/1

Print the number of primes up to the input `N`, at most `10000000`, in mode 3: `5` gives `3`. Four solutions were published, each a recursion over the candidates with a recursion over their divisors inside:

```wl
primeCount = {
    "S. Ionov" -> StringRiffle[{
        "less = k - i",
        "great_eq = 1 - less(k, i)",
        "self_div = (1 - (i % l)) * great_eq(l, i / 2)",
        "self_div2 = (1 - (1 - (i % l))) * great_eq(l, i / 2)",
        "cprost = cprost(l + 1, i) * self_div2(i, l) * (1 - self_div(i, l)) + self_div(i, l)",
        "is_prost = 1 - cprost(2, i)",
        "n = (is_prost(i) + n(i + 1, k)) * great_eq(i, k)",
        "print n(2, k)"
    }, "\n"],
    "A. Khanov, E. Shmakov" -> StringRiffle[{
        "nul = 0",
        "y   = a - a + x + x(b)",
        "x   = a - b",
        "leq = 1 - x",
        "isp = nul(a,p)+isp(a,p+1)*(1-(1-(a%p)))*leq(p,a/2)+1*(1-(a%p))",
        "isp2=2-isp",
        "allp = allp(a,p+1)*leq(p+1,a)+ isp2(p,2)",
        "print allp(a,2)"
    }, "\n"],
    "I. Mikhailov, E. Pavlyuk, M. Panachev, A. Khozov" -> StringRiffle[{
        "R=c-(c-1)",
        "S=S(n,k+2)*R(n-(k+2))+(1-n%k)",
        "D=1-n%2",
        "Si=1-(D+S(n,3))*R(n-3)",
        "Pi=Pi(n-1)*R(n-2)+Si*R(n-2)",
        "print Pi+R(n-1)"
    }, "\n"],
    "N. Murzin" -> StringRiffle[{
        "is=is(a,b+1)*((1-(b-a/2))-(1-a%b))+(b-a/2)",
        "simp=(simp(a,b+1)+is(b,2))*(1-(b-a))",
        "print simp(a,2)"
    }, "\n"]
};
```

On the sample, three of them print `3`. The solution of A. Khanov and E. Shmakov prints `6`: its `isp` is `1` for `2` and for a composite number and `0` for an odd prime, so `isp2 = 2 - isp` is `2` for an odd prime and `1` for every other number, and `allp` adds them from `2` to `N`, `1 + 2 + 1 + 2`:

```wl
#1 -> ABCRun[#2, "5"] & @@@ primeCount
```

<!-- => {"S. Ionov" -> {3}, "A. Khanov, E. Shmakov" -> {6}, "I. Mikhailov, E. Pavlyuk, M. Panachev, A. Khozov" -> {3}, "N. Murzin" -> {3}} -->

On `30` the three agree with [PrimePi](), ten primes; the fourth adds `1` for each of the 29 numbers from `2` to `30` and `1` more for each of the 9 odd primes:

```wl
#1 -> ABCRun[#2, {30}] & @@@ primeCount
```

<!-- => {"S. Ionov" -> {10}, "A. Khanov, E. Shmakov" -> {38}, "I. Mikhailov, E. Pavlyuk, M. Panachev, A. Khozov" -> {10}, "N. Murzin" -> {10}} -->

### conn/...

A graph is given by its number of vertices and then each vertex's adjacency list, each list ending in `0`; print `1` if the graph is connected and `0` otherwise, with at most 1000 vertices, in mode 3. The sample `5 2 4 0 1 3 0 2 4 0 1 3 0 0` gives `0`. No solution was published: in mode 3 a calculation reads only as deep into the stack as its own parameters go, so no program can walk a list as long as its input. K:-)M 2009 changed the calls to make that possible.

### palin/...

The inputs are the character codes of a text ending in `0`; print the length of its longest palindromic substring, for at most 1000 characters, in mode 3. The sample `12 3 3 5 4 4 5 3 17 5 17 98 0` gives `6`. No solution was published, for the reason of `conn`.

### area/...

A convex polygon is given by its number of vertices `N` and then the coordinates of the `N` vertices, counterclockwise; print twice its area, with `N` at most 1000, in mode 3. The sample `3 0 0 10 11 5 7` gives `15`. No solution was published, for the reason of `conn`; K:-)M 2009 below has one that walks the stack.

### kmin/...

Given `N`, `K` and then `N` numbers, print the `K`-th smallest of the numbers, in mode 3. The sample `12 7 4 0 1 3 0 2 4 0 1 3 0 0` gives `1`. No solution was published, for the reason of `conn`.

### square/6

Given three points, `x0 y0 x1 y1 x2 y2`, print `1 X Y` if they are three corners of a square whose fourth corner is `(X, Y)`, and `0 0 0` otherwise, in mode 1. The samples `0 0 1 1 0 1` and `0 0 2 2 0 1` give `1 1 0` and `0 0 0`. One solution was published, by N. Glazyrin, in three `print` lines: the first tests each point in turn for the corner between the other two, and the other two compute the fourth corner's coordinates. `0*(x1+y1+x2+y2+x3+y3)` at the start of each only fixes the order of its parameters:

```wl
squareProgram = StringRiffle[{
    "print 0*(x1+y1+x2+y2+x3+y3)+(1-((((x2+x3-x1-x1) + (x1+x1-x2-x3))-((y2-y3) + (y3-y2)))+(((y2-y3) + (y3-y2))-((x2+x3-x1-x1) + (x1+x1-x2-x3)))+(((y2+y3-y1-y1) + (y1+y1-y2-y3))-((x2-x3) + (x3-x2)))+(((x2-x3) + (x3-x2))-((y2+y3-y1-y1) + (y1+y1-y2-y3)))))+(1-((((x3+x1-x2-x2) + (x2+x2-x3-x1))-((y3-y1) + (y1-y3)))+(((y3-y1) + (y1-y3))-((x3+x1-x2-x2) + (x2+x2-x3-x1)))+(((y3+y1-y2-y2) + (y2+y2-y3-y1))-((x3-x1) + (x1-x3)))+(((x3-x1) + (x1-x3))-((y3+y1-y2-y2) + (y2+y2-y3-y1)))))+(1-((((x1+x2-x3-x3) + (x3+x3-x1-x2))-((y1-y2) + (y2-y1)))+(((y1-y2) + (y2-y1))-((x1+x2-x3-x3) + (x3+x3-x1-x2)))+(((y1+y2-y3-y3) + (y3+y3-y1-y2))-((x1-x2) + (x2-x1)))+(((x1-x2) + (x2-x1))-((y1+y2-y3-y3) + (y3+y3-y1-y2)))))",
    "print 0*(x1+y1+x2+y2+x3+y3)+(x2+x3-x1-0)*(1-((((x2+x3-x1-x1) + (x1+x1-x2-x3))-((y2-y3) + (y3-y2)))+(((y2-y3) + (y3-y2))-((x2+x3-x1-x1) + (x1+x1-x2-x3)))+(((y2+y3-y1-y1) + (y1+y1-y2-y3))-((x2-x3) + (x3-x2)))+(((x2-x3) + (x3-x2))-((y2+y3-y1-y1) + (y1+y1-y2-y3))))+1)-(x2+x3-x1)+(x3+x1-x2-0)*(1-((((x3+x1-x2-x2) + (x2+x2-x3-x1))-((y3-y1) + (y1-y3)))+(((y3-y1) + (y1-y3))-((x3+x1-x2-x2) + (x2+x2-x3-x1)))+(((y3+y1-y2-y2) + (y2+y2-y3-y1))-((x3-x1) + (x1-x3)))+(((x3-x1) + (x1-x3))-((y3+y1-y2-y2) + (y2+y2-y3-y1))))+1)-(x3+x1-x2)+(x1+x2-x3-0)*(1-((((x1+x2-x3-x3) + (x3+x3-x1-x2))-((y1-y2) + (y2-y1)))+(((y1-y2) + (y2-y1))-((x1+x2-x3-x3) + (x3+x3-x1-x2)))+(((y1+y2-y3-y3) + (y3+y3-y1-y2))-((x1-x2) + (x2-x1)))+(((x1-x2) + (x2-x1))-((y1+y2-y3-y3) + (y3+y3-y1-y2))))+1)-(x1+x2-x3)",
    "print 0*(x1+y1+x2+y2+x3+y3)+(y2+y3-y1-0)*(1-((((x2+x3-x1-x1) + (x1+x1-x2-x3))-((y2-y3) + (y3-y2)))+(((y2-y3) + (y3-y2))-((x2+x3-x1-x1) + (x1+x1-x2-x3)))+(((y2+y3-y1-y1) + (y1+y1-y2-y3))-((x2-x3) + (x3-x2)))+(((x2-x3) + (x3-x2))-((y2+y3-y1-y1) + (y1+y1-y2-y3))))+1)-(y2+y3-y1)+(y3+y1-y2-0)*(1-((((x3+x1-x2-x2) + (x2+x2-x3-x1))-((y3-y1) + (y1-y3)))+(((y3-y1) + (y1-y3))-((x3+x1-x2-x2) + (x2+x2-x3-x1)))+(((y3+y1-y2-y2) + (y2+y2-y3-y1))-((x3-x1) + (x1-x3)))+(((x3-x1) + (x1-x3))-((y3+y1-y2-y2) + (y2+y2-y3-y1))))+1)-(y3+y1-y2)+(y1+y2-y3-0)*(1-((((x1+x2-x3-x3) + (x3+x3-x1-x2))-((y1-y2) + (y2-y1)))+(((y1-y2) + (y2-y1))-((x1+x2-x3-x3) + (x3+x3-x1-x2)))+(((y1+y2-y3-y3) + (y3+y3-y1-y2))-((x1-x2) + (x2-x1)))+(((x1-x2) + (x2-x1))-((y1+y2-y3-y3) + (y3+y3-y1-y2))))+1)-(y1+y2-y3)"
}, "\n"]
```

The first sample, a square with its fourth corner at `(1, 0)`:

```wl
ABCRun[squareProgram, "0 0 1 1 0 1"]
```

<!-- => {1, 1, 0} -->

The second sample, three points of no square:

```wl
ABCRun[squareProgram, "0 0 2 2 0 1"]
```

<!-- => {0, 0, 0} -->

### clock/2

Given the time as hours and minutes, print the number of seconds until the clock's hands next coincide, in mode 2: `17 18` gives `556`. Three solutions were published:

```wl
clock = {
    "A. Khanov, E. Shmakov" -> StringRiffle[{
        "check=(3600*(a%12)+60*b)*11",
        "x=z* (a%12) -check",
        "y=z*((a%12)+1)-check",
        "t=x*(1-(1-(y-x-(z-1))))+y*(1-(y-x-(z-1)))"
    }, "\n"],
    "N. Glazyrin" -> "print (((h%12)*3600+43200-m*660)%43200)/11",
    "SiBears" -> StringRiffle[{
        "x=1+300*(h%12)+5*m-60*m",
        "t=z-z+60*(60-m)",
        "b=(t+3600*((h%12)+1)/11)",
        "a=(60*(60*(h%12)-11*m)/11)",
        "y=a*(1-(1-x))+b*(1-x)",
        "print y"
    }, "\n"]
};
```

Two print `556`. The solution of A. Khanov and E. Shmakov, as published, has no `print` line, so it prints nothing:

```wl
#1 -> ABCRun[#2, "17 18"] & @@@ clock
```

<!-- => {"A. Khanov, E. Shmakov" -> {}, "N. Glazyrin" -> {556}, "SiBears" -> {556}} -->

### brackets/...

The inputs are the character codes of a text ending in `0`; print `1` if its brackets `()`, `<>`, `[]` and `{}` are balanced and `0` otherwise, in mode 3. The sample `40 48 43 48 41 45 49 0`, the text `(0+0)-1`, gives `1`. No solution was published, for the reason of `conn`.

## K:-)M 2009

The organizers of K:-)M 2009 listed four bugs found in the machine of EACP 2008: it did not tell the modes apart; `print stop` failed with an out-of-memory error; a `[` hid the rest of its line from the parser, as a comment; and lazy multiplication went wrong, so that `print 1 + 2 * 3 * 0` printed `3` instead of `1`. They found the first three amusing and kept them for the contest, and fixed the last. [ABCRun]() has none of them; `2 * 3 * 0` is `0`, and the sum is `1`:

```wl
ABCRun["print 1 + 2 * 3 * 0"]
```

<!-- => {1} -->

### Calls that walk the stack

EACP 2008 had also shown that no calculation could look arbitrarily deep into the stack. The organizers designed two new modes, 4 and 5, for that, but found new syntax dull, and for K:-)M 2009 changed how a call places its arguments instead. A calculation's *depth* is the number of its parameters. A call moves the top of the stack up by the smaller of the callee's depth and the number of arguments, and writes the arguments from the top down, so that arguments beyond the depth overwrite elements already on the stack. When the call returns, it pops as many elements as it had arguments, and popping an empty stack is not an error. A call with no more arguments than its callee has parameters works as before; one with more drops the extra elements from the stack, for good. [ABCRun]() takes the rule as `"Calls" -> "Advance"`; the rule of 2008 is the default, `"Calls" -> "Push"`.

Their example sums as many elements of the stack as its top says:

```wl
stackSum = StringRiffle[{
    "n = 0",
    "m = 1 - (1 - x)",
    "s = (s(n(1,1) + x - 1) + y) * m",
    "print s"
}, "\n"]
```

<!-- => "n = 0\nm = 1 - (1 - x)\ns = (s(n(1,1) + x - 1) + y) * m\nprint s" -->

`m` is `1` while `x` is positive, and `s` adds `y`, the element below `x`, to a call of itself on `x - 1`. In the argument of that call, `n(1,1)` is `0`, but it passes two arguments to a calculation with no parameters, so its return drops the top two elements, `x` and `y`, both read by then; `x - 1` then goes on top of what is left. The page traced the stack before each call of `s` as `(3, 1, 2, 3)`, `(2, 2, 3)`, `(1, 3)` and `(0)`, and the sum is `1 + 2 + 3`:

```wl
ABCRun[stackSum, {3, 1, 2, 3}, "Calls" -> "Advance"]
```

<!-- => {6} -->

That sample gives `6` with the calls of 2008 too; with other elements the two rules part. With the new calls, the sum of `10`, `20` and `30`:

```wl
ABCRun[stackSum, {3, 10, 20, 30}, "Calls" -> "Advance"]
```

<!-- => {60} -->

With the calls of 2008, `n(1,1)` pops what it pushed, and each recursive call reads its caller's `x` as its `y`, summing `10 + 3 + 2`:

```wl
ABCRun[stackSum, {3, 10, 20, 30}]
```

<!-- => {15} -->

### The problems

K:-)M 2009 set `conn`, `palin`, `area`, `kmin` and `brackets` again, with the samples of 2008, and five new problems. No solutions were published. The solutions below are written for this note: one for `area`, which needs the new calls, and four for new problems with a fixed number of inputs, whose calls never pass more arguments than parameters, so that they give the same results under either rule.

#### area/...

The polygon's vertices, after `N`, are walked down the stack one at a time. `g` carries five numbers as its arguments: the number of vertices left, `c`; the first vertex, `fx` and `fy`; and two sums, `p` and `q`. Its other parameters, `xi`, `yi`, `xj` and `yj`, are the current vertex and the next, on the stack below the arguments. Twice the area is the sum of `xi * yj - xj * yi` over the edges, and since no number is negative, `p` and `q` add up the two products apart. `z` is `0`; called with seven arguments and no parameters of its own, it drops `g`'s five arguments and the current vertex, so that the next call of `g` finds the next vertex under its arguments. On the last vertex `e(c, 1)` is `1`, and `g` closes the polygon on the first vertex instead. Operands evaluate right first, so the term that walks sits left of the terms that read; the term first in the text, multiplied by `0` and so never evaluated, only fixes the order of the parameters. The `print` drops `N` the same way, with `z(1)`:

```wl
areaProgram = StringRiffle[{
    "z = 0",
    "e = 1 - (u - v + (v - u))",
    "g = (c + fx + fy + p + q + xi + yi + xj + yj) * 0 + g(z(1, 1, 1, 1, 1, 1, 1) + c - 1, fx, fy, p + xi * yj, q + xj * yi) * (1 - e(c, 1)) + (p + xi * fy - (q + fx * yi)) * e(c, 1)",
    "print g(z(1) + n, a, b, 0, 0)"
}, "\n"]
```

It gives the sample with the new calls:

```wl
ABCRun[areaProgram, "3 0 0 10 11 5 7", "Calls" -> "Advance"]
```

<!-- => {15} -->

With the calls of 2008, `z` drops nothing, and the walk reads the wrong elements:

```wl
ABCRun[areaProgram, "3 0 0 10 11 5 7"]
```

<!-- => {30} -->

A polygon of a hundred vertices, on a circle:

```wl
polygon = Table[Round[100 + 90 {Cos[2 Pi k/100], Sin[2 Pi k/100]}], {k, 0, 99}];
```

The program agrees with twice the [Area]() of the [Polygon]():

```wl
ABCRun[areaProgram, Prepend[Flatten[polygon], Length[polygon]], "Calls" -> "Advance"] === {2 Area[Polygon[polygon]]}
```

<!-- => True -->

#### pi/1

Print the integer part of `n` times π, which the problem promises fits the machine's largest number: `30` gives `94`. Only the answer is promised to fit, so the intermediate results have to fit as well. With numbers of 32 bits, the largest `2^32 - 1`, the program splits `n` into its last four digits, `l`, and the rest, `h`, and multiplies both by the digits of π after the point, four at a time, carrying from the last group as in long multiplication; `k1` is the carry into the units. No intermediate result exceeds the answer or `1.5 * 10^9`:

```wl
piProgram = StringRiffle[{
    "h = n / 10000",
    "l = n % 10000",
    "k7 = l * 3832 / 10000",
    "k6 = (h * 3832 + l * 2643 + k7) / 10000",
    "k5 = (h * 2643 + l * 3846 + k6) / 10000",
    "k4 = (h * 3846 + l * 7932 + k5) / 10000",
    "k3 = (h * 7932 + l * 3589 + k4) / 10000",
    "k2 = (h * 3589 + l * 9265 + k3) / 10000",
    "k1 = (h * 9265 + l * 1415 + k2) / 10000",
    "print 3 * n + h * 1415 + k1"
}, "\n"]
```

It gives the sample:

```wl
ABCRun[piProgram, "30"]
```

<!-- => {94} -->

It agrees with [Floor]() of `n` times π on the first hundred `n`:

```wl
Table[ABCRun[piProgram, {n}], {n, 100}] === List /@ Floor[Range[100] Pi]
```

<!-- => True -->

`"MaxNumber"` makes [ABCRun]() a machine of 32 bits. The largest `n` whose answer fits gives `2^32 - 1` itself:

```wl
ABCRun[piProgram, {1367130551}, "MaxNumber" -> 2^32 - 1]
```

<!-- => {4294967295} -->

For the next `n` the answer no longer fits:

```wl
ABCRun[piProgram, {1367130552}, "MaxNumber" -> 2^32 - 1]
```

#### pal/...

The inputs are the character codes of a text ending in `0`; print `1` if the text is a palindrome and `0` otherwise, for at most 1000 characters. The sample `98 17 5 17 98 0` gives `1`. It is left open here.

#### rightΔ/6

Given the corners of a triangle, `x0 y0 x1 y1 x2 y2`, print `1` if it has a right angle and `0` otherwise: `0 0 0 4 3 4` gives `1`. With no negative numbers at hand, the program compares squared sides, by Pythagoras: `ab` is the distance between two numbers, `sq` the squared distance between two points, and `eq` a test of equality. `0 * (...)` at the start of the `print` fixes the order of the six parameters:

```wl
rightProgram = StringRiffle[{
    "ab = a - b + (b - a)",
    "sq = ab(x, u) * ab(x, u) + ab(y, v) * ab(y, v)",
    "eq = 1 - (p - q + (q - p))",
    "print 0 * (x0 + y0 + x1 + y1 + x2 + y2) + eq(sq(x0, x1, y0, y1) + sq(x1, x2, y1, y2), sq(x0, x2, y0, y2)) + eq(sq(x0, x1, y0, y1) + sq(x0, x2, y0, y2), sq(x1, x2, y1, y2)) + eq(sq(x1, x2, y1, y2) + sq(x0, x2, y0, y2), sq(x0, x1, y0, y1))"
}, "\n"]
```

It gives the sample:

```wl
ABCRun[rightProgram, "0 0 0 4 3 4"]
```

<!-- => {1} -->

A triangle with no right angle gives `0`:

```wl
ABCRun[rightProgram, "0 0 2 1 0 3"]
```

<!-- => {0} -->

#### weekday/3

Given a date as year, month and day, the year from 1917 to 2009, print its day of the week, `0` for Sunday to `6` for Saturday: `2009 04 21` gives `2`. The program is Zeller's congruence: `jf` is `1` for January and February, which count as months 13 and 14 of the year before; `mm` and `yy` are that month and year; and `h` gives `0` for Saturday, so the `print` shifts it. `y - y + m - m` at the start of the `print` fixes the order of its parameters, the year first:

```wl
weekdayProgram = StringRiffle[{
    "jf = 1 - (m - 2)",
    "mm = m + 12 * jf(m)",
    "yy = y - jf(m)",
    "h = (d + 13 * (mm(m) + 1) / 5 + yy(y, m) % 100 + yy(y, m) % 100 / 4 + yy(y, m) / 400 + 5 * (yy(y, m) / 100)) % 7",
    "print y - y + m - m + (h(d, m, y) + 6) % 7"
}, "\n"]
```

It gives the sample:

```wl
ABCRun[weekdayProgram, "2009 04 21"]
```

<!-- => {2} -->

It agrees with [DateValue]() on the first of January and of March of every year the problem allows:

```wl
And @@ Flatten @ Table[ABCRun[weekdayProgram, {y, m, 1}] === {Mod[DateValue[DateObject[{y, m, 1}], "ISOWeekDay"], 7]}, {y, 1917, 2009}, {m, {1, 3}}]
```

#### root/2

Given `N` and `K`, with `K > 0`, print the largest `L` with `L^K <= N`: `100 2` gives `10`. The program halves the range of candidates. `r` keeps `lo`, whose power fits, and `hi`, above which no power does, and tests the middle, `md`, with `q`. `q` builds the power one factor at a time and gives up as soon as the next factor would pass `N`; it compares `c` with `n / m` rather than `c * m` with `n`, so no product exceeds `N`. `le` and `gt` compare two numbers. The search starts from `1`, whose power fits any positive `N`, so the middle is at least `2`, and `q` multiplies at most 32 times on numbers of 32 bits:

```wl
rootProgram = StringRiffle[{
    "le = 1 - (a - b)",
    "gt = 1 - (1 - (a - b))",
    "md = lo + 1 + (hi - lo - 1) / 2",
    "q = q(e - 1, m, n, c * m) * le(c, n / m) * (1 - (1 - e)) + (1 - e)",
    "r = r(md(lo, hi), hi, k, n) * q(k, md(lo, hi), n, 1) * gt(hi, lo) + r(lo, md(lo, hi) - 1, k, n) * (1 - q(k, md(lo, hi), n, 1)) * gt(hi, lo) + lo * (1 - gt(hi, lo))",
    "print r(1 - (1 - n), n, k, n)"
}, "\n"]
```

It gives the sample:

```wl
ABCRun[rootProgram, "100 2"]
```

<!-- => {10} -->

The cube root of `27`:

```wl
ABCRun[rootProgram, "27 3"]
```

<!-- => {3} -->

For `26`, the largest whole cube root is `2`:

```wl
ABCRun[rootProgram, "26 3"]
```

<!-- => {2} -->

The square root of the largest number of 32 bits, on a machine of 32 bits:

```wl
ABCRun[rootProgram, {2^32 - 1, 2}, "MaxNumber" -> 2^32 - 1]
```

<!-- => {65535} -->

The remaining problems, `conn`, `palin`, `kmin`, `brackets` and `pal`, are left as exercises; the stack sum and the area above are the patterns their walks start from.

## The tree

[ABCAST]() runs the same grammar over a node-building algebra. A line is a [CallNode]() headed by its keyword, a named calculation a [BinaryNode]() `"="`:

```wl
ASTStripSource @ ABCAST[maxProgram]
```

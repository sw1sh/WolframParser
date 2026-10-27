# The reader's build program

The Wolfram Language reader of `Wolfram/Parser` reads a source in three passes. The typed lexer
`fastLex` gives its tokens. The typed parser `fastParse` gives a postfix program of the
statements. The build pass `fastBuild` runs that program on a stack and gives each statement as
a held expression. This note is the contract of the third pass: what a builder of its own, such as
a kernel's typed one, takes, and what it gives for each instruction. The reference implementation
is `fastBuild` and `fastStep` in
[`WolframLanguageFast.wl`](../Parser/Kernel/Languages/WolframLanguageFast.wl), with the held helpers
of [`WolframLanguage.wl`](../Parser/Kernel/Languages/WolframLanguage.wl). A builder is right where it
gives the same statements as `fastBuild` on the reader corpus.

## What a builder takes

For the statements of a program, `fastBuild[steps, kinds, texts, marks]` takes:

| Argument | What it is |
|---|---|
| `steps` | The instructions, three integers each, `{code, a, b}`, one after another, as `fastParse` gives them after its status and count. `WolframLanguageHeldNext` passes one statement's: instructions `row[[5]]` to `row[[6]]` of its segment's program, the last of them its code 25. `WolframLanguageProgram` gives a whole source's (see A whole source). |
| `kinds`, `texts`, `marks` | The leaves of those instructions, the instructions of code 1, in order, as `fastLeafData` gives them: each leaf's kind, its text in the source, and its mark, 1 for a number literal and 0 else. |

And these tables of the paclet, constant for a version of it:

| Table | What it is |
|---|---|
| `$fastHeadNames` | The heads, a list of strings, by head code: code `k` is the head named `$fastHeadNames[[k]]`. A head of a value is the `` System` `` symbol of that name, as `heldSymbol` gives it. Codes 1 to 7 are `"Minus"`, `"Unset"`, `"Paren"`, `"List"`, `"Association"`, `"NotNot"` and `"Optional"`. |
| special head codes | `fastHeadCode[name]` for `"Minus"`, `"Paren"`, `"At"`, `"SlashSlash"` and `"Divide"`, which instructions 2, 4 and 9 read apart. `"Paren"`, `"At"`, `"SlashSlash"` and `"Divide"` name no head of a value. |
| `$fastIntegralList` | The integrals by index, each `{head name, kind}`, the kind `Integrate` for the integral form of instruction 24. |

## A whole source

`WolframLanguageProgram[s]` gives the program of all of a plain source at once: one that reads
whole, with no line continuation and no syntax warning. Any other source is `None`, and
`WolframLanguageHeldNext` reads it. The program is `{codes, prog, parts}`, three packed arrays of
integers:

| Array | What it is |
|---|---|
| `codes` | The source's character codes. |
| `prog` | `fastParse`'s program of all the statements: `{0, n}` and then the `n` instructions, three integers each: instruction `k` is `prog[[3k ;; 3k + 2]]`. |
| `parts` | `fastWhole`'s, after the program in its array: `{0, m, r}`, then the `m` leaves' kinds, their marks, their starts and their ends, `m` integers each, then `r` rows of four, one for each part `WolframLanguageHeldNext` gives, in order. |

A leaf's text is `codes[[start ;; end - 1]]`, the characters of its token. A statement's row is
`{first instruction, last instruction, first leaf, last leaf}`, its last instruction its code 25,
its last leaf one less than its first where it has none, as `{}` has none. Blank lines, a return
and a newline, and lines holding only a comment part statements and have no row, where Wolfram 15's
`ToExpression` reads each as a `Null` [W15 bug]; a source with no statement has no rows.
`parts[[1]]`, the count of the Nulls a comma leaves, is 0 in a program. An empty `codes`, for the empty source, is
`{}`, which Wolfram 15 does not pack.

`fastProgram` makes the program in one typed call: the lexer, the parser, the lines and
`fastWhole`, each once, with nothing between them. It takes the codes with three zeros after
them, as `paddedCodes` gives them, and the tables `$fastProgramTables` lists, packed arrays of
integers all, and gives one packed array:

| It gives | Where |
|---|---|
| `{0, lp}`, then `prog`'s `lp` integers, then `parts` | the source has a program |
| `{1}` | `WolframLanguageProgram` gives `None` |
| `{2}` | the stages, called in turn, read it: a line continuation, a token that is two, as in `?a*=b`, or a long name in a string |

`fastProgramText` takes the source string itself, makes its codes and their padding in typed code,
calls `fastProgram`, and gives `{0, lp, prog, parts, codes}` in one packed array, or `{1}` or
`{2}` as `fastProgram` does. `flatProgram` calls it where a compiler of typed code gave it a
definition, as a kernel's does; Wolfram 15 calls the stages in turn. A kernel's builder takes the
program with the fewest evaluation steps from
`` Wolfram`Parser`Languages`WolframLanguage`Private`flatProgram[s] ``: that one array, or `None`.
`prog` is `flat[[3 ;; 2 + lp]]`, `parts` is the `3 + 4 m + 4 r` integers after it, for its `m`
leaves and `r` rows, and the codes are the rest: a leaf's text is the codes from its start to the
one before its end. `WolframLanguageProgram` gives the same program as its three arrays.

A builder reads the rows in turn, each a statement's, which builds its instructions over its leaves, the statement's names made then, in the contexts the statements
before it left. Instruction 28 reads the codes too. The parts are those `WolframLanguageHeldNext`
gives, each with no warning; `dev/check-reader-program.wls` holds the two to each other on the
reader corpus. A source read whole warns only of a `Null` a comma leaves, which instruction 11
marks, and of a string's escapes. Making the program takes the lexer, the parser, the lines and
`fastWhole`, typed code all, and, for a source with a backslash, `warningsAt` over its strings; it
keeps nothing.

## The machine

| State | What it holds |
|---|---|
| a stack of values | Held expressions, `HoldComplete[e]`, built without evaluating anything. `sp` is the top. |
| a stack of marks | One integer by value (see Marks). |
| a stack of heads | The relations' operators that instruction 6 pushes and instruction 7 takes. |
| the leaf cursor | The next leaf, from the first; instruction 1 takes it. |
| the statements | The values that instruction 25 takes, in order. `fastBuild` gives this list. |

### Marks

A value's mark is what a notebook reads differently for it:

| Mark | The value | What reads it |
|---|---|---|
| 0 | anything else, a number in parentheses and a product too | A minus is `Times[-1, x]`: `-(2)` is `Times[-1, 2]`, `a - b c` is `Plus[a, Times[-1, Times[b, c]]]`. |
| 1 | a number literal | A minus right before it folds into it: `-5` is the integer `-5`. |

No flat chain splices an operand: `a <> StringJoin @ b` is `StringJoin[a, StringJoin[b]]` and `a + +b` is `Plus[a, Plus[b]]`.

Every instruction that makes a value sets its mark: 0 but where the table below says otherwise.

## The instructions

`x` is the value at the top, `y` the one above it where there are two; `pop n` takes the top `n`
values, the lowest first, and the instruction's value replaces the value below them, or is pushed
where the instruction takes none.

| Code | Operands | Effect |
|---|---|---|
| 1 | kind, token | Push the next leaf's value (see Leaves), its mark the leaf's. The kind and token are the lexer's: `texts` holds the token's characters. |
| 2 | head | Prefix. `Minus`: `x` negated: mark 1, the number negated; else `Times[-1, x]`. Else `head[x]`, `Plus[x]` for a unary plus. |
| 3 | head | Postfix: `head[x]`. |
| 4 | head | Binary, pop 1 (`y`): `At`: `x[y]`; `SlashSlash`: `y[x]`; `Divide`: `Times[x, Power[y, -1]]`; else `head[x, y]`. |
| 5 | head, n | A flat chain of `n` operands: `head[ops...]`. |
| 6 | head | Push the head on the stack of heads; the values stay. |
| 7 | n | A chain of `n` relations' operands, with the last `n - 1` heads (taken from the stack of heads): all one head, not a vector relation: `head[ops...]`; else as below. |
| 8 | n | A call, pop `n` (the arguments): `x[args...]`. |
| 9 | head, n | A group. `Paren`: the value stays, its mark 0. Else pop `n`, `head[items...]`: `List`, `Association` and the long-name brackets. |
| 10 | n | A part, pop `n` (the indices): `Part[x, indices...]`. |
| 11 | 1 where a comma leaves it, else 0 | Push `Null`. The `Null` a comma leaves, as in `f[1,]`, gives the warning `{"com"}`; a `;`'s gives none. |
| 12 | | Push `All`. |
| 13 | | Push the integer `1`, mark 1: the first of a span begun with `;;`. |
| 14 | n | A message name, pop `n` (the symbol and its parts): `MessageName[items...]`. A part that is a word of one token comes as a leaf of kind 100, its text. |
| 15 | n | A type's parameters, pop `n`: `TypeSpecifier[x][params...]`. |
| 16 | primes | `Derivative[primes][x]`. |
| 17 | | `a ~f~ b`: the top three are `a`, `f`, `b`; they become `f[a, b]`. |
| 18 | n | A span, pop `n`: `Span[items...]`. |
| 19 | n | A compound, pop `n`: `CompoundExpression[items...]`. |
| 20 | 1, 2 or 3 | A tag set: 1, the top three `TagSetDelayed[f, lhs, rhs]`; 2, `TagSet[f, lhs, rhs]`; 3, the top two `TagUnset[f, lhs]`. |
| 21 | head | A put, pop 1 (`y`): `head[x, y]`, the head `Put` or `PutAppend`. |
| 22 | | `Get[x]`. |
| 23 | | A pattern, pop 1 (`y`): `Pattern[x, y]`. |
| 24 | integral | `{name, kind}` = `$fastIntegralList[[integral]]`. The kind `Integrate`: `x` of the form `d[v]`, `d` `DifferentialD` or `CapitalDifferentialD`, is `Integrate[1, v]`; of the form `Times[g..., d[v]]`, `Integrate[g, v]` with one factor, `Integrate[Times[g...], v]` with more; else `name[x]`. Another kind: `name[x]`. |
| 25 | first token, token after | The end of a statement: pop the value into the statements. |
| 26 | n | A chain of `∣`, pop `n`: `Divisible` of the operands in reverse order. |
| 27 | | `!!`: `Not[Not[x]]`. |
| 28 | start, end | The words of a `?` query: push the string of the source's characters from `start` to `end - 1`, each tab a space, its escapes decoded as a string's are. |
| 29 | 1 or 0 | A query: `Information[x, LongForm -> True]` for `??` (1), `Information[x, LongForm -> False]` for `?` (0). |

### A chain of relations

Instruction 7 with more than one kind of head, or with a vector relation (`VectorLess`,
`VectorGreater`, `VectorLessEqual`, `VectorGreaterEqual`), reads as `relationValue` does. Each
head has an affinity: vector for the vector relations, none for `Equal`, `Unequal`, `Less`,
`Greater`, `LessEqual` and `GreaterEqual`, and scalar for the rest. The operands and heads are read
from the left. Where a head's affinity is not none and differs from the affinity so far, the
chain read up to there is made one operand, simplified as below, and the reading goes on from it.
A simplified chain is:

- of one vector relation `r`: `r[{operands...}]`, a `List` of its operands;
- of one relation `r` of another kind: `r[operands...]`;
- of several heads, the affinity so far vector: `` Developer`VectorInequality[o1, r1, o2, r2, ...] ``;
- of several heads, else: `Inequality[o1, r1, o2, r2, ...]`;

the heads `ri` as symbols between the operands.

## Leaves

A leaf's value is held, made from its kind and text alone, so the reference makes each distinct
pair once.

| Kind | Name | Value of the text |
|---|---|---|
| 1 | Symbol | The symbol of the name, interned as the kernel's reader interns it: by its context where it has one, else in `$Context` or found on `$ContextPath`. `heldName` asks the kernel for it, the one place the reader does. |
| 2 | Blank | The name before the first `_`, the number of `_`, and the text after the last: 1, 2 or 3 underscores are `Blank`, `BlankSequence`, `BlankNullSequence`, with the head after them as its argument, `_h` being `Blank[h]`. A name before is `Pattern[name, blank]`. A `.` after is `Optional` of the whole: `x_.` is `Optional[Pattern[x, Blank[]]]`. |
| 3, 4 | Integer, Real | Digits alone: the integer. Else `b^^` gives the base, `*^e` a power of the base, `` `p `` a precision and ``` ``a ``` an accuracy, in digits of the base, an accuracy's digits needed: `` 1`` `` is no number, and reading stops at its marks. A count `n` of digits of base `b` is `n Log2[b] Log10[2.]` decimal digits, by its bits. A real with no mark, or a `` ` `` with no precision, is a machine real unless its digits are more than a machine real holds: `Floor[53 / Log2[b]] + 2` of base `b`, 17 decimal ones, 53 binary ones, and never fewer than 17 with `*^e`. A longer one has the precision of its digits' accuracy and its magnitude, counted in bits: `(a Log2[b] + (Log2[digits] + scale Log2[b])) Log10[2.]` for `a` digits after its point less `e`. A machine real is the one nearest its value: below `$MinMachineNumber` the subnormal nearest, `0.` where that is nearer, past `$MaxMachineNumber` the value at machine precision, `Overflow[]` past `$MaxNumber` and `Underflow[]` below `$MinNumber`. A precision on a zero is `0.` for a real and `0` for an integer. |
| 5 | String | The characters between the quotes, each escape decoded: `\\`, `\"`, `\n`, `\t`, `\r`, `\b`, `\f`, `\ ` and `\<newline>`, `\ooo` octal, `\.hh`, `\:hhhh` and `\|hhhhhh` codes, `\[Name]` the long name's character, and the linear syntax escapes `\!` `\(` `\)` `\*` `\@` `\^` `\_` `\%` `\&` `\+` `\/` `` \` `` their private characters. An escape no rule has stays as written. |
| 6 | Slot | `#` `Slot[1]`, `#n` `Slot[n]`, `#name` `Slot["name"]` with its long names read, `#"text"` `Slot` of the string, `##` `SlotSequence[1]`, `##n` `SlotSequence[n]`. |
| 7 | Out | `%` `Out[]`, `%%` `Out[-2]`, `%` k times `Out[-k]`, `%n` `Out[n]`. |
| 8 | File | The name of `<<`, `>>` or `>>>`: a quoted one as a string; else its characters with `\.hh`, `\:hhhh` and `\[Name]` decoded, as a string. |
| 20 | Boxes | Linear syntax: `\(...\)` its boxes; `\!\(...\)` `` Wolfram`Parser`Languages`WolframLanguage`LinearBoxes[boxes] ``, whose `MakeExpression` the kernel applies. |
| 100 | Tag | A word of one token after a `::`, or of a query that does not begin its statement: the text as a string. |

## Failures and warnings

The build pass gives no failure: `fastParse` makes a program only of what it has read. A source
that cannot be read stops before the build, and `WolframLanguageHeldNext` gives
`{Failure["ParseError", assoc], pos}`, `pos` where the failing statement's line begins. The
association has `"MessageTemplate"`, `"MessageParameters"` `<|"Position" -> p|>`, `"Position" -> p`,
the position in the source where the kernel's message points, `"Incomplete"`, `True` where the
source ends before its expression does, and `"Warnings"`, the warnings of the statement that stops.

The warnings come from the tokens, not the build: `warningTokens` finds the tokens that may give
one, and `warningsAt` gives them, each a list whose first element is the tag of the kernel's
`Syntax::` message of the same name:

| Warning | When |
|---|---|
| `{"com"}` | a comma leaves a `Null`: after a bracket's opener, before another comma, its closer, the end, or where reading stops |
| `{"stresc", c}` | a string's `\c`, `c` a letter no escape has |
| `{"sntoct1"}`, `{"sntoct2"}` | a string's `\` and too few octal digits, or `\.` and too few hexadecimal ones |
| `{"snthex"}`, `{"snthex32"}` | a string's `\:` or `\|` and too few hexadecimal digits |
| `{"sntufn", name}` | a long name no character has, or one not closed at the end of the source |
| `{"sntunc", name}` | a string's long name not closed before the string is |
| `{"sntmsng", text}` | a long name with no name before its end; `text` is the source from the statement on |

`WolframLanguageHeldNext[s, pos]` gives, for the part of `s` whose line begins at `pos`:

- `{HoldComplete[statement], next, <|"Warnings" -> warnings|>}` for a statement;
- `{Failure["ParseError", assoc], pos}` where reading stops;
- `EndOfFile` past the last part.

`next` is where the next part begins, just past the line end of the statement before it, the blank
lines and comments before the next statement its own; a caller reads it as the second element.

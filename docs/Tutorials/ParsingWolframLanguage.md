---
Template: TechNote
Name: ParsingWolframLanguage
Title: Parsing the Wolfram Language with Its Own Precedences
Context: Wolfram`Parser`Languages`WolframLanguage`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/ParsingWolframLanguage
Keywords: [Wolfram Language, InputForm, operator precedence, Pratt, CodeParser, flat operators, ternary operators, newlines, held expressions]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserZoo, PrattVsPEG, BuildingLanguageFrontEnds]
---

## What this note covers

[WolframLanguageHeld]() reads Wolfram Language source, the text of a `.wl` or `.m` package, to the expressions the kernel reads from it, and [WolframLanguageAST]() to a standard syntax tree. Both run one grammar, [WolframLanguageGrammar](), built of the paclet's combinators. This note builds a small part of that grammar step by step, to show the four things the language asks of a parser beyond an ordinary expression grammar:

- operators that gather a whole chain into one call, `a + b - c` into one sum;
- an operator with three operands, `a ~f~ b`;
- forms whose operands are optional, `a ;; b` and `a;`;
- newlines that end an expression outside brackets, and only where it could end.

The full grammar then reads what the kernel reads:

```wl
WolframLanguageHeld["f[x_] := Module[{y = x^2}, y - 1]"]
```

<!-- => {HoldComplete[f[x_] := Module[{y = x^2}, y - 1]]} -->

## Tokens

A token is its text, then the spaces after it. The operands of the small grammar are names, which become symbols, and numbers:

```wl
ws = ParseMany[ParseCharacter[" "]]
```

```wl
name = ParseAction[ParseRegex["[a-z]+"] ~~ ws, Symbol[#1] &]
```

```wl
number = ParseAction[ParseRegex["[0-9]+"] ~~ ws, FromDigits[#1] &]
```

An operator token gives its own text:

```wl
op[s_] := ParseAction[ParseLiteral[s] ~~ ws, s &]
```

## A sum is one call

In the kernel, `a + b - c` is `Plus[a, Times[-1, b], c]`: one call of `Plus` whatever the number of terms, each term after a `-` negated. A left-associative operator would nest instead. A `"InfixN"` operator of [ParseOperatorTable]() gathers a run of operators of its level that share a combining function, and hands that function the operands and what each operator's parser gave:

```wl
sumOf[terms_, signs_] := sum @@ Prepend[MapThread[If[#2 === "-", minus[#1], #1] &, {Rest[terms], signs}], First[terms]]
```

```wl
productOf[factors_, ops_] := product @@ factors
```

A product is written with `*` or with nothing at all between its factors, `2 x y`. The empty operator is a [ParseLookahead]() for the start of an operand, which reads nothing:

```wl
juxtaposed = ParseAction[ParseLookahead[ParseRegex["[a-z0-9(]"]], "*" &]
```

The table's levels are tightest first; the operand is a number, a name or an expression in parentheses:

```wl
unit = ParseChoice[number, name, ParseBetween[op["("], ParseRecursive[expr], op[")"]]]
```

```wl
expr = ParseOperatorTable[unit, {
   {{"InfixN", op["*"], productOf}, {"InfixN", juxtaposed, productOf}},
   {{"InfixN", op["+"], sumOf}, {"InfixN", op["-"], sumOf}}
}]
```

```wl
Parse[expr, "a - 2 b + c"]
```

<!-- => sum[a, minus[product[2, b]], c] -->

Parentheses start a new chain:

```wl
Parse[expr, "a - (b + c)"]
```

<!-- => sum[a, minus[sum[b, c]]] -->

The full grammar gives the kernel's forms. A minus folds into a number, and joins the factors of a product written as one:

```wl
FullForm[WolframLanguageHeld["a - 2 b + c - 3"]]
```

<!-- => FullForm[{HoldComplete[a - 2*b + c - 3]}] -->

## Relations

`a < b < c` is `Less[a, b, c]`, but `a < b <= c` is `Inequality[a, Less, b, LessEqual, c]`. All the relations share one combining function, which looks at the operators of the chain it is handed:

```wl
relationOf[operands_, heads_] := If[Length[Union[heads]] === 1,
   Apply[Symbol[First[heads]], operands],
   inequality @@ Riffle[operands, heads]]
```

```wl
rel[s_, head_] := ParseAction[ParseLiteral[s] ~~ ws, head &]
```

```wl
comparison = ParseOperatorTable[unit, {
   {{"InfixN", op["*"], productOf}, {"InfixN", juxtaposed, productOf}},
   {{"InfixN", op["+"], sumOf}, {"InfixN", op["-"], sumOf}},
   {{"InfixN", rel["<=", "LessEqual"], relationOf}, {"InfixN", rel["<", "Less"], relationOf}}
}]
```

```wl
Parse[comparison, "a < b + 1 <= c"]
```

<!-- => inequality[a, "Less", sum[b, 1], "LessEqual", c] -->

The table tries `<=` before `<`, so that `<` does not take the first character of `<=`. The full grammar instead makes every operator the longest one there, so the order of a level does not matter.

## Three operands

`a ~f~ b` is `f[a, b]`, and `a ~f~ b ~g~ c` is `g[f[a, b], c]`. A `"Ternary"` spec reads the left operand, its first operator, the middle operand, its second operator and the right operand, and applies what the second operator's parser gave to the three:

```wl
infix = ParseOperatorTable[unit, {
   {"Ternary", op["~"], ParseAction[ParseLiteral["~"] ~~ ws, Function[{l, m, r}, m[l, r]] &]}
}]
```

```wl
Parse[infix, "a ~f~ b ~g~ c"]
```

<!-- => g[f[a, b], c] -->

## Optional operands

`a ;; b` is `Span[a, b]`, `a ;;` is `Span[a, All]`, and `;; ;; 2` is `Span[1, All, 2]`. A postfix operator's parser may read anything after the operator, so the grammar reads these operands in the parser of `;;` itself, from a table of the levels that bind more tightly, and fills in `All` where one is left out. The trailing `;` of a compound expression is read the same way, `Null` where nothing follows:

```wl
WolframLanguageHeld["m[[;; , 2 ;; -1]]; a;"]
```

<!-- => {HoldComplete[m[[1 ;; All,2 ;; -1]]; a; ]} -->

## Newlines

Outside brackets a newline ends an expression if the expression could end there, so

```wl
WolframLanguageHeld["x = a\n  + b"]
```

<!-- => {HoldComplete[x = a], HoldComplete[Plus[b]]} -->

is two expressions, while an operator at the end of a line carries the expression on:

```wl
WolframLanguageHeld["x = a +\n  b"]
```

<!-- => {HoldComplete[x = a + b]} -->

The grammar is therefore built twice over, for two kinds of whitespace. Outside brackets the whitespace after an operand or a postfix operator stops at a newline; the newline then matches no operator, and the expression ends. After an infix or prefix operator, inside brackets and between expressions, whitespace takes newlines too:

```wl
WolframLanguageHeld["f[a\n  + b]"]
```

<!-- => {HoldComplete[f[a + b]]} -->

## Precedences

The levels of the grammar's table are not written by hand. [CodeParser]() publishes the precedence of every operator, and the grammar keeps the value of each one it reads, under CodeParser's name for it, then generates its levels by sorting them. A level is every operator of one value: `->` and `:>` share one, `+` and `-` another.

## Checking it against the kernel

The kernel reads source with [ImportString]() and `{"WL", "HeldExpressions"}`; the grammar's test suite compares the two on a hundred and fifty forms and on every source of the paclet's languages. The grammar reads its own source as the kernel does:

```wl
source = Import[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "Languages", "WolframLanguage.wl"}], "Text"];
```

```wl
WolframLanguageHeld[source] === ImportString[source, {"WL", "HeldExpressions"}]
```

<!-- => True -->

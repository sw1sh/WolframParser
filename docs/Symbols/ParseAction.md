---
Template: Symbol
Name: ParseAction
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/ref/ParseAction
Keywords: [parser, action, transform, reshape, semantic]
SeeAlso: [ParseCapture, ParseSequence, ParserCombinator]
RelatedGuides: [WolframParser]
---

## Usage

<code>[ParseAction]()[$p$, $f$]</code> returns the [ParserCombinator]() that runs $p$ and then applies $f$ to its result, returning $f$'s return value as the new parse result. The action $f$ is a [Function]() of one argument, or a function of *many* arguments if $p$'s result is a list (the arguments are spread).

## Details & Options

- If $p$'s result is a [List]() of $n$ elements, `$f$` is called as `$f$[el_1, …, el_n]` (i.e. the list is splatted). For a scalar result, $f$ is called as `$f$[el]`.
- Use [ParseCapture]() with a name if you want $f$ to look up arguments by name instead of position.
- $f$ is invoked at parse time, *not* compile time - so closures and ordinary WL evaluation work.
- The combinator type is `Action`.

## Basic Examples

Convert a digit-list to an integer:

```wl
Parse[
    ParseAction[ParseCharacter[DigitCharacter].., FromDigits @ StringJoin[#] &],
    "42"
]
```

<!-- => 42 -->

A two-piece sequence with a binary action:

```wl
Parse[
    ParseAction[
        ParseLiteral["a"] ** ParseLiteral["b"],
        Function[{l, r}, {right -> r, left -> l}]
    ],
    "ab"
]
```

<!-- => {right -> "b", left -> "a"} -->

## Scope

`ParseAction` chains - the inner action runs first, the outer one wraps it:

```wl
Parse[
    ParseAction[
        ParseAction[ParseCharacter[DigitCharacter].., FromDigits @ StringJoin[#] &],
        # + 1 &
    ],
    "9"
]
```

<!-- => 10 -->

The action can rebuild a structured AST:

```wl
Parse[
    ParseAction[
        ParseLiteral["if "] ** ParseCharacter[LetterCharacter].. ** ParseLiteral[" then "] ** ParseCharacter[LetterCharacter]..,
        Function[{_, cond, _, body}, Hold[If[cond, body]]]
    ],
    "if x then y"
]
```

<!-- => Hold[If[{"x"}, {"y"}]] -->

## Properties and Relations

`ParseAction[p, Identity]` is `p` (no reshape):

```wl
{
    Parse[ParseAction[ParseLiteral["foo"], Identity], "foo"],
    Parse[ParseLiteral["foo"], "foo"]
}
```

<!-- => {"foo", "foo"} -->

`ParseAction` is what powers the `:>` slot bodies in a [GrammarRules]() declaration:

```wl
Parse[
    GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}],
    "add 3 and 5"
]
```

<!-- => 8 -->

## Possible Issues

The function arity must match the parse-result shape. A length-3 sequence with a length-2 action fails at runtime, not parse time:

```wl
Parse[
    ParseAction[
        ParseLiteral["a"] ** ParseLiteral["b"] ** ParseLiteral["c"],
        Function[{l, r}, {l, r}]
    ],
    "abc"
]
```

<!-- => Function::flpar error + the raw {"a", "b", "c"} -->

## Neat Examples

A signed decimal:

```wl
Parse[
    ParseAction[
        ParseOptional[ParseLiteral["-"]] **
            ParseCharacter[DigitCharacter].. **
            ParseOptional[ParseLiteral["."] ** ParseCharacter[DigitCharacter]..],
        Function[{sign, intPart, fracPart},
            (If[MissingQ[sign], 1, -1]) *
                ToExpression @ StringJoin[
                    StringJoin[intPart],
                    If[MissingQ[fracPart], "", "." <> StringJoin[fracPart[[2]]]]
                ]
        ]
    ],
    "-3.14"
]
```

<!-- => -3.14 -->

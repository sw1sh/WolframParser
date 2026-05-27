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

- If `p`'s result is a [List]() of `n` elements, `f` is called as `f[el1, ..., eln]` (i.e. the list is splatted). For a scalar result, `f` is called as `f[el]`.
- Use [ParseCapture]() with a name if you want $f$ to look up arguments by name instead of position.
- $f$ is invoked at parse time, *not* compile time - so closures and ordinary WL evaluation work.
- The combinator type is `Action`.

## Basic Examples

Convert a digit-list to an integer. `StringJoin` is variadic, so it can be passed directly as the action:

```wl
Parse[
    ParseAction[ParseCharacter[DigitCharacter].., StringJoin],
    "42"
]
```

<!-- => "42" -->

To get the parsed integer instead of the digit string, compose with `FromDigits @ StringJoin[{##}]`:

```wl
Parse[
    ParseAction[ParseCharacter[DigitCharacter].., FromDigits @ StringJoin[{##}] &],
    "42"
]
```

<!-- => 42 -->

A two-piece sequence with a binary action:

```wl
Parse[
    ParseAction[
        ParseLiteral["a"] ~~ ParseLiteral["b"],
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
        ParseAction[ParseCharacter[DigitCharacter].., FromDigits @ StringJoin[{##}] &],
        # + 1 &
    ],
    "9"
]
```

<!-- => 10 -->

The action can rebuild a structured AST. Function parameters must all be named symbols - bind the bits you don't care about and ignore them in the body. Use [With]() to fold the StringJoin work *before* wrapping in [Hold]():

```wl
Parse[
    ParseAction[
        ParseLiteral["if "] ~~ ParseCharacter[LetterCharacter].. ~~ ParseLiteral[" then "] ~~ ParseCharacter[LetterCharacter]..,
        Function[{kw1, cond, kw2, body},
            With[{c = StringJoin[cond], b = StringJoin[body]},
                Hold[If[c, b]]
            ]
        ]
    ],
    "if x then y"
]
```

<!-- => Hold[If["x", "y"]] -->

## Properties and Relations

`ParseAction[p, Identity]` is `p` (no reshape):

```wl
{
    Parse[ParseAction[ParseLiteral["foo"], Identity], "foo"],
    Parse[ParseLiteral["foo"], "foo"]
}
```

<!-- => {"foo", "foo"} -->

`ParseAction` is what powers the `:>` slot bodies in a [GrammarRules]() declaration. The string template `"add <a:Number> and <b:Number>"` lowers to a [ParseSequence]() of literals and slot-recognizers, all wrapped in a `ParseAction` that binds the captured slot values to `a` / `b` in the rule body:

```wl
Parse[GrammarRules[{"add <a:Number> and <b:Number>" :> a + b}], "add 3 and 5"]
(* 8 *)
```

See [Parsing GrammarRules Locally](paclet:Wolfram/WolframParser/tutorial/ParsingGrammarRules) for the full subset of `GrammarRules` shapes lowered to `ParserCombinator`s.

## Possible Issues

The function arity should match the parse-result shape. A length-3 sequence applied through a length-2 [Function]() silently drops the third arg - keep the parameter count in sync with the sequence length:

```wl
Parse[
    ParseAction[
        ParseLiteral["a"] ~~ ParseLiteral["b"] ~~ ParseLiteral["c"],
        Function[{l, r}, {l, r}]
    ],
    "abc"
]
```

<!-- => {"a", "b"} -->

Use a variadic action (`##` / `{##}`) when you don't want to commit to a fixed arity:

```wl
Parse[
    ParseAction[
        ParseLiteral["a"] ~~ ParseLiteral["b"] ~~ ParseLiteral["c"],
        {##} &
    ],
    "abc"
]
```

<!-- => {"a", "b", "c"} -->

## Neat Examples

A signed decimal:

```wl
Parse[
    ParseAction[
        ParseOptional[ParseLiteral["-"]] ~~
            ParseCharacter[DigitCharacter].. ~~
            ParseOptional[ParseLiteral["."] ~~ ParseCharacter[DigitCharacter]..],
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

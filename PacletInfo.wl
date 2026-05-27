(* ::Package:: *)

PacletObject[<|
    "Name" -> "Wolfram/WolframParser",
    "Description" -> "A general, fast, composable parser library for the Wolfram Language - parser combinators, GrammarRules-compatible declarative grammars, FunctionCompile-backed local execution",
    "Creator" -> "Nikolay Murzin, Claude (Anthropic)",
    "PublisherID" -> "Wolfram",
    "License" -> "MIT",
    "Version" -> "0.2.0",
    "WolframVersion" -> "14.0+",
    "PrimaryContext" -> "Wolfram`Parser`",
    "Extensions" -> {
        {
            "Kernel",
            "Root" -> "Kernel",
            "Context" -> "Wolfram`Parser`",
            "Symbols" -> {
                "Wolfram`Parser`Parse",
                "Wolfram`Parser`ParsePartial",
                "Wolfram`Parser`ParserCompile",
                "Wolfram`Parser`ParserCombinator",
                "Wolfram`Parser`ParserCombinatorQ",
                "Wolfram`Parser`ParseError",
                "Wolfram`Parser`ParseLiteral",
                "Wolfram`Parser`ParseCharacter",
                "Wolfram`Parser`ParseSucceed",
                "Wolfram`Parser`ParseFail",
                "Wolfram`Parser`ParseSequence",
                "Wolfram`Parser`ParseChoice",
                "Wolfram`Parser`ParseMany",
                "Wolfram`Parser`ParseSome",
                "Wolfram`Parser`ParseOptional",
                "Wolfram`Parser`ParseBetween",
                "Wolfram`Parser`ParseSepBy",
                "Wolfram`Parser`ParseSepBy1",
                "Wolfram`Parser`ParseChainLeft",
                "Wolfram`Parser`ParseChainRight",
                "Wolfram`Parser`ParseLookahead",
                "Wolfram`Parser`ParseNotFollowedBy",
                "Wolfram`Parser`ParseTry",
                "Wolfram`Parser`ParseRecursive",
                "Wolfram`Parser`ParseAction"
            }
        },
        {
            "Kernel",
            "Root" -> "Kernel",
            "Context" -> "Wolfram`Parser`LaTeX`",
            "Symbols" -> {
                "Wolfram`Parser`LaTeX`LaTeXMathParse",
                "Wolfram`Parser`LaTeX`LaTeXMathParser"
            }
        },
        {
            "Kernel",
            "Root" -> "Kernel",
            "Context" -> "Wolfram`Parser`EBNF`",
            "Symbols" -> {
                "Wolfram`Parser`EBNF`EBNFParseFile",
                "Wolfram`Parser`EBNF`EBNFParseString",
                "Wolfram`Parser`EBNF`EBNFRules"
            }
        },
        {
            "Documentation",
            "Language" -> "English"
        }
    }
|>]

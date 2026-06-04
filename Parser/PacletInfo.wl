(* ::Package:: *)

PacletObject[<|
    "Name" -> "Wolfram/Parser",
    "Description" -> "Parser combinators for the Wolfram Language - GrammarRules compatible, locally compiled, with a LaTeX math parser",
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
                "Wolfram`Parser`ParseLiteral",
                "Wolfram`Parser`ParseCharacter",
                "Wolfram`Parser`ParseRegex",
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
                "Wolfram`Parser`ParseAction",
                "Wolfram`Parser`LaTeXMathParse",
                "Wolfram`Parser`LaTeXMathParser",
                "Wolfram`Parser`LaTeXMathStyle",
                "Wolfram`Parser`EBNFParse",
                "Wolfram`Parser`EBNFRules",
                "Wolfram`Parser`TPTPImport",
                "Wolfram`Parser`MarkdownInlineParse",
                "Wolfram`Parser`MarkdownInlineParser",
                "Wolfram`Parser`MarkdownParse",
                "Wolfram`Parser`MarkdownParser"
            }
        },
        {
            "Asset",
            "Root" -> "Assets",
            "Assets" -> {
                {"CompiledLaTeXParser", "LaTeXMathParserCompiled.wxf"}
            }
        },
        {
            "Documentation",
            "Language" -> "English"
        }
    }
|>]

(* ::Package:: *)

(* :Title: WolframLanguageReader.wl - Wolfram/Parser's core and its Wolfram Language reader alone *)
(* :Context: Wolfram`Parser` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    Loads what reading the Wolfram Language takes, and nothing else: the parser core, the AST
    vocabulary and the Wolfram Language's grammar and reader, WolframLanguageHeld,
    WolframLanguageAST, WolframLanguageConcrete and the rest of Languages/WolframLanguage.wl.
    No other module or language is loaded: not LaTeX, EBNF, TPTP or Markdown, nor Calculator,
    JSON, Lisp, Lambda, Brainfuck, OpenQASM or ABC. Get it in place of Needs["Wolfram`Parser`"],
    where only the reader is wanted:

        Get[FileNameJoin[{PacletObject["Wolfram/Parser"]["Location"], "Kernel", "WolframLanguageReader.wl"}]]

    The context is then loaded, so Needs["Wolfram`Parser`"] after it loads nothing more.
*)

Block[{Wolfram`Parser`Private`$wolframLanguageOnly = True},
    Get[FileNameJoin[{DirectoryName[$InputFileName], "Parser.wl"}]]
]

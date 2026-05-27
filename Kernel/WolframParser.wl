(* :Title: WolframParser *)
(* :Context: Wolfram`WolframParser` *)
(* :Summary:
    A general, fast, composable parser library for the Wolfram Language.

    The package combines three things that are otherwise scattered across
    the WL parser landscape:

    1. Parser combinators in the Parsec / FunctionalParsers tradition - a
       parser is a function of input, returning either a parse tree and the
       remaining input or a failure. Combinators glue smaller parsers into
       bigger ones.

    2. A declarative EBNF / GrammarRules-style entry point for users who
       prefer writing the grammar as data rather than as function calls.

    3. A token-oriented core: parsers operate uniformly on strings, on
       lists of tokens, and on flat lists of Wolfram expressions - one
       library covers text grammars, lexical post-processing, and
       expression-walker patterns.

    The kernel is dependency-free and entirely local (no cloud).

    This is the v0.1 skeleton: the survey tech note in
    docs/Tutorials/ParserLandscape.md records the design problem and
    contrasts what exists today. The library itself is being filled in
    iteratively; this file is intentionally minimal so the survey can
    land first.
*)

BeginPackage["Wolfram`WolframParser`"]


Begin["`Private`"]

(* implementation TBD - see the survey tech note for the design context. *)

End[]

EndPackage[]

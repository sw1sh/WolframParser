(* :Title: Parser *)
(* :Context: Wolfram`Parser` *)
(* :Summary:
    A general, fast, composable parser library for the Wolfram Language.

    The package combines three things that are otherwise scattered across
    the WL parser landscape:

    1. Parser combinators in the Parsec / FunctionalParsers tradition - a
       parser is a function of input, returning either a parse tree and the
       remaining input or a failure. Combinators glue smaller parsers into
       bigger ones.

    2. A declarative entry point compatible with the GrammarRules slot
       syntax - the same declaration travels to CloudDeploy (built-in path)
       or to a local FunctionCompile-built parser (this paclet's path).

    3. A token-oriented core: parsers operate uniformly on strings, on
       lists of tagged tokens, and on flat lists of Wolfram expressions -
       one library covers text grammars, lexical post-processing, and
       expression-walker patterns.

    The kernel compiles hot parsers to native code via FunctionCompile
    (LLVM-backed), so there is no C dependency and no cloud round-trip.

    This is the v0.1 skeleton. Two tech notes drive the implementation:
    docs/Tutorials/ParserLandscape.md surveys what exists today and where
    the gaps are; docs/Tutorials/DesignAndCompilationStrategy.md spells
    out the API, the algebra, the compilation strategy, and the worked
    targets (LaTeX math, TPTP, custom DSLs).
*)

BeginPackage["Wolfram`Parser`"]


Begin["`Private`"]

(* Implementation TBD - see docs/Tutorials/DesignAndCompilationStrategy.md
   for the design that the code is being written against. *)

End[]

EndPackage[]

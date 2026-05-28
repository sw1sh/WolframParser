---
Template: TechNote
Name: TPTPProblemLibrary
Title: Indexing the TPTP Problem Library
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/TPTPProblemLibrary
Keywords: [TPTP, theorem proving, ATP, automated reasoning, problem library, benchmarks, EBNFParse, TPTPImport]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParsingTPTP, ParsingBNFGrammars]
---

## What this note covers

The full [TPTP v9.2.1](https://tptp.org/TPTP/) distribution ships 26,264 problems across 57 mathematical domains, spanning all six TPTP clause heads (CNF, FOF, TFF, TCF, THF, NCF). This note shows how to index the corpus and parse problems on demand using [TPTPImport](paclet:Wolfram/WolframParser/ref/TPTPImport) - the EBNFParse-driven parser the [Parsing TPTP](paclet:Wolfram/WolframParser/tutorial/ParsingTPTP) tutorial builds piece by piece.

The pattern is two-step:

1. Walk the corpus's `Problems/` tree once, harvest the `%`-prefixed catalogue headers (`%Status`, `%Rating`, ...) into a lightweight metadata `Association` - tens of seconds for the whole 26K-problem corpus.
2. Parse a single problem's axioms + conjecture on demand via `TPTPImport[File[path]]` - tens to hundreds of milliseconds per call.

Keeping the full parsed corpus out of the index keeps the in-memory footprint small (the full parsed corpus would be multi-GB; the headers index is ~5 MB) while still letting any user re-parse any problem with one call.

---

## Setting up the corpus

The TPTP distribution lives at https://tptp.org/TPTP/Distribution/TPTP-v9.2.1.tgz (922 MB compressed, 9.9 GB extracted). Pre-download it once to `~/Downloads/TPTP-v9.2.1.tgz` (a ~75-minute download against the TPTP server; doing it from a shell rather than inside a notebook cell is much friendlier). The block below extracts the tarball into a persistent sibling directory and points the `TPTP` env-var at it so include directives resolve at parse time:

```wl
Needs["Wolfram`Parser`"];

$tptpTar = FileNameJoin[
    {$HomeDirectory, "Downloads", "TPTP-v9.2.1.tgz"}];
$tptpRoot = FileNameJoin[
    {$HomeDirectory, "Downloads", "TPTP-v9.2.1"}];
If[ ! FileExistsQ[$tptpTar],
    Message[TPTPImport::badparse,
        "Pre-download TPTP v9.2.1 to " <> $tptpTar <>
        " from https://tptp.org/TPTP/Distribution/TPTP-v9.2.1.tgz (~922 MB).",
        "missing tarball"];
    Abort[]];
If[ ! DirectoryQ[$tptpRoot],
    RunProcess[{"tar", "xzf", $tptpTar,
        "-C", DirectoryName[$tptpRoot]}]];
$tptpProblemsRoot = FileNameJoin[{$tptpRoot, "Problems"}];
SetEnvironment["TPTP" -> $tptpRoot];
```

---

## Building the metadata index

Each `.p` file in the corpus has a `%`-prefixed catalogue header at the top with `%Name`, `%Domain`, `%Status`, `%Rating`, ... fields. Parse the header into an [Association]() and pick out the SZS status and the current-version TPTP rating:

```wl
tptpHeaderOf[path_] := Association @ Flatten @ StringCases[
    Quiet @ ReadList[path, "String", 50],
    RegularExpression["^%\\s+([A-Za-z_]+)\\s*:\\s*(.+)$"] :>
        StringTrim["$1"] -> StringTrim["$2"]];

tptpRating[h_] := Quiet @ Replace[
    ToExpression @ First @ StringSplit[
        Lookup[h, "Rating", ""], " " | ","],
    _?(! NumberQ[#] &) -> Missing["NoRating"]];

tptpMetaOf[path_] := With[
    {name = FileBaseName[path], h = tptpHeaderOf[path]},
    name -> <|"Name" -> name,
        "Domain" -> FileNameTake[DirectoryName[path]],
        "Path"   -> StringDrop[path, StringLength[$tptpProblemsRoot] + 1],
        "Status" -> Lookup[h, "Status", Missing["NoStatus"]],
        "Rating" -> tptpRating[h]|>];
```

Walk every `.p` file and build the keyed [Association](). Takes about a minute on a 2024 laptop for the full corpus:

```wl
tptpProblems = Association @ Map[
    tptpMetaOf, FileNames["*.p", $tptpProblemsRoot, Infinity]];
```

---

## Browsing the metadata

Look up a single problem's metadata by its TPTP name. `GRP001-4` is one of the abelian-group warmup problems:

```wl
tptpProblems["GRP001-4"]
```

The dataset has 26,264 entries across every TPTP clause head:

```wl
Length[tptpProblems]
```

The TPTP domains carry very different problem counts; the synthetic (`"SYN"`), software-verification (`"SWV"`), and set theory (`"SET"`) domains dominate. The top ten by count:

```wl
Take[ReverseSort @ Counts[Values[tptpProblems][[All, "Domain"]]], 10]
```

The SZS catalogue status partitions the corpus; the vast majority of problems are `"Theorem"` or `"Unsatisfiable"` (both standard ATP targets):

```wl
Counts @ Values[tptpProblems][[All, "Status"]]
```

Filter by rating to find the unsolved-at-state-of-the-art frontier (rating $\geq 0.98$ - the problems no system in the current evaluation cohort closes):

```wl
Take[
    Sort @ Select[Values[tptpProblems],
        NumberQ[#["Rating"]] && #["Rating"] >= 0.98 &][[All, "Name"]],
    UpTo[10]]
```

---

## Parsing one problem on demand

`TPTPImport[File[path]]` parses a single `.p` file end to end and returns the standard `<|"Axioms" -> {...}, "Conjecture" -> phi|>` shape. Resolve the problem name to a path via the metadata index, then hand it to TPTPImport:

```wl
TPTPImport[File @ FileNameJoin[{$tptpProblemsRoot,
    tptpProblems["GRP001-4"]["Path"]}]]
```

`include('Axioms/...')` directives in the `.p` file resolve recursively against the `TPTP` env-var we set up earlier, so the returned `"Axioms"` list contains the included axioms inlined.

---

## Difficulty + clause-head structure

A histogram of TPTP ratings shows the difficulty distribution: most problems have low ratings (solved easily by every modern prover); a long tail at the high end carries the hard ones:

```wl
Histogram[Values[tptpProblems][[All, "Rating"]], 20,
    AxesLabel -> {"TPTP rating", "problem count"},
    PlotLabel -> "Difficulty distribution",
    PerformanceGoal -> "Speed",
    ImageSize -> 600]
```

The four CASC-style format separators (`-` for CNF, `+` for FOF, `=` for TFF, `^` for THF) partition the corpus by clause head. Counting each shows the modern shift toward higher-order and typed first-order:

```wl
Counts @ Cases[Keys[tptpProblems],
    name_ /; StringMatchQ[name, ___ ~~ DigitCharacter ~~ x:("-"|"+"|"="|"^"|"~") ~~ ___] :>
        StringCases[name, DigitCharacter ~~ x:("-"|"+"|"="|"^"|"~") :> x][[1, 1]]]
```

The TPTP rating spread within one domain (group theory) shows the difficulty gradient - low-rated problems are warm-ups, high-rated ones are the open frontier for state-of-the-art provers:

```wl
With[{grp = Select[Values[tptpProblems],
        #["Domain"] === "GRP" && NumberQ[#["Rating"]] &]},
    <|"Min" -> Min[grp[[All, "Rating"]]],
      "Median" -> Median[grp[[All, "Rating"]]],
      "Max" -> Max[grp[[All, "Rating"]]],
      "Count" -> Length[grp]|>
]
```

---

## Acknowledgements

The TPTP library is the work of Geoff Sutcliffe and Christian Suttner, 1993 onward. See [Sutcliffe (2017)](https://link.springer.com/article/10.1007/s10817-017-9407-7), *The TPTP Problem Library and Associated Infrastructure: From CNF and DPLL to TFF0 and TPI*, Journal of Automated Reasoning, 59(4):483-502. The published BNF lives at the [TPTPWorld/SyntaxBNF](https://github.com/TPTPWorld/SyntaxBNF) repository; this note's parser is generated mechanically from that BNF by [EBNFParse](paclet:Wolfram/WolframParser/ref/EBNFParse) - see the [Parsing TPTP](paclet:Wolfram/WolframParser/tutorial/ParsingTPTP) sibling tutorial.

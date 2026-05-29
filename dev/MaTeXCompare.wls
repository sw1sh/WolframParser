#!/usr/bin/env wl
(* ::Package:: *)

(* MaTeXCompare - a visual + quantitative fidelity harness for
   LaTeXMathParse, graded from atomic building blocks up to full
   compositions.

   Gold standard: MaTeX (https://github.com/szhorvat/MaTeX) shells out to
   a real LaTeX install and returns true Computer-Modern output as WL
   Graphics - far more faithful than the fetched KaTeX screenshot PNGs,
   and local.  For each case we render

       gold = MaTeX[src]                  (* true LaTeX               *)
       ours = DisplayForm @ LaTeXMathParse[src]

   normalize both to a common height, and report:
     - width ratio  (ours / gold ink width) - a font+spacing proxy;
       ~1.0 means our horizontal extent matches LaTeX.
     - image distance (after width-padding) - conflates glyph shape
       (CM vs the FE's Times) with spacing, so read it relatively.
   The montage (gold on top, ours below, per case) is the honest read.

   Requirements: MaTeX paclet + a working LaTeX (latex/dvisvgm or
   pdflatex + Ghostscript).  NOT part of the .wlt suite - it is a dev
   tool, run by hand:  wl -f dev/MaTeXCompare.wls

   Run with `wl` (not wolframscript) - see the project notes on why. *)

$pacletDir = FileNameJoin[{DirectoryName[$InputFileName], ".."}];
Quiet[
    Get[FileNameJoin[{$pacletDir, "Kernel", "Parser.wl"}]];
    Get[FileNameJoin[{$pacletDir, "Kernel", "LaTeX.wl"}]];
];
Needs["MaTeX`"];
Quiet @ UsingFrontEnd[CurrentValue[$FrontEnd, LightDark] = "Light"];

lp = Wolfram`Parser`LaTeXMathParse;
$outDir = FileNameJoin[{$pacletDir, "dev", "matex-out"}];
Quiet @ CreateDirectory[$outDir, CreateIntermediateDirectories -> True];
$H = 70;

tight[img_] := ImageResize[ImageCrop[img], {Automatic, $H}];
goldR[src_] := Quiet @ Check[
    tight @ Rasterize[MaTeX[src, FontSize -> 24], Background -> White, ImageResolution -> 144],
    $Failed];
ourR[src_] := Module[{r = Quiet @ Check[lp[src], $Failed]},
    If[ MatchQ[r, _Wolfram`Parser`ParseError | $Failed], $Failed,
        tight @ Rasterize[Style[DisplayForm[r], FontSize -> 24], Background -> White,
            ImageResolution -> 144]]];
pad[img_, w_] := ImagePad[img, {{0, w - ImageDimensions[img][[1]]}, {0, 0}}, White];

(* Graded building-block corpus: tier 0 atoms -> tier 7 compositions.
   Extend freely; the harness derives all metrics automatically. *)
$cases = {
    {0, "x"}, {0, "2"}, {0, "\\alpha"}, {0, "\\Omega"},
    {1, "a+b"}, {1, "a=b"}, {1, "x-y"}, {1, "a \\cdot b"}, {1, "a < b \\leq c"},
    {2, "x^2"}, {2, "x_i"}, {2, "x_i^2"}, {2, "e^{-x^2}"}, {2, "f'"},
    {3, "\\frac{a}{b}"}, {3, "\\sqrt{x}"}, {3, "\\sqrt[3]{x}"}, {3, "\\frac{1}{1+x}"},
    {4, "\\sum_{i=0}^n a_i"}, {4, "\\int_a^b f"}, {4, "\\prod_{k=1}^n k"},
    {5, "(x+1)"}, {5, "\\left(\\frac{a}{b}\\right)"}, {5, "|x|"}, {5, "\\big(x\\big)"},
    {6, "\\sin x + \\cos y"}, {6, "a \\, b"}, {6, "f(x) = x^2 + 1"},
    {7, "\\sum_{n=0}^\\infty \\frac{1}{n^2}"}, {7, "\\frac{\\partial f}{\\partial x}"}
};

proc[{tier_, src_}] := Module[{g = goldR[src], o = ourR[src], w, wr, d},
    If[ !ImageQ[g] || !ImageQ[o],
        {tier, src, Missing[], Missing[], Style["MISSING", Red]},
        w = Max[ImageDimensions[g][[1]], ImageDimensions[o][[1]]];
        wr = N[ImageDimensions[o][[1]] / ImageDimensions[g][[1]], 3];
        d = Round @ N @ ImageDistance[pad[g, w], pad[o, w]];
        {tier, src, wr, d,
            ImageAssemble[
                {{pad[g, w]}, {ConstantImage[GrayLevel[.7], {w, 1}]}, {pad[o, w]}},
                Background -> White]}
    ]];

rows = proc /@ $cases;
montage = Grid[
    Prepend[rows, {"T", "source", "w-ratio", "imgdist", "gold (top) / ours (bottom)"}],
    Frame -> All, Alignment -> {Left, Center}];
Export[FileNameJoin[{$outDir, "montage.png"}],
    Rasterize[montage, Background -> White, ImageResolution -> 108]];

metricRows = Select[rows, NumberQ[#[[3]]] &];
meanWR = If[metricRows === {}, Missing[], N[Mean[metricRows[[All, 3]]], 3]];
Export[FileNameJoin[{$outDir, "metrics.tsv"}],
    Prepend[
        {ToString[#[[1]]], #[[2]], ToString[#[[3]]], ToString[#[[4]]]} & /@ rows,
        {"tier", "source", "width_ratio", "img_dist"}],
    "TSV"];

Print["MaTeXCompare: ", Length[$cases], " cases, mean width-ratio = ", meanWR];
Print["  montage -> ", FileNameJoin[{$outDir, "montage.png"}]];
Print["  metrics -> ", FileNameJoin[{$outDir, "metrics.tsv"}]];

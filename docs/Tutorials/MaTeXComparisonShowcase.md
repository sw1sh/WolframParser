---
Template: TechNote
Name: MaTeXComparisonShowcase
Title: MaTeX Comparison Showcase
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/MaTeXComparisonShowcase
Keywords: [LaTeX, math, parser, MaTeX, Computer Modern, fidelity, comparison, FractionBox, GridBox, RowBox]
RelatedGuides: [WolframParser]
RelatedTutorials: [LaTeXMathParserImplementation]
---

## What this note covers

`LaTeXMathParse` turns LaTeX math into a Wolfram box tree that the front end then typesets. The natural question is: *how close is that to what LaTeX itself would draw?* This note answers it directly, with [MaTeX](https://github.com/szhorvat/MaTeX) as the gold standard.

MaTeX shells out to a real LaTeX installation and returns genuine Computer Modern output as resolution-independent **vector graphics** - the actual LaTeX rendering, not an approximation, and not a screenshot. For each expression below it appears in the **MaTeX (gold)** column. The **ImportString** column is Wolfram's stock `ImportString[…, "LaTeX"]` importer - what you get *without* this paclet - shown in the front end's **own default math font**, exactly as it comes (we deliberately do *not* restyle it to Computer Modern, so its typeface is part of the contrast too). The **LaTeXMathParse** column is the front end's own live typesetting of *this* paclet's boxes, restyled into the same Computer-Modern face as gold, so it differs from gold only in *layout*, never in typeface. Read each row left to right: LaTeX, then gold, then stock Wolfram, then ours.

The corpus is graded - atoms, operators, sub/superscripts, fractions and radicals, large operators, delimiters, functions, accents, environments, full real-world formulas, double-struck blackboard, and quantum / bra-ket notation - so you can see where the parser tracks LaTeX exactly and where the front end's math engine spaces or sizes things a little differently. Every entry both parses to a non-[ParseError]() box tree **and** renders in real LaTeX, so each row is an honest apples-to-apples read.

> MaTeX needs a working LaTeX toolchain (``latex`` + ``dvisvgm``, or ``pdflatex`` + Ghostscript). When it isn't available the gold column shows a placeholder and the `LaTeXMathParse` column still renders, so this note always builds. A companion headless harness, ``dev/MaTeXCompare.wls``, runs the same comparison and additionally prints quantitative width-ratio / image-distance metrics for regression tracking.

## Gold vs. parser, by tier

```wl
#| collapse: true
(* MaTeX is the gold standard: it shells out to a real LaTeX install and
   returns true Computer-Modern output as vector Graphics.  We render each
   source two ways - MaTeX (gold) and the front end's live typesetting of
   LaTeXMathParse's boxes - and lay them side by side.  Guard the load so the
   note still builds where LaTeX/MaTeX is absent.  Load best-effort (Needs can
   emit a benign first-run message that a Check gate would mistake for failure)
   and decide availability purely by whether MaTeX actually returns Graphics. *)
Quiet @ Check[Needs["MaTeX`"], Null];
$hasMaTeX = MatchQ[Quiet @ MaTeX["x"], _Graphics];

(* Render our boxes in a Computer-Modern-family font so the comparison is
   about structure and spacing, not typeface (the FE's default math face is
   Times-based).  Detect by font FILE on disk - a headless build FE returns
   {} from $FontFamilies yet still renders a family by name.  Homebrew's
   `font-computer-modern` installs cmun*.ttf; Latin Modern installs
   lmroman*/latinmodern*. *)
(* Prefer Latin Modern *Math* - the OpenType math font whose italics are the
   cmmi math-italic letterforms MaTeX actually uses (so variable shapes match,
   not just the upright glyphs).  Fall back to Latin Modern Roman (the text
   family - close, but text-italic and a touch heavier), then CMU Serif
   (heavier still). *)
$fontDirs = {FileNameJoin[{$HomeDirectory, "Library", "Fonts"}], "/Library/Fonts"};
$mathFont = Which[
    FileNames["latinmodern-math*" | "lmmath*" | "LatinModernMath*", $fontDirs] =!= {}, "Latin Modern Math",
    FileNames["lmroman*" | "latinmodern*", $fontDirs] =!= {}, "Latin Modern Roman",
    FileNames["cmun*", $fontDirs] =!= {}, "CMU Serif",
    True, None];
$mathFontOpts = If[$mathFont === None, {}, {FontFamily -> $mathFont}];

(* Double-struck (\mathbb) is its own font: MaTeX uses AMS msbm, which no
   OpenType math font reproduces.  MSBM10.otf is msbm converted to OpenType
   with its blackboard letters remapped to the Unicode double-struck codepoints
   (build it once with fontforge from texmf's msbm10.pfb).  When present, render
   the double-struck characters in it so ours matches gold's blackboard exactly;
   otherwise they fall back to the FE's own double-struck. *)
$msbmFont = If[FileNames["MSBM10.otf", $fontDirs] =!= {}, "MSBM10", None];
dblStruckQ[c_String] := With[{cc = First @ ToCharacterCode[c]},
    MemberQ[{16^^2102, 16^^210D, 16^^2115, 16^^2119, 16^^211A, 16^^211D, 16^^2124}, cc] ||
    (16^^1D538 <= cc <= 16^^1D56B) || (16^^1D7D8 <= cc <= 16^^1D7E1)];
toMSBM[box_] := If[$msbmFont === None, box,
    box /. s_String /; s =!= "" && AllTrue[Characters[s], dblStruckQ] :>
        StyleBox[s, FontFamily -> $msbmFont]];

(* LaTeXMathParse tags italic identifiers StyleBox[letter, "TI"] (Times-pinned);
   re-style them into the chosen CM family.  An OpenType *math* font (Latin
   Modern Math) carries the cmmi math-italic glyphs MaTeX uses at the
   math-alphanumeric codepoints, NOT via FontSlant - so for it we remap each
   letter to its math-italic codepoint (h -> Planck, a-z, A-Z, lowercase Greek)
   and drop the slant, matching gold's variable shapes and weight.  A text-only
   fallback (Latin Modern Roman / CMU Serif) just gets FontSlant -> Italic. *)
$useMathItalic = $mathFont =!= None && StringContainsQ[$mathFont, "Math"];
mathItalicChar[c_String] := With[{cc = First @ ToCharacterCode[c]},
    FromCharacterCode @ Which[
        cc == 104, 16^^210E,                                      (* h -> Planck constant *)
        97 <= cc <= 122, cc + (16^^1D44E - 97),                   (* a-z *)
        65 <= cc <= 90, cc + (16^^1D434 - 65),                    (* A-Z *)
        16^^03B1 <= cc <= 16^^03C9, cc + (16^^1D6FC - 16^^03B1),  (* alpha-omega *)
        True, cc]];
toMathItalic[s_String] := StringJoin[mathItalicChar /@ Characters[s]];
applyMathFont[box_] := toMSBM @ Which[
    $mathFont === None, box,
    $useMathItalic, box /. {
        StyleBox[a_String, "TI", r___] :> StyleBox[toMathItalic[a], FontFamily -> $mathFont, r],
        StyleBox[a_, "TI", r___] :> StyleBox[a, FontSlant -> Italic, FontFamily -> $mathFont, r]},
    True, box /. StyleBox[a_, "TI", r___] :> StyleBox[a, FontSlant -> Italic, FontFamily -> $mathFont, r]];

(* MaTeX returns black vector glyphs with no color directive, so on a dark
   background they vanish.  Recolor them with LightDarkSwitched[Black, White]
   (the appearance-adaptive color; see GUIDE.md) so the gold glyphs follow
   light/dark exactly like the parser column's live text - black on light,
   white on dark. *)
darkSafe[g_Graphics] := g /. Graphics[p_, o___] :> Graphics[
    {LightDarkSwitched[Black, White], p}, o];
gold[src_String] := If[! $hasMaTeX,
    Style["(needs MaTeX)", Gray, FontSize -> 10],
    With[{r = Quiet @ MaTeX[src, FontSize -> 18]},
        If[MatchQ[r, _Graphics], darkSafe[r], Style["LaTeX error", Red, FontSize -> 10]]]];

(* the raw box tree behind the parser column - the actual Wolfram boxes
   LaTeXMathParse produced, as InputForm text. *)
$mutedText = LightDarkSwitched[GrayLevel[0.45], GrayLevel[0.65]];
(* LaTeXMathParse signals a parse failure with a Failure["ParseError", ...]
   object (head Failure), so the guard must catch _Failure - matching only
   _ParseError lets a failure through and renders it as a red error box. *)
parseFailedQ[r_] := MatchQ[r, _Failure | _ParseError | $Failed];
boxes[src_String] := Module[{r = Quiet @ Check[LaTeXMathParse[src], $Failed]},
    Pane[
        Style[If[parseFailedQ[r], "ParseError", ToString[r, InputForm]],
            FontFamily -> "Source Code Pro", FontSize -> 7, $mutedText],
        {240, Automatic}, Alignment -> {Left, Top}]];

ours[src_String] := Module[{r = Quiet @ Check[LaTeXMathParse[src], $Failed]},
    If[ parseFailedQ[r],
        Style["ParseError", Red, FontSize -> 12],
        (* ScriptLevel -> 0 renders in *display* style - big operators with
           their limits stacked above/below, full-size fractions - to match
           MaTeX, which typesets display math.  Without it the front end uses
           inline/text style (small operators, limits to the side, shrunken
           fractions), which would read as a parser difference when it is only
           a display-vs-inline one.  The parser's UnderoverscriptBox is already
           correct; this just renders it in the right environment. *)
        Style[RawBoxes[StyleBox[applyMathFont[r], ScriptLevel -> 0]],
            FontSize -> 18, LineBreakWithin -> False, Sequence @@ $mathFontOpts]]];

(* The stock Wolfram LaTeX importer, for contrast - what you get WITHOUT this
   paclet.  ImportString[..., "LaTeX"] needs math-mode delimiters (bare "x^2"
   returns $Failed), so wrap each source in $...$; it returns a whole Notebook,
   from which we pull the math FormBox and strip the importer's nested
   Cell / TextData / BoxData / FormBox wrappers (its grid cells are wrapped
   Cells that won't render as bare boxes otherwise).  Rendered in the front
   end's OWN default math font (we do NOT restyle it to Computer Modern the way
   the gold/ours columns are matched) - this is the stock importer exactly as it
   comes.  Watch where it falls short of LaTeXMathParse: \mathbb{R} comes back a
   plain R (no blackboard), \begin{cases} loses its brace, \overrightarrow
   misfires, Greek is left upright. *)
cleanBuiltin[b_] := b //. {
    Cell[BoxData[x_], ___] :> x, Cell[TextData[x_List], ___] :> RowBox[x],
    Cell[TextData[x_], ___] :> x, Cell[x_, ___] :> x, BoxData[x_] :> x,
    TextData[x_List] :> RowBox[x], TextData[x_] :> x, FormBox[x_, ___] :> x};
builtinBoxes[src_String] := Module[{nb, b},
    nb = Quiet @ Check[ImportString["$" <> src <> "$", "LaTeX"], $Failed];
    If[! MatchQ[nb, _Notebook], Return[$Failed]];
    b = FirstCase[nb, FormBox[box_, ___] :> box, $Failed, Infinity];
    If[b === $Failed, $Failed, cleanBuiltin[b]]];
builtin[src_String] := Module[{b = builtinBoxes[src]},
    If[ b === $Failed,
        Style["(no import)", $mutedText, FontSize -> 10],
        (* render in the FE's OWN default math font - NOT restyled to Computer
           Modern like the gold/ours columns - so this shows the stock
           importer's true appearance, typeface and all. *)
        Style[RawBoxes[StyleBox[b, ScriptLevel -> 0]],
            FontSize -> 18, LineBreakWithin -> False]]];

(* Graded corpus: atoms -> full compositions.  Extend freely - add a string
   to any tier and the row appears automatically. *)
$corpus = {
    "Atoms and symbols" -> {
        "x", "\\alpha", "\\theta", "\\pi", "\\Omega", "\\Gamma",
        "\\infty", "\\partial", "\\nabla", "\\hbar", "\\ell", "\\aleph"},
    "Operators and relations" -> {
        "a+b", "a = b", "x \\cdot y", "a \\times b", "a \\div b", "a \\pm b",
        "a \\mp b", "a \\circ b", "a \\oplus b", "a \\otimes b", "A \\cup B",
        "A \\cap B", "A \\subseteq B", "x \\in \\mathbb{R}", "a \\neq b",
        "a \\approx b", "a \\equiv b \\pmod n", "a \\le b \\le c",
        "x \\to \\infty", "p \\Rightarrow q", "\\forall x \\, \\exists y"},
    "Subscripts and superscripts" -> {
        "x^2", "x_i", "x_i^2", "x^{2^3}", "x_{i+1}", "e^{-x^2}", "f'", "f''",
        "a_{i,j}^{(n)}", "x_1 + x_2 + \\cdots + x_n"},
    "Fractions and radicals" -> {
        "\\frac{a}{b}", "\\dfrac{a}{b}", "\\tfrac{1}{2}", "\\frac{1}{1+x}",
        "\\frac{\\frac{a}{b}}{c}", "\\sqrt{x}", "\\sqrt[3]{x}",
        "\\sqrt{x^2+y^2}", "\\binom{n}{k}"},
    "Large operators and limits" -> {
        "\\sum_{i=0}^n a_i", "\\sum_{n=1}^\\infty \\frac{1}{n^2}",
        "\\prod_{k=1}^n k", "\\int_a^b f(x)\\,dx", "\\iint_D f", "\\oint_C f",
        "\\bigcup_{i=1}^n A_i", "\\bigcap_i A_i", "\\bigoplus_i V_i",
        "\\coprod_i X_i", "\\lim_{x \\to 0} \\frac{\\sin x}{x}",
        "\\max_{x \\in S} f(x)"},
    "Delimiters and sizing" -> {
        "(x+1)", "[a, b]", "\\{x : x > 0\\}", "\\left(\\frac{a}{b}\\right)",
        "\\left[\\sum_i a_i\\right]", "|x|", "\\|v\\|", "\\lvert x \\rvert",
        "\\lVert v \\rVert", "\\langle a, b \\rangle", "\\lceil x \\rceil",
        "\\lfloor x \\rfloor", "\\big( x \\big)", "\\left| \\frac{a}{b} \\right|"},
    "Functions and spacing" -> {
        "\\sin x + \\cos y", "\\sin^2\\theta + \\cos^2\\theta = 1",
        "\\log_2 n", "\\ln x", "\\exp(x)", "\\tan\\theta", "\\arctan x",
        "\\gcd(a,b)", "a \\, b", "a \\; b", "a \\quad b", "\\operatorname{tr}(A)"},
    "Accents and decorations" -> {
        "\\hat{x}", "\\tilde{a}", "\\bar{x}", "\\vec{v}", "\\dot{x}",
        "\\ddot{x}", "\\check{a}", "\\breve{a}", "\\acute{e}",
        "\\overline{AB}", "\\underline{x}", "\\widehat{xy}",
        "\\widetilde{xyz}", "\\overrightarrow{AB}", "\\overbrace{a+b+c}",
        "\\underbrace{1+1+1}"},
    "Matrices and environments" -> {
        "\\begin{matrix} a & b \\\\ c & d \\end{matrix}",
        "\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}",
        "\\begin{bmatrix} x \\\\ y \\end{bmatrix}",
        "\\begin{vmatrix} a & b \\\\ c & d \\end{vmatrix}",
        "\\begin{Vmatrix} a & b \\\\ c & d \\end{Vmatrix}",
        "\\begin{cases} 1 & x>0 \\\\ 0 & x \\le 0 \\end{cases}",
        "\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}"},
    "Full compositions" -> {
        "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}", "e^{i\\pi} + 1 = 0",
        "\\sum_{n=0}^\\infty \\frac{x^n}{n!} = e^x",
        "\\frac{\\partial f}{\\partial x}",
        "\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}",
        "\\left( \\sum_{i=1}^n a_i b_i \\right)^2 \\le \\left( \\sum_i a_i^2 \\right)\\left( \\sum_i b_i^2 \\right)",
        "f(x) = \\sum_{n=0}^\\infty \\frac{f^{(n)}(a)}{n!}(x-a)^n",
        "\\nabla \\times \\mathbf{B} = \\mu_0 \\mathbf{J} + \\mu_0 \\epsilon_0 \\frac{\\partial \\mathbf{E}}{\\partial t}"},
    (* double-struck \mathbb renders in the converted AMS msbm font (MSBM10.otf,
       see $msbmFont) so it matches gold's blackboard exactly - both the
       Letterlike-block letters (C H N P Q R Z) and the math-alphanumeric ones
       (A B D F K ...). *)
    "Double-struck (\\mathbb)" -> {
        "\\mathbb{N}", "\\mathbb{Z}", "\\mathbb{Q}", "\\mathbb{R}", "\\mathbb{C}",
        "\\mathbb{H}", "\\mathbb{F}", "\\mathbb{K}", "\\mathbb{P}",
        "x \\in \\mathbb{R}^n", "f : \\mathbb{Q} \\to \\mathbb{R}",
        "\\mathbb{Z}/n\\mathbb{Z}", "\\mathbb{C}^2 \\cong \\mathbb{R}^4"},
    "Quantum / bra-ket" -> {
        "|\\psi\\rangle", "\\langle\\phi|\\psi\\rangle",
        "\\frac{1}{\\sqrt{2}}(|0\\rangle + |1\\rangle)",
        "|0\\rangle \\otimes |1\\rangle", "\\langle\\psi|\\hat{H}|\\psi\\rangle",
        "\\rho = \\sum_i p_i |\\psi_i\\rangle\\langle\\psi_i|",
        "H = \\frac{1}{\\sqrt{2}}\\begin{pmatrix} 1 & 1 \\\\ 1 & -1 \\end{pmatrix}",
        "\\sigma_y = \\begin{pmatrix} 0 & -i \\\\ i & 0 \\end{pmatrix}",
        "U|\\psi\\rangle = e^{i\\theta}|\\psi\\rangle"}
};

(* muted text uses a mid GrayLevel that is legible on both light and dark
   backgrounds (no appearance switch needed); headers and the parser column
   carry no explicit color, so they inherit the front end's adaptive
   foreground.  Backgrounds/frame are translucent gray, dark-mode safe. *)
srcCell[s_String] := Pane[
    Style[s, FontFamily -> "Source Code Pro", FontSize -> 8, $mutedText],
    {190, Automatic}, Alignment -> {Left, Center}];
tierRow[name_String] := {
    Item[Style[name, Bold, 11], Background -> GrayLevel[0.5, 0.13]],
    SpanFromLeft, SpanFromLeft, SpanFromLeft, SpanFromLeft};

Grid[
    Join[
        {Style[#, Bold] & /@ {"LaTeX source", "MaTeX (gold)", "ImportString", "LaTeXMathParse", "Boxes"}},
        Flatten[
            Function[grp,
                Prepend[
                    Function[s, {srcCell[s], gold[s], builtin[s], ours[s], boxes[s]}] /@ grp[[2]],
                    tierRow[grp[[1]]]
                ]
            ] /@ $corpus,
            1]
    ],
    Frame -> All,
    FrameStyle -> GrayLevel[0.5, 0.5],
    Alignment -> {Left, Center},
    Spacings -> {1.5, 1.2},
    Background -> {None, {1 -> GrayLevel[0.5, 0.2]}}
]
```

## Reading the comparison

- **Structure is the parser's job.** Whether a fraction stacks, a subscript binds to the right atom, a matrix lays out as a grid, an integral carries its limits - that is what `LaTeXMathParse` builds, and it should match the gold column row for row.
- **Display style is forced on both sides.** MaTeX typesets *display* math, so the parser column is rendered at `ScriptLevel -> 0` to match: ``\sum`` / ``\prod`` / ``\bigcup`` / ``\lim`` carry their limits stacked **above and below** (the parser emits [UnderoverscriptBox]() / [UnderscriptBox](); the front end only stacks them in display style, putting them to the side inline), ``\int`` keeps its side limits, and fractions render full size. The same boxes in an inline ``$…$`` context would correctly show side-set limits and smaller fractions.
- **Typeface is matched in shape.** Italic letters use **Latin Modern Math** - the OpenType math font whose italics are the very `cmmi` letterforms MaTeX renders, reached by remapping each `"TI"` letter to its math-alphanumeric codepoint (so variable *shapes* match, not just the upright glyphs). Double-struck `\mathbb` uses **`MSBM10`** - the AMS `msbm` font (what MaTeX's `\mathbb` is) converted to OpenType and remapped to the Unicode double-struck codepoints - so the blackboard letters match gold's exactly rather than the FE's own design.
- **Stroke weight is the one thing that can't match, and it's the render engine, not the font.** Measured at identical size and resolution, the front-end column carries ~1.5× (italics) to ~1.8× (dense upright caps) the ink of the LaTeX column - and that ratio is *identical* whether the FE font is Latin Modern Math or the FE default, so no font choice changes it. MaTeX is a resolution-independent LaTeX vector; the parser column is front-end-rasterized text, which is simply heavier. Equalizing it would mean rendering both columns through the same engine - which would make them identical and defeat the comparison. It reads closest in light appearance.
- **The ImportString column is the stock Wolfram importer**, shown for contrast - it is what `ImportString[…, "LaTeX"]` gives without this paclet (math-wrapped in `$…$`, since bare snippets return `$Failed`), drawn in the front end's **own default math font** rather than restyled to Computer Modern, so you see it exactly as it comes - typeface included. It handles the easy structural cases - superscripts, fractions, radicals, sums - but watch where it diverges from both gold and ours: `\mathbb{R}` comes back a **plain `R`** with no blackboard, `\begin{cases}` **loses its enclosing brace**, `\overrightarrow{AB}` misfires into a stray ring, and Greek letters are left **upright** rather than math-italic. That gap is the reason `LaTeXMathParse` exists.
- **The fifth column is the raw box tree** `LaTeXMathParse` produced (InputForm), so you can read the structure that drives the rendering - `FractionBox`, `UnderoverscriptBox`, the bracketing-bar characters, the `"TI"` italic tags, and so on.
- **Where the two diverge** is the front end's automatic math-spacing engine versus TeX's: the gaps around binary operators and relations, and how aggressively a delimiter grows around tall content. Those are rendering-side, not parse-side - the box tree is faithful; the FE just spaces it by its own rules. See [WolframBoxTypesetting](paclet:Wolfram/WolframParser/tutorial/WolframBoxTypesetting) for the levers that tighten this.

> The code cell that builds this table is collapsed by default (``#| collapse: true``) so only the comparison shows; click the closed group's bracket to reveal the code. The MaTeX column is recolored with ``LightDarkSwitched[Black, White]`` so it stays legible in both light and dark front-end appearances.

## See also

- [LaTeXMathParserImplementation](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) - design and implementation notes, and the KaTeX-corpus coverage benchmark
- [WolframBoxTypesetting](paclet:Wolfram/WolframParser/tutorial/WolframBoxTypesetting) - how the front end renders boxes, and how to control its math spacing/fonts
- [LaTeXMathParse]() - the symbol reference page
- [MaTeX](https://github.com/szhorvat/MaTeX) - the gold-standard LaTeX-to-graphics package used here

# WolframParser documentation guide

How to write the WolframParser documentation sources under `docs/` — the
`Template: Symbol` reference pages, the `Template: Guide` guide, and the
`Template: TechNote` tutorials. They are literate-markdown files that
[`build.wls`](../build.wls) turns into evaluated Wolfram notebooks via
`MarkdownToNotebook` (MTN), landing under `Parser/Documentation/English/`.
This is the house style. It is adapted from the THVMLink doc guide and
overrides the upstream
[wolfram-symbol-page skill](https://github.com/WolframInstitute/MarkdownToNotebook/blob/main/skills/wolfram-symbol-page/SKILL.md)
where they disagree (noted inline).

## Build and inspect, always

Every page is a *twin*: the `.md` source and the evaluated `.nb` that MTN
builds from it. A page is not done until you have **built it and read back
every output cell**. Run the build with the `wl` CLI (not `wolframscript` —
its init can wedge kernels), and confirm each cell's value:

```
wl -f build.wls
```

`build.wls` auto-discovers every `docs/**/*.md`, so a new file builds with no
wiring. To iterate on one page without rebuilding the whole set, call
`MarkdownToNotebook[src, out, "EvaluateSeparator" -> None]` on it directly.

Two gates hold the cells to the rules below; run both before committing a doc
change:

```
python3 dev/check-doc-cells.py           # cell shape: compounds, bundles, bare first use
wl -f dev/run-doc-examples.wls           # evaluates every cell: messages, echoes, hints
wl -f dev/run-doc-examples.wls --write   # ... and rewrites the value hints from the outputs
```

Both take page paths to check just those pages.

## State threads across sections — `EvaluateSeparator -> None`

This is the one rule that **inverts** the upstream skill. `build.wls` builds
every page with `"EvaluateSeparator" -> None`, so the per-heading context reset
is **off**: a parser built in `## Basic Examples` is still bound in
`## Properties and Relations`. Pages may — and the tutorials do — carry one
parser across sections. Do not redundantly rebuild a grammar in each section,
and do not reuse a name for two different parsers across sections (the later
binding wins for the whole notebook). Build a grammar once, then refer back to
it.

## Symbols are autolinked, never bare backticks

Every symbol — **built-in (`StringTake`, `FromDigits`, `Fold`) and paclet
(`Parse`, `ParseChoice`, `ParseOperatorTable`)** — is a link, never a backticked
code word.

- A bare mention is the inferred-link form `[ParseChoice]()` (empty parens; the
  converter resolves it to the ref page). Built-ins take the same form:
  `[Fold]()`, `[StringTake]()`.
- An inline *call* is code-styled **and** autolinked: write
  <code>[Parse]()[*parser*, *input*]</code>, not `` `Parse[parser, input]` `` and
  not plain `[Parse]()`. Markdown forbids nested formatting inside a backtick
  span but processes markdown inside an inline `<code>` element, so the link
  renders inside the code style.
- Backticks are only for things that are *not* symbols: a combinator **type
  tag** (`"Choice"`, `"OperatorTable"`, `"Recursive"`), an **option value**
  (`"ChoiceMode" -> "PEG"`, `"InfixL"`), a **context** (`Wolfram``Parser```), a
  **grammar fragment or literal token** (`<thf_unit_formula>`, `@`, `=>`), or a
  **path** (`Parser/Tests/`).
- If you link a paclet symbol that has no `docs/Symbols/<Name>.md` page,
  **create the page** in the same pass, so the link resolves.
- **The Guide `## Functions` listing — two forms.** The listing's parser makes an
  `InlineGuideFunction` chip (the built-in-style function grid; built-in vs paclet inferred
  from context, no marker needed) *only* from a bullet that **leads with a backtick span**
  (`` - `Parse` the entry point ``). A bullet that leads with the inferred-link form
  (`- [Parse]() the entry point`) instead renders as a plain `GuideText` bullet whose link
  still works — a clean prose index rather than a chip grid. This guide uses the **`[Parse]()`
  prose form** throughout, consistent with the "always autolinked" rule above; keep that form
  here for new entries. Switch a listing to leading backticks only if you specifically want
  the chip grid.

## Argument names are italics, not math

Argument names here are whole words, so write them in *italics*:
<code>[ParseOperatorTable]()[*unit*, *levels*]</code> — **not** the `$x$` math form, which
renders as ugly inline LaTeX. The one case that still needs `$…$` is a genuinely
*subscripted* name (`$v_1$`), because `*v_1*` leaks the underscore and `*v1*` renders the
literal pair `v1`; prefer a plain word to sidestep it. (This narrows the upstream skill's
blanket `$x_i$` rule to "whole words in italics, subscripts in `$…$`". The older pages that
still carry `$p_1$` for whole-word args predate this and should migrate when next touched.)

## Cells: no ceremony, one output each

- **No `Needs`.** MTN loads the package from the frontmatter `Context:`
  (`Context: Wolfram``Parser```) before it evaluates the cells, so an example
  never needs `Needs["Wolfram``Parser```"]`.
- **Show the combinator, not its guts.** A `ParserCombinator` renders as a
  summary box (icon + `Type` / `Arity` / `Compiled`). Where the box aids the
  reader, display the combinator itself rather than extracting
  `combinator[[1]]`.
- **Failures are honest output.** A `Parse` that does not consume all input
  returns `Failure["ParseError", <|"Position" -> …, "Expected" -> …,
  "Found" -> …|>]`. Show the real failure (it round-trips and renders), and in
  prose explain *why* it failed — a mis-ordered [ParseChoice](), leftover input,
  and so on.

## Showing input and output

Adapted from the PureMath documentation rules, minus the reset-boundary rules
that state threading makes moot here.

- **Show what a symbol returns, bare, before anything derived from it.** The
  first cell of a Symbol page that uses its symbol applies it with nothing
  applied to the result: a combinator constructor shows the combinator
  (`ParseMany[ParseCharacter[DigitCharacter]]`, a summary box) before a
  [Parse]() runs it, and a grammar builder shows the grammar it builds. A symbol
  that is a value shows itself (`MarkdownInlineParser`), or, for an algebra whose
  builders would print as a wall of private-context code, its `Keys`.
  Reductions (`Head`, `Length`, `Keys @ Last[...]`, an `=== expected` check)
  come after the raw value, never instead of it.
- **An honest slice for a large output.** Before reducing a big result, show a
  representative piece: `Take[cases, 3]`, `First[tree]`, or the smallest input
  that makes the point (`LambdaAST["\\x.x"]`, not a three-term application).
  A wall of InputForm, such as a box dump or a private-context closure, is shown
  through its summary box or a property instead.
- **One value per cell.** No `a = …; f[a]` compound: the binding is its own
  cell whose output shows the object, and the use follows in the next cell. No
  `{f[a], g[b]}` bundle either: each value gets its own cell and caption. A list
  is the right single output only when the list *is* the showcase, a progression
  of short values. Cells are cheap and state threads, so split freely. A cell of
  delayed definitions (`f[x_] := …`) shows nothing and may group them.
- **Captions say what the output shows.** A binding sits under a sentence naming
  what it makes, and the cell that uses it may follow directly; any other cell
  gets its own lead-in. The prose agrees with the output it describes: check it
  against the evaluated value, not the intent.
- **A side effect with nothing to show ends in `;`, in its own cell**, as an
  `Export` or a `CreateDirectory` does. Its value would be a path under
  `$TemporaryDirectory`, which differs on every machine; write files there
  (`FileNameJoin[{$TemporaryDirectory, "greeting.bnf"}]`), never into the
  working directory. So does a binding whose value would print as private
  implementation, such as an algebra of closures, when the next cell shows what
  it does; a private symbol an output may show is one the page's prose names.
- **A listing is `#| eval: false`.** Code shown for reading rather than running
  (a sketch of generated code, a definition quoted from the source, a call that
  needs software the build machine lacks) is marked so, and the gates skip it.
  A `#| collapse: true` setup cell of helper definitions that shows nothing
  (its last statement ends in `;`) may group them.
- **A message example shows its message.** Never wrap the point of an example
  in [Quiet](); its hint names the message: `<!-- => the message
  GrammarApply::arg1 is issued and the expression returns unevaluated -->`.
  `Quiet` is only for an incidental warning that is not the example's point, and
  then it names that message (`Quiet[expr, Solve::ifun]`).

### Hints

The `<!-- => … -->` comment after a cell is for the reader of the source; the
converter drops it. It holds the output's `ToString[…, InputForm]`, ASCII
encoded so a special character reads `\[Alpha]` or `\:211d`, character for
character, written by evaluating the cell, never from memory: a wrong hint is
worse than none. `dev/run-doc-examples.wls --write` writes them.

- **No hint on an output that renders rather than reads**: a summary box
  ([ParserCombinator](), a recursion cell, [Failure]()), a graphic, a color, a
  link such as a [CloudObject](), a typeset form ([DisplayForm](),
  [TraditionalForm]()), a layout ([Grid](), [Column]()).
- **No hint on a value that varies** between runs (a timing, a random draw, a
  date, a fresh `x$123` temporary), and none needed past 400 characters of
  InputForm.
- **Every short value gets one**: an output whose InputForm fits in 160
  characters carries its hint.

## Output types that round-trip

Strings, numbers, lists, association-free WL terms (`And[p, q]`, `"f"[a, b]`),
`Failure` objects, and `ParserCombinator` summary boxes all serialize and render
in the `.nb`. Typeset math round-trips too — delimited matrices
(`\begin{pmatrix|bmatrix|Bmatrix|vmatrix|Vmatrix}…\end{…}`), stretchy norm/abs bars
(`\|…\|`, `\lVert…\rVert`) around a tall argument, and Dirac kets/bras — which the LaTeX
tutorials lean on. What does **not** round-trip cleanly is a *bare* `Association`
(`<|…|>` with no wrapping head) or an `InputForm[…]` box — project those to a
list/string (`Keys[…]`, `ToString[…, InputForm]`) only when you must.

Examples evaluate in a private per-page context, with the frontmatter contexts on
`$ContextPath`, so a symbol an example creates in `` Global` `` prints qualified.
[TPTPImport]() makes its variables there, and a bare page would show
``"p"[Global`X_]`` where a reader's session shows `"p"[X_]`. A page whose outputs
carry such symbols lists the context in its frontmatter, `` ContextPath: [Global`] ``,
and prints what the reader sees.

## Headless rasterization caveat

A headless `wl` session **cannot rasterize** text or typeset boxes — `Rasterize`
of a `RawBoxes` / `Style` expression comes back all white. `build.wls` pins the
front end to Light so the example outputs that *do* rasterize (LaTeX render
samples in the tutorials) are not inverted. If a page needs to show typeset math
or a box rendering, verify it by exporting a PDF and converting with `sips`, not
by `Rasterize`.

## Page shape

- **Frontmatter**: `Template`, `Name`, `Context`, `Paclet`, `URI` (the `ref/` or
  `tutorial/` path; the basename must match the URI tail), `Keywords`, and — for
  a Symbol page — `SeeAlso` and `RelatedGuides`.
- **Symbol page** (`Template: Symbol`): `## Usage` (the signature, one statement
  per paragraph), `## Details & Options` (bullets become Notes), then
  `## Basic Examples` / `## Scope` / `## Properties and Relations` /
  `## Possible Issues` / `## Neat Examples` as warranted. Model it on
  [Symbols/ParseChoice.md](Symbols/ParseChoice.md) or
  [Symbols/ParseOperatorTable.md](Symbols/ParseOperatorTable.md).
- **Guide page** (`Template: Guide`): a `## Functions` section grouping the paclet's (and
  relevant built-in) symbols into topic subsections, each item a **backtick-led** bullet
  (`` - `Parse` the entry point ``; see the listing exception above). Fill the Tech Notes
  section from a `RelatedTutorials:` frontmatter list and Related Links from `Links:`. Model
  it on [Guides/WolframParser.md](Guides/WolframParser.md).
- **Tutorial** (`Template: TechNote`): one running grammar carried deep across
  sections with real prose, like
  [Tutorials/ParsingTPTP.md](Tutorials/ParsingTPTP.md). Because state threads,
  build the grammar once near the top and extend it section by section.

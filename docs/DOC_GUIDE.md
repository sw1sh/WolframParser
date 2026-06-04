# WolframParser documentation guide

How to write the WolframParser documentation sources under `docs/` — the
`Template: Symbol` reference pages, the `Template: Guide` guide, and the
`Template: TechNote` tutorials. They are literate-markdown files that
[`build.wls`](../build.wls) turns into evaluated Wolfram notebooks via
`MarkdownToNotebook` (MTN), landing under `Parser/Documentation/English/`.
This is the house style. It is adapted from the THVMLink doc guide and
overrides the upstream
[wolfram-symbol-page skill](https://github.com/sw1sh/MarkdownToNotebook/blob/main/skills/wolfram-symbol-page/SKILL.md)
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
wiring. Probe each example against the live paclet first and paste the **real**
result into the `<!-- => ... -->` hint after the cell — a wrong hint is worse
than none. To iterate on one page without rebuilding the whole set, call
`MarkdownToNotebook[src, out, "EvaluateSeparator" -> None]` on it directly.

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

## Argument names are italics, not math

In a `## Usage` signature and in prose, write argument names in *italics*:
<code>[ParseOperatorTable]()[*unit*, *levels*]</code>. **Do not** use the `$x$`
math form — it renders as ugly inline LaTeX. (This overrides the skill, which
uses `$x_i$`. The older pages that still carry `$p_1$` predate this rule and
should migrate when next touched.)

## Cells: no ceremony, one output each

- **No `Needs`.** MTN loads the package from the frontmatter `Context:`
  (`Context: Wolfram``Parser```) before it evaluates the cells, so an example
  never needs `Needs["Wolfram``Parser```"]`.
- **One output per cell.** Never show `{Parse[p, "a"], Parse[p, "b"]}` to save a
  cell — split into two.
- **Show the combinator, not its guts.** A `ParserCombinator` renders as a
  summary box (icon + `Type` / `Arity` / `Compiled`). Where the box aids the
  reader, display the combinator itself rather than extracting
  `combinator[[1]]`.
- **Failures are honest output.** A `Parse` that does not consume all input
  returns `Failure["ParseError", <|"Position" -> …, "Expected" -> …,
  "Found" -> …|>]`. Show the real failure (it round-trips and renders), and in
  prose explain *why* it failed — a mis-ordered [ParseChoice](), leftover input,
  and so on.

## Output types that round-trip

Strings, numbers, lists, association-free WL terms (`And[p, q]`, `"f"[a, b]`),
`Failure` objects, and `ParserCombinator` summary boxes all serialize and render
in the `.nb`. What does **not** round-trip cleanly is a *bare* `Association`
(`<|…|>` with no wrapping head) or an `InputForm[…]` box — project those to a
list/string (`Keys[…]`, `ToString[…, InputForm]`) only when you must.

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
- **Tutorial** (`Template: TechNote`): one running grammar carried deep across
  sections with real prose, like
  [Tutorials/ParsingTPTP.md](Tutorials/ParsingTPTP.md). Because state threads,
  build the grammar once near the top and extend it section by section.

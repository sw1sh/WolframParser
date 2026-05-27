---
Template: TechNote
Name: LaTeXMathParserImplementation
Title: Implementing the LaTeX Math Parser
Context: Wolfram`Parser`LaTeX`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation
Keywords: [LaTeX, math, parser, KaTeX, ParserCombinator, MathML, FractionBox, GridBox, environments, delimiters]
RelatedGuides: [WolframParser]
RelatedTutorials: [DesignAndCompilationStrategy, ParserLandscape]
---

## What this note covers

[`Wolfram\`Parser\`LaTeX\``](paclet:Wolfram/WolframParser/guide/WolframParser) is a working LaTeX math-mode parser built on top of the [ParserCombinator]() core. It parses 126 / 126 of the inline cases from KaTeX's own [screenshot test corpus](https://github.com/KaTeX/KaTeX/blob/main/test/screenshotter/ss_data.yaml) - the same shapes a production JS-side math renderer is expected to handle. This note is the second half of the [`DesignAndCompilationStrategy`](paclet:Wolfram/WolframParser/tutorial/DesignAndCompilationStrategy) story: that one explained the combinator core; this one walks through what it takes to point those primitives at real-world TeX and not flinch.

The interesting part of writing a LaTeX parser is not the grammar - LaTeX math has no grammar in any formal sense. The interesting part is *tolerance*: real TeX users mix balanced and unbalanced constructs, single-character and multi-character delimiters, math-mode and text-mode, optional and required brace arguments, and macros that were defined in someone's `.sty` file 15 years ago and never documented. A parser that demands well-formedness rejects most of the corpus on the first line. A parser that's pure regex-fallback renders the corpus as gibberish.

This note has four parts:

1. **The grammar layers**: how `LaTeXMathParse` is stratified from `atom` up to `outerRow`, and which row each context uses.
2. **The two preprocessing decisions**: when to strip TeX macros before parsing vs. handle them in the grammar.
3. **A tour of the hard cases**: the specific KaTeX inputs that drove specific design choices.
4. **Coverage and limits**: what the parser does, what it doesn't, and how to add to it.

---

## Part 1 - The grammar layers

`LaTeXMathParse` is a [PEG-ordered](https://en.wikipedia.org/wiki/Parsing_expression_grammar) parser. From innermost to outermost the layers are:

| Layer        | Purpose                                          | Defined in [Kernel/LaTeX.wl](paclet:Wolfram/WolframParser/guide/WolframParser) |
|--------------|--------------------------------------------------|--------------------|
| `atom`       | the smallest unit a factor can latch onto        | numbers, identifiers, commands, `(...)`, `[...]`, `|...|`, `{...}`, `\left...\right`, Unicode glyphs |
| `factor`     | atom + a chain of `_` / `^` / `'` postfixes      | `x^2_i'` collapses into one `SubsuperscriptBox` with prime-decorated sup |
| `factorChain`| factors joined by `*`, `/`, `\cdot`, `\times`, or juxtaposition | `2x` and `\sin x` parse the same as `2 * x` |
| `term`       | optional leading sign + factorChain              | `-x^2` parses as a single unary-minus expression |
| `sumExpr`    | terms joined by `+` and `-` (left-associative)   | `a-b-c = (a-b)-c` |
| `expr`       | sumExprs joined by relation operators            | `1 < x \leq 2` chains relations |
| `mathRow`    | comma- / semicolon- / colon-separated expr's     | `(x, y, z)` and function-arg lists |
| `topRow`     | mathRow + line breaks (`\\`, `\cr`) + math toggles (`$`) | what appears inside `{...}`, `(...)`, `[...]`, `\left...\right` |
| `cellRow`    | mathRow + bare closing `)` / `]`                  | what appears inside one matrix cell - tolerates the unbalanced trailers TeX users sprinkle |
| `outerRow`   | topRow + bare closing `)` / `]`                   | the entry point for `LaTeXMathParse[s]`, where `\right)`-stripped trailers can land |

The three "row" variants exist for a reason: each is the same skeleton (`ParseSome[token]`) with a slightly different set of tokens accepted, chosen to make balanced-delimiter parsing still work *inside* a row that tolerates bare delimiters *outside*.

A concrete example: the closing bracket `]` shows up in three different roles in real TeX:

- `[a, b, c]` - balanced bracket group, must pair with a literal `[`
- `\sqrt[3]{x}` - optional argument bracket, must pair with the `[` after `\sqrt`
- `\left( x \right]` - unbalanced delimiter via `\left.../\right`, the `]` is a passthrough

If `]` is a token at the row level used inside `bracketAtom`'s recursive inner row, then `[a, b]` parses `a, b]` as the inner content and `bracketAtom` finds no `]` to close on. If `]` is *not* a token at any level, the `\left./\right]` case bombs out. The split lets `topRow` (used inside delimited groups) refuse `]`, while `outerRow` (entry-point only) and `cellRow` (one matrix cell) accept it.

```
parenAtom = "(" topRow ")"     (* topRow refuses bare ), so ) closes the paren *)
LaTeXMathParser = ws outerRow  (* outerRow accepts bare ) so \right] survives *)
matrixCell = cellRow | ...     (* cellRow accepts bare ) so `3\times)` cells parse *)
```

---

## Part 2 - The two preprocessing decisions

TeX has dozens of "spacing / sizing" macros that *the parser shouldn't see*. Doc-math doesn't care that the user wrote `\bigl(` instead of `(`; the visual size will be picked by the renderer downstream. There are two places to strip them: before parsing (regex preprocess) or inside the grammar (a no-op handler / dedicated atom). Each has consequences.

### Stripped before parsing: `\big` / `\Big` / `\bigg` / `\Bigg` (+ l/r/m variants), `\middle`

These all act as "this delimiter, but visually larger". `\bigl( x \bigr)` is the same content as `( x )` with the renderer asked to make the parens taller. We strip the macro *together with its following delimiter* via regex:

```
\\\\(bigl|bigr|biggl|biggr|...|big|Big|bigg|Bigg)\\s*(\\\\[a-zA-Z]+|\\\\[^a-zA-Z]|[()\\[\\]{}|.])
```

The reason we strip the delimiter too, not just the macro prefix: TeX users *don't* always pair them. `a^{\big| x^{\big(}}` has `\big|` and `\big(` with no matching `\big)`. If the regex stripped just the macro, the leftover `(` would have no matching close and `parenAtom` would back out, failing the whole expression. Stripping both loses the visual big-delim but makes the input parseable.

### Handled by the grammar: `\left` / `\right`

`\left X content \right Y` is different. `\left` and `\right` always come in pairs (TeX requires it), but X and Y are *independent* delimiters - `\left( x \right]` is valid TeX meaning "open with `(`, close with `]`". Stripping `\left`/`\right` and leaving the bare delimiters would break `parenAtom` on this case (it requires matching `()`). So `\left`/`\right` stay in the input, and a dedicated `leftRightAtom` parses the whole thing as one unit:

```
leftRightAtom = "\\left" ws delimMacro ws topRow "\\right" ws delimMacro
```

`delimMacro` accepts any single-token TeX delimiter: `(` `)` `[` `]` `|` `<` `>` `.` (null), `\{` `\}` `\langle` `\rangle` `\lceil` `\rfloor`, the arrows used as vertical extensible delimiters, and so on. `delimGlyph` maps each to the Wolfram glyph that renders it, or `""` for `.` (the explicit null delimiter).

For `\left.` and `\right.`, `delimGlyph["."] = ""`, and the `RowBox` filters empties - so `\left. + a \right)` renders as `+ a )`, exactly the right thing.

### A consequence: commandAtom needs guards

Both decisions force a small wrinkle in `commandAtom`: it can't greedily match the macros the other decisions claim. The full guard list:

```
ParseNotFollowedBy[
    "\\begin" ws "{"                      (* \begin{name} is environmentAtom *)
    | "\\end"   ws "{"                    (* \end{name} is environmentAtom *)
    | "\\cr"    ParseNotFollowedBy[letter]   (* \cr is rowSep, but \crfoo is a user macro *)
    | "\\right" ParseNotFollowedBy[letter]   (* \right is leftRightAtom, but \rightarrow isn't *)
]
```

The `letter` lookahead on `\cr` and `\right` is the same pattern the `\big` regex uses: a word-character boundary so that user macros with similar prefixes (`\crfoo`, `\rightarrow`) still reach `commandAtom`.

---

## Part 3 - A tour of the hard cases

The KaTeX corpus benchmark drove most of the parser's design. Each case below names a real test from `Tests/katex-cases.json`, what was hard about it, and the parser piece that fixed it.

### `Pmb`, `StackRel`: bare operators inside braces

```
\\pmb{=}     \\stackrel{?}{=}     \\textcolor{#0f0}{b}
```

A standard expression doesn't start with `=` or `?` or `#`. But these are legitimate braced-group contents - `\pmb{=}` is the bolded `=` glyph; `\stackrel{?}{=}` is `=` with `?` above it; `\textcolor` uses a hex color in its first argument.

The fix is `puncToken`, an extra alternative inside `mathToken`:

```
puncToken = "?" | "!" | "*" | "#" | "~" | "." | "|" | "/"
          | "+" | "-" | "=" | "<" | ">" | "^" | "_"
          | "`" | "'" | "\""
```

Each character is tried *after* `expr` - so `1 + 2` still parses normally via `addOp` chaining, and `\pmb{=}` parses by fallback when `expr` can't open with `=`. The closing delimiters `)` and `]` are deliberately *not* in `puncToken` so that `parenAtom` / `bracketAtom` recursion stays balanced; they live in `cellPuncToken` and `outerPuncToken` instead.

### `Aligned`, `Cases`: cells starting with a relation

```
\begin{aligned}
    a &= 1 & b &= 2 \\
\end{aligned}
```

After `&` the next cell starts with `=`, which `expr` can't open with (no LHS). `cellLeadingOp` catches the leading relation as a standalone token and lets the rest of the cell parse as a normal `mathRow`:

```
cellLeadingOp = "=" | "+" | "-" | "<" | ">"
              | "\\neq" | "\\leq" | "\\geq" | "\\to" | "\\in" | ...
matrixCell = cellRow | cellLeadingOp ~~ Optional[cellRow] | ""
```

The trick: `cellRow` is tried *first*, not the leading-op form. The first version of this code tried `cellLeadingOp` first, and that broke `\left(...)` cells - because `cellLeadingOp` includes `\le` (= `\leq` alias), which greedily ate the first three characters of `\left` before `leftRightAtom` had a chance.

### `DelimiterSizing`, `SupSubHorizSpacing`: unbalanced `\big*` family

```
a^{\\big| x^{\\big(}}_{\\Big\\uparrow}
```

No matching `\big)` or `\big.` anywhere. The preprocess strip-both rule (Part 2) handles it: `\big|`, `\big(`, `\Big\uparrow` all reduce to the empty string, leaving `a^{ x^{}}_{}` which parses cleanly to a `SubsuperscriptBox`. The visual sizing is lost, but the structure is intact.

### `Tag`, `TextWithMath`: math toggle `$ ... $` inside braces

```
\\tag{$+$hi}     \\text{for $a<b$ and $c<d$}
```

`$` switches between text mode and math mode in TeX. Inside a `\tag` argument, you're in text mode by default, and the `$...$` chunks are inline math. We don't model the text/math distinction (we're a math parser; everything is math), so `$` is a *transparent token* - consume it, emit nothing:

```
dollarToken = ParseAction[literal["$"], "" &]
```

This is in `topToken` (which appears in `topRow`, used inside braces), so `{$+$hi}` parses as the sequence `$` `+` `$` `h` `i` = `+ hi` after the empty `$` tokens are filtered out.

### `OpLimits`, `Substack`: `\substack` and `\\` inside braces

```
\\sum_{\\substack{0<i<m\\\\0<j<n}}
```

`\substack` takes a brace argument with `\\` (row break) inside. Bare `\\` is normally only valid as a matrix row separator. The `linebreakToken` puts it in `topToken`:

```
linebreakToken = ("\\\\" | "\\cr") Optional[bracketed length] ws  ->  ""
```

So `\substack{0<i<m\\0<j<n}` parses as: `\substack` (commandAtom), then a brace arg whose `topRow` contents are `0<i<m` (one expression), `\\` (linebreakToken, emits empty), `0<j<n` (another expression). The result is a `RowBox` of the three pieces - not visually identical to a real `\substack` (which would be a tiny grid), but parseable, which is what matters for the rest of the expression.

### `BoldSymbol`, `LineBreak`: `\\` at the top level

```
x \\\\ y     \\frac{a}{b} \\newline \\frac{c}{d}
```

`\\` at the top level (no surrounding env) is a hint to the renderer to break the line. Same treatment: `linebreakToken` is in `topToken`, so `outerRow` (which contains `topToken`) accepts `\\` and emits empty. The `\newline` macro is a `noopHandler`-registered command that does the same thing.

### `Arrays`: `\left(\begin{array}...\end{array}\\right]`

```
\\left( \\begin{array}{|rl:c||} ... \\end{array}\\right]
```

`\left(` opens, but `\right]` closes with `]` not `)`. `leftRightAtom` handles it: its left and right delimiters are independent, so `(` open and `]` close are both accepted. Renders as `RowBox[{"(", content, "]"}]`.

### `BinCancellation`: cells ending with a bare `)`

```
\\begin{array}{cccc}
    +1 & 1+ & 1+1 & (,) \\\\
    1++1 & 3\\times) & 1+, & \\left(,\\right)
\\end{array}
```

`3\times)` has a `)` with no matching `(`. Inside a normal row, `mulOp` would expect a factor after `\times`, fail, and the cell would stop at `3 \times`. The trailing `)` would then break the matrix because the cell-end expects either `&` or `\\`. `cellPuncToken` puts `)` and `]` into `cellRow` (matrix cells only - kept out of `mathRow` so balanced parens still close).

The cell `\left(,\right)` works for a different reason: `leftRightAtom` matches it as one atom, with content `,` (a `mathToken` comma).

### Non-ASCII math symbols: `\Braket{ \[Phi] | \\frac{\[PartialD]^2}{\[PartialD] t^2} | \[Psi] }`

`\[Phi]` and `\[Psi]` are letters - `identAtom`'s `LetterCharacter` matches them. But `\[PartialD]` is *not* a letter (it's `Sm` mathematical-symbol class), so it falls through. `unicodeAtom` is the fallback:

```
unicodeReservedQ = MemberQ[{" ", "\\", "{", "}", ..., "?", "!", ...}, #] &
unicodeAtom = token[ParseCharacter[_?(! unicodeReservedQ[#] &)]]
```

It matches any single character that *isn't* one of the reserved punctuation characters - so Unicode math symbols, Asian script (`\[Korean]`, `\[Japanese]`), and accented letters that miss `LetterCharacter`'s definition all parse.

---

## Part 4 - Coverage and limits

The benchmark assertion in [`Tests/LaTeX.wlt`](paclet:Wolfram/WolframParser/tutorial/LaTeXMathParserImplementation) loads `Tests/katex-cases.json` directly and asserts the count of cases that parse without error:

```
VerificationTest[
    With[{cases = Association @ Import[FileNameJoin[{DirectoryName[$TestFileName], "katex-cases.json"}]]},
        Count[Values[cases], _?(! MatchQ[LaTeXMathParse[#], _ParseError] &)]
    ],
    126,
    TestID -> "KaTeX corpus: all 126 inline cases parse clean"
]
```

The `126` floor catches any regression that drops a previously-passing case. Raising it after improvements documents the gain in one place.

### What this parser does well

- Standard expressions: sums, products, fractions, sub/sup, primes, square roots, binomials, all the named functions (`\sin`, `\log`, `\lim`, `\limsup`, ...).
- The KaTeX-supported macro vocabulary: `\frac` / `\dfrac` / `\tfrac` / `\cfrac`, `\sqrt[n]{}`, `\stackrel` / `\overset` / `\underset`, `\binom` / `\dbinom` / `\tbinom`, accents (`\hat`, `\vec`, `\widehat`, ...), Greek letters (`\alpha`-`\omega`, capital and lowercase), all the bold-symbol fonts (`\mathbb`, `\mathcal`, `\mathfrak`, `\mathbf`, ...), arrows, set operations, modular notations.
- Matrix environments: `matrix`, `pmatrix`, `bmatrix`, `Bmatrix`, `vmatrix`, `Vmatrix` (and their starred variants); `cases` / `dcases` / `rcases`; `align` / `aligned` / `alignedat`; `equation` / `gather` / `gathered` / `split` / `multline` / `eqnarray`; `array` with column spec.
- Delimiter sizing: `\big*` family stripped together; `\left.../\right...` parsed as a unit with arbitrary delimiter pairs.
- Top-level / brace-content tolerance: `\\` line breaks, `$...$` math toggles, bare `?` `!` `*` `#` `~` `.` and the operators `+` `-` `=` `<` `>` `|` `/` `^` `_` ` `` ` `` `'` `"`.
- Unicode math symbols and exotic letters via `unicodeAtom`.

### Things the parser deliberately doesn't model

- **Spacing accuracy.** TeX's spacing rules (\thinspace, \medspace, the implicit spaces around `\mathop` vs. `\mathrel` vs. `\mathbin`) are dropped. The renderer downstream picks its own spacing.
- **The text/math mode distinction.** `\text{...}` content is parsed as if it were math (with `$...$` toggles silently consumed). Output is approximate for prose with embedded math.
- **Big-delim visual sizing.** `\bigl(`, `\Bigl`, `\biggl`, `\Biggl` and their `r` / `m` siblings all strip together with their delimiter.
- **`\genfrac`'s six-argument `<delim><delim>{thk}{style}{num}{denom}` shape**, `\substack`'s grid layout, `\\` row-break length args (`\\\[1ex\]`) - the input parses but renders as a `RowBox` rather than its specialized box.
- **`\def` / `\newcommand` / `\renewcommand`**: registered as no-ops that consume nothing, so a `\def\foo{...}` followed by `\foo` will see `\foo` as an unknown command.

### Adding a new macro

The dispatch table is in [Kernel/LaTeX.wl](paclet:Wolfram/WolframParser/guide/WolframParser). To add `\foo{a}` rendering as some `Box[a]`:

```
commandHandlers["\\foo"] = Function[{opt, req}, Box[First[req, ""]]]
```

For a macro that takes an optional bracket arg, the first arg `opt` is either the parsed bracket content or `Missing[]`. For purely structural macros that shouldn't render, use `noopHandler`. For "render my argument as-is" macros (`\mathrm`, `\smash`, ...), use `identArgHandler`.

For a macro that takes a non-brace single-token argument (like `\big`, `\not`), prefer the preprocess regex route, since the grammar's `commandAtom` only sees braced args.

---

## What this parser is for

`LaTeXMathParse[s]` returns Wolfram boxes - `FractionBox`, `SubsuperscriptBox`, `RadicalBox`, `GridBox`, `RowBox`, `StyleBox`. These slot directly into a notebook cell or `DisplayForm[...]` for rendering. The downstream `MarkdownToNotebook` workflow routes `$...$` and `$$...$$` math through this parser when it's available, so a markdown source with KaTeX-flavored math compiles to a notebook with proper typeset math - the same path the v0.2 [PAdic](https://resources.wolframcloud.com/PacletRepository/resources/Wolfram/PAdic/) docs use.

The next thing to add is the same treatment for *display-mode* features that aren't in the inline corpus: numbered equations with `\label` / `\ref`, multi-line aligned proofs, the `\boxed`-as-result-frame convention. The infrastructure is in place; what's left is the macro dictionary.

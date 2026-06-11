---
Template: Symbol
Name: LispSymbol
Context: Wolfram`Parser`Languages`Lisp`
Paclet: Wolfram/Parser
URI: Wolfram/Parser/ref/LispSymbol
Keywords: [lisp, symbol, identifier, atom, inert, parser zoo]
SeeAlso: [LispRead, LispAST, LispGrammar, LispSemantic, Symbol]
RelatedGuides: [ParserZoo]
---

## Usage

<code>[LispSymbol]()[*name*]</code> is a read Lisp symbol with name the string *name*.

It is kept distinct from a Wolfram [Symbol]() because Lisp names like `+` or `list->vector` are not Wolfram identifiers.

## Details & Options

- [LispRead]() wraps every Lisp symbol it reads in `LispSymbol`, so a parsed program is plain Wolfram data that a downstream evaluator can walk without name clashes.
- `LispSymbol` is inert: it carries no [DownValues](), so <code>[LispSymbol]()[*name*]</code> stays unevaluated and an applied form like <code>[LispSymbol]()["+"][*x*, *y*]</code> does not compute. Meaning is supplied by whatever evaluator consumes the read data.
- Wrapping the name as a string sidesteps Wolfram's identifier rules: `+`, `-`, `list->vector`, `set!` and `*global*` are all valid Lisp symbols but none is a legal bare Wolfram symbol.
- The quote reader macro reads `'x` to `{`[LispSymbol]()`["quote"], `*x*`}`, so `quote` itself is just another `LispSymbol`.

## Basic Examples

`LispSymbol` holds a name a bare Wolfram symbol cannot:

```wl
LispSymbol["list->vector"]
```

<!-- => LispSymbol["list->vector"] -->

[LispRead]() produces it for every symbol atom:

```wl
LispRead["foo"]
```

<!-- => LispSymbol["foo"] -->

Inside a list, symbols and numbers sit side by side - only the symbols are wrapped:

```wl
LispRead["(+ 1 2)"]
```

<!-- => {LispSymbol["+"], 1, 2} -->

## Properties and Relations

`LispSymbol` has no [DownValues](), so it is inert - applying one does not evaluate:

```wl
DownValues[LispSymbol]
```

<!-- => {} -->

```wl
LispSymbol["+"][1, 2]
```

<!-- => LispSymbol["+"][1, 2] -->

The head a symbol atom reads to is `LispSymbol`, never a Wolfram [Symbol]():

```wl
Head[LispRead["foo"]]
```

<!-- => LispSymbol -->

## Neat Examples

The quote reader macro is just a `LispSymbol["quote"]` cons'd onto the quoted form:

```wl
LispRead["'x"] === {LispSymbol["quote"], LispSymbol["x"]}
```

<!-- => True -->

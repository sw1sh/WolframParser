---
Template: TechNote
Name: ParsingOpenQASM
Context: Wolfram`Parser`Languages`OpenQASM`
ContextPath: [Wolfram`Parser`]
Paclet: Wolfram/Parser
URI: Wolfram/Parser/tutorial/ParsingOpenQASM
Keywords: [OpenQASM, quantum, circuit, parser zoo, combinators, IR, QuantumFramework]
RelatedGuides: [ParserZoo]
---

# Parsing OpenQASM

OpenQASM is the assembly language quantum hardware speaks - the format qiskit
emits and QuantumFramework imports. It is the parser zoo's full-fledged tier: a
real DSL with two dialects, a statement grammar, parametrized and modified
gates, custom gate definitions, and angle expressions. This note builds up the
language a construct at a time, parsing it with [Parse]() combinators into a
neutral *circuit IR* - plain Wolfram data, no QuantumFramework dependency - that
an adapter can turn into a QuantumCircuitOperator.

The two entry points are [OpenQASMRead]() (source to the IR) and [OpenQASMAST]()
(source to the standard syntax tree). Everything below threads one growing
example: a Bell circuit, then its variations.

## The neutral IR

A whole program reads to a single [Association]() with five keys - the version,
the includes, the register declarations, any gate definitions, and an ordered
list of statements:

```wl
OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\nh q[0];\ncx q[0], q[1];"]
```

<!-- => <|"Version" -> 3, "Includes" -> {}, "Registers" -> {<|"Kind" -> "qubit", "Name" -> "q", "Size" -> 2|>}, "GateDefs" -> {}, "Statements" -> {<|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "h", "Params" -> {}, "Qubits" -> {<|"Register" -> "q", "Index" -> 0|>}|>, <|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "cx", "Params" -> {}, "Qubits" -> {<|"Register" -> "q", "Index" -> 0|>, <|"Register" -> "q", "Index" -> 1|>}|>}|> -->

Each gate is a record carrying its name, evaluated parameters, modifiers, and a
list of qubit references. A qubit reference is itself a small Association:
`<|"Register" -> "q", "Index" -> 0|>` for `q[0]`, `<|"Register" -> "q"|>` for a
bare register, `<|"Physical" -> 0|>` for the hardware qubit `$0`.

## One grammar, two dialects

OpenQASM 2.0 and 3.0 differ mostly in how they spell register declarations and
measurement, so a single grammar handles both and lowers them to the same IR. A
declaration production is just an ordered choice over the four spellings:

```wl
#| eval: false
regDecl = ParseChoice[
    ParseAction[kw["qreg"] ~~ identTok ~~ lit["["] ~~ intTok ~~ lit["]"] ~~ lit[";"],
        (alg["Reg"]["qubit", #2, #4]) &],            (* v2: qreg q[2];  *)
    ParseAction[kw["qubit"] ~~ ParseOptional[ParseBetween[lit["["], intTok, lit["]"]]] ~~ identTok ~~ lit[";"],
        (alg["Reg"]["qubit", #3, #2]) &],            (* v3: qubit[2] q; *)
    ...
];
```

Because both branches call the same `alg["Reg"]["qubit", name, size]` builder,
the dialects are indistinguishable downstream. The same Bell circuit in v2 and
v3 produces identical gate statements:

```wl
OpenQASMRead["OPENQASM 2.0;\nqreg q[2];\nh q[0];"]["Statements"] ===
    OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\nh q[0];"]["Statements"]
```

<!-- => True -->

## Gate modifiers and angle expressions

A gate application carries an optional chain of modifiers (`inv @`, `pow(k) @`,
`ctrl @`, `negctrl @`), an optional parenthesized parameter list, and its qubit
arguments. The modifiers parse with a [ParseMany]() of a small choice, and the
parameters run through a precedence grammar over `pi` / `tau` / `euler` built
with [ParseOperatorTable]() - so `rx(pi/2)` evaluates its angle to a real
Wolfram value, while `inv @ pow(2) @` accumulates into the `"Modifiers"` list:

```wl
OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;\ninv @ pow(2) @ rx(pi/2) q[0];"]["Statements"]
```

<!-- => {<|"Type" -> "Gate", "Modifiers" -> {<|"Kind" -> "inv", "Arg" -> Missing[]|>, <|"Kind" -> "pow", "Arg" -> 2|>}, "Name" -> "rx", "Params" -> {Pi/2}, "Qubits" -> {<|"Register" -> "q", "Index" -> 0|>}|>} -->

The angle grammar is deliberately closed: its only identifiers are `pi`, `tau`,
and `euler`, so an injected Wolfram expression simply has no parse and is
refused at the grammar level rather than evaluated.

## Custom gate definitions

A `gate` block names a sub-circuit. Its body is parsed by the very same
statement parser via [ParseRecursive]() (the recursion cell `stmtRef`), so a
definition's body is a list of ordinary gate records, ready to inline:

```wl
OpenQASMRead["OPENQASM 3.0;\ngate bell a, b { h a; cx a, b; }\nqubit[2] q;\nbell q[0], q[1];"]["GateDefs"]
```

<!-- => {<|"Name" -> "bell", "Params" -> {}, "Qubits" -> {"a", "b"}, "Body" -> {<|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "h", "Params" -> {}, "Qubits" -> {<|"Register" -> "a"|>}|>, <|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "cx", "Params" -> {}, "Qubits" -> {<|"Register" -> "a"|>, <|"Register" -> "b"|>}|>}|>} -->

## Measurement and unsupported constructs

The two measurement spellings - v2's <code>measure q -> c</code> and v3's
<code>c = measure q</code> - both normalize to one record naming the measured
qubit and the classical target. And a construct outside the circuit-level subset
(classical control flow, timing, `def`) is recognized by its leading keyword and
captured as an `"Unsupported"` record instead of failing the whole read, so a
mostly-importable file still yields its importable part:

```wl
OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;\nwhile (true) { x q[0]; }"]["Statements"]
```

<!-- => {<|"Type" -> "Unsupported", "Keyword" -> "while"|>} -->

## The standard AST

The same grammar, run over the standard-AST algebra instead, gives the
[ContainerNode]() syntax tree - each statement a [CallNode](), each qubit
reference and keyword a [LeafNode]() - the algebra-free view shared with every
other zoo language:

```wl
Head @ OpenQASMAST["OPENQASM 3.0;\nqubit[2] q;\nh q[0];\ncx q[0], q[1];"]
```

<!-- => ContainerNode -->

## From IR to circuit

The IR is intentionally neutral: it validates *syntax*, not *semantics*. It does
not check gate arities, resolve register offsets to absolute wires, or know that
`cx` is a controlled `X` - those are an importer's job. That separation is the
point: QuantumFramework's importer can map this IR's `"Statements"` to
QuantumOperator elements and assemble a
QuantumCircuitOperator, replacing the
hand-rolled regex scanner it used before with a real grammar - while the parser
itself stays a dependency-free part of the zoo. See the
parser zoo guide for the other
languages and the shared design.

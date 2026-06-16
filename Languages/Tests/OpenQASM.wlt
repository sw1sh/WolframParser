(* :Title: OpenQASM.wlt - OpenQASM 2.0 / 3.0 parser tests *)
(* :Context: Wolfram`Parser`Languages`OpenQASM` *)
(* :Summary: version + register declarations, gate applications with params and
   modifiers, both measure dialects, gate definitions, physical qubits, the
   unsupported-construct fallback, v2/v3 parity, and the standard-AST shape.
   The output is the neutral circuit IR (plain Wolfram data). Run via run-tests.wls. *)

(* === version + registers === *)
VerificationTest[OpenQASMRead["OPENQASM 2.0;\nqreg q[1];"]["Version"], 2,
    TestID -> "qasm: v2 header"]
VerificationTest[OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;"]["Version"], 3,
    TestID -> "qasm: v3 header"]
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\nbit[2] c;"]["Registers"],
    {<|"Kind" -> "qubit", "Name" -> "q", "Size" -> 2|>, <|"Kind" -> "bit", "Name" -> "c", "Size" -> 2|>},
    TestID -> "qasm: v3 qubit/bit register declarations"]
VerificationTest[
    OpenQASMRead["OPENQASM 2.0;\nqreg q[2];\ncreg c[2];"]["Registers"],
    {<|"Kind" -> "qubit", "Name" -> "q", "Size" -> 2|>, <|"Kind" -> "bit", "Name" -> "c", "Size" -> 2|>},
    TestID -> "qasm: v2 qreg/creg map to the same register IR"]

(* === gate applications === *)
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\ncx q[0],q[1];"]["Statements"],
    {<|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "cx", "Params" -> {},
        "Qubits" -> {<|"Register" -> "q", "Index" -> 0|>, <|"Register" -> "q", "Index" -> 1|>}|>},
    TestID -> "qasm: gate application with indexed qubit args"]
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;\nrz(pi/3) q[0];"]["Statements"][[1]]["Params"],
    {Pi/3},
    TestID -> "qasm: parametrized gate evaluates the pi angle expression"]
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\nctrl @ x q[0],q[1];"]["Statements"][[1]]["Modifiers"],
    {<|"Kind" -> "ctrl", "Arg" -> 1|>},
    TestID -> "qasm: ctrl modifier"]
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;\ninv @ pow(2) @ x q[0];"]["Statements"][[1]]["Modifiers"],
    {<|"Kind" -> "inv", "Arg" -> Missing[]|>, <|"Kind" -> "pow", "Arg" -> 2|>},
    TestID -> "qasm: chained inv / pow modifiers"]
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nbit[1] c;\nh $0;"]["Statements"][[1]]["Qubits"],
    {<|"Physical" -> 0|>},
    TestID -> "qasm: physical qubit $0"]

(* === measurement, both dialects, normalize to the same record === *)
VerificationTest[
    OpenQASMRead["OPENQASM 2.0;\nqreg q[1];\ncreg c[1];\nmeasure q[0] -> c[0];"]["Statements"],
    {<|"Type" -> "Measure", "Qubit" -> <|"Register" -> "q", "Index" -> 0|>, "Target" -> <|"Register" -> "c", "Index" -> 0|>|>},
    TestID -> "qasm: v2 measure q -> c"]
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;\nbit[1] c;\nc[0] = measure q[0];"]["Statements"],
    {<|"Type" -> "Measure", "Qubit" -> <|"Register" -> "q", "Index" -> 0|>, "Target" -> <|"Register" -> "c", "Index" -> 0|>|>},
    TestID -> "qasm: v3 c = measure q normalizes to the same record"]

(* === v2 / v3 parity: same gate statements regardless of dialect === *)
VerificationTest[
    OpenQASMRead["OPENQASM 2.0;\nqreg q[2];\nh q[0];\ncx q[0],q[1];"]["Statements"] ===
        OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\nh q[0];\ncx q[0], q[1];"]["Statements"],
    True,
    TestID -> "qasm: v2 and v3 produce identical gate IR"]

(* === gate definitions === *)
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\ngate mygate a, b { h a; cx a, b; }\nqubit[2] q;\nmygate q[0], q[1];"]["GateDefs"],
    {<|"Name" -> "mygate", "Params" -> {}, "Qubits" -> {"a", "b"},
        "Body" -> {
            <|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "h", "Params" -> {}, "Qubits" -> {<|"Register" -> "a"|>}|>,
            <|"Type" -> "Gate", "Modifiers" -> {}, "Name" -> "cx", "Params" -> {}, "Qubits" -> {<|"Register" -> "a"|>, <|"Register" -> "b"|>}|>}|>},
    TestID -> "qasm: gate definition captures params, qubits, and a parsed body"]

(* === reset / barrier / gphase === *)
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[2] q;\nbarrier q;\nreset q[1];\ngphase(pi/4);"]["Statements"],
    {<|"Type" -> "Barrier", "Qubits" -> {<|"Register" -> "q"|>}|>,
     <|"Type" -> "Reset", "Qubits" -> {<|"Register" -> "q", "Index" -> 1|>}|>,
     <|"Type" -> "GPhase", "Modifiers" -> {}, "Param" -> Pi/4, "Qubits" -> {}|>},
    TestID -> "qasm: barrier (whole register), reset, gphase"]

(* === unsupported constructs flagged, not fatal === *)
VerificationTest[
    OpenQASMRead["OPENQASM 3.0;\nqubit[1] q;\nfor int i in [0:2] { h q[0]; }"]["Statements"],
    {<|"Type" -> "Unsupported", "Keyword" -> "for"|>},
    TestID -> "qasm: an unsupported construct parses to an Unsupported record"]

(* === comments are skipped === *)
VerificationTest[
    OpenQASMRead["OPENQASM 3.0; // a line comment\nqubit[1] q; /* block */ x q[0];"]["Statements"][[1]]["Name"],
    "x",
    TestID -> "qasm: // line and /* block */ comments are skipped"]

(* === standard AST === *)
VerificationTest[
    Head @ OpenQASMAST["OPENQASM 3.0;\nqubit[2] q;\nh q[0];\ncx q[0], q[1];"],
    ContainerNode,
    TestID -> "qasm: OpenQASMAST returns a ContainerNode of statements"]

(* === failure === *)
VerificationTest[Head @ OpenQASMRead["OPENQASM 3.0;\n@@@ not qasm"], Failure,
    TestID -> "qasm: unparseable input is a Failure"]

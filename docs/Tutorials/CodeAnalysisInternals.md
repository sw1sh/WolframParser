---
Template: TechNote
Name: CodeAnalysisInternals
Title: Inside CodeAnalysis - How CodeStructure Parses C
Context: Wolfram`Parser`
Paclet: Wolfram/WolframParser
URI: Wolfram/WolframParser/tutorial/CodeAnalysisInternals
Keywords: [CodeAnalysis, CodeStructure, libclang, Clang, LLVM, C parser, AST, LibraryLink, CallGraph, survey]
RelatedGuides: [WolframParser]
RelatedTutorials: [ParserLandscape]
---

**Scope.** This document analyzes `CodeAnalysis` v0.9.6 (`~/Library/Wolfram/Paclets/Repository/CodeAnalysis-MacOSX-ARM64-0.9.6`), the engine behind `ResourceFunction["CodeStructure"]`. It parses **C / C++ / Objective-C** source. It is **not** CodeParser (Wolfram's WL-source parser) and shares no machinery with it; the name collision is purely nominal. CodeAnalysis is a thin Wolfram Language layer over **Clang/LLVM 11** binaries that ship inside the paclet (`libclang.dylib`, `libLLVM.dylib`, `libcodeanalysis.dylib`, plus a `bin/` of gllvm/LLVM executables).

A single overriding fact governs the whole design: there are **two completely separate native engines**, and they never mix.

- **(A) The syntax-tree path** — `CodeStructure[code]` and the `"SyntaxTree"`, `"SyntaxAnnotation"`, `"SourceAnnotation"`, `"TokenAnnotation"` forms, plus `CodeCases` — drives **in-process libclang** through a LibraryLink shim (`libcodeanalysis.dylib`, entry points `ll_parseFileIntoTree` / `ll_getNodeDetails` / `ll_getNodeTypeInformation`). No subprocess is spawned for parsing.
- **(B) The call-graph path** — `CodeStructure[_, "CallGraph"]` / `"FileCallGraph"` — uses **no LibraryLink at all**. It `RunProcess`-shells out to bundled **gllvm/LLVM binaries** (`gclang`, `gclang++`, `get-bc`, `opt`, `llvm-nm`, …) and works off LLVM bitcode/IR, not the Clang AST.

---

## 1. Architecture at a glance

```
                       CodeStructure[...]  (public dispatch head, CodeAnalysis`)
                                 |
        +------------------------+-----------------------------------+
        |  (A) SYNTAX-TREE PATH                                      |  (B) CALL-GRAPH PATH
        |  CodeStructure[code], "SyntaxTree",                        |  "CallGraph" / "FileCallGraph"
        |  "SyntaxAnnotation","SourceAnnotation",                    |
        |  "TokenAnnotation", CodeCases                              |
        v                                                           v
  internalCodeStructure / parseFileIntoTree                  internalCallGraph (CallGraph.wl)
  (ParsingUtilities.wl, CodeStructure.wl)                    NO LibraryLink — pure RunProcess
        |                                                           |
        |  LibraryLink (LibraryInitialization.wl)                   |  RunProcess[$SystemShell, All, ...]
        |   llParseFileIntoTree : {Int,1}->Int                      |
        |   llGetNodeDetails    : {Int,1}->{Int,1} (11)             v
        |   llGetNodeTypeInfo   : {Int,1}->{Int,1}            +------------------------------+
        v                                                     |  BinaryResources/$SystemID/  |
  +--------------------------+                                |  bin/                        |
  | libcodeanalysis.dylib    |  C++ shim, holds the AST       |   gclang / gclang++  (CC/CXX)|
  |  (in-process)            |  as state between calls        |   get-bc   (extract .bc)     |
  +------------+-------------+                                |   opt      (-dot-callgraph)  |
               | links @rpath/libclang.dylib (v11)            |   llvm-nm  (sym -> object)   |
               v                                              +--------------+---------------+
  +--------------------------+   23 clang_* imports,                        |
  | libclang.dylib (LLVM 11) |   0 LLVM imports                             v
  | Clang's PRODUCTION C/C++ |                                    Graphviz .dot  --Import-->  WL Graph
  | parser, exposed as a lib |                                    (post-processed: rename/prune)
  +--------------------------+
```

Key invariants confirmed by `otool -L` / `nm -u`:

- `libcodeanalysis.dylib` links **only** `@rpath/libclang.dylib` (v11.0.0) and `libSystem`. It imports **23 `clang_*` symbols and zero LLVM symbols**. The Clang parser runs inside the loaded LibraryLink dylib, in-process.
- `libLLVM.dylib` is **not** linked by `libcodeanalysis.dylib`. It is a dependency of `libclang` and is used by the bundled `opt`/`gclang` **binaries** on the call-graph path.
- The `bin/` executables (`gclang`, `get-bc`, `opt`, …) are used **only** by `CallGraph.wl`. The AST path never shells out.

The WL package surface is minimal. `CodeAnalysis.wl` opens `BeginPackage["CodeAnalysis`"]`, `Get`s `Initialization.wl`, then `GetOnce`-loads the implementation files (`CodeStructure.wl`, `SyntaxAnnotation.wl`, `SourceAnnotation.wl`, `SyntaxTree.wl`, `CallGraph.wl`, `TokenAnnotation.wl`, `CodeCases.wl`). There is exactly **one public context**, `CodeAnalysis`` (`PacletInfo.wl:6`, `Loading -> Manual`), exporting four symbols: `CodeStructure`, `CodeElement`, `CodeElementToken`, `CodeCases`. `CodeElement`/`CodeElementToken` are inert wrapper heads (no downvalues); behavior lives in `CodeStructure` and `CodeCases`.

---

## 2. The parse pipeline (syntax-tree path), step by step

Every syntax-tree request funnels through one driver. The walk is **stateful** and costs **O(nodes) LibraryLink round-trips**.

1. **String → temp `.c` file → `File[...]` redirection.** `CodeStructure[string_?StringQ, …]` (`CodeStructure.wl:155-197`) calls `createTemporaryFileName[]` (random 15-letter base + `.c` in `$TemporaryDirectory`; `ParsingUtilities.wl:63-93`), does `Export[tmp, string, "String"]`, then re-invokes `CodeStructure[File[tmp], …, "IncludeFilePrefixes"->False]` and `Quiet[DeleteFile[tmp]]` afterward. So **every string ultimately goes through the `File[...]` path**, with a forced `.c` extension (C++ snippets given as strings get `.c` unless `CommandLineArguments` override the language) and a forced `IncludeFilePrefixes->False` that overrides the user's value on this path.

2. **One-arg dispatch.** `CodeStructure[arg, opts]` (`CodeStructure.wl:206-217`) calls `internalCodeStructure[arg, False, opts]` — the second positional argument is the **node-callback function**, and `False` means "use the plain builder." `internalCodeStructure[File[fileName], nodeCallback, opts]` (`CodeStructure.wl:52-139`) reads options `CommandLineArguments`/`IncludeTypeInformation`/`IncludeNodeText` (defaults `{}`, `False`, `False` at lines 40-42), runs `checkLibraryFunctions[]`, then `parseFileIntoTree`, then `buildCodeElementTree[sourceFileAssociation, {}, nodeCallback]` — the `{}` is the root node location.

3. **LibraryLink loading and guard.** `LibraryInitialization.wl` prepends `BinaryResources/$SystemID/lib` to `$LibraryPath`, finds `libcodeanalysis` via `FindLibrary`, and `LibraryFunctionLoad`s the three entry points: `ll_parseFileIntoTree → llParseFileIntoTree` (`{Integer,1}->Integer`), `ll_getNodeDetails → llGetNodeDetails` (`{Integer,1}->{Integer,1}`), `ll_getNodeTypeInformation → llGetNodeTypeInformation`. `llGetNodeDetailsResultLength` is hard-coded to **11** (line 126). On Windows it also preloads `libclang`. `checkLibraryFunctions[]` (lines 147-159) returns `$Failed` (surfacing `CodeStructure::libraryerror`) if any of the three handles failed.

4. **The single parse call (in-process libclang).** `parseFileIntoTree` (`ParsingUtilities.wl:100-213`) `ExpandFileName`s the path; validates it is printable-ASCII and an existing `File`; validates `CommandLineArguments` is a list of printable-ASCII strings; validates `IncludeTypeInformation` is Boolean and `IncludeNodeText` is `False`-or-string. It builds `libraryLinkArgument = Join[{expandedFileName}, commandLineArguments]`, `Map`s `ToCharacterCode`, `Riffle`s a `0` (NUL) separator between strings (`Riffle[…, 0, {2,-1,2}]`), and `Flatten`s into **one flat Integer list**. Then `size = llParseFileIntoTree[libraryLinkArgument]` — **the single LibraryLink call that runs Clang in-process**. It returns only the **tree node count**; `size < 0` ⇒ `CodeStructure::parsefailed`. The CommandLineArguments are exactly the `argv` handed to `clang_parseTranslationUnit`.

5. **The handoff record.** The AST itself is **not** serialized to WL. It is retained as C++ state inside `libcodeanalysis.dylib`. `parseFileIntoTree` returns a small association `sourceFileAssociation = <|"SourceString" -> Import[expandedFileName,"String"], "IncludeTypeInformation" -> …, "IncludeNodeText" -> …, "ParseIdentifier" -> createRandomString[15], "TreeSize" -> size|>`. `SourceString` is re-imported from disk so node text can be sliced by byte offset; `ParseIdentifier` names a per-parse `Dynamic` symbol for hover highlighting; `TreeSize` gates whether `Dynamic`s are enabled (`< 300`).

6. **Stateful per-node walk via positional paths.** `buildCodeElementTree[sourceFileAssoc, nodeLocation, callback]` (`TreeBuildingUtilities.wl:46-136`) addresses each AST node by an **integer-list path** of child indices (root = `{}`, child *i* = `Append[nodeLocation, i]`). `getNodeAssociation` (`NodeUtilities.wl:53-104`) calls `llGetNodeDetails[nodeLocation]`, expecting **exactly 11 integers**, decoded positionally (see §4); if `IncludeTypeInformation`, it also calls `llGetNodeTypeInformation[nodeLocation]` and `FromCharacterCode`s the result into a `TypeInformation` string. For a non-token node it recurses over children `0 .. ChildrenWithTokensNumber-1`. **Node lookups are positional re-queries into the C++-held AST, not a one-shot dump.**

7. **CodeElement tree.** Each node becomes a `CodeElement[...]` or `CodeElementToken[...]` via the builder pattern (see §4). When `callback === False`, `getCodeElementFromBuilder` materializes the literal expression; otherwise `callback[builder, sourceFileAssoc, nodeAssoc]` is invoked bottom-up to produce a form-specific element (see §5).

**Statefulness consequences.** Because only the most-recently-parsed tree is addressable, the API is effectively single-tenant: you cannot hold two ASTs at once, and the WL walk is one `llGetNodeDetails` native round-trip per node addressed by an ever-growing index list, with deep WL recursion. `SyntaxAnnotation`/`SourceAnnotation` impose practical caps (highlighting disabled above 300 nodes; `SourceAnnotation` truncates to the first 1000 source lines).

---

## 3. The parsing primitives — Clang's own parser, exposed

This is the heart of the matter: **CodeAnalysis does not implement a C/C++ grammar. It exposes Clang's production parser as a library.** `libcodeanalysis.dylib` is a thin C++ shim that calls the **libclang C API** in-process. Confirmed by `nm -u`: 23 `clang_*` undefined imports, 0 LLVM imports. The libclang functions doing the real work:

**Parse / translation unit**
- `clang_createIndex` / `clang_disposeIndex`
- `clang_parseTranslationUnit` — **the parse** (CommandLineArguments are its `argv`)
- `clang_getTranslationUnitCursor` — the root cursor (becomes node `TranslationUnit`, kind 300)
- `clang_Cursor_getTranslationUnit`, `clang_hashCursor`

**AST traversal & node classification**
- `clang_visitChildren` — the AST walk
- `clang_getCursorKind` — `CXCursorKind` → node type
- `clang_getCursorType` + `clang_getTypeSpelling` — `IncludeTypeInformation` payload
- `clang_getCursorExtent` — the cursor's source range

**Lexer / tokenization**
- `clang_tokenize` + `clang_disposeTokens` — raw token stream
- `clang_annotateTokens` — attaches each token to its spanning cursor (token↔AST unification, so `CodeElementToken` leaves slot under the right structural `CodeElement` in one source-ordered tree)
- `clang_getTokenKind` — `CXTokenKind` (Keyword/Identifier/Literal/Punctuation/Comment)
- `clang_getTokenExtent`

**Source locations → byte ranges**
- `clang_getRangeStart` / `clang_getRangeEnd`, `clang_Range_isNull`
- `clang_getSpellingLocation` — line/column and the **byte offset** that becomes `SourceRange`
- `clang_getCString` / `clang_disposeString`

The internal C helpers in the shim (`parseFileIntoTree`, `tokenizeTreeElement`, `addAllSubordinateTokens`, `addTokenTreeElements`, `addTokensToChildren`, `copyTokenInformation`) exist to merge the structural cursor tree with the token stream into the single integer-indexed tree the WL side walks.

**Version pinning.** libclang is **v11.0.0**. Language coverage and the `CXCursorKind`/`CXTokenKind` taxonomy are exactly what Clang 11 supports — newer C++ standards or attributes are out of reach, and the enum-to-string maps (§4) top out where Clang 11's enums do.

---

## 4. Node & token data model

The flat native record per node (from `llGetNodeDetails`, length 11) is decoded positionally in `getNodeAssociation` (`NodeUtilities.wl:39-104`):

```
{ IsToken(0/1), TokenKind, Kind, Type, ChildrenWithTokensNumber,
  Location1=startLine, Location2=startCol, Location3=endLine,
  Location4=endCol,    Location5=startOffset, Location6=endOffset }
```

`Location5/Location6` are **clang byte offsets** (from `clang_getSpellingLocation`). `SourceRange` in the emitted expression is exactly `{Location5, Location6}`. Note `Type` (`d[[4]]`) is read but **never used** downstream — type info instead comes from the separate `llGetNodeTypeInformation` string.

**Builder pattern → two output heads** (`NodeUtilities.wl:113-245`). `createCodeElementBuilder` yields a mutable `<|"Head"->…, "FirstArgument"->…, "SecondArgument"->…, "Options"->{}|>`. `convertToCodeElement` prepends `"SourceRange"->{Location5,Location6}` to `Options`, then dispatches:

- **`CodeElement[{children…}, kindString, opts…]`** — a non-token node (`convertNode`). Arg1 = list of child elements; Arg2 = `kindsToStrings[Kind]`; opts always include `"SourceRange"`, optionally `"TypeInformation"->str` (CodeElement only), optionally `"NodeText"->str`.
- **`CodeElementToken[tokenText, classString, opts…]`** — a leaf token (`convertToken`). Arg1 = source text via `getNodeText`; Arg2 = `tokenKindsToStrings[TokenKind]`; opts always include `"SourceRange"`, optionally `"NodeText"`. Tokens never carry `TypeInformation`.

`getNodeText` does `StringTake[SourceString, {Location5+1, Location6}]` (1-based WL char indices vs. clang's 0-based byte offset, hence `+1`). It is wrapped in `Quiet`; an invalid range yields `$Failed`/`""` and the option is simply omitted.

**Where the taxonomies come from.** Two static associations in `NodeInitialization.wl` map clang's integer enums to strings:

- **Token classes (5, from `CXTokenKind`)**: `0->Punctuation, 1->Keyword, 2->Identifier, 3->Literal, 4->Comment`.
- **Node types (~190, from `CXCursorKind`)**: `kindsToStrings` (`NodeInitialization.wl:46+`). Examples — Decls: `StructDecl(2)`, `FunctionDecl(8)`, `VarDecl(9)`, `ParmDecl`, `CXXMethod`, `Namespace`, `Constructor`, `FunctionTemplate`, plus the full `ObjC*Decl` family. Expressions (100–152): `CallExpr`, `IntegerLiteral(106)`, `BinaryOperator(114)`, `CStyleCastExpr`, `CXXNewExpr`, `LambdaExpr`, etc. Statements (200–231): `CompoundStmt(202)`, `IfStmt`, `ForStmt`, `ReturnStmt(214)`, `CXXTryStmt`. OpenMP directives (232–292). `TranslationUnit = 300` (root). Attributes (400–441). Preprocessing (500–503: `MacroDefinition`, `InclusionDirective`, …). Other (600–700: `StaticAssert`, `FriendDecl`, …).

**Data-model gotchas.**
- `SourceRange` is in **byte offsets** but `getNodeText` slices the WL string by **character index**. For pure-ASCII C these coincide; UTF-8 multibyte source would misalign `NodeText`/`SourceRange`. The paclet restricts only the *filename* and *command-line args* to `PrintableASCIIQ`, **not file contents**.
- `kindsToStrings` has **duplicate integer keys** (`40->FirstRef` and `40->ObjCSuperClassRef`; likewise 70, 100, 200, 400). Association keeps the **last** rule, so e.g. Kind 40 resolves to `ObjCSuperClassRef` and the `First*` alias names are unreachable as outputs.
- A `Kind`/`TokenKind` absent from the maps makes `convertNode`/`convertToken` `Return[$Failed]`, which propagates as `CodeStructure::miscerror`. Maps top out at 700; clang-11-and-beyond kinds beyond what's enumerated fail.

---

## 5. Output forms

All four visualization forms share the driver in §2. They differ only in (a) the per-node callback and (b) the final assembly. None returns a `Tree`, `Dataset`, or a literal `CodeElement[...]` expression — the literal tree appears **only** on the plain `CodeStructure[arg]` path (`callback === False`).

| Form | Returned head | Callback / assembly |
|---|---|---|
| `"SyntaxTree"` | **`Graph`** | `syntaxTreeNodeFunction` (`SyntaxTree.wl:94`) rebuilds the tree as a nested **string-headed** expression `label[child…]` (label = kind, optionally `… \| … <> TypeInformation`); empty nodes dropped via `Nothing`. `toGraph` (line 51) numbers vertices, builds `UndirectedEdge`s, returns `Graph[edges, GraphLayout->{"LayeredEmbedding", "RootVertex"->…}, VertexLabels->Placed[Framed[Style[…]], Center], …]`. A laid-out parse-tree diagram. |
| `"SyntaxAnnotation"` | **`RawBoxes`** | `syntaxAnnotationNodeFunction` (`:310`) returns `{boxes, tokenLocations, {startLine,endLine}}`; lays children into `GridBox`es (single-line vs `SplitBy`-line multi-line with a rotated kind label) with `EventHandler[…,{"MouseEntered","MouseExited"}]` hover. Finishes `RawBoxes[ToBoxes[DisplayForm[…]]]`. Interactive only when `TreeSize < 300` (`maximumTreeSizeForDynamics`); above that, static Courier styling. |
| `"TokenAnnotation"` | **`RawBoxes`** | `tokenAnnotationNodeFunction` (`:39`) returns per token `{GridBox[{{Style[text,Courier]},{Style[kind,"TextElementLabel"]}}], startLine, endLine}`; non-tokens pass children through, so recursion flattens to a token stream. `internalTokenAnnotation` `Flatten`/`Partition[…,3]`/`SplitBy[…,Rest]` groups tokens by line range into `GridBox` rows. A token-by-token strip with lexical-kind labels. |
| `"SourceAnnotation"` | **`Graphics`** | **Stateful** callback `sourceAnnotationNodeFunction` (`:95`) returns nothing — it `AppendTo`s `{label, Location1..4}` into module-scoped `horizontal`/`vertical` lists (single-line vs multi-line spans). `internalSourceAnnotation` comments out `#include` lines, caps at **1000 lines**, writes a **second temp file**, re-parses, then hand-builds `Graphics[…, PlotRange->All, ImageSize->{All, yLength}]`: source text as `Text`, each span as `Tooltip[Line[{Offset[…],Offset[…]}], label]`, plus `Dynamic` yellow highlight `Rectangle`s. |

**`SourceAnnotation`'s Rasterize dependency (important caveat).** It measures monospace glyph widths via `length[n] = ImageDimensions[Rasterize[Text[Style[…, Courier, 13]]]][[1]]` (`SourceAnnotation.wl:66`). Per the environment's known limitation, `Rasterize` of text is all-white under headless `wl`, so this form's geometry/output is unreliable outside the front end. It is also the only stateful, side-effecting callback of the four (it resets `horizontal`/`vertical` to `{}` at the end), and silently truncates input (`#include` stripping + 1000-line cap).

Both `RawBoxes` forms wrap their `GridBox` in `RawBoxes[ToBoxes[DisplayForm[…]]]` — pre-typeset boxes, not re-evaluable expressions. Per-parse hover state is keyed on a dynamically built global symbol `CodeAnalysis`Private`<ParseIdentifier>IxACTIVATEDTOKENLOCATIONS`.

---

## 6. The CallGraph / LLVM-IR subsystem

Entirely separate from libclang. Implemented in `CallGraph.wl` (the largest Kernel file) by shelling out to a bundled **whole-program-LLVM (gllvm/WLLVM)** toolchain. Call edges come from **LLVM IR**, not the Clang AST. `CodeStructure[arg,"CallGraph"]` routes to `internalCallGraph[arg, False]`; `"FileCallGraph"` to `internalCallGraph[arg, True]` (`CallGraph.wl:1239-1265`).

**Pipeline.**
1. **Build to bitcode (gclang).** `internalCallGraph` sets `buildEnvironmentVariables` to `export CC=<gclang>; export CXX=<gclang++>; export PATH=…;` (lines 950-963) and builds via CMake (lines 968-1009), Make (1011-1027), or — for a bare set of `.c` files — a direct `gclang -c <sources>; gclang *.o -shared -o .codeanalysis-binary` (1042-1062). `gclang`/`gclang++` are gllvm clang wrappers: each compile emits a native `.o` that **also embeds the LLVM bitcode**. Captured in `CodeAnalysis`$BuildError`.
2. **Extract whole-program bitcode (get-bc).** `extractBitcode` (`:84-110`) runs `<get-bc> <BinaryLocation>`, linking the embedded bitcode into a single `<BinaryLocation>.bc`. Captured in `CodeAnalysis`$ExtractError`.
3. **Emit raw call graph (opt).** `generateRawCallGraph` (`:112-173`) runs `<opt> <BinaryLocation>.bc -analyze -dot-callgraph` (LLVM 11's legacy-PassManager analysis; `--basiccg` "CallGraph Construction" + `--dot-callgraph`), `FileNames["*.dot", …]`, then `Import`s the Graphviz `.dot` into a WL `Graph`. Captured in `CodeAnalysis`$OptError`. If no `.dot` appears: `CodeStructure::nobin` / `::miscerror`.
4. **Map IR nodes → functions → files.** Raw vertices are opaque `Node0x<hex>` ids with a function name in `VertexLabels`. `processRawCallGraph` (`:528`) builds `functionNamesToObjectFiles` by scanning every `.o` with `getFunctionsInObjectFile` → `llvm-nm --extern-only --defined-only` (`:175-254`), stripping the leading underscore on macOS (`objectFileFunctionStringDropCount=1`). `VertexReplace` renames each `Node0x` vertex to its function name.
5. **Prune.** `verticesToDrop` (`:600-614`) always drops functions whose names start with `_` (compiler/runtime internals) and — when **`DropExternalFunctions`** is `True` (default) — any function not defined in the project (libc, library calls). `VertexDelete` removes them, so the graph is **project-internal by default**.

**CallGraph vs FileCallGraph** (branch on the boolean at `:623`):
- **CallGraph** (function-level): `Graph[functions, function→function DirectedEdges, VertexLabels -> (fn -> "objectfile:fn" when `IncludeFilePrefixes`, else "fn")]`.
- **FileCallGraph** (file-level): `EdgeTaggedGraph` whose vertices are object-file basenames and each edge `callingFile → calledFile` is tagged by the called function (`generateFileCallGraphEdges`, `:422-526`). When **`ShowFunctionCount`** is `True`, edges are `CountsBy`-counted on `{callingFile, calledFunction}`, bucketed into 6 strata via an `EmpiricalDistribution` CDF, and `Style`d by `GrayLevel`/`Thickness` (labels read `"calledFunction (N)"`). `ShowFunctionCount` affects **only** the file-level output.

**Inputs & escape hatch.** `internalCallGraph` accepts `File[directory]`, a list of `File[...]` (copied into a fresh `CreateDirectory[]` temp dir), or a single `File[file]`. `Recursive` controls `FileNames` depth for `*.c`. **`NoPostProcessing->True`** returns the raw `Node0x`-vertex graph, skipping rename/prune.

**Error channels.** `CodeAnalysis`$BuildError` / `$OptError` / `$ExtractError` each hold the **full `RunProcess[…, All]` association** (`ExitCode`/`StandardOutput`/`StandardError`) for the build, opt, and get-bc stages respectively. `CodeStructure::nobin` explicitly directs the user to inspect these three symbols. They are global symbols in `CodeAnalysis`` but are not pre-declared — they materialize after a call-graph build runs.

**Hard constraints.** **Windows is unsupported** (`CodeStructure::windowscallgraph`, `:831-835`; shipped binaries are macOS Mach-O). CMake/Make builds **require** the `BinaryLocation` option (`CodeStructure::nobinoption`, `:912-923`) because the artifact can't be inferred; only the bare-`.c` path auto-sets `.codeanalysis-binary`. `get-bc`/`gclang` are gllvm (Go binaries — "Go build ID" in the Mach-O header) and **require the project to actually be (re)built** so bitcode gets embedded; a prebuilt binary without embedded bitcode yields no `.bc`. `opt -dot-callgraph` is a legacy pass that newer LLVM removed/renamed — the LLVM 11 binary is the pinned implementation.

---

## 7. Options & error channels

**Options (`CodeStructure` / `CodeCases`):**

| Option | Default | Path | Behavior |
|---|---|---|---|
| `CommandLineArguments` | `{}` | AST | Passed verbatim as `argv` to `clang_parseTranslationUnit` (set language/std/includes). Must be printable ASCII. |
| `IncludeTypeInformation` | `False` | AST | Adds a per-node `llGetNodeTypeInformation` call; emits `"TypeInformation"->str` on `CodeElement`s. |
| `IncludeNodeText` | `False` | AST | **Value-matched, not Boolean.** `"NodeText"` is attached only when `sourceFileAssociation["IncludeNodeText"] === SecondArgument` (the node's kind string). Passing `True` attaches nothing; pass a *kind string* to select which kind gets text. This is the hook `CodeCases` exploits. |
| `IncludeFilePrefixes` | `True` (CallGraph) | both | Prefixes vertex labels with `objectfile:`; forced `False` on the string→temp-file AST path. |
| `Recursive` | `False` | CallGraph | `FileNames` depth for `*.c`. |
| `NoPostProcessing` | `False` | CallGraph | Return raw `.dot` graph (`Node0x` vertices), skip rename/prune. |
| `DropExternalFunctions` | `True` | CallGraph | Drop functions not defined in the project. |
| `BinaryLocation` | `""` | CallGraph | **Required** for CMake/Make builds. |
| `ShowFunctionCount` | `False` | CallGraph | Style FileCallGraph edges by call frequency (file-level only). |
| `ClangBinariesDirectory` | `""` | CallGraph | Extra `PATH` entry for the build. |
| `ShellProlog` | `""` | CallGraph | Prepended to the build shell command. |

**Error / message tags** (all return `$Failed`; declared in `MessageInitialization.wl:28-37`):

| Tag | Trigger |
|---|---|
| `CodeStructure::parsefailed` | `llParseFileIntoTree` returned `size < 0`. |
| `CodeStructure::libraryerror` | Any of the three `ll_*` LibraryLink handles failed to load. |
| `CodeStructure::miscerror` | A `Kind`/`TokenKind` missing from the maps (propagated `$Failed`), or no `.dot`. |
| `CodeStructure::invalidarg` | Bad argument. (**Same message object** as `CodeCases::invalidarg`, `:33`.) |
| `CodeStructure::invalidoption` | Bad option value. |
| `CodeStructure::invalidformat` | Unknown format string (string fallthrough in `CodeAnalysis.wl:45-51`). |
| `CodeStructure::windowscallgraph` | CallGraph invoked on Windows. |
| `CodeStructure::nobinoption` | CMake/Make build without `BinaryLocation`. |
| `CodeStructure::nobin` | Expected binary/`.dot` missing — points the user at `$BuildError`/`$OptError`/`$ExtractError`. |
| `CodeStructure::nofiles` | No source files found. |

Several messages referenced in comments (`formatnotfound`, `elementlimit`, `nonodes`, `nomake`, `notools`, **`CodeCases::nocase`**) are **commented out / inactive**. Notably, because `CodeCases::nocase` is inactive, a misspelled case string silently yields `{}` with no diagnostic.

**`CodeCases` (the query layer).** `CodeCases[arg, case_String, opts]` (`CodeCases.wl:32-64`): rejects non-string `case` (`$Failed`); builds `tree = CodeStructure[arg, "IncludeNodeText"->case, opts]`; harvests `Cases[tree, (CodeElement|CodeElementToken)[_, case, ___, "NodeText"->t_, ___] -> t, Infinity]`. The filter is the kind string in the **second-argument slot** plus the presence of a `"NodeText"` rule — a **node-type filter at level `Infinity`**, not a numeric level spec and not a WL pattern. It returns **only the node-text substrings**, never the `CodeElement` expressions. To get subtrees, call `CodeStructure` and `Cases` yourself.

---

## 8. Implications for a parser-library survey

If the goal is a Wolfram parser-combinator library, here is the honest accounting of what CodeAnalysis offers as reusable *primitive* versus what is a closed black box.

**What is genuinely reusable as a primitive (but only as-is):**
- **Clang-as-a-library for C/C++/ObjC.** The single most valuable thing here is the demonstration that a *production* parser (libclang) can be driven in-process from WL via a LibraryLink shim with a tiny ABI: one `parse` call returning a count, plus stateful per-node accessors. If you need an industrial C/C++/ObjC front end, this is the right primitive — Clang's own parser, fully standard-conformant for C++ up to what Clang 11 supports, with locations, types, and token↔AST unification for free. You would not reimplement this in a combinator library.
- **LLVM-as-binaries for IR analysis.** The call-graph path is a clean template for "compile to bitcode, run `opt` analyses, import Graphviz." Reusable for any IR-level static analysis, independent of any parser you write.

**What is a closed, single-language, externally-backed black box (not reusable as parsing infrastructure):**
- It parses **only C/C++/ObjC**, via an **external engine you don't control**. There is no grammar to compose, extend, or retarget — `CommandLineArguments` tweak Clang's flags, nothing more. You cannot point this at a new language, add a production, or get a partial/error-tolerant parse beyond what Clang offers.
- The WL-side machinery (`CodeElement`/`CodeElementToken`, the builder, `buildCodeElementTree`, the kind-string maps) is **adaptor glue tightly coupled to libclang's enums and integer-array ABI**, not a general tree/parsing abstraction. The `kindsToStrings` map even has unreachable duplicate keys. None of it generalizes to a combinator framework.
- The API is **in-process but stateful and single-tree**: only the most-recently-parsed AST is walkable, and walking it is **O(nodes) LibraryLink round-trips** with deep WL recursion. That is the opposite of what you want from a reusable parser primitive (you want the full parse result handed back once). A combinator library would return an immutable tree in one shot.
- **Hard operational constraints**: ASCII-only file paths and command-line args (source *content* goes straight to libclang, but byte-offset vs. character-index slicing of `NodeText` silently misaligns on UTF-8 multibyte source); `libclang` **pinned to v11**; `opt -dot-callgraph` pinned to the bundled LLVM 11 (the pass was later removed/renamed); the call-graph path is **macOS-only** and requires a real (re)build for bitcode embedding. No retargeting, no version flexibility.

**Comparison to CodeParser (WL-source).** They are architecturally opposite, and the contrast is instructive:
- **CodeParser** is a *bespoke parser* for *one language Wolfram controls* (WL). It returns a complete, re-evaluable concrete syntax tree as WL expressions in a single pass, is cross-platform, error-tolerant by design, and version-coupled to the WL it parses. It is the natural reference point and arguably the better *model* for a from-scratch WL parser library.
- **CodeAnalysis** is a *thin binding* to a *foreign, externally-maintained parser* (Clang) for languages Wolfram does not control. It buys instant, fully-conformant C/C++/ObjC coverage at the cost of being a closed, stateful, single-tree, version-pinned, ASCII-path-restricted, platform-limited black box.

**Bottom line for the survey.** Treat CodeAnalysis as **two reusable engine bindings — "Clang for C-family parsing" and "LLVM `opt` for IR analysis" — wrapped in non-reusable adaptor glue.** If you are building a Wolfram parser-combinator library, there is essentially nothing here to borrow at the *combinator* or *grammar* level; the lesson is the integration pattern (LibraryLink shim over a production parser, or RunProcess over compiler binaries) and the explicit demonstration that for C/C++ the sane answer is "bind Clang," not "write a grammar." For everything CodeParser already covers (WL), CodeParser is the model; for C-family languages, CodeAnalysis's libclang binding is the primitive to wrap, not to reproduce.

---

**Primary source files** (all under `~/Library/Wolfram/Paclets/Repository/CodeAnalysis-MacOSX-ARM64-0.9.6/`):
- `Kernel/CodeStructure.wl`, `ParsingUtilities.wl`, `LibraryInitialization.wl`, `TreeBuildingUtilities.wl`, `NodeUtilities.wl`, `NodeInitialization.wl`
- `Kernel/SyntaxTree.wl`, `SyntaxAnnotation.wl`, `SourceAnnotation.wl`, `TokenAnnotation.wl`
- `Kernel/CallGraph.wl`, `CodeCases.wl`, `CodeAnalysis.wl`, `Initialization.wl`, `MessageInitialization.wl`, `PacletInfo.wl`
- `BinaryResources/MacOSX-ARM64/lib/{libcodeanalysis.dylib, libclang.dylib, libLLVM.dylib}` and `bin/{gclang, gclang++, get-bc, opt, llvm-nm, llvm-link, llvm-ar}`

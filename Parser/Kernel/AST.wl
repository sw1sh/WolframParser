(* ::Package:: *)

(* :Title: AST.wl - the standard syntax-tree vocabulary for the parser zoo *)
(* :Context: Wolfram`Parser` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    A small, language-neutral node vocabulary modelled on Wolfram's own
    code-parse output (the CodeParser paclet): LeafNode / CallNode /
    BinaryNode / InfixNode / PrefixNode / PostfixNode / TernaryNode /
    GroupNode / ContainerNode, every node a 3-slot
    Head[descriptor, children, <|meta|>] triple just like CodeParser.

    The difference from CodeParser is deliberate: operator descriptors stay
    language-native strings ("+", ":=", "->") instead of being forced into
    Wolfram symbols (Plus, SetDelayed, Rule), so the SAME vocabulary serves
    a calculator, JSON, lambda calculus, Brainfuck and C alike. ToCodeParser
    maps a neutral tree onto CodeParser`-exact nodes for Wolfram-like grammars.

    THE DESIGN (what this whole directory battle-tests): a grammar is written
    ONCE over an abstract ALGEBRA - an Association of builder functions its
    semantic actions call (alg["Binary"][op, l, r], alg["Leaf"][kind, src], ...).
    Feed the grammar `ASTAlgebra` and it emits the standard syntax tree below;
    feed it the language's own semantic algebra and the same grammar yields a
    meaningful value (a number, a WL expression, a run result). That is exactly
    "meaningful language-specific parse actions, but without which a standard
    AST" - the actions are swapped, the grammar is untouched.
*)

BeginPackage["Wolfram`Parser`"]

LeafNode::usage      = "LeafNode[kind, source, <|meta|>] is a terminal. kind is a descriptor string (\"Integer\", \"Real\", \"String\", \"Symbol\", \"Token\", ...); source is the matched text."
CallNode::usage      = "CallNode[head, {args...}, <|meta|>] is an application / call; head is itself a node (usually a LeafNode)."
PrefixNode::usage    = "PrefixNode[op, operand, <|meta|>] is a prefix-operator application; op is an operator descriptor."
PostfixNode::usage   = "PostfixNode[operand, op, <|meta|>] is a postfix-operator application."
BinaryNode::usage    = "BinaryNode[op, {lhs, rhs}, <|meta|>] is a binary-operator application."
InfixNode::usage     = "InfixNode[op, {children...}, <|meta|>] is a flat n-ary operator chain (a+b+c -> one node)."
TernaryNode::usage   = "TernaryNode[op, {a, b, c}, <|meta|>] is a ternary-operator application."
GroupNode::usage     = "GroupNode[kind, {children...}, <|meta|>] is a delimited group; kind is \"Paren\", \"Square\", \"Curly\", \"Object\", \"Array\", ..."
ContainerNode::usage = "ContainerNode[kind, {children...}, <|meta|>] is the root node wrapping every top-level form, mirroring CodeParser's ContainerNode."
ErrorNode::usage     = "ErrorNode[kind, source, <|meta|>] marks a syntax-error token."

ASTAlgebra::usage = "ASTAlgebra is the Association of builder functions that emit the standard AST nodes. A grammar written over an algebra produces a standard syntax tree when handed ASTAlgebra. Extend it (<|ASTAlgebra, \"Object\" -> ...|>) for language-specific constructs that map onto CallNode/GroupNode."

ASTContainer::usage = "ASTContainer[children] wraps a list of top-level forms in a ContainerNode[\"String\", ...] root."
ASTLeafQ::usage     = "ASTLeafQ[node] tests whether node is a LeafNode."
ASTNodeQ::usage     = "ASTNodeQ[node] tests whether node is any standard AST node."

ToCodeParser::usage = "ToCodeParser[tree] (or ToCodeParser[tree, opmap]) best-effort converts a neutral node tree to CodeParser`-namespaced nodes, mapping operator descriptors to Wolfram symbols via opmap (an Association \"op\" -> Symbol)."

RecCell::usage = "RecCell[] allocates a recursion cell - a stable symbol for a self/mutually-recursive grammar production. Use RecRef[cell] to reference it and SetRec[cell, parser] to give it its parser."
RecRef::usage  = "RecRef[cell] is a ParseRecursive reference to a recursion cell. Safe to build before or after SetRec, and in any number of places."
SetRec::usage  = "SetRec[cell, parser] gives a recursion cell its parser."

SpannedToken::usage = "SpannedToken[token, ws, build] matches token, captures the source span it covered (excluding trailing whitespace ws via ParsePosition), builds the leaf with build, and stamps Source -> {start, end} (character offsets) onto it. A non-node build result - the value a semantic algebra returns - passes through unstamped."
ASTAddSource::usage = "ASTAddSource[tree, source] finalizes source metadata: it fills every composite node's Source by spanning its children (leaves carry the offsets SpannedToken captured), then converts every offset span to a {{startLine, startColumn}, {endLine, endColumn}} pair against the source string - CodeParser's LineColumn convention."
ASTStripSource::usage = "ASTStripSource[tree] clears the Source metadata from every node, leaving the bare structure (useful for structural comparison)."

Begin["`Private`"]

(* Recursion cells. A ParseRecursive target must outlive the function that built
   the grammar; a Module-local symbol can be garbage-collected once the builder
   returns (its only reference is held inside ParseRecursive), silently breaking
   the recursion - the failure even depends on unrelated load order. A fresh
   global Unique symbol, kept un-evaluated inside the HoldFirst wrapper RC, never
   gets collected and resolves correctly regardless of when its value is set.
   This mirrors the Unique[]-per-rule wiring the paclet's own EBNF front-end uses. *)
SetAttributes[RC, HoldFirst]
RecCell[]            := With[{s = Unique["Wolfram`Parser`Private`rec$"]}, RC[s]]
RecRef[RC[s_]]       := ParseRecursive[s]
SetRec[RC[s_], p_]   := (s = p)

(* The nine node heads are inert DATA - they carry no down-values. They exist
   only to give parsed output a uniform, inspectable shape. *)

ASTContainer[children_List] := ContainerNode["String", children, <||>]
ASTContainer[child_]        := ContainerNode["String", {child}, <||>]

ASTLeafQ[_LeafNode] := True
ASTLeafQ[_]         := False

$nodeHeads = {LeafNode, CallNode, PrefixNode, PostfixNode, BinaryNode,
    InfixNode, TernaryNode, GroupNode, ContainerNode, ErrorNode};
ASTNodeQ[node_] := MemberQ[$nodeHeads, Head[node]]

(* The standard algebra: every builder produces the matching node with empty
   metadata. Source is left empty here and filled later: SpannedToken records a
   leaf's offset span at parse time (via the ParsePosition primitive), and
   ASTAddSource spans the composites and converts everything to {line, column}. *)
ASTAlgebra = <|
    "Leaf"      -> Function[{kind, src}, LeafNode[kind, src, <||>]],
    "Prefix"    -> Function[{op, x}, PrefixNode[op, x, <||>]],
    "Postfix"   -> Function[{x, op}, PostfixNode[x, op, <||>]],
    "Binary"    -> Function[{op, l, r}, BinaryNode[op, {l, r}, <||>]],
    "Infix"     -> Function[{op, children}, InfixNode[op, children, <||>]],
    "Ternary"   -> Function[{op, a, b, c}, TernaryNode[op, {a, b, c}, <||>]],
    "Call"      -> Function[{head, args}, CallNode[head, args, <||>]],
    "Group"     -> Function[{kind, children}, GroupNode[kind, children, <||>]],
    "Container" -> Function[{children}, ContainerNode["String", children, <||>]]
|>

(* --- source positions --- *)

setSource[n_, span_] := ReplacePart[n, 3 -> Append[n[[3]], "Source" -> span]]
sourceOf[n_]         := Lookup[n[[3]], "Source", Missing["NoSource"]]

(* stamp a captured offset span onto a freshly built node; a non-node (the value
   a semantic algebra returns) passes straight through *)
stampSource[n_ ? ASTNodeQ, span_] := setSource[n, span]
stampSource[other_, _]            := other

SpannedToken[token_, ws_, build_] := ParseAction[
    ParsePosition[] ~~ token ~~ ParsePosition[] ~~ ws,
    (stampSource[build[#2], {#1, #3}]) &]

(* fill every composite node's Source by spanning its children, bottom-up *)
fillSpans[n_ ? ASTNodeQ] := Module[{a = fillKids[n[[1]]], b = fillKids[n[[2]]], rebuilt, spans},
    rebuilt = ReplacePart[n, {1 -> a, 2 -> b}];
    If[ ! MissingQ[sourceOf[rebuilt]],
        rebuilt,
        spans = Cases[sourceOf /@ Select[Flatten[{a, b}], ASTNodeQ], {_Integer, _Integer}];
        If[ spans === {},
            rebuilt,
            setSource[rebuilt, {Min[spans[[All, 1]]], Max[spans[[All, 2]]]}]
        ]
    ]]
fillKids[x_ ? ASTNodeQ] := fillSpans[x]
fillKids[x_List]        := fillKids /@ x
fillKids[x_]            := x

(* 1-based {line, column} of a character offset in the source *)
lineColOf[input_String, off_Integer] := Module[{nls = StringPosition[StringTake[input, {1, off - 1}], "\n"][[All, 1]]},
    {Length[nls] + 1, off - If[nls === {}, 0, Last[nls]]}]

toLineCol[n_ ? ASTNodeQ, input_] := Module[{a = lcKids[n[[1]], input], b = lcKids[n[[2]], input], rebuilt, src},
    rebuilt = ReplacePart[n, {1 -> a, 2 -> b}];
    src = sourceOf[rebuilt];
    If[ MatchQ[src, {_Integer, _Integer}],
        setSource[rebuilt, {lineColOf[input, src[[1]]], lineColOf[input, src[[2]]]}],
        rebuilt]]
lcKids[x_ ? ASTNodeQ, input_] := toLineCol[x, input]
lcKids[x_List, input_]        := lcKids[#, input] & /@ x
lcKids[x_, _]                 := x

ASTAddSource[tree_, input_String] := toLineCol[fillSpans[tree], input]

ASTStripSource[tree_] := tree /. (a_Association /; KeyExistsQ[a, "Source"]) :> KeyDrop[a, "Source"]

(* --- best-effort projection onto CodeParser`-exact nodes --- *)

opSymbol[opmap_, op_] := Lookup[opmap, op, op]

leafKind[k_String] := Switch[k,
    "Integer", Integer, "Real", Real, "String", String,
    "Symbol", Symbol, "Rational", Rational, _, Symbol]
leafKind[k_] := k

ToCodeParser[tree_, opmap_Association : <||>] := tree //. {
    LeafNode[k_, v_, m_] :>
        CodeParser`LeafNode[leafKind[k], v, m],
    BinaryNode[op_, {l_, r_}, m_] :>
        CodeParser`CallNode[CodeParser`LeafNode[Symbol, opSymbol[opmap, op], <||>], {l, r}, m],
    InfixNode[op_, ch_List, m_] :>
        CodeParser`CallNode[CodeParser`LeafNode[Symbol, opSymbol[opmap, op], <||>], ch, m],
    PrefixNode[op_, x_, m_] :>
        CodeParser`CallNode[CodeParser`LeafNode[Symbol, opSymbol[opmap, op], <||>], {x}, m],
    PostfixNode[x_, op_, m_] :>
        CodeParser`CallNode[CodeParser`LeafNode[Symbol, opSymbol[opmap, op], <||>], {x}, m],
    TernaryNode[op_, ch_List, m_] :>
        CodeParser`CallNode[CodeParser`LeafNode[Symbol, opSymbol[opmap, op], <||>], ch, m],
    CallNode[h_, args_List, m_] :>
        CodeParser`CallNode[h, args, m],
    GroupNode[kind_, ch_List, m_] :>
        CodeParser`CallNode[CodeParser`LeafNode[Symbol, kind, <||>], ch, m],
    ContainerNode[k_, ch_List, m_] :>
        CodeParser`ContainerNode[k, ch, m]
}

End[]

EndPackage[]

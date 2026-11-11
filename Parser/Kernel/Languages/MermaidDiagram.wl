(* ::Package:: *)

(* :Title: MermaidDiagram.wl - Mermaid diagrams drawn as Graphics *)
(* :Context: Wolfram`Parser`Languages`Mermaid` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
	Draws the diagram MermaidRead gives. A flowchart, a state diagram and a class diagram are
	scenes of boxes, groups of boxes and links, laid out in layers along the diagram's direction:
	links point down the layers, the boxes of a layer are ordered to cross few links, a group is
	laid out by itself and then placed as one box. A sequence diagram is a column for each
	participant and a row for each message.

	One unit of the drawing is one printer's point at its natural size. Colors that depend on the
	notebook's appearance are LightDarkSwitched values; the text is measured from a table of
	character widths, so a drawing is the same with and without a front end.
*)

BeginPackage["Wolfram`Parser`Languages`Mermaid`", {"Wolfram`Parser`"}]

Begin["`Private`"]

(* ::Section:: *)
(*Text and colors*)

$fontSize = 13
$fontFamily = "Source Sans Pro"

(* the width of a character, in units of the font size *)
$characterWidths = Association[
	Thread[CharacterRange["A", "Z"] -> 0.6],
	Thread[Join[CharacterRange["a", "z"], CharacterRange["0", "9"]] -> 0.5],
	Thread[Characters["ijlI.,:;'|!"] -> 0.25],
	Thread[Characters["ftr ()[]{}-/\\*\""] -> 0.33],
	Thread[Characters["mwMW@%"] -> 0.8]
]

characterWidth[character_String] := Lookup[$characterWidths, character, If[First[ToCharacterCode[character]] >= 11904, 1., 0.56]]

lineWidth[line_String, size_] := size Total[characterWidth /@ Characters[line]]

(* the {width, height} a text takes at a font size *)
textSize[text_String, size_ : $fontSize] := With[{lines = StringSplit[text, "\n", All]},
	{Max[lineWidth[#, size] & /@ lines], 1.3 size Length[lines]}
]
textSize[None | "", ___] := {0, 0}

(* text centered at a point, a line at a time; fontScale[size] becomes a fraction of the drawing's width *)
textAt[text_String, {x_, y_}, color_, size_ : $fontSize, style___] := With[{lines = StringSplit[text, "\n", All]},
	MapIndexed[
		Function[{line, index},
			Text[
				Style[line, FontSize -> fontScale[size], FontFamily -> $fontFamily, FontColor -> color, style],
				{x, y - (1.3 size (First[index] - (Length[lines] + 1) / 2))}
			]
		],
		lines
	]
]

(* text that starts at a point *)
textFrom[text_String, {x_, y_}, color_, size_ : $fontSize, style___] :=
	Text[Style[text, FontSize -> fontScale[size], FontFamily -> $fontFamily, FontColor -> color, style], {x, y}, {-1, 0}]

(* the colors of a drawing, each for a light and a dark notebook *)
$theme = <|
	"NodeFill" -> LightDarkSwitched[RGBColor[0.925, 0.937, 1.], RGBColor[0.17, 0.2, 0.31]],
	"NodeEdge" -> LightDarkSwitched[RGBColor[0.42, 0.47, 0.82], RGBColor[0.56, 0.62, 0.95]],
	"Text" -> LightDarkSwitched[GrayLevel[0.1], GrayLevel[0.93]],
	"Line" -> LightDarkSwitched[GrayLevel[0.3], GrayLevel[0.78]],
	(* a group's face and the ground of a link's text are drawn with an Opacity beside them: a color that holds its own
		opacity loses it inside LightDarkSwitched in a dark notebook *)
	"GroupFill" -> LightDarkSwitched[RGBColor[0.5, 0.5, 0.56], RGBColor[0.75, 0.78, 1.]],
	"GroupEdge" -> LightDarkSwitched[GrayLevel[0.62], GrayLevel[0.46]],
	"LabelFill" -> LightDarkSwitched[GrayLevel[0.93], GrayLevel[0.24]],
	(* the ground under the text of a link: near a notebook's own background, so the text reads as a gap in the line *)
	"Ground" -> LightDarkSwitched[GrayLevel[0.995], GrayLevel[0.1]],
	"NoteFill" -> LightDarkSwitched[RGBColor[1., 0.96, 0.76], RGBColor[0.33, 0.3, 0.14]],
	"NoteEdge" -> LightDarkSwitched[RGBColor[0.78, 0.7, 0.3], RGBColor[0.66, 0.6, 0.3]],
	"Solid" -> LightDarkSwitched[GrayLevel[0.2], GrayLevel[0.85]]
|>

(* a CSS color: #rgb, #rrggbb, #rrggbbaa, rgb(r, g, b) or one of the common names; None for any other text *)
$colorNames = <|
	"black" -> Black, "white" -> White, "red" -> Red, "green" -> RGBColor[0, 0.5, 0], "blue" -> Blue, "yellow" -> Yellow,
	"orange" -> Orange, "purple" -> Purple, "pink" -> Pink, "gray" -> Gray, "grey" -> Gray, "lightgray" -> LightGray,
	"lightgrey" -> LightGray, "lightblue" -> LightBlue, "lightgreen" -> LightGreen, "lightyellow" -> LightYellow,
	"cyan" -> Cyan, "magenta" -> Magenta, "brown" -> Brown, "transparent" -> Transparent, "none" -> Transparent
|>

cssColor[text_String] := With[{value = ToLowerCase[StringTrim[text]]},
	Which[
		StringMatchQ[value, "#" ~~ Repeated[HexadecimalCharacter, {3}]],
			RGBColor @@ (FromDigits[# <> #, 16] / 255. & /@ Characters[StringDrop[value, 1]]),
		StringMatchQ[value, "#" ~~ Repeated[HexadecimalCharacter, {6}] | Repeated[HexadecimalCharacter, {8}]],
			RGBColor @@ (FromDigits[#, 16] / 255. & /@ StringPartition[StringDrop[value, 1], 2]),
		StringMatchQ[value, "rgb(" ~~ __ ~~ ")"] && Length[StringCases[value, DigitCharacter ..]] === 3,
			RGBColor @@ (FromDigits[#] / 255. & /@ StringCases[value, DigitCharacter ..]),
		KeyExistsQ[$colorNames, value],
			$colorNames[value],
		True,
			None
	]
]
cssColor[_] := None

(* the number a CSS length starts with *)
cssNumber[text_String, default_] := With[{digits = StringCases[text, StartOfString ~~ WhitespaceCharacter ... ~~ d : (DigitCharacter ..) :> d]},
	If[digits === {}, default, FromDigits[First[digits]]]
]
cssNumber[_, default_] := default

(* the directives a style gives a shape: its face, its edge and the color of its text *)
shapeStyle[style_Association, fill_, edge_, text_] := <|
	"Face" -> Replace[cssColor[Lookup[style, "fill"]], None -> fill],
	"Edge" -> Directive[
		Replace[cssColor[Lookup[style, "stroke"]], None -> edge],
		AbsoluteThickness[cssNumber[Lookup[style, "stroke-width"], 1.2]],
		If[KeyExistsQ[style, "stroke-dasharray"], AbsoluteDashing[{4, 3}], AbsoluteDashing[{}]],
		JoinForm["Round"]
	],
	"Text" -> Replace[cssColor[Lookup[style, "color"]], None :> Replace[cssColor[Lookup[style, "fill"]], {None -> text, color_ :> readableOn[color, text]}]]
|>

(* the color of text on a face a style colors: dark on a light face, light on a dark one, whatever the notebook *)
readableOn[face_, text_] := With[{rgb = PadRight[List @@ ColorConvert[face, "RGB"], 4, 1.]},
	Which[
		Last[rgb] < 0.5, text,
		{0.299, 0.587, 0.114} . Take[rgb, 3] > 0.55, GrayLevel[0.1],
		True, GrayLevel[0.95]
	]
]

(* ::Section:: *)
(*Shapes*)

(* A shape is drawn in a box: its center and its {width, height}. shapeOutline is the polygon a link
	stops at, shapePrimitives what is drawn. *)

arcPoints[{cx_, cy_}, {rx_, ry_}, {from_, to_}, count_ : 12] := Table[{cx + rx Cos[angle], cy + ry Sin[angle]}, {angle, from, to, (to - from) / count}]

roundedOutline[{cx_, cy_}, {w_, h_}, radius_] := With[{r = Min[radius, w / 2, h / 2]},
	Join[
		arcPoints[{cx + w / 2 - r, cy - h / 2 + r}, {r, r}, {-Pi / 2, 0}, 6],
		arcPoints[{cx + w / 2 - r, cy + h / 2 - r}, {r, r}, {0, Pi / 2}, 6],
		arcPoints[{cx - w / 2 + r, cy + h / 2 - r}, {r, r}, {Pi / 2, Pi}, 6],
		arcPoints[{cx - w / 2 + r, cy - h / 2 + r}, {r, r}, {Pi, 3 Pi / 2}, 6]
	]
]

shapeOutline["Rounded", center_, size_] := roundedOutline[center, size, 8]
shapeOutline["Stadium", center_, size : {_, h_}] := roundedOutline[center, size, h / 2]
shapeOutline["Circle" | "DoubleCircle" | "Ellipse" | "Start" | "End", center_, {w_, h_}] := arcPoints[center, {w / 2, h / 2}, {0, 2 Pi}, 40]
shapeOutline["Diamond" | "Choice", {cx_, cy_}, {w_, h_}] := {{cx, cy - h / 2}, {cx + w / 2, cy}, {cx, cy + h / 2}, {cx - w / 2, cy}}
shapeOutline["Hexagon", {cx_, cy_}, {w_, h_}] := With[{d = h / 4},
	{{cx - w / 2 + d, cy - h / 2}, {cx + w / 2 - d, cy - h / 2}, {cx + w / 2, cy}, {cx + w / 2 - d, cy + h / 2}, {cx - w / 2 + d, cy + h / 2}, {cx - w / 2, cy}}
]
(* the four corners of a slanted box: how far the top and the bottom edge are pulled in on each side *)
slanted[{cx_, cy_}, {w_, h_}, {topLeft_, topRight_, bottomRight_, bottomLeft_}] := With[{d = 0.3 h}, {
	{cx - w / 2 + d topLeft, cy + h / 2}, {cx + w / 2 - (d topRight), cy + h / 2},
	{cx + w / 2 - (d bottomRight), cy - h / 2}, {cx - w / 2 + d bottomLeft, cy - h / 2}
}]
shapeOutline["Parallelogram", center_, size_] := slanted[center, size, {1, 0, 1, 0}]
shapeOutline["ParallelogramAlt", center_, size_] := slanted[center, size, {0, 1, 0, 1}]
shapeOutline["Trapezoid", center_, size_] := slanted[center, size, {1, 1, 0, 0}]
shapeOutline["TrapezoidAlt", center_, size_] := slanted[center, size, {0, 0, 1, 1}]
shapeOutline["Flag", {cx_, cy_}, {w_, h_}] :=
	{{cx - w / 2, cy - h / 2}, {cx + w / 2, cy - h / 2}, {cx + w / 2, cy + h / 2}, {cx - w / 2, cy + h / 2}, {cx - w / 2 + h / 4, cy}}
shapeOutline["Cylinder", {cx_, cy_}, {w_, h_}] := With[{ry = cylinderCap[h]},
	Join[
		arcPoints[{cx, cy + h / 2 - ry}, {w / 2, ry}, {0, Pi}],
		arcPoints[{cx, cy - h / 2 + ry}, {w / 2, ry}, {Pi, 2 Pi}]
	]
]
shapeOutline[_, center_, size_] := roundedOutline[center, size, 3]

cylinderCap[h_] := Min[7, h / 5]

shapePrimitives["DoubleCircle", center_, {w_, h_}, style_] := {
	FaceForm[style["Face"]], EdgeForm[style["Edge"]],
	Polygon[shapeOutline["Circle", center, {w, h}]],
	FaceForm[None],
	Polygon[shapeOutline["Circle", center, {w - 8, h - 8}]]
}
shapePrimitives["Subroutine", center : {cx_, cy_}, size : {w_, h_}, style_] := {
	FaceForm[style["Face"]], EdgeForm[style["Edge"]],
	Polygon[shapeOutline["Rectangle", center, size]],
	style["Edge"],
	Line[{{cx - w / 2 + 7, cy - h / 2}, {cx - w / 2 + 7, cy + h / 2}}],
	Line[{{cx + w / 2 - 7, cy - h / 2}, {cx + w / 2 - 7, cy + h / 2}}]
}
shapePrimitives["Cylinder", center : {cx_, cy_}, size : {w_, h_}, style_] := {
	FaceForm[style["Face"]], EdgeForm[style["Edge"]],
	Polygon[shapeOutline["Cylinder", center, size]],
	style["Edge"],
	Line[arcPoints[{cx, cy + h / 2 - cylinderCap[h]}, {w / 2, cylinderCap[h]}, {Pi, 2 Pi}]]
}
(* the start of a state diagram is a filled disk, its end a disk in a ring *)
shapePrimitives["Start", center_, size_, style_] := {FaceForm[$theme["Solid"]], EdgeForm[None], Polygon[shapeOutline["Circle", center, size]]}
shapePrimitives["End", center_, size : {w_, h_}, style_] := {
	FaceForm[None], EdgeForm[Directive[$theme["Solid"], AbsoluteThickness[1.2]]],
	Polygon[shapeOutline["Circle", center, size]],
	FaceForm[$theme["Solid"]], EdgeForm[None],
	Polygon[shapeOutline["Circle", center, {w - 8, h - 8}]]
}
shapePrimitives["Bar", center_, size_, style_] := {FaceForm[$theme["Solid"]], EdgeForm[None], Polygon[roundedOutline[center, size, 2]]}
shapePrimitives[kind_, center_, size_, style_] := {FaceForm[style["Face"]], EdgeForm[style["Edge"]], Polygon[shapeOutline[kind, center, size]]}

(* the box a shape needs around a text of a size *)
shapeSize["Circle", {tw_, th_}] := ConstantArray[Max[Sqrt[tw ^ 2 + th ^ 2] + 14, 36], 2]
shapeSize["DoubleCircle", text_] := shapeSize["Circle", text] + 10
shapeSize["Ellipse", {tw_, th_}] := {1.25 tw + 30, 1.3 th + 22}
shapeSize["Stadium", {tw_, th_}] := {tw + th + 40, th + 20}
shapeSize["Subroutine", {tw_, th_}] := {tw + 46, th + 20}
shapeSize["Diamond", {tw_, th_}] := With[{w = tw + 2.2 th + 20}, {w, Max[th / (1 - tw / w) + 10, 40]}]
shapeSize["Hexagon", {tw_, th_}] := {tw + 32 + (th + 20) / 2, th + 20}
shapeSize["Parallelogram" | "ParallelogramAlt" | "Trapezoid" | "TrapezoidAlt", {tw_, th_}] := {tw + 32 + 0.6 (th + 20), th + 20}
shapeSize["Flag", {tw_, th_}] := {tw + 34 + (th + 20) / 4, th + 20}
shapeSize["Cylinder", {tw_, th_}] := {tw + 32, th + 34}
shapeSize[_, {tw_, th_}] := {Max[tw + 32, 40], th + 20}

(* where the text of a shape goes, from its center *)
textOffset["Flag", {w_, h_}] := {h / 8, 0}
textOffset["Cylinder", {w_, h_}] := {0, -cylinderCap[h] / 2}
textOffset[_, _] := {0, 0}

(* the point where the ray from the center of an outline toward a point leaves it *)
boundaryPoint[outline_List, center_, toward_] := With[{direction = toward - center},
	If[Norm[direction] < 10. ^ -9,
		center,
		With[{hits = Cases[rayHit[center, direction, ##] & @@@ Partition[outline, 2, 1, 1], _Real | _Integer | _Rational]},
			If[hits === {}, center, center + Min[Max[hits], 1] direction]
		]
	]
]

cross[{ax_, ay_}, {bx_, by_}] := ax by - (ay bx)

(* how far along a ray from origin the segment from p to q is crossed, None where it is not *)
rayHit[origin_, direction_, p_, q_] := With[{denominator = cross[direction, q - p]},
	If[Abs[denominator] < 10. ^ -12,
		None,
		With[{t = cross[p - origin, q - p] / denominator, s = cross[p - origin, direction] / denominator},
			If[t > 0 && -10. ^ -9 <= s <= 1 + 10. ^ -9, N[t], None]
		]
	]
]

(* ::Section:: *)
(*The layered layout of one level*)

(* The least-squares fit to values that does not decrease, the pool-adjacent-violators way: runs
	of values out of order are replaced by their weighted mean. *)
isotonic[values_List, weights_List] := Module[{blocks},
	blocks = Fold[
		Function[{stack, block}, mergeBlocks[Append[stack, block]]],
		{},
		Transpose[{weights, weights values, ConstantArray[1, Length[values]]}]
	];
	Catenate[ConstantArray[#[[2]] / #[[1]], #[[3]]] & /@ blocks]
]

mergeBlocks[{rest___, a_, b_}] /; a[[2]] / a[[1]] > b[[2]] / b[[1]] := mergeBlocks[{rest, a + b}]
mergeBlocks[blocks_List] := blocks

(* the links that close a cycle, found depth first from the vertices in order: those that reach a
	vertex still being visited *)
backLinks[count_Integer, links_List] := Module[{state = ConstantArray[0, count], outgoing, back = {}, visit},
	outgoing = GroupBy[Range[Length[links]], links[[#, 1]] &];
	visit[v_] := (
		state[[v]] = 1;
		Scan[
			Function[e,
				With[{w = links[[e, 2]]},
					Which[
						state[[w]] === 1, back = {back, e},
						state[[w]] === 0, visit[w]
					]
				]
			],
			Lookup[outgoing, v, {}]
		];
		state[[v]] = 2
	);
	Scan[If[state[[#]] === 0, visit[#]] &, Range[count]];
	Flatten[back]
]

(* how many pairs of links between two layers cross: links are pairs of positions *)
crossings[pairs_List] := Count[Subsets[pairs, {2}], {{a_, b_}, {c_, d_}} /; (a - c) (b - d) < 0]

(* layeredLayout[sizes, links, gaps, {first, last}]: boxes numbered from 1, each {breadth, depth}; links, each
	{from, to, length, label}, label the {breadth, depth} of its text or None. The layers run down
	the depth. Gives the centers of the boxes, for each link the points it passes between its ends
	and the center of its label, and the {breadth, depth} of the whole. The boxes first and last are
	kept in a layer of their own before and after all the others: the points where links enter and leave. *)
layeredLayout[sizes_List, links_List, {boxGap_, layerGap_}, {first_List, last_List}] := Module[{
	count = Length[sizes], back, oriented, labeled, incoming, rank, ranks, sources, itemRank, itemSize, itemEdge,
	chains, segments, layers, order, position, neighbors, x, y, depths, gap, best, bestCrossings, sweep, segmentPairs,
	place, total, labelItem, gaps
},
	back = backLinks[count, links];
	(* a link against the layers is laid out reversed *)
	oriented = MapIndexed[If[MemberQ[back, First[#2]], {#1[[2]], #1[[1]], #1[[3]], #1[[4]]}, #1] &, links];
	(* where a link has a label, every link is twice as long and the gap half, so a label has a layer of its own *)
	labeled = AnyTrue[links, #[[4]] =!= None &];
	oriented = If[labeled, MapAt[2 # &, oriented, {All, 3}], oriented];
	gap = If[labeled, layerGap / 2, layerGap];
	incoming = GroupBy[oriented, #[[2]] &];
	rank[v_] := rank[v] = Max[0, (rank[#[[1]]] + #[[3]]) & /@ Lookup[incoming, v, {}]];
	ranks = Block[{$RecursionLimit = Max[$RecursionLimit, 8 count + 1024]}, rank /@ Range[count]];
	(* a box no link enters sits just above the nearest box it links to *)
	sources = Complement[oriented[[All, 1]], oriented[[All, 2]]];
	ranks = ReplacePart[ranks, Map[# -> Min[Cases[oriented, {#, to_, length_, _} :> ranks[[to]] - length]] &, sources]];
	ranks = With[{inside = Delete[ranks, List /@ Join[first, last]]},
		If[inside === {}, ranks, ReplacePart[ranks, Join[Thread[first -> Min[inside] - 1], Thread[last -> Max[inside] + 1]]]]
	];
	ranks = ranks - Min[ranks];
	(* a link over several layers passes a point in each layer between, the middle one its label *)
	itemRank = ranks;
	itemSize = sizes;
	chains = Map[
		Function[link,
			With[{between = Range[ranks[[link[[1]]]] + 1, ranks[[link[[2]]]] - 1]},
				With[{items = Length[itemRank] + Range[Length[between]]},
					itemRank = Join[itemRank, between];
					itemSize = Join[itemSize, ReplacePart[
						ConstantArray[{0, 0}, Length[between]],
						If[link[[4]] =!= None && between =!= {}, {Ceiling[Length[between] / 2] -> link[[4]]}, {}]
					]];
					Join[{link[[1]]}, items, {link[[2]]}]
				]
			]
		],
		oriented
	];
	labelItem = MapThread[
		If[#1[[4]] =!= None && Length[#2] > 2, #2[[1 + Ceiling[(Length[#2] - 2) / 2]]], None] &,
		{oriented, chains}
	];
	(* the segments between neighboring layers; one between two points of a link weighs more, to keep the link straight *)
	segments = Catenate[Partition[#, 2, 1] & /@ chains];
	neighbors = Merge[
		Catenate[{#1 -> {#2, segmentWeight[count, #1, #2]}, #2 -> {#1, segmentWeight[count, #1, #2]}} & @@@ segments],
		Identity
	];
	(* the first order of each layer: the items as a walk from the boxes in order first meets them *)
	order = firstOrder[Length[itemRank], count, segments];
	layers = Values[KeySort[GroupBy[order, itemRank[[#]] &]]];
	(* sweep down and up, each layer sorted by the mean position of its neighbors in the layer before; the best order is kept *)
	segmentPairs[current_] := With[{at = positions[current, Length[itemRank]]},
		Total[crossings /@ Values[GroupBy[segments, itemRank[[First[#]]] &, Map[at[[#]] &]]]]
	];
	best = layers;
	bestCrossings = segmentPairs[layers];
	sweep[current_, down_] := Fold[
		Function[{done, index},
			With[{at = positions[done, Length[itemRank]], reference = itemRank[[First[done[[index]]]]] + If[down, -1, 1]},
				ReplacePart[done, index -> SortBy[
					done[[index]],
					Function[item,
						With[{around = Select[First /@ Lookup[neighbors, item, {}], itemRank[[#]] === reference &]},
							{If[around === {}, at[[item]], Mean[at[[around]]]], at[[item]]}
						]
					]
				]]
			]
		],
		current,
		If[down, Range[2, Length[current]], Range[Length[current] - 1, 1, -1]]
	];
	Do[
		If[bestCrossings === 0, Break[]];
		layers = sweep[layers, OddQ[round]];
		With[{now = segmentPairs[layers]}, If[now < bestCrossings, best = layers; bestCrossings = now]],
		{round, 16}
	];
	layers = best;
	(* across a layer: boxes packed in order, then each moved toward the mean of its neighbors, a box
		never closer to the next than the gap *)
	x = ConstantArray[0., Length[itemRank]];
	place[layer_, wanted_, weights_] := With[{
		offsets = Prepend[Accumulate[separation[itemSize, count, boxGap] @@@ Partition[layer, 2, 1]], 0.]
	},
		x[[layer]] = isotonic[wanted - offsets, weights] + offsets
	];
	Scan[
		Function[layer,
			place[layer, ConstantArray[0., Length[layer]], ConstantArray[1., Length[layer]]];
			x[[layer]] = x[[layer]] - Mean[x[[layer]][[{1, -1}]]]
		],
		layers
	];
	Do[
		Scan[
			Function[layer,
				place[
					layer,
					Map[With[{around = Lookup[neighbors, #, {}]}, If[around === {}, x[[#]], Total[x[[around[[All, 1]]]] around[[All, 2]]] / Total[around[[All, 2]]]]] &, layer],
					Map[Max[1., Total[Lookup[neighbors, #, {}][[All, 2]]]] &, layer]
				]
			],
			If[OddQ[round], layers, Reverse[layers]]
		],
		{round, 40}
	];
	x = x - Min[x - itemSize[[All, 1]] / 2];
	(* down the layers: each as deep as its deepest box *)
	depths = Max[itemSize[[#, 2]]] & /@ layers;
	(* the layer of the entering points, and that of the leaving ones, is close to the boxes *)
	gaps = (If[SubsetQ[first, #1] || SubsetQ[last, #2], Min[gap, 22], gap] &) @@@ Partition[layers, 2, 1];
	(* a box far shallower than its layer, as one beside a group is, sits near the start of the layer *)
	y = With[{centers = Accumulate[Prepend[(Most[depths] + Rest[depths]) / 2 + gaps, First[depths] / 2]]},
		ReplacePart[
			ConstantArray[0., Length[itemRank]],
			Catenate @ MapThread[
				Function[{layer, center, depth},
					Map[# -> If[# <= count && depth - itemSize[[#, 2]] > 90, center - depth / 2 + itemSize[[#, 2]] / 2 + 36, center] &, layer]
				],
				{layers, centers, depths}
			]
		]
	];
	total = {Max[x + itemSize[[All, 1]] / 2], Total[depths] + Total[gaps]};
	<|
		"Centers" -> Take[Transpose[{x, y}], count],
		"Routes" -> MapIndexed[
			With[{points = Transpose[{x, y}][[#1[[2 ;; -2]]]]},
				If[MemberQ[back, First[#2]], Reverse[points], points]
			] &,
			chains
		],
		"Labels" -> Map[If[# === None, None, {x[[#]], y[[#]]}] &, labelItem],
		"Size" -> total
	|>
]

layeredLayout[{}, _, _, _] := <|"Centers" -> {}, "Routes" -> {}, "Labels" -> {}, "Size" -> {0, 0}|>

segmentWeight[count_, a_, b_] := Which[a > count && b > count, 4., a > count || b > count, 2., True, 1.]

(* the distance between the centers of two neighbors in a layer *)
separation[itemSize_, count_, boxGap_][a_, b_] :=
	(itemSize[[a, 1]] + itemSize[[b, 1]]) / 2 + If[a > count || b > count, If[itemSize[[a, 1]] + itemSize[[b, 1]] > 0, boxGap / 2, boxGap / 2.5], boxGap]

(* the position of each item in its layer *)
positions[layers_List, count_Integer] := ReplacePart[ConstantArray[0, count], Catenate[MapIndexed[#1 -> First[#2] &, #] & /@ layers]]

(* the items in the order a depth-first walk along the segments, from each box in turn, first meets them *)
firstOrder[itemCount_Integer, count_Integer, segments_List] := Module[{seen = ConstantArray[False, itemCount], next, found = {}, visit},
	next = GroupBy[segments, First -> Last];
	visit[item_] := If[! seen[[item]],
		seen[[item]] = True;
		found = {found, item};
		Scan[visit, Lookup[next, item, {}]]
	];
	Block[{$RecursionLimit = Max[$RecursionLimit, 8 itemCount + 1024]}, Scan[visit, Range[count]]];
	Flatten[found]
]

(* ::Section:: *)
(*A scene: boxes, groups and links*)

(* A scene is <|"Direction", "Boxes" -> <|name -> <|"Size", "Parent", "Kind", "Draw"|>|>,
	"Groups" -> <|name -> <|"Title", "Parent", "Direction", "Style"|>|>, "Links" -> {<|"From", "To", "Length",
	"Label", "Line", "Head", "Tail", "Style"|>, ...}|>. "Draw" is a function of the center of a box
	that gives its primitives. *)

$groupPadding = 16

(* the member of a group that holds a name: the name itself or the group below that holds it; None outside the group *)
memberOf[parents_Association, group_, name_] := Which[
	! KeyExistsQ[parents, name], None,
	parents[name] === group, name,
	parents[name] === None, None,
	True, memberOf[parents, group, parents[name]]
]

(* to and from the frame the layout works in, where the layers run down *)
toFrame[direction_, {w_, h_}] := If[MatchQ[direction, "LR" | "RL"], {h, w}, {w, h}]
fromFrame[direction_, {breadth_, depth_}][{x_, y_}] := Switch[direction,
	"LR", {y, x},
	"RL", {depth - y, x},
	"BT", {x, depth - y},
	_, {x, y}
]

(* placeGroup lays out the members of a group (None: the whole scene) and gives the size of its box
	and, from the corner of that box: the boxes of all it holds, name -> {center, size}; the points
	of each link between its members; and for each link that leaves or enters the group a stub, the
	points from its end inside to the side of the group it leaves by, or from the side it enters by. *)
placeGroup[scene_, parents_, group_, inherited_] := Module[{
	direction = inherited,
	members, inner, sizes, index, ends, links, leaving, entering, layout, back, content, title, origin, box, placed, shifted, stubs,
	count, innerStubs, point
},
	members = Keys[Select[parents, # === group &]];
	count = Length[members];
	index = AssociationThread[members, Range[count]];
	ends = MapIndexed[
		<|"Link" -> First[#2], "From" -> memberOf[parents, group, #1["From"]], "To" -> memberOf[parents, group, #1["To"]],
			"Length" -> #1["Length"], "Outside" -> ! MemberQ[{#1["From"], #1["To"]}, group], "Label" -> #1["Label"]|> &,
		scene["Links"]
	];
	(* the links of this level: those whose two ends are in different members *)
	links = Select[ends, #From =!= None && #To =!= None && #From =!= #To &];
	leaving = If[group === None, {}, Select[ends, #From =!= None && #To === None && #Outside &]];
	entering = If[group === None, {}, Select[ends, #From === None && #To =!= None && #Outside &]];
	(* a group keeps a direction of its own only while no link joins what it holds to the outside, as in Mermaid *)
	If[group =!= None && leaving === {} && entering === {}, direction = Replace[scene["Groups", group, "Direction"], None -> inherited]];
	inner = AssociationMap[placeGroup[scene, parents, #, direction] &, Select[members, KeyExistsQ[scene["Groups"], #] &]];
	sizes = Map[If[KeyExistsQ[inner, #], inner[#, "Size"], scene["Boxes", #, "Size"]] &, members];
	layout = layeredLayout[
		Join[toFrame[direction, #] & /@ sizes, ConstantArray[{0, 0}, Length[leaving] + Length[entering]]],
		Join[
			{index[#From], index[#To], #Length, If[MatchQ[#Label, None | ""], None, toFrame[direction, textSize[#Label, $fontSize - 1] + {12, 6}]]} & /@ links,
			MapIndexed[{index[#1["From"]], count + First[#2], 1, None} &, leaving],
			MapIndexed[{count + Length[leaving] + First[#2], index[#1["To"]], 1, None} &, entering]
		],
		{If[MatchQ[direction, "LR" | "RL"], 30, 44], 46},
		{count + Length[leaving] + Range[Length[entering]], count + Range[Length[leaving]]}
	];
	back = fromFrame[direction, layout["Size"]];
	content = toFrame[direction, layout["Size"]];
	title = If[group === None, {0, 0}, textSize[scene["Groups", group, "Title"]]];
	box = If[group === None,
		content,
		{Max[First[content], 1.1 First[title] + 8] + 2 $groupPadding, Last[content] + 2 $groupPadding + If[Last[title] > 0, Last[title] + 4, 0]}
	];
	origin = If[group === None, {0, 0}, {(First[box] - First[content]) / 2, $groupPadding + If[Last[title] > 0, Last[title] + 4, 0]}];
	point = origin + back[#] &;
	placed = AssociationThread[members, MapThread[{point[#1], #2} &, {Take[layout["Centers"], count], sizes}]];
	(* what the groups inside hold, from the corner of this box *)
	shifted[key_] := Association @ KeyValueMap[
		Function[{name, sub}, With[{corner = First[placed[name]] - sub["Size"] / 2}, Map[shift[key, corner], sub[key]]]],
		inner
	];
	innerStubs = shifted["Stubs"];
	stubs[link_, side_] := Lookup[innerStubs, Key[{link, side}], {}];
	<|
		"Size" -> box,
		"Placed" -> Association[placed, shifted["Placed"]],
		"Routes" -> Association[
			MapThread[
				#1["Link"] -> <|
					"Points" -> Join[stubs[#1["Link"], "From"], point /@ #2, stubs[#1["Link"], "To"]],
					"Label" -> If[#3 === None, None, point[#3]]
				|> &,
				{links, Take[layout["Routes"], Length[links]], Take[layout["Labels"], Length[links]]}
			],
			shifted["Routes"]
		],
		"Stubs" -> Association[
			MapIndexed[
				{#1["Link"], "From"} -> Join[
					stubs[#1["Link"], "From"],
					point /@ Append[layout["Routes"][[Length[links] + First[#2]]], layout["Centers"][[count + First[#2]]]]
				] &,
				leaving
			],
			MapIndexed[
				{#1["Link"], "To"} -> Join[
					point /@ Prepend[layout["Routes"][[Length[links] + Length[leaving] + First[#2]]], layout["Centers"][[count + Length[leaving] + First[#2]]]],
					stubs[#1["Link"], "To"]
				] &,
				entering
			]
		]
	|>
]

(* what a group holds, moved by the corner of the group's box *)
shift["Placed", corner_][{center_, size_}] := {corner + center, size}
shift["Routes", corner_][route_] := <|"Points" -> Map[corner + # &, route["Points"]], "Label" -> If[route["Label"] === None, None, corner + route["Label"]]|>
shift["Stubs", corner_][points_] := Map[corner + # &, points]

(* the head of a link at a point, pointing along a unit direction *)
headPrimitives["Arrow", point_, direction_, color_] := With[{normal = {-1, 1} Reverse[direction]},
	{FaceForm[color], EdgeForm[Directive[color, AbsoluteThickness[0.8], JoinForm["Round"]]], Polygon[{point, point - (10 direction) + 4 normal, point - (8 direction), point - (10 direction) - (4 normal)}]}
]
headPrimitives["Open", point_, direction_, color_] := With[{normal = {-1, 1} Reverse[direction]},
	{color, AbsoluteThickness[1.3], CapForm["Round"], JoinForm["Round"], Line[{point - (10 direction) + 5 normal, point, point - (10 direction) - (5 normal)}]}
]
headPrimitives["Triangle", point_, direction_, color_] := With[{normal = {-1, 1} Reverse[direction]},
	{FaceForm[$theme["NodeFill"]], EdgeForm[Directive[color, AbsoluteThickness[1.2], JoinForm["Round"]]], Polygon[{point, point - (13 direction) + 7 normal, point - (13 direction) - (7 normal)}]}
]
headPrimitives[kind : "Diamond" | "DiamondOpen", point_, direction_, color_] := With[{normal = {-1, 1} Reverse[direction]},
	{FaceForm[If[kind === "Diamond", color, $theme["NodeFill"]]], EdgeForm[Directive[color, AbsoluteThickness[1.2], JoinForm["Round"]]],
		Polygon[{point, point - (8 direction) + 5 normal, point - (16 direction), point - (8 direction) - (5 normal)}]}
]
headPrimitives["Circle", point_, direction_, color_] := {FaceForm[color], EdgeForm[None], Disk[point - (4.5 direction), 4.5]}
headPrimitives["Cross", point_, direction_, color_] := With[{normal = {-1, 1} Reverse[direction], middle = point - (6 direction)},
	{color, AbsoluteThickness[1.6], CapForm["Round"], Line[{middle - (4.5 direction) - (4.5 normal), middle + 4.5 direction + 4.5 normal}], Line[{middle - (4.5 direction) + 4.5 normal, middle + 4.5 direction - (4.5 normal)}]}
]
headPrimitives[_, _, _, _] := {}

(* how much of a link's end its head covers *)
headLength["Arrow"] := 8
headLength["Triangle"] := 13
headLength["Diamond" | "DiamondOpen"] := 16
headLength["Circle"] := 9
headLength[_] := 0

unit[vector_] := With[{length = Norm[vector]}, If[length < 10. ^ -9, {0., 0.}, vector / length]]

lineDirectives[link_, color_] := Directive[
	Replace[cssColor[Lookup[link["Style"], "stroke"]], None -> color],
	AbsoluteThickness[cssNumber[Lookup[link["Style"], "stroke-width"], If[link["Line"] === "Thick", 3, 1.3]]],
	If[link["Line"] === "Dotted" || KeyExistsQ[link["Style"], "stroke-dasharray"], AbsoluteDashing[{3, 4}], AbsoluteDashing[{}]],
	CapForm["Round"],
	JoinForm["Round"]
]

(* a smooth curve through points: cubic Bezier segments, the tangent at a point along the line between
	its neighbors, each handle a third of its own segment, so a short segment after a long one does not overshoot *)
smoothCurve[points : {_, _}] := Line[points]
smoothCurve[points_List] := With[{padded = Join[{First[points]}, points, {Last[points]}]},
	BezierCurve[Prepend[
		Catenate[
			Function[{before, from, to, after},
				{from + Norm[to - from] / 3 unit[to - before], to - (Norm[to - from] / 3 unit[after - from]), to}
			] @@@ Partition[padded, 4, 1]
		],
		First[points]
	]]
]

(* a link drawn along its points, from the outline of one box to the outline of the other *)
linkPrimitives[link_, route_, outlines_, placed_] := Module[{
	from = First[placed[link["From"]]], to = First[placed[link["To"]]], points, start, end, startDirection, endDirection,
	color = Replace[cssColor[Lookup[link["Style"], "stroke"]], None -> $theme["Line"]]
},
	points = Join[{from}, route["Points"], {to}];
	start = boundaryPoint[outlines[link["From"]], from, points[[2]]];
	end = boundaryPoint[outlines[link["To"]], to, points[[-2]]];
	(* a point of the route too near an end only bends the link there *)
	points = Join[{start}, Select[route["Points"], Norm[# - start] > 14 && Norm[# - end] > 14 &], {end}];
	startDirection = unit[start - points[[2]]];
	endDirection = unit[end - points[[-2]]];
	points = ReplacePart[points, {1 -> start - (headLength[link["Tail"]] startDirection), -1 -> end - (headLength[link["Head"]] endDirection)}];
	If[link["Line"] === "Invisible",
		{},
		{
			{lineDirectives[link, $theme["Line"]], smoothCurve[points]},
			headPrimitives[link["Head"], end, endDirection, color],
			headPrimitives[link["Tail"], start, startDirection, color],
			endLabel[Lookup[link, "FromLabel", None], start, startDirection, headLength[link["Tail"]]],
			endLabel[Lookup[link, "ToLabel", None], end, endDirection, headLength[link["Head"]]]
		}
	]
]

(* the text at an end of a link, a multiplicity: beside the line, clear of the head *)
endLabel[text_String, point_, direction_, head_] :=
	textAt[text, point - ((head + 12) direction) + (6 + First[textSize[text, $fontSize - 2]] / 2) {-1, 1} Reverse[direction], $theme["Text"], $fontSize - 2]
endLabel[_, _, _, _] := {}

(* a link from a box to itself: a loop at its side *)
loopPrimitives[link_, {center : {cx_, cy_}, {w_, h_}}] := With[{
	color = Replace[cssColor[Lookup[link["Style"], "stroke"]], None -> $theme["Line"]],
	right = cx + w / 2
},
	{
		{lineDirectives[link, $theme["Line"]], BezierCurve[{{right, cy + h / 4}, {right + 34, cy + h / 2 + 4}, {right + 34, cy - h / 2 - 4}, {right + 8, cy - h / 4}}]},
		headPrimitives[link["Head"], {right, cy - h / 4}, {-1., 0.}, color],
		If[MatchQ[link["Label"], None | ""], {}, textFrom[link["Label"], {right + 30, cy}, $theme["Text"], $fontSize - 1]]
	}
]

labelPrimitives[text_String, center_] := With[{size = textSize[text, $fontSize - 1] + {8, 3}},
	{
		{Opacity[0.88], FaceForm[$theme["Ground"]], EdgeForm[None], Polygon[roundedOutline[center, size, 4]]},
		textAt[text, center, $theme["Text"], $fontSize - 1]
	}
]

groupPrimitives[group_, {center : {cx_, cy_}, size : {w_, h_}}] := With[{
	style = shapeStyle[group["Style"], $theme["GroupFill"], $theme["GroupEdge"], $theme["Text"]]
},
	{
		{If[KeyExistsQ[group["Style"], "fill"], Opacity[1], Opacity[0.09]], FaceForm[style["Face"]], EdgeForm[None], Polygon[roundedOutline[center, size, 6]]},
		{FaceForm[None], EdgeForm[style["Edge"]], Polygon[roundedOutline[center, size, 6]]},
		If[group["Title"] === "", {}, textFrom[group["Title"], {cx - w / 2 + 12, cy + h / 2 - $groupPadding / 2 - Last[textSize[group["Title"]]] / 2}, style["Text"], $fontSize, FontWeight -> "DemiBold"]]
	}
]

(* the depth of a group: how many groups it is inside *)
groupDepth[groups_, name_] := If[groups[name, "Parent"] === None, 0, 1 + groupDepth[groups, groups[name, "Parent"]]]

(* the primitives of a scene and the {width, height} they take: x from 0 to the width, y from 0 down to minus the height *)
scenePrimitives[scene_] := Module[{
	parents = Join[Map[#Parent &, scene["Boxes"]], Map[#Parent &, scene["Groups"]]],
	layout, placed, outlines, routes
},
	layout = placeGroup[scene, parents, None, scene["Direction"]];
	placed = Map[{{1, -1} First[#], Last[#]} &, layout["Placed"]];
	outlines = Association @ KeyValueMap[
		#1 -> If[KeyExistsQ[scene["Groups"], #1], roundedOutline[First[#2], Last[#2], 6], shapeOutline[scene["Boxes", #1, "Kind"], First[#2], Last[#2]]] &,
		placed
	];
	routes = Map[<|"Points" -> Map[{1, -1} # &, #Points], "Label" -> If[#Label === None, None, {1, -1} #Label]|> &, layout["Routes"]];
	{
		{
			KeyValueMap[groupPrimitives[#2, placed[#1]] &, KeySortBy[scene["Groups"], groupDepth[scene["Groups"], #] &]],
			MapIndexed[
				Which[
					! KeyExistsQ[placed, #1["From"]] || ! KeyExistsQ[placed, #1["To"]], {},
					#1["From"] === #1["To"], loopPrimitives[#1, placed[#1["From"]]],
					True, linkPrimitives[#1, Lookup[routes, First[#2], <|"Points" -> {}, "Label" -> None|>], outlines, placed]
				] &,
				scene["Links"]
			],
			KeyValueMap[#2["Draw"][First[placed[#1]]] &, scene["Boxes"]],
			MapIndexed[
				With[{route = Lookup[routes, First[#2], None]},
					Which[
						MatchQ[#1["Label"], None | ""] || #1["From"] === #1["To"] || ! KeyExistsQ[placed, #1["From"]] || ! KeyExistsQ[placed, #1["To"]], {},
						route === None || route["Label"] === None, labelPrimitives[#1["Label"], (First[placed[#1["From"]]] + First[placed[#1["To"]]]) / 2],
						True, labelPrimitives[#1["Label"], route["Label"]]
					]
				] &,
				scene["Links"]
			]
		},
		layout["Size"] + {If[AnyTrue[scene["Links"], #From === #To &], 44, 0], 0}
	}
]

(* ::Section:: *)
(*The drawing*)

$margin = 10

(* Graphics of primitives that take a {width, height}, x from 0 to the width and y from 0 down to
	minus the height, with a title above. A font size becomes a fraction of the width, so text keeps
	its place when the drawing is resized. *)
drawing[primitives_, {width_, height_}, title_, options_List] := With[{
	titleSize = If[MatchQ[title, None | ""], {0, 0}, textSize[title, $fontSize + 3] + {0, 10}]
},
	With[{side = $margin + Max[First[titleSize] - width, 0] / 2},
		Graphics[
			ReplaceAll[
				{
					If[MatchQ[title, None | ""], {}, textAt[title, {width / 2, Last[titleSize] / 2 + 2}, $theme["Text"], $fontSize + 3, FontWeight -> "DemiBold"]],
					primitives
				},
				fontScale[size_] :> Scaled[size / (width + 2 side)]
			],
			Sequence @@ options,
			PlotRange -> {{-side, width + side}, {-height - $margin, Last[titleSize] + $margin}},
			PlotRangePadding -> None,
			ImagePadding -> None,
			ImageSize -> Round[width + 2 side]
		]
	]
]

(* ::Section:: *)
(*Flowcharts*)

(* the style of a node or a subgraph: the class default, its classes in order, then its own *)
mergedStyle[data_, item_] := Association[
	Lookup[data["ClassDefinitions"], "default", <||>],
	Lookup[data["ClassDefinitions"], item["Classes"], <||>],
	item["Style"]
]

flowBox[data_][node_] := With[{
	style = shapeStyle[mergedStyle[data, node], $theme["NodeFill"], $theme["NodeEdge"], $theme["Text"]],
	size = shapeSize[node["Shape"], textSize[node["Label"]]]
},
	<|
		"Size" -> size,
		"Parent" -> node["Parent"],
		"Kind" -> node["Shape"],
		"Draw" -> Function[center, {shapePrimitives[node["Shape"], center, size, style], textAt[node["Label"], center + textOffset[node["Shape"], size], style["Text"]]}]
	|>
]

flowScene[data_] := <|
	"Direction" -> data["Direction"],
	"Boxes" -> Map[flowBox[data], data["Nodes"]],
	"Groups" -> Map[Append[#, "Style" -> mergedStyle[data, #]] &, data["Subgraphs"]],
	"Links" -> data["Edges"]
|>

(* ::Section:: *)
(*State diagrams*)

(* a note: a box of its own, joined to what it is about by a dotted line *)
noteBox[text_String, parent_] := With[{size = textSize[text] + {20, 14}},
	<|
		"Size" -> size, "Parent" -> parent, "Kind" -> "Rectangle",
		"Draw" -> Function[center, {
			{FaceForm[$theme["NoteFill"]], EdgeForm[Directive[$theme["NoteEdge"], AbsoluteThickness[1]]], Polygon[roundedOutline[center, size, 3]]},
			textAt[text, center, $theme["Text"]]
		}]
	|>
]

noteLink[from_, to_] := <|"From" -> from, "To" -> to, "Length" -> 1, "Label" -> None, "Line" -> "Dotted", "Head" -> "None", "Tail" -> "None", "Style" -> <||>|>

stateBox[data_, direction_][state_] := With[{
	style = shapeStyle[mergedStyle[data, state], $theme["NodeFill"], $theme["NodeEdge"], $theme["Text"]],
	text = If[state["Descriptions"] === {}, state["Label"], StringRiffle[If[state["Label"] === "" || Length[state["Descriptions"]] === 1, state["Descriptions"], Prepend[state["Descriptions"], state["Label"]]], "\n"]]
},
	With[{
		kind = Replace[state["Kind"], {"State" -> "Rounded", "Fork" | "Join" -> "Bar"}],
		size = Switch[state["Kind"],
			"Start", {16, 16},
			"End", {20, 20},
			"Choice", {30, 30},
			"Fork" | "Join", If[MatchQ[direction, "LR" | "RL"], {8, 70}, {70, 8}],
			_, shapeSize["Rounded", textSize[text]]
		]
	},
		<|
			"Size" -> size, "Parent" -> state["Parent"], "Kind" -> kind,
			"Draw" -> Function[center, {
				shapePrimitives[kind, center, size, style],
				If[state["Kind"] === "State", textAt[text, center, style["Text"]], {}]
			}]
		|>
	]
]

stateScene[data_] := With[{
	composite = Select[data["States"], #Kind === "Composite" &],
	notes = Association @ MapIndexed["note_" <> ToString[First[#2]] -> #1 &, data["Notes"]]
},
	<|
		"Direction" -> data["Direction"],
		"Boxes" -> Join[
			Map[stateBox[data, data["Direction"]], KeyDrop[data["States"], Keys[composite]]],
			Map[noteBox[#Text, Lookup[data["States"], #State, <|"Parent" -> None|>]["Parent"]] &, notes]
		],
		"Groups" -> Map[<|"Title" -> #Label, "Parent" -> #Parent, "Direction" -> None, "Style" -> mergedStyle[data, #]|> &, composite],
		"Links" -> Join[
			Map[<|"From" -> #From, "To" -> #To, "Length" -> 1, "Label" -> #Label, "Line" -> "Normal", "Head" -> "Arrow", "Tail" -> "None", "Style" -> <||>|> &, data["Transitions"]],
			KeyValueMap[noteLink[#2["State"], #1] &, notes]
		]
	|>
]

(* ::Section:: *)
(*Class diagrams*)

(* a class: its name under its annotations, then its attributes, then its methods, a line between the parts *)
classBox[data_][class_] := Module[{
	style = shapeStyle[mergedStyle[data, class], $theme["NodeFill"], $theme["NodeEdge"], $theme["Text"]],
	head = Append[Map["\[LeftGuillemet]" <> # <> "\[RightGuillemet]" &, class["Annotations"]], class["Label"]],
	row = 1.35 $fontSize, width, parts, heights, size
},
	parts = {head, class["Attributes"], class["Methods"]};
	width = Max[Max[First[textSize[#]] & /@ Catenate[parts], 40] + 32, First[textSize[class["Label"], $fontSize + 1]] + 28];
	heights = Map[Max[Length[#], 0.6] row + 10 &, parts];
	size = {width, Total[heights]};
	<|
		"Size" -> size, "Parent" -> class["Parent"], "Kind" -> "Rectangle",
		"Draw" -> Function[center,
			With[{left = First[center] - width / 2, top = Last[center] + Last[size] / 2, tops = Accumulate[Prepend[Most[heights], 0]]},
				{
					shapePrimitives["Rectangle", center, size, style],
					{style["Edge"], Map[Line[{{left, top - #}, {left + width, top - #}}] &, Rest[tops]]},
					MapIndexed[
						textAt[#1, {First[center], top - 5 - (row (First[#2] - 0.5))}, style["Text"], $fontSize, If[First[#2] === Length[head], FontWeight -> "DemiBold", FontSlant -> "Italic"]] &,
						head
					],
					MapThread[
						Function[{lines, partTop},
							MapIndexed[textFrom[#1, {left + 10, top - partTop - 5 - (row (First[#2] - 0.5))}, style["Text"]] &, lines]
						],
						{Rest[parts], Rest[tops]}
					]
				}
			]
		]
	|>
]

classScene[data_] := With[{notes = Association @ MapIndexed["note_" <> ToString[First[#2]] -> #1 &, data["Notes"]]},
	<|
		"Direction" -> data["Direction"],
		"Boxes" -> Join[Map[classBox[data], data["Classes"]], Map[noteBox[#Text, None] &, notes]],
		"Groups" -> data["Namespaces"],
		"Links" -> Join[
			Map[Join[#, <|"Length" -> 1, "Line" -> Replace[#Line, "Solid" -> "Normal"], "Style" -> <||>|>] &, data["Relations"]],
			Cases[Normal[notes], (name_ -> note_) /; note["Class"] =!= None :> noteLink[note["Class"], name]]
		]
	|>
]

(* ::Section:: *)
(*Sequence diagrams*)

(* A column for each participant, in order, and a row for each event, down the page. The primitives
	are sown by layer: the frames of blocks, the lifelines and activation bars, the messages, the notes. *)

$headerHeight = 38

participantSize[participant_] := {Max[First[textSize[participant["Label"]]] + 28, 72], $headerHeight}

(* the header of a participant, its box centered at a point; an actor is a figure over its name *)
participantPrimitives[participant_, {x_, y_}] := If[participant["Kind"] === "Actor",
	{
		{$theme["NodeEdge"], AbsoluteThickness[1.4], CapForm["Round"],
			Line[{{x, y + 6}, {x, y - 3}}], Line[{{x - 9, y + 3}, {x + 9, y + 3}}], Line[{{x - 8, y - 12}, {x, y - 3}, {x + 8, y - 12}}]},
		{FaceForm[$theme["NodeFill"]], EdgeForm[Directive[$theme["NodeEdge"], AbsoluteThickness[1.4]]], Disk[{x, y + 11}, 5.5]},
		textAt[participant["Label"], {x, y - 22}, $theme["Text"]]
	},
	{
		{FaceForm[$theme["NodeFill"]], EdgeForm[Directive[$theme["NodeEdge"], AbsoluteThickness[1.2]]], Polygon[roundedOutline[{x, y}, participantSize[participant], 4]]},
		textAt[participant["Label"], {x, y}, $theme["Text"]]
	}
]

(* the centers of the columns: neighbors far enough apart for their headers and for the text that goes between them *)
columnCenters[data_] := Module[{
	names = Keys[data["Participants"]], widths, index, between, spans, centers
},
	widths = First @* participantSize /@ Values[data["Participants"]];
	index = AssociationThread[names, Range[Length[names]]];
	between = Table[(widths[[i]] + widths[[i + 1]]) / 2 + 28, {i, Length[names] - 1}];
	(* what each event needs between the columns it lies on: {first column, last column, width} *)
	spans = Cases[data["Events"], event_ :> With[{width = First[textSize[Lookup[event, "Text", ""]]]},
		Switch[{event["Event"], Lookup[event, "Placement", None]},
			{"Message", _}, With[{a = index[event["From"]], b = index[event["To"]]}, If[a === b, {a, a + 1, width + 62}, {Min[a, b], Max[a, b], width + 36}]],
			{"Note", "RightOf"}, With[{a = index[First[event["Participants"]]]}, {a, a + 1, width + 44}],
			{"Note", "LeftOf"}, With[{a = index[First[event["Participants"]]]}, {a - 1, a, width + 44}],
			_, Nothing
		]
	]];
	between = Fold[
		Function[{gaps, span},
			With[{range = Range[Max[span[[1]], 1], Min[span[[2]] - 1, Length[gaps]]]},
				If[range === {} || Total[gaps[[range]]] >= span[[3]], gaps, ReplacePart[gaps, Thread[range -> gaps[[range]] + (span[[3]] - Total[gaps[[range]]]) / Length[range]]]]
			]
		],
		between,
		SortBy[spans, #[[2]] - #[[1]] &]
	];
	centers = Accumulate[Prepend[between, 0.]];
	AssociationThread[names, centers]
]

sequencePrimitives[data_] := Module[{
	columns = columnCenters[data], y, lastLine, active = <||>, blocks = {}, number = 0, left, right, grow, sown, primitives, bottom,
	header = $headerHeight + If[MemberQ[Values[data["Participants"]][[All, "Kind"]], "Actor"], 12, 0]
},
	If[Length[columns] === 0, Return[{{}, {0, 0}}, Module]];
	left = Min[KeyValueMap[columns[#1] - First[participantSize[#2]] / 2 &, data["Participants"]]];
	right = Max[KeyValueMap[columns[#1] + First[participantSize[#2]] / 2 &, data["Participants"]]];
	(* what is drawn from x1 to x2 widens the drawing and every open block *)
	grow[x1_, x2_] := (
		left = Min[left, x1];
		right = Max[right, x2];
		blocks = Map[Append[#, {"Left" -> Min[#Left, x1], "Right" -> Max[#Right, x2]}] &, blocks]
	);
	y = header + 16;
	lastLine = y;
	sown = Reap[
		Scan[
			Function[event,
				Switch[event["Event"],
					"Message",
						number++;
						With[{from = columns[event["From"]], to = columns[event["To"]], size = textSize[event["Text"]], color = $theme["Line"]},
							With[{directives = Directive[color, AbsoluteThickness[1.3], If[event["Line"] === "Dotted", AbsoluteDashing[{3, 3}], AbsoluteDashing[{}]], CapForm["Round"], JoinForm["Round"]]},
								If[from == to,
									y += 8;
									Sow[{
										{directives, Line[{{from, -y}, {from + 34, -y}, {from + 34, -y - 22}, {from + headLength[event["Head"]], -y - 22}}]},
										headPrimitives[event["Head"], {from, -y - 22}, {-1., 0.}, color],
										If[event["Text"] === "", {}, textFrom[event["Text"], {from + 42, -y - 11}, $theme["Text"]]],
										If[TrueQ[data["Autonumber"]], numberPrimitives[number, {from, -y}], {}]
									}, "Messages"];
									grow[from - 10, from + 48 + First[size]];
									y += 22;
									lastLine = y;
									y += 16,
									y += Last[size] + 10;
									With[{direction = {Sign[to - from], 0.}},
										Sow[{
											{directives, Line[{{from, -y} + headLength[event["Tail"]] direction, {to, -y} - (headLength[event["Head"]] direction)}]},
											headPrimitives[event["Head"], {to, -y}, direction, color],
											headPrimitives[event["Tail"], {from, -y}, -direction, color],
											If[event["Text"] === "", {}, textAt[event["Text"], {(from + to) / 2, -y + Last[size] / 2 + 5}, $theme["Text"]]],
											If[TrueQ[data["Autonumber"]], numberPrimitives[number, {from, -y}], {}]
										}, "Messages"]
									];
									grow[Min[from, to] - 10, Max[from, to] + 10];
									lastLine = y;
									y += 16
								]
							]
						],
					"Note",
						With[{size = textSize[event["Text"]] + {18, 12}, xs = columns /@ event["Participants"]},
							With[{span = Switch[event["Placement"],
								"RightOf", {First[xs] + 14, First[xs] + 14 + First[size]},
								"LeftOf", {First[xs] - 14 - First[size], First[xs] - 14},
								_, With[{width = Max[First[size], Max[xs] - Min[xs] + 40]}, Mean[xs] + {-width, width} / 2]
							]},
								y += 4;
								Sow[{
									{FaceForm[$theme["NoteFill"]], EdgeForm[Directive[$theme["NoteEdge"], AbsoluteThickness[1]]], Polygon[roundedOutline[{Mean[span], -y - Last[size] / 2}, {span[[2]] - span[[1]], Last[size]}, 3]]},
									textAt[event["Text"], {Mean[span], -y - Last[size] / 2}, $theme["Text"]]
								}, "Notes"];
								grow @@ span;
								y += Last[size] + 14
							]
						],
					"Activate",
						active[event["Participant"]] = Append[Lookup[active, event["Participant"], {}], lastLine],
					"Deactivate",
						With[{open = Lookup[active, event["Participant"], {}]},
							If[open =!= {},
								Sow[activationBar[columns[event["Participant"]], Last[open], lastLine, Length[open]], "Bars"];
								active[event["Participant"]] = Most[open]
							]
						],
					"BlockStart",
						y += 6;
						blocks = Append[blocks, <|"Top" -> y, "Kind" -> event["Kind"], "Label" -> event["Label"], "Left" -> Infinity, "Right" -> -Infinity, "Branches" -> {}|>];
						y += 28,
					"BlockBranch",
						If[blocks =!= {},
							y += 2;
							blocks = Append[Most[blocks], Append[Last[blocks], "Branches" -> Append[Last[blocks]["Branches"], {y, event["Label"]}]]];
							y += 24
						],
					"BlockEnd",
						If[blocks =!= {},
							With[{block = Last[blocks]},
								With[{x1 = If[block["Left"] === Infinity, Min[columns] - 20, block["Left"]] - 50, x2 = If[block["Right"] === -Infinity, Max[columns] + 20, block["Right"]] + 12},
									blocks = Most[blocks];
									Sow[blockFrame[block, x1, x2, y], "Frames"];
									grow[x1, x2];
									y += 14
								]
							]
						],
					_,
						Null
				]
			],
			data["Events"]
		],
		{"Frames", "Bars", "Messages", "Notes"}
	];
	bottom = y + 6;
	primitives = {
		KeyValueMap[{$theme["GroupEdge"], AbsoluteThickness[1], AbsoluteDashing[{4, 4}], Line[{{columns[#1], -header}, {columns[#1], -bottom}}]} &, data["Participants"]],
		sown[[2, 2]],
		(* a participant still active at the end is active to the end *)
		KeyValueMap[Function[{name, open}, MapIndexed[activationBar[columns[name], #1, bottom - 6, First[#2]] &, open]], active],
		sown[[2, 1]],
		sown[[2, 3]],
		sown[[2, 4]],
		KeyValueMap[participantPrimitives[#2, {columns[#1], -header + $headerHeight / 2}] &, data["Participants"]],
		KeyValueMap[participantPrimitives[#2, {columns[#1], -bottom - $headerHeight / 2 - If[#2["Kind"] === "Actor", 12, 0]}] &, data["Participants"]]
	};
	{Translate[primitives, {-left, 0}], {right - left, bottom + header}}
]

activationBar[x_, top_, bottom_, depth_] :=
	{FaceForm[$theme["LabelFill"]], EdgeForm[Directive[$theme["NodeEdge"], AbsoluteThickness[1]]], Rectangle[{x - 5 + 4 (depth - 1), -Max[bottom, top + 8]}, {x + 5 + 4 (depth - 1), -top}]}

numberPrimitives[number_, {x_, y_}] := {
	{FaceForm[$theme["Solid"]], EdgeForm[None], Disk[{x, y}, 8]},
	textAt[ToString[number], {x, y}, LightDarkSwitched[GrayLevel[1], GrayLevel[0.1]], $fontSize - 3, FontWeight -> "DemiBold"]
}

(* the text of a block or a branch between brackets, on a ground of its own, since a lifeline may pass behind it *)
bracketLabel[text_String, {x_, y_}] := With[{size = textSize["[" <> text <> "]", $fontSize - 1]},
	{
		{Opacity[0.88], FaceForm[$theme["Ground"]], EdgeForm[None], Polygon[roundedOutline[{x + First[size] / 2, y}, size + {6, 2}, 3]]},
		textFrom["[" <> text <> "]", {x, y}, $theme["Text"], $fontSize - 1]
	}
]

(* the frame of a block from its top to y: its kind in a tab at the corner, its label beside it, a dashed line at each branch *)
blockFrame[block_, x1_, x2_, y_] := With[{tab = First[textSize[block["Kind"], $fontSize - 1]] + 14},
	{
		If[block["Kind"] === "rect",
			{Opacity[0.09], FaceForm[$theme["GroupFill"]], EdgeForm[None], Rectangle[{x1, -y}, {x2, -block["Top"]}]},
			{
				{FaceForm[None], EdgeForm[Directive[$theme["GroupEdge"], AbsoluteThickness[1.1]]], Rectangle[{x1, -y}, {x2, -block["Top"]}]},
				{FaceForm[$theme["LabelFill"]], EdgeForm[Directive[$theme["GroupEdge"], AbsoluteThickness[1.1]]],
					Polygon[{{x1, -block["Top"]}, {x1 + tab, -block["Top"]}, {x1 + tab, -block["Top"] - 13}, {x1 + tab - 7, -block["Top"] - 20}, {x1, -block["Top"] - 20}}]},
				textFrom[block["Kind"], {x1 + 6, -block["Top"] - 10}, $theme["Text"], $fontSize - 1, FontWeight -> "DemiBold"],
				If[block["Label"] === "", {}, bracketLabel[block["Label"], {x1 + tab + 8, -block["Top"] - 10}]],
				Map[
					{
						{$theme["GroupEdge"], AbsoluteThickness[1], AbsoluteDashing[{4, 3}], Line[{{x1, -First[#]}, {x2, -First[#]}}]},
						If[Last[#] === "", {}, bracketLabel[Last[#], {x1 + 8, -First[#] - 12}]]
					} &,
					block["Branches"]
				]
			}
		]
	}
]

(* ::Section:: *)
(*MermaidDiagram and MermaidGraph*)

Options[MermaidDiagram] = Options[Graphics]

MermaidDiagram[source_String, options : OptionsPattern[]] := With[{data = MermaidRead[source]},
	If[FailureQ[data], data, MermaidDiagram[data, options]]
]

MermaidDiagram[data_Association, options : OptionsPattern[]] /; data["Type"] === "Flowchart" :=
	drawing[Sequence @@ scenePrimitives[flowScene[data]], data["Title"], {options}]

MermaidDiagram[data_Association, options : OptionsPattern[]] /; data["Type"] === "State" :=
	drawing[Sequence @@ scenePrimitives[stateScene[data]], data["Title"], {options}]

MermaidDiagram[data_Association, options : OptionsPattern[]] /; data["Type"] === "Class" :=
	drawing[Sequence @@ scenePrimitives[classScene[data]], data["Title"], {options}]

MermaidDiagram[data_Association, options : OptionsPattern[]] /; data["Type"] === "Sequence" :=
	drawing[Sequence @@ sequencePrimitives[data], data["Title"], {options}]

(* the Graph of a diagram of boxes and links: a vertex for each box, labeled, and a directed edge for each link *)
MermaidGraph[source_String, options : OptionsPattern[Graph]] := With[{data = MermaidRead[source]},
	If[FailureQ[data], data, MermaidGraph[data, options]]
]

MermaidGraph[data_Association, options : OptionsPattern[Graph]] /; MatchQ[data["Type"], "Flowchart" | "State" | "Class"] := With[{
	boxes = data[Replace[data["Type"], {"Flowchart" -> "Nodes", "State" -> "States", "Class" -> "Classes"}]],
	links = data[Replace[data["Type"], {"Flowchart" -> "Edges", "State" -> "Transitions", "Class" -> "Relations"}]]
},
	With[{vertices = DeleteDuplicates[Join[Keys[boxes], Catenate[{#From, #To} & /@ links]]]},
		Graph[
			vertices,
			DirectedEdge[#From, #To] & /@ links,
			options,
			VertexLabels -> Map[# -> Lookup[boxes, #, <|"Label" -> #|>]["Label"] &, vertices],
			EdgeLabels -> DeleteDuplicatesBy[Cases[links, link_ /; StringQ[link["Label"]] :> DirectedEdge[link["From"], link["To"]] -> link["Label"]], First],
			GraphLayout -> {"LayeredDigraphEmbedding", "Orientation" -> Replace[data["Direction"], {"TB" -> Top, "BT" -> Bottom, "LR" -> Left, "RL" -> Right}]}
		]
	]
]

End[]

EndPackage[]

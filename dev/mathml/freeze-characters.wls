(* Records the characters Wolfram 15.0's MathML reader gives otherwise than Unicode has them, into
   Parser/Kernel/Languages/MathMLCharacters.tsv: a line for each, the code a document gives, a tab, and the codes
   read for it, in decimal: the double-struck, script and Gothic letters, the differential and exponential signs
   and the like, which the Wolfram Language keeps at codes of its own. Every character of XML in planes 0 and 1 is asked for by a character reference.
   Run with the 15.0 kernel:  WolframKernel -noinit -script dev/mathml/freeze-characters.wls *)

here = DirectoryName[$InputFileName];
codes = Select[Join[Range[33, 55295], Range[57344, 65533], Range[65536, 131071]], ! MemberQ[{60, 38}, #] &];
read[chunk_List] := Replace[
	ImportString["<math>" <> StringJoin[Map["<mi xml:space='preserve'>&#" <> ToString[#] <> ";</mi>" &, chunk]] <> "</math>", {"MathML", "XMLElement"}],
	{XMLElement["math", _, children_List] /; Length[children] === Length[chunk] :> Map[Replace[#, {XMLElement["mi", _, {s_String}] :> ToCharacterCode[s], _ -> {}}] &, children], _ -> Table[Missing[], Length[chunk]]}
];
pairs = Catenate[Map[Transpose[{#, read[#]}] &, Partition[codes, UpTo[5000]]]];
(* a character past plane 0 that the reader does not rename comes back as its two surrogates, which is no renaming *)
changed = Select[pairs, MatchQ[#[[2]], {_Integer}] && #[[2]] =!= {#[[1]]} &];
out = FileNameJoin[{ParentDirectory[ParentDirectory[here]], "Parser", "Kernel", "Languages", "MathMLCharacters.tsv"}];
BinaryWrite[out, StringToByteArray[StringJoin[Map[{ToString[#[[1]]], "\t", If[ListQ[#[[2]]], StringRiffle[ToString /@ #[[2]], " "], "?"], "\n"} &, changed]], "UTF-8"]];
Close[out];
Print[Length[pairs], " asked, ", Length[changed], " changed, ", Count[pairs, {_, _Missing}], " unread"];

(* Records the character Wolfram 15.0 reads for each entity name MathML declares, into
   Parser/Kernel/Languages/MathMLEntities.tsv: a line for each name, the name, a tab, and the codes of its characters
   in decimal with spaces between. A name the reader does not find, though a file declares it, is left out. The names are those the entity files of the installation's MathML DTDs declare.
   Run with the 15.0 kernel:  WolframKernel -noinit -script dev/mathml/freeze-entities.wls *)

here = DirectoryName[$InputFileName];
xml = FileNameJoin[{$InstallationDirectory, "SystemFiles", "IncludeFiles", "XML"}];
files = FileNames["*.ent" | "*.dtd" | "*.mod", xml, Infinity];
names = Union[Catenate[Map[
	StringCases[ByteArrayToString[ReadByteArray[#], "ISO8859-1"], "<!ENTITY" ~~ Whitespace ~~ name : Except[WhitespaceCharacter | "%"] .. ~~ Whitespace :> name] &,
	files
]]];
Off[XML`Parser`XMLGetString::prserr]; Off[XML`Parser`XMLGetString::nfprserr]; Off[General::stop];
codes[name_String] := Replace[
	ImportString["<math><mi xml:space='preserve'>&" <> name <> ";</mi></math>", {"MathML", "XMLElement"}],
	{XMLElement["math", _, {XMLElement["mi", _, {s_String}]}] /; StringFreeQ[s, "\[EntityStart]"] :> ToCharacterCode[s], _ -> Missing[]}
];
table = DeleteMissing[AssociationMap[codes, names]];
(* the five entities of XML itself are the grammar's *)
table = KeyDrop[table, {"lt", "gt", "amp", "quot", "apos"}];
out = FileNameJoin[{ParentDirectory[ParentDirectory[here]], "Parser", "Kernel", "Languages", "MathMLEntities.tsv"}];
BinaryWrite[out, StringToByteArray[StringJoin[KeyValueMap[{#1, "\t", StringRiffle[ToString /@ #2, " "], "\n"} &, table]], "UTF-8"]];
Close[out];
Print[Length[names], " names, ", Length[table], " read, ", FileByteCount[out], " bytes"];
Print[Complement[names, Keys[table]]];

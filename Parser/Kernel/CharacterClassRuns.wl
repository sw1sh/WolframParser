(* ::Package:: *)

(* :Title: CharacterClassRuns.wl - the characters of the classes string patterns name *)
(* :Context: Wolfram`Parser`Private` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The characters of the classes string patterns name, as Wolfram 15 matches them: the runs of
    code points that dev/freeze-character-classes.wls records in CharacterClasses.wl beside this
    file. The paclet's core reads them for ParserCompile's classes, and the engine of string
    patterns for its own; each loads this file, so that the engine loads with nothing else.
*)

Begin["Wolfram`Parser`Private`"]

$characterClassFile = FileNameJoin[{DirectoryName[$InputFileName], "CharacterClasses.wl"}];

(* class -> {{first, last}, ...} runs of code points, or the name of the class before it with the
   same characters; Missing where the file or the class is not there. The file is read by Get
   alone, which a kernel that carries it in its units answers without the disk. *)
characterClassRuns[] := characterClassRuns[] = Replace[Get[$characterClassFile], {
    classes_Association :> Map[Replace[#, runs_List :> Developer`ToPackedArray[runs]] &, classes],
    _ :> <||>}]
characterClassRuns[class_String] := Replace[Lookup[characterClassRuns[], class, regexPropertyRuns[class]], same_String :> characterClassRuns[same]]

(* A general category of a regex, "regex \p{name}": its runs from RegexProperties.wl beside this
   file, read by Get alone when one is first asked for *)
$regexPropertyFile = FileNameJoin[{DirectoryName[$InputFileName], "RegexProperties.wl"}];
regexProperties[] := regexProperties[] = Replace[Get[$regexPropertyFile], {
    properties_Association :> Map[Replace[#, runs_List :> Developer`ToPackedArray[runs]] &, properties],
    _ :> <||>}]
regexPropertyRuns[class_String] := If[StringStartsQ[class, "regex \\p{"],
    Replace[Lookup[regexProperties[], StringTake[class, {10, -2}], Missing["NotRecorded", class]], same_String :> "regex \\p{" <> same <> "}"],
    Missing["NotRecorded", class]]

End[]

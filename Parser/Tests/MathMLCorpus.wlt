(* :Title: MathMLCorpus.wlt - the MathML reader against Wolfram 15.0 on presentation and content MathML *)
(* :Context: Wolfram`Parser` *)
(* :Summary: mathml-cases.json holds what Wolfram 15.0 gives for each input of the corpus dev/mathml/corpus.wl.
   A count below is of the cases the reader answers the same, out of the cases of the corpus, with the kernel of
   wl, Wolfram 15.1, typesetting content MathML; it moves only when the reader changes. dev/mathml/parity.wls
   prints every count, and the differences. Run via run-tests.wls. *)

$mathmlCases := $mathmlCases = Developer`ReadRawJSONFile[FileNameJoin[{DirectoryName[$TestFileName], "mathml-cases.json"}]]
$mathmlSame[mine_, recorded_String] := ToString[FullForm[mine], CharacterEncoding -> "ASCII"] === recorded || mine === Quiet[ToExpression[recorded], {Syntax::sntxf, ToExpression::esntx, FromCharacterCode::intnm}]
mathmlParity[corpus_String, field_String, read_] := With[{cases = Select[$mathmlCases, #Corpus === corpus &]},
    {
        Count[cases, case_ /; $mathmlSame[
            Quiet[read[case["Input"]], {MathMLBoxes::prserr, MathMLBoxes::nfprserr, MathMLBoxes::incrt, MathMLBoxes::unkntag, MathMLBoxes::unknstrc,
                MathMLBoxes::msngargs, MathMLBoxes::bmml, MathMLBoxes::nmmlr}],
            case[field]]],
        Length[cases]
    }
]

VerificationTest[mathmlParity["presentation", "XMLElement", MathMLImport[#, "XMLElement"] &], {1257, 1257}, TestID -> "mathml parity: presentation, XMLElement"]
VerificationTest[mathmlParity["presentation", "Boxes", MathMLBoxes], {1225, 1257}, TestID -> "mathml parity: presentation, boxes"]
VerificationTest[mathmlParity["presentation", "Held", MathMLHeld], {1189, 1257}, TestID -> "mathml parity: presentation, held expressions"]
VerificationTest[mathmlParity["content", "XMLElement", MathMLImport[#, "XMLElement"] &], {838, 838}, TestID -> "mathml parity: content, XMLElement"]
VerificationTest[mathmlParity["content", "Boxes", MathMLBoxes], {789, 838}, TestID -> "mathml parity: content, boxes"]
VerificationTest[mathmlParity["content", "Held", MathMLHeld], {792, 838}, TestID -> "mathml parity: content, held expressions"]

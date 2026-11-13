(* :Title: MathMLRoundTrip.wlt - the MathML reader against Wolfram 15.0 on the MathML Wolfram 15.0 writes *)
(* :Context: Wolfram`Parser` *)
(* :Summary: mathml-cases.json holds, for each expression of dev/mathml/roundtrip.wl, the MathML Wolfram 15.0
   exports for it, as presentation, as content and as both, and what its readers give back for that text. A count
   below is of the cases the reader answers the same, out of the cases of the corpus, with the kernel of wl,
   Wolfram 15.1, typesetting content MathML; it moves only when the reader changes. dev/mathml/parity.wls prints
   every count, and the differences. Run via run-tests.wls. *)

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

VerificationTest[mathmlParity["roundtrip-presentation", "Boxes", MathMLBoxes], {470, 472}, TestID -> "mathml round trip: presentation, boxes"]
VerificationTest[mathmlParity["roundtrip-presentation", "Held", MathMLHeld], {454, 472}, TestID -> "mathml round trip: presentation, held expressions"]
VerificationTest[mathmlParity["roundtrip-content", "Boxes", MathMLBoxes], {463, 470}, TestID -> "mathml round trip: content, boxes"]
VerificationTest[mathmlParity["roundtrip-content", "Held", MathMLHeld], {449, 470}, TestID -> "mathml round trip: content, held expressions"]
VerificationTest[mathmlParity["roundtrip-both", "Boxes", MathMLBoxes], {467, 472}, TestID -> "mathml round trip: presentation and content, boxes"]
VerificationTest[mathmlParity["roundtrip-both", "Held", MathMLHeld], {438, 472}, TestID -> "mathml round trip: presentation and content, held expressions"]

(* :Title: MathML.wlt - the MathML reader *)
(* :Context: Wolfram`Parser` *)
(* :Summary: boxes, held expressions and import elements of presentation and content MathML, and the parity of the
   reader with Wolfram 15.0 on the xml corpus of mathml-cases.json, which dev/mathml/record.wls records. The other
   corpora are in MathMLCorpus.wlt and MathMLRoundTrip.wlt. Run via run-tests.wls. *)

$tag[boxes_] := FormBox[TagBox[boxes, "MathMLPresentationTag", AutoDelete -> True], TraditionalForm]
$content[boxes_] := FormBox[TagBox[boxes, "MathMLContentTag", AutoDelete -> True], TraditionalForm]

(* === boxes of presentation MathML === *)
VerificationTest[MathMLBoxes["<math><mi>x</mi></math>"], $tag["x"], TestID -> "mathml: an identifier"]
VerificationTest[MathMLBoxes["<math xmlns='http://www.w3.org/1998/Math/MathML' display='block'>\n <mi> x </mi>\n</math>"], $tag["x"],
    TestID -> "mathml: the namespace, an attribute of math and whitespace change nothing"]
VerificationTest[MathMLBoxes["<m:math xmlns:m='http://www.w3.org/1998/Math/MathML'><m:mi>x</m:mi></m:math>"], $tag["x"],
    TestID -> "mathml: a prefix for the namespace"]
VerificationTest[MathMLBoxes["<math><mfrac><mn>1</mn><mi>x</mi></mfrac></math>"], $tag[FractionBox["1", "x"]], TestID -> "mathml: a fraction"]
VerificationTest[MathMLBoxes["<math><msqrt><mi>x</mi><mo>+</mo><mn>1</mn></msqrt></math>"], $tag[SqrtBox[RowBox[{"x", "+", "1"}]]],
    TestID -> "mathml: a square root takes its children as a row"]
VerificationTest[MathMLBoxes["<math><mroot><mi>x</mi><mn>3</mn></mroot></math>"], $tag[RadicalBox["x", "3"]], TestID -> "mathml: a root"]
VerificationTest[MathMLBoxes["<math><msubsup><mi>x</mi><mn>1</mn><mn>2</mn></msubsup></math>"], $tag[SubsuperscriptBox["x", "1", "2"]],
    TestID -> "mathml: a subscript and a superscript"]
VerificationTest[MathMLBoxes["<math><munderover><mo>&sum;</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover></math>"],
    $tag[UnderoverscriptBox["\[Sum]", RowBox[{"i", "=", "1"}], "n"]], TestID -> "mathml: a sum sign with its limits"]
VerificationTest[MathMLBoxes["<math><mrow><mi>a</mi><mo>+</mo><mi>b</mi><mo>&InvisibleTimes;</mo><mi>c</mi></mrow></math>"],
    $tag[RowBox[{"a", "+", RowBox[{"b", " ", "c"}]}]], TestID -> "mathml: a row is grouped by the precedence of its operators"]
VerificationTest[MathMLBoxes["<math><mrow><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mo>*</mo><mi>c</mi></mrow></math>"],
    $tag[RowBox[{"a", "+", RowBox[{"b", "*", "c"}]}]], TestID -> "mathml: the rows within a row are read as one row"]
VerificationTest[MathMLBoxes["<math><mrow><mi>f</mi><mo>(</mo><mi>x</mi><mo>,</mo><mi>y</mi><mo>)</mo></mrow></math>"],
    $tag[RowBox[{"f", "(", RowBox[{"x", ",", "y"}], ")"}]], TestID -> "mathml: a parenthesis after a name applies it"]
VerificationTest[MathMLBoxes["<math><mrow><mn>2</mn><mo>(</mo><mi>x</mi><mo>)</mo></mrow></math>"],
    $tag[RowBox[{"2", RowBox[{"(", "x", ")"}]}]], TestID -> "mathml: a parenthesis after a number groups"]
VerificationTest[MathMLBoxes["<math><mi>&alpha;</mi><mo>&le;</mo><mi>&#x3B2;</mi></math>"],
    $tag[RowBox[{"\[Alpha]", "\[LessEqual]", "\[Beta]"}]], TestID -> "mathml: entities and character references"]
VerificationTest[MathMLBoxes["<math><mi>&ee;</mi><mi>&#x1D49C;</mi><mi>&Ropf;</mi></math>"],
    $tag[RowBox[{"\[ExponentialE]", "\[ScriptCapitalA]", "\[DoubleStruckCapitalR]"}]],
    TestID -> "mathml: the characters the Wolfram Language keeps at codes of its own"]
VerificationTest[MathMLBoxes["<math><mi mathvariant='bold'>v</mi></math>"],
    $tag[StyleBox["v", FontFamily -> "Times", FontWeight -> "Bold", FontSlant -> "Plain"]], TestID -> "mathml: mathvariant"]
VerificationTest[MathMLBoxes["<math><mi mathvariant='double-struck'>R</mi></math>"],
    $tag[StyleBox["\[DoubleStruckCapitalR]", FontFamily -> "Times", FontWeight -> "Plain", FontSlant -> "Plain"]], TestID -> "mathml: a letter of another alphabet"]
VerificationTest[MathMLBoxes["<math><mstyle mathcolor='#f00' mathsize='big'><mi>x</mi></mstyle></math>"],
    $tag[StyleBox["x", FontSize -> 18, FontColor -> RGBColor[1., 0., 0.]]], TestID -> "mathml: mstyle"]
VerificationTest[MathMLBoxes["<math><mtext>if </mtext></math>"], $tag[Cell["if", "Text"]], TestID -> "mathml: text"]
VerificationTest[MathMLBoxes["<math><mspace width='1em'/></math>"], $tag[AdjustmentBox["\[InvisibleSpace]", BoxMargins -> {{0, 1.}, {0, 0}}]],
    TestID -> "mathml: a space"]
VerificationTest[MathMLBoxes["<math><mfenced open='[' close=']'><mi>a</mi><mi>b</mi></mfenced></math>"],
    $tag[RowBox[{"[", RowBox[{"a", ",", "b"}], "]"}]], TestID -> "mathml: mfenced"]
VerificationTest[
    MathMLBoxes["<math><mtable columnalign='left'><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></mtable></math>"],
    $tag[GridBox[{{"1", "2"}, {"3", "4"}}, GridBoxAlignment -> {"Columns" -> {{Left}}, "Rows" -> {{Baseline}}}]], TestID -> "mathml: a table"]
VerificationTest[MathMLBoxes["<math></math>"], FormBox["", TraditionalForm], TestID -> "mathml: nothing"]

(* === boxes of content MathML === *)
VerificationTest[MathMLBoxes["<math><apply><plus/><ci>x</ci><cn>1</cn></apply></math>"], $content[RowBox[{"x", "+", "1"}]],
    TestID -> "mathml: content is typeset in TraditionalForm"]
VerificationTest[MathMLBoxes["<math><apply><sin/><ci>x</ci></apply></math>"], $content[RowBox[{"sin", "(", "x", ")"}]], TestID -> "mathml: a content function"]
VerificationTest[MathMLBoxes["<math><apply><divide/><cn>2</cn><cn>4</cn></apply></math>"], $content[FractionBox["2", "4"]],
    TestID -> "mathml: content is not evaluated"]
VerificationTest[MathMLBoxes["<math><mrow><ci>x</ci><mo>+</mo><mn>1</mn></mrow></math>"],
    $tag[RowBox[{TagBox["x", "MathMLContentTag", AutoDelete -> True], "+", "1"}]], TestID -> "mathml: content within presentation carries its tag"]
VerificationTest[
    MathMLBoxes["<math><semantics><mi>x</mi><annotation-xml encoding='MathML-Content'><ci>y</ci></annotation-xml></semantics></math>"],
    FormBox[TagBox[TagBox["x", "MathMLPresentationTag", AutoDelete -> True], "AnnotationsTagWrapper"[TagBox["y", "MathMLContentTag", AutoDelete -> True]], AutoDelete -> True], TraditionalForm],
    TestID -> "mathml: semantics keeps a MathML annotation beside its child"]
VerificationTest[
    MathMLBoxes["<math><semantics><mi>x</mi><annotation encoding='Mathematica'>TemplateBox[List[\"x\"], \"Abs\"]</annotation></semantics></math>"],
    FormBox[TemplateBox[{"x"}, "Abs"], TraditionalForm], TestID -> "mathml: an annotation of boxes is the boxes"]
VerificationTest[
    MathMLBoxes["<math><semantics><mi>x</mi><annotation encoding='Mathematica'>Print[1]</annotation></semantics></math>"],
    $tag["x"], TestID -> "mathml: an annotation that is not boxes is not evaluated"]

(* === symbolic XML, and what is not MathML === *)
VerificationTest[MathMLBoxes[XMLElement["math", {}, {XMLElement["msqrt", {}, {XMLElement["mi", {}, {"x"}]}]}]], $tag[SqrtBox["x"]],
    TestID -> "mathml: symbolic XML"]
VerificationTest[MathMLBoxes[XMLObject["Document"][{}, XMLElement["math", {}, {XMLElement["mi", {}, {"x"}]}], {}]], $tag["x"],
    TestID -> "mathml: a symbolic document"]
VerificationTest[MathMLBoxes["<math><mi>x</mi>"], $Failed, {MathMLBoxes::prserr}, TestID -> "mathml: text that is not well formed"]
VerificationTest[MathMLBoxes["<mi>x</mi>"], $tag["x"], {MathMLBoxes::incrt}, TestID -> "mathml: a root that is not math"]
VerificationTest[MathMLBoxes["<foo><mi>x</mi></foo>"], $Failed, {MathMLBoxes::nmmlr}, TestID -> "mathml: a root that is no MathML"]
VerificationTest[MathMLBoxes["<math><mi>&nosuch;</mi></math>"], $tag["\[EntityStart]nosuch\[EntityEnd]"], {MathMLBoxes::nfprserr},
    TestID -> "mathml: an entity MathML does not have"]
VerificationTest[MathMLBoxes["<math><mfrac><mn>1</mn></mfrac></math>"], $tag[RowBox[{"mfrac", "(", "1", ")"}]], {MathMLBoxes::unknstrc},
    TestID -> "mathml: an element with the wrong children"]

(* === held expressions === *)
VerificationTest[MathMLHeld["<math><mrow><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mn>1</mn></mrow></math>"], HoldComplete[x^2 + 1], TestID -> "mathml held: a sum"]
VerificationTest[MathMLHeld["<math><mrow><mn>1</mn><mo>+</mo><mn>2</mn></mrow></math>"], HoldComplete[1 + 2], TestID -> "mathml held: nothing is evaluated"]
VerificationTest[MathMLHeld["<math><mrow><mi>sin</mi><mo>&ApplyFunction;</mo><mo>(</mo><mi>x</mi><mo>)</mo></mrow></math>"], HoldComplete[Sin[x]],
    TestID -> "mathml held: a function TraditionalForm names"]
VerificationTest[MathMLHeld["<math><mrow><mi>f</mi><mo>&ApplyFunction;</mo><mrow><mo>(</mo><mrow><mi>x</mi><mo>,</mo><mi>y</mi></mrow><mo>)</mo></mrow></mrow></math>"],
    HoldComplete[f[x, y]], TestID -> "mathml held: an application sign"]
VerificationTest[MathMLHeld["<math><mrow><mn>2</mn><mo>&InvisibleTimes;</mo><mi>&pi;</mi><mo>&InvisibleTimes;</mo><mi>&ImaginaryI;</mi></mrow></math>"],
    HoldComplete[2 Pi I], TestID -> "mathml held: constants"]
VerificationTest[MathMLHeld["<math><mfrac><mi>a</mi><mi>b</mi></mfrac></math>"], HoldComplete[a b^-1], TestID -> "mathml held: a fraction"]
VerificationTest[MathMLHeld["<math><msqrt><mn>2</mn></msqrt></math>"], HoldComplete[Sqrt[2]], TestID -> "mathml held: a square root"]
VerificationTest[MathMLHeld["<math><msub><mi>a</mi><mrow><mi>i</mi><mo>,</mo><mi>j</mi></mrow></msub></math>"], HoldComplete[Subscript[a, i, j]],
    TestID -> "mathml held: subscripts"]
VerificationTest[MathMLHeld["<math><msup><mi>f</mi><mo>&prime;</mo></msup></math>"], HoldComplete[Derivative[1][f]], TestID -> "mathml held: a prime"]
VerificationTest[
    MathMLHeld["<math><mrow><munderover><mo>&sum;</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><msup><mi>i</mi><mn>2</mn></msup></mrow></math>"],
    HoldComplete[Sum[i^2, {i, 1, n}]], TestID -> "mathml held: a sum with its limits"]
VerificationTest[
    MathMLHeld["<math><mrow><msubsup><mo>&int;</mo><mn>0</mn><mn>1</mn></msubsup><mrow><mi>x</mi><mo>&InvisibleTimes;</mo><mrow><mo>&DifferentialD;</mo><mi>x</mi></mrow></mrow></mrow></math>"],
    HoldComplete[Integrate[x, {x, 0, 1}]], TestID -> "mathml held: an integral with its limits"]
VerificationTest[
    MathMLHeld["<math><mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></mtable></math>"],
    HoldComplete[{{1, 2}, {3, 4}}], TestID -> "mathml held: a table"]
VerificationTest[MathMLHeld["<math><mtext>if</mtext></math>"], HoldComplete[TextCell["if", "Text"]], TestID -> "mathml held: text"]
VerificationTest[MathMLHeld["<math><apply><divide/><cn>2</cn><cn>4</cn></apply></math>"], HoldComplete[2 4^-1], TestID -> "mathml held: content, read from its boxes"]
VerificationTest[MathMLHeld["<math><apply><eq/><ci>x</ci><apply><times/><cn>2</cn><ci>y</ci></apply></apply></math>"], HoldComplete[x == 2 y],
    TestID -> "mathml held: a content equation"]
VerificationTest[
    MathMLHeld["<math><apply><int/><bvar><ci>t</ci></bvar><lowlimit><cn>0</cn></lowlimit><uplimit><cn>1</cn></uplimit><apply><power/><ci>t</ci><cn>2</cn></apply></apply></math>"],
    HoldComplete[Integrate[t^2, {t, 0, 1}]], TestID -> "mathml held: a content integral"]
VerificationTest[MathMLHeld["<math><mrow><mi>x</mi><mo>+</mo></mrow></math>"], ErrorBox[FormBox[ErrorBox[RowBox[{"x", "+"}]], TraditionalForm]],
    TestID -> "mathml held: boxes that do not read"]
VerificationTest[MathMLHeld["<math><mi>x</mi>"], HoldComplete[$Failed], {MathMLBoxes::prserr}, TestID -> "mathml held: text that is not well formed"]

(* === expressions and import elements === *)
VerificationTest[MathMLExpression["<math><mrow><mn>1</mn><mo>+</mo><mn>2</mn></mrow></math>"], 3, TestID -> "mathml expression: evaluated"]
VerificationTest[MathMLExpression["<math><apply><sin/><apply><divide/><pi/><cn>2</cn></apply></apply></math>"], 1, TestID -> "mathml expression: content"]
VerificationTest[MathMLExpression["<math><mrow><mi>x</mi><mo>+</mo></mrow></math>"], $Failed, TestID -> "mathml expression: boxes that do not read"]
VerificationTest[MathMLImport["<math><mi>x</mi></math>", "Elements"], {"Boxes", "Expression", "HeldExpression", "XMLElement", "XMLObject"},
    TestID -> "mathml import: the elements"]
VerificationTest[MathMLImport["<math><mi>x</mi></math>"], MathMLBoxes["<math><mi>x</mi></math>"], TestID -> "mathml import: boxes where no element is named"]
VerificationTest[MathMLImport["<math><mn>2</mn><mo>+</mo><mn>2</mn></math>", "HeldExpression"], HoldComplete[2 + 2], TestID -> "mathml import: HeldExpression"]
VerificationTest[MathMLImport["<math><mn>2</mn><mo>+</mo><mn>2</mn></math>", "Expression"], 4, TestID -> "mathml import: Expression"]
VerificationTest[MathMLImport["<math><mrow><mi>x</mi><mo>+</mo></mrow></math>", "Expression"], ErrorBox[FormBox[ErrorBox[RowBox[{"x", "+"}]], TraditionalForm]],
    TestID -> "mathml import: Expression gives boxes that do not read as they are"]
VerificationTest[MathMLImport["<m:math xmlns:m='http://www.w3.org/1998/Math/MathML'><m:mi m:a='1'> x </m:mi><!-- c --></m:math>", "XMLElement"],
    XMLElement["math", {"m" -> "http://www.w3.org/1998/Math/MathML"}, {XMLElement["mi", {{"http://www.w3.org/1998/Math/MathML", "a"} -> "1"}, {"x"}]}],
    TestID -> "mathml import: XMLElement, names without prefixes and text without the whitespace around it"]
VerificationTest[MathMLImport["<!-- c --><math><mi>x</mi></math>", "XMLObject"],
    XMLObject["Document"][{XMLObject["Comment"][" c "]}, XMLElement["math", {}, {XMLElement["mi", {}, {"x"}]}], {}], TestID -> "mathml import: XMLObject"]

(* === parity with Wolfram 15.0 ===
   mathml-cases.json holds what Wolfram 15.0 gives for each input. A count below is of the cases the reader answers
   the same, out of the cases of the corpus; it moves only when the reader changes. dev/mathml/parity.wls prints
   every count, and the differences. *)
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

VerificationTest[mathmlParity["xml", "XMLElement", MathMLImport[#, "XMLElement"] &], {120, 123}, TestID -> "mathml parity: xml corpus, XMLElement"]
VerificationTest[mathmlParity["xml", "XMLObject", MathMLImport[#, "XMLObject"] &], {119, 123}, TestID -> "mathml parity: xml corpus, XMLObject"]
VerificationTest[mathmlParity["xml", "Boxes", MathMLBoxes], {120, 123}, TestID -> "mathml parity: xml corpus, boxes"]
VerificationTest[mathmlParity["xml", "Held", MathMLHeld], {119, 123}, TestID -> "mathml parity: xml corpus, held expressions"]

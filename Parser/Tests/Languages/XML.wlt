(* :Title: XML.wlt - the XML reader *)
(* :Context: Wolfram`Parser`Languages`XML` *)
(* :Summary: elements, attributes, text, references, comments, processing instructions, CDATA sections, the prolog,
   and what is not well formed. Run via run-tests.wls. *)

VerificationTest[XMLRead["<a/>"], XMLObject["Document"][{}, XMLElement["a", {}, {}], {}],
    TestID -> "xml: an empty element"]
VerificationTest[XMLRead["<a x='1'>t<b/></a>"],
    XMLObject["Document"][{}, XMLElement["a", {"x" -> "1"}, {"t", XMLElement["b", {}, {}]}], {}],
    TestID -> "xml: attributes, text and a child"]
VerificationTest[XMLRead["<a x = \"1\" y='it&apos;s'\n z=''/>"],
    XMLObject["Document"][{}, XMLElement["a", {"x" -> "1", "y" -> "it's", "z" -> ""}, {}], {}],
    TestID -> "xml: both quotes, whitespace around =, an empty value"]
VerificationTest[XMLRead["<a x='p\tq\nr'/>"],
    XMLObject["Document"][{}, XMLElement["a", {"x" -> "p q r"}, {}], {}],
    TestID -> "xml: whitespace in an attribute value is a space"]
VerificationTest[XMLRead["<a> x  y </a>"],
    XMLObject["Document"][{}, XMLElement["a", {}, {" x  y "}], {}],
    TestID -> "xml: text keeps its whitespace"]
VerificationTest[XMLRead["<a>&lt;&gt;&amp;&quot;&apos;</a>"],
    XMLObject["Document"][{}, XMLElement["a", {}, {"<>&\"'"}], {}],
    TestID -> "xml: the five entities of XML"]
VerificationTest[XMLRead["<a>&#65;&#x42;&#x3b1;</a>"],
    XMLObject["Document"][{}, XMLElement["a", {}, {"AB\[Alpha]"}], {}],
    TestID -> "xml: character references, decimal and hexadecimal"]
VerificationTest[XMLRead["<a>&nbsp;&foo;</a>", "Entities" -> <|"nbsp" -> "\[NonBreakingSpace]"|>],
    XMLObject["Document"][{}, XMLElement["a", {}, {"\[NonBreakingSpace]\[EntityStart]foo\[EntityEnd]"}], {}],
    TestID -> "xml: an entity the option gives, and one nothing gives"]
VerificationTest[XMLRead["<a>x<![CDATA[ <b> & ]]]>y</a>"],
    XMLObject["Document"][{}, XMLElement["a", {}, {"x <b> & ]y"}], {}],
    TestID -> "xml: a CDATA section is text, joined to the text around it"]
VerificationTest[XMLRead["<a>x<!-- c -->y<?pi go on?></a>"],
    XMLObject["Document"][{}, XMLElement["a", {}, {"x", XMLObject["Comment"][" c "], "y", XMLObject["ProcessingInstruction"]["pi", "go on"]}], {}],
    TestID -> "xml: a comment and a processing instruction in content"]
VerificationTest[XMLRead["<?xml version='1.0' encoding=\"UTF-8\" standalone='yes'?>\n<!-- c -->\n<a/>\n<?pi?>"],
    XMLObject["Document"][{XMLObject["Declaration"]["Version" -> "1.0", "Encoding" -> "UTF-8", "Standalone" -> "yes"], XMLObject["Comment"][" c "]},
        XMLElement["a", {}, {}], {XMLObject["ProcessingInstruction"]["pi", ""]}],
    TestID -> "xml: the declaration, and what stands before and after the element"]
VerificationTest[XMLRead["<!DOCTYPE math PUBLIC '-//W3C//DTD MathML 2.0//EN' \"http://www.w3.org/TR/MathML2/dtd/mathml2.dtd\" [ <!ENTITY a 'b'> ]><math/>"],
    XMLObject["Document"][{XMLObject["Doctype"]["math", "Public" -> "-//W3C//DTD MathML 2.0//EN", "System" -> "http://www.w3.org/TR/MathML2/dtd/mathml2.dtd",
        "InternalSubset" -> " <!ENTITY a 'b'> "]}, XMLElement["math", {}, {}], {}],
    TestID -> "xml: a document type declaration, its internal subset kept as text"]
VerificationTest[XMLRead["<m:a xmlns:m='u' m:x='1'><m:b/></m:a>"],
    XMLObject["Document"][{}, XMLElement["m:a", {"xmlns:m" -> "u", "m:x" -> "1"}, {XMLElement["m:b", {}, {}]}], {}],
    TestID -> "xml: names stay as they are written, prefix and all"]
VerificationTest[XMLRead["<\[Alpha]\[Beta] \:4e2d='1'>\|01d49c</\[Alpha]\[Beta]>"],
    XMLObject["Document"][{}, XMLElement["\[Alpha]\[Beta]", {"\:4e2d" -> "1"}, {"\|01d49c"}], {}],
    TestID -> "xml: names and text past ASCII"]
VerificationTest[XMLRead["<a>]] ] > ]>x</a>"],
    XMLObject["Document"][{}, XMLElement["a", {}, {"]] ] > ]>x"}], {}],
    TestID -> "xml: brackets in text that do not end a CDATA section"]

(* === what is not well formed === *)
VerificationTest[FailureQ[XMLRead[#]], True, TestID -> "xml: not well formed: " <> #] & /@ {
    "", "x", "<a>", "<a></b>", "<a><b></a>", "<a/>x", "<a/><b/>", "<a x=1/>", "<a x='1' x='2'/>", "<a x='<'/>", "<a>&</a>", "<a>&#0;</a>",
    "<a>&#xD800;</a>", "<a>]]></a>", "<a><!-- a -- b --></a>", "<1a/>", " <?xml version='1.0'?><a/>", "<a>&#x110000;</a>"
};
VerificationTest[XMLRead["<a><b></a>"]["Position"], 11,
    TestID -> "xml: a failure says where reading stopped"]
VerificationTest[XMLRead["<a></b>"][[2, "MessageParameters"]], {"a", "b"},
    TestID -> "xml: an end tag that names another element"]

(* === the grammar === *)
VerificationTest[StringContainsQ[XMLEBNF, "<Element>"] && StringContainsQ[XMLEBNF, "%tokens"], True,
    TestID -> "xml: the grammar is the text of XML.ebnf"]
VerificationTest[Parse[XMLGrammar[<|"e" -> "E"|>], "<a>&e;</a>"], {{}, XMLElement["a", {}, {"E"}], {}},
    TestID -> "xml: the parser of the grammar gives prolog, element and epilog"]

(* The expressions of the round trip: Wolfram 15.0 exports each as MathML, presentation, content and both,
   and what its readers give back for that text is what the paclet's reader gives. Each is evaluated as the list is made, HoldForm keeping what would change, and held from there on. *)

Module[{vars = {x, y, z, a, b, n}, unary, binary, atoms, bodies},
	atoms = {x, y, a, n, 0, 1, 2, -1, -3, 10, 123456789, 1/2, -2/3, 3/4, 1.5, -0.25, 2.5*^10, 1.*^-7, Pi, E, I, EulerGamma, Infinity, -Infinity,
		GoldenRatio, Degree, True, False, 2 + 3 I, 1.5 - 2. I, I/2, \[Alpha], \[Beta], \[CapitalGamma], \[Omega], x1, xy, "a string", "", "two words"};
	unary = {Sin, Cos, Tan, Cot, Sec, Csc, ArcSin, ArcCos, ArcTan, Sinh, Cosh, Tanh, ArcSinh, ArcTanh, Exp, Log, Sqrt, Abs, Floor, Ceiling, Round,
		Factorial, Gamma, Re, Im, Conjugate, Arg, Sign, Not, Zeta, Erf, f, g, Minus, Det, Transpose, Inverse, Tr, Length, Prime, Fibonacci, LogGamma,
		EllipticK, BesselJ[0, #] &, #^2 &, #^3 &, 1/# &, #^(1/3) &, Sqrt[1 + #] &, 2 # &, -# &, # + 1 &, {#} &, f[#, y] &};
	binary = {Plus, Times, Subtract, Divide, Power, Equal, Unequal, Less, Greater, LessEqual, GreaterEqual, And, Or, Xor, Implies, Rule, List,
		Max, Min, GCD, LCM, Mod, Quotient, Binomial, Log, ArcTan, BesselJ, Dot, Cross, Element, f, Subscript, Superscript,
		Derivative[1][f][#1] + #2 &, SameQ, Composition, Function, Condition, Alternatives, Span, CenterDot, CircleTimes, TildeTilde, Congruent};
	bodies = {
		x^2 + 1, x^2 + 2 x + 1, (x + 1)^2, (x + y) (x - y), 1/(1 + x), x/(1 + x^2), (a + b)/(a - b), a b c, a + b + c, a - b - c, -x, -x - y, -(x + y), 2 x y, x^-1, x^-2,
		x^(1/2), x^(2/3), x^y^z, (x^y)^z, Sqrt[x^2 + y^2], Sqrt[2], 2 Sqrt[2], Sqrt[x]/2, E^x, E^(-x^2), E^(I Pi), E^(I x), 2^x, 2^10, 10^-3,
		Sin[x]^2 + Cos[x]^2, Sin[2 x], Sin[x + y], Sin[x] Cos[y], Sin[x]/x, Tan[x]^2, Log[x]^2, Log[2, x], Log[1 + x], Exp[x] Sin[x], Sin[Cos[x]], f[x], f[x, y], f[x, y, z], f[], f[g[x]], f[x][y],
		x == y, x != y, x < y, x <= y, x > y, x >= y, x < y < z, x == y == z, x <= y < z, a && b, a || b, !a, a && b || !a, Implies[a, b], Xor[a, b], Equivalent[a, b],
		{}, {x}, {x, y}, {1, 2, 3}, {{1, 2}, {3, 4}}, {{a, b}, {b, a}}, {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}, {x, {y, z}}, {{1, 2, 3}}, {{1}, {2}, {3}}, {1, {2, 3}, 4},
		D[f[x], x], D[f[x], {x, 2}], D[f[x, y], x, y], Derivative[1][f][x], Derivative[2][f][x], Derivative[1, 1][f][x, y], f', f''[x],
		Integrate[f[x], x], Integrate[f[x], {x, 0, 1}], Integrate[f[x, y], {x, 0, 1}, {y, 0, 1}], Integrate[Sin[x]^2, {x, 0, Pi}], Sum[f[i], {i, 1, n}], Sum[i^2, {i, 1, n}], Sum[f[i], {i, n}], Sum[f[i, j], {i, 1, n}, {j, 1, i}],
		Product[f[i], {i, 1, n}], Product[1 + 1/i^2, {i, 1, Infinity}], Limit[f[x], x -> 0], Limit[f[x], x -> Infinity], Limit[Sin[x]/x, x -> 0], Limit[f[x], x -> 0, Direction -> "FromAbove"],
		Piecewise[{{x, x > 0}, {-x, x < 0}}], Piecewise[{{x, x > 0}}, 0], Piecewise[{{1, x > 0}, {2, x < 0}}, 3], Abs[x] + Abs[y], Floor[x/2], Ceiling[x] + 1, Binomial[n, 2], n!, (n + 1)!, n!!, Gamma[n + 1],
		Mod[a, n], Quotient[a, b], GCD[a, b, n], Max[x, y, z], Min[1, x], Re[z] + I Im[z], Conjugate[z] z, Arg[1 + I], Sign[x], Boole[x > 0], KroneckerDelta[a, b], DiracDelta[x], HeavisideTheta[x], UnitStep[x],
		BesselJ[n, x], BesselY[0, x], LegendreP[n, x], HermiteH[n, x], ChebyshevT[n, x], Hypergeometric2F1[a, b, n, x], Zeta[2], PolyLog[2, x], EllipticK[x], Erf[x] + Erfc[x], AiryAi[x], Beta[a, b], LaguerreL[n, x],
		Subscript[x, 1], Subscript[x, i, j], Superscript[x, 2], Subsuperscript[x, 1, 2], OverBar[x], OverHat[x], OverTilde[x], OverVector[x], OverDot[x], UnderBar[x], Subscript[a, n] + Subscript[a, n + 1],
		x -> y, x :> y, {x -> 1, y -> 2}, a . b, a . b . n, Cross[a, b], a \[Cross] b, Det[{{a, b}, {b, a}}], Transpose[a], Inverse[a], a\[Transpose], Tr[a], Norm[a], Dot[{1, 2}, {x, y}],
		Element[x, Reals], Element[n, Integers], Element[x, Complexes], NotElement[x, a], Subset[a, b], HoldForm[Union[a, b]], HoldForm[Intersection[a, b]], HoldForm[Complement[a, b]], ForAll[x, x > 0], Exists[x, x > 0], ForAll[x, x > 0, f[x] > 0],
		Function[x, x^2], Function[{x, y}, x + y], #^2 &, Composition[f, g], Composition[f, g][x], InverseFunction[f], InverseFunction[f][x], Identity[x],
		Interval[{0, 1}], Mean[{a, b}], Variance[{a, b, n}], StandardDeviation[{a, b}], Median[{1, 2, 3}], Total[{a, b}], Div[{x, y}, {x, y}], Grad[f[x, y], {x, y}], Curl[{x, y, z}, {x, y, z}], Laplacian[f[x, y], {x, y}],
		Hold[1 + 1], HoldForm[1 + 1], HoldForm[2 2], HoldForm[x x], HoldForm[1/2], HoldForm[2/4], HoldForm[x - y], HoldForm[x/y], HoldForm[Sqrt[4]], HoldForm[D[x^2, x]], HoldForm[Integrate[x, x]], HoldForm[Sum[i, {i, 1, 10}]], HoldForm[a/b/c],
		HoldForm[-1], HoldForm[-(1/2)], HoldForm[(-1)^2], HoldForm[-1^2], HoldForm[a - (b - c)], HoldForm[a/(b/c)], HoldForm[(a/b)/c], HoldForm[2^3^4], HoldForm[(2^3)^4], HoldForm[x + -y], HoldForm[x*-y], HoldForm[Times[-1, x]],
		1 + 2 I, x + I y, (1 + I) x, I x, -I, 2 I, I/2, 1/2 + I/3, E^(2 Pi I/3), x + 1/2, x/2, 2/x, -x/2, -2/x, (-x)^2, -x^2, 1 - x, x - 1, 1 - 2 x, -1 + x, 3 - x^2 + 2 x^3, 1/x + 1/y, 1/(x y), x/(y z), (x y)/z,
		1.5 x, 2.5*^10 x, 1.*^-7, 0.1 + 0.2, N[Pi], N[Pi, 30], 1.`20, 12345678901234567890, 2^100, 1/3 + 2/7, Rational[22, 7], Complex[0, 1], Complex[1.5, 2.5], 0.5, -0.5, 1000000., 1.*^6, 123.456,
		Infinity, -Infinity, ComplexInfinity, Indeterminate, DirectedInfinity[I], Pi/2, 2 Pi, Pi^2, E^2, Sqrt[Pi], Degree, 30 Degree, GoldenRatio, EulerGamma, Catalan, Khinchin, Glaisher,
		\[Alpha] + \[Beta], \[Alpha]^2, Sin[\[Theta]], \[Lambda] x, \[CapitalDelta] x, \[Psi][x], \[Mu]/\[Sigma], \[HBar] \[Omega], \[Phi] == (1 + Sqrt[5])/2,
		"text", "two words" + x, f["s"], Style[x, Bold], Style[x, Red], Style[x + y, Italic], Row[{x, y}], Row[{x, "+", y}], Column[{x, y}], Grid[{{a, b}, {x, y}}], MatrixForm[{{a, b}, {x, y}}], TableForm[{{a, b}, {x, y}}],
		Framed[x], Tooltip[x, y], Defer[1 + 1], Quantity[1, "Meters"], DateObject[{2020, 1, 1}], Missing[], Null, None, Automatic, All, List, Plus, Sin, x_, x__, _, x_Integer, x_ /; x > 0, x | y, x .. , Hold[x_ -> y],
		a ~f~ b, f @ x, f /@ {a, b}, f @@ {a, b}, x // f, x /. a -> b, HoldForm[x[[1]]], HoldForm[x[[1, 2]]], <|a -> 1|>, <|a -> 1, b -> 2|>, "a" <> "b", a ** b, a \[CirclePlus] b, a \[CircleTimes] b, a \[TildeTilde] b, a \[Congruent] b,
		a \[Element] b, a \[Subset] b, a \[Union] b, a \[Intersection] b, a \[RightArrow] b, a \[LeftRightArrow] b, a \[Proportional] b, a \[PlusMinus] b, \[PlusMinus]a, a \[Star] b, a \[CenterDot] b, a \[Wedge] b, a \[Vee] b, \[Del]f, \[Square]f,
		Ket[a], Bra[a], BraKet[{a}, {b}], AngleBracket[a, b], Floor[a] + Ceiling[b], BracketingBar[a], DoubleBracketingBar[a], Abs[a b], Norm[{a, b}], Factorial2[n], Pochhammer[a, n], Multinomial[a, b, n], StirlingS1[n, a],
		Series[Exp[x], {x, 0, 3}], Normal[Series[Sin[x], {x, 0, 5}]], O[x]^3, SeriesData[x, 0, {1, 1}, 0, 3, 1], Root[#^5 - # + 1 &, 1], RootSum[#^3 - 1 &, Log], ConditionalExpression[x, x > 0], DifferenceDelta[f[n], n],
		Solve[x^2 == 1, x], Expand[(a + b)^3], Factor[x^4 - 1], Together[1/x + 1/y], Apart[1/(x^2 - 1)], Simplify[Sin[x]^2 + Cos[x]^2], TrigExpand[Sin[2 x]], Integrate[1/(1 + x^2), x], D[Sin[x]^2, x], D[x^n, x], Sum[1/k^2, {k, 1, Infinity}],
		Table[i^2, {i, 5}], Range[5], IdentityMatrix[2], Array[Subscript[a, ##] &, {2, 2}], N[Sqrt[2], 20], N[E], N[1/3], 1/3., 2.^0.5, Sin[1.], Exp[1.] I, Table[x^i/i!, {i, 0, 3}], {x, x^2, x^3}, Total[Table[x^i, {i, 0, 4}]]
	};
	DeleteDuplicates[Join[
		HoldComplete /@ atoms,
		HoldComplete /@ Map[#[x] &, unary],
		HoldComplete /@ Map[#[x, y] &, binary],
		HoldComplete /@ Map[#[2, 3] &, Take[binary, 16]],
		HoldComplete /@ bodies
	]]
]

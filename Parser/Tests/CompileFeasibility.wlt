(* :Title: CompileFeasibility.wlt *)
(* :Summary:
    Proves the mechanism behind v0.4 full action-compilation: a
    compiled function CAN call an arbitrary Wolfram callback (the kind
    a ParseAction / GrammarRules rule carries) via KernelFunction, and
    CAN thread arbitrary Wolfram expressions through compiled code as
    the "InertExpression" value type. These two facts are what make
    single-pass compilation of action-bearing grammars possible -
    correcting the earlier (wrong) assumption that Wolfram callbacks
    can't go through the compiler. *)

Needs["Wolfram`Parser`"]

(* A compiled function calls back into the kernel via a typed
   KernelFunction - exactly the ParseAction callback case. *)
VerificationTest[
    Module[{act, cf},
        act[s_String] := StringReverse[s] <> "!";
        cf = FunctionCompile[
            Function[{Typed[s, "String"]},
                Typed[KernelFunction[act], {"String"} -> "String"][s]
            ]
        ];
        {Head[cf], cf["abc"]}
    ],
    {CompiledCodeFunction, "cba!"},
    TestID -> "CompileFeasibility: KernelFunction callback from compiled code"
]

(* InertExpression flows through compiled code as a value type, so an
   action returning an arbitrary expression (here an Integer) can be
   produced and carried by the compiled function. *)
VerificationTest[
    Module[{act, cf},
        act[s_String] := FromDigits[s];
        cf = FunctionCompile[
            Function[{Typed[s, "String"]},
                Typed[KernelFunction[act], {"String"} -> "InertExpression"][s]
            ]
        ];
        {Head[cf], cf["42"]}
    ],
    {CompiledCodeFunction, 42},
    TestID -> "CompileFeasibility: action returns arbitrary expression via InertExpression"
]

(* InertExpression values can be threaded between two KernelFunction
   callbacks inside one compiled function - the composition pattern a
   multi-stage grammar action needs. *)
VerificationTest[
    Module[{cf},
        cf = FunctionCompile[
            Function[{Typed[s, "String"]},
                Module[{e = Typed[KernelFunction[Identity], {"String"} -> "InertExpression"][s]},
                    Typed[KernelFunction[ToUpperCase], {"InertExpression"} -> "InertExpression"][e]
                ]
            ]
        ];
        cf["abc"]
    ],
    "ABC",
    TestID -> "CompileFeasibility: thread InertExpression between callbacks"
]

(* End-to-end: a digit-run recogniser fused with its action, compiled
   to a single CompiledCodeFunction that returns the parsed integer -
   the shape a compiled ParseAction[ParseSome[digit], FromDigits] takes. *)
VerificationTest[
    Module[{act, cf},
        act[s_String] := FromDigits[s];
        cf = FunctionCompile[
            Function[{Typed[input, "String"], Typed[pos, "MachineInteger"]},
                Module[{p = pos, start = pos},
                    While[p <= StringLength[input] && DigitQ[StringTake[input, {p, p}]], p++];
                    If[ p === start,
                        Typed[KernelFunction[(Missing["NoMatch"] &)], {"String"} -> "InertExpression"][""],
                        Typed[KernelFunction[act], {"String"} -> "InertExpression"][
                            StringTake[input, {start, p - 1}]
                        ]
                    ]
                ]
            ]
        ];
        {cf["12345xyz", 1], cf["xyz", 1]}
    ],
    {12345, Missing["NoMatch"]},
    TestID -> "CompileFeasibility: digit-run recogniser + action fused into one compiled fn"
]

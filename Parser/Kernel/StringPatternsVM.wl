(* ::Package:: *)

(* :Title: StringPatternsVM.wl - the typed matcher of string patterns *)
(* :Context: Wolfram`Parser`StringPatterns`Private` *)
(* :Author: Nikolay Murzin, Claude (Anthropic) *)
(* :Summary:
    The matcher of the engine of string patterns: a backtracking machine over the bytecode that
    StringPatterns.wl compiles a pattern's program to, typed code over packed integers, which a
    kernel compiles once; here Compile compiles it. It matches as the program's interpreter does,
    which stays the reference.
*)

Begin["Wolfram`Parser`StringPatterns`Private`"]

(* The matches of programs compiled to bytecode, typed code over packed integers, every argument a
   packed vector of machine integers: the code, five integers an instruction, {op, a, b, c, d}; the
   pool of constants; the classes, {k, the start of each of the k, then each four words of 32 bits
   of its codes below 128 and its runs, {count, first, last, ...}}; the text's codes; the
   parameters {mode, from, programs, names, registers, the program table in the pool}; and the
   state to go on from, {} at first. It gives {status, matches, width, then each match {start, end,
   k, the start and end of each name}}, status 0 when the scan is done, and 2 where a condition is
   to be evaluated, then {condition, k, the names, the length of the state, the state}, to call
   again with the state and the condition's value after it, 1 or 0.

   Instructions, a to d their operands:
     1 CHAR c        2 STR off len      3 CLASS k         4 RUN k min max greedy
     5 SPLIT a b     6 JMP a            7 FAIL            8 MATCH
     9 ANCHOR kind wordclass            10 NOPEN name skip 11 NCLOSE name     12 BREF name
     13 REPSTART e   14 LOOP e          15 ITER e         16 ITEREND e      17 DONE e
     18 EXCL k       19 TSTART reg      20 TEND reg k     21 COND index
   A name is three registers from its base, start, end and where it opened, -1 unbound and -2
   unbound the first time round a repeat; a repeat's entry e in the pool {count register, min,
   max, greedy, loop, iteration, done, exit, poison list, its length}, max -1 for none. Choice
   frames are six integers, {kind, pc, sp, trail, x, y}: 1 another way at pc, 2 a greedy run of
   x characters giving one back down to y, 3 a shortest run of x characters taking one more up to
   y. The trail undoes the registers set since a frame, {register, value} pairs. The declaration is
   made the first time it is asked for: its types load the compiler. *)
(* Whether the code cc is of the class cls, into inside, held code each test of a class is: below 128
   a bit of the class's four words, the bit a word's and a mask's, as Compile takes a shift by a
   variable for a real; else a search of its runs. *)
SetAttributes[vmCode, HoldAll]
$vmMember = vmCode[
    off = vClasses[[cls + 1]];
    If[ cc < 128,
        inside = If[BitAnd[vClasses[[off + Quotient[cc, 32]]], masks[[BitAnd[cc, 31] + 1]]] == 0, 0, 1],
        inside = 0; rlo = 0; rhi = vClasses[[off + 4]] - 1;
        While[ rlo <= rhi,
            rmid = Quotient[rlo + rhi, 2];
            Which[
                cc < vClasses[[off + 5 + 2 rmid]], rhi = rmid - 1,
                cc > vClasses[[off + 6 + 2 rmid]], rlo = rmid + 1,
                True, inside = 1; rlo = rhi + 1]]]];

$vmDeclaration := $vmDeclaration = FunctionDeclaration[vmRun,
    Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
        "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} ->
        "PackedArray"::["MachineInteger", 1]] @@ ReplaceAll[ReplaceAll[Hold @ Function[{vCode, vPool, vClasses, vText, vParams, vState},
        Module[{n = Length[vText], mode = vParams[[1]], m = vParams[[3]], maxNames = vParams[[4]], nRegs = vParams[[5]], progOff = vParams[[6]],
                width = 3 + 2 vParams[[4]], i = vParams[[2]], k = 1, status = 0, result = 0, pending = 0, answer = 0, fail = 0,
                pc = 0, sp = 0, start = 0, top = 0, ttop = 0, regs, stack, trail, out, outLen = 3, nRec = 0,
                op = 0, a = 0, b = 0, c = 0, d = 0, j = 0, j2 = 0, cc = 0, off = 0, inside = 0, na = 0, ok = 0, len = 0, e = 0, r = 0,
                cnt = 0, mn = 0, mx = 0, kind = 0, rpc = 0, rsp = 0, rtt = 0, x = 0, y = 0, cls = 0, grown, q = 0, before = 0, after = 0, rlo = 0, rhi = 0, rmid = 0,
                nNames = 0, entry = 0, firstClass = 0, stateLen = 0, base = 0, masks},
            (* the bit of each of 32, a class's test of a code its word's and its bit's: Compile takes a
               shift by a variable for a real *)
            masks = Table[2^j, {j, 0, 31}];
            regs = Table[0, {Max[nRegs, 1]}];
            stack = Table[0, {6 64}];
            trail = Table[0, {2 64}];
            out = Table[0, {3 + 16 width}];
            (* the state given: the scan's position and program, and the matcher's registers, choice stack and trail *)
            If[ Length[vState] > 0,
                i = vState[[1]]; k = vState[[2]]; pc = vState[[3]]; sp = vState[[4]]; start = vState[[5]];
                q = 6; Do[regs[[j + 1]] = vState[[q + j]], {j, 0, nRegs - 1}]; q = q + nRegs;
                top = vState[[q]]; q++;
                If[6 top > Length[stack], stack = Table[0, {6 top + 64}]];
                Do[stack[[j]] = vState[[q + j - 1]], {j, 1, 6 top}]; q = q + 6 top;
                ttop = vState[[q]]; q++;
                If[2 ttop > Length[trail], trail = Table[0, {2 ttop + 64}]];
                Do[trail[[j]] = vState[[q + j - 1]], {j, 1, 2 ttop}]; q = q + 2 ttop;
                answer = vState[[q]]; pending = 1];
            While[ i <= n && status == 0,
                If[ k > m, i++; k = 1,
                    entry = progOff + 4 (k - 1); nNames = vPool[[entry + 1]];
                    If[ pending == 0,
                        (* the program k at position i, unless its first character cannot be there *)
                        pc = vPool[[entry]]; firstClass = vPool[[entry + 2]];
                        sp = i; start = i; top = 0; ttop = 0;
                        Do[regs[[3 j + 1]] = -1; regs[[3 j + 2]] = -1, {j, 0, nNames - 1}];
                        result = 0;
                        If[ firstClass > 0,
                            If[ i >= n, result = -1,
                                cc = vText[[i + 1]]; cls = firstClass;
                                vmMember[];
                                If[inside == 0, result = -1]]],
                        result = 0];
                    While[ result == 0,
                        fail = 0;
                        If[ pending == 1,
                            (* back from a condition: on past it, or another way *)
                            pending = 0; If[answer == 1, pc++, fail = 1],
                            q = 5 pc; op = vCode[[q + 1]]; a = vCode[[q + 2]]; b = vCode[[q + 3]]; c = vCode[[q + 4]]; d = vCode[[q + 5]];
                            Which[
                                op == 1, If[sp < n && vText[[sp + 1]] == a, sp++; pc++, fail = 1],
                                op == 2,
                                    If[ sp + b <= n,
                                        j = 0; While[j < b && vText[[sp + j + 1]] == vPool[[a + j]], j++];
                                        If[j == b, sp = sp + b; pc++, fail = 1],
                                        fail = 1],
                                op == 3 || op == 18,
                                    If[ sp < n,
                                        cc = vText[[sp + 1]]; cls = a;
                                        vmMember[];
                                        Which[op == 3 && inside == 1, sp++; pc++, op == 18 && inside == 0, pc++, True, fail = 1],
                                        fail = 1],
                                op == 4,
                                    (* a run of the class a, from b to c characters: the longest, as many as there are, then
                                       one fewer at a time; the shortest, b, then one more at a time, as the choice is taken *)
                                    j = 0; ok = 1; cls = a;
                                    While[ ok == 1 && (c < 0 || j < c) && sp + j < n && (d == 1 || j < b),
                                        cc = vText[[sp + j + 1]];
                                        vmMember[];
                                        If[inside == 1, j++, ok = 0]];
                                    If[ j < b, fail = 1,
                                        If[ (d == 1 && j > b) || (d == 0 && (c < 0 || b < c) && sp + b < n),
                                            If[ 6 top + 6 > Length[stack], grown = Table[0, {2 Length[stack]}]; Do[grown[[q]] = stack[[q]], {q, Length[stack]}]; stack = grown];
                                            q = 6 top; stack[[q + 1]] = If[d == 1, 2, 3]; stack[[q + 2]] = pc + 1; stack[[q + 3]] = sp; stack[[q + 4]] = ttop;
                                            stack[[q + 5]] = j; stack[[q + 6]] = b; top++];
                                        sp = sp + j; pc++],
                                op == 5,
                                    If[ 6 top + 6 > Length[stack], grown = Table[0, {2 Length[stack]}]; Do[grown[[q]] = stack[[q]], {q, Length[stack]}]; stack = grown];
                                    q = 6 top; stack[[q + 1]] = 1; stack[[q + 2]] = b; stack[[q + 3]] = sp; stack[[q + 4]] = ttop; stack[[q + 5]] = 0; stack[[q + 6]] = 0; top++;
                                    pc = a,
                                op == 6, pc = a,
                                op == 7, fail = 1,
                                op == 8, result = 1,
                                op == 9,
                                    Which[
                                        a == 1, ok = If[sp == 0, 1, 0],
                                        a == 2, ok = If[sp == n, 1, 0],
                                        a == 3, ok = If[sp == 0 || (sp < n && vText[[sp]] == 10), 1, 0],
                                        a == 4, ok = If[sp == n || vText[[sp + 1]] == 10, 1, 0],
                                        True,
                                            (* a word boundary: a word character on one side alone *)
                                            cls = b; before = 0; after = 0;
                                            If[ sp > 0,
                                                cc = vText[[sp]];
                                                vmMember[]; before = inside];
                                            If[ sp < n,
                                                cc = vText[[sp + 1]];
                                                vmMember[]; after = inside];
                                            ok = If[before != after, 1, 0]];
                                    If[ok == 1, pc++, fail = 1],
                                op == 10 || op == 12,
                                    (* a name: bound, its text again; unbound, opened here, or for a backreference none *)
                                    Which[
                                        regs[[a + 1]] == -1 && op == 10,
                                            If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                            trail[[2 ttop + 1]] = a + 2; trail[[2 ttop + 2]] = regs[[a + 3]]; ttop++; regs[[a + 3]] = sp; pc++,
                                        regs[[a + 1]] < 0, fail = 1,
                                        True,
                                            len = regs[[a + 2]] - regs[[a + 1]];
                                            If[ sp + len <= n,
                                                j = 0; While[j < len && vText[[sp + j + 1]] == vText[[regs[[a + 1]] + j + 1]], j++];
                                                If[j == len, sp = sp + len; pc = If[op == 10, b, pc + 1], fail = 1],
                                                fail = 1]],
                                op == 11,
                                    If[ 2 ttop + 4 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                    trail[[2 ttop + 1]] = a; trail[[2 ttop + 2]] = regs[[a + 1]]; ttop++; regs[[a + 1]] = regs[[a + 3]];
                                    trail[[2 ttop + 1]] = a + 1; trail[[2 ttop + 2]] = regs[[a + 2]]; ttop++; regs[[a + 2]] = sp;
                                    pc++,
                                op == 13,
                                    r = vPool[[a]];
                                    If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                    trail[[2 ttop + 1]] = r; trail[[2 ttop + 2]] = regs[[r + 1]]; ttop++; regs[[r + 1]] = 0;
                                    pc++,
                                op == 14,
                                    (* a repeat's head: the longest first, one more then none, else none then one more *)
                                    r = vPool[[a]]; mn = vPool[[a + 1]]; mx = vPool[[a + 2]]; cnt = regs[[r + 1]];
                                    If[ vPool[[a + 3]] == 1,
                                        If[ mx < 0 || cnt < mx,
                                            If[ 6 top + 6 > Length[stack], grown = Table[0, {2 Length[stack]}]; Do[grown[[q]] = stack[[q]], {q, Length[stack]}]; stack = grown];
                                            q = 6 top; stack[[q + 1]] = 1; stack[[q + 2]] = vPool[[a + 6]]; stack[[q + 3]] = sp; stack[[q + 4]] = ttop; stack[[q + 5]] = 0; stack[[q + 6]] = 0; top++;
                                            pc = vPool[[a + 5]],
                                            pc = vPool[[a + 6]]],
                                        If[ cnt >= mn,
                                            If[ 6 top + 6 > Length[stack], grown = Table[0, {2 Length[stack]}]; Do[grown[[q]] = stack[[q]], {q, Length[stack]}]; stack = grown];
                                            q = 6 top; stack[[q + 1]] = 1; stack[[q + 2]] = vPool[[a + 5]]; stack[[q + 3]] = sp; stack[[q + 4]] = ttop; stack[[q + 5]] = 0; stack[[q + 6]] = 0; top++;
                                            pc = vPool[[a + 7]],
                                            pc = vPool[[a + 5]]]],
                                op == 15,
                                    r = vPool[[a]]; mx = vPool[[a + 2]];
                                    If[ mx >= 0 && regs[[r + 1]] >= mx, fail = 1,
                                        If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                        trail[[2 ttop + 1]] = r + 1; trail[[2 ttop + 2]] = regs[[r + 2]]; ttop++; regs[[r + 2]] = sp;
                                        pc++],
                                op == 16,
                                    (* an iteration's end: one that matched nothing ends the repeat once its least are there; the
                                       names of the first that took no part in it match no more *)
                                    r = vPool[[a]]; mn = vPool[[a + 1]]; cnt = regs[[r + 1]];
                                    If[ sp == regs[[r + 2]] && cnt + 1 >= mn, pc = vPool[[a + 7]],
                                        If[ cnt == 0,
                                            Do[ base = vPool[[vPool[[a + 8]] + j]];
                                                If[ regs[[base + 1]] == -1,
                                                    If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                                    trail[[2 ttop + 1]] = base; trail[[2 ttop + 2]] = -1; ttop++; regs[[base + 1]] = -2],
                                                {j, 0, vPool[[a + 9]] - 1}]];
                                        If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                        trail[[2 ttop + 1]] = r; trail[[2 ttop + 2]] = cnt; ttop++; regs[[r + 1]] = cnt + 1;
                                        pc = vPool[[a + 4]]],
                                op == 17, If[regs[[vPool[[a]] + 1]] < vPool[[a + 1]], fail = 1, pc = vPool[[a + 7]]],
                                op == 19,
                                    If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
                                    trail[[2 ttop + 1]] = a; trail[[2 ttop + 2]] = regs[[a + 1]]; ttop++; regs[[a + 1]] = sp;
                                    pc++,
                                op == 20,
                                    (* a test of each character since the register *)
                                    j = regs[[a + 1]]; ok = 1; cls = b;
                                    While[ j < sp && ok == 1,
                                        cc = vText[[j + 1]];
                                        vmMember[];
                                        If[inside == 0, ok = 0]; j++];
                                    If[ok == 1, pc++, fail = 1],
                                op == 21, result = 2,
                                True, fail = 1]];
                        (* another way: the last choice, the registers set since it undone, until one goes on *)
                        While[ fail == 1,
                            If[ top == 0, result = -1; fail = 0,
                                top--; q = 6 top;
                                kind = stack[[q + 1]]; rpc = stack[[q + 2]]; rsp = stack[[q + 3]]; rtt = stack[[q + 4]]; x = stack[[q + 5]]; y = stack[[q + 6]];
                                While[ttop > rtt, ttop--; regs[[trail[[2 ttop + 1]] + 1]] = trail[[2 ttop + 2]]];
                                Which[
                                    kind == 1, pc = rpc; sp = rsp; fail = 0,
                                    kind == 2,
                                        (* a longest run, one character fewer *)
                                        x--;
                                        If[ x > y,
                                            q = 6 top; stack[[q + 1]] = kind; stack[[q + 2]] = rpc; stack[[q + 3]] = rsp; stack[[q + 4]] = ttop; stack[[q + 5]] = x; stack[[q + 6]] = y; top++];
                                        sp = rsp + x; pc = rpc; fail = 0,
                                    True,
                                        (* a shortest run, one character more, if the run's class has it: the RUN before rpc *)
                                        q = 5 (rpc - 1); a = vCode[[q + 2]]; c = vCode[[q + 4]]; cls = a;
                                        cc = vText[[rsp + x + 1]];
                                        vmMember[];
                                        If[ inside == 1,
                                            x++;
                                            If[ (c < 0 || x < c) && rsp + x < n,
                                                q = 6 top; stack[[q + 1]] = kind; stack[[q + 2]] = rpc; stack[[q + 3]] = rsp; stack[[q + 4]] = ttop; stack[[q + 5]] = x; stack[[q + 6]] = y; top++];
                                            sp = rsp + x; pc = rpc; fail = 0]]]]];
                    Which[
                        result == 2, status = 2,
                        result == 1,
                            (* the match, then on as the mode takes the next *)
                            If[ outLen + width > Length[out], grown = Table[0, {2 Length[out]}]; Do[grown[[q]] = out[[q]], {q, Length[out]}]; out = grown];
                            out[[outLen + 1]] = start; out[[outLen + 2]] = sp; out[[outLen + 3]] = k;
                            Do[ out[[outLen + 4 + 2 j]] = If[j < nNames, regs[[3 j + 1]], -1]; out[[outLen + 5 + 2 j]] = If[j < nNames, regs[[3 j + 2]], -1], {j, 0, maxNames - 1}];
                            outLen = outLen + width; nRec++;
                            Which[
                                mode == 1, If[sp > i, i = sp, i++]; k = 1,
                                mode == 2, If[sp > i, i = sp; k = 1, k++],
                                True, k++],
                        True, k++]]];
            out[[1]] = status; out[[2]] = nRec; out[[3]] = width;
            If[ status == 2,
                (* the condition, its program's names, and the state to go on from *)
                stateLen = 5 + nRegs + 1 + 6 top + 1 + 2 ttop;
                If[ outLen + 3 + 2 maxNames + stateLen > Length[out],
                    grown = Table[0, {outLen + 3 + 2 maxNames + stateLen}]; Do[grown[[q]] = out[[q]], {q, outLen}]; out = grown];
                out[[outLen + 1]] = vCode[[5 pc + 2]]; out[[outLen + 2]] = k;
                Do[out[[outLen + 3 + 2 j]] = If[j < nNames, regs[[3 j + 1]], -1]; out[[outLen + 4 + 2 j]] = If[j < nNames, regs[[3 j + 2]], -1], {j, 0, maxNames - 1}];
                q = outLen + 3 + 2 maxNames; out[[q]] = stateLen;
                out[[q + 1]] = i; out[[q + 2]] = k; out[[q + 3]] = pc; out[[q + 4]] = sp; out[[q + 5]] = start;
                q = q + 6; Do[out[[q + j]] = regs[[j + 1]], {j, 0, nRegs - 1}]; q = q + nRegs;
                out[[q]] = top; q++; Do[out[[q + j - 1]] = stack[[j]], {j, 1, 6 top}]; q = q + 6 top;
                out[[q]] = ttop; q++; Do[out[[q + j - 1]] = trail[[j]], {j, 1, 2 ttop}]; q = q + 2 ttop;
                outLen = q - 1];
            Take[out, outLen]]], vmMember[] -> $vmMember], vmCode[code_] :> code]];

(* the matcher: the host's compiled one, where its units define vmRun; else the declaration's
   Function compiled by Compile, every argument a packed vector of integers, as the paclet's typed
   code is; else evaluated *)
vmFunction := vmFunction = If[DownValues[vmRun] =!= {} || OwnValues[vmRun] =!= {}, vmRun,
    With[{f = $vmDeclaration[[2, 1]]},
        Replace[Compile @@ Join[Hold[Evaluate[Map[{#, _Integer, 1} &, f[[1]]]]], Extract[f, {2}, Hold]], Except[_CompiledFunction] -> f]]]

End[]

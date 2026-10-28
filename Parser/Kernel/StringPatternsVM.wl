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
	parameters {mode, from, programs, names, registers, the program table in the pool}, the mode 1
	or 2 the first program that matches at a position, after an empty match the position again for
	one not empty, 3 every one, an empty match once and its program again for one not empty, 4
	every way of every one; and the state to go
	on from, {} at first. It gives {status, matches, width, then each match {start, end,
	k, the start and end of each name}}, status 0 when the scan is done, and 2 where a condition is
	to be evaluated, then {condition, k, the names, the length of the state, the state}, to call
	again with the state and the condition's value after it, 1 or 0.

	Instructions, a to d their operands:
	1 CHAR c        2 STR off len      3 CLASS k         4 RUN k min max greedy
	5 SPLIT a b     6 JMP a            7 FAIL            8 MATCH
	9 ANCHOR kind wordclass            10 NOPEN name skip 11 NCLOSE name     12 BREF name 0 caseless table
	13 REPSTART e   14 LOOP e          15 ITER e         16 ITEREND e      17 DONE e
	18 EXCL k       19 TSTART reg      20 TEND reg k     21 COND index     22 GOPEN group
	23 AOPEN kind reg len past          24 ACLOSE reg      25 BREFREP group min past
	A name is three registers from its base, start, end and where it opened, -1 unbound and -2
	unbound the first time round a repeat; a repeat's entry e in the pool {count register, min,
	max, greedy, loop, iteration, done, exit, poison list, its length, 1 if its pattern has a name},
	max -1 for none. Choice
	frames are six integers, {kind, pc, sp, trail, x, y}: 1 another way at pc, 2 a greedy run of
	x characters giving one back down to y, 3 a shortest run of x characters taking one more up to
	y. The trail undoes the registers set since a frame, {register, value} pairs. Each test of a class
	is a call of vmMember. A group of a regex is three registers as a name is, GOPEN opening it each
	time, NCLOSE closing it, BREF its backreference, of any case where caseless is 1: two characters
	the same where each is the first of its caseless set by the table in the pool, {count, then
	each code and that first, in order of the codes}, a search of it; an anchor's kind 1 to 7 is StartOfString,
	EndOfString, StartOfLine, EndOfLine, WordBoundary, the end or before a newline that ends the
	text, and no word boundary. An assertion or atomic part pushes a barrier, a choice frame of kind 4
	{4, past, sp, trail, kind, 0}, and keeps the depth below it in its register: ACLOSE cuts the
	choices back to it, and the matcher's failing back to it is the part's having no way, which a
	negative assertion takes for holding. BREFREP passes over a repeat of a backreference to a group
	that holds nothing, or none where the repeat may be none. The declarations are made the first time they are asked for: their types
	load the compiler. *)
(* Whether the code cc is of the class cls of the classes, 1 or 0, the typed function each test of a
	class calls: below 128 a bit of the class's four words, the bit a word's and a mask's, as Compile
	takes a shift by a variable for a real; else a search of its runs. *)
$vmMemberDeclaration := $vmMemberDeclaration = FunctionDeclaration[vmMember,
	Typed[{"MachineInteger", "MachineInteger", "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} -> "MachineInteger"] @
	Function[{cc, cls, vClasses, masks},
		Module[{off = vClasses[[cls + 1]], inside = 0, rlo = 0, rhi = 0, rmid = 0},
			If[ cc < 128,
				inside = If[BitAnd[vClasses[[off + Quotient[cc, 32]]], masks[[BitAnd[cc, 31] + 1]]] == 0, 0, 1],
				rhi = vClasses[[off + 4]] - 1;
				While[ rlo <= rhi,
					rmid = Quotient[rlo + rhi, 2];
					Which[
						cc < vClasses[[off + 5 + 2 rmid]], rhi = rmid - 1,
						cc > vClasses[[off + 6 + 2 rmid]], rlo = rmid + 1,
						True, inside = 1; rlo = rhi + 1]]];
			inside]]]

(* The program to try next at a position, past the program k: the first after k of those the table of
	starts lists for the text's code there, below 128, as their first character may be it, m + 1
	where none is left; else k + 1. The table is at starts in the pool, 0 for none, the place of the
	list of each code c below 128 at starts + c, its programs in order and a 0 after them. *)
$vmNextDeclaration := $vmNextDeclaration = FunctionDeclaration[vmNext,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "MachineInteger", "MachineInteger", "MachineInteger",
		"MachineInteger", "MachineInteger"} -> "MachineInteger"] @
	Function[{nxPool, nxText, nxStarts, nxAt, nxK, nxM, nxN},
		Module[{p = 0, c = 0, r = nxK + 1},
			If[ nxStarts > 0 && nxAt < nxN,
				c = nxText[[nxAt + 1]];
				If[ c >= 0 && c < 128,
					p = nxPool[[nxStarts + c]];
					While[nxPool[[p]] != 0 && nxPool[[p]] <= nxK, p++];
					r = If[nxPool[[p]] == 0, nxM + 1, nxPool[[p]]]]];
			r]]]

$vmDeclaration := $vmDeclaration = FunctionDeclaration[vmRun,
	Typed[{"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1],
		"PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1], "PackedArray"::["MachineInteger", 1]} ->
		"PackedArray"::["MachineInteger", 1]] @
	Function[{vCode, vPool, vClasses, vText, vParams, vState},
		Module[{n = Length[vText], mode = vParams[[1]], m = vParams[[3]], maxNames = vParams[[4]], nRegs = vParams[[5]], progOff = vParams[[6]],
				width = 3 + 2 vParams[[4]], i = vParams[[2]], k = 1, status = 0, result = 0, pending = 0, answer = 0, fail = 0,
				pc = 0, sp = 0, start = 0, top = 0, ttop = 0, regs, stack, trail, out, outLen = 3, nRec = 0,
				op = 0, a = 0, b = 0, c = 0, d = 0, j = 0, cc = 0, inside = 0, ok = 0, len = 0, e = 0, r = 0,
				cnt = 0, mn = 0, mx = 0, kind = 0, rpc = 0, rsp = 0, rtt = 0, x = 0, y = 0, cls = 0, grown, q = 0, before = 0, after = 0,
				nNames = 0, entry = 0, firstClass = 0, stateLen = 0, base = 0, masks, u = 0, w = 0, fold = 0, flo = 0, fhi = 0, fmid = 0, ne = 0,
				starts = If[Length[vParams] >= 7, vParams[[7]], 0]},
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
				ne = vState[[q]]; q++;
				answer = vState[[q]]; pending = 1];
			(* the first program at the first position, by the table of starts *)
			If[Length[vState] == 0, k = vmNext[vPool, vText, starts, i, 0, m, n]];
			While[ i <= n && status == 0,
				If[ k > m, i++; k = vmNext[vPool, vText, starts, i, 0, m, n]; ne = 0,
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
								inside = vmMember[cc, cls, vClasses, masks];
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
										inside = vmMember[cc, cls, vClasses, masks];
										Which[op == 3 && inside == 1, sp++; pc++, op == 18 && inside == 0, pc++, True, fail = 1],
										fail = 1],
								op == 4,
									(* a run of the class a, from b to c characters: the longest, as many as there are, then
										one fewer at a time; the shortest, b, then one more at a time, as the choice is taken *)
									j = 0; ok = 1; cls = a;
									While[ ok == 1 && (c < 0 || j < c) && sp + j < n && (d == 1 || j < b),
										cc = vText[[sp + j + 1]];
										inside = vmMember[cc, cls, vClasses, masks];
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
								op == 8, If[ne == 1 && sp == start, fail = 1, result = 1],
								op == 9,
									Which[
										a == 1, ok = If[sp == 0, 1, 0],
										a == 2, ok = If[sp == n, 1, 0],
										a == 3, ok = If[sp == 0 || (sp < n && vText[[sp]] == 10), 1, 0],
										a == 4, ok = If[sp == n || vText[[sp + 1]] == 10, 1, 0],
										a == 6, ok = If[sp == n || (sp == n - 1 && vText[[sp + 1]] == 10), 1, 0],
										True,
											(* a word boundary: a word character on one side alone *)
											cls = b; before = 0; after = 0;
											If[ sp > 0,
												cc = vText[[sp]];
												inside = vmMember[cc, cls, vClasses, masks]; before = inside];
											If[ sp < n,
												cc = vText[[sp + 1]];
												inside = vmMember[cc, cls, vClasses, masks]; after = inside];
											ok = If[before != after, 1, 0]; If[a == 7, ok = 1 - ok]];
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
												j = 0; ok = 1;
												While[ j < len && ok == 1,
													u = vText[[sp + j + 1]]; w = vText[[regs[[a + 1]] + j + 1]];
													If[ u != w,
														If[ op == 12 && c == 1,
															(* of any case: each character the first of its caseless set, itself where it has none *)
															fold = u; flo = 1; fhi = vPool[[d]];
															While[ flo <= fhi,
																fmid = Quotient[flo + fhi, 2];
																Which[
																	vPool[[d + 2 fmid - 1]] < u, flo = fmid + 1,
																	vPool[[d + 2 fmid - 1]] > u, fhi = fmid - 1,
																	True, fold = vPool[[d + 2 fmid]]; flo = fhi + 1]];
															u = fold; fold = w; flo = 1; fhi = vPool[[d]];
															While[ flo <= fhi,
																fmid = Quotient[flo + fhi, 2];
																Which[
																	vPool[[d + 2 fmid - 1]] < w, flo = fmid + 1,
																	vPool[[d + 2 fmid - 1]] > w, fhi = fmid - 1,
																	True, fold = vPool[[d + 2 fmid]]; flo = fhi + 1]];
															If[u != fold, ok = 0],
															ok = 0]];
													If[ok == 1, j++]];
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
											pc = vPool[[a + 6]],
											pc = vPool[[a + 5]]]],
								op == 15,
									r = vPool[[a]]; mx = vPool[[a + 2]];
									If[ mx >= 0 && regs[[r + 1]] >= mx, fail = 1,
										If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
										trail[[2 ttop + 1]] = r + 1; trail[[2 ttop + 2]] = regs[[r + 2]]; ttop++; regs[[r + 2]] = sp;
										pc++],
								op == 16,
									(* an iteration's end: one that matched nothing ends a repeat of any number once its least are
										there, or with names after its first, once all but one are; the names of the first that took
										no part in it match no more *)
									r = vPool[[a]]; mn = vPool[[a + 1]]; mx = vPool[[a + 2]]; cnt = regs[[r + 1]];
									If[ sp == regs[[r + 2]] && mx < 0 && If[vPool[[a + 10]] == 0, cnt + 1 >= mn, cnt >= Max[1, mn - 1]], pc = vPool[[a + 7]],
										If[ cnt == 0,
											Do[ base = vPool[[vPool[[a + 8]] + j]];
												If[ regs[[base + 1]] == -1,
													If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
													trail[[2 ttop + 1]] = base; trail[[2 ttop + 2]] = -1; ttop++; regs[[base + 1]] = -2],
												{j, 0, vPool[[a + 9]] - 1}]];
										If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
										trail[[2 ttop + 1]] = r; trail[[2 ttop + 2]] = cnt; ttop++; regs[[r + 1]] = cnt + 1;
										pc = vPool[[a + 4]]],
								op == 17,
									(* a repeat's end: with names and no least, none in place of the first goes on with the rest,
										the names of the first that took no part matching no more *)
									r = vPool[[a]]; cnt = regs[[r + 1]];
									Which[
										cnt == 0 && vPool[[a + 1]] == 0 && vPool[[a + 10]] == 1,
											Do[ base = vPool[[vPool[[a + 8]] + j]];
												If[ regs[[base + 1]] == -1,
													If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
													trail[[2 ttop + 1]] = base; trail[[2 ttop + 2]] = -1; ttop++; regs[[base + 1]] = -2],
												{j, 0, vPool[[a + 9]] - 1}];
											If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
											trail[[2 ttop + 1]] = r; trail[[2 ttop + 2]] = 0; ttop++; regs[[r + 1]] = 1;
											pc = vPool[[a + 4]],
										cnt < vPool[[a + 1]], fail = 1,
										True, pc = vPool[[a + 7]]],
								op == 19,
									If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
									trail[[2 ttop + 1]] = a; trail[[2 ttop + 2]] = regs[[a + 1]]; ttop++; regs[[a + 1]] = sp;
									pc++,
								op == 20,
									(* a test of each character since the register *)
									j = regs[[a + 1]]; ok = 1; cls = b;
									While[ j < sp && ok == 1,
										cc = vText[[j + 1]];
										inside = vmMember[cc, cls, vClasses, masks];
										If[inside == 0, ok = 0]; j++];
									If[ok == 1, pc++, fail = 1],
								op == 21, result = 2,
								op == 22,
									If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
									trail[[2 ttop + 1]] = a + 2; trail[[2 ttop + 2]] = regs[[a + 3]]; ttop++; regs[[a + 3]] = sp; pc++,
								op == 23,
									(* an assertion's or atomic part's opening, a lookbehind's back by its length *)
									If[ (a == 3 || a == 4) && sp < c,
										If[a == 3, fail = 1, pc = d],
										If[ 2 ttop + 2 > Length[trail], grown = Table[0, {2 Length[trail]}]; Do[grown[[q]] = trail[[q]], {q, Length[trail]}]; trail = grown];
										trail[[2 ttop + 1]] = b; trail[[2 ttop + 2]] = regs[[b + 1]]; ttop++; regs[[b + 1]] = top;
										If[ 6 top + 6 > Length[stack], grown = Table[0, {2 Length[stack]}]; Do[grown[[q]] = stack[[q]], {q, Length[stack]}]; stack = grown];
										q = 6 top; stack[[q + 1]] = 4; stack[[q + 2]] = d; stack[[q + 3]] = sp; stack[[q + 4]] = ttop; stack[[q + 5]] = a; stack[[q + 6]] = 0; top++;
										If[a == 3 || a == 4, sp = sp - c];
										pc++],
								op == 24,
									(* its closing: the choices since its opening dropped, at the place it opened but for an
										atomic part, a lookbehind's part ending there; a negative assertion fails *)
									q = 6 regs[[a + 1]]; kind = stack[[q + 5]];
									If[ (kind == 3 || kind == 4) && sp != stack[[q + 3]], fail = 1,
										If[kind != 5, sp = stack[[q + 3]]];
										top = regs[[a + 1]];
										If[kind == 2 || kind == 4, fail = 1, pc++]],
								op == 25,
									(* a repeat of a backreference: past it where its group holds nothing, and where it holds
										none, past it if it may be none, else no match *)
									Which[
										regs[[a + 1]] < 0, If[b == 0, pc = c, fail = 1],
										regs[[a + 2]] == regs[[a + 1]], pc = c,
										True, pc++],
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
									kind == 4,
										(* an assertion's part with no way: a negative assertion holds, on past it *)
										If[x == 2 || x == 4, pc = rpc; sp = rsp; fail = 0],
									True,
										(* a shortest run, one character more, if the run's class has it: the RUN before rpc *)
										q = 5 (rpc - 1); a = vCode[[q + 2]]; c = vCode[[q + 4]]; cls = a;
										cc = vText[[rsp + x + 1]];
										inside = vmMember[cc, cls, vClasses, masks];
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
								(* the first match at a place; after an empty one, the place again for one not empty *)
								mode == 1 || mode == 2, If[sp > i, i = sp; k = vmNext[vPool, vText, starts, i, 0, m, n]; ne = 0, k = vmNext[vPool, vText, starts, i, 0, m, n]; ne = 1],
								(* every program's match at a place, an empty one once, its program there again for one not empty *)
								mode == 3, If[sp == i, ne = 1, k = vmNext[vPool, vText, starts, i, k, m, n]],
								(* every way: the program's next, as after a condition that fails *)
								mode == 4, pending = 1; answer = 0,
								True, k = vmNext[vPool, vText, starts, i, k, m, n]],
						True, k = vmNext[vPool, vText, starts, i, k, m, n]]]];
			out[[1]] = status; out[[2]] = nRec; out[[3]] = width;
			If[ status == 2,
				(* the condition, its program's names, and the state to go on from *)
				stateLen = 5 + nRegs + 1 + 6 top + 1 + 2 ttop + 1;
				If[ outLen + 3 + 2 maxNames + stateLen > Length[out],
					grown = Table[0, {outLen + 3 + 2 maxNames + stateLen}]; Do[grown[[q]] = out[[q]], {q, outLen}]; out = grown];
				out[[outLen + 1]] = vCode[[5 pc + 2]]; out[[outLen + 2]] = k;
				Do[out[[outLen + 3 + 2 j]] = If[j < nNames, regs[[3 j + 1]], -1]; out[[outLen + 4 + 2 j]] = If[j < nNames, regs[[3 j + 2]], -1], {j, 0, maxNames - 1}];
				q = outLen + 3 + 2 maxNames; out[[q]] = stateLen;
				out[[q + 1]] = i; out[[q + 2]] = k; out[[q + 3]] = pc; out[[q + 4]] = sp; out[[q + 5]] = start;
				q = q + 6; Do[out[[q + j]] = regs[[j + 1]], {j, 0, nRegs - 1}]; q = q + nRegs;
				out[[q]] = top; q++; Do[out[[q + j - 1]] = stack[[j]], {j, 1, 6 top}]; q = q + 6 top;
				out[[q]] = ttop; q++; Do[out[[q + j - 1]] = trail[[j]], {j, 1, 2 ttop}]; q = q + 2 ttop;
				out[[q]] = ne; q++;
				outLen = q - 1];
			Take[out, outLen]]]]

(* The matcher: the host's compiled one, where its units define vmRun; else the declarations'
	Functions compiled by Compile, vmMember's and vmNext's first and put in vmRun's code, where Compile inlines them,
	every argument of vmRun a packed vector of integers, as the paclet's typed code is; else
	evaluated. *)
vmFunction := vmFunction = If[DownValues[vmRun] =!= {} || OwnValues[vmRun] =!= {}, vmRun,
	With[{member = With[{f = $vmMemberDeclaration[[2, 1]]},
			Compile @@ Join[Hold[{{cc, _Integer}, {cls, _Integer}, {vClasses, _Integer, 1}, {masks, _Integer, 1}}], Extract[f, {2}, Hold]]],
			next = With[{f = $vmNextDeclaration[[2, 1]]},
				Compile @@ Join[Hold[{{nxPool, _Integer, 1}, {nxText, _Integer, 1}, {nxStarts, _Integer}, {nxAt, _Integer}, {nxK, _Integer}, {nxM, _Integer},
					{nxN, _Integer}}], Extract[f, {2}, Hold]]],
			run = $vmDeclaration[[2, 1]]},
		Replace[
			If[ Head[member] === CompiledFunction && Head[next] === CompiledFunction,
				Compile @@ Join[Hold[Evaluate[Map[{#, _Integer, 1} &, run[[1]]]]], Extract[run, {2}, Hold] /. {vmMember -> member, vmNext -> next},
					Hold[CompilationOptions -> {"InlineCompiledFunctions" -> True}]],
				$Failed],
			Except[_CompiledFunction] -> (run /. {vmMember -> $vmMemberDeclaration[[2, 1]], vmNext -> $vmNextDeclaration[[2, 1]]})]]]

End[]

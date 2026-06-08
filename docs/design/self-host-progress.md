# Self-Host Progress Log

**Status:** Living log for the N# compiler self-hosting / dogfood migration. Newest entries on top.
See [`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md) for per-slice methodology and
evidence, [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md) for the numbers, and
[`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md) for the
delegate-boundary cost analysis (the key perf finding driving the endgame).

This log records: what migrated, benchmark deltas, adapters removed, bootstrap coverage %, and every
language/runtime/compiler limitation found plus the principled change made to resolve it.

---

## 2026-06-08 — columnar codegen grows `break`/`continue` (corpus coverage 10 → 11 files)

Loop `break`/`continue`. The emitter keeps a stack of the enclosing loops' (end, check) labels; `while`
pushes (endLabel, checkLabel) around its body, `break` branches to the innermost loop's end label,
`continue` to its check label (re-testing the condition). Both reach their target with an empty stack (the
body up to the transfer is net-zero), so they are stack-consistent; nested loops work (an inner break exits
only the inner loop). A `break`/`continue` outside any loop declines. The block emitter's "must be last"
rule now also covers a DIRECT `break`/`continue` child (anything after it is unreachable NL312 code) — a
break/continue nested inside an `if` is conditional, so only a direct child counts. Parity-gated
(`ColumnarCodegen_Parity_BreakContinue`): break-on-match, break-until-negative, continue-to-skip, and nested
loops. This unblocked one more real dogfood file (`ParserDeclarations.nl`), raising measured corpus coverage
to **11 of 32 files**. Cheapest remaining unblocks: `new int[](n)` allocation, then strings/char/casts.

## 2026-06-08 — 🎯 MILESTONE: columnar backend compiles a REAL dogfood file (int[] arrays + Stage-5 proof)

**The standalone columnar backend now compiles a real compiler-service file — `FormatterSafetyScan.nl` —
end-to-end straight from its columnar tables with NO C# AST, and every function matches the authoritative C#
pipeline.** This is the Stage-5 proof-of-concept: the inflection where the columnar pipeline does real
self-host work, not just synthetic spike functions. The new test
`ColumnarCodegen_CompilesRealDogfoodFile_FormatterSafetyScan` reads the ACTUAL file (so it tracks the real
source), asserts the backend accepts it (a silent decline fails the test), and invokes all three functions
(`FormatterSafetyHasError`, `FormatterSafetyErrorIndicesInto`, `FormatterSafetyErrorIndicesChecksumInto`)
via BOTH paths over error/no-error/empty inputs, asserting identical results.

The enabling feature: **`int[]`/`long[]` arrays**. `TryResolveType` maps a canonical `int[]` to the CLR
array type (a single trailing `[]` → `MakeArrayType()`); `IsSupportedType` admits an `IsSZArray` of a
supported element (int/long); `.Length` (member access kind 8) emits `Ldlen; Conv_I4` → int; element read
`a[i]` (index access kind 10) emits `Ldelem_I4`/`Ldelem_I8` (result = element type); element write `a[i] = x`
(assignment to a kind-10 target) emits `Stelem_I4`/`Stelem_I8` after checking the value type == element type.
Index must be int. Jagged (`int[][]`), multi-dimensional (`int[,]`), and unsupported-element (`bool[]`,
`string[]`, `double[]`) arrays all DECLINE (resolution fails → C# path stays authoritative).

Parity-gated across synthetic arrays (sum loops; `safeAt` proving `&&` short-circuits BEFORE indexing so an
out-of-range index can't throw; long[] past int range), array writes (`collectInto` — the real
`FormatterSafetyErrorIndicesInto` pattern; deterministic-overwrite so the shared array across the two
invocations is benign), the decline surface, AND the real file. **Adversarial review (read-only): SHIP** —
array support is SOUND (every seam type-checked; no jagged/multi-dim/element-opcode/stack hole), and the
milestone test is GENUINE (asserts Ok, truly compares both paths, exercises real logic). Added the judge's
suggested decline-boundary cases.

Next real targets (per `project_columnar_gap_analysis`): the ~13 pure-`int[]` dogfood kernels (~40% of the
corpus) now within reach, then strings (`string` type + `.Length` + `str[i]` + IndexOf/Substring) for ~37%.

**Measured corpus coverage: 10 of 32 real dogfood files (~31%, 39 functions) now compile** end-to-end through
the columnar backend with NO C# AST: `AnalyzerExhaustiveness`, `AnonymousUnionShims`, `AotRequirements`,
`CliTreeDependencies`, `CompletionGrouping`, `FormatterImportOrdering`, `FormatterSafetyScan`,
`OverloadCandidates`, `StructCopyAnalysis`, `TextEditOrdering`. Pinned by a ratcheting coverage test
(`ColumnarCodegen_CompilesRealDogfoodCorpus_Coverage`): each named file must compile to a loadable assembly,
and the total compiling count is asserted ≥ the floor, so new features only RAISE coverage. The 22 declines
are blocked by (in rough order): strings/char (most), `break`/`continue`, `new int[](n)` allocation,
match/foreach, casts — the cheapest next unblocks are `break`/`continue` + array allocation, then strings.

## 2026-06-08 — GAP ANALYSIS (target-driven pivot) + short-circuit `&&`/`||`

A read-only gap-analysis workflow surveyed the real 32-file dogfood corpus
(`Compiler.Dogfood/CompilerServices/*.nl` — the compiler's own services in N#) against the backend's
coverage. Findings drove a strategy decision (memory `project_columnar_gap_analysis`): the corpus is
**procedural and array-heavy with NO custom types** (structs/records/classes/enums/unions, generics, match,
foreach, lambdas, exceptions are rare-to-ABSENT — so none are needed for self-host), and **`double` is 0% of
the corpus — a dead end**. Universal needs: int/bool, `int[]` arrays (`a[i]`, `.Length`), if/else, while,
funcs, calls. Very common: casts `(int)char`, string ops, `&&`/`||`. **Decision: go TARGET-DRIVEN** — build
arrays + `&&`/`||` toward compiling the simplest real file (`FormatterSafetyScan.nl`: int[] params, `.Length`,
read+write indexing, `&&`/`||`, sibling calls — nothing else), then the ~13 pure-int[] kernels (~40%), then
strings (~37%). Skip `double`. This replaces the naive scalar-ladder plan (`double`/`string` next).

First slice toward that: **short-circuit `&&`/`||`**. Handled BEFORE evaluating either operand (emit left,
branch on it, evaluate right only on the non-short-circuiting path) — `&&` branches to a `0` on a false left,
`||` to a `1` on a true left. This is both C#-correct AND safety-critical: `i < n && a[i] == x` must not index
`a[i]` when `i >= n`. Both operands and the result are bool. Parity-gated (`ColumnarCodegen_Parity_ShortCircuit`)
incl. chained `a > 0 && b > 0 && c > 0` and a `safeDiv(a, b) = b != 0 && a / b > 0` case that PROVES
short-circuit — with `b == 0`, evaluating `a / b` would throw, so a correct (no-throw) result requires not
evaluating the right side. The former `&&` decline test is now removed. Next: int[] arrays
(param type + `a[i]` read + `.Length`, then `a[i] = x` write) → compile the first real file.

## 2026-06-08 — Stage 4b-bit: columnar codegen grows bitwise & shift operators (int/long)

Bitwise `&`/`|`/`^` (And/Or/Xor) and shifts `<<`/`>>` (Shl/Shr) for int/long — mechanically simple, no
NaN/BCL complexity. `&`/`|`/`^` require both operands the same int/long type (result that type). Shifts are
the exception to the same-type rule: the value is int/long but the shift COUNT is always int, and the result
is the value's type; `>>` is the SIGNED/arithmetic right shift (sign-extends a negative value), matching C#.
Confirmed the columnar `>>` is a single binary operator in expression context (the `>>` token split only
applies inside generic type arguments). Parity-gated (`ColumnarCodegen_Parity_Bitwise`) incl. negative `>>`
sign-extension (`-8 >> 1`, `-1 >> 4`), long shifts past 32 bits (`1L << 40`), and the `Modifiers`-flag idiom
`1 << 11 | 1 << 12` — directly relevant to compiling the compiler's own flag code. Next on the type ladder:
`double` (NaN-correct `<=`/`>=` deferred for fresh review) and `string` (BCL `op_Equality`/`Concat`).

## 2026-06-08 — Stage 4b-div: columnar codegen grows integer/long division & modulo

Rounds out the arithmetic operators for int/long: `/` → `Div`, `%` → `Rem` (the SIGNED forms, matching C#
for int/long). No type-system subtlety — both operands the same int/long type, result that type — and no
new BCL/NaN complexity, so a small, low-risk slice. Divide-by-zero and `INT_MIN / -1` throw at runtime
exactly as the C# path does. Parity-gated (`ColumnarCodegen_Parity_DivMod`) with NEGATIVE operands to pin
the C#-matching semantics (truncation toward zero; the remainder's sign follows the dividend), an
in-expression use (`(a + b) / 2`), and large long values. Useful for real compiler code (hashing, indexing
math). Next on the type ladder: `double` (`ldc.r8` + NaN-correct `<=`/`>=` via the `.un` compare variants —
deferred for fresh review of the NaN subtlety) and `string` (BCL `op_Equality`/`Concat`).

## 2026-06-08 — Stage 4b-ii: columnar codegen grows `long` (i8 — first distinct stack representation)

On the type-aware foundation, `long` slots in cleanly. A long literal is an `IntLiteral` token whose text
keeps the `L`/`l` suffix (the lexer preserves it), so the emitter distinguishes `5L` → `ldc.i8` (type long)
from `5` → `ldc.i4` (type int); unsigned suffixes (`u`/`U`, `UL`/`LU`) decline (uint/ulong unsupported).
Long arithmetic/comparison/unary reuse the SAME opcodes as int (`add`/`sub`/`mul`/`neg`/`not`/`clt`/`cgt`/
`ceq` all work on i8) — the only new opcode is `ldc.i8` — with the result type propagated as long. Long
params/locals/returns work via the existing type machinery. Mixed int/long arithmetic (implicit widening)
is NOT modelled — both operands must be the same type, else decline (safe: the C# path handles widening).

This is the first type where the per-arg type check added in 4b-i genuinely matters: int and long have
distinct stack representations (i4 vs i8), so passing an int where a long is expected would be invalid IL —
the check declines it. Parity-gated (`ColumnarCodegen_Parity_LongType`) vs the C# pipeline, deliberately
including VALUES BEYOND int range (`1e9 * 1e9 = 1e18`, `factL(20)`) to prove it is genuinely i8, not i4.
Declines mixed int/long and a `ulong` literal. Updated the now-stale int-only decline tests (a pure-long
function is no longer declined). Next: 4b-iii `double` (`ldc.r8`, float arithmetic), then `string`.

## 2026-06-08 — Stage 4b-i: TYPE-AWARE columnar emitter + bool (first type beyond int)

The biggest Stage-4 refactor: `ColumnarIlEmitter` went from an UNTYPED int-only emitter to a TYPE-AWARE
one. `EmitExpression(int idx, out Type type)` now reports each expression's CLR type, and every consumer
checks it — Return requires the value type == the declared return type; a `:=` local declares its type from
the initializer (`DeclareLocal(initType)`); assignment requires value type == the local's `LocalType`; a
Binary requires both operands the same type (no implicit conversions); a Call checks each argument's type
against the callee's param types. This is the foundation for every type beyond int.

Proven by adding **bool** alongside int: bool literals (`true`/`false` → i4 1/0), comparisons in VALUE
position (the comparison opcodes moved from the old `EmitCondition` into `EmitExpression`'s Binary case via
a shared `EmitComparison`; ordering `< > <= >=` on int, equality `== !=` on int or bool → bool), logical
`!` (`ldc.i4.0; ceq`), bool params/locals/returns, and — since conditions are now any bool expression —
a bool literal/param/local or a bool-returning call drives `if`/`while` directly. The type machinery
prevents cross-type mixing (a bool can never leak into int arithmetic or an int return).

Verified in two stages: FIRST the int subset was confirmed behavior-preserving (all existing int tests pass
unchanged — the refactor adds type checks as a safeguard layer without altering int opcodes/control flow),
THEN bool was added. Parity-gated (`ColumnarCodegen_Parity_BoolType`) vs the C# pipeline across all bool
forms, plus declines for `&&` (short-circuit, not yet lowered), bool-from-int-return, and bool+int mixing.

**Adversarial review (read-only) — ship-with-nits.** The int-regression probe confirmed behavior
preservation (all-info findings); the soundness probe found ONE real gap that bool *introduced*: call
ARGUMENT types weren't checked against callee param types, so (int and bool both being i4) `needsBool(5)`
would emit verifiable-but-wrong IL. Fixed by carrying callee param types in the sibling map and checking
each arg's type; added the judge's exact suggested cases (a `needsBool(5)` decline + a correct
`needsBool(x > 0)` positive). Next: 4b-ii `long` (distinct i8 representation — `ldc.i8`, long arithmetic/
comparisons), then `double`, then `string`.

## 2026-06-08 — Stage 4i: columnar codegen grows sibling calls (incl. recursion + mutual recursion)

Direct calls to top-level functions (columnar Call, kind 9, `[callee, args...]`). The multi-function
backend's two-pass structure makes this clean: pass 1 declares ALL methods and builds a sibling map
(name → declared `MethodBuilder` + param count) BEFORE any body is emitted, so a body can `call` any
function — including a forward reference (a callee declared later) and **itself** (the map includes the
current function, so direct recursion works for free). The Call case: require a bare-identifier callee
(kind 6) not shadowed by a local/param (a delegate/closure invocation declines), look it up in the sibling
map, check arity (no overloads/defaults/params-array), emit each int arg left-to-right, then
`call` the `MethodBuilder` (the token is baked at `CreateType`/`Save`). Param count is carried in the map
because `MethodBuilder.GetParameters()` is unsupported before the type is created. A duplicate top-level
function name (an overload set the spike does not model) declines the whole program.

Parity-gated (extends `ColumnarCodegen_Parity_MultiFunction`) and matched to the C# pipeline across: a
sibling call + a NESTED call (`add(add(a,b), c)`); **self-recursion** (`fact`, two-call `fib`); and
**mutual recursion** with a FORWARD reference (`isEven` calls `isOdd` declared after it). With calls the
columnar backend can now compile genuinely recursive int programs end-to-end with no C# AST. Next: 4b
(types beyond int — long/bool/double/string via the builtin map + type-aware emission).

## 2026-06-08 — ROUTING DECISION + Stage 4-multi: standalone columnar backend, multi-function emission

**Architecture decision (user, 2026-06-08):** route columnar codegen into production via a **standalone
columnar pipeline** — a columnar-first backend that OWNS parse→bind→analyze→codegen→assembly with NO
internal C# AST — NOT by re-parsing each function inside the AST-driven `ILCompiler`. The scoping (two
read-only workflows) found the load-bearing constraint: `ILCompiler` consumes only the `CompilationUnit`
AST and has no source access (`CompilationUnit`/`FunctionDeclaration` carry Line/Column but no source text
or byte span), while the columnar kernels parse source strings — so the re-parse-in-ILCompiler path means a
redundant second parse + unsolved per-function source extraction. The standalone pipeline avoids both and
IS the Stage 5/6 endgame. (Recorded in memory `project_routing_standalone_columnar_pipeline`.) The Stage-4
spike's `TryEmitColumnarFunction` already builds a real assembly (PersistedAssemblyBuilder→DefineType→
DefineMethod→Save) — it is the seed of this backend, not throwaway.

**First slice — multi-function emission.** Generalised the single-function spike into
`ColumnarIlEmitter.TryEmitColumnarAssembly(typeName, funcs[], source)`: emit EVERY top-level function into
ONE assembly/type via a **two-pass** structure — pass 1 resolves each signature (int-only) and DECLARES all
methods up front; pass 2 emits each body. Declaring all methods before emitting any body is the foundation
for sibling calls (4i): a body will resolve a call to a sibling `MethodBuilder` that is declared but not yet
emitted. The whole program declines if ANY function is ineligible (keeping the C# path authoritative). New
`ColumnarFunctionInput` carries one function's signature + columnar body tables; the adapter's orchestration
was refactored into a shared `TryGetColumnarFunctionInputs` (tokenize+compact, require every top-level decl
to be a `func`, parse each) + `TryParseColumnarFunctionAt` (one function's signature+body), with
`TryEmitColumnarFunction` (single, unchanged surface) and the new `TryEmitColumnarProgram` (multi) on top.

Parity-gated by the new `ColumnarCodegen_Parity_MultiFunction`: two/three independent int functions
(arithmetic, guard clause, while accumulation, if/else) emitted into one assembly, each invoked and matched
to the C# pipeline; a single function through the multi path; and a decline when a second function is
non-int. The single-function spike + parity tests still pass (back-compat preserved). Next: 4i (sibling
calls — emit `call` to a declared MethodBuilder), then 4b (types beyond int).

## 2026-06-08 — Stage 4g-ii: columnar if/else completed — general fall-through merge (all four arm combos)

Unifies `ColumnarIlEmitter`'s `If` (kind 27) into one general algorithm covering all four
then/else fall-through-vs-return combinations, replacing the two special cases (closed both-return else +
bare if-without-else). The merge: `cond; brfalse else; then; [br end (if then falls through)]; else:
<else>; [end: (if then falls through)]`. The skip-`br` over the else-block and the `end` label it targets
are emitted **only when the then-branch can fall through** — exactly the just-landed EmitIf fix carried into
the columnar emitter; if the then-branch always returns, that `br` is dead and would risk a method-end
label. The function-level always-returns gate guarantees a later statement follows whenever the if itself
falls through, so the merge is never the bare method end. Both branches' `:=` locals are scoped. The
both-return form (`max`/`sign`) is unchanged behaviorally — it now flows through the same code with
`thenFallsThrough == false`, so no `br`/`end` is emitted (identical IL).

Parity-gated across the full if/else state space, each over multiple inputs: then-falls/else-returns,
then-returns/else-falls, both-fall-through (and both-return via the existing `max`/`sign`), plus the 4g
guard-clause and merge-position cases. The former `elseFall` decline is now the positive `tf`. The if/else
control flow is now complete in the columnar emitter.

## 2026-06-08 — Stage 4g: columnar codegen grows if-WITHOUT-else (guard clauses, fall-through merge)

Extends `ColumnarIlEmitter`'s `If` (kind 27) to the bare `if cond { then }` form (childCount 2) — the
first fall-through branch with a merge label: `cond; brfalse end; then; end:`. Both edges reach `end` with
an empty stack (the brfalse pops the condition bool; a fall-through then-branch is net-zero; a then-branch
that returns ends in `ret` and never reaches `end`). The just-fixed EmitIf/EmitSwitch method-end-label
hazard **cannot arise here**: an if-without-else has `AlwaysReturns == false`, and the block emitter
declines any non-last statement that always-returns, so a successfully-emitted always-returning body always
has a later statement after the guard (a loop back-edge, an enclosing merge, or a trailing `return`) — `end`
is never the bare method end. The then-branch's `:=` locals are scoped (a braceless `:=` would otherwise
leak), mirroring the while-body scoping. The if-WITH-else fall-through shape (else present, not both-return)
is still declined — only the closed both-return else and the bare if-without-else are modelled so far.

Verified empirically (the strongest check for codegen — it caught the EmitIf/EmitSwitch bugs the adversarial
review missed): the parity oracle now compiles guard-clause functions via BOTH paths and asserts identical
results across inputs, including the **risky merge-label positions** — a guard nested in another guard's
then-branch, a guard as the LAST statement of a while body (merge label followed by the back-edge), and a
guard as a non-last while-body statement. Plus spike invoke-tests for then-returns / then-falls-through /
sequential guards. The former `noElse` decline is now a positive; a new `elseFall` case pins that the
else-with-fall-through shape still declines.

## 2026-06-08 — Stage 4c: columnar↔C# parity oracle — and the two production codegen bugs it caught

The Stage-4 inflection needs an acceptance gate before any routing: proof that the columnar emitter is
semantically equivalent to the C# path it will replace, not merely self-consistent. New test
`ColumnarCodegen_Parity_MatchesCSharpPath` compiles each eligible function **both** ways — the columnar
path (`TryEmitColumnarFunction`) and the authoritative production pipeline (`MultiFileCompiler` →
`ILCompiler`) — then invokes each emitted method over a spread of inputs (negatives, zero, comparison
boundaries, overflow extremes) and asserts the results are identical. 15 functions spanning every
supported form (literals, params, `+ - *`, unary `-`/`~`, paren, `:=` locals, assignment, if/else, nested
if/else, while accumulation incl. `fact`). This is the gate every future codegen-routing slice must clear.

**The oracle immediately earned its keep — it caught two real, latent production codegen bugs in the C#
`ILCompiler`, both the same class** ("a `br` to a label marked at the very end of the method, i.e. an
offset with no instruction" → IL that crashes ilverify with `MarkPredecessorWithLowerOffset` and faults
the JIT with `InvalidProgramException` *on invoke*). Both compile cleanly and only fail when the method is
actually run — which is why they hid: the prior coverage (`ILCompiler_CanCompileIfStatement`,
`ILCompiler_CanExecuteSwitchStatement`) either never invoked, or never used the triggering shape.

- **`EmitIf` (`ILCompiler.cs:~12312`)** — `if/else` where **both arms return and nothing follows the
  `if`** (e.g. `func max(a,b) { if a > b { return a } else { return b } }`). It unconditionally emitted
  `br endLabel` to skip the else, then marked `endLabel` at method-end. Fix: a sound, conservative
  `StatementCompletesNormally(Statement)` helper (false only for provable always-transfer:
  return/throw/break/continue, a block whose any statement transfers, an if whose both arms transfer;
  everything else defaults to "may fall through"); the skip-branch and its label are emitted only when
  the then-branch can fall through. Reachable control flow is unchanged in every other case (the elided
  `br` was always dead).
- **`EmitSwitch` (`ILCompiler.cs:~12776`)** — the **identical shape**: a `switch` as the last statement of
  a non-void function where every case body **including `default`** returns (definite-return is satisfied
  by the cases, so it compiles). Same fix: gate the per-case implicit-break `br endLabel` on
  `StatementsCompleteNormally(case.Statements)`; `endLabel` stays unconditionally marked because `break`
  and the no-default no-match dispatch path still target it.

**Verification discipline:** standalone CLI repros confirmed each bug as an ilverify `MarkPredecessorWith­
LowerOffset` crash *before* the fix and `CLEAN` after, with fall-through controls staying clean. A
read-only adversarial workflow (Explore agents + judge) ruled the `EmitIf` fix **sound** (no unsound
false-positive, no label-marking hazard). The judge under-rated `EmitSwitch` ("endLabel is always marked,
so the branch is valid") — but that misdiagnoses the bug (the *original* `EmitIf` endLabel was also always
marked; the hazard is a label at method-*end*, not an unmarked one). A direct ilverify repro proved the
`EmitSwitch` bug real and in-scope. Lesson reaffirmed: **empirically reproduce, don't trust a judge's
hand-wave.** Two columnar-independent regression tests added
(`ILCompiler_IfElseBothBranchesReturn_NoTrailingStatement_IsRunnable`,
`ILCompiler_SwitchAllCasesReturn_AsLastStatement_IsRunnable`) so the guards survive even if the spike is
later removed. Gate green (3781 tests + IL-verification gate).

**On 4j (routing into `ILCompiler`):** scoping confirmed `ILCompiler` consumes only the `CompilationUnit`
AST and has **no access to raw source** (`CompilationUnit`/`FunctionDeclaration` carry `Line`/`Column` but
no source text or byte span), while the columnar kernels parse source strings. So "inject columnar
body-emit into `EmitFunctionBody`" as originally framed implies threading source through `ILCompiler` and
**re-parsing each function** — a redundant second parse, blocked on unsolved per-function source
extraction. 4c was the right fork-independent step regardless; the routing approach (re-parse-in-ILCompiler
vs a standalone columnar codegen pipeline that Stage 5 routes to wholesale) is the open architecture fork.

## 2026-06-08 — Stage 4e: columnar codegen grows unary `-`/`~`

Small slice: int prefix unary in `ColumnarIlEmitter` — `-`→`neg`, `~`→`not` (emit the operand, then the
opcode). `!` (logical not), `++`, and `--` decline (the operator-token text isn't `-`/`~`). Invoke-tested:
`neg(5)==-5`, `bnot(0)==-1` / `bnot(5)==-6` (one's-complement = two's-complement minus one), and unary inside a
larger expression (`x := -a; return x + b`). Nested `- -a` parses as nested unary and works; the unsupported
`!a` declines. Proportionate to a 2-opcode slice, this skipped the heavy adversarial workflow — the direct
load+invoke test across signs/edge cases plus the gate's IL-verification are dispositive here.

With this the spike covers params, int literals, unary `-`/`~`, `+/-/*` and comparisons, paren, `:=` locals,
assignment, if/else, and while — enough to compile real int functions, and the columnar→IL question is well
proven. The strategic next step is the inflection itself: 4c (a parity-vs-C#-path harness) then 4j (routing the
columnar codegen into `ILCompiler` with C# fallback), where it starts replacing C#.

## 2026-06-07 — Stage 4h: columnar codegen grows while loops (general control flow) + block scoping

The first GENERAL (fall-through) control flow in the columnar emitter. A While (kind 26) emits
`check: cond; brfalse end; body; br check; end:` — the stack is empty at both merge labels (the condition
pushes a bool that `brfalse` pops; the body is net-zero), so it is stack-consistent and verifiable. A
degenerate loop whose body always returns (exits on the first iteration) declines rather than emit a dead
back-edge. Invoke-tested with real iterative computations: `count` (accumulate to n), `sumTo` (1..n with `<=`),
`fact` (`fact(5)==120`, a local read+written each iteration), and `twice` (a `:=` local declared inside the
loop body and used within it).

Also added BLOCK SCOPING: a `:=` local declared in a block leaves scope when the block ends (snapshot the local
names on entry, remove the ones added on exit). Without it, a flat name table would let a loop-body local leak
into the post-loop scope — and a reference there (out of scope in N#) could read a method-level slot that is
unassigned when the loop runs zero times (invalid IL), or just wrong. **Adversarial review surfaced a gap in
the first cut:** block scoping only covered `{ }` Block bodies, but the kernel also allows a BRACELESS
single-statement loop body (a bare `:=`), which isn't a Block and leaked. Fix: the while case scopes its body
directly too. Decline tests for both the braced and braceless leak shapes, plus the degenerate loop.

Note the if/else first cut still requires BOTH branches to always return, so an `if` with non-returning branches
(the common in-loop conditional) currently declines — the general fall-through `if` is deferred to 4g+. Gate
green. Next: 4c (real dispatcher + parity-vs-C#-path harness), 4i (calls), 4j (route).

## 2026-06-07 — Stage 4f: columnar codegen grows simple assignment statements

Extends `ColumnarIlEmitter` with a simple `local = expr` assignment statement. An ExpressionStatement (kind 23)
whose child is an Assignment (kind 14) with operator `=` and an Identifier target that is an existing `:=` local
emits the value expression then `stloc` into that local. Invoke-tested: `acc` (`x = x + b`) and `bump` (two
reassignments). Declines: compound assignment (`+=`/`-=`/… — the operator-token text is not `=`), assigning to
a parameter or a non-identifier target (`arr[i]`, `obj.f`), and any non-assignment statement (a bare call). The
columnar fact that made this clean: AssignmentExpression carries its operator token in its value span
(`ParserExpressions.nl:578`), so `=` vs `+=` is a string check; and the corpus uses no compound assignments.

**Adversarial review caught a latent codegen bug (present since 4d):** a function body that does not return on
all paths — e.g. `func f(a: int): int { x := a` then `x = x + 1 }` (ends in an assignment) or `{ x := a }`
(ends in a `:=`) — emitted IL that falls off the end with no `ret` = invalid (`InvalidProgramException` on load).
All prior positive tests happened to end in `return`, so it slipped through. Fix: the emitter requires the
function body to ALWAYS return (the same `AlwaysReturns` subset) before emitting; a non-returning body declines
to the C# analyzer (which would flag NL305). Decline tests added for an assignment-ended and a `:=`-ended body.
Gate green. Next: 4c (real dispatcher + parity-vs-C#-path harness), 4h (while), 4i (calls), 4j (route).

## 2026-06-07 — Stage 4g: columnar codegen grows if/else (first cut) + int comparisons

Extends `ColumnarIlEmitter` with control flow. **First cut deliberately requires an `if`/`else` where BOTH
branches always return** — then there is no fall-through, so no merge label or trailing-`ret` analysis is
needed: emit the condition, `brfalse elseLabel`, emit the then-branch (ends in `ret`), `MarkLabel(elseLabel)`,
emit the else-branch (ends in `ret`). Conditions are restricted to an int comparison (`< > <= >= == !=`, the
negated ones as `cgt`/`clt` followed by `ceq 0`), emitted via a separate `EmitCondition` so a comparison (a
bool) can never leak into an int value/return position (which would diverge from N#'s type rules). A new
`AlwaysReturns` helper (the same subset as the diagnostics pass) gates the both-branches-return requirement.
Invoke-tested: `max` (via `>`), `absish` (via `>=` and `0 - a`), and a nested `sign` whose else branch is itself
a both-returning if/else.

**Adversarial review caught a real codegen bug:** `AlwaysReturns(Block)` is true if ANY statement returns, but
the Block emitter emits ALL statements — so a block with code after a return (e.g. `{ return 1` then `y := 2 }`,
which the parser accepts and NL312 flags as unreachable) would emit IL past a `ret`. Fix: a returning statement
must be the LAST in its block; otherwise the emitter declines (keeping the C# analyzer/codegen authoritative —
the dogfood corpus has zero unreachable code, so no coverage cost). Decline tests added for if-without-else, a
fall-through branch, non-comparison conditions, a comparison in value position, and unreachable-after-return.
Gate green. Next: 4c (real dispatcher + parity-vs-C#-path harness), 4h (while), 4i (calls), 4j (route).

## 2026-06-07 — Stage 4d: columnar codegen grows `:=` locals

Extends the Stage-4 spike (`ColumnarIlEmitter`) to int `:=` local variables. A VariableDeclaration (kind 24)
emits its initializer, `DeclareLocal(typeof(int))`, then `stloc`; identifiers resolve to a local (`ldloc`)
before a parameter (`ldarg`). Invoke-tested: a `:=` local feeding a return (`sum`), chained locals where the
second reads the first (`chained`: `x := a + 1` then `y := x * 2`), and a local mixed with a param in the
returned expression (`square`: `t := a * a` then `return t + a`).

**Adversarial review caught a real divergence:** a local that shadows a parameter (`func shadow(x: int): int {
x := x + 1 … }`) was accepted, but N# treats shadowing as a diagnostic — so the columnar path would silently
compile a program the C# path flags. Fix: the VariableDeclaration case DECLINES when the name is already a
parameter (shadow) or an already-declared local (redeclaration), keeping the C# analyzer authoritative. With
that, the local and parameter name sets are disjoint for accepted programs. Decline tests added for shadowing,
redeclaration, and assignment statements (`x = …`, kind 23 — an ExpressionStatement, not handled yet). Gate
green. Next: 4c (turn the spike into a real dispatcher + a parity-vs-C#-path harness), 4g–4h (if/while), 4i
(calls), then 4j (route through `ILCompiler.DeclareFunction`).

## 2026-06-07 — Stage 4 SPIKE: columnar codegen proven end-to-end (columnar tables → runnable IL)

The Stage 4 inflection point, de-risked. New `Columnar/ColumnarIlEmitter.cs` + adapter
`TryEmitColumnarFunction` emit a real one-method .NET assembly whose body IL is generated **directly from the
columnar statement/expression tables — no C# AST** — then the test **loads and invokes** it and checks results.
This proves the columnar pipeline can drive codegen, which is the load-bearing assumption for routing C# out
(stages 5–6).

Self-contained (`PersistedAssemblyBuilder` → `Save` → `Assembly.Load`), so it touches NONE of the 25k-line
`ILCompiler.cs` — the emit primitives (`ldarg`/`ldc.i4`/`add`/`sub`/`mul`/`ret`) are exactly what the full
columnar codegen will emit, so the logic transfers; only the tiny assembly-build harness is spike-local (replaced
by `ILCompiler`'s flow at slice 4j). Proven INT-ONLY for: param load, int literal, parenthesized expr, and int
`+`/`-`/`*` binary including nested left-associative (`a - b - c`) and multi-param (`a * b - c`, `(a+b)*b`).
Invoke-tested: `identity(42)==42`, `answer()==42`, `add(2,3)==5`, `poly(3,4,5)==7`, `chain(10,3,2)==5`,
`paren(2,3)==15`, `inc(5)==6`.

Adversarially verified (read-only Explore): decline-safety is strong — every unsupported form (locals, expr
statements, if/while, calls, member/index, unary, comparison/logical/division operators, non-int types,
multi-function sources, empty bodies) returns false (no assembly) so the C# path is untouched. Two mis-emit
risks were caught and fixed proactively: (1) mixed-type arithmetic (`int + long`) would emit `add` on (i4, i8)
= invalid IL → added an INT-ONLY guard (return + every param must be `int`); (2) a value-less `return` in an
int function would emit `ret` with an empty stack → now declined. Both have decline tests.

Folds in 4a (binary) + 4f (int literals) for the int subset. **Next:** 4c — turn the spike into a real columnar
dispatcher + a parity-vs-C#-path harness (compare columnar-emitted output to `NSharpCompiledMethod.Bind`); then
4d locals, 4g–4h if/while, and 4j route through `ILCompiler.DeclareFunction` (where emitted IL hits the
ilverify gate).

## 2026-06-07 — Stage 3b-iii: columnar unused-local (NL001) — Stage 3b COMPLETE

Third and last columnar diagnostic, completing Stage 3b. NL001 ("declared but never read") lives in the
**Linter** (not the Analyzer), and it is **time-/scope-ordered**: `CheckUnusedVariables` runs at each block's
`PopScope` against a file-level `_usedVariables` set that `MarkVariableUsed` populates for every identifier use
(including assignment targets and call callees) plus every parameter, accumulates in traversal order, and is
**never cleared between functions**. So a use appearing AFTER a block closes (a later sibling block, or a later
function) does NOT suppress that block's unused locals, while an EARLIER use (a prior function, an earlier
statement, or a parameter) does.

**A first attempt got this wrong** and was reverted (`fe61aa51`): it used a naive "a local is unused iff its
name never appears as an identifier anywhere in the source" GLOBAL rule. That over-suppresses — e.g.
`func first() { x := 42 }` (an unused `x`) followed by a `func second()` whose body reads `x`: the Linter flags
`first`'s `x` (its block closed before `second` was visited), but the global rule does not. The first adversarial review's *judge* approved it on
mirror-parity grounds, but a direct audit of `Linter.cs` (functions push a scope at `:631`, blocks at `:833`;
the check at `PopScope`/`:285`) showed the mirror itself wasn't faithful to the Linter — so it was discarded.

**The faithful implementation** (`ColumnarDiagnosticsPass.CollectUnusedLocals` + the adapter's
`TryCollectUnusedLocals`): process functions in source order sharing one `usedNames` set (seeded per function
with its params, never cleared); walk each body in source order with a stack of per-Block scopes; record each
`:=` local (kind 24) in the innermost block; and at each Block (kind 25) exit, flag its locals whose name is not
`_`/`_`-prefixed and not in `usedNames` AS OF THEN. The per-scope `used` flag is correctly subsumed (used=true ⟹
name in `_usedVariables`, so the check reduces to "name not in `usedNames` at block exit"). Braceless bodies
(`if c x := 1`) attribute the local to the enclosing block — matching the Linter, which pushes no scope for a
non-block body. Interpolated strings (`$"...{x}..."`) can't hide a use: the kernel refuses them, so such sources
decline (`bodyNodeCount <= 0`) to the C# linter (verified empirically). Reported at the declaration's line:col.

**Parity:** a new `MirrorWalkUnused` reproduces the exact time-ordered walk on the C# AST; 9 hand-built cases
pin both ordering directions (later use does NOT suppress / earlier use DOES), nesting, assignment-marks-used,
and discard exemption; plus the full 32-file dogfood corpus (sorted columnar == sorted mirror). Re-verified
clean (APPROVE) after the rewrite. **Stage 3b is now COMPLETE** (NL305 + NL312 + NL001). Next: Stage 4 —
columnar codegen, the inflection point where the C# binder/analyzer begin to be routed out and deleted.

## 2026-06-07 — Stage 3b-ii: columnar unreachable-after-terminal (NL312), parity-gated

Second columnar diagnostic. `ColumnarDiagnosticsPass.CollectUnreachable` mirrors `Analyzer.AnalyzeStatements`
(2017): in each statement list (a Block), once a statement always exits (`StatementAlwaysReturns`), the
IMMEDIATELY following statement is reported unreachable (once, then the rest of that list is skipped), recursing
into nested blocks / if-branches / while-bodies exactly as `AnalyzeStatement` does. Emitted per function before
the definite-return descriptor (deterministic order).

**Position fidelity (the tricky bit):** the diagnostic reports the unreachable statement's `line:col`. The AST
carries `Statement(Line, Column)`; the columnar statement node carries only a byte span. Rather than reconstruct
line/col (and risk a counting-convention mismatch with the C# lexer), the adapter builds a byte-offset → (line,
col) map straight from the tokenizer's own per-token metadata (`rawStarts`/`rawLines`/`rawColumns`) and passes a
`PositionOf` resolver to the pass. Because the dogfood tokenizer and the C# lexer agree byte-identically, the
resolved line/col equals the AST `Statement.Line/Column` — confirmed empirically: the test asserts the FULL
descriptor strings (incl. `line:col`) equal the C#-AST-walk mirror, which would fail on any position drift.

**Parity:** a new `MirrorCollectUnreachable` walks the AST with identical logic; tested on 6 hand-built cases
(dead code after return; after a terminal if/else; only-first-reported-then-skip; unreachable inside a reachable
nested block; the unreachable-before-missing-return ordering; and a clean negative) asserting columnar == mirror
+ a non-vacuous unreachable count. The 32-file dogfood corpus (in the definite-return test's corpus loop) now
also validates zero unreachable on valid self-host source. Adversarially verified (read-only Explore workflow:
control-flow parity, position fidelity, test non-weakening — all clean, APPROVE). Note the analyzer's NL312 keys
off `StatementAlwaysReturns`, which is FALSE for break/continue, so code after break/continue is NOT flagged —
the columnar pass matches (it does not "improve" on the analyzer). Next: 3b-iii unused-local.

## 2026-06-07 — Stage 3b-i: columnar definite-return (NL305) — first columnar diagnostic, parity-gated

First slice of Stage 3b (columnar diagnostics): definite-return / not-all-paths-return (NL305), computed
DIRECTLY over the columnar statement tables with no C# AST. New `Columnar/ColumnarDiagnosticsPass.cs` +
adapter entry `NSharpCompilerDogfoodAdapter.TryCollectTopLevelFunctionDiagnostics` (reuses the stage-3 parse
scaffold; per function returns `[]` or `["missing-return:<canonicalReturnType>"]`).

`ColumnarDiagnosticsPass.StatementAlwaysReturns` is the columnar **subset** of the real
`Analyzer.StatementAlwaysReturns`: Return always exits; a Block exits if any statement exits; an If exits only
with an else where both branches exit; Break/Continue/ExpressionStatement/VariableDeclaration/While are
non-exiting. This subset is faithful by construction because the parser kernel REFUSES throw/switch/try/wrapper
forms (the richer terminal shapes the real analyzer also handles can't appear on any body the pass accepts), and
an omitted return type is treated as void — matching `Analyzer.cs:621` (`func.ReturnType != null ? ResolveType :
Void`).

**Limitation found + resolved (adversarial review):** the real analyzer EXEMPTS async-unit-task
(`async func f(): Task {}` / `ValueTask`) and iterator (`func* g()`) functions from NL305 — exemptions that need
BCL task-type knowledge the structural pass cannot model. The first cut accepted `async func f(): Task {}` and
wrongly emitted `missing-return:Task`. Fix: the adapter now DECLINES any source with an async/generator function
(via `TopLevelDeclarationModifiers` + `Modifiers.Async|Generator`), falling back to the C# analyzer for exact
parity. The dogfood corpus has zero async/generator functions, so coverage is unaffected. (Generators already
declined at the parse stage; the modifier guard makes it explicit and covers async.)

**Parity:** per hand-built case against the EXACT expected diagnostics AND a C#-AST-walk mirror
(`MirrorAlwaysReturns`); on the full **32-file dogfood corpus**, equal to the mirror AND emitting ZERO
missing-return (valid self-host source compiles → the real analyzer emits no NL305 → a real-analyzer parity
check). Plus boundary assertions that async/generator sources decline. Adversarially verified twice (read-only
Explore workflow): the first pass caught the async unit-task divergence; the re-verify after the fix was clean
(no remaining columnar-vs-analyzer divergence on valid input). Definitive routed parity follows at stages 4–5.
Next: 3b-ii unreachable-after-terminal, 3b-iii unused-local.

## 2026-06-07 — Track C perf capstone: rigorous single-machine native re-run + P4 backend decision

Closed out Phase P with the rigorous step the roadmap reserved: a **cross-language re-run with all four
languages measured back-to-back on one cool, idle machine** (Apple M4, .NET 10, rustc 1.96, Apple clang 17),
using the **vectorizing N# compiler** (P1+P2+P-minmax+P-ctrans, default-on). This converts the previously
*implied* "~1.6–2× behind native" into a **measured** result and refreshes the stale 2026-06-06
pre-vectorization table in [`systems-vs-native.md`](systems-vs-native.md).

**Measured N#/best-native (was scalar 2026-06-06 → now vectorized):** checksum-sum 8.78× → **2.02×**;
count-ascii 6.30× → **1.63×**; count-transitions 4.54× → **1.97×**; min-max-delta 10.5× → **1.67×**;
rolling-hash 1.61× → **1.62×** (non-vectorizable floor, correctly unchanged); parse-eight-digits 1.84× →
**1.80×** (all at 4096). Worst single cell across the whole matrix is **2.49×** (min-max-delta @64, where the
SIMD helper's fixed setup dominates a 4.5 ns native min/max) — down from 10.5×. N# now **beats C#/RyuJIT
~2–6×** on the vectorizable kernels (it emits `Vector<T>`; RyuJIT runs scalar) and ties C# on the
non-vectorizable ones (rolling-hash, scan-tag ≈1.0×). Native (Rust/C) columns are within run-to-run noise of
2026-06-06 — only the N# column moved, by emitting SIMD. Internal consistency confirms the vectorized path
(MinMaxDelta 5.9× faster than C# matches P-minmax(c); CountTransitions 2.2× matches P-ctrans; RollingHash/ScanTag
correctly ≈1.0×).

**P4 — LLVM/NativeAOT backend decision (DEFERRED, evidence-gated).** New decision doc
[`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md). The structural backend's
original justification was the 8.8–10.5× SIMD-vs-scalar gap; Phase P's per-pattern `Vector<T>` emission (the
.NET-recommended approach, since RyuJIT does not auto-vectorize loops — dotnet/runtime#11263) already captured
that prize. The residual ~1.6–2× is latency-bound / small-input / scalar-scheduling tax, which a backend swap
does not cheaply remove: NativeAOT shares RyuJIT's codegen (no loop auto-vectorization either), and
NativeAOT-LLVM is experimental and WASM-targeted. **Decision: defer the vectorizing structural backend (D/E)
behind gates G1–G4; keep extending per-pattern `Vector<T>` only on measured need; treat NativeAOT *image
emission* as a separate, lower-risk CLI startup/size track (orthogonal to throughput — `nlc publish --aot` is
analysis-only today).** Cheapest next perf step: broaden the corpus from synthetic i32 kernels to a real
compiler hot path before any structural bet. Docs-only slice; non-VS-Code gate green.

## 2026-06-07 — Rust-perf P-ctrans: shifted-compare SIMD count-transitions — the LAST vectorizable kernel, Rust-class

Vectorizes the count-transitions kernel (the last addressable Rust gap, ~2.5–4.5× behind native). This is the
realization of the roadmap's "P3" — but as VECTORIZATION rather than literal bounds-check elision, which is the
bigger win (the BCE goal — removing the per-iteration indexed-load+branch tax — is subsumed by replacing the loop
with a SIMD helper). count-transitions counts `i in [1,len)` where `a[i] != a[i-1]`. The loop carries `previous`,
but seeding the helper with `previous`'s live value makes the rewrite value-identical for ANY init — no non-local
init analysis: the scalar loop's first comparison is `a[start]` vs `previous` and every later one is `a[i]` vs
`a[i-1]`, which the helper reproduces exactly.

`SimdReductions.CountTransitionsInt32(array, start, end, seedPrevious) -> (int Count, int LastPrevious)`: compares
`a[start]` vs the seed (scalar), then SIMD-compares `a[i]` vs `a[i-1]` over `[start+1, end)` via shifted loads —
`~Vector.Equals(curr, prevShifted)` is an all-ones mask per NOT-equal lane, `acc -= mask` accumulates +1 per
mismatch across four lane-accumulators — then a scalar tail; returns the count and the terminal `previous`
(`a[end-1]`, or the seed when empty). It reads ONLY `a[start..end-1]` (the seed replaces `a[start-1]`), so the
empty/OOB guards match the other helpers (OOB → `IndexOutOfRangeException` at the same element).
`TryEmitMatchedCountTransitions` lowers a matched `current := a[i]; if current != previous { count++ };
previous = current` to `(delta, last) = CountTransitionsInt32(a, i, bound, previous); count = count + delta;
previous = last; index = max(i, bound)` (ValueTuple `Item1`/`Item2` via `ldloca`/`ldfld`, reusing the P-minmax(c)
fields). The terminal `previous = last` restores the carried scalar to its scalar-loop exit value for any later use.

**Measured (BDN short job, M4, isolated worktree):** CountTransitions @4096 — C# 1119.8 ns → **N# 471.9 ns =
0.421× = 2.37× faster than C#** (was ~0.99×, scalar) → implied **~4.54× → ~1.9× behind native**; @64 — 16.91 →
**10.93 ns = 0.646×** → ~2.45× → ~1.6× behind native. **With this, EVERY vectorizable kernel is Rust-class
(within ~2× of native):** checksum ~2×, count-ascii ~1.6×, score-frame ~2×, min-max-delta ~1.77×,
count-transitions ~1.9×, parse-eight-digits already faster than C#. Only rolling-hash remains (~1.5×, the
latency-bound floor — a carried multiply-mask dependency, not vectorizable). Phase P's auto-vectorization program
is essentially complete on the systems kernels.

Tests: 46 count-transitions tests — 17 detector accept/reject (for/while, carry/distinctness near-misses); parity
scalar≡vectorized for the COUNT and the restored terminal `previous` across lengths incl. SIMD tails (for+while);
lowers to ONE helper call; non-int[] falls back (0 calls); OOB → `IndexOutOfRangeException`; empty/negative → seed;
direct helper edge cases (all-equal→0, all-different→N, runs, int extremes, seed ==/!= a[start], partial ranges).
Adversarially verified; full gate green. Developed in the `systems-language-perf` worktree.

## 2026-06-07 — Rust-perf P-minmax(c): FUSED single-pass MinMaxInt32 — min-max-delta to Rust-class (~1.8× native)

The fused follow-up to P-minmax(b). (b) lowered min-max-delta to TWO passes (`MinInt32` then `MaxInt32`, each
re-scanning the array); (c) adds `SimdReductions.MinMaxInt32(array, start, end, seedMin, seedMax) -> (int Min,
int Max)` that loads each `Vector<int>` ONCE and applies both `Vector.Min` and `Vector.Max`, and routes the
canonical `[1 min, 1 max]` body to it. `TryGetMinMaxPair` (in `ILCompiler.Vectorization.cs`) detects exactly one
min + one max reduction; the emitter calls the fused helper (seedMin = the min accumulator, seedMax = the max
accumulator), stores the `ValueTuple<int,int>` to a local, and reads `Item1 -> min` / `Item2 -> max` via
`ldloca + ldfld`. min-only/max-only (and any homogeneous pair) keep the per-reduction `MinInt32`/`MaxInt32` path.
The fused helper reuses the same empty/negative-range early-out, in-bounds guard, and scalar-tail OOB semantics.

**Measured — rigorous back-to-back on the SAME machine (worktree `systems-language-perf`, isolated tree; BDN
short job, MinMaxDelta):**

| size | two-pass (b) | fused (c) | fused speedup | fused vs best-native |
|---|---|---|---|---|
| 4096 | 453.2 ns (0.296× C#) | **262.5 ns (0.168× = 5.94× faster than C#)** | **1.73×** | ~10.5× → **~1.77× behind** |
| 64 | 30.6 ns (1.303× — *slower* than C#) | **18.4 ns (0.768×)** | **1.67×** | — |

The fused path is **1.73× faster than two-pass** at 4096 — far beyond the ~10–15% I'd predicted from memory
traffic alone. The extra win is the eliminated second call/loop boundary (visible at size 64, where two-pass was
actually *slower* than C#, 1.303×, and fused is 0.768×). This puts min-max-delta at **~1.77× behind native —
BELOW the ~2× DONE bar, matching checksum-sum and count-ascii (Rust-class).** Decision rule honored: I measured
fused vs two-pass before keeping it (would have dropped it if ≈ two-pass).

Tests: 69 MinMax tests (the codegen `[1 min, 1 max]` now lowers to ONE fused call — `MinMax_LowersToOneFusedHelperCall`;
end-to-end scalar≡vectorized parity through the fused path; direct `MinMaxInt32` helper edge cases proving fused ≡
the two separate helpers ≡ the scalar fold across seeds/partial ranges/extremes/all-equal/empty). Developed in an
isolated worktree (`systems-language-perf` off `ca9ba88e`) after a concurrent session made the shared
`systems-language` tree non-compiling. Adversarially verified; full gate green.

## 2026-06-07 — Rust-perf P-minmax: lane-wise SIMD min/max reduction (min-max-delta) — the 10.5× kernel

The codegen that vectorizes the min-max-delta kernel — the single LARGEST remaining native gap (10.5× behind
best-native at size 4096 when N# tied C#). min-max-delta is two min/max reductions in one loop body
(per element `value := a[i]`, then `if value < min { min = value }` and `if value > max { max = value }`). Signed integer min and max
are associative AND commutative (a total order), so lane-wise `Vector.Min`/`Vector.Max` across SIMD lanes and
four accumulators is value-identical to the sequential scalar fold — the same class of safe rewrite as P1's
integer sum, just a different operator and the conditional-assignment shape.

`SimdReductions.MinInt32(array, start, end, seed)` / `MaxInt32(...)` seed all four `Vector<int>` accumulators
with the pre-loop accumulator value broadcast, run `Vector.Min`/`Vector.Max` over the SIMD body, fold the four
accumulators + the lanes horizontally (no `Vector.Min`-reduce intrinsic), then a scalar tail. They reuse P1's
guards verbatim: empty/negative range early-out (`end <= start`, which also avoids the P1(d) `end - step`
int.MinValue overflow); SIMD only over a provably in-bounds range; the scalar tail reproduces
`IndexOutOfRangeException` at the same element (not the Vector ctor's `ArgumentOutOfRangeException`).
`ILCompiler.TryEmitMatchedMinMaxReduction` (hooked into `EmitWhile`/`EmitFor` after the reduction + range-count
hooks) lowers a matched loop to `min = MinInt32(a, i, bound, min); max = MaxInt32(a, i, bound, max);
i = max(i, bound)` — one helper call per reduction, the bound evaluated once, the index unchanged between calls
so both helpers see the same start. The detector (`MinMaxReductionLoopShape`, P-minmax(a)) matches while/for,
temp/inlined subject, one OR two reductions, and reversed `min > value` operand order, with full
distinct-name/no-aliasing/single-write-per-accumulator safety.

**Measured (2026-06-07, Apple M4, .NET 10, BenchmarkDotNet `SystemsHotPathBenchmarks`, N# vectorized vs the C#
scalar baseline; short job):** MinMaxDelta size 4096 — C# 1535.3 ns → **N# 468.0 ns = 0.305× (3.28× faster)**;
size 64 — C# 23.55 ns → **N# 16.79 ns = 0.713× (1.40× faster)**. Was ~1.0× (tied, scalar) on 2026-06-06.
Implied vs best-native (applying the measured speedup to the prior M4 native numbers): **10.5× → ~3.2× behind**
(4096), 5.70× → ~4.1× (64). The same-run cross-check confirms surgical scope: checksum 0.226×, count-ascii
0.249×, score-frame 0.228× hold their P1/P2 wins, and every non-matching kernel (count-transitions ~0.99×,
rolling-hash ~1.0×, scan-tag, parse-eight-digits) is unchanged — the min/max codegen fires only on min-max-delta.
The 3.28× (vs checksum's ~4.4×) reflects the TWO-PASS cost (MinInt32 + MaxInt32 each re-scan the array); a fused
single-pass `MinMaxInt32` (slice c) is the obvious follow-up to push toward checksum's ratio (~2.4× behind native).

Tests (236 Simd-category total): the min-max-delta benchmark shape (for/while, temp/inlined), min-only/max-only,
scalar≡vectorized across lengths incl. SIMD tails and signed extremes (int.MinValue/MaxValue mid-array);
fires-only-when-enabled (2 helper calls for min+max, 1 for min-only); non-int[] array falls back (0 calls) and
stays correct; OOB bound → `IndexOutOfRangeException`; empty/negative/int.MinValue bound → seed; plus direct
helper edge cases on the SIMD path (all-equal, seed=extremum, partial ranges, empty/negative). The
adversarial-verify workflow (3 lenses → skeptic-per-finding → judge) raised 7 candidates; I adjudicated all as
non-divergent. The one the judge flagged "real" (a cached `array.Length` bound diverging under "concurrent array
resize") rests on an impossible premise — .NET `int[]` is fixed-length, `array.Length` is immutable for an
instance (`Array.Resize` allocates a new array), the function holds the array by a fixed local reference for the
call, and the cached-bound pattern is identical to the already-shipped/reviewed SumInt32 (P1) and CountInRangeInt32
(P2) emitters; the detector also rejects every genuinely-mutable bound, and the `a.Length`-bound parity test passes.
Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate green; no IL-shape test fallout (the min/max shape is
specific, like the range count).

## 2026-06-07 — Rust-perf P2(b): masked-SIMD range-predicate count (count-ascii) — the 5.7–6.3× kernel

The codegen that vectorizes the count-ascii kernel. `SimdReductions.CountInRangeInt32(array, start, end, lo, hi)`
counts in-range elements via packed compares — `Vector.GreaterThanOrEqual(v, lo) & Vector.LessThanOrEqual(v, hi)`
gives an all-ones lane mask per in-range element; `acc -= mask` accumulates +1 per match across four independent
lane-accumulators; then `Vector.Sum` + a scalar tail. It reuses P1's empty/OOB/extreme-bound guards verbatim
(`end <= start` early-out; SIMD only over a provably in-bounds range; the scalar tail throws
`IndexOutOfRangeException` at the same element as the scalar loop — not the Vector ctor's
`ArgumentOutOfRangeException`). `ILCompiler.TryEmitMatchedRangeCount` (hooked into `EmitWhile` + `EmitFor`
after the reduction hook) lowers a matched `if a[i] >= lo && a[i] <= hi { count++ }` loop body (optionally
preceded by `value := a[i]`) to `count = count + CountInRangeInt32(a, i, bound, lo, hi)` then `i = max(i, bound)`.
Fires for an `int[]` array, int
counter/index, int side-effect-free bound, and int side-effect-free `lo`/`hi` (evaluated ONCE — the masked
compare must match the scalar `int a[i]` comparison exactly, so non-int `lo`/`hi` or a non-`int[]` array fall
back to scalar). Counts are order-independent, so the result is value-identical to the scalar loop.

Tests (162 Simd-category total): count-ascii while/for forms, temp + inlined subject; scalar≡vectorized across
lengths incl. SIMD tails and inclusive boundaries (values exactly `== lo`/`== hi`); fires-only-when-enabled;
non-int `lo`/`hi` and non-`int[]` array fall back (0 helper calls) and stay correct; OOB bound →
`IndexOutOfRangeException`; empty/negative/`int.MinValue` bound → 0; plus direct helper edge cases on the SIMD
path (`lo>hi`→0, `lo==hi`, negative ranges, `int.MinValue`/`int.MaxValue` boundaries). The adversarial-verify
workflow (3 lenses) found NO codegen divergence: signed compare semantics, the mask arithmetic, no accumulator
overflow (count ≤ length ≤ `int.MaxValue`; per-lane and intermediate sums ≤ total), once-evaluation of the
side-effect-free `lo`/`hi`, and the terminal index are all correct. Full `VSCODE_TESTS=skip ./scripts/test-all.sh
--commit` gate green; no IL-shape test fallout (the range-count shape is specific, unlike the broad for-form).

## 2026-06-07 — Rust-perf P2(a): range-predicate count detector (count-ascii; no codegen change)

First sub-slice of the count-ascii vectorization (the 5.7–6.3× Rust gap). `RangePredicateCountShape.TryMatch`
recognizes the canonical range-predicate count loop — `for`/`while i < n { [value := a[i];] if a[i] >= lo &&
a[i] <= hi { count++ } }` (inclusive range; while- and for-forms; temp or inlined subject; counter increment
`count = count + 1`/`+= 1`/`++`) — purely structurally, enforcing every safety condition that makes the future
masked-SIMD rewrite (P2(b)) value-preserving: loop-invariant side-effect-free `lo`/`hi` (not index/temp/counter,
so evaluating them once in the helper matches per-iteration evaluation), no `else`, a single unit-counter-increment
body, the array indexed only by the loop var, and distinct counter/array/index/temp names. 19 tests pin 6 accepted
shapes + 13 near-miss rejections (else branch, exclusive `>`/`<`, `||`, non-unit increment, extra statements,
wrong index, two arrays, loop-variant bound, subject mismatch). **No IL emission yet → zero regression risk** —
this is the analytical gate the masked-count emission (P2(b)) will hook into `EmitWhile`/`EmitFor`. The masked
helper design is validated (`Vector.GreaterThanOrEqual & Vector.LessThanOrEqual` → an all-ones mask per in-range
lane; `acc -= mask`; `Vector.Sum`), and will reuse P1's empty/OOB/overflow-guarded helper structure. **Next:
P2(b)** — the masked-count helper (`SimdReductions.CountInRangeInt32`) + the emitter hook + parity tests.

## 2026-06-07 — Rust-perf P1(f): vectorize the FOR-form — the win now fires where it is actually measured

**Discovery (high-leverage):** the reduction auto-vectorizer (P1 a–e) hooked ONLY `EmitWhile`, but the systems
benchmarks (`SystemsHotPathBenchmarks`: checksum, countAscii) and idiomatic N# use the **`for`-form**.
Empirically confirmed via a probe: a for-form reduction emitted **0** SIMD helper calls while the equivalent
while-form emitted **1** — so the measured "~8.8× → ~2×" checksum win was **not actually reaching the benchmark
or any for-loop code**. `EmitFor` emits its own loop and never called `TryEmitVectorizedReduction`; there is no
for→while desugaring. P1(f) closes that gap so the existing, proven SIMD machinery finally fires where it counts
(and unblocks P2 — count-ascii is for-form).

`ReductionLoopShape` now also matches the for-form `for i := start; i < bound; i++ { acc = acc + a[i] }` — the
increment is the ITERATOR (`i++`/`++i`/`i = i + 1`/`i += 1`) and the body is the single accumulator-update
statement (braced or braceless). `EmitFor` emits the initializer (so the index holds its start value), then the
SAME shared core (`TryEmitMatchedReduction`) used by the while-form lowers the loop to the SIMD helper call plus
the terminal `index = max(index, bound)` — which equals a counted for-loop's exit value `max(start, n)` for all
start/n. The detector + emitter were refactored to share all matching/emission logic between the two forms with
**no while-form behavior change** (verified: the while-body increment is still matched as an `AssignmentExpression`,
so an `i++` statement cannot slip into the while-form).

35 new tests (121 Simd-category total): for-form detector accept (`i++`/`++i`/`i=i+1`/`i+=1`, `a.Length` bound,
non-zero start) + reject (stride≠1, `i--`, `a[i]*2`, two arrays, `a[j]`, `<=`, extra body statement); end-to-end
for-form scalar≡vectorized across lengths incl. SIMD tails for int/long/uint/ulong (with uint/ulong wraparound);
non-zero-start `[start, n)` parity incl. empty ranges; for-form terminal index = `max(start, n)`; braceless body;
OOB bound → `IndexOutOfRangeException`. The read-only adversarial-verify workflow (3 lenses) returned **SAFE TO
SHIP — no for-form-specific divergence**: the only genuinely new surface (initializer emitted exactly once,
terminal index, single-statement body shape-matched-then-discarded) is correct, and the helper's overflow/OOB/
wrap fixes from P1(d) are shared by both forms. Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate green
(this is the higher-blast-radius change — it now vectorizes every matching for-loop in the dogfood compiler,
examples and templates; the gate compiles and runs all of them + IL verification).

## 2026-06-07 — Rust-perf P1(d): widen auto-vectorized reductions to long/uint/ulong (+ 2 correctness fixes)

Widened the counted-reduction auto-vectorization (P1 a–e, previously `int[]`-only) to the rest of the
associative-add integer family: `long[]`, `uint[]`, `ulong[]`. `NSharpLang.Runtime.SimdReductions` gains
`SumInt64`/`SumUInt32`/`SumUInt64` (the same unrolled 4-accumulator `Vector<T>` reduction); the emitter
(`ILCompiler.TryEmitVectorizedReduction`) now resolves the helper by the array element type and requires the
accumulator type to equal the element type. **float/double remain scalar by construction** — there is no FP
helper, because FP addition is not associative (reassociating across lanes/accumulators changes the result).
44 new tests pin scalar≡vectorized across lengths (incl. 0 and SIMD-tail non-multiples) for all three widths,
including deliberate uint/ulong wraparound (mod-2^32 / mod-2^64), plus "lowers to a helper call only when
enabled" and "float/double never vectorize."

The adversarial-verify workflow (4 lenses, read-only) — the self-host-loop.md review substitute now that Codex
is lifted — found **two real correctness divergences**, both pre-existing in the shipped `int` path and now
fixed for all four widths in the runtime helper (the bound is a runtime parameter, so the fix must live in the
helper, not the emitter):

1. **`int.MinValue` bound overflow (CRITICAL).** The helper computed the vector-loop limit as `end - step` in
   unchecked int arithmetic. For `end = int.MinValue` (a caller passing `n = int.MinValue`), `end - step` wraps
   to a large positive, so the SIMD loop ran and read out of bounds — while the scalar loop `while i < n`
   never runs (returns 0). Fixed with an `if (end <= start) return sum;` early-out (the empty/negative range is
   the scalar identity AND `end - step` is never reached for a hugely-negative `end`).
2. **Out-of-bounds exception-type divergence.** When `n > array.Length` (or a negative start index), the scalar
   loop throws `IndexOutOfRangeException` at `a[i]`, but `new Vector<T>(array, i)` throws a *different*,
   observable type — `ArgumentOutOfRangeException` (verified empirically on .NET 10). Fixed by taking the SIMD
   fast path only over a provably in-bounds range (`start >= 0 && end <= array.Length`); otherwise the scalar
   tail reproduces the exact `IndexOutOfRangeException` at the same element. Regression tests cover
   `n = int.MinValue/+1/+8/-1/-100` (→ 0, no OOB read) and `n > length` (→ `IndexOutOfRangeException`, not
   `ArgumentOutOfRangeException`) for int/long/uint/ulong.

Also added a defensive `_overflowCheckingEnabled` guard: a `checked` reduction would emit `add.ovf` (throws on
overflow) in the scalar path, which the wrapping helper would not reproduce — so vectorization is skipped in a
checked context. (Currently unreachable: N# `checked` is expression-only and `while` is a statement, so a while
body is never emitted under overflow checking — but the guard pins the invariant against a future `checked`
block.) The full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate is green (unit suite incl. the 81
Simd-category tests + Systems BenchmarkDotNet zero-tolerance gate + IL verification + dogfood/examples/templates).

## 2026-06-07 — Rust-perf P1(e): vectorization ON by default — the perf win is now ACTIVE

Flipped reduction auto-vectorization ON by default (env `NSHARP_VECTORIZE_REDUCTIONS=0` opts out). The N#
systems compiler now auto-vectorizes `int[]` counted reductions for every program — the worst-case
checksum-sum kernel goes from ~8.8× behind C/Rust to ~2× (the helper's measured 4.5× over scalar). Never-
regress proven broadly: the FULL 3466-test unit suite passes with vectorization active (no test changed
behavior), and the gate (dogfood recompile + all examples + templates + IL-verification + the SystemsFastGate
benchmark) is green. This is the first Rust-perf win shipped active, not just built. Design constraint for the
next widening (P1(d)): integer types only (long/uint/ulong — wrapping add is associative); float/double
reductions must stay scalar (FP reassociation changes results).

## 2026-06-07 — Rust-perf P1(b): counted-reduction auto-vectorization codegen (off by default)

The codegen that realizes the measured ~4.5× checksum-sum win. When `NSHARP_VECTORIZE_REDUCTIONS` (or a
thread-local test override) is set, `ILCompiler.TryEmitVectorizedReduction` (hooked into `EmitWhile`) lowers a
matched `int[]` counted reduction to `acc = acc + NSharpLang.Runtime.SimdReductions.SumInt32(array, index,
bound); index = max(index, bound)` — i.e. a call to the unrolled 4-accumulator `Vector<int>` reduction in
plain testable C#, instead of hand-emitting vector IL (much safer; the emitted IL is just load-args + call +
add + store + a max). Off by default + thread-local so it can't affect other tests or production.

27 tests: run(vectorized) == run(scalar) across lengths incl. 0 and non-multiples of the SIMD width (scalar
tail), the post-loop index left at the scalar terminal value `max(index,bound)` (incl. empty/negative bounds),
the array.Length path, and the optimization-fires shape check (scalar element-load loop replaced by a call).

Adversarial review (4 agents) caught one real divergence and it was fixed: the bound was evaluated multiple
times and `.Count`/custom `.Length` bounds could be side-effecting property getters, so a vectorized loop
would observe a different evaluation count than the scalar loop. Now bounds are restricted to provably
side-effect-free int (int local/param read, int literal, or `.Length` on an ARRAY = the pure ldlen intrinsic)
and evaluated exactly once; anything else falls back to the scalar loop. Next: (d) widen element types, then
(e) the end-to-end SystemsFastGate bench + default-on once never-regress is proven.

## 2026-06-07 — Rust-perf P1(a): counted-reduction loop detector (safe, no codegen change)

First sub-slice of the auto-vectorization codegen (the measured ~4.5× checksum-sum win). `ReductionLoopShape
.TryMatch` recognizes the systems `while`-form counted reduction — `while index < bound { acc = acc +
array[index]; index = index + 1 }` (and the `+=` forms, with bound = identifier / int literal / `x.Length`/
`x.Count`) — purely structurally, enforcing every safety condition that makes the SIMD rewrite
value-preserving (unit stride, single array indexed only by the loop var, distinct acc/array/index, the fixed
two-statement body so no break/continue/other-write, accumulator-update-before-increment). 11 tests pin 3
accepted shapes + 8 near-miss rejections. No IL emission yet → zero regression risk; this is the analytical
gate the emission (P1(b)) will hook into EmitWhile. Scoped by workflow w8urlgage (EmitWhile hook, Vector<int>
Reflection.Emit feasibility via RuntimeCalls.cs patterns, associativity of int wrapping add).

## 2026-06-06 — Columnar pipeline STAGE 3: expression type inference (no C# AST) + 2 binder gaps surfaced

Third downstream stage: infer the canonical type of every expression in a function body, walking the columnar
tables directly. `Columnar.ColumnarTypeInferer` + the shared `ColumnarTypeLattice` (numeric promotion,
operator results, literal/element/cast/new types) over the columnar + symbol tables; `:=` locals take their
initializer's inferred type, calls take the function-signature return type (two-pass, forward refs resolve),
BCL forms (member access, non-N# calls) yield `External` (the typed host boundary a later stage fills).
`NSharpCompilerDogfoodAdapter.TryInferTopLevelFunctionTypes` orchestrates it; fallback-safe.
`ColumnarTypes_Inference_MatchesAstWalk` verifies the inferer implements the spec identically to the C#-AST
walk on every dogfood file + hand corpora.

**Adversarial review (3 lenses vs the REAL binder) surfaced two genuine C# binder ECMA gaps** — the binder
does not concretely type bitwise binary ops (`& | ^ << >>` → Unknown) nor numeric-promote unary `-`/`~`
(Analyzer.cs §12.4 gaps); both appear in the corpus (e.g. `BindingLookup.nl` `(lower+upper) >> 1`). It also
correctly flagged that the parity oracle was self-referential. Resolution (behavior-preserving self-host):
`ColumnarTypeLattice` was **aligned to the binder's actual behavior** (bitwise → External/deferred, unary as
the binder does), so the columnar inferer is a faithful replacement rather than silently diverging. The
binder's ECMA gaps are logged as a **reconciliation roadmap item** (fix the binder + promote the lattice, or
keep matching). The DEFINITIVE binder/output parity is verified end-to-end at stages 4-5 (IL that runs
identically) — the right place for it, since intermediate type differences only matter if they change output.

## 2026-06-06 — Rust-perf: auto-vectorization CEILING measured — unrolled Vector<int> = 4.5x over scalar

The first move on the Rust performance bar (after stages 1–2): quantify the prize before any codegen change.
`benchmarks/VectorReductionCeilingBenchmarks.cs` measures `System.Numerics.Vector<int>` reductions vs the
scalar reduction the N# codegen emits today, under the same RyuJIT (Apple M4 / .NET 10), ratios vs scalar:

- single-accumulator `Vector<int>`: **2.08×** faster (N=4096), 3.8× (N=64)
- **4 accumulators (unrolled): 4.5×** faster (N=4096), 5.0× (N=64)

checksum-sum is 8.8× behind C/Rust today; unrolled-vectorized codegen would close it to **≈2× behind native**
(8.8/4.5) — the worst-case kernel becomes top-tier for a CLR language. UNROLLING is the key (a single
accumulator is add-latency-bound at ~2×; four independent accumulators hide the latency, the LLVM trick).
Full numbers + the concrete codegen plan in [`systems-vs-native.md`](systems-vs-native.md) item A. The
codegen itself (recognize the `while`-form counted reduction + emit unrolled `Vector<int>` IL + parity/
benchmark gate) is justified and is the next major, focused Rust-perf effort — large + correctness-critical,
not folded into a slice.

## 2026-06-06 — Columnar pipeline STAGE 2: lexical name resolution over columnar tables (no C# AST)

The second downstream stage: resolve every bare identifier in a function body to its binding, walking the
columnar statement/expression node tables directly — no C# AST.

- `Columnar.ColumnarNameResolver` performs scoped pre-order resolution over the columnar tables: parameters as
  the base scope, `:=` locals entering at their declaration point, Block/While/If bodies introducing nested
  scopes, all top-level functions pre-declared (forward references resolve). Each bare identifier (kind 6)
  classifies as Parameter / Local / Function / NotInScope (the last = BCL/types, a later stage's concern).
  Member names (kind-8 value span) and New/Cast TYPE subtrees (child[0]) are not scope lookups.
- `NSharpCompilerDogfoodAdapter.TryResolveTopLevelFunctionNames` orchestrates it (tokenizer + declarations
  kernel for the pre-declared function set + per-function signature kernel for parameters + statement kernel
  for the body), fallback-safe.
- `ColumnarNames_Resolution_MatchesAstWalk` asserts the columnar resolution is IDENTICAL to the same algorithm
  walking the C# AST — every identifier, same classification, same pre-order — on **every dogfood file** plus
  hand-built corpora (forward refs, while/if scopes, member access, BCL receivers, cast/new). The terrain was
  mapped by a parallel understanding sweep (corpus binding patterns + the C# binder's resolution order +
  the columnar traversal spec); the resolver then passed a 3-lens adversarial review (scoping, traversal
  completeness, mirror fidelity) → clean.

Perf is covered by slice 27 (resolution = the same cache-friendly columnar traversal, ~1.6× faster than the
AST walk, plus O(1) scope-set lookups). Stage 3 (type checking) builds on this + the stage-1 symbol model.

## 2026-06-06 — Columnar pipeline STAGE 1: declared-symbol model (the first downstream stage, no C# AST)

Decision "go big" (2026-06-06): commit to the columnar self-host pipeline (architecture + staged plan in
[`columnar-pipeline.md`](columnar-pipeline.md)). This is stage 1 — the declared-symbol model that name
resolution queries, built DIRECTLY from the columnar declaration + signature tables with NO C# AST
materialization.

- `NSharpCompilerDogfoodAdapter.TryBuildTopLevelFunctionSymbols(source)` → `List<ColumnarFunctionSymbol>`
  (name, modifiers, canonical parameter + return type signatures). It runs the dogfood tokenizer + the
  declarations kernel (kinds + modifier flags) + the per-function signature kernel, and canonicalizes each
  parameter/return type subtree to a string via `ColumnarTypeCanon` — straight off the columnar type tables,
  never building a `FunctionDeclaration`/`TypeReference` object. Conservative + fallback-safe (false on any
  non-function decl or kernel refusal).
- `Columnar.ColumnarFunctionSymbol` (new) holds the symbol; `CanonicalType(TypeReference)` is the matching C#
  AST canon used only by the parity baseline.
- `ColumnarSymbols_TopLevelFunctions_MatchProductionBinderModel` asserts the columnar symbol model matches the
  C# AST-derived model (name + modifiers + canonical signatures) on **every dogfood file** plus hand-built
  corpora (arrays, generics, nullable, casts). First proof that the columnar IR feeds a real **semantic
  model**, not just round-trips through the parser.

This is the foundation stage 2 (name resolution → symbol IDs) builds on. Per the pipeline design rules, the
never-slower benchmark + production routing (with C# fallback) come with stage 2's integration; the front-end
and downstream-traversal perf are already established (slices 26–27: 2.4× faster parse, ~1.6× faster passes,
no AST allocation). Design rule reaffirmed: resolve names to symbol IDs once — the symbol model is the place
that interning will live.

## 2026-06-06 — Slice 27: downstream-pass spike — the columnar win COMPOUNDS past the parser

Validates the columnar-pipeline thesis on the NEXT stage after parsing. `ColumnarSemanticPassBenchmarks`
takes an already-parsed file and runs the SAME semantic pass two ways — collect the distinct identifier names
referenced in every function body (a full traversal with representative per-node work) — on the C# object-graph
AST vs the flat columnar int[] node tables. Parsing is done in Setup, so this isolates the PASS. Apple M4 /
.NET 10, LargeGenerated (40 funcs), ratios vs the C# AST pass:

| Pass | Time | Alloc |
|---|---|---|
| C# AST walk (recursive visitor) | 1.00× (11.2 µs) | 1.00× (368 B) |
| Columnar scan, naive `Substring` per ref | **0.62× (1.6× faster)** | 53× (19.6 KB) |
| Columnar scan, **interned names** | **0.64× (1.56× faster)** | 2.74× (1.0 KB) |

**Findings:**
- **Columnar traversal is ~1.6× faster** than walking the AST — sequential int[] scan vs virtual-dispatch
  pointer-chasing. The traversal advantage is real and holds past the parser.
- **Name handling matters:** the naive columnar scan re-materializes a string per identifier *occurrence*
  (53× alloc). Done right — intern each distinct name once (a span-keyed lookup; in a real pipeline, integer
  symbol IDs) — allocation collapses to ~1 KB. This is standard fast-compiler practice, not a columnar flaw.
- **The C# pass's tiny 368 B is an illusion:** it reuses strings already allocated in the **662 KB AST built
  at parse time** (slice 26). The columnar path never builds that AST. So end-to-end (parse + N passes) the
  columnar pipeline wins decisively and the gap **compounds with each pass** — every AST pass re-walks the
  600 KB+ graph; every columnar pass scans tiny, cache-resident int[] tables.

**Verdict:** the 2.4×-faster front-end (slice 26) is not a one-off — the advantage carries into downstream
semantic passes (~1.6× faster, no AST allocation). This confirms the columnar self-host pipeline (port the
binder/analyzer to consume the columnar tables directly, with interning/symbol IDs) is the path that BOTH
eliminates the C# reliance AND captures the speed. The naive-vs-interned result also pins the one design
rule: never re-materialize names per access — resolve to symbol IDs once.

## 2026-06-06 — Slice 26: routing-cost DECOMPOSITION — the front-end is 2.4x FASTER; the tax is materialization, not marshaling

Slice 25 showed routing is ~4-5x slower end-to-end, but lumped the causes together. This slice decomposes the
cost with two more `CompilationUnitRoutingBenchmarks` variants (columnar-parse-only with fresh per-function
tables, and the same with POOLED tables), isolating each tax. Apple M4 / .NET 10.0.5, LargeGenerated (40
funcs), ratios vs the C# parser (ratios are stable; absolute µs drift with machine temperature):

| Variant | Time | Alloc |
|---|---|---|
| **Columnar front-end, POOLED tables, no materialize** | **0.41× (2.4× FASTER)** | 1.88× |
| Columnar front-end, fresh per-function tables, no materialize | 3.65× slower | 16.95× |
| Full routing (fresh tables + materialize → C# AST) | 5.52× slower | 18.5× |

On a small file the pooled front-end is **0.39× time (2.6× faster) and 0.51× allocation (HALF of C#)**.

**The regression is NOT a marshaling/boundary problem.** The delegate boundary is crossed identically in the
pooled variant, which is 2.4× *faster* — so the C#↔N# boundary is negligible. The 4-5x came from two
separable taxes:

1. **Table over-allocation (fixable artifact):** pooled → fresh is 0.41× → 3.65× and 1.88× → 16.95× alloc.
   The naive orchestrator (and `TryParseCompilationUnit`) allocate ~19 int[] tables sized to the *whole file*
   *per function*, i.e. O(funcs·N). Pooling/right-sizing the buffers removes it entirely. Not fundamental.
2. **Materialization to the C# AST (the real, structural tax):** no-materialize → materialize adds the rest.
   This is the cost of rebuilding the C# object-graph AST (`ColumnarAstMaterializer`) so the *C# binder/
   analyzer/codegen* can consume it.

**Conclusion — and the answer to "how do we eliminate C#":** the N# parser front-end is genuinely **2.4×
faster than C# and lower-allocation** when it is NOT forced back into the C# AST. Materialization exists ONLY
because the downstream stages are still C# and consume the C# `CompilationUnit`/`Statement`/`Expression`
records. So **"eliminate the C# reliance" and "capture the speed win" are the same goal**: port the binder/
analyzer (and eventually codegen) to N# consuming the columnar tables directly — no materialization, no C#
AST, no boundary. Materialization is a *symptom of the half-ported state* (N# parser feeding a C# back end),
not an integration bug to optimize. The path is a columnar semantic pipeline, built incrementally downward
from the (now correctness-complete, 2.4×-faster) parser, with pooled tables. Next concrete step: a contained
spike — one semantic pass (declaration/symbol collection) reading the columnar tables directly, benchmarked
vs the C# AST-based pass — to confirm the win compounds past the parser before committing to the full port.

## 2026-06-06 — Slice 25: END-TO-END routing benchmark — materialization erases the kernel's win (never-slower FAILS)

The never-slower gate for flipping parser routing on. `CompilationUnitRoutingBenchmarks` measures the full
**source → `CompilationUnit`** path both ways: the C# `Parser` (Lexer + ParseCompilationUnit) vs the N#
routing path (dogfood tokenizer + declarations/signature/statement kernels + `ColumnarAstMaterializer`).
Apple M4, .NET 10.0.5:

| Corpus | C# parser | N# routing | Time | Alloc |
|---|---|---|---|---|
| Representative (~2 funcs) | 6.28 µs / 21.95 KB | 5.12 µs / 61.58 KB | **0.82× (faster)** | **2.81× more** |
| LargeGenerated (40 funcs) | 214.6 µs / 662 KB | 934.9 µs / 12.2 MB | **4.36× slower** | **18.5× more** |

**Verdict: routing stays OFF.** On realistic input the routed path is **4.36× slower and allocates 18.5×
more**. This is *fundamental*, not a tuning gap:

1. **Materialization re-creates the C# object-graph AST** — the routed path allocates the *same* records the
   C# parser does (via `ColumnarAstMaterializer`), so routed allocation is **C#'s allocation + the columnar
   int[] tables**, i.e. strictly greater. Materializing to the C# AST can never beat the C# parser on memory.
2. **Per-function table over-allocation** — each function allocates ~11 int[] arrays sized to the whole-file
   token count, so a 40-function file allocates O(40·N) table memory vs the parser's O(N).
3. Plus re-tokenization and delegate-boundary overhead.

The statement kernel's **5–6× raw-parse win (slice 21) does NOT survive materialization.** The kernel is fast
because it writes compact int[] tables instead of an object graph; materializing those tables back into the
object graph throws that advantage away.

**Implication for the endgame:** the self-host *speed* win is **not** "route the parser + materialize to C#
records" — that path regresses perf. The real win requires the binder/analyzer/codegen to **consume the
columnar tables directly (zero materialization)**, with pooled, right-sized tables — a large architectural
bet (a columnar semantic pipeline), not parser routing. The slice-24 routing path remains valuable as the
**correctness oracle** (it proves the N# parser parses 100% of its own source identically to C#) and as the
front-end for that future columnar pipeline — but it must not be the production speed path while it
materializes. See also [`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md).

## 2026-06-06 — Slice 24: PRODUCTION ROUTING + cast expressions — the N# front-end parses 100% of its own systems source

The N# parser front-end is now **wired into the production parse path** and parses the entire dogfood
compiler-service corpus (32 `CompilerServices/*.nl` files) **byte-for-byte identically** to the C# parser.

- **`NSharpCompilerDogfoodAdapter.TryParseCompilationUnit`** (new): a whole-file orchestrator that runs the
  dogfood tokenizer + declarations kernel (imports/package/decl kinds) + per-function signature & statement
  kernels + `ColumnarAstMaterializer`, assembling a production `CompilationUnit`. It is conservative and
  **fallback-safe**: any non-function top-level declaration, package declaration, or kernel refusal makes it
  return `false` so the C# parser handles the file.
- **`Parser.ParseCompilationUnit()` routes through it** when `NSharpCompilerDogfoodAdapter
  .ParserFrontEndRoutingEnabled` is set (env var `NSHARP_PARSER_FRONTEND=1`). **Off by default**, so
  production behavior is unchanged until the end-to-end benchmark (next) justifies flipping it on.
- **Cast expressions (kind 16)** were the *only* gap to full-corpus parity. Building the orchestrator + a
  whole-corpus parity test surfaced that the expression kernel silently mis-parsed C-style casts `(int)x` as
  `(int)` (parenthesized) + a stray statement — a real refusal-incompleteness bug. Added faithful cast
  detection to `ParserExpressions.nl` mirroring `Parser.cs` `IsCastExpression`: speculatively parse a type
  after `(`, and if it is followed by `)` and an expression-start token (`IsExpressionStartKind`, mirroring
  C#'s `IsExpressionStart`), emit a `CastExpression`; otherwise roll back and parse as parenthesized. With
  casts, the corpus went from 29/32 to **32/32 files routed, 0 divergent**.
- **Safety:** `Router_CompilationUnit_MatchesProductionParserAst` asserts every dogfood file routes AND
  matches the C# parser structurally (the corpus is the safety proof — a silently-wrong tree fails here).
  `Router_RefusesUnsupportedForms` proves the front-end declines class/struct/enum/package/`let`/`foreach`
  (so "kernel didn't refuse" + whole-file acceptance is a trustworthy routing signal).

This is the self-host **parser** milestone: the N# parser is genuinely USED in production (env-gated) and is
correct on 100% of the compiler's own systems source. Next: end-to-end benchmark (routed tokenize+kernels
+materialize vs C# Lexer+Parser) — the never-slower gate before flipping the default on — then expand the
supported declaration forms (types/classes) and begin shrinking the C# parser surface.

## 2026-06-06 — Slice 23: whole-function-declaration materialization (the routing unit)

Composes the fnsig kernel (name + parameter names/types + return type) and the statement kernel (body) and
materializes both into a C# `FunctionDeclaration` via `ColumnarAstMaterializer`. Verified
(`Materializer_FunctionDeclaration_MatchesProductionParserAst`) on every dogfood function within the
supported forms (>30 real functions): name, each parameter's name + type tree, return type tree, and the
whole body all match the production parser's `FunctionDeclaration` shape. So the full pipeline
**tokenize → parse signature + body (N# kernels) → materialize (C#) → FunctionDeclaration** now round-trips
real compiler functions. This is the declaration-level unit the whole-file `CompilationUnit` materialization
and the production routing are built from. Next: assemble imports + declarations → `CompilationUnit`, then
wire it into an actual production parse path (behind an engine flag, C# fallback for unsupported forms) so
the N# front-end is demonstrably USED in production — then drive coverage up and shrink the C# parser/adapter
surface.

## 2026-06-06 — Slice 22: MATERIALIZATION — columnar front-end → production C# AST (the routing bridge)

The first real step beyond "verified-but-unrouted": `ColumnarAstMaterializer`
(src/NSharpLang.Compiler/ColumnarAstMaterializer.cs) turns the N# front-end's columnar node table (the flat
int[] forest the kernels emit) into the production C# AST records (`Expression`/`Statement`/`TypeReference`)
the rest of the compiler consumes. This is the bridge between the fast columnar parser output and a usable
`CompilationUnit` — the prerequisite for routing the N# front-end into production and deleting the C#
`Parser`. Dispatches by node kind, disambiguating shared type/expr kind ranges positionally (e.g. a New
node's child[0] is a type subtree, the rest are argument expressions), and derives Line/Column from byte
spans via a line map.

Verified by `Materializer_Expression_MatchesProductionParserAst`: each corpus expression's columnar output
is materialized and **structurally identical** (positions aside — operator nodes key off different tokens)
to the C# parser's `Expression`; AND every dogfood function body within the supported forms (>30 real bodies)
is materialized into a C# `BlockStatement` matching the production parser's `FunctionDeclaration.Body`. Found
+ matched a real fact: the C# parser keeps char/string `Value` as the verbatim source token (quotes
included, no unescape), so the materializer uses the raw span.

This is the honest answer to "is the bridge eliminated?" advancing from "no, nothing" toward "the bridge now
EXISTS and round-trips real code." Remaining to actually delete `Parser.cs`: (1) whole-FILE materialization
(imports + function declarations w/ signatures + bodies → `CompilationUnit`), (2) full language-form parity
(handle arbitrary N#, not just the supported subset), (3) route the production parse path through
tokenize→parse→materialize and delete/shrink the C# parser + `*DogfoodAdapter` surface.

## 2026-06-06 — Systems N# vs Rust vs C head-to-head + direction decision

Ran the `systems-nsharp-vs-rust-c` workflow (5 phases, adversarial fairness). Full report:
[`systems-vs-native.md`](systems-vs-native.md); reproducible harness: `benchmarks/native-comparison/`;
deferred-bet backlog: [`systems-vs-native.md`](systems-vs-native.md). Headline: **systems-N# ties
C#/RyuJIT (top-of-class among CLR languages) but trails Rust/C by 1.4×–10.5×**, entirely RyuJIT's missing
auto-vectorization (N# ties C# everywhere → 100% of the native gap is RyuJIT codegen, not N#-specific). The
adversarial pass caught + I fixed two `clang -O3` DCE'd C harnesses (per-iteration pointer-launder barrier);
now 6-of-6 clean.

**Decision (user, 2026-06-06):** finish self-host (the Roslyn-class N# entry point) and sharpen the evidence
first; **backlog** the two big perf bets (auto-vectorization codegen; LLVM/NativeAOT backend) — see
systems-vs-native.md. Key unblocker this gives the self-host work: since systems-N# is performance-neutral
vs C#, porting compiler hot paths to N# carries NO speed regression, so the migration proceeds on
correctness/ergonomics. Near-term order: (1) sharpen evidence (broaden the comparison corpus from synthetic
i32 kernels to a real compiler hot path — token scan / symbol-table probe), (2) resume finishing the N#
front-end + production routing (materialize the columnar AST into the host CompilationUnit / N# consumers,
route CLI/LSP, delete C# `*DogfoodAdapter` surface — the still-untouched criteria 5-6).

## 2026-06-06 — N# parser slice 21: front-end perf benchmark — the N# parser is ~5-6x faster than C# (clears the 5x gate)

The perf answer for the parser front-end (benchmark-first, per the loop). `CompilerServiceParserBenchmarks`
(benchmarks/CompilerServiceParserBenchmarks.cs) parses the SAME supported-form function body with the
N#-native statement kernel (`ParseStatementNodesInto`, composed lexer→type→expression→statement, compiled
from the concatenated kernel sources) vs the production C# `Parser`. Tokenization is done once in setup;
the benchmark measures the PARSE phase only. `[MemoryDiagnoser]` captures allocation.

Results (`--job short`, this machine):

| Corpus         | N# kernel | C# parser | Speedup | N# alloc | C# alloc | Alloc ratio |
|----------------|-----------|-----------|---------|----------|----------|-------------|
| Representative | 550 ns    | 3,266 ns  | **5.9x**| 400 B    | 5,688 B  | 14x less    |
| LargeGenerated | 15.9 us   | 83.3 us   | **5.2x**| 8,608 B  | 148,224 B| 17x less    |

The N# columnar parser is **~5-6x faster and allocates 14-17x less**, and **clears the acceptance standard's
5x gate** (3266/550 = 5.94x; 83259/15887 = 5.24x) on both corpora. This is the first hard evidence that the
N# parser approach meets the "at least as fast as C#, ideally faster" bar — decisively.

**Honest framing of the comparison.** The two implementations are behaviorally equivalent (the kernel's tree
is parity-verified node-for-node against the C# parser by slice 20's whole-body pin) but represented
differently: the C# parser allocates a record per AST node + `List`s; the N# kernel writes a flat columnar
node table into caller-pre-allocated arrays (its only per-call allocation is the small `st`/`argStack`
scratch — hence 400 B / 8,608 B). The columnar design IS the source of the win; this is exactly the
"systems-tier N# beats allocating C#" thesis. The C# baseline also parses the trivial `func benchBody() {…}`
wrapper (signature + constructor token-compaction); for the body-dominated LargeGenerated corpus that
overhead is negligible, so the 5.2x there is the conservative, representative number.

This is the acceptance-standard speed gate met for the front-end parse path. Remaining toward full
acceptance: (1) complete parser parity for the deferred language forms, and (2) production routing of the
in-assembly N# front-end (materialize the columnar table into the host's `CompilationUnit`, or route N#
consumers) so the CLI/LSP path actually uses it — the swap-evidence criterion.

## 2026-06-06 — N# parser slice 20: real-corpus WHOLE-BODY pin (capstone — the N# parser parses real compiler code)

The capstone dogfood validation. Runs the full N#-native front-end statement kernel — which composes the
type + expression + `new` kernels in-assembly over one shared columnar node table — on every dogfood
compiler-kernel function body whose statements stay within the supported forms, and compares the resulting
statement tree **structurally to the C# parser's `FunctionDeclaration.Body`**. This is the N# parser parsing
the actual N# compiler kernels (real recursive-descent compiler code: `:=` declarations, `while`/`if`/`else`,
`return`/`break`/`continue`, assignments, calls, member/index access, the full operator precedence chain,
`new int[](...)`) and matching the production parser node-for-node. 30+ supported-form bodies verified; bodies
using a not-yet-supported form (deferred expression/statement kinds) are skipped and counted via a recursive
`IsSupportedStatement`/`IsSupportedExpr` filter, with a per-file func-count safety net so nothing is silently
mis-paired. Test-only (no kernel change). **No language gaps surfaced — the N# parser reproduces the C#
parser's AST on real compiler code.**

This closes the parser self-host arc for the supported language subset: slices 1-5 (declaration index),
6-8 (type-reference grammar), 9 (function signatures), 10-15 (full common expression grammar), 16-17
(statements + control flow), 19 (`new` + type/expr composition), and now whole-body parity on real code.
Remaining for FULL parser parity (each a future slice): for/foreach, let/const + typed local declarations,
tuple deconstruction, the remaining statement forms (throw/try/using/lock/switch/yield/print/assert), and the
remaining expression primaries (`new[size]`/`new{init}`, match, tuple, array/object literals, interpolated
strings, lambdas, is/as, range, cast). After full parity: production routing of the in-assembly front-end
behind a 5x benchmark (the acceptance-standard endgame).

## 2026-06-06 — N# parser slice 19: st-layout unification + `new` expressions (type/expr kernel composition)

Unblocks whole-body parsing of the dogfood kernels, which use `new int[](...)` array allocation (20 sites).
A `NewExpression` composes the TYPE kernel (the constructed element type) with the EXPRESSION kernel (the
constructor arguments) in one node tree — which required the two kernels to share parser state. They had
incompatible `st` slot layouts, so this slice **unified the `st` layout**: the type + function-signature
kernels' slots were remapped (via a precise simultaneous regex remap, 75 + 16 refs) to match the expression
layout — `st[0]=pos, st[1]=nodeCursor, st[2]=childCursor, st[3]=argStackTop, st[4]=splitGreaterDepth,
st[5]=owedGreaterByteEnd` — and the expr/statement kernels now allocate a 6-slot `st`. The remap is a pure
no-behavior-change refactor, verified by the type + fnsig parity tests passing unchanged.

`new <type>(args)` (kind 15) then drops cleanly in: `ParsePrimaryExpressionNode` calls the type kernel for
the element type (child[0]) and the expression kernel for the positional constructor args (children 1+),
sharing the unified `st` + `argStack`. The type child is a type-kernel subtree (kinds 0-5) and the args are
expression subtrees (kinds 0-14) in ONE table; the host walker disambiguates **positionally** (child[0] →
type walker, rest → expression walker), so the overlapping kind numbers never conflict. The shared `argStack`
stays LIFO-safe under nesting (`f(new List<int>(k))`: the type's generic-arg gathering pushes/pops within the
new's arg region, which nests within the call's). Verified against the production parser's NewExpression on
`new int[](n)`, `new char[](length + 1)`, `new Foo()`, `new List<int>()`, `new int[](count + 1)`, and
nested `f(new int[](k))` / `buffer = new int[](count + 1)`, plus all five existing parser parity tests
(type/fnsig/expr/statement/real-corpus) still green, then a focused adversarial-refutation pass
(new-composition + shared-state-safety lenses).

**Adversarial pass found + fixed 1 fragility:** the `new` branch called the type kernel without first
resetting `st[4]` (splitGreaterDepth), inconsistent with the function-signature kernel which resets it
before every type parse. Latent for valid input (a balanced generic always leaves `st[4]=0`), but the
"`st[4]==0` entering a type parse" invariant should be explicit, not rely on the caller's prior state.
Fixed by resetting `st[4]=0` before the call (NOT `st[3]`/argStackTop — that is the nested LIFO base);
pinned with nested-generic `new` cases (`new List<List<int>>()`, two-news-in-sequence).

Deferred: `new <type>[size]` (sized array), `new <type>{init}` (object initializer), target-typed `new(...)`,
named/ref/out constructor args. Milestone: the front-end kernels (lexer → type → expression → statement)
now compose in-assembly over one shared node table — the substrate for parsing whole dogfood function bodies.

## 2026-06-06 — N# parser slice 18: real-corpus expression pin (anti-overfitting)

Validates the slice 10-15 expression kernel against the production parser on REAL dogfood code — the
anti-overfitting discipline the lexer's 108-file pin established. For each dogfood `.nl` kernel, every
`return <expr>` value whose expression stays within the supported forms (recursively: literals/identifiers/
parenthesized/member/index/call/prefix-unary/binary/ternary/assignment) is parsed by
`ParseExpressionNodesInto` and compared structurally to the C# AST (50+ real return expressions verified).
A per-file safety net — skip the file if the recursively-collected return count disagrees with the `return`
token count — means a missed statement-container in the harvest can never silently mis-pair returns. No
language gaps surfaced; the expression kernel reproduces the C# expression AST on real compiler code.

**Next-step architectural note:** parsing whole dogfood function bodies (the natural real-corpus *statement*
pin) is blocked on `new int[](...)` array-allocation, which is ubiquitous in the kernels. A `NewExpression`
composes the TYPE kernel (its element type) with the EXPRESSION kernel (its arguments) in one node tree, but
the two kernels currently use incompatible `st` slot layouts (type: pos/splitDepth/nodeCursor/childCursor/
owedGreaterByteEnd/argStackTop; expr: pos/nodeCursor/childCursor/argStackTop). The clean unblock is to unify
the `st` layout (expr already matches slots 0-3; renumber the type kernel's slots and let both use a 6-slot
`st`, with the New node bridging a type child + expression-argument children positionally). That is the next
deliberate slice; the type parity test (`Parser_TypeReferenceTree_MatchesProductionParser`) is a fast safety
net for the renumber.

## 2026-06-06 — N# parser slice 17: control flow — blocks, while, if/else

Restructures the statement kernel into a recursive dispatcher (`ParseStatementCoreNode`) and adds
`BlockStatement` (kind 25, `{ stmt* }` — children gathered on the LIFO arg-stack), `WhileStatement`
(kind 26, children [condition, body]), and `IfStatement` (kind 27, children [cond, then, else?]). Following
the C# parser, if/while bodies are ANY statement (a `{ }` block or a single statement), so they recurse
through the dispatcher; `else if` chains as a nested if in the else child. This lets the kernel parse whole
function bodies. Verified against the production parser's Statement AST on blocks, while, if/else, else-if
chains, break/continue in loops, and **deep nesting** (`while i < n { if arr[i] == target { return i }
i = i + 1 }`) which stresses the block arg-stack under recursion (nested blocks push/append/pop within their
own region, LIFO). Followed by a focused adversarial-refutation pass (structure + bounds/arg-stack lenses).

**Language feature exercised:** the N# compiler's own unused-parameter lint (NL012) caught a dead `depth`
parameter in `ParseSimpleStatementNode` during this slice — a nice dogfood signal that the analyzer works on
real kernel code. Fixed by dropping the parameter.

Deferred: for/foreach, let/const/readonly + typed `name: Type = init` declarations, tuple deconstruction,
throw/try/using/lock/switch/yield/print/assert/local-functions, and `new`/`alloc` initializers. Next: those
remaining statement/expression forms as needed, then a real-corpus pin over whole dogfood function bodies.

## 2026-06-06 — N# parser slice 16: simple statements (statement subsystem begins)

Starts the last major parser subsystem — function bodies, the critical path for parsing the dogfood kernels
(flat top-level functions whose bodies are statements). `ParseStatementNodesInto` (new
`ParserStatements.nl`) parses ONE statement, dispatching like the C# `ParseStatement` (Parser.cs:2165), and
COMPOSES the slice 10-15 expression kernel into a SHARED node table (statement kinds 20+, expression kinds
0-14): `ReturnStatement` (20, optional value child), `BreakStatement` (21), `ContinueStatement` (22),
`ExpressionStatement` (23, incl. assignment expressions like `x = e`/`x += 1`), and
`VariableDeclarationStatement` (24, the `:=` shorthand after a bare identifier — name in the value span,
initializer child). `:=` (ColonAssign 121) is the declaration; `=` (Assign 93) is an assignment expression
wrapped in an ExpressionStatement. Verified against the production parser's Statement AST (extracted from a
`func f() { <stmt> }` body) on return-with/without-value, break/continue, `:=` declarations, assignment and
call expression-statements, with full-consumption (the statement ends at the body `}`).

Deferred to later slices: control flow (if/else, while, for, foreach) and their nested blocks (the block
kernel parsing a `{ ... }` sequence is next); let/const/readonly and typed `name: Type = init` declarations;
tuple deconstruction; throw/try/using/lock/switch/yield/print/assert/local-functions; and `new`/`alloc`
initializers (a deferred expression primary). No language gaps surfaced.

## 2026-06-06 — N# parser slice 15: ternary + assignment (expression top)

Adds the two levels above the binary chain (mirroring `ParseTernaryExpression` Parser.cs:3916 and
`ParseAssignmentExpression` Parser.cs:3599): `TernaryExpression` (kind 13, `cond ? then : else`, children
[cond, then, else]) and `AssignmentExpression` (kind 14, `target OP value` for `=`/`+=`/`-=`/`*=`/`/=`/`??=`,
operator token in the value span, children [target, value]). Assignment is right-associative (`a = b = c`
=> `a = (b = c)`) and the ternary else-branch is a full expression, so it nests right (`a ? b : c ? d : e`).
The "full expression" entry now routes through assignment -> ternary -> binary -> unary -> postfix ->
primary. Verified against the production parser's TernaryExpression/AssignmentExpression on nesting,
right-associativity, compound assignments, and composition (`result = cond ? f(x) : g(y)`,
`total = total + n`, `x ??= y`), plus the full expression corpus, refusals, determinism, root-span, and
full-consumption invariants.

**Milestone:** the N# expression kernel now covers the full common expression grammar — primaries, postfix
(member/index/call), prefix unary, the binary precedence chain, ternary, and assignment. Remaining for full
parity: `is`/`as`, range `..`, lambdas, and the less-common primaries (new/alloc/match/tuple/array&object
literals/interpolated strings/cast). Next: statements (the function bodies — the last major piece for
parsing the dogfood kernels), composing this expression kernel. No language gaps surfaced.

## 2026-06-06 — N# parser slice 14: binary-operator precedence chain (expression core complete)

Adds the full left-associative binary precedence chain via **precedence climbing**
(`ParseBinaryExpressionNode` + `BinaryOpPrecedence`, mirroring the C# levels
ParseNullCoalescing..ParseMultiplicative, Parser.cs:3940-4185): `??` < `||` < `&&` < `|` < `^` < `&` <
`==`/`!=` < relational(`<` `<=` `>` `>=`) < shift(`<<` `>>`) < `+`/`-` < `*`/`/`/`%`. Each
`BinaryExpression` (kind 12) records the operator token in the value span with children `[left, right]`
(fixed arity → contiguous, no arg-stack). The left-associative formulation (parse RHS at `precedence + 1`)
reproduces the same left-leaning trees as the C# while-loop levels; the "full expression" entry is
`minPrec == 1`. Operators above this chain (`is`/`as`, range `..`, assignment, ternary) correctly STOP the
loop (deferred). Verified against the production parser's BinaryExpression on precedence boundaries
(`1 + 2 * 3`, `a == b && c != d`, `x | y & z`), left-associativity (`a - b - c`), and composition with
postfix/unary (`i < count && tokenKinds[pos] == 102`, `f(x) + g(y) * 2`, `!found && i < n`), then a focused
adversarial-refutation pass (precedence/associativity + safety/dual-use lenses).

**Milestone:** the N# expression kernel now covers the core expression grammar — primaries, full postfix
(member/index/call), prefix unary, and the complete binary precedence chain — enough to parse the bulk of
real dogfood expression shapes. Remaining for full expression parity: `is`/`as`, range, assignment,
ternary, and the less-common primaries (new/alloc/match/tuple/array&object literals/interpolated strings/
lambda/cast). Next natural step: a real-corpus expression pin over the dogfood kernel bodies (supported-form
filtered), then statements. No language gaps surfaced.

## 2026-06-06 — N# parser slice 13: prefix unary expressions

Adds the unary level (`ParseUnaryExpressionNode`, mirroring `ParseUnaryExpression` Parser.cs:4223):
prefix `!` (Not), `-` (Negate), `~` (BitwiseNot), `++` (PreIncrement), `--` (PreDecrement), `^`
(IndexFromEnd) wrapping a recursively-parsed unary operand -> `UnaryExpression` (kind 11, the operator
token in the value span). The "full expression" recursion points (entry, parenthesized-inner, index, call
arguments) now route through this unary level, so prefixes compose with postfix: `-arr[i]`, `!a.b`,
`-f(x)`, `!!x`, `-(value)`. Verified against the production parser's UnaryExpression (operator + recursive
operand) plus the full primary/postfix corpus, refusals, determinism, root-span, and full-consumption
invariants. Prefix `+` is invalid in N# and is refused (fall-through to primary). Postfix `++`/`--` and
`must` are deferred. Next: the binary-operator precedence chain (after which a real-corpus expression pin
over the dogfood kernel bodies becomes possible). No language gaps surfaced.

## 2026-06-06 — N# parser slice 12: call expressions (postfix level complete)

Adds `CallExpression` (kind 9) to the postfix loop: `callee(args)` with children `[callee, arg0, arg1, ...]`.
Arguments are variable-arity, so the callee + argument node ids are gathered on a caller-owned LIFO
arg-stack (the exact pattern the type kernel uses for generic arguments — recursion is LIFO, append the
contiguous child run after the closing `)`) — the expression kernel's `st` gains `st[3]=argStackTop` and an
`argStack` array. Composes with member/index: `obj.method(x)`, `f(g(x))`, `f(a)(b)` (curried), `f(x)[i]`,
`compute(a, b, c).result`. Verified against the production parser's CallExpression (callee + positional
argument trees, no type arguments) on empty/single/multi/nested/curried/mixed calls, plus refusals (-1) for
named (`f(x: 1)`) and ref/out (`g(ref y)`) arguments (deferred), plus determinism, root-span, and
full-consumption invariants.

The N# expression kernel now covers the full primary + postfix level (literals, identifiers, parenthesized,
member access, indexing, calls). Deferred: `?.`/`?[`, generic calls, `++`/`--`, `with`, then unary and the
binary precedence chain (after which a real-corpus expression pin over the dogfood kernel bodies becomes
possible). No language gaps surfaced.

## 2026-06-06 — N# parser slice 11: postfix expressions (member + index access)

Extends the expression kernel with the postfix level (`ParsePostfixExpressionNode`, mirroring
`ParsePostfixExpression` Parser.cs:4312): a primary followed by any run of `.member` (MemberAccess, kind 8 —
member name in the value span) and `[index]` (IndexAccess, kind 10 — children [object, index]) suffixes. The
entry and the parenthesized-inner now route through this postfix level, so chains compose:
`arr[i].field`, `a[b][c]`, `(x).y`, `data[i].next.value`. Index expressions recurse to the postfix level.
Both forms are fixed-arity, so their child runs stay contiguous by appending right after the object/index
are fully parsed — no arg-stack needed (that is reserved for the variable-arity CallExpression in the next
slice). Verified against the production parser's MemberAccess/IndexAccess (member name + recursive object/
index trees, non-null-conditional) on member/index/mixed chains, plus the existing primary corpus, refusals,
determinism, root-span, and full-consumption invariants.

Deferred: CallExpression (kind 9, reserved — needs the arg-stack for variable arity), `?.`/`?[`
null-conditional, generic method calls, `++`/`--`, `with`; then unary and the binary precedence chain. No
language gaps surfaced.

## 2026-06-06 — N# parser slice 10: primary expressions (the expression subsystem begins)

Starts the largest parser subsystem — the ~17-level expression precedence chain
(Parser.cs ParseExpression..ParsePrimaryExpression). This is the critical path for self-hosting the dogfood
kernels themselves, which are flat top-level functions whose BODIES are statements + expressions (they have
no type members). `ParseExpressionNodesInto` (new `ParserExpressions.nl`) parses PRIMARY expressions —
int/float/char/string/bool/null literals (kinds 0-5), identifiers (kind 6), and parenthesized expressions
(kind 7, `( expr )`) — into a columnar node table (post-order, root last), mirroring
`ParsePrimaryExpression`. Verified against the production parser's Expression AST (extracted from a
`return <expr>` statement) on every primary form incl. nested parens, plus refusals (-1) for tuples
`(a, b)`, named elements `(x: e)`, and non-primary leads (`+5`, `.x`, `)`), plus determinism, root-span, and
full-consumption (continuation lands on the block's `}`) invariants.

Deferred to later slices (the rest of the chain): postfix (call/index/member access), unary, the binary
precedence chain, assignment, ternary, range, new/alloc, match, tuples, array/object literals, interpolated
strings, lambdas, casts. Literal VALUE materialization (unescaping) stays the host's job — the kernel
records the value token's byte span (int/float values verified to equal that span; string/char are
kind-only). No language gaps surfaced.

## 2026-06-06 — N# parser slice 9: function signatures (first declaration-level kernel, composes the type kernel)

The first slice that goes ABOVE type references: `ParseFunctionSignatureInto` (new
`ParserFunctionSignatures.nl`) parses a function's signature — name, parameter names + parameter type
trees, and the return type tree — mirroring C# `ParseFunctionDeclaration`/`ParseParameterList`
(Parser.cs:405-535, 770-840). It COMPOSES the slice 6-8 type kernel: every parameter type and the return
type are parsed by `ParseUnionTypeReferenceNode` and share ONE columnar node table (each is an independent
root), with the shared parser-state array carrying the node/child cursors across the per-type parses while
`st[0]` is repositioned to each type's start. This proves the kernels compose cleanly in-assembly
(cross-file calls within the merged `Program` type) — the pattern the whole N# parser will use.

Handles parameter modifiers (`ref`/`out`/`params`/`this`, skipped), attribute lists (skipped), `= default`
values (skipped balanced, not parsed), and optional `<TypeParams>` between the name and `(` (skipped by
scanning to the first `(`). Verified against the production parser's `FunctionDeclaration`
(Name, Parameters[].Name/.Type, ReturnType) on a synthetic corpus exercising every supported param/return
form plus modifiers/defaults/`this`/generic-function, AND on a real-corpus pin: **every top-level function
in the dogfood kernels whose signature stays within the supported type forms (>100 verified)**, with
deferred-form signatures filtered out and counted.

**Adversarial pass found + fixed 2 real defects.** A focused refutation pass (signature-correctness +
bounds-safety lenses) confirmed that on a MALFORMED default value with unbalanced brackets (e.g.
`func f(x: int = {): void`), the default-value skip's single depth counter let a `)` close a `{`, so the
scan ran past the parameter list's `)` and silently mis-parsed (wrong parameter count / dropped return
type). Valid input was always correct (the corpus + real-corpus pin passed), but silent wrong output on
malformed input violates the rock-solid bar. Fix: after skipping a parameter's optional default, require
the next token to be `,` or `)` — otherwise refuse with -1 (fail-fast; full error recovery stays deferred).
Locked with negative tests (`= {`, `= (,`, `= [` → -1).

**Finding — the parser layer consumes a newline-compacted token stream.** The C# `Parser` drops every
`Newline` token in its constructor (Parser.cs:24-26); N# is not newline-significant at the parse level
(indentation already became virtual braces in the lexer). The single-line type-reference tests never hit
this, but real multi-line signatures do, so the host now compacts the lexer's raw token arrays (removing
ordinal 136) before invoking the parser kernels — matching production. Byte offsets are unaffected. No
language gaps surfaced.

## 2026-06-06 — N# parser slice 8: by-ref type references + the source-access limit finding

Adds `ByRefTypeReference` (`&T`, node kind 5) to the type kernel — `&` prefixing a postfix type, placed in
`ParseBaseTypeReferenceNode` exactly as the C# parser (Parser.cs:1830-1840), so a by-ref is reachable as a
union arm or generic argument too (`&int | string`, `List<&int>`). Verified against the production parser
on `&int`, `&List<int>`, `&int[]`, by-ref-as-generic-arg, and by-ref-in-union.

The N# type-reference parser now covers Simple / Generic / Array / Nullable / Union / ByRef — the
overwhelming majority of real type references — each parity-verified against `Parser.cs`.

**Finding (documented, not a hack): the two remaining type forms hit real design limits, not parser bugs.**
- **`Func<...>`** — the C# parser special-cases the *identifier text* `"Func"` to produce a
  `FunctionTypeReference` (Parser.cs:1849-1852). The kernel works on token kind/offset arrays and has **no
  source string**, so it cannot distinguish `Func` from any other generic name; it would parse `Func<...>`
  as a `GenericTypeReference`. Func is therefore excluded from the corpus. Resolving it requires giving the
  parser kernels **source access** (a future architectural step that also unlocks name-based contextual
  keywords like `duck`/`scoped` and on-the-fly name materialization).
- **Tuple `(...)`** — needs per-tuple-element **name** edge-metadata (`(x: int, y: string)`) that the
  current columnar node table does not carry, plus the single-unnamed-element `(T)` → parenthesized-type
  collapse. Refused with -1 for now.

These two limits — source access for text-based decisions, and richer edge-metadata — are the natural
inputs to the next parser phase. No language gaps surfaced.

## 2026-06-06 — N# parser slice 7: union type references (closes the first deferred form)

Extends slice 6's recursive-descent type kernel with the top-of-grammar union level
(`ParseUnionTypeReferenceNode`, mirroring C# `ParseUnionTypeReference`, Parser.cs:1723-1756): a postfix
type optionally followed by `| postfix` arms becomes a `UnionTypeReference` (node kind 4) whose arms are
its children; with no `|` it returns the single postfix node unchanged (matching the C# `return first`).
Both the top-level entry AND generic arguments now route through this level (matching the C# parser, where
generic args call full `ParseTypeReference`), so a union can be a generic argument — `List<int | string>`,
`Dictionary<int | string, bool>`. Arms are gathered on the same shared LIFO arg-stack as generic args, so
union+generic nesting keeps every node's child run contiguous. Span = first-arm-start .. last-arm-end.

Verified against the production parser's `UnionTypeReference` (arm count + recursive arm trees) on
multi-arm unions, unions of generics/arrays/nullables (`int[] | List<int> | string?`), and union-as-
generic-arg, plus a focused adversarial-refutation pass (union-correctness + arg-stack-discipline lenses).
Remaining deferred type forms: Tuple `(...)`, Func `Func<...>` (a `FunctionTypeReference` in the C# AST),
ByRef `&T` — all still refused with -1. No language gaps surfaced.

## 2026-06-06 — N# parser slice 6: FIRST recursive-descent, tree-building kernel (type references)

The qualitative jump from flat single-pass token *scans* (slices 1-5) to genuine recursive-descent AST
*construction*. `ParseTypeReferenceNodesInto` + helpers (NEW file `ParserTypeReferences.nl`) reproduce the
C# parser's `ParseTypeReference` → `ParsePostfixTypeReference` → `ParseBaseTypeReference` recursion
(Parser.cs:1718-1907) for the four dominant forms — `SimpleTypeReference` (incl. dotted `A.B.C`),
`GenericTypeReference`, `ArrayTypeReference`, `NullableTypeReference` (incl. `?[]` → `Array(Nullable)`) —
and emit a real parent→child AST as a flat columnar node table (kind / name span / child run / byte span),
in **post-order** so the root is the last node. Verified structurally against the production parser's
`TypeReference` tree (kind + name + recursive children) plus byte-span, post-order-root, full-consumption,
determinism, deferred-form-seam, and depth-cap invariants, on a corpus covering every form and composition.

**Why this rung is the product blocker:** `ParseTypeReference` is the shared leaf of every
field/param/return/constraint parse, so no declaration/statement/expression parser slice can self-host
until type references do. It also begins Phase 2 (the in-assembly N# front-end that removes the
~1.2 ns/token delegate boundary blocking production routing of the lexer and the routed kernels).

**Capability proven (no language gap surfaced):** N# supports recursive-descent **tree construction** —
mutual recursion (`ParsePostfix` ↔ `ParseBase`) plus shared mutable state threaded through recursive
frames (the `st[]` parser-state array — pos / splitGreaterDepth / node & child cursors — and the
columnar out-arrays). Recursion alone was already proven (`ProjectSourceFilterMatchFrom`); building a tree
with it is the new, now-validated surface.

**Correctness highlights handled (faithful to the C# parser):**
- **`>>` RightShift split.** The lexer emits one `RightShift` (112) token for `>>`, so `List<List<int>>`
  has ONE token closing TWO generics. The kernel mirrors C# `ConsumeGreater`/`_splitGreaterDepth`: a
  `RightShift` close consumes the token and credits one *owed* `>` (tracked with its byte-end) that the
  enclosing close consumes without advancing. Proven: `splitGreaterDepth` provably never exceeds 1 (each
  `RightShift` is immediately followed by an owed close), so a single owed-byte-end slot suffices.
  Corpus: `List<List<int>>`, `Foo<Bar<Baz<int>>>`.
- **Child-run contiguity under interleaving (the one real bug found & fixed mid-slice).** A generic whose
  arguments are themselves generic would, with naïve append-as-you-parse, fragment the parent's child run
  in the shared `outChildIndices` (the nested arg appends ITS edges in between). Fix: gather each generic's
  argument ids on a shared **LIFO arg-stack** (recursion is LIFO, so nested generics push/append/pop within
  their own region) and append the parent's contiguous child block only after the whole arg list + closing
  `>` are consumed. Regression pin in the corpus: `Dictionary<List<int>, List<int>>`.
- **Deferred-form seam.** Union (`A | B`) cleanly STOPS at `|` (returns the first arm, leaves `|`
  unconsumed — the next slice). Tuple `(...)`, `Func<...>` (a `FunctionTypeReference` in the C# AST, not a
  generic — intentionally out of corpus), and ByRef `&T` are REFUSED with -1 (non-identifier first token).
- **Depth cap.** Generic nesting > 64 returns the -1 overflow sentinel (a tested, documented limit; the
  real stack is never blown). Pin: a 70-deep `List<...>` asserts -1.

Deferred to later rungs: Union arms, Tuple, Func semantics, ByRef, lifetimes, line/col `SourceSpan`
(byte-span only this slice), a full real-corpus type-annotation harvest, and production routing. No
language gaps surfaced.

## 2026-06-06 — N# parser slice 5: top-level declaration modifiers

`TopLevelDeclarationModifiersInto` + `ModifierFlag` (ParserDeclarations.nl) record, for each top-level
declaration, the accumulated modifier-flag set from the modifier keywords appearing at depth 0 before
its keyword — mirroring `ParseModifiers` (Parser.cs:330) and the `Modifiers` `[Flags]` enum
(Declarations.cs:271). All twelve recognized declaration modifiers are mapped by TokenType ordinal to
their flag bit (Public 1, Private 2, Internal 4, Protected 8, Static 16, Virtual 32, Abstract 64,
Sealed 128, Partial 256, Async 2048, File 32768, Override 65536); attributes sit inside brackets so the
depth tracking skips them, and member-level modifiers (Readonly/Const/Required/Init) are correctly
excluded. Verified against `(int)Declaration.Modifiers` on a new modifier-rich corpus (every modifier
singly and combined — `private static func`, `internal async func`, `public abstract class`,
`internal partial struct`, `[Obsolete] public record`, `protected virtual`/`public override` funcs),
plus the controlled/indentation corpora and all 27 dogfood kernels. `type`/`test` are skipped in the
modifier check: their C# AST nodes (`TypeAliasDeclaration`/`TestDeclaration`) carry no `Modifiers`
field, so the parser discards leading modifiers there while the kernel records raw leading modifiers
for every declaration keyword — corpora intentionally do not modify `type`/`test` to avoid that one
known C#-AST-vs-kernel divergence. No new language gaps surfaced.

## 2026-06-06 — N# parser slice 4: namespace imports (file-structure index complete)

`NamespaceImportSpansInto` (ParserDeclarations.nl) walks the `package`/`import` header prefix linearly
(matching `Parser.cs:52-81`), recording each `import A.B.C [as X]` namespace import's dotted-name span +
optional alias span, and skipping file imports (string after `import`, which the C# parser routes to
FileImports). Verified against `CompilationUnit.Imports` (namespace + alias) on the controlled corpus
(`import System`; `import A.B.C as Alias`), the indentation corpus, and all 27 dogfood kernels.

**Milestone:** the N# parser now extracts a complete top-level file-structure index — namespace imports,
package, and the ordered declaration kind+name list — entirely in-assembly from the lexer's tokens, each
piece verified against the C# parser. Next rungs deepen into declarations (modifiers, signatures) and
then statements/expressions toward a full N# parser. No new language gaps surfaced in slices 1-4.

## 2026-06-06 — N# parser slice 3: package name

`PackageNameSpanInto` (ParserDeclarations.nl) records the file's `package A.B.C` dotted-name span (or
returns 0 when absent), matching the C# parser's `CompilationUnit.Package?.Name`. Verified on the
controlled/indentation corpora and all 27 dogfood kernels. The N# parser now extracts a coherent
file-structure index — package + top-level declaration kinds + names — from the lexer's tokens,
in-assembly. (Imports' namespace-vs-file-import distinction is deferred to a later careful slice.)

## 2026-06-06 — N# parser slice 2: top-level declaration names

`TopLevelDeclarationNameSpansInto` (ParserDeclarations.nl) extends slice 1 to also record each
top-level declaration's NAME span. A declaration's name is the token immediately after its keyword
(modifiers precede the keyword), so `name = next token when it is an Identifier` is exact for all eight
keyword declaration kinds and correctly yields no-name for `test "..."` (string-named, out of scope
this slice). Verified against the C# parser's `Declaration.Name` (kind + name pairs) on the controlled
corpus, the indentation-style corpus, and all 27 dogfood kernels. The N# parser now extracts a
top-level declaration index (kind + name) from the lexer's tokens, all in-assembly.

## 2026-06-06 — Phase 2 begins: first N#-native parser slice (top-level declaration extraction) + nlc query ast

**What:** Two slices that open the parser-migration phase (the path to actually deleting the
`*DogfoodAdapter` bridge and, ultimately, bootstrap).

1. **`nlc query ast`** (LLM-first CLI + verification harness). New `nlc query ast [--file F]`
   subcommand emits the parsed `CompilationUnit` AST(s) as stable, node-typed JSON
   (`OutputFormatter.AstToJson`: each node `{ "node": "<ConcreteType>", …declared props }`, recursing,
   preserving the concrete kind through the polymorphic Declaration/Statement/Expression bases). This
   is both an AGENTS LLM-first-CLI deliverable and the **canonical AST representation** for verifying an
   N# parser against the C# parser. Hardened by `Parser_RealCorpus_AstSerializesDeterministically`
   (parse + serialize all 108 real .nl files: valid, deterministic, no crashes).

2. **First N#-native parser kernel** (`CompilerServices/ParserDeclarations.nl`):
   `TopLevelDeclarationKindsInto` extracts the top-level declaration KIND sequence from the
   brace-inserted token stream (output of the now-complete N# lexer), tracking brace/bracket/paren depth
   so it captures declaration keywords (Func/Class/Struct/Interface/Union/Record/Enum/Type/Test) only at
   depth 0 — naturally skipping modifiers, attributes, and NESTED declarations, and capturing
   `ref struct`/`duck interface` at their `struct`/`interface` keyword exactly as the C# dispatch
   (`Parser.cs:226-273`) produces. Verified by `Parser_TopLevelDeclarationKinds_MatchProductionParser`
   against the C# parser's `CompilationUnit.Declarations` (mapped to keyword ordinals) on a controlled
   corpus (all keyword kinds + nested-decl exclusion + modifiers + attributes), an indentation-style
   corpus (virtual braces handled identically to explicit), and all 27 dogfood kernels (real code).

**Significance:** the lexer is feature-complete and an N# consumer of its tokens now exists in-assembly
(the kernel reads the lexer's token arrays). This is the first verified rung of the parser ladder.
Building it surfaced no new language gaps. Bootstrap coverage remains 0% (these are services behind the
adapter), but the verification harness (AstToJson) + the first parser rung are the scaffolding for
growing an N# parser slice-by-slice against the C# parser.

## 2026-06-06 — Lexer real-corpus dogfood parity (108 real .nl files) + CommentsInto benchmark

**What:** Two consolidation slices proving the now-complete N# lexer on real code.

1. **Real-corpus parity.** Extended `LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer`
   to run the COMPLETE N# lexer (`TokenizeMetadataWithIndentationInto` + `CommentsInto`) against the C#
   production lexer (`Lexer.Tokenize()` / `Lexer.Comments`) over **every real `.nl` file** — 81 in
   `examples/` + 27 dogfood compiler-service kernels = **108 files**, including the systems source the
   compiler is written in (lifetimes, `scoped`/`unsafe`, raw/interpolated strings, comments,
   indentation). Full token-stream parity (kind/start/valueLength/line/column) AND comment-trivia
   parity hold on all 108 — the strongest available correctness evidence that the N# lexer matches C#
   on the code that matters. (This is the "use the compiler on itself to ensure correctness" mandate.)

2. **CommentsInto benchmark** (`CompilerServiceLexerCommentBenchmarks`, see
   [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md)): N#'s zero-alloc comment scan vs
   C#'s tokenize-byproduct comment collection — 4.7× representative (0 B vs 33.9 KB), 18× large
   (0 B vs 10.7 MB). Framed honestly there (C# has no dedicated comment scanner).

**Status:** the N# lexer is feature-complete AND validated correct on the real compiler/example corpus.
The remaining self-host work is the large subsystem migration (parser → N#, consuming N# tokens
in-assembly) needed to actually delete the `*DogfoodAdapter` bridge — a multi-slice Phase 2/3 effort.

## 2026-06-06 — Phase 1 lexer: comment-trivia collection (N# lexer feature-complete vs C#)

**What:** Added the `CommentsInto` N# kernel — the last lexer feature gap. The C# `Lexer.Tokenize`
collects line/doc/block comments into `Lexer.Comments` (consumed by the formatter) while excluding them
from the token stream. `CommentsInto` reproduces it exactly: for each comment it records line, column,
start offset, length, and `isMultiLine` (1 = block `/* */`, 0 = line `//` or doc `///`). C#'s stored
text is the full span for line/doc comments and `"/*" + inner + "*/"` for block comments — both equal
`end - start`, so `length` = `end - start` uniformly. The kernel mirrors `TokenizeMetadataInto`'s token
dispatch (consuming string / raw-string / char / lifetime / number / identifier / operator runs as
units), so a `//` or `/*` INSIDE a literal is never misread as a comment and line/column tracking
through multi-line raw strings stays exact.

**Verified:** `AssertCommentsLikeProductionLexer` compares `CommentsInto` to `new Lexer(src).Comments`
(line/column/start/length/isMultiLine) on a dedicated `commentSource` (line + doc + single-line block +
multi-line block + trailing comment with no final newline + `//`/`/*` inside string and char literals
that must NOT be collected) plus the representative/metadata/source/lifetime corpora. Targeted test
green.

**Milestone — the N# lexer is now feature-complete vs the C# production lexer:** token kind, source
position (start/line/column), value length, indentation braces, Unicode classification, lifetimes,
malformed-number Unknown tokens, AND comment trivia all match `Lexer.Tokenize()`/`Lexer.Comments`.
Token-text is host-derivable from start+length (not a kernel gap). The Phase 0/1 lexer beachhead's
correctness work is done; what remains for the lexer is the **architecture** (Phase 2): an N#-native
Token representation + an in-assembly N#→N# consumer (parser) so the `*DogfoodAdapter` delegate
boundary can actually be deleted — the dogfood kernels remain behind that bridge until their caller is
also N#.

## 2026-06-06 — Phase 1 lexer: malformed-number Unknown tokens (raw-tokenizer kind-stream parity complete)

**What:** Closed the last raw-tokenizer kind divergence — malformed numbers. The C# `ReadNumber`
emits an `Unknown` token (137) for: a `0x`/`0b` prefix with no valid digit immediately after (a leading
`_` counts as "no digit", `Lexer.cs:592/614`), a second decimal point (`Lexer.cs:650-659`), and an
exponent `e`/`E[+/-]` with no following digit (`Lexer.cs:681-684`). The N# `ScanNumberInfo` had no
error path — it returned `IntLiteral`/`FloatLiteral` and (for a leading `_` after `0x`/`0b`)
over-consumed the span. Added the four error branches: `ScanNumberInfo` now returns a kind-`3` sentinel
(Unknown) with the exact span C# consumes, and the two metadata/kind callers map `3`→`137`. Because
the error branches return C#'s consumed span and `NumberValueLength` counts non-`_` chars, the Unknown
token's value text/length matches C#'s `sb` automatically (`1_e'`→"1e", `0x`→"0x", `1.2.3`→"1.2.3").

**Cleanup:** consolidated the duplicate number scanner — `TokenizeCount` now uses
`ScanNumberInfo(...) >> 2` for the end offset, and the redundant `ScanNumber` function was removed
(single source of truth for number consumption).

**Coverage completion (honest accounting):** also added `indentLifetimeSource` (the indentation-style
lifetime corpus the `5c793e57` entry claimed to restore but missed) and composed-path asserts for the
flat lifetime/unicode/char-literal/malformed-number corpora — closing the two coverage gaps from the
earlier agent-revert incident.

**Verified:** `malformedNumberSource` (`0x`, `0b`, `1e`, `1.2.3`, `0x_F`, `1e+`) asserted across all
three raw tokenizers + the composed path vs `Lexer.Tokenize()` (kind/start/valueLength/line/column +
count). Targeted test green. With this, **N# raw-tokenizer kind-stream parity with the C# production
lexer is complete** — identifiers, keywords (incl. systems), literals (incl. raw/interpolated/char),
lifetimes, operators, delimiters, comments-excluded, indentation braces, Unicode classification, and
now malformed-number Unknown tokens all match.

**Remaining lexer gaps:** comment-trivia collection for the formatter (`Lexer.Comments`) and token-text
materialization (host-derivable from start+length) — neither is a *kind/position* parity gap.

## 2026-06-05 — Phase 1 lexer: Unicode character classification + char-literal fix

**What:** Closed the last raw-tokenizer character-classification gap and restored lost test coverage.

1. **Unicode classification.** The scanner's char helpers were ASCII-only; the C# lexer uses the BCL
   Unicode predicates throughout (`char.IsDigit` 336/631/…/757, `char.IsLetter` 342/905,
   `char.IsLetterOrDigit` 567/922/926/942, `char.IsWhiteSpace` 912/1084). Rewrote
   `IsWhitespaceExceptNewline` → `char.IsWhiteSpace(ch) && ch != '\n' && ch != '\r'`,
   `IsIdentifierStart` → `ch == '_' || char.IsLetter(ch)`, `IsIdentifierPart` →
   `ch == '_' || char.IsLetterOrDigit(ch)`, `IsDigit` → `char.IsDigit(ch)`, and the lifetime-lookback
   whitespace → `char.IsWhiteSpace(ch)`. `IsHexDigit` stays `IsDigit || a-f || A-F` (now matching C#'s
   `char.IsDigit(c) || a-f || A-F`). **The C# lexer has no ASCII fast path, so calling the same BCL
   predicates is BOTH exact-parity AND the same cost** — no perf regression vs C#.
2. **Char-literal `'\<CR>` fix.** `ScanCharLiteral` consumed the escaped char unconditionally; C#
   `ReadCharLiteral` guards it with `!IsAtLineBreak()` (Lexer.cs:882). Added the `\n`/`\r` guard so a
   backslash at end-of-line leaves the line break to become a separate Newline token (pre-existing gap
   surfaced by the lifetime slice's fuzz).

**Audit answer (resolved):** the open question "do `char.IsWhiteSpace`/`IsLetter`/`IsLetterOrDigit`/
`IsDigit` compile in the dogfood kernel?" is **YES** — verified by compiling the dogfood project with
them and passing the full ASCII corpus. This also retroactively confirms the lifetime port could have
used them; the ASCII helpers it used are exactly equivalent on ASCII, and now share the Unicode upgrade.

**Verification:** added `unicodeSource` (Unicode-letter identifiers `café`/`ident١`, NBSP U+00A0 as an
inline separator splitting `x y`, Arabic-Indic digit U+0661 in identifier-continuation) asserted via
all three raw tokenizers + the composed path, and `charLiteralLineBreakSource` (`'\<CR>`) — all match
`Lexer.Tokenize()`. Targeted test green; gate green.

**Test-coverage restoration (honest accounting):** the prior lifetime slice's commit `dc42b0f0` was
SUPPOSED to add `lifetimeSource`/`indentLifetimeSource` parity corpora, but a concurrent adversarial
review agent (running in the main repo, not an isolated worktree) ran `git checkout HEAD -- tests/...`
to revert its own scratch edits — which silently wiped my uncommitted lifetime corpora before the
commit. The lifetime KERNEL code committed fine and was independently validated by the review's
differential-fuzz harness, but the corpora were missing from `dc42b0f0`'s test. This slice restores
`lifetimeSource` (all contexts: `<'a>`, `<'a,'b>`, `scoped 'a`, `returns 'a`, char-literal non-lifetimes)
+ `indentLifetimeSource`. Process fix recorded: verify/review agents must be read-only or worktree-
isolated, and never commit while they run against the shared tree.

**Remaining lexer gaps:** a number-scanner exponent/underscore divergence (`1_e'`-style, surfaced by
fuzz — separate from classification; **closed in the next-dated entry above**); then comment-trivia
(`Lexer.Comments`) + token-text materialization for a full production N# lexer.

## 2026-06-05 — Phase 1 lexer: lifetime tokens ported to N# (blocker closed)

**What:** Closed the lifetime-token blocker from the prior entry's audit. The C# lexer
(`Lexer.cs:325-328`, `IsLifetimeStart`/`IsLifetimeContext`/`ReadLifetime` at `Lexer.cs:903-958`) emits
a single `Lifetime` token (ordinal 142) — instead of a char literal — when an apostrophe begins an
identifier (next char letter/`_`, and the char after that is not a closing quote, so `'a` vs the char
literal `'a'`) AND it sits in a lifetime *context*: the nearest preceding non-whitespace char is `<`
or `,`, or the identifier word immediately before it is `scoped`/`returns`. The N# scanner had no
lifetime handling, so it lexed `'a` as a char literal — wrong kind, and for multi-char lifetimes
(`'a1`) even the wrong token *count*.

**Port** (`CompilerServices/LexerTokenKindScanner.nl`): added `IsLifetimeStartAt`,
`IsLifetimeContextAt`, `MatchesScopedOrReturns`, `ScanLifetime`, and `IsAsciiWhitespace`, mirroring the
C# methods statement-for-statement, and inserted a lifetime branch **before the char-literal branch in
all three tokenizers** (`TokenizeKindsInto`, `TokenizeMetadataInto`, `TokenizeCount`) so every parity
path agrees. The backward context scan (skip whitespace incl. newlines → `<`/`,` early-true → else read
the preceding identifier word and match `scoped`/`returns`) reuses the scanner's existing ASCII
classification helpers (`IsIdentifierStart` ≡ `char.IsLetter||'_'`, `IsIdentifierPart` ≡
`char.IsLetterOrDigit||'_'`, `IsAsciiWhitespace` ≡ `char.IsWhiteSpace` — exact on ASCII), keeping the
scanner uniformly ASCII; the scanner-wide ASCII-vs-Unicode gap (next slice) will upgrade all helpers
together. The systems-keyword recognition landed in the prior slice is what makes the `scoped` context
word resolve correctly.

**Verified:** added a brace-style `lifetimeSource` corpus (so `InsertIndentationBraces` is a no-op and
it exercises ALL three raw tokenizers + the composed path against `Lexer.Tokenize()`) mixing every
lifetime context (`<'a>`, `<'a, 'b>`, `scoped 'a`, `returns 'a`) with char literals that must STAY char
literals (`'x'`, `'\n'`, escaped quote, and `name 'a` whose preceding word is not scoped/returns), plus
an indentation-style `indentLifetimeSource` (lifetimes + virtual braces + a char literal in one stream).
Full token-stream parity (kind/start/valueLength/line/column + count) holds; targeted test green. An
adversarial differential-fuzz workflow (compiled dogfood DLL vs the real C# `Lexer.Tokenize()` over
many ASCII lifetime/char-literal inputs) confirmed no divergence.

> **Correction:** these two corpora were LOST from this commit — a concurrent review agent reverted the
> test file before commit, so `dc42b0f0` shipped the lifetime kernel + an under-covered test. The
> corpora were RESTORED in the next-dated entry above. The kernel itself was independently validated by
> the differential-fuzz harness, so the port was correct; only the in-suite regression coverage lapsed.

**Remaining lexer gaps:** (a) ASCII-vs-Unicode character classification (whitespace/digits/letters);
(b) a pre-existing `ScanCharLiteral` edge case surfaced by this slice's adversarial fuzz — a char
literal whose body is a backslash immediately followed by a line break (`'\<CR>`): C# `ReadCharLiteral`
guards the escaped-char consumption against EOL, the N# `ScanCharLiteral` does not (pre-existing, from
commits d636e3a2/ff921348, NOT a lifetime-port regression). Both fold into the char-classification /
char-literal parity slice. Then comment-trivia + token-text for a full production N# lexer.

## 2026-06-05 — Phase 1 lexer: indentation tokens + systems-keyword recognition ported to N#

**What:** Two cohesive N# lexer kind-stream parity improvements, plus an adversarial audit that
surfaced (and this slice partly closes) several pre-existing raw-tokenizer gaps.

1. **Indentation tokens.** Ported `Lexer.InsertIndentationBraces` (`src/NSharpLang.Compiler/Lexer.cs:167-266`)
   — the virtual `{`/`}` insertion for indentation-style (brace-free) source — to N#. Until now the N#
   scanner emitted only the *raw* token stream (`TokenizeMetadataInto`), so metadata parity was pinned
   only on explicit-brace corpora where `InsertIndentationBraces` is a no-op.
2. **Systems keywords.** `KeywordKind` now recognizes the five systems keywords the C# lexer emits
   (`Lexer.cs:97-101`): `alloc`→`Alloc(143)`, `allow`→`Allow(144)`, `stackalloc`→`Stackalloc(145)`,
   `unsafe`→`Unsafe(146)`, `scoped`→`Scoped(147)` — appended to the length-gated first-char dispatch,
   so near-miss prefixes (`all`/`scope`/`alloca`) stay `Identifier`. Previously the scanner returned
   `Identifier(0)` for these, so it could not even tokenize the dogfood's own systems-N# source.

**Adversarial audit:** a 4-agent workflow (line-by-line + edge-case + metadata lenses + synthesis,
with 400k-program structural fuzzing and a differential harness against the compiled C# lexer)
confirmed the **indentation post-pass port is faithful** (zero divergences across all fuzz + 92
hand-built cases) and drove out the gap list below. Systems keywords are closed here; the rest are the
next slices.

Added two N# kernels to `CompilerServices/LexerTokenKindScanner.nl`:
- `InsertIndentationBracesInto(...)` — a faithful, zero-alloc (caller-owned-buffer) port of
  `InsertIndentationBraces`, operating purely over the raw metadata arrays
  (kind/start/valueLength/line/column). It tracks an indent stack, explicit-brace depth, and
  paren/bracket depth; opens a virtual `LeftBrace` (ordinal 129) on indentation increase and closes
  virtual `RightBrace` (130) tokens on dedent and at EOF, with the base-indent capture, the
  `Math.Max(0, …)` clamps, the "halfway dedent pops without re-opening" stack walk, and the
  brace-vs-indentation suppression rules matching the C# source statement-for-statement. A virtual
  brace's start offset is derived as `tokenStart - (tokenColumn - 1)` (the trigger token's line start)
  with column fixed to 1 — exactly what the parity test's `TokenStartFromLineColumn` expects.
- `TokenizeMetadataWithIndentationInto(source, …)` — the composed entry: tokenize raw, then run the
  brace post-pass, producing the exact stream `Lexer.Tokenize()` yields on any source **whose tokens
  are already correctly recognized by the raw scanner** (i.e. excluding the gaps below).

**Verification (parity, not a perf-routing slice):** extended
`LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer` with
`AssertTokenMetadataWithIndentationLikeProductionLexer`, asserting full token-stream parity (kind +
start + valueLength + line + column, count included) against `new Lexer(src).Tokenize()`. Coverage:
the composed entry is first proven a correct **superset** on all four existing explicit-brace corpora
(it must equal the raw stream there), then proven on indentation-style corpora that genuinely trigger
insertion — simple single indent, nested indents with multi-level dedent and sibling blocks,
globally-indented source with interior blank lines, paren-continuation + explicit-brace suppression,
CRLF endings, tab indentation, an inconsistent "halfway" dedent, and degenerate empty / whitespace-
only inputs. The count assertion makes the tests non-trivial: if the port inserted nothing while C#
did (or vice-versa) the token counts would differ and the test would fail. For systems keywords, added
a `systemsKeywordSource` corpus asserted three ways (raw kinds, raw metadata, composed) that exercises
each of the five keywords plus near-miss prefixes (`all`/`scope`/`alloca`/`scopes`/`unsaf` must stay
`Identifier`). Targeted test passes; full `CompilerDogfoodProjectTests` class green, including the
`Newline == 136` ordinal-layout pin. Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate run
for the commit.

**Language/compiler findings (Phase 0 audit):** the port compiled on today's N# with **no new gaps** —
confirming the audit's "lexer port is feasible" finding extends to the control-heavy indentation
logic. Specifically exercised and confirmed working: an 11-array-parameter function signature
(previously the widest kernel was 7 arrays), intra-assembly N#→N# calls with internal `new int[](…)`
allocation, `bool` locals with reassignment and logical `!`/`&&`/`||`, nested `while` with `continue`,
mid-loop `return`, and `else if` chains. No principled compiler change was required this slice.

**Architecture note (honest framing):** this is a correctness/parity slice that **advances the N#
lexer's kind-stream** (indentation post-pass), not a production-routing slice. Per the
boundary-profiling finding, the lexer adapter bridge cannot be deleted until its *caller* (the parser)
is also N# and the call inlines in-assembly; routing tokenization through this kernel today would only
add another ~1.2 ns delegate boundary. The indentation logic is written in the fast canonical style
(counted loops, manual int stack, zero per-call allocation in the pure kernel) so it is ready to be
the production lexer once the in-assembly N#→N# parser path lands (Phase 2). No adapter added/removed.

**Audit findings (pre-existing raw-tokenizer parity bugs, NOT in the new indentation code; latent
because no in-tree corpus exercised them):**

- ✅ **Systems keywords (blocker) — CLOSED this slice.** `KeywordKind` returned `Identifier(0)` for
  `alloc`/`allow`/`stackalloc`/`unsafe`/`scoped`; now emits `143/144/145/146/147`. Empirically
  confirmed against the compiled C# lexer and pinned by `systemsKeywordSource`.

**Remaining gaps (the immediate next slices):**

> ✅ Gap 1 (lifetime tokens) was closed in the next-dated entry above.

1. **Lifetime tokens (blocker) — CLOSED (see entry above).** `TokenizeMetadataInto` has no lifetime handling; C# `NextToken`
   (`Lexer.cs:325-328`) calls `IsLifetimeStart()`/`ReadLifetime()` (`Lexer.cs:903-960`) to emit a
   single `Lifetime(142)` token (e.g. `,'a`→`Lifetime`, `,'b1`→`Lifetime`). `IsLifetimeStart` is
   context-sensitive: apostrophe, next char letter/`_`, char-after-next not `'`, AND the nearest
   preceding non-whitespace char is `<` or `,` or the word `scoped`/`returns`. The N# scanner instead
   lexes `'a` as a char literal, diverging on kind AND count. Fix: port `IsLifetimeStart`/`ReadLifetime`
   into the scanner before the char-literal branch — its own slice given the source lookback. **Note:**
   the systems-keyword recognition landed here is a prerequisite for the `scoped`/`returns` lookback.
2. **ASCII-vs-Unicode character classification (major).** The scanner's `IsWhitespaceExceptNewline`,
   `IsDigit`, and `IsIdentifierStart` are ASCII-only, but the C# lexer uses the Unicode-aware BCL
   predicates `char.IsWhiteSpace` (`Lexer.cs:1084`), `char.IsDigit` (`Lexer.cs:336`), and
   `char.IsLetter` (`Lexer.cs:342`). So non-ASCII whitespace (NBSP/NEL/U+2028/U+2029/U+2000–U+200A/
   U+202F/U+205F/U+1680/U+3000 — note C# treats U+0085/U+2028/U+2029 as inline whitespace, not line
   breaks, since `IsAtLineBreak` is `\n`/`\r` only), Unicode letters in identifiers, and Unicode
   decimal digits all diverge (the scanner emits `Unknown(137)` / wrong kinds/columns/count). Fix as
   one coherent slice: ASCII fast-path + BCL-predicate fallback for ch > 127 in all three helpers
   (parity guaranteed by sharing the BCL predicate), with Unicode corpora. **Open audit question:**
   confirm the kernel compile path supports `char.IsWhiteSpace`/`char.IsLetter`/`char.IsDigit` interop
   (the Phase 0 probe verified `char.IsDigit`/`char.IsLetter` standalone; no dogfood kernel calls them
   today — they all hand-roll ASCII checks).
3. **Comment-trivia + token-text** for the formatter (`Lexer.Comments`) and token-text materialization
   (derivable from start+length by the host) — the last pieces to a full production N# lexer.

## 2026-06-05 — Consolidation: dogfood work merged onto `systems-language`

**What:** Consolidated all scattered dogfood worktrees/branches onto the canonical working branch
`systems-language` (which carries the separate "Systems N#" line: memory pools, zero-copy proofs,
ref/lifetime safety, source generators, etc.). Previously the dogfood self-hosting work lived only on
`codex/compiler-dogfood-benchmarks` and a fan of unit branches.

Merged in:
- `nsharp-dogfood-profiling` — the real integration branch: canonical dogfood base (145 commits) +
  accepted/routed units **1** (formatter import ordering), **3** (ProjectFile source filtering),
  **5** (ILCompiler overload selection) + rejection-evidence units **2** (formatter safety scan),
  **4** (analyzer overload-signature distinctness), **6** (declared-type exact-name lookup) + all
  three design docs + the `DogfoodBoundaryOverheadBenchmarks` decomposition benchmark.
- `nsharp-dogfood-unit-7-code-intel-audit` — the audit-only doc section.

**Routed (production) kernels carried in** (unchanged numbers, see metrics doc):
- Formatter import ordering — 6.2× representative / 20.2× large, 0 B.
- ProjectFile source filtering — 25.8× / 26.9×.
- ILCompiler overload selection — 11.3× / 10.9×, 0 B (runs on every declared-method/ctor call).

**Conflicts reconciled (8 core files)** — preserving BOTH systems-language semantics and dogfood
routing:
- `ILCompiler.cs`: kept profiling's routed compact-candidate overload ranking
  (`SelectBestDeclaredMethodCandidate`) **and** systems-language's `HasRuntimeTypeParameters` generic
  detection; kept systems-language's `FinalizeTopLevelEnumTypes` (re-registers baked enums in
  `_enumTypes`/`_typeKeys`) **and** the dogfood `OrderTypeBuildersByDescendingTypeKeyDepth` helper;
  kept systems-language's `EmitExpressionStatement`/`TryEmitAssignmentStatement` lowering (a superset
  of profiling's inline assignment-discard); combined profiling's member-load null-guard with the
  correct `memberOwnerType`.
- `Program.cs`: preserved systems-language's `--systems` template flag on top of profiling's
  `GetFirstPositionalArg` refactor.
- `Program.Backends.cs`: dropped profiling's now-dead `ValidateStrictLintDiagnostics` (systems-language
  moved strict-lint into the compiler via `CompileToIlAssembly(validateStrictLint: true)`).
- `CompilationStubEmitter.cs`, `Analyzer.cs`, `memory/README.md`, `runTest.ts`: additive.

### Limitation found + principled fix: TokenType ordinal coupling

**Symptom:** After a clean (compiling) merge, the full gate hit **63 failures** — formatting gate,
unit tests, example builds, IL verification — all braced N# source failing to parse with
"Unexpected token newline in expression."

**Root cause:** The systems-language line inserted six token types (`Lifetime`, then
`Alloc`/`Allow`/`Stackalloc`/`Unsafe`/`Scoped`) into the **middle** of the `TokenType` enum. The
production-routed dogfood kernel `ParserTokenCompactionIndicesInto`
(`src/NSharpLang.Compiler.Dogfood/CompilerServices/LexerTokenKindScanner.nl`) — reached from the
`Parser` constructor via `NSharpCompilerDogfoodAdapter.TryCompactParserTokens` — filters newline
tokens by the **hard-coded integer ordinal 136**. The insertions shifted `Newline` from 136 to 142,
so the kernel filtered the wrong token type and left stray newlines in the parser's token stream.
This is the dogfood kernels' ordinal-coupling fragility surfacing through a real enum change.

**Fix (smallest principled change):** Restore the kernels' ordinal contract by appending the six new
token types at the **end** of `TokenType` (they are referenced only by name in C#, never by ordinal).
Documented the load-bearing ordering on the enum, and added an explicit guard test
`ParserTokenCompactionParityRespectsTokenTypeLayout` pinning `(int)TokenType.Newline == 136` so any
future mid-enum insertion fails loudly at the C# test layer instead of silently in production.

**Follow-up debt (tracked, not yet done):** The dogfood `TokenType`-ordinal kernels remain coupled to
a fixed enum layout. The more robust long-term fix is to pass ordinal constants (e.g. the newline
kind) into the kernels as data rather than baking them — decoupling kernels from enum layout entirely.
Deferred to avoid widening the binding/benchmark/test surface during consolidation; the guard test +
enum comment prevent silent recurrence in the meantime.

**Verification:** `format --project examples --check` → "All files are properly formatted"; targeted
re-run of the previously-failing classes (`CompilerDogfoodProjectTests`, `StructCopyEliminationTests`,
`AnalyzerBindingMapTests`) → 42/42 pass.

### Limitation found + principled fix: short-circuit `&&`/`||` codegen vs C#

**Symptom:** After the ordinal fix the full gate had exactly one remaining failure — the Systems
BenchmarkDotNet gate (`SystemsFastGateBenchmarks`), `HotResultCombinations` scenario, N# at
~1.01× the C# baseline (zero-tolerance gate; N# must be ≤ C#).

**Root cause (verified by emitted-IL diff vs pre-merge `84dda83`):** the merge correctly brought in
the dogfood branch's short-circuit `&&`/`||` lowering (commit `b4a873e "Fix IL primitive operator
semantics"`, with the `ILCompiler_LogicalOperatorsShortCircuit` test). Pre-merge systems-language
lowered `&&`/`||` **eagerly** (`clt; cgt; or; brfalse` — one branch) which is a *latent correctness
bug* (the right operand is always evaluated). The IL diff showed only `scanDigits`,
`scanAndChecksumDigits`, `copyDigits` changed — each a hot loop with `if value < 48 || value > 57`.
The materializing short-circuit helper (`EmitLogicalOr`) added `ldc.i4.0`/`ldc.i4.1`/`br`
boolean-materialization and a second branch; RyuJIT compiles the equivalent C# range check
(`value < 48 || value > 57`) to a single branch, so correct-but-two-branch N# lost by ~1–2%.

**Fix (compiler self-improvement — explicitly in scope):** added a short-circuiting
`EmitConditionBranch(condition, target, branchIfTrue)` used by `EmitIf`/`EmitWhile`/`EmitFor`. It
lowers `&&`/`||`/`!` to branches taken directly against the target labels (no boolean
materialization), and:
- **fuses** integer relational comparisons with their branch into one
  `blt`/`bgt`/`ble`/`bge`/`beq`/`bne.un` opcode (gated to integral operands, where the relational
  inverse is exact — no NaN/unordered hazard);
- **eagerly** evaluates `a && b`/`a || b` as `left; right; and/or; br` (a single branch) ONLY when
  both operands are provably pure and non-throwing (an integer comparison whose leaves are integer
  locals/params or integer/char literals) — observably identical to short-circuit but one branch
  instead of two, matching the JIT-folded C# shape.

Side-effecting operands (calls, member access, indexing, division) still short-circuit, so
`ILCompiler_LogicalOperatorsShortCircuit` and the operator-matrix/IL-shape suites pass (100/100 on
the targeted run). After the fix the emitted IL for the hot loops is *smaller* than pre-merge's, and
`HotResultCombinations` measures **0.99×** (N# faster), so the benchmark gate passes. This is a net
codegen quality improvement for every `if`/`while`/`for` condition in the language.

**Verification:** Systems BenchmarkDotNet gate passes (all 6 scenarios ≤ 1.00, HotResultCombinations
0.99); 100/100 targeted short-circuit/operator/control-flow tests pass. Full
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` re-run pending.

---

## 2026-06-05 — Lever 3 codegen: `array.Length` → `ldlen` for SZ arrays

**What:** `EmitMemberAccess`/`EmitMemberLoadValue` lowered `array.Length` on a single-dimension
zero-based array (`IsSZArray`) to a non-virtual `call Array.get_Length()`. Replaced with the canonical
`ldlen; conv.i4`. Strings, `Span<T>`, and multidimensional arrays are unaffected (not `IsSZArray`).

**Why (boundary-profiling Lever 3):** `ldlen` is the form the JIT's bounds-check elimination
pattern-matches, so an `array.Length`-bounded counted loop (`for i := 0; i < a.Length; i++ { a[i] }`)
now emits the same shape C# does and the JIT elides the `ldelem` bounds check.

**Evidence (direct micro-benchmark, 4096-int sum, 2M iterations, identical checksums):**

| N# array.Length form | N# / C# ratio | IL size (`sumArray`) |
|----------------------|---------------|----------------------|
| `call get_Length` (before) | 1.003× (slightly slower) | 33 B |
| `ldlen; conv.i4` (after)   | **0.999× (parity)** | 30 B |

Modest but real: moves the canonical counted array loop from marginally-slower to parity with C#,
meeting the "never slower than C#" bar, with smaller and canonical IL. 537 array/length/span/string/
loop tests pass; parity is guaranteed (same value). Benefits every `array.Length`-bounded loop,
including the array-heavy dogfood kernels.

## 2026-06-05 — Phase 0 audit kickoff: lexer feature surface + N# interop readiness

Per [`roadmap-to-done.md`](roadmap-to-done.md), began the language-completeness audit by scoping
the **lexer** beachhead (`src/NSharpLang.Compiler/Lexer.cs`, 1150 LOC). Its dependency surface:
`string` indexing, one `Dictionary<string,TokenType>` (keywords), `List<Token>` (output), 13
`StringBuilder` uses (token text), one `Stack`/indentation, 15 `char.Is*` calls, 14 `switch`, the
`Token` record, the `TokenType` enum. No LINQ.

**Finding — a correct lexer port is feasible on today's N#.** N#'s C# interop already covers every BCL
dependency. Verified by compiling AND running an N# probe that uses `new StringBuilder()` +
`Append`/`ToString`, `new Stack<int>()` + `Push`/`Pop`, `char.IsDigit`/`char.IsLetter`, and
`new Dictionary<string,int>()` + indexer + `ContainsKey` (output `hi 2 True True True`). Examples
already use `List<T>`, nested `Dictionary<...>`, collection expressions, records, enums, and `switch`.

**Open work for the port (not feasibility, but the "super fast" bar):**
- Decide BCL collections (mechanical, allocates) vs **systems-native pooled/zero-alloc** `Token`/
  `TokenStream` for the hot path — the latter is what makes the migrated lexer dramatically faster.
- Confirm full trivia / indentation-token / diagnostic / source-position parity in N#.
- The keyword table: prefer the existing first-character dispatch (already proven in the dogfood
  scanner) over a `Dictionary` lookup on the hot path.

**Finding 2 — the existing N# lexer scanner is production-close.** `LexerTokenKindScanner.nl`
(1573 LOC) already emits full per-token metadata (kind, start, value length, line, column) for
identifiers, separated int/hex/binary/float numbers, string/raw/interpolated/char literals, the full
operator set, and keywords, and it excludes comments from the stream exactly as the C# lexer does.
Pinned with a new representative-corpus parity test in `CompilerDogfoodProjectTests`
(`AssertTokenMetadataLikeProductionLexer`) over a single source that combines line/doc/block comments,
string + interpolated + char literals, separated numeric literals, a wide operator set, and keywords —
it matches the production `Lexer.Tokenize()` token stream exactly (count + kind + start + length +
line + column), and the compaction parity holds too.

**Remaining gaps to a full production N# lexer** (narrower than first thought): indentation-token
insertion for indentation-style (brace-free) source, comment-trivia collection for the formatter
(`Lexer.Comments`), and token-text materialization (derivable from start+length by the host). Token
*kind/position* parity — the hard part — is already met on realistic code.

Next slice: cover indentation-token insertion in the N# scanner (the main remaining kind-stream gap),
or stand up the N#-native pooled `Token`/`TokenStream` so the parser can consume N# tokens directly
(removing the host materialization boundary). Record any language gap here and close it principled.

> **Update (newest entry above):** indentation-token insertion is now DONE and verified faithful.
> BUT the adversarial audit of that slice surfaced three pre-existing raw-tokenizer parity gaps
> (systems keywords, lifetime tokens, Unicode whitespace) that the old "kind/position parity is
> already met on realistic code" claim missed — they were latent only because no corpus exercised
> them. See the newest entry's "Gaps surfaced" list; those are the immediate next slices.

## Bootstrap coverage

- **0%** — no compiler source is yet compiled by the N# compiler itself. The dogfood kernels are
  N#-authored compiler *services* compiled through the normal `NSharpLang.Sdk` path and bound via the
  `*DogfoodAdapter` delegate boundary; this is the pre-bootstrap stage. The endgame (per the boundary
  profiling doc) is removing those delegate boundaries via in-assembly N#-to-N# calls.

## Adapters (debt to shrink toward zero)

- `NSharpCompilerDogfoodAdapter`, `NSharpCodeIntelligenceDogfoodAdapter`,
  `NSharpPerformanceDogfoodAdapter`, `NSharpCliDogfoodAdapter` — all still present as temporary
  transition boundaries. None removed yet. Each routed kernel still crosses the ~1.2 ns
  delegate-dispatch + bounds-check floor documented in the boundary profiling doc.

# Roadmap to Done — complete N# compiler and tooling

The standing execution plan. Work this top-to-bottom autonomously, but keep the objective narrow and concrete:
**WRITE THE N# COMPILER AND COMPILER TOOLING COMPLETELY.** Living evidence in
[`self-host-progress.md`](self-host-progress.md), [`columnar-pipeline.md`](columnar-pipeline.md),
[`systems-vs-native.md`](systems-vs-native.md).

## Current objective

N# owns the compiler and compiler tooling. That means parser, symbol tables, semantic model, diagnostics,
IL lowering, compiler-service APIs, and the `nlc` command logic (`check`, `fix`, `query`, `format`, `lint`,
`build`, `run`, `test`) move out of transition-era C# and into N#/columnar implementations where they are not
true host boundaries.

- C# remains only for CLR/BCL host boundaries, bootstrap loading, MSBuild/VS Code/LSP glue, public .NET object
  materialization, or a measured fallback while an N# implementation has not cleared parity and the required
  performance gate.
- Every C#-side change must identify itself as exactly one of: `host-boundary`, `oracle-bug`,
  `pre-emission-safety`, `temporary-SoA-proof`, or `C#-surface-shrink`. If it is none of those, it is not roadmap
  progress.
- SoA is an emitter-port/table-migration proof until a real compiler table moves onto it. Do not add more
  hard-cast/checked/Array/ref-out permutation pins unless they block a named product compiler migration or close
  a currently accepted invalid-IL path.
- Parity-only probes stay in parity fixtures/corpora. They do not route product traffic and do not count as
  product compiler ownership.
- Process, gate, and documentation-only work is subordinate to compiler/tooling implementation. Do it only when
  it directly preserves the compiler migration path or records a completed implementation change.

## Operating contract (how this gets executed)

- Execute this roadmap top-to-bottom, **one verified + committed slice at a time**, without pausing for
  approval between slices. After a slice lands, take the next item automatically.
- Every implementation slice: build → the narrowest relevant focused evidence (`./scripts/dev.sh <pattern>`,
  `./scripts/dev.sh --since`, or a targeted `dotnet test --filter ...`) → commit. Use
  `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` only at integration checkpoints: before merge/push/handoff,
  after broad shared compiler changes, after SDK/runtime/build-script/package changes, after benchmark-gate
  changes, or when focused evidence is ambiguous. IDE/LSP/VS Code changes must run the VS Code-enabled gate and
  be visually verified in VS Code.
- New non-trivial compiler logic still needs correctness/parity evidence and review-level adversarial thinking.
  No shortcuts, no faked parity, no weakened tests, no regressions. A failed gate that is a known thermal flake
  (HotResultCombinations ≈1.0×, systems compile/build-perf tests) is re-run cool and serially, not worked around.
- **Decompose large efforts into verified sub-slices** (e.g. vectorization codegen = detection → single-lane
  emission → unrolling → widen types → default-on). Never defer a large item wholesale to "a future session."
- **Surface to the user ONLY for:** (a) a genuine architectural fork this roadmap does not pre-decide where a
  wrong choice wastes major work; (b) a hard blocker (a decision/credential only they can give); (c) the
  roadmap is complete. Progress itself is reported by the commits + the progress log, not by stopping.
- **Hands-off mode:** the user runs `/loop` so I am re-invoked to keep taking the next slice while they are
  away. Otherwise I continue turn-to-turn. Either way the contract is the same.
- Keep this doc current: check items off, add discovered work, record the real numbers.

## Definition of DONE

1. **Compiler/tooling complete:** parser, symbol model, semantic model, diagnostics, IL lowering,
   compiler-service APIs, and `nlc` command logic are production-quality, schema-stable, and owned by N#/columnar
   code except for explicit host boundaries.
2. **C#-free product core:** the C# binder/analyzer/codegen and the `*DogfoodAdapter` bridges are deleted or
   reduced to documented host/fallback edges. Only AGENTS.md-permitted CLR/BCL, bootstrap, MSBuild, VS Code/LSP,
   and public-object materialization boundaries remain in C#.
3. **Rust-class perf:** systems-N# generated code is within ~2× of Rust/C on the vectorizable hot kernels
   (checksum-sum, count-ascii) and ties-or-better elsewhere; the SystemsFastGate never-regress bar holds.
4. **Top-of-class developer tooling:** LSP/CLI operate on semantic data instead of grep-shaped shortcuts;
   JSON schemas are versioned and stable; diagnostics are product-quality; docs current.

## End deliverable — what "done" ships

A dynamic workflow spawns many short-lived `nlc` invocations; cold-start latency and reliability dominate.
The finished product is:
1. **AOT single-binary `nlc`** — `PublishAot` the CLI (and keep it AOT-clean as subsystems migrate; the
   systems AOT/readiness reporting helps here). Eliminates JIT warmup → millisecond cold starts.
2. **LLM-first CLI** — the versioned `nlc query` JSON toolchain: stable, schema-versioned JSON for
   check/fix/query/diagnostics so an agent has the same power as VS Code.
3. **Daemon/fast-path** for repeated invocations in one workflow (warm compiler, incremental).
4. **Deterministic, hermetic builds** (project.yml-first, single SDK reference) so a workflow can
   `nlc new`/`build`/`run`/`test` with no environment surprises.

The fast self-hosted compiler (Phase S) + AOT packaging is what makes N# genuinely snappy for agents.

## Phase S — Self-host (eliminate C# reliance)

- [x] Parser kernels parse 100% of own systems source (slices 1–24); 2.4× faster than C# unmaterialized
- [x] Routing-via-materialization proven a dead end; columnar pipeline chosen (slices 25–27)
- [x] Stage 1 — columnar declared-symbol model
- [x] Stage 2 — columnar name resolution
- [x] Stage 3 — columnar type checking (expression inference; reviewed against the real binder; binder/output
      parity deferred to stages 4-5). Surfaced two C# binder ECMA gaps (fixed below).
- [x] **Binder reconciliation** (correctness improvement surfaced by stage-3 adversarial review): the C#
      binder (Analyzer.cs) now concretely types built-in bitwise binary ops (`& | ^ << >>`) and applies
      numeric promotion to unary `-`/`~`; `ColumnarTypeLattice` was updated to the same promoted types and
      re-verified against analyzer semantic-model coverage, declared operator-overload coverage, and the
      columnar type-inference parity corpus.
- [x] **Stage 3b — columnar diagnostics** (pure-structural: definite-return, unreachable-after-terminal,
      unused-local). Parity vs the C# analyzer. **COMPLETE** — all three sub-slices below landed, each
      parity-gated vs a C#-AST mirror on hand-built cases + the 29-file shipped product corpus and adversarially verified.
      - [x] **3b-i definite-return (NL305)** — `ColumnarDiagnosticsPass.StatementAlwaysReturns` is the columnar
        subset of `Analyzer.StatementAlwaysReturns` (Return exits; Block exits if any stmt exits; If exits only
        with an else where both branches exit; Break/Continue/ExprStmt/VarDecl/While non-exiting). The kernel
        refuses throw/switch/try/wrapper forms, so the subset is faithful by construction; omitted return type =
        void (matches `Analyzer.cs:621`). Async/generator functions carry the `isAsyncUnitTask`/`isIterator`
        exemptions (BCL task-type knowledge the pass can't model) → the parity harness DECLINES those sources to the C#
        analyzer (corpus has none, so zero coverage loss). Parity-tested vs a C#-AST mirror + exact expected
        diagnostics on 7 hand-built cases, and on the 29-file shipped product corpus (mirror parity + ZERO
        false-positive NL305 on valid self-host source). Adversarially verified (the review caught the async
        unit-task divergence; fixed + regression-tested).
      - [x] **3b-ii unreachable-after-terminal (NL312)** — `ColumnarDiagnosticsPass.CollectUnreachable` mirrors
        `Analyzer.AnalyzeStatements`: within a statement list, once a statement always exits, the immediately
        following statement is reported unreachable (once, then the list is skipped), recursing into nested
        blocks / if-branches / while-bodies exactly as `AnalyzeStatement` does. Reported position is the
        statement's `line:col`, resolved from the tokenizer's own per-token line/col (a byte-offset→position map
        in the parity harness) — empirically equal to the AST `Statement.Line/Column` (the exact-parity test would fail
        otherwise). Parity vs a C#-AST mirror on 6 hand-built cases (incl. only-first-reported, nested, and the
        unreachable-before-missing-return ordering) + zero unreachable on the 29-file shipped product corpus. Adversarially
        verified (clean — no divergence).
      - [x] **3b-iii unused-local (NL001)** — `ColumnarDiagnosticsPass.CollectUnusedLocals` walks the body in
        SOURCE ORDER, faithful to the Linter's time-/scope-ordered NL001 (a first naive "global" attempt was
        reverted — see `fe61aa51`). The parity harness processes functions in source order sharing one `usedNames` set
        that accumulates every identifier use (the file-level `_usedVariables` analog), seeded with each
        function's params and NEVER cleared between functions; each Block's `:=` locals are checked at the
        Block's exit against `usedNames` AS OF THEN — so a use after the block closes (later sibling block / later
        function) does NOT suppress, while an earlier use does. Discards (`_`/`_`-prefixed) exempt; params always
        used; assignment-target counts as a use; interpolated strings decline upstream (kernel refuses `$"..."`).
        Parity vs a C#-AST mirror reproducing the exact ordering on 9 hand-built cases (both ordering directions,
        nesting, assignment, discard) + the 29-file shipped product corpus. Adversarially verified (the prior global rule's
        divergence is fixed; APPROVE, clean).
- [~] **Stage 4 — columnar codegen.** Emit IL directly from the columnar + resolved tables for the systems
      subset; compile a trivial then a real dogfood function with NO C# AST. Parity: emitted IL runs identically
      to the C# path (same outputs); IL-verification gate green.
      **NOTE (2026-06-08): the emission-seam scoping below is SUPERSEDED** by the Stage 4j ROUTING decision
      (standalone columnar pipeline, NOT re-parse-in-`ILCompiler`) — kept for history. The columnar emitter
      grows as its own backend; it does not reuse `ILCompiler`'s `ILGenerator`.
      **SCOPED (read-only Explore workflow, 2026-06-07).** Emission seam: REUSE the existing
      `ILGenerator` (`ILCompiler._currentIL`) — it is already AST-decoupled — via a SEPARATE columnar dispatcher
      (`EmitColumnarBody`/`EmitColumnarExpression`) that switches on columnar node kinds and calls the same
      low-level emit helpers (`EmitLoadArgument` ~9590, `EmitInt32Constant`, `_currentIL.Emit(OpCodes.Add)`,
      `_currentIL.Emit(OpCodes.Ret)`), populating the context dicts (`_parameters`/`_parameterTypes`/
      `_currentReturnType`/`_locals`) from columnar data — no AST materialized. Key methods: `Compile` ~10108,
      `DeclareFunction` ~10480, `EmitFunctionBody` ~10783, `EmitExpression` ~13573, `EmitBinaryExpression` ~15436,
      `EmitReturn` ~11858. Data is ~80% sufficient from stages 1–3; gaps for the trivial case: CLR `Type` from a
      canonical string (hardcode builtins / reuse `ResolveType` ~8000), param ordinal (= index in the signature),
      local slots (assign in source order at `:=`); calls/method-tokens (`_methods` ~10593) and `External` types
      deferred. Parity gate: route columnar-emitted method → `Assembly.Load` → invoke vs the C# path oracle (same
      pattern as `NSharpCompiledMethod.Bind`), assert equal across inputs + ilverify green. Decompose:
      - [x] **4-spike DONE** — `Columnar/ColumnarIlEmitter.cs` plus the original adapter spike emitted a real
        one-method assembly whose body IL came straight from the columnar tables; the test LOADS + INVOKES it.
        That spike entry has since been retired in favor of the production-shaped `TryEmitColumnarProgram` route.
        Proven end-to-end for INT-ONLY top-level funcs: param load, int literal, paren, and int `+`/`-`/`*`
        binary (incl. nested left-assoc + multi-param) — `identity(42)==42`, `add(2,3)==5`, `poly(3,4,5)==7`,
        `(a+b)*b`, `a-b-c`. Folds in 4a (binary) + 4f (int literals) for the int subset. Self-contained
        (`PersistedAssemblyBuilder.Save` → `Assembly.Load`), no `ILCompiler` changes, declines every unsupported
        form (locals, if/while, calls, non-int, value-less return, multi-func) → C# path unaffected.
        Adversarially verified (decline-safety strong; the one edge — value-less int return — fixed + tested).
      - [x] **4d locals DONE** — `:=` int locals: the emitter declares an int local (`DeclareLocal`), emits the
        initializer then `stloc`, and identifiers resolve to a local (`ldloc`) before a param. A local that
        shadows a parameter or redeclares a local DECLINES (N# treats shadowing as a diagnostic; the spike keeps
        the C# analyzer authoritative). Invoke-tested: chained locals (`y := x * 2`), local+param mixes; declines
        shadowing, redeclaration, and assignment statements (`x = …`, kind 23 — not handled yet). Adversarially
        verified (the review caught the param-shadow gap; fixed + tested).
      - [x] **4g if/else DONE** (first cut) — `if`/`else` where BOTH branches always return (no fall-through →
        no merge-label/trailing-`ret` subtleties): `EmitCondition` (brfalse) + emit each branch (each ends in
        `ret`). Conditions are an int comparison only (`< > <= >= == !=`; the negated ones via `cgt/clt` + `ceq 0`),
        so a bool can't leak into an int value/return. Invoke-tested: `max` (`>`), `absish` (`>=`, `0 - a`), nested
        `sign`. Declines: if-without-else, a fall-through branch, a non-comparison condition, a comparison in value
        position, and unreachable code after a return (an NL312 case — the review caught that the Block emitter
        emitted past a `ret`; fixed: a returning statement must be last in its block).
      - [~] **4b types beyond int** — [x] **4b-i TYPE-AWARE emitter + bool DONE**: `EmitExpression(out Type)`
        reports each expr's CLR type; Return/`:=`/assignment/Binary/Call all type-check (no implicit conversions;
        per-arg type check vs callee params). bool: literals, comparisons-in-value (`EmitComparison`), logical `!`,
        bool params/locals/returns, bool conditions. Int subset proven behavior-preserving first, then bool added;
        parity-gated (`ColumnarCodegen_Parity_BoolType`) + declines `&&`/bool-from-int/bool+int/wrong-arg-type.
        Adversarial review (ship-with-nits) caught the call-arg-type gap bool introduced → fixed + tested. · [x]
        **4b-ii `long` DONE** (i8: `5L`→`ldc.i8` via the preserved lexer suffix; arith/cmp/unary reuse int opcodes
        on i8; long params/locals/returns; mixed int/long widening declines. First distinct stack rep, so the
        per-arg type check now genuinely prevents i4-where-i8 invalid IL. Parity-gated incl. values > int range
        — `1e9*1e9`, `factL(20)` — + ulong/mixed declines) · [x] **div/mod DONE** (int/long `/`→`Div`, `%`→`Rem`
        signed; parity-gated w/ negatives + large long) · [x] **bitwise/shift DONE** (int/long `& | ^`→And/Or/Xor,
        `<< >>`→Shl/Shr signed; shift count is int; parity-gated w/ negative `>>` sign-extend, `1L<<40`, flag idiom)
        · [x] **4b-iii `double` DONE** (`ldc.r8`; FP arithmetic/rem/negate; int/long casts; `double[]`;
        NaN-correct comparisons via unordered complements; parity-gated over NaN, infinities, signed zero, and
        casts) · [x] **4b-iii-a `float` DONE** (`ldc.r4`; FP arithmetic/negate; casts incl. float↔double;
        `float[]`; same NaN comparison contract) · [x] **4b-iv `string` DONE** (`ldstr`, `Length`,
        `get_Chars`, `String.op_Equality`, `String.Concat`, interpolation, escapes, `StringComparison`
        `IndexOf`, `Substring`, scalar `.ToString()`, and the current string BCL whitelist; parity-gated by
        `ColumnarCodegen_Parity_StringBasics`, `StringMethods`, `CharAndStringIndex`, `StringComparisonAndIndexOf`,
        `StringInterpolation`, `StringEscapes`, and `StringBclWhitelist`). · [x] **4c parity-vs-C#-path
        harness DONE** (`ColumnarCodegen_Parity_MatchesCSharpPath`: compile each eligible fn via BOTH the columnar
        path AND `MultiFileCompiler`→`ILCompiler`, invoke over many inputs incl. negatives/boundaries/overflow,
        assert identical; 15 fns. Caught + fixed TWO latent C# codegen bugs of one class — `EmitIf` both-arms-return
        and `EmitSwitch` all-cases-return both emitted a `br` to a label marked at method-end → ilverify
        `MarkPredecessorWithLowerOffset` crash / JIT `InvalidProgramException` *on invoke*; gated by the new
        `StatementCompletesNormally`. Two columnar-independent regression tests added. Unifying the spike into a
        single production dispatcher folds into 4j routing.) · [x] **4f simple assignment statements DONE** (`local =
        expr` to a `:=` local: emit value, `stloc`; compound `+=`, param targets, and non-identifier targets
        decline). Surfaced + fixed a latent bug: an int body that does not return on all paths (NL305) emitted IL
        with no final `ret` — now the body must always-return or the source declines. · [x] **4h while loops
        DONE** (the first general fall-through control flow): `check: cond; brfalse end; body; br check; end:` —
        stack-empty at both merge labels. Added BLOCK SCOPING (a `:=` leaves scope at its block end; the while
        also scopes a braceless single-statement body), so a loop-body local referenced after the loop declines
        rather than reading a possibly-unassigned slot. Invoke-tested: count/sumTo/fact accumulation loops, a
        loop-body-scoped local used within. Declines a degenerate (always-returning) body + both leak shapes. ·
        [x] **4e unary DONE** (int prefix `-`→`neg`, `~`→`not`; `!`/`++`/`--` decline; invoke-tested neg/bnot/
        nested) · [x] **4g if/else COMPLETE** (kind 27 unified into one general fall-through-merge algorithm
        covering all four then/else fall-vs-return combos: `cond; brfalse else; then; [br end iff then falls
        through]; else; [end:]`. The skip-`br`/`end` are gated on then-falling-through — the EmitIf fix carried
        into the columnar emitter; the always-returns gate keeps the merge off the bare method end. Both-return
        `max`/`sign` unchanged. Parity-gated across the full state space incl. nested/while-last/while-mid merge
        positions and braceless guard locals scoped) · [x] **4-multi DONE** — multi-function emission: emit EVERY
        top-level func into one assembly (type "ColumnarProgram") via a two-pass declare-then-emit
        (`ColumnarIlEmitter.TryEmitColumnarAssembly` + adapter `TryEmitColumnarProgram`); the whole program
        declines if any func is ineligible. Two-pass (declare all methods, then emit bodies) is the foundation
        for sibling calls. Parity-gated (`ColumnarCodegen_Parity_MultiFunction`). · [x] **4i sibling calls DONE**
        (columnar Call kind 9: bare-identifier callee resolved in the pass-1 sibling map → `call` the declared
        MethodBuilder; arity-checked, int args left-to-right; declines shadowed/overloaded/delegate callees.
        Forward references + self/mutual RECURSION work via declare-first. Parity-gated: nested call, `fact`,
        `fib`, mutual `isEven`/`isOdd`) · [x] 4b primitive types beyond int (bool/long/double/float/string via the
        builtin map + type-aware emission).
- [~] **Stage 4j ROUTING — STANDALONE columnar pipeline (user decision 2026-06-08; NOT re-parse-in-ILCompiler).**
      Grow `TryEmitColumnarProgram` into a `ColumnarCompiler` parallel to the C# `ILCompiler` that OWNS
      parse→bind→analyze→codegen→assembly from columnar tables with NO C# AST. This SUPERSEDES the 2026-06-07
      re-parse-in-`ILCompiler` scoping above — that path needs source threaded into the AST-only `ILCompiler`
      plus a redundant second parse (the columnar kernels parse source; `ILCompiler` has no source access), so
      it was rejected. Flagged off; the C# pipeline stays default until parity + never-slower are proven
      end-to-end. See memory `project_routing_standalone_columnar_pipeline`.
- [x] **Stage 5 — end-to-end route.** Compile the dogfood corpus through the standalone columnar pipeline with no
      internal materialization; behind a flag, then default-on once never-slower + parity proven end-to-end.
      **FIRST FILE PROOF (2026-06-08; now retained as rejected-probe evidence):** `FormatterSafetyScan.nl`
      originally compiled end-to-end by the columnar backend with NO C# AST, all 3 functions parity-matched to
      the C# pipeline. Its production-shaped benchmark later missed the speed gate, so the formatter scan moved
      to `NSharpLang.Compiler.Dogfood.ParityCorpus` and no longer counts as shipped product routing evidence.
      The parity-corpus test still compiles the extracted scan to keep the historical int[]/long[]/short-circuit
      coverage live without routing `Formatter.FormatSafe` through N#.
      **PRODUCTION ROUTING LANDED (2026-06-08; default-on 2026-06-13):** the columnar backend is wired into `MultiFileCompiler.
      CompileToIlAssembly` by default, with `NSHARP_COLUMNAR_BACKEND=0` as the explicit C#-backend opt-out and
      C# fallback on decline —
      flag-on emits an eligible program via the columnar pipeline (drop-in: assembly name + type `Program`),
      proven to differ from the C# IL yet run identically (`Stage5_ColumnarBackend_*`). Product corpus coverage
      is now **36/36 shipped compiler-service files via MULTI-FILE merge**. The ratchet enumerates
      `src/NSharpLang.Compiler.Dogfood/CompilerServices/*.nl` directly, requires at least 36 product files, emits
      all of them together through `ColumnarCompiler.TryEmitProgramMultiFile`, and pins a loadable assembly with
      at least 429 methods. Single-file eligibility is no longer the product-routing metric: parser and semantic
      kernels legitimately call sibling kernels, so the meaningful product proof is full-corpus merged emission.
      Rejected probes and flattened compatibility wrappers live only in
      `NSharpLang.Compiler.Dogfood.ParityCorpus` (37 files at this checkpoint) and do not inflate product routing
      evidence. Historical Phase A coverage before the parity extraction was driven by SourceTextLines via
      `Array.Fill` + void-call statement + parameter assignment; PathMatching via char arithmetic; LinterImports
      via discarded-call statement; CliDocOrdering via `new string(char[],int,int)`; CliQueryParsing via the
      `ulong` unsigned scalar + `BitOperations.PopCount`; LexerTokenKindScanner via lowercase `char.` static
      predicates; DiagnosticDeduplication via void functions; IdentifierSpans via while-scan-loop;
      CompletionReceivers via StringBuilder; CliArguments via StringComparison enum + IndexOf overloads +
      char/int promotion; DiagnosticClusters via Math.Abs + int.ToString("x") (value-type instance) + string
      concat + String.Compare(3/6-arg) + Trim + StringBuilder-as-param; SemanticScopes via the implicit-void
      return type (`func f(...) {`). Multi-file production routing LANDED 2026-06-08
      (`TryEmitWithColumnarBackend` routes >1 source through the merge).
      **NEVER-SLOWER MEASURED 2026-06-08** (`ColumnarBackendEmitBenchmarks`, same production entry, flag toggled):
      columnar emit is end-to-end TIED-to-marginally-faster vs C# `ILCompiler` (Representative 3.947 vs 3.963 ms;
      LargeGenerated 21.193 vs 21.520 ms; identical alloc) — never slower, but only ~0.4–1.5% because the SHARED
      parse+analyze dominate the total. The default-on flip is now complete with the C# path retained as the
      `NSHARP_COLUMNAR_BACKEND=0` opt-out; remaining self-host work is columnar-owned analysis and the Stage 6
      C# surface shrink.
- [~] **Stage 6 — delete C#.** Remove the C# binder/analyzer/codegen paths the columnar pipeline replaces;
      shrink/remove the `*DogfoodAdapter` bridges. Track C# LOC deleted. **Current cursor (2026-06-16):**
      route-all/default-on has landed, including the Phase-P vectorization port and IF-2 residuals; the C#
      backend remains as the explicit `NSHARP_COLUMNAR_BACKEND=0/false` fallback and as the parity oracle.
      **Current directive (2026-06-18):** Stage 6 is about compiler/tooling ownership, not broadening the C#
      analyzer or building a SoA conformance matrix. A valid Stage 6 slice must do at least one of these:
      delete/shrink a transition surface, route a real compiler/tooling product path through N#/columnar code,
      close a currently accepted invalid-IL path before emission, or fix a C# oracle bug proven by product
      parity. SoA-only work is paused unless it is the named blocker for migrating an actual compiler table or
      for rejecting an accepted invalid-IL product path.
      The active blocker is no longer rich-language route coverage. It is replacing transition-era C# surface
      only where columnar ownership is complete, and proving the emitter-port table model before moving hot
      compiler tables. The production emit entry has moved from `NSharpCompilerDogfoodAdapter.TryEmitColumnarProgram*`
      to `ColumnarCompiler.TryEmitProgram*`, and typed `ColumnarProgramInput` construction now lives beside the
      columnar backend in `ColumnarProgramInputBuilder` instead of the general compiler adapter. Parser-token
      compaction now lives beside `Parser` in `ParserTokenCompactor`, and project source filtering now lives beside
      `ProjectConfig` in `ProjectSourceFileFilter`; formatter import ordering now lives beside `Formatter` in
      `FormatterImportOrderer`; source-file dedup and stub namespace ordering now live beside their compiler/stub
      consumers in `SourceFileDeduplicator` and `CompilationStubNamespaceOrderer`, and analyzer exhaustiveness
      selection now lives beside `Analyzer` in `AnalyzerExhaustivenessSelector`; anonymous-union shim eligibility
      and overload candidate ranking now live beside IL emission in `AnonymousUnionShimSelector` and
      `OverloadCandidateSelector`, and declared-type lookup/order/dedup now lives beside IL emission in
      `ILTypeTableSelector`. AOT requirement grouping and struct-copy readonly gating now live beside compiler
      performance consumers in `AotRequirementSelector` and `StructCopyInitOnlySelector`. The source
      `NSharpCompilerDogfoodAdapter`, `NSharpPerformanceDogfoodAdapter`, and `NSharpCliDogfoodAdapter`
      types have been deleted. CLI query
      symbol-name filtering now lives beside `QueryCommand` in `QuerySymbolNameFilter` instead of the broad CLI
      adapter, and `nlc check`/`nlc lint` compiler-error severity filtering now lives beside the command
      implementations in `CompilerErrorSeverityFilter`; batch query duplicate-id validation and packed
      success counting now live beside `BatchQueryRunner` in `BatchQueryKernels`; unified-diff hunk range
      construction now lives beside `UnifiedDiff` in `UnifiedDiffHunkRangeBuilder`; fix safety/skipped/applied
      grouping routes now live beside `FixCommand` in `FixCommandKernels`; clean option summary now lives beside
      `CleanCommand` in `CleanCommandKernels`, and clean artifact directory ordering now lives beside
      `CleanCommand` in `CleanArtifactDirectoryOrderer`; env option summary now lives beside `EnvCommand`
      in `EnvCommandKernels`; doctor option summary now lives beside `DoctorCommand` in
      `DoctorCommandKernels`; audit option summary now lives beside `AuditCommand` in
      `AuditCommandKernels`; init option summary now lives beside `InitCommand` in
      `InitCommandKernels`; update all-NuGet and target-package
      dependency filtering now lives beside `UpdateCommand` in `UpdateDependencyFilter`; doc option summary,
      symbol/member ordering, and slug generation now live beside `DocCommand` in `DocCommandKernels`; tree option
      summary now lives beside `TreeCommand` in `TreeCommandKernels`, and tree dependency and
      target-framework deduplication now live beside `TreeCommand` in `TreeDependencyDeduplicator`;
      restore option summary, reference filtering, and project-reference deduplication now live beside
      `RestoreCommand` in `RestoreCommandKernels`; stale generated-output directory de-duplication now lives beside
      `Program.CleanStaleGeneratedFiles` in `GeneratedOutputDirectoryDeduplicator`; native
      compilation-reference filtering now lives beside `CompilationReferenceResolver` in
      `CompilationReferenceResolverKernels`, and NuGet/framework best-score selection now routes through
      the same resolver-local kernels; check argument summary now lives beside `CheckCommand` in
      `CheckCommandKernels`; fix argument summary now lives beside `FixCommand` in
      `FixCommandArgumentKernels`; add argument summary now lives beside `AddCommand` in
      `AddCommandKernels`; remove argument summary now lives beside `RemoveCommand` in
      `RemoveCommandKernels`; update argument summary now lives beside `UpdateCommand` in
      `UpdateCommandKernels`; new argument summary now lives beside `Program.NewCommand` in
      `NewCommandKernels`; tidy
      option summary, classification, status summary, and fix filtering now live beside `TidyCommand`
      in `TidyCommandKernels`;
      lint option summary and file-argument extraction now live beside `LintCommand` in `LintCommandKernels`; format
      discovered-path filtering now lives beside `Program.FormatCommand` in `FormatCommandKernels`; export
      csharp option summary, input selection, reference filtering, and
      stable reference de-duplication now live beside `ExportCommand` in `ExportCommandKernels`; run
      source operand selection now lives beside `Program.RunCommand` in `RunCommandKernels`; publish
      option summary now lives beside `Program.PublishCommand` in
      `PublishCommandKernels`; pack option summary now lives beside `PackCommand` in
      `PackCommandKernels`; build option and operand summaries now live beside `Program.BuildCommand`
      in `BuildCommandKernels`; test option and outcome summaries now live beside `Program.TestCommand` in
      `TestCommandKernels`; watch forwarded-argument selection now lives beside `WatchCommand` in
      `WatchCommandKernels`; shared positional-argument collection now lives beside `Program` in
      `PositionalArgumentKernels`; fix-applicator text-edit ordering now lives beside `FixApplicator` in
      `FixApplicatorTextEditOrderer`; output-format diagnostic severity summary/filtering now lives
      beside `OutputFormatter` in `OutputFormatterDiagnosticKernels`; output-format diagnostic-cluster
      trait/group kernels now live beside `OutputFormatter` in
      `OutputFormatterDiagnosticClusterKernels`; output-format inspect-summary and diagnostic-cluster
      reference-file summaries now live beside `OutputFormatter` in `OutputFormatterReferenceFileKernels`;
      diagnostic/reference result de-duplication and lint-shadow suppression now live beside
      code-intelligence result consumers in `CodeIntelligenceResultKernels`; symbol-kind filtering
      now lives beside symbol query consumers in `CodeIntelligenceSymbolKernels`; completion
      receiver/grouping kernels now live beside `CompletionEngine` in `CompletionEngineKernels`;
      binding lookup kernels now live beside semantic lookup consumers in `BindingLookupKernels`;
      source/text extraction kernels now live beside code-intelligence text consumers in
      `CodeIntelligenceSourceTextKernels`, deleting `NSharpCodeIntelligenceDogfoodAdapter`; DocQuery
      type/reference-pack de-duplication, best-type selection, and member ordering now live beside
      `DocQuery` in `DocQueryKernels`. Product parser
      wrappers for function, constructor, property, body/local-function, enum, struct/class/record, union, and
      interface routes now compose typed N# cores directly where wrapper ownership is complete, and columnar
      tokenization now compacts parser token kind/start/value-length rows in N# instead of a C# kept-index copy loop;
      flattened exports remain
      compatibility/parity ABIs, with the full-array token-compaction wrapper, function-signature wrappers, constructor signature/chain
      wrappers, property accessor wrappers, top-level declaration probes, declaration utility
      wrappers, statement parsing, local-function discovery, type-reference canonicalization wrappers,
      enum/interface/struct/union declaration-only shims, and the flattened
      interface-signature shim now extracted to the parity corpus when no product caller remains. The
      SoA table-type design gate is complete in [`soa-table-types.md`](soa-table-types.md);
      non-generic `soa record` parsing/lowering and the cold overload-candidate fixture are in place behind
      `NSHARP_EXPERIMENTAL_SOA=1`. Next slices must either shrink redundant adapter/C# transition surface or
      migrate a named compiler/tooling table only when the wrapper ABI, lowering evidence, parity evidence, and
      product route are present.
- [ ] **Coverage expansion** (pulled in as stages need them): class/struct/enum/record/interface/union decls
      + members; for/foreach/let/match/lambdas/generics/tuples/is-as/range/`new[size]`/`new{init}`. Each is a
      parser-kernel form added + parity-gated, then threaded through stages 1–4.
- **Deferred parity findings** (carried over from the retired dogfood-parity roadmap; fix as the parser
  kernel / inferer work lands): **M6 routing safety fixed** — top-level contextual `test`/`setup`/`teardown`
  declarations now make the columnar route decline to the C# test emitter through the N# product
  `TopLevelContextualTestDeclarationExistsInto` scanner instead of silently ignoring them; parsing/emitting
  tests in columnar remains future coverage. **M8 fixed** — the columnar type inferer records
  overload return rows by canonical parameter signature and exact-matches calls instead of letting duplicate names
  overwrite each other.

## Phase P — Rust-class performance

- [x] Ceiling measured: unrolled `Vector<int>` = 4.5× over scalar (checksum-sum 8.8× → ~2× behind native)
- [x] **P1 — auto-vectorize counted reductions** (the `while`-form counted reduction: an `i := 0` init, then
      `while i < len` accumulating `acc = acc + a[i]` and incrementing `i`).
      Sub-slices: [x] (a) pattern detection (`ReductionLoopShape.TryMatch` + 11 tests, no emission change);
      [x] (b) lowering to the unrolled `Vector<int>` SIMD helper (`SimdReductions.SumInt32` in NSharpLang.Runtime;
      `ILCompiler.TryEmitVectorizedReduction` hooks EmitWhile), behind an off-by-default thread-local flag, with
      run(vectorized)==run(scalar) across lengths incl. tails + post-loop index = max(index,bound) + the
      optimization-fires shape check (27 tests). Adversarial review caught + fixed a real divergence: bounds are
      now restricted to provably side-effect-free int (int local/param, int literal, array.Length=pure ldlen)
      and evaluated once — `.Count`/custom `.Length` no longer vectorize. Already unrolled to 4 accumulators
      (the helper). [x] (c) [merged into (b)]; [x] (e) DEFAULT-ON (env NSHARP_VECTORIZE_REDUCTIONS=0 to opt
      out) — never-regress proven: the full 3466-test suite + dogfood + examples + IL-verification + the
      SystemsFastGate benchmark all pass with vectorization active. [x] (d) widen element types: INTEGER ONLY
      (long/uint/ulong — wrapping add is associative); float/double do NOT vectorize (FP reassociation is not
      value-preserving) — they fall back to scalar. DONE: `SumInt64`/`SumUInt32`/`SumUInt64` helpers +
      element-type dispatch in the emitter (accumulator type must equal element type); 44 tests incl. wraparound.
      Adversarial review found+fixed two real divergences (both pre-existing in the int path): `int.MinValue`
      bound overflowing `end - step` (→ `if (end <= start) return`), and OOB throwing `ArgumentOutOfRangeException`
      instead of `IndexOutOfRangeException` (→ SIMD only over a provably in-bounds range).
      [x] (f) FOR-FORM: the vectorizer hooked only `EmitWhile`, but the benchmarks + idiomatic N# use `for`
      (probe: for-form emitted 0 SIMD calls vs while-form's 1 — the win was NOT reaching the benchmark). Now
      `ReductionLoopShape` matches `for i := s; i < n; i++ { acc = acc + a[i] }` (iterator increment, single-stmt
      body braced/braceless) and `EmitFor` emits the initializer then shares the while-form's emit core; terminal
      `index = max(s, n)` matches a counted for-loop's exit. 35 tests; adversarial review SAFE-TO-SHIP. **P1 COMPLETE
      (and now actually firing on idiomatic `for`-loops).**
      Scoping (workflow w8urlgage): hook EmitWhile (ILCompiler.cs:12401, _currentIL/_locals); Vector<int>
      Reflection.Emit feasible (RuntimeCalls.cs generic-binding patterns; N# already emits Vector<int> op IL);
      int wrapping add associative (reorder safe); mandatory scalar tail (Vector<int>.Count platform-varies).
      P1(b) APPROACH DECIDED (probe): RAW Reflection.Emit, NOT AST-lowering — N# supports `Vector<int>` +
      operators + `new Vector<int>(arr)` but NOT `Vector.Sum` (the non-generic `Vector` static class is
      "undefined variable"), so the horizontal sum must be emitted directly. Emit via reflection: ctor(int[],
      int), op_Addition, Vector.Sum<int> (MakeGenericMethod), Vector<int>.Count getter; zero vacc via
      ldloca+initobj; vector loop while i<=len-lanes; then acc += Vector.Sum(vacc); then the scalar tail.
      Behind an off-by-default flag; correctness test = run(vectorized) == run(scalar) across lengths incl.
      non-multiples of Count.
- [x] **P2 — range-predicate counts** (count-ascii) — packed compare + masked accumulate.
      [x] (a) detector `RangePredicateCountShape.TryMatch` (while/for, temp/inlined subject, inclusive range, unit
      counter increment; 19 accept/reject tests; no codegen change). [x] (b) masked-count helper
      `SimdReductions.CountInRangeInt32` (`Vector.GreaterThanOrEqual & Vector.LessThanOrEqual` → mask; `acc -= mask`;
      `Vector.Sum`; reuses P1's empty/OOB/overflow guards) + emitter hook (`TryEmitMatchedRangeCount` in
      EmitWhile/EmitFor) + parity tests (int[], while/for, temp/inlined, tails + inclusive boundaries) +
      adversarial review (no divergence). Fires for int[]/int counter+index/int side-effect-free bound+lo+hi only;
      non-int lo/hi or non-int[] array fall back to scalar. **P2 COMPLETE for int[].** [ ] (c) DEFERRED unless the
      corpus needs it: widen element types or generalize predicate operators (`>`/`<`, reversed operands).
- [x] **P-minmax — min/max conditional reductions** (min-max-delta — the 10.5× kernel, the LARGEST remaining
      native gap). min/max are associative + commutative integer reductions, so lane-wise `Vector.Min`/`Vector.Max`
      is value-preserving like P1's sum. [x] (a) detector `MinMaxReductionLoopShape.TryMatch` (while/for,
      temp/inlined subject, one OR two reductions in one body, reversed `min > value` operand order; 22
      accept/reject tests; no codegen change). [x] (b) lane-wise SIMD helpers `SimdReductions.MinInt32`/`MaxInt32`
      (seed-broadcast accumulators + horizontal fold + scalar tail; reuse P1's empty/OOB/overflow guards) + emitter
      hook (`TryEmitMatchedMinMaxReduction` in EmitWhile/EmitFor; one helper call per reduction, bound evaluated
      once, index unchanged between calls) + parity tests (for/while, temp/inlined, min-only, scalar≡vectorized
      across lengths incl. SIMD tails + int.MinValue/MaxValue extremes) + adversarial review (7 candidates, ALL
      adjudicated non-divergent — the one the judge flagged "real" rested on an impossible "concurrent array resize"
      premise: .NET `int[]` is fixed-length, `array.Length` immutable, and the cached-bound pattern is identical to
      the shipped/reviewed SumInt32/CountInRangeInt32). int[] only. [x] (c) FUSED single-pass
      `SimdReductions.MinMaxInt32` (loads each `Vector<int>` once, applies both `Vector.Min`+`Vector.Max`, returns
      `(min,max)`); routed via `TryGetMinMaxPair` for the `[1 min, 1 max]` body (ValueTuple return, `ldloca`+`ldfld`
      Item1→min/Item2→max); per-reduction path kept for min-only/max-only. **MEASURED — rigorous back-to-back, same
      machine (BDN, M4):** fused **262.5 ns @4096 = 0.168× = 5.94× faster than C#** (vs two-pass 453 ns/0.296×) →
      **1.73× faster than two-pass** → implied **~10.5× → ~1.77× behind native — BELOW the ~2× DONE bar, Rust-class**
      (at 64, two-pass was 1.303× = *slower* than C#; fused 0.768×). Decision rule honored (measured fused>two-pass
      before keeping). 69 MinMax tests; adversarially verified. **P-minmax (a,b,c) COMPLETE for int[]** — widen to
      long/uint/ulong only if the corpus needs it.
- [x] **P3 / P-ctrans — count-transitions, realized as VECTORIZATION** (the bigger win; the bounds-check-elision
      goal — removing the per-iteration indexed-load+branch tax — is subsumed by replacing the loop with a SIMD
      helper). count-transitions counts `i in [1,len)` where `a[i] != a[i-1]`; the loop carries `previous`, but
      passing it as the helper's seed makes the rewrite value-identical for ANY init (the first compare is
      `a[start]` vs the seed, the rest `a[i]` vs `a[i-1]`) — no non-local init analysis. [x] (a) detector
      `CountTransitionsShape` (for/while temp form; carry `previous=current` + `current!=previous` + unit counter
      increment; five distinct names; 17 accept/reject tests; no codegen change). [x] (b)
      `SimdReductions.CountTransitionsInt32(a, start, end, seedPrevious) -> (count, lastPrevious)` (first-vs-seed
      scalar, then SIMD shifted compare `~Vector.Equals`/`acc-=mask` over `[start+1,end)`, scalar tail; reads only
      `a[start..end-1]`, same empty/OOB guards) + emitter (`TryEmitMatchedCountTransitions`; ValueTuple `Item1`→
      count, `Item2`→previous restore, `index=max`) + 46 tests (parity incl. terminal previous; OOB; fallbacks) +
      adversarial review. **MEASURED:** N# **2.37× faster than C#** @4096 (1119.8→471.9 ns; was ~0.99× tied) →
      implied **~4.54× → ~1.9× behind native (Rust-class)**. **With this every vectorizable kernel is within ~2× of
      native; only rolling-hash (~1.5×, the latency-bound floor) remains, and it is not vectorizable.** int[] only.
- [x] **P4 — LLVM / NativeAOT backend evaluation** (decision doc): DONE 2026-06-07 →
      [`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md). **DECISION: defer the
      structural vectorizing backend (evidence-gated reopen, gates G1–G4).** Phase P's per-pattern `Vector<T>`
      emission already closed the 8.8–10.5× SIMD gap to ≤2.0× native (measured), so the structural backend's
      original prize is gone; the residual ~1.6–2× is latency-bound / small-input / scalar-scheduling, which
      NativeAOT (shares RyuJIT → no loop auto-vectorization) and the WASM-only experimental NativeAOT-LLVM do not
      cheaply fix. Split out: NativeAOT **image emission** is a separate, lower-risk CLI startup/size track
      (orthogonal to throughput), worth pursuing on its own merits — `nlc publish --aot` is analysis-only today.

## Phase T — Tooling + language strategy

- [ ] Route the columnar pipeline into the CLI (`nlc check`/`query`/`format`) and the LSP once stages 3–4 land
      (the LLM-first toolchain + IDE run on the fast N# path).
- [x] Re-run the systems-vs-native harness; keep `systems-vs-native.md` numbers current. **RIGOROUS
      single-machine re-run DONE (2026-06-07):** N#(vectorized)/C#/Rust/C all re-measured back-to-back on one
      cool, idle machine → the previously *implied* "~1.6–2× behind native" is now **MEASURED**: N#/best-native
      ≤2.02× at 4096 (checksum 2.02×, count-ascii 1.63×, count-transitions 1.97×, min-max-delta 1.67×,
      rolling-hash 1.62×, parse-eight-digits 1.80×); worst single cell 2.49× (min-max-delta @64, fixed
      SIMD/call overhead). Down from 8.24–10.5×. N# beats C#/RyuJIT ~2–6× on the vectorizable kernels. Full
      table + 2026-06-06 history in `systems-vs-native.md`.
- [ ] Broader general-purpose language features per `project_roadmap_2026q2` — lower priority until self-host +
      perf land, then resumed.

## Status cursor

Phase P **P1 is COMPLETE** (a–f: int/long/uint/ulong counted-reduction auto-vectorization, default-on, both
`while` and `for` forms — now firing on idiomatic/benchmark code — parity- and adversarially-verified, all
correctness bugs fixed). **P2 is COMPLETE for int[]** (a: detector; b: masked-SIMD count codegen, count-ascii,
adversarially verified). **P-minmax is COMPLETE for int[]** (a: detector; b: lane-wise Vector.Min/Vector.Max
codegen; c: FUSED single-pass MinMaxInt32 — MEASURED **5.94× faster than C#** at 4096 (1.73× over two-pass) →
**~1.77× behind native, Rust-class**, adversarially verified). **P3/P-ctrans is COMPLETE for int[]** (count-transitions
vectorized as a seeded shifted-compare count — MEASURED **2.37× faster than C#** @4096, ~1.9× behind native).
**EVERY vectorizable systems kernel is now Rust-class (within ~2× of native); only rolling-hash (~1.5×, the
latency-bound floor) is left, and it is not vectorizable.** Phase P's per-pattern auto-vectorization program is
essentially DONE. **Stage 3b — columnar diagnostics (Phase S) is COMPLETE**: 3b-i definite-return (NL305),
3b-ii unreachable-after-terminal (NL312), and 3b-iii unused-local (NL001) all landed in `ColumnarDiagnosticsPass`
(the columnar subset of `StatementAlwaysReturns`; `CollectUnreachable` mirroring `Analyzer.AnalyzeStatements`;
`CollectUnusedLocals` reproducing the Linter's time-/scope-ordered NL001) — async/generator sources decline to
C#; positions resolved from the tokenizer's own line/col matching the AST; parity vs a C#-AST mirror on
hand-built cases + the 29-file shipped product corpus, each adversarially verified (the reviews caught + we fixed an async
unit-task divergence in 3b-i and a global-rule ordering divergence in 3b-iii). **Stage 4 — columnar codegen
is SCOPED** (read-only Explore workflow): reuse `ILCompiler._currentIL` via a separate columnar dispatcher, data
~80% sufficient from stages 1–3, decomposed into a spike + 4a–4k (see the Stage 4 item above). **The 4-spike
is DONE and retired** — `ColumnarIlEmitter` proved runnable one-method assemblies straight from the columnar
tables (load+invoke for int-only param/literal/paren/`+`/`-`/`*` functions), then the coverage moved onto the
production-shaped `TryEmitColumnarProgram` route. **4d (int `:=` locals) is also DONE** —
`stloc`/`ldloc`, chained locals invoke-tested, shadowing/redeclaration declined (keeping the C# analyzer
authoritative). **4g (if/else, both-branches-return cut, with int comparisons) is also DONE.** So the emitter
now covers params, int literals, `+/-/*`, paren, `:=` locals, and if/else — invoke-tested, every unsupported or
diagnostic-bearing form (shadowing, unreachable-after-return, if-without-else, bool-in-value) declined. **4f
(simple `local = expr` assignment statements) is also DONE** — and surfaced + fixed a latent fall-off-the-end
bug (an int body must now always-return, else decline). **4h while loops is also DONE** — the first general
fall-through control flow (`brfalse`/back-edge, stack-empty merge labels), with block scoping so loop-body
locals don't leak (`fact(5)==120` invoke-tested). **4e (unary `-`/`~`) is also DONE.** So the emitter covers
params, int literals, unary `-`/`~`, `+/-/*` + comparisons, paren, `:=` locals, assignment, if/else, and while —
enough to compile real int functions. The spike has now thoroughly proven the columnar→IL question. **Next, the
strategic pivot: 4c (parity-vs-C#-path harness) then 4j (route into `ILCompiler` with C# fallback) — the
inflection where columnar codegen starts REPLACING C#** (Stages 5 route → 6 delete). Remaining small emitter
gaps (4g+ general if, 4i calls) are pulled in as the routed corpus needs them.
(columnar codegen) — where end-to-end binder/output parity (incl. the binder reconciliation item) is verified —
→ 5 (route) → 6 (delete C#). Phase T (route columnar into CLI/LSP) follows stages 3–4.

**Perf capstone (Track C) — COMPLETE 2026-06-07.** The rigorous single-machine cross-language re-run is done:
N#/best-native is now **MEASURED ≤2.02× at 4096** (worst cell 2.49×), down from 8.24–10.5× — `systems-vs-native.md`
leads with the authoritative post-vectorization table. **P4** (LLVM/NativeAOT backend) is **evaluated and
deferred** — decision doc [`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md):
the structural backend's order-of-magnitude prize was captured by Phase P's `Vector<T>` emission, so it stays
deferred behind evidence gates G1–G4; NativeAOT image emission is split out as a separate, lower-risk CLI
startup/size track.

**Status cursor (2026-06-13).** Stages 3b (columnar diagnostics), 4 (columnar codegen spike→backend), and 5
(production routing default-on with `NSHARP_COLUMNAR_BACKEND=0` as the C# opt-out) are DONE — the standalone columnar pipeline
owns parse→emit for the modelled surface (36/36 shipped product files via multi-file merge, with parity-only probes outside
product routing) and is parity-gated per
slice. The live work is **Phase D rich-language columnar emit** (newest-on-top log:
[`self-host-progress.md`](self-host-progress.md) is the authoritative cursor): D-11d class inheritance landed;
the oracle static-member fix bundle landed (`7952bc54`); D-12/13/14 columnar STATIC METHODS/FIELDS/PROPERTIES landed (`80204c27`, `2982ef50`, `c3da5311` — the
static-member arc is complete); D-15a columnar GENERIC FUNCTIONS landed (`ca0b64da` — real CLR generic
methods + call-site inference). D-15b explicit type args landed (`d0c079ba` — generic FUNCTIONS complete). The
audit-driven oracle hygiene bundle landed (NL201 unresolved types `109efcd2`, NL923 reference-load pairing
`e9273453` — Arc-3 analysis ports must mirror both). Generic-user-types oracle fix bundle 1/3 landed
(`47bd7d2e` — B1 closed-generic member access, B10 generic-typed ctor params, B12 generic instance methods;
B14 fixed by NL201). The oracle arc COMPLETED with bundles 2/3 (`c4b42395` — B2/B13 arity diagnostics NL207)
and 3/3 (`ee5a60ba` — B4 generic-record object-init refuses cleanly on an upstream .NET 10
PersistedAssemblyBuilder modreq bug; B5 generic structs fixed transitively + pinned). D-16 columnar GENERIC
TYPES landed (`a10d33f9` — generic classes end-to-end: kernel `<T,U>` decl parse, closed construction,
rebound member access, TypesEquivalent for TypeBuilderInstantiation identity; generic records/bases/statics/
value-struct-construction decline, pinned). B4 then CLOSED for the oracle: the upstream report was withdrawn
and generic-record init members now emit via backing-field lowering (rebound FieldRefs carry no modreq to
lose; setters keep their modreq for C# `init` interop), with `with`/Equals/Clone on generic records fixed
and block-form record value semantics made real (see the self-host progress log); columnar still declines
generic records pending that lowering. The ORACLE also gained GENERIC UNIONS (`d1c41b6e` — `union Result<T>`
parse→analyze→emit→export, the README flagship); columnar GENERIC UNIONS then landed (the D-10 pin FLIPPED:
kernel `<T,U>` union-decl parse + brace-less BareNew kind 42, PASS-0 base-declares/case-redeclares/SetParent-
closed mirror of the oracle machinery, closed construction with explicit args after the CASE name, the
five-position adoption surface (return/typed-local/field-value/local- and param-reassignment — probe-pinned),
match closing cases over the scrutinee's arguments, TypesEquivalent flow relaxation; the adversarial review's
two probe-confirmed breaks — trailing-comma `<T,>` kernel over-accept in all THREE declaration kernels and
the generic-sibling `Opt<T>` return escaping unsubstituted into callers (BadImageFormatException) — fixed and
pinned). D-17a columnar VALUE-STRUCT user constructors landed (`e2f4a553` — generic structs included;
ctor bodies accept partial assignment matching the oracle; the `new S()`-bypasses-parameterless-ctor oracle
defect is recorded). D-17b columnar generic-function `where` CONSTRAINTS landed (kernel clause parse → flat
rows; definition-time application + call-site enforce-or-decline at the MakeGenericMethod chokepoint; the
five top-level scanners learned to not see `where ... class/struct` as declarations) plus an ORACLE fix:
circular constraints (`where T: T`) used to HANG the compiler at declaration time — the analyzer now rejects
them with NL208 (F-bounded stays legal); the interface-constraint member-dispatch NL103 emit crash is
recorded for a future oracle bundle. The LAMBDAS ARC then closed its main ladder (nine rungs — see the
progress log), MATCH POSITIONS parity-proved match expressions in every position, columnar GENERIC UNIONS
landed (above), and columnar GENERIC RECORDS landed (the D-16 adapter decline flipped — columnar's
plain-field record model needs no modreq lowering; closed-generic reference object-init + review-driven
declines for type-param/member collisions, record user ctors — whose body assignments the PIPELINE drops,
a newly-pinned oracle defect — and static fields on generic types). NAMED TUPLES then landed in two
halves (oracle `7e151c7c`: t.x threw at emit despite analyzer acceptance — per-variable name retention +
ItemN rewriting; columnar: kernel kinds 7/43 name channels, name-erased canonicals, the same per-variable
mapping; a pre-existing bare-tuple-typed-local over-accept fixed). The scalar, strings, nullability,
collections, async, interfaces, Phase-P columnar ports, and route-all/default-on rungs have since landed
in the progress log. The active path is Stage 6 surface shrink plus SoA/emitter-port proof work before
`ILCompiler/` and `Analyzer.cs` can be retired.

The `systems-language-perf` worktree (P-minmax(c) + P3/P-ctrans) has been merged into `systems-language`
(commit `d2a447f3`).

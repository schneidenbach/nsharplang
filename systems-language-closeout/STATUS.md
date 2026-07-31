# Systems-language closeout cursor

Last updated: 2026-07-30 (**TASK 017 SLICE 7 LANDED — THE `ResolveType` ARC IS OPEN: ITS WHOLE CLOSURE
IS MEASURED, THE STAGED PLAN IS RECORDED, AND STAGE 1 — THE PURE DECISION SURFACE — IS N#-OWNED.**
The mandate was to open the type-REFERENCE engine. Measurement first: a throwaway instrumented build
with 40 counters, run over all 40 corpus targets, the full 3,193-test suite (which passed **3,193 /
3,193 WITH the probe armed**) and 11 purpose-built resolution-error fixtures, then reverted. It says
`ResolveType` is a CHANNEL WALK with **exactly five report sites and one `_semanticModel.RecordTypeReference`
per resolved reference** (9,606 / 29,565 / 268 calls), every report site living in
`ResolveSimpleType`/`ResolveGenericType` and none in any helper — so the recording path is not
separable and the slice cut AROUND it, taking everything that is a total function of separable state.
THE CUT: **7 whole C# members + 1 inline table + 1 STATE FIELD deleted, 225 lines**
(`TryResolveExternalType` 41, `TryResolveBuiltInTypeKeyword` 28, `BuildUnresolvedTypeSuggestion` 24,
`GetGenericHeadArity` 23, `GetVisibleProjectTypeNamespaces` 23, `TryResolveExactExternalType` 20,
`GetKnownGenericHeadArities` 17, the 20-line built-in name table → 1 line, and `_externalTypeCache`
itself) into TWO new N# owners — `AnalyzerExternalTypeProbe` (152 lines; it now OWNS the resolution
cache) and `AnalyzerTypeReferenceFacts` (147) — plus one new member each on `AnalyzerWellKnownTypeFacts`
and `AnalyzerDiagnostics`. 29 routing sites, all in-class. `Analyzer.cs` **22,243 → 22,050**;
`git diff` +32 / −225 = **net −193**, the only C# added being a field, one constructor line and 28
rewritten call sites. THE NON-MECHANICAL FINDING: **the probe's cache is ORDER-BEARING, not an
optimisation** — the bare exported-name scan (40 / 100 / 9 live hits) caches under the BARE spelling and
short-circuits the import loop on the next call, so this owner is the one analyzer owner that must NEVER
be rebuilt; the well-known-type bag is passed as an argument instead. PROOF: a throwaway reflection
differential against the C# originals on a really-loaded analyzer AND on one with no
MetadataLoadContext — **4,918 cells, 0 mismatches, 483 true positives** — run COLD per cell (cache
cleared, fresh owner) and then WARM as a three-pass ordered replay with the two caches compared as MAPS,
plus 232 using-namespace ORDERINGS; and a **4,918-row before/after transcript that is byte-identical
(md5 `892e23a2603e1861102cf60d4d3b7cfd` both times)**, the "after" column taken from the analyzer's own
routed path so it proves the wiring too. `nlc check --json` **byte-identical on 40 / 40 project targets
(ORACLE_DIFFS = 0)** plus 11 purpose-built resolution-error fixtures firing 57 diagnostics
(FIXTURE_DIFFS = 0); corpus IL **64 / 64 comparable assemblies BYTE-IDENTICAL** (PRODUCT_IL_DIFFS = 0,
SINGLE_IL_DIFFS = 0, SKIPPED_TARGET_DIFFS = 0). GATES: unit **3,193 / 3,193** (zero drift), contracts
**1,607 → 1,627**, ownership audit **18 / 18** after a one-row net-negative in-place repin that keeps
the manifest at **391 lines**, `dev.sh --since` (full-suite fail-safe, 3,193/3,193 Debug), and the FULL
VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 846s** in a fresh isolated copy
(105 `✓ PASSED`, zero `✗`, VS Code integration **36 passing**, all 67 assemblies IL-verified); VSIX
rebuilt + reinstalled. TWO GUARDS MEASURED DEAD and recorded rather than acted on (the assembly-identity dedupe 0 /
15,218 yields, the using-namespace dedupe 0 / 77,953), as was a structurally dead using-alias channel.
New .nl gotchas: **`partial` is RESERVED as a local name**; **`Object.ReferenceEquals` needs the capital
`Object`**; **`Assembly.get_FullName` / `AssemblyName.get_Name` and the 3-argument `Assembly.GetType`
are unbound**. No wall — both capability gaps were routed around. NEXT: **STAGE 2 — THE SCOPE STACK**
(`Scope` is already N#; the slice is the `Stack<Scope>` and its 51 sites), then project discovery, then
the reporting/recording walk, then the assignability SCC in one cut)

Last updated (prior): 2026-07-30 (**TASK 017 SLICE 6 LANDED — THE ASSIGNABILITY SHAPE DECISIONS ARE N#-OWNED,
AND THE ROOT'S ONE REMAINING BLOCKER IS MEASURED AND NAMED.** The mandate was `IsAssignable` itself.
Measurement — a throwaway instrumented build run over all 40 corpus targets AND the full 3,193-test
suite, then reverted — says the ROOT CANNOT MOVE YET, and says exactly why: `IsAssignable` is one
strongly-connected component with `IsSubtypeOf`, `HasImplicitConversion`, the delegate scorer and the
lambda/known-generic arms, and its own dispatch holds the DUCK-INTERFACE arm, which compares member
signatures through `MethodSignaturesMatch` → **`ResolveType` — 128 live calls that RECORD into the
semantic model and REPORT diagnostics** (19 live `ImplementsDuckInterface` calls in the suite), plus
the ActionResult arm's `TryResolveExternalType` (1 live call, `_mlcAssemblies` + `_usingNamespaces`).
A reporting arm cannot move silently, so the slice RECUT to the largest terminal sub-closure, exactly
as the mandate directs. Also measured and recorded rather than acted on: `ResolveTypeForSourceOwner`'s
`ResolveType` fallback fired **0 / 5,256** and `ResolveGenericDefinition`'s scope-stack `LookupType`
fallback **0 / 1,769** — dead, but not the reason the root stayed. THE CUT: **6 whole C# members
DELETED** (`IsCollectionType` 61 lines, `IsArrayToSpanAssignable` 18,
`CanBindCallableReferenceToExpectedType` 13, `IsReferenceLikeForVariance` 10 — caller-free once the
policy moved — `MayUseDelegateReferenceConversion` 9, `IsDelegateType` 7) plus
`IsKnownGenericTypeAssignable` 45 → 15 and `IsFunctionTypeAssignable` 31 → 14, both reduced to
CLASSIFICATION-FREE shells, into the new N# owner `AnalyzerAssignabilityFacts` (408 lines, two
classes, 22 members). **THE PENDING-PAIR PROTOCOL** is the non-mechanical idea: a decision that needs
recursion answers with a DECIDED verdict or the ORDERED target/source pairs the caller must answer, so
the whole classification moves and only the recursion stays — no callback, no fallback. 13 routing
sites, all in-class. `Analyzer.cs` **22,409 → 22,243**; `git diff` +28 / −194 = **net −166**, and the
only C# added is a field, 3 wiring lines and the two shells. PROOF: a throwaway reflection
differential against the C# originals on a really-loaded analyzer AND on one with no
MetadataLoadContext — **420,946 cells, 0 mismatches** (361 TypeInfo values squared for the two
two-argument relations, 107 CLR types, 16 function types squared; 200 true known-generic, 24 true
array-to-span, 131 true collection, 145 true function-type, 8 true delegate cells) — plus a
**420,946-row before/after transcript that is byte-identical (same md5)**; `nlc check --json`
**byte-identical on 40 / 40 project targets (ORACLE_DIFFS = 0)** plus 5 purpose-built assignability
fixtures firing 26 diagnostics (FIXTURE_DIFFS = 0); and a corpus IL sweep of **64 / 64 comparable
assemblies BYTE-IDENTICAL** (PRODUCT_IL_DIFFS = 0, SINGLE_IL_DIFFS = 0, SKIPPED_TARGET_DIFFS = 0).
GATES: unit **3,193 / 3,193** (zero drift), contracts **1,596 → 1,607**, ownership audit **18 / 18**
after a one-row net-negative in-place repin that keeps the manifest at **391 lines**, `dev.sh --since`
(full-suite fail-safe), and the FULL VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS
PASSED in 17m08s** in a fresh isolated copy (VS Code integration **36 passing**, all 67 assemblies
IL-verified, contracts 1,607/1,607 inside the gate); VSIX rebuilt + reinstalled. New .nl
gotchas: a **chained instance call on a member-access or call result declines** (bind the receiver);
**returning `string?` from a `string` signature declines**; **`typeof` over most generic collection
types is off the columnar surface** — resolve open definitions with `Type.GetType` by canonical
identity and close them with `MakeGenericType`. No wall. NEXT: **`ResolveType(TypeReference)`** — the
type-REFERENCE engine is now the ONLY thing standing between the analyzer and the whole assignability
SCC; `CreateFunctionTypeInfoFromDelegate` is separately blocked only by assembly direction
(`NullabilityMetadata` lives above BootstrapServices))

Last updated (prior): 2026-07-29 (**TASK 017 SLICE 5 LANDED at `a60260357`** — the CLR-conversion
funnel. 7 C# members / 210 lines deleted into the N# `AnalyzerClrTypeConversion`, 40 routing sites,
`Analyzer.cs` 22,608 → 22,409, 800-shape / 1,682-cell differential with 0 mismatches, a byte-identical
1,170-row before/after transcript, oracle 40/40, corpus IL 64/64, contracts 1,585 → 1,596. Its full
record — including the rebuild-not-mutate discipline for the nullable well-known bag that slice 6
reuses — is in the Cursor block below; this header entry was not written at the time)

Last updated (prior): 2026-07-29 (**TASK 017 SLICE 4 LANDED — ALIAS IDENTITY IS UNIFIED AND
`ResolveTypeAlias` IS GONE FROM `Analyzer.cs`.** The slice-3 measurement said the alias funnel's
pure N# branch fired **0 / 36** because `Analyzer.cs` :369 built a FRESH `AliasTypeInfo` per alias
declaration while `AnalyzerDeclarationContext.filesByType` keys on TypeInfo REFERENCE identity. The
fix is one N# entry point — `RegisterDeclaredAlias(filePath, alias)`, which writes `filesByType`
and NOTHING else — plus **5 lines** of mechanical C# in `DeclareType`'s registration arm; the
`TryGetCanonicalType` adoption arm KEEPS its alias exclusion, because the context deliberately
stores the RESOLVED target under an alias NAME and adopting it would replace the analyzer's
`AliasTypeInfo` with its target. **THE FLIP IS MEASURED**: slice 3's exact four-alias fixture goes
`aliasSeen=36 b1=0 b2=36` → `aliasSeen=28 b1=28 b2=0`, every one of 10 alias fixtures plus
`tests/native/direct-calls` flips the same way (**b2 total 523 → 0**), and — the licence for the
deletion — **the full 3,193-test unit suite run with the probe armed reports `b1=103 b2=0`**, so the
C# `ResolveType` arm is DEAD, not merely unused by the corpus. With that proven, `ResolveTypeAlias`
(the trampoline + the 17-line engine, **20 lines / 2 methods**) is DELETED and all **143** in-class
call sites route to `AnalyzerDeclarationContext.ResolveDeclaredAlias`. `Analyzer.cs`
**22,622 → 22,608**; `git diff` +152 / −166 = **net −14**, of which the only C# ADDED is the 5-line
registration branch. N#: **+43 lines / 3 members** on `AnalyzerDeclarationContext` (82 → 85) and
**4 contracts** (**1,581 → 1,585**). PROOF: `nlc check --json` **byte-identical on 40 / 40 project
targets (ORACLE_DIFFS = 0)**; a 10-project / 50-diagnostic alias differential covering chains,
cycles, alias-to-generic/union/class/record/interface/enum/array/nullable/tuple/`Func<,>`,
cross-file, namespace-qualified and external-CLR aliases and unresolvable targets, with
**exactly ONE difference — a FALSE POSITIVE REMOVED**: `type BoxedAlias = Box<IntList>` used to
raise NL202 whose `expectedType` printed the internal class name `NSharpLang.Compiler.AliasTypeInfo`
because the scope-stack path never resolved the alias INSIDE the type argument; and a corpus IL
sweep of **64 / 64 comparable assemblies BYTE-IDENTICAL** (PRODUCT_IL_DIFFS = 0,
SINGLE_IL_DIFFS = 0, SKIPPED_TARGET_DIFFS = 0). GATES: unit **3,193 / 3,193** (zero drift),
contracts **1,585 / 1,585**, ownership audit **18 / 18** after a one-row net-negative in-place repin
that keeps the manifest at **391 lines**, `dev.sh --since` (full-suite fail-safe), and the FULL
VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 13m51s** in a fresh isolated
copy (VS Code integration **36 passing**, all 67 assemblies IL-verified); VSIX rebuilt + reinstalled.
New .nl gotchas: **`newtype` is reserved as a local name**; **`==` between differently-typed
`TypeInfo` expressions declines** (bind through `as TypeInfo`); **`.ToString()` on a `TypeInfo`-typed
value declines**. No wall. NEXT: **the CLR-conversion funnel is now DELETION-READY** — re-reading
`TryConvertTypeInfoToClrType` (30 sites) + `TryConvertTypeInfoToClrTypeForBinding` (11) and their
four helpers shows their entire state surface is N# already (`ResolveDeclaredAlias`,
`AnalyzerWellKnownTypes`, `AnalyzerWellKnownTypeFacts`) with **no `ResolveType`, no `_errors`, no
`_semanticModel`, no scope stack**; take that as one owner, then `IsAssignable`)

Last updated (prior): 2026-07-29 (**TASK 017 SLICE 3 LANDED — THE N# WELL-KNOWN-TYPE OWNER, AND A MEASURED
REFUTATION OF THE RECORDED SLICE-3 PLAN.** This slice moves analyzer STATE, not just policy over it:
the nested `internal sealed class WellKnownTypes` — the MetadataLoadContext-backed fact bag every
semantic type comparison and generic construction reads — is out of `Analyzer.cs`, together with all
three tables that are pure functions of it. **4 C# units / 271 lines DELETED, 20 inserted and every
one of them mechanical routing**: `WellKnownTypes` (173 lines), `TryGetKnownOpenGenericType`,
`TryConvertBuiltInTypeInfoToRuntimeClrType`, and the INLINE binding-surrogate open-generic table
inside `TryConvertTypeInfoToClrTypeForBinding` → the new N# owners `AnalyzerWellKnownTypes` (225
lines, 52 members) and `AnalyzerWellKnownTypeFacts` (212 lines, 5 members). `Analyzer.cs`
**22,873 → 22,622**; `git diff` +20 / −271. All 7 routing sites are in-class — nothing external
referenced any of it — and nothing calls back. **THE RECUT IS THE OTHER PRODUCT.** The recorded
target was "absorb `ResolveTypeAlias` + `TryConvertTypeInfoToClrType`, built on the N#
`AnalyzerDeclarationContext` facts". That premise is FALSE AT RUNTIME and it was refuted by
measurement, not argument: a throwaway instrumented Debug CLI over six corpus projects plus a
four-alias fixture shows the alias funnel's declaration-context branch fires **0** times and its
`ResolveType`-engine branch **36** — because `Analyzer.cs` :369 declares each alias as a FRESH
`AliasTypeInfo` while `AnalyzerDeclarationContext.filesByType` is keyed by TypeInfo REFERENCE
identity over the instances IT built. The live alias path is therefore 100% the C# TypeReference
engine (`_semanticModel`, `_errors`, the scope stack, the MLC), and taking the funnels needs that
identity unified first — recorded as slice 4, which is now a far smaller cut precisely because
`_wellKnownTypes` is the state this slice removed from the problem. PROOF: an exhaustive throwaway
reflection differential against the C# originals on a really-loaded analyzer — **692 cells, 0
mismatches** over 5 facts, compared by value OR THROWN EXCEPTION TYPE (which caught and pinned the
originals' `TypeLoadException` on `void[]`) — plus a **byte-identical 146-shape / 292-cell
end-to-end transcript of BOTH CLR-conversion funnels taken before and after the deletion**;
`nlc check --json` **byte-identical on 40/40 project targets** plus 5 purpose-built fixtures firing
37 resolution-sensitive diagnostics (16 × NL202 naming the compiler-known generics); and a corpus IL
sweep of **64/64 comparable assemblies BYTE-IDENTICAL (PRODUCT_IL_DIFFS = 0)** with the 7
non-building native targets proven to fail identically. GATES: unit **3,193 / 3,193** (zero drift),
BootstrapServices contracts **1,571 → 1,581**, ownership audit **18 / 18** after a one-row
net-negative repin that keeps the manifest's compact **391-line** format, `dev.sh --since`
(full-suite fail-safe). New .nl gotchas: **`MetadataLoadContext.CoreAssembly`, `typeof(void)` and
`typeof(Nullable<>)` are all off the columnar binding/typeof surface** — routed around with the core
assembly passed in as a constructor argument and the `typeof(object).get_Assembly()` idiom, rather
than extending a plan and tripping the wall; typed `catch ex: T` clauses DO work in `.nl`. No wall.
NEXT: slice 4 — unify alias-TypeInfo identity between `DeclareType` and the declaration context,
then take `ResolveTypeAlias` (143 call sites) and the CLR-conversion funnel (30 + 11), then
`IsAssignable`)

Last updated (prior): 2026-07-29 (**TASK 017 SLICE 2 LANDED — THE CALLABLE / DELEGATE-REFERENCE
CLASSIFICATION FAMILY.** The eight remaining pure, `private static`, zero-instance-state predicates
in the assignability neighbourhood are out of `Analyzer.cs`. **8 C# methods / 66 lines deleted, ZERO
C# added**: `IsCallableReferenceType`, `IsMethodGroupReferenceType`, `HasSourceFunctionIdentity`,
`IsRuntimeDelegateType`, `GetFunctionParameterModifier`, `NormalizeDelegateParameterModifier`,
`TryCreateFunctionTypeInfoFromGenericDelegate` → the NEW sibling owner
`AnalyzerCallableReferenceFacts` (7 members), and `IsSpanTypeName` → `AnalyzerConversionFacts`,
where it belongs (its only consumer gates an implicit array-to-span CONVERSION; filing a conversion
table under a callable/delegate class would have misfiled it — the one recorded deviation from the
slice-1 plan). `Analyzer.cs` **22,938 → 22,873**; `git diff` +21 / −86. All **21** call sites —
every one in-class, the predicates had no external caller — route straight to the owners; no
callback, no fallback, no comparison route. PROOF: an exhaustive throwaway reflection differential
against the C# originals, run before the deletion — **271 cells, 0 mismatches** across 6 facts
(50 `TypeInfo` values × 2 predicates, 42 CLR types **including 9 loaded into a real
MetadataLoadContext**, 24 source-identity, 19 span-name, 46 modifier and 40 signature-reification
cells); `nlc check --json` **byte-identical on 40/40 project targets** plus 4 purpose-built fixtures
that fire this family's own diagnostics (**4 × NL411 MethodGroupUsedAsValue** + 11 more, 15 total,
byte-identical); and a corpus IL sweep of **64/64 comparable assemblies BYTE-IDENTICAL
(PRODUCT_IL_DIFFS = 0)** with the 7 non-building native targets proven to fail identically. GATES:
unit **3,193 / 3,193** (zero drift), BootstrapServices contracts **1,561 → 1,571**, ownership audit
**18 / 18** after a one-row net-negative repin that **KEEPS THE MANIFEST'S COMPACT 391-LINE FORMAT**
(the slice-1 pretty-print defect is fixed: the script edits lines in place and asserts the line
count), `dev.sh --since` (full-suite fail-safe). New .nl gotcha: **`typeof(Delegate)` /
`typeof(MulticastDelegate)` do not resolve** — the columnar `typeof` surface has a hardcoded
well-known list and extending it is a kernel change, so the owner reads the roots out of the core
library with the established `typeof(object).get_Assembly()` idiom. No wall. NEXT: the recorded
architectural prerequisite — an **N# type-resolution owner** absorbing `ResolveTypeAlias` +
`TryConvertTypeInfoToClrType`, which unblocks `IsAssignable` itself and also retires two 015
emitter blockers)

Last updated (prior): 2026-07-29 (**TASK 017 SLICE 1 LANDED — THE SEMANTIC-ANALYZER ARC IS OPEN.** The
conversion/assignability CLASSIFICATION TABLES — the task file's first-listed family — are out of
`Analyzer.cs` and owned by the new N# `AnalyzerConversionFacts`. **7 C# methods / 122 lines deleted,
ZERO C# added**: both `IsImplicitNumericConversion` overloads (the CLR implicit-numeric-widening
table, which the analyzer carried TWICE — once keyed by N# source names, once by CLR full names),
`GetNumericTypeFullName`, `IsReferenceType`, `IsReflectionAssignableFrom`, and the two bodyless
`GetInterfacesSafe`/`GetBaseTypeSafe` pass-throughs (inlined, not reproduced). `Analyzer.cs`
**23,060 → 22,938**; `git diff` +27 / −149. All **26** call sites — every one in-class, the
predicates had no external caller — route straight to the owner; no callback, no fallback, no
comparison route. The owner states the widening relation ONCE over a `NumericConversionKind` and
reaches it through two DISJOINT name maps, so the two vocabularies stay separate; that is pinned by
negative contracts. PROOF: an exhaustive throwaway reflection differential against the C# originals,
run before the deletion — **2,400 cells, 0 mismatches** (23×23 source-name grid, 30×30 CLR grid,
30×30 reflection-assignability grid, 71 `TypeInfo` values covering every subclass); `nlc check --json`
**byte-identical on 40/40 project targets** plus 3 purpose-built conversion-error fixtures; and a
corpus IL sweep of **64/64 comparable assemblies BYTE-IDENTICAL (PRODUCT_IL_DIFFS = 0)** — 26 project
targets + 38 single-file examples, normalized with an explicit PE/CLI parser touching only the COFF
timestamp, the PE checksum, the debug directory and the `#GUID`/`#Pdb` heaps — with the 7 native
targets that do not build standalone proven to fail IDENTICALLY at baseline and after. GATES: unit
**3,193 / 3,193** (zero drift), BootstrapServices contracts **1,554 → 1,561**, ownership audit
**18 / 18** after a one-row net-negative repin, `dev.sh --since` (full-suite fail-safe), and the FULL
VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 13m47s** in a fresh isolated
copy, VS Code integration step included and all 67 assemblies passing IL verification; VSIX rebuilt +
reinstalled. Interactive computer-use verification was DENIED by the permission system again and is
recorded as an open gap. No wall. NEXT: slice 2, the callable/delegate-reference classification family
into a SIBLING owner — and the recorded architectural prerequisite for `IsAssignable` itself, an N#
type-resolution owner absorbing `ResolveTypeAlias` + `TryConvertTypeInfoToClrType`)

Last updated (prior): 2026-07-29 (**STAGE N+3 LANDED — `Parser.cs` IS DELETED. THE 016 PARSER-OWNERSHIP ARC IS
COMPLETE.** `src/NSharpLang.Compiler/Parser.cs` (7,116 lines) and the `ParseResult` record it was the sole
producer of (`ErrorReporting.cs`, 14 lines) are GONE — **7,130 lines of C# parser policy deleted, zero
replacement C# added.** The real caller inventory was **21 files**, not the 3 the N+1 records named: 20 test
files plus Parser.cs's own interpolation sub-parser. Every one of the 53 test parse sites now routes to
`ColumnarParserRecovery.ParseFileAst`, the same entry the 12 production consumers took in N+2 — so the C#
tests no longer exercise a parser that left the product. **NOT ONE ASSERTION WAS LOST OR REWRITTEN**: the
2,021 parser assertions across ParserTests / ParserErrorTests / ErrorHandlingTests / EventSubscriptionTests /
LocalFunctionTests (356 facts) are now executable proof obligations ON THE N# OWNER over a synthetic surface the native
corpus does not otherwise reach, and the suite is **3,193 / 3,193 — the exact N+2 count, zero drift**. The
owner's `FileParseAst` gained the one member `ParseResult` had that it lacked (`Success`, reproducing
`CompilationUnit != null && !Errors.Any(Error)`), pinned by 4 new contracts → **1,554 / 1,554**. GATES:
ownership audit 18/18 after the repin, corpus IL sweep **78 / 78 byte-identical** (PRODUCT_IL_DIFFS = 0,
fresh Release CLIs baseline-vs-after over the whole example/fixture corpus), dev.sh `--since`, and the FULL
VS Code-enabled `./scripts/test-all.sh --commit` **EXIT 0 in 13m48s** (105 gate steps green, VS Code
integration smoke **36 passing**); `nsharp-0.6.0.vsix` rebuilt + reinstalled. RATCHET: `Parser.cs` and
`ErrorReporting.cs` retired to `removed` (zero `current*`, `text-v1:removed`, epochs preserved) and 20 test
rows repinned, every one net-negative. The only assertion-marker movement is −53 `it(` false positives — the
JS-framework heuristic matching `ParseCompilationUnit()`; `[Fact]` / `[Theory]` / `Assert.` counts are
UNCHANGED in every file, proven by a per-marker diff. No wall)

Last updated (prior): 2026-07-29 (**STAGE N+2 LANDED — THE PRODUCTION CUTOVER. The N# owner
`ColumnarParserRecovery` is now the SOLE production parse + ordered-diagnostic authority.** All 12
external production consumers (MultiFileCompiler.ParseAllFiles, Analyzer ×4, Formatter, CLI
FormatSource + LintCommand, FixApplicator, CodeIntelligenceService, DocumentManager, PlaygroundCompiler)
route to `ColumnarParserRecovery.ParseFileAst`, which now returns a `FileParseAst { CompilationUnit,
Errors }` whose field names mirror `ParseResult`'s so every downstream read is byte-unchanged. Errors are
Parser.cs's RAW recording order. Parser.cs is UNREFERENCED by production but NOT deleted (N+3). No shadow
parse, no comparison route, no fallback flag. The owner's per-class member ceiling is respected — ZERO
member functions added. SIX owner parity defects were found and fixed en route by a cutover-grade probe
(Assign/Arrow `TokenTypeToString` renderings, the parameter-list boundary anchor, two non-parity
`SplitGreaterDepth` resets, four retained `<error>`-name declines, and the `on`-handler report anchor).
PROOF: 514 tree files + 452 malformed-corpus sources + 26,728 fuzz mutants = **27,694 sources, 0
mismatches** on BOTH the whole tree and the raw-ordered diagnostic stream; corpus IL sweep **88/88
comparable assemblies byte-identical** (PRODUCT_IL_DIFFS=0). GATES: unit 3,193/3,193, contracts
1,550/1,550, ownership 18/18, dev.sh Parser 384/384, and the **FULL VS Code-enabled
`./scripts/test-all.sh --commit` EXIT 0** with 36 VS Code integration tests passing; extension rebuilt +
reinstalled. Ratchet repinned across the 9 touched C# files, all net-negative-or-neutral. No wall)

Last updated (prior): 2026-07-29 (STAGE N+1c TRANCHE 11 LANDED — **ERROR-NODE MATERIALIZATION: the MALFORMED-FILE
surface. The owner no longer DECLINES anywhere.** Every synthetic recovery artifact Parser.cs substitutes on
malformed input is now REPRODUCED byte-exact: the 9 `IdentifierExpression("<error>")` production sites, the
`IdentifierPattern("<error>")` terminal, the 3 `SimpleTypeReference("<error>")` parameter/field/new
substitutes, every `<error>`-named declaration / member / parameter / property / attribute / pattern-segment
placeholder (incl. the top-level unexpected-token `ClassDeclaration` and the reserved-keyword member), the
constructor's synthetic empty `this()`, the local function's synthetic empty block, the `on` recovery lambda,
and ParseOperatorSymbol's `"+"` default. FIVE structural fixes landed with it: MULTI-LINE `SourceSpan` (the
4-arg primary constructor emits — no new factory needed; the single-line gate is retired), the type gate no
longer declines on panic/errors/multi-line, the TOP-LEVEL recovery-boundary column save/restore Parser.cs does
and the owner did not, `Trim('"')` on unterminated test descriptions, `ref struct`'s `isRefStruct`, and the
interpolation-hole span resolution. PROOF (whole tree AND the full diagnostic stream, via an extended
throwaway triangulation probe): **407/407** recorded in-repo files (was 404) and **513/513** of every `.nl` in
the tree; **453/453** malformed diagnostic-corpus sources (was 262); **10,560/10,560** LSP-shaped fuzz mutants
(truncation / char-deletion / line-deletion / garbage-injection) across 3 seeds — **11,526 sources, 0
mismatches**. Contracts +26 net → 1,550/1,550, ZERO retained declines. dev.sh Parser 384/384. Owner member
count UNCHANGED at 280 (wall respected: reproductions inlined, one new parameter + one new FIELD; two
now-dead gate fields deleted). Production
untouched [ParseFileAst still test-only, zero callers], no LSP change, no repin, no wall. The owner is a
DROP-IN for Parser.cs; the N+2 cutover is now pure WIRING)

Last updated (prior): 2026-07-29 (STAGE N+1c TRANCHE 10 LANDED — **STATEMENT BODIES: `BlockStatement` + the WHOLE Statement
node family, and the member-BODY consumers**. Recut into two halves, both landed: 10a = BlockStatement, every
statement kind (let/const/readonly + typed + tuple deconstruction, expression/empty statements, if/else, while,
C-style + for-in for, foreach / await-foreach, return, print, yield, break, continue, throw, preprocessor, off,
try/catch/finally, using, lock, switch + SwitchCase, unsafe, alloc, assert + assert-throws, allow) and the
BLOCK-BODIED LAMBDA — retiring the LAST expression-side decline; 10b = the consumers — function / method /
constructor / property / indexer BODIES, local functions, the test/setup/teardown DSL declarations, and the
top-level + member PreprocessorDeclaration. FOUR recorded owner-vs-Parser.cs divergences were retired en route:
the top-level `func` now routes through the SAME full ParseFunctionDeclaration reproduction as the member path
(the Stage-3 reduced vehicle + 5 dead helpers DELETED), the parameter list models Parser.cs's FULL grammar
(params/ref/out, `this`, scoped/lifetime, defaults, the recovery boundary), `ParseModifiers` no longer eats
`readonly` (which was swallowing the flag on every readonly field), and `foreach (x in y)` parens are modelled.
**WHOLE-FILE SWEEP: 404 of 407 in-repo `.nl` files now parse byte-exact owner==Parser.cs — up from 26.** The 3
residuals are principled no-stub declines of Parser.cs RECOVERY ARTIFACTS (an `is` pattern-variable capture with
no same-line guard; a `>>`-split nested generic whose type node gets a multi-line span), not parity gaps.
Contracts +82 net → 1,524 / 1,524 PASS. dev.sh Parser slice 384/384. NEW CONSTRAINT RECORDED: the owner class has
reached the columnar front-end's per-class MEMBER CEILING — adding ANY member function trips
`NL103 … parse.struct`; the tranche's helper was inlined instead (raising it means a kernel change = the
two-stage bootstrap wall). Production untouched [ParseFileAst still test-only, zero callers], no LSP change, no
repin, no wall)

Last updated (prior): 2026-07-29 (RATCHET + PARITY REMEDIATION of `170244a5f` "Fix infinite loop in ParseTestDeclaration
table-case recovery" — a CORRECT fix landed by a separate session that (a) exceeded the IMMUTABLE E0 epoch ceilings on
BOTH files it touched and (b) skipped the N# parity mirror, so the ownership audit failed with 6 violations
[OWN004+OWN005 on each file] and broke the integration gate. BOTH debts are now PAID, no behavior change:
(1) LOSSLESS COMMENT COMPRESSION back under the ceilings. `Parser.cs` 7,128/6,192 → 7,116/6,180 vs epoch 7,117/6,183
(six XML-doc `<summary>` collapses; PROVEN zero functional change — strip every whole-line comment + blank from HEAD and
from the compressed file and the remaining 5,872 code lines are BYTE-IDENTICAL). `ParserErrorTests.cs`
1,944/1,609/568 → 1,923/1,588/563 vs epoch 1,923/1,592/563 — paid as 10 comment lines (2 XML `<summary>` collapses +
the 10-line tuple-double-failure block reflowed to 7 + 3 one-line reflows), 6 standalone comments merged to trailing
comments on the single statement each annotates (the file's own existing idiom), and 5 GENUINELY-SUBSUMED assertions
deleted for the marker budget, each in a LinterTests-precedent class: `Assert.Contains(c, pred)` immediately followed
by `c.First(pred)` [x3 — First(predicate) throws when nothing matches, so Contains adds no coverage],
`Assert.NotEmpty(c)` immediately followed by `Assert.Contains(c, pred)` [Contains-with-predicate cannot pass on an
empty collection], and `Assert.NotNull(error.Message)` immediately followed by `Assert.NotEmpty(error.Message)`
[NotEmpty strictly implies non-null, and `CompilerError.Message` is NON-nullable so no nullable-flow warning appears].
A code-only diff (whole-line comments + blanks stripped) shows EXACTLY those 5 deletions plus 6 lines that differ only
by an appended trailing comment — nothing else. (2) THE N# PARITY MIRROR the original fix skipped:
`ColumnarParserRecovery.nl`'s `ParseTestDeclaration` table-case loops now carry the SAME no-progress guards
(`rowStartPosition`/`itemStartPosition` captured from `Position`, `break` when an iteration consumed nothing) — the
owner's `ConsumeToken` does NOT advance on mismatch either, so it reproduced the hang faithfully. +4 parity contracts
for the shapes that PREVIOUSLY HUNG, golden values from the freshly built Release CLI oracle (`nlc check --json`,
filtered to parser codes NL101-NL109): `test "d" with (a) 9 { }` and `test "d" with (a) [ 9 ] { }` both terminate on
the single parameter-`:` NL102 @(1,16,1) (the table-case Consume reports are panic-suppressed behind it), and the
typed-header variants `test "d" with (a: int) 9 { }` / `test "d" with (a: int) [ 9 ] { }` — added so the guard's OWN
reported diagnostics are pinned, not just termination — terminate on the table-`[` NL102 @(1,24,1) and the row-`(`
NL102 @(1,26,1). The Stage-16 EOF-pinned row contracts are UNCHANGED and still green (their loops end on `IsAtEnd()`,
never on the guard). EVIDENCE: ownership audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`);
BootstrapServices contracts 1,442/1,442 via the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices
-c Release -p:NSharpExcludeTests=false` (1,438 baseline + 4); full unit suite `dotnet test tests/Tests.csproj
-c Release`; dev.sh Parser slice. RATCHET REPIN (current* + fingerprints ONLY; every epoch* value and
epochPath/epochFact fingerprint untouched, re-validated after the write): Parser.cs currentLines 7117→7116,
currentNonBlankLines 6183→6180, fingerprint `text-v1:895641da1f9de8a6`→`text-v1:a22d50fc70a12d42`;
ParserErrorTests.cs currentLines 1923→1923, currentNonBlankLines 1592→1588, currentAssertionMarkers 563→563,
fingerprint `text-v1:5a291d0279aea87f`→`text-v1:5e650e2c1d8ae677`; reviewedHeadFingerprint
`head-v1:1be7f7cb4c07e417`→`head-v1:682bbdb2c76e50c8` in BOTH the manifest and the mirrored
`OwnershipPolicy.ReviewedHeadFingerprint` constant. NET non-N# change is −33 lines across the two C# files; all new
code is N#. No production/LSP wiring change → no VS Code gate, no extension reload)

Last updated (prior): 2026-07-29 (STAGE N+1c tranches 9b + 9c LANDED — THE EXPRESSION SURFACE IS COMPLETE. 9b = the
ARGUMENT/ELEMENT-LIST forms: postfix CALL (CallExpression over an owned `ParseArgumentList` that now RETURNS the
byte-exact `List<Argument>` — named / spread / ref / out / inline-out / bare-alloc argument shapes — plus the
split-`>>`-aware generic-call `List<TypeReference>`), `with` (WithExpression + PropertyInitializer), `new`
(NewExpression: target-typed / traditional / sized-array-length / object-vs-COLLECTION initializer), tuples
(named + unnamed TupleElement), array + immutable-array literals, and alloc / stackalloc. 9c = the LAST
expression families: match (MatchExpression + MatchCase + the FULL 12-node Pattern grammar), interpolated
strings (InterpolatedStringExpression + text/hole parts incl. format clauses and brace escapes), and lambda
literals (implicit `var` parameter lists + expression bodies). BONUS PARITY FIX: the owner's recorded "does not
know the receiver's array-ness" approximation is RETIRED — `new T[] { a, b }` now takes Parser.cs's collection-
initializer branch (it previously emitted two spurious missing-colon NL102s). BONUS CONSUMER: argument-bearing
ATTRIBUTES (`[Attr(1)]`) now materialize, retiring the tranche-4 decline. VERIFIED owner==LIVE-Parser.cs whole-
tree via a throwaway fresh-Compiler AstToJson probe: 79/80 synthetic + field-init + attribute + whole-file
shapes MATCH (0 unexplained mismatches; the sole non-match is the BLOCK-bodied lambda, whose body is a
BlockStatement — the intended statement-tranche no-stub deferral), and a WHOLE-FILE sweep of all 407 in-repo
`.nl` files shows 26 parsing byte-exact owner==Parser.cs. +79 net contracts → 1,438 total / 1,438 PASS via the
canonical `dotnet test -c Release`. dev.sh Parser slice 384/384. Production untouched [ParseFileAst test-only],
no LSP change, no repin, no wall. REMAINING before the N+2 cutover: expression-bodied members + STATEMENT BODIES
[BlockStatement + the whole Statement node family])

Last updated (prior): 2026-07-24 (STAGE N+1c tranche 9a LANDED — the SINGLE-OPERAND / TYPE-CARRYING postfix + keyword-
primary expression forms: postfix MEMBER `.`/`?.` (MemberAccessExpression) + INDEX `[…]`/`?[…]`
(IndexAccessExpression), is/as (IsExpression + optional pattern variable / CastExpression Safe), await/must/throw
(AwaitExpression/MustExpression/ThrowExpression via ParseUnaryOperandOrMissing → Expression?), and the keyword
primaries typeof/nameof/sizeof/checked/unchecked (TypeOfExpression/NameofExpression/SizeOfExpression/
CheckedExpression/UncheckedExpression) + cast `(T)expr` (CastExpression Hard) + spread `...expr`
(SpreadExpression) now all MATERIALIZE byte-exact via the ExprResult.Node gate [every present operand non-null →
materialize; else decline no-stub]; type operands route through the shared ParseMaterializedTypeReference gate.
The ARGUMENT/ELEMENT-LIST forms [call/with/new/match/tuple/array/immutable-array/interpolated-string/lambda]
stay per-form no-stub gated for tranche 9b. VERIFIED owner==LIVE-Parser.cs whole-tree via a throwaway fresh-
Compiler AstToJson probe on 24/24 synthetic + field-init + whole-file shapes [0 mismatches; the 2 tranche-9b
declines F()/new T() correctly show live-materializes-vs-owner-declines]; +25 net contracts [20 postfix/keyword
positives + 3 field-init + 1 whole-file 3-member enum + 3 negative self-checks − 2 tranche-8 is/member declines
converted to positives] → 1,359 total / 1,359 PASS via the canonical `dotnet test -c Release` [the 3
ExternalAssemblyScan Debug-layout tests trip on a clean rebuild — the documented Debug CLI rebuild fix restores
full green, coordinator-confirmed]. Production untouched [ParseFileAst test-only], no LSP change, no repin.
Tranche 9b [the list forms] deferred)

Last updated (prior): 2026-07-24 (STAGE N+1c tranche 8 LANDED — the COMPOSED OPERATOR TIERS: the BINARY tiers [equality/
relational-comparison/shift/additive/multiplicative/bitwise and-or-xor/logical and-or/null-coalesce], RANGE,
UNARY prefix [- ! ~ ++ -- ^] + postfix ++/--, TERNARY, and ASSIGNMENT now MATERIALIZE their byte-exact node over
tranche 7's leaf nodes via the `ExprResult.Node` gate [a tier materializes only when all operands carry nodes;
else declines — no-stub]; CONSUMERS unlocked = richer valued ENUM MEMBERS [composed values, automatic] + FIELD
INITIALIZERS [ParseRequiredExpressionAfter returns the node; FieldDeclaration.Initializer materialized]; VERIFIED
owner==LIVE-Parser.cs whole-tree via a throwaway fresh-Compiler AstToJson probe on 34/34 synthetic + whole-file
shapes [0 mismatches]; +37 tranche-8 contracts [3 tranche-7 'composed-value DECLINES' tests converted to
positive] → 1334 total / 1331 PASS via the canonical `dotnet test -c Release`, the only 3 fails PRE-EXISTING
ExternalAssemblyScan Debug-path infra [confirmed identical on the stashed baseline]; is/as + await/must/throw +
non-leaf primaries + postfix call/index/member/with deferred to tranche 9)

Last updated (prior): 2026-07-24 (STAGE N+1c tranche 7 LANDED — BEGIN EXPRESSION MATERIALIZATION, the LEAF/PRIMARY tier: the int/float/char/string literals, bool/null, default/this/base, identifier, and single-expression parenthesized forms now RETURN their byte-exact Expression node, carried up the ladder via a new nullable `ExprResult.Node` [every operator-composing tier leaves it null → declines]; CONSUMER unlocked = VALUE-BEARING ENUM MEMBERS [EnumMember.Value materialized; Parser.cs :1304 string→String inference replicated]; VERIFIED owner==live-Parser.cs whole-tree on 14 leaf/paren synthetic shapes + WHOLE-FILE DeclarationEnums.nl [5 enums, 26 int-literal-valued members], the 3 composed forms correctly decline; +19 contracts → 1300/1300; the whole composed ladder + non-leaf primaries + field initializers deferred to tranche 8)

## Cursor

- Current task: `tasks/017-semantic-analyzer-ownership.md` (016 ACCEPTED at `53e272711` — Parser.cs
  DELETED, the checkbox's stronger arm; N# is the sole production parser and ordered
  syntax-diagnostic authority. The 016 arc: 17 capability stages + 11 materialization tranches +
  cutover + deletion, 762→1,554 contracts, 27,694-source cutover proof, all landed without a
  single toolset repin.)
- Current iteration: one terminal slice
- Active sub-slice (017 arc, THIS TURN): **017 SLICE 10 — THE `ResolveType` ARC, STAGE 4: THE
  REPORTING AND RECORDING WALK.**
  MANDATED TARGET, recorded verbatim from the coordinator and unchanged BEFORE any production edit:
  the `ResolveType` walk orchestration itself — `ResolveType`'s 9-arm dispatch, `ResolveDeclaredType`
  (the `_reportUnresolvedTypes` opt-in trampoline), BOTH `ResolveSimpleType` overloads (the 8-channel
  name walk), `ResolveGenericType`, `ResolveAnonymousUnionType`, `ReportSoaRowTypeReferenceIfNeeded`,
  `RecordResolvedTypeReference`, `TryResolveDottedNestedType` and the remaining helpers
  (`ResolveTypeReferenceIfPresent`, `ResolveTypeReferences`, `ResolveGenericConstraintTypes`) —
  together with the diagnostic sink they need (the report sites' exact `CompilerError` construction,
  ordering and `_errors` interaction) and the three dedupe/opt-in state pieces
  (`_reportUnresolvedTypes`, `_reportedUnresolvedTypeRefs`, `_reportedSoaRowTypeRefs`).
  THE MEASUREMENT (completed BEFORE any production edit; a throwaway instrumented Release build with
  **58 branch counters** over the whole walk — the 9 dispatch arms, the 8 channels, all TEN report
  sites, both dedupe sets with their suppression outcomes, every semantic-model and binding-map write,
  the snippet source and the span-validity gate — run across all **49 `project.yml` corpus targets**,
  the full 3,193-test unit suite AND **53 purpose-built fixture runs** (50 plus 3 re-run with
  `NSHARP_EXPERIMENTAL_SOA=1`), then reverted — `Analyzer.cs` was byte-identical to `31290556c` again
  before the cut began, `md5 d2fb4067e0d6caf2ea562f1f8ebc9e48`, 21,461 lines / 18,861 non-blank):
  * **THE FIVE-REPORT-SITE CLAIM IS TRUE OF THE NL201/NL207 FAMILY AND FALSE OF THE WALK. THERE ARE
    TEN.** The slice-7/9 records named five (NL201 ×3 shapes, NL207 ×2) and those five are exactly
    right, all in `ResolveSimpleType(string,…)` and `ResolveGenericType`. But the walk ALSO reports:
    **NL103 for `var` used as a type** (`ResolveSimpleType` :18315, the one-argument `Error` overload,
    4 / 4 live in suite / fixtures); **NL103 for a SoA `.Row` reference**
    (`ReportSoaRowTypeReferenceIfNeeded` :18213); **NL306 for a repeated anonymous-union arm** and
    **NL207 for more than two distinct arms** (`ResolveAnonymousUnionType` :18247 / :18263, 3 / 3 and
    4 / 6); and **NL308 via `ReportInaccessibleMember`** (`ResolveSimpleType` :18395, 5 / 1). So the
    diagnostic sink had to reproduce ten sites, not five, and `ReportInaccessibleMember` had to move
    with them — it is a report, its message text is built from the project source provider, and
    leaving it behind would have split one diagnostic across the boundary.
  * **THE RECORDING SINKS ARE ALREADY N# AND ARE ARGUMENT-PASSED — CONFIRMED, and so is a THIRD one
    the earlier records did not name.** `SemanticModel` and `BindingMap` are N# (the slice-8
    precedent), and `_errors` is a `List<CompilerError>` whose element type is N# too
    (`CompilerError.nl`). The list is therefore handed in BY REFERENCE rather than owned, which is
    what preserves report ORDER: the shell's ~218 surviving `Error(` sites and the owner's ten append
    to the same instance, so a diagnostic's position among its neighbours does not depend on which
    side of the boundary produced it. That is a structural guarantee, not a measured one.
  * **THE WHOLE CLOSURE IS ALREADY CLOSED OVER N# OWNERS — THE FINDING THAT MADE THIS A ONE-CUT
    SLICE.** A call-by-call read of all eleven walk members found NOT ONE call back into the shell:
    `_scopes` (N#), `_declarationContext` (N#), `_projectDiscovery` (N#), `_externalTypeProbe` (N#),
    `_bindingMap` / `_semanticModel` (N#), `AnalyzerTypeReferenceFacts` / `AnalyzerWellKnownTypeFacts`
    / `AnalyzerDiagnostics` / `TypeInfoIdentityFacts` / `TypeReferenceFacts` / `SoaFeature` /
    `BuiltInTypes` (N# statics), and `GetUnitNamespace`, which slice 9 had already routed to
    `AnalyzerProjectSourceProvider.UnitNamespace`. The only non-N# thing left was the walk itself.
  * **THE STATE IS THREE PIECES AND TWO OF THEM LEAK OUTSIDE THE WALK.** `_reportUnresolvedTypes` and
    `_reportedSoaRowTypeRefs` are used ONLY inside the walk (plus their reset). But
    `_reportedUnresolvedTypeRefs` has **two `Add` sites outside it** — `AnalyzeNewExpression` :16220
    (the `new Union.Case` inaccessible probe) and `TryResolveIdentifierBindingTarget` :18561 (the
    identifier-binding inaccessible probe) — both immediately after a `ReportInaccessibleMember`, both
    claiming the position so the later NL201 stays silent. Both are live in the fixtures (1 / 1) and
    both now route through the owner's `MarkUnresolvedTypeReported`.
  * **`_currentFilePath`, `_sourceText` AND `_compilationUnit` ARE EACH ASSIGNED IN EXACTLY ONE PLACE**
    (`Analyze` :323/:325/:326), which is what makes a single per-analysis `BeginAnalysis` call exact
    rather than a guess. `_semanticModel` and `_bindingMap` are REPLACED there too (:303/:304), so they
    are passed per analysis rather than held from construction.
  * **LIVE COVERAGE (corpus / unit suite / fixtures).** `ResolveType` **159,195 / 29,565 / 333**, one
    `RecordTypeReference` attempt per call exactly, of which **13 / 34 / 0 have no valid span** and are
    skipped; `rec.model-refused` (a valid span with a non-positive line or column) is **0 / 0 / 0**.
    Dispatch arms: simple 135,472 / 26,873 / 270, generic 10,470 / 1,920 / 26, array 8,009 / 468 / 4,
    nullable 4,918 / 175 / 2, tuple 162 / 18 / 9, byref 78 / 27 / 0, function 77 / 50 / 1, union
    9 / 34 / 21; the unmodelled arm is 0 / 0 / 0 and is preserved. `ResolveSimpleType(string,…)`
    **145,988 / 28,793 / 296** with **59 / 33 / 0 at line 0**. Channels: built-in
    88,854 / 15,641 / 159, scope 13,596 / 5,744 / 35, file-alias **0 / 1 / 1** (plus **0 / 0 / 2**
    claimed-but-missing), dotted-nested **2 / 42 / 14**, project 19,457 / 3,854 / 10,
    **using-alias 0 / 0 / 0**, external 14,237 / 1,443 / 12, unresolved 9,842 / 2,064 / 47.
    `ResolveDeclaredType` **55,067 / 12,909 / 149**, and `rd.nested` — the trampoline re-entered while
    already reporting — is **0 / 0 / 0**, so the save/restore is a real but never-exercised guard.
    Writes: `RecordBinding` scope 13,578 / 5,744 / 35, project 19,429 / 3,854 / 10, file-alias
    0 / 1 / 1; `RecordType` project 19,457 / 3,854 / 10, file-alias 0 / 1 / 1. Generic head:
    line-positive 10,470 / 1,920 / 26 (line 0 is **0 / 0 / 0** in the corpus and suite and only reached
    through the differential), arity-qualified hit 10,323 / 1,785 / 6, definition-from-name
    1,108 / 320 / 17, known-arities 0/1/many **4,0,0 / 19,13,3 / 3,2,1**, caller-opt-in on
    5,247 / 874 / 24 versus off 5,223 / 1,046 / 2. `TryResolveDottedNestedType` 43,538 / 7,405 / 95,
    of which **43,298 / 6,946 / 76 are not dotted at all**, root known 56 / 240 / 14, root unknown
    184 / 219 / 5. The SoA gate is entered 145,942 / 28,793 / 250 times and refuses at the feature flag
    every time in the corpus and the suite; with the flag ON the three SoA fixtures reach **8
    is-row decisions, 2 reports and 6 dedupe suppressions**. Snippets come from the analysed text
    2,425 / 1,742 / 178 times, **from the project snapshot 0 / 0 / 0**, and from nothing 0 / 598 / 0.
  * **EVERY REPORT SITE IS LIVE SOMEWHERE, AND THE ONE DEAD CHANNEL IS THE ONE SLICE 7 ALREADY
    RECORDED.** R1 0 / 0 / 2, R2 115 / 19 / 25, R3 0 / 0 / 2, R4 0 / 1 / 1, R5 6 / 14 / 15, `var`
    0 / 4 / 4, SoA-row 0 / 0 / 2 (flag on), union-duplicate 0 / 3 / 3, union-too-wide 0 / 4 / 6,
    NL308-in-walk 0 / 5 / 1, plus the two outside sites 0 / 0 / 1 each. Dedupe SUPPRESSIONS fire
    0 / 7 / 8. The using-alias-as-a-type channel is **0 / 0 / 0** and is preserved verbatim with slice
    7's recorded reason: `RegisterNamespaceImport` only records an alias after `ValidateNamespaceImport`
    proves the target is a namespace and not a type, so it is structurally unreachable, not untested.
  **RESULT: LANDED (no commit — mandate).** `AnalyzerTypeResolver` is the sole authority for the
  analyzer's type-reference resolution — decisions, reports AND records — and `AnalyzerDiagnosticSink`
  for the construction of every semantic diagnostic, with no callback, fallback, shadow path or
  comparison route anywhere.
  DELETIONS (exact, **13 whole C# members + 3 gutted bodies + 3 fields, 565 deleted lines**):
  * `ResolveDeclaredType` :18019 (21 incl. the `// Type resolution` section comment and its 7-line
    XML doc) — the `_reportUnresolvedTypes` opt-in trampoline;
  * `ResolveType` :18041 (23) — the 9-arm dispatch;
  * `ResolveSimpleType(SimpleTypeReference)` :18065 (9) and `ResolveGenericType` :18075 (121) — the
    whole generic head with its three reports;
  * `ReportSoaRowTypeReferenceIfNeeded` :18197 (27), `ResolveAnonymousUnionType` :18225 (49),
    `RecordResolvedTypeReference` :18275 (8);
  * `ResolveTypeReferenceIfPresent` :18284 (7), `ResolveTypeReferences` :18292 (7),
    `ResolveGenericConstraintTypes` :18300 (10);
  * `ResolveSimpleType(string,int,int)` :18311 (118) — the 8-channel name walk;
  * `TryResolveDottedNestedType` :18453 (26);
  * `ReportInaccessibleMember` :20697 (11) — NL308 moves with the other nine reports;
  * `Error(ErrorCode,…)` 14 → 2, `Warning(ErrorCode,…)` 14 → 2 and `GetSourceSnippet` 8 → 1: three
    zero-policy expression-bodied routes, kept rather than deleted because they have **206, 2 and 38**
    call sites respectively and rewriting those would be churn, not ownership. The two-argument
    `Error(string,…)` and `Warning(string,…)` overloads are untouched and still forward to the
    code-carrying ones;
  * the three fields `_reportUnresolvedTypes` :191, `_reportedUnresolvedTypeRefs` :192 and
    `_reportedSoaRowTypeRefs` :193 with their 3-line comment — the STATE itself, now owned by the N#
    resolver — plus the three `Clear()`/reset lines in `Analyze`'s reset block, folded into
    `_typeResolver.BeginAnalysis(...)`.
  ROUTING: **97 lines, every one mechanical, all inside `Analyzer.cs`** — 2 field declarations + their
  4-line comment, 13 lines in the constructor, 2 lines in `Analyze`'s reset block, 2
  `SetWellKnownTypes` lines at the two `_wellKnownTypes` mutation points (`LoadSystemAssemblies` and
  `Dispose`, exactly where slices 5/6 rebuild their owners — the resolver is TOLD about the new bag
  rather than rebuilt, because rebuilding would drop the dedupe sets mid-analysis), the three routed
  bodies above, and **66 rewritten call sites**: 22 `ResolveDeclaredType`, 32 `ResolveType` (two of
  them `.Select(_typeResolver.ResolveType)` method groups), 4 `ResolveTypeReferences`, 3
  `ResolveSimpleType(name, 0, 0)`, 2 `ReportSoaRowTypeReferenceIfNeeded`, 2
  `MarkUnresolvedTypeReported`, 1 `TryResolveDottedNestedType`, 1 `ResolveTypeIfPresent` and 1
  `ResolveGenericConstraintTypes` — **71 `_typeResolver.` references** in all once `BeginAnalysis` and
  the two `SetWellKnownTypes` calls are counted — plus **8 `_diagnostics.` references** (4 surviving
  `ReportInaccessibleMember` call sites, the 3 routed bodies and `BeginAnalysis`; the walk's own fifth
  `ReportInaccessibleMember` site went with the walk). **NO new C# method, helper, bridge, callback or
  state.**
  `git diff` on `Analyzer.cs` is **+97 / −565 = net −468**; the file is **21,461 → 20,993**
  (non-blank 18,861 → 18,441).
  N# ADDED: `AnalyzerTypeResolver.nl` (**714 lines, ONE class, 23 members** — 16 fields, the
  constructor and 22 methods, of which 10 are public entry points; well inside the per-class ceiling)
  + `AnalyzerDiagnosticSink.nl` (**119 lines, ONE class, 10 members** — 4 fields, the `CurrentFilePath`
  property, the constructor and 5 methods) + `AnalyzerTypeResolver.tests.nl` (831 lines, **22
  contracts**, covering BOTH classes). No other `.nl` file changed.
  SIX NON-MECHANICAL DECISIONS: (1) **THE ERROR LIST IS AN ARGUMENT, NOT OWNED STATE.** The sink is
  constructed with the analyzer's own `List<CompilerError>`. Owning a second list and merging would
  have made report ORDER depend on the merge, and order is what a user sees; passing the list makes
  interleaving with the shell's 218 surviving report sites exact by construction rather than by
  argument. This is the slice-8 `BindingMap` precedent applied to diagnostics.
  (2) **`Error`, `Warning` AND `GetSourceSnippet` WERE ROUTED RATHER THAN LEFT ALONE.** They could
  have stayed, with the sink duplicating the snippet-plus-`Create` policy. Two copies of that policy
  is exactly the drift this task exists to remove, so the three bodies became one-line routes and the
  sink is the single place a `CompilerError` is built. Their 262 call sites are untouched.
  (3) **`ReportInaccessibleMember` MOVED WITH THE REPORTS, NOT WITH THE WALK.** It was called from five
  places, only one of which is in this walk (that one went with the walk; four remain). Splitting it — walk-report in N#, shell-report in C# —
  would have left one diagnostic with two producers and two message-building paths. It is a pure
  function of the name, the declaring file and the project source provider, so it moved whole and all
  five sites route to it.
  (4) **THE GENERIC HEAD BECAME ITS OWN MEMBER, AND THE OPT-IN DISCIPLINE IS THE REASON.**
  `ResolveGenericType` was 121 lines with a save/force-off/restore around one call and three reports
  that consult the SAVED value rather than the live one. Splitting the head into
  `ResolveGenericHead(generic): TypeInfo?` makes that separation structural: the probe's suppression
  cannot leak past the member boundary, and each report's guard names `previousReport` explicitly.
  (5) **THE DEDUPE SETS ARE `Dictionary<(Name,Line,Column), bool>`, NOT `HashSet<…>`.** A tuple-keyed
  `HashSet` is not on the columnar surface while a tuple-keyed `Dictionary` is (`SemanticModel.nl` and
  `PerformanceFactStore.nl` both use one, the latter with a nullable string element). `HashSet.Add`'s
  add-and-tell-me semantics are reproduced by `ContainsKey`-then-assign, and the key's equality is the
  same `EqualityComparer<ValueTuple<…>>.Default` in both, so string components compare ordinally
  exactly as before.
  (6) **THE PROJECT DECLARATION'S NULL GUARD IS PROVED, NOT ADDED.** `RecordBinding` takes a
  non-nullable `SymbolDeclaration` while `ResolveVisibleProjectType`'s `out` parameter is nullable, so
  N#'s own analyzer refuses the call (NL202). Rather than widen `BindingMap`'s public API or invent an
  exception, the call site narrows — and the comment records WHY it can: `TryMaterializeProjectTypeSelection`
  assigns a materialised declaration on its ONLY success path before answering true, so the narrowing
  is unreachable. The same NL202 pressure produced three more shape changes, all behaviour-preserving:
  the snippet's `?? ""` chain became explicit branches, and the two `LookupType(x) ?? Unknown` sites
  became two-armed calls into `ResolveDeclaredAlias`.
  PROOF — DIFFERENTIAL AGAINST THE C# ORIGINALS. One throwaway xunit probe, written ONCE and run in
  BOTH trees — the baseline `31290556c` in a throwaway `/tmp/nsharp017s10` worktree and the working
  tree. Both transcripts are **byte-identical, 79,911 COMPARED CELLS, 0 MISMATCHES, md5
  `38a9feeebfb89dc97354a3738e88e223` in both trees**, with **69,433 non-default answers, 9,289
  diagnostic rows, 19,906 semantic-model type-reference rows, 838 binding rows and 0 thrown cells**.
  The reported diagnostics inside the transcript cover **NL201 ×497, NL207 ×882, NL103 ×488, NL306
  ×3,406, NL903 ×4,008, NL308 ×3, NL301 ×3 and NL704 ×2**. THE WIRING IS PROVEN SEPARATELY AND
  EXPLICITLY: four `HOST.*` rows — excluded from the byte comparison and reported on their own — say
  `Analyzer` in the baseline and **`AnalyzerTypeResolver` in the working tree**, and every walk cell
  is driven through whichever side hosts the member; on TOP of that, five SURVIVING shell members with
  identical signatures in both trees (`ResolveDefaultEnumTypeName`, `ResolveTypeWithSubstitution`,
  `TryResolveIdentifierBindingTarget`, `ReportSoaRowTypeReferencesInAttributeTypeof`,
  `TryResolveSourceAttributeCandidate`) plus `GetSourceSnippet` are probed at every grid point, so in
  the working tree those very calls execute the ROUTED owner. The grid: **5 single-file shapes** (empty;
  every declared family including nested, generic and non-generic classes; an alias that shadows a
  built-in and a class named `List`; the GLOBAL namespace) × **53 probe names** (every built-in
  keyword, `var`, declared and undeclared names, near-misses, dotted, doubly-dotted, degenerate `.`
  and `..`, empty, `_`, CLR spellings both bare and qualified, and `.Row` spellings) × 4 operations
  each, plus **129 TypeReference SHAPES** (every family, composed two deep, at a position and at line
  0, arities 0–3 over 18 generic and non-generic heads, a span-carrying union and a span-less array)
  × 6 operations; plus **4 multi-file PROJECTS materialised on disk** (cross-namespace exported and
  non-exported, a file-import alias with an exported, a non-exported and a missing member, the
  unique-exported fallback, and the same name in two namespaces so the fallback must refuse) and a
  **SoA project probed with `NSHARP_EXPERIMENTAL_SOA=1`** over 6 row spellings. Every shape is run
  five ways: on a FRESH analyzer per cell; on ONE long-lived analyzer replaying the whole sequence
  three times (forward, forward, reversed) so the dedupe sets and the probe cache are pinned WARM;
  with NO `LoadSystemAssemblies` (the live `_wellKnownTypes == null` state); across a SECOND `Analyze`
  on the same analyzer (so `BeginAnalysis`'s clearing of both dedupe sets is pinned); and AFTER
  `Dispose`. Diagnostics are compared by CODE, LINE, COLUMN, LENGTH, SEVERITY, FILE, full MESSAGE,
  SUGGESTION, SNIPPET, human explanation, contextual hint and docs URL — the full `CompilerError`
  surface — and the semantic model and binding map are compared entry by entry. The probe was DELETED
  from both trees after the run (`git status` shows no probe residue in either).
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `31290556c` in the throwaway worktree and at the working tree (both trees' Debug CLIs built too —
  the recorded environmental artefact), over **49 `project.yml` corpus targets (ORACLE_TARGETS=49)**:
  **ORACLE_DIFFS=1, ORACLE_STDERR_DIFFS=0 and ORACLE_EXIT_DIFFS=0**. The single diff is the
  `checkedFiles` count on BootstrapServices rising by exactly the number of new `.nl` files
  (284 → 286); every diagnostic on every target, including that project's 281 pre-existing errors, is
  byte-identical. **An earlier revision of this slice made that number 285 rather than 281** — four new
  NL202 nullability reports on the new `.nl` files — and that is what forced decision (6): the four
  shapes were rewritten until the analyzer's own verdict on the new sources was clean. Plus **53
  fixture runs firing 238 diagnostics, FIXTURE_DIFFS = 0**: 50 fixtures covering every report site and
  every channel (near/far/short unresolved names with their did-you-mean and generic suggestions; a
  dotted name staying lenient; the same name twice at one position; fields, properties and returns;
  file-alias hits, misses and a non-exported member; unknown and dotted generic names; multi-arity
  `Tuple` and `Nullable`; local generics at too many and too few arguments; a non-generic given
  arguments; an external at the wrong arity; type arguments on all eight declared families and on four
  GENERIC ones; `var` as a local type and as a parameter type; duplicate, three-armed, nested-flatten,
  clean and unresolved-arm anonymous unions; dotted nested types present and missing; cross-namespace
  exported and non-exported discovery; the unique-exported fallback resolving and refusing; a
  duplicate inside one namespace; an unparseable sibling; a missing namespace import; every declared
  family referenced across a namespace boundary; CLR spellings bare, qualified and missing; composed
  array/nullable/tuple/function shapes both resolvable and not; **both inaccessible-member sites
  OUTSIDE the walk**; and the lenient `typeof`/`is`/`as` positions) — plus the same 3 SoA fixtures
  re-run with **`NSHARP_EXPERIMENTAL_SOA=1`**, which is the only population in which the `.Row` report
  is reachable at all.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, the established explicit PE/CLI normaliser
  touching ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries
  AND the CodeView blobs they point at, and the `#GUID`/`#Pdb` metadata heaps): **72 / 72 comparable
  assemblies BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (34 product assemblies
  from the 36 corpus targets that build standalone, 38 single-file examples), **SINGLE_LOG_DIFFS = 0**,
  and **SKIPPED_TARGET_DIFFS = 0** — the 13 targets that do not build standalone fail with byte-identical
  output and the same exit code in both trees.
  ASSERTION MIGRATION: all 13 deleted members were `private` and the three gutted bodies stay, so no
  test named any of them; a grep over `src/` + `tests/` + `editors/` finds no external consumer of any
  of them. Their behaviour was pinned only INDIRECTLY by end-to-end analyzer diagnostics, which STAY
  and now execute against the N# owner (the slice-1…9 precedent). The DIRECT pinning is new and
  native: **22 contracts** covering the sink's shared-list ordering with a shell report on either side
  of an owner report; the file/severity/length/suggestion stamp and the snippet coming from the
  diagnostic's OWN line; no-text, empty-text, line 0 and past-the-end all meaning no snippet, and a
  code with no catalogue entry keeping a null suggestion rather than being given invented advice;
  NL308 naming the declaring namespace read from DISK, `<global>` for a file that declares none and for
  an absent file, and a minimum length of one; the channel ORDER in both directions (a declared `int`
  cannot shadow the keyword, a scope type answers before the fallback, and the fallback is a
  placeholder rather than an error type); line 0 resolving while recording nothing, and a positioned
  scope hit recording a binding that points at the DECLARING file and column — with the
  no-declaration-location case proven to resolve and record NOTHING; the NL201 opt-in being off by
  default, on inside a declared-type position, off again afterwards, silent at line 0 and silent for a
  dotted name, and reporting exactly once per position but again at a different one; the dedupe set
  being shared with the shell's own `MarkUnresolvedTypeReported` in both directions and cleared by a
  new analysis; the did-you-mean suggestion built from the names actually in scope with the far-miss
  fallback; `var` refused WITHOUT consulting the opt-in and WITHOUT being deduped, and — measured, not
  assumed — falling through to the placeholder at line 0; all nine dispatch arms including the
  unmodelled one, composed two deep, with an unnamed tuple element keeping its null name; the
  per-reference record landing at the reference's own start span and being skipped for a span-less
  reference; both NL207 wordings with their suggestions, underlining the NAME and not the reference,
  the correct arity staying silent and carrying the declaration as its definition; the head probe
  suppressing its own report while the caller's opt-in still decides, and a dotted generic staying
  lenient; a line-0 generic resolving its arguments with no definition and no diagnostic; the nested
  union FLATTENING; the duplicate arm being reported AND dropped so the union is not also over-wide;
  the over-wide report; a span-carrying union underlining its whole width while a span-less one falls
  back to one column, and an empty union being silent; the dotted walk requiring a root IN SCOPE,
  dropping empty segments, and refusing a single segment, a separator-only name, an absent root and an
  absent member — all as misses rather than reports; and the SoA gate in all four of its refusals plus
  the report, its own dedupe, its short-circuit through the reference walk, and its set being cleared
  by a new analysis.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 4m36s —
  exactly the slice-1…9 baseline, zero drift); BootstrapServices contracts **1,675 → 1,697** (+22) via
  the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false`, **1,697 / 1,697 PASS** (the 3 ExternalAssemblyScan Debug-layout tests
  DID trip once, immediately after the IL sweep deleted the Debug output layout, and passed again as
  soon as the Debug CLI and test assembly were rebuilt — the recorded environmental artefact, not a
  regression); ownership audit **18 / 18** (`nlc test --project tests/native/ownership-audit`, 1.3s)
  after the repin; `./scripts/dev.sh --since` **PASS** — it correctly took the FULL unit-suite
  fail-safe (the three new `.nl` paths plus `OwnershipAudit.nl` are unmapped), **3,193 / 3,193 in
  Debug, done in 3m38s**; the differential, oracle, fixture and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s10.py` (slice 2…9's script, unchanged apart from its
  header) — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs`
  currentLines 21,461 → **20,993**, currentNonBlankLines 18,861 → **18,441**, fingerprint
  `text-v1:5f42f09ea77d4c6a` → `text-v1:bf70afa68307e4ba` (epoch ceilings 23,451 / 20,537 PRESERVED and
  now clear by **2,458 / 2,096**); `reviewedHeadFingerprint head-v1:459f3828f6f19ed3` →
  `head-v1:4c3ea64acc280913`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` (381) untouched and RE-VALIDATED by recomputation after
  the write; the script self-checks by reproducing all three composite fingerprints over the 381 rows
  before changing anything. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND after,
  and the `git diff` is exactly 2 changed lines.** The `.nl` additions need no row.
  .nl GOTCHAS ADDED (two, both found by building, both bisected):
  * **A `return` INSIDE A `try` WITH A `finally` IS NOT A RETURNING PATH.** `try { return X } finally
    { … }` in a value-returning member reports **NL305** ("not all code paths return a value") at the
    member's own signature line. Assigning to a local inside the `try` and returning AFTER the
    `finally` is the equivalent shape and binds — and it is exactly equivalent, because the `finally`
    still runs on exception propagation. This is a TYPE-CHECK report, not a columnar decline, so it is
    the first of this family that a plain `nlc build` catches by itself.
  * **`union` IS RESERVED AND CANNOT BE A PARAMETER OR LOCAL NAME.** `func F(union: UnionTypeReference)`
    declines the WHOLE class at `parse.struct`, reported at the class declaration rather than at the
    parameter — the same shape as slice 1's `type`, slice 4's `newtype`, slice 5's `record`, slice 7's
    `partial` and slice 9's `file`. `unionReference` is fine. This one cost a two-stage bisection
    because the first suspect was the property access on the call result in the same expression.
  .nl POSITIVES CONFIRMED (recorded because they were expected to be problems and are not, each
  proven by an isolated columnar-emit probe inside BootstrapServices rather than assumed): **a tuple
  LOCAL literal binds** (`key := (Name: n, Line: l, Column: c)`), and so does a **tuple-keyed
  `Dictionary` field with a string element** through `ContainsKey` and the indexer; **`.ToString()` on
  a member-access chain and on an indexer result bind** (`h.Items.Count.ToString()`,
  `items[0].ToString()`) — the recorded "chained call on a member-access or call result" gotcha does
  NOT extend to these; **`continue` inside a `while`**; **`value as string == null` as a whole
  expression**; **`name.Split('.')` with `raw.Length` and `raw[i].Length`**; **a `SourceSpan` struct
  local returned from a static call, then read**; and **a nullable argument passed to a non-nullable
  parameter EMITS** (it is the analyzer's NL202, not the columnar backend, that refuses it).
  DOCS: `memory/components/analyzer.md`'s "The type-reference resolver" section is rewritten — the
  stale "the walk itself stays in the shell" claim is replaced by the ownership statement, and five new
  subsections record the eight channels with the dead-but-preserved using-alias arm and the `line <= 0`
  rule (including the deliberate `var` asymmetry), all TEN report sites with the opt-in and the head
  probe's suppression, the two dedupe sets and the sharing with the shell's two outside sites, the
  three record kinds with their readers, and the sink's shared-list ordering guarantee; the
  "not movable yet" note now names `CreateFunctionTypeInfoInDeclarationContext` as the last remaining
  C# piece of the resolution surface; and the two new owners join the file list.
  `memory/architecture.md`'s Analyzer entry now lists all sixteen owners.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability
  needed, and no repin of the packaged toolset. Both new gotchas were routed AROUND rather than
  through: the `try`/`return` shape by assigning to a local, and the reserved `union` name by renaming.
  The packaged 0.1.0 SDK self-emits both new classes and their 22 contracts.
  GATES: **INCOMPLETE — the full VS Code-enabled `./scripts/test-all.sh --commit` did NOT finish and
  is NOT green. This is recorded as an OPEN item, not as a pass.** The run went into a fresh isolated
  copy (`/private/tmp/nsharp-test-all.55ed0f93ea78.2mOSe3/repo`); the log says "Fresh isolated test run
  required: pre-commit verification" and "Existing cache entries will not satisfy this invocation", so
  it was neither a cached whole-gate nor a cached per-step verdict. What it DID reach:
  * **Step 1 clean, Step 2 compiler build, Step 2b format contract gate — PASSED.**
  * **Step 3 unit tests — PASSED, 3,193 / 3,193** (3m34s inside the gate).
  * **Step 3a native N# tests — PASSED, all 22 projects**, including BootstrapServices'
    **1,697 / 1,697** and `tests/native/ownership-audit`, which is the ratchet re-validated inside the
    gate against the freshly written manifest.
  * **Step 3b VS Code integration smoke — FAILED: 35 passing, 1 failing.** The one failure is
    `Diagnostics > diagnostics clear after fixing syntax error`, and it is a **mocha TIMEOUT** ("Timeout
    of 45000ms exceeded"), not an assertion. Every other diagnostics test passed, including
    `diagnostics update after introducing syntax error` — the same file, the same server, the
    diagnostic direction that this slice's resolver actually produces. The step took **19m 15s**
    against the 41s / 2m18s recorded for slices 7 and 9, a 10–25x slowdown of the same suite on the
    same machine, which is the recorded load/thermal-flake signature rather than a behavioural one.
    **It is NOT dismissed on that basis: it must be re-run cool and serially before this slice is
    accepted, and if it reproduces it is a real regression in diagnostic CLEARING.**
  * **Step 4 pack/install SDK — TERMINATED (signal 15) 17m41s in**, when the session's own watchdog
    killed the run. Everything after it — SDK install, template pack/install/creation, the
    template-generated project, all example projects, single-file examples, `nlc check` over the
    examples and the ECMA-335 IL verification gate — **did not run at all**.
  `./scripts/reload-vscode-extension.sh` was **NOT run**. It IS required for this slice on the slice-7/9
  precedent — no LanguageServer source changed, but `Analyzer.cs` ships in the `NSharpLang.Compiler`
  assembly the language server builds against and `NSharpLang.Compiler.BootstrapServices` gained two
  public types — so it is part of the outstanding work, not something this slice can claim.
  INTERACTIVE computer-use verification was NOT attempted, per the coordinator's standing instruction
  that it owns that record.
  WHAT IS PROVEN INDEPENDENTLY OF THE GATE, and what makes the outstanding item bounded rather than
  open-ended: the unit suite (3,193 / 3,193 in Release standalone AND inside the gate), the contracts
  (1,697 / 1,697 both ways), the audit (18 / 18), `dev.sh --since`, the 79,911-cell differential, the
  49-target oracle, the 53 fixture runs and the 72 / 72 IL sweep were all run and are all green. The
  two IDE-facing surfaces this slice touches are pinned rather than assumed — the `SetProjectSourceTexts`
  snapshot (unchanged by this slice) and the semantic model / binding map that hover and
  go-to-definition read, compared entry by entry at every one of the differential's grid points.
  **OUTSTANDING BEFORE ACCEPTANCE: re-run the full VS Code-enabled gate cool and serially, and run
  `./scripts/reload-vscode-extension.sh`.**
  **NEXT SUB-SLICE — STAGE 5 OF THE `ResolveType` ARC: THE ASSIGNABILITY SCC, IN ONE CUT, EXACTLY AS
  SLICE 6 MEASURED. Its sole blocker is gone.** Slice 6 recorded that the assignability closure could
  not be cut because it bottoms out in `ResolveType`; `ResolveType` is now N#-owned end to end, and so
  are the seven owners the SCC also consults (`AnalyzerConversionFacts`, `AnalyzerClrTypeConversion`,
  `AnalyzerAssignabilityFacts`, `AnalyzerWellKnownTypeFacts`, `AnalyzerDeclarationContext`,
  `TypeInfoIdentityFacts` and now `AnalyzerTypeResolver` itself). Stage 5 also inherits the two pieces
  this slice built and which every later analyzer slice needs: an N#-owned DIAGNOSTIC SINK that can
  emit any `CompilerError` in the analyzer's own report order, and the `BeginAnalysis` per-file
  handshake for the semantic model and binding map. Nothing in the assignability closure needs a
  capability the compiler does not already have.
  TWO SMALLER PREREQUISITES REMAIN RECORDED AND UNCHANGED: `CreateFunctionTypeInfoInDeclarationContext`
  / `CreateFunctionTypeInfo` (32 live calls, and the last C# piece of the resolution surface) still
  needs the reflection half of `NullabilityMetadata`, which lives ABOVE BootstrapServices; and
  `Assembly.get_FullName` / `AssemblyName.get_Name` on the columnar external binding surface would
  release the metadata half of `NamespaceExists` and `GetExternalSearchAssemblies` together. The
  one-argument `Dictionary.Remove` analyzer-overload-table gap from slice 8 is still open and still
  unrelated to this arc.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `31290556c`): **017 SLICE 9 — THE `ResolveType`
  ARC, STAGE 3: PROJECT DISCOVERY.**
  MANDATED TARGET, recorded verbatim from the coordinator and unchanged BEFORE any production edit:
  `Analyzer.cs`'s `TryResolveVisibleProjectType` family — `TryResolveVisibleProjectType`,
  `TryResolveProjectTypeInNamespace`, `TryResolveUniqueExportedProjectType`,
  `TryMaterializeProjectTypeSelection`, `TryReportInaccessibleVisibleProjectDeclaration` — together
  with the source-text/unit provider they are blocked on (`EnumerateProjectSourceTexts`,
  `GetProjectCompilationUnit`, `TryGetProjectSourceText`, `ProjectConfig.EnumerateSourceFiles`) and
  its caches (`_projectSourceTexts`, `_projectCompilationUnitCache`, `_projectNamespaceCache`, and
  the fourth cache the slice-7/8 records did not name, `_projectFileNamespaceCache`).
  THE MEASUREMENT (completed BEFORE any production edit; a throwaway instrumented Release build with
  47 branch counters over the whole family, run across all **49 `project.yml` corpus targets** AND the
  full unit suite, then reverted — `Analyzer.cs` was byte-identical to `bd11ad61d` again before the
  cut began):
  * **THE PREREQUISITE WAS ALREADY SATISFIED AND THE SLICE-7/8 RECORD WAS STALE.** Every piece the
    provider needs is ALREADY N#: `ProjectConfig.EnumerateSourceFiles` (`ProjectConfigModels.nl`),
    `ColumnarParserRecovery.ParseFileAst` (`ColumnarParserRecovery.nl`, the post-cutover N# parser —
    VERIFIED, the shell was already calling it), `CompilationUnit` and every `*Declaration`
    (`Declarations.nl`), `SymbolDeclaration` (`BindingMap.nl`), `DeclarationFacts`,
    `CodeIntelligenceTextUtilities.FindIdentifierNameColumn`, `AnalyzerDeclarationContext` and
    `AnalyzerTypeReferenceFacts.VisibleTypeNamespaces`. So the provider COMPOSES existing N# owners
    and needed no new capability. `File.ReadAllText` / `File.Exists` / `Directory.Exists` /
    `Directory.CreateDirectory` are all on the columnar surface already.
  * **THERE ARE FOUR CACHES, NOT THREE.** `_projectFileNamespaceCache` (file → declared namespace,
    `OrdinalIgnoreCase`) was never named by slices 7 or 8. It is the cache behind `GetNamespaceForFile`,
    and it is what the `InaccessibleMember` diagnostic's namespace text comes from.
  * **THE ENUMERATION ORDER IS LOAD-BEARING — MEASURED, NOT ASSUMED (the slice-7 lesson).** A
    behaviour-neutral second pass over every project unit tallied duplicate
    (namespace, declaration-name, is-function) triples once per `Analyze`. The root corpus target has
    **47 distinct duplicate pairs**: types `Person` ×14, `Point` ×6, `Calculator` ×5, `Program` ×5,
    `Address` ×3, `Logger` ×3 and 10 more, plus the whole `IssueTracker` namespace ×2; functions
    `Main` ×42, `main` ×4, `ClassifyNumber` ×3, `Sum` ×3 and 9 more. The unit suite shows 420 type and
    228 function duplicate counts. So "first file wins" is a DECISION.
  * **BUT THE TWO CHANNELS DIFFER ON DUPLICATES, AND THAT IS THE FINDING THAT SHAPED THE CONTRACTS.**
    `AnalyzerDeclarationContext.TryResolveDeclarationInNamespace` REFUSES a duplicate type name inside
    one namespace (`if !resolved || matchedType != null { return false }` — an ambiguity, not a
    pick), while `TryResolveVisibleProjectFunction` and the inaccessible probe take the FIRST match.
    So the order is decisive for the function channel and the inaccessible probe (whose file name
    reaches the user IN the diagnostic) and irrelevant for the type channel. My first draft contract
    asserted first-wins for the TYPE channel and FAILED — the failure is what found this.
  * **LIVE BRANCH COVERAGE** (corpus / unit suite). `EnumerateProjectSourceTexts` 195,391 / 22,282
    calls: in-memory branch **195,391 / 18,705**, disk branch **0 / 259**, no-root **0 / 3,318** — the
    corpus NEVER takes the disk branch and the unit suite is the only population that does. Yields
    **65,033,078 / 133,391 + 36,360**, i.e. ~333 files per call on the root target;
    `GetProjectCompilationUnit` is called once per yield (**65,033,078 / 169,751**) with
    **65,032,200 / 161,568 cache hits** and only **878 / 8,183 parses** — so the walk is one of the
    hottest paths in the analyzer and the unit cache carries it. `unit.parse-THREW`,
    `unit.parsed-null` and `unit.cache-hit-null` are **0 / 0** — the negative unit cache never fires
    in either population and is preserved verbatim. `TryResolveVisibleProjectType` 62,538 / 9,052:
    namespace hit 28,294 / 4,424, unique-exported hit **476 / 30**, miss 33,768 / 4,593, line ≤ 0
    **28 / —**. `TryReportInaccessibleVisibleProjectDeclaration` 34,259 / 4,642 calls but fires only
    **0 / 7** times (5 type, 2 function) — vanishingly rare and fully live.
    `TryMaterializeProjectTypeSelection` 301,002 / 49,422: resolved 28,828 / 4,666 with the source
    text coming from the snapshot 28,828 / 4,623, **from DISK 0 / 35** and **EMPTY 0 / 8** — both
    fallbacks are live in the suite; `mat.no-declaration` and `mat.blank-filepath` are **0 / 0** and
    preserved anyway. `TryResolveProjectTypeInNamespace` 266,758 / 44,799 (require-exported
    196,578 / 32,017, same-namespace 70,180 / 12,782). `GetNamespaceForFile` 22,498 / 2,975 with
    **408 / 24 cached-NULL hits** and **0 / 2 missing-file** writes — the negative cache is real.
    `GetProjectNamespaces` 1,585 / 1,004 (cache hit 977 / 499); `ProjectNamespaceExists` hit
    206 / 124, miss 1,379 / 880, no-root **0 / 222**. `TryGetProjectSourceText` 64,143 / 13,728 with
    **0 / 3,960 null-path** and **0 / 326 miss** answers.
  **RESULT: LANDED (no commit — mandate).** `AnalyzerProjectSourceProvider` is the sole authority for
  the analyzer's project sources, parsed units and file/root namespace questions, and
  `AnalyzerProjectTypeDiscovery` for the project-discovery walk over them — with no callback, fallback,
  shadow path or comparison route anywhere.
  DELETIONS (exact, **13 whole C# members + 1 gutted body + 5 fields, 369 deleted lines**):
  * `TryResolveVisibleProjectType` :18409 (46) — the whole three-outcome type channel;
  * `TryReportInaccessibleVisibleProjectDeclaration` :18493 (44) — its `Func<Declaration, bool>`
    predicate parameter goes with it;
  * `IsTopLevelTypeDeclaration` :18538 (10) — the `is ClassDeclaration or …` pattern;
  * `TryResolveProjectTypeInNamespace` :18549 (18), `TryResolveUniqueExportedProjectType` :18568 (12),
    `TryMaterializeProjectTypeSelection` :18581 (23), `CreateTopLevelTypeSymbolDeclaration` :18605 (13);
  * `EnumerateProjectSourceTexts` :18619 (26) — the ITERATOR, and `GetProjectCompilationUnit` :18646 (20);
  * `TryGetProjectSourceText` :20023 (10);
  * `ProjectNamespaceExists` :20886 (10), `GetProjectNamespaces` :20897 (23),
    `GetNamespaceForFile` :20921 (25);
  * `TryResolveVisibleProjectFunction` 32 → 18 lines: the walk is one routed call and only the
    `CreateFunctionTypeInfoInDeclarationContext` materialisation stays (the recorded
    `NullabilityMetadata` blocker, which lives ABOVE BootstrapServices);
  * `GetUnitNamespace` 4 → 2, one routed expression body;
  * the five fields `_projectRoot` :169, `_projectNamespaceCache` :201, `_projectFileNamespaceCache`
    :202, `_projectCompilationUnitCache` :203 and `_projectSourceTexts` :205 — the STATE itself, now
    owned by the N# provider — plus the two `Clear()` calls in `Analyze`'s reset block, folded into
    `_projectSources.BeginAnalysis(projectRoot)` together with the `_projectRoot` assignment they sat
    beside.
  ROUTING: **95 lines, every one mechanical, all inside `Analyzer.cs`** — 2 field declarations + their
  3-line comment, 2 lines in the constructor, and 26 rewritten call sites: 3 `ResolveVisibleProjectType`
  (each expanding the old 2-way call into the 3-way answer plus the shell's own
  `ReportInaccessibleMember` + `_reportedUnresolvedTypeRefs.Add`, which is exactly where the C# member
  reported and recorded), 1 `TryFindInaccessibleVisibleFunction`, 3
  `TryResolveProjectTypeInNamespace`, 5 `TryGetProjectSourceText`, 3 `GetNamespaceForFile`, 1
  `ProjectNamespaceExists`, 1 `ContainsSourceText`, 1 `AddProjectUnitsTo` (replacing
  `InitializeDeclarationContext`'s enumerate/parse/add loop), 1
  `AnalyzerProjectTypeDiscovery.IsTopLevelTypeDeclaration` in `ExtractPublicSymbols`, 2
  `SetProjectSourceTexts` body lines, and 4 `_projectSources.ProjectRoot` reads for the `FileResolver`
  sites. **NO new C# method, helper, bridge, callback or state.**
  `git diff` on `Analyzer.cs` is **+95 / −369 = net −274**; the file is **21,735 → 21,461**
  (non-blank 19,094 → 18,861).
  N# ADDED: `AnalyzerProjectDiscovery.nl` (**603 lines, TWO classes, 28 members** —
  `AnalyzerProjectSourceProvider` 15 members / 5 fields and `AnalyzerProjectTypeDiscovery` 13 members /
  4 fields; both far inside the per-class ceiling) + `AnalyzerProjectDiscovery.tests.nl` (650 lines,
  **24 contracts**). No other `.nl` file changed.
  SIX NON-MECHANICAL DECISIONS: (1) **THE THREE OUTCOMES ARE ONE MEMBER, NOT THREE.**
  `ResolveVisibleProjectType(name, currentNamespace, probeInaccessible, out typeInfo, out declaration,
  out inaccessibleFilePath)` returns resolved / inaccessible / absent from a single call, because the
  inaccessible probe runs BETWEEN the namespace sweep and the unique-exported fallback AND SUPPRESSES
  it. Splitting it would have let the shell interleave them wrongly; a nullable-enum result is off the
  surface (the slice-8 gotcha), so the third outcome is an out-parameter. The shell keeps the REPORT and
  the dedupe-set write, in that order, exactly as the C# member did — and crucially does NOT return
  early afterwards, because the C# member returned `false` and its caller carried on through the
  remaining channels with the later `NL201` suppressed by the dedupe set.
  (2) **THE FILE LIST IS SEPARATED FROM THE FILE TEXT, so the walks stay lazy.** The C# iterator read
  every file's text eagerly as it yielded, and callers broke out early; materialising `(path, text)`
  pairs would have read ~333 files per call on a path measured at 195,391 calls / 65 M yields. So the
  provider exposes `SourceFilePaths()` (paths only, cached for the snapshot branch, re-enumerated on
  the disk branch exactly as the shell re-enumerated) and reads text only on a unit-cache MISS. Strictly
  fewer reads, identical file set and identical order.
  (3) **THE INSERTION ORDER IS HELD EXPLICITLY.** A `List<string>` mirrors the snapshot dictionary's
  keys rather than relying on `Dictionary<K,V>` enumerating in insertion order. A repeated path keeps
  its ORIGINAL position and takes the new text, which is what `dict[key] = value` did. Given a decision
  that provably depends on the order, depending on it implicitly was not acceptable.
  (4) **THE KIND TEST IS TYPE IDENTITY, NOT A SPELLING.** `IsTopLevelTypeDeclaration` was cut from
  slice 7 because "a name match is not semantic resolution". It is now
  `declaration as ClassDeclaration != null` once per family over the typed N# AST — the same decision
  the shell's `is ClassDeclaration or …` pattern made. The recorded blocker is RETIRED, not worked
  around. Same for the function test (`as FunctionDeclaration`), which also replaces the deleted
  `Func<Declaration, bool>` predicate parameter with a `wantFunctions: bool` discriminator — there were
  exactly two call kinds.
  (5) **THE CACHE LIFETIMES ARE ASYMMETRIC AND ARE REPRODUCED, NOT TIDIED.** `BeginAnalysis` clears the
  two NAMESPACE caches and nothing else; `ResetSourceTexts` also drops the parsed units, because they
  were parsed from the old texts. The shell's `Analyze` cleared exactly the two namespace caches and its
  `SetProjectSourceTexts` cleared exactly the snapshot plus the unit cache.
  (6) **`_projectRoot` MOVED RATHER THAN BEING DUPLICATED.** The provider owns it and the four
  surviving `FileResolver` sites read `_projectSources.ProjectRoot`, so there is one copy of the root
  rather than two that could drift.
  PROOF — DIFFERENTIAL AGAINST THE C# ORIGINALS. One throwaway xunit probe, written ONCE and run in
  BOTH trees — the baseline `bd11ad61d` in a throwaway `/tmp/nsharp017s9` worktree and the working
  tree. It is driven ONLY through members that exist with the SAME signature in both trees
  (`ResolveSimpleType`, `ResolveIdentifier`, `TryResolveVisibleProjectFunction`, `GetUnitNamespace`,
  `NamespaceExists`, `IsCrossPackageFile`, `ExtractPublicSymbols`, `ResolveFileImportPath`, plus the
  public `SetProjectSourceTexts` / `Analyze` / `GetTypeDeclarationFiles`), so in the working tree the
  very same calls execute the ROUTED N# owner — the wiring is proven, not only the behaviour. Both
  transcripts are **byte-identical, 46,226 CELLS, 0 MISMATCHES, md5
  `720cc579b867b61e52f567eb81a84b26` in both trees**, with **12,408 non-default answers**, **38
  `InaccessibleMember` reports** and **20 function-channel hits**. The grid: **10 project shapes**
  (empty; every declared family exported and non-exported side by side across 7 files of one namespace;
  the GLOBAL namespace; duplicate exported names in one namespace; duplicate NON-exported names; two
  namespaces both declaring the same names; a `package` declaration behind an UNPARSEABLE first file;
  a type reachable only through the project-wide unique-exported fallback; the same exported name in
  two un-imported namespaces so the fallback must refuse; and names that collide with CLR types) × **9
  contexts** (6 fixed plus 3 derived per shape from the shape's own namespaces, so every shape is
  probed from inside its own namespace, from an outsider importing all of them, and from the global
  namespace) × **34 probe names** (every name any shape declares, bound and unbound, exported and not,
  dotted, `_`, empty, a built-in keyword) × **7 operations** — `ResolveSimpleType` with its type, its
  full diagnostic list and the whole binding map, the SAME call repeated to pin the dedupe set, the
  same call at line 0 to pin the no-position path, `ResolveIdentifier` as a value and as a callable,
  `TryResolveVisibleProjectFunction`, and the `GetTypeDeclarationFiles` snapshot — plus per-(shape,
  context) cells for the declaration context's FILE ORDER, `GetUnitNamespace` over every unit and over
  `null`, `NamespaceExists` over 9 candidates, `IsCrossPackageFile` over every file plus a missing one,
  `ExtractPublicSymbols` per file, and `ResolveFileImportPath` over 5 spellings. Each shape is
  MATERIALISED ON DISK under a stable root so the on-disk namespace caches and the import validation
  are exercised for real, and every cell gets a FRESH analyzer so both trees' dedupe sets and caches
  evolve identically. Diagnostics are compared by CODE, ID, LINE, COLUMN, LENGTH, SEVERITY and full
  MESSAGE TEXT — which is what pins `GetNamespaceForFile`, since the `InaccessibleMember` message names
  the declaring namespace. The probe was DELETED from both trees after the run (`git status` shows no
  probe residue in either).
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `bd11ad61d` in the throwaway worktree and at the working tree (both trees' Debug CLIs built too — the
  recorded environmental artefact, since several `tests/native/*` projects reference a Debug
  `Compiler.dll`), over **49 `project.yml` corpus targets (ORACLE_TARGETS=49)**: **ORACLE_DIFFS=2 and
  ORACLE_STDERR_DIFFS=0, with matching exit codes on all 49**. Both diffs are the `checkedFiles` count
  rising by exactly the number of new `.nl` files (root 439 → 441, BootstrapServices 283 → 284); every
  diagnostic on every target, including the pre-existing BootstrapServices errors, is byte-identical.
  Plus **22 fixtures firing 51 diagnostics, FIXTURE_DIFFS = 0** — slice 8's 10 scope fixtures re-run as
  regression coverage, and **12 new cross-file discovery fixtures**: NL308 `InaccessibleMember` for a
  non-exported cross-namespace TYPE, for a non-exported cross-namespace FUNCTION and across a
  `package` boundary; the unique-exported fallback resolving CLEAN from an un-imported namespace; the
  same name in two un-imported namespaces refusing (NL201); a duplicate type name inside ONE namespace
  refusing (NL201); a cross-file `union` case in a `new` expression resolving clean; every declared
  family referenced across a namespace boundary; an import of a namespace no project file declares
  (NL704); an UNPARSEABLE sibling file skipped rather than failing the walk; a dotted
  `Namespace.Type` reference with a missing sibling; and an ALIASED namespace import resolving a
  project type through the alias.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, an explicit PE/CLI normaliser touching ONLY the
  COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries AND the CodeView
  blobs they point at, and the `#GUID`/`#Pdb` metadata heaps): **75 / 75 comparable assemblies
  BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (37 product assemblies from the 37
  corpus targets that build standalone, 38 single-file examples), and **SKIPPED_TARGET_DIFFS = 0** (12
  targets fail to build standalone with the SAME exit code in both trees). **102 build logs compared
  after normalising the two tree roots: 1 diff, and it is a `[0.5s]`-vs-`[0.6s]` timing string.** The
  toolchain assemblies are EXCLUDED with recorded reasons rather than silently:
  `NSharpLang.Compiler.BootstrapServices.dll` and `Compiler.dll` MUST differ (they contain the new
  owner and the edited `Analyzer.cs`), and `NSharpLang.Runtime.dll` differs by **exactly 57 bytes** on
  source that is byte-identical to baseline (`git diff bd11ad61d -- src/NSharpLang.Runtime` is empty) —
  the SAME 57 bytes slice 8 recorded, so this is the same single build-environment artefact and not a
  new one.
  ASSERTION MIGRATION: all 13 deleted members were `private` and both gutted bodies stay, so no test
  named any of them; a grep over `src/` + `tests/` + `editors/` finds no external consumer of any of
  them. Their behaviour was pinned only INDIRECTLY by end-to-end analyzer diagnostics, which STAY and
  now execute against the N# owners (the slice-1…8 precedent). The DIRECT pinning is new and native:
  **24 contracts** covering the snapshot's insertion order and a repeated path keeping its position;
  case-insensitive full-path keying including a relative spelling; the snapshot-then-disk-then-empty
  text chain and the null-means-ask-the-disk distinction; the cache lifetimes in BOTH directions (a new
  analysis keeps the parsed units by reference identity, a new snapshot drops them); parse-once-per-path
  and package-outranks-namespace with the global namespace as a real `null` candidate; the file-namespace
  question reading DISK rather than the snapshot and caching its NEGATIVE answer until the next analysis;
  the project-namespace set with no root, a blank root and a non-existent root all answering NO rather
  than throwing, and its case-SENSITIVITY; the disk fallback firing only without a snapshot; same-namespace
  resolution with and without export and cross-namespace resolution requiring it; the inaccessible case
  naming the declaring FILE, being skipped without a source position, and SUPPRESSING the unique-exported
  fallback; the fallback resolving a type no visible namespace offers while a name nothing declares is
  absent rather than inaccessible; **the enumeration order deciding the function channel and the
  inaccessible probe in BOTH directions over the same two files**, and the type channel REFUSING a
  duplicate instead; the visible-namespace order putting the file's own namespace ahead of every import;
  a declaration pointing at the NAME's column rather than the declaration's; all eight type families
  answering YES to the kind test and a function answering NO; the exported/non-exported function split
  with the type-versus-function probe crossover proven negative in both directions; an unparseable file
  being skipped by every walk; the declaring file being recorded for the project index on BOTH the sweep
  and the fallback and NOT on a miss; and the declaration context receiving the units in enumeration
  order.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m20s —
  exactly the slice-1…8 baseline, zero drift); BootstrapServices contracts **1,651 → 1,675** (+24) via
  the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false`, **1,675 / 1,675 PASS** (the 3 ExternalAssemblyScan Debug-layout tests
  did not trip); ownership audit **18 / 18** (`nlc test --project tests/native/ownership-audit`, 1.3s)
  after the repin; `./scripts/dev.sh --since` **PASS** — it correctly took the FULL unit-suite fail-safe
  (the two new `.nl` paths plus `OwnershipAudit.nl` are unmapped), **3,193 / 3,193 in Debug, done in
  3m19s**; the differential, oracle, fixture and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s9.py` (slice 2…8's script, unchanged apart from its header)
  — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs` currentLines
  21,735 → **21,461**, currentNonBlankLines 19,094 → **18,861**, fingerprint
  `text-v1:528472e43a179fae` → `text-v1:5f42f09ea77d4c6a` (epoch ceilings 23,451 / 20,537 PRESERVED and
  now clear by **1,990 / 1,676**); `reviewedHeadFingerprint head-v1:0db5fad465104e6e` →
  `head-v1:459f3828f6f19ed3`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` (381) untouched and RE-VALIDATED by recomputation after
  the write; the script self-checks by reproducing all three composite fingerprints over the 381 rows
  before changing anything. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND after,
  and the `git diff` is exactly 2 changed lines.** The `.nl` additions need no row.
  .nl GOTCHAS ADDED (three, all found by building; all three are the same family as slice 1's `type`,
  slice 4's `newtype`, slice 5's `record` and slice 7's `partial`, or the same family as the surface
  gaps):
  * **A BARE `null` THROUGH A DICTIONARY INDEXER IS OFF THE SURFACE.** `unitCache[fullPath] = null`
    declines at `emit.expression.unhandled-kind` ("unsupported expression (node kind 5)"). A typed
    local (`missingUnit: CompilationUnit? = null; unitCache[fullPath] = missingUnit`) is the same
    write and binds. Both negative caches in this slice needed it.
  * **AN `out` ARGUMENT IN THE RIGHT-HAND OPERAND OF `&&` DECLINES AT `parse.struct`.**
    `if flag && Try…(name, out result) { … }` makes the columnar front end decline the WHOLE class,
    reported at the class declaration rather than at the condition — which is why it took a
    member-by-member bisection to find. A nested `if` is the equivalent shape and binds. Multi-line
    `&&` chains are fine; it is specifically the `out` argument in a short-circuit position.
  * **`file` IS RESERVED AND CANNOT BE A LOCAL NAME.** `file := declaration.File` declines the whole
    class at `parse.struct`; `declarationFile := …` is fine. This one also cost a bisection, because
    the report lands on the class rather than on the statement.
  * **AND ONE RE-CONFIRMED THE HARD WAY:** `out type: TypeInfo` — `type` is reserved as a PARAMETER
    name (slice 2's recorded gotcha), and an `out` parameter is no exception. Renamed to `typeInfo`.
  .nl POSITIVES CONFIRMED (recorded because they were expected to be problems and are not): **the
  typed N# AST is directly usable** — `unit.Package`, `unit.Namespace`, `unit.Declarations`,
  `declaration.Line/.Column`, `functionDeclaration.Name` and `declaration as ClassDeclaration` all bind
  without reflection, which is what made the TYPE-identity kind test possible instead of the name-based
  one slice 7 had to refuse; **`Dictionary<string, CompilationUnit?>` and `Dictionary<string, string?>`
  round-trip** through `TryGetValue` with a nullable `out` local declared as `cached: T? = null`;
  **`foreach x in ProjectConfig.EnumerateSourceFiles(root)`** iterates an `IEnumerable<string>`
  returned from another N# owner; **a `try`/`catch` around a parse with a cache write in BOTH arms**
  works in production `.nl`; and **`File.ReadAllText` / `File.Exists` / `Directory.Exists` /
  `Directory.CreateDirectory` / `File.WriteAllText` / `File.Delete` / `Directory.Delete(dir, true)` /
  `Guid.NewGuid().ToString()` / `Path.GetTempPath()` are all bound**, which is what let the contracts
  exercise the DISK branches for real rather than mocking them.
  DOCS: `memory/components/analyzer.md` gains "Project discovery" — why the capability exists at all
  (N# has no `using`-style TYPE import), the provider's four caches with their ASYMMETRIC lifetimes,
  the enumeration order stated as behaviour with the measured duplicate counts, which two namespace
  questions read DISK rather than the snapshot and why, the three-outcome ordering with the
  suppression rule, the type-versus-function difference on duplicates, the one remaining C# piece
  (`CreateFunctionTypeInfo`) with its recorded reason, and the name-column rule for
  go-to-definition; the two stale non-movable claims in "The type-reference resolver" are corrected
  (`IsTopLevelTypeDeclaration` is RETIRED as a blocker and is now type-identity based;
  `NamespaceExists`'s project half is N#-owned and only its metadata half is blocked); and
  `AnalyzerProjectDiscovery.nl` joins the file list. `memory/architecture.md`'s Analyzer entry now
  lists all fourteen owners.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability needed,
  and no repin of the packaged toolset. All three new gotchas were routed AROUND rather than through:
  the bare-`null` indexer write by binding a typed local, the `out`-in-`&&` shape by nesting the `if`,
  and the reserved `file`/`type` names by renaming. The packaged 0.1.0 SDK self-emits both new classes
  and their 24 contracts.
  GATES: the FULL VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 852s
  (14m12s)** in a fresh isolated copy (`/private/tmp/nsharp-test-all.14d7ab40024d.I4Kh06/repo`) — the
  log says "Fresh isolated test run required: pre-commit verification" and "Existing cache entries will
  not satisfy this invocation", and it stored a NEW result (`14d7ab40024d479b`), so this is neither a
  cached whole-gate nor a cached per-step verdict. **105 `✓ PASSED` steps and ZERO `✗`/`FAILED`
  anywhere**: the format contract gate (which is what re-validates the ratchet manifest's compact
  format), unit **3,193 / 3,193** (3m18s inside the gate), every native `.tests.nl` project including
  `tests/native/ownership-audit` and BootstrapServices' **1,675 / 1,675** (2s), **VS Code integration
  smoke 36 passing (2m18s)**, SDK pack + install, template pack/install/creation and the
  template-generated project via `nlc build`, all example projects, all single-file examples,
  `nlc check` over the examples, and the ECMA-335 **IL verification gate — all 67 N# assemblies pass
  with no new errors vs baseline**. `./scripts/reload-vscode-extension.sh`: **EXIT 0** — language
  server republished, `nsharp-0.6.0.vsix` repackaged (289 files, 3.98 MB) and `Extension
  'nsharp-0.6.0.vsix' was successfully installed`, VS Code reopened. It WAS required even though no
  LanguageServer source changed: `Analyzer.cs` ships in the `NSharpLang.Compiler` assembly the language
  server builds against, and `NSharpLang.Compiler.BootstrapServices` gained two public types — which is
  also why the VS Code-enabled profile rather than the `VSCODE_TESTS=skip` path is the right bar for
  this slice. INTERACTIVE computer-use verification was NOT attempted, per the coordinator's standing
  instruction that it owns that record. This slice adds no LSP or IDE behaviour of its own, and the two
  IDE-facing surfaces it DOES touch are pinned rather than assumed: the `SetProjectSourceTexts`
  snapshot (the unsaved-editor-buffer path `MultiFileCompiler` feeds, whose case-insensitive full-path
  keying and insertion order are contract-pinned) and the `SymbolDeclaration` spans go-to-definition
  reads (name-column rule contract-pinned, and every declaration in the binding map compared cell by
  cell in the differential).
  **NEXT SUB-SLICE — STAGE 4 OF THE `ResolveType` ARC: THE REPORTING AND RECORDING WALK. Every
  structural blocker in front of it is now gone.** With the scope stack (stage 2) and project discovery
  (stage 3) owned, the measured remainder of the closure is exactly: `ResolveType` :18041 itself,
  `RecordResolvedTypeReference`, `ResolveDeclaredType` (the `_reportUnresolvedTypes` opt-in
  trampoline), `ResolveSimpleType` (BOTH overloads — the 8-channel name walk), `ResolveGenericType`,
  `ResolveAnonymousUnionType`, `ReportSoaRowTypeReferenceIfNeeded` and `TryResolveDottedNestedType`.
  **SEVEN of the name walk's eight channels now consult an N# owner** — built-in table, scope lookup,
  file-import alias, dotted-nested (via the scope stack and the declaration context), visible-project,
  using-alias-external and external — and only the terminal unresolved-`ExternalTypeInfo` arm is bare
  shell code. What stage 4 needs is NOT another data owner: it needs an **N#-owned diagnostic sink**
  able to emit the five recorded report sites (NL201 ×3 shapes, NL207 ×2) with byte-identical text,
  spans and lengths, plus the per-reference `_semanticModel.RecordTypeReference` write that fires on
  EVERY `ResolveType` call (measured 9,606 corpus / 29,565 suite / 268 fixtures — one per call,
  exactly), and it is where the three dedupe sets (`_reportedUnresolvedTypeRefs`,
  `_reportedSoaRowTypeRefs`, `_reportUnresolvedTypes`) move. `SemanticModel` is ALREADY N#
  (`SemanticModel.nl`), so the recording half is an argument-passed sink exactly like slice 8's
  `BindingMap`; the DIAGNOSTIC half is the genuinely new piece and is the whole of stage 4's risk.
  Stage 5 is the assignability SCC in one cut, as slice 6 measured.
  TWO SMALLER PREREQUISITES REMAIN RECORDED AND UNCHANGED (one of the three from slice 8 was RETIRED
  by this slice): `CreateFunctionTypeInfoInDeclarationContext` / `CreateFunctionTypeInfo` (32 live
  calls, and now also the last C# piece of the project-function channel) still needs the reflection
  half of `NullabilityMetadata`, which lives ABOVE BootstrapServices; and `Assembly.get_FullName` /
  `AssemblyName.get_Name` on the columnar external binding surface would release the metadata half of
  `NamespaceExists` and `GetExternalSearchAssemblies` together. **RETIRED THIS SLICE:**
  `IsTopLevelTypeDeclaration`'s "name match is not semantic resolution" objection — the typed N# AST
  makes it a TYPE-identity dispatch. The one-argument `Dictionary.Remove` analyzer-overload-table gap
  from slice 8 is still open and still unrelated to this arc.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `bd11ad61d`): **017 SLICE 8 — THE `ResolveType`
  ARC, STAGE 2: THE SCOPE STACK.**
  MANDATED TARGET, recorded verbatim from the coordinator and unchanged: `Analyzer.cs`'s
  `Stack<Scope> _scopes` field and its **51 sites** — the stack itself plus its walk semantics, NOT
  the element type (`Scope` was already N# in `AnalyzerStateModels.nl`). The measurement below was
  completed before any production edit.
  THE MEASUREMENT (a brace-matched read of all 51 sites and of every member that hosts one, plus a
  multiline-aware scan of each host body for `Error(ErrorCode.`, `_errors.`, `_semanticModel.` and
  `_bindingMap.`):
  * **51 sites, 35 HOST MEMBERS.** `_scopes` :138 (the field), `Analyze` :300 (`Clear`),
    `AnalyzeFunctionDeclaration` :1887/:1928/:1929, `AnalyzeClassDeclaration` :2246/:2247,
    `AnalyzeStructDeclaration` :2320/:2321, `AnalyzeRecordDeclaration` :2377/:2378,
    `AnalyzeInterfaceDeclaration` :2607/:2608, `DeclareNestedTypesInCurrentScope` :2631,
    `AnalyzeUnionDeclaration` :2646/:2647, `AnalyzeLocalFunction` :4484/:4485,
    `ApplyNarrowingsToScope` :4923, `TryFindNullableOriginForIdentifier` :8584 (`Skip(1)`),
    `IsCurrentTypeMemberReference` :14262, `TryRecordTypeBinding` :18749, `LookupType` :18765,
    `LookupSymbol` :18778, `TryLookupNullState` :18788, `SetNullStateInCurrentScope` :18800/:18803,
    `RegisterErrorTupleResult` :18808/:18811, `MarkErrorTupleResultsAvailableForError`
    :18817/:18820/:18821, `MarkErrorTupleResultAvailableAfterAssignment` :18838/:18843,
    `TryGetErrorTupleResultGuard` :18870, `IsErrorTupleResultAvailable` :18885,
    `InvalidateNullFactsForAssignment` :18902, `TryResolveIdentifierBindingTarget` :18932/:18945,
    `GetCurrentTypeScope` :19075, `PushScope` :20205, `PopScope` :20213, `DeclareSymbol` :20288,
    `CheckShadowedDeclaration` :20362/:20368/:20376, `DeclareType` :20416, `ProcessFileImport` :20984
    (`.Last()`), `FindSimilarVariableNames` :21787, `FindSimilarFunctionNames` :21803,
    `GetAllTypesInScope` :21822.
  * **THE "REPORTS NOTHING, RECORDS NOTHING" CLAIM IS TRUE OF THE STACK AND OF EVERY WALK, AND FALSE
    OF 12 OF THE 35 HOSTS — VERIFIED, NOT ASSUMED.** 23 hosts / **32 of the 51 sites** are entirely
    silent, including EVERY pure walk. The 12 non-silent hosts split three ways: (a) **four record ON
    THE SCOPE PATH** — `TryRecordTypeBinding` :18756 and `TryResolveIdentifierBindingTarget`
    :18939/:18952 write `_bindingMap.RecordBinding` inside the walk, and `PushScope`/`PopScope`
    :20207/:20217 write `_semanticModel.OpenScope`/`CloseScope`; (b) **five report or record in
    DECLARATION POLICY beside a bare `Peek()`/`.Last()`** — `DeclareSymbol`, `DeclareType`,
    `CheckShadowedDeclaration` (NL316, a multiline `Error(` my first scan missed and the second
    caught), `ProcessFileImport`, `Analyze` (whose non-silence is `_errors.Clear()` in the same reset
    block as `_scopes.Clear()`); (c) **three are large hosts whose reports are nowhere near the scope
    site** — `AnalyzeFunctionDeclaration`, `AnalyzeUnionDeclaration`, `AnalyzeLocalFunction`.
  * **THE CONSEQUENCE THAT SHAPED THE CUT.** Group (a) did NOT have to be split into a decision plus a
    shell write, because `BindingMap` and `SemanticModel` are THEMSELVES N# (`BindingMap.nl`,
    `SemanticModel.nl`): the map or the model is handed in as an ARGUMENT and the member moves WHOLE.
    That is not a callback — no N# code names `Analyzer`. Group (b) keeps its reporting members and
    routes the accessor; only `CheckShadowedDeclaration`'s DECISION moved out.
  * **`_semanticScopeIds` (`Stack<int>`, 9 sites) IS SCOPE-STACK STATE** and was pulled in: it is a
    second stack maintained in exact lockstep with `_scopes` by the same two members, so leaving it
    behind would have left the shell owning half the push/pop discipline.
  * **EVERY MOVED MEMBER HAS EXACTLY ONE OR TWO CALLERS**, all inside `Analyzer.cs`; a grep over
    `src/` + `tests/` + `editors/` finds no external consumer of any of them. The only same-named
    things anywhere are `ColumnarRuntimeDirectCallResolver.LookupType` /
    `ColumnarDirectCallPlanner.LookupType` / `ColumnarOrdinaryRuntimeDirectCallResolver.LookupType`
    (different resolvers, untouched) and `Linter.cs`'s own `PushScope`/`PopScope` over its own
    `Stack<Dictionary<…>>` (a different scope stack, task-019 territory, untouched).
  **RESULT: LANDED (no commit — mandate).** `AnalyzerScopeStack` is the sole authority for the
  analyzer's scope stack and every walk over it, with no callback, fallback, shadow path or comparison
  route anywhere.
  DELETIONS (exact, **17 whole C# members + 2 gutted bodies + 2 fields, 403 deleted lines**):
  * `LookupType` :18763 (9), `LookupSymbol` :18776 (12 incl. its 3-line XML doc),
    `CurrentScopeSymbol`'s inline `Peek().Symbols.GetValueOrDefault` :1887;
  * `TryLookupNullState` :18786 (11), `SetNullStateInCurrentScope` :18798 (7),
    `InvalidateNullFactsForAssignment` :18900 (14) — its LINQ `Where`/`ToList` key sweep included;
  * `TryFindNullableOriginForIdentifier` :8582 (15) — the `Skip(1)` walk;
  * `RegisterErrorTupleResult` :18806 (8), `MarkErrorTupleResultsAvailableForError` :18815 (20),
    `MarkErrorTupleResultAvailableAfterAssignment` :18836 (10), `TryGetErrorTupleResultGuard` :18868
    (14), `IsErrorTupleResultAvailable` :18883 (16);
  * `GetCurrentTypeScope` :19073 (9), `IsCurrentTypeMemberReference` :14260 (17);
  * `TryRecordTypeBinding` :18747 (18 incl. its 3-line XML doc) — walk AND record together;
  * `FindSimilarVariableNames` :21783 (15), `FindSimilarFunctionNames` :21799 (19),
    `GetAllTypesInScope` :21819 (12) — all three with their XML docs;
  * `TryResolveIdentifierBindingTarget`'s TWO walks :18932/:18945 (24 lines → 5): the scope arm is one
    call now, and the member's project/member/external arms are untouched (stage 3/4);
  * `CheckShadowedDeclaration` 41 → 14 lines: the `Count`/`Peek`/`ReferenceEquals`-guarded walk is
    gone and ONLY the `Error(ErrorCode.ShadowedDeclaration, …)` report remains;
  * `PushScope(Scope,int,int)` 7 → 3 and `PopScope` 9 → 3: both bodies are one routed call;
  * the `Stack<Scope> _scopes` field :138 becomes `AnalyzerScopeStack _scopes`, and the
    `Stack<int> _semanticScopeIds` field :209 **plus its `Clear()` at :311 are DELETED** — the two
    Clears were consecutive statements in the same reset block with nothing between them touching
    either stack, so folding them into `_scopes.Clear()` is exactly equivalent.
  ROUTING: **88 lines, every one mechanical, all inside `Analyzer.cs`** — 26 `LookupType`, 13
  `LookupSymbol`, 7 `DeclareTypeParameter` (each collapsing a 3-line `new SimpleTypeInfo` +
  two-dictionary write into one call), 5 `CurrentTypeScope`, 4 `SetNullStateInCurrentScope`, 2
  `AllTypeNamesInScope`, 2 `HasSemanticScope`/`CurrentSemanticScopeId` pairs in
  `RecordVariableInCurrentScope`/`RecordFunctionInCurrentScope`, and one each for
  `CurrentScopeSymbol`, `DeclareNestedTypeIfAbsent`, `GlobalScope`, `RecordTypeBinding`,
  `ResolveBindingTarget`, `RegisterErrorTupleResult`, `MarkErrorTupleResultsAvailableForError`,
  `MarkErrorTupleResultAvailableAfterAssignment`, `FindErrorTupleResultGuard` +
  `IsErrorTupleResultAvailable`, `InvalidateNullFactsForAssignment`, `IsCurrentTypeMemberReference`,
  `FindEnclosingNullableSymbol`, `HasNullState` + `NullStateOrUnknown`,
  `ShadowsEnclosingValueBinding`, `SuggestSimilarVariableNames`, `SuggestSimilarCallableNames`,
  `Push`, `Pop` and the field declaration. **NO new C# method, helper, bridge, callback or state**;
  the only non-call additions are the five relocated lines of the surviving NL316 `Error(` call, one
  comment, and `_extensionMethods.Select(m => m.Name).ToList()` at the callable-suggestion site
  (extension methods are not scope state, so they arrive as an argument).
  `git diff` on `Analyzer.cs` is **+88 / −403 = net −315**; the file is **22,050 → 21,735**
  (non-blank 19,366 → 19,094).
  N# ADDED: `AnalyzerScopeStack.nl` (**620 lines, ONE class, 36 members** — 2 fields, the `Count`
  property, the constructor, 30 public entry points and 2 helpers; far inside the per-class ceiling)
  + `AnalyzerScopeStack.tests.nl` (682 lines, **24 contracts**). No other `.nl` file changed.
  FIVE NON-MECHANICAL DECISIONS: (1) **THE STORE IS A `List<Scope>`, NOT A `Stack<Scope>`** (both are
  on the columnar surface — `Lexer.nl` and `Preprocessor.nl` already use `Stack<T>`). A list gives
  index-based innermost-first walks with no enumerator and no materialization, which matters because
  `LookupType`/`LookupSymbol` are among the hottest members in the analyzer. The cost is that
  `Stack<T>`'s exceptional behaviour has to be reproduced by hand, which is decision (2).
  (2) **`Peek`, `Pop` and `GlobalScope` THROW EXPLICITLY**, with the CLR's own messages — `Peek`/`Pop`
  `InvalidOperationException("Stack empty.")` and `GlobalScope`
  `InvalidOperationException("Sequence contains no elements")` (the LINQ `Last()` message, which has
  **no trailing period** — the differential caught the period I had written and it was the ONLY
  mismatch in 12,700 cells). Indexing a list would have thrown `ArgumentOutOfRangeException` instead.
  No production path reaches any of the three, but a silent change from one exception to another is
  still a behaviour change. (3) **PRESENCE AND VALUE OF A NULL FACT ARE TWO MEMBERS**
  (`HasNullState` + `NullStateOrUnknown`) because `NullState?` — a nullable ENUM return — is OFF the
  columnar surface (new gotcha below), and collapsing them onto `NullState.Unknown` would have
  conflated "no fact" with "recorded as unknown", which the caller distinguishes: the first falls back
  to the declared nullability and the second must not. The one caller pays one extra walk on a hit.
  (4) **THE TWO RECORDING WALKS MOVED WHOLE**, with `BindingMap` passed as an argument rather than
  held as a field, because the map is REPLACED on every `Analyze` call — the same reasoning as the
  slice-7 fact bag, and the reason `Push`/`Pop` take the `SemanticModel` too. (5)
  **`ShadowsEnclosingValueBinding` starts at index `Count - 2` rather than reproducing the
  `sawCurrent`/`ReferenceEquals(scope, currentScope)` guard**, which is provably identical because
  `Peek()` IS by definition the first element a top-to-bottom walk visits; the differential pins it
  over 1,681 decision cells and 1,680 report cells, INCLUDING a stack that pushes the SAME `Scope`
  instance twice (where a naive `ReferenceEquals` reading would have differed and does not).
  PROOF — THE LIFO PARITY PROOF, AND THE DIFFERENTIAL AGAINST THE C# ORIGINALS. One throwaway xunit
  probe, written ONCE and run in BOTH trees — at baseline `dc65075bf` in a throwaway
  `/tmp/nsharp017s8` worktree it reflects into `Analyzer.cs`'s ORIGINAL private members and its
  `Stack<Scope>`/`Stack<int>` fields; in the working tree the same source drives the analyzer's OWN
  `_scopes` field (so the wiring is proven, not just the behaviour) and falls through to the routed
  shells where they survive. It emits a tab-separated transcript of every cell; both trees'
  transcripts are **byte-identical, 12,700 CELLS, 0 MISMATCHES, md5
  `27f0e299d81066ca6a9aa7de90b0e34b` in both trees**, with **5,502 non-default answers** and **108
  THROW cells matched by exception TYPE AND MESSAGE**. The grid: **14 scope shapes** (empty;
  global-only; global+class+function with a shadowed name, a `this` binding, declaration locations
  and a narrowed local; three nested blocks carrying null facts including a recorded `Unknown`; an
  error-tuple guard chain; the same chain with the result name REBOUND by an inner scope; a
  locals-only chain holding `this`, `value` and an underscore name; function→class→block; a type
  scope with NO `this`; interface/struct/record kinds; callable-versus-non-callable near-misses; and
  outer-only declaration locations) × **35 probe names** (bound and unbound, dotted, empty,
  whitespace-only, `_`, and every name any shape binds) × **53 distinct operations** — the 8 pure
  reads, the 9 mutators each on a FRESH probe so every cell starts from the same shape, the two
  binding-recording walks compared through `BindingMap.BindingCount` + `AllDeclarations`, the
  shadowing DECISION and separately the shell's actual `Error(ErrorCode.ShadowedDeclaration)` firing
  over 4 declared types, and callable suggestions with and without extension methods. Plus the
  **LIFO REPLAY**: 24 snapshots driving the analyzer's own `PushScope`/`PopScope` through all seven
  `ScopeKind`s and back out, each snapshot dumping the FULL stack, the semantic-scope-id stack and
  every `SemanticModel` scope with its id, parent, start and end — so the parent chaining, the
  `int.MaxValue` end column, the interleaved `RecordScopedVariable`/`RecordScopedFunction` reads, the
  pop of an EMPTY stack, `Clear()` and a push after it are all pinned; and a shared-instance replay
  that pushes one `Scope` object twice. The probe was DELETED from both trees after the run (`git
  status` shows no probe residue).
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `dc65075bf` in the throwaway worktree and at the working tree (both trees' Debug CLIs built too —
  the recorded environmental artefact, since several `tests/native/*` projects reference a Debug
  `Compiler.dll` and their check FAILS identically without it), over **49 `project.yml` corpus targets
  (ORACLE_TARGETS=49, a superset of slice 7's 40)**: **ZERO diagnostic differences and
  ORACLE_STDERR_DIFFS=0**. The only textual deltas in the whole sweep are two `checkedFiles` counts
  rising by exactly the number of new `.nl` files (root 438 → 440, BootstrapServices 282 → 283);
  every diagnostic on every target, including the 281 pre-existing BootstrapServices errors, is
  byte-identical. Plus **10 purpose-built scope fixtures firing 36 diagnostics, FIXTURE_DIFFS = 0**:
  NL316 shadowing ×3 (a block shadowing a function local, a parameter, and a doubly-nested block) with
  the underscore, reserved-`value` and member-name cases proven NEGATIVE; NL301 undefined
  variable/function ×4 with did-you-mean suggestions from both the variable and the callable
  candidate lists; NL201/NL202 unresolved types ×6 with the in-scope-type suggestion, including a
  wrong type parameter inside a generic class and a missing nested type; NL306 duplicate type and
  duplicate local; NL303 nullable member access through a narrowed origin; NL905 flow narrowing across
  an invalidating assignment; NL314/NL202 error-tuple result use, checked, unchecked and reassigned;
  and generic type parameters resolvable as types and identifiers across class, struct, record,
  interface and free-function declarations.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, an explicit PE/CLI normalizer touching ONLY the
  COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries AND the CodeView
  blobs they point at, and the `#GUID`/`#Pdb` metadata heaps): **84 / 84 comparable assemblies
  BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (46 assemblies from 47 `project.yml`
  targets, 38 single-file examples with SINGLE_LOG_DIFFS = 0), and **SKIPPED_TARGET_DIFFS = 0** (10
  targets fail to build standalone with the same exit code in both trees). Two toolchain assemblies are
  EXCLUDED with recorded reasons rather than silently: `NSharpLang.Compiler.BootstrapServices.dll`
  MUST differ (the working tree's copy contains the new owner), and `NSharpLang.Runtime.dll` differs by
  **57 bytes** on source that is byte-identical to baseline (`git diff dc65075bf --
  src/NSharpLang.Runtime` is empty) — proven to be ONE build-environment artefact rather than 37, since
  all 37 copies in each tree normalize to a single hash (base `9f4e6100…`, work `9530edb4…`).
  ASSERTION MIGRATION: all 17 moved members were `private` and both gutted bodies stay, so no test
  named any of them; their behaviour was pinned only INDIRECTLY by end-to-end analyzer diagnostics,
  which STAY and now execute against the N# owner (the slice-1…7 precedent). The DIRECT pinning is new
  and native: **24 contracts** covering the LIFO discipline and the two ends of the stack; the three
  empty-stack throws by type AND message; the semantic-scope parent chaining, the `int.MaxValue` end
  column and the id stack's own lifetime; innermost-first lookup with shadowing and the
  current-scope-only read; the type parameter being ONE instance in both namespaces and visible only
  where declared; first-declaration-wins for nested types; the innermost null fact winning, an outer
  fact coming BACK when the narrowing scope closes, a recorded `Unknown` being distinguishable from no
  fact, and the empty-stack/blank-path refusals; invalidation reaching member paths in every scope
  while a mere prefix survives; the nullable ORIGIN skipping the innermost scope and NOT stopping at a
  non-nullable binding; guard registration refusing `_` and blanks and dying with its scope; the guard
  walk stopping at a rebinding scope; availability landing in the CURRENT scope and dying with the
  branch, and the mark/guard/symbol precedence including "a name nothing knows is available";
  assignment over a guarded result; shadowing's type-boundary stop, underscore opt-out, the `this`/
  `value`/function-declaration/also-a-type refusals and the non-local current scope; `this` as the
  current type and the three exits of the member-reference decision; innermost-first type-name order;
  and the two suggestion policies including the extension-method merge that keeps the FIRST spelling.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m16s — exactly the slice-1…7 baseline, zero drift); BootstrapServices contracts **1,627 → 1,651** (+24) via
  the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false`, **1,651 / 1,651 PASS**; ownership audit **18 / 18**
  (`nlc test --project tests/native/ownership-audit`, 1.2s) after the repin; `./scripts/dev.sh --since`
  **PASS** — it correctly took the FULL unit-suite fail-safe (the two new `.nl` paths plus
  `OwnershipAudit.nl` are unmapped), **3,193 / 3,193 in Debug, done in 3m21s**; the differential, oracle, fixture and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s8.py` (slice 2…7's script, rewritten against the manifest's
  actual `files` key) — `current*` + fingerprints ONLY, ONE row:
  `src/NSharpLang.Compiler/Analyzer.cs` currentLines 22,050 → **21,735**, currentNonBlankLines
  19,366 → **19,094**, fingerprint `text-v1:af0c13184e6f6907` → `text-v1:528472e43a179fae` (epoch
  ceilings 23,451 / 20,537 PRESERVED and now clear by **1,716 / 1,443**);
  `reviewedHeadFingerprint head-v1:eb9d3505a2d49eaf` → `head-v1:0db5fad465104e6e`, mirrored into
  `OwnershipAudit.nl`'s `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value,
  `epochPathFingerprint`, `epochFactFingerprint` and `epochFileCount` (381) untouched and
  RE-VALIDATED by recomputation after the write; the script self-checks by reproducing all three
  composite fingerprints over the 381 rows before changing anything. **FORMAT DISCIPLINE HELD: `wc -l`
  on the manifest is 391 before AND after, and the `git diff` is exactly 2 changed lines.** The `.nl`
  additions need no row.
  .nl GOTCHAS ADDED (five, all found by building):
  * **A NULLABLE ENUM RETURN IS OFF THE SURFACE.** `NullState?` declines at
    `emit.declaration.method-return` ("method return type 'NullState?' could not be resolved"), even
    though `int?` and `bool?` return fine (`CompilerBootstrapServices.ParseInt`,
    `BatchQueryOutputKernels.OptionalBool`). Split presence from value.
  * **A TOP-LEVEL PascalCase FREE `func` COLLIDES WITH A SAME-NAMED `static func` IN ANOTHER FILE'S
    CLASS.** A helper `func Names(values: List<string>): string` in a new `.tests.nl` made
    `AstEq.FieldNames` in `ColumnarParserAst.tests.nl` decline at `emit.return.expression` — its own
    unqualified `Names(spaceSeparated)` call bound to the free function instead of to `AstEq.Names`.
    PascalCase is public, so every top-level test helper needs a distinctive prefix
    (`ScopeNameList`, `ScopeTypeName`, …), which is exactly what the existing `Probe*`/`Clr*` helpers
    already do.
  * **`ex.GetType().Name` DECLINES INSIDE A `catch`** at `emit.statement.block-child` (the
    already-recorded "GetType() on typed receiver" and "chained calls on call results" gotchas
    combined). Assert on `ex as SpecificException != null` plus `ex.Message` instead — which is a
    stronger assertion anyway.
  * **`new X().Method(...)` DECLINES IN EXPRESSION-STATEMENT POSITION** at
    `emit.expression-statement.call`, while the SAME expression inside an `assert` is fine. Bind the
    instance to a local first.
  * **`Dictionary<K, V>.Remove(key)` IS NOT ON THE ANALYZER'S OVERLOAD TABLE.** Columnar emission
    accepts the one-argument form, but `nlc check` reports **NL402** "No overload of 'Remove' accepts
    1 argument … Available overloads: Remove(TKey? key, out TValue? value)". The oracle caught it as
    the ONLY new corpus diagnostic (BootstrapServices 281 → 282 errors) and it is fixed by using the
    two-argument overload, which the BCL defines as the same operation plus the removed value. The
    ANALYZER-side gap is recorded, not worked around elsewhere.
  .nl POSITIVES CONFIRMED (recorded because they were expected to be problems and are not):
  **`throw` WORKS IN PRODUCTION `.nl`** — this is its first production use outside `.tests.nl`
  (`grep '^\s*throw ' src/**/*.nl` previously matched tests only), which is what makes the
  exception-parity decision expressible at all; **`foreach entry in dictionary { entry.Key /
  entry.Value }`** iterates a `Dictionary` directly, so the LINQ key sweep in
  `InvalidateNullFactsForAssignment` ports without materializing `.Keys`; **`scopes[i].Types
  .TryGetValue(name, out candidate)`** — an index, then a member access, then a call with an `out`
  argument — binds fine, as does **`Peek().Types[name] = value`** (a call result, a member access and
  an indexer assignment); and **`2147483647`** stands in for `int.MaxValue` exactly.
  DOCS: `memory/components/analyzer.md` gains "The scope stack" — the three load-bearing rules (the
  innermost-first walk and the scopes that END it, the two walks that SKIP the innermost scope, and
  the lexical/semantic-id lockstep with its legal depth asymmetry), why the two recording walks live
  in the owner and take their sink as an argument, the null-fact presence-versus-value rule, what
  declaration policy the shell keeps and why, and the empty-stack exception parity; the stale claim
  that the scope stack is the next prerequisite is corrected, the "Symbol Tables" section is rewritten
  from the long-dead `EnterScope`/`ExitScope` names to the real routed surface, and
  `AnalyzerScopeStack.nl` + `AnalyzerStateModels.nl` join the file list. `memory/architecture.md`'s
  Analyzer entry now lists all thirteen owners.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability
  needed, and no repin of the packaged toolset. All five gotchas were routed AROUND rather than
  through: the nullable enum by splitting one member into two, the free-function collision by
  renaming test helpers, the `GetType()` and `new X().M()` shapes by restructuring the contracts, and
  the `Dictionary.Remove` analyzer gap by using the equivalent two-argument overload. The packaged
  0.1.0 SDK self-emits the new class and its 24 contracts.
  GATES: the FULL VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 846s
  (14m06s)** in a fresh isolated copy (`/tmp/nsharp-test-all.bb8bfdd3db1f.w5cDp4`) — the log says
  "Fresh isolated test run required: pre-commit verification" and "Existing cache entries will not
  satisfy this invocation", and it stored a NEW result (`bb8bfdd3db1f207f`), so this is neither a
  cached whole-gate nor a cached per-step verdict. **105 `✓ PASSED` steps and ZERO `✗`/`FAILED`
  anywhere**: the format contract gate, unit **3,193 / 3,193** (4m39s inside the gate), every native
  `.tests.nl` project including `tests/native/ownership-audit` and BootstrapServices'
  **1,651 / 1,651** (2m22s), **VS Code integration smoke 36 passing (2m18s)**, SDK pack + install
  (2m51s), template pack/install/creation and the template-generated project via `nlc build`, all
  example projects, all single-file examples, `nlc check` over the examples, and the ECMA-335 **IL
  verification gate — all 67 N# assemblies pass with no new errors vs baseline**.
  `./scripts/reload-vscode-extension.sh`: EXIT 0 — language server republished, `nsharp-0.6.0.vsix`
  repackaged (289 files, 3.98 MB) and `Extension 'nsharp-0.6.0.vsix' was successfully installed`, VS
  Code reopened. It WAS required even though no LanguageServer source changed: `Analyzer.cs` ships in
  the `NSharpLang.Compiler` assembly the language server builds against, and
  `NSharpLang.Compiler.BootstrapServices` gained a public type — which is also why the VS Code-enabled
  profile rather than the `VSCODE_TESTS=skip` path is the right bar for this slice. INTERACTIVE
  computer-use verification was NOT attempted, per the coordinator's standing instruction that it owns
  that record. This slice adds no LSP or IDE behaviour of its own; the semantic model's scope
  open/close records — which the position-aware LSP lookups read — are pinned snapshot by snapshot by
  the LIFO replay, and the diagnostics are proven byte-identical corpus-wide.
  **NEXT SUB-SLICE — STAGE 3 OF THE `ResolveType` ARC: THE PROJECT-DISCOVERY CHANNEL, and it is now
  the only structural blocker left before the reporting walk.** With the scope stack owned, the
  measured remainder of the closure is exactly: `ResolveType` :18082 itself with
  `RecordResolvedTypeReference`, `ResolveDeclaredType`, `ResolveSimpleType` (both overloads),
  `ResolveGenericType`, `ResolveAnonymousUnionType`, `ReportSoaRowTypeReferenceIfNeeded`,
  `TryResolveDottedNestedType`, the `TryResolveVisibleProjectType` family, and `NamespaceExists` +
  `GetExternalSearchAssemblies`. **Five of the name walk's eight channels now consult an N# owner**,
  and `GetAllTypesInScope` — the last C# input to the now-N# suggestion policy — is gone. Stage 3 is
  `TryResolveVisibleProjectType` → `TryResolveProjectTypeInNamespace` /
  `TryResolveUniqueExportedProjectType` / `TryMaterializeProjectTypeSelection` /
  `TryReportInaccessibleVisibleProjectDeclaration`, and it is BLOCKED on a source-text/unit provider
  on the N# side (`EnumerateProjectSourceTexts`, `GetProjectCompilationUnit`,
  `ProjectConfig.EnumerateSourceFiles` — file enumeration plus re-parsing, with three caches:
  `_projectSourceTexts`, `_projectCompilationUnitCache`, `_projectNamespaceCache`). Stage 4 (the
  reporting and recording walk) needs an N#-owned diagnostic sink and the per-reference
  `RecordTypeReference` write, and stage 5 is the assignability SCC in one cut. THREE SMALLER
  PREREQUISITES REMAIN RECORDED AND UNCHANGED: `CreateFunctionTypeInfoFromDelegate` (32 live calls)
  still needs the reflection half of `NullabilityMetadata`, which lives ABOVE BootstrapServices;
  `Assembly.get_FullName` / `AssemblyName.get_Name` on the columnar external binding surface would
  release `NamespaceExists` and `GetExternalSearchAssemblies` together; and the one-argument
  `Dictionary.Remove` overload is missing from the ANALYZER's overload table.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `dc65075bf`): **017 SLICE 7 — THE
  OPENING OF THE `ResolveType` ARC: MEASURE THE WHOLE CLOSURE, RECORD THE STAGED PLAN, LAND STAGE 1.**
  MANDATED TARGET: open `ResolveType(TypeReference)` — the sole blocker for the whole assignability
  SCC per slice 6 — by measuring its complete closure, recording a staged arc plan, and landing the
  largest terminal sub-family.
  THE MEASUREMENT (done BEFORE any production edit; a throwaway instrumented Release build with 40
  counters over the whole closure, run across all 40 `project.yml` corpus targets, the full
  3,193-test unit suite AND 11 purpose-built resolution-error fixtures, then reverted — `Analyzer.cs`
  is byte-identical to `72ffc3113` apart from this slice's cut, and the suite passed **3,193 / 3,193
  WITH the probe armed**, so the instrumentation was behaviour-neutral):
  * **THE CLOSURE MAP.** `ResolveType(TypeReference)` :18079 is a 9-arm dispatch that ends in ONE
    `RecordResolvedTypeReference` :18353 → `_semanticModel.RecordTypeReference` for EVERY reference it
    resolves, at the reference's start span. Its helpers: `ResolveDeclaredType` :18065 (the
    `_reportUnresolvedTypes` opt-in trampoline), `ResolveSimpleType(SimpleTypeReference)` :18103,
    `ResolveGenericType` :18113, `ResolveAnonymousUnionType` :18303, `ResolveSimpleType(string,int,int)`
    :18389 — the 8-CHANNEL name walk — `ReportSoaRowTypeReferenceIfNeeded` :18235, `LookupType` :18936
    (the `_scopes` stack), `TryRecordTypeBinding` :18849, `TryResolveDottedNestedType` :18796,
    `TryResolveVisibleProjectType` :18516 → `GetVisibleProjectTypeNamespaces` :18656 /
    `TryResolveProjectTypeInNamespace` / `TryResolveUniqueExportedProjectType` /
    `TryMaterializeProjectTypeSelection` / `TryReportInaccessibleVisibleProjectDeclaration`,
    `TryResolveExternalType` :18894, `GetGenericHeadArity` :18267, `GetKnownGenericHeadArities` :18286,
    `BuildUnresolvedTypeSuggestion` :18823 → `GetAllTypesInScope` :22012, and
    `TryResolveBuiltInTypeKeyword` :18869 in the adjacent identifier path.
  * **THE STATE SURFACE.** `_scopes` (`Stack<Scope>`, **51 sites**), `_semanticModel`, `_errors`,
    `_bindingMap`, `_reportUnresolvedTypes` + `_reportedUnresolvedTypeRefs` +
    `_reportedSoaRowTypeRefs` (the three dedupe/opt-in flags), `_usingAliases`, `_usingNamespaces`,
    `_mlcAssemblies`, `_externalTypeCache`, `_externalNamespaceCache`, `_currentFilePath`,
    `_compilationUnit`, `_importedSymbolsByAlias` / `_importedDeclarationsByAlias`,
    `_typeDeclarationFiles`, `_projectSourceTexts` / `_projectCompilationUnitCache` /
    `_projectNamespaceCache` (file I/O + re-parsing), and `_declarationContext` (already N#).
  * **THE DIAGNOSTICS.** Five report sites, ALL of them in `ResolveSimpleType(string,…)` and
    `ResolveGenericType`, none in any helper: NL201 `TypeNotFound` for a claimed file-alias
    (`R1`, 0 / 0 / **1**), NL201 for an undotted simple name (`R2`, 0 / **19** / 6), NL201 for a
    generic name (`R3`, 0 / 0 / **1**), NL207 `InvalidTypeArgument` "available arities are …"
    (`R4`, 0 / **1** / **2**), NL207 arity mismatch (`R5`, 0 / **14** / **16**), plus NL103 SoA-row
    and the union arm's `DuplicateDeclaration`/`InvalidTypeArgument`. **Counts are corpus / unit
    suite / fixtures.**
  * **THE SEMANTIC-MODEL WRITES, inventoried with their readers.** `RecordTypeReference(line, column,
    resolved)` fires on **EVERY** `ResolveType` (9,606 / 29,565 / 268 — one per call, exactly), plus
    `_semanticModel.RecordType(name, type)` on the file-alias and visible-project channels and
    `_bindingMap.RecordBinding` on the scope, file-alias and project channels. So the recording path
    is NOT separable from the walk, and stage 1 had to be cut around it — which is what happened.
  * **CHANNEL FREQUENCIES** (`ResolveSimpleType(string,…)` 9,358 / 28,793 / 268): built-in table
    6,204 / 15,641 / 204; scope lookup 1,442 / 5,744 / 21; file-import alias 0 / **1** / 3;
    dotted-nested 0 / **42** / 3; visible-project 520 / 3,854 / 3; using-alias-external
    **0 / 0 / 0**; external 656 / 1,443 / 12; unresolved-`ExternalTypeInfo` 536 / 2,064 / 47.
  * **`TryResolveExternalType` 2,844 / 6,789 / 288**, by branch: bare cache hit 218 / 292 / 19,
    namespace-prefixed cache hit 1,796 / 2,525 / 46, namespace scan hit 172 / 675 / 21, **bare
    exported-name scan hit 40 / 100 / 9**, miss 618 / 3,197 / 257. The bare-scan branch is what makes
    the cache ORDER-BEARING: it caches under the BARE spelling, so a later call short-circuits before
    the import loop is reconsidered. `TryResolveExactExternalType` 222 / 1,230 / 15 (scan hit 0 / 2 / 1).
  * **`GetGenericHeadArity`** arms all live: Class 158 / 769 / 15, External (→ −1) 464 / 1,608 / 18,
    Record 64 / 579 / 9, Reflection 268 / 657 / 12, Simple 12 / 6 / 0, Struct 24 / 110 / 9,
    Interface 0 / 14 / 9, Union 0 / 45 / 3, **SoaRecord 0 / 1 / 0**, Enum 0 / 0 / 3, Alias 0 / 0 / 3,
    Newtype 0 / 0 / 3. `GetKnownGenericHeadArities` 0 / 35 / 21 (count-0 0/19/6, count-1 0/13/9,
    count-many 0/**3**/**6**). `TryResolveBuiltInTypeKeyword` 1,646 / 2,835 / 0 — with **6 live
    no-facts calls** in the suite, so that null state is real. `BuildUnresolvedTypeSuggestion`
    0 / 19 / 7 (did-you-mean 0/1/4, generic 0/18/3).
  * **TWO GUARDS MEASURED DEAD and recorded rather than acted on:** the assembly-identity dedupe in
    `GetExternalSearchAssemblies` fired **0** times out of 2,326 / 12,801 / 91 yields, and the
    using-namespace dedupe inside `GetVisibleProjectTypeNamespaces` fired **0** times out of
    29,362 / 48,300 / 291. Both are PRESERVED verbatim. So is the structurally dead
    using-alias-as-a-type channel (`_usingAliases` → `TryResolveExternalType(fullName)`, 0 across all
    three populations): `RegisterNamespaceImport` only records an alias AFTER
    `ValidateNamespaceImport` proves the target is a namespace and not a type, so the aliased full
    name can never resolve as a type. Recorded, not deleted.
  THE STAGED ARC PLAN (recorded before editing; the 016 precedent — capability + proofs first where
  the surface is separable, and the reporting/recording paths only once an N# owner can produce the
  SAME diagnostics and the SAME `_semanticModel` records):
  * **STAGE 1 (THIS SLICE) — the PURE DECISION SURFACE.** Every member of the closure that is a total
    function of separable state and reports/records NOTHING: the MLC probe with its cache, the arity
    tables, the built-in name tables, the namespace candidate ordering and the suggestion policy.
    Terminal on its own, and it clears the `ActionResult` arm's blocker.
  * **STAGE 2 — THE SCOPE STACK.** `LookupType` / `LookupSymbol` / `GetAllTypesInScope` /
    `TryRecordTypeBinding` / `TryLookupNullState` and the `Stack<Scope>` itself. `Scope` is ALREADY N#
    (`AnalyzerStateModels.nl`), so this is the stack and its **51** sites, not the element type. It is
    a strict prerequisite for the name walk, because 5 of the 8 channels consult it.
  * **STAGE 3 — THE PROJECT-DISCOVERY CHANNEL.** `TryResolveVisibleProjectType` and friends. Blocked
    on file enumeration + re-parsing (`EnumerateProjectSourceTexts`, `GetProjectCompilationUnit`,
    `ProjectConfig.EnumerateSourceFiles`), so it needs a source-text/unit provider on the N# side
    first.
  * **STAGE 4 — THE REPORTING AND RECORDING WALK.** `ResolveSimpleType` / `ResolveGenericType` /
    `ResolveAnonymousUnionType` / `ResolveType` itself. This is the stage that must reproduce all five
    diagnostics AND the per-reference `RecordTypeReference` write; it needs an N#-owned diagnostic sink
    and semantic-model writer, and it is where the dedupe sets move.
  * **STAGE 5 — the assignability SCC** follows in one cut, exactly as slice 6 measured.
  **RESULT: STAGE 1 LANDED (no commit — mandate).**
  `AnalyzerExternalTypeProbe` is the sole authority for the analyzer's referenced-assembly metadata
  probe, `AnalyzerTypeReferenceFacts` for the resolver's pure rules, and the two existing owners grew
  the remaining two tables — no callback, fallback, shadow path or comparison route anywhere.
  DELETIONS (exact, 7 whole C# members + 1 inline table + 1 field, **225 deleted lines**):
  * `TryResolveExternalType(string)` :18894 (41 lines) — the ordered probe;
  * `TryResolveExactExternalType(string)` :21284 (20) — the exact probe;
  * `GetKnownGenericHeadArities(string)` :18286 (17) — the arity sweep;
  * `GetGenericHeadArity(TypeInfo)` :18267 (23 incl. its 4-line XML doc) — the head-arity table;
  * `TryResolveBuiltInTypeKeyword(string)` :18869 (28 incl. its 4-line XML doc) — the WKT keyword table;
  * `BuildUnresolvedTypeSuggestion(string)` :18823 (24) — the did-you-mean policy;
  * `GetVisibleProjectTypeNamespaces()` :18656 (23) — the namespace candidate ordering, an ITERATOR
    replaced by a materialized list (behaviour-neutral: the enumeration has no side effects and the
    callers either enumerate fully or break early);
  * the 20-line inline built-in name table inside `ResolveSimpleType(string,int,int)` :18397 → 1 line;
  * the `_externalTypeCache` field :197 — the state itself, now OWNED by the N# probe.
  ROUTING: **29 live sites**, every one inside `Analyzer.cs` (a grep over `src/` + `tests/` +
  `editors/` finds no external consumer of any of the seven; the only same-named thing anywhere is
  `ColumnarBindingScopeFacts.TryResolveExternalType`, which is a DIFFERENT resolver — it verifies a
  candidate against an expected emitted type identity for the columnar back end — and is untouched):
  12 `ResolveExternalType`, 1 `ResolveExactExternalType`, 1 `KnownGenericHeadArities`,
  3 `GenericHeadArity`, 5 `BuiltInMetadataClrType`, 2 `UnresolvedTypeSuggestion`,
  1 `BuiltInSimpleType`, 4 `VisibleTypeNamespaces`. (13 `TryResolveExternalType` call sites were
  rewritten; one of them lived inside `GetKnownGenericHeadArities` and went away with it.)
  C# ADDED: **32 lines, all mechanical** — a field declaration + its 2-line comment, ONE line in the
  existing parameterless `Analyzer` constructor, and 28 rewritten call sites. **NO new method, helper,
  bridge, callback or state**, and the probe is deliberately NOT rebuilt at the `_wellKnownTypes`
  mutation points (unlike the slice-5/6 owners) because rebuilding would drop its order-bearing cache;
  the fact bag is passed as an ARGUMENT to the one entry point that needs it.
  `git diff` on `Analyzer.cs` is **+32 / −225 = net −193**; the file is **22,243 → 22,050**
  (non-blank 19,538 → 19,366).
  N# ADDED: `AnalyzerExternalTypeProbe.nl` (**152 lines, one class, 5 members** — 3 fields, the
  constructor, 3 public entry points) + `AnalyzerExternalTypeProbe.tests.nl` (241 lines, **8
  contracts**); `AnalyzerTypeReferenceFacts.nl` (**147 lines, one class, 3 public statics**) +
  `AnalyzerTypeReferenceFacts.tests.nl` (294 lines, **7 contracts**); **+30 lines / 1 member** to
  `AnalyzerWellKnownTypeFacts.nl` (`BuiltInMetadataClrType`) with **+1 contract**; **+36 lines /
  1 member** to `AnalyzerDiagnostics.nl` (`UnresolvedTypeSuggestion`) with a new
  `AnalyzerDiagnostics.tests.nl` (100 lines, **4 contracts**). **20 new contracts.**
  FOUR NON-MECHANICAL DECISIONS: (1) **THE PROBE IS NEVER REBUILT.** Slices 5 and 6 rebuild their
  owners at the two `_wellKnownTypes` mutation points; this one must not, because its cache is part of
  the answer (the bare exported-name scan caches under the BARE spelling and short-circuits the import
  loop on the next call — measured live at 40 / 100 / 9 hits). The fact bag is therefore an argument to
  `KnownGenericHeadArities` rather than a field. (2) **`Assembly.GetType(name)` replaces
  `GetType(name, throwOnError: false, ignoreCase: false)`** in the exact probe: the 3-argument overload
  is not on the columnar binding surface and adding it would trip the bootstrap wall, while
  `Assembly.GetType(String)` is defined as exactly that call — the differential pins the equivalence
  over 236 cold cells per state, including every qualified, nested and arity-suffixed spelling.
  (3) **`GetVisibleProjectTypeNamespaces` becomes a materialized `List<string?>`** rather than an
  iterator, and the null entry is KEPT as null rather than encoded, because the global namespace is a
  real candidate. (4) **`NamespaceExists` / `GetExternalSearchAssemblies` and
  `IsTopLevelTypeDeclaration` were CUT FROM the slice with recorded reasons** rather than forced: the
  first pair needs `Assembly.get_FullName` (bootstrap wall), and the second needs a declaration
  TYPE-identity dispatch while the N# `DeclarationFacts` idiom is name-based — and a name match is not
  semantic resolution.
  PROOF — DIFFERENTIAL AGAINST THE C# ORIGINALS, BUILT AND RUN BEFORE THE DELETION, DELETED AFTER
  (the tree has zero probe residue): a throwaway xunit probe reflected into the private C# members on a
  REALLY-LOADED analyzer (`new Analyzer(); LoadSystemAssemblies(); Analyze(...)` over a 5-alias /
  11-declared-family source) and on a SECOND analyzer with no `LoadSystemAssemblies` — the live
  `_wellKnownTypes == null` state — and compared them against the N# owners cell by cell, by value OR
  THROWN EXCEPTION TYPE. **4,918 CELLS, 0 MISMATCHES, 0 THROWN CELLS, 483 TRUE POSITIVES.** The grid:
  118 spellings (bare CLR names, fully-qualified names, arity-qualified definitions from `` `1 `` to
  `` `18 ``, nested `+` spellings, namespaces, the 11 declared families, all 16 keywords, near-misses,
  empty/dot-only/backtick-only degenerates) probed COLD — the analyzer's cache cleared and a fresh N#
  probe built for every single cell, so both implementations start from the same state — and then
  WARM, as one long-lived probe replaying the whole sequence three times (forward, forward, reversed)
  against the analyzer's own warming cache, which is what pins the cache's order-dependence; the two
  caches are then compared as MAPS, key by key and value by assembly-qualified name, and are equal.
  Plus 29 ambiguity-sensitive names × 8 import lists × BOTH directions (232 orderings) for the
  using-namespace order; 236 arity-sweep cells; 328 keyword cells; 92 built-in-table cells driven
  through a SEPARATE empty-source analyzer so that "answered with a `SimpleTypeInfo`" can only be the
  table (driving them through the loaded analyzer reads the SCOPE channel instead — a type alias to a
  built-in resolves to a `SimpleTypeInfo` there, which is a different decision and is not moving in
  this slice; that distinction was found BY the probe and is why the cell definition is what it is);
  88 head-arity cells over 44 TypeInfo shapes including every family, open/closed/non-generic/array/
  type-parameter reflected types and both alias spellings; 296 suggestion cells; and 24
  namespace-ordering cells.
  PROOF — BEFORE/AFTER TRANSCRIPT: the same probe wrote a **4,918-row** transcript of every cell from
  the C# ORIGINALS before the deletion; re-emitted AFTER the deletion with the ORIGIN column taken from
  the analyzer's OWN routed path (its `_externalTypeProbe` field and the static owners) it is
  **byte-identical — diff = 0, md5 `892e23a2603e1861102cf60d4d3b7cfd` both times**, which proves the
  behaviour AND the wiring in one artefact.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `72ffc3113` in a throwaway `/tmp/nsharp017s7` worktree and at the working tree (both trees' Debug
  CLIs built too — the recorded environmental artefact), **byte-identical on 40 / 40 `project.yml`
  targets (ORACLE_TARGETS=40, ORACLE_DIFFS = 0)**, plus **11 purpose-built resolution-error fixtures
  firing 57 diagnostics, FIXTURE_DIFFS = 0**: near-miss and far-miss unresolved names with their
  did-you-mean/generic suggestions and a sub-3-character name; local generics at too many/too few
  arguments, a non-generic given arguments, an unknown generic name, and `Dictionary`/`Task` at the
  wrong arity; the multi-arity "available arities are …" case via `Tuple`/`ValueTuple` at 9 and 10
  arguments and `Nullable` at 2; aliased and bare namespace imports; a type imported as a namespace and
  a missing namespace; duplicate and three-armed anonymous unions with a nested-flatten control; dotted
  nested types, a missing nested type and `var`-as-a-type; bare/qualified/generic/arity-qualified
  external CLR types and a missing one; cross-namespace exported vs non-exported project types; type
  arguments on EVERY declared family (union, enum, alias, newtype, struct, interface, record) plus the
  generic ones at the wrong arity; and file-import aliases with a missing alias-qualified type.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, the established explicit PE/CLI normalizer
  touching ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries
  and the CodeView blobs they point at, and the `#GUID`/`#Pdb` heaps): **64 / 64 comparable assemblies
  BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (26 from the `project.yml` targets,
  38 single-file examples, SINGLE_LOG_DIFFS = 0), with the same 7 `tests/native/*` targets that do not
  build standalone failing identically at baseline and after (**SKIPPED_TARGET_DIFFS = 0**).
  ASSERTION MIGRATION: all seven members were `private` and the built-in table was inline, so no test
  named them; their behaviour was pinned only INDIRECTLY by end-to-end analyzer diagnostics, which STAY
  and now execute against the N# owners (the slice-1…6 and 016 classification-(a) precedent). The
  DIRECT pinning is new and native: **20 contracts** covering the ordered probe's three channels and
  the "every import is tried in order" rule (including an import that resolves nothing in either
  position, and the single-dot composition that refuses a PREFIX import); the exported-name scan on
  both simple and full name; **the cache being consulted BEFORE the imports** — demonstrated by
  emptying the live assembly list AND adding an import and still getting the cached answer, while a
  probe with the same inputs and no history answers nothing — and a MISS not being cached, so it is
  genuinely retried; the live-list semantics in both directions (an assembly added after construction
  is visible, and `Dispose`'s `Clear` takes uncached answers away while cached ones remain); the exact
  probe refusing every unqualified spelling and sharing the one cache in both directions; a FRESH
  `ReflectionTypeInfo` per call over an identical `Type`; the arity sweep's compiler-table half, its
  arity-qualified metadata half, the open-DEFINITION requirement (a non-generic hit does not count),
  ascending order, the 17 ceiling, `Tuple`/`ValueTuple` stopping at 8 and `Nullable` at 1, and every
  reported arity re-verified to name a definition of exactly that arity; the built-in table's sixteen
  spellings with the synthesised types, `var`, the CLR spellings, case variants and whitespace all
  refused, and its fresh-instance/compare-by-value discipline; head arity's ZERO-versus-−1 distinction
  across every family, a CLOSED reflected generic answering 0 rather than its argument count, the
  union's optional type-parameter list with absent and empty both meaning zero, and enum/alias/newtype
  pinned at zero; the metadata keyword table's fifteen names with `void` DELIBERATELY absent, its
  not-reference-equal-to-`typeof` discipline and its no-facts state; the namespace ordering's
  global-first rule, self-imported and duplicate dedupe from either position, case-sensitivity, and an
  empty import name kept as a real candidate; and the suggestion policy's distance-1/2/3 boundary,
  case-insensitive comparison with the candidate's own spelling preserved, the under-3 and self skips,
  and ties keeping the caller's FIRST candidate.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m24s —
  exactly the slice-1…6 baseline, zero drift); BootstrapServices contracts **1,607 → 1,627** (+20) via
  the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false`, **1,627 / 1,627 PASS** (the 3 ExternalAssemblyScan Debug-layout tests
  did not trip); ownership audit **18 / 18** (`nlc test --project tests/native/ownership-audit`,
  1.2s) after the repin; `./scripts/dev.sh --since` PASS — it correctly took the FULL unit-suite
  fail-safe (six unmapped `.nl` paths plus `OwnershipAudit.nl`), **3,193 / 3,193 in Debug, 3m17s**;
  the oracle, differential, transcript and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s7.py` (slice 2…6's script, unchanged apart from its header)
  — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs` currentLines
  22,243 → **22,050**, currentNonBlankLines 19,538 → **19,366**, fingerprint
  `text-v1:3160b9b907f7abe8` → `text-v1:af0c13184e6f6907` (epoch ceilings 23,451 / 20,537 PRESERVED and
  now clear by 1,401 / 1,171); `reviewedHeadFingerprint head-v1:8eee56698b0d2f9e` →
  `head-v1:eb9d3505a2d49eaf`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` (381) untouched and RE-VALIDATED by recomputation after
  the write; the script self-checks by reproducing all three composite fingerprints over the 381 rows
  before changing anything. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND after,
  and the `git diff` is exactly 2 changed lines.** The `.nl` additions need no row.
  .nl GOTCHAS ADDED: **`partial` is RESERVED and cannot be a local name** — `prefixOnly := …` is fine
  but `partial := …` makes the columnar front end decline the WHOLE test at `parse.test`, reported at
  the test's own line, the same shape as slice 1's `type`, slice 4's `newtype` and slice 5's `record`;
  **`object.ReferenceEquals(a, b)` declines at `emit.call.static-member-unmodeled` with lower-case
  `object`** — the bound spelling is `Object.ReferenceEquals` (capital O, the
  `AnalyzerDeclarationContext.tests.nl` idiom), and casting the operands `as object` first does not
  help; **`Assembly.get_FullName` and `AssemblyName.get_Name` are NOT bound** (only `GetName`,
  `get_Location`, `GetType(string)`, `GetExportedTypes` on `Assembly` and `get_FullName` on
  `AssemblyName`), so an assembly-identity dedupe cannot be expressed in `.nl` today; and
  **`Assembly.GetType(string, bool, bool)` is likewise unbound** — use the 1-argument overload, which
  the BCL defines as exactly `GetType(name, throwOnError: false, ignoreCase: false)`.
  .nl POSITIVES CONFIRMED (recorded because they were expected to be problems and are not):
  **`List<string?>` works** — a nullable-element generic list round-trips through construction, `Add`,
  indexing and a `foreach` on the C# side, so a genuinely-nullable sequence does not need a sentinel
  encoding; and **an inline array literal is a legal argument** (`Helper(["a", "b"])` binds to a
  `string[]` parameter), which is what makes the tabular contract style readable.
  DOCS: `memory/components/analyzer.md` gains "The type-reference resolver: what is N#-owned and what
  is not" — the channel walk staying in the shell and WHY (five report sites plus a per-reference
  semantic-model write), the probe's exact order with the cache's participation in it stated as
  behaviour, the never-rebuilt/live-list discipline, the exact-versus-ordered distinction, the arity
  sweep, the ZERO-versus-−1 rule, the namespace candidate order, the suggestion policy, and the three
  recorded non-movables (the `Assembly.FullName` bootstrap-wall pair, the name-versus-type-identity
  dispatch, and the scope stack as the next prerequisite); the three new owners join the file list; and
  the stale claim that the `ActionResult` arm is blocked by `TryResolveExternalType` is corrected.
  `memory/architecture.md`'s Analyzer entry, which had drifted to slice 3's six owners, now lists all
  eleven.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability needed.
  The two capability gaps found (`Assembly.get_FullName` / `AssemblyName.get_Name`, and the 3-argument
  `Assembly.GetType`) were both routed AROUND precisely to avoid tripping it: the first by cutting
  `NamespaceExists` from the slice, the second by using the equivalent 1-argument overload. The
  packaged SDK self-emits the new classes and their 20 contracts.
  GATES: the FULL VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 846s
  (14m06s)** in a fresh isolated copy — the log says "Fresh isolated test run required: pre-commit
  verification" and it stored a NEW result (`c8a7c219c5b8dd31`), so this is not a cached whole-gate or
  per-step verdict. **105 `✓ PASSED` steps and ZERO `✗`/`FAILED` anywhere**: the format contract gate,
  unit **3,193 / 3,193** (3m19s inside the gate), every native `.tests.nl` project including
  `tests/native/ownership-audit`, **VS Code integration smoke 36 passing (41s)**, SDK pack + install,
  template pack/install/creation and the template-generated project via `nlc build`, all example
  projects, all single-file examples, `nlc check` over the examples, and the ECMA-335 **IL verification
  gate — all 67 N# assemblies pass with no new errors vs baseline**. `./scripts/reload-vscode-extension.sh`:
  EXIT 0 — language server republished, `nsharp-0.6.0.vsix` repackaged (289 files, 3.98 MB) and
  `Extension 'nsharp-0.6.0.vsix' was successfully installed`, VS Code reopened. It WAS required even
  though no LanguageServer source changed: `Analyzer.cs` ships in the `NSharpLang.Compiler` assembly the language server builds
  against, and `NSharpLang.Compiler.BootstrapServices` gained public types — which is also why the
  VS Code-enabled profile rather than the `VSCODE_TESTS=skip` path is the right bar for this slice.
  INTERACTIVE computer-use verification was NOT attempted, per the coordinator's standing instruction
  that it owns that record (the grant was DENIED four consecutive sessions). This slice adds no LSP or
  IDE behaviour of its own, and its diagnostics are proven byte-identical corpus-wide.
  **NEXT SUB-SLICE — STAGE 2 OF THE `ResolveType` ARC: THE SCOPE STACK, AND IT IS NOW THE SOLE
  PREREQUISITE FOR THE NAME WALK.** The measured remainder of the closure is exactly:
  `ResolveType` :18082 itself with `RecordResolvedTypeReference`, `ResolveDeclaredType`,
  `ResolveSimpleType` (both overloads), `ResolveGenericType`, `ResolveAnonymousUnionType`,
  `ReportSoaRowTypeReferenceIfNeeded`, `TryResolveDottedNestedType`, the
  `TryResolveVisibleProjectType` family, `NamespaceExists` + `GetExternalSearchAssemblies`, and the
  scope readers. Take the SCOPE STACK next: `Scope` is already N# (`AnalyzerStateModels.nl`), so the
  slice is the `Stack<Scope>` field and its **51** sites — `LookupType` (25 sites), `LookupSymbol`,
  `GetAllTypesInScope`, `TryRecordTypeBinding`, `TryLookupNullState`, `SetNullStateInCurrentScope`,
  `RegisterErrorTupleResult` and the `_scopes.Peek().Types[...] = ...` declaration writes — moved to an
  N# `AnalyzerScopeStack` owner. It reports nothing and records nothing (measured), it is the last
  non-N# dependency of 5 of the name walk's 8 channels, and `GetAllTypesInScope` is the only remaining
  C# input to the now-N# suggestion policy. After it, stage 3 (project discovery, blocked on a source
  provider) and stage 4 (the reporting/recording walk, which needs an N#-owned diagnostic sink and
  semantic-model writer) are the two remaining pieces before the assignability SCC falls in one cut.
  TWO SMALLER PREREQUISITES REMAIN RECORDED AND UNCHANGED: `CreateFunctionTypeInfoFromDelegate`
  (32 live calls) still needs the reflection half of `NullabilityMetadata`, which lives ABOVE
  BootstrapServices; and `Assembly.get_FullName` / `AssemblyName.get_Name` on the columnar external
  binding surface would release `NamespaceExists` and `GetExternalSearchAssemblies` together.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `72ffc3113`): **017 SLICE 6 —
  `IsAssignable`, MEASURED FIRST, THEN RECUT TO THE TERMINAL SUB-CLOSURE.**
  MANDATED TARGET: `IsAssignable` (:19306) and its 12-arm closure, measure-first.
  THE MEASUREMENT (done BEFORE any production edit; a throwaway instrumented Debug/Release build
  counting every arm and every fallback, run over all 40 `project.yml` corpus targets AND the full
  3,193-test unit suite, then reverted):
  * **NO REPORTING ARM AND NO `_semanticModel` WRITE ANYWHERE IN THE CLOSURE.** A brace-matched read
    of all 22 members finds zero `Error(`, zero `_errors`, zero `_semanticModel`.
  * `_activeImplicitConversions` — the re-entrancy set — is read/written by `HasImplicitConversion`
    ONLY (2 sites), so it moves with that arm and nothing else.
  * THREE REMAINING C#-ENGINE READS, all static facts (not counts): (a) `ImplementsDuckInterface` →
    `MethodSignaturesMatch` → **`ResolveType` ×4**, and `ResolveType` both RECORDS into the semantic
    model (`RecordResolvedTypeReference` :18147) and REPORTS diagnostics (`ReportSoaRowTypeReference`,
    unresolved-type reporting) — moving that arm would silently drop semantic-model records, exactly
    the case the mandate says to recut around; (b) `IsAspNetActionResultGenericAssignable` →
    `TryResolveExternalType` (`_mlcAssemblies` + `_usingNamespaces` + `_externalTypeCache`);
    (c) `IsSubtypeOf` / `HasImplicitConversion` → `ResolveTypeForSourceOwner` (N# context, with a
    `ResolveType` fallback) and `ResolveGenericDefinition` → `LookupType` (the `_scopes` stack).
  * `IsAssignable` is one strongly-connected component with `IsSubtypeOf`, `HasImplicitConversion`,
    `IsKnownGenericTypeAssignable`, `IsFunctionTypeAssignable`, `IsLambdaAssignableToDelegate`,
    `TryGetDelegateSignatureConversionScore`, `TryGetRuntimeDelegateMethodGroupMatchScore` and
    `IsFunctionTypeAssignableToRuntimeDelegateMethodGroup` — every one of them reaches
    `IsAssignable`, whose own dispatch contains the duck arm. **So the ROOT cannot move until
    `ResolveType` moves**, and no callback is permitted.
  * `CreateFunctionTypeInfoFromDelegate` is blocked by ASSEMBLY DIRECTION, not by state: its
    `Invoke`-method arm calls `NullabilityMetadata.ConvertParameter/ConvertReturn`, which live in
    `NSharpLang.Compiler` — the assembly that DEPENDS on `NSharpLang.Compiler.BootstrapServices`, so
    an N# owner cannot reach them. Recorded as a nullability-metadata prerequisite.
  THE RECUT (largest terminal sub-closure — every dependency N#-owned, no engine read, no callback):
  ONE new N# owner `AnalyzerAssignabilityFacts`, constructor
  `(context: AnalyzerDeclarationContext, wellKnown: AnalyzerWellKnownTypes?)` — slice 5's
  rebuild-at-the-two-mutation-points instance pattern — taking:
  * `IsCollectionType` :20102 (the collection-expression element-type table),
  * `IsArrayToSpanAssignable` :19623, `IsReferenceLikeForVariance` :19642,
    `MayUseDelegateReferenceConversion` :19815,
  * `CanBindCallableReferenceToExpectedType` :6816 + `IsDelegateType` :9857 (the delegate-target
    classification pair),
  * and `IsKnownGenericTypeAssignable`'s ENTIRE POLICY :19562 — the known-conversion name-pair
    matrix, the covariant-target set, the arity and known-runtime-definition gates and the
    argument-equality skip — handed back as an explicit decision plus the ordered list of argument
    pairs whose assignability only the (still-C#) root can answer.
  BAR: differential probe against the reflected C# originals over an exhaustive grid, built and run
  BEFORE the deletion and deleted after; `nlc check --json` byte-identical 40/40 + purpose-built
  assignability fixtures; corpus IL 64/64 byte-identical; unit 3,193; contracts ≥1,596; audit 18/18;
  manifest 391 lines in place; `dev.sh --since`; the FULL VS Code-enabled gate + VSIX reload.
  **RESULT: LANDED (no commit — mandate).** `AnalyzerAssignabilityFacts` is the sole authority for
  every assignability arm listed above, with no callback, fallback, shadow path or comparison route.
  THE MEASUREMENT NUMBERS (the instrumented build was reverted; `Analyzer.cs` is byte-identical to
  `a60260357` apart from this slice's cut, and the 3,193-test suite passed WITH the probe armed, so
  the instrumentation was behaviour-neutral): over the 40-target corpus and the full unit suite,
  `IsAssignable` fires 6,010 / 14,552 times; `IsSubtypeOf` 50 / 419; `HasImplicitConversion` 42 / 332;
  `ImplementsDuckInterface` 0 / **19** (17 class, 1 record, 1 struct) with `MethodSignaturesMatch`
  0 / **32** — i.e. **128 live `ResolveType` calls inside the closure**, each one recording into the
  semantic model; `IsAspNetActionResultGenericAssignable` 74 / 507 of which **1** reaches
  `TryResolveExternalType`; the delegate scorer 0 / 61; `IsCollectionType` 46 / 116;
  `IsArrayToSpanAssignable` 4,970 / 9,376; `CanBindCallableReferenceToExpectedType` 9,938 / 21,527;
  `IsDelegateType` 6,048 / 9,023; `IsKnownGenericTypeAssignable` 74 / 506. TWO FALLBACKS MEASURED
  DEAD and recorded rather than acted on: `ResolveTypeForSourceOwner`'s `ResolveType` fallback fired
  **0** times out of 5,256 calls (all took `_declarationContext.TryResolveTypeForOwner`), and
  `ResolveGenericDefinition`'s `LookupType` scope-stack fallback **0** times out of 1,769. They are
  NOT the reason the root stayed: `IsSubtypeOf` and `HasImplicitConversion` are inside the SCC with
  `IsAssignable`, whose dispatch holds the duck arm.
  DELETIONS (exact, 6 whole C# members + 2 bodies replaced by protocol shells):
  * `IsCollectionType` (61 lines), `CanBindCallableReferenceToExpectedType` (13),
    `IsArrayToSpanAssignable` (18), `IsReferenceLikeForVariance` (10) — which had NO caller left once
    the known-generic policy moved, so it is a pure deletion — `MayUseDelegateReferenceConversion`
    (9), `IsDelegateType` (7);
  * `IsKnownGenericTypeAssignable` 45 → 15 lines and `IsFunctionTypeAssignable` 31 → 14 (its 5-line
    XML doc goes with it): both are now the pending-pair protocol's other half and contain ZERO
    classification.
  ROUTING: **13 sites**, every one inside `Analyzer.cs` (a grep over `src/` + `tests/` + `editors/`
  finds no external consumer of any of the eight members) — 5 `IsDelegateType` (:9792 lambda target,
  :13018 delegate construction, :13876 the callable-reference switch arm, :15828 + :15837 the
  lambda-inference pair), 2 `CanBindCallableReferenceToExpectedType` (:6780, :19345), 2
  `IsCollectionType` (:15929, :19438), 1 `IsArrayToSpanAssignable` (:19365), 2
  `MayUseDelegateReferenceConversion` (:19754-19755 in the delegate scorer), and the 2 shells' own
  calls into the owner.
  C# ADDED: **28 lines total, all mechanical** — one field, one line in the parameterless `Analyzer`
  constructor, one rebuild line at each of the two `_wellKnownTypes` mutation points (:21858 build,
  :21868 dispose — the slice-5 rebuild-not-mutate pattern, extended to this owner), and the two
  protocol shells. **NO new method, helper, bridge, callback or state**; the pending-pair loop is
  INLINED in both shells rather than shared, because a shared helper would be new C#.
  `git diff` on `Analyzer.cs` is **+28 / −194 = net −166**; the file is **22,409 → 22,243**
  (non-blank 19,680 → 19,538).
  N# ADDED: `AnalyzerAssignabilityFacts.nl` (**408 lines, TWO classes** — the 7-member
  `AnalyzerAssignabilityDecision` protocol type and the 15-member owner: 2 fields, the constructor,
  8 public entry points, 4 file-private statics; both far inside the per-class ceiling) +
  `AnalyzerAssignabilityFacts.tests.nl` (656 lines, **11 contracts**).
  THREE NON-MECHANICAL DECISIONS: (1) **THE PENDING-PAIR PROTOCOL** — the known-generic and
  function-type relations cannot finish without re-entering assignability, and a callback is
  forbidden, so they answer with a DECIDED verdict or the ORDERED pairs the caller must answer. It is
  behaviour-preserving because the C# originals short-circuited in exactly that order and
  `IsAssignable` reports nothing; the differential proves it cell by cell. (2) **`IsCollectionType`'s
  reflection arm is gated on `IsGenericType && !IsGenericTypeDefinition`, not on `IsGenericType`** —
  the original read `Type.GenericTypeArguments`, which is `IsConstructedGenericType ?
  GetGenericArguments() : EmptyTypes`, so an OPEN `List<>` must answer nothing; using
  `GetGenericArguments()` without that gate would have handed callers a type PARAMETER as the element
  type. The probe pins both readings on `List<>` in the runtime and metadata universes. (3) **the
  span definitions are resolved by canonical identity** (`Type.GetType("System.Span`1,
  System.Private.CoreLib")`, the established `TypeInfoIdentityFacts` idiom) because `typeof(Span<>)`
  is off the columnar `typeof` surface.
  PROOF — DIFFERENTIAL AGAINST THE C# ORIGINALS, BUILT AND RUN BEFORE THE DELETION, DELETED AFTER
  (the tree has zero probe residue): a throwaway xunit probe reflected into the private C# members on
  a REALLY-LOADED analyzer (`new Analyzer(); LoadSystemAssemblies(); Analyze(...)` over an 8-alias /
  7-declared-family source) and on a SECOND analyzer with no `LoadSystemAssemblies` — the live
  `wellKnown == null` state — and compared them against the N# owner cell by cell, by value OR THROWN
  EXCEPTION TYPE. **420,946 CELLS, 0 MISMATCHES, 0 THROWN CELLS.** The grid: 361 loaded TypeInfo
  values (19 built-ins × bare/array/nullable, oblivious, byref, jagged, array-of-nullable, tuple,
  anonymous union, the 7 declared families bare/arrayed/nullable, 8 registered aliases in 4 positions
  each, 20 generic NAMES × 6 element types plus a no-definition, a zero-arity and a two-argument
  variant each, `Dictionary`/`Func`/`Action`/a stranger, and 19 reflection names taken BOTH from the
  MetadataLoadContext — open, closed-over-`string` and as a type PARAMETER — and from the host
  runtime) squared for the two two-argument relations, 107 CLR types for the delegate test, and 16
  function types (arity 0-2, unknown parameter, unknown return, null return, null parameter list,
  null both, alias parameter and return, declared-type parameter and return, array parameter) squared.
  The positives are real: 200 true known-generic cells, 24 true array-to-span, 131 true collection
  cells over 6 distinct element-type shapes, 145 true function-type cells, 8 true delegate cells, 25
  true callable-reference cells, 533 true variance cells.
  PROOF — BEFORE/AFTER TRANSCRIPT: the same probe wrote a **420,946-row** transcript of every cell;
  re-emitted from the N# owner reached through the analyzer's own `_assignabilityFacts` field AFTER
  the deletion it is **byte-identical (diff = 0, md5 `d08a772ab66302ed525444685ce02683` both times)**,
  which also proves the two rebuild points hand the owner the right collaborators.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `a60260357` in a throwaway `/tmp/nsharp017s6` worktree and at the working tree, **byte-identical on
  40 / 40 `project.yml` targets (ORACLE_TARGETS=40, ORACLE_DIFFS = 0)**, plus **5 purpose-built
  assignability fixtures firing 26 diagnostics, FIXTURE_DIFFS = 0**: collection expressions against
  `List`/`HashSet`/`IReadOnlyList`/`SortedSet`/`Queue`/`Dictionary`/`List<Widget>`/`List<object>`/
  `List<List<int>>` (6 × NL202, including the `Dictionary` decline and the nested-element case, with
  the read-only and sorted spellings correctly ACCEPTED); the known-generic relation across
  `List`/`HashSet`/`Queue` into `IEnumerable`/`ICollection`/`IList`/`IReadOnlyList` at matching,
  covariant, invariant and widening arguments (5 × NL202); array-to-span at the right element type,
  through an ALIASED element type, and at two wrong ones (2 × NL202); method groups and lambdas
  against `Func`/`Action` targets and a non-delegate (4 × NL202 + 1 × NL411); and function-type
  arity/parameter/return mismatches (5 × NL202).
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, the established explicit PE/CLI normalizer
  touching ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries
  and the CodeView blobs they point at, and the `#GUID`/`#Pdb` heaps): **64 / 64 comparable
  assemblies BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (26 from the
  `project.yml` targets, 38 single-file examples, SINGLE_LOG_DIFFS = 0), with the same 7
  `tests/native/*` targets that do not build standalone failing identically at baseline and after
  (**SKIPPED_TARGET_DIFFS = 0**).
  ASSERTION MIGRATION: all eight members were `private`, so no test named them; their behaviour was
  pinned only INDIRECTLY by end-to-end analyzer diagnostics, which STAY and now execute against the
  N# owner (the slice-1/2/3/4/5 and 016 classification-(a) precedent). The DIRECT pinning is new and
  native: **11 contracts** covering every accepted known-generic pair and the closed table's
  refusals in both directions, both sides' runtime-definition requirement, arity-before-table,
  covariant pairs handed back vs. value-typed arguments decided false vs. mutable targets refused;
  alias resolution before variance and the OPAQUE unowned alias; reference-likeness through the
  nullable and oblivious shells and the `Nullable<T>`-spelled-generically exception; the collection
  table's fifteen generic spellings, its narrower twelve-name reflection arm and the OPEN-definition
  refusal; array-to-span nominal on the target, invariant on the element, alias-resolved on both
  halves; function-type arity, the inferred-parameter skip, the null-return and null-parameter-list
  rules and the two DIRECTIONS; callable-reference binding to a function type, the two names exactly,
  the shells and a real runtime delegate; and `IsDelegateType` answering nothing without facts, then
  answering for `Action`/`EventHandler`/`Func\`2` while REFUSING both abstract roots and a
  host-runtime delegate.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m13s —
  exactly the slice-1/2/3/4/5 baseline, zero drift); BootstrapServices contracts **1,596 → 1,607**
  (+11) via the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false`, **1,607 / 1,607 PASS** (the 3 ExternalAssemblyScan Debug-layout tests
  did not trip); ownership audit **18 / 18** after the repin; `./scripts/dev.sh --since`; the oracle,
  differential, transcript and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s6.py` (slice 2/3/4/5's script, unchanged apart from its
  header) — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs`
  currentLines 22,409 → **22,243**, currentNonBlankLines 19,680 → **19,538**, fingerprint
  `text-v1:59454bd5ce828173` → `text-v1:3160b9b907f7abe8` (epoch ceilings 23,451 / 20,537 PRESERVED
  and now clear by 1,208 / 999); `reviewedHeadFingerprint head-v1:4a87a5ed8adc448d` →
  `head-v1:8eee56698b0d2f9e`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` (381) untouched and RE-VALIDATED by recomputation after
  the write. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND after, and the
  `git diff` is exactly 2 changed lines.** The `.nl` additions need no row.
  .nl GOTCHAS ADDED: **a chained instance call on a member-access or call result declines**
  (`reflection.Type.get_FullName()` and `candidate.GetType().Name` both trip
  `emit.return.expression`; bind the receiver to a local); **returning a `string?` where the
  signature says `string` declines** even after a null guard — annotate the local
  (`name: string? = …`) and return through a checked branch; **`GetType()` on a `TypeInfo`-typed
  receiver declines** at `emit.local.initializer`, confirming the recorded rule; and **`typeof` over
  most generic collection types is off the columnar surface** (`typeof(List<int>)` and
  `typeof(IEnumerable<int>)` work, `typeof(ICollection<int>)` / `typeof(IList<int>)` /
  `typeof(HashSet<int>)` / `typeof(Queue<int>)` / `typeof(SortedSet<int>)` / `typeof(Span<int>)` do
  NOT) — resolve open definitions by canonical identity with `Type.GetType` and close them with
  `MakeGenericType`.
  GATES: the FULL VS Code-enabled `./scripts/test-all.sh --commit` **ALL TESTS PASSED in 17m08s** in a
  fresh isolated copy (`Stored validated isolated test cache result: 38ea76da14afa0a4`) — every step
  green including the format contract gate, unit **3,193 / 3,193**, the native `.tests.nl` estate
  **1,607 / 1,607**, **VS Code integration smoke 36 passing**, SDK pack + install, template creation
  and build, all example projects and single-file examples, `nlc check` over the examples, and the
  ECMA-335 **IL verification gate — all 67 N# assemblies pass**. `nsharp-0.6.0.vsix` rebuilt and
  reinstalled via `./scripts/reload-vscode-extension.sh`. INTERACTIVE computer-use verification was
  NOT attempted, per the coordinator's instruction that it owns that record (denied 4 consecutive
  sessions); this slice adds no LSP/IDE behaviour of its own — `Analyzer.cs` ships in the
  `NSharpLang.Compiler` assembly the language server builds against, which is why the VS Code-enabled
  gate rather than the `VSCODE_TESTS=skip` path is the right bar.
  DOCS: `memory/components/analyzer.md` gains "The assignability shape decisions" — the closed
  known-generic table, the four covariant targets and why the mutable ones are invariant, the two
  DIFFERENT collection arms and the open-definition rule, the span rule, the callable-reference and
  concrete-delegate rules, the pending-pair protocol with its two directions and the inferred-parameter
  rule, and the measured statement of why `IsAssignable` itself stayed — plus the new owner in the
  file list.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability
  needed. The packaged SDK self-emits the new classes and their 11 contracts.
  **NEXT SUB-SLICE — `ResolveType(TypeReference)`, AND IT IS NOW THE ONLY THING BLOCKING THE ROOT.**
  The measured remainder of the `IsAssignable` closure is exactly: `IsAssignable` itself (:19306, 147
  lines), `IsSubtypeOf`, `HasImplicitConversion` (+ its `_activeImplicitConversions` re-entrancy set,
  which must move WITH it and with nothing else), `ImplementsDuckInterface` + `MethodSignaturesMatch`,
  `IsAspNetActionResultGenericAssignable`, `IsLambdaAssignableToDelegate`,
  `TryGetDelegateSignatureConversionScore`, `TryGetRuntimeDelegateMethodGroupMatchScore`,
  `IsFunctionTypeAssignableToRuntimeDelegateMethodGroup` and the two protocol shells. They are ONE
  strongly-connected component and their only non-N# dependencies are now (a) `ResolveType` — via the
  duck arm's `MethodSignaturesMatch`, 128 live calls, semantic-model-recording and
  diagnostic-reporting — and (b) `TryResolveExternalType` — via the ActionResult arm, 1 live call,
  `_mlcAssemblies` + `_usingNamespaces` + `_externalTypeCache`. Take the type-REFERENCE engine next
  (its own sub-slices: `ResolveSimpleType`/`ResolveGenericType` name resolution, the
  `RecordResolvedTypeReference` semantic-model write, and the MLC external-type probe), and the whole
  assignability SCC follows in one cut. A THIRD, SMALLER prerequisite is also now measured:
  `CreateFunctionTypeInfoFromDelegate` (32 live calls) is blocked ONLY by assembly direction — it
  needs `NullabilityMetadata.ConvertParameter/ConvertReturn`, which live in `NSharpLang.Compiler`
  above BootstrapServices — so N#-owning the reflection half of `NullabilityMetadata` unblocks it and
  the method-group arm of `IsAssignable` with it.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `a60260357`): **017 SLICE 5 — THE
  CLR-CONVERSION FUNNEL.**
  TARGET: move the analyzer's entire TypeInfo → CLR `Type` construction family out of `Analyzer.cs`
  into ONE new N# owner, `AnalyzerClrTypeConversion`, and DELETE the C# methods.
  THE STATE SURFACE, RE-VERIFIED BY READING EACH METHOD AT THIS TREE (not inherited from the
  slice-4 re-derivation): `_declarationContext.ResolveDeclaredAlias` (N#), `_wellKnownTypes` — an
  `AnalyzerWellKnownTypes` since slice 3 (N#), `AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType` /
  `.KnownOpenGenericType` / `.BindingSurrogateOpenGenericType` (N#), `BuiltInTypes.Is` (N#), and
  the reflection surface on `Type` itself. **CONFIRMED: no `ResolveType`, no `_errors`, no
  `_semanticModel`, no scope stack, no `_mlc`, no `_currentFilePath` anywhere in the closure.**
  THE UNIT (7 C# members, by pre-edit line):
  * `TryConvertTypeInfoToClrType(TypeInfo)` :10164 — public on the owner;
  * `TryConvertTypeInfoToClrTypeForBinding(TypeInfo)` :9657 — public on the owner;
  * `TryConstructDelegateType(FunctionTypeInfo)` :10259 — public (it has ONE external caller,
    :13412, the lambda-to-delegate path);
  * `TryConstructRuntimeUnionType` :10201, `TryConvertNullableType` :10214,
    `TryConstructKnownGenericType` :10223 — file-private on the owner (zero external callers);
  * `IsJsonTypeInfoGenericName(string)` :9368 — the `private static` name predicate; its ONLY
    caller is :10247 inside `TryConstructKnownGenericType`, so it moves cleanly with the family.
  EXACT CALL-SITE MAP (measured, not estimated; a grep over `src/` + `tests/` + `editors/` finds NO
  external consumer of any of the seven): `TryConvertTypeInfoToClrType(` 39 occurrences =
  1 definition + 9 in-family + **29 sites**; `TryConvertTypeInfoToClrTypeForBinding(` 15 =
  1 + 4 in-family + **10 sites**; `TryConstructDelegateType(` 3 = 1 + 1 in-family + **1 site**; the
  other three and the predicate are 100% in-family. **40 sites route.**
  ONE DIVERGENCE FROM THE RE-DERIVATION, RECORDED BECAUSE IT DRIVES THE DESIGN: `_wellKnownTypes`
  is NOT readonly. It is null until `LoadSystemAssemblies` :22056 builds it and is set back to null
  in `Dispose` :22067, and the null state is LIVE (it selects the `BuiltInRuntimeClrType`
  no-metadata fallback). So the owner cannot be a single instance captured once at field-init;
  it is rebuilt at exactly those two mutation points, keeping its own fields immutable.
  OWNER DESIGN: a new sibling file `AnalyzerClrTypeConversion.nl` in the `Analyzer*` family, one
  class, constructor `(context: AnalyzerDeclarationContext, wellKnown: AnalyzerWellKnownTypes?)` —
  the slice-3/4 constructor-argument pattern — well inside the per-class member ceiling. C# side:
  one field, one 3-line parameterless `Analyzer` constructor to hand the owner the declaration
  context (a field initializer cannot reference another instance field), and one rebuild line at
  each of the two `_wellKnownTypes` mutation points. NO other new C#.
  BAR: a differential probe over the whole conversion surface taken BEFORE the deletion and deleted
  after (nested aliases at every position, unions, nullables, known generics, delegates, binding
  surrogates, MLC types, exception-type comparison); `nlc check --json` byte-identical on 40/40
  targets + purpose-built fixtures; corpus IL 64/64 byte-identical; unit 3,193; contracts ≥1,585;
  audit 18/18; manifest 391 lines; `dev.sh --since`; the FULL VS Code-enabled gate + VSIX reload.
  **RESULT: LANDED (no commit — mandate). THE FUNNEL NO LONGER EXISTS IN `Analyzer.cs`.**
  `AnalyzerClrTypeConversion` is the sole authority for TypeInfo → CLR `Type` construction, with no
  callback, fallback, shadow path or comparison route.
  THE STATE-READ MAP, VERIFIED BY READING ALL SEVEN MEMBERS AT THIS TREE: `TryConvertTypeInfoToClrType`
  → `_declarationContext.ResolveDeclaredAlias`, `_wellKnownTypes` (null check + 16 field reads),
  `AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType`, `BuiltInTypes.Is`, `ReflectionTypeInfo.Type`;
  `TryConstructRuntimeUnionType` → `_wellKnownTypes.GetRuntimeUnionOpen()`, `Arms`;
  `TryConvertNullableType` → `_wellKnownTypes.NullableOpen`; `TryConstructKnownGenericType` →
  `AnalyzerWellKnownTypeFacts.KnownOpenGenericType`, `IsJsonTypeInfoGenericName`;
  `TryConstructDelegateType` → `_wellKnownTypes.Action`/`Action1-4`/`Func1-5`;
  `TryConvertTypeInfoToClrTypeForBinding` → `ResolveDeclaredAlias`, `_wellKnownTypes.Object`/
  `.NullableOpen`, `AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType`;
  `IsJsonTypeInfoGenericName` → nothing. **The slice-4 re-derivation HOLDS: no `ResolveType`, no
  `_errors`, no `_semanticModel`, no scope stack, no `_mlc`, no `_currentFilePath`.**
  ONE MEASURED DIVERGENCE (recorded because it drove the design): `_wellKnownTypes` is NOT readonly —
  null until `LoadSystemAssemblies` :22056, null again in `Dispose` :22067 — and the null state is
  LIVE (it selects the `BuiltInRuntimeClrType` runtime-type fallback). So the owner is REBUILT at
  those two points instead of being captured once or given a setter; its fields are immutable after
  construction.
  DELETIONS (exact, by pre-edit line range — 7 C# members, **210 lines**):
  * `10164-10304` (141) the five-method block: `TryConvertTypeInfoToClrType` (36),
    `TryConstructRuntimeUnionType` (12), `TryConvertNullableType` (8),
    `TryConstructKnownGenericType` (35), `TryConstructDelegateType` (45) + 4 blank separators;
  * `9652-9717` (66) `TryConvertTypeInfoToClrTypeForBinding` with its 5-line XML doc + separator;
  * `9368-9370` (3) `IsJsonTypeInfoGenericName` + separator.
  ROUTING: **40 sites, exactly as pre-measured** — 29 `TryConvertTypeInfoToClrType`,
  10 `TryConvertTypeInfoToClrTypeForBinding`, 1 `TryConstructDelegateType` (:13412, the
  lambda-to-delegate path) — every one inside `Analyzer.cs`; a grep over `src/` + `tests/` +
  `editors/` finds NO external consumer of any of the seven. `_clrTypeConversion` now occurs 44
  times = 40 sites + 1 field + 3 assignments.
  C# ADDED: **11 lines, all mechanical wiring** — the field declaration + its 2-line comment, a
  3-line parameterless `Analyzer()` constructor (a field initializer cannot reference
  `_declarationContext`, so the owner is handed its collaborator there), one rebuild line at each of
  the two `_wellKnownTypes` mutation points, and one extra line from re-targeting a `<see cref>` that
  named a now-deleted member. No new method, helper, bridge or state.
  `git diff` on `Analyzer.cs` is **+52 / −251 = net −199**; the file is **22,608 → 22,409**
  (non-blank 19,848 → 19,680).
  N# ADDED: `AnalyzerClrTypeConversion.nl` (**439 lines, one class, 18 members** — 2 fields, the
  constructor, 3 public entry points, 5 file-private instance helpers, 5 file-private statics; well
  inside the per-class ceiling) + `AnalyzerClrTypeConversion.tests.nl` (612 lines, **11 contracts**).
  THREE NON-MECHANICAL DECISIONS: (1) **the owner is an INSTANCE rebuilt at the two `_wellKnownTypes`
  mutation points**, not a static class taking the context + bag as arguments at all 40 sites (which
  would have added ~40 wrapped lines at call sites) and not a mutable-setter object (which would
  duplicate live state). (2) **`TryConstructDelegateType` is PUBLIC** while the other three helpers
  are file-private, because it has one genuine external caller; publishing only what is called keeps
  the surrogate/exact distinction enforceable. (3) **`NormalizeOpenDefinition` is shared** by both
  generic constructors — the C# stated the same three-case reduction twice (closed → definition,
  already-open → itself, non-generic → not a definition) and it is proven equivalent case by case.
  PROOF — DIFFERENTIAL AGAINST THE C# ORIGINALS, BUILT AND RUN BEFORE THE DELETION, DELETED AFTER
  (the tree has zero probe residue): a throwaway xunit probe reflected into the private C# methods on
  a REALLY-LOADED analyzer (`new Analyzer(); LoadSystemAssemblies(); Analyze(...)` over a 16-alias /
  6-declared-family source) and compared them against the N# owner cell by cell, by VALUE OR THROWN
  EXCEPTION TYPE. **800 TypeInfo shapes, 1,682 comparison cells, 0 MISMATCHES**, of which **5 cells
  agree on a THROWN exception** rather than a value. Coverage: all 18 built-in simple names × 7
  wrappers (bare/array/array-of-array/nullable/oblivious/nullable-of-oblivious/array-of-nullable);
  unknown / inference-hole / deferred-external / stranger-simple / external / newtype / byref /
  unregistered-alias; the 6 declared families (class, record, struct, interface, enum, union) bare,
  arrayed, nullable and as a `List` argument; MLC `System.String` and the MLC open `List\`1` as a
  carried definition at arity 1 and 2; runtime `int`, a closed-generic carried definition, a
  non-generic carried definition and a non-Reflection carried definition; 16 generic NAMES × 5
  arities (0,1,2,3,5) plus 2 user-argument variants each; nested generic / generic-of-nullable /
  generic-of-array; 18 function types (void and value returns at arities 0-5, null return, null
  parameter list, nested function, array parameter, user parameter, user return); unions at arity
  0/1/2/3 plus nested and user arms; a tuple; and **all 16 REGISTERED aliases × 15 positions** —
  bare, array, array-of-array, nullable, oblivious, `List` argument, `Dictionary` second argument,
  nested-generic argument, `JsonTypeInfo` argument, delegate parameter, delegate return, both,
  union arm, both arms, tuple element. The whole grid was ALSO run against a SECOND analyzer with no
  `LoadSystemAssemblies` — the live `_wellKnownTypes == null` state that selects the runtime-type
  fallback — which is where the 5 exception-typed cells come from.
  PROOF — BEFORE/AFTER TRANSCRIPT: the same probe wrote a **1,170-row** transcript of both entry
  points (and the delegate constructor) over the loaded grid from the C# ORIGINALS before the
  deletion; re-emitted from the N# owner after the deletion it is **byte-identical (diff = 0)**.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `ac389ecac` in a throwaway `/tmp/nsharp017s5` worktree and at the working tree (both trees' Debug
  CLIs built too — the slice-4 environmental artefact), **byte-identical on 40 / 40 `project.yml`
  targets (ORACLE_TARGETS=40, ORACLE_DIFFS = 0)**, plus **6 purpose-built fixtures firing 39
  diagnostics, FIXTURE_DIFFS = 0**: compiler-known generics at right and wrong arity
  (`List`/`Dictionary`/`IEnumerable`/`ICollection`/`IList`/`Task`/`ValueTask`, nested `List<List<…>>`,
  `List<Widget>`), the `Func<…>` delegate surface across arities 0-5 in both void and value form with
  deliberate shape mismatches, nullable/array/jagged/array-of-nullable shells, alias conversions
  (alias-to-builtin/generic/nullable/array/class, chains, alias-as-generic-argument), binding
  surrogates (LINQ `Count`/`FirstOrDefault`/`Select`/`ToList` over `List<Widget>`, a
  `Dictionary<string,Widget>`, a `List<Color>`), and anonymous-union returns with a user arm.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, the established explicit PE/CLI normalizer
  touching ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries
  and the CodeView blobs they point at, and the `#GUID`/`#Pdb` heaps): **64 / 64 comparable
  assemblies BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (26 from the
  `project.yml` targets, 38 single-file examples, SINGLE_LOG_DIFFS = 0), with the same 7
  `tests/native/*` targets that do not build standalone failing identically at baseline and after
  (**SKIPPED_TARGET_DIFFS = 0**).
  ASSERTION MIGRATION: all seven members were `private`, so no test named them; their behaviour was
  pinned only INDIRECTLY by end-to-end analyzer diagnostics, which STAY and now execute against the
  N# owner (the slice-1/2/3/4 and 016 classification-(a) precedent). The DIRECT pinning is new and
  native: **11 contracts** covering the 16 built-ins as METADATA types proven not reference-equal to
  the compiler's `typeof`; `null`/`never`/unknown/stranger answering nothing; array, jagged, nullable
  value-vs-reference and oblivious descent with poisoned positions; the compiler-known table at exact
  arity, wrong arity, wrong case and unknown name; a carried definition overriding the table, being
  normalized from CLOSED to open, rejected when non-generic, and NOT falling back to the table when
  present-but-unusable; `JsonTypeInfo` as the ONE surrogate-accepting generic in both spellings, with
  `List`/`Task` proven to decline the same argument and a stranger argument proven to decline even
  there; `Action` 0-4 / `Func` 0-4 with arity-5 declines and the type-shaped entry point agreeing;
  anonymous unions declining at every arity without the runtime assembly, including the arity that
  WOULD construct; the surrogate substituting `object` for all 7 declared families and rebuilding
  array/nullable/`List`/`Dictionary` shells while the exact conversion refuses them; the surrogate
  vocabulary's deliberate omission of both `Result` spellings; a registered alias resolved at 9
  nested positions with an unowned alias proven transparent; and the no-facts path answering RUNTIME
  types, declining generics/functions/unions, and — the precise rule — resolving the TOP-LEVEL alias
  but NOT a nested one.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m14s —
  exactly the slice-1/2/3/4 baseline, zero drift); BootstrapServices contracts **1,585 → 1,596**
  (+11) via the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false`, **1,596 / 1,596 PASS** (the 3 ExternalAssemblyScan Debug-layout tests
  did not trip); ownership audit **18 / 18** after the repin; `./scripts/dev.sh --since` PASS — it
  correctly took the FULL unit-suite fail-safe, **3,193 / 3,193**; the oracle, differential,
  transcript and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s5.py` (slice 2/3/4's script, unchanged apart from its
  header) — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs`
  currentLines 22,608 → **22,409**, currentNonBlankLines 19,848 → **19,680**, fingerprint
  `text-v1:4cb7a19e315c5877` → `text-v1:59454bd5ce828173` (epoch ceilings 23,451 / 20,537 PRESERVED
  and now clear by 1,042 / 857); `reviewedHeadFingerprint head-v1:191f5810e69ee49c` →
  `head-v1:4a87a5ed8adc448d`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` (381) untouched and RE-VALIDATED by recomputation after
  the write; the script self-checks by reproducing all three composite fingerprints over the 381 rows
  before changing anything. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND
  after, and the `git diff` is exactly 2 changed lines.** The `.nl` additions need no row —
  `OwnershipPolicy.Classify` ignores `.nl`.
  .nl GOTCHAS CONFIRMED/ADDED: **`record` is RESERVED and cannot be a local name** (`record := …`
  makes the columnar front end decline the WHOLE test at `parse.test`, reported at the test's own
  line — the same shape as slice 1's `type` and slice 4's `newtype`); **a method call on an ARRAY
  INDEX expression declines** (`arguments[index].get_FullName()` →
  `emit.call.instance-member-unmodeled`; bind the element to a local first); **omitting a defaulted
  CONSTRUCTOR parameter declines** at `emit.expression-statement.call`, the constructor analogue of
  the recorded free-function rule (pass every defaulted argument explicitly).
  DOCS: `memory/components/analyzer.md` gains a "The CLR-conversion funnel" section stating the two
  entry points and why they are NOT interchangeable, the delegate rule, the alias-at-every-position
  rule, the `JsonTypeInfo` exception, the arity-two union rule, and the rebuild-not-mutate discipline
  for the nullable fact bag; the file list gains the new owner; and the stale paragraph claiming
  `Analyzer.cs` still owns the funnel "because their non-alias arms recurse into `ResolveType`" — a
  premise this slice measured to be FALSE — is replaced with the accurate statement that `ResolveType`
  is a different thing and is not a dependency of the funnel.
  GATES: **the FULL VS Code-enabled `./scripts/test-all.sh --commit` is RUN BY THE COORDINATOR —
  VERDICT PENDING** (this session hit the no-progress watchdog just before it; the changeset is
  intact in the tree). It IS the right bar: `Analyzer.cs` ships in the `NSharpLang.Compiler` assembly
  the language server builds against, and `NSharpLang.Compiler.BootstrapServices` gained public
  members, so the non-VS-Code path is NOT available. VSIX reload and INTERACTIVE computer-use
  verification are likewise the coordinator's record for this slice, per its explicit instruction.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability
  needed. The packaged SDK self-emits the new class and its 11 contracts.
  **NEXT SUB-SLICE — `IsAssignable` IS NOW READY, AND HERE IS THE MEASURED REASON.** Slice 3
  recorded `IsAssignable` :19604 and its 12-arm closure (`IsSubtypeOf`, `IsCollectionType`,
  `HasImplicitConversion`, `ImplementsDuckInterface`, `IsKnownGenericTypeAssignable`,
  `IsArrayToSpanAssignable`, `IsAspNetActionResultGenericAssignable`, `IsFunctionTypeAssignable`,
  `IsLambdaAssignableToDelegate`, `TryGetDelegateSignatureConversionScore`,
  `MayUseDelegateReferenceConversion`, `IsReferenceLikeForVariance`) as blocked because every arm
  "either calls the funnels directly or recurses into `IsAssignable`, which does". **Both funnels are
  now N#**, and so are the three classification tables the closure reads
  (`AnalyzerConversionFacts` from slice 1, `AnalyzerCallableReferenceFacts` from slice 2,
  `AnalyzerWellKnownTypeFacts` from slice 3) and the alias/declaration facts (slice 4). What the next
  slice must MEASURE FIRST, exactly as slices 3-5 did rather than inherit: `IsAssignable`'s own
  remaining reads — the `_activeImplicitConversions` re-entrancy set (analyzer state that would have
  to move WITH it), `_declarationContext` (already N#), and whether any arm reports a diagnostic or
  records into `_semanticModel` (the delegate-score and duck-interface arms are the ones to read in
  full). If a diagnostic-reporting arm is found, cut to the pure sub-closure and record the
  divergence. After `IsAssignable`, `ResolveType(TypeReference)` — the diagnostic-reporting,
  semantic-model-recording, MLC-probing type-REFERENCE engine — is the arc's big remaining C# owner.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `ac389ecac`): **017 SLICE 4 — UNIFY
  ALIAS-TypeInfo IDENTITY, THEN TAKE `ResolveTypeAlias`.**
  TARGET, in order:
  (1) UNIFY THE IDENTITY. `Analyzer.cs` :369 declares a top-level type alias as
      `DeclareType(aliasDecl.Name, new AliasTypeInfo(aliasDecl.Type), …)` — a FRESH instance — and
      `DeclareType` :20965 explicitly excludes `AliasTypeInfo` from BOTH the canonical-type
      adoption (`TryGetCanonicalType`) and the registration (`RegisterCanonicalType`), so
      `AnalyzerDeclarationContext.filesByType` — keyed by TypeInfo REFERENCE identity — never
      contains it. That is why slice 3 measured the alias funnel's pure N# branch at **0/36**.
      The fix is to register the CONSTRUCTED instance with the declaration context. The
      `TryGetCanonicalType` half of the exclusion MUST STAY: the declaration context deliberately
      stores the RESOLVED target type under an alias name (`ResolveDeclarationTypeCore` :1713-1731
      resolves `TypeAliasDeclaration` eagerly and writes `byName[name] = resolvedTarget`), so
      adopting the canonical type would replace the analyzer's `AliasTypeInfo` with its target and
      change every alias-naming diagnostic. `RegisterCanonicalType` is likewise NOT reusable — it
      writes `typesByFile[file][name]`, which would poison the declaration context's own alias
      resolution and its `ResolveDeclarationTypeCore` cache. So the unification is a NEW N# entry
      point on `AnalyzerDeclarationContext` that registers an alias instance in `filesByType`
      ONLY, plus ONE mechanical C# call in `DeclareType`.
  (2) PROVE IT: rebuild slice 3's throwaway branch counters transiently and show the funnel flip
      from **0/36 → 36/0** on the same measurement setup (six corpus projects + the four-alias
      fixture), then remove the instrumentation; and show the semantic-diagnostic oracle
      BYTE-IDENTICAL (40/40 project targets) plus purpose-built alias fixtures, because the
      resolution PATH changes and the behaviour must not.
  (3) THEN TAKE `ResolveTypeAlias`. With the pure branch live, `ResolveTypeAlias(TypeInfo)` :20246
      and `ResolveTypeAlias(TypeInfo, HashSet<AliasTypeInfo>)` :20249 stop needing the C#
      TypeReference engine at all, so the decision moves into the N# owner family and the C#
      methods are DELETED, with all **143** in-class call sites routed mechanically.
  (4) `Analyzer.cs` net-negative overall; no callback, no fallback, no comparison route.
  BAR: the 0/36 → 36/0 counter proof; a differential probe over alias-resolution shapes (chains,
  alias-to-generic, alias-to-union, alias-to-function, alias-to-array/nullable, cross-file aliases,
  nested aliases, unresolvable aliases, cycles) taken BEFORE any deletion and deleted after;
  `nlc check --json` byte-identical on 40/40 targets + alias fixtures; corpus IL 64/64
  byte-identical; unit 3,193; contracts ≥1,581; audit 18/18; manifest 391 lines; `dev.sh --since`;
  the FULL VS Code-enabled gate + VSIX reload.
  **RESULT: LANDED IN FULL (no commit — mandate). BOTH HALVES SHIPPED.** Alias identity is unified,
  the alias funnel's pure N# branch is the ONLY live path, and `ResolveTypeAlias` no longer exists
  in `Analyzer.cs`; `AnalyzerDeclarationContext.ResolveDeclaredAlias` is the sole authority, with no
  callback, fallback, shadow path or comparison route.
  THE UNIFICATION (the design, exactly as reasoned above): ONE new N# entry point
  `AnalyzerDeclarationContext.RegisterDeclaredAlias(filePath, alias)` writes `filesByType[alias]`
  and NOTHING ELSE, and `DeclareType`'s registration arm calls it for the `AliasTypeInfo` case
  (`+5` lines of mechanical C#). The `TryGetCanonicalType` adoption arm KEEPS its
  `is not AliasTypeInfo` exclusion — pinned by a contract — so the analyzer's scope still holds the
  `AliasTypeInfo` and every alias-naming diagnostic is unchanged, while the canonical entry for the
  alias NAME stays the resolved target the context computes.
  COUNTER PROOF (throwaway Debug CLI, static counters dumped at process exit, rebuilt for this
  slice and DELETED after — the tree has zero probe residue):
  * Slice 3's EXACT four-alias fixture reproduces its number and then flips:
    **`aliasSeen=36 b1=0 b2=36 cycle=0` → `aliasSeen=28 b1=28 b2=0 cycle=0`.**
  * Every other measured target flips the same way and NONE keeps a `b2`: 9 purpose-built alias
    fixtures + `tests/native/direct-calls` (a corpus project slice 3's six did not include, which
    carries `type ByteArrayPool = System.Buffers.ArrayPool<byte>`) — **b2 total 523 → 0**
    (`direct-calls` 48→48/0, `alias_source` 130→130/0, `alias_chain` 90→26/0, `alias_basic`
    81→72/0, `alias_generic` 49→43/0, `alias_nested` 32/32, `alias_mismatch` 18/18,
    `alias_crossfile` 15/15, `alias_bad` 12/12, `alias_union` 12/12). `aliasSeen` FALLS on the
    chain-shaped inputs because the N# owner resolves a whole alias chain in one hop where the
    scope-stack path re-entered the funnel per link; the 5-deep chain fixture is 90 → 26.
  * **THE DELETION LICENCE: the full 3,193-test unit suite, run with the probe armed, reports
    `b1=103 b2=0`.** The C# `ResolveType` arm of the alias funnel is DEAD across the entire suite,
    the corpus and every fixture — that is what makes deleting it a relocation rather than a
    behaviour change, and it is measured, not argued.
  DELETIONS (exact, by pre-edit line range — 2 methods, 20 lines):
  * `20246-20265` `ResolveTypeAlias(TypeInfo)` (the 2-line
    `HashSet<AliasTypeInfo>(ReferenceEqualityComparer.Instance)` trampoline) and
    `ResolveTypeAlias(TypeInfo, HashSet<AliasTypeInfo>)` (17 lines: the alias arm with its
    two-branch ternary, the cycle guard, the `ObliviousTypeInfo` descent and the identity return),
    plus the blank separator.
  ROUTING: **143 call sites**, every one inside `Analyzer.cs` — a grep over `src/` + `tests/` +
  `editors/` finds NO external caller — mechanically rewritten to
  `_declarationContext.ResolveDeclaredAlias(`; the 3 self-recursions went with the definitions.
  `git diff` on `Analyzer.cs` is **+152 / −166 = net −14**; the file is **22,622 → 22,608**
  (non-blank 19,862 → 19,848). C# ADDED: **5 lines**, all of them the alias branch of the existing
  registration `if` — no new method, no helper, no bridge.
  N# ADDED: **+43 lines / 3 members** to `AnalyzerDeclarationContext.nl` (82 → 85 members):
  `RegisterDeclaredAlias`, the public `ResolveDeclaredAlias(TypeInfo)` and its file-private
  `ResolveDeclaredAliasCore(TypeInfo, HashSet<object>)`; plus **+140 lines / 4 contracts** to
  `AnalyzerDeclarationContext.tests.nl`.
  ONE NON-MECHANICAL DECISION, recorded because it is the only one in the slice: **the owner is
  `AnalyzerDeclarationContext` itself, not a new sibling.** The alias decision is a pure function of
  state that class already holds (`filesByType`, `TryResolveTypeForOwner`, the file facts); a
  sibling would have to be handed the context and would add an indirection with no owner boundary
  behind it. 85 members is well inside the practical ceiling (the class carried 82 before).
  THE CYCLE SET IS REFERENCE IDENTITY, EXACTLY AS THE C# STATED IT: `AliasTypeInfo` does not
  override `Equals`/`GetHashCode`, so a bare `new HashSet<object>()` reproduces
  `HashSet<AliasTypeInfo>(ReferenceEqualityComparer.Instance)` cell for cell — pinned by contract.
  ASSERTION MIGRATION: `ResolveTypeAlias` was `private`, so no test named it; its behaviour was
  pinned INDIRECTLY by end-to-end analyzer diagnostics, which STAY and now execute against the N#
  owner (the slice-1/2/3 and 016 classification-(a) precedent). The DIRECT pinning is new and
  native: **4 contracts** covering instance-keyed registration (a second `AliasTypeInfo` over the
  same aliased reference is a DIFFERENT fact), the untouched canonical name entry via both
  `TryResolveName` and `TryGetCanonicalType`, owned-versus-unowned resolution, resolution against
  the alias's OWN declaring file (a source class name resolves to that file's `ClassTypeInfo`), the
  array/nullable shells rebuilt rather than flattened, a two-link chain walked to a fixed point, a
  self-referential alias answering `unknown` instead of recurring, single and nested
  `ObliviousTypeInfo` transparency, and the identity case over six families INCLUDING the negative
  "an alias nested inside another family is NOT rewritten".
  PROOF — DIFFERENTIAL OVER ALIAS-RESOLUTION SHAPES (throwaway, built BEFORE the deletion, deleted
  after): **10 purpose-built alias projects, 50 diagnostics**, baseline-vs-after `nlc check --json` —
  alias-to-builtin/string/bool/array/nullable/tuple/`Func<,>`, 5-deep chains, a mutual cycle,
  alias-to-generic (`List<int>`, `Dictionary<string,int>`, `Task<int>`, nested `List<List<int>>`, a
  source `Box<T>`, and an alias USED AS A GENERIC ARGUMENT), alias-to-union with a
  direct-union CONTROL arm, alias-to-class/record/interface/enum with member access through the
  alias, cross-file aliases, namespace-qualified and external-CLR aliases
  (`System.Buffers.ArrayPool<byte>`, `System.ValueTuple<int,int>`), 6 unresolvable-target shapes and
  a type-mismatch set. **FIXTURE_DIFFS = 1 — and it is a FALSE POSITIVE BEING REMOVED**, identical
  before and after the deletion (so step 3 changed nothing on its own): `type IntList = List<int>` /
  `type BoxedAlias = Box<IntList>` / `d: BoxedAlias = new Box<List<int>>()` used to raise NL202
  "Type mismatch" whose **`expectedType` printed the compiler-internal class name
  `NSharpLang.Compiler.AliasTypeInfo`** — the scope-stack path left the alias unresolved INSIDE the
  type argument. The declaration-context path resolves it, the valid code is accepted, and the
  internal-name leak is gone. Recorded as an intended improvement, not silent drift.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `0dee71b98` in a throwaway `/tmp` worktree and at the working tree, **byte-identical on 40 / 40
  `project.yml` targets (ORACLE_DIFFS = 0)**. METHOD NOTE: the first sweep reported 40/40 "diffs"
  and then 7 — both artefacts, not behaviour. The first was a SCRUBBING bug (macOS reports the
  worktree as `/private/tmp/...`, so the `/tmp/...` prefix never matched); the second was
  ENVIRONMENTAL (7 targets reference a DLL by a path relative to the repo root that only exists
  once the Debug CLI has been built, which the baseline worktree had not). Building the baseline's
  Debug CLI and scrubbing both prefixes gives 0. Neither was ever a diagnostic difference.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, the established explicit PE/CLI normalizer
  touching ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory
  entries and the CodeView blobs they point at, and the `#GUID`/`#Pdb` heaps): **64 / 64 comparable
  assemblies BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (26 from the
  `project.yml` targets, 38 single-file examples, SINGLE_LOG_DIFFS = 0), with the same 7
  `tests/native/*` targets that do not build standalone failing identically at baseline and after
  (`SKIPPED_TARGET_DIFFS = 0`).
  .nl GOTCHAS CONFIRMED/ADDED: **`newtype` is RESERVED and cannot be a local name** (`newtype := …`
  makes the columnar front end decline the WHOLE test at `parse.test`, reported at the test's own
  line — the same shape as slice 1's `type` finding); **`==` between two DIFFERENTLY-TYPED TypeInfo
  expressions declines at `emit.statement.block-child`** (compare through a common static type — bind
  the operand with `as TypeInfo`); and **`.ToString()` on a `TypeInfo`-typed value declines** — go
  through the concrete type (`as ClassTypeInfo` then `.Name`) or the established `as object` idiom.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m15s —
  exactly the slice-1/2/3 baseline, zero drift), and separately **3,193 / 3,193 with the branch
  probe armed**, which is where `b2=0` comes from; BootstrapServices contracts
  **1,581 → 1,585** via the canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c
  Release -p:NSharpExcludeTests=false` (the 3 ExternalAssemblyScan Debug-layout tests did not trip);
  ownership audit **17/18 before the repin → 18 / 18 after**; `./scripts/dev.sh --since` PASS — it
  correctly took the FULL unit-suite fail-safe (three unmapped `.nl` paths), **3,193 / 3,193**; the
  oracle, differential and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s4.py` (slice 2/3's script, unchanged apart from its
  header) — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs`
  currentLines 22,622 → **22,608**, currentNonBlankLines 19,862 → **19,848**, fingerprint
  `text-v1:289fe435a271355f` → `text-v1:4cb7a19e315c5877` (epoch 23,451 / 20,537 PRESERVED and
  comfortably clear); `reviewedHeadFingerprint head-v1:d18683df9c788b71` →
  `head-v1:191f5810e69ee49c`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` untouched and RE-VALIDATED by recomputation after the
  write; the script self-checks by reproducing all three composite fingerprints over the 381 rows
  before changing anything. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND
  after, and the `git diff` is exactly 2 changed lines.** The `.nl` edits need no row —
  `OwnershipPolicy.Classify` ignores `.nl`.
  DOCS: `memory/components/analyzer.md` gains an "Alias identity and alias resolution" section
  stating the registration rule (instance-only, and WHY `RegisterCanonicalType`/`TryGetCanonicalType`
  must NOT be reused for aliases), the owner's exact contract, and the one behaviour that improves;
  the declaration-context paragraph now names declared-alias identity and alias resolution among its
  owned policies; the stale "the funnels are NOT movable while `ResolveType` is C#" paragraph is
  replaced with the accurate remaining-blocker statement.
  GATES (the FULL IDE bar — `Analyzer.cs` ships in the `NSharpLang.Compiler` assembly the language
  server builds against, and `NSharpLang.Compiler.BootstrapServices` gained public members, so the
  non-VS-Code path was NOT taken even though the behavioural proof is airtight):
  * **`./scripts/test-all.sh --commit` with NO `VSCODE_TESTS=skip`: `ALL TESTS PASSED`, 831s
    (13m51s)**, run FRESH in the script's own isolated copy
    (`/private/tmp/nsharp-test-all.f33030d5487b.puwFnq/repo`, created at run time) — not a cached
    whole-gate or per-step result. **ZERO `✗`/`FAILED` anywhere.** Unit tests 3,193 / 3,193 (3m14s),
    BootstrapServices contracts 1,585 / 1,585, every native N# project (including
    `tests/native/ownership-audit`), **VS Code Integration Tests 36 passing (41s)**, SDK pack +
    install, template pack/install/creation, the template-generated project via `nlc build`, all
    example projects, all single-file examples, `nlc check` on examples, and the IL verification
    gate — **all 67 N# assemblies pass ECMA-335 IL verification with no new errors vs baseline**.
  * `./scripts/dev.sh --since`: PASS, full unit-suite fail-safe, 3,193 / 3,193.
  * `./scripts/reload-vscode-extension.sh`: EXIT 0 — language server republished,
    `nsharp-0.6.0.vsix` (289 files, 3.98 MB) repackaged, `Extension 'nsharp-0.6.0.vsix' was
    successfully installed`, VS Code reopened. It WAS required: no LanguageServer source changed,
    but the `NSharpLang.Compiler` assembly the server ships did.
  * INTERACTIVE computer-use verification: **NOT PERFORMED — per the coordinator's explicit
    instruction for this slice, the grant was not re-requested** (it was DENIED four consecutive
    sessions: 016 N+3, 017 slices 1-3, and the coordinator now owns that record). The automated IDE
    evidence above stands, as does the fact that this slice's diagnostics are byte-identical
    corpus-wide. A human/coordinator eyes-on pass over the reloaded editor is the outstanding item.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, no new capability
  needed. The packaged SDK self-emits the new members.
  **NEXT SUB-SLICE — AND THE INVENTORY THAT MAKES IT DELETION-READY, RE-READ AFTER THIS SLICE
  RATHER THAN INHERITED: THE CLR-CONVERSION FUNNEL.** Slice 3 recorded
  `TryConvertTypeInfoToClrType` as blocked because "EVERY nested position re-enters the alias
  funnel", and the alias funnel reached the C# TypeReference engine. **That blocker no longer
  exists.** Reading the family in full at the post-slice tree, its ENTIRE state surface is now:
  `_declarationContext.ResolveDeclaredAlias` (N#), `_wellKnownTypes` — an `AnalyzerWellKnownTypes`
  since slice 3 (N#), `AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType` /
  `.KnownOpenGenericType` / `.BindingSurrogateOpenGenericType` (N#), and the `private static`
  name predicate `IsJsonTypeInfoGenericName` :9368. **No `_semanticModel`, no `_errors`, no scope
  stack, no `_mlc`, no `ResolveType` — anywhere in the closure.** The unit is six methods:
  `TryConvertTypeInfoToClrType` :10164 (**30 call sites**), `TryConstructRuntimeUnionType` :10201,
  `TryConvertNullableType` :10214, `TryConstructKnownGenericType` :10223,
  `TryConstructDelegateType` :10259, and `TryConvertTypeInfoToClrTypeForBinding` :9657
  (**11 call sites**) — they recurse into each other and nothing else, so they move as ONE owner
  that is constructed from the declaration context and the well-known-type bag. Take it next; after
  it, `IsAssignable` :19604 and its closure lose their last non-N# dependency and become the slice
  after. `ResolveType(TypeReference)` itself — the diagnostic-reporting, semantic-model-recording,
  MLC-probing engine — remains the arc's big remaining C# owner and is NOT a prerequisite for
  either.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `0dee71b98`): **017 SLICE 3 — THE N#
  WELL-KNOWN-TYPE OWNER** (`AnalyzerWellKnownTypes` + `AnalyzerWellKnownTypeFacts`), the RECUT of
  the recorded "N# type-resolution owner" target.
  **WHY A RECUT — THE FUNNEL INVENTORY REFUTED THE RECORDED PLAN, AND THE REFUTATION IS MEASURED,
  NOT ARGUED.** The recorded slice-3 target was "an N# owner that absorbs `ResolveTypeAlias` +
  `TryConvertTypeInfoToClrType`, built on the existing N# `AnalyzerDeclarationContext` facts, with
  the analyzer's declaration/resolution state passed IN rather than reached OUT for". The inventory
  below shows that plan rests on a premise that is FALSE at runtime, so the pair cannot be taken in
  this slice without either (a) moving the analyzer's entire type-REFERENCE resolution engine
  (`ResolveType` + `ResolveSimpleType` + `ResolveGenericType` + scope lookup + external-MLC probing
  + the `TypeNotFound`/`InvalidTypeArgument` diagnostics + semantic-model recording), or (b) handing
  the N# owner a C# callback — both of which the execution contract forbids in this slice.
  FUNNEL INVENTORY (read in full, not grepped):
  * `ResolveTypeAlias(TypeInfo)` :20326 is a 2-line trampoline onto
    `ResolveTypeAlias(TypeInfo, HashSet<AliasTypeInfo>)` :20329 (17 lines total). It is NOT a pure
    normalizer. Its `AliasTypeInfo` arm reads `_declarationContext.ContainsSourceType(alias)` and
    then takes ONE OF TWO branches: (1) `ResolveTypeForSourceOwner(alias.AliasedType, alias, null)`
    → `_declarationContext.TryResolveTypeForOwner(...)` (pure N#), or (2)
    `ResolveType(alias.AliasedType)` → the analyzer's full TypeReference engine :18383, which
    reaches `_semanticModel` (`RecordResolvedTypeReference`), `_errors` (`Error(...)` for
    `TypeNotFound` / `InvalidTypeArgument`), `_reportUnresolvedTypes`,
    `_reportedUnresolvedTypeRefs`, `_mlc`/`TryResolveExternalType`, and the scope stack
    (`LookupType`). Its `ObliviousTypeInfo` arm and its identity arm are pure.
  * MEASURED BRANCH REACHABILITY (throwaway instrumented Debug CLI, static counters dumped at
    process exit, deleted after): over `examples/17-issue-tracker`, `examples/09-linq-and-collections`,
    `examples/11-advanced-features`, `examples/16-task-cli`, `examples/10-interop`,
    `examples/05-unions` and a purpose-built four-alias fixture (`type Meters = int`,
    `type Names = List<string>`, `type Callback = func(int): string`, `type Chain = Meters`):
    **branch (1) fires 0 times; branch (2) fires 36 times** on the alias fixture (aliasSeen=36,
    b1=0, b2=36, cycle=0) and 0/0 on every corpus project. The cause is structural, not corpus
    accident: `Analyzer.cs` :369 declares a type alias as `DeclareType(aliasDecl.Name, new
    AliasTypeInfo(aliasDecl.Type), …)` — a FRESH instance — while `_declarationContext`'s
    `filesByType` is keyed by TypeInfo REFERENCE identity over the instances IT built, so
    `ContainsSourceType` is false for every alias the analyzer's own scope hands back. **The live
    alias path is 100% the C# engine.** (Recorded so the next attempt does not re-derive it: the
    prerequisite for taking `ResolveTypeAlias` is either unifying alias-TypeInfo identity between
    `DeclareType` and the declaration context, or moving `ResolveType` itself.)
  * `TryConvertTypeInfoToClrType(TypeInfo)` :10183 (36 lines) opens with `ResolveTypeAlias(typeInfo)`
    and then RECURSES through itself for `ArrayTypeInfo.ElementType`, `ObliviousTypeInfo.InnerType`,
    `NullableTypeInfo.InnerType` (via `TryConvertNullableType`), `GenericTypeInfo.TypeArguments` (via
    `TryConstructKnownGenericType`), `FunctionTypeInfo.ParameterTypes`/`ReturnType` (via
    `TryConstructDelegateType`) and `AnonymousUnionTypeInfo.Arms` (via `TryConstructRuntimeUnionType`)
    — so EVERY nested position re-enters the alias funnel. It therefore inherits the blocker above in
    full; there is no "pass the resolved type in at the top" shape that preserves behaviour.
  * CALLER MAP (this working tree, `Analyzer.cs` only — a grep over `src/` + `tests/` + `editors/`
    finds no external caller of either): `ResolveTypeAlias(` occurs 148 times = 2 definitions +
    3 self-recursions + **143 call sites**; `TryConvertTypeInfoToClrType(` 39 = 1 definition +
    8 self-recursions + **30 call sites**; `TryConvertTypeInfoToClrTypeForBinding(` 15 =
    1 definition + 3 self-recursions + **11 call sites**.
    `IsAssignable` :19604 and every arm of its closure (`IsSubtypeOf`, `IsCollectionType`,
    `HasImplicitConversion`, `ImplementsDuckInterface`, `IsKnownGenericTypeAssignable`,
    `IsArrayToSpanAssignable`, `IsAspNetActionResultGenericAssignable`, `IsFunctionTypeAssignable`,
    `IsLambdaAssignableToDelegate`, `TryGetDelegateSignatureConversionScore`,
    `MayUseDelegateReferenceConversion`, `IsReferenceLikeForVariance`) either calls the funnels
    directly or recurses into `IsAssignable`, which does — CONFIRMING slice 2's finding that the
    pure surface there is exhausted.
  * STATE READS, by funnel: `ResolveTypeAlias` → `_declarationContext`, and (through `ResolveType`)
    `_semanticModel`, `_errors`, `_mlc`, the scope stack. `TryConvertTypeInfoToClrType` →
    `_wellKnownTypes` (its ONLY direct instance-state read) plus the alias funnel.
    **`_wellKnownTypes` is the one piece of that state that is separable today**, and it is exactly
    what the recorded plan named as the thing to hand the owner "mechanically at analyzer
    initialization". Moving it is therefore the largest terminal cut available and is a strict
    prerequisite for the eventual funnel move rather than a detour.
  TARGET (the recut, terminal, named C# deletions): move the well-known-type FACT BAG and the two
  well-known-type-driven TABLES out of `Analyzer.cs` (22,873) into N#:
  (A) `internal sealed class WellKnownTypes` :22705-22872 (168 lines) — the nested MLC-backed fact
      bag holding 16 required core types, `SystemType`, `Delegate`, 12 optional open generics, the
      `Action`/`Action1-4`/`Func1-5` delegate roots, `JsonTypeInfoOpen`, and the LAZY
      `RuntimeUnionOpen`/`RuntimeResultOpen` pair with its `EnsureRuntimeTypes` +
      `FileNotFoundException` guard → N# `AnalyzerWellKnownTypes`;
  (B) `TryGetKnownOpenGenericType(string, int)` :10309-10340 (32 lines) — the compiler-known
      name+arity → open CLR generic table (`List`/`IEnumerable`/`IQueryable`/`ICollection`/`IList`/
      `Dictionary`/`IDictionary`/`Task`/`ValueTask`/`Result`/`NSharpLang.Runtime.Result`/
      `JsonTypeInfo`/its full name/`Func`1-5/`Action`1-4) → N# `AnalyzerWellKnownTypeFacts`;
  (C) the INLINE open-generic table nested inside `TryConvertTypeInfoToClrTypeForBinding`
      :9679-9701 (23 lines) — the same policy in a DISJOINT, SMALLER vocabulary (no `Result`, no
      `JsonTypeInfo`, no qualified spellings) → a SECOND entry point on the same owner, kept
      deliberately separate the way slice 1 kept the two numeric vocabularies apart;
  (D) `TryConvertBuiltInTypeInfoToRuntimeClrType(TypeInfo)` :10220-10247 (28 lines) — the
      WKT-independent fallback used when `_wellKnownTypes` is null, which maps built-in
      `SimpleTypeInfo` names to RUNTIME `typeof(...)` types and recurses on itself WITHOUT alias
      resolution (verified by reading it) → N# `AnalyzerWellKnownTypeFacts`.
  WHY THESE FOUR: (A) is the `_wellKnownTypes` state itself; (B)(C)(D) are every piece of policy in
  `Analyzer.cs` that is a pure function of that state (or of nothing at all). Nothing else in the
  CLR-construction family qualifies — `TryConvertNullableType`, `TryConstructRuntimeUnionType`,
  `TryConstructKnownGenericType`, `TryConstructDelegateType`, `TryConvertTypeInfoToClrType` and
  `TryConvertTypeInfoToClrTypeForBinding` all recurse through the alias funnel and are recorded as
  the remainder.
  OWNER PLAN: two NEW files in `src/NSharpLang.Compiler.BootstrapServices/` —
  `AnalyzerWellKnownTypes.nl` (the fact bag; PascalCase public fields, one ctor taking the
  `MetadataLoadContext` and the core `Assembly`, plus the lazy runtime-type accessors as METHODS
  because the `.nl` surface has no block-bodied property) and `AnalyzerWellKnownTypeFacts.nl` (the
  three static tables). `MetadataLoadContext.get_CoreAssembly()` is NOT in the columnar external
  binding plan and adding it would be a kernel-side capability change (the two-stage bootstrap
  wall), so the core assembly is read at the single C# construction site and PASSED IN — a
  mechanical argument, not policy.
  BAR: full unit suite, BootstrapServices contracts, exhaustive throwaway reflection differential
  against the C# originals BEFORE deletion, `nlc check --json` oracle goldens over 40 project
  targets + purpose-built well-known-type-sensitive fixtures, corpus IL byte-exact sweep, ownership
  audit 18/18 after an in-place one-row ratchet repin that keeps the manifest at 391 lines,
  `dev.sh --since`, and the FULL VS Code-enabled gate + VSIX reload.
  **RESULT: LANDED IN FULL (no commit — mandate). `WellKnownTypes` no longer exists in
  `Analyzer.cs`; `AnalyzerWellKnownTypes` and `AnalyzerWellKnownTypeFacts` are the sole authority
  for the fact bag and its three tables, with no callback, fallback, shadow path or comparison
  route.**
  DELETIONS (exact, by pre-edit line range — 4 units, 271 deleted lines, **20 inserted, all of them
  mechanical routing**):
  * `22622-22794` the nested `internal sealed class WellKnownTypes` (173 lines incl. its XML doc
    and the blank separator) — the MLC fact bag, its two-probe `Resolve` local function, the
    required-type throws, the `System.Text.Json` / `System.Collections` / `System.Linq.Expressions` /
    `System.Threading.Tasks` probes, and the lazy `RuntimeUnionOpen`/`RuntimeResultOpen` pair with
    `EnsureRuntimeTypes`;
  * `10309-10340` `TryGetKnownOpenGenericType(string, int)` (32) — the compiler-known name+arity
    table, XML doc included;
  * `10220-10247` `TryConvertBuiltInTypeInfoToRuntimeClrType(TypeInfo)` (28) — the no-metadata
    runtime fallback;
  * `9674-9701` the INLINE binding-surrogate open-generic table inside
    `TryConvertTypeInfoToClrTypeForBinding` plus its now-dead `var wkt = _wellKnownTypes` alias (28
    collapsed to 4).
  ROUTING: **7 sites**, every one inside `Analyzer.cs` — a grep over `src/` + `tests/` + `editors/`
  confirms `WellKnownTypes` and the three methods had NO external caller, so the reroute is total:
  the field declaration `:176` (type change only), the construction site `:22072` (now
  `new AnalyzerWellKnownTypes(_mlc, _mlc.CoreAssembly ?? throw …)` — the ONE place the core assembly
  is read, since `get_CoreAssembly` is off the columnar binding surface and adding it would trip the
  bootstrap wall), the three `KnownOpenGenericType` consumers (`:10229` generic construction,
  `:18373` the arity-qualified external probe, `:18514` the unresolved-generic reporter), the
  `BuiltInRuntimeClrType` consumer `:10171`, and the `BindingSurrogateOpenGenericType` consumer
  `:9678`. Two `RuntimeUnionOpen` property reads became `GetRuntimeUnionOpen()` calls and two
  `wkt.RuntimeResultOpen` reads moved into the owner. `git diff` on `Analyzer.cs` is
  **+20 / −271 = net −251**; the file is **22,873 → 22,622** (non-blank 20,087 → 19,862).
  N# ADDED: `AnalyzerWellKnownTypes.nl` (225 lines, one class, 52 members — 39 public type fields,
  6 private state fields, the constructor, the two lazy accessors and four file-private helpers;
  comfortably under the per-class ceiling) + `AnalyzerWellKnownTypeFacts.nl` (212 lines, one class,
  5 members) + `AnalyzerWellKnownTypeFacts.tests.nl` (391 lines, **10 contracts**).
  THREE NON-MECHANICAL DECISIONS, recorded because they are the only ones in the slice:
  (1) **The core assembly is a constructor ARGUMENT, not a property read.**
  `MetadataLoadContext.get_CoreAssembly` is not in `ColumnarExternalBindingPlans`, and adding it is a
  compiler-capability change that would trip the two-stage bootstrap wall. Reading it at the single
  C# construction site and passing it in is exact (the `?? throw` and its message are preserved
  verbatim) and keeps the wall untouched — the same discipline slice 2 applied to `typeof(Delegate)`.
  (2) **The lazy runtime accessors become METHODS.** `RuntimeUnionOpen`/`RuntimeResultOpen` were
  block-bodied C# properties calling `EnsureRuntimeTypes()`; the `.nl` surface has expression-bodied
  properties only, so they are `GetRuntimeUnionOpen()` / `GetRuntimeResultOpen()`. The four call
  sites are rewritten mechanically and the laziness (first read decides, answer never changes) is
  pinned by contract.
  (3) **The two open-generic tables are NOT merged.** The inline binding-surrogate table is a strict
  SUBSET of `TryGetKnownOpenGenericType`'s — it lacks `Result`, `NSharpLang.Runtime.Result`,
  `JsonTypeInfo` and the full JsonTypeInfo name. Merging would silently widen the surrogate surface
  (a `Result<,>` reconstructed with `object` surrogates names a type the program never wrote), so
  they are two entry points on one owner, and the disjointness is pinned by explicit negative
  contracts — slice 1's two-numeric-vocabularies precedent.
  ASSERTION MIGRATION: all four units were `private`/nested, so no test named them — their behaviour
  was pinned only INDIRECTLY by end-to-end analyzer diagnostics (`AnalyzerTests.cs`,
  `AnalyzerMetadataLoadContextTests.cs`, the LSP diagnostics tests). Those are diagnostics tests
  whose SUBJECT is the analyzer, not the table, so they STAY and now execute against the N# owners —
  the slice-1/2 and 016 classification-(a) precedent. The DIRECT pinning is new and native:
  **10 contracts** covering every required core type resolved into the LOAD CONTEXT and proven NOT
  reference-equal to the compiler's own `typeof`, every optional open generic proven to be an open
  DEFINITION of the right arity, the split-core-library second probe (a fact bag handed an assembly
  that declares none of the core types still resolves all of them), lazy-accessor stability across
  repeated reads, the full known-generic table in both spellings of `Result`/`JsonTypeInfo`, its
  arity-exactness / case-sensitivity / unqualified-only discipline including degenerate arities
  (`0`, `-1`, `17`), the surrogate table's subset relation AND its four deliberate omissions, the
  built-in runtime table over all 16 names with `void` proven identical to the core-library instance,
  the array/nullable/oblivious descent (including the value-type-only nullable rule), and the
  "every other family answers null, and NO alias is resolved" negative set.
  PROOF — EXHAUSTIVE DIFFERENTIAL (throwaway xunit probe, built and run BEFORE the deletion, then
  deleted; the slice-1/2 precedent): it reflected into the C# originals on a REAL loaded analyzer
  (`new Analyzer(); LoadSystemAssemblies()`) and compared them against the N# owners cell by cell.
  **5/5 facts green, 692 comparison cells, 0 mismatches**: 61 fact-bag cells (all 39 type fields by
  REFERENCE identity plus a required-non-null check on the 18 mandatory ones, plus the two lazy
  accessors read twice each); 310 known-generic cells (31 names × 9 arities including `-1`, `0`,
  `6`, `17`, plus 31 null-facts guards); 202 surrogate cells (31 names × 5 arities probed THROUGH
  `TryConvertTypeInfoToClrTypeForBinding` with an N#-declared class as the type argument — the only
  way to reach an inline table — plus null-facts guards and 8 disjointness cells); and 119
  built-in-runtime cells over a grid of every simple name in four wrappers plus nested and
  cross-family shapes. The comparison is by VALUE OR THROWN EXCEPTION TYPE, which caught and pinned
  a real behaviour: the original throws `TypeLoadException` on `void[]`, and the owner reproduces it.
  PROOF — END-TO-END FUNNEL, BEFORE vs AFTER THE DELETION: the same probe recorded
  `TryConvertTypeInfoToClrType` and `TryConvertTypeInfoToClrTypeForBinding` over **146 TypeInfo
  shapes = 292 cells**, as assembly-qualified names, on the pre-deletion tree; re-running it on the
  post-deletion tree gives a **byte-identical 146-row transcript**. This is the strongest available
  check on the routed (not deleted) funnels.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `9249b4eb0` in a throwaway `/tmp` worktree and at the working tree, **byte-identical on 40 / 40
  `project.yml` targets (ORACLE_DIFFS = 0)** plus 5 purpose-built fixtures exercising exactly this
  family — every compiler-known generic at correct AND wrong arity, the `Func`/`Action` delegate
  roots across arities 0-4 with deliberate shape mismatches, `Task`/`ValueTask`/`Result`, nullable /
  array / nested-array shapes over every built-in, and assignability errors across the well-known
  surface — **37 diagnostics (16 × NL202 with `expectedType`/`actualType` naming the compiler-known
  generics, plus NL201 / NL207 / NL303 / NL905 / NL907 / NL004 / NL010), FIXTURE_DIFFS = 0**.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, the established explicit PE/CLI normalizer
  touching ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory
  entries and the CodeView blobs they point at, and the `#GUID`/`#Pdb` heaps): **64 / 64 comparable
  assemblies BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (26 from the
  `project.yml` targets, 38 single-file examples, SINGLE_LOG_DIFFS = 0). The same 7 `tests/native/*`
  targets that do not build standalone fail at baseline AND after with identical return codes and
  identical scrubbed output (`SKIPPED_TARGET_DIFFS = 0`).
  .nl GOTCHAS CONFIRMED/ADDED: **`MetadataLoadContext.CoreAssembly` is NOT bound** (no
  `get_CoreAssembly` in `ColumnarExternalBindingPlans`) — pass the assembly in rather than extending
  the plan, which is a kernel-side capability change. **`typeof(void)` and `typeof(Nullable<>)` do
  not resolve** either (`ColumnarTypeOfPlanner.TryResolveBuiltinType` carries the 14 primitives plus
  `IntPtr`/`UIntPtr`/`DateTime`/`Index`/`Range`, and `object` via the special-known list, but not
  `void` and no open generics) — resolved with the same
  `typeof(object).get_Assembly().GetType(...)` idiom slice 2 established. **`catch ex: T` typed
  catch clauses DO work in `.nl`** (`OwnershipAudit.nl` precedent), so `EnsureRuntimeTypes`'s
  `FileNotFoundException`-only guard is reproduced exactly rather than widened to a bare catch. And
  **`.Type` is a legal member name** (`AnalyzerSourceTypeSelection` precedent) even though `type` is
  reserved as a parameter name.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m13s —
  exactly the slice-1/2 baseline, zero drift); BootstrapServices contracts **1,581 / 1,581** via the
  canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false` (1,571 baseline + 10 new; the 3 ExternalAssemblyScan Debug-layout
  tests did not trip); ownership audit **18 / 18** after the repin; `./scripts/dev.sh --since` PASS —
  it correctly took the FULL unit-suite fail-safe, **3,193 / 3,193 in Debug**, 3m14s; the oracle,
  differential and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s3.py` (slice 2's script, unchanged apart from its
  header) — `current*` + fingerprints ONLY, ONE row: `src/NSharpLang.Compiler/Analyzer.cs`
  currentLines 22,873 → **22,622**, currentNonBlankLines 20,087 → **19,862**, fingerprint
  `text-v1:ba8c1dbd980168b8` → `text-v1:289fe435a271355f` (epoch 23,451 / 20,537 PRESERVED and
  comfortably clear); `reviewedHeadFingerprint head-v1:cff6e83081a53db1` →
  `head-v1:d18683df9c788b71`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` untouched and RE-VALIDATED by recomputation after the
  write; the script self-checks by reproducing all three composite fingerprints over the 381 rows
  before changing anything. **FORMAT DISCIPLINE HELD: `wc -l` on the manifest is 391 before AND
  after, and the `git diff` is exactly 2 changed lines** (the head fingerprint and the Analyzer.cs
  row). The three new `.nl` files need no row — `OwnershipPolicy.Classify` ignores `.nl`.
  DOCS: `memory/components/analyzer.md` gains both new owners as listed files with a precise
  statement of every moved rule (metadata-versus-runtime types, the required/optional split, the
  two-probe resolve, why the core assembly is passed in, why the lazy accessors are methods, why the
  two open-generic tables stay separate, and the no-alias-resolution difference in the runtime
  fallback), plus a new paragraph recording WHY `ResolveTypeAlias` and `TryConvertTypeInfoToClrType`
  remain in C# and what the prerequisite for taking them is; `memory/architecture.md`'s Analyzer
  entry names its five N# owners.
  015 NOTE (per the mandate — the emitter was NOT touched here): the N# well-known-type owner now
  EXISTS and is constructible from a `MetadataLoadContext` outside `Analyzer.cs`. When 015 resumes,
  blockers #2 and #5 (the C# preflight typing engine and interpolation parsed-hole resolution) can
  build on `AnalyzerWellKnownTypes` / `AnalyzerWellKnownTypeFacts` for their CLR-type facts instead
  of re-deriving them; the remaining gap for a full preflight port is the alias/TypeInfo→CLR funnel
  recorded above, not the well-known-type surface.
  GATES (the FULL IDE bar — `Analyzer.cs` lives in the `NSharpLang.Compiler` assembly the language
  server ships, and `NSharpLang.Compiler.BootstrapServices` gained two types, so the non-VS-Code path
  was NOT taken even though the behavioural proof is airtight):
  * **`./scripts/test-all.sh --commit` with NO `VSCODE_TESTS=skip`: `ALL TESTS PASSED`, 13m49s**, run
    FRESH in the script's own isolated copy (`/private/tmp/nsharp-test-all.787f03c80f35.k961Ts/repo`,
    created at run time) — not a cached whole-gate or per-step result. ZERO `✗`/`FAILED` anywhere.
    Step timings: compiler build 1m30s, format-contract gate, unit tests 4m33s, native N# tests
    2m19s, **VS Code Integration Tests 2m16s (36 passing)**, SDK pack+install 2m48s, template
    pack/install/creation, template-generated project via `nlc build`, all example projects, all
    single-file examples, `nlc check` on examples, and the IL verification gate — **all 67 N#
    assemblies pass ECMA-335 IL verification with no new errors vs baseline**.
  * `./scripts/dev.sh --since`: PASS, full unit-suite fail-safe, 3,193 / 3,193 in Debug, 3m14s.
  * `./scripts/reload-vscode-extension.sh`: EXIT 0 — language server republished,
    `nsharp-0.6.0.vsix` (289 files, 3.98 MB) repackaged, `Extension 'nsharp-0.6.0.vsix' was
    successfully installed`, VS Code reopened on `examples/01-hello-world`. It WAS required: no
    LanguageServer source changed, but the `NSharpLang.Compiler` assembly the server ships did.
  * INTERACTIVE computer-use verification: **NOT PERFORMED — the permission system DENIED the VS
    Code control grant again this session** (`request_access` → `user_denied`, the FOURTH
    consecutive session: 016 N+3, 017 slice 1, 017 slice 2, 017 slice 3). Recorded as a standing
    gap, not skipped by choice. The automated IDE evidence above (the VS Code integration-test step
    over a freshly installed VSIX) stands, as does the fact that this slice's diagnostics are proven
    byte-identical corpus-wide; a human/coordinator eyes-on pass over `examples/01-hello-world`, now
    open in the reloaded editor, is the outstanding item.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change, and the two capability
  gaps found (`get_CoreAssembly`, `typeof(void)`/`typeof(Nullable<>)`) were both routed around
  precisely to avoid tripping it. The packaged SDK self-emits both owners.
- Active sub-slice (017 arc, PRIOR TURN): **017 SLICE 2 — THE
  CALLABLE / DELEGATE-REFERENCE CLASSIFICATION FAMILY** (the sub-slice recorded at the end of
  slice 1). TARGET: move the eight remaining PURE, `private static`, zero-instance-state predicates
  in the assignability neighbourhood out of `Analyzer.cs` (22,938) into a NEW SIBLING N# owner
  `AnalyzerCallableReferenceFacts`, route every in-class call site, and DELETE the exact C# methods.
  Line numbers RE-VERIFIED against the working `Analyzer.cs` before editing (all eight matched the
  numbers slice 1 recorded, and each was read in full to confirm the brace-scan did not over-run a
  multi-line signature):
  (A) `IsCallableReferenceType(TypeInfo)` :6779 — "is this value a bare method reference?", the
      predicate behind `MethodGroupUsedAsValue` and the `IsAssignable` method-group rejection;
  (B) `IsMethodGroupReferenceType(TypeInfo)` :6783 — the three method-group TypeInfo shapes;
  (C) `HasSourceFunctionIdentity(FunctionTypeInfo)` :6788 — "is this a NAMED source function rather
      than a lambda?", the discriminator that decides method-group-vs-lambda everywhere;
  (D) `IsRuntimeDelegateType(Type)` :6834 — CLR delegate classification excluding the two abstract
      roots (`Delegate`, `MulticastDelegate`);
  (E) `IsSpanTypeName(string)` :19940 — the Span/ReadOnlySpan name gate gating array→span
      assignability;
  (F) `GetFunctionParameterModifier(FunctionTypeInfo, int)` :20028 — the safe modifier read;
  (G) `NormalizeDelegateParameterModifier(ParameterModifier)` :20036 — `params` erases to `None`
      for delegate-signature matching;
  (H) `TryCreateFunctionTypeInfoFromGenericDelegate(GenericTypeInfo, out FunctionTypeInfo)` :20196 —
      `Func<...>`/`Action<...>` reified into a `FunctionTypeInfo` signature.
  WHY THIS ONE: every one is `private static` with ZERO analyzer instance state — verified by reading
  each body, not by grep — and none touches `_declarationContext`, `ResolveType*`, `_errors`, or
  `_semanticModel`. They operate only over models N# ALREADY OWNS (`TypeInfo` and its subclasses in
  `TypeInfoModels.nl` / `ReflectionTypeInfoModels.nl`, `ParameterModifier` in `DeclarationEnums.nl`,
  `BuiltInTypes`) plus `System.Type` reflection, which is already driven from `.nl`. This is the rest
  of the leaf policy under `IsAssignable` :19604 that slice 1 did not take; after it, everything left
  in that neighbourhood is instance-bound and blocked on the recorded type-resolution owner
  (`ResolveTypeAlias` + `TryConvertTypeInfoToClrType`).
  OWNER PLAN (class layout planned from the start): a NEW file
  `src/NSharpLang.Compiler.BootstrapServices/AnalyzerCallableReferenceFacts.nl`, class
  `AnalyzerCallableReferenceFacts` in namespace `NSharpLang.Compiler`, **7 members** — (A)-(D) and
  (F)-(H). (E) `IsSpanTypeName` is NOT a callable/delegate fact: it is a CONVERSION gate (its only
  consumer is `IsArrayToSpanAssignable`), so it is filed with slice 1's family in
  `AnalyzerConversionFacts` (9 → 10 members, still far under the per-class ceiling) rather than
  misfiled into the new class. Recorded as the one class-layout deviation from the slice-1 note, with
  its reason.
  SCOPE NOTE (recorded before editing so it is not mistaken for an oversight): a grep of the eight
  names across `src/` + `tests/` + `editors/` finds exactly ONE other C# definition — a private
  static `GetFunctionParameterModifier(FunctionTypeInfo, int)` in
  `src/NSharpLang.Compiler/CodeIntelligence/CompletionEngine.cs` :751, a completion-LABEL helper with
  an extra `index < 0` guard. It is a different subsystem with a different consumer, and folding it in
  would move a SECOND ratchet row outside this slice's mandate, so it is NOT taken here and is named
  as a follow-on below.
  BAR: full unit suite, BootstrapServices contracts, corpus IL byte-exact sweep, `nlc check --json`
  oracle goldens over method-group / delegate-conversion fixtures, ownership audit 18/18 after a
  one-row ratchet repin, `dev.sh --since`, and — because `Analyzer.cs` ships in the assembly the
  language server builds against — the full IDE bar.
  **RESULT: LANDED IN FULL (no commit — mandate). All eight predicates are DELETED from
  `Analyzer.cs`; `AnalyzerCallableReferenceFacts` (seven of them) and `AnalyzerConversionFacts`
  (the span-name gate) are the sole authority, with no callback, fallback, shadow path or
  comparison route.**
  DELETIONS (exact, by pre-edit line range — 8 methods, 66 lines, **ZERO C# added**):
  * `6779-6790` `IsCallableReferenceType` + `IsMethodGroupReferenceType` + `HasSourceFunctionIdentity`
    (12 lines — three expression-bodied predicates and their separators);
  * `6834-6838` `IsRuntimeDelegateType(Type)` (5);
  * `19940-19942` `IsSpanTypeName(string)` (3);
  * `20028-20040` `GetFunctionParameterModifier` + `NormalizeDelegateParameterModifier` (13);
  * `20196-20228` `TryCreateFunctionTypeInfoFromGenericDelegate` (33).
  ROUTING: **21 call sites**, every one inside `Analyzer.cs` — 5 `IsCallableReferenceType`
  (:6776 unbound-reference gate, :6891/:6904 the argument-diagnostic phrasing pair, :19657
  `IsAssignable`'s target rejection, :22523 the callable-symbol completion candidates), 1
  `IsMethodGroupReferenceType` (:19652), 6 `HasSourceFunctionIdentity` (:6689 synthetic-SoA-operation
  guard, :11633, :13329 the delegate match-score gate, :17008, :19641 `IsAssignable`'s source arm,
  :20146), 3 `IsRuntimeDelegateType` (:6827, :14177 — the two delegate-like-expected-type switches —
  and :19646), 1 `IsSpanTypeName` (:19929), 2 `GetFunctionParameterModifier` + 2
  `NormalizeDelegateParameterModifier` (:20005-:20007), 1
  `TryCreateFunctionTypeInfoFromGenericDelegate` (:20147). A grep over `src/` + `tests/` + `editors/`
  confirms the eight predicates had NO external caller, so the reroute is total. `git diff` on
  `Analyzer.cs` is **+21 / −86 = net −65**; the file is **22,938 → 22,873** (non-blank
  20,139 → 20,087).
  N# ADDED: `AnalyzerCallableReferenceFacts.nl` (148 lines, one class with **7 members**, no helpers
  needed) + `AnalyzerCallableReferenceFacts.tests.nl` (338 lines, 9 contracts), plus **+9 lines** to
  `AnalyzerConversionFacts.nl` (the span-name gate, class 9 → 10 members) and **+23 lines** to its
  contracts (1 contract).
  TWO NON-MECHANICAL DECISIONS, recorded because they are the only ones in the slice:
  (1) **`IsSpanTypeName` is filed with the CONVERSION family, not the callable family.** Its only
  consumer is `IsArrayToSpanAssignable` — it gates an implicit conversion — so putting it in a class
  named for callable/delegate references would have misfiled it. This is the recorded deviation from
  the slice-1 note's "do NOT grow `AnalyzerConversionFacts`", which was about not dumping the
  CALLABLE family there; a 2-line conversion table is exactly what that class is for. (Note the
  analyzer's spelling set is a STRICT SUPERSET of `LoopSequenceTypeFacts`'s same-named file-private
  helper, which matches only the unqualified pair — they were NOT merged, and the difference is
  pinned by contract.)
  (2) **`TryCreateFunctionTypeInfoFromGenericDelegate`'s `out` parameter becomes a nullable return.**
  The owner is `CreateFunctionTypeInfoFromGenericDelegate(GenericTypeInfo): FunctionTypeInfo?`, and
  the single call site becomes `… is { } delegateSignature`, which preserves the `&&` short-circuit
  exactly. The C# assigned a discarded placeholder signature on the false path; no caller read it.
  ASSERTION MIGRATION: all eight were `private`, so no test named them — their behaviour was pinned
  only INDIRECTLY by end-to-end analyzer diagnostics (`AnalyzerTests.cs`'s method-group and delegate
  regions, `CompletionEngineTests`, the LSP diagnostics tests). Those are diagnostics tests whose
  SUBJECT is the analyzer, not the predicate, so they STAY and now execute against the N# owner — the
  slice-1 / 016 classification-(a) precedent. The DIRECT pinning is new and native: **10 contracts**
  covering the three method-group shapes (incl. the empty-group case), the source-name/whitespace/
  empty/absent identity grid, the callable union, the delegate-root exclusions against six concrete
  delegates and six non-delegates, the total modifier read over absent/empty/short/past-the-end
  indices, the params-erases-but-ref/out-do-not rule, `Func`/`Action` reification across arities 0-4
  with type-argument IDENTITY carried through, and the case-sensitive simple-name match that rejects
  `System.Func` / `func` / `Predicate`.
  PROOF — EXHAUSTIVE DIFFERENTIAL (throwaway probe, built and run BEFORE the deletion, then deleted;
  the slice-1 precedent): a temporary xunit harness reflected into the eight C# privates and compared
  them against the N# owners cell by cell. **6/6 facts green, 271 cells, 0 mismatches**:
  50 `TypeInfo` values × 2 predicates = 100 cells for the callable/method-group pair (every TypeInfo
  subclass incl. all three method-group shapes, an EMPTY reflection group, function types across
  null/empty/whitespace/qualified source names, `Alias`/`Oblivious`/`ByRef`/`Newtype`/`Tuple`/
  `AnonymousUnion` and a bare `TypeInfo`); 8 source names × 3 synthetic names = 24 cells for source
  identity; **42 CLR types** for the delegate-root classification — 33 runtime (both abstract roots,
  6 concrete delegates incl. an open generic delegate definition, `ValueType`/`Enum`/`Array`, a
  `Delegate[]`, `void`) **plus 9 loaded into a real `MetadataLoadContext`**, which pins the
  load-context asymmetry the reimplementation depends on; 19 span-name strings; 46 modifier cells
  (4 enum values × normalize, 7 modifier-list shapes × 6 indices); and 8 generic names × 5 arities =
  40 signature-reification cells compared by parameter-type REFERENCE identity, modifier list and
  return type.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `dfec28f2a` in a throwaway `/tmp` worktree and at the working tree, **byte-identical on 40 / 40
  `project.yml` targets (ORACLE_DIFFS = 0)** plus 4 purpose-built fixtures exercising exactly this
  family — bare method references in four positions (4 × **NL411 MethodGroupUsedAsValue**, byte
  identical including message, explanation, suggestion, hint, span and docs URL), good-vs-bad
  method-group and lambda delegate conversions (6 × NL202), array-to-span vs array-to-memory
  (3 × NL202), and a `params`/`ref`/`out` method-group-to-delegate set — **15 diagnostics,
  FIXTURE_DIFFS = 0**.
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs, slice 1's explicit PE/CLI normalizer touching
  ONLY the COFF `TimeDateStamp`, the optional-header `CheckSum`, the Debug Directory entries and the
  CodeView blobs they point at, and the `#GUID`/`#Pdb` heaps): **64 / 64 comparable assemblies
  BYTE-IDENTICAL — PRODUCT_IL_DIFFS = 0 and SINGLE_IL_DIFFS = 0** (26 from the `project.yml` targets,
  38 single-file examples, SINGLE_LOG_DIFFS = 0). The same 7 `tests/native/*` targets that do not
  build standalone fail at baseline AND after with identical return codes and identical scrubbed
  output (`SKIPPED_TARGET_DIFFS = 0`).
  .nl GOTCHA FOUND (new, add to the cumulative list): **`typeof(Delegate)` and
  `typeof(MulticastDelegate)` do NOT resolve** — the columnar front end's `typeof` surface
  (`ColumnarTypeOfPlanner`) carries a hardcoded well-known-name list that does not include them, so
  `typeof(Delegate)` declines at `emit.local.initializer` (and, inlined into an `if`, at
  `emit.if.condition`, which points at the CONDITION rather than the `typeof`). Extending that list
  is a KERNEL-side capability change and would trip the two-stage bootstrap wall, so the owner uses
  the established `typeof(object).get_Assembly().GetType("System.Delegate")` idiom
  (`ColumnarRuntimeInstanceMemberResolver`'s `RequiredAssemblyType` pattern). It yields the identical
  runtime `Type` instances, so the runtime-versus-MLC asymmetry is preserved exactly — proven by the
  9 MetadataLoadContext cells in the differential.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m16s —
  exactly the slice-1 baseline, zero drift); BootstrapServices contracts **1,571 / 1,571** via the
  canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false` (1,561 baseline + 10 new; the 3 ExternalAssemblyScan Debug-layout tests
  did not trip); ownership audit **18 / 18** after the repin; `./scripts/dev.sh --since` PASS — it
  correctly took the FULL unit-suite fail-safe (`Analyzer.cs` is a shared compiler file, the `.nl`
  paths unmapped), **3,193 / 3,193 in Debug**; the oracle and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s2.py` — `current*` + fingerprints ONLY, ONE row:
  `src/NSharpLang.Compiler/Analyzer.cs` currentLines 22,938 → **22,873**, currentNonBlankLines
  20,139 → **20,087**, fingerprint `text-v1:d4234d5d68f1a2b4` → `text-v1:ba8c1dbd980168b8` (epoch
  23,451 / 20,537 PRESERVED and comfortably clear); `reviewedHeadFingerprint
  head-v1:3efdebb585fd02c4` → `head-v1:cff6e83081a53db1`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` untouched and RE-VALIDATED by recomputation after the
  write; the script reimplements `OwnershipFacts` exactly and self-checks by reproducing all three
  composite fingerprints over the 381 rows before changing anything.
  **FORMAT DISCIPLINE (the slice-1 defect, fixed): the repin script edits the affected LINES in place
  and NEVER re-serializes the document**, so the manifest keeps its COMPACT shape — 2-space top-level
  keys, one compact JSON row per line. It asserts `391` lines before AND after; the resulting
  `git diff` on the manifest is exactly **2 changed lines** (the head fingerprint and the Analyzer.cs
  row). `wc -l tests/native/ownership-audit/non-nsharp-growth-ratchet.v1.json` = **391**.
  DOCS: `memory/components/analyzer.md` gains `AnalyzerCallableReferenceFacts.nl` as a listed owner
  with a precise statement of each moved rule (including why the delegate roots are read out of the
  core library) and a "do not reintroduce in C#, do not grow this class" note; the
  `AnalyzerConversionFacts` section gains `IsSpanTypeName` with the LoopSequenceTypeFacts distinction;
  `memory/architecture.md`'s Analyzer entry names its four N# owners.
  GATES (the FULL IDE bar — `Analyzer.cs` lives in the `NSharpLang.Compiler` assembly the language
  server ships, and `NSharpLang.Compiler.BootstrapServices` gained a type, so the non-VS-Code path was
  NOT taken even though the behavioural proof is airtight):
  * **`./scripts/test-all.sh --commit` with NO `VSCODE_TESTS=skip`: `ALL TESTS PASSED`, 13m44s**, run
    FRESH in the script's own isolated copy (`/private/tmp/nsharp-test-all.b3cd30a806d8.CgpS8t/repo`,
    created at run time) — not a cached whole-gate or per-step result. ZERO `✗`/`FAILED` anywhere.
    Step timings: compiler build 1m29s, format-contract gate, unit tests 4m34s, native N# tests
    2m16s, **VS Code Integration Tests 2m16s**, SDK pack+install 2m47s, template pack/install/
    creation, template-generated project via `nlc build`, all example projects, all single-file
    examples, `nlc check` on examples, and the IL verification gate — **all 67 N# assemblies pass
    ECMA-335 IL verification with no new errors vs baseline**.
  * `./scripts/dev.sh --since`: PASS, full unit-suite fail-safe, 3,193 / 3,193 in Debug.
  * `./scripts/reload-vscode-extension.sh`: EXIT 0 — language server republished, `nsharp-0.6.0.vsix`
    repackaged, `Extension 'nsharp-0.6.0.vsix' was successfully installed`, VS Code reopened on
    `examples/01-hello-world`. It WAS required: no LanguageServer source changed, but the
    `NSharpLang.Compiler` assembly the server ships did.
  * INTERACTIVE computer-use verification: **NOT PERFORMED — the permission system DENIED the VS Code
    control grant again this session** (`request_access` → `user_denied`, the THIRD consecutive
    session: 016 N+3, 017 slice 1, 017 slice 2). Recorded as a standing gap, not skipped by choice.
    The automated IDE evidence above (the VS Code integration-test step over a freshly installed
    VSIX) stands, as does the fact that this slice's diagnostics are proven byte-identical
    corpus-wide; a human/coordinator eyes-on pass over `examples/01-hello-world`, now open in the
    reloaded editor, is the outstanding item.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change; the packaged SDK
  self-emits both owners. The `typeof(Delegate)` decline above was resolved WITHOUT touching the
  planner, precisely to avoid the wall.
- Active sub-slice (017 arc, PRIOR TURN, LANDED at `dfec28f2a`): **017 SLICE 1 — THE
  CONVERSION/ASSIGNABILITY CLASSIFICATION TABLES** (the task file's first-listed family,
  "conversions/assignability"). TARGET: move the four PURE, STATIC, policy-bearing conversion
  predicates out of `Analyzer.cs` into a new N# owner `AnalyzerConversionFacts`, route all 25
  in-class call sites (this pre-edit count was one short — the RESULT below records the exact 26),
  and DELETE the exact C# methods:
  (A) `IsImplicitNumericConversion(TypeInfo, TypeInfo)` :20413 — the CLR implicit-numeric-conversion
      table keyed by N# simple type names (`byte`/`sbyte`/…/`float`);
  (B) `IsImplicitNumericConversion(Type, Type)` :13813 + `GetNumericTypeFullName(Type)` :13837 — the
      SAME table keyed by CLR `System.*` FullName after `Nullable.GetUnderlyingType`;
  (C) `IsReferenceType(TypeInfo)` :20507 — the reference-vs-value classification that decides
      "null is assignable to T", delegate-variance eligibility, and pattern possibility;
  (D) `IsReflectionAssignableFrom(Type, Type)` :20373 + `GetInterfacesSafe` :20399 +
      `GetBaseTypeSafe` :20404 — the MLC-safe assignability walk (identity → IsAssignableFrom →
      interface list → base chain).
  WHY THIS ONE: all four are `private static` with ZERO analyzer instance state, they operate over
  models N# ALREADY OWNS (`TypeInfo` + subclasses live in `TypeInfoModels.nl`; `System.Type`
  reflection is already driven from `.nl` in `TypeInfoIdentityFacts.nl`), and every caller is
  inside `Analyzer.cs`, so the routing is total and no callback survives. They are the leaf
  policy of `IsAssignable` :19634 — the arc's eventual target — so this slice is the bottom of
  that dependency tree, not a detour.
  OWNER PLAN (member ceiling planned from the start, per the 016 lesson): a NEW file
  `src/NSharpLang.Compiler.BootstrapServices/AnalyzerConversionFacts.nl`, class
  `AnalyzerConversionFacts` in namespace `NSharpLang.Compiler`, ~6 members. The rest of the
  assignability closure lands in SIBLING classes/files in later slices
  (`IsAssignable`'s composite walk, `IsSubtypeOf`, `IsCollectionType`, `HasImplicitConversion`,
  the delegate/lambda conversion scorers) — NOT by growing this class.
  BAR: full unit suite, BootstrapServices contracts, corpus IL byte-exact sweep, semantic-diagnostic
  oracle proofs (`nlc check --json` goldens over conversion-error fixtures), ownership audit 18/18
  after the ratchet repin, `dev.sh --since`. `Analyzer.cs` ships in the assembly the language server
  builds against, but this slice changes NO diagnostic behavior (pure relocation of pure predicates)
  — the corpus IL sweep + oracle goldens are the behavioral proof.
  **RESULT: LANDED IN FULL (no commit — mandate). All four predicates are DELETED from `Analyzer.cs`;
  `AnalyzerConversionFacts` is the sole authority for every one of them, with no callback, fallback,
  shadow path, or comparison route.**
  DELETIONS (exact, by pre-edit line range — 7 methods, 122 lines, **ZERO C# added**):
  * `13813-13836` `IsImplicitNumericConversion(Type, Type)` — the CLR-FullName-keyed widening table;
  * `13837-13842` `GetNumericTypeFullName(Type)` — its `Nullable.GetUnderlyingType` normalizer;
  * `20373-20408` `IsReflectionAssignableFrom(Type, Type)` + `GetInterfacesSafe` + `GetBaseTypeSafe`
    (the latter two were bodyless pass-throughs — the vestige of a removed try/catch — and are
    INLINED into the owner's walk rather than reproduced as members);
  * `20409-20433` `IsImplicitNumericConversion(TypeInfo, TypeInfo)` — the source-name-keyed table;
  * `20503-20533` `IsReferenceType(TypeInfo)` — the reference-vs-value classification.
  ROUTING: **26 call sites**, every one inside `Analyzer.cs` — a grep over `src/` + `tests/` +
  `editors/` confirms the four predicates had NO external caller, so the reroute is total — plus one
  `<see cref>` doc reference repointed at the owner. `git diff` on `Analyzer.cs` is **+27 / −149 =
  net −122**; the file is **23,060 → 22,938** (non-blank 20,246 → 20,139).
  N# ADDED: `AnalyzerConversionFacts.nl` (254 lines — one `NumericConversionKind` enum plus one class
  with **9 members**: 4 public entry points and 5 file-private helpers, far under the per-class
  ceiling) and `AnalyzerConversionFacts.tests.nl` (343 lines, 7 contracts).
  ONE DELIBERATE CONSOLIDATION, recorded because it is the only non-mechanical decision in the slice:
  the two C# numeric tables were the SAME policy written twice in two vocabularies. The owner states
  the widening relation ONCE over a `NumericConversionKind` and reaches it through two DISJOINT name
  maps (`SourceNumericCode` for `byte`/`sbyte`/…, `ClrNumericCode` for `System.Byte`/…). Neither map
  accepts the other's spellings, so cross-vocabulary behaviour is preserved exactly — pinned by
  explicit negative contracts (`SimpleTypeInfo("System.Int32")` → `SimpleTypeInfo("long")` is NOT a
  conversion, and vice versa) and by the exhaustive differential below.
  ASSERTION MIGRATION: the four predicates were `private`, so no test named them. Their behaviour was
  pinned only INDIRECTLY, by end-to-end analyzer diagnostics — chiefly `AnalyzerTests.cs`'s
  "Numeric Widening — Comprehensive Assignability Matrix" region (:8112-:8765, **53 facts /
  53 assertions**). Those are diagnostics tests whose SUBJECT is the analyzer, not the table, so they
  STAY and now execute against the N# owner — the 016 classification-(a) precedent: rerouting is a
  strictly stronger check than hand-mapping a test to a contract. The DIRECT pinning of the tables is
  new and native: 7 `.tests.nl` contracts that walk the full 12×12 widening grid in BOTH vocabularies,
  every `TypeInfo` family for the reference/value split, and the identity / `Nullable` read-through /
  interface-list / base-chain arms of the reflection walk.
  PROOF — EXHAUSTIVE DIFFERENTIAL (throwaway probe, run BEFORE the deletion, then deleted; the 016
  triangulation-probe precedent): a temporary xunit harness reflected into the four C# privates and
  compared them against the N# owner cell by cell. **4/4 green, 2,400 cells, 0 mismatches**:
  the source-name numeric grid 23×23 = 529 cells (the 12 numerics plus `bool`/`void`/`null`/`never`/
  `string`/`object`/`Int32`/`System.Int32`/`System.Int64`/`Widget`/empty), the CLR numeric grid
  30×30 = 900 cells (the 12 numerics plus nullable, reference, interface, array, `Enum`, `ValueType`),
  the reflection-assignability grid 30×30 = 900 cells, and the reference/value classification over
  71 distinct `TypeInfo` values covering every subclass incl. `Alias`/`Oblivious`/`Tuple`.
  PROOF — SEMANTIC-DIAGNOSTIC ORACLE: `nlc check --json`, fresh Release CLIs built at baseline
  `9f2dd9572` in a throwaway `/tmp` worktree and at the working tree, **byte-identical on 40 / 40
  `project.yml` targets (ORACLE_DIFFS = 0)** plus 3 purpose-built conversion-error fixtures
  (widening/narrowing chains, `null` to every reference and value family, reflection up/down-casts —
  14 NL202 diagnostics, byte-identical including message, hint, span, `expectedType`/`actualType`).
  PROOF — CORPUS IL BYTE-EXACT SWEEP (same two CLIs): **64 / 64 comparable assemblies BYTE-IDENTICAL,
  PRODUCT_IL_DIFFS = 0** — 26 from the `project.yml` targets and 38 single-file examples — after
  normalizing ONLY the run-varying image fields (COFF `TimeDateStamp`, optional-header `CheckSum`,
  the Debug Directory entries and the CodeView blobs they point at, and the `#GUID`/`#Pdb` metadata
  heaps) via an explicit PE/CLI parser. The 7 `tests/native/*` targets that do not build standalone
  fail at baseline AND after with an **identical return code and identical scrubbed output**
  (`SKIPPED_TARGET_DIFFS = 0`), so they are accounted for rather than silently dropped.
  METHOD NOTE (recorded so it is not repeated): the first sweep attempt derived the "run-varying"
  offsets EMPIRICALLY, by building the baseline twice. That is UNSOUND — two builds in the same
  second share a `TimeDateStamp`, and individual MVID bytes collide 1-in-256 — and it produced 10
  false IL DIFFs, every one a single byte at a timestamp or GUID offset. The precise PE normalizer
  above replaced it and returned 0.
  .nl GOTCHA FOUND (new, add to the cumulative list): **`type` is RESERVED and cannot be a parameter
  or local name.** `func F(type: TypeInfo)` makes the columnar front end decline the WHOLE enclosing
  class with `NL103 … parse.struct`, reported at the CLASS-NAME span — not at the parameter — so the
  message points nowhere near the offending token. Renamed to `candidate`.
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m15s —
  exactly the 016 baseline, zero drift); BootstrapServices contracts **1,561 / 1,561** via the
  canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release
  -p:NSharpExcludeTests=false` (1,554 baseline + 7 new; the 3 ExternalAssemblyScan Debug-layout tests
  did not trip); ownership audit **18 / 18** after the repin; the oracle and IL sweeps above.
  RATCHET REPIN via `scratchpad/repin_017_s1.py` — `current*` + fingerprints ONLY, one row:
  `src/NSharpLang.Compiler/Analyzer.cs` currentLines 23,060 → **22,938**, currentNonBlankLines
  20,246 → **20,139**, fingerprint `text-v1:8fb5356afa080c19` → `text-v1:d4234d5d68f1a2b4` (epoch
  23,451 / 20,537 PRESERVED and comfortably clear); `reviewedHeadFingerprint
  head-v1:d889362e0ea7e2a4` → `head-v1:3efdebb585fd02c4`, mirrored into `OwnershipAudit.nl`'s
  `OwnershipPolicy.ReviewedHeadFingerprint`. Every `epoch*` value, `epochPathFingerprint`,
  `epochFactFingerprint` and `epochFileCount` untouched and RE-VALIDATED by recomputation after the
  write; the script reimplements `OwnershipFacts` exactly and self-checks by reproducing all three
  composite fingerprints over the 381 pre-edit rows before changing anything. The two new `.nl` files
  need no row — `OwnershipPolicy.Classify` ignores `.nl`.
  GATES (the FULL IDE bar — `Analyzer.cs` lives in the `NSharpLang.Compiler` assembly the language
  server ships, and `NSharpLang.Compiler.BootstrapServices` gained a type, so the non-VS-Code path
  was NOT taken even though the behavioural proof is airtight):
  * `./scripts/dev.sh --since`: PASS. It correctly took the FULL unit-suite fail-safe — it names
    `Analyzer.cs` a shared compiler file and the two `.nl` paths unmapped — 3,193 / 3,193 in Debug.
  * **`./scripts/test-all.sh --commit` with NO `VSCODE_TESTS=skip`: `ALL TESTS PASSED`, 13m47s**,
    run FRESH in the script's own isolated copy (`/private/tmp/nsharp-test-all.9f6779f2f874.NW7t3P/repo`,
    created at run time) — not a cached whole-gate or per-step result. Zero `✗`/`FAILED` anywhere in
    the log. Step timings: compiler build 1m30s, format-contract gate, unit tests 4m36s, native N#
    tests 2m17s, **VS Code Integration Tests 2m15s**, SDK pack+install 2m46s, template pack/install/
    creation, template-generated project via `nlc build`, all example projects, all single-file
    examples, `nlc check` on examples, and the IL verification gate — **all 67 N# assemblies pass
    ECMA-335 IL verification with no new errors vs baseline**.
  * `./scripts/reload-vscode-extension.sh`: EXIT 0 — language server republished, `nsharp-0.6.0.vsix`
    (289 files, 3.98 MB) repackaged, `Extension 'nsharp-0.6.0.vsix' was successfully installed`,
    VS Code reopened on `examples/01-hello-world`. It WAS required: no LanguageServer source changed,
    but the `NSharpLang.Compiler` assembly the server ships did.
  * INTERACTIVE computer-use verification: **NOT PERFORMED — the permission system DENIED the VS Code
    control grant again this session** (`request_access` → `user_denied`, exactly as in 016 N+3).
    Recorded as a gap, not skipped by choice. The automated IDE evidence above (the VS Code
    integration-test step over a freshly installed VSIX) stands, as does the fact that this slice's
    diagnostics are proven byte-identical corpus-wide; a human/coordinator eyes-on pass over
    `examples/01-hello-world`, now open in the reloaded editor, is the outstanding item.
  DOCS: `memory/components/analyzer.md` gains `AnalyzerConversionFacts.nl` as a listed owner with a
  precise statement of each moved rule and a "do not reintroduce in C#, do not grow this class"
  note; `memory/architecture.md`'s Analyzer entry names its three N# owners. Two STALE 016 leftovers
  were corrected while there: both `memory/architecture.md` and `memory/components/error-reporting.md`
  still pointed at `src/NSharpLang.Compiler/ErrorReporting.cs`, a file task 016 DELETED — they now
  name the N# owners (`CompilerError.nl`, `ErrorCode.nl`, `ErrorSeverity.nl`, `ErrorMessageBuilder.nl`,
  `ErrorSuggestions.nl`, `ErrorSuggestionHelpers.nl`).
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change; the packaged SDK
  self-emits the new owner.
- Task 015 status: UNCHECKED, iteration PAUSED at `e0f987bba` — the movable decision surface is
  EXHAUSTED per the 015 completion roadmap (recorded below): every remaining emitter policy is
  BLOCKED-WITH-RECORD on four named future owners (plan-row lambda-body emitter, N# preflight/
  typing-owner port, async-func lowering, planner operand unlocks) or MECHANICAL. Resume 015 only
  when one of those owners lands. Emitter at 21,433/20,375 vs epoch 21,723/20,646 (−290 lines this
  task across 8 landed slices + 2 proven refutations + 1 restored regression).
- 016 note: BOTH production-touching slices (N+2 cutover, N+3 deletion) have LANDED and were run on the IDE
  bar (VS Code-enabled gate + extension reinstall), as recorded. `Parser.cs` no longer exists: it is neither
  the LSP parser, nor any production consumer's parser, nor any test's parser. The
  kernel-capability arc stages (Stages 1-8) were NOT IDE-affecting: they added self-contained N# owner files
  + native contracts with NO production/LSP wiring, so the non-VS-Code path sufficed until the cutover.
- Task 016 status: **THE TASK'S COMPLETION CRITERION IS MET — `Parser.cs` IS DELETED** (not "a reviewed
  zero-policy mechanical host"; the file is gone, along with the `ParseResult` record it solely produced).
  STAGE N+3 (THE DELETION ARC) HAS LANDED on the full IDE bar; there is no remaining parser sub-slice and no
  parser policy left in C#. The N# owner `ColumnarParserRecovery` is the sole parse + ordered-diagnostic
  authority for production AND for every test in the repository. The one piece of residual BOOKKEEPING —
  translating the 2,021 rerouted C# parser assertions into native `.tests.nl` contracts — is recorded as a
  follow-on in "Iterative-task targets"; it moves no ownership and does not gate this task's checkbox.
  The diagnostic-CAPABILITY arc
  (Stages 0-17) is COMPLETE and the parity ledger is CLOSED; the arc has moved into the AST/facts BRIDGE (STAGE N+1); N+1a (preamble-node construction), N+1b
  (the full AST-hierarchy MIGRATION from C# records to N# classes — the C# `Ast/` directory DELETED, CompilationUnit now
  owner-constructable, the Except site made reference-based), N+1c TRANCHE 1 (the owner's `ParseFileAst` now returns a
  real `CompilationUnit` for the container + preamble + FileImports + empty-body struct/interface/enum/record top-level
  declarations, proven node-by-node equal to Parser.cs by the reflection deep-equal harness `AstEq`; contracts 1215/1215),
  and N+1c TRANCHE 2 (ClassDeclaration materialized, +2 contracts → 1217/1217; the tranche-1 "constructor-planner gap"
  was DISPROVEN — the real cause was a simple-name TYPE COLLISION with test-helper classes in
  AnalyzerDeclarationContext.tests.nl, resolved by the byte-exact fully-qualified-name idiom, no planner change / no wall)
  have ALL landed — see the THIS-TURN Active sub-slice +
  the "## 016 AST/facts bridge (N+1) design record" section. Capability-arc
  summary follows (STAGE 17 landed — the CAPABILITY SURFACE IS NOW COMPLETE: residual map
  item [5], the LAST capability family — the garbage-type cascade shapes [`class 5` / `struct 5` non-`{` braced
  found-other via the unconditional `ParseTypeBody`; `func f(5)` non-identifier parameter name; `(x: 1, 5: 2)`
  named-tuple bad-name], the TYPE-ALIAS underlying-type consumer [`type T = <type>` — the `= <type>` body via
  ConsumeToken(Assign) + the newtype variant + the Stage-15 full type grammar], plus the deferral-ledger closeout
  [the corpus-light operator-`@` / `returns`-lifetime / multi-line-raw shapes now PINNED; the EOF-length-clamp class
  recorded PERMANENTLY-UNMATCHABLE; the Stage-16 table-row HANG recorded PRODUCTION-BUG-GATED with a chip filed]; the
  arc's parity ledger CLOSES — EVERY residual-map item [1]-[5] is DONE and EVERY recorded deferral is resolved or
  definitively classified. STAGE 16 [PRIOR] landed the TEST DSL + ATTRIBUTES [residual [4]]. 432 native parity
  contracts total [410 through Stage 16 + 22], `ColumnarParserRecovery.nl` now 6,855 lines; residual map items [1],
  [2], [3], [4], and [5] are ALL DONE) — the prior
  PROVEN-BLOCKED-WITH-RECORD finding
  (below) is the STAGE-0 prerequisite record for a staged parser-front-end arc (arc plan recorded in the "016
  parser/diagnostic ownership finding" section). STAGE 1 (shared-panic RECOVERY MODEL + import/namespace/package
  family, 11 contracts), STAGE 2 (the DECLARATION-NAME family — "Expected <kind> name" for func/class/struct/
  record/soa/interface/union/enum/type-alias, with `DiagnosticSpanFromToken` keyword-anchoring + the
  reserved-keyword-as-name variant, +24 contracts), STAGE 3 (the MALFORMED-LITERAL family — NL105
  unterminated string / interpolated / char / triple / interpolated-raw + empty char, reached via the
  expression-bodied `func f() => <literal>` context, +14 contracts), and STAGE 4 (the MEMBER / PARAMETER /
  FIELD declaration family — the `:`/`:=` colon and type-annotation errors via `func f(<params>)` and
  `class C { … }` / `struct S { … }`, the `ParseMemberList` per-member panic-reset sync point, and the
  Stage-2-deferred braced-kind found-other `{`-offender retirement, +17 contracts), and STAGE 5 (the
  GENERICS / CONSTRAINTS family — `ReportMissingTypeParameterName` / `ReportMissingGenericTypeArgument`, the
  `ConsumeGreater` split-`>>` discipline, and the `where`-clause constraint errors incl. the class/struct and
  struct/new() `InvalidSyntax` validations, via the function head + class type-params, +22 contracts), and STAGE 6
  (the STATEMENT family — the real `func f() { … }` block-body grammar Stages 3-5 left unparsed, the
  `SynchronizeToNextStatement` sync point + per-statement panic reset + `_currentRecoveryBoundaryColumn` tracking,
  the dangling-binary/assignment-operator through-token span, the missing-initializer `:=`/`=` forms, the
  missing if/while condition, the missing for/foreach `in`, and the missing-statement-body report, +25 contracts),
  and STAGE 7 (the EXPRESSIONS family — the fuller precedence ladder over Stage-6's shallow subset [ternary /
  coalescing / logical-or/and / bitwise-or/xor/and / equality / relational / shift / additive / multiplicative /
  range / unary / postfix-member], carrying the expression ERROR families Stages 3/6 kept panic-suppressed:
  unexpected-token-in-expression, prefix `+` [NL103], leading `.`, the ternary missing-then / missing-`:` /
  missing-else sites, dangling binary operators across every ladder tier, await/must/throw missing-operand, and
  member-name-after-dot [incl. the reserved-keyword member], +35 contracts), and STAGE 8 (the MATCH / PATTERN
  family — `ParseMatchExpression` [the match-keyword primary vehicle + `Consume(LeftBrace/Arrow/Comma/RightBrace)`
  case sites + the `EnsureProgress` per-case boundary that does NOT reset panic], the `ParsePattern` →
  or/and/not/relational → `ParsePrimaryPattern` grammar [list / slice / positional / literal / object / union-case /
  type / qualified-name] terminating in the "Invalid pattern" NL103, and `ParsePropertyPatterns`' property-name /
  brace sites, +18 contracts)
  have LANDED (no production edit to any consumer, no commit — mandate; working tree carries the two N# files + the
  STAGE-1 ColumnarSyntaxDiagnostics scaffolding deletion + this STATUS update). `ColumnarParserRecovery.nl`
  reproduces Parser.cs's recovery discipline faithfully and is proven byte-exact against the production Parser.cs
  path on a golden parity corpus (166 native contracts total, including the cascading-suppression, does-not-swallow-
  following, keyword-anchored absent/reserved name, cross-boundary panic-reset, the malformed-literal
  in-region-suppression, the member-boundary panic-reset, the split-`>>` well-formed-nested-generic, the
  statement-boundary reset + within-statement cascade-suppression, the expression-family unexpected-token-skip /
  prefix-plus-cascade / initializer-terminator-then-reset shapes, and the match/pattern cascade-suppression-within-a-
  match / statement-boundary-reset-between-matches / invalid-pattern-terminal shapes). Parser.cs REMAINS the sole
  production syntax authority; cutover is the arc's LAST stage. No wall tripped (self-contained shape, packaged SDK
  emits it — no repin).
- Active sub-slice (016 arc, THIS TURN, TARGET RECORDED BEFORE EDITING): **STAGE N+3 — THE `Parser.cs`
  DELETION ARC.** TARGET: retire the LAST callers of `Parser.cs` (C# unit tests only — production was cut
  over in N+2) and DELETE `src/NSharpLang.Compiler/Parser.cs` (7,116 lines) plus everything left provably
  dead behind it, then retire its `compiler-core` ratchet row to `removed`.
  INVENTORY (grep of `new Parser(` across the tree, re-verified before editing — the N+1 records named only
  3 candidate files; the REAL set is **21 files**, 20 of them tests plus Parser.cs's own internal
  interpolation sub-parser): `ParserTests.cs` (16 sites / 212 facts / 1,503 asserts), `ParserErrorTests.cs`
  (1 / 91 / 419), `ErrorHandlingTests.cs` (1 / 39 / 54), `EventSubscriptionTests.cs` (2 / 10 / 28),
  `LocalFunctionTests.cs` (1 / 4 / 17), `AnalyzerTests.cs` (7), `AnalyzerBindingMapTests.cs`, `AnalyzerSemanticModelTests.cs`, `AstNodeFinderTests.cs`,
  `CliParityAuditTests.cs`, `CodeFixTests.cs` (2), `CodeIntelligenceTests.cs`, `CompletionEngineTests.cs`,
  `ErrorRecoveryPipelineTests.cs` (2), `ExampleLintTests.cs` (2), `FormatterTests.cs` (5), `LinterTests.cs` (5),
  `LinterUnusedVariableTests.cs`, `SoaRecordNullConditionalTests.cs`, `SystemsNSharpTests.cs`.
  `LanguageServerDiagnosticsTests.cs` does NOT construct `Parser` — it drives the LSP end-to-end and simply
  keeps passing over the routed pipeline, exactly as the mandate anticipated.
  CLASSIFICATION + FATE (recorded before editing):
  (a) **15 files whose SUBJECT is not the parser** (analyzer / linter / formatter / completion / code-fix /
  code-intelligence / systems / CLI-parity) construct `Parser` only as an AST FACTORY. Their assertions are
  live coverage of OTHER owners and are NOT parser assertions, so they are neither "covered by a contract" nor
  "retired": they **ROUTE MECHANICALLY TO N#** (`ColumnarParserRecovery.ParseFileAst`), which is exactly what
  the task contract permits ("Existing C# may only shrink, route mechanically to N#, or be deleted") and what
  the 12 production consumers did in N+2. This is also a CORRECTNESS FIX: since N+2 these tests were
  exercising a parser that is no longer in the product.
  (b) **5 parser-subject files** (`ParserTests` / `ParserErrorTests` / `ErrorHandlingTests` /
  `EventSubscriptionTests` / `LocalFunctionTests`, 356 facts / 2,021 assertions) route the SAME way. RATIONALE,
  recorded as the deliberate fork decision: deleting 2,021 assertions on the strength of "the N+2 probe covered
  it" is the SHORT path, not the complete one — the probe proves owner==Parser.cs on 27,694 corpus sources, not
  on these synthetic snippets. Rerouted, every one of those assertions becomes an EXECUTABLE proof obligation on
  the N# owner over a 2,021-assertion synthetic surface the native corpus does not otherwise reach, and it
  passes or the suite goes red. No assertion is lost, no C# parser POLICY survives, and the task's completion
  criterion (`Parser.cs` deleted) is met in full. The residual C#-to-N#-contract translation of those
  assertions is bookkeeping, not ownership, and is recorded as a follow-on below — it does NOT gate 016.
  (c) **retired with the owner**: `ParseResult` (`ErrorReporting.cs`) and any other type left reachable only
  from `Parser.cs` — deleted iff provably dead after the reroute.
  BAR: full unit suite, BootstrapServices contracts, corpus IL byte-exact sweep, ownership audit 18/18 after
  the ratchet repin (`Parser.cs` → `removed`, zero `current*`, epochs preserved, `text-v1:removed`), and the
  FULL VS Code-enabled gate — `Parser.cs` is in the assemblies the LSP builds against.
  **RESULT: LANDED IN FULL (no commit — mandate). `Parser.cs` IS DELETED; TASK 016's COMPLETION CRITERION IS
  MET.**
  DELETIONS (line accounting): `src/NSharpLang.Compiler/Parser.cs` **−7,116** (the whole file) and
  `src/NSharpLang.Compiler/ErrorReporting.cs` **−14** (the `ParseResult` record — the ONLY thing in the file,
  and `Parser.cs` was its only producer; grep across `src/` + `tests/` + `editors/` confirms zero surviving
  references). **TOTAL C# DELETED: 7,130 lines. TOTAL C# ADDED: 0.** The 20 rerouted test files are a further
  **net −134 C# lines** (+75 / −209: each 4-line Lexer+Tokenize+Parser+ParseCompilationUnit idiom collapses to
  one call, minus one `using` per file), so the slice is **−7,264 C# / +53 N#** (the owner's 22-line `Success`
  property + 31 lines of contracts). Docs updated with the owner: `memory/components/parser.md` (File → Owner,
  the testing layers, the usage example) and `memory/architecture.md`'s pipeline entry.
  DEAD-CODE SWEEP behind the owner (step 3 of the mandate) — every helper `Parser.cs` referenced was checked
  and is LIVE, owned by N#, and KEPT: `ParserTokenCompactor` (`CompilerBootstrapServices.nl`, called by the
  owner's own compaction step), `DiagnosticSpan` (`ParserDiagnosticSpan.nl`), `DiagnosticSpanResolver`
  (`DiagnosticSpanResolver.nl`; also read by `LspDiagnosticConverter.cs`, `Linter.cs`, `CompilerError.nl`),
  `Preprocessor`, `Lexer` / `Token`. `ParseResult` was the ONLY provably-dead type and it is deleted.
  ASSERTION-MIGRATION LEDGER (the mandate's (a)/(b)/(c) classification, applied to all 21 files):
  * (a) ALREADY COVERED → 0 files deleted on this basis. The claim was tested rather than asserted: rerouting
    runs every assertion against the owner, which is a STRICTLY STRONGER check than mapping it to a contract
    by hand, and it came back 100% green. Deleting on a mapping argument would have traded executable
    coverage for prose.
  * (b) MIGRATED → all 53 parse sites in 20 files, mechanically, to `ColumnarParserRecovery.ParseFileAst`
    (`Lexer`+`Tokenize`+`new Parser`+`ParseCompilationUnit` → one call). 15 of those files are
    ANALYZER / LINTER / FORMATTER / COMPLETION / CODE-FIX / CODE-INTELLIGENCE / SYSTEMS / CLI-PARITY tests
    that only used `Parser` as an AST factory; 5 are parser-subject files. Plus 4 NEW native contracts for
    the owner's new `Success` member.
  * (c) RETIRED WITH THE OWNER → the `ParseResult` record and Parser.cs's internal interpolation SUB-parser
    (`:5148`, never reachable from outside the class). No test asserted Parser-class-internal mechanics, so
    no test file was retired.
  * `LanguageServerDiagnosticsTests.cs` never constructed `Parser`; it drives the LSP end-to-end and passes
    unchanged over the routed pipeline, exactly as the mandate anticipated.
  THREE SITES WERE NOT MECHANICAL and are recorded: (1) `FormatterTests.FormatWithComments` still needs
  `lexer.Comments`, so its `Lexer` is KEPT and lexes alongside the owner's internal lex — the same shape
  production's `Formatter.FormatSafe` / CLI `FormatSource` / `PlaygroundCompiler` / `DocumentManager` took in
  N+2; (2) `ParserErrorTests`'s `Parse` returned the `ParseResult` TYPE by name (the only test that did) and
  now returns `FileParseAst`, retiring its private `Tokenize` helper with it; (3) `CodeFixTests`'s
  re-parse-the-fixed-source site was a one-line `new Parser(t).ParseCompilationUnit()` chain.
  OWNER CHANGE (N#, the ONLY new code in this slice): `FileParseAst` gains `Success: bool { get { … } }`,
  reproducing `ParseResult.Success` exactly (`CompilationUnit != null && !Errors.Any(e => e.Severity ==
  ErrorSeverity.Error)`). Without it the retiring record still had a member the owner lacked, and every test
  read of `.Success` would have had to be REWRITTEN rather than routed. It is a PROPERTY on the small leaf
  result class, NOT on `ColumnarParserRecovery`, so the per-class member ceiling is untouched.
  SUITE-COUNT ACCOUNTING: **3,193 → 3,193.** The total is UNCHANGED because zero test files and zero `[Fact]`s
  were deleted — the migration moved what each test parses WITH, not what it asserts. (Had the 5 parser-subject
  files been deleted instead, the total would have fallen by 356 facts / 2,021 assertions with nothing
  executable put in their place.)
  EVIDENCE: full unit suite **3,193 / 3,193** (`dotnet test tests/Tests.csproj -c Release`, 3m12s);
  BootstrapServices contracts **1,554 / 1,554** via the canonical `dotnet test
  src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false` (1,550 baseline + 4 new
  `Success` contracts, incl. the below-error-severity and absent-CompilationUnit arms; the 3 ExternalAssemblyScan
  Debug-layout tests did NOT trip); ownership audit **18 / 18**; corpus IL sweep **78 / 78 comparable
  assemblies BYTE-IDENTICAL, PRODUCT_IL_DIFFS = 0** (fresh Release CLIs built at baseline `4d7a7cb79` in a
  throwaway `/tmp` worktree and at the working tree, driven over every `project.yml` target under
  `examples/` + `tests/` plus every single-file example, normalizing ONLY the COFF TimeDateStamp and the
  `#GUID`/`#Pdb` heaps — the same two run-varying fields N+2 normalized); `./scripts/dev.sh --since` (it
  correctly took the FULL unit suite fail-safe, naming `ErrorReporting.cs` as a shared compiler file and the
  three `.nl` paths as unmapped).
  RATCHET REPIN via `scratchpad/repin_016_n3.py` — `current*` + per-file fingerprints ONLY:
  * **REMOVED rows** (the N+1b `Ast/*.cs` precedent): `src/NSharpLang.Compiler/Parser.cs`
    `existing-debt` 7,116/6,180 → `state: "removed"`, 0/0/0/0, `text-v1:removed` (epoch 7,117/6,183 PRESERVED);
    `src/NSharpLang.Compiler/ErrorReporting.cs` 14/12 → `removed`, 0/0/0/0, `text-v1:removed`
    (epoch 14/12 PRESERVED).
  * **20 test rows repinned**, every one net-negative and comfortably inside its ceilings — largest movers
    `ParserTests.cs` 6,130→6,087 (nonblank 5,210→5,167), `AnalyzerTests.cs` 13,452→13,433 (11,746→11,727),
    `LinterTests.cs` 1,380→1,366, `FormatterTests.cs` 2,146→2,134, `ParserErrorTests.cs` 1,923→1,914.
    No compression or consolidation was needed anywhere.
  * ASSERTION MARKERS: the only movement is **−53, and every one is a FALSE POSITIVE** — the marker heuristic
    counts `it(` for JS frameworks, and `ParseCompilationUnit()` contains it. A per-marker diff over all 20
    files proves `[Fact]` / `[Theory]` / `Assert.` / `Should(` / `test(` / `expect(` counts are IDENTICAL in
    EVERY file, and that each file's `it(` delta equals exactly its `ParseCompilationUnit()` delta.
  * `reviewedHeadFingerprint head-v1:18244d220963ad03 → head-v1:d889362e0ea7e2a4`, mirrored into
    `OwnershipAudit.nl`'s `OwnershipPolicy.ReviewedHeadFingerprint`. **Every `epoch*` value, `epochPathFingerprint`,
    `epochFactFingerprint` and `epochFileCount` untouched and RE-VALIDATED by recomputation after the write**
    (the repin script reimplements `OwnershipFacts` exactly and was self-checked against the pre-edit manifest:
    it reproduces the existing pathset, epochfacts and head fingerprints bit-for-bit before changing anything).
  GATES (the FULL IDE bar — deleting `Parser.cs` changes the Compiler assembly the language server ships):
  * **`./scripts/test-all.sh --commit` with NO `VSCODE_TESTS=skip`: EXIT 0 in 13m48s**, run FRESH in the
    script's own isolated copy (`/private/tmp/nsharp-test-all.29934dd4912d.*/repo`) — not a cached whole-gate
    or per-step result. **105 `✓ PASSED` steps, ZERO failures**: unit 3,193/3,193, BootstrapServices contracts
    1,554/1,554, every native N# project (compiler-service contracts, the example test projects, all
    `tests/native/*`), the format-contract gate, SDK/runtime/template pack + install, `dotnet new` template
    creation, the console AND Web API template builds via `nlc build`, every example project, every
    single-file example, `nlc check` on examples, and the ECMA-335 IL verification gate.
  * **Step 3b VS Code Integration Tests: `36 passing` (41s), ✓ PASSED** — extension activation, diagnostics,
    hover, completion, all driven over the routed pipeline with `Parser.cs` gone.
  * `./scripts/reload-vscode-extension.sh`: EXIT 0 — language server republished, `nsharp-0.6.0.vsix`
    (289 files, 3.98 MB) repackaged, `Extension 'nsharp-0.6.0.vsix' was successfully installed`, VS Code
    reopened on `examples/01-hello-world`. It WAS needed: no LanguageServer source changed, but the
    `NSharpLang.Compiler` assembly the server ships lost `Parser.cs`, so the shipped server had to be rebuilt.
  * INTERACTIVE computer-use verification: **NOT PERFORMED — the permission system DENIED the VS Code
    control grant for this session** (`request_access` → `user_denied`). Recorded as a gap, not skipped by
    choice. The automated IDE evidence above (36 VS Code integration tests over a freshly installed VSIX)
    stands; a human/coordinator screenshot pass over `examples/01-hello-world` — now open in the reloaded
    editor — is the outstanding item if an eyes-on record is required.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change; the packaged SDK self-emits the
  owner edit.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): **STAGE N+2 — THE PRODUCTION
  CUTOVER.** TARGET: route EVERY production consumer of `Parser.ParseCompilationUnit()` to the N# owner
  `ColumnarParserRecovery`, so the owner becomes the sole production parse + ordered-diagnostic authority.
  Parser.cs is left UNREFERENCED by production but NOT deleted (deletion + the C# parser-test migration is
  N+3). No shadow parse, no comparison route, no fallback flag.
  OWNER SHAPE: `ParseFileAst(source, fileName)` currently returns a bare `CompilationUnit`, but consumers need
  the diagnostics too. It gains a result class (`FileParseAst { CompilationUnit, Errors }`) whose FIELD NAMES
  match `ParseResult`'s, so each consumer's downstream reads are byte-identical and the routing edit is a
  one-line replacement of the Lexer+Parser pair. Errors are the RAW recording-order list (Parser.cs returns
  `_errors` unsorted; `SortErrorsByPosition` stays the ParseFilePreamble/CLI-oracle path only) — verified by
  probe, see below. This adds NO member FUNCTION to the owner class (the per-class ceiling holds: a new
  top-level class + a changed return type only).
  CONSUMER INVENTORY (re-verified by grep of `new Parser(` / `ParseCompilationUnit` across src — 12 external
  production sites + Parser.cs's own interpolation sub-parser, which is internal and stays):
  MultiFileCompiler.ParseAllFiles :192; Analyzer :19133 (project unit cache), :21704 (file-import unit),
  :22025 (project namespaces), :22059 (per-file namespace); Formatter.FormatSafe :36 (re-parse gate);
  CLI Program.FormatSource :688; CLI LintCommand :90; CodeIntelligence FixApplicator :26 and
  CodeIntelligenceService.GetOutlineSingleFile :117; LanguageServer DocumentManager :250; Playground
  PlaygroundCompiler :73.
  STAGING: (1) the NON-IDE consumers first (compiler front-end, CLI, CodeIntelligence, Playground), proven by
  the non-VS-Code gate + a corpus IL byte-exact sweep (identical trees → identical analysis → identical IL,
  fresh Release CLIs at baseline and after over every example/fixture/native target); (2) then the LSP
  (DocumentManager) with `./scripts/reload-vscode-extension.sh` + the FULL VS Code-enabled gate.
  KNOWN NON-MECHANICAL POINT (recorded before editing): MultiFileCompiler is the ONLY consumer that
  preprocesses (`Preprocessor.Process(tokens…)` at :190) before parsing. The owner tokenizes internally, so
  that site routes through the SOURCE-level `Preprocessor.ProcessSource(source…)` — the same overload
  MultiFileCompiler ALREADY uses for the columnar emit path at :495, which blanks non-emitted lines in place
  and so preserves every line/column. Exactly ONE file in the tree carries `#if`
  (`examples/11-advanced-features/PreprocessorDirectives`), and it is in the IL sweep corpus.
  Sites that ALSO need the Lexer for comments/tokens (Formatter, CLI FormatSource, Playground,
  DocumentManager) keep their Lexer and lex twice; the owner's internal lex is the parse input.
  **RESULT: LANDED IN FULL (no commit — mandate). THE N# OWNER IS NOW THE SOLE PRODUCTION PARSE AND
  ORDERED-DIAGNOSTIC AUTHORITY.** `grep` of `new Parser(` / `ParseCompilationUnit` across `src/` +
  `editors/` returns exactly TWO hits, both inside `Parser.cs` itself (its own entry :28 and its
  interpolation-hole SUB-parser :5148). No production type reference to `Parser` survives anywhere else.
  ROUTING TABLE (before → after, net tracked lines):
  * `MultiFileCompiler.ParseAllFiles` :184-195 — Lexer+Tokenize+`Preprocessor.Process(tokens…)`+Parser
    (11 lines) → `Preprocessor.ProcessSource(source…)` + `ColumnarParserRecovery.ParseFileAst(live, …)`
    (7 lines). **−4.** The ONE non-mechanical point, recorded above: the token-level preprocessor is
    replaced by the SOURCE-level overload already used at :495 for the columnar emit path.
  * `Analyzer` ×4 — :19132 project-unit cache, :21701 file-import unit, :22023 project namespaces,
    :22052 per-file namespace: each Lexer(+Tokenize)+Parser+ParseCompilationUnit collapses to ONE
    `ColumnarParserRecovery.ParseFileAst(...)`; one `using NSharpLang.Compiler.Columnar;` added. **−8.**
  * `Formatter.FormatSafe` :34 — the re-parse gate; the Lexer STAYS (its `Comments` feed the idempotence
    re-format), `Tokenize()` is called for that side-effect only. **−1.**
  * `CLI Program.FormatSource` :686 — same shape (Lexer kept for `lexer.Comments`). **−1.**
  * `CLI LintCommand` :88. **−3.**  * `CodeIntelligence.FixApplicator` :24. **−3.**
  * `CodeIntelligenceService.GetOutlineSingleFile` :115. **−3.**
  * `PlaygroundCompiler` :72 — Lexer kept for `lexer.Comments`. **0.**
  * `LanguageServer DocumentManager.UpdateDocument` :250 — Lexer kept (`state.Tokens` / `state.Comments`
    feed completion + semantic tokens); only the Parser pair is replaced. **−1.**
  Every downstream read (`parseResult.CompilationUnit`, `parseResult.Errors`) is BYTE-UNCHANGED at all
  12 sites, because the owner's new result class names its fields exactly as `ParseResult` does.
  OWNER CHANGE (N#): a new leaf class `FileParseAst { CompilationUnit: CompilationUnit?; Errors:
  List<CompilerError> }` (the `PreambleAst` precedent) and `ParseFileAst` now returns it instead of a bare
  `CompilationUnit`. Errors are the RAW RECORDING-ORDER list — Parser.cs returns `_errors` unsorted, so
  `SortErrorsByPosition` stays the `ParseFilePreamble` / CLI-oracle path only. **The per-class member
  ceiling is RESPECTED: zero member functions added** (a new top-level class + a changed return type).
  SIX OWNER PARITY DEFECTS FOUND AND FIXED by the cutover-grade probe — all invisible to the tranche-11
  probe, which compared fewer diagnostic fields and did not fuzz these shapes:
  (1) the object-initializer INDEXER `Consume(Assign)` passed `"="` where Parser.cs's `TokenTypeToString`
  has NO `Assign` case and renders `"assign"` (`TokenType.Equal` is the one mapped to `"="`);
  (2) the multi-parameter LAMBDA `Consume(Arrow)` passed `"=>"` where `TokenTypeToString(Arrow)` renders
  `"arrow"`. An exhaustive audit of all 21 `ConsumeToken(TokenType.X, msg, expected)` shapes confirms the
  other 19 already match `TokenTypeToString`;
  (3) `ParseParameterListRecovery` anchored `IsParameterListRecoveryBoundary` on the LIST'S OPENING token;
  Parser.cs anchors on `Previous` at EACH iteration (:778) — the `(` on the first pass, the `,` on later
  ones — so a same-line continuation after a comma is never a boundary. With the wrong anchor a
  `record R(\n  B: int,func\n  C: int)` broke out of the parameter list and re-parsed `func …` as a MEMBER
  where Parser.cs consumes the reserved keyword and keeps going into the base list;
  (4) the owner reset `SplitGreaterDepth = 0` unconditionally at BOTH the top-level and the member
  boundary; Parser.cs resets the split-`>>` debt ONLY inside SynchronizeToNextDeclaration/Statement
  (:7044/:7088), so `class C { A: X<Y>>\n B: int }` must carry the owed `>` across the member boundary
  and produce the field literally named `>`;
  (5) FOUR retained `<error>`-name DECLINES — both tuple-deconstruction forms (parenthesized :2589 and
  bare :3573), `foreach` (:2784), `await foreach` (:2814) and the `using` declaration (:3109). Parser.cs
  adds every name it gets from `ConsumeIdentifier`, placeholders included, so these are reproduced now;
  the surviving `IsVisibleName` uses are message-SHAPING only (parameter/field type anchors, the
  object-initializer colon report), never gates;
  (6) the `on`-subscription "Expected an event handler lambda" NL103 anchored on the pre-parse cursor;
  Parser.cs anchors on the PARSED handler expression's own Line/Column (:2926-2929), which for a binary
  expression is the OPERATOR column, not the first token.
  PROOF (whole tree AND the RAW-ordered diagnostic stream — code / severity / line / column / length /
  message / humanExplanation / contextualHint / suggestion / fileName / docsUrl / diagnosticId /
  suggestions; trees through the identical `OutputFormatter.AstToJson`):
  * **WHOLE-TREE 514 / 514** `.nl` files in the working tree.
  * **MALFORMED-CORPUS 452 / 452** non-empty `RunPreamble(…)` / `RunPreambleAst(…)` sources extracted from
    the arc's diagnostic parity corpus.
  * **FUZZ 26,728 / 26,728** LSP-shaped mutants over 11 independently seeded rounds (truncation /
    structural-character deletion / whole-line deletion / token-garbage injection). Rounds on seeds
    11/23/47/101/303/707 caught the six defects above; after the fixes ALL eleven rounds are 100%.
  * **TOTAL PROVEN: 27,694 sources, 0 mismatches, 0 exceptions.**
  CORPUS IL BYTE-EXACT SWEEP (fresh Release CLIs at baseline `b0ad09fd9` and after, over EVERY
  example/fixture/native target — 40 `project.yml` builds + 31 single-file examples + 18 `nlc test`
  native assemblies = **89 emitted assemblies**): **88 / 88 comparable assemblies BYTE-IDENTICAL**
  after normalizing ONLY the two provably run-varying PE fields (the COFF TimeDateStamp and the `#GUID`
  heap that carries the module MVID — a same-CLI rebuild differs in exactly those 17 bytes). The 89th,
  `tests/native/ownership-audit`, differs solely because its OWN N# source carries the new
  `ReviewedHeadFingerprint` constant. **PRODUCT_IL_DIFFS = 0.**
  EVIDENCE: full unit suite **3,193 / 3,193**; BootstrapServices contracts **1,550 / 1,550** via the
  canonical `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`
  (the 3 ExternalAssemblyScan Debug-layout tests did NOT trip); ownership audit **18 / 18**;
  `./scripts/dev.sh Parser` **384 / 384**; **the FULL VS Code-ENABLED gate `./scripts/test-all.sh --commit`
  (no `VSCODE_TESTS=skip`) EXIT 0** in 13m44s — VS Code integration smoke **36 passing** (extension,
  diagnostics, hover, completion), Web API template listed/created/built, IL verification gate,
  format-contract gate, all 24 native N# projects, all example + single-file builds, `nlc check` on
  examples. `./scripts/reload-vscode-extension.sh` run: `nsharp-0.6.0.vsix` rebuilt and installed, VS Code
  reopened on `examples/01-hello-world` for the coordinator's visual-verification record.
  RATCHET: 9 tracked C# files touched, every one **net-negative or net-neutral**, so no comment
  compression was needed — LintCommand.cs 205→202 (nonblank 186→183, epoch 205/186), Program.cs 787→786
  (683→682, epoch 787/683), Analyzer.cs 23068→23060 (20254→20246, epoch 23451/20537),
  CodeIntelligenceService.cs 1906→1903 (1667→1664, epoch 1906/1667), FixApplicator.cs 57→54 (50→47,
  epoch 57/50), Formatter.cs 2303→2302 (2128→2127, epoch 2303/2128), MultiFileCompiler.cs 669→665
  (593→589, epoch 670/595), DocumentManager.cs 1450→1449 (1247→1246, epoch 1450/1247),
  PlaygroundCompiler.cs 614→614 (556→556, epoch 614/556). REPIN via `scratchpad/repin_015_s3.py` with
  CHANGED covering exactly those 9: `current*` + per-file fingerprints only, plus
  `reviewedHeadFingerprint head-v1:682bbdb2c76e50c8 → head-v1:18244d220963ad03` mirrored into
  `OwnershipAudit.nl`. **Every `epoch*` value and both epoch fingerprints untouched and re-validated
  after the write.** All net-new code is N#.
  WALL STATUS: **NO two-stage bootstrap wall** — no kernel or OpCodes change; the packaged SDK self-emits
  every owner edit.
  CONSUMERS LEFT UNROUTED: **NONE.** No divergence forced a stop; the six defects above were fixed in the
  N# owner, never worked around in a consumer.
  N+3 DELETION-ARC READINESS: `Parser.cs` (7,116 lines) is now dead to production — its only remaining
  callers are `tests/` unit tests (ParserTests / ParserErrorTests / FormatterTests / LinterTests /
  AnalyzerTests / CodeFixTests / CompletionEngineTests / ErrorRecoveryPipelineTests / … , which is why the
  full unit suite still shows 3,193 green). N+3 is therefore exactly: migrate those C# parser assertions
  to native N# contracts against `ParseFileAst`, then delete `Parser.cs` and retire its `compiler-core`
  ratchet row. Nothing in the product path blocks that deletion any more.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST
  MATERIALIZATION), TRANCHE 11 = **ERROR-NODE MATERIALIZATION — the MALFORMED-FILE surface**. TARGET:
  (1) reproduce, byte-exact, EVERY synthetic recovery artifact Parser.cs produces on malformed input
  (`IdentifierExpression("<error>")` at each of its production sites, the `IdentifierPattern("<error>")`
  terminal, the `SimpleTypeReference("<error>")` parameter/field/new type substitutes, the `<error>`-named
  declaration placeholders incl. the top-level unexpected-token ClassDeclaration and the `<error>` member
  from the reserved-keyword arms, the `<error>` test description) INSTEAD of declining them — a declining
  owner cannot serve the LSP on files being actively edited, which are malformed most of the time, and the
  N+2 cutover hands consumers whatever Parser.cs produces TODAY; (2) close the two recorded STRUCTURAL gaps
  — the MULTI-LINE type SourceSpan gate and the `is` pattern-variable next-line capture; (3) prove the
  3 residual whole-file declines join the set (407/407) AND extend the proof to the MALFORMED corpus
  (the arc's diagnostic parity-corpus sources are malformed by design) via the AstEq harness + the
  triangulation probe. WALL: the owner class is AT the columnar per-class member ceiling — every new helper
  must be INLINED or an existing member deleted/merged first.
  **RESULT: LANDED IN FULL (no commit — mandate). ZERO irreproducible sites; nothing declines any more.**
  SYNTHETIC-NODE SITE INVENTORY (exhaustive grep of `"<error>"` in Parser.cs + the two structural gaps),
  every one now REPRODUCED byte-exact:
  (A) `IdentifierExpression("<error>")` — 9 production sites: ParseRightOperandOrMissing / the shared binary
  + assignment dangling-operator arm (:3785, column = op.Column + Max(1, op.Value.Length)),
  ParseUnaryOperandOrMissing (:3824, await/must/throw), ParseInvalidPrefixPlusExpression (:3850, anchored ON
  the plus), ParseRequiredExpressionAfter (:3895 — the if/while/for-in/return/print/yield/throw/assert/
  using/lock/`:=`/`=` missing-value anchor), the ParsePrimaryExpression TERMINAL (:4838), the
  object-initializer MISSING-`:` value (:5334, propName.Column + TokenLengthOrFallback) and MISSING-VALUE
  value (ParseObjectInitializerMemberValue :5376, separator-anchored), the tuple recovery-boundary
  `ParenthesizedExpression(IdentifierExpression("<error>"))` (:5456), and the leading-`.`
  no-receiver arm (:6447).
  (B) `IdentifierPattern("<error>")` — the ParsePrimaryPattern "Invalid pattern" terminal (:3467).
  (C) `SimpleTypeReference("<error>") { Span = FromStartAndLength(span…) }` — ParseParameterTypeReference
  (:6541), ParseFieldTypeReference (:6577), ParseNewTypeReference (:6610).
  (D) `<error>`-NAMED placeholders — the top-level unexpected-token `ClassDeclaration` (:255, Line/Column
  read AFTER the skip Advance so they name the FOLLOWING token), the ConsumeIdentifier/ConsumeSystemsIdentifier/
  ConsumeAttributeIdentifier name placeholder (:6747/:6767/:6792/:6819) flowing into function / class /
  struct / record / soa / interface / union / enum / type-alias / newtype names, field + property names,
  parameter names (:822), lambda parameter names (:5520), type-parameter names (:755), `where`
  type-parameter names (:936), union case + case-property names, enum member names, soa column names,
  attribute names (:5292), object-initializer + `with` property names, property-pattern names, qualified
  PATTERN segments (:3414), event-target member names (:2949), the `returns param(<error>)` lifetime
  string (:510), the MEMBER-ACCESS `<error>` member from BOTH the reserved-keyword (:4446) and
  missing-name (:4451) arms, and the test DESCRIPTION (:569).
  (E) OTHER recovery artifacts — the constructor's synthetic EMPTY `this()` initializer for a
  non-`this`/`base` target (:1559), the local function's synthetic EMPTY `BlockStatement` body (:2530), the
  `on` subscription's synthetic empty-parameter lambda over an empty block when the handler is not a lambda
  (:2930), ParseOperatorSymbol's `symbol = "+"` switch DEFAULT (:5854), the property/indexer accessor
  recovery (the declaration is still built, :1768/:1642), the generic-soa report (the declaration is still
  built, :1136), the parameter-list trailing-comma (:775) and recovery-boundary (:778) BREAKS (Parser.cs
  returns the PARTIAL list, not a decline), and the `<>` / `<T,>` type-parameter + `Name<>` / `Name<T,>`
  generic-argument early breaks (the partial list is the result).
  THREE STRUCTURAL FIXES beyond the site inventory:
  (1) **MULTI-LINE SourceSpan** — the recorded single-line gate is RETIRED. `SourceSpan`'s 4-arg PRIMARY
  CONSTRUCTOR is public and emits fine (`new SourceSpan(startLine, startColumn, endLine, endColumn)`), so
  `SpanFromTokensSingleLine` / `ExtendSpanFromNode` / the `?[`-nullable and `&`-byref span builders now
  reproduce Parser.cs's `SpanFromTokens` / `ExtendSpan` EXACTLY instead of routing through the single-line
  `FromStartAndLength` factory — no sibling factory was needed. Root cause of the `>>` residual, now
  understood and pinned: for `Dictionary<string, List<int>>?` the owed split `>` is consumed by the FIRST
  `?` postfix (Check/Advance honor the split for ANY token), so the arm is DOUBLY nullable, the outer
  ConsumeGreater then fails on the NEXT LINE's token and `SpanFromTokens` produces a MULTI-LINE span.
  (2) **the type gate** — `ParseGatedTypeReference` no longer declines on panic-before / errors-during /
  multi-line; the type grammar itself is now byte-exact on every error path, so it always materializes.
  (3) **the top-level RECOVERY-BOUNDARY COLUMN** — Parser.cs's top-level declaration loop also does the
  save/set/restore of `_currentRecoveryBoundaryColumn` (:85-95) that the member and statement loops do; the
  owner's `Run()` did not. Without it a `record R(` whose parameters start on a LATER line at or left of the
  declaration keyword's column missed the `IsContinuationRecoveryBoundary` break (found by fuzzing).
  (4) **`Trim('"')`** — Parser.cs unquotes the test DESCRIPTION (:574) and SKIP REASON (:642) with
  `Trim('"')`, which strips EVERY leading/trailing quote rather than unwrapping a PAIR; on an UNTERMINATED
  literal (the LSP-while-typing shape) the two differ. Both now route through the existing
  `StripSurroundingQuotes` (the import-path idiom) — no new member.
  (5) **`ref struct`** — `isRefStruct` is threaded from the two `ref struct` dispatch arms (:224/:1446);
  the owner previously hard-coded `false` (found by the whole-file sweep, 2 real files).
  (6) **the interpolation-HOLE span resolution** — Parser.cs builds its hole sub-parser with NO sourceCode,
  so a hole diagnostic reported with a requested length of 0 resolves through `DiagnosticSpanResolver` on a
  NULL line and lands on (column, 1); the owner SHARES `Source` (deliberately, so the hole diagnostic keeps
  the CLI-shaped snippet the Stage-12 contracts pin), which let the resolver infer a token width and shift
  the column. A new `HoleDepth` FIELD clamps a 0 length to 1 while inside a hole — provably identical, since
  the resolver already ignores the line for every length > 0.
  WALL STATUS: **RESPECTED — the owner's member-function count is UNCHANGED at 280.** Every reproduction
  reused an existing member (the quote-strip reused `StripSurroundingQuotes`; the `<error>` type substitutes
  and synthetic expression/pattern nodes were built INLINE at their existing sites); the only additions are
  one parameter (`ParseStructName(…, isRefStruct)`) and one FIELD (`HoleDepth`). Fields do not trip the
  per-class member ceiling; member FUNCTIONS do.
  DEAD-GATE CLEANUP (same tranche): the two materialization gates the reproductions made permanently true —
  `TypeParamsMaterializable` and `ReturnLifetimeMaterializable` — were DELETED (fields, initializers, setters
  and all readers), so no always-true gate is left behind.
  DELIVERABLES: `ColumnarParserRecovery.nl` 9,358 → 9,371; `ColumnarParserAst.tests.nl` 5,170 → 5,463.
  CONTRACTS: **1,550 total / 1,550 PASS** (+26 net: 3 tranche-10 pinned DECLINES converted to POSITIVE
  contracts — the `using r { }` synthetic initializer, the `dispatch:<error>` allow effect, the
  conversion-operator `<error>` property member — plus 26 new tranche-11 contracts incl. 3 negative
  self-checks: a wrong synthetic member NAME, a wrong synthetic-operand COLUMN, a single-line span where
  Parser.cs builds a multi-line one). **ZERO retained declines.**
  EVIDENCE — the triangulation probe was extended to diff the DIAGNOSTIC STREAM as well as the whole tree
  (code / line / column / LENGTH / message / human explanation / hint / suggestion; SourceSnippet excluded
  because Parser.cs's hole sub-parser carries none in the raw ParseResult while the CLI fills it downstream):
  * **WHOLE-FILE: 407 / 407** of the recorded in-repo set (src 325 + examples 82) — was 404 — and
    **513 / 513** of EVERY `.nl` in the working tree (adds tests 57, docs 21, editors 17, templates 10),
    byte-exact owner==Parser.cs on BOTH tree and diagnostics. The malformed VS Code fixture
    `editors/vscode/test/fixtures/errors/MultipleSyntaxErrors.nl` is in that set.
  * **MALFORMED-CORPUS: 453 / 453.** All 453 unique `RunPreamble(…)` / `RunPreambleAst(…)` sources extracted
    from `ColumnarParserRecovery.tests.nl` (the arc's 444-contract diagnostic parity corpus, malformed by
    design) parse tree-equal AND diagnostic-equal. Baseline before this tranche: 262 / 453.
  * **FUZZ: 10,560 / 10,560** across three independently seeded rounds (2,420 + 3,740 + 4,400) over
    960 real repo files, using the four LSP-shaped mutations — mid-file TRUNCATION (the "being typed" shape),
    single structural-character DELETION, whole-LINE deletion, and token-garbage INJECTION. Rounds 2 and 3
    each caught one real divergence (the top-level recovery-boundary column; the hole span resolution), both
    fixed above; the final state is 100% on all three.
  * TOTAL PROVEN: **11,526 sources, 0 mismatches, 0 exceptions.**
  * BootstrapServices contracts 1,550 / 1,550 via the canonical `dotnet test
    src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false` (the 3
    ExternalAssemblyScan Debug-layout tests did NOT trip; the documented `dotnet build src/NSharpLang.Cli
    -c Debug` remains the remedy after a clean `rm -rf obj bin`). dev.sh Parser slice **384 / 384**.
  * Ownership audit: only `.nl` / `.tests.nl` / `.md` changed (2 .nl + 1 .md, **zero .cs** → OWN003 cannot
    trip, no C# growth → **NO REPIN**). Production compile path **UNTOUCHED** — `ParseFileAst` still has
    ZERO callers outside its `.tests.nl` (grep across src + editors + tests); Parser.cs stays the sole
    production authority. **No LSP / VS Code / extension file touched → no reload, no VS Code gate.** NO
    two-stage bootstrap wall tripped (no kernel or OpCodes change).
  N+2 CUTOVER READINESS: the owner is now a DROP-IN for Parser.cs's parse surface. On every source proven
  above — well-formed and malformed alike — it produces the identical `CompilationUnit` AND the identical
  ordered diagnostic list, including every synthetic recovery artifact an IDE consumer sees while a file is
  mid-edit. The remaining cutover work is pure WIRING (routing `ParseResult`'s producers and the LSP at
  Parser.cs's call sites, then deleting Parser.cs), which IS IDE-affecting: VS Code-enabled gate + extension
  reinstall + computer-use verification.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 10 = **STATEMENT BODIES — `BlockStatement` and the whole Statement node family** — the last node
  family before whole-file equivalence. TARGET was recorded before editing and the permitted RECUT was
  taken as TWO halves, BOTH landed this turn: **10a = BlockStatement + the ENTIRE Statement family + the
  block-bodied LAMBDA**; **10b = the member-BODY CONSUMERS** (function / method / constructor / property /
  indexer bodies, local functions, the test-DSL declarations).
  MECHANISM (unchanged discipline): every `ParseXStatement` now RETURNS `Statement?`; `ParseBlock` /
  `ParseBlockBody` return `BlockStatement?`; `ParseBlockStatementsLoop` ACCUMULATES `List<Statement>` and
  returns null when ANY contained statement declined (no-stub — a block never carries a partial list). The
  Advance / Report / Consume / synchronize sequence is UNTOUCHED at every site, so the ~440
  ColumnarParserRecovery diagnostic-stream contracts stay green.
  CONSTRUCTION-SITE INVENTORY — TRANCHE 10a (owner, each byte-exact to Parser.cs, VERIFIED owner==LIVE via
  the AstToJson probe): (1) BLOCK — `new BlockStatement(statements, line, column)` (Parser.cs :2227),
  line/column = the OPENING BRACE; the found-declaration `break` (:2180) still returns the statements
  accumulated so far; (2) EMPTY — `new EmptyStatement(ownerSpan.Line, ownerSpan.Column)` (:2235, the
  missing-body arm) / `(line, column)` (:2244, a bare `;`); (3) VARIABLE DECLARATION —
  `new VariableDeclarationStatement(name, type, initializer, kind, line, column)` (:2578), anchored on the
  NAME, `kind` read off the let/const/readonly token (:2248-2252); (4) TUPLE DECONSTRUCTION —
  `new TupleDeconstructionStatement(names, initializer, kind, line, column)` (:2637 paren form / :3583
  paren-free / :3625 statement-level); (5) EXPRESSION STATEMENT —
  `new ExpressionStatement(expr, line, column)` (:3643, anchored on the STATEMENT start) plus the typed
  let-less declaration (:3535) and the `identifier :=` shorthand (:3640, anchored on the IDENTIFIER node);
  (6) IF / WHILE — (:2659 / :2829), an ABSENT else is a materialized null; (7) FOR — the two for-in arms
  wrap `new ForeachStatement(...)` in `new ForStatement(null, null, null, <foreach>, line, column)` (:2678/
  :2691, BOTH nodes on the `for` keyword) and the C-style arm builds (:2755) over the `:=`-shorthand
  initializer (:2723) or `new ExpressionStatement(expr, expr.Line, expr.Column)` (:2727 — anchored on the
  EXPRESSION, unlike :3643); (8) FOREACH / AWAIT-FOREACH — (:2784 / :2814, the latter on the `await`
  keyword); the previously-unmodelled OPTIONAL PARENTHESES `foreach (x in y)` (:2765/:2779) are now
  modelled; (9) RETURN / YIELD (:2844 / :2870, both with a materialized-null bare form), PRINT (:2883),
  BREAK / CONTINUE (:2901 / :2983), THROW (:2996), PREPROCESSOR (:2893), OFF (:2975); (10) TRY —
  (:3056) over `new CatchClause(exceptionType, varName, catchBlock)` (:3046, both parts optional);
  (11) USING — the declaration form (:3121), the rejected-tuple form whose Expression is the TUPLE's
  Initializer (:3119), and the bare-resource form (:3136); Parser.cs's `stmt as VariableDeclarationStatement`
  decision is reproduced through a transient `VariableDeclarationWasTuple` field so it stays correct even
  when the node declines; (12) LOCK (:3178); (13) SWITCH — (:3271) over `new SwitchCase(pattern, statements,
  caseLine, caseColumn)` (:3250); a BRACED case FLATTENS its block's statements into the case list (:3243),
  so no BlockStatement wrapper appears; `default` keeps a materialized-null Pattern; (14) UNSAFE / ALLOC
  BLOCK (:2396 / :2318); (15) ASSERT + ASSERT THROWS (:2427 / :2411); (16) ALLOW — (:2370) with
  `reason`/`owner` unquoted through a new `TryGetStringLiteralValue` (:6834) and named effects formatted
  through `FormatAllowValue` (:6846); (17) the BLOCK-BODIED LAMBDA — `new LambdaExpression(parameters, null,
  blockBody, line, column)` (:3675 single-param / :5533 multi-param), **retiring the LAST expression-side
  decline recorded at the end of tranche 9c**; (18) BONUS: `on` subscriptions now materialize
  `new OnSubscriptionExpression(target, handler, line, column)` (:2917), reachable only now that a block
  handler builds, over a node-returning `ParseEventTarget` (:2949/:2957).
  CONSTRUCTION-SITE INVENTORY — TRANCHE 10b: (19) FUNCTION / METHOD —
  `new FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParams, constraints,
  modifiers, attributes, isOperatorOverload, operatorSymbol, isConversionOperator, isImplicitConversion,
  line, column) { OperatorKeywordSpan, OperatorSymbolSpan, ReturnLifetime }` (:503-508), including the
  operator-overload and conversion-operator forms; (20) `ParseGenericConstraints` now RETURNS
  `List<GenericConstraint>?` (:928, null when the `where` clause is absent) and `ParseReturnLifetimeAnnotation`
  records its string (:511); (21) CONSTRUCTOR — (:1572) with the `: this(args)` / `: base(args)` initializer
  as a `new CallExpression(new ThisExpression/BaseExpression(...), arguments, null, ...)` (:1518/:1536);
  (22) PROPERTY — the expression-bodied (:1698) and get/set-accessor (:1768) forms; (23) INDEXER — (:1642);
  (24) LOCAL FUNCTION — `new LocalFunctionStatement(functionDecl, line, column)` (:2539) over the local
  function's own FunctionDeclaration (:2533); (25) the TEST-DSL family — `new TestDeclaration(description,
  body, tableParameters, tableCases, skipReason, line, column)` (:650, description/skip unquoted, an absent
  `with` leaving BOTH lists null), `new SetupDeclaration(body, …)` (:700), `new TeardownDeclaration(body, …)`
  (:715); (26) `new PreprocessorDeclaration(directive, line, column)` at BOTH the top level (:211) and the
  member level (:1432).
  FOUR RECORDED OWNER DIVERGENCES FROM Parser.cs RETIRED en route (each a real parity fix, all 440
  diagnostic contracts still green): (a) the top-level `func` declaration now routes through the SAME full
  ParseFunctionDeclaration reproduction as the member path (Parser.cs :217 and :1475 call the same
  function), replacing the Stage-3 reduced "literal-reaching vehicle" — this retires the `<error>`-name
  early return, the missing `-> T` / missing-return-type-marker arms, and the shallow
  `ParseLiteralBearing*` expression body (the malformed-literal checks still run inside
  ParsePrimaryExprValue); the five now-dead Stage-3 helpers were DELETED; (b) `ParseParameterListRecovery`
  models Parser.cs's FULL parameter grammar — the params/ref/out modifier prefix (:784-798), the `this`
  extension marker (:801), the scoped/lifetime annotation (:813), the DEFAULT value (:816) and the
  `IsParameterListRecoveryBoundary` early break (:778); (c) `ParseModifiers` no longer consumes `readonly`
  (Parser.cs's ParseModifiers has NO readonly arm and BREAKS there, leaving the token for
  ParseFieldDeclaration's property-modifier loop, which sets BOTH PropertyModifier.Readonly and
  Modifiers.Readonly, :1671) — the extra consumption was swallowing the flag on every `readonly` field in
  the corpus; (d) `ParseForeachStatement` models the optional parentheses.
  EMITTER GAPS HIT (all worked around, no kernel change): (i) `GetType()` on a typed receiver still
  declines — the receiver is cast to `object` first in `FormatAllowValue`; (ii) an explicitly-typed
  nullable NESTED-generic local (`List<List<Expression> >?`) declines — the test-table lists are bound as
  non-nullable `:=` locals with a `hasTable` branch, and the null argument goes through typed
  `NoTableParameters()` / `NoTableCases()` helpers (the established `NoTypeArguments()` idiom); (iii) NEW
  AND IMPORTANT — **`ColumnarParserRecovery` has reached the columnar front-end's per-class MEMBER
  CEILING**: adding ANY additional member function to the class makes `ParseColumnarStructInfoInto` (the
  dogfood kernel behind ColumnarProgramInputBuilder) decline the whole class with
  `NL103 … Declined at parse.struct`, regardless of that member's name, signature, or body (proven by
  bisecting to a one-line `func F(s: string): string { return s }`). Raising the ceiling means changing
  the KERNEL, which would trip the two-stage bootstrap wall, so the quote-trimming helper this tranche
  needed was INLINED at its two call sites instead. **Any future tranche that wants a new helper on this
  class must inline it or delete an existing member first.**
  DELIVERABLES: `ColumnarParserRecovery.nl` 8,614 → 9,358; `ColumnarParserAst.tests.nl` 4,004 → 5,170
  (40 new AstEq FieldNames registrations — 30 for the Statement family incl. CatchClause / SwitchCase /
  OnSubscriptionExpression, 10 for the tranche-10b declaration nodes incl. GenericConstraint — plus ~50 golden
  builders and a `RunBody`/`BodyUnit` vehicle). CONTRACTS: +82 net → **1,524 total / 1,524 PASS** (55
  tranche-10a + 27 tranche-10b, minus the 2 declines they convert: the tranche-9c block-bodied lambda and
  the tranche-4 default-valued parameter). Coverage includes 8 negative self-checks (wrong VariableKind,
  wrong block statement COUNT, swapped then/else, wrong foreach variable, wrong allow reason, wrong
  ParameterModifier, swapped get/set body, wrong test-table row) and 4 RETAINED principled declines.
  TRIANGULATION: a THROWAWAY (scratchpad) fresh-Compiler ProjectReference probe ran BOTH live Parser.cs
  (Lexer→Parser→ParseCompilationUnit) AND the owner's ParseFileAst through the identical
  `OutputFormatter.AstToJson` serializer and diffed — 99/102 synthetic statement/member shapes MATCH
  owner==Parser.cs (the 3 non-matches are the recorded synthetic-`<error>` declines pinned as contracts). **WHOLE-FILE SWEEP: 404 of the 407 in-repo `.nl` files now parse byte-exact
  owner==Parser.cs (was 26).** All THREE residuals are PRINCIPLED no-stub declines of Parser.cs RECOVERY
  ARTIFACTS, not parity gaps: (1) `ColumnarParserRecovery.nl` — an `is` pattern-variable capture with no
  same-line guard (Parser.cs :4157) swallows the NEXT line's identifier, so Parser.cs emits a synthetic
  `IdentifierExpression("<error>")` statement; (2) `TypeInfoModels.nl` and (3) `OutputFormatterJsonKernels.nl`
  — a `>>`-split nested generic (`Dictionary<string, List<TypeInfo>>?`) whose Parser.cs type node ends up
  with a MULTI-LINE span, which the recorded single-line materialization gate declines. Two further
  synthetic-`<error>` declines are pinned as contracts (`using r { }` with a missing `:=`, an `allow`
  effect value that is not an effect name) plus the conversion-operator shape where Parser.cs adds a
  spurious `<error>`-named PropertyDeclaration member.
  EVIDENCE: BootstrapServices contracts **1,524 / 1,524 PASS** via the canonical
  `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`
  (baseline re-measured at 1,442/1,442 on the same command before editing; the 3 ExternalAssemblyScan
  Debug-layout tests did NOT trip this turn — the documented `dotnet build src/NSharpLang.Cli -c Debug`
  remains the remedy after a clean `rm -rf obj bin`). dev.sh Parser slice run by this agent. Ownership
  audit: only `.nl`/`.tests.nl`/`.md` changed (2 .nl + 1 .md, **zero .cs** → OWN003 cannot trip, no C#
  growth → NO REPIN). Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers outside
  its `.tests.nl` (grep across src+editors+tests); Parser.cs stays the sole production authority. No
  LSP / VS Code / extension file touched → no reload, no VS Code gate. NO two-stage bootstrap wall
  tripped (no kernel or OpCodes change).
  NEXT (DONE — see TRANCHE 11 above): ERROR-NODE MATERIALIZATION. The decision recorded here was resolved
  as REPRODUCE-EVERY-SITE (a declining owner cannot serve the LSP on a file being edited); all three
  residuals closed, 407/407 reached, and the malformed surface proven over 11,526 sources.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHES 9b + 9c = the ARGUMENT/ELEMENT-LIST expression forms and then the LAST expression families. The
  mandate's permitted RECUT was taken and BOTH halves landed in this turn: 9b = call / with / new / tuple /
  array / immutable-array / alloc / stackalloc; 9c = match+patterns / interpolated strings / lambda literals.
  With these, the EXPRESSION SURFACE IS COMPLETE — the only expression-side decline left is the BLOCK-bodied
  lambda, which needs `BlockStatement` (the statement tranche). MECHANISM (unchanged discipline): each form
  captures its sub-part nodes BEFORE reconstructing `new ExprResult(span)` (Node null by default) and sets
  `.Node` ONLY when every present sub-part materialized; the LIST-bearing forms accumulate into a real
  `List<T>` and return `null` from the list producer when ANY element declined (the whole form then declines —
  no-stub). The Advance/Report/Consume sequence is UNTOUCHED at every site, so the 440 ColumnarParserRecovery
  stream contracts stay green.
  CONSTRUCTION-SITE INVENTORY — TRANCHE 9b (owner, each byte-exact to Parser.cs, VERIFIED owner==LIVE via the
  AstToJson probe): (1) ParseArgumentList → `List<Argument>?` (Parser.cs :4544): the recovery-boundary `break`
  is NOT a decline (Parser.cs returns the partial list there too); (2) ParseArgument → `Argument?`
  (`new Argument(argName, argValue, modifier)` :4617) covering ref (:4560) / out (:4565) / the INLINE-OUT arm
  (:4582 — a REAL `IdentifierExpression` over the second identifier alongside the NL103, so it MATERIALIZES),
  the named `name:` prefix (:4592), spread (`new SpreadExpression(spreadExpr, spreadLine, spreadColumn)` :4604),
  and the bare alloc/allow/stackalloc identifier (:4610); (3) ParseCallTypeArguments → `List<TypeReference>?`
  (:2100/:2104) through the shared ParseMaterializedTypeReference gate, split-`>>` aware; (4) CALL — `new
  CallExpression(expr, args, typeArgs, parenToken.Line, parenToken.Column)` (:4492) / `(…, null, …)` for the
  non-generic arm (:4499) / the empty-argument generic fallback (:4486); the node is anchored on the `(` while
  the ExprResult SPAN stays the CALLEE's; (5) WITH — `new PropertyInitializer(propName, null, propValue,
  propNameToken.Line, propNameToken.Column)` (:4524) + `new WithExpression(expr, props, withToken.Line,
  withToken.Column)` (:4533); ParseWithExpression now takes the receiver ExprResult; (6) NEW — `new
  NewExpression(type, args, initializer, line, column)` (:5353) and the sized-array `(…, arrayLengthExpression)`
  (:5286), with `new ArrayTypeReference(type) { Span = type.Span }` (:5253 — the wrapper KEEPS the element
  span, unlike the postfix `[]` wrapper) via a new `WrapNewArrayType`; (7) OBJECT/COLLECTION INITIALIZER — `new
  ObjectInitializerExpression(props, line, column)` (:5283/:5350) over bare-value (:5276/:5307), indexer
  (:5317) and named (:5339) PropertyInitializers; (8) TUPLE — `new TupleExpression(elements, line, column)`
  (:5449/:5483/:5497) + `new TupleElement(name, value)` (:5471/:5489), the named form reading the name off the
  first element's IdentifierExpression; (9) ARRAY — `new ArrayLiteralExpression(elements, isImmutable, line,
  column)` (:5436), `ParseArrayLiteral` gaining the `isImmutable` parameter (the `immutable` arm passes true and
  the node still anchors on the `[`); (10) ALLOC/STACKALLOC — `new AllocExpression(inner, line, column)`
  (:5196/:5199/:5202/:5205) and `new StackAllocExpression(elementType, length, line, column)` (:5217).
  CONSTRUCTION-SITE INVENTORY — TRANCHE 9c: (11) LAMBDA — `new LambdaExpression(parameters, exprBody, null,
  line, column)` (:3686 single-param / :5542 multi-param) over the implicit `new Parameter(name, new
  SimpleTypeReference("var"), null, false, Line:…, Column:…)` (:3676/:5520 — the type is POSITION-FREE, Line/
  Column 0 and an invalid Span); a BLOCK body builds a BlockStatement → declines; (12) MATCH — `new MatchCase(
  pattern, guard, caseExpr)` (:5404) + `new MatchExpression(value, cases, line, column)` (:5415); (13) the FULL
  PATTERN grammar, every tier now returning `Pattern?`: Or (:3290) / And (:3306) / Not (:3320) / Relational
  (:3340 — Operator is the RAW token TEXT) / List (:3383) / Slice (:3373 — anchored on the enclosing `[`, NOT
  its own `..`) / Positional (:3401) / Literal (:3409) / Object (:3416) / UnionCase (:3435) / Type (:3444 — a
  position-free `SimpleTypeReference`) / Identifier (:3448, qualified names dot-joined), with `ParsePropertyPatterns`
  → `List<PropertyPattern>?` (:3487 explicit / :3494 implicit-binding); the "Invalid pattern" terminal returns
  the synthetic `IdentifierPattern("<error>")` in Parser.cs → the owner declines; (14) INTERPOLATED STRING —
  `new InterpolatedStringExpression(parts, line, column, isRaw)` (:5183) over `new InterpolatedStringText(
  textBuf, textStartLine, textStartCol)` (:4988/:5122) and `new InterpolatedStringHole(expr, formatClause,
  holeLine, holeCol)` (:5163); Parser.cs's AppendText/EmitText/AdvancePosition local CLOSURES are INLINED over
  plain locals (N# has no first-class Func) — deliberately NOT parser fields, so a nested interpolated string
  inside a hole cannot clobber the outer text buffer; `ParseHoleExpression` now returns the sub-parsed
  `Expression?` and the `:format` clause is captured (:5129).
  PARITY FIX (a recorded approximation RETIRED): the owner previously "did not know the receiver's array-ness"
  and always took the object-initializer branch. Now that the `new` type materializes, `ParseObjectInitializer`
  takes Parser.cs's `type is ArrayTypeReference` COLLECTION branch (:5294) — `new T[] { a, b }` reports NOTHING
  (it previously produced two spurious missing-colon NL102s) and materializes bare-value PropertyInitializers.
  The RAW-vs-GATED type split is served by a new `ParseGatedTypeReference` + `TypeReferenceMaterialized` field
  (the decision reads the raw node exactly as Parser.cs does; the gate still decides materialization).
  CONSUMERS: the value-bearing ENUM MEMBER and the FIELD INITIALIZER (both unchanged mechanisms) plus the NEW
  attribute consumer — `ParseAttributes` now stores the materialized `List<Argument>`, so `[Attr(1)]` /
  `[Attr(x: 1)]` no longer clear `AttributesMaterializable` (the tranche-4 decline is retired).
  NO EMITTER GAP hit (the packaged SDK self-emitted every new construct — nullable GENERIC-LIST returns
  [`List<Argument>?` / `List<TypeReference>?` / `List<PropertyInitializer>?` / `List<PropertyPattern>?`] bound
  to `:=` locals and assigned into non-nullable locals after a null check, the `firstExpr.Node as
  IdentifierExpression` narrowing cast, `newType is ArrayTypeReference`, char→string concatenation, and the 20+
  node constructors; clean build 0 warnings / 0 errors). DELIVERABLES: `ColumnarParserRecovery.nl`
  8,037 → 8,601; `ColumnarParserAst.tests.nl` 2,673 → 4,004 (30 new AstEq FieldNames registrations — 11 for the
  9b list nodes/elements + 19 for lambda/match/MatchCase/the 12 Pattern types/PropertyPattern/the 3
  interpolated-string types — plus ~40 golden builders). CONTRACTS: 49 tranche-9b + 33 tranche-9c tests, minus
  the 3 declines they convert (the tranche-9a `F()` / `new T()` and the tranche-4 argument-bearing attribute)
  → +79 net → 1,438 total / 1,438 PASS. Coverage includes 7 negative self-checks (wrong Argument.Modifier,
  wrong argument-list LENGTH, wrong TupleElement name, wrong IsImmutable, wrong Pattern node TYPE, wrong
  interpolated TEXT run, wrong lambda parameter name), 2 WHOLE-FILE multi-member enums, and 1 retained decline
  (the block-bodied lambda). TRIANGULATION: a THROWAWAY (scratchpad) fresh-Compiler ProjectReference probe ran
  BOTH live Parser.cs (Lexer→Parser→ParseCompilationUnit) AND the owner's ParseFileAst through the identical
  `OutputFormatter.AstToJson` serializer and diffed — 79/80 shapes MATCH owner==Parser.cs, the sole non-match
  being the intended block-bodied-lambda decline; a WHOLE-FILE sweep over all 407 in-repo `.nl` files reports
  26 parsing byte-exact owner==Parser.cs (the rest need statement bodies / methods / properties).
  EVIDENCE: BootstrapServices contracts 1,438 total / 1,438 PASS via the canonical `dotnet test
  src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false` (the 3 ExternalAssemblyScan
  Debug-layout tests did NOT trip this turn — obj/Debug was already present; the documented fix
  `dotnet build src/NSharpLang.Cli -c Debug` remains the remedy after a clean `rm -rf obj bin`). dev.sh Parser
  slice 384/384 (run by this agent; the C# Parser.cs path is untouched). Ownership audit: only `.nl`/`.tests.nl`/
  `.md` changed (2 .nl + 1 .md, zero .cs → OWN003 cannot trip, no C# growth → no repin). Production compile
  path UNTOUCHED — `ParseFileAst` still has ZERO callers outside its `.tests.nl` (grep across src+editors+tests);
  Parser.cs stays the sole production authority. No LSP/VS Code change → no reload. NO two-stage bootstrap wall.
  Next: STATEMENT BODIES — `BlockStatement` and the whole Statement node family (variable declarations, if /
  while / for / foreach, return / print / yield / break / continue / throw, try / using / lock / switch, the
  systems statements), which unlock expression-bodied and block-bodied MEMBERS (functions, methods, properties,
  constructors, indexers, local functions) and the block-bodied lambda — the last families before a whole
  valid-or-malformed file parses into (CompilationUnit, Errors) provably equal to Parser.cs (the N+2 cutover
  prerequisite).
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 9a = the SINGLE-OPERAND / TYPE-CARRYING postfix + keyword-primary expression forms (a RECUT of the
  tranche-9 mandate: the argument/element-LIST forms — call/with/new/match/tuple/array/immutable-array/
  interpolated-string/lambda — are deferred to tranche 9b, each keeping its per-form no-stub gate). Over tranche
  8's composed operator tiers, these forms now RETURN their byte-exact Expression node as a PURE side-effect (the
  Advance/Report/Consume diagnostic sequence is UNCHANGED — the ColumnarParserRecovery.tests.nl stream contracts
  stay green). MECHANISM: each form captures its operand node(s) BEFORE reconstructing `new ExprResult(span)`
  (Node null by default) and sets `.Node` ONLY when every present operand carried a node (else declines — the
  established no-stub gate); type operands route through the shared `ParseMaterializedTypeReference` gate (the
  SAME `ParseTypeReferenceRecovery` call, so the diagnostic stream is byte-identical; it returns null on a
  structurally-unbuildable / panic / multi-line type). CONSTRUCTION-SITE INVENTORY (owner, each byte-exact to
  Parser.cs, VERIFIED owner==LIVE-Parser.cs whole-tree via the AstToJson probe): (1) MEMBER ACCESS — `new
  MemberAccessExpression(receiver, memberName, isNullConditional, dotToken.Line, dotToken.Column)` (Parser.cs
  :4453) in ParseMemberAccess, materialized ONLY in the well-formed-identifier arm (receiver.Node non-null); the
  reserved-keyword / missing-name arms build a "<error>" member in Parser.cs → the owner DECLINES them
  (synthetic-error content, the ParseRequiredExpressionAfter discipline); (2) INDEX ACCESS — `new
  IndexAccessExpression(object, index, isNullConditional, bracketToken.Line, bracketToken.Column)` (:4461) inline
  in ParsePostfix (object.Node + `ParseExprValue().Node` both non-null); both `[` and `?[` (QuestionBracket)
  forms; (3) is — `new IsExpression(expr, type, varName, isToken.Line, isToken.Column)` (:4162) in ParseRelational,
  varName captured from the optional trailing identifier (`is int x`), type via ParseMaterializedTypeReference;
  (4) as — `new CastExpression(expr, type, CastKind.Safe, asToken.Line, asToken.Column)` (:4168), the SAME
  CastExpression node as the hard cast, distinguished by Kind; (5) await/must/throw — `ParseUnaryOperandOrMissing`
  now RETURNS `Expression?` (present: `ParseUnary().Node`; missing: null — Parser.cs :3824 returns a synthetic
  IdentifierExpression("<error>"), the owner declines), the three ParseUnary arms build `new AwaitExpression/
  MustExpression/ThrowExpression(operand, kwToken.Line, kwToken.Column)` (:4390/:4400/:4410); (6) typeof/sizeof —
  `new TypeOfExpression/SizeOfExpression(type, line, column)` (:4717/:4735), type via ParseMaterializedTypeReference,
  line/column captured at ParsePrimaryExpression entry = the keyword token; (7) nameof — `new NameofExpression(
  target, line, column)` (:4726), target = `ParseExprValue().Node`; (8) checked/unchecked — `new CheckedExpression/
  UncheckedExpression(expr, line, column)` (:4745/:4755), expr = `ParseExprValue().Node`; (9) cast `(T)expr` — `new
  CastExpression(castExpr, castType, CastKind.Hard, line, column)` (:4800), castType via ParseMaterializedTypeReference
  + castExpr = `ParseUnary().Node`, anchored on the `(`; (10) spread `...expr` — `new SpreadExpression(spreadExpr,
  line, column)` (:4814), anchored on the `...`. NO NEW GATE FIELDS (each form gates inline on its operand nodes).
  CONSUMERS: the value-bearing ENUM MEMBER (`A = <expr>` → EnumMember.Value, tranche-7 mechanism, NO code change)
  and the FIELD INITIALIZER (`X := <expr>` / `X: T = <expr>` → FieldDeclaration.Initializer, tranche-8 mechanism);
  a form that materializes flows straight through, a still-deferred form (tranche 9b) leaves Node null → the
  consumer declines. FORMS DECLINING (recorded, per-form no-stub, deferred to TRANCHE 9b): postfix CALL `f(…)` /
  generic-call `M<T>(…)` (CallExpression — needs the owned argument-list node materialization), `with {…}`
  (WithExpression — needs property-init nodes), and the non-leaf list primaries new / match / tuple / array /
  immutable-array / interpolated-string / lambda / alloc / stackalloc. NO EMITTER GAP hit (the packaged SDK
  self-emitted every new construct — the nullable Expression? locals, the ParseUnaryOperandOrMissing return-type
  change, the 13 node constructors, the CastKind enum arg; clean build 0 warnings/0 errors). DELIVERABLES:
  `ColumnarParserRecovery.nl` 7,946 → 8,037 (+155/−43): the is/as materialization in ParseRelational,
  ParseUnaryOperandOrMissing → Expression? + the three await/must/throw arms, ParseMemberAccess materialization,
  the ParsePostfix index arm, and the typeof/nameof/sizeof/checked/unchecked/cast/spread arms in ParsePrimaryExprValue;
  `ColumnarParserAst.tests.nl` 2,293 → 2,673 (+402/−43): 13 new AstEq FieldNames registrations (MemberAccess/
  IndexAccess/Is/Cast/Await/Must/Throw/TypeOf/Nameof/SizeOf/Checked/Unchecked/Spread) + 13 golden builders + 25
  net contracts (2 tranche-8 is/member declines CONVERTED to positives). CONTRACTS (all AstEq owner==golden, every
  golden position/Span TRIANGULATED against LIVE Parser.cs via the AstToJson oracle): 20 postfix/keyword positives
  (member, null-conditional member, member chain, index, null-conditional index, index-over-member, is + is-pattern-
  variable + is-generic-type, as, await, must, throw, typeof, nameof, sizeof, checked, unchecked, hard-cast, spread),
  3 field-initializer (`:=` member-access, typed `= ` is-expression, `:=` typeof), 1 WHOLE-FILE 3-member enum
  mixing member-access / is-type / typeof values (comma-separated, each member a distinct node type), 2 retained-gate
  declines (call `F()`, new `T()` — tranche-9b forms), and 3 negative self-checks (wrong member name; wrong
  IsNullConditional flag; wrong node TYPE Is-vs-TypeOf). TRIANGULATION: a THROWAWAY (scratchpad) fresh-Compiler
  ProjectReference probe ran BOTH live Parser.cs (Lexer→Parser→ParseCompilationUnit) AND the owner's ParseFileAst
  through the identical `OutputFormatter.AstToJson` serializer and diffed — 24/24 synthetic + field-init + whole-file
  shapes MATCH owner==Parser.cs (0 mismatches); the 2 tranche-9b forms (F() / new T()) correctly show live-
  materializes-vs-owner-declines (the intended no-stub deferral, the strongest owner==Parser.cs proof). EVIDENCE:
  BootstrapServices contracts 1,359 total / 1,359 PASS via the canonical `dotnet test src/NSharpLang.Compiler.
  BootstrapServices -c Release -p:NSharpExcludeTests=false` (baseline 1,334 + 25 net; all 25 net-new green). NOTE:
  a clean `rm -rf obj bin` rebuild wipes obj/Debug → the 3 PRE-EXISTING ExternalAssemblyScan.tests.nl Debug-layout
  tests trip; the documented Debug CLI rebuild (`dotnet build src/NSharpLang.Cli -c Debug`) restores full green
  (coordinator-confirmed 1,359/1,359 — the known fix, not a regression). dev.sh Parser slice: NOT run by this
  agent (coordinator to run; the C# Parser.cs path is untouched so 384/384 is expected). Ownership audit: only
  `.nl`/`.tests.nl`/`.md` changed (2 .nl + 1 .md, zero .cs → OWN003 cannot trip, no C# growth → no repin).
  Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers outside its `.tests.nl` (grep across
  src+editors+tests); Parser.cs stays the sole production authority. No LSP/VS Code change → no reload. NO two-stage
  bootstrap wall (the packaged SDK self-emitted every new construct — no planner/kernel/OpCode change). Next:
  TRANCHE 9b — the ARGUMENT/ELEMENT-LIST expression forms: postfix CALL (CallExpression, via the owned
  ParseArgumentList materializing `List<Argument>` incl. named/spread/ref-out forms) + generic-call type args,
  `with` (WithExpression + property inits), and the non-leaf list primaries new (object/collection/sized-array
  initializer), match (MatchExpression + arms + the owned Pattern grammar), tuple, array/immutable-array,
  interpolated-string (parts from the owned hole grammar), and lambda; then expression-bodied members + statement
  bodies (BlockStatement), until a whole valid-or-malformed file parses into (CompilationUnit, Errors) provably
  equal to Parser.cs (the N+2 cutover prerequisite).
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 8 = the COMPOSED OPERATOR TIERS. Over tranche 7's leaf/primary nodes, the operator-composing expression
  tiers now RETURN their byte-exact Expression node as a PURE side-effect (the Advance/Report/Consume diagnostic
  sequence is UNCHANGED, so the diagnostic stream is unperturbed — the ColumnarParserRecovery.tests.nl stream
  contracts stay green). MECHANISM: each tier captures leftNode := result.Node BEFORE overwriting result,
  captures the right operand's node from the recursive parse, reconstructs `new ExprResult(span)` (Node null by
  default), and sets `.Node` ONLY when all operands carry nodes (a shared `ComposeBinary` helper for the binary
  tiers; inline gates for unary/ternary/assignment/range) — a missing/deferred operand leaves Node null → the
  whole expression declines (the established no-stub gate). A left-associative chain nests naturally (iteration N's
  node becomes iteration N+1's left node). CONSTRUCTION-SITE INVENTORY (owner, each byte-exact to Parser.cs,
  VERIFIED owner==LIVE-Parser.cs whole-tree via the AstToJson probe): (1) BINARY — every tier `new
  BinaryExpression(left, op, right, opToken.Line, opToken.Column)` anchored on the OPERATOR token (NOT the left
  operand): NullCoalesce (:4052), Or (:4066), And (:4080), BitwiseOr (:4094), BitwiseXor (:4108), BitwiseAnd
  (:4122), Equal/NotEqual (:4137, op from opToken.Type), the four comparisons Less/LessOrEqual/Greater/
  GreaterOrEqual (:4209, via RelationalComparisonOp), LeftShift/RightShift (:4225), Add/Subtract (:4240),
  Multiply/Divide/Modulo (:4285); (2) RANGE — `new RangeExpression(start?, end?, opToken.Line, opToken.Column)`
  (:4305/:4321), Start/End legitimately nullable (open ranges) so the gate is "every PRESENT operand carried a
  node" (`..` always materializes; `..end`/`start..end` need their present operands); (3) UNARY prefix — `new
  UnaryExpression(op, operand, opToken.Line, opToken.Column)` (:4380) via PrefixUnaryOp (Minus→Negate, Not→Not,
  BitwiseNot→BitwiseNot, Increment→PreIncrement, Decrement→PreDecrement, BitwiseXor→IndexFromEnd); postfix `++`/
  `--` `new UnaryExpression(PostIncrement/PostDecrement, operand, opToken.Line, opToken.Column)` (:4504/:4509); (4)
  TERNARY — `new TernaryExpression(cond, then, else, questionToken.Line, questionToken.Column)` (:4038), then/else
  captured from ParseRequiredExpressionAfter, materialized when cond+then+else all non-null; (5) ASSIGNMENT — `new
  AssignmentExpression(target, op, value, opToken.Line, opToken.Column)` (:3752) via AssignmentOpFor (Assign,
  PlusAssign→AddAssign, MinusAssign→SubtractAssign, StarAssign→MultiplyAssign, SlashAssign→DivideAssign,
  QuestionQuestionAssign→NullCoalesceAssign). `ParseRequiredExpressionAfter` now RETURNS `Expression?` (present:
  ParseExprValue().Node; missing: null — Parser.cs returns a synthetic IdentifierExpression("<error>"), the owner
  declines no-stub); its ~15 statement-context callers ignore the return (a value-returning func is callable as a
  statement, as ParseExprValue already is), so the diagnostic behavior is unchanged. CONSUMERS UNLOCKED: (a)
  richer valued ENUM MEMBERS — the existing ParseEnumBody `ParseExprValue().Node` capture now materializes
  composed values (`A = 1 << 4`, `A = a ? b : c`, …) with NO code change; (b) FIELD INITIALIZERS — ParseFieldMember
  materializes `FieldDeclaration.Initializer` for both `X: Type = <expr>` (Parser.cs :1782) and `X := <expr>`
  (:1686, null Type), gated the same as the tranche-3 initializer-free field (Modifiers.None / no property
  modifier / non-null simple type). TIERS DECLINING (recorded, per-tier no-stub, deferred to TRANCHE 9): is/as
  (IsExpression/CastExpression — separate nodes), await/must/throw, the non-leaf primaries (typeof/nameof/new/
  match/cast/array/tuple/…), and postfix call/index/member/with (CallExpression/IndexAccess/MemberAccess/
  WithExpression) — each leaves Node null so its enum/field consumer declines. NO EMITTER GAP hit (the packaged
  SDK self-emitted every new construct — nullable Expression? locals, the op-mapping helpers, the composed
  constructors, the ParseRequiredExpressionAfter return-type change, the field-init materialization; clean build 0
  warnings/0 errors). DELIVERABLES: `ColumnarParserRecovery.nl` 7,731 → 7,946 (the ComposeBinary/PrefixUnaryOp/
  AssignmentOpFor/RelationalComparisonOp helpers, the 11 binary/range/unary/postfix/ternary/assignment
  materialization sites, ParseRequiredExpressionAfter → Expression?, the two field-initializer sites);
  `ColumnarParserAst.tests.nl` 1,878 → 2,293 (5 FieldNames registrations [Binary/Unary/Ternary/Assignment/Range];
  the Bin/Un/Tern/Assign/Rng + AddFieldInit/AddFieldInfer golden builders; +37 contracts). CONTRACTS (all AstEq
  owner==golden, every golden position/operator TRIANGULATED against LIVE Parser.cs via the AstToJson oracle):
  13 binary-op positives (add/mul/sub/shl/shr/bor/band/bxor/eq/neq/lt/le/ge), 3 logical (and/or/coalesce), 2
  composition (precedence bottom-up 1+2*3, left-assoc 1+2+3), 3 unary (negate/not/bitwise-not), 1 ternary, 2 range
  (a..b two-operand, ..b open-start), 2 assignment (=, +=), 1 parenthesized-COMPOSED (paren now wraps a
  BinaryExpression, vs tranche-7 leaf-only), 2 negative self-checks (wrong BinaryOperator Add-vs-Subtract; wrong
  composed NODE TYPE Binary-vs-Unary), 3 field-initializer (literal `X: int = 5`, composed `X: int = 1 + 2`,
  inference `X := 5`), 1 WHOLE-FILE field-only struct (namespace + `struct Config` with literal + computed
  initializers — every member materializes), and 4 retained-gate declines (call `F()`, `a is int`, `new T()`,
  `a.b` — the tranche-9 tiers). TRIANGULATION: a THROWAWAY (deleted) fresh-Compiler ProjectReference probe ran
  BOTH live Parser.cs (Lexer→Parser→ParseCompilationUnit) AND the owner's ParseFileAst through the identical
  `OutputFormatter.AstToJson` serializer and diffed — 34/34 synthetic + whole-file shapes MATCH owner==Parser.cs
  (0 mismatches). EVIDENCE: BootstrapServices contracts 1334 total / 1331 PASS via the canonical `dotnet test
  src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false` (fresh CLEAN `rm -rf obj bin`
  rebuild, 0 warnings/0 errors — no emit gap). The ONLY 3 failures are the PRE-EXISTING ExternalAssemblyScan.tests.nl
  Debug-path infra tests (they `assert File.Exists(obj/Debug/net10.0/refint/…dll)` + walk a Debug directory layout,
  but the canonical command builds `-c Release` → the Debug reference assembly is absent, plus the Release refint
  DLL has no extractable MVID); VERIFIED identical 3/3 failures on the STASHED baseline (owner reverted to
  e5324b24e, zero tranche-8 code) with the same `-c Release` filter → they are environment/config artifacts
  INDEPENDENT of this change, not a regression. All 37 tranche-8 tests green; the tranche-1..7 AST-materialization
  suite unchanged-green. dev.sh Parser slice 384/384 (the C# Parser.cs path is untouched). Ownership audit: only
  `.nl`/`.tests.nl`/`.md` changed (2 .nl + 1 .md, zero .cs → OWN003 cannot trip, no C# growth → no repin).
  Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers outside its `.tests.nl` (grep across
  src+editors+tests); Parser.cs stays the sole production authority. No LSP/VS Code change → no reload. NO
  two-stage bootstrap wall (the packaged SDK self-emitted every new construct — no planner/kernel/OpCode change).
  Next: TRANCHE 9 — the STILL-deferred expression sub-grammars: is/as (IsExpression/CastExpression), await/must/
  throw, the non-leaf primaries (typeof/nameof/sizeof/checked/unchecked/new/match/cast/array/immutable-array/
  tuple/spread/interpolated-string/lambda), and postfix call/index/member/with (CallExpression/IndexAccess/
  MemberAccess/WithExpression), then expression-bodied members + statement bodies (BlockStatement), until a whole
  valid-or-malformed file parses into (CompilationUnit, Errors) provably equal to Parser.cs (the N+2 cutover
  prerequisite).
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 7 = BEGIN EXPRESSION MATERIALIZATION — the LEAF/PRIMARY tier. The stage-6/7 expression ladder (which
  already parses the full 14-tier precedence grammar for diagnostics) now RETURNS the byte-exact Expression
  node for the LEAF ATOMS + the single-expression PARENTHESIZED form, as a PURE side-effect: the
  Advance/Report/Consume sequence is UNCHANGED, so the diagnostic stream is unperturbed. MECHANISM: `ExprResult`
  gains a mutable nullable `Node: Expression?` (default null); the ladder's non-operator tiers `return result`/
  `return expr` UNCHANGED, so a leaf node set by the primary tier PROPAGATES UP automatically, while every
  operator-composing tier reconstructs `new ExprResult(...)` (Node null) → a value that composes ANY operator
  declines. No touch to the ~30 existing `new ExprResult` call sites (the field defaults null; materialization
  sites set `.Node`). CONSTRUCTION-SITE INVENTORY (owner, each byte-exact to Parser.cs, VERIFIED owner==LIVE-
  Parser.cs whole-tree via the AstToJson serializer): (1) INT/FLOAT `new IntLiteralExpression(token.Value, line,
  column)` / FloatLiteral (Parser.cs :4649/:4652 — line/column captured at ParsePrimaryExpression entry = the
  value token); (2) CHAR `new CharLiteralExpression(token.Value, line, column)` (:4658 — built regardless of the
  malformed diagnostic, quotes included in Value); (3) STRING `new StringLiteralExpression(token.Value, line,
  column)` for a plain StringLiteral or TripleQuoteStringLiteral (:4669, quotes included) — the `$"`-interpolated
  + raw-interpolated forms route to ParseInterpolatedString and DECLINE (Node null, later tranche); (4) BOOL
  `new BoolLiteralExpression(true/false, line, column)` (:4675/:4681); (5) NULL `new NullLiteralExpression(line,
  column)` (:4687); (6) DEFAULT/THIS/BASE `new DefaultExpression/ThisExpression/BaseExpression(line, column)`
  (:4694/:4701/:4707); (7) IDENTIFIER `new IdentifierExpression(name, line, column)` (:4821, IsBareIdentifier
  retained); (8) PARENTHESIZED `new ParenthesizedExpression(firstExpr, line, column)` for the single-expression
  `(e)` form (:5502, line/column on the `(`) — materialized ONLY when the inner expr itself materialized (a
  composed/deferred inner leaves firstExpr.Node null → the paren declines too); the empty/recovered/tuple
  paren forms decline. CONSUMER UNLOCKED: VALUE-BEARING ENUM MEMBERS — `ParseEnumBody` now captures
  `ParseExprValue().Node` into `EnumMember.Value` (Parser.cs :1301/:1310); a value that MATERIALIZES no longer
  clears `TypeBodyMaterializable`, a value that FAILS to materialize (a composed/deferred form) still does →
  the enum declines. STRING-VALUE INFERENCE REPLICATED (Parser.cs :1304): a new `EnumBodyInferredString` gate,
  set by ParseEnumBody when the FIRST member's value is a StringLiteralExpression, is applied by ParseEnumName
  only when there is NO explicit `: int|string` backing type (`hasExplicitType` tracked) → `enum E { A = "x" }`
  infers EnumType.String byte-exact, while `enum E: int { A = "x" }` stays Int. TIERS MATERIALIZED: the leaf/
  primary atoms + single-expr parenthesized. TIERS DECLINING (recorded, per-tier no-stub, deferred to tranche
  8): the whole composed ladder (binary/unary/ternary/coalescing/assignment/postfix — call/index/member/`with`/
  `++`/`--`) and the non-leaf primaries (typeof/nameof/sizeof/checked/unchecked/alloc/stackalloc/new/match/
  array/immutable-array/cast/tuple/spread/interpolated-string/lambda) — each leaves Node null so its enum/field
  consumer declines. FIELD INITIALIZERS deferred to tranche 8 (the field `= <expr>` site still declines). NO
  EMITTER GAP hit — the packaged SDK self-emitted every new construct (the mutable nullable field, the `is
  StringLiteralExpression` type-test, the value-returning leaf golden builders); no reused workaround needed.
  DELIVERABLES: `ColumnarParserRecovery.nl` 7,654 → 7,731: `ExprResult.Node` field + init; the 8 leaf/paren
  materialization sites in ParsePrimaryExprValue / ParseTupleOrParenthesizedExpression; ParseEnumBody value
  capture + string-inference set; ParseEnumName `hasExplicitType` + inference apply; the `EnumBodyInferredString`
  field. `ColumnarParserAst.tests.nl` 1,538 → 1,878: 11 new AstEq FieldNames registrations (Int/Float/Char/
  String/Bool/Null/Identifier/Default/This/Base/Parenthesized LiteralExpression) + 11 value-returning leaf
  golden builders (IntLit/FloatLit/CharLit/StrLit/BoolLit/NullLit/Ident/DefaultE/ThisE/BaseE/Paren) + the
  AddEMemV value-bearing enum-member builder + 20 new contracts (the tranche-6 "value-bearing enum member
  DECLINES" test CONVERTED to the positive int materialization → +19 net). CONTRACTS (all AstEq owner==golden,
  every golden position/Value TRIANGULATED against LIVE Parser.cs via the AstToJson oracle): 14 leaf/paren
  positive shapes (int, mixed valued/valueless, float, char, string+inference, explicit-int-not-overridden,
  true, false, null, identifier, default, this, base, parenthesized-wrapping-inner), 2 negative self-checks (a
  wrong literal Value; a wrong value NODE TYPE — Int golden vs Identifier actual), 3 retained-gate declines (a
  binary `1 + 2` / unary `-1` / call `F()` composed value declines the enum, no-stub), and 1 WHOLE-FILE real-
  corpus equality on DeclarationEnums.nl (5 public enums — ParameterModifier/EnumType valueless,
  SpecialConstraintKind/PropertyModifier/Modifiers with 26 int-literal-valued members total, every
  EnumMember.Value an IntLiteralExpression). TRIANGULATION MECHANISM: a THROWAWAY (deleted) fresh-Compiler
  ProjectReference probe ran BOTH live Parser.cs (Lexer→Parser→ParseCompilationUnit) AND the owner's
  ParseFileAst through the identical `OutputFormatter.AstToJson` serializer and diffed — 14/14 leaf/paren
  synthetic sources whole-tree MATCH + WHOLE-FILE DeclarationEnums.nl MATCH; the 3 composed forms show LIVE
  Parser.cs materializing (Binary/Unary/CallExpression) vs OWNER declining (empty declarations) — exactly the
  intended no-stub deferral, the strongest owner==Parser.cs proof. EVIDENCE: BootstrapServices contracts
  1300/1300 (1281 tranche-6 baseline + 19; fresh CLEAN `rm -rf obj bin` + `dotnet build
  -p:NSharpExcludeTests=false` [0 warnings/0 errors — no emit gap]). NOTE: this environment's vstest testhost
  fails to load `Microsoft.TestPlatform.CoreUtilities` (a stale SDK-copied testhost DLL, an ENV issue
  independent of the change), and `nlc test` trips on PRE-EXISTING NL011/NL012 lint errors in CodeFix.nl /
  ColumnarTypeOfPlanner.nl (not this slice's files); so the 1300/1300 count was gathered by a THROWAWAY
  reflection runner that loads the emitted test assembly and invokes every `[Fact]` in-process (matched 1300,
  PASS 1300, FAIL 0 — the 19 tranche-7 `Test_016N1cTranche7*` methods all confirmed present + green). The
  diagnostic-stream tests (ColumnarParserRecovery.tests.nl) UNCHANGED-green prove the Node-returning refactor
  does NOT perturb the diagnostic stream; dev.sh Parser slice 384/384 (0 failures — the C# Parser.cs path is
  untouched); ownership audit: only `.nl`/`.tests.nl`/`.md` changed (2 .nl + 1 .md, zero .cs → OWN003 cannot
  trip, no C# growth → no repin). Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers
  outside its `.tests.nl` (grep across src+editors+tests); Parser.cs stays the sole production authority. No
  LSP/VS Code change → no reload. NO two-stage bootstrap wall (the packaged SDK self-emitted every new
  construct — no planner/kernel/OpCode change). Next: TRANCHE 8 — the BINARY + UNARY tiers (the TokenType→
  BinaryOperator / UnaryOperator mappings, byte-exact to Parser.cs), then ternary/coalescing/assignment/range,
  then the postfix + non-leaf-primary sub-grammars, then FIELD INITIALIZERS + expression-bodied members, until
  a whole valid-or-malformed file parses into (CompilationUnit, Errors) provably equal to Parser.cs (the N+2
  cutover prerequisite).
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 6 = TYPE-PARAMETER LISTS + BASE/INTERFACE LISTS + the remaining TYPE BODIES (union cases + payloads,
  enum members, soa columns, type-alias/newtype underlying type). The `hasTypeParams` and `hasBaseList` gates
  are now RELAXED; a generic and/or based/interfaced declaration NO LONGER declines. CONSTRUCTION-SITE
  INVENTORY (owner, each byte-exact to Parser.cs, VERIFIED owner==LIVE-Parser.cs whole-tree via the AstToJson
  serializer on 24 shapes): (1) TYPE-PARAMETER LISTS — `ParseTypeParameters` now RETURNS `List<TypeParameter>?`
  (null when no `<`, else one `new TypeParameter(name)` per param, name = the lifetime token value or the
  ConsumeIdentifier result — Parser.cs :736/:755), threaded into class/struct/record/interface/union; a
  malformed list (`<>`/`<T,>`/reserved-keyword name — a diagnostic fires) or an in-panic parse clears the new
  `TypeParamsMaterializable` gate → the declaration declines. (2) BASE/INTERFACE LISTS — `ParseBaseTypeList`
  now RETURNS `List<TypeReference>` through the shared ParseMaterializedTypeReference gate (each base type the
  full stage-15 grammar), and the CALLER applies the class-vs-others DISPATCH byte-exact to Parser.cs: a class
  splits [0]→BaseClass, [1..]→Interfaces (Parser.cs :977-978, the NL010-era single-colon-to-BaseClass finding);
  struct/record take the whole list as Interfaces (:1008/:1053); interface takes it as BaseInterfaces (:1160).
  A structurally-unbuildable / multi-line base type clears the new `BaseListMaterializable` gate → decline.
  (3) UNION BODIES — `ParseUnionBody` now RETURNS `List<UnionCase>` (each `new UnionCase(name, properties,
  line, column)`, Parser.cs :1223; payloads `new UnionCaseProperty(name, type)` :1212 with the type through the
  materialization gate; NEWLINE-separated cases — the comma-separated form yields `<error>` cases in Parser.cs,
  so the owner correctly declines it), and ParseUnionName (now threaded modifiers/attributes) materializes the
  UnionDeclaration. (4) ENUM MEMBERS — `ParseEnumBody` now RETURNS `List<EnumMember>` (each `new EnumMember(
  name, null, line, column)`, Parser.cs :1310); VALUELESS members materialize byte-exact, a VALUE-bearing
  member `A = 1` clears the shared `TypeBodyMaterializable` gate (the Value is an Expression, a later tranche)
  → the enum declines (the tranche-1..5 empty-members placeholder is REPLACED by the real list). (5) SOA
  BODIES — `ParseSoaRecordBody` now RETURNS `List<SoaColumnDeclaration>` (:1108), and ParseSoaRecordName (now
  threaded modifiers/attributes) materializes the SoaRecordDeclaration; a generic soa is the error shape →
  decline. (6) TYPE-ALIAS / NEWTYPE — ParseTypeAliasName captures the name + routes the `= <type>` underlying
  type through the materialization gate, materializing TypeAliasDeclaration (Parser.cs :1361, FQN'd — a
  TestStubs `class TypeAliasDeclaration` twin) or NewtypeDeclaration (:1356) for the `newtype` variant; these
  carry NO modifiers/attributes (the model has no such fields), byte-exact. NEW GATE FIELDS (transient no-stub,
  captured by the caller into a local IMMEDIATELY before ParseTypeBody, whose nested decls overwrite them):
  `TypeParamsMaterializable`, `BaseListMaterializable`, `TypeBodyMaterializable`. GATES RELAXED: `hasTypeParams`
  (generic type-param list ON the declaration) and `hasBaseList` (base/interface list). GATES RETAINED (still
  decline, unchanged): a parameter DEFAULT `=`, a per-parameter attribute, an argument-bearing attribute, field
  property-modifiers/initializers/accessors, and EVERYTHING BODY-SHAPED (function/property/method/constructor
  bodies — BlockStatement/Expression materialization, a later tranche); a VALUE-bearing enum member (Expression
  Value). NO EMITTER GAP hit — the packaged SDK self-emitted every new construct (the node constructors, the
  nullable-list-local avoidance via inline `null` at the UnionCase/EnumMember construction sites, the
  List<X>-returning body functions); the ONLY reused workaround is inlining `null` for the absent
  Properties/Value rather than a `List<T>?` local. DELIVERABLES: `ColumnarParserRecovery.nl` 7,473 → 7,654
  (+270/−89): ParseTypeParameters/ParseBaseTypeList/ParseUnionBody/ParseEnumBody/ParseSoaRecordBody rewritten to
  return their lists + set gates, the 6 declaration sites (class/struct/record/interface/union/soa) threaded,
  ParseTypeAliasName materialized, ParseUnionName/ParseSoaRecordName given modifiers/attributes params + the 4
  dispatch call sites updated, 3 new gate fields. `ColumnarParserAst.tests.nl` 1,074 → 1,538 (+466/−2): 9 new
  AstEq FieldNames registrations (TypeParameter/UnionDeclaration/UnionCase/UnionCaseProperty/SoaRecordDeclaration/
  SoaColumnDeclaration/EnumMember/TypeAliasDeclaration/NewtypeDeclaration) + 18 golden builders + 30 new
  contracts (the tranche-4 "generic type-param list DECLINES" test CONVERTED to a positive materialization →
  +26 net). CONTRACTS (all AstEq owner==golden, every golden Span/position TRIANGULATED against LIVE Parser.cs
  via the AstToJson oracle): 4 base/interface shapes (class base, class base+interface split, struct interface,
  interface base), 5 type-param shapes (generic class, two-param generic struct, generic record + T-typed param,
  generic record + interface list, public generic class + base + interface), the converted generic-record
  positive, 3 union shapes (bare newline-separated cases, single payload, multi-property mixed-case), 2 enum
  shapes (valueless int members, valueless string-backed members), 1 soa shape, 4 type-alias/newtype shapes
  (simple, union, generic underlying, newtype), 3 WHOLE-FILE real-corpus equalities (ErrorSeverity.nl +
  DiagnosticSeverity.nl — public valueless enums, the DIRECT tranche-6 enum-member unlock; CodeIntelligence-
  CallGraphModels.nl — two public records with generic/nullable primary-ctor param types + import), 3 negative
  self-checks (mismatched type-param name / union-case name / base-class name — guarding the new recursion
  paths against a vacuous pass), and 1 retained-gate decline (a value-bearing enum member declines). TRIANGULATION
  MECHANISM: a THROWAWAY (deleted) fresh-Compiler ProjectReference probe ran BOTH live Parser.cs AND the owner's
  ParseFileAst through the identical `OutputFormatter.AstToJson` serializer and diffed the JSON — 24/24 whole-tree
  MATCH (21 synthetic + 3 whole-file), the strongest owner==Parser.cs proof. EVIDENCE: BootstrapServices
  contracts 1281/1281 (1255 tranche-5 baseline + 26; fresh CLEAN `rm -rf obj bin` + `dotnet test
  -p:NSharpExcludeTests=false`); the diagnostic-stream tests (ColumnarParserRecovery.tests.nl) UNCHANGED-green
  prove the list-returning body/type-param/base-list refactor still does NOT perturb the diagnostic stream;
  dev.sh Parser slice 384/384 (0 failures — the C# Parser.cs path is untouched); ownership audit: only
  `.nl`/`.tests.nl`/`.md` changed (the 3 changed files are absent from the non-nsharp-growth ratchet manifest) →
  no ownership repin. Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers outside its
  `.tests.nl` (grep across src+editors+tests); Parser.cs stays the sole production authority. No LSP/VS Code
  change → no reload. NO two-stage bootstrap wall (the packaged SDK self-emitted every new construct — no
  planner/kernel/OpCode change). Next: TRANCHE 7 — the STATEMENT + EXPRESSION + PATTERN families that unblock
  function/property/method/constructor bodies (BlockStatement/Expression materialization) and value-bearing enum
  members, then field property-modifiers/initializers/accessors + argument-bearing attributes + parameter
  defaults, until a whole valid-or-malformed file parses into (CompilationUnit, Errors) provably equal to
  Parser.cs (the N+2 cutover prerequisite).
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 5 = the RICHER TypeReference node family. The owner's already-full-diagnostic-parity stage-15 type
  grammar (ParseTypeReferenceRecovery → Postfix → Base → Tuple / Func) now RETURNS the byte-exact
  TypeReference node it parses (or null for a structurally-unbuildable sub-part) as a PURE side-effect — the
  Advance/Report/Consume sequence is UNCHANGED, so the diagnostic stream (1238 baseline) is unperturbed. The
  ~30 diagnostic-only callers discard the returned node; the field/parameter sites capture it. TYPE-REFERENCE
  CONSTRUCTION-SITE INVENTORY (owner, each byte-exact to Parser.cs, VERIFIED owner==LIVE-Parser.cs whole-tree
  via the AstToJson serializer on 15 shapes): (1) SimpleTypeReference incl. the QUALIFIED dotted-name form
  `A.B.C` (Parser.cs :1959 — name = dot-joined via the `while Check(Dot)` loop, Line/Column = first id token,
  Span = SpanFromTokens(typeNameToken, lastNameToken) where lastNameToken is the LAST id, captured as Current
  BEFORE each ConsumeIdentifier per :1921); (2) GenericTypeReference `List<T>` (Parser.cs :1951 — the 4-arg
  ctor sets Line/Column = typeNameToken, Span = SpanFromTokens(typeNameToken, greater)); NESTED `List<List<T>>`
  works via the SPLIT-`>>` discipline — ConsumeGreater splits a `>>` into a virtual `>` at rightShift.Column
  and the enclosing close consumes an owed `>` at prev.Column+1, both byte-identical to Parser.cs, so the two
  generic spans end at rightShift.Column+1 / rightShift.Column+2 EXACTLY (verified `[2,13..22]` / `[2,8..23]`
  vs oracle); (3) ArrayTypeReference `T[]` (Parser.cs :1825, Span = ExtendSpan(base, rightBracket)); (4)
  NullableTypeReference `T?` (Parser.cs :1857, Span = ExtendSpan(base, question)) AND the `T?[]` half whose
  span ends at questionBracket.Column+1 (Parser.cs :1835-1844 — NOT token-length-extended, a distinct span
  rule); (5) TupleTypeReference `(a: T, b: U)` (Parser.cs :1994, named/unnamed elements) PLUS the single-
  UNNAMED-element UNWRAP (Parser.cs :1988-1992 — returns the inner type with its Span RESET to the whole
  paren extent but Line/Column left on the inner name token); (6) FunctionTypeReference `Func<…>` (Parser.cs
  :2017 — the LAST parsed type is ReturnType, the preceding ones ParameterTypes); (7) UnionTypeReference
  `A | B` (Parser.cs :1808, Span = ExtendSpan(first, lastToken=Previous)); (8) ByRefTypeReference `&T`
  (Parser.cs :1890, Span from the ampersand through inner.Span.EndColumn, else FromStartAndLength(amp,1)).
  SPAN IDIOM: SourceSpan's only multi-arg factory is the single-line FromStartAndLength, so two helpers
  (SpanFromTokensSingleLine / ExtendSpanFromNode) reproduce Parser.cs's SpanFromTokens/ExtendSpan for a
  SINGLE-LINE span (the corpus shape), and the materialization gate defers any multi-line type. MATERIALIZATION
  GATE (ParseMaterializedTypeReference, at the field + parameter sites): returns the node only when the parse
  produced NO diagnostic (well-formed), did not ENTER in panic, and was SINGLE-LINE; else null → the caller
  declines (no-stub). This is the RELAXATION: `ParseFieldTypeReference`/`ParseParameterTypeReference` no longer
  restrict to the single-token simple type — every richer WELL-FORMED form now materializes, so a richer
  field/param type NO LONGER declines its declaration (the existing `fieldType != null` / `paramType != null`
  checks do the relaxation automatically once the grammar returns richer nodes). GATES RETAINED (still-deferred
  families, unchanged): `hasTypeParams` (a generic type-parameter list ON the declaration, `record R<T>(…)`),
  `hasBaseList` (a base/interface list `class C: Base`), a parameter DEFAULT `=`, a per-parameter attribute, an
  argument-bearing attribute, and field property-modifiers/initializers/accessors — each still DECLINES.
  EMITTER GAP FOUND + WORKED AROUND (surfaced by a fresh-Compiler ProjectReference emit probe): a property
  assignment through a list-index + property chain (`elements[0].Type.Span = …`, the tuple single-unnamed
  unwrap) declines the columnar backend (NL103 emit.statement.block-child node-kind-23) — resolved by binding
  the element + its inner type to LOCALS first (`onlyElement := elements[0]; innerType := onlyElement.Type;
  innerType.Span = …`), byte-identical. DELIVERABLES: `ColumnarParserRecovery.nl` 7,270 → 7,473 (+267/−64):
  the 2 span helpers + ParseMaterializedTypeReference gate + the 5 grammar functions rewritten to return
  TypeReference? + the ByRef/Array/Nullable/`?[`-Nullable wrapper helpers + the 2 field/param site rewrites.
  `ColumnarParserAst.tests.nl` 719 → 1,074 (+363/−8): 8 new AstEq FieldNames registrations (Generic/Array/
  Nullable/Tuple/TupleTypeElement/Function/Union/ByRef) + 11 golden type-ref builders (SpanOf/SimpleT/
  SimpleTSpan/GenericT/ArrayT/NullableT/ByRefT/UnionT/FuncT/TupleElem/TupleT + AddFieldT/AddParamT); +17
  contracts (net; one tranche-4 decline test converted to positive). CONTRACTS (all AstEq owner==golden, every
  golden Span TRIANGULATED against LIVE Parser.cs via the AstToJson oracle): 11 synthetic field shapes (generic,
  qualified-dotted, nullable, array, nested-generic split-`>>`, named tuple, single-unnamed-tuple unwrap,
  union, Func, byref, nullable-array), a two-richer-field class, the tranche-4 "generic param type DECLINES"
  test CONVERTED to a positive materialization, 3 WHOLE-FILE real-corpus equalities on in-repo pure-data files
  that carry richer param types (CodeIntelligenceParameterResult.nl [nullable `string?`],
  DocCommandModels.nl [generic `IReadOnlyList<DocPage>`, 2 records + a namespace import],
  CodeIntelligenceImplementorModels.nl [nullable + generic `List<ImplementorResult>`, 2 records + import]) —
  each triangulated so owner == golden == Parser.cs, and 2 NEW negative self-checks (a wrong generic type-
  argument name; a Nullable-vs-Simple node-type mismatch — guarding the new recursion paths against a vacuous
  pass). TRIANGULATION MECHANISM: a THROWAWAY (deleted) fresh-Compiler ProjectReference probe ran BOTH live
  Parser.cs AND the owner's ParseFileAst through the identical `OutputFormatter.AstToJson` serializer and
  diffed the JSON — 15/15 whole-tree MATCH (11 synthetic + 4 whole-file), the strongest owner==Parser.cs proof.
  EVIDENCE: BootstrapServices contracts 1255/1255 (1238 tranche-4 baseline + 17; fresh CLEAN `rm -rf obj bin`
  + restore + `dotnet test -p:NSharpExcludeTests=false`); the 1238 baseline UNCHANGED proves the node-returning
  grammar refactor still does NOT perturb the diagnostic stream; dev.sh Parser slice 384/384 (0 failures — the
  C# Parser.cs path is untouched); ownership audit 18/18.
  Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers outside its `.tests.nl` (grep across
  src+editors+tests); Parser.cs stays the sole production authority. Only `.nl`/`.tests.nl`/`.md` changed (all
  ratchet-ignored; the 3 changed files are absent from the non-nsharp-growth ratchet manifest) → no ownership
  repin. No LSP/VS Code change → no reload. NO two-stage bootstrap wall (the packaged SDK self-emitted every
  new construct — the node constructors + the single-line span factory + the nullable TypeReference? returns —
  no planner/kernel/OpCode change; the local-extraction workaround for the list-index property-set is the ONLY
  new emit accommodation, and it stays inside dogfood N#). Next: TRANCHE 6 — functions/properties/methods/
  constructors (blocked on statement/expression body materialization), then type-parameter lists + base/
  interface lists on declarations (relaxing `hasTypeParams`/`hasBaseList`), then union/soa/type-alias bodies,
  then the statement + expression + pattern families, until a whole valid-or-malformed file parses into
  (CompilationUnit, Errors) provably equal to Parser.cs.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 4 = MODIFIERS + PRIMARY-CONSTRUCTOR PARAMETERS + argument-free ATTRIBUTES. MILESTONE ACHIEVED:
  WHOLE-FILE `ParseFileAst(corpus) == golden` on THREE real-corpus public-positional-record files
  (PlaygroundWasmModels.nl [int/string, 3 params], SystemsAotReport.nl [string/bool, 4 params],
  SystemsReportSummary.nl [7 int params]) — exceeding the ≥2 bar; each golden triangulated against LIVE Parser.cs
  via `nlc query ast`, so owner == golden (by the AstEq contract) == Parser.cs (by the query-ast oracle). These
  were the tranche-3 pure-data candidates, blocked ONLY on `Modifiers.Public` + the primary-ctor Parameter list.
  CONSTRUCTION-SITE INVENTORY (owner, each byte-exact to Parser.cs): (1) MODIFIERS — `ParseModifiers` now returns
  the byte-exact `Modifiers` Parser.cs :215/:298 hangs on the node. It accumulates an int bitmask (`value = value |
  System.Convert.ToInt32(Modifiers.X)`) over Parser.cs's exact recognized flag set/order (Public/Private/Static/
  Internal/Protected/Virtual/Override/Abstract/Sealed/Partial/Async/File) and returns `(Modifiers)value` — the
  emittable idiom (DeclarationFacts.nl :52 / TypeInfoFactories.nl :938; enum bitwise operators route through the C#
  fenced residual and are avoided in dogfood .nl). Consumption is PRESERVED exactly: `Readonly` (never a ParseModifiers
  flag in Parser.cs) is still consumed via `IsModifierKeyword` for recovery but contributes NO flag (the 1225 diagnostic
  baseline stayed green, proving zero consumption/report perturbation). System.Convert is FULLY-QUALIFIED (no
  `import System` — the 7270-line owner has 214 bare `Type`/27 `Func`/… identifiers, a collision hazard). (2)
  PRIMARY-CTOR PARAMS — `ParseParameterListRecovery` now RETURNS `List<Parameter>` and materializes each parameter as
  a PURE side-effect of the existing diagnostic parse (byte-exact to Parser.cs :811 — `new Parameter(paramName, paramType,
  null [DefaultValue], false [IsThis], ParameterModifier.None, null [Attributes], paramLine, paramColumn, false [IsScoped],
  null [Lifetime])`; Line/Column on the param-name start :796-797). `ParseParameterTypeReference` now returns
  `TypeReference?` reusing the field single-token-identifier heuristic (Parser.cs :1959 — `new SimpleTypeReference(name,
  line, column) { Span = SpanFromTokens(t,t) }` ≡ `FromStartAndLength(t.Line, t.Column, t.Value.Length)`), else null for
  richer forms. (3) ATTRIBUTES — `ParseAttributes` now RETURNS `List<AttributeNode>`, materializing the argument-free
  shape byte-exact to Parser.cs :292 (`new AttributeNode(name, [], attrLine, attrColumn)`; Line = the `[` line, Column =
  the `[` column + 1, Parser.cs :274-275). (4) THREADING + GATE — both dispatch sites (ParseTopLevelDeclaration :761 +
  the member-level ParseMemberDeclaration :1424) capture `attributes`/`attrsOk`/`modifiers` and thread them into the five
  materializing name parsers (ParseClassName/ParseStructName/ParseRecordName/ParseInterfaceName/ParseEnumName, now taking
  `(modifiers, attributes, attrsOk)`). Each applies a NO-STUB materialization GATE — `canMaterialize := attrsOk && paramsOk
  && !hasTypeParams && !hasBaseList` — so a declaration carrying a DEFERRED feature (a richer/qualified/generic param
  type, a param default `=`, a per-parameter or argument-bearing attribute, a generic type-parameter list, or a base/
  interface list) is DECLINED (no node added) rather than partially compared. Two transient recovery fields
  (`ParamListMaterializable` / `AttributesMaterializable`) carry the gate signals, captured into the caller's local
  IMMEDIATELY (before the body parse whose nested params/attrs would reset them). RICHER TypeReference forms
  (generic/qualified/array/nullable/tuple/Func), attribute-with-args, generics, and base lists stay DEFERRED-and-
  UNMATERIALIZED (the corpus uses none). DELIVERABLES: `ColumnarParserRecovery.nl` 7,117 → 7,270 (+153 net; +266/−113):
  the two gate fields + ParseModifiers/ModifierFlagOrZero rewrite + ParseAttributes materialization + ParseParameterList-
  Recovery/ParseParameterTypeReference materialization + the two dispatch rewrites + the five name-parser rewrites.
  `ColumnarParserAst.tests.nl` 520 → 719 (+199): registered `Parameter` + `AttributeNode` in AstEq.FieldNames; added
  `AddParam`/`AddRecordParams`/`AddStructFull`/`AddClassFull`/`AddAttr`/`Mods2` golden builders; +13 contracts. CONTRACTS
  (+13, all AstEq owner==golden): 3 WHOLE-FILE corpus equalities (the milestone); a public struct (Modifiers.Public); a
  `public sealed class` (multi-flag bitmask Public|Sealed = 129, proving the OR accumulation); an argument-free `[Foo]
  struct` (AttributeNode); a `record R(a: int, b: string)`; 4 NO-STUB decline gates (richer generic param type / param
  default value / generic type-param list / argument-bearing attribute — each proven to leave Declarations EMPTY, the
  intentional deferral, NOT a Parser.cs-parity claim); 2 negative self-checks (a wrong Modifiers value + a wrong param
  type both caught, guarding the new comparison paths against a vacuous pass). GOTCHA RESOLVED: `params` is a reserved
  keyword (TokenType.Params) — the golden builders/locals use `paramList`; and `(Modifiers)(<parenthesized expr>)` fails
  the columnar cast-detection parse — cast a bare local (`value := …; return (Modifiers)value`) instead. EVIDENCE:
  BootstrapServices contracts 1238/1238 (1225 tranche-3 baseline + 13; fresh CLEAN `rm -rf obj bin` + `dotnet test
  -p:NSharpExcludeTests=false`); the 1225 baseline unchanged proves the materialization side-effect + the ParseModifiers/
  ParseAttributes/ParseParameterListRecovery return-value refactor still do NOT perturb the diagnostic stream; dev.sh
  Parser 381/381; ownership audit 18/18. Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers
  outside its `.tests.nl` (grep across src+editors+tests); Parser.cs stays the sole production authority. Only
  `.nl`/`.tests.nl`/`.md` changed (all ratchet-ignored) → no ownership repin (audit 18/18 confirms). No LSP/VS Code change
  → no reload. NO two-stage bootstrap wall (byte-exact idioms — int OR / `(Modifiers)value` cast / `System.Convert.ToInt32`
  FQN / nullable `TypeReference?` + non-null `List<Parameter>` returns / `new Parameter` / `new AttributeNode` /
  `List<Argument>` — no planner/kernel/OpCode change; the packaged SDK self-emitted them, clean build). Next: TRANCHE 5 —
  richer TypeReference forms in param/field types (generic/qualified/array/nullable/tuple/Func materialization from the
  owned stage-15 grammar), then functions/properties/methods/constructors (blocked on statement/expression body
  materialization), then the remaining member + statement/expression families.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 3 = MEMBERS threaded through the type bodies. The owner now materializes a POPULATED `Members` list
  on every class/struct/record/interface shell, the FieldDeclaration member for the initializer-free
  `name: <simple type>` corpus, and NESTED-type recursion (a nested type lands in its enclosing type's
  Members, not the top level). MECHANISM (as recorded by tranche 2): (1) a nesting-safe member-list stack
  `TypeMemberStack: List<List<Declaration> >` (the `> >` space is the `>>`-tokenizer workaround) + an
  `AddDeclaration(node)` helper that targets the stack top when a type body is open, else the top-level
  `DeclarationNodes` — replaces every `DeclarationNodes.Add(...)` at the five type construction sites; (2)
  `ParseTypeBody` now RETURNS the parsed member list — it pushes a fresh list on entry (the active member
  target), parses members into it, pops on exit (restoring the enclosing target for nested placement), and
  the caller hangs that list on the declaration node's `Members`; (3) `ParseFieldMember` materializes the
  plain FieldDeclaration at Parser.cs :1771, guarded to the materialized subset (no property modifiers, a
  single-token simple type, no initializer); (4) `ParseFieldTypeReference` now returns `TypeReference?` — for
  the single-token identifier type (`Position == startPosition + 1`) it builds the byte-exact
  `SimpleTypeReference(name, line, column)` with `.Span = SourceSpan.FromStartAndLength(line, column, len)`
  (≡ Parser.cs :1959-1962 `new SimpleTypeReference(name, typeNameLine, typeNameColumn) { Span =
  SpanFromTokens(typeNameToken, typeNameToken) }`, since SpanFromTokens(t,t) ≡ FromStartAndLength(t.Line,
  t.Column, t.Value.Length) — Parser.cs :5878 vs SourceSpan.nl :42), else null (richer/error types are a
  later tranche → the caller declines to materialize that field). MEMBER CONSTRUCTION-SITE INVENTORY (owner,
  each byte-exact to Parser.cs): FieldDeclaration → `ParseFieldMember` end vs Parser.cs :1771
  (`new FieldDeclaration(name, type, initializer, modifiers, propertyModifier, attributes, line, column)`,
  Line/Column on the field-name start :1639-1640, Modifiers.None / PropertyModifier.None / [] / null
  Initializer for the corpus); SimpleTypeReference → `ParseFieldTypeReference` vs Parser.cs :1959-1962;
  ClassDeclaration/StructDeclaration/RecordDeclaration/InterfaceDeclaration → their name parsers now hang the
  `members` list from ParseTypeBody (Parser.cs :973/:1010/:1052/:1150). FQN: `FieldDeclaration` (like
  `ClassDeclaration`) collides with a test-helper `class FieldDeclaration` in
  `AnalyzerDeclarationContext.tests.nl` under the tests-enabled build → fully qualified
  `NSharpLang.Compiler.Ast.FieldDeclaration`; `SimpleTypeReference` has no collision (simple name used).
  STUB DISCIPLINE RECORD: NOTHING is stubbed in this tranche — every materialized node/field is a real,
  byte-exact value, so no field is excluded from the golden comparison. The corpus is confined to the
  fully-byte-exact subset (plain `name: <simple identifier type>` fields + nested types); any field with a
  property modifier, `:=` inference, `=> expr`, a `{ get/set }` accessor block, an `= initializer`, or a
  richer/qualified/generic type is PARSED for diagnostics but its node is NOT materialized (deferred), so it
  never enters a golden comparison. Properties/methods/constructors are DEFERRED to tranche 4 because their
  bodies are BlockStatement/Expression and statement/expression materialization is a later tranche (an empty
  `func f() {}` body would still require the whole FunctionDeclaration/Parameter/BlockStatement surface — out
  of scope here). DELIVERABLES: `ColumnarParserRecovery.nl` +106/−38 (the stack field + AddDeclaration +
  ParseTypeBody return + five AddDeclaration rewrites + FieldDeclaration/SimpleTypeReference construction +
  ParseFieldTypeReference return); `ColumnarParserAst.tests.nl` +141/−5 (registered FieldDeclaration +
  SimpleTypeReference in AstEq.FieldNames; added `AddClassM/AddStructM/AddInterfaceM/AddRecordM/AddFieldTo`
  golden builders; 7 positive member contracts + 1 field-type-mismatch negative self-check). EQUALITY /
  TRIANGULATION: all 8 new contracts prove owner == golden (AstEq); every positive golden's positions were
  DERIVED from and re-checked against the LIVE Parser.cs via `nlc query ast` (freshly built CLI, scratch
  project) — struct{x:int,y:int}, class Box{item:Widget}, interface I{id:int}, record R{id:int}, nested
  class Outer{tag:int, struct Inner{v:int}}, nested empty struct — every field/type Line/Column/Span and the
  nested placement matched byte-for-byte (golden == Parser.cs). REAL-CORPUS FILES: no in-repo `.nl` file fits
  the current narrow subset — the pure-data candidates (`PlaygroundWasmModels.nl`, `SystemsAotReport.nl`,
  `SystemsReportSummary.nl`, `SystemsEffectFacts.nl`) are all `public` positional records (Modifiers.Public +
  PrimaryConstructorParameters, both deferred), so a real-file whole-tree comparison is deferred to the
  tranche that materializes modifiers + primary-ctor params + methods; the realistic multi-field/nested/
  user-named-type surfaces above were triangulated against the live Parser.cs oracle in their place.
  EVIDENCE: BootstrapServices contracts 1225/1225 (1217 tranche-2 baseline + 8, fresh CLEAN `rm -rf obj bin`
  + `dotnet test -p:NSharpExcludeTests=false`); the 1217 baseline unchanged proves the member side-effect
  still does not perturb diagnostics; dev.sh Parser 381/381; ownership audit 18/18. Production compile path
  UNTOUCHED — `ParseFileAst` still has ZERO callers outside its `.tests.nl` (grep across src+editors+tests);
  Parser.cs stays the sole production authority. Only `.nl`/`.tests.nl`/`.md` changed (all ratchet-ignored)
  → no ownership repin. No LSP/VS Code change → no reload. NO two-stage bootstrap wall (byte-exact idioms —
  no planner/kernel/OpCode change; the packaged SDK self-emitted the new constructs incl. the nullable
  `TypeReference?` return local, the `List<List<Declaration> >` stack field, and the `.Span`-via-factory
  set). Next: TRANCHE 4 — properties/methods/constructors (blocked on statement/expression body
  materialization), then modifiers/attributes/primary-ctor params/richer type references, then the remaining
  member + statement/expression families.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 2 = ClassDeclaration materialized + the tranche-1 blocker ROOT-CAUSED and DISPROVEN. The mandate's #1
  item was "resolve the ClassDeclaration blocker" recorded in tranche 1 (`new ClassDeclaration(...)` supposedly
  declines in the columnar constructor planner when nullable-generic-list args are null AND the `BaseClass:
  TypeReference?` param is present). THAT THEORY IS WRONG. The real root cause is a SIMPLE-NAME TYPE COLLISION:
  `AnalyzerDeclarationContext.tests.nl` (namespace `NSharpLang.Compiler`) defines LOCAL test-helper classes named
  `ClassDeclaration`, `TypeAliasDeclaration`, `FieldDeclaration` (dummy stand-ins for the reflection-`object`
  AnalyzerDeclarationContext tests). The owner's namespace `NSharpLang.Compiler.Columnar` imports BOTH
  `NSharpLang.Compiler` and `NSharpLang.Compiler.Ast`, so when the test files are compiled (tests-enabled build),
  the simple name `ClassDeclaration` resolves AMBIGUOUSLY (two visible types, neither in the owner's own namespace)
  → `TryResolveExactExplicitTypeInContext` fails → the columnar construction planner declines. struct/record/
  interface/enum have NO colliding test-helper → resolve unambiguously → emit (which is why tranche 1 saw ONLY
  ClassDeclaration decline and mis-attributed it to the `BaseClass` param). PROOF (all empirical, clean builds):
  (a) the tests-EXCLUDED build (no test helpers present) EMITS the identical `new ClassDeclaration(name, null, null,
  [], [], null, None, [], line, col)` fine — so it is NOT an intrinsic construction gap; (b) under tests-ENABLED
  the empty-LIST-args variant AND the assign-to-a-local-then-Add variant BOTH decline identically → not the null
  generic-list args; (c) `TypeReference` is a `class`, so a null BaseClass adopts via ldnull, and the resolver scores
  a null-literal arg 4 against any reference/nullable param → not the null; (d) `AnalyzerDeclarationContext.tests.nl`
  itself does `new ClassDeclaration("X")` and is GREEN because its SAME-NAMESPACE local helper wins resolution.
  RESOLUTION (byte-exact idiom, the mandate's preferred path — NO planner extension, so NO two-stage bootstrap wall):
  fully-qualify the type at the construction site — `new NSharpLang.Compiler.Ast.ClassDeclaration(...)` — which
  resolves uniquely to the real AST type; identical type, args, and runtime node values (byte-exact). Applied at the
  owner's `ParseClassName` site AND at the harness `Golden.AddClass` (which is in `NSharpLang.Compiler.Columnar` and
  imports both namespaces, so it had the same collision). WHAT LANDED in `ColumnarParserRecovery.nl` (+7 lines):
  `ParseClassName` now appends `new NSharpLang.Compiler.Ast.ClassDeclaration(name, null, null, new
  List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), classToken.Line,
  classToken.Column)` — byte-exact to Parser.cs :973 (Line/Column on the class keyword per :933-934; TypeParameters/
  BaseClass/PrimaryConstructorParameters null per :943/:952/:946; Interfaces/Members/Attributes empty; Modifiers.None)
  for the empty-body / modifier-free corpus. HARNESS (`ColumnarParserAst.tests.nl`): `Golden.AddClass` added (FQN'd);
  the ClassDeclaration field registry was already present from tranche 1; +2 contracts (empty-body class materializes
  null TypeParameters/BaseClass/PrimaryConstructorParameters — Parser.cs :973; a class-alongside-a-struct preserves
  declaration order + per-line anchoring). CORRECTED the stale tranche-1 deferral comment in the harness. EVIDENCE:
  BootstrapServices contracts 1217/1217 (1215 tranche-1 baseline + 2, fresh CLEAN `dotnet test
  -p:NSharpExcludeTests=false`); the 1215 baseline unchanged proves the AST side-effect still does not perturb
  diagnostics; dev.sh Parser 381/381. Production compile path UNTOUCHED — `ParseFileAst` still has ZERO callers
  outside its `.tests.nl` (grep across src+editors+tests); Parser.cs stays the sole production authority. Only
  `.nl`/`.tests.nl` files changed (both ratchet-ignored) → no ownership repin. No LSP/VS Code change → no reload. NO
  two-stage bootstrap wall (byte-exact idiom, no planner/kernel/OpCode change; the packaged SDK self-emits it).
  MEMBER GRAMMAR — RECUT to TRANCHE 3, but PROVEN VIABLE this turn (de-risked, no blocker): probes (clean, tests-
  enabled) show `new NSharpLang.Compiler.Ast.SimpleTypeReference("int", l, c)` + `new
  NSharpLang.Compiler.Ast.FieldDeclaration(...)` EMIT, and — crucially — setting the byte-exact `TypeReference.Span`
  via `SourceSpan.FromStartAndLength(l, c, len)` ALSO emits. The cumulative "no value-struct construction" gap applies
  to `new SourceSpan(...)` but NOT to a static FACTORY that returns the struct; and for a single-token simple type
  Parser.cs's `SpanFromTokens(t, t)` (Parser.cs :5873, `new SourceSpan(sl, sc, sl, sc+max(1,len))`) is value-equal to
  `SourceSpan.FromStartAndLength(sl, sc, len)` — so byte-exact spans ARE achievable via the factory. `nlc query ast`
  serializes every public property (OutputFormatter.AstValueToJson :138-143), so `TypeReference.Span`/`NameSpan` ARE
  observed and MUST be set for the golden==Parser.cs triangulation. TRANCHE-3 MECHANISM (recorded): (1) thread a
  `CurrentTypeMembers` recovery field through `ParseTypeBody` (save/restore around the recursive call for NESTED
  types — currently the type parsers append unconditionally to top-level `DeclarationNodes`, which would mis-place a
  nested type's node; replace `DeclarationNodes.Add(...)` with an `AddDeclaration` that targets `CurrentTypeMembers`
  when set); (2) make `ParseModifiers`/`ParseAttributes` return the parsed `Modifiers`/`List<AttributeNode>` for
  byte-exact member `.Modifiers`/`.Attributes` (or restrict the first member corpus to no-modifier/no-attribute
  plain fields, `Modifiers.None`+`[]`); (3) materialize FieldDeclaration first (the simplest, initializer-free
  `name: type` corpus — no expression stub needed since Initializer is null), then properties/methods(signatures)/
  ctors/nested-types; (4) FQN the colliding member names (`FieldDeclaration`, `TypeAliasDeclaration`). FOLLOW-UP
  (optional, filed as a chip): the three shadowing test-helper types in `AnalyzerDeclarationContext.tests.nl` are a
  latent hazard for ALL member tranches — renaming them (e.g. `Stub*`) would let the whole owner use simple names,
  but FQN is the lower-risk per-site idiom and is what this tranche used. Next: TRANCHE 3 — thread members through
  ParseTypeBody and materialize the FieldDeclaration family per the mechanism above.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1c (FULL-TREE AST MATERIALIZATION),
  TRANCHE 1 = the CompilationUnit CONTAINER + FileImports + the top-level TYPE-declaration skeleton (struct/interface/
  enum/record). The owner's (already full-diagnostic-parity) recovery grammar now CONSTRUCTS the production
  `CompilationUnit` as it parses, materialized as a PURE side-effect into recovery fields (the N+1a pattern, so the
  diagnostic-only `ParseFilePreamble` path is unperturbed — proven by the 1202 baseline contracts staying green).
  WHAT LANDED in `ColumnarParserRecovery.nl` (6,937 → ~7,000; `.nl`, ratchet-ignored): (a) new fields FileImportNodes/
  DeclarationNodes/UnitLine/UnitColumn + a test-only `ParseFileAst(source, fileName): CompilationUnit` entry
  paralleling `ParseFilePreambleAst`, assembling `new CompilationUnit(Namespace, Imports, FileImports, Package,
  Declarations, UnitLine, UnitColumn)` (Line/Column = first token, Parser.cs :33-34); (b) `ParseImport` materializes
  the FileImport statement for `import "path" [as X]` (path = quote-trimmed literal, PathColumn/PathLength on the raw
  token, Line/Column on the `import` keyword — Parser.cs :159-163) into FileImportNodes; (c) the struct/interface/enum/
  record name parsers append their empty-body declaration node (Members=[], no type-params/base/primary-ctor,
  Modifiers.None, Attributes=[], IsRefStruct/IsStruct/IsDuckInterface/EnumType tracked from the parse) — byte-exact to
  Parser.cs's ParseStruct/Interface/Enum/Record for the empty-body/modifier-free corpus. HARNESS (new
  `ColumnarParserAst.tests.nl`, `.tests.nl` ratchet-free): a native reflection-based RECURSIVE deep-structural-equality
  comparator `AstEq.Diff` (compares runtime type NAME + every stored field via GetProperty/GetField reflection + child
  ORDER, recursing nodes+lists, driven by a per-node field registry so it needs no enumerable reflection), comparing
  the owner's `ParseFileAst` output against hand-built GOLDEN trees inventoried from Parser.cs construction sites (the
  same golden-value methodology the 432 diagnostic contracts use — a live Parser.cs call from this host is infeasible:
  Compiler.dll is absent from the BootstrapServices test host and MetadataLoadContext cannot execute). HARNESS CHOICE
  RATIONALE: C# tests/*.cs is RATCHET-BLOCKED (near-zero headroom; a new .cs trips OWN003, growth trips OWN004), so the
  native `.nl` route is the pragmatic choice. 13 contracts (struct, interface, duck-interface, int-enum, string-enum,
  record, record-struct, namespace, package+import, file-import, two-structs order, whole-file container, + a NEGATIVE
  self-check proving the comparator flags a divergence — not a vacuous pass). CLASSDECLARATION DEFERRED — EMITTER GAP
  FOUND: `new ClassDeclaration(...)` DECLINES in the columnar constructor planner whenever a nullable-generic-list arg
  (TypeParameters/PrimaryConstructorParameters) is `null` AND the node also has the extra `BaseClass: TypeReference?`
  param; struct/record/interface/enum (which lack `BaseClass`) emit fine with the SAME null args, and a zero-null
  ClassDeclaration construction emits but is not byte-exact to Parser.cs's null. Class materialization is the first task
  of the next tranche (needs a columnar-planner fix or a byte-exact null-typing idiom). NOTE for future tranches: a
  nullable-generic-list TYPED LOCAL (`x: List<T>? = null`) also declines — pass such nulls as bare inline literals.
  DEFERRED to later N+1c tranches: ClassDeclaration, functions (bodies), members (fields/methods/ctors/props), type-
  references/parameters, type-params/base-types, modifiers/attributes, union/soa/type-alias/test-DSL bodies, statements,
  expressions/patterns, and error-node materialization. EVIDENCE: BootstrapServices contracts 1215/1215 (1202 baseline
  + 13, fresh clean `dotnet test -p:NSharpExcludeTests=false`); the 1202 baseline unchanged proves the AST side-effect
  does not perturb diagnostics. Production compile path UNTOUCHED — grep confirms `ParseFileAst` has ZERO callers
  outside its own `.tests.nl`; Parser.cs stays the sole production authority. Only `.nl`/`.tests.nl`/`.md` files changed
  (all ratchet-ignored) → no ownership repin. No LSP/VS Code change → no extension reload. No two-stage bootstrap wall
  (self-contained owner edit + new test file; the packaged SDK self-emits it, no new kernel/OpCode surface). Next:
  TRANCHE 2 — resolve the ClassDeclaration emitter gap, then materialize members (fields/methods) + type-references +
  parameters + modifiers, extending the same harness.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1b (the AST-HIERARCHY MIGRATION — the
  CompilationUnit-container unblock). The ENTIRE `AstNode` hierarchy is migrated from C# records to N# classes and
  the C# definitions DELETED, making `CompilationUnit` (and every Declaration/Statement/Expression/Pattern node)
  constructable from the upstream `BootstrapServices` owner. This is the production-touching native motion of the arc.
  TYPE INVENTORY + TRANCHE: the migration is ALL-OR-NOTHING at the base (C# records cannot derive from N# classes, so
  moving `AstNode` forces every derived node; and the moved nodes reference the standalone helpers — Parameter/Argument/
  AttributeNode/EnumMember/CatchClause/SwitchCase/TupleElement/PropertyInitializer/MatchCase/PropertyPattern/the Pattern
  hierarchy — which in turn reference nodes, one mutually-recursive cluster). All SUPPORTING types were ALREADY N#
  (TypeReference, the Declaration/Statement/Expression enums, TypeParameter/GenericConstraint, UnionCase/
  SoaColumnDeclaration, SourceSpan) and the three preamble leaves (Namespace/Imports/Package) landed N+1a — so the only
  remaining C# was the node hierarchy itself. MOVED THIS SLICE (~110 types across 3 new N# files): `Expressions.nl`
  (AstNode/Expression/InterpolatedStringPart/Pattern bases + all 41 expression leaves + 12 pattern leaves + Argument/
  TupleElement/PropertyInitializer/MatchCase/PropertyPattern), `Statements.nl` (Statement base + 30 statement leaves +
  CatchClause/SwitchCase), `Declarations.nl` (Declaration base + CompilationUnit + 18 declaration leaves + Parameter/
  EnumMember/AttributeNode). C# DELETIONS (whole files, byte accounting): `Ast/Declarations.cs` (238 lines),
  `Ast/Statements.cs` (225), `Ast/Expressions.cs` (381) = 844 lines removed from compiler-core; the C# `Ast/` directory
  is gone. THE EXCEPT FIX: `Analyzer.cs:18169` `pattern.Properties.Except(constrainedProperties).All(...)` (the ONE
  parser-AST value-equality dependency per the N+1a audit) rewritten to
  `pattern.Properties.Where(p => !ReferenceEquals(p, constrainedProperty)).All(...)` — reference-based, byte-equivalent
  (constrainedProperties is a single-element reference subset; no two PropertyPatterns are value-equal). MECHANICAL
  CONSUMER ADJUSTMENTS (field-vs-property reflection fallbacks — N# emits data members as public FIELDS, C# records
  exposed properties; every reflector already had the GetProperty→GetField pattern EXCEPT four spots the full suite
  surfaced): `CompilationUnitFacts.nl` GetRequiredListProperty (SoA-emission check), `CodeFix.nl` GetLastImportLine
  (import-position, "Imports"+"Line"), and `CodeIntelligence/OutputFormatter.cs` AstValueToJson (the `nlc query ast`
  serializer now enumerates fields+properties). One TEST adjustment: `AstChildrenTests.cs` excludes the base `Expression`
  from its concrete-leaf enumeration (N# emits classes WITHOUT the CLR abstract flag, so `abstract`-record bases now
  report non-abstract; single-line in-place change, no line-count growth). EMITTER GAPS DISCOVERED + WORKED AROUND
  (probed EARLY, before committing to the tranche): (1) field initializers to a non-default RHS (`X: SourceSpan =
  SourceSpan.None`) CRASH ColumnarFieldInitPlanner — resolved by relying on zero-defaults (SourceSpan.None ≡
  default(SourceSpan); null; both byte-identical to the record initializer defaults, since FileImport/FunctionDeclaration
  either always set them or the omitted default equals the zero value); (2) a parameterless ctor with all-unassigned
  fields declines NL103 (no real AST type needs it); (3) `List<List<Expression>>` nested-generic field trips the `>>`
  tokenizer — resolved with the standard `List<List<Expression> >` space (emits the identical closed type, verified by
  reflection); (4) `IsAsyncIterator` (the only `.HasFlag`-bearing computed prop) OMITTED — proven dead (zero consumers),
  avoiding the untested emitter path. Every other shape emits: `: base(...)` chaining + inherited readable Line/Column,
  non-readonly settable fields (C# object-initializers for OperatorKeywordSpan/OperatorSymbolSpan/ReturnLifetime/
  PathColumn/PathLength), nullable/List/struct/enum fields, enum-typed default params, computed expression-bodied props
  (DiagnosticColumn/DiagnosticLength/IsIndexerInitializer), post-construction get/set fields (IsResultFactory/
  IsExhaustive). PascalCase ctor params (this.X=X) so BOTH positional and named-arg (`new Parameter(...,Line:l,Column:c)`)
  call sites compile unchanged. FULL-BAR EVIDENCE: full unit suite 3190/3190 (Debug); BootstrapServices contracts
  1202/1202; dev.sh Parser 381/381; LanguageServer slice 273/273; ownership audit 18/18 after repin; **byte-exact corpus
  IL diff — 159 assemblies (all example/fixture project targets + all native `.tests.nl` projects) fingerprinted with
  fresh Release CLIs (baseline e50953baf worktree vs the migrated tree) via an MVID/timestamp-independent IL fingerprint
  (System.Reflection.Metadata over every method body + member shape), diff EMPTY** — the migration changes ZERO emitted
  user IL (the columnar emit path consumes ColumnarNodeTable, never the C# AST); Web API template (`templates/nsharp-webapi`)
  builds clean. RATCHET ACCOUNTING (repin via scratchpad math, mirrored constant): the 3 deleted files → state `removed`,
  current metrics 0, fingerprint `text-v1:removed` (epoch facts preserved, immutable); `Analyzer.cs` (23068 lines
  unchanged, fingerprint updated), `AstChildrenTests.cs` (147 lines unchanged, fingerprint updated), and
  `OutputFormatter.cs` (compacted 379→378 lines — the field+property serializer LINQ-Concat kept it UNDER the immutable
  379 epoch ceiling — fingerprint updated); reviewedHeadFingerprint recomputed d7f043fb…→1be7f7cb4c07e417 in BOTH the
  manifest and `OwnershipPolicy.ReviewedHeadFingerprint`. Net non-N# change is −846 lines (844 deletions + the −1
  OutputFormatter reduction + 0-net Analyzer/AstChildren); the 3 new N# files are `.nl` (ignored by the non-nsharp
  ratchet — the whole point). NO WALL TRIPPED: the AST classes are self-contained leaf definitions; the packaged SDK
  0.1.0 self-emitted them (incl. all 1202 contracts) with no repin/no new kernel surface. No LSP/VS Code BEHAVIOR change
  (type identity moved assemblies but the server builds + its slice passes) → no extension reload needed. Next: STAGE
  N+1c — extend the owner's recovery grammar to MATERIALIZE the full node tree (declarations/statements/expressions) into
  a real `CompilationUnit`, proving node-by-node structural equality against Parser.cs on the parity corpus.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE N+1 (the AST/facts BRIDGE, FIRST INCREMENT) —
  the recovery owner now constructs the PRODUCTION `NSharpLang.Compiler.Ast` node instances for the file preamble
  (Namespace / Imports / Package) alongside its owned diagnostics, the first fact surface it produces beyond
  `List<CompilerError>`. Full design record + the bridge-shape decision + the precise CompilationUnit-container block +
  the refined N+1..N+3 staging are in the new "## 016 AST/facts bridge (N+1) design record" section below. WHAT LANDED:
  (1) a new `PreambleAst` result class {Namespace: NamespaceDeclaration?, Imports: List<ImportDirective>, Package:
  PackageDeclaration?, Errors: List<CompilerError>} and a static `ParseFilePreambleAst(source, fileName): PreambleAst`
  entry; (2) `ParseQualifiedName` now RETURNS the dot-joined name (bit-identical ConsumeIdentifier diagnostic sequence
  to the prior void form), and `ParseNamespace`/`ParsePackage`/`ParseImport` capture the keyword line/column and
  materialize `new NamespaceDeclaration(name, line, column)` (Parser.cs :127) / `new PackageDeclaration(...)` (:136) /
  `new ImportDirective(namespace, alias, importKwLine, importKwCol)` (:71) into recovery fields — a PURE side-effect of
  the existing grammar, so the diagnostic-only `ParseFilePreamble` stream is unperturbed (proven by the diagnostic-
  preservation contract). WHY LANDABLE / WHY BOUNDED HERE: those three preamble leaf types are already N# and owned in
  THIS assembly (FileHeaderDeclarations.nl / ImportDirective.nl), so the owner constructs the IDENTICAL instances
  Parser.cs constructs. The CompilationUnit CONTAINER + the FileImports list (FileImport/NamespaceImport) + the
  Declarations list are C# in the DOWNSTREAM `NSharpLang.Compiler` assembly (Ast/Declarations.cs, Ast/Statements.cs),
  which this upstream `BootstrapServices` owner cannot NAME (the dependency runs Compiler → BootstrapServices, never the
  reverse — confirmed: every BootstrapServices `.nl` that handles a `CompilationUnit` takes it as `object` + reflection,
  e.g. AnalyzerDeclarationContext.AddCompilationUnit / AstNodeFinderCore.VisitCompilationUnit) — so the container is NOT
  built here and is the recorded N+1 block (an assembly-dependency block, NOT an emitter gap). EQUIVALENCE PROOFS: +8
  native parity contracts in `ColumnarParserRecovery.tests.nl` asserting node-field equality against Parser.cs's
  constructor semantics on WELL-FORMED preambles (lone namespace keyword-anchored; package keyword-anchored; bare import
  null-alias; qualified aliased import joined-name + alias; a full multi-line namespace+package+two-imports subtree with
  per-line Line anchoring; a file-import-builds-no-ImportDirective negative; empty-source all-absent) PLUS a diagnostic-
  preservation contract proving `ParseFilePreambleAst("import 5\n").Errors` matches `ParseFilePreamble`'s exactly (the
  found-other NL102 then the boundary-reset NL101). Evidence: BootstrapServices contracts 1202/1202 (1194 baseline + 8;
  full-suite fresh no-build run, `-p:NSharpExcludeTests=false`); dev.sh Parser 381/381; ownership audit 18/18; git
  status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). PRODUCTION COMPILE PATH UNTOUCHED — Parser.cs
  stays the sole production authority; `ParseFilePreambleAst`/`PreambleAst` are referenced ONLY by the owner's own
  `.tests.nl` (verified by grep across src+editors+tests: zero references outside the owner + its tests), so nothing in
  the production compile path changed. No LSP/VS Code change → no extension reload. NO wall tripped (self-contained edit
  to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner — incl. the AST construction + all 1202
  contracts cleanly — no repin; no new OpCode/kernel-entry surface). `ColumnarParserRecovery.nl` 6,855 → 6,937 (+82);
  `.tests.nl` 5,711 → 5,836 (+125). Next: STAGE N+1 continues — the CompilationUnit-container unblock (move the AstNode/
  Statement/Declaration hierarchy + CompilationUnit + FileImport/NamespaceImport upstream to N#), per the design record.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 17 of the parser-front-end arc — residual map
  item [5], the LAST capability family; the arc's parity ledger now CLOSES. Carried through the SAME shared-panic
  owner over the already-owned expression / statement / member / type / delimiter grammars, PROVEN byte-exact against
  the freshly built Release CLI oracle (`nlc check --json`, parser codes NL101-NL109, excluding the line-0 columnar-
  backend emit-decline NL103). SITE INVENTORY: (a) the GARBAGE-TYPE cascade shapes deferred since stages 4/9. The
  non-`{` braced found-other for class/struct: Parser.cs `ParseClassDeclaration`/`ParseStructDeclaration` (:970-971)
  ALWAYS parse the body (`Consume('{')` + `ParseMemberList`), so a `<error>`-named type whose offender is a non-`{`
  token (`class 5` / `struct 5`) leaves the offender for `ParseMemberList`, which — via its per-member panic reset +
  the SynchronizeToNextStatement panic reset before the type-body missing-`}` NL106 — reports the class-name NL102,
  the in-body field-name NL102(s), and the missing-`}` NL106; the Stage-12 position-sort orders them to the CLI
  display order (`class 5` → NL102@col1 [class], NL106@col1 [missing-`}`, emission-order tie], NL102@col7 [field]).
  The non-identifier parameter name (`func f(5)`): the param-name `ConsumeIdentifier` NL102 fires @ the offender,
  `ParseParameterTypeReference` routes the garbage through `ParseTypeReference` (which does NOT consume it), the `)`
  Consume is suppressed under panic, and the function returns bodiless — so `5 ) { }` each surface as a top-level
  "Unexpected token" NL101 through Run's per-declaration panic reset (the ALREADY-OWNED terminal arm). The named-tuple
  bad-name (`(x: 1, 5: 2)`): the named-element loop's `ConsumeIdentifier("Expected identifier")` NL102 fires @ the
  offender, the value `ParseExpression` consumes the offending `5`, the `)` Consume is suppressed under panic, and the
  leftover `:` and `)` surface as "Unexpected token '…' in expression" NL101 through the block-statement per-statement
  panic reset (ALREADY-OWNED). (b) the TYPE-ALIAS underlying-type consumer: Parser.cs `ParseTypeAliasDeclaration`
  (:1338-1350) `Consume(Assign)` + the optional `newtype` keyword (a bare advance) + `ParseTypeReference` (the full
  Stage-15 grammar) — the owner's `ParseTypeAliasName` previously parsed ONLY the alias NAME (a latent divergence: any
  aliased body `type T = int` would have leaked its `= int` to the top-level unexpected-token arm), now closed.
  IMPLEMENTATION: (1) renamed `ParseTypeBodyIfPresent` → `ParseTypeBody` and made it UNCONDITIONAL (`ConsumeToken(
  LeftBrace)` + `ParseMemberList`, mirroring Parser.cs :970-971 exactly, replacing the `if !Check('{') return`
  simplification that diverged for the non-`{` offender) — the 4 callers (class/struct/record/interface) route through
  it, so all four inherit the faithful body-always-parsed behavior; the `class {`/`struct {` `{`-offender case and every
  valid-name-with-body case are unchanged (the `{` is consumed as the opening brace), and every name-error-at-EOF case
  stays a single diagnostic (the missing-`}` NL106 is panic-suppressed). (2) extended `ParseTypeAliasName` with the
  `= <type>` body: `ConsumeToken(TokenType.Assign, "Expected '='", "assign")` [expected="assign" = TokenTypeToString(
  Assign)] + the `if Check(Newtype) { Advance() }` variant + `ParseTypeReferenceRecovery()`. All construction delegates
  to the shared `Report` / `ConsumeToken` / `ParseTypeReferenceRecovery` / `ParseMemberList`, so codes / messages /
  spans / snippets / hints / suggestions match Parser.cs automatically. VERIFIED PANIC INTERACTIONS (each pinned or
  re-proven): `class 5` reports THREE diagnostics (the member reset lets the field NL102 record, the sync reset before
  the NL106 lets it record); `class 5 { }` reports THREE NL102 with NO NL106 (the explicit `}` closes the body);
  `class struct\nfunc class` STILL reports exactly two NL109 (the func-name error now routes through the member-method
  `ParseMethodMember` path since the body is now parsed, but its `ConsumeDeclarationName("Expected function name",
  SpanFromToken(funcToken))` is byte-identical to the top-level `ParseFunctionName` path — same anchor @2:1 len4, same
  message; the outer missing-`}` NL106 is panic-suppressed) — the existing contract passes UNCHANGED. +22 native
  parity contracts in `ColumnarParserRecovery.tests.nl` (garbage cascade: `class 5` [3-diag], `struct 5` [3-diag],
  `class 5 { }` [3-diag], `func f(5) { }` [5-diag: param NL102 + 4 top-level NL101], `(x: 1, 5: 2)` [3-diag: element
  NL102 + 2 expr-terminal NL101]; type-alias positives: missing-`=` at EOF NL104 / missing-type at EOF NL104 /
  mid-line missing-`=` NL102 / `type T = List<>` generic-arg NL102 [proves the full type grammar] / `type = int`
  name-error-only NL102 [proves the body is cleanly consumed AFTER a name error] / `type T = newtype` at EOF NL104
  [newtype variant] / `type T = A |` union-missing-arm NL103; type-alias negatives: `A | B` / `int` / `newtype int` /
  `(int, string)` / `Func<int, bool>` / `int[]` / `A?` [all Count 0 — the underlying type routes through the full
  Stage-15 union/tuple/Func/postfix grammar]; ledger closeout: `func operator @` invalid-operator-symbol NL103 /
  `func g(): int returns {` missing-lifetime NL102 [via the local-function vehicle that wires ParseReturnLifetimeAnnotation] /
  a well-formed multi-line interpolated-raw `$"""…"""` in the block vehicle [Count 0]).
  COMPLETE DEFERRAL-LEDGER CLASSIFICATION (every recorded deferral across stages 1-16, resolved or definitively
  recorded): [NOW PINNED this stage] the garbage-type cascade (stages 4/9: `class 5`/`struct 5`/`func f(5)`/
  `(x: 1, 5: 2)`); the type-alias underlying-type (stage 15); the operator-symbol INVALID `func operator @` (stage 14,
  corpus-light); the `returns`-lifetime label error (stages 13/14, corpus-light — pinned via the local-function
  vehicle, the only owned `returns` consumer); the multi-line interpolated-raw negative (stage 12, corpus-light — a
  well-formed `$"""…"""` in the block vehicle is Count 0, the swallow concern does not materialize). [PERMANENTLY
  UNMATCHABLE at the CompilerError level] the EOF-length-clamp class (stages 5/12/16: the EOF-anchored `ConsumeGreater`
  `func f(): List<int`, the empty hole `$"{}"`, the bare `test`-at-EOF description, the EOF-anchored `returns`) —
  Parser.cs derives these lengths from `Current.Value.Length` = 0 at EOF, and the CLI's `DiagnosticSpanResolver.Resolve`
  clamps the JSON length 0→1 for display; the model faithfully emits the RAW length 0 (= Parser.cs), so a contract
  asserting length 1 would diverge from the model and a contract asserting length 0 cannot be oracle-CONFIRMED
  (BootstrapServices cannot reference Parser.cs, and the CLI — the only golden source — never exposes the raw 0). The
  diagnostic CAPABILITY (code/message/position at EOF) is present and is exercised by each family's NON-EOF variant
  already pinned; at cutover the model routes through the SAME clamp, so the DISPLAYED diagnostic converges. Definitively
  not a byte-exact CompilerError pin. [NOT A GAP — site-covered-elsewhere] the `allow` missing-`)` cascade-to-EOF (stage
  13): its `ConsumeSystemsIdentifier` / `Consume(Comma)` / `Consume(LeftParen)` / `Consume(RightParen)` sites are all
  exercised by the pinned allow-missing-`(` / allow-bad-effect + the Stage-9 closing-delimiter recovery; the corpus
  keeps the clean shapes to avoid asserting the fragile whole-file token consumption, which adds no new site.
  [PRODUCTION-BUG-GATED] the Stage-16 table-driven malformed-ROW HANG (`test "d" with (a) 9 { }`, `test "d" with (a)
  [ 9 ] { }`) — CONFIRMED this stage: production `nlc check` on `test "d" with (a) 9 { }` spins >12s (killed, no
  completion). Root cause: Parser.cs `ParseTestDeclaration` :590-604 — the outer table-case loop and the inner row loop
  (`while (!Check(RightParen) && !IsAtEnd()) { row.Add(ParseExpression()); … }`) have NO no-progress guard, so when
  `ParseExpression` cannot consume a `}`/`]` expression-terminator sitting in the row-expression position (and
  `ShouldSkipUnexpectedExpressionToken` returns false), the cursor never advances and the loop spins. The model
  reproduces the loop faithfully, so pinning the full malformed-row shape would hang the contract suite; the table `[`
  / row `(` / cases `]` Consume sites stay pinned at EOF (where the loop terminates). Chip filed (task_1f371371) with
  the precise site + the fix (a no-progress guard mirroring `ParseMemberList` :1379-1388) + a regression-test note; the
  older duplicate chip (task_9babb6f4) was dismissed as superseded. NO production wiring; NO wall tripped (self-contained
  edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner — incl. the `ParseTypeBody`
  restructure + the type-alias body + all 1194 contracts cleanly — no repin). Evidence: BootstrapServices contracts
  1194/1194 (1172 baseline + 22; full-suite fresh no-build run, `-p:NSharpExcludeTests=false`); dev.sh Parser 381/381;
  ownership audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`); git status shows ONLY the two `.nl`
  files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests:
  zero references outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code
  change → no extension reload. `ColumnarParserRecovery.nl` 6,841 → 6,855 lines (+14); `.tests.nl` 5,347 → 5,711 (+364).
  RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 17 — the CAPABILITY
  SURFACE IS NOW COMPLETE): [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE Stage 14] the MEMBER grammars +
  the record/interface/union/enum/soa type BODIES; [3 — DONE Stage 15] the richer type-reference forms; [4 — DONE Stage
  16] the TEST DSL + ATTRIBUTES; [5 — DONE] the garbage-type cascade shapes + the TYPE-ALIAS underlying-type consumer
  (this stage). EVERY residual-map item is DONE and EVERY recorded deferral is resolved or definitively classified.
  What remains before the arc completes: the AST/node-table-facts stage (N+1 — expose a `CompilationUnit`-equivalent /
  node-table surface the Analyzer/Linter/Formatter/LSP consume in place of Parser.cs's C# `CompilationUnit`), the
  CUTOVER (N+2, IDE-affecting — route every consumer to the N# owner at full diagnostic + AST parity), and the DELETION
  arc (N+3 — retire Parser.cs). Next: STAGE N+1 = the AST/node-table facts, per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 16 of the parser-front-end arc — the TEST DSL +
  ATTRIBUTES (residual map item [4]), carried through the SAME shared-panic owner over the already-owned expression /
  statement / member / block / argument / closing-delimiter grammars, PROVEN byte-exact against the freshly built
  Release CLI oracle (`nlc check --json`, parser codes NL101-NL109, excluding the columnar-backend emit-decline NL103 —
  for the test-DSL declarations the oracle also emits a line-0/1 emit decline ["…unmodeled declaration shape such as
  setup or teardown" / "…xunit attribute types were not resolvable"] which is a BACKEND diagnostic, not a parser one).
  SITE INVENTORY (grep of `ParseTestDeclaration`/`ParseSetupDeclaration`/`ParseTeardownDeclaration`/`ParseAttributes`/
  `ConsumeAttributeIdentifier` in Parser.cs): (a) the TEST-DSL declarations are dispatched from `ParseDeclaration`
  (:190-202) BEFORE attributes/modifiers via `IsTestDeclarationStart`/`IsSetupDeclarationStart`/`IsTeardownDeclarationStart`
  (:642/:667/:704), so each is its OWN top-level declaration and resets panic at the Run() declaration boundary. TEST
  (`ParseTestDeclaration` :546): the description-not-a-string-literal ExpectedToken DIRECT report ("Expected string
  literal for test description. Got 'X'", two example `suggestions`, length = Current.Value.Length) + skip-the-offender
  (`if (!IsAtEnd()) Advance()`, :570); the table-driven `with (params) [ (row), … ]` (:582 — `ParseParameterList` +
  `Consume(LeftBracket)` "…to start test cases" [plain NL102, LeftBracket declines closing-recovery] + the row loop's
  `Consume(LeftParen)` "…to start test case row" + `ParseExpression` list + `Consume(RightParen)` "…to end test case
  row" [NL107 via Stage-9] + `Consume(RightBracket)` "…to end test cases" [NL108 via Stage-9]); the `skip "reason"`
  string-literal ExpectedToken DIRECT report (:611, one suggestion, does NOT skip the offender); the `ParseBlock` body
  (owner span = the `test` keyword, length 4). SETUP/TEARDOWN (:695/:710): a bare `Advance()` past the contextual
  keyword then `ParseBlock` (owner span length 5 / 8), no own error site. assert/assert-throws already owned (Stage
  13). (b) ATTRIBUTES `[Name(.Name)* (args)?]` (`ParseAttributes` :269) precede modifiers on top-level declarations
  (:214), members (`ParseMemberDeclaration` :1424), AND parameters (`ParseParameterList` :770 — the owner's
  `ParseParameterListRecovery` per-parameter loop, closing the Stage-4-deferred parameter-attribute gap): the name via
  `ConsumeAttributeIdentifier` (:6811 — Identifier/Alloc/Allow, else the owned Stage-1 `ConsumeIdentifier` NL102 with
  its reserved-keyword / found-other / EOF variants + dot-access variant) + the qualified `.` continuation, the optional
  `(args)` via the owned Stage-10 `ParseArgumentList` (NL107 when unclosed), and the closing `]` via the owned Stage-9
  `Consume(RightBracket)` (NL108 when unclosed, else plain NL102). Also added the top-level PreprocessorDirective
  declaration (:205, a bare advance) so the `ParseDeclaration` dispatch ORDER is faithful. IMPLEMENTATION: inserted the
  test/setup/teardown/preprocessor checks + `ParseAttributes()` at the top of `ParseTopLevelDeclaration` (before
  `ParseModifiers`), the member `ParseAttributes()` into `ParseMemberDeclaration` (between the preprocessor check and
  `ParseModifiers`), and the per-parameter `ParseAttributes()` into `ParseParameterListRecovery`; added
  `IsTestDeclarationStart`/`IsSetupDeclarationStart`/`IsTeardownDeclarationStart`, `ConsumeTestKeyword`,
  `ParseTestDeclaration`, `ParseSetupDeclaration`, `ParseTeardownDeclaration`, `ParseAttributes`,
  `ConsumeAttributeIdentifier` — all delegating construction to the shared `Report` / `ConsumeToken` /
  `ConsumeIdentifier` / `ParseArgumentList` / `ParseBlock` / `ParseParameterListRecovery` and reusing the live shared
  `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints / suggestions match Parser.cs
  automatically. VERIFIED PANIC INTERACTIONS (each pinned): two malformed tests BOTH report (declaration-boundary
  reset); a malformed test then a valid decl reports only the test error; a non-string skip reason before a body
  cascades the skip NL102 AND the block missing-`}` NL106 (block per-statement reset lets the NL106 record; the two are
  position-sorted so NL106 @col1 precedes the skip @col18); a non-identifier top-level attribute name (`[123]`) reports
  the ConsumeIdentifier NL102 then the `]` UnexpectedToken NL101 after the boundary reset re-dispatches (does-not-swallow-
  following); a non-identifier MEMBER attribute name (`class C { [123] … }`) cascades the attr-name NL102 and the
  field-name NL102 across the ParseMemberList member-boundary reset. +25 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (14 positive-diagnostic: test-desc-not-string / two-malformed-tests-boundary-reset /
  malformed-test-then-valid / skip-not-string / skip-then-body-cascade [NL106+NL102 position-sorted] / table-missing-`[`
  NL102 / table-row-missing-`(` NL102 / table-unclosed-`]` NL108 / attr-bad-name-then-`]`-NL101 / attr-bad-qualified-`.`
  dot-access NL102 / attr-unclosed-`]` NL108 / attr-unclosed-args-`)` NL107 / member-attr-bad-name-cascade [attr-name +
  field-name across member reset]; 11 negatives: empty-test / assert-body-test / valid-skip / valid-table / setup /
  teardown / valid-attr / valid-attr-args / valid-qualified-attr / two-stacked-attrs / member-attr / parameter-attr).
  DEFERRED / RECORDED (NOT corpus-pinned — with reasons): the malformed table-driven ROW shapes reached via a following
  `{ }` BODY (`test "d" with (a) 9 { }`, `test "d" with (a) [ 9 ] { }`) HANG the PRODUCTION parser — the row loop
  `while (!Check(RightParen) && !IsAtEnd()) ParseExpression()` does NOT force-advance and `ShouldSkipUnexpectedExpressionToken`
  returns false for a `}` / `]` expression-terminator sitting in the row-expression position, so `ParseExpression` spins;
  the model reproduces this loop faithfully, so pinning such a shape would hang the suite — the malformed table `[` / row
  `(` / cases `]` Consume sites are instead pinned at EOF (where the loop terminates and the leading Consume error is the
  single unsuppressed diagnostic), which exercises exactly those Consume sites. The bare-`test`-at-EOF description error
  is the Stage-5/12 EOF-length-0-clamp class (Current.Value.Length 0 vs the JSON clamp to 1) so the corpus uses a
  numeric bad description. NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the
  packaged SDK 0.1.0 self-emitted the edited owner — incl. all new parsers + all 1172 contracts cleanly — no repin).
  Evidence: BootstrapServices contracts 1172/1172 (1147 baseline + 25; full-suite fresh no-build run,
  `-p:NSharpExcludeTests=false`; `FullyQualifiedName~Test_016Attributes|~Test_016TestDsl` filter 25/25); dev.sh Parser
  381/381; ownership audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`); git status shows ONLY the two
  `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests:
  zero references outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code
  change → no extension reload. `ColumnarParserRecovery.nl` 6,640 → 6,841 lines (+201); `.tests.nl` 5,069 → 5,347 (+278).
  RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 16):
  [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE Stage 14] the MEMBER grammars + the record / interface /
  union / enum / soa type BODIES; [3 — DONE Stage 15] the richer type-reference forms (union / postfix array-nullable /
  byref / tuple / `Func<>`); [4 — DONE] the TEST DSL (test / setup / teardown + the table-driven case rows) and
  ATTRIBUTES (top-level / member / parameter) (this stage); [5] the garbage-type cascade shapes (non-identifier
  parameter name, named-tuple bad-name) needing `ParseTypeReference`-on-garbage + the stable position-sorted emit
  (unblocked since Stage 12), and the TYPE-ALIAS underlying-type consumer (`type T = A | B`, Parser.cs
  `ParseTypeAliasDeclaration` :1344/:1348 — the owner's `ParseTypeAliasName` parses only the alias NAME, not the
  `= <type>` body). THEN the AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc
  (N+3). Next: STAGE 17 = residual map item [5] (the garbage-type cascade shapes + the type-alias underlying-type
  consumer), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 15 of the parser-front-end arc — the richer
  TYPE-REFERENCE forms (residual map item [3]), carried through the SAME shared owner over the already-owned
  simple / qualified / generic type subset, PROVEN byte-exact against the freshly built Release CLI oracle
  (`nlc check --json`, filtered to the parser codes NL101-NL109, excluding the SEMANTIC diagnostics — not-all-paths-
  return NL305, type-not-found NL201, undefined-name NL301, etc. — which are analyzer, not parser, diagnostics).
  SITE INVENTORY (grep of `ParseTypeReference` + its helpers in Parser.cs :1774-2021): the entry `ParseTypeReference`
  (:1774) → `ParseUnionTypeReference` (:1779) → `ParsePostfixTypeReference` (:1814) → `ParseBaseTypeReference`
  (:1884). The COMPLETE reachable error-site surface: (a) the UNION layer's ONE new report — the NL103
  "Expected a type after '|' in anonymous union type" (:1793, InvalidSyntax, anchored on Current, length
  Max(1, Current.Value.Length), humanExplanation + hint, NO suggestions) fired when a `|` is IMMEDIATELY followed by
  a type terminator (`IsTypeTerminator`: Comma/RightParen/RightBracket/RightBrace/Newline/Eof/Assign/Semicolon/Arrow/
  Colon — NOTE `{` / `|` / an identifier are NOT terminators, so `A | {` / `A | | B` reach the ConsumeIdentifier NL102
  on the arm, and the shared lexer's newline-suppression-after-`|` means the arm greedily crosses a suppressed newline
  and consumes the next line's leading identifier), then BREAK (only the first trailing `|` reports; panic suppresses
  any later one regardless); (b) the POSTFIX layer's `[]` / `?[]` / `?` suffixes (:1821/:1832/:1854) — the array /
  nullable-array closes are LOOKAHEAD-GUARDED (`[` only when `]` immediately follows), so their `Consume(RightBracket)`
  NEVER fails — NO reachable diagnostic; they only shape the consumed extent so a following error anchors byte-exact;
  (c) the BASE dispatch — byref `&T` (:1886, inner is a POSTFIX type, no own report), the tuple / parenthesized type
  `( … )` (`ParseParenthesizedOrTupleTypeReference` :1965 — its closing `)` routes through the shared ConsumeToken so a
  missing `)` reaches the Stage-9 closing-delimiter recovery [NL107 at a line / same-line boundary, else the plain
  NL102], and its element types + the empty-tuple / bad-named-element cases reach the shared ConsumeIdentifier NL102),
  the `Func<…>` function type (`ParseFunctionTypeReference` :2000 — `Consume(Less)` [NL102 "Expected '<'", expected
  "less", or the ConsumeToken EOF NL104] + a comma-separated ParseTypeReference list + the split-`>>`-aware
  ConsumeGreater; unlike the generic identifier arm, `Func` does NOT call ReportMissingGenericTypeArgument, so
  `Func<>` / `Func<int,>` reach the ConsumeIdentifier NL102 on the `>` — verified divergent from `List<>` /
  `List<int,>`), and the simple / qualified / generic identifier arm owned since Stage 5. So the ONLY genuinely new
  report Stage 15 adds is the union NL103; every other reachable site reduces to an already-owned primitive
  (ConsumeIdentifier NL102/NL104, ConsumeToken NL102/NL107/NL108, ConsumeGreater NL102, ReportMissingGenericTypeArgument).
  IMPLEMENTATION: restructured `ParseTypeReferenceRecovery` into the union entry (the `|`-arm loop + `ReportUnionMissingTypeArm`)
  → `ParsePostfixTypeReferenceRecovery` (the `[]` / `?[]` / `?` loop) → `ParseBaseTypeReferenceRecovery` (byref / tuple /
  Func dispatch + the moved simple/generic body) + `ParseParenthesizedOrTupleTypeReferenceRecovery` +
  `ParseFunctionTypeReferenceRecovery`, all delegating construction to the shared `Report` / `ConsumeIdentifier` /
  `ConsumeToken` / `ConsumeGreater` / `ReportMissingGenericTypeArgument` and reusing the live shared `IsTypeTerminator`
  / `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints / suggestions match Parser.cs
  automatically. RETIRED the narrower `ParseSimpleTypeReference` (the Stage-4 minimal single-identifier vehicle):
  Parser.cs threads PARAMETER (`ParseParameterTypeReference` :6507), FIELD (`ParseFieldTypeReference` :6543), and
  `let`-declaration (`ParseVariableDeclaration` :2553) types through the FULL `ParseTypeReference` — so its three
  callers now route through `ParseTypeReferenceRecovery`, closing a latent parity gap (a generic / union / tuple /
  byref param or field type would previously have diverged) and giving the mandate's parameter/field consumers the
  full grammar; the speculative expression-statement typed-decl (`ParseExpressionStatement` :4244) already used it.
  SHARED-CONSUMER PROOF SITES (chosen representative, not exhaustive cross-products): the union NL103 pinned at the
  RETURN-type (`func f(): A |`), FIELD (`struct S { x: A | }`), CATCH (`catch (e: A |)`), IS-EXPRESSION
  (`x is A |`), and TYPED-DECLARATION (`x: A | = y`) sites — proving all five owned consumers thread the SAME grammar;
  the postfix / byref / tuple forms proven CONSUMED via the "form-then-trailing-`|`" shape (`A[] |` / `A? |` / `&A |` /
  `(int, string) |` each report the union NL103 AFTER the form, which only fires if the form was consumed to exactly
  the byte-position Parser.cs reaches); the generic-arg / tuple-element / Func-param recursion proven via the nested
  negatives (`List<A | B>`, `Func<Func<int, string>, bool>`); the base-list via the valid `class C : A | B`; the
  parameter consumer via `func f(x: &)`. +33 native parity contracts in `ColumnarParserRecovery.tests.nl` (19
  positive-diagnostic: union NL103 at return / field / typed-decl / catch / is-expr; array-then-`|` / nullable-then-`|`
  / byref-then-`|` / tuple-then-`|` NL103; byref-missing-inner NL104 [return] + NL102 [param `&)`]; tuple unclosed-`)`
  NL107 / empty-`()` NL102 / bad-named-element NL102; Func missing-`<` NL104 / unclosed-`>` NL102 / empty-`<>` NL102
  [divergent from generic] / trailing-comma NL102; the union arm greedily consuming across the `|`-suppressed newline
  [one NL102 field-name, not two]; 14 negatives: valid union / array / nullable / nullable-array / byref-param / tuple /
  named-tuple / single-unwrap / Func / multi-Func / union-in-generic-arg / nested-Func-`>>` / is-union / base-list-union).
  DEFERRED / RECORDED (NOT corpus-pinned — with reasons): the TYPE-ALIAS underlying type (`type T = A | B`) is NOT an
  arc-owned consumer — the owner's declaration preamble parses only the alias NAME (`ParseTypeAliasName`), not the
  `= <type>` body (Parser.cs `ParseTypeAliasDeclaration` :1344/:1348 does, via `ParseTypeReference`) — so the type-alias
  vehicle is out of Stage-15 scope; adding it is a separate consumer slice. The CAST site `(A | )x` does NOT reach the
  type-union grammar: the `IsCastExpression` lookahead requires a well-formed cast type, so a malformed `A |` fails the
  scan and the whole `(A | )` is parsed as a PARENTHESIZED bitwise-OR EXPRESSION (the Stage-7 "Expected expression
  after '|'" NL102), not a cast type — an expression diagnostic, already owned. The `new`-expression type
  (`ParseNewTypeReference`) routes through the same upgraded `ParseTypeReferenceRecovery`, so it inherits the full
  grammar for free (no separate pin — the new corpus is expression-side). NO production wiring; NO wall tripped
  (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner — incl. the
  ParseTypeReferenceRecovery restructure + ParseSimpleTypeReference retirement + all new parsers + all 1147 contracts
  cleanly — no repin). Evidence: BootstrapServices contracts 1147/1147 (1114 baseline + 33; full-suite fresh no-build
  run, `-p:NSharpExcludeTests=false`; `FullyQualifiedName~016TypeRef` filter 33/33); dev.sh Parser 381/381; ownership
  audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`); git status shows ONLY the two `.nl` files +
  STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble`
  are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests: zero references
  outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code change → no
  extension reload. `ColumnarParserRecovery.nl` 6,520 → 6,640 lines (+120); `.tests.nl` 4,731 → 5,069 (+338).
  RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 15):
  [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE Stage 14] the MEMBER grammars + the record / interface /
  union / enum / soa type BODIES; [3 — DONE] the richer type-reference forms (union / postfix array-nullable / byref /
  tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc/catch/typed-decl/local-func-return/base-lists/
  member-return-types/parameter/field/new/generic-args/tuple-elements/Func-params (this stage); [4] the TEST DSL
  (test / setup / teardown + the test-case rows) and ATTRIBUTES (member + declaration); [5] the garbage-type cascade
  shapes (non-identifier parameter name, named-tuple bad-name) needing `ParseTypeReference`-on-garbage + the stable
  position-sorted emit (unblocked since Stage 12); and the TYPE-ALIAS underlying-type consumer (recorded above). THEN
  the AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 16 =
  the TEST DSL + ATTRIBUTES (map residual [4]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 14 of the parser-front-end arc — the MEMBER
  grammars + the remaining type BODIES (residual map item [2]), carried through the SAME shared-panic model over the
  already-owned expression / statement / type / delimiter / block grammars, PROVEN byte-exact against the freshly
  built Release CLI oracle (`nlc check --json`, filtered to the parser codes NL101-NL109, excluding the SEMANTIC
  diagnostics — not-all-paths-return NL305, undefined-name NL3xx, etc. — which are analyzer, not parser,
  diagnostics). SITE INVENTORY (grep of the type-declaration + `ParseMemberList`/`ParseMemberDeclaration` +
  `ParseFieldDeclaration`/`ParseFunctionDeclaration`/`ParseConstructorDeclaration`/`ParseIndexerDeclaration` grammars
  in Parser.cs): (a) the MEMBER dispatch — `ParseMemberDeclaration` (:1412): the preprocessor member (:1415), the
  modifiers (attributes are residual [4], omitted like the top-level dispatch), the nested-type declarations
  (class / ref-struct / struct / soa / record / enum / union / interface, :1428-1460), the `constructor` contextual
  identifier (:1463), the `func this[…]` indexer (:1469), the method / conversion-operator (:1475), and the
  field/property fall-through (:1481); `ParseMemberList` (:1359) now dispatches this full grammar (was FIELD-only at
  Stage 4) with the member-boundary panic reset, the `_currentRecoveryBoundaryColumn` save/set/restore around each
  member (:1367-1376), and the no-progress `SynchronizeToNextStatement`-then-force-advance (:1379-1388). (b) METHODS
  `ParseMethodMember` (Parser.cs `ParseFunctionDeclaration` :373 reached as a member) — the keyword-anchored name
  (`ConsumeDeclarationName`, DiagnosticSpanFromToken(funcToken), :435), `func*` generators (:409), `async`
  (via `ParseModifiers`), `func operator SYM` overloads (:415, `ParseOperatorSymbol` :5752 + the invalid-symbol
  NL103), `implicit`/`explicit operator` conversions (:393, return type BEFORE params :452), the `: T`/`-> T` return
  type or the `ReportMissingReturnTypeMarker` (NL102, name/operator-keyword-anchored, length = the NAME length so
  `func A() int` reports length 1 while `func Foo() int` reports 3), the `returns`-lifetime + generic constraints,
  and the `=> expr` / `{ }` body — with NO missing-body report (an abstract / interface method with no body is
  valid, unlike a local function). (c) CONSTRUCTORS `ParseConstructorMember` (:1484) — the `constructor` identifier,
  the parameter list, the optional `: this(args)` / `: base(args)` initializer (each `Consume(LeftParen)` +
  `ParseArgumentList`), the "Expected 'this' or 'base' after ':'" NL102 (+ skip the offender), and the block body
  (owner span on `constructor`, length 11). (d) INDEXERS `ParseIndexerMember` (:1564) — `func this[params]: retType
  { get/set }`, the `[`/`]`/`:`/`{` Consumes, the parameter loop (`ConsumeParameterColon`), and the accessor loop's
  "Expected 'get' or 'set' accessor, got X" NL102 (:1613) + skip. (e) PROPERTIES — `ParseFieldMember` extended
  (Parser.cs `ParseFieldDeclaration` :1637): the leading `required`/`init`/`readonly` property modifiers (:1644),
  the `:=` inferred form, the expression-bodied `=> expr` property (:1683), and the `{ get/set }` accessor block
  with the ", got X" invalid-identifier NL102 (:1718, anchored on the token AFTER the accessor, length = the bad
  accessor's) + skip, the ". Got X" non-identifier NL102 (:1738) + skip, and the "Expected '}' after property
  accessors" close (:1756); the `= initializer` field via `ParseRequiredExpressionAfter` (:1762). (f) the class /
  struct / record positional (primary-ctor) parameter lists (`(…)` after the type-params, :947/:992/:1037) and the
  base / interface lists (`: T, U`, `ParseBaseTypeList`, :955/:998/:1043/:1150) — added to `ParseClassName` /
  `ParseStructName` / `ParseRecordName` / `ParseInterfaceName`. (g) the record / interface type BODIES route through
  the shared `ParseMemberList` (like class/struct); the UNION body (`ParseUnionBody`, :1179) has its OWN case loop
  (the "Expected union case name" ConsumeIdentifier, the `{ prop: type, … }` payload with its "Expected ':'"
  ConsumeToken + `EnsureProgress`-per-property, the `EnsureProgress`-then-panic-reset per case, and the union-specific
  missing-`}` NL106 anchored on the union name / keyword, "The union body that started on line N…"); the ENUM body
  (`ParseEnumBody`, :1274) has its OWN member loop (the optional `= value` via `ParseExprValue`, the comma-or-break,
  the "Expected enum member name", and the enum-specific missing-`}` NL106) plus the optional `: int|string` backing
  type ("Expected enum backing type" + the "Unsupported enum backing type 'X'" NL101, length via the shared Create
  default-0 fallback → the type-name length); the SOA body (`ParseSoaRecordBody`, :1085) has its OWN column loop
  (the "Expected soa column name", the "Expected ':'" ConsumeToken, the trailing `,`/`;`, the per-column panic reset,
  and the soa-specific missing-`}` NL106) plus the generic-soa `<…>` "soa record type parameters are not supported
  yet" NL103. RETIRED the stage-2 deferred non-`{` braced found-other cases for record / interface / union / enum /
  soa: their name parsers now capture the name-token span (or the declaration-keyword span for a `<error>` name) and
  parse the body, exactly like class/struct since Stage 4, so a `record {` / `union {` etc. flows into body parsing
  byte-exact (verified against the oracle with the Stage-12 position-sort in place). IMPLEMENTATION: extended
  `ParseMemberList` + `ParseFieldMember` and added ~18 new parser methods + reports (`ParseMemberDeclaration`,
  `ParseConstructorMember`, `ParseIndexerMember`, `ParseMethodMember`, `ParseOperatorSymbol`, `IsOverloadableOperator`,
  `ParseBaseTypeList`, `ParseUnionBody`, `ParseEnumBody`, `ParseSoaRecordBody`, `ReportTypeBodyMissingClosingBrace`,
  `ReportConstructorInitializerTarget`, `ReportIndexerAccessorInvalid`, `ReportPropertyAccessorInvalidIdentifier`,
  `ReportPropertyAccessorExpectedGetSet`, `ReportSoaTypeParametersUnsupported`, `ReportEnumBackingTypeUnsupported`),
  all delegating construction to the shared `Report` / `ConsumeToken` / `ConsumeIdentifier` /
  `ParseRequiredExpressionAfter` and reusing the live shared `ParserTokenFacts` / `ParserErrorDiagnostics.Create`, so
  codes / messages / spans / snippets / hints / suggestions match Parser.cs automatically. VERIFIED PANIC INTERACTIONS
  (each pinned by a contract): two class methods each missing the `:` marker BOTH report (member-boundary reset); two
  properties each with a bad accessor BOTH report; a body-less method's missing-marker panic-suppresses the type-body
  EOF missing-`}` (one diagnostic); an unclosed NESTED enum reports its OWN missing-`}` and panic-suppresses the outer
  class body's; the invalid-accessor / bad-init-target cascades produce the byte-exact trailing "Unexpected token '}'"
  / EOF missing-`}` the oracle produces. +36 native parity contracts in `ColumnarParserRecovery.tests.nl` (20
  positive-diagnostic: interface-method-missing-marker / two-methods-each-report / method-missing-marker-suppresses-
  type-`}` / ctor-bad-init-target-then-`}` / ctor-this-missing-`(` / prop-non-ident-accessor / prop-invalid-ident-
  accessor-then-`}` / two-props-each-report / indexer-invalid-accessor-then-`}` / record-positional-param-colon /
  union-case-name / union-missing-`}` NL106 / union-payload-missing-`:` / enum-member-name-then-cascade / enum-
  unsupported-backing NL101 / enum-missing-`}` NL106 / soa-missing-`:` / soa-generic NL103 / soa-missing-`}` NL106 /
  nested-enum-missing-`}`; 3 stage-2 found-other retirement: record/union/enum whose name is a `{`; 13 negatives:
  method block / generator func* / async / expr-body / operator-overload / implicit-conversion / ctor-this-init /
  property-get-set / expr-body-property / nested-enum / union-payload / interface-members / record-positional).
  DEFERRED (recorded, NOT corpus-pinned — with reasons): the operator-symbol
  INVALID case (`func operator @`) is modelled faithfully (`ParseOperatorSymbol`'s NL103) but corpus-light (the corpus
  uses valid operators); the `returns`-lifetime body is shared-owned (Stage 13) and unchanged; the richer
  type-reference forms in base lists / indexer return types / method return types (union / postfix array-nullable /
  byref / tuple / `Func<>`) remain shared residual [3] (the member corpus uses simple / qualified / generic type
  names). NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0
  self-emitted the edited owner — incl. `ParseMemberList`/`ParseFieldMember` refactors + all new parsers + all 1114
  contracts cleanly — no repin). Evidence: BootstrapServices contracts 1114/1114 (1078 baseline + 36; full-suite
  fresh no-build run, `-p:NSharpExcludeTests=false`; `FullyQualifiedName~016Member|016TypeBody` filter 33/33 [+ the 3
  found-other retirement contracts under the decl-name/type-body names]); dev.sh Parser 381/381; ownership audit 18/18
  (`nlc test --project tests/native/ownership-audit`); git status shows ONLY the two `.nl` files + STATUS (no non-N#
  file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced
  ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests: zero references outside the owner +
  its tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension reload.
  `ColumnarParserRecovery.nl` 5,826 → 6,520 lines (+694); `.tests.nl` 4,303 → 4,731 (+428). RESIDUAL-TO-PARITY MAP
  (what remains for full Parser.cs syntax-diagnostic parity, after Stage 14):
  [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE] the MEMBER grammars + the record / interface / union /
  enum / soa type BODIES (this stage); [3] the richer type-reference forms (union / postfix array-nullable / byref /
  tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc/catch/typed-decl/local-func-return/base-lists/
  member-return-types; [4] the TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES (member +
  declaration); [5] the garbage-type cascade shapes (non-identifier parameter name, named-tuple bad-name) needing
  `ParseTypeReference`-on-garbage + the stable position-sorted emit (unblocked since Stage 12). THEN the
  AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 15 =
  the richer type-reference forms (map residual [3]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 13 of the parser-front-end arc — the REMAINING
  STATEMENT kinds (residual map item [1]), carried through the SAME shared-panic model over the already-owned
  expression / type / pattern / delimiter grammars, PROVEN byte-exact against the freshly built Release CLI oracle
  (`nlc check --json`, filtered to the parser codes NL101-NL109, excluding the line-0 columnar-backend decline and
  the SEMANTIC diagnostics — loop-context for break/continue/yield, generator-return NL202, undefined-name
  NL301/NL412, unused-local NL001 — which are analyzer, not parser, diagnostics). SITE INVENTORY (grep of the
  ParseStatement dispatch + helpers in Parser.cs): (a) the SIMPLE keyword statements with ZERO own error sites —
  `break` (:2885) / `continue` (:2967) (the guarded `Consume` never fires) / `preprocessor` (:2875) / `off`
  (:2957, `IsOffStatementStart` + a bare `ParseExpression` handle); (b) the REQUIRED-EXPRESSION statements routed
  through the already-owned `ParseRequiredExpressionAfter` (the `ShouldUnderlineAnchorForMissingRequiredExpression`
  set already carries Throw/Yield/Assert/Using/Lock/Switch) — `throw` (:2975, "an exception expression"), `yield`
  (:2839, "a value to yield" or the `yield break` no-value form), `assert` (:2388, "a condition expression" + the
  optional `, message` + the `assert throws Type { … }` form), `lock` (:3128, "an object expression" + optional
  parens; the "Expected block statement after lock" report is UNREACHABLE dead C# — `ParseBlock` always yields a
  block); (c) the BLOCK-bearing statements routed through the new `ParseBlock` (Consume-first, the Parser.cs :2143
  entry the block-bearing kinds call directly, refactored to share `ParseBlockStatementsLoop` with the Stage-6
  `ParseBlockBody`) — `unsafe` (:2379) / `alloc { … }` (:2301, the `Alloc && LookAhead=={` compound dispatch) /
  `try`-`catch`-`finally` (:2988, the catch parameter list `(Type e)` / `(e: Type)` / bare forms, the catch type
  via the owned `ParseTypeReferenceRecovery`, the catch `)` via the Stage-9 closing-delimiter recovery [NL107]);
  (d) the STATEMENTS with their OWN diagnostics — `using` (:3048, the `Consume(ColonAssign)` "Expected ':='" [NL102,
  expected "colonassign"] + the `using let (a, b)` invalid-tuple InvalidSyntax [NL103] anchored on the single-line
  `(…)` pattern span via the ported `TryGetSingleLineDelimiterSpanAt` :5968), `switch` (:3170, `Consume(LeftBrace)` +
  the per-case `Consume(Arrow)` [expected "arrow"] + the "Expected 'case' or 'default'" [NL102] skip-and-continue/
  break arm + the switch-specific missing-`}` [NL106, its own body-line message] distinct from the block NL106),
  `allow` (:2310, `Consume(LeftParen, "…after 'allow'")` + the effect loop's `ConsumeSystemsIdentifier` [NL102] +
  `Consume(Comma, "…between allow arguments")` + the `if (Current == nameToken) Advance()` force-advance modelled by
  a position guard + the trailing `Consume(RightParen)`; `ParseAllowEffectValue` + the reason/owner named args),
  `local-function` (:2419, `[static][async] func Name<…>(…)`; the LOCAL func uses plain `ConsumeIdentifier` for the
  name NOT the keyword-anchored `ConsumeDeclarationName`, and reaches `ReportMissingReturnTypeMarker` [NL102 "Expected
  ':' before return type", name-anchored via `IsLikelyMissingReturnTypeMarker`], the `-`-`>` return-type arrow's
  `Consume(Greater)`, the `ParseReturnLifetimeAnnotation` `returns` grammar [ported faithfully, corpus-light], and
  the missing-body ReportError [NL102 "Expected function body or '=>'…"]), `on` (:2893/:3649, the highest-precedence
  `ParseExprValue` prefix — `IsOnSubscriptionStart` + `ParseEventTarget` [a primary + member/index chain that STOPS
  before a `(` so the handler's parameter list is not swallowed; the member `ConsumeIdentifier("Expected event or
  member name after '.'")` reaches the dot-access NL102 variant] + the handler-is-lambda check [pre-detected via the
  two `ParseExprValue` lambda prefixes, avoiding an ExprResult flag] + the "Expected an event handler lambda" [NL103]
  when the handler is not a lambda); (e) the `for` (:2651) C-STYLE `for (init; cond; incr)` branch appended after the
  two foreach-style branches — optional parens, the `let`/`:=`/bare-expr initializer, the two `Consume(Semicolon)`
  [NL102, the `;` hint], the optional condition/iterator, and the optional `Consume(RightParen)` via the Stage-9
  recovery [NL107]; (f) `await foreach` (:2776) mirroring foreach with the `ConsumeInOrReportMissing` shared idiom +
  the "This await foreach statement" owner description; (g) `ParseVariableDeclaration` extended with the
  `(x, y) := …` TUPLE deconstruction dispatch (returns a bool so `using` can distinguish it) + `ParseTupleDeconstruction`
  [the name list, the "Tuple deconstruction requires ':=' or '='" NL102, the skip-the-offender + required-initializer]
  and `ParseExpressionStatement` extended with the typed `name: T = value` declaration [speculative parse + rewind on
  no `=`; NL102 "…after '='" name-anchored], the no-paren `x, y := e` and paren `(x, y) := e` tuple forms.
  IMPLEMENTATION: extended the `ParseStatement` dispatch in Parser.cs order (await-foreach compound before while, then
  yield/break/continue/throw/try/using/lock/switch/allow/alloc-block/unsafe/…/assert/preprocessor, then the
  static-async-func local-function forms, then the `off` contextual dispatch before the expression statement); added
  the ~30 new parser methods + reports (all delegating construction to the shared `Report` /
  `ParseRequiredExpressionAfter` / `ConsumeToken` / `ConsumeIdentifier`, and every boundary DECISION reusing the live
  shared `ParserTokenFacts`, so codes / messages / spans / snippets / hints / suggestions match Parser.cs
  automatically); refactored `ParseBlockBody`→`ParseBlockStatementsLoop`+`ParseBlock` (the Consume-first block entry).
  VERIFIED PANIC INTERACTIONS (each pinned by a contract): switch's missing-`{` panic still-set suppresses the func's
  own EOF missing-`}` (one diagnostic, not two); two switches each with a bad branch BOTH report (per-statement
  boundary reset); two functions each with a body-less local function BOTH report (declaration-boundary reset); the
  `on w. => 1` dot-access NL102 panic-suppresses the trailing non-lambda NL103 (one diagnostic). +45 native parity
  contracts in `ColumnarParserRecovery.tests.nl` (22 positive-diagnostic: yield-missing / throw-missing / lock-missing
  / catch-unclosed-`)` NL107 / switch-missing-`{` / switch-bad-branch / switch-missing-arrow / switch-missing-`}` NL106
  / allow-missing-`(` / allow-bad-effect / assert-missing / local-func-missing-body / local-func-missing-return-colon /
  await-foreach-missing-in / c-for-missing-`;` / c-for-missing-`)` NL107 / tuple-missing-`:=` / typed-decl-missing-init /
  using-missing-`:=` / using-invalid-tuple NL103 / on-non-lambda NL103 / on-missing-member-after-dot; 4 panic-interaction:
  switch-panic-suppresses-func-`}`, two-switches-each-report, two-local-funcs-each-report, on-dot-suppresses-non-lambda;
  19 negatives: yield-break / yield-value / break-continue-in-loop / throw-expr / try-catch-finally / catch-typed-var /
  lock-obj / lock-parens / unsafe / alloc / assert-cond+msg+throws / preprocessor / local-func block+expr+static /
  await-foreach / c-for paren+bare / tuple paren+no-paren / typed-decl / using-let+ident / off / on single+multi lambda).
  DEFERRED (recorded, NOT corpus-pinned — with reasons): the `allow` missing-`)` shape is really a "missing comma"
  cascade that, under the shared panic set by the first NL102, consumes to EOF with every further report suppressed —
  the loop (incl. the force-advance) is modelled faithfully and the OUTPUT is the single NL102, but the whole-file
  consumption is fragile to pin so the corpus keeps the clean allow shapes; the `returns` lifetime body of
  `ParseReturnLifetimeAnnotation` is ported faithfully but corpus-light (no `returns` annotation in the statement
  corpus); the richer type-reference forms in catch / typed-decl / assert-throws types (union / postfix array-nullable /
  byref / tuple / `Func<>`) remain shared residual [3] (the corpus uses simple / qualified / generic type names). NO
  production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted
  the edited owner — incl. the `ParseBlock` refactor + all new parsers — + all 1078 contracts cleanly — no repin).
  Evidence: BootstrapServices contracts 1078/1078 (1033 baseline + 45; full-suite fresh no-build run,
  `-p:NSharpExcludeTests=false`; `FullyQualifiedName~Test_016Stmt` filter 70/70 = 45 new + 25 Stage-6); dev.sh Parser
  381/381; ownership audit 18/18 (`nlc test --project tests/native/ownership-audit`); git status shows ONLY the two
  `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests:
  zero references outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code
  change → no extension reload. `ColumnarParserRecovery.nl` 4,854 → 5,826 lines (+972); `.tests.nl` 3,784 → 4,303
  (+519). RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 13):
  [1 — DONE] the remaining statement kinds (this stage); [2] the MEMBER grammars (method / constructor / nested-type /
  record-positional / union-case / interface / property) + the record / interface / union / enum / soa type BODIES
  (each with its own missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [3] the richer type-reference
  forms (union / postfix array-nullable / byref / tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc/
  catch/typed-decl/local-func-return; [4] the TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES;
  [5] the garbage-type cascade shapes (non-`{` braced found-other, non-identifier parameter name, named-tuple bad-name)
  needing `ParseTypeReference`-on-garbage + the stable position-sorted emit (unblocked since Stage 12). THEN the
  AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 14 =
  the MEMBER grammars + type BODIES (map residual [2]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED): STAGE 12 of the parser-front-end arc — the
  interpolated-string `$"…"` HOLE grammar (`ParseInterpolatedString`, Parser.cs :4932). Extended
  `ColumnarParserRecovery.nl` to carry the hole grammar through the SAME shared-panic model, PROVEN byte-exact
  against the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109, excluding the columnar-backend
  emit-decline NL103 anchored at line 0). SITE INVENTORY (grep of `ParseInterpolatedString`): the whole `$"…"`
  is ONE outer token whose VALUE is char-scanned; the method has ZERO `Consume` sites and exactly ONE explicit
  ReportError — the NL101 "Unexpected token 'X' after interpolated string expression" hole-tail (:5141) — but
  EVERY hole-EXPRESSION error is produced by a FRESH sub-Lexer + sub-Parser (`new Parser(subTokens, _fileName)`,
  sourceCode=null → the CLI re-attaches the snippet by line number, verified) reaching the owned expression
  grammar. The scan carries `{{`/`}}` escapes, non-raw `\` escapes, the raw `{`-literal heuristic (:5019), position
  tracking through text/holes (`AdvancePosition` newline handling), the `braceDepth` + `inNestedString` hole-content
  scan (:5051), the raw-with-newlines literal edge (:5101), the format-clause `:` split via the live shared
  `ParserLiteralFacts.FindFormatSpecifierColon` (:5117, the same function Parser.cs calls), token position
  adjustment (`tok.Line + exprStartLine - 1` / same-line `tok.Column + exprStartCol - 1`, :5129-5135), and the
  closing-`}` consume. VERIFIED PANIC INDEPENDENCE (each probed against the oracle and pinned by a contract): each
  hole's sub-parser has its OWN `_panicMode`, so (a) TWO bad holes in one string BOTH report — `$"{a +} {b +}"` →
  two NL102, `$"{a b} {c d}"` → two NL101; (b) the OUTER parser's panic is UNAFFECTED by hole errors AND a hole
  error records even when the outer parser is mid-panic, because Parser.cs appends the sub-parser's errors via
  `_errors.AddRange(...)` which BYPASSES the outer panic gate — `print + $"{b +}"` → BOTH the outer prefix-plus
  NL103 AND the hole NL102; (c) WITHIN a hole the sub-panic cascades, so a hole-EXPRESSION error SUPPRESSES the
  hole-tail — `$"{+ a b}"` → only the prefix-plus NL103, the trailing `b` swallowed. IMPLEMENTATION: added the
  interpolated dispatch to `ParsePrimaryExprValue`'s string-literal arm (Parser.cs :4654-4657 — a `$"`-prefixed
  StringLiteral or an InterpolatedRawStringLiteral routes to `ParseInterpolatedString`; the malformed NL105 check
  still runs FIRST), reached through the Stage-6 block-body statement vehicle `func f() { print $"…" }` (the Stage-3
  `=>` expression body uses the minimal literal vehicle and does NOT descend `ParsePrimaryExprValue`, so the corpus
  uses the block vehicle); `ParseInterpolatedString` (the full char-scan port — the C# local closures
  `AdvancePosition`/`AppendText`/`EmitText` are inlined/dropped since N# has no first-class Func values AND the text
  parts carry no diagnostic); `ParseHoleExpression` (the fresh sub-parse — the recovery model is a SINGLE instance,
  so a hole SAVES the outer cursor/panic/split/boundary state, swaps in the position-adjusted + Newline-compacted
  sub-token stream with `PanicMode=false` (a fresh panic universe → hole errors record even under outer panic,
  reproducing the AddRange bypass), runs `ParseExprValue` + the hole-tail, then RESTORES the outer state (so the
  hole never affects the outer panic universe); Errors + Source are SHARED, so hole diagnostics accumulate and the
  CLI's by-line snippet re-attachment matches the model's Source-based snippet automatically; nested holes recurse
  naturally via the sub-parse's own `ParsePrimaryExprValue`); and the helpers `IndexOfCharFrom` /
  `RangeContainsNewline` / `ContainsNewline` / `EndsWithString` (a hand-rolled ordinal EndsWith so the owner needs
  no `import System`). Also added a STABLE position-sort to `ParseFilePreamble` mirroring the CLI's
  `OutputFormatter.DeduplicateAndSortDiagnostics` → `CodeIntelligenceResultKernels.DiagnosticIndexComesAfter`
  (File, Line, Column, stable index): a hole diagnostic is RECORDED before a following outer-expression diagnostic
  positioned EARLIER (e.g. `print $"{a +}" +` — the hole dangling at col 21 is recorded before the outer dangling
  span at col 18), and the CLI presents diagnostics position-sorted; the stable sort is a proven no-op for every
  already-in-order family (full suite 1033/1033, no Stage 1-11 contract moved). +21 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (7 negatives: hole-free / single hole / two holes / format `{x:D3}` / escaped
  `{{ }}` / nested `{g($"{y}")}` / raw `$"""…"""`; dangling-hole NL102; hole-tail NL101; hole-tail-first-trailing-
  only; two-bad-holes-EACH-report NL102 [independence]; two-tails-EACH-report NL101; bad-first/good-second; good-
  first/bad-second; two-DIFFERENT-error-kinds independent; expr-error-SUPPRESSES-tail [sub-panic gate]; format-
  expr-bad [format stripped]; nested-bad-inner [recursive composed positions, col 26]; raw-hole-bad; INTERLEAVE
  outer-prefix-plus + hole BOTH report [outer panic does not suppress the hole]; INTERLEAVE hole-recorded-first-
  positioned-after outer-dangling [position-sort]). DEFERRED (recorded, NOT covered — with reasons): the EMPTY
  hole `$"{}"` — the sub-parse's unexpected-token terminal fires at the sub-EOF with `Current.Value.Length == 0`,
  and the check pipeline clamps the JSON length 0→1, so the model's raw CompilerError (length 0) is unmatchable
  against the clamped golden (length 1) — the SAME EOF-length-clamp class Stage 5 deferred for the EOF-anchored
  `ConsumeGreater`; the raw multi-line `{`-literal heuristic + raw-with-newlines literal edge are PORTED faithfully
  but corpus-light (single-line raw only — a multi-line raw string placed in the block vehicle would swallow the
  block's closing `}`). NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the
  packaged SDK 0.1.0 self-emitted the edited owner + all 1033 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 1033/1033 (1012 baseline + 21; full-suite fresh no-build run,
  `-p:NSharpExcludeTests=false`; interpolation-only filter 21/21); dev.sh Parser 381/381; ownership audit 18/18
  (18 native tests; ratchet 0 refs to any `.nl` — no movement); git status shows ONLY the two `.nl` files + STATUS
  (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble`
  are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests), so nothing in
  the production compile path changed. No LSP/VS Code change → no extension reload. `ColumnarParserRecovery.nl`
  4,476 → 4,854 lines (+378); `.tests.nl` 3,516 → 3,784 (+268). RESIDUAL-TO-PARITY MAP (what remains for full
  Parser.cs syntax-diagnostic parity, after Stage 12): [1] the remaining statement kinds (yield / break / continue /
  throw / try / using / lock / switch / allow / alloc-stmt / unsafe / assert / preprocessor / local-function /
  await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction / typed `name: T = value` declarations +
  the `on` subscription; [2] the MEMBER grammars (method / constructor / nested-type / record-positional /
  union-case / interface / property) + the record / interface / union / enum / soa type BODIES (each with its own
  missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [3] the richer type-reference forms (union /
  postfix array-nullable / byref / tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc; [4] the
  TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES; [5] the garbage-type cascade shapes
  (non-`{` braced found-other, non-identifier parameter name, named-tuple bad-name) needing `ParseTypeReference`-on-
  garbage + position-sorted emit — NOW UNBLOCKED on the emit side by the stable position-sort added this stage.
  THEN the AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next:
  STAGE 13 = the remaining statement kinds (map residual [1]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 11 of the parser-front-end arc — the remaining
  keyword-led primaries (map item [1]: alloc / stackalloc / lambda) + the `is`/`as` type sub-grammar (map item [2]).
  Extended `ColumnarParserRecovery.nl` to carry, through the SAME shared-panic model, four sub-families end-to-end,
  PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109, excluding the
  columnar-backend emit-decline NL103 anchored at Main.nl:1:1). ORIGIN INVENTORY (grep of Parser.cs): (a) the `is`/
  `as` TYPE arms (`ParseRelationalExpression` :4140/:4153) — both call `ParseTypeReference` (the type sub-grammar);
  `is` also consumes an optional trailing pattern-variable identifier (no diagnostic). Reused the already-owned
  `ParseTypeReferenceRecovery` (the simple / qualified / generic subset — the identical typeof / sizeof / cast type-
  reference vehicle), so the is/as type errors (missing type name NL102, qualified `.` NL102, `Name<>` generic-arg
  NL102, unclosed `>` NL102, reserved-keyword NL109) fire byte-exact; the `<` after an is/as type is absorbed as a
  generic open (verified). The invalid-relational default (:4177) is an unreachable dead arm (peeled before it).
  (b) the ALLOC primary (`ParseAllocExpression` :5178, dispatched :4747) — the guarded `Consume(Alloc)` never fires;
  the new / array-literal / string-primary / unary sub-shape all delegate to already-owned grammars, so alloc adds no
  new error site (missing-operand routes to the NL101 unexpected-token terminal; `alloc new` with no type to the
  Stage-10 ParseNewTypeReference NL102). (c) the STACKALLOC primary (`ParseStackAllocExpression` :5197, dispatched
  :4752) — element `ParseTypeReference` + `Consume(LeftBracket, "…after stackalloc element type")` (distinct NL102) +
  length `ParseExpression` + `Consume(RightBracket, "…after stackalloc length")` (NL108 next-line/EOF via the Stage-9
  closing-delimiter recovery, else the distinct NL102 when the mid-line offender declines recovery). (d) the LAMBDA
  family (`ParseLambdaOrAssignmentExpression` :3641) — single-param `x => …` (:3652, gated `Check(Identifier) &&
  LookAhead(1)==Arrow`) and multi-param `(x,y) => …` (:3681, gated `IsLambdaExpression` :5535 — a bounded lookahead
  admitting ONLY a well-formed `( ident, … ) =>`, so `ParseMultiParameterLambda`'s ConsumeIdentifier / Consume(
  RightParen) / Consume(Arrow) sites never fire; the ONLY reachable error is the missing lambda body via the already-
  owned `ParseRequiredExpressionAfter` with span `DiagnosticSpanFromTokenRange(paramOr'('→'=>')`). The `on`
  subscription prefix (:3649) is a separate deferred family. IMPLEMENTATION: added the is/as arms to `ParseRelational`;
  the alloc / stackalloc arms to `ParsePrimaryExprValue` (between unchecked and new, Parser.cs order); the two lambda
  prefixes to the top of `ParseExprValue` (Parser.cs ParseExpression→ParseLambdaOrAssignmentExpression, so every
  ParseExpression consumer allows lambdas) + the new `IsLambdaExpression` (pure token-scan, the IsGenericMethodCall
  idiom) and `ParseMultiParameterLambda`. DECISIONS reuse the live shared `ParserTokenFacts` and CONSTRUCTION
  delegates to the live shared `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints /
  suggestions match automatically. +31 native parity contracts in `ColumnarParserRecovery.tests.nl` (is/as: 4
  negatives [is / is-with-var / as / is-generic], missing-type NL102 [is / as / in-arg], `List<>` generic-arg NL102,
  qualified-`.` NL102, unclosed-`>` NL102, reserved-keyword NL109, two-`is`-statement-boundary-reset [NL101 swallowed-
  name then NL102]; alloc: 3 negatives [new / array / in-arg], missing-operand NL101, `alloc new` missing-type NL102;
  stackalloc: 2 negatives [int[4] / generic-element], missing-`[` NL102, missing-type NL102, unclosed-`]` NL108,
  mid-line-`]`-declines-then-stray-`]` [NL102 + NL101]; lambda: 4 negatives [single / multi / empty / block-body],
  single missing-body NL102, multi missing-body NL102, missing-body-does-not-swallow-following-statement, two-
  functions-each-body-less [declaration-boundary reset]). RECUT (recorded, DEFERRED to STAGE 12 — with reason): the
  interpolated-string `$"…"` HOLE grammar (`ParseInterpolatedString` :4932) — its inventory shows ZERO Consume sites
  and exactly ONE explicit ReportError (the NL101 "Unexpected token 'X' after interpolated string expression" hole-
  tail), BUT that error AND every hole-EXPRESSION error are produced by a FRESH sub-Lexer + sub-Parser (`new Parser(
  subTokens, _fileName)`, sourceCode=null → the CLI re-attaches the snippet by line number, verified) with per-hole
  hole-content char-scanning (`{{`/`}}` escapes, format-`:` split, nested strings, raw-string multi-line) + token
  position adjustment (`tok.Line + exprStartLine - 1` / `tok.Column + exprStartCol - 1`) + separate-panic semantics
  — materially heavier than the other three families combined, its own coherent sub-slice. The malformed-`$"…"` NL105
  (unterminated single-line / raw) is ALREADY owned (Stage 3, via ReportMalformedStringLiteralIfNeeded). Also DEFERRED
  (shared with typeof / sizeof / cast): the richer type-reference forms the whole is/as/typeof/sizeof/cast sub-grammar
  routes through `ParseTypeReferenceRecovery` does not model — union `A | B` ("Expected a type after '|'…"), postfix
  array `[]` / nullable `?`, byref `&`, tuple `( … )`, `Func<>` — a later shared type-grammar extension; the corpus's
  is/as types are all simple / qualified / generic names. The multi-param lambda `on` subscription prefix (:3649).
  NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-
  emitted the edited owner + all 1012 contracts cleanly — no repin). Evidence: BootstrapServices contracts 1012/1012
  (981 baseline + 31; full-suite fresh run, `-p:NSharpExcludeTests=false`); dev.sh Parser 381/381; ownership audit
  18/18 (all deltas `.nl`, no ratchet movement — verified 0 refs to any `.nl` in the growth-ratchet manifests); git
  status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A —
  `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep
  across src+editors+tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension
  reload. `ColumnarParserRecovery.nl` 4,302 → 4,476 lines (+174); `.tests.nl` 3,146 → 3,516 (+370). RESIDUAL-TO-PARITY
  MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 11): [1] the interpolated-string `$"…"`
  hole grammar (STAGE 12 — the fresh sub-Lexer/sub-Parser + position adjustment described above); [2] the remaining
  statement kinds (yield / break / continue / throw / try / using / lock / switch / allow / alloc-stmt / unsafe /
  assert / preprocessor / local-function / await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction /
  typed `name: T = value` declarations + the `on` subscription; [3] the MEMBER grammars (method / constructor /
  nested-type / record-positional / union-case / interface / property) + the record / interface / union / enum / soa
  type BODIES (each with its own missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [4] the richer
  type-reference forms (union / postfix array-nullable / byref / tuple / `Func<>`) shared across is/as/typeof/sizeof/
  cast/stackalloc; [5] the TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES; [6] the garbage-
  type cascade shapes (non-`{` braced found-other, non-identifier parameter name, named-tuple bad-name) needing
  `ParseTypeReference`-on-garbage + position-sorted emit. THEN the AST/node-table-facts stage (N+1), the CUTOVER (N+2,
  IDE-affecting), and the DELETION arc (N+3). Next: STAGE 12 = the interpolated-string `$"…"` hole grammar (map
  residual [1]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 10 of the parser-front-end arc — the POSTFIX
  CALL / INDEX / generic-call / `with {…}` + call-argument family (map item [1]) and the first KEYWORD-LED-PRIMARY
  tranche — new / cast / tuple / typeof (+ the cheap same-shape nameof / sizeof / checked / unchecked) / array
  (map item [2]). Extended `ColumnarParserRecovery.nl` to carry, through the SAME shared-panic model, these
  sub-grammars with their error sites, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check
  --json`, NL101-NL109, excluding the columnar-backend emit-decline NL103 anchored at Main.nl:1:1 — a backend
  diagnostic, not a parser one). Reached through the Stage-6 block-body statement vehicle `func f() { <expr> }`.
  ORIGIN INVENTORY (grep of ParsePostfixExpression + ParseArgumentList + ParsePrimaryExpression in Parser.cs):
  (a) POSTFIX (:4405) — the loop's INDEX `[…]`/`?[…]` arm (:4444, `Consume(RightBracket)` → NL108 via the Stage-9
  recovery, IndexAccess span = the OBJECT's :5948), the GENERIC-CALL `<…>(…)` arm (:4452 — `IsGenericMethodCall`
  :2025 bounded lookahead + `ParseCallTypeArguments` :2086 split-`>>`-aware + the "Expected '(' after generic type
  arguments" NL102 :4460, CallExpr span = the CALLEE's :5946), the CALL `(…)` arm (:4484), and the `with {…}` arm
  (:4500 — `Consume(LeftBrace)` / `ConsumeIdentifier`(property name) / `Consume(Colon)` / `Consume(RightBrace)` +
  an `EnsureProgress` that does NOT reset panic, unlike the new-object / match-case reset). (b) ARGUMENT LIST
  (`ParseArgumentList` :4533) — the `IsArgumentListRecoveryBoundary(Previous)` break (:4541 → :4615/:4622 +
  `IsContinuationRecoveryBoundary` :6927), the inline-out NL103 (:4561), and the spread `...` / named `name:` /
  bare alloc-family-keyword recognitions (:4587/:4579/:4595, each consuming without a diagnostic); its closing `)`
  routes through the Stage-9 recovery (NL107). (c) KEYWORD-LED PRIMARIES (`ParsePrimaryExpression` :4626) —
  typeof / nameof / sizeof (:4700/:4709/:4718) and checked / unchecked (:4728/:4738), all the `( expr | Type )`
  paren-wrapped shape (`Consume(LeftParen)` NL102 + the `)` via the Stage-9 recovery); `new` (`ParseNewExpression`
  :5209 — target-typed `new(args)` / `new { init }`, traditional `new Type[len]?(args)?{ init }?`,
  `ParseNewTypeReference` :6579 "Expected type name" NL102 anchored on `new`, and the object / collection / sized-
  array initializer loops with the panic-RESET-on-natural-progress discipline :5334/:5268 + `ReportMissingObjectInitializerColon`
  :6605 + `ParseObjectInitializerMemberValue` :5345); the immutable / plain ARRAY literal (`ParseArrayLiteral`
  :5407, `[` … `]` → NL108 via recovery); the CAST `(Type)expr` (:4783), disambiguated from tuple / paren by the
  full `IsCastExpression` lookahead (:5573 — its nested scan closures lowered to methods over two scan-state
  fields `ScanPosition`/`ScanSplit`, since N# has no first-class Func values), then `ParseUnary` operand; and the
  full TUPLE / parenthesized grammar (`ParseTupleOrParenthesizedExpression` :5428 — empty tuple, the recovery-
  boundary `<error>`, single paren, named tuple `(a: x, …)` with its `ConsumeIdentifier` / `Consume(Colon)` sites,
  and unnamed tuple `(a, b)`; ParenthesizedExpr span = INNER, TupleExpr span = the default). DECISIONS reuse the
  live shared `ParserTokenFacts` (`IsCastOperandStart` / `IsStatementStartKeyword` / `IsDeclarationKeyword` /
  `IsModifierKeyword`) and the owner's `IsTypeTerminator` / `IsMissingRequiredExpressionBoundary` / `ParseTypeReferenceRecovery`
  / `ConsumeGreater`; CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`, so codes /
  messages / spans / snippets / hints / suggestions match automatically. +40 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (call: inline-out NL103, unclosed-`)` NL107, named / spread / bare-alloc
  negatives; index: closed negative, unclosed-`]` NL108; gencall: closed / nested-generic-args negatives,
  unclosed-`)` NL107; with: closed negative, missing-`{` / missing-`:` / bad-name NL102, two-bad-props-report-ONCE
  [with-loop no-reset]; new: 5 negatives [new() / Foo() / {init} / Foo{init} / Foo[2]{coll}], missing-type NL102,
  object-init missing-`:` TWO diags [panic-reset-on-progress] + bad-name ONE diag, unclosed-`(` NL107 + unclosed-
  `[` NL108; cast: hard / unary-operand negatives; tuple: unnamed / named / empty negatives + named-missing-`:`
  NL102; typeof: closed negative + missing-`(` NL102 + unclosed-`)` NL107; nameof / sizeof negatives; array: closed
  negative + unclosed-`]` NL108; postfix: mixed member/call/index chain negative + two-functions-each-unclosed-call
  [declaration-boundary reset]). DEFERRED (recorded, NOT covered — with reasons): the alloc / stackalloc primaries
  (`ParseAllocExpression` :5178 / `ParseStackAllocExpression` :5197 — their own sub-grammar; stackalloc has the
  distinct `Consume(LeftBracket, "…after stackalloc element type")` / `Consume(RightBracket, "…after stackalloc
  length")` messages) → next tranche; the `is`/`as` type sub-grammar; interpolation `$"…"` (ParseInterpolatedString)
  / lambda primaries; the named-tuple bad-NAME garbage cascade (`(x: 1, 5: 2)` → a 3-diagnostic cascade whose exact
  reproduction needs the ConsumeIdentifier-no-advance + ParseExpression recursion + reset interplay — the same
  garbage-type-cascade class Stage 4 deferred, kept out of the corpus); the generic-call ":4460" arm (modelled
  faithfully but not corpus-reachable — `IsGenericMethodCall` guarantees a `(` follows the `>`). NO production
  wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the
  edited owner — incl. the `IsCastExpression` scan-state port — + all 981 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 981/981 (941 baseline + 40; full-suite fresh run); dev.sh Parser 381/381; ownership
  audit 18/18 (all deltas `.nl`, no ratchet movement — verified 0 refs to `ColumnarParserRecovery` / any `.nl` in
  `non-nsharp-growth-ratchet.v1.json`); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved).
  Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by
  this owner's own `.tests.nl` (verified by grep across src+editors+tests), so nothing in the production compile
  path changed. No LSP/VS Code change → no extension reload. `ColumnarParserRecovery.nl` 3,564 → 4,302 lines
  (+738); `.tests.nl` 2,741 → 3,146 (+405). RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-
  diagnostic parity, after Stage 10): [1] the remaining keyword-led primaries — alloc / stackalloc / interpolation
  `$"…"` / lambda; [2] the `is`/`as` type sub-grammar; [3] the remaining statement kinds (yield / break / continue /
  throw / try / using / lock / switch / allow / alloc / unsafe / assert / preprocessor / local-function /
  await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction / typed `name: T = value` declarations;
  [4] the MEMBER grammars (method / constructor / nested-type / record-positional / union-case / interface /
  property) + the record / interface / union / enum / soa type BODIES (each with its own missing-`}` + special
  diagnostics, e.g. soa's "not supported yet"); [5] the TEST DSL (test / setup / teardown + the test-case rows)
  and ATTRIBUTES; [6] the garbage-type cascade shapes (non-`{` braced found-other, non-identifier parameter name,
  named-tuple bad-name) needing `ParseTypeReference`-on-garbage + position-sorted emit. THEN the AST/node-table-
  facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 11 = the remaining
  keyword-led primaries (alloc / stackalloc first — cheap, then interpolation / lambda) + the `is`/`as` type
  sub-grammar (map items [1]+[2]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 9 of the parser-front-end arc — the
  CLOSING-DELIMITER recovery family. Extended `ColumnarParserRecovery.nl` to carry, through the SAME shared-panic
  model, the `Consume`-path closing-delimiter recovery + the block/type-body missing-`}` NL106 sites + the
  parameter trailing-comma recovery, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check
  --json`, NL101-NL109, excluding the columnar-backend emit-decline NL103 anchored at Main.nl:1:1 — a backend
  diagnostic, not a parser one). ORIGIN INVENTORY (grep of Consume + the delimiter helpers in Parser.cs): (a) the
  RECOVERY BRANCH — `Consume` (:6048) tries `TryReportMissingClosingDelimiter` (:6103) FIRST for a missing `)` /
  `]` (RightBrace is DECLINED, :6119): it reports the position-aware NL107 (`Missing closing ')'`) / NL108
  (`Missing closing ']'`) and returns a SYNTHETIC closing token so parsing continues. Two triggers: (i) crossed
  onto a LATER line or reached EOF (found==null, "reached the next line", :6148) → span via
  `GetMissingClosingDelimiterDiagnosticSpan` (:6164) → `TryFindUnmatchedOpeningDelimiter` (:6194, depth-tracked
  backward scan) → `TryGetDelimiterOwnerSpan` (:6237, anchors on the identifier/keyword `IsVisibleDelimiterOwner`
  :6268 that owns the delimiter, or the assigned name via `IsAssignmentAnchor` :6287 + `TryGetPreviousTokenOnLine`
  :6290), FALLING to the opening delimiter itself; (ii) a same-line BOUNDARY token (`IsSameLineMissingClosingDelimiterBoundary`
  :6309 — `{`/`}`/`]`/`:`/`=>`/`;` for `)`, `}`/`)`/`;` for `]`) stands in for the close (found!=null, "I found 'X'",
  span on the offender); a MID-LINE offender (not a boundary) DECLINES recovery (:6133) and takes the plain
  ExpectedToken path (NL102). (b) BLOCK missing-`}` (NL106) — `ParseBlock` (:2143) reports it directly (NOT via
  TryReport) both at EOF (:2205, "reached the end of the file") and at the `IsBlockClosingDeclarationStart` (:6964)
  found-declaration break (:2158, "I found 'class' … looks like a new declaration", does NOT advance). (c) TYPE-BODY
  missing-`}` (NL106) — `ParseMemberList` (:1396) reports it at EOF anchored on the `typeBodyDiagnosticSpan` (name,
  or the class/struct keyword for a `<error>` name). (d) PARAMETER trailing-comma — `ParseParameterList` (:761)
  reports `ReportMissingParameterAfterTrailingComma` (:6487, `DiagnosticSpanFromTokenRange(lastParameterStartToken,
  Previous)`, last-param-through-comma span) before its `Consume(RightParen)` (:819). IMPLEMENTATION: added the
  `TryReportMissingClosingDelimiter` result-carrier port (N# has no reference-typed out args → `ClosingDelimiterRecovery`
  / `TokenLookupResult` / `OwnerSpanResult` explicit carriers) + `GetMissingClosingDelimiterDiagnosticSpan` /
  `TryFindUnmatchedOpeningDelimiter` / `TryGetDelimiterOwnerSpan` / `FindTokenIndex` / `IsVisibleDelimiterOwner` /
  `IsAssignmentAnchor` / `TryGetPreviousTokenOnLine` / `IsSameLineMissingClosingDelimiterBoundary`, and hooked the
  recovery branch into `ConsumeToken` (so the EXISTING `new(` constraint close, the pattern list `]` / positional
  `)` closes, and the now-ConsumeToken-routed parameter `)` close all reach it with ZERO call-site churn); added
  `IsBlockClosingDeclarationStart` / `IsSoaRecordDeclarationStartAtOffset` + the `ParseBlockBody` found-declaration
  break + `ReportBlockMissingClosingBraceFoundDeclaration`; threaded the `typeBodyDiagnosticSpan` through
  `ParseClassName` / `ParseStructName` → `ParseTypeBodyIfPresent` → `ParseMemberList` and added its EOF NL106 report;
  and added the parameter trailing-comma recovery + `ReportMissingParameterAfterTrailingComma` to
  `ParseParameterListRecovery`. DECISIONS reuse the live shared `ParserTokenFacts` (`IsTypeDeclarationKeyword` /
  `IsModifierKeyword`) and CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`, so codes /
  messages / spans / snippets / hints / suggestions match automatically. RETIRED the deferrals recorded across
  stages 4-8: Stage-4 parameter trailing-comma; Stage-5 `new(` missing-`)` (NL107 via the `where T: new(` constraint);
  Stage-6 block's own missing-`}` (both EOF + `IsBlockClosingDeclarationStart` found-declaration, now corpus-exercised);
  Stage-8 pattern-list `]` / positional `)` unclosed closes (NL108 / NL107). +13 native parity contracts (2 same-line-
  boundary/next-line NL107·NL108 triggers; 1 `new(` EOF NL107; 1 same-line-comma DECLINE→NL102; 1 parameter trailing-
  comma NL102; 2 block missing-`}` EOF + found-declaration NL106; 3 panic-model: two-unclosed-positionals-report-ONCE
  [cascade suppression, no per-case reset] + two-`new(`-functions-each-report [declaration-boundary reset] + found-
  declaration-then-type-body-EOF [two NL106, boundary reset]; 3 negatives: closed `new()`, class-after-closed-block,
  closed positional/list). DEFERRED (recorded, NOT covered — with reasons): the postfix CALL `(…)` / INDEX `[…]` /
  generic-call / `with {…}` + the call-argument families (`ParseArgumentList` inline-out / spread / named-args — their
  closing-delimiter close now routes through this recovery, but the argument grammar itself is unmodelled); the
  keyword-led primaries (new / alloc / stackalloc / cast / tuple / typeof / nameof / sizeof / checked / unchecked /
  array / immutable / interpolation / lambda — each opens its own Consume / closing-delimiter sub-grammar); the
  `is`/`as` type sub-grammar; the `ParseBlockBody` attribute-led / modifier-led-to-soa `IsBlockClosingDeclarationStart`
  arms (ported faithfully but corpus-exercised only via the direct `class` case); the parameter-list
  `IsParameterListRecoveryBoundary` early break; the soa/union/interface/record/enum type-body missing-`}` (NL106) at
  their own bodies (those bodies are unmodelled — later member-grammar stages); the non-`{` braced found-other
  (`class 5`) / non-identifier parameter name (`func f(5)`) garbage-type cascades (need `ParseTypeReference`-on-garbage +
  position-sorted emit). NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged
  SDK 0.1.0 self-emitted the edited owner + all 941 contracts cleanly — no repin). Evidence: BootstrapServices contracts
  941/941 (928 baseline + 13); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no ratchet movement — the
  growth ratchet does not track `.nl`, verified: 0 refs to any `.nl` in `non-nsharp-growth-ratchet.v1.json`); git status
  shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A —
  `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep
  across src+editors+tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension
  reload. `ColumnarParserRecovery.nl` 3,091 → 3,564 lines (+473); `.tests.nl` 2,533 → 2,741 (+208). RESIDUAL-TO-PARITY
  MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 9): [1] postfix CALL/INDEX/`with` +
  call-argument families (ParseArgumentList: inline-out / spread / named-args); [2] keyword-led primaries (new / cast /
  tuple / typeof / array / interpolation / lambda / alloc / stackalloc / …); [3] the `is`/`as` type sub-grammar; [4] the
  remaining statement kinds (yield / break / continue / throw / try / using / lock / switch / allow / alloc / unsafe /
  assert / preprocessor / local-function / await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction / typed
  `name: T = value` declarations; [5] the MEMBER grammars (method / constructor / nested-type / record-positional /
  union-case / interface / property) + the record / interface / union / enum / soa type BODIES (each with its own
  missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [6] the TEST DSL (test / setup / teardown + the
  test-case rows) and ATTRIBUTES; [7] the garbage-type cascade shapes (non-`{` braced found-other, non-identifier
  parameter name) needing `ParseTypeReference`-on-garbage + position-sorted emit. THEN the AST/node-table-facts stage
  (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 10 = the POSTFIX CALL / INDEX /
  `with` + call-argument family (map item [1]) + the first keyword-led-primary tranche (new / cast / tuple / typeof /
  array, map item [2]), whose Consume / closing-delimiter sites now route through this Stage-9 recovery.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 8 of the parser-front-end arc — the
  MATCH / PATTERN diagnostic family (Stage-7's recorded cut B). Extended `ColumnarParserRecovery.nl` to carry,
  through the SAME shared-panic model, the match-expression + pattern-grammar diagnostics, PROVEN byte-exact against
  the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109). ORIGIN INVENTORY (grep of
  ParseMatchExpression + the pattern helpers in Parser.cs): (a) MATCH — `ParseMatchExpression` (:5368) with
  `Consume(LeftBrace :5375 / Arrow :5391 / Comma :5397 / RightBrace :5402)` and the `EnsureProgress(startPosition)`
  per-case boundary (:5399) that — UNLIKE the union per-case reset (:1216) or the object-initializer per-element
  reset (:5269/:5335) — does NOT reset `_panicMode`, so a pattern/arrow/comma error cascade-suppresses the rest of
  the match until the enclosing statement/declaration boundary resets it (block boundary :2172); (b) PATTERN GRAMMAR
  — `ParsePattern` (:3263) → `ParseOrPattern` (:3269) → `ParseAndPattern` (:3285) → `ParseNotPattern` (:3301) →
  `ParseRelationalPattern` (:3315, comparison-operator prefix over a PRIMARY value) → `ParsePrimaryPattern` (:3335:
  list `[…]` / slice `..` / positional `(…)` / literal / object `{…}` / identifier-led qualified-name / union-case /
  type / identifier), terminating in the "Invalid pattern. Got 'X'" NL103 (:3440, keyword-and-operator offenders,
  span = `Current.Value.Length`, NO advance); (c) the pattern QUALIFIED NAME `A.B` ConsumeIdentifier("Expected
  identifier after '.'") (:3417, NL102 dot-access variant); (d) PROPERTY PATTERNS — `ParsePropertyPatterns` (:3459)
  property-name ConsumeIdentifier (:3468, NL102 found / NL109 reserved-keyword) + the closing RightBrace (:3494).
  IMPLEMENTATION: added the `match` keyword-led primary arm to `ParsePrimaryExprValue` (Parser.cs :4764 — the
  MINIMAL match vehicle Stage 7 deferred, reached through the Stage-6 block-body statement grammar `func f() { match
  … }`), `ParseMatchExpression` (value / `when` guard / case body all descend the full Stage-7 `ParseExprValue`
  ladder), the seven pattern-tier parsers, `ParsePropertyPatterns`, and a shared `EnsureProgress` helper
  (Parser.cs :6709); extended `GetHintForMissingToken` to the full Parser.cs :6345 mirror (RightParen / RightBrace /
  RightBracket / Semicolon) so the match / property-pattern `Consume(RightBrace)` NL102 carries its hint (RightBrace
  is NOT in `TryReportMissingClosingDelimiter`, so it takes the standard Consume path). CONSTRUCTION delegates to the
  live shared `ParserErrorDiagnostics.Create`, and the decisions reuse the live shared `ParserTokenFacts` /
  `Lexer.IsReservedKeyword`, so codes / messages / spans / snippets / hints match automatically. +18 native parity
  contracts in `ColumnarParserRecovery.tests.nl` (4 invalid-pattern terminal: `+` / `*` / reserved `return` /
  guard-`when`; 4 match Consume: missing `{` / missing `=>` [arrow] / missing `,` / EOF-comma NL104; 3 property:
  bad-name NL102 / reserved-kw NL109 / object-missing-`}` re-enters-loop NL102; 1 qualified-name dot-access NL102;
  2 panic-model: two-bad-patterns-in-one-match report ONCE [cascade suppression, no per-case reset] + two-separate-
  match-statements each report their first [statement-boundary reset]; 4 negatives: literal/ident/type,
  relational/or/and/not, list/positional/object/union-case/guard, slice patterns). DEFERRED (recorded, NOT covered —
  with reasons): the list `]` / positional `)` UNCLOSED closes route through `TryReportMissingClosingDelimiter`
  (RightBracket→NL108 / RightParen→NL107) — the closing-delimiter recovery family, a later arc stage (ConsumeToken
  here reproduces the CLOSED present-delimiter case byte-exact and the corpus keeps every list/positional/object
  pattern closed); the `is`/`as` relational operators (type sub-grammar) and complex guard/value expressions reuse
  the Stage-7 ladder (the corpus uses only simple values). NO production wiring; NO wall tripped (self-contained edit
  to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner + all 928 contracts cleanly — no
  repin). Evidence: BootstrapServices contracts 928/928 (910 baseline + 18); dev.sh Parser 381/381; ownership audit
  18/18 (all deltas `.nl`, no ratchet movement — the growth ratchet does not track `.nl`, verified: 0 refs to
  `ColumnarParserRecovery` / any `.nl` in `non-nsharp-growth-ratchet.v1.json`); git status shows ONLY the two `.nl`
  files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+tests+editors),
  so nothing in the production compile path changed. No LSP/VS Code change → no extension reload. Next: STAGE 9 =
  the CLOSING-DELIMITER recovery family (`TryReportMissingClosingDelimiter` — missing `)` NL107 / `]` NL108 / `}`
  NL106), then the postfix call/index/`with` + remaining keyword-led primaries, per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 7 of the parser-front-end arc — the
  EXPRESSIONS diagnostic family (recut A: the core precedence ladder + the leading expression ERROR families;
  match/patterns deferred to a follow-on stage). Extended `ColumnarParserRecovery.nl` by replacing Stage-6's
  shallow assignment/additive/multiplicative statement-expression subset with the FULLER Parser.cs precedence
  ladder and carrying the expression ERROR families Stages 3/6 deliberately kept panic-suppressed, all through
  the SAME shared-panic model, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check --json`,
  NL101-NL109, excluding the columnar-backend emit-decline NL103 — a backend diagnostic anchored at a nonzero line,
  not a parser diagnostic). ORIGIN INVENTORY (grep of ParseExpression + the ladder + ParsePrimaryExpression in
  Parser.cs): (a) the LADDER — `ParseAssignmentExpression` (:3690) → `ParseTernaryExpression` (:4009) →
  `ParseNullCoalescingExpression` (:4033) → `ParseLogicalOr/AndExpression` (:4047/:4061) →
  `ParseBitwiseOr/Xor/AndExpression` (:4075/:4089/:4103) → `ParseEqualityExpression` (:4117) →
  `ParseRelationalExpression` (:4132) → `ParseShiftExpression` (:4205) → `ParseAdditiveExpression` (:4220) →
  `ParseMultiplicativeExpression` (:4235) → `ParseRangeExpression` (:4280) → `ParseUnaryExpression` (:4316) →
  `ParsePostfixExpression` (:4405) → `ParsePrimaryExpression` (:4626); (b) UNEXPECTED-TOKEN-IN-EXPRESSION — the
  `ParsePrimaryExpression` terminal arm (:4813, NL101 `UnexpectedToken`) + `ShouldSkipUnexpectedExpressionToken`
  (:6943); (c) PREFIX `+` — `ParseInvalidPrefixPlusExpression` (:3816, NL103 `InvalidSyntax`, the plus-through-operand
  `DiagnosticSpanFromTokenRange` span), reached from `ParseUnaryExpression` (:4318); (d) LEADING `.` —
  `ParseLeadingMemberAccessWithoutReceiver` (:6407), reached from `ParsePrimaryExpression` (:4631); (e) TERNARY —
  the missing-then / missing-else `ParseRequiredExpressionAfter` sites (:4016/:4022, through-token spans) + the
  missing-`:` generic `Consume(Colon, "Expected ':' in ternary expression")` (:4021); (f) DANGLING BINARY OPERATOR —
  `ParseBinaryRightOperandOrMissing` (:3778) → `ParseRightOperandOrMissing` (:3750) with the
  `DiagnosticSpanFromExpressionThroughToken` span, now fired across every ladder tier; (g) await/must/throw
  MISSING-OPERAND — `ParseUnaryOperandOrMissing` (:3789, `IsMissingRequiredExpressionBoundary`-gated, the distinct
  "Add … or remove '…'" hint); (h) MEMBER-NAME-AFTER-DOT — `ReportMissingMemberNameAfterDot` (:6385, receiver-anchored)
  + the reserved-keyword member `ReportReservedKeywordAsName(…, isDotAccess: true)` (:4433), reached from
  `ParsePostfixExpression`. IMPLEMENTATION: rewrote the statement-expression entry `ParseExprValue` to descend the
  full ladder (each binary tier accumulates the operator-position `(line,column,1)` `DiagnosticSpanFromExpression`
  default that a `BinaryExpression` yields, so the following dangling operator's through-token span is byte-exact);
  added `ParseTernary`/`ParseNullCoalescing`/`ParseLogicalOr`/`ParseLogicalAnd`/`ParseBitwiseOr`/`ParseBitwiseXor`/
  `ParseBitwiseAnd`/`ParseEquality`/`ParseRelational`/`ParseShift`/`ParseRange`/`ParseUnary`/`ParsePostfix`/
  `ParseMemberAccess`, the `BinaryRightOperandMissing`/`RightOperandMissingWithSpan` operand-missing helpers (replacing
  the Stage-6 `additiveOperand`-bool variant, since N# has no first-class `Func<Expression>`), `ParseInvalidPrefixPlusExpression`,
  `ParseUnaryOperandOrMissing`, `ReportMissingMemberNameAfterDot`, `ParseLeadingMemberAccessWithoutReceiver`, and
  `ShouldSkipUnexpectedExpressionToken`; rewrote `ParsePrimaryExprValue` into the full primary (leading-dot / int-float /
  char-string malformed / true-false-null / default / this / base / parenthesized / identifier / the unexpected-token
  terminal). The boundary DECISIONS reuse the live shared `ParserTokenFacts` (`IsAssignmentOperator` /
  `CanStartExpression` / `IsExpressionTerminator` / `IsStatementStartKeyword` / `IsDeclarationKeyword` /
  `IsModifierKeyword`, identical to Parser.cs), and CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`,
  so codes / messages / spans / snippets / hints match automatically. +35 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (8 leading-family: unexpected `*`, prefix `+`, leading `.`, trailing-`.` member,
  reserved-keyword member, ternary missing-then / missing-`:` / missing-else; 9 dangling-per-tier: `?? || && | ^ & == <
  <<` [additive `+` / multiplicative already Stage-6]; 3 await/must/throw missing-operand; 5 panic-model: initializer-
  terminator `)` [missing-init NL102 then the reset-boundary unexpected-token NL101], two dangling operators in
  different statements, unexpected-token-skip-then-valid-statement, within-expression prefix-plus cascade suppression,
  a leading-dot error then a dangling operator across the DECLARATION boundary; 10 negatives: `a||b&&c`, `a<b`, `!a`,
  `a.b.c`, `a?.b`, `a?b:c`, `(a+b)*c`, `a..b`, `a++`, `a<<b`). DEFERRED (recorded, NOT covered — with reasons): the
  MATCH / PATTERN family (`ParseMatchExpression` :5368 — `Consume(LeftBrace/Arrow/Comma/RightBrace)` + `ParsePattern`
  :3263 → `ParsePrimaryPattern` :3335 terminal "Invalid pattern. Got 'X'" [NL103] + the list `Consume(RightBracket)`
  / positional `Consume(RightParen)` / qualified-name `ConsumeIdentifier` sites + `ParsePropertyPatterns` :3459) — the
  "match/patterns second" recut half, its own follow-on stage; the `is`/`as` relational operators (parse a type
  reference — the type sub-grammar); postfix CALL `(…)` / INDEX `[…]` / generic-call `<…>(…)` / `with {…}` (the
  call-argument + closing-delimiter families — `ParseArgumentList`'s inline-out / spread / named-args / missing `)`
  `]` `}`); the keyword-led primaries (new / alloc / stackalloc / match / immutable / array / cast / tuple / typeof /
  nameof / sizeof / checked / unchecked / spread / interpolation / lambda — each opens its own sub-grammar with
  Consume / closing-delimiter sites; Parser.cs would not reach the unexpected-token terminal for them, so their
  absence keeps that arm byte-exact); and the four INVALID-OPERATOR default arms (`ParseAssignmentExpression` :3718 /
  `ParseRelationalExpression` :4177 / `ParseMultiplicativeExpression` :4253 / `ParseUnaryExpression` :4348) — proven
  UNREACHABLE dead defaults (each `switch` is guarded by an exact-match fact — `IsAssignmentOperator` and the
  while/if token checks — that admits only tokens the switch already handles, so the default never fires and cannot be
  reached byte-exact). The Stage-3 `=>` expression-body and Stage-4 field-`:=` init still use the minimal
  `ParseLiteralBearingExpression` vehicle (a validated byte-exact subset for their corpora); unifying them onto the
  full ladder is a later mechanical cleanup. NO production wiring; NO wall tripped (self-contained edit to one owner +
  its tests; the packaged SDK 0.1.0 self-emitted the edited owner + all 910 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 910/910 (875 baseline + 35); dev.sh Parser 381/381; ownership audit 18/18 (all deltas
  `.nl`, no ratchet movement — the non-nsharp growth ratchet does not track `.nl`); git status shows ONLY the two `.nl`
  files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+tests+editors),
  so nothing in the production compile path changed. No LSP/VS Code change → no extension reload. Next: STAGE 8 =
  match/patterns (the deferred `ParseMatchExpression` + pattern family), then closing-delimiter recovery, per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 6 of the parser-front-end arc — the
  STATEMENT diagnostic family. Extended `ColumnarParserRecovery.nl` with the block-body statement grammar (a real
  `func f() { … }` vehicle Stages 3-5 deliberately left unparsed) and carried the statement diagnostics through the
  SAME shared-panic model, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check --json`,
  NL101-NL109, excluding the line-0 columnar-backend decline NL103 — not a parser diagnostic).
  ORIGIN INVENTORY (grep of ParseStatement + its helpers in Parser.cs): (a) the SYNC POINT + BOUNDARY RESET —
  `ParseBlock` (:2143) resets `_panicMode` at each statement (:2172), tracks `_currentRecoveryBoundaryColumn`
  (:2177), and on no progress calls `SynchronizeToNextStatement` (:2188 → :7084, which resets panic +
  `_splitGreaterDepth` and skips to a closing brace / statement-start / type-declaration keyword); (b) the
  DANGLING BINARY/ASSIGNMENT OPERATOR — `ParseRightOperandOrMissing` (:3750) / `ParseBinaryRightOperandOrMissing`
  (:3778) report "Expected expression after 'X'" with the `DiagnosticSpanFromExpressionThroughToken` (:3842)
  left-operand-through-operator span, gated by `IsMissingOperandBoundary` (:6908, the recovery-boundary-column
  rule that stops the operator swallowing the following statement — `Parser_DanglingBinaryOperator_...`); (c) the
  MISSING-INITIALIZER `:=`/`=` and MISSING-CONDITION if/while — `ParseRequiredExpressionAfter` (:3855) with
  `IsMissingRequiredExpressionBoundary` (:3928) / `LooksLikeStatementStartAfterRequiredExpression` (:3946) /
  `ShouldUnderlineAnchorForMissingRequiredExpression` (:3887), anchored on the declaration target
  (`DiagnosticSpanFromExpression` :5917) or the keyword; (d) the MISSING for/foreach `in` —
  `ReportMissingInKeywordAndRecover` (:3908, keyword-anchored, returns a synthetic `in`); (e) the
  MISSING-STATEMENT-BODY — `IsMissingStatementBodyBoundary` (:3961) / `ReportMissingStatementBody` (:3968),
  reached through the `blockOwnerSpan` threaded into `ParseStatement` for if/while/for bodies. IMPLEMENTATION:
  extended the function head (`ParseFunctionHeadAndBody`) with the block-body branch (Parser.cs :498), and added
  `ParseBlockBody` / `ParseStatement` (let/const/readonly, if, for, foreach, while, return, print, block,
  expression-statement) + a deliberately shallow expression subset (assignment over additive/multiplicative over
  identifier/literal/bool/null/parenthesized primaries) that reproduces the two diagnostic-bearing behaviours
  (the dangling operator + its through-token span) byte-exact and consumes well-formed operands identically. The
  boundary DECISIONS reuse the live shared `ParserTokenFacts` (`IsStatementStartKeyword` / `CanStartExpression` /
  `IsExpressionTerminator` / `IsAssignmentOperator` / `IsModifierKeyword` / `IsDeclarationKeyword` /
  `IsTypeDeclarationKeyword`, identical to Parser.cs), and CONSTRUCTION delegates to the live shared
  `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints match automatically. +25 native
  parity contracts in `ColumnarParserRecovery.tests.nl` (13 single-diagnostic: dangling `+`, dangling `=`,
  shorthand `:=` no-init, `let`/`const` no-init, `print` no-expr, `while`/`if` no-condition, `foreach`/`for`
  missing-`in`, `if`/`while`/`for-in` missing-body; 5 panic-model: two-`:=` statement-boundary reset,
  within-statement cascade suppression (`while` no-cond+no-body → 1), a valid statement between two errors,
  dangling-then-missing-init across the DECLARATION boundary, nested-block per-statement reset; 7 negatives:
  well-formed decl+print, binary, assignment, `while true { }`, `foreach … in …`, bare `return`, empty body).
  DEFERRED (recorded, NOT covered — with reasons): the C-style `for init; cond; iter` loop, tuple deconstruction,
  typed `name: T = value` declarations, and the remaining statement kinds (yield / break / continue / throw /
  try / using / lock / switch / allow / alloc / unsafe / assert / preprocessor / local-function / await-foreach /
  off) are later arc stages (each adds its own ReportError sites under the same shared-panic model); the full
  expression precedence ladder (ternary / coalescing / logical / bitwise / equality / relational / shift / range /
  unary / postfix / call / member / index) and the expression ERROR families (unexpected token, prefix `+`,
  leading `.`) belong to the expressions/patterns stage; the block's own missing-`}` (NL106) report +
  `IsBlockClosingDeclarationStart` break are reproduced-but-not-corpus-exercised (every corpus body is closed and
  free of nested type declarations) — the broader closing-delimiter family (missing `)`/`]`/`}`) stays a later
  arc stage. NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK
  0.1.0 self-emitted the edited owner + all 875 contracts cleanly — no repin). Evidence: BootstrapServices
  contracts 875/875 (850 baseline + 25); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no
  ratchet movement); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite /
  corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own
  `.tests.nl` (verified by grep across src+tests+editors), so nothing in the production compile path changed. No
  LSP/VS Code change → no extension reload. Next: STAGE 7 = expressions/patterns (the expression ERROR families +
  the full precedence ladder) per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 5 of the parser-front-end arc — the
  GENERICS / CONSTRAINTS diagnostic family. Extended `ColumnarParserRecovery.nl` to carry, through the SAME
  shared-panic model, four sub-families end-to-end, PROVEN byte-exact against the freshly built Release CLI oracle
  (`nlc check --json`, NL101-NL109, excluding the columnar-backend decline NL103 — not a parser diagnostic).
  ORIGIN INVENTORY (grep of Parser.cs): (a) TYPE PARAMETER NAMES — `ParseTypeParameters` (:725) funnels the name
  through `ConsumeIdentifier` (:743, reserved-keyword variant reachable) and reports `ReportMissingTypeParameterName`
  (:6439, `DiagnosticSpanFromTokenRange(lessToken, Current)`) for the empty `<>` / trailing-comma `<T,>` shapes;
  the list closes with the generic `Consume(Greater)` (:747, NOT the split-aware ConsumeGreater →
  TokenTypeToString(Greater)="greater"); (b) GENERIC TYPE ARGUMENTS — the generic type-reference `Name<…>`
  (:1925-1957) reports `ReportMissingGenericTypeArgument` (:6457, `DiagnosticSpanFromTokenRange(typeNameToken,
  Current)`, message interpolates the type name + opening `<`) for `Name<>` / `Name<T,>`; (c) the `ConsumeGreater`
  split-`>>` discipline (:2101) — the `>>`-split mechanism (`_splitGreaterDepth` + the split-aware Check :6025 /
  Advance :5860; reset at the sync points :7042/:7086) so a well-formed nested generic `List<List<int>>` reports
  NOTHING, plus the "Expected '>'. Got 'X'" ExpectedToken error (:2121) when a type-argument list is left unclosed;
  (d) the `where`-clause constraints (`ParseGenericConstraints` :851) — the "Expected type parameter"
  `ConsumeIdentifier` name error (:861), the missing-`:` `Consume(Colon)` error (:862), and the class/struct
  mutual-exclusion (:901) and struct/new() redundancy (:915) `InvalidSyntax` validations with the
  `LaterToken`/`TokenLengthOrFallback`/`TokenSpanLengthOrFallback` anchoring (:6010/:5897/:5900). IMPLEMENTATION:
  routed the function head through `ParseTypeParameters` (after the name, before the params — Parser.cs :446) + a
  generic-aware `ParseTypeReferenceRecovery` for the return type (Parser.cs :475, the ReportMissingGenericTypeArgument
  + ConsumeGreater vehicle) + `ParseGenericConstraints` (after the return type — Parser.cs :488); added
  `ParseTypeParameters` to the class/struct declaration heads (Parser.cs :943/:988 — a no-op for the non-generic
  Stage-4 class corpus). Diagnostic CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`, and
  the constraint DECISIONS mirror Parser.cs exactly (`GetHintForMissingToken(Greater/Colon)`=null, the constraint
  validation `LaterToken` + span-length math ported verbatim, incl. the "…not permitted in ." message typo), so
  codes / messages / spans / snippets / hints match automatically. +22 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (4 type-param-name: empty `<>` / trailing-comma `<T,>` / class-`<>` /
  reserved-keyword; 3 generic-arg: empty / trailing-comma / named-type; 1 ConsumeGreater unclosed; 1 split-`>>`
  well-formed-nested NEGATIVE; 2 constraint validations: class+struct / struct+new(); 3 constraint name/colon:
  missing-name / reserved-keyword / missing-`:`; 1 non-type-constraint cross-boundary cascade (NL102 + boundary-reset
  NL101); 2 two-function boundary-reset (type-param / generic-return); 5 well-formed negatives). DEFERRED (recorded,
  NOT covered — with reasons): the EOF-anchored `ConsumeGreater` (the check pipeline clamps its JSON length 0→1 —
  Current.Value at EOF is "" so length 0 at the CompilerError level, unmatchable against the clamped golden); the
  `new(` missing-`)` (emits NL107 `Missing closing ')'` via `TryReportMissingClosingDelimiter` — the closing-delimiter
  recovery stage, deferred); class/interface/union/record/soa/method type-params (soa additionally reports the "soa
  record type parameters are not supported yet" special diagnostic) and class/interface/union bodies — later stages;
  classes do NOT take `where` clauses (verified: `class C<T> where …` cascades to 3 diagnostics), so the constraint
  family is function-only this stage. NO production wiring; NO wall tripped (self-contained edit to one owner + its
  tests; the packaged SDK 0.1.0 self-emitted the edited owner + all 850 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 850/850 (828 baseline + 22); dev.sh Parser 381/381; ownership audit 18/18 (all deltas
  `.nl`, no ratchet movement); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit
  suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's
  own `.tests.nl` (verified by grep across src+tests+editors), so nothing in the production compile path changed. No
  LSP/VS Code change → no extension reload. Next: STAGE 6 = statements (the `SynchronizeToNextStatement` sync point +
  the dangling-operator / missing-initializer / missing-condition shapes the ParserErrorTests pin) per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 4 of the parser-front-end arc — the
  MEMBER / PARAMETER / FIELD declaration diagnostic family (the `:`/`:=` colon and type-annotation errors,
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 4 of the parser-front-end arc — the
  MEMBER / PARAMETER / FIELD declaration diagnostic family (the `:`/`:=` colon and type-annotation errors,
  NL102 `ExpectedToken` / NL109 `ReservedKeywordAsName`). Extended `ColumnarParserRecovery.nl` to carry, through
  the SAME shared-panic model, four sub-families end-to-end, byte-exact against the freshly built Release CLI
  oracle. ORIGIN INVENTORY (grep of Parser.cs): (a) PARAMETERS — `ParseParameterList` (:751) funnels the name
  through `ConsumeIdentifier(message, diagnosticSpan?)` (:6720) with `GetMissingParameterNameDiagnosticSpan`
  (:6476, anchors a missing name on the following type token), the `:` through `ConsumeParameterColon` (:6625,
  anchors on the parameter NAME), and the type through `ParseParameterTypeReference` (:6504, name-anchored
  missing-type); (b) FIELDS — `ParseFieldDeclaration` (:1637) funnels the name through the no-span
  `ConsumeIdentifier` (:1666), the `:`/`:=` through `ConsumeFieldColon` (:6651), and the type through
  `ParseFieldTypeReference` (:6536) with the `LooksLikeNextFieldAfterMissingType` heuristic (:6572, so a
  following `Ident(:|:=)` on a later line is NOT swallowed as this field's type); (c) the MEMBER-BOUNDARY
  recovery — `ParseMemberList`'s per-member `_panicMode = false` reset (:1365) — proven by two malformed fields
  each reporting at their own member boundary; (d) the Stage-2-DEFERRED braced-kind found-other NAME, now
  reachable for the `{`-offender variant (`class {` / `struct {`), where the offending `{` is consumed as the
  empty body brace and panic suppresses the rest — RETIRING that deferred Stage-2 case. IMPLEMENTATION: routed
  the function head through a real `ParseParameterListRecovery` (empty `()` handled identically, so Stage-3's
  `func f() => <lit>` corpus is unaffected); extended `ParseClassName` / `ParseStructName` with
  `ParseTypeBodyIfPresent` (parses the braced body for a VALID name → fields, and for an `<error>` name ONLY
  when the offender is `{` — every other `<error>`-name shape keeps Stage-2 return-early, so no Stage-2
  multi-declaration case regresses); added `ParseMemberList` (member-boundary reset + force-advance),
  `ParseFieldMember`, the four `Consume*`/`Parse*TypeReference` reporters, and shared `IsTypeTerminator` /
  `IsVisibleName` / `TypeErrorAnchor` helpers. Diagnostic CONSTRUCTION delegates to the live shared
  `ParserErrorDiagnostics.Create`, and the field-type/parameter-type/colon DECISIONS reuse the live shared
  `ParserTokenFacts.IsTypeReferenceStart` (identical to Parser.cs), so codes / messages / spans / snippets /
  hints match automatically. +17 native parity contracts in `ColumnarParserRecovery.tests.nl` (7 parameter: the
  missing-`:` / missing-type / `:`-where-name-required found / reserved-keyword name / second-parameter-`:` /
  well-formed negative / two-functions-boundary-reset; 8 field: missing-`:`/`:=` / missing-type /
  member-boundary-reset (two malformed fields) / reserved-keyword field name / struct-body field / two-classes
  boundary reset / well-formed-field negative / empty-body negative; 2 braced found-other: `class {` / `struct {`).
  DEFERRED (recorded, NOT covered — with reasons): the non-`{` braced found-other (`class 5` / `struct 5`) emits a
  3-diagnostic cascade (name error → `Missing closing '}'` → in-body `Expected field name`) whose report order
  diverges from the oracle's position-sorted output and needs `ParseTypeReference`-on-garbage +
  `SynchronizeToNextStatement` + the sorted-emit order — a later stage; the non-identifier parameter name
  (`func f(5)`) cascade needs the same garbage-type reachability; the trailing-comma
  (`ReportMissingParameterAfterTrailingComma`), the missing-`)` / missing-`{` / missing-`}` (NL106/NL107)
  closing-delimiter recovery, and the method / nested-type / constructor / record-positional / union-case /
  interface member grammars (and record/interface/union bodies) are their own later arc stages. NO production
  wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the
  edited owner + all 828 contracts cleanly — no repin). Evidence: BootstrapServices contracts 828/828 (811
  baseline + 17); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no ratchet movement); git
  status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A —
  `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by
  grep across src+tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension
  reload. Next: STAGE 5 = generics / constraints (the `ConsumeGreater`, split `>>`, type-parameter /
  type-argument errors) per the arc plan.
- Prior sub-slice (016 arc, STAGE 3, LANDED — no commit): the parser-front-end arc — the
  MALFORMED-LITERAL diagnostic family (NL105 `InvalidLiteral`). Extended `ColumnarParserRecovery.nl` to carry the
  malformed-literal diagnostics — unterminated string, unterminated interpolated (single-line) string,
  unterminated char, empty char, unterminated triple-quoted string, unterminated interpolated raw string —
  through the SAME shared-panic model, byte-exact against the live-CLI oracle. ORIGIN INVENTORY (grep of
  Parser.cs + the N# Lexer): every malformed-literal diagnostic is REPORTED in `Parser.cs`
  `ParsePrimaryExpression` (:4646/:4653 → `ReportMalformedCharLiteralIfNeeded` :4905 /
  `ReportMalformedStringLiteralIfNeeded` :4830 → `ReportMalformedRawStringLiteralIfNeeded` :4876), each
  routing through the shared-panic `ReportError` (:6845). The already-N# `Lexer.nl` only CLASSIFIES
  (sets `Token.IsTerminated`, produces the token value); it emits NO diagnostic. The malformed DECISION reuses
  the LIVE shared N# owner `ParserLiteralFacts.IsCompleteStringLiteral`/`IsCompleteCharLiteral` (Parser.cs
  delegates to the identical calls). So the family belongs to the PARSER model (Parser.cs-reported,
  shared-panic-gated), NOT a separate lexer lane — carried in full this stage. Reached via the shallowest
  byte-exact expression context: the expression-bodied function `func f() => <literal>` (oracle-verified to
  emit exactly ONE NL105 per shape). Adds a MINIMAL literal-reaching expression path (paren + literal primary
  + minimal binary-operator continuation) as the vehicle — full expression grammar + the expression/statement
  ERROR families (unexpected-token-in-expression, dangling operator, missing `)`) stay a LATER arc stage; those
  would-be errors never fire here because they route through the SAME shared panic the literal error already
  set, so the diagnostic output stays byte-exact. Ported the three Parser.cs reporters faithfully
  (`ReportMalformedLiteralIfNeeded` → char / string / raw-string), delegating the DECISION to the live shared
  `ParserLiteralFacts` (identical to Parser.cs) and the CONSTRUCTION to `ParserErrorDiagnostics.Create`, so
  codes / messages / spans / snippets / hints match automatically. Extended `ParseFunctionName` to continue a
  validly-named function into its expression body (Stage-2 name-error cases preserved: a `<error>` name returns
  before any body parse). +14 native parity contracts in `ColumnarParserRecovery.tests.nl`: one per literal
  shape, plus panic interactions — across a DECLARATION boundary the next literal error fires (two malformed
  funcs → 2 diags; malformed literal then stray top-level token → NL105 + NL101), and IN-REGION a following
  malformed literal is SUPPRESSED by shared panic (`'a + 'b` / `'' + 'b` → 1 diag; the parenthesized `('a`
  suppresses the missing-`)` and anchors the char at column 14), plus negatives (well-formed literals report
  nothing). NO production wiring; NO wall (self-contained; packaged SDK 0.1.0 self-emits the edited owner +
  tests cleanly — including the `"""`-bearing message literals — no repin). Evidence: BootstrapServices
  contracts 811/811 (797 baseline + 14); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no
  ratchet movement); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit
  suite / corpus IL sweeps N/A — the owner is referenced ONLY by its own tests (verified), so nothing in the
  production compile path changed. No LSP/VS Code change → no extension reload. Next: STAGE 4 = member /
  parameter / field declaration diagnostics (the `:`/`:=` colon and type errors) per the arc plan.
- Prior sub-slice (016 arc, STAGE 2, LANDED — no commit): the DECLARATION-NAME diagnostic family.
  Extended `ColumnarParserRecovery.nl` to carry the "Expected <kind>
  name" diagnostics for func / class / struct / record / soa record / interface / union / enum / type-alias
  declarations through the SAME shared-panic model, with the `DiagnosticSpanFromToken` KEYWORD-ANCHORING
  discipline (a missing/invalid name underlines the DECLARATION KEYWORD, not the offending token, in all
  three ConsumeIdentifier variants) and the reserved-keyword-as-name variant. Added `ConsumeDeclarationName`
  (Parser.cs ConsumeIdentifier with a non-null diagnosticSpan), the `ParseTopLevelDeclaration` dispatch
  (ParseModifiers + the exact Parser.cs keyword order incl. `ref struct` / `soa record` / `duck interface`
  / `record struct` variants + LookAhead), the per-kind name parsers, and the boundary/force-advance loop
  (Parser.cs ParseCompilationUnit :83/:99-108). Bodies are NOT parsed (a later arc stage); the loop makes
  progress by consuming the keyword (and, for reserved-keyword recovery, the offender) or the stray token.
  +24 native parity contracts in `ColumnarParserRecovery.tests.nl` (per-kind absent-name / reserved-keyword,
  plus func/enum/type found-other + two panic-model interaction fixtures), proven byte-exact against golden
  live-CLI Parser.cs output (`nlc check --json`, NL101-NL109). NO production wiring; NO wall tripped
  (self-contained edit to one owner + its tests, packaged SDK emits it — no repin). Evidence: BootstrapServices
  contracts 797/797 (773 baseline + 24); ownership audit 18/18; git status shows only the two `.nl` files
  changed (no non-N# file moved). Next: STAGE 3 = the next-smallest family per the arc plan (malformed-literal:
  unterminated string/char/triple/interpolated, empty char).
- Prior sub-slice (016 arc, STAGE 1, LANDED — no commit): the shared-panic RECOVERY MODEL + import/namespace/
  package family. Added `ColumnarParserRecovery.nl` (Parser.cs `_panicMode` lifecycle: one shared flag,
  suppress-while-set, set-on-report, reset only at the declaration-boundary sync point; ordered reporting;
  the ConsumeIdentifier reserved-keyword/EOF/found variants + LastVisibleTokenSpan anchoring) + 11 golden
  parity contracts. Deleted the inert divergent `ColumnarSyntaxDiagnostics` scaffolding closure (see the arc
  plan's scaffolding-fate decision).
- CORRECTION (post-Stage-2): sub-slice 5's Min/Max deletion (`86f4c251b`) was PARTIALLY WRONG — its
  "provably dead" claim held only for plannable receivers. `Select(v => ...).Min()/.Max()` chains
  whole-subtree-exit to the legacy residual (contextual-lambda decline), where the deleted emit +
  preflight arms were load-bearing: tests/native/lambda-placement failed to emit at the checkpoint
  gate. The arms are RESTORED as fenced load-bearing residuals (retire with arc stages 3-4); the
  resolver-side ownership of plannable Min/Max receivers stands. LESSON (bar raised): every
  byte-exact corpus sweep MUST include the tests/native/* projects — the 59-assembly example/fixture
  sweep alone missed this; sub-slice 6's refutation of the identical premise for ToArray/ToList/
  Contains applied retroactively to 5 and nobody re-checked.
- Active sub-slice (THIS TURN, LANDED a net-negative deletion): the interpolation BASE-CALL
  CLASSIFICATION decision. CHOICE recorded pre-edit: move the string-classification half of
  `TryResolveInterpolationBaseCallPlan` (the `base.` prefix + `()` suffix parse and the method-name
  extraction/validation, deciding THAT an interpolated hole is a well-formed `base.<name>()` call and
  extracting the name) into the N# splitter owner `ColumnarInterpolationSplitter.TrySplitBaseCall(text,
  out methodName)` — an exact mirror of the accepted `TrySplitCast`/`TrySplitEquality`/`TrySplitCoalesce`
  splits (9a3c20950/aaddf...). The reflection-coupled resolution half (`_currentStruct?.BaseDef`,
  `TryFindMethodOnChain` over the base chain, and the return-type guards `void`/enum/generic-param/
  `ContainsBuilderBoundType`/`IsSupportedType`) STAYS C# as a mechanical host. Byte-exact verifiable on
  the live corpus path `examples/06-classes-and-records/ConstructorChaining.nl:56`
  (`$"{base.GetInfo()} - {EmployeeId} ({Department})"`). N# splitter +TrySplitBaseCall + tests; C#
  emitter net-negative (removes the const/prefix/suffix guard + the name-validation block, keeps the
  `BaseDef==null` reflection guard + mechanical resolution). This supersedes the case-12 prune below,
  which is now COMMITTED at 6e94ca88c.
- Prior committed sub-slice (6e94ca88c, "Prune the dead case-12 residual arms by four-surface liveness
  proof"): pruned the case-12 primitive-binary whole-subtree residual to its live reaching-set. Four sub-arms proven DEAD
  across ALL FOUR exercise surfaces — corpus+native (162 assemblies), units (3,190), and self-emit
  (BootstrapServices kernels, full 228-arm run) — via IL-neutral arm instrumentation (0 IL diff baseline
  vs instrumented across all 162 assemblies), then DELETED:
  * `case "&"|"|"|"^"` bitwise residual arm
  * record-struct structural-equality residual arm (`==`/`!=` boxing through the synthesized Equals)
  * the `null == null` / `null != null` constant fold
  * the multi-term string-concat CHAIN lowering (`TryEmitStringConcatChain` + its sole-caller
    `CanProveStringExpression`) — the residual pair-concat (`String.Concat(string,string)`) STAYS.
  ColumnarIlEmitter.cs 21,534 -> 21,438 (net -96 lines / -92 non-blank; epoch ceiling 21,723/20,646
  untouched). N# delta: ZERO — ColumnarPrimitiveBinaryPlanner / ColumnarConditionalPlanner already own
  these operators at the front door; the residual only served a non-plannable-OPERAND band that is
  empty for these four families. No test migration (dead-code deletion; live coverage = native
  primitive-binary 16/16 + conditional 8/8). SLICE-5 GUARD HONORED: a PARTIAL self-emit run (166 arms)
  showed `stringcharconcat` dead, but the COMPLETE run (228 arms) caught it firing late, so it was
  RETAINED — the exact slice-5 escape signature; every dead verdict waited for the full self-emit.
  * Candidate (a) BLOCKED (definitive record): the live preflight static-call arm (case-9
    `TryFindStaticMethodOnChain` on `_enclosingType`) types the user's OWN enclosing-type static-method
    call results (bare identifier, no receiver) — NOT external `ColumnarExternalBindingPlans` catalog
    facts (external static calls have a type-name receiver whose `TryGetPreflightExpressionType` returns
    false, so they never reach this arm). It FIRED on the corpus -> load-bearing, not dead. Six lines
    fused into the unified bare-call preflight tier (localfn->sibling->ownstruct->ownstatic); deleting it
    regresses user-static-call-result typing. Rerouting to an N# planner return-type is the forbidden
    add-a-planner-for-a-relocation anti-pattern (identical to the lambda-arc Candidate A rejection): no
    decision deleted, net N#+plumbing positive. The other corpus-dead preflight arms are BCL-shape
    (span/AsSpan/ArrayPool/MemoryPool/Stream — self-emit-live: the kernels use them) or lambda-family
    (where/toarray/minmax/contains — blocked with the lambda arc). No net-negative deletion in (a).
  * Candidate (b) partial blocks (definitive record): within the SAME residual, three more sub-arms fire
    in SELF-EMIT (kernel compilation) though dead in corpus+native+units, so RETAINED: the case-13
    ternary residual (kernels have 80 ternaries incl. `setter == null ? 0 : 1`, ColumnarDefinitions.nl:189,
    the exact form task 007 flagged; the N# ColumnarConditionalPlanner declines non-Boolean conditions +
    mixed-type arms, so the residual still serves them); reference-identity equality on user reference
    types (`==`/`!=`); and string+char concat (`TryEmitStringCharConcat`). Residual arith (`+`/`-`/`*`/`/`)
    and ordering (`<`/`<=`/`>`/`>=`) are all self-emit-live. These retire only as their non-plannable
    OPERAND forms become N#-plannable — a future four-surface-gated cut, not this turn.

- Lambda-taking LINQ ownership ARC — staged plan (concrete owners + deletion targets; ordered by the
  d2257f33c refutation, whose three blockers are the ground truth for why stages 3–5 must precede any
  enumerable-arm deletion):
  * Stage 1 (THIS TURN): contextual-lambda SIGNATURE binding → `ColumnarLambdaPlacementPlanner`; delete the
    C# param-binding loop in `TryEmitLambdaLiteral`. DONE.
  * Stage 2 (THIS TURN): contextual-lambda CAPTURE-SET collection → N#. Move `CollectLambdaCaptures` (the pure
    AST capture-name scan against the enclosing local/param/lifted name sets) into an N# owner; the
    non-capturing-vs-capturing branch consumes the N# capture set. Delete the C# `CollectLambdaCaptures`
    walk (~35 lines). The this-capture member-chain scan `BodyReferencesEnclosingChain` (needs the emitter's
    member-chain resolvers) and the display-class capturing residual stay C# until Stage 6.
  * Stage 3a (THIS TURN): contextual-lambda RETURN-TYPE inference DECISION → N#. DONE. The
    `TryInferSingleParameterContextualDelegateReturnType` decision (which of the two admitted argument forms —
    a contextual lambda body vs a visible local-function method group — supplies a single-parameter
    contextual delegate's return type, refutation blocker 2's `Select`-result / MapGet-return machinery) now
    routes to `ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType` (lambda precedence,
    null → decline). The two duplicated single/zero-parameter inference helpers
    (`TryInferSingleParameterLambdaReturnType` + `TryInferZeroParameterLambdaReturnType`) collapsed into one
    mechanical host `TryPreflightContextualLambdaReturnType` that reuses the N#-owned `PlanContextualSignature`
    for the parameter-SHAPE decision (removing the third duplicated C# shape authority) and consumes the
    scoped sub-emitter body-preflight mechanically. Emitter 21,551 → 21,534 (net −17). GROUND TRUTH from the
    inventory: the inference's core (recursive body preflight = the C# expression-typing engine) and its
    validity gates (`IsSupportedType`/`TypesEquivalent`, reflection-bound) cannot move without porting the
    whole preflight engine, so they stay mechanical; only the SHAPE + SELECTION decisions were movable.
  * Stage 3b/4: PROVEN BLOCKED (re-inventoried THIS TURN, Candidate C). N# cannot own lambda-chain EMISSION
    or DELETE the enumerable EMIT+PREFLIGHT arms until the lambda BODY is plan-row-emittable: today a lambda
    body is emitted by a recursive C# sub-emitter (`new ColumnarIlEmitter(...)` at ColumnarIlEmitter.cs:1551 +
    `EmitLambdaBody` at :1566, NOT `ColumnarCodePlanExecutor` plan rows) and typed by the C# preflight engine
    (`TryPreflightContextualLambdaReturnType` → scoped sub-emitter body preflight). Stage 3a moved only the
    return-type SELECTION to N#; it did NOT unblock emission. Neither the chain-admission decision (Candidate A)
    nor the Cast/OfType type-argument binding (Candidate B) is a net-negative decision deletion (reasons in the
    Active sub-slice above). Proven byte-exact: neutralizing the three arms fails 8 corpus builds + 3 native
    projects with 0 common-file IL diffs — the arms are the sole load-bearing emitter of lambda-taking chains
    and Cast/OfType. RE-SEQUENCED: this family retires as a DEDICATED FUTURE TASK "plan-row lambda-body emitter"
    (whole-expression columnar emission of lambda bodies via schema plan rows executed by
    `ColumnarCodePlanExecutor`, + N# lambda-chain planning that retires the `ColumnarDirectCallPlanner.nl:112`
    contextual-lambda decline). Only after that lands can the old Stage 4 (below) delete the arms.
  * Stage 4 (GATED on the plan-row lambda-body emitter task above): DELETE the lambda-taking enumerable EMIT +
    PREFLIGHT arms (`TryEmitEnumerableExtensionCall` Where/Select/ToArray/ToList/Contains/Min/Max +
    `TryGetPreflightEnumerableExtensionCallType` mirror) — retires refutation blockers 1+2 together.
  * Stage 5 (Cast/OfType, separable from lambdas but a NEW-capability slice): the explicit-type-argument
    `TryEmitExplicitEnumerableExtensionGenericCall` Cast/OfType arm is lambda-free but its `TResult` is a
    return-type-only generic parameter the N# `ColumnarExtensionMethodResolver` cannot structurally bind (the
    explicit arg is never consumed by inference). Owning it needs N# explicit-type-argument extension-call
    support + ported type-node/member-chain resolution — a new capability, not a duplicated-fact deletion.
    Separable from Stage 4 and can precede or follow it.
  * Stage 5' (was Stage 5): receiver WIDENING with user-source-extension precedence — model user-source extension precedence
    in `ColumnarExtensionMethodResolver` so BCL generic `First`/`Last` never shadow user extensions
    (`examples/07-interfaces/ExtensionMethods.nl`, refutation blocker 3), then admit interface/variance
    receiver widening for the generic non-lambda arms. NOTE: the widening logic itself was proven correct in
    isolation but the `ColumnarExtensionMethodResolver` widening test was REVERTED with the refuted slice —
    contracts baseline is 740 (now 747 with Stage 1), NOT 741.
  * Stage 6: value-capture DISPLAY-CLASS lowering → N# (the fenced capturing residual in `TryEmitLambdaLiteral`,
    the `<>c__DisplayClass` `ModuleBuilder.DefineType` path) — model the reflection-emit display-class surface
    in the columnar backend and retire the C# capturing path.
- Refutation ground truth (d2257f33c, do not re-litigate): the `ToArray`/`ToList`/`Contains` family has NO
  deletion-ready subset before Stages 3–4 land. (1) the EMIT arms are LOAD-BEARING for lambda chains routed
  via the contextual-lambda decline; disabling ToArray makes WeatherDemo fail to build. (2) the PREFLIGHT
  arms are LOAD-BEARING for lambda RETURN-TYPE inference (MapGet `() => …ToList()`, Endpoints.nl:28) — only
  the byte-exact corpus IL diff catches the `List<IssueResponse>` → `object` regression; builds + the full
  unit suite do not. (3) receiver widening is not admission-safe until user-source-extension precedence is
  modeled (BCL `First`/`Last` shadow user extensions).
- Next smallest concrete sub-slice: NONE remaining as a movable-decision deletion. See the "015 completion
  roadmap" below (the exhaustive three-way policy inventory that replaces the former ad-hoc residual lists):
  after this slice the directly-MOVABLE decision surface is EXHAUSTED (base-call was the last inline
  string-classification split), and every remaining policy decision is BLOCKED-WITH-RECORD on a named future
  task or is already a MECHANICAL reflection-emit host. Do NOT reopen the lambda arms (blocked on the plan-row
  lambda-body emitter task), the case-12/13 live residual families (retire only under the four-surface gate as
  planner OPERAND forms unlock), or candidate (a) preflight static-call typing (load-bearing, not net-negative).
- Method note (this turn): the byte-exact product-IL sweep (scratchpad `verify_basecall.sh`: baseline HEAD via
  `git stash` vs working tree, both fresh Release CLIs, `sweepall.sh` over examples+fixtures+all 18 tests/native)
  yielded PRODUCT_IL_DIFFS=0 across all 162 N#-emitted assemblies. The only expected non-product diffs are the
  C# `Compiler.dll`/`BootstrapServices.dll` binaries copied as a reflection-test dependency by the six native
  reflection projects (they reflect any emitter/kernel source change); exclude them and compare only N#-EMITTED
  assemblies.
- Last committed ownership slice: the case-12 residual dead-arm prune at `6e94ca88c` (ratchet head
  `40cb7fa576abc6c2`, a fresh non-VS-Code gate is fully green there). This turn's base-call classification
  deletion is NOT committed (mandate: do not commit); the working tree carries the emitter deletion + the
  N# splitter `TrySplitBaseCall` + its tests + repin + this STATUS update.
- Prior accepted ownership commits: task 014's slice commits (`d396a847c`, `73ae226d5`,
  `0a33f1ff2`, `f3d1e89c9`).
- Queue: `tasks/README.md`

## Current evidence

- Task 005 is accepted at `6746c1b2c` (stage-0 prerequisites `67a3e5803`,
  `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`, and `ff2cf1138`). N# now owns
  construction planning end-to-end for the admitted family: ordinary source/runtime constructor
  calls with exact selection, defaults (including enum and dotted/aliased enum defaults), sized and
  inferred array literals with exact store opcodes, source class/struct/record and union-case object
  initializers (including nested values, generic-base member rebinding, and target-typed integers),
  closed source/runtime generic construction, and the approved runtime constructor catalog, all
  through schema-v3 plan rows executed and stack-validated by `ColumnarCodePlanExecutor`.
- The Analyzer's string-matched member/export/declaration resolution was deleted and replaced by
  the N#-owned `AnalyzerDeclarationContext`/`ColumnarSemanticTypeRegistry` exact-scope facts:
  `Analyzer.cs` fell from 23,471 to 23,068 lines. `ColumnarSynthesizedGenericScopeTests.cs` was
  deleted in favor of the native `generic-scope-invalid` project. Aggregate C# across the slice is
  net negative (−157 lines).
- The C# emitter retains exactly one fenced legacy surface for constructions: the whole-subtree
  residual (kinds 15/58/36 plus four helpers), reachable only when the N# planner declines without
  claiming (a value outside the plannable surface, e.g. interpolated holes or sibling-function call
  arguments). This mirrors the accepted task-004 fenced-call architecture; `ColumnarIlEmitter.cs`
  is 21,586 lines (epoch ceiling 21,723). The residual shrinks as later owners land (interpolation,
  sibling calls: task 015).
- Evidence: 3,182/3,182 units in the fresh gate (task 009's issue-tracker failure is FIXED by this
  slice); 553/553 BootstrapServices contracts; native product contracts all green: 14/14
  direct-calls, 18/18 ownership-audit, 7/7 construction-arrays (new), 3/3 generic-scope-invalid
  (new), 1/1 erased-enum-identity (new). Previously red vs HEAD and now green: `examples/16-task-cli`
  (union-case construction with interpolated argument), `examples/12-multi-file-projects/WeatherDemo`
  (record object initializer with call/index values), AutoDiscovery, issue-tracker backend check,
  and systems proof 36 (`new Dictionary<int,int>(capacity: 128)` named argument).
- The fresh non-VS-Code product gate has exactly four remaining failure groups, all verified
  byte-identical at HEAD `ff2cf1138` and assigned to later queue owners: Web API template build
  (009), Iterators single-file example (013), AsyncStreams single-file example (014), and the IL
  verification findings `RecordStructs.dll` CallVirtOnValueType/StackUnexpected (011) and
  `RecordsAndInterfaces.dll` InitOnly on `<InitializeFields>$` (012). Down from ten groups at the
  task-004 acceptance.
- The ownership growth ratchet is repinned to observed state (audit 18/18); the emitter entry rises
  only within its immutable epoch ceiling and records the restored fenced residual.
- Post-acceptance follow-ups `195028aa9` and `7f4e727d6`: columnar emission now runs on a dedicated
  wide-stack thread (MSBuild task threads run ~256 KB stacks and the emitter's per-node frames are
  large; the July-12 sources overflowed every fresh SDK-path emit), and the NL103 decline diagnostic
  is built inside that same thread (the decline trace is thread-local). The stale mid-slice SDK pack
  in `~/.nuget/local-feed` (the feed actually consulted; `~/.nsharp/packages` is not) was replaced,
  and the self-host loop is regenerative again: BootstrapServices Release re-emits cleanly through
  the packaged SDK, 553/553 contracts pass against the fresh kernel, and the clean repin is
  `nlc 0.1.0+7f4e727d615d2c38b5b71e6ac69690e5aa2275ff` with doctor status all-green.

## 015 completion roadmap

Exhaustive three-way classification of the REMAINING `ColumnarIlEmitter.cs` policy surface (this
replaces the former ad-hoc residual lists). Method: swept the full decision surface (516 members; the
`EmitExpressionCore` per-node-kind switch at ~10231, the `EmitStatement` switch at 6711, the preflight
typing engine `TryGetPreflight*`/`TryPreflight*` at 16718-17588, the interpolation core at 20340-21200,
the lambda family, and the declaration/reflection-emit hosting). N# planners run at the FRONT DOOR of
every dispatch (26 distinct `Columnar*Planner/Resolver/Facts` owners consulted before any C# residual
arm); the residual switch arms are whole-subtree-exit servers for non-plannable OPERAND bands.

### MOVABLE (an existing N# owner absorbs it with a named C# deletion) — EXHAUSTED
The interpolation string-classification splits were the only clean movable-decision family, and
`TrySplitBaseCall` (this slice) was the last of them (cast/equality/coalesce/integer-additive landed at
9a3c20950/aff33f1db/d37d3d732). The ~40-arm prior inventory (notes_015_pivot.md) plus this sweep find no
further decision an existing N# owner can absorb with a net-negative C# deletion. The two marginal
remainders are NOT clean decision deletions and are declined: decimal-literal VALUE parse (case 0/1 →
`TryEmitDecimalLiteral`, fused with the reflection-backed `decimal(...)` ctor emission → net N#+plumbing
positive, no decision deleted) and the entry-point return-shape rule (already N#-owned for async via
ColumnarIteratorPlanner facts; residual is reflection-typed return wrapping).

### BLOCKED-WITH-RECORD (proven/provable; retires via a named OTHER task)
1. LAMBDA-TAKING FAMILY — the dominant remaining policy block. `case 9` residual calls →
   `TryEmitEnumerableExtensionCall` (~17792: Where/Select/ToArray/ToList/Contains/Min/Max),
   `TryEmitExplicitEnumerableExtensionGenericCall` (~13943: Cast/OfType), `TryEmitLambdaLiteral` (~1491)
   + `EmitLambdaBody` recursive C# sub-emitter (~1702), `BodyReferencesEnclosingChain` (~1724), the
   `<>c__DisplayClass` capturing residual, and the preflight `TryPreflightContextualLambdaReturnType`
   (~17588) / `TryGetPreflightEnumerableExtensionCallType` (~17215). A lambda body is emitted by a
   recursive C# sub-emitter + typed by the C# preflight engine, not by plan rows. Stages 1–3a landed
   (signature/capture-set/return-type SELECTION → N#); Stage 3b/4/5/6 GATED on the FUTURE TASK "plan-row
   lambda-body emitter". Cited: lambda-arc Stages 3b–6, refutation d2257f33c, arms-off byte-exact proof.
2. C# PREFLIGHT TYPING ENGINE. `TryGetPreflightExpressionType` (~16718) + family
   (Binary/InstanceCall/MemberAccess/ExtensionSibling/ExtensionStatic). Reflection-bound expression-TYPING
   authority serving interpolation parsed holes + lambda return inference. Candidate (a) proven
   load-bearing (types the user's own enclosing-type statics, not catalog facts); its reroute is the
   forbidden add-a-planner-for-a-relocation anti-pattern. Retires via a FUTURE N# typing-owner port
   (adjacent to 017 analyzer semantic ownership).
3. LIVE case-12/13 RESIDUAL FAMILIES. `case 12` (short-circuit `&&`/`||`, null-comparison nullable+ref,
   `??` coalesce nullable+ref, signed arith `+`/`-`/`*`/`/`, ordering `<`/`<=`/`>`/`>=`, ref-identity
   equality on user reference types, string+char concat, String.Concat pair) and `case 13` ternary — all
   self-emit-load-bearing (four-surface probe). Retire ONLY as their non-plannable OPERAND forms become
   N#-plannable (member-chains-on-call-results, dictionary indexers, enum string constants) via the
   planners — an incremental four-surface-gated cut, not a movable relocation. Cited: 6e94ca88c prune.
4. BLOCKING-AWAIT MODEL. `case 53` await (`TryEmitBlockingAwait` ~6643) + `case 73` await-foreach
   consumer. The accepted synchronous GetAwaiter().GetResult() model retires when REAL async-func lowering
   lands (a FUTURE async-func task). Cited: 014 residuals.
5. INTERPOLATION CHAIN/PARSED-HOLE RESOLUTION. `TryResolveInterpolationChainPlan`/`TryResolveInterpolationHole`
   (~20885) + `TryResolveInterpolationMemberPlan` (~21041) + `TryParseInterpolationExpressionHole`/
   `TryGetParsedInterpolationExpressionType`. Chain tokenization is intertwined WITH reflection member/
   local/getter resolution (hop boundaries drive reflection) and parsed holes route through the preflight
   engine (#2). No clean string-classification split remains to peel off; retires with the preflight port.

### MECHANICAL (reflection-emit hosting, zero policy — the target end-state, already non-growing)
- Control flow + structural statement arms: block/if/while/for/return/break/continue, try/catch region ops
  (schema-4), lock lowering, throw, print, var/typed-local/tuple-deconstruction lowering, assert/
  assert-throws, expression-statement assignment, the StatementExits analysis mirror.
- Expression mechanical arms: parenthesized (7), checked-context (57), spread (64), unary (11, via
  ColumnarSourceOperatorResolver), is/as isinst (46/47), must (45), postfix ++/-- (44), match/pattern-test
  emit (18/34/33/35/32/8-pattern via ColumnarPatternFacts), index reads (10), anonymous-object synthesis (59).
- Construction/with/record/field-init: kinds 15/58/36/42 (ColumnarConstructionPlanner), 52
  (ColumnarRecordWithPlanner), record member synthesis, ColumnarFieldInitPlanner.
- Iterator/async hosting: yield (72), foreach (29), MoveNext/state-machine emission
  (ColumnarIteratorPlanner/ColumnarIteratorBodyPlanner), async fault guards.
- Type/member definition: DefineType/DefineMethod/DefineGenericParameters, union/generic declaration +
  constraints, delegate mapping (IsSupportedDelegateType/CreateDelegateType), bare-static + ref/out-deref
  reads (case 6), typeof, interpolation cast/equality/call-argument emit, and the base-call reflection
  RESOLUTION (this slice's mechanical host over TrySplitBaseCall's extracted name).

### VERDICT
015 does NOT complete this turn; its box stays UNCHECKED. After this slice the directly-MOVABLE decision
surface for 015-proper is EXHAUSTED. What concretely remains before the "reviewed, non-growing, zero-policy
mechanical host" criterion is met is ALL BLOCKED-WITH-RECORD policy that retires only via OTHER queue tasks:
- the FUTURE "plan-row lambda-body emitter" task (retires blocker #1: lambda family Stages 4/5/6 + the
  enumerable/Cast-OfType arms + display-class);
- a FUTURE N# preflight/typing-owner port (retires blockers #2 + #5: the C# typing engine and interpolation
  parsed-hole resolution) — adjacent to 017 analyzer;
- a FUTURE async-func-lowering task (retires blocker #4: blocking await);
- incremental planner-driven OPERAND unlocks that let the live case-12/13 residual families (#3) retire
  under the four-surface gate.
016 (parser) and 017 (analyzer) own the LSP-fallback parser/analyzer, NOT the emitter. 015's cursor is
therefore: no movable decision remains in the emitter; 015 is gated on the four future tasks above.

## 016 parser/diagnostic ownership finding

Verdict (this turn, PROVEN-BLOCKED-WITH-RECORD; no production edit, no commit): no bounded syntax
behavior can be moved from `src/NSharpLang.Compiler/Parser.cs` (7,117 lines; ratchet row
`compiler-core`, ceiling 7,117, fingerprint `text-v1:895641da1f9de8a6`) to N# as the "sole production
parser + ordered diagnostic authority" this turn while keeping every compiler AND Language Server
consumer byte-exact. The AST-shape half and the syntax-diagnostic half are gated on the SAME missing
prerequisite. Evidence below is code + committed-test grounded (the C# model is verified-green by the
full VS Code-enabled gate at HEAD `2859f8329`); no fresh live run was required.

### Inventory — who consumes `Parser.cs` output (exactly)
`Parser.ParseCompilationUnit()` returns `ParseResult { CompilationUnit, Errors }` — the C#
`CompilationUnit` AST + the syntax diagnostics. Every non-emit front-end consumes it MONOLITHICALLY:
- `MultiFileCompiler.ParseAllFiles` (192-198): `_allErrors.AddRange(parseResult.Errors)` — the
  production `nlc build`/check syntax-diagnostic source; Analyzer/Systems/Linter then run on the C# AST.
- `LanguageServer/Services/DocumentManager` (250-296): builds `state.CompilationUnit` ONCE, then the
  Analyzer, Linter, symbol/hover/completion extraction, and all 25+ LSP handlers read that one AST.
- `Analyzer.cs` (5 parse sites: cross-file/project/import), `Formatter.cs`, CLI `Program.FormatSource`
  (688) + `LintCommand` (90), `CodeIntelligence/{FixApplicator,CodeIntelligenceService}` (fix/query),
  `Playground`.
The N# columnar parser kernels (`CompilerServices/ColumnarParserKernels.nl`, 13,773 lines) produce
columnar node TABLES consumed ONLY by the emit pipeline (`ColumnarProgramInputBuilder` →
`ColumnarIlEmitter`), and only AFTER the C# path is error-free (`MultiFileCompiler` gates emit on zero
errors). They build no `CompilationUnit` and feed no tooling/LSP consumer. NO node-table→C#-AST bridge
exists; materialization-to-AST was explicitly rejected (memory
`project_parser_routing_materialization_deadend`: "port downstream to consume columnar tables directly").

### Why the AST-shape families are blocked (imports/namespaces, type/member decls, functions/generics, statements, expressions, patterns)
Moving any AST-shape behavior to N# requires the tooling/LSP front-end to consume N#-produced facts for
that behavior. The front-end reads the whole C# `CompilationUnit` as one recursive tree; a single node
family cannot be excised from that tree without breaking the tree the Analyzer/LSP read, and there is no
bridge to splice N# facts in per-family. Blocked on the bridge.

### Why the syntax-diagnostic families are blocked (the unwired `ColumnarSyntaxDiagnostics` arc)
A prior 9-commit arc (`760cf0203`..`771f741b7`, Jul 8, ALL ancestors of HEAD, ALL PURE ADDITIONS — zero
`Parser.cs` deletion, zero consumer wiring) built an UNWIRED N# owner: `ColumnarSyntaxDiagnostics.ParseFile`
+ `ParserDiagnosticMessages.Materialize` + `ParserDiagnosticsTable`. It has ZERO external references (C#
or N#), is in no `.tests.nl`, and `Parser.cs` still owns every production syntax diagnostic. It CANNOT be
wired byte-exact, for three independent reasons:
1. COVERAGE. It mirrors ~20 of `Parser.cs`'s ~256 distinct syntax diagnostics (100 emit sites) — 10
   "expected-token/malformed" families only (`ParserDiagnosticMessageKind` 1-20). Wiring `ParseFile` as
   the sole authority would LOSE ~236 diagnostics (missing `)`/`]`/`}`/`:`/`;`/`=>`, unexpected tokens,
   dangling operators, constraint conflicts, pattern/match/test-DSL errors, …) — a catastrophic regression.
2. DIVERGENT SUPPRESSION MODEL. `Parser.cs` emits inline during ONE recursive-descent pass gated by one
   shared `_panicMode` flag (`ReportError` at 6856 returns early if panic; sets panic after each error;
   resets only at true parse-structure sync points — declaration/statement/member/case boundaries).
   Committed tests PIN this: `Parser_CascadingErrorsSuppressed` (`Errors.Count <= 5`),
   `Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements` (exactly one error, exact column 14
   / length 3, parse-context message "Expected expression after '+'"). The N# owner runs 10 INDEPENDENT
   whole-token-scan collectors, each with a per-token-boundary panic heuristic (`ParserDiagnosticTable.
   PanicMode`, reset at Newline/Semicolon/Comma/Brace) threaded across sequential passes. The models
   diverge exactly in the cascading-error cases the tests pin, and the collectors fire on scan-reached
   tokens vs the parser's parse-reached tokens.
3. SHARED-PANIC COUPLING ⇒ NO BOUNDED SINGLE-FAMILY EXTRACTION. Deleting any one family's inline
   `Parser.cs` report also deletes its `_panicMode = true` side-effect, changing the suppression seen by
   every subsequent diagnostic of EVERY OTHER family. So even a single-family diagnostic move is not
   side-effect-free and cannot be verified byte-exact against the 520-assertion
   `LanguageServerDiagnosticsTests` + `ParserErrorTests`/`ErrorHandlingTests`.
Note: the C# report site already delegates `CompilerError` CONSTRUCTION to the shared N#
`ParserErrorDiagnostics.Create`, so only the DECISION (whether/where to report, under the shared panic
model) + the message/hint/suggestion literals are C#-owned. Moving just the literals is NOT a
decision-ownership move and is declined.

### Prerequisite that unblocks 016 (sized honestly)
One N# parse front-end whose output the C# tooling/IDE consumers can consume in place of `Parser.cs`. Either:
(a) Extend the N# columnar parser kernels to (i) emit the FULL syntax-diagnostic surface WITH the parser's
    shared-panic recovery model (NOT the `ColumnarSyntaxDiagnostics` token-scan mirror) and (ii) expose a
    `CompilationUnit`-equivalent / node-table facts the Analyzer/Linter/Formatter/LSP handlers consume;
    validated byte-exact against the diagnostic + parser-error suites. This is a PARSER-KERNEL change → it
    TRIPS THE TWO-STAGE BOOTSTRAP WALL (coordinator toolset repin required before dependent code compiles)
    and is a multi-slice effort, not one bounded deletion. OR
(b) Port the tooling front-end (Analyzer/Linter/Formatter/LSP handlers) to consume the columnar node tables
    directly (the memory-endorsed direction) — task 017+ (analyzer ownership) scope, far beyond one bounded
    parser slice.
The `ColumnarSyntaxDiagnostics` arc is scaffolding for path (a)'s diagnostic half but is incomplete (~8%
coverage) and model-divergent; it must NOT be wired as-is. `Parser.cs` stays the sole production syntax
parser/diagnostic authority until the prerequisite lands; 016 stays UNCHECKED.

### Staged parser-front-end ARC PLAN (chosen: path (a), the recovery-aware N# front-end)
The finding above is STAGE 0 (the prerequisite record). The arc builds path (a)'s kernel-side capability to
FULL parity FIRST (family by family, each stage's diagnostics proven byte-exact against Parser.cs on a
native parity corpus), then production-wires the consumers LAST at parity, then deletes Parser.cs. This is
the 013/014/lambda-arc precedent: a proven-record capability arc, not a single byte-exact deletion. No
production shadow/comparison route ever runs — parity proofs live only in `.tests.nl`.

- STAGE 1 (LANDED this turn) — the SHARED-PANIC RECOVERY MODEL + first diagnostic family. New owner
  `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` faithfully reproduces Parser.cs's
  recovery discipline (one shared `PanicMode`; `Report` suppresses-while-set / records-in-source-order /
  sets-panic; reset ONLY at the declaration-boundary sync point; the `ConsumeIdentifier` reserved-keyword /
  end-of-file / found-other variants; `LastVisibleTokenSpan` EOF anchoring) and carries the
  IMPORT / NAMESPACE / PACKAGE family end-to-end (qualified-name identifier errors, dot-access member
  errors, missing import alias, duplicate-package). Diagnostic CONSTRUCTION delegates to the already-live
  shared owner `ParserErrorDiagnostics.Create` (the same call Parser.cs uses), so codes/snippets/docs URLs
  match automatically. Proven by 11 native contracts in `ColumnarParserRecovery.tests.nl` against golden
  Parser.cs output captured from the fresh CLI — INCLUDING the two committed-test model shapes: cascading
  suppression (triple-package → 1 diagnostic; the third suppressed with no intervening reset, mirroring
  `Parser_CascadingErrorsSuppressed`) and does-not-swallow-following (package/package/stray-token → 2
  diagnostics; the declaration-boundary reset lets the stray token report, mirroring
  `Parser_DanglingBinaryOperator_...`). NO production wiring; NO wall tripped (self-contained new files, the
  packaged SDK emits them — no repin). Evidence: BootstrapServices contracts 773/773 (762 baseline + 11);
  ownership audit 18/18; dev.sh Parser 381/381.
- STAGE 2 (LANDED this turn) — the DECLARATION-NAME family. Extended `ColumnarParserRecovery.nl` with
  `ConsumeDeclarationName` (Parser.cs ConsumeIdentifier with a non-null diagnosticSpan, :6720) carrying the
  "Expected <kind> name" diagnostics for func / class / struct / record / soa record / interface / union /
  enum / type-alias, with the `DiagnosticSpanFromToken` KEYWORD-ANCHORING discipline (missing/invalid name
  underlines the declaration keyword in all three variants) and the reserved-keyword-as-name variant; plus
  the `ParseTopLevelDeclaration` dispatch (ParseModifiers + the exact Parser.cs keyword order incl.
  `ref struct` / `soa record` / `duck interface` / `record struct` + LookAhead), the per-kind name parsers,
  and the boundary/force-advance loop (Parser.cs ParseCompilationUnit :83/:99-108). Bodies are NOT parsed;
  the corpus keeps to shapes where a name-only parser is byte-exact with the full Parser.cs body parse
  (absent-at-EOF, reserved-keyword-then-EOF for every kind; found-other only for func/enum/type, whose
  failing body consumes no trailing token so the stray token fires at the next boundary — the panic-reset
  demonstration). +24 native contracts; BootstrapServices 797/797 (773+24); ownership audit 18/18; git
  status shows only the two `.nl` files (no non-N# move). NO production wiring; NO wall (self-contained).
- STAGE 3 (LANDED this turn) — the MALFORMED-LITERAL family (NL105 `InvalidLiteral`). Extended
  `ColumnarParserRecovery.nl` with `ReportMalformedLiteralIfNeeded` → the three Parser.cs reporters
  (`ReportMalformedCharLiteralIfNeeded` :4905 / `ReportMalformedStringLiteralIfNeeded` :4830 /
  `ReportMalformedRawStringLiteralIfNeeded` :4876), carried through the shared-panic `Report`. ORIGIN: every
  malformed-literal diagnostic is Parser.cs-REPORTED inside `ParsePrimaryExpression` (:4646/:4653); the
  already-N# `Lexer.nl` only CLASSIFIES (`Token.IsTerminated` + the token value), emitting NO diagnostic, and
  the malformed DECISION delegates to the live shared `ParserLiteralFacts` (Parser.cs delegates identically).
  So the family belongs to the parser model, NOT a lexer lane. Reached via the shallowest byte-exact literal
  context — the expression-bodied `func f() => <literal>` — through a MINIMAL literal-reaching expression path
  (paren + literal primary + minimal binary-operator continuation); the expression/statement ERROR families
  (unexpected-token-in-expression, dangling operator, missing `)`) are DEFERRED to their own stages and never
  fire here (suppressed under the same shared panic, so output stays byte-exact). +14 native contracts:
  per-shape single-malformed, across-boundary (next fires), in-region suppression (`'a + 'b` → 1), and
  negatives. BootstrapServices 797→811; dev.sh Parser 381/381; ownership audit 18/18; NO production wiring;
  NO wall (self-contained). NOTE for later: `import`-path strings and test-description strings do NOT run the
  malformed check (verified: `import "abc` → NL701, not NL105), so they are correctly out of this family.
- STAGE 4 (LANDED this turn) — the MEMBER / PARAMETER / FIELD declaration family (NL102 `ExpectedToken` /
  NL109 `ReservedKeywordAsName`). Extended `ColumnarParserRecovery.nl` with a real `ParseParameterListRecovery`
  (from the function head) carrying the parameter name (`ConsumeIdentifier`(message, span?) :6720 +
  `GetMissingParameterNameDiagnosticSpan` :6476), colon (`ConsumeParameterColon` :6625, name-anchored), and
  type (`ParseParameterTypeReference` :6504) errors; and a braced-body path (`ParseClassName` / `ParseStructName`
  → `ParseTypeBodyIfPresent` → `ParseMemberList` → `ParseFieldMember`) carrying the field name
  (`ConsumeIdentifier` "Expected field name" :1666), colon (`ConsumeFieldColon` :6651, name-anchored), and type
  (`ParseFieldTypeReference` :6536 with `LooksLikeNextFieldAfterMissingType` :6572) errors, plus the
  `ParseMemberList` per-member panic-reset sync point (:1365). RETIRED the Stage-2-deferred braced-kind
  found-other NAME for the `{`-offender variant (`class {` / `struct {`) — now reachable because the offending
  `{` is consumed as the empty body brace; `ParseTypeBodyIfPresent` enters the body for a valid name (→ fields)
  or an `<error>` name ONLY when the offender is `{`, so no Stage-2 multi-declaration case regresses (proven by
  the unchanged Stage-1/2/3 contracts). Bodies parse FIELD members only; type-params/primary-ctor/base-lists,
  the missing-`{`/`}` (NL106) reports, and the method/nested/constructor/record-positional/union-case member
  grammars are later stages (corpus avoids them). +17 native contracts (7 parameter, 8 field incl. the
  member-boundary-reset two-field and two-class shapes, 2 braced found-other). DEFERRED with reasons: the
  non-`{` braced found-other (`class 5`) and non-identifier parameter name (`func f(5)`) both emit garbage-type
  cascades whose report order diverges from the oracle's position-sorted output (need `ParseTypeReference`-
  on-garbage + `SynchronizeToNextStatement` + sorted emit); trailing-comma
  (`ReportMissingParameterAfterTrailingComma`) and the closing-delimiter recovery are their own stages.
  BootstrapServices 811→828; dev.sh Parser 381/381; ownership audit 18/18; NO production wiring; NO wall
  (self-contained; packaged SDK self-emitted the edited owner + all 828 contracts — no repin).
- STAGE 5..N (per-family capability, each proven byte-exact on the parity corpus, NO production wiring):
  extend `ColumnarParserRecovery` family by family until it matches Parser.cs's full ~256-diagnostic
  surface under the shared-panic model. Suggested order (smallest-coherent first, member/parameter/field +
  generics/constraints DONE above): [STAGE 5 DONE — generics/constraints: `ConsumeGreater`, split `>>`,
  type-param / type-argument errors, `where`-clause constraints] → [STAGE 6 DONE — statements: the block-body
  grammar + `SynchronizeToNextStatement` sync point + per-statement panic reset + `_currentRecoveryBoundaryColumn`,
  the dangling-operator through-token span, missing-initializer `:=`/`=`, missing if/while condition, missing
  for/foreach `in`, missing-statement-body] → [STAGE 7 DONE — expressions (recut A): the fuller precedence ladder +
  the expression ERROR families unexpected-token-in-expression / prefix `+` / leading `.` / ternary errors /
  dangling-operator-per-tier / await-must-throw missing-operand / member-name-after-dot] → [STAGE 8 DONE — the
  MATCH / PATTERN family (`ParseMatchExpression` + `ParsePattern`/`ParsePrimaryPattern`/`ParsePropertyPatterns`; the
  "match/patterns second" recut half)] → [STAGE 9 DONE — closing-delimiter recovery (`TryReportMissingClosingDelimiter`,
  missing `)` NL107 / `]` NL108 + the block/type-body missing-`}` NL106 + the parameter trailing-comma; retired
  STAGE 5's deferred `new(` missing-`)`, STAGE 6's block missing-`}` [EOF + found-declaration], STAGE 8's pattern-list
  `]` / positional `)` closes, and STAGE 4's parameter trailing-comma)] → [STAGE 10 DONE — the POSTFIX CALL / INDEX /
  generic-call / `with {…}` + call-argument family (`ParseArgumentList`: inline-out NL103 + spread / named / bare-alloc
  recognition, closes via the Stage-9 recovery) and the first keyword-led-primary tranche (new incl. the object-init
  panic-reset-on-progress + `ParseNewTypeReference`; cast via the ported `IsCastExpression` scanner; the full tuple /
  parenthesized grammar; typeof / nameof / sizeof / checked / unchecked; array literal); +40 contracts]. STAGE 2's
  non-`{` declaration-body found-other and the remaining keyword-led primaries (alloc / stackalloc / interpolation /
  lambda) + `is`/`as` remain — STAGE 11+.
  Each stage adds the family's `ConsumeX`/`ReportError` sites + its sync-point discipline, and grows the
  parity corpus; each stays self-contained (new/edited `.nl` in BootstrapServices + `.tests.nl`) UNLESS a
  stage needs a kernel entry point dependents compile against — that stage TRIPS the two-stage bootstrap
  wall and needs a coordinator repin (call it out at stage start).
- STAGE N+1 (AST/node-table facts): expose a `CompilationUnit`-equivalent / node-table surface the
  Analyzer/Linter/Formatter/LSP consume in place of Parser.cs's C# `CompilationUnit`, proven fact-equivalent.
- STAGE N+2 (CUTOVER, IDE-AFFECTING): at full diagnostic + AST parity, route every consumer
  (`MultiFileCompiler.ParseAllFiles`, `DocumentManager`, `Analyzer`, `Formatter`, CLI format/lint,
  `CodeIntelligence`, Playground) directly to the N# front-end. VS Code-enabled gate + extension reinstall +
  computer-use visual check. No shadow route.
- STAGE N+3 (DELETION ARC): delete Parser.cs's per-family parsing/recovery/reporting decisions as each
  consumer is cut over, ending when Parser.cs is deleted or is a reviewed zero-policy mechanical host
  (`compiler-core` ratchet row retires). The C# `ParserErrorTests`/`ErrorHandlingTests`/
  `LanguageServerDiagnosticsTests` assertions migrate to native `.tests.nl` as their families cut over.

### Scaffolding fate decision (recorded): DELETE the divergent `ColumnarSyntaxDiagnostics` closure
The inert prior-arc scaffolding is SUPERSEDED by `ColumnarParserRecovery` (which uses the correct shared
ordered-panic model, not the divergent 10-pass per-token-scan model that must never be wired). The closure
`{ColumnarSyntaxDiagnostics.nl, ParserDiagnosticMessages.nl, ParserDiagnosticsTable.nl}` was fully
self-contained (zero external references — verified across all of src+tests; the four support types
`ParserDiagnosticTable`/`ParserDiagnosticTableOps`/`ParserDiagnosticMessageKind`/`ParserDiagnosticContextKind`
were reachable only through that closure) and has been DELETED this turn to honor the no-dead-code rule.
`ParserErrorDiagnostics.nl` is KEPT — it is LIVE (Parser.cs and now `ColumnarParserRecovery` both call
`ParserErrorDiagnostics.Create`). Its message templates are not lost: the message ORACLE is Parser.cs
itself, and git history preserves the scaffolding. Not ratchet-tracked (all `.nl`); the deletion left the
BootstrapServices contract count unchanged at 773 (the deleted files carried no `.tests.nl`).

## 016 AST/facts bridge (N+1) design record

The diagnostic-capability arc (Stages 0-17) is complete: `ColumnarParserRecovery.nl` reproduces every Parser.cs
syntax diagnostic byte-exact (432 native contracts). N+1 turns that recovery-only owner into one that ALSO produces
the AST the non-emit consumers read, so that at N+2 (cutover) every consumer can be routed to the N# owner and at N+3
Parser.cs can be deleted. This section is the definitive N+1 design.

### Consumer-needs inventory (what each consumer reads from ParseResult / CompilationUnit)
`Parser.ParseCompilationUnit()` returns `ParseResult { CompilationUnit?, Errors, Success }`. Verified consumer-by-
consumer (13 production parse sites; grep of `ParseCompilationUnit` / `new Parser(` / `.CompilationUnit`):
- `.Success` is NEVER read by any consumer — the bridge need not reproduce it (it is a convenience predicate).
- `.Errors` (`List<CompilerError>`) is read by MultiFileCompiler.ParseAllFiles (:198), DocumentManager (:255/:301),
  Analyzer's import site (:21708), Formatter's re-parse gate (:39), CLI FormatSource (:691) + LintCommand (:92/:113).
  The owner ALREADY produces this list identically (the whole 432-contract arc) — the `Errors` half is DONE.
- `.CompilationUnit` (`Ast.CompilationUnit`) is read by all 13 sites. What they read off it:
  * `Namespace` / `Package` — Analyzer.GetUnitNamespace = `Package?.Name ?? Namespace?.Name` (:22066), used by
    project-namespace resolution (Analyzer :19122/:22012/:22038) and Formatter (:67/:117).
  * `Imports` (`List<ImportDirective>`, `.Namespace`) — Formatter (:79/:111), CodeIntelligenceService.GetOutline (:126).
  * `FileImports` (`List<Statement>` of FileImport/NamespaceImport; `.Path`/`.Line`/`.DiagnosticColumn`/
    `.DiagnosticLength`) — MultiFileCompiler (:248), Analyzer import site (:21736/:21740), Formatter (:96/:111).
  * `Declarations` (`List<Declaration>`) — recursed by Analyzer.Analyze, Linter.Lint, SystemsAnalyzer.Analyze,
    Formatter.Format, and 12+ LSP handlers (DocumentSymbol/CallHierarchy/TypeHierarchy/SemanticTokens/Completion/…).
  * `Line` / `Column` — the AstNode base coordinates.
  * FixApplicator (:29) positionally CONSTRUCTS a fallback `CompilationUnit(null, [], [], null, [], 1, 1)` — so a
    consumer already depends on the C# CompilationUnit constructor shape.
- RECORD-FEATURE AUDIT (does any consumer rely on AST nodes being C# `record`s?): NO `with`-expressions and NO
  positional deconstruction on any parser AST node anywhere in src. AST-node-keyed collections all use
  `ReferenceEqualityComparer` (Linter/Analyzer/SystemsAnalyzer). The ONLY value-equality dependency on a parser record
  is `Analyzer.cs:18169` — `pattern.Properties.Except(constrainedProperties)` over `List<PropertyPattern>` (a record),
  where `constrainedProperties` is a `.Where`-filtered subset so it works by identity coincidence today. CONCLUSION:
  migrating the AST hierarchy from C# `record`s to N# CLASSES (reference equality) is safe for every consumer EXCEPT
  that one `Except`, which must be reproduced with `ReferenceEqualityComparer` or rewritten to a reference-based diff
  at cutover. This removes the only real risk from the "AST-as-N#-classes" migration.

### Bridge-shape decision (chosen: option (a) — the owner constructs the production Ast types directly)
Two shapes were weighed under the hard constraint NO new production C#:
- (a) The N# owner CONSTRUCTS the existing production `NSharpLang.Compiler.Ast` node instances directly. The consumers
  are statically typed against `Ast.CompilationUnit` and its field types, so the bridge MUST output exactly those
  types; producing them directly means N+2 cutover changes zero consumer field-reads. PROBED viable: the three preamble
  leaf types are already N# classes in this assembly and the owner constructs them field-exact THIS turn; N# supports
  the class-inheritance hierarchies the AstNode tree needs (TypeInfoModels.nl: `class ClassTypeInfo: TypeInfo` + 12
  siblings); and the record-feature audit shows classes suffice. The 2026-06 decision that rejected node-table→C#-AST
  materialization was an EMIT-path perf decision; the TOOLING path already pays AST materialization today (Parser.cs
  builds the full tree for every consumer), so (a) carries no new perf cost there.
- (b) An N#-native fact surface the owner exposes, with consumers rewritten to read it. REJECTED: it pushes an enormous
  consumer rewrite (Analyzer/Linter/Formatter/every LSP handler recurse the typed `Declarations` tree) into N+2 and
  still must reach full AST fidelity. (a) confines the work to the parser side and keeps consumers byte-stable.

Rationale recorded: (a) is correct, and its enabler is moving the AST TYPE DEFINITIONS upstream to N# so the owner can
NAME/construct them — the precedent is already set (ImportDirective/PackageDeclaration/NamespaceDeclaration moved to N#
classes in BootstrapServices and Parser.cs constructs them fine). This is the mandate's "shrink C# / move to N#"
pattern, not new C#.

### The CompilationUnit-container block (proven precisely) — and what unblocks it
The owner CAN construct today (all N# in this assembly): `NamespaceDeclaration`, `ImportDirective`, `PackageDeclaration`,
`CompilerError`. It CANNOT construct: `CompilationUnit`, `FileImport`, `NamespaceImport`, the `AstNode`/`Statement`/
`Declaration` bases, and every concrete Declaration/Statement/Expression subtype — because they are C# in the DOWNSTREAM
`NSharpLang.Compiler` assembly and `BootstrapServices` cannot reference it (Compiler → BootstrapServices; the reverse is
a cycle). This is an ASSEMBLY-DEPENDENCY block, NOT an emitter gap: no `.nl` emitter operand family is missing — the
types are simply not nameable upstream (confirmed: BootstrapServices `.nl` code that must touch a `CompilationUnit`
takes it as `object` + reflection). Even an EMPTY-Declarations preamble `CompilationUnit` is blocked, because its
constructor signature NAMES `List<Statement>` and `List<Declaration>` (downstream bases). A thin C# assembler in the
Compiler assembly would be new production C# (forbidden); routing Parser.cs's preamble into the owner is the N+2
cutover (out of scope, and Parser.cs must stay authority this stage).

UNBLOCK (the bulk of N+1): move the AST type hierarchy upstream to N#. The hard sub-constraint is that C# `record`s
cannot derive from N# classes, so the AstNode → {Expression, Statement, Declaration} → concrete-subtype hierarchy must
move TOGETHER (all-or-nothing at the base). The record-feature audit shows N# CLASSES suffice (only the one
`PropertyPattern` `Except` needs care), so the migration is: port `AstNode` + all subtypes (Declarations.cs,
Statements.cs, Expressions.cs — ~3 files, deep but mechanical record→class ports) into N# in an assembly the owner
references (BootstrapServices, or a dedicated upstream `NSharpLang.Compiler.Ast` N# assembly both the owner and Compiler
reference). Parser.cs keeps constructing the SAME (now-N#) types, so it is untouched until cutover; the C# record
definitions are deleted as they move (shrink, not new). NO emitter-operand unlock is required (this does NOT feed the
015 planner-operand backlog) — it is a location/dependency migration, gated only on the record→class port + the single
`Except` fix.

### Refined N+1..N+3 staging
- N+1a (LANDED this turn): the owner constructs the preamble leaf subtree (Namespace/Imports/Package) + the Errors list,
  field-exact to Parser.cs, via `ParseFilePreambleAst`. Proves the direct-construction mechanism on the upstream types.
- N+1b (LANDED — no commit): migrated the ENTIRE AST type hierarchy (AstNode + Statement/Declaration/Expression/
  InterpolatedStringPart/Pattern bases + all ~110 subtypes + CompilationUnit + FileImport/NamespaceImport + the standalone
  helpers) from C# records to N# classes in BootstrapServices (`Expressions.nl`/`Statements.nl`/`Declarations.nl`); DELETED
  the C# `Ast/` directory (844 lines); reproduced the `PropertyPattern` value-equality site (Analyzer.cs:18169) with a
  reference-based `Where(!ReferenceEquals)`. The tranche was ALL-OR-NOTHING at the base (records can't derive from N#
  classes + mutual recursion with the helpers) — no smaller safe partition exists, so the whole cluster moved in one slice.
  CompilationUnit is now constructable from the owner. NO emitter unlock; NO two-stage bootstrap wall (self-contained leaf
  classes, packaged SDK self-emitted them). Full-bar evidence green incl. an EMPTY byte-exact corpus IL diff (159
  assemblies) — see the THIS-TURN Active sub-slice.
- N+1c: extend the owner's recovery grammar (already at full diagnostic parity) to also MATERIALIZE the full node tree
  (declarations/statements/expressions) it currently parses for diagnostics only, returning a real `CompilationUnit`;
  prove node-by-node structural equality against Parser.cs on the parity corpus (comparison in `.tests.nl` only).
  - TRANCHE 1 LANDED: `ParseFileAst` returns a real `CompilationUnit` for the container + preamble +
    FileImports + empty-body struct/interface/enum/record top-level declarations, proven node-by-node equal to
    Parser.cs by the reflection deep-equal harness `AstEq` in `ColumnarParserAst.tests.nl` (13 contracts; 1215/1215
    BootstrapServices). ClassDeclaration deferred on a MISDIAGNOSED "planner gap" (see tranche 2).
  - TRANCHE 2 LANDED (this turn): ClassDeclaration materialized (empty-body/modifier-free corpus), +2 contracts
    (1217/1217). The tranche-1 ClassDeclaration blocker was root-caused and DISPROVEN — it was NOT a columnar
    constructor-planner gap on the `BaseClass: TypeReference?` param but a SIMPLE-NAME TYPE COLLISION:
    `AnalyzerDeclarationContext.tests.nl` defines local test-helper classes `ClassDeclaration`/`TypeAliasDeclaration`/
    `FieldDeclaration` (namespace `NSharpLang.Compiler`) that collide, under the tests-enabled build, with the real
    `NSharpLang.Compiler.Ast.*` types the owner constructs, making the simple name resolve ambiguously. Resolved with
    the byte-exact fully-qualified-name idiom (`new NSharpLang.Compiler.Ast.ClassDeclaration(...)`) — NO planner
    extension, NO two-stage wall. Full detail + the member-tranche viability proofs are in the THIS-TURN Active
    sub-slice.
  - TRANCHE 3 LANDED: members threaded through `ParseTypeBody` (nesting-safe), FieldDeclaration + single-token
    SimpleTypeReference materialized. TRANCHE 4 LANDED: modifiers + primary-ctor params + argument-free attributes,
    with WHOLE-FILE equality on 3 public-positional-record files. TRANCHE 5 LANDED (this turn): the RICHER
    TypeReference node family (generic / qualified-dotted / array / nullable / tuple / Func / union / byref) in
    field + parameter types — each byte-exact to Parser.cs and verified owner==live-Parser.cs whole-tree; richer
    field/param types no longer decline (the `hasTypeParams`/`hasBaseList` decls-level gates + the default/attr/
    property-modifier gates are RETAINED); +3 whole-file real-corpus equalities on richer-typed pure-data records.
    See the THIS-TURN Active sub-slice for the construction-site inventory + evidence.
  - TRANCHE 6+ (next): thread type-parameter lists + base/interface lists on the declaration nodes (relaxing
    `hasTypeParams`/`hasBaseList`); functions/properties/methods/constructors (blocked on statement/expression body
    materialization); union/soa/type-alias bodies; then the statement + expression + pattern families — extending
    the same `AstEq` harness per family. Proceed until a whole valid-or-malformed file parses into
    (CompilationUnit, Errors) provably equal to Parser.cs.
- N+2 (CUTOVER, IDE-AFFECTING): at full AST + diagnostic parity, route every consumer (MultiFileCompiler.ParseAllFiles,
  DocumentManager, Analyzer's 4 sites, Formatter, CLI format/lint, CodeIntelligence, Playground) to the N# owner. VS
  Code-enabled gate + extension reinstall + computer-use visual check. No shadow route.
- N+3 (DELETION): delete Parser.cs's per-family parse/recovery/report decisions as each consumer cuts over; end when
  Parser.cs is deleted or a reviewed zero-policy mechanical host (`compiler-core` ratchet row retires).

## Iterative-task targets

These are populated only when their task becomes current.

- Task 015 next emitter sub-slice: NONE — movable-decision surface exhausted (see the 015 completion
  roadmap above); gated on the plan-row lambda-body emitter, N# preflight/typing-owner port, async-func
  lowering, and incremental planner OPERAND unlocks.
- Task 016 next parser sub-slice: **NONE — `Parser.cs` IS DELETED and the task's completion criterion is met.**
  The whole arc (Stages 0-17 capability → N+1a/b/c bridge → N+2 cutover → N+3 deletion) is done: the N# owner
  `ColumnarParserRecovery` is the sole parse + ordered-diagnostic authority for production and for every test,
  and 7,130 lines of C# parser policy (`Parser.cs` 7,116 + the `ParseResult` record 14) are gone with zero
  replacement C#. ONE OPTIONAL FOLLOW-ON remains, and it is BOOKKEEPING, not ownership: the 2,021 parser
  assertions (356 facts) in `ParserTests.cs` / `ParserErrorTests.cs` / `ErrorHandlingTests.cs` /
  `EventSubscriptionTests.cs` / `LocalFunctionTests.cs` are still expressed in C# xunit even though every one
  of them now executes against the N# owner. Translating them into native `.tests.nl` contracts would move the
  last parser TEST text to N#; it deletes no C# policy, unlocks nothing, and must not be done as a bulk
  DELETION (that would drop 356 facts of executable synthetic-surface coverage the native corpus does not
  otherwise reach). Sequence it behind the remaining `final-compiler-tasks/` owners.
  (HISTORICAL) STAGE N+1c (materialize the full node tree in the owner). N+1b (the AST-hierarchy
  migration — the whole AstNode hierarchy moved from C# records to N# classes in BootstrapServices, the C# `Ast/`
  directory DELETED, the Except site made reference-based) LANDED this turn with the full production-touching bar green
  (unit 3190/3190, contracts 1202/1202, ownership 18/18, an EMPTY byte-exact corpus IL diff over 159 assemblies). N+1c:
  extend the owner's recovery grammar (already at full diagnostic parity) to MATERIALIZE the full node tree
  (declarations/statements/expressions) it currently parses for diagnostics only, returning a real `CompilationUnit`, and
  prove node-by-node structural equality against Parser.cs on the parity corpus (comparison in `.tests.nl` only). Then
  N+2 (CUTOVER, IDE-affecting) and N+3 (Parser.cs deletion), per the "## 016 AST/facts bridge (N+1) design record". The
  historical STAGE-14 pointer below is retained for reference only.
  (HISTORICAL) STAGE 14 of the parser-front-end arc (see the "Staged parser-front-end
  ARC PLAN" + the Stage-13 RESIDUAL-TO-PARITY MAP in the Active sub-slice above). STAGES 1-13 have LANDED
  (recovery model + import/namespace/package; declaration-NAME; malformed-literal; member/parameter/field;
  generics/constraints; statements; expressions; match/patterns; CLOSING-DELIMITER recovery; POSTFIX
  call/index/generic-call/`with` + call-argument family + the new / cast / tuple / typeof / nameof / sizeof /
  checked / unchecked / array primary tranche; is/as + alloc/stackalloc/lambda; the interpolated-string `$"…"`
  hole grammar; and the REMAINING STATEMENT kinds [yield/break/continue/throw/try-catch-finally/using/lock/switch/
  allow/alloc-block/unsafe/assert/preprocessor/local-function/await-foreach/off/on + C-style for + tuple
  deconstruction + typed declarations] — 316 native contracts). STAGE 14 = the MEMBER grammars (method /
  constructor / nested-type / record-positional / union-case / interface / property) + the record / interface /
  union / enum / soa type BODIES (residual map item [2]). Still kernel-capability-only (no production wiring, no
  IDE gate). Do NOT resurrect the deleted `ColumnarSyntaxDiagnostics` scanner.
  (HISTORICAL, for reference — the Stage 1-8 pointer this replaced): STAGE 1 (recovery model + import/namespace/package), STAGE 2 (declaration-NAME family),
  STAGE 3 (MALFORMED-LITERAL family), STAGE 4 (MEMBER / PARAMETER / FIELD declaration family), STAGE 5
  (GENERICS / CONSTRAINTS family), STAGE 6 (STATEMENT family — block-body grammar +
  `SynchronizeToNextStatement` sync point + per-statement panic reset + `_currentRecoveryBoundaryColumn`, the
  dangling-operator through-token span, missing-initializer `:=`/`=`, missing if/while condition, missing
  for/foreach `in`, missing-statement-body; proven byte-exact incl. `Parser_DanglingBinaryOperator_...`'s exact
  span/message and the statement-boundary reset + within-statement cascade shapes), and STAGE 7 (EXPRESSIONS,
  recut A — the fuller precedence ladder [ternary / coalescing / logical / bitwise / equality / relational /
  shift / range / unary / postfix-member] replacing Stage-6's shallow subset, carrying the expression ERROR
  families STAGE 3/6 kept panic-suppressed: unexpected-token-in-expression, prefix `+` [NL103 InvalidSyntax],
  leading `.`, ternary missing-then/`:`/else, dangling operators per-tier, await/must/throw missing-operand, and
  member-name-after-dot; proven byte-exact incl. the initializer-terminator-then-reset and prefix-plus-cascade
  panic shapes; +35 contracts) have LANDED. STAGE 8 = the DEFERRED MATCH / PATTERN family through the SAME
  shared-panic model: `ParseMatchExpression` (:5368, the `Consume(LeftBrace/Arrow/Comma/RightBrace)` + `ParsePattern`
  scaffolding) and the pattern parsers `ParsePattern`/`ParseOrPattern`/…/`ParsePrimaryPattern` (:3263-:3457, the
  terminal "Invalid pattern. Got 'X'" [NL103] + list `Consume(RightBracket)` / positional `Consume(RightParen)` /
  qualified-name `ConsumeIdentifier` sites) + `ParsePropertyPatterns` (:3459). NOTE: match/pattern shapes lean on
  closing-delimiter `Consume` sites (`{`/`}`/`)`/`]`), so STAGE 8 may fold in or immediately precede the
  closing-delimiter stage. Also DEFERRED from STAGE 7 (recorded): the `is`/`as` relational operators (type
  sub-grammar); postfix CALL `(…)` / INDEX `[…]` / generic-call / `with {…}` (the call-argument + closing-delimiter
  families); the keyword-led primaries (new / alloc / match / cast / tuple / typeof / array / interpolation / lambda /
  …); and the four INVALID-OPERATOR default arms (assignment/relational/multiplicative/unary) — UNREACHABLE dead
  defaults (exact-match-fact guards admit only tokens the switch handles), never fired, not corpus-modellable. Still
  kernel-capability-only (no production wiring, no IDE gate). Stays self-contained (BootstrapServices `.nl` +
  `.tests.nl`, no repin) unless the stage needs a kernel entry point dependents compile against — call out the
  two-stage bootstrap wall at stage start. Do NOT resurrect the deleted `ColumnarSyntaxDiagnostics` scanner
  (divergent per-token panic model). NOTES for later stages:
  (a2) STAGE 7's statement-expression path is now the fuller ladder; the Stage-3 `=>` expression-body and Stage-4
  field-`:=` init still use the minimal `ParseLiteralBearingExpression` vehicle (validated byte-exact for their
  corpora) — unifying them onto the full ladder is a later mechanical cleanup, not a diagnostic change.
  (a1) STAGE 6 carries the statement family via the block-body vehicle; DEFERRED (with reasons): the C-style
  `for init; cond; iter` loop, tuple deconstruction, typed `name: T = value` declarations, the remaining
  statement kinds (yield / break / continue / throw / try / using / lock / switch / allow / alloc / unsafe /
  assert / preprocessor / local-function / await-foreach / off — each adds its own ReportError sites under the
  same shared-panic model), the full expression ladder + expression ERROR families (STAGE 7), and the block's own
  missing-`}` (NL106) report + `IsBlockClosingDeclarationStart` break (reproduced-but-not-corpus-exercised;
  retire with the closing-delimiter stage). The STAGE-6 expression subset is assignment over additive/
  multiplicative over identifier/literal/bool/null/parenthesized primaries — a vehicle that reproduces only the
  dangling-operator through-token span byte-exact; the corpus keeps its statement expressions within that subset.
  (a0) STAGE 5 carries the generics/constraints family via the FUNCTION head + class type-params; DEFERRED
  (with reasons): the EOF-anchored `ConsumeGreater` (the check pipeline clamps JSON length 0→1; unmatchable at
  the CompilerError level), the `new(` missing-`)` (NL107 via `TryReportMissingClosingDelimiter` — the
  closing-delimiter stage), class/interface/union/record/soa/method type-params + soa's "not supported yet"
  special diagnostic, and class-body `where` (classes do NOT take `where` — `class C<T> where …` cascades).
  (a) STAGE 4 parses FIELD members only and retires the braced-kind found-other ONLY for the `{`-offender; the
  non-`{` found-other (`class 5`), non-identifier parameter name (`func f(5)`), trailing-comma, and the
  method/nested/constructor/record-positional/union-case member grammars remain deferred (garbage-type cascade
  + position-sorted emit order — need `ParseTypeReference`-on-garbage + `SynchronizeToNextStatement`), retiring
  with the expression/statement + closing-delimiter stages. (b) STAGE 3's MINIMAL literal-reaching
  expression path (paren + literal primary + flat binary-operator continuation) is a vehicle, NOT the full
  expression grammar — the expressions/patterns and closing-delimiter stages OWN the expression/statement
  ERROR families (unexpected-token-in-expression, dangling operator, missing `)`/`]`/`}`); STAGE 3/4 corpus
  shapes deliberately keep those would-be errors panic-suppressed so their output is byte-exact without them.
- Task 017 next semantic sub-slice: **SLICE 8 — STAGE 2 OF THE `ResolveType` ARC: THE SCOPE STACK**
  (`Scope` is already N# in `AnalyzerStateModels.nl`; the slice is the `Stack<Scope>` field and its 51
  sites). Slices 1-7 are DONE — `Analyzer.cs` is **22,050**. The historical note below is kept because
  it records what slice 3 established; the live sequencing is in the THIS-TURN Active sub-slice.
  (Historical, written at slice 4's start:) Slices 1, 2 and 3
  are DONE — full records in the 017 Active sub-slice blocks above; `Analyzer.cs` is **22,622**, the
  twelve pure classification predicates and the whole well-known-type surface it carried are gone,
  and the N# side now HOLDS the `_wellKnownTypes` state (`AnalyzerWellKnownTypes`).
  WHAT SLICE 3 ESTABLISHED, and why the next cut is what it is: the two funnels
  (`ResolveTypeAlias` :20075-era, `TryConvertTypeInfoToClrType` :9964-era) are the last gateway, and
  `TryConvertTypeInfoToClrType`'s ONLY remaining instance-state read after slice 3 is the alias
  funnel itself — `_wellKnownTypes` is now an N#-owned object it can be handed. So the pair reduces
  to ONE blocker: `ResolveTypeAlias`'s `AliasTypeInfo` arm, whose live branch is
  `ResolveType(alias.AliasedType)` — the full C# TypeReference engine (`_semanticModel`, `_errors`,
  `_reportUnresolvedTypes`, the scope stack, the MLC). MEASURED, not assumed: instrumented counters
  over six corpus projects and a four-alias fixture gave aliasSeen=36, declaration-context
  branch=**0**, `ResolveType` branch=**36**. The cause is identity, not policy — `Analyzer.cs`
  :369 declares an alias as `new AliasTypeInfo(aliasDecl.Type)`, a FRESH instance, while
  `AnalyzerDeclarationContext.filesByType` is keyed by TypeInfo REFERENCE identity over the
  instances IT built, so `ContainsSourceType` is false for every alias the analyzer's own scope
  hands back.
  SLICE-4 TARGET, in order:
  (a) Make `DeclareType` register the alias TypeInfo the DECLARATION CONTEXT built (or register the
      analyzer's instance into the context) so `ContainsSourceType(alias)` is true for source
      aliases. This is a small, provable change with an obvious differential: the alias branch
      counter must flip from 0/36 to 36/0 with `nlc check --json` byte-identical corpus-wide. Note
      `TryResolveTypeForOwner` returns false on exactly the same `filesByType` miss that
      `ContainsSourceType` reports, so once identity is unified branch (1) is TOTAL and the
      `ResolveTypeWithSubstitution` fallback inside `ResolveTypeForSourceOwner` is unreachable from
      this path — verify that with a counter before relying on it.
      IF THAT IS NOT ACHIEVABLE without changing diagnostics, the alternative is to move
      `ResolveType(TypeReference)` + `ResolveSimpleType` + `ResolveGenericType` and their
      diagnostics into N# as its own multi-slice arc; recut and record if so.
  (b) With the alias arm N#-reachable, move `ResolveTypeAlias` (cycle set, oblivious unwrap,
      recursion) onto `AnalyzerDeclarationContext` or a sibling owner, and route all **143** call
      sites.
  (c) Then `TryConvertTypeInfoToClrType` + `TryConvertTypeInfoToClrTypeForBinding` (**30** and
      **11** call sites) and their four remaining construction helpers
      (`TryConvertNullableType`, `TryConstructRuntimeUnionType`, `TryConstructKnownGenericType`,
      `TryConstructDelegateType`), which at that point read only N#-owned state.
  (d) Only then `IsAssignable` :19294-era and its closure.
  Prove each the way slices 1-3 did: throwaway reflection differential over an exhaustive value
  grid, the before/after end-to-end funnel transcript, then the oracle + IL sweeps.
  SECONDARY, small and independent, STILL OPEN: the ONE surviving C# duplicate this arc has found —
  `CompletionEngine.cs` :751's private static `GetFunctionParameterModifier` (a completion-LABEL
  helper with an extra `index < 0` guard, deliberately left out of slice 2 because folding it in
  would have moved a second ratchet row). Route it to `AnalyzerCallableReferenceFacts` after
  reconciling the guard, and repin the `CompletionEngine.cs` row.
  ARCHITECTURAL PREREQUISITE FOR THE ARC'S REAL TARGET, restated with slice 3's measurement:
  `IsAssignable` and with it `IsSubtypeOf`, `IsCollectionType`, `HasImplicitConversion`,
  `ImplementsDuckInterface`, `IsKnownGenericTypeAssignable`, `IsArrayToSpanAssignable`,
  `IsAspNetActionResultGenericAssignable`, `IsFunctionTypeAssignable`, `IsLambdaAssignableToDelegate`,
  `TryGetDelegateSignatureConversionScore`, `MayUseDelegateReferenceConversion` and
  `IsReferenceLikeForVariance` are NOT movable while `ResolveTypeAlias` stays in C#. Every one of
  them either calls a funnel directly or recurses into `IsAssignable`, which does. There is no
  remaining "pure leaf predicate" cut in that neighbourhood — slice 2 took the last of them, and
  slice 3 confirmed it by inventory.
- Task 018 next systems-policy sub-slice: not selected
- Task 019 next tooling sub-slice: not selected
- Task 020 next native-runner sub-slice: not selected

## Completion ledger

Completed slices:

- Task 017 — THIRD slice: the WELL-KNOWN-TYPE OWNER moves to N# — the `_wellKnownTypes` STATE
  itself, not just policy over it. **4 C# units / 271 lines deleted from `Analyzer.cs`
  (22,873 → 22,622), 20 lines inserted and every one of them mechanical routing**: the nested
  `internal sealed class WellKnownTypes` (173 lines — the MLC fact bag, the two-probe resolve, the
  required-type throws, the four assembly probes and the lazy `RuntimeUnionOpen`/`RuntimeResultOpen`
  pair), `TryGetKnownOpenGenericType`, `TryConvertBuiltInTypeInfoToRuntimeClrType`, and the inline
  binding-surrogate open-generic table inside `TryConvertTypeInfoToClrTypeForBinding` → the new N#
  owners `AnalyzerWellKnownTypes` (225 lines, 52 members) and `AnalyzerWellKnownTypeFacts` (212
  lines, 5 members) + 10 contracts. All 7 routing sites are in-class; nothing external referenced
  any of it; nothing calls back. THIS IS A RECUT, and the recut is the slice's other product: the
  recorded target (absorb `ResolveTypeAlias` + `TryConvertTypeInfoToClrType`) was REFUTED BY
  MEASUREMENT — an instrumented Debug CLI over six corpus projects and a four-alias fixture shows the
  alias funnel's declaration-context branch fires **0** times and its `ResolveType`-engine branch
  **36**, because `Analyzer.cs` :369 builds a FRESH `AliasTypeInfo` per alias while the N#
  declaration context keys its catalog by TypeInfo reference identity. Taking the funnels therefore
  needs either that identity unified or the whole TypeReference engine moved — recorded as slice 4,
  which is now a much smaller cut because `_wellKnownTypes` is the state this slice removed from the
  problem. Three recorded non-mechanical decisions: the core assembly is a constructor ARGUMENT
  (`get_CoreAssembly` is off the columnar binding surface and adding it would trip the bootstrap
  wall), the lazy accessors become METHODS (no block-bodied properties in `.nl`), and the two
  open-generic tables stay SEPARATE because the surrogate vocabulary is a strict subset and merging
  would silently widen it. PROOF: an exhaustive throwaway reflection differential against the C#
  originals on a really-loaded analyzer — **692 cells, 0 mismatches** across 5 facts, comparing by
  value OR thrown exception type (which pinned the originals' `TypeLoadException` on `void[]`) —
  plus a **byte-identical 146-shape / 292-cell end-to-end transcript of both CLR-conversion funnels
  taken BEFORE and AFTER the deletion**, `nlc check --json` **byte-identical on 40/40 project
  targets** and 5 purpose-built fixtures firing 37 resolution-sensitive diagnostics (16 × NL202
  naming the compiler-known generics), and a corpus IL sweep of **64/64 comparable assemblies
  BYTE-IDENTICAL (PRODUCT_IL_DIFFS = 0)** with the 7 non-building native targets proven to fail
  identically. Suite 3,193/3,193 (zero drift), contracts 1,571 → 1,581, ownership audit 18/18 after
  a one-row net-negative repin that preserved the manifest's compact 391-line format. New .nl
  gotchas: `MetadataLoadContext.CoreAssembly`, `typeof(void)` and `typeof(Nullable<>)` are all off
  the columnar surface (routed around, not extended); typed `catch ex: T` clauses DO work. No wall.
  Full detail in the 017 Active sub-slice.
- Task 017 — SECOND slice: the CALLABLE / DELEGATE-REFERENCE CLASSIFICATION FAMILY moves to the new
  N# owner `AnalyzerCallableReferenceFacts` (plus one span-name conversion gate to
  `AnalyzerConversionFacts`). **8 C# methods / 66 lines deleted from `Analyzer.cs`
  (22,938 → 22,873), 0 C# lines added**: `IsCallableReferenceType`, `IsMethodGroupReferenceType`,
  `HasSourceFunctionIdentity`, `IsRuntimeDelegateType`, `GetFunctionParameterModifier`,
  `NormalizeDelegateParameterModifier`, `TryCreateFunctionTypeInfoFromGenericDelegate` and
  `IsSpanTypeName`. All 21 call sites — every one in-class; the predicates had no external caller —
  route directly to the owners; nothing calls back. N# added: `AnalyzerCallableReferenceFacts.nl`
  (148 lines, 7 members) + 9 contracts, and +9 lines / +1 contract on the conversion owner. Two
  recorded non-mechanical decisions: the span-name gate is filed with the CONVERSION family because
  its only consumer is an implicit conversion, and the `out`-parameter Try-pattern becomes a nullable
  return read with `is { }`, preserving the `&&` short-circuit. PROOF: an exhaustive throwaway
  reflection differential against the C# originals — **271 cells, 0 mismatches**, including **9 types
  loaded into a real MetadataLoadContext** to pin the runtime-versus-load-context asymmetry the
  reimplementation depends on — plus `nlc check --json` **byte-identical on 40/40 project targets**
  and 4 purpose-built fixtures firing this family's own diagnostics (15 diagnostics incl. 4 NL411
  MethodGroupUsedAsValue), and a corpus IL sweep of **64/64 comparable assemblies BYTE-IDENTICAL
  (PRODUCT_IL_DIFFS = 0)** with the 7 non-building native targets proven to fail identically. Suite
  3,193/3,193 (zero drift), contracts 1,561 → 1,571, ownership audit 18/18 after a one-row
  net-negative repin that preserved the manifest's compact 391-line format. New .nl gotcha:
  `typeof(Delegate)`/`typeof(MulticastDelegate)` do not resolve (the columnar `typeof` surface is a
  hardcoded well-known list; extending it is a kernel change), resolved with the
  `typeof(object).get_Assembly()` idiom rather than tripping the wall. No wall. Full detail in the
  017 Active sub-slice.
- Task 017 — FIRST slice (the semantic-analyzer arc opens): the CONVERSION/ASSIGNABILITY
  CLASSIFICATION TABLES move to the new N# owner `AnalyzerConversionFacts`. **7 C# methods /
  122 lines deleted from `Analyzer.cs` (23,060 → 22,938), 0 C# lines added**: both
  `IsImplicitNumericConversion` overloads (the CLR implicit-numeric-widening table, written twice
  in two vocabularies), `GetNumericTypeFullName`, `IsReferenceType`, `IsReflectionAssignableFrom`,
  `GetInterfacesSafe` and `GetBaseTypeSafe`. All 26 call sites — every one in-class; the predicates
  had no external caller — route directly to the owner; nothing calls back. N# added:
  `AnalyzerConversionFacts.nl` (254 lines, 9 members) + 7 native contracts. The widening relation is
  now stated ONCE over a `NumericConversionKind` and reached through two disjoint name maps, with the
  cross-vocabulary disjointness pinned by negative contracts. PROOF: an exhaustive throwaway
  reflection differential against the C# originals — **2,400 cells, 0 mismatches** (23×23 source-name
  grid, 30×30 CLR grid, 30×30 reflection-assignability grid, 71 `TypeInfo` values) — plus
  `nlc check --json` **byte-identical on 40/40 project targets** and 3 conversion-error fixtures, and
  a corpus IL sweep of **64/64 comparable assemblies BYTE-IDENTICAL (PRODUCT_IL_DIFFS = 0)** with the
  7 non-building native targets proven to fail identically. Suite 3,193/3,193 (zero drift), contracts
  1,554 → 1,561, ownership audit 18/18 after a one-row net-negative repin. No wall. Full detail in
  the 017 Active sub-slice.
- Task 016 — **TERMINAL slice (STAGE N+3): `Parser.cs` DELETED. The parser-ownership arc is COMPLETE and the
  task's checkbox criterion ("Parser.cs is deleted or a reviewed zero-policy mechanical host") is MET by the
  stronger arm — the file is gone, not reduced to a host.** `src/NSharpLang.Compiler/Parser.cs` (−7,116) and
  `src/NSharpLang.Compiler/ErrorReporting.cs` (−14, the `ParseResult` record it solely produced) are deleted;
  **7,130 C# lines out, 0 C# lines in.** All 53 parse sites across 20 C# test files route to
  `ColumnarParserRecovery.ParseFileAst`; `FileParseAst` gained the one member `ParseResult` had that it did
  not (`Success`), pinned by 4 native contracts. Suite 3,193/3,193 (unchanged — no test deleted, no assertion
  rewritten), contracts 1,554/1,554, ownership audit 18/18, corpus IL sweep 78/78 byte-identical
  (PRODUCT_IL_DIFFS=0), dev.sh `--since`, and the FULL VS Code-enabled `./scripts/test-all.sh --commit` with
  the extension rebuilt + reinstalled. Ratchet: two `removed` rows (epochs preserved) + 20 net-negative test
  repins + `reviewedHeadFingerprint` mirrored into `OwnershipAudit.nl`. No wall. Full detail in the
  THIS-TURN Active sub-slice.
- Task 016 — EIGHTH slice (parser-front-end arc STAGE 7): the EXPRESSIONS diagnostic family (recut A — the
  fuller precedence ladder over Stage-6's shallow assignment/additive/multiplicative subset, carrying the
  expression ERROR families Stages 3/6 kept panic-suppressed: unexpected-token-in-expression [NL101], prefix `+`
  [NL103], leading `.` [NL102], the ternary missing-then / missing-`:` / missing-else sites, dangling binary
  operators across every ladder tier [NL102], await/must/throw missing-operand [NL102], and member-name-after-dot
  [NL102 + the reserved-keyword member NL109]), in N#, PROVEN byte-exact against the freshly built Release CLI
  oracle. NOT committed (mandate: do not commit); working tree carries the two edited N# files + STATUS. NO
  production wiring — Parser.cs remains the sole production syntax authority.
  - Site inventory (grep of ParseExpression + the ladder + ParsePrimaryExpression in Parser.cs): the LADDER
    `ParseAssignmentExpression` (:3690) → `ParseTernaryExpression` (:4009) → `ParseNullCoalescingExpression` (:4033)
    → `ParseLogicalOr/AndExpression` (:4047/:4061) → `ParseBitwiseOr/Xor/AndExpression` (:4075/:4089/:4103) →
    `ParseEqualityExpression` (:4117) → `ParseRelationalExpression` (:4132) → `ParseShiftExpression` (:4205) →
    `ParseAdditiveExpression` (:4220) → `ParseMultiplicativeExpression` (:4235) → `ParseRangeExpression` (:4280) →
    `ParseUnaryExpression` (:4316) → `ParsePostfixExpression` (:4405) → `ParsePrimaryExpression` (:4626); the
    unexpected-token terminal (:4813) + `ShouldSkipUnexpectedExpressionToken` (:6943); `ParseInvalidPrefixPlusExpression`
    (:3816); `ParseLeadingMemberAccessWithoutReceiver` (:6407); the ternary sites (:4016/:4021/:4022);
    `ParseBinaryRightOperandOrMissing`/`ParseRightOperandOrMissing` (:3778/:3750); `ParseUnaryOperandOrMissing` (:3789);
    `ReportMissingMemberNameAfterDot` (:6385) + the reserved-keyword member (:4433).
  - Deliverables: `ColumnarParserRecovery.nl` 2,334 → 2,822 lines (+488: the full ladder tiers +
    `BinaryRightOperandMissing`/`RightOperandMissingWithSpan` + `ParseUnary`/`ParsePostfix`/`ParseMemberAccess` +
    `ParseInvalidPrefixPlusExpression` + `ParseUnaryOperandOrMissing` + `ReportMissingMemberNameAfterDot` +
    `ParseLeadingMemberAccessWithoutReceiver` + `ShouldSkipUnexpectedExpressionToken` + the rewritten full
    `ParsePrimaryExprValue`; the removed Stage-6 `ParseBinaryRightOperandOrMissing`/`ParseRightOperandOrMissing`
    replaced by the boolean operand-missing helpers, since N# has no first-class `Func<Expression>`). +35 native
    parity contracts in `ColumnarParserRecovery.tests.nl` (1,842 → 2,279 lines).
  - Parity + evidence: BootstrapServices contracts 910/910 (875 baseline + 35); dev.sh Parser 381/381; ownership
    audit 18/18 (all deltas `.nl`, no ratchet movement); git status shows ONLY the two `.nl` files + STATUS. NO
    wall (self-contained; packaged SDK 0.1.0 self-emitted the edited owner + all 910 contracts cleanly — no repin).
    Full suite / corpus sweeps N/A (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's
    own `.tests.nl`, verified by grep across src+tests+editors); no LSP change → no reload. Next: STAGE 8 =
    match/patterns (deferred), then closing-delimiter recovery.
- Task 016 — SEVENTH slice (parser-front-end arc STAGE 6): the STATEMENT diagnostic family (the block-body
  statement grammar Stages 3-5 left unparsed, the `SynchronizeToNextStatement` sync point + per-statement panic
  reset + `_currentRecoveryBoundaryColumn` tracking, the dangling-binary/assignment-operator through-token span,
  the missing-initializer `:=`/`=` forms, the missing if/while condition, the missing for/foreach `in`, and the
  missing-statement-body report), in N#, PROVEN byte-exact against the freshly built Release CLI oracle. NOT
  committed (mandate: do not commit); working tree carries the two edited N# files + STATUS. NO production wiring —
  Parser.cs remains the sole production syntax authority.
  - Site inventory (grep of ParseStatement + helpers in Parser.cs): the SYNC POINT + BOUNDARY RESET via `ParseBlock`
    (:2143 — panic reset :2172, `_currentRecoveryBoundaryColumn` :2177, `SynchronizeToNextStatement` :2188 → :7084);
    the DANGLING OPERATOR via `ParseRightOperandOrMissing` (:3750) / `ParseBinaryRightOperandOrMissing` (:3778) +
    `DiagnosticSpanFromExpressionThroughToken` (:3842) + `IsMissingOperandBoundary` (:6908); the MISSING-INITIALIZER
    / MISSING-CONDITION via `ParseRequiredExpressionAfter` (:3855) + `IsMissingRequiredExpressionBoundary` (:3928) +
    `LooksLikeStatementStartAfterRequiredExpression` (:3946) + `ShouldUnderlineAnchorForMissingRequiredExpression`
    (:3887) + `DiagnosticSpanFromExpression` (:5917); the MISSING-`in` via `ReportMissingInKeywordAndRecover` (:3908);
    the MISSING-STATEMENT-BODY via `IsMissingStatementBodyBoundary` (:3961) / `ReportMissingStatementBody` (:3968);
    the statement dispatch `ParseStatement` (:2219) and the block-body branch of the function head (:498).
  - Deliverables: `ColumnarParserRecovery.nl` 1,648 → 2,334 lines (+686: the `ExprResult` carrier +
    `RecoveryBoundaryColumn`/`HasRecoveryBoundaryColumn` state; `ParseBlockBody`, `ReportMissingClosingBrace`,
    `SynchronizeToNextStatement`, `ParseStatement`, `IsMissingStatementBodyBoundary`, `ReportMissingStatementBody`,
    `ParseVariableDeclaration`, `ParseIfStatement`, `ParseWhileStatement`, `ParseForStatement`,
    `ParseForeachStatement`, `ConsumeForeachInKeyword`, `ReportMissingInKeywordAndRecover`, `ParseReturnStatement`,
    `ParsePrintStatement`, `ParseExpressionStatement`, `ParseExprValue`, `ParseAdditive`, `ParseMultiplicative`,
    `ParseBinaryRightOperandOrMissing`, `ParseRightOperandOrMissing`, `ReportExpectedExpressionAfter`,
    `DiagnosticSpanFromExpressionThroughToken`, `ParsePrimaryExprValue`, `ParseRequiredExpressionAfter`,
    `ShouldUnderlineAnchorForMissingRequiredExpression`, `IsMissingRequiredExpressionBoundary`,
    `LooksLikeStatementStartAfterRequiredExpression`, `StartsTupleDeconstructionAtCurrentPosition`,
    `IsMissingOperandBoundary`, `IntToString`; `ParseFunctionName` / `ParseFunctionHeadAndBody` extended for the
    block body). +25 native parity contracts in `ColumnarParserRecovery.tests.nl` (1,485 → 1,842 lines).
  - Parity + evidence: BootstrapServices contracts 875/875 (850 baseline + 25); dev.sh Parser 381/381; ownership
    audit 18/18; git status shows ONLY the two `.nl` files + STATUS. NO wall (self-contained; packaged SDK 0.1.0
    self-emitted the edited owner + all 875 contracts cleanly — no repin). Full suite / corpus sweeps N/A
    (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's own `.tests.nl`, verified by
    grep across src+tests+editors); no LSP change → no reload. Next: STAGE 7 = expressions/patterns.
- Task 016 — SIXTH slice (parser-front-end arc STAGE 5): the GENERICS / CONSTRAINTS diagnostic family
  (`ReportMissingTypeParameterName` / `ReportMissingGenericTypeArgument` NL102, the reserved-keyword NL109
  type-param name, the `ConsumeGreater` split-`>>` discipline + its NL102 unclosed-list error, and the
  `where`-clause NL102/NL109 name/colon errors + the class/struct and struct/new() NL103 `InvalidSyntax`
  validations), in N#, PROVEN byte-exact against the freshly built Release CLI oracle. NOT committed (mandate:
  do not commit); working tree carries the two edited N# files + STATUS. NO production wiring — Parser.cs remains
  the sole production syntax authority.
  - Site inventory (grep of Parser.cs): TYPE PARAMS via `ParseTypeParameters` (:725) → `ConsumeIdentifier` (:743)
    + `ReportMissingTypeParameterName` (:6439) + the closing `Consume(Greater)` (:747); GENERIC ARGS via the
    generic type-reference (:1925-1957) → `ReportMissingGenericTypeArgument` (:6457); the `ConsumeGreater`
    split-`>>` (:2101, `_splitGreaterDepth` + split-aware Check :6025 / Advance :5860, reset :7042/:7086);
    `where` constraints via `ParseGenericConstraints` (:851) → `ConsumeIdentifier` (:861) / `Consume(Colon)`
    (:862) / the class-struct (:901) + struct-new (:915) `InvalidSyntax` validations with
    `LaterToken`/`TokenLengthOrFallback`/`TokenSpanLengthOrFallback` (:6010/:5897/:5900).
  - Deliverables: `ColumnarParserRecovery.nl` 1,252 → 1,648 lines (+396: split-aware Check/Advance +
    SplitGreaterDepth; `ParseTypeParameters`, `ReportMissingTypeParameterName`, `ParseTypeReferenceRecovery`,
    `ReportMissingGenericTypeArgument`, `ConsumeGreater`, `ConsumeToken`, `GetHintForMissingToken` /
    `HintForMissingTokenOrDefault`, `ParseGenericConstraints`, `ReportClassStructConflict`,
    `ReportStructNewRedundancy`, `LaterToken`, `TokenLengthOrFallback`, `TokenSpanLengthOrFallback`,
    `DiagnosticSpanFromTokenRange`; `ParseFunctionHeadAndBody` / `ParseClassName` / `ParseStructName` extended).
    +22 native parity contracts in `ColumnarParserRecovery.tests.nl` (1,144 → 1,484 lines).
  - Parity + evidence: BootstrapServices contracts 850/850 (828 baseline + 22); dev.sh Parser 381/381; ownership
    audit 18/18; git status shows ONLY the two `.nl` files + STATUS. NO wall (self-contained; packaged SDK 0.1.0
    self-emitted the edited owner + all 850 contracts cleanly — no repin). Full suite / corpus sweeps N/A
    (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's own `.tests.nl`, verified by
    grep across src+tests+editors); no LSP change → no reload. Next: STAGE 6 = statements.
- Task 016 — FIFTH slice (parser-front-end arc STAGE 4): the MEMBER / PARAMETER / FIELD declaration
  diagnostic family (the `:`/`:=` colon and type-annotation errors, NL102 `ExpectedToken` / NL109
  `ReservedKeywordAsName`), in N#, PROVEN byte-exact against the freshly built Release CLI oracle. NOT committed
  (mandate: do not commit); working tree carries the two edited N# files + STATUS. NO production wiring —
  Parser.cs remains the sole production syntax authority.
  - Site inventory (grep of Parser.cs): PARAMETERS via `ParseParameterList` (:751) → `ConsumeIdentifier`(msg,
    span?) (:6720) + `GetMissingParameterNameDiagnosticSpan` (:6476), `ConsumeParameterColon` (:6625),
    `ParseParameterTypeReference` (:6504); FIELDS via `ParseFieldDeclaration` (:1637) → no-span `ConsumeIdentifier`
    (:1666), `ConsumeFieldColon` (:6651), `ParseFieldTypeReference` (:6536) + `LooksLikeNextFieldAfterMissingType`
    (:6572); the MEMBER-BOUNDARY panic reset in `ParseMemberList` (:1365); and the Stage-2-deferred braced-kind
    found-other NAME (`ConsumeDeclarationName` reached with a `{` offender, retired for `class {` / `struct {`).
  - Deliverables: `ColumnarParserRecovery.nl` +~350 lines (`ParseParameterListRecovery`, `ConsumeNameWithSpan`,
    `GetMissingParameterNameDiagnosticSpan`, `ConsumeParameterColon`, `ParseParameterTypeReference`,
    `ParseTypeBodyIfPresent`, `ParseMemberList`, `ParseFieldMember`, `ConsumeFieldColon`,
    `ParseFieldTypeReference`, `LooksLikeNextFieldAfterMissingType`, `ParseSimpleTypeReference`, `TypeErrorAnchor`,
    `IsVisibleName`, `IsTypeTerminator`, `SingleSuggestion`, `FieldColonSuggestions`; `ParseFunctionHeadAndBody` /
    `ParseClassName` / `ParseStructName` extended). +17 native parity contracts in `ColumnarParserRecovery.tests.nl`.
  - Parity + evidence: BootstrapServices contracts 828/828 (811 baseline + 17); dev.sh Parser 381/381; ownership
    audit 18/18; git status shows ONLY the two `.nl` files + STATUS. NO wall (self-contained; packaged SDK 0.1.0
    self-emitted the edited owner + all 828 contracts cleanly — no repin). Full suite / corpus sweeps N/A
    (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's own `.tests.nl`); no LSP
    change → no reload.
- Task 016 — FOURTH slice (parser-front-end arc STAGE 3): the MALFORMED-LITERAL diagnostic family (NL105
  `InvalidLiteral`), in N#, PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not commit);
  working tree carries the two edited N# files + STATUS. NO production wiring — Parser.cs remains the sole
  production syntax authority.
  - Origin inventory (grep of Parser.cs AND the N# Lexer path): all six shapes are Parser.cs-REPORTED inside
    `ParsePrimaryExpression` — `ReportMalformedCharLiteralIfNeeded` (:4646→:4905, empty/unterminated char),
    `ReportMalformedStringLiteralIfNeeded` (:4653→:4830, unterminated string + unterminated interpolated
    single-line string), and its delegate `ReportMalformedRawStringLiteralIfNeeded` (:4876, unterminated
    triple-quoted + unterminated interpolated-raw), each routed through the shared-panic `ReportError`
    (:6845). The already-N# `Lexer.nl` (`ReadString`/`ReadCharLiteral`/`ReadTripleQuoteString`/
    `ReadInterpolatedRawString`) only CLASSIFIES — it sets `Token.IsTerminated` and builds the token value —
    and emits NO diagnostic. The malformed DECISION delegates to the LIVE shared N# owner `ParserLiteralFacts`
    (`IsCompleteStringLiteral`/`IsCompleteCharLiteral`), the identical calls Parser.cs makes. VERDICT: the
    family belongs to the PARSER model (Parser.cs-reported, shared-panic-gated), NOT a separate lexer lane; it
    is carried in FULL this stage. (`import`-path and test-description strings are NOT part of it — they never
    run the malformed check; `import "abc` → NL701, verified.)
  - Extended `ColumnarParserRecovery.nl`: `ReportMalformedLiteralIfNeeded` dispatches to the three ported
    reporters (byte-exact messages / explanations / hints / suggestions / marker-lengths), all routing through
    the shared-panic `Report`; the decision reuses `ParserLiteralFacts` and construction reuses
    `ParserErrorDiagnostics.Create`. `ParseFunctionName` now continues a validly-named function through its
    head (empty params, optional return type) into the `=> <expr>` expression body via a MINIMAL
    literal-reaching expression path (`ParseLiteralBearingExpression`/`ParseLiteralBearingPrimary`:
    `( expr )` grouping + literal primaries + a flat binary-operator continuation) — enough to reach literals
    and consume the corpus's trailing tokens identically to Parser.cs's `ParseExpression`. Stage-2 name-error
    cases preserved (a `<error>` name returns before any body parse). The expression/statement ERROR families
    are NOT modeled (a later arc stage); their would-be errors never fire because they route through the same
    shared panic the literal error already set, so the output is byte-exact.
  - +14 native parity contracts in `ColumnarParserRecovery.tests.nl`: one per literal shape (string / char /
    empty char / triple / interpolated / interpolated-raw), across-boundary (two malformed funcs → 2 diags;
    malformed literal then stray top-level token → NL105 + NL101), IN-REGION suppression (`'a + 'b` and
    `'' + 'b` → 1 diag — the second malformed literal's check runs but is suppressed by shared panic; the
    parenthesized `('a` anchors the char at column 14 and suppresses the missing `)`), and negatives
    (well-formed literals report nothing). Every expected value is GOLDEN Parser.cs output captured from the
    freshly built Release CLI (`nlc check --json`, filtered NL101-NL109).
  - Evidence: BootstrapServices contracts 811/811 (797 baseline + 14; packaged SDK 0.1.0 self-emits the edited
    owner + tests cleanly, INCLUDING the `"""`-bearing message literals); dev.sh Parser 381/381; ownership
    audit 18/18 (no ratchet change — all deltas are `.nl`); git status shows ONLY the two `.nl` files + STATUS
    (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` is referenced
    ONLY by its own tests (verified across src/tests/examples), so nothing in the production compile path
    changed. No LSP/VS Code change → no extension reload. NO wall tripped (self-contained; no dependent
    compiles against a changed kernel signature). Next: STAGE 4 (member/parameter/field declaration family).

- Task 016 — THIRD slice (parser-front-end arc STAGE 2): the DECLARATION-NAME diagnostic family, in N#,
  PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not commit); working tree carries the two
  edited N# files + STATUS. NO production wiring — Parser.cs remains the sole production syntax authority.
  - Extended N# owner `ColumnarParserRecovery.nl`: `ConsumeDeclarationName(message, anchor)` (Parser.cs
    ConsumeIdentifier with a non-null diagnosticSpan, :6720) — the keyword-anchor overrides the offending-
    token span in all three variants (reserved-keyword NL109 / end-of-file NL104 / found-other NL102), so a
    missing/invalid declaration name underlines the DECLARATION KEYWORD. Added the `ParseTopLevelDeclaration`
    dispatch (ParseModifiers + the exact Parser.cs ParseDeclaration keyword order, incl. `ref struct` /
    `soa record` (contextual, LookAhead) / `duck interface` / `record struct` variants), the per-kind name
    parsers (func/class/struct/record/soa/interface/union/enum/type-alias, each anchoring on
    DiagnosticSpanFromToken(keywordToken) per Parser.cs :435/939/984/1029/1067/1143/1173/1247/1337), a
    `LookAhead` helper, and the boundary loop with the force-advance safety net (Parser.cs
    ParseCompilationUnit :83/:99-108). Removed the now-unreferenced `IsDeclarationStart`/
    `IsContextualDeclarationStart` (superseded by the dispatch). Bodies are NOT parsed (a later arc stage).
  - Site inventory (Parser.cs ConsumeIdentifier sites carried, with keyword anchor): func :435, class :939,
    struct :984, record :1029, soa record :1067, interface :1143, union :1173, enum :1247, type-alias :1337
    (the last uses `new DiagnosticSpan(line,column,Math.Max(1,"type".Length))` = SpanFromToken(typeToken)).
    All route through the shared `ConsumeDeclarationName` + `ReportReservedKeywordAsName` + `Report` model;
    the terminal unexpected-token arm reuses Parser.cs ParseDeclaration :241.
  - +24 native contracts in `ColumnarParserRecovery.tests.nl`: per-kind absent-name (EOF, 11 incl. the soa
    col-5 / duck col-6 / record-struct anchor variants), per-kind reserved-keyword-as-name (8 core kinds),
    found-other for func/enum/type (the panic-reset shape: name error then the stray token fires at the next
    boundary), and two panic-model interaction fixtures (`func 5\nenum` three-diagnostic cross-boundary;
    `class struct\nfunc class` two reserved names at two boundaries). Every expected value is GOLDEN Parser.cs
    output captured from the fresh Release CLI (`nlc check --json`, filtered to NL101-NL109).
  - Method: BootstrapServices cannot reference Parser.cs, so parity is proven against golden Parser.cs output
    captured out-of-band, same as STAGE 1. class/struct/record/interface/union found-other cases were
    DELIBERATELY EXCLUDED (their member-list body consumes the trailing junk and resets panic, diverging from
    a name-only parser — verified against the oracle, e.g. `class 5` → NL102+NL106+NL102 not NL102+NL101);
    they retire in the body/closing-delimiter stage.
  - Evidence: BootstrapServices contracts 797/797 (773 baseline + 24 new; packaged SDK 0.1.0 self-emits the
    edited owner cleanly); ownership audit 18/18 (no ratchet change — all deltas are `.nl`); git status shows
    ONLY the two `.nl` files changed (no non-N# file moved). Full unit suite / corpus IL sweeps are N/A —
    nothing in the production compile path changed (the owner is inert, referenced only by its own tests). No
    LSP/VS Code change → no extension reload. NO wall tripped (self-contained, no dependent compiles against a
    changed kernel signature). Next: STAGE 3 (malformed-literal family).

- Task 016 — SECOND slice (parser-front-end arc STAGE 1): shared-panic RECOVERY MODEL + import/namespace/
  package diagnostic family, in N#, PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not
  commit); working tree carries the two new N# files + the `ColumnarSyntaxDiagnostics` scaffolding deletion
  + STATUS. NO production wiring — Parser.cs remains the sole production syntax authority (cutover is the
  arc's last stage).
  - Added N# owner: `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` — a faithful
    reproduction of Parser.cs's `_panicMode` lifecycle (one shared flag; suppress-while-set; set-on-report;
    reset only at the declaration-boundary sync point), ordered reporting, and the `ConsumeIdentifier`
    reserved-keyword / end-of-file / found-other message variants + `LastVisibleTokenSpan` EOF anchoring,
    carrying the import/namespace/package family end-to-end (qualified-name identifier errors, dot-access
    member errors, missing import alias, duplicate-package, and the declaration-boundary terminal
    unexpected-token arm). Diagnostic construction delegates to the live shared `ParserErrorDiagnostics.Create`.
    Introduces a local `RecoverySpan` reference class instead of the C#-owned `DiagnosticSpan` value struct
    (user value-struct construction is not yet columnar-emittable), and inlines the Newline-strip compaction
    (the reference-typed `out` argument on `ParserTokenCompactor.TryCompact` is not yet columnar-emittable) —
    both faithful to Parser.cs's behavior. Plus `ColumnarParserRecovery.tests.nl` — 11 native parity
    contracts against golden Parser.cs output (captured from the fresh CLI), including the cascading-
    suppression shape (`Parser_CascadingErrorsSuppressed`) and the does-not-swallow-following shape
    (`Parser_DanglingBinaryOperator_...`).
  - Deleted N# owner: the inert divergent `ColumnarSyntaxDiagnostics` scaffolding closure
    (`ColumnarSyntaxDiagnostics.nl` + `ParserDiagnosticMessages.nl` + `ParserDiagnosticsTable.nl`, ~2,177
    lines) — superseded by the correct-model `ColumnarParserRecovery`; zero external references (verified);
    `ParserErrorDiagnostics.nl` kept (live). See the arc plan's scaffolding-fate decision.
  - Method: BootstrapServices cannot reference Parser.cs (Compiler depends on BootstrapServices, not the
    reverse), so parity is proven against GOLDEN Parser.cs output captured out-of-band via `nlc check --json`
    on the malformed corpus, filtered to parser codes NL101-NL109. Both paths construct diagnostics through
    the identical live `ParserErrorDiagnostics.Create`, and the CompilerError→DiagnosticResult mapping +
    `DiagnosticSpanResolver.Resolve` (length>0) are identity for these cases, so the golden values equal the
    owner's raw CompilerError fields.
  - Evidence: BootstrapServices contracts 773/773 (762 baseline + 11 new; unchanged by the scaffolding
    deletion — no `.tests.nl` in it); ownership audit 18/18 (no ratchet change — all deltas are `.nl`, and
    the ratchet tracks only non-N# files); dev.sh Parser 381/381 (C# build re-emits the new file + the
    deletion cleanly, Parser oracle green). NO wall tripped: the self-contained shape (new `.nl` + `.tests.nl`,
    no dependent compiling against a changed kernel signature) emits through the packaged SDK 0.1.0 with no
    repin. Full unit suite / corpus IL sweeps are N/A this stage — nothing in the production compile path
    changed (the new owner is inert, referenced only by its own tests; the deletion removed inert code). No
    LSP/VS Code change → no extension reload. Next: STAGE 2 (next diagnostic family — declaration-name or
    malformed-literal — through the same model).

- Task 016 — FIRST slice: PROVEN-BLOCKED-WITH-RECORD (no commit; mandate: do not commit; STATUS.md-only,
  working tree otherwise clean). No C#/N# production delta. The full consumer inventory, the AST-bridge
  blocker, the syntax-diagnostic blockers (`ColumnarSyntaxDiagnostics` ~8% coverage / divergent panic
  model / shared-panic coupling), and the honestly-sized prerequisite are recorded in the "016
  parser/diagnostic ownership finding" section. Evidence is code + committed-test grounded: ~256 vs ~20
  diagnostic coverage; `Parser_CascadingErrorsSuppressed` + `Parser_DanglingBinaryOperator…` pin the
  shared-panic model; `ColumnarSyntaxDiagnostics`/`ParserDiagnosticMessages`/`ParserDiagnosticsTable` have
  ZERO external references and no `.tests.nl`; `MultiFileCompiler`/LSP/`Analyzer` all consume the C#
  `CompilationUnit` monolithically with no node-table→AST bridge. Next: the enabling PARSER-KERNEL slice
  (kernel-repin wall) or the task-017 front-end port.

- Task 015 sub-slice — interpolation BASE-CALL classification → N# splitter. NOT committed this turn
  (mandate: do not commit); working tree carries the emitter deletion + the N# splitter method + its tests
  + repin + STATUS.
  - Deleted C# owner: the string-classification half of `TryResolveInterpolationBaseCallPlan` (the `base.`
    prefix + `()` suffix Ordinal parse and the method-name extraction/validation with the no-`.`/`(`/`)`
    guard) in `ColumnarIlEmitter.cs`. Replaced by one mechanical call to
    `ColumnarInterpolationSplitter.TrySplitBaseCall(text, out methodName)` plus a fence comment; the retained
    `_currentStruct?.BaseDef == null` reflection guard, `TryFindMethodOnChain` base-chain resolution, and the
    return-type guards (`void`/enum/generic-param/`ContainsBuilderBoundType`/`IsSupportedType`) stay as the
    mechanical host. `ColumnarIlEmitter.cs` fell 21,438 → 21,433 (net −5 lines / −4 non-blank; epoch ceiling
    21,723/20,646 untouched). This was the LAST inline interpolation string-classification split (cast/
    equality/coalesce/integer-additive already N#-owned) — the movable-decision surface is now exhausted (see
    the 015 completion roadmap).
  - Added N# owner: `ColumnarInterpolationSplitter.TrySplitBaseCall` (an exact mirror of the accepted
    `TrySplitCast`/`TrySplitEquality`/`TrySplitCoalesce` split-decision methods; `import System` added for
    `StringComparison.Ordinal`) + two canonical `.tests.nl` contracts (decompose modeled base-call holes;
    decline non-base-call shapes: no prefix, no `()` suffix, arg-suffix, empty name, paren-in-name, dotted
    name).
  - Method: the live corpus path `examples/06-classes-and-records/ConstructorChaining.nl:56`
    (`$"{base.GetInfo()} - {EmployeeId} ({Department})"`) exercises the arm, making the relocation directly
    byte-exact verifiable rather than a dead-code deletion.
  - Evidence: product IL BYTE-EXACT — PRODUCT_IL_DIFFS=0 across all 162 N#-emitted example/fixture/native
    assemblies (baseline HEAD `6e94ca88c` via `git stash` vs working tree, both fresh Release CLIs,
    `sweepall.sh`); native 208/208 (18 projects; ownership-audit 18/18 post-repin — the single pre-repin
    failure was the ratchet net-negative check, cleared by the repin); BootstrapServices contracts 762/762
    (760 baseline + 2 new split tests, fresh Release self-emit); units 3,190/3,190 Release; Web API template
    builds via the IL backend; ratchet repin (currentLines 21,438→21,433, head `d7f043fb072388db`, mirrored
    in OwnershipAudit.nl).

- Task 015 pivot sub-slice — case-12 primitive-binary residual dead-arm prune (pivot off the blocked
  lambda family). COMMITTED at `6e94ca88c` ("Prune the dead case-12 residual arms by four-surface liveness
  proof"); ratchet head `40cb7fa576abc6c2`.
  - Deleted C# owners: the case-12 primitive-binary whole-subtree residual's four provably-dead sub-arms —
    the `&`/`|`/`^` bitwise arm, the record-struct structural-equality arm (`==`/`!=` boxing through the
    synthesized Equals), the `null == null`/`null != null` constant fold, and the multi-term string-concat
    CHAIN lowering (`TryEmitStringConcatChain` + its sole caller `CanProveStringExpression`). The residual
    pair-concat (`String.Concat(string,string)`) and the reference-identity/string+char/ternary residuals
    stay (self-emit-live). `ColumnarIlEmitter.cs` fell 21,534 -> 21,438 (net -96 lines / -92 non-blank;
    epoch ceiling 21,723/20,646 untouched).
  - Added N# owners: none — ColumnarPrimitiveBinaryPlanner / ColumnarConditionalPlanner already own the
    plannable surface at the front door; the deleted arms served an empty non-plannable-operand band.
  - Method: IL-neutral env-gated arm instrumentation (0 IL diff instrumented vs baseline across all 162
    assemblies) built a FOUR-surface liveness map (corpus+native, units 3,190, full self-emit 228 arms).
    The four deleted arms were 0 on all three logs; three sibling arms (ternary, ref-identity equality,
    string+char) were caught firing in the FULL self-emit and RETAINED (a partial 166-arm run had missed
    `stringcharconcat` — the slice-5 escape signature). Candidate (a) preflight static-call typing proven
    load-bearing (types user-owned enclosing-type statics, not catalog facts) — blocked, recorded.
  - Evidence: product IL BYTE-EXACT (0 diffs across all N#-emitted example/fixture/native assemblies; the
    only 12 sweep diffs are the C# `Compiler.dll`/`BootstrapServices.dll` binaries copied as a reflection-test
    dependency by 6 native projects — expected reflection of the emitter source change, not product IL);
    native 208/208 (18 projects, ownership-audit 18/18 post-repin); BootstrapServices contracts 760/760
    (two-stage, fresh deletion Release SDK); units 3,190/3,190 (Debug and Release); Web API template builds
    via the IL backend; ratchet repin (audit 18/18, head `40cb7fa576abc6c2`); clean feed restored.

- Task 001 — external static fields and properties; commit `6110bbbcf`.
  - Deleted C# owners: `TryUsePlannedExternalStaticMember`,
    `PreloadSupportedExternalReferenceAssemblies`, `TryGetStringComparisonValue`,
    `TryEmitPrimitiveStaticConstant`, and the matching enum/primitive/pool/static-member emission
    and preflight branches. `ColumnarIlEmitter.cs` fell from 21,515 to 21,361 lines.
  - Added N# owners: `ColumnarBindingScopeFacts`, `ColumnarExternalStaticMemberPlanner`,
    `ExternalAssemblyScan`, `ExternalQualifiedTypeResolver`, schema-v3 field handles/`ldsfld`, and
    their native contracts plus package and relative-DLL product fixtures.
  - Evidence: 3,182 units; 178 BootstrapServices contracts; 18 ownership tests; package,
    outside-CWD DLL, issue-tracker, exact-reference, persisted execution, and clean repin proofs.

- Task 002 — bound identifier reads; commit `61a593715`.
  - Deleted C# owners: ordinary local/non-byref-parameter, lifted-local, boxed-capture,
    explicit-`this`, and bare current-instance field/property identifier emission, plus the
    matching preflight/type branches. `ColumnarIlEmitter.cs` fell from 21,361 to 21,209 lines.
  - Added N# owners: `ColumnarBoundIdentifierPlanner`, exact lexical/current-instance binding
    facts, recursive code-plan argument-address and declared-signature validation, live source-type
    metadata, and atomic zero-arity property accessor definition, with native malformed, rollback,
    shadowing, generic/inherited receiver, persisted, and source-type-return contracts.
  - Evidence: 3,182 units; 201 BootstrapServices contracts; 26 range-index product contracts;
    18 ownership tests; fresh non-VS-Code product-gate task surfaces; clean SDK repin.

- Task 003 — instance fields and properties; commit `ad51692d4` (stage-0 prerequisites
  `da2be2c32`, `97cde7c6e`, and `aedb1267f`).
  - Deleted C# owners: direct one-receiver source field/property read emission, direct
    `Exception.Message` and `WebApplication.Environment` property arms, the member-chain preflight
    shortcut for the migrated roots, `typeof` emission/preflight, and zero-hole interpolation
    emission. The retained source-member branch is restricted to excluded nested receivers.
    `ColumnarIlEmitter.cs` fell from 21,209 to 21,164 lines.
  - Added N# owners: `ColumnarInstanceMemberPlanner`, exact runtime/source member resolvers,
    schema-v3 field/method/type handles and receiver-address operations, `ColumnarTypeOfPlanner`,
    zero-hole interpolation receiver planning, and live source type/union/tuple facts, with native
    accessibility, shadowing, inheritance, closed-generic, value/reference/byref, corrupt-handle,
    rollback, persisted-execution, nested-fallback, and recursive range/index contracts.
  - Evidence: 3,182 units; 238 BootstrapServices contracts; 41 range-index product contracts;
    18 ownership tests; three adversarial audits; fresh non-VS-Code product-gate task surfaces;
    clean SDK repin.

- Task 004 — fixed-arity direct calls; commit `5ad756e1d` (stage-0 prerequisites `d6d551ea1`,
  `d24ec7bb4`, `8ce4d49e2`, `fcbcf4ef6`, `0cd216a44`, `0e1d02ed1`, `507742abc`,
  `1e747dd97`, `469408917`, `1b63b9a82`, and `0035d82ae`).
  - Deleted C# owners: synthesized-record `Equals(object)` and `GetHashCode()` call preflight and
    emission, the direct `TextWriter.WriteLine(string)` arm, and unrestricted re-entry into ordinary
    source/runtime fixed-call paths. Retained C# routes are mechanically fenced to excluded call
    families. `ColumnarIlEmitter.cs` fell from 21,164 to 21,097 lines.
  - Added N# owners: `ColumnarDirectCallPlanner`, exact source/runtime resolvers, contextual
    conversion and nullable lowering, source-static scope resolution, exact method/constructor facts,
    address-preserving value receivers, synthesized record call facts, and schema/executor stack
    validation, with native overload, accessibility, malformed-handle, rollback, recursive,
    persisted, alias/shadowing, and IL-shape contracts.
  - Evidence: 3,181/3,182 fresh-gate units with only Task 009 remaining; 382 BootstrapServices
    contracts; 14 direct-call, 2 interface-parameter, 18 ownership, 4 decline-diagnostic, and 2
    reflection-bootstrap contracts; exact ILVerify; three adversarial audits; clean SDK repin.

- Task 005 — construction and array literals; commit `6746c1b2c` (stage-0
  prerequisites `67a3e5803`, `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`,
  and `ff2cf1138`).
  - Deleted C# owners: the Analyzer's string-matched member/export/declaration resolution
    (nested-type, tuple, primary-constructor-parameter, declared-member and export-visibility
    string lookups; `Analyzer.cs` fell from 23,471 to 23,068 lines), the emitter's unconditional
    construction ownership (constructions claimed by the N# planner never reach C#; the retained
    kinds 15/58/36 arms are fenced to the whole-subtree residual), and
    `ColumnarSynthesizedGenericScopeTests.cs` (replaced by the native `generic-scope-invalid`
    project). Aggregate C# net −157 lines.
  - Added N# owners: `ColumnarConstructionPlanner` (source/runtime/closed-generic constructor
    selection with defaults, sized/inferred arrays, source and union-case object initializers,
    runtime catalog), construction-row execution in `ColumnarCodePlanExecutor`,
    `ColumnarSemanticTypeRegistry` + `AnalyzerDeclarationContext` exact declaration scopes,
    `ColumnarPrimitiveBinaryPlanner` (admitted value-position binaries),
    `ColumnarSourceOperatorResolver`, and `TypeInfoIdentityFacts`, with native construction-arrays,
    generic-scope-invalid, and erased-enum-identity product contracts.
  - Evidence: 3,182/3,182 fresh-gate units (issue-tracker fixed); 553 BootstrapServices contracts;
    14 direct-call, 18 ownership, 7 construction-arrays, 3 generic-scope-invalid, and 1
    erased-enum-identity contracts; fresh non-VS-Code product gate down to four failure groups all
    verified pre-existing at HEAD and owned by 009/011/012/013/014; ratchet repin (audit 18/18);
    clean SDK repin.

- Task 006 — primitive binary expressions; commit `e57c80c8a` (stage commits `3dcb60bd2`,
  `e41570f69`, `83941f204`, `62ab5ffdf`, `096655625`, `5523402c5`, `aade33590`, `8397811ea`).
  - Deleted C# owners: the case-12 shifts branch, decimal op_* table, and right-literal adoption
    path from both emission and preflight, plus the preflight's arith/bitwise/ordering/numeric
    equality arms. `ColumnarIlEmitter.cs` fell from 21,618 to 21,499. The retained fenced numeric
    core serves exactly the whole-subtree residual: contextual-lambda call operands (010), member
    chains on call results, unary-negated call operands, dictionary-indexer reads, and string-typed
    operands such as enum string-constant reads (015 grows the nested-operand surface).
  - Added N# owners: the full primitive binary family (arithmetic with checked/unchecked overflow
    selection, bitwise, shifts, ordering with float unordered complements, numeric/Boolean
    equality, decimal op_* calls, string-pair concat, right-literal adoption) at expression roots
    and value position; operand families unlocked along the way — numeric casts, decimal literals
    (incl. negative), sibling-function calls, local-delegate invocations, String.Join catalog,
    List<T> indexer chains, byref-parameter deref reads over the typed-ldind family, ushort literal
    casts, and slot-reinterpretation casts via explicit conv.
  - Evidence: 608 BootstrapServices contracts (Debug and fresh Release self-emit); 15 primitive-
    binary, 41 range-index, 14 direct-call, 3 interface-parameter, 18 ownership contracts;
    3,182/3,182 units; fresh non-VS-Code gate at the same four pre-existing later-owner failure
    groups (009/011/012/013/014) as the 005 acceptance; toolset repins at each two-stage bootstrap.

- Task 007 — conditional and short-circuit expressions; commit `e9df4eb60` (routing commit
  `7eaccb1e9`, Brtrue two-stage bootstrap with mid-stage toolset repin).
  - Deleted C# owner: the `&&`/`||` sub-arm in `TryGetPreflightBinaryExpressionType` (proven dead —
    N# types every plannable short-circuit at the front door; a residual short-circuit is only ever
    emitted, never preflight-typed; zero hits across units, native contracts, examples, and the
    self-emit). `ColumnarIlEmitter.cs` fell from 21,499 to 21,497. The case-12 short-circuit and
    case-13 ternary EMIT arms are verify-first load-bearing (self-emit ternary null-comparison
    conditions; example `||` chains over string equality) and are recut as precisely-fenced
    whole-subtree residual servers retiring with task 015's nested-operand/equality surface growth.
  - Added N# owners: `ColumnarConditionalPlanner` — Boolean `&&`/`||` with the exact case-12
    short-circuit lowering and relocated ternary planning with widened operand recursion, claimed
    at expression roots and value position across emit and preflight facades; the `Brtrue` schema
    identity (contract id 58, condition-gated validation, allowlist name).
  - Evidence: 619 BootstrapServices contracts (Debug and fresh Release-packed-SDK re-emit); new
    conditional product project 8/8 with executed side-effect-order and right-operand-not-evaluated
    proofs; 3,182/3,182 units; all native projects green; fresh non-VS-Code gate at the same four
    pre-existing later-owner failure groups (009/011/012/013/014); clean toolset repin.

- Task 008 — complete range/index owner deletion; commit `23ced5034`.
  - Deleted C# owners: every range/index decision from `399008ea9` and its expansions — five
    static handles plus their resolver, thirteen lowering helpers, the case-11 index-from-end and
    case-69 range arms, the case-10 string/array Index/Range reads, and both preflight
    type-selection helpers with their dispatch arms. Only the Index/Range type-system entries
    remain (typed locals/parameters, not lowering policy). Residual inventory: empty — no fallback
    from N# to any old branch. `ColumnarIlEmitter.cs` fell from 21,497 to 21,209 (net −288).
  - Added N# owners: none needed — `ColumnarRangeIndexPlanner`/`ColumnarRangeIndexHandles` already
    owned the entire surface; the historical C# canonical test was migrated at `0206a1ed1`.
  - Evidence: 41/41 range-index product contracts identical before and after the deletion (the
    decisive dead-code proof); 619 BootstrapServices contracts against both feed and fresh SDK;
    3,182/3,182 units; all native projects green; fresh Release self-emit clean; fresh non-VS-Code
    gate at the same four pre-existing later-owner failure groups (009/011/012/013/014).

- Task 009 — external base and interface resolution; slice commits `85c817440` (base/interface
  classification), `5f9bf3fce` (inherited external-base-method calls), and the extension-calls
  commit; ACCEPTANCE: the generated Web API template checks, builds, and ILVerifies clean, and the
  fresh gate fell from four failure groups to three (013/014 iterators, 011/012 ilverify).
  - Deleted C# owners: the emitter's PASS 0a' base/interface classification decision block
    (`ColumnarIlEmitter.cs` 21,209 → 21,164); the remaining slices added zero C#.
  - Added N# owners: `ColumnarBaseTypePlanner` (ordered base classification incl. external runtime
    class bases with protected-ctor default chaining), inherited external-base-method bare/this
    call planning over the recorded base chain, `ColumnarExtensionMethodResolver` (ExtensionAttribute
    index with instance-beats-extension precedence and trailing-optional null-default fill),
    IServiceCollection admission, and highest-version NuGet runtime-asset unification.
  - Evidence: 625 BootstrapServices contracts; external-base-interface 18/18, extension-calls 4/4
    executed; 3,182/3,182 units; fresh Release self-emit clean; Web API ILVerify fully verified;
    all native projects green; gate baseline shrunk to three groups.

- Task 014 — async iterators; staged commits `d396a847c` (async classification facts: IsAsync,
  AwaitResumeCount, async return-shape admission/declines), `73ae226d5` (await-foreach parsing in
  the N# kernels: awaited kind-29 form + kind-73 consumer statement, toolset repin), `0a33f1ff2`
  (async state machines with REAL suspension: IAsyncEnumerable/IAsyncEnumerator/IAsyncDisposable
  member specs, schema-4 catch regions op 7, awaiter/promise/result/continuation field roles 5-8,
  MoveNextAsync fast-path vs TaskCompletionSource pending path, ldftn MoveNextCore continuation
  ctor, both exception routes, clone/dispose discipline — proven resuming off-caller-thread),
  `f3d1e89c9` (closing: classic C-style for kind 28, postfix ++/-- kind 44 incl. yield i++,
  ToUpper/ToLower/Trim instance calls, kind-73 await-foreach consumer lowering via the accepted
  blocking-await model; AsyncStreams.nl end-to-end).
  - NEW SURFACE like 013: no C# async-iterator emitter ever existed; deletion contract satisfied
    by planner-owned decline sites (emit.iterator.async-*) plus the deleted
    emit.iterator.async-emit-pending gate and zero net C# decision growth (emitter net −2 across
    the closing slice: 21,719/20,644 vs immutable epoch 21,723/20,646 — case-73 additions paid by
    lossless comment compression).
  - Added N# owners: ColumnarIteratorPlanner async classification + AnalyzeShape async facts +
    BuildAsyncMoveNextCore/MoveNextAsync/DisposeAsync/GetAsyncEnumerator/AsyncFactory plans, the
    kind-28/44/instance-string-call body surface, ColumnarCodePlan/Executor schema-4 catch
    regions, parser-kernel await-foreach forms.
  - Evidence: FULL VS Code-ENABLED GATE GREEN — ZERO failure groups (first fully-green gate of
    the closeout; AsyncStreams cleared; 14m11s; gate exit 0 with ALL TESTS PASSED). 731/731
    BootstrapServices contracts (717+14); 3,185/3,185 units; native iterators 25/25 (21+4 async);
    ownership audit 18/18; AsyncStreams.nl builds via the columnar pipeline, output order exact,
    real delays (1.273s wall for 10×100ms+4×50ms), ILVerify 2/2; nlc check/lint on the example
    0 findings; post-commit SDK repin to ~/.nuget/local-feed + gate dependency-cache reseed
    (nsharplang.* must be copied into the active Caches/NSharpLang/test-all/dependencies/<key>
    after a repin — the isolated gate only sees nuget.org plus that cache). VS Code extension
    rebuilt+reinstalled (reload-vscode-extension.sh exit 0); gate VS Code integration tests
    (extension, diagnostics, hover, completion) pass. OUTSTANDING: the computer-use visual IDE
    spot-check was attempted at this acceptance and screen-control access was DENIED at the
    approval dialog again (second denial after 013); the automated VS Code integration evidence
    stands in. Retry at the next IDE-affecting acceptance only if the user re-enables access.
  - Residuals recorded for 015+: await foreach inside an async iterator body (machine
    composition), async instance/generic iterators, awaited operands beyond statement-position
    Task.Delay(int), real async-func lowering to retire the blocking consumer await model.

- Task 013 — synchronous iterators; staged commits `489895987` (func*/yield parsing in the N#
  kernels, node kind 72, generator flag 4096, toolset repin), `71c5450b1` (schema-4 stage 1:
  Ret/Throw/Isinst/Stsfld/Leave allowlist + exception-region operations incl. FAULT, repin),
  `dd7d12107` (method-body executor + backward-branch stack-fixpoint validator, 13 contracts incl.
  the leave-runs-finally-not-fault proof), `03849de55` (ColumnarIteratorPlanner decision layer),
  `d0a4ee530` (MoveNext lowering proven running), `0c0961048` (native iterators project registered
  in ilverify.sh at its 476 ceiling + fall-through fix), `9698fbb76` (array for..in, throw, slot
  reuse), `bb359043f` (enumerator hoisting under the Roslyn try/FAULT region discipline; Dispose
  cascade), `d3602cfa4` (generic iterators via self-instantiation TypeSpec rebinding + MVAR-leak
  guard), `edfcbeb66` (instance iterators: <>__this capture, member reads, user-type sequence
  elements, member-call for..in sources incl. recursion), `f1c1b3b9f` (consumer surface:
  interpolation multi-arg call holes, plan-pinned generic String.Join<Int32>, open-generic
  extension inference — all N#, zero C# growth).
  - NEW SURFACE, not a migration: no C# iterator emitter ever existed (the C# recursive-descent
    func*/yield parser/analyzer stays as the LSP-fallback/oracle owned by 016/017; the analyzer
    already validated func* correctly). The "delete the C# owner" premise did not apply; the
    deletion contract is satisfied by the planner-owned decline sites replacing the blanket
    emit.statement.yield-unsupported arm and by zero net C# decision growth (emitter hosts
    mechanically at 21,619 of the immutable 21,723 ceiling).
  - Added N# owners: parser kernels (func* scan/signature/method-scan + yield statements),
    ColumnarCodePlan/Executor schema-4 method bodies, ColumnarIteratorPlanner (shape facts, state
    numbering, field layout, member/override specs, MoveNext/member/factory plans, decline
    classification), interpolation splitter multi-arg holes, plan-pinned generic external calls,
    open-generic extension-method inference.
  - Evidence: examples/09-linq-and-collections/Iterators.nl builds through the columnar pipeline,
    runs byte-exact across all nine sections, and ILVerifies (all six assemblies); native
    tests/native/iterators 21/21 executed proofs (sequences, infinite+break, re-enumeration
    clones, lazy throw, recursive tree traversal 1,2,4,5,3,6, generic value+reference elements,
    LINQ chain); 690/690 BootstrapServices contracts; 3,182/3,182 units; ownership audit 18/18;
    FULL VS Code-ENABLED GATE: exactly one failure group remains (AsyncStreams, owned by 014) —
    the Iterators group is CLEARED; VS Code smoke tests (extension, diagnostics, hover,
    completion) pass; extension rebuilt+reinstalled via reload-vscode-extension.sh. OUTSTANDING:
    the computer-use visual IDE spot-check was not performed this session (screen-control access
    denied at the approval dialog); the gate's automated VS Code integration evidence stands in.
    Perform the visual check at the next IDE-affecting acceptance (014).
  - Fenced 015 residuals recorded: lambda-taking LINQ arms (TryEmitEnumerableExtensionCall,
    TryEmitLambdaLiteral), the interpolation hole/emission core, the C# generic String.Join arm
    for non-int/string elements, extension interface-receiver inference, preflight typing of
    legacy-owned static calls.

- Task 012 — readonly-field initialization placement; commit recorded in git ("Own readonly-field
  initialization placement in N#").
  - Deleted C# owners: the initialized-fields decision, unconditional helper synthesis, whole-body
    helper emission, and the inline default-ctor body decision — the N# plan is the sole placement
    authority.
  - Added N# owners: `ColumnarFieldInitPlanner` — initonly stores inline in every base-reaching
    constructor, mutable stores in a helper synthesized only when needed, static ownership
    untouched.
  - Evidence: RecordsAndInterfaces builds, runs, ILVerifies clean; estate-wide ILVerify 0 findings
    (empty baseline); the gate's IL-verification step now PASSES — the gate is down to TWO groups
    (013 Iterators, 014 AsyncStreams). New readonly-init project 18/18; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean.

- Task 011 — record-with lowering for value receivers; commit `8a90bcd92`.
  - Deleted C# owners: the case-52 arm's clone-always callvirt selection, receiver gate, per-field
    binding, and result-type decision, plus the value-record `<Clone>$` synthesis branch (record
    structs now carry no Clone, matching C#). The arm is mechanical over the N# plan.
  - Added N# owners: `ColumnarRecordWithPlanner` — clone/copy strategy (reference clone versus
    verifiable value copy through an addressed temp), receiver shape, ordered member resolution,
    readonly decline, exact call form, result type.
  - Evidence: RecordStructs builds, runs correctly, ILVerifies clean (delta −2 findings);
    whole-estate ILVerify over 91 assemblies leaves only the task-012 InitOnly finding; new
    record-with product project 12/12 registered in the ilverify gate; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean; gate steady at three groups.

- Task 010 — lambda definition placement and visibility; slice commit recorded
  in git ("Own lambda definition placement in N#").
  - Deleted C# owners: the non-capturing lambda placement decisions — visibility attribute
    literals, name+counter construction, synthesized-signature guards, value-type/ctor guard,
    type-parameter ownership decision, static-versus-this classification branching, and the dual
    sub-emitter constructions (unified). `ColumnarIlEmitter.cs` 21,164 → 21,150. The value-capture
    display-class path is a precisely-fenced residual pending ModuleBuilder/DefineType modeling.
  - Added N# owners: `ColumnarLambdaPlacementPlanner` — owning-type selection, generated method
    identity, exact visibility (assembly-static for verifiable cross-type ldftn), signature
    validation, and the physical DefineMethod, consumed mechanically by the emitter.
  - Evidence: byte-identical IL across all three product reproducers (which run correctly and
    ILVerify clean; the historical cross-type MethodAccess shapes are confirmed fixed); new
    lambda-placement product project 9/9 registered in the ilverify gate; 625 BootstrapServices
    contracts; 3,182/3,182 units; fresh Release self-emit clean; gate steady at three groups
    (013/014 iterators, 011/012 ilverify).

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

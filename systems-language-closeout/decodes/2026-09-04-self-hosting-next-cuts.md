# Self-hosting follow-ups at 5ac4faa79

Read-only triage. All 425 production `.nl` files match the retained checked archive byte-for-byte;
the retained 260 findings therefore still describe this base. No fresh execution or fix is claimed.
Raw evidence is `/private/tmp/nsharp-takeover-live-check/README.md`.

| Code | Count | Triage grouping; individual fixes still require execution |
|---|---:|---|
| NL010 | 12 | Proven unused imports |
| NL011 | 20 | Empty catches |
| NL012 | 20 | Unused parameters |
| NL202 | 97 | Nullable annotation/flow 61; nullable equality 12; source subtype identity 9; ternary short inference 8; repeated by-ref wrapping 7 |
| NL301 | 16 | Qualified `System.Convert.ToInt32` receiver analysis |
| NL303 | 3 | Nullable `.Value` lookup after flow exposes the inner type |
| NL402 | 63 | Source overload/by-ref binding 58; reflected argument typing 5 |
| NL412 | 3 | Parser helper function visibility |
| NL905 | 26 | Null-flow findings |

## Proven import cleanup

All paths are under `src/NSharpLang.Compiler.BootstrapServices`. Remove only imports reported by
semantic lint, then prove the exact diagnostic delta. The complete base list is:

- `AnalyzerAssignability.nl`: System
- `AnalyzerClrTypeConversion.nl`: System.Collections.Generic
- `AnalyzerDiagnostics.nl`: System
- `AnalyzerStructuralAssignability.nl`: System and System.Collections.Generic
- `AnalyzerTypeSubstitution.nl`: System
- `AnalyzerWellKnownTypes.nl`: System.IO
- `CodeIntelligenceQueryModels.nl`: System
- `CodeIntelligenceSignatureKernels.nl`: System
- `ColumnarConstructionPlanner.nl`: System.IO
- `ColumnarDeclarationPlan.nl`: System.Collections.Generic (owned by the concurrent writer slice)
- `ColumnarGenericConstraintPlanner.nl`: System

There are 306 test-source files, 215 containing literal `import System`; neither that count nor the
old 206/296 estimate measures unused imports. `nlc lint` accepts explicit positional `.tests.nl`
paths even though project discovery excludes them. Use that existing semantic path for a later
test-source hygiene census. Removing all twelve base production imports would leave 248 findings;
re-derive the target after the writer's own cleanup lands.

## Qualified static receivers

All sixteen NL301 rows are `System.Convert.ToInt32`: thirteen in `ColumnarParserRecovery.nl` and
three in `AnalyzerFunctionTypeFactory.nl`. `AnalyzerMemberAccess.NextStep` already resolves the
outer callee's `System.Convert` receiver through `TryResolveQualifiedExternalType`. Reflection-call
phase 30 (`AnalyzerCallAnalysis.AcquireReflectionReceiver`) then asks for another ordinary expression
walk of `System.Convert`; that walk treats `System` as a missing value. Respelling the sources as
`Convert` would bypass this defect.

Preferred narrow candidate: pass the existing `AnalyzerMemberAccess` owner directly into
`AnalyzerCallAnalysis`, then use its guarded qualified-type resolution during phase-30 receiver
acquisition. A hit supplies the receiver type and proceeds to phase 31; a miss keeps the current
expression request and diagnostic behavior. `Analyzer.cs.CreateCallAnalysis` can pass that already
constructed collaborator mechanically without adding a helper, driver request, adapter or callback.
The existing N# call harness also constructs it first. Any C# edit requires the observed ratchet repin.

Alternative: resolve the whole qualified expression in `AnalyzerMemberAccess.NextStep`. This needs
no host wiring but can change standalone type-expression semantics. Choose only after comparing
qualified/unqualified types in assignment, return and argument positions under both check and build.

Controls must also cover missing members, invalid arguments, source/local/alias/enclosing-member
shadows, deeper namespaces, parenthesized and null-conditional receivers, generic owners/methods,
instance and extension calls, and current invalid-receiver diagnostic multiplicity. Reuse the
qualified resolver's existing identity/scope fences; generic/extension binding still needs receiver
analysis. The member-access unit harness currently supplies no assemblies, so existing tests alone
cannot establish the positive reflected path. Prove the sixteen rows disappear without hiding other
findings. This analyzer change will require the IDE verification prescribed by AGENTS.md.

## Separate reflected-argument context defect

The five reflected NL402 rows in `NumericLiteralFacts` analyze `Substring(2)` with a `ulong` argument
inherited from the enclosing return context. `EmitReflectionArgument` requests no expected type and
the driver retains the ambient slot. Investigate context restoration independently; constant
conversion changes alone do not establish that this cause is fixed.

Full CLI `Execute` migration still has the measured assembly-direction and mixed-language inclusion
boundary recorded in `invariant-diagnostics-boundary.md`. The format-command closure is a possible
later ownership cut. Keep the SDK's BootstrapServices analysis exception until strict analysis and
the actual build both pass; these proposed cuts do not satisfy that terminal condition.

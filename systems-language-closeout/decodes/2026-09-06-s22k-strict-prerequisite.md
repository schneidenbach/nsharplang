# S2.2(k): strict-analysis prerequisite

The connected member-iterator owner is integrated at
`9dc7edc852c35536cdd56fe2985482a5387bc4f5`, with the measured ownership ratchet at
`5614eb20c039254da113d55a88825c3327f2b79e`. It is not accepted yet. Its immutable comparison
has zero differences across 94 normalized images and 2,184 native passes per arm, and the current
native declaration suite passes 109/109. Strict checking on the same final source reports 263
findings under both compilers, five more than the accepted 258. The original proof remains at
`/private/tmp/nsharp-023-s22k-proof-20260906/strict/failure.json`.

Three findings concern nullable locals and dereference spellings. Their correction must preserve
the original null failure, short-circuit and member-read phases. The remaining two are NL202 on
passing `IReadOnlyList<ColumnarStructInput>` and `IReadOnlyList<ColumnarFunctionInput>` to the
existing typed `IEnumerable<T>` acquisition helpers. That raw reference pass already emits with
the exact generic Current slots and required disposal. Nine strict-compatible spelling attempts
exposed emission refusals rather than a shared accepted spelling; their sources and outputs remain
under `/private/tmp/nsharp-s22k-executor-logs/strict-correction/`.

The measured discrepancy is in `AnalyzerAssignabilityFacts.IsKnownGenericConversion`: its
`IEnumerable` row omits `IReadOnlyList`, while `ColumnarReferenceConversionFacts` already admits
that inherited reference conversion. The bounded prerequisite adds this relation to the existing
N# analyzer owner. Retain the surrounding real runtime generic-definition identity gate, arity
checks, variance protocol and adjacent refusals. Do not add C# or widen the iterator source forms.
Use complete-analyzer and actual reference-pass controls, including source-name impostors and
incompatible arguments. Restore the already-emitted raw acquisition calls; independently review
the final compiled driver and nullable dereferences.

The corrected immutable comparison will use
`/private/tmp/nsharp-023-s22k-proof-20260906-r2/`. Its strict proof must explain each intentional
diagnostic difference and preserve the accepted baseline, rather than requiring or claiming byte
equality after an analyzer correction. The four new member semantic controls remain required.
The existing seed already emits the conversion; any new seed requirement must be measured.

This prerequisite changes NL202 in the IDE. Final acceptance therefore requires a fresh VS
Code-enabled product gate, extension reload and visual verification of the relevant editor
diagnostics. The earlier backend-only verification plan is superseded. Tasks 015/021/022/023 stay
open; the contingent entry-point slice is not started.

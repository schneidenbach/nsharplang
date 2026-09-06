# S2.2(i): record value-member synthesis

Implementation baseline: `b1abca5841924382006644d5fa5bdba26e77778f`. This slice makes
`ColumnarRecordValueMemberPlanner` the sole owner of PASS 0e's record selection, declaration and body
execution policy. The C# host now supplies the existing ordered inputs, definitions and structural
table through one direct call.

## Driver and structural ownership

The N# driver reads the live input count, checks `input.IsRecord` before indexing the parallel
definition array, and skips every nonnull generic-parameter map. It walks each live field row in
order and stops at the first builder-bound field. Baked-field records define/register Equals, build
its plan, obtain its IL generator and execute it before starting GetHashCode. Clone processing remains
last and runs for reference records on both field paths. The clone keeps attributes 134 and the BCL
`Type.EmptyTypes` array; `RecordClone` is published only after its plan executes successfully.

The five record body type-pool sites now consume structural references from the caller's existing
table. Each plan independently selects its record builder by `DeclaredTypeName`, while object and int
use runtime selections. The plan retains the selected key beside its runtime `Type`, and the existing
executor validates every pair before touching the IL generator.

## Measured spelling and contracts

The first direct expression `def.Fields[fieldName].get_FieldType()` declined at the seeded backend's
instance-member call boundary. Storing the same dictionary result in a local and then reading the
same `FieldBuilder.FieldType` getter is admitted and preserves lookup/getter order. The rejected source
is retained under `/private/tmp/nsharp-s22i-executor-logs/stage0`.

The focused real-driver contract uses a registered nongeneric reference record with one int field. It
bakes the type and executes Equals, GetHashCode and `<Clone>$`, proving all three bodies rather than
only inspecting their builders. Companion contracts pin the non-record and nonnull-empty-generic
skips before structural selection, all five same-table keyed rows, source declaration identity, and
an independently corrupted record runtime companion rejected before any IL or local mutation.

## Host reduction and focused evidence

`ColumnarIlEmitter.cs` removes the PASS 0e loop and both synthesis helpers. The replacement is the
single N# call from the same pipeline phase. The host shrinks by 70 total lines, 66 nonblank lines and
3,479 bytes, exactly matching the reviewed boundary.

The final owned source passed `./scripts/dev.sh Columnar` and the three focused N# record contracts
after a forced test-enabled restore. The formatter changed no owned N# source and `git diff --check`
is clean. Raw logs, TRX output, source hashes and the handoff receipt are under
`/private/tmp/nsharp-s22i-executor-logs`. The coordinator owns immutable corpus replay, strict mapping,
metadata parity, the ownership ratchet and the final backend gate.

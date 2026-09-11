# S2.2(b): structural source-interface member resolution

Implementation baseline: `d29eac35f5c594599f2512c63787b78c8025a4de`. This slice moves ordinary
source-interface method lookup into N#, captures the selected declaration as an emission-scoped
structural member binding, and makes that binding a required input to the existing override
attachment executor. Closed source generics, external interfaces, base slots and iterator member
descriptors remain later S2.2 work.

## Lookup and binding ownership

`ColumnarSourceInterfaceMethodResolver` now owns the former host recursion. It reads only the first
`Methods[memberName]` row, compares the return and ordered parameter handles with CLR `Type ==`,
tries the current declaration before its bases, and visits `InterfaceBases` depth first in declared
order. Default-body rows remain candidates. Exhaustion still returns false with a null binding.
Emitted IL calls `System.Type.op_Equality`/`op_Inequality`; the estate also distinguishes two
non-reference-equal `TypeDelegator` values that compare equal from two separately constructed
builder closures that have equal structural keys but compare unequal as CLR `Type` values.

The successful row produces a `ColumnarSourceInterfaceMethodDescriptor` from the actual found
`ColumnarStructDef` and its authoritative first `ColumnarInstanceMethodDef`. Construction rejects an
owner/definition mismatch by reference identity. The descriptor retains the found declared source
owner, method family, name, zero generic arity, return and ordered parameter structural references,
parameter modifiers, and independent runtime `Type` companions. The binding captures the original
`MethodBuilder` from that same definition. Capture happens only after matching succeeds and does not
call `MethodBuilder.GetParameters`, `ReturnType`, `MethodHandle` or a metadata token.

`ColumnarMethodOverrideDeclaration` keeps its existing default `HashSet<MethodInfo>` source domain,
shared by direct descriptors and the untouched closed-source route. A duplicate therefore preserves
whichever representation arrived first. `Complete` retains a direct binding in its resolved row.
The production three-argument `Apply` first validates every direct binding against the consuming
emission table, including every declaring/return/parameter key and independent runtime companion,
then performs any `DefineMethodOverride` call. The two-argument overload remains valid for existing
bare-handle rows and rejects a structural row without context. Foreign-table and deliberately forged
selected/runtime pairs both fail before an earlier valid row can attach. The C# host now makes one
direct N# call and forwards its existing structural table to `Apply`; the recursive
`TryFindInterfaceMethod` body is deleted with no replacement C# helper, branch, callback or fallback.

## Retained identity immutability

The descriptor review exposed a prerequisite in the S2.2(a) type identities: getter-only N# rows
still emitted ordinary public mutable backing fields, and copied arrays remained reachable through
those fields. The retained scalar/reference fields are now `readonly`, which emits CLR `initonly`.
Nested-name, child-key, descriptor-parameter and completed-target inputs are copied into fresh lists
whose only retained view is a BCL read-only wrapper. Public APIs expose indexed readers or defensive
arrays, never the mutable list. The table/catalog collections remain mutable through their intended
registration APIs; this correction applies to retained identity and completion values.

The package-SDK spelling probes are retained under
`/private/tmp/nsharp-s22b-executor-logs/readonly-stage0-v1` through `-v7`. They measured that
`Array.AsReadOnly` declines at `emit.call.static-member-unmodeled`, while a copied
`List<string>.AsReadOnly()` builds and runs. An `IReadOnlyList<string>` field is admitted, but its
interface `get_Count` expression declines in this stage, so the final rows retain a separate readonly
count and use `get_Item`. The admitted v7 program prints `left:right` after mutating its source array.
These results describe those exact expressions; they do not imply a broader collection or property
limitation. Formatter removal of attempted `private` tokens is metadata-neutral: current N# field
visibility still emits public, while `readonly` supplies the required `initonly` guarantee.

The final linked compiler copy and its complete IL are under
`/private/tmp/nsharp-s22b-executor-logs/final-linked`. The copied DLL SHA256 is
`66fbcd03624ae4b4c4923e62a11af5f2f5d99576852a60829d47c5853a315607`; the IL SHA256 is
`cfaf9005ee43a5340f80927d32fe3284d96ef9d06398ae2dc85c9bddfa1bfd25`. The receipt verifies all
fields across the five structural identity rows plus the new descriptor, binding, resolved-row and
completion rows are `initonly`. Independent contracts show caller array mutation cannot change the
captured key, casts to mutable `IList` cannot mutate the read-only name/child views, and the completed
target array is defensive.

## Focused evidence

| Check | Result | Raw evidence |
|---|---|---|
| Bootstrap-services N# estate | **7,714 passed, 0 failed** | `/private/tmp/nsharp-s22b-executor-logs/estate-12-postformat.log` |
| `./scripts/dev.sh Columnar` | CLI build passed; **12 passed, 0 failed** | `/private/tmp/nsharp-s22b-executor-logs/dev-columnar-final.log` |
| Native columnar emit facts with source-interface controls | **85 passed, 0 failed** | `/private/tmp/nsharp-s22b-executor-logs/native-source-interface-controls-final.log` |
| Native iterators | **25 passed, 0 failed** | `/private/tmp/nsharp-s22b-executor-logs/native-iterators-final.log` |
| Baseline/current strict walk on the same edited source | **428 files, 259 existing findings, byte-identical JSON** | `/private/tmp/nsharp-s22b-executor-logs/strict-{pre,current}-on-final-edited.json` |

The strict stdout SHA256 is
`347308150ef3bf8c6667882bab5e3eaf4901346914247e6dbc1608c625406d99` for both compilers and stderr
is empty. An earlier combined condition introduced two nullable-flow findings; an explicit null-row
invariant guard restores the baseline 259 count and only changes malformed internal null-row failure
to an `InvalidOperationException`. The zero-output `estate-11-postformat` invocation was not a test
verdict: `dev.sh` had restored the project with N# tests excluded. A forced test-enabled restore
preceded the counted 7,714-test result above.

The native controls pin own declaration selection, mismatch-to-actual-ancestor fallback, first-base
diamond order, default-body admission, combined source/external slots, successful parser-to-emitter
counterparts, and false-with-empty-trace missing/signature-mismatch outcomes. The direct estate pins
the first-`Methods`-row-only rule, CLR equality boundary, generic owner identity, source/closed shared
deduplication, snapshots, foreign emissions, malformed pairs, no-partial-attachment behavior and
actual unbaked binding execution.

`ColumnarIlEmitter.cs` decreases from **19,629 / 18,637 / 1,021,506** total lines, nonblank lines and
bytes to **19,613 / 18,622 / 1,020,953**. Its SHA256 is
`a6b77bb26cafa85fe6a1a047eb7be2cfdb08aaa43568667902608f62704a4eaa`. The coordinator owns the
fixed-corpus and physical `MethodImpl` parity replay, ownership ratchet, integration gate and push.
This slice does not publish an SDK.

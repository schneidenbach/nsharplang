# Static-field initializer emission ownership

Selected from clean/pushed `4269be784`: complete static-field initializer emission, including the
production `.cctor` driver and seven connected helpers: `TryEmitStaticFieldInitializerLoad`,
`TryEmitStaticFieldExpressionInitializerLoad`, `TryParseParameterlessStaticInitializerCall`,
`IsSimpleIdentifierText`, `TryEmitStaticFieldLiteralInitializerLoad`, `TryParseFloatingLiteralBody`
and `IsSupportedGenericExtensionReceiverChainText`. The last caller moves with the identifier
predicate so its C# Array.Exists decision callback disappears too.

The driver visits source definitions in declaration order, scans pending initializer rows by owner
identity, creates a type initializer only on the first matched row, emits each value then Stsfld, and
emits Ret after that owner’s rows. A failed value emission preserves earlier emitted work and stops
before later owners. The load owner resolves same-type static overloads in order before lazily
checking siblings. Literal handling preserves integer suffix/type rules, unchecked ulong conversion,
floating culture/separators/sign/narrowing, character decoding and string behavior. Parsing and
receiver-chain outputs retain their initial/failure states and original exception/read order.

Original state includes List<(ColumnarStructDef, FieldBuilder, Type, int, string)> pending rows and an
eight-field sibling signature dictionary. Compile the actual complete proposed source before
claiming a capability blocker. Necessary state moves with callers; no new C# projection helper,
adapter, decision callback, fallback or canonical test is permitted. Canonical assertions migrate
with their complete compiler behavior; native coverage is reused where it already proves the path.

Sol Max owns production and end-to-end assertion migration, Terra Max direct N# controls, Astra
reviews/integrates/ratchets/gates/pushes. Evidence:
`/private/tmp/nsharp-static-initializer-ownership-20260906/baseline.json`, immutable `baseline-cli`,
`emitter-before.cs`, `ratchet-before.json`. Prior fresh gate passed590 unit/7,849 canonical/52 native
projects/12 throughput/68 IL in448s. The selected area and full compiler goal remain open.
Broader branch initiatives stay in `tasks/BRANCH-BACKLOG.md`.

Actual-source findings: `proposed-r1/build.log` rejects the pending List<ValueTuple<ColumnarStructDef,
FieldBuilder,Type,int,string>> parameter. Its producer and consumers move to a validation-free N#
pending-initializer data owner. Intermediate full-source r2 admits the existing eight-field sibling
tuple registry and reaches body emission, so no sibling representation change is justified by that
probe. Its first refusal is a chained Builder/Name/coalesce argument; ordered local reads preserve
the original argument-evaluation phase. At that stage no SDK prerequisite was established; the later complete-source findings below establish the necessary calls.

Historical static-field tests were deleted with the transpiler at `a50cb4000`; current successor
searches by unique program names/source found no equivalent native compiler contracts. This is a
coverage gap, not a restart of accepted migration. Baseline probes guide new focused runtime/metadata
controls; obsolete historical decline expectations are not copied into current canonical tests.

Further full-source r8 reaches sibling local materialization and rejects `new ValueTuple<8-rest>()`
(`emit.local.initializer`); declaration admission alone did not establish usable storage. A
validation-free N# sibling-signature data owner now replaces the tuple at the original producer,
with all consumers routed mechanically and original field/array identities retained. The provisional
fresh List allocation before TryGetValue is replaced by a typed-null out local to preserve lookup
allocation/order behavior. These are dependency ownership moves, not new C# projection layers.

Sequential discovery establishes four prerequisites: Array.Empty<string> (r13), UInt64.TryParse
(string,out ulong) (r12), Int64.TryParse(string,out long) (discovery-r14), and Double.TryParse
(string,NumberStyles,IFormatProvider,out double) (discovery-r18). With only those calls temporarily
substituted, the complete candidate builds (discovery-r20); exact source is restored at proposed-r21.
Immediate operand locals and the accepted full-arity StringLiteralDecoder call retain emission/failure
phases. Temporary call substitutes and cached-array state are not product code. Sol implements the
Array.Empty N# direct-call/binding path; Terra the three numeric N# binding rows. Both are isolated
from the owner and will form one verified seed checkpoint before exact-owner compilation resumes.

Prerequisite review requires the explicit generic external path to preserve value, additional-root,
visible-type-parameter, alias, and source-owner shadows before runtime selection. Source generic
methods retain their existing owner. Numeric admission pins the exact by-reference types and the
Double IFormatProvider formal; native assertions cover signed extrema, unsigned max/overflow, and
failure out resets. The initializer owner must retain null-overload lookup failure rather than
silently consulting siblings. These review controls accompany the complete ownership area.

Prerequisite seed accepted at `9b01b93bf`: one fresh backend gate passed in 449s with 590 unit,
7,854 canonical, 52 native projects, 12 throughput cells and 68 IL assemblies. Official setup
published the tested package set; both feeds match, all 10 tool payloads match Release and all
12 SDK/cache payloads match. A normal minimal SDK project compiled the exact two native prerequisite
files plus an integer control and passed 3/3. IL names the exact four BCL calls. SDK SHA-256:
`5e8b271fadc349bf6c50d00746910fe5db01af5e2d7df4f8ef3ad4f204e7998d`. Receipt:
`/private/tmp/nsharp-static-initializer-ownership-20260906/seed/acceptance.json`. The full initializer
owner and canonical assertion migration now resume; this prerequisite is not area completion.

Integrated complete owner at `a81ec8de9` (worker `7b91d6deb`): N# now owns the `.cctor` driver,
all seven connected helper methods, and pending initializer/sibling signature data. Three production
calls route directly into N#; the C# driver, helpers and Array.Exists callback are deleted. Surviving
C# changes construct/pass the N# data objects at the original producers and update their parameter
types; they add no compiler decisions. The rest of the containing emitter remains compiler debt.

Fresh focused N# controls pass 6/6 after formatting. Three new native contracts cover the historical
coverage gap; the exact same final source passes baseline and candidate with identical six selected
names/outcomes (three related existing tests are also selected). Runtime/metadata checks cover class,
struct and record fields, literal values, same-owner/sibling calls and declaration-order effects.
Root independently reviewed emitted IL and source; primitive equality, unchecked conversion/negation,
exact BCL calls, lookup failures, lazy construction and load/store/Ret sequencing are preserved.
Integrated dev build passed. Emitter shrinks 18,447→18,213 lines and 17,532→17,308 nonblank;
all 380 other ratchet rows and all epoch values remain unchanged. New head is
`head-v1:109c7a7ac6bb731e`. Final integration verification remains pending.

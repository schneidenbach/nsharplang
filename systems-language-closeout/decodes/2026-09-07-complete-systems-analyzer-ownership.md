# Complete SystemsAnalyzer ownership

Compiler-only boundary: replace the whole 1,156-line / 1,061-nonblank C# SystemsAnalyzer class at
`a207ee13bcfa0feb90696264d0abca56c561d914`, including all five nested state types. Keep the already
accepted N# Systems* policies. Move state/initialization, declaration registration and semantic site
resolution, visible-file projection, recursive traversal and effect propagation, guard/allow/unsafe/
allocation state, finding transport, and report construction into the sole N# owner. MultiFileCompiler
must consume that type directly; no C# wrapper, decision callback or fallback survives.

Preserve AST reference-keyed caches, DeclarationSite component value equality (including null
containing type), recursive cache/visiting/emitted ordering, fresh-versus-shared report collections,
complete visible-candidate enumeration and conservative ambiguity, expression/statement evaluation
order, exact finding metadata and meaningful failure state. Existing scope push/walk/pop calls do
not use finally; do not silently add cleanup on exceptions. Normalized duplicate source paths must
still fail rather than overwrite entries. Keep existing AOT report fields without expanding into
NativeAOT or runtime reimplementation.

Sol Max owns the complete class replacement in an isolated worktree. Canonical inventory and lifecycle
regressions are preserved; after a Terra capacity failure, a second Sol Max worker completed the
collection prerequisites and now reviews constructor/reset/report semantics. Astra owns review, integration,
shared ratchets, gates, any necessary SDK publication and push. Compile the complete proposed source
to prove blockers; implement necessary prerequisites in N#, grouping related capabilities. No new
C# compiler behavior, tests, helpers, adapters or fallback implementations. Use focused dev/native
checks for commits and reserve a fresh integration gate for the completed area/SDK checkpoints.

Evidence: `/private/tmp/nsharp-systems-analyzer-owner-20260907`. Baseline C# SHA256
`7f2a7ef455eba43607499d5bf089d781b499d5186f8ce43ba5e0c1d29ddbf780`. The previous complete Analyzer
migration remains accepted: fresh backend gate 481s, 574 C# / 7,928 canonical / 53 native projects /
12 throughput / 68 IL assemblies, installed self-host 7,928 and Analyzer corpus 1,088. Accepted SDK
SHA256 `d43d021038063adf04322c9964cfec81d50a22593b903a5abf78541d15416430`. Frozen source,
ratchet and production compiler payloads are retained. The compiler-wide objective stays open;
CLI/editor and older SDK branches remain held in the separate branch backlog.

## Execution evidence

The two uncovered public lifecycle contracts are now canonical N# assertions at `843363b96`:
an older report retains the live Functions list across Analyze calls, and normalized duplicate
input paths fail after that list is reset. Baseline evidence is 2/2 focused and 24/24 for the
containing native project. The existing systems corpus retains 123 canonical N# test blocks.

Compiling the complete replacement exposed actual capabilities needed by this owner. The grouped
N# prerequisite work covers source record-struct Dictionary keys, typed enumeration of the existing
KeyValuePair shell with a source-class value, and the explicit generic Enumerable.ToDictionary call.
First test the existing N# explicit-generic static-call planner/catalog route for that call. The
terminal C# generic-unresolved diagnostic alone does not prove this earlier N# route is unavailable.
Move the complete existing Cast/OfType route and its helpers only if an actual dependency requires
it; any surviving C# call must be mechanical, with argument planning owned by N#.
Keep the BCL materialization call: its non-enumerated count and
enumeration behavior are observable through the public input interface. Source probes and exact
declines live under the evidence directory's `probes` and `record-key-seed` subdirectories.

Supported N# source equivalents avoid other seed changes: a private static factory preserves the
single shared readonly semantic-model map, explicit CLR accessor/interface calls preserve the
same keys and iterator operations, and private list-count helpers preserve the ordered report
flag counts. Final emitted-IL and production verification remain required. Temporary discovery
substitutions are recorded separately and must all disappear before owner acceptance. No new
SDK seed has been published, and no selected-area integration gate or push is claimed.

Review removed two unnecessary proposed prerequisites: the complete private DeclarationSite factory
decisions move into their callers, so source-static out-record calls and default-zero record
construction are not needed. The discarded private out value was not observable on failure; the
valid branch retains the original property-read and construction order. Do not add compiler
capabilities solely to satisfy an expanded probe that the production replacement no longer needs.

The private DeclarationSite helper can use a non-positional record struct with explicit readonly
component fields and its complete constructor. Actual source compiles and emits initonly fields
with synthesized field-wise equality/hash. This preserves its immutable dictionary-key behavior.
The private type lacks the C# IsReadOnlyAttribute; no public API exposes it and no production decision
consumes that attribute. Record this internal metadata difference rather than adding parser or
arbitrary type-attribute support solely to reproduce it. Public SystemsAnalyzer API metadata remains
an acceptance requirement. Evidence: `probes/readonly-record-explicit-fields-r1` and its attribute
control beneath the evidence directory above; final native equality and whole-owner checks remain open.

The existing N# explicit-generic static-call route is sufficient: `792bd93c6` integrates the exact
ToDictionary string closure and ReferenceEqualityComparer.Instance binding without a new planner
or C# route. Verified evidence is four canonical controls, two native ToDictionary cases (including
duplicate-key failure), and one object-key reference-identity case. The latter does not prove typed
AST-key constructor support. Logs: `todictionary-bss-r9-final.log`, `todictionary-native-r5-final.log`,
and `reference-equality-native-r4-object-final.log` beneath the evidence directory.

`400d500cc` adds the exact inherited dictionary-enumeration receiver conversion; all ten focused
reference-conversion controls pass (`dictionary-inherited-conversion-canonical-r2.log`). `65307d718`
integrates source record keys and the exact inherited typed-enumerator selector. Its combined
canonical controls pass 5/5, exact immutable-key native test 1/1, and reflection-bootstrap project
33/33. Metadata/IL confirms the private value key, five initonly components, complete field-wise
equality/hash, typed Current, and disposal. See `record-key-seed` receipts r41 and r43–r46.

The merged prerequisite source also passes `./scripts/dev.sh Columnar`: 12/12 focused tests in 64s
at `65307d718` (`root-dev-columnar-65307d718.log`). This is inner-loop evidence, not a product gate.

`f7ef6b789` integrates typed reference-comparer support (worker commit `3537ce3b4`). The actual
substituted constructor-parameter probe established independent type-admission and argument-flow
gaps. Both are fixed in N#: the canonical control passes 1/1 and actual typed HashSet/Dictionary
runtime identity passes 1/1 (`reference-equality-canonical-prereq-r4-admission.log` and
`reference-equality-native-r8-typed-explicit-project.log`). The production-only candidate SHA256 is
`9f33c6cc76e7814e1b220d7b909eadf3ef5b0dc07cbf4afa72ab67689327e8a5`.

The complete owner is integrated at `946821316`: all 1,156 C# lines are deleted. Exact production
emission of 801 N# sources passes in 19.88s and test-inclusive emission in 52.54s, both with zero
warnings/errors (`combined-owner-r1/logs/production-build-r3.log` and `tests-included-build-r2.log`).
The only final source spelling correction passes the existing optional null explicitly to
ProjectFileParser.CreateDefault. Root `./scripts/dev.sh Systems` passes 3/3 in 32s; the existing
systems corpus passes 123/123 (66 census, 13 gauntlet, 44 proof). Lifecycle/error-handling passes
24/24 against the direct N# identity. `d8120962` integrates that lookup and retires exactly the
SystemsAnalyzer ratchet row; 380 other rows and all epochs remain unchanged, audit 18/18,
head `head-v1:130fb0badc59fc18`. Emitted Compiler IL directly constructs and calls SystemsAnalyzer
in BootstrapServices; the only surviving C# reference is mechanical MultiFileCompiler transport.

Metadata review found two meaningful gaps despite the passing behavior tests. `eefbf6cdb` replaces
the two private expression properties with private methods at the same evaluation sites; both
production and test-inclusive emission pass, and emitted metadata no longer exposes public getters.
The existing explicit sealed class modifier is still lost between declaration scanning and type
planning. A bounded N# fix must preserve that bit for the outer class and four private reference
types before acceptance. Public Analyze signature/defaults and all 24 field shapes (22 readonly)
otherwise match. Constructor HideBySig omission has no inherited-constructor behavior; absence of
BeforeFieldInit only strengthens initialization timing for the private shared empty-map allocation.
These metadata differences and the private key attribute difference above are accepted explicitly;
loss of sealed or private visibility is not accepted.

`bc3fa6865` completes the N# sealed-modifier path through existing declaration columns, input state
and type planning. Three executed canonical controls pass, including preservation of the original
null-output error code. `2a5be66e3` adds actual source metadata regressions: the baseline fails the
three sealed cases while the ordinary-class/value control passes; the candidate passes all four.
Final root metadata confirms the outer class is sealed, all five declared nested types are private
and sealed, the public constructor/Analyze signatures and defaults match, and no private helper is
exposed. Receipt: `root-final-metadata-review.json`. No C# file changed in this prerequisite.

Final `./scripts/dev.sh Columnar` passes 12/12 in 63s. The rebuilt root compiler passes lifecycle
24/24, reflection-bootstrap 37/37 (including the record-key and sealed controls), and ownership audit
18/18. Evidence: `root-dev-final-sealed.log`, `root-lifecycle-final.json`, `root-reflection-final.json`,
and `root-audit-final.json`. Final systems corpus also passes 123/123 (66/13/44) under
`systems-owner-native-final`. Private bootstrap payload receipts live under `root-stage0-bootstrap`
and `root-stage0-sealed`; these isolated payloads preceded the verified installation below.

## Acceptance

The complete selected area is accepted. The fresh backend gate at `3617a809a` passes in 474s:
574 unit / 7,940 N# canonical / 53 native projects / 12 throughput cells / 68 IL assemblies.
Evidence: `/private/tmp/gate-20260907-systems-analyzer-final-r1` and `final-gate-receipt.json`.
Official SDK setup succeeds after that gate, and the ordinary installed-package probe passes 11/11.
Both feeds contain the same four packages; ten SDK tool payloads match the Release build and all
twelve loaded SDK/cache files match the package. SDK SHA256:
`b8aea5469c99f281ecacf34c5f5117521bd95baf13d45db90dc809be7a8d2aee`.
The installed SDK freshly self-hosts the compiler and passes 7,940/7,940 canonical assertions with
no SDK-path override. Installed owner metadata exactly matches the reviewed integrated metadata;
the SDK contains the production-only assembly. See `final-sdk-acceptance.json` and `seed-final`.

No SystemsAnalyzer C# owner, decision callback, adapter or fallback survives. MultiFileCompiler's
existing direct construction/call is the sole mechanical non-N# consumer boundary for this area.
Canonical lifecycle lookups name BootstrapServices directly. Broader compiler ownership is still
open; the next dependency-based candidate is the complete ColumnarProgramInputBuilder class.

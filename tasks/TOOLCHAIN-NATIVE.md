# Active managed toolchain conversion

Authorized 2026-09-09, after completed compiler ownership and Compiler Core rename.
Astra plans, reviews and integrates. Luna Max subagents implement bounded complete areas using
the N# skill and current repository language docs/executable N# examples. Minimal faithful
conversion is the default; no redesign or new feature work is implied.

## Scope and completion

Convert remaining managed Compiler facade, Build.Tasks, CLI, LanguageServer, Playground and Runtime
production ownership to N#. Evaluate and convert the Wasm export host where supported; document any
strictly mechanical host boundary. SDK/Templates remain native packaging configuration; change their
integration only as required by these ports. Visual Studio extension is deferred at very low priority.
NativeAOT, a new metadata writer and unrelated branch initiatives remain separate.

Migrate canonical C# assertions with each owner, including setup/state, ordering, exact diagnostics,
outputs and failure/lifecycle behavior. Remove replaced assertions and unused helpers after N#
successors execute. No new C# behavior, tests, helpers, adapters, callbacks or fallbacks. Intentional
C# interoperability fixture inputs may remain where they prove cross-language behavior.

Move complete classes or connected methods with necessary helpers and state. Preserve public and
package contracts; don't treat changing project extensions as completion. Compile actual proposed
N# sources to prove prerequisites; implement required compiler fixes in N#. Root serializes shared
compiler prerequisites, SDK seeds/feed writes, ratchets and integration gates. Use dev.sh and targeted
native tests while implementing. Commit coherent green pieces; root reviews and runs fresh required
integration gates and IDE verification before push. Retire completed worktrees/branches after checking
active users, unique history and dirty files, preserving evidence and recoverable unfinished work.

## Current lanes

Base: 06186dc6d (includes bootstrap/CI work; preserve it).

| Area | Owner | Worktree / branch | Status |
|---|---|---|---|
| Complete Compiler service facade and assertions | Luna Max toolchain_facade | /private/tmp/nsharp-agent-wt/toolchain-facade; codex/toolchain-facade | Implementing |
| Complete LoadProjectConfig / LoadProjectReferences and assertions | Luna Max toolchain_build_tasks | /private/tmp/nsharp-agent-wt/toolchain-build-tasks; codex/toolchain-build-tasks | Implementing; reuse held config work |
| CLI query/commands and LSP signature/services | Next wave | Existing held branches preserved | Refresh and integrate accepted work; don't restart |
| Playground interpreter | Queued | No new worktree yet | Complete connected owner and tests |
| Runtime ABI and bootstrap | Queued | No new worktree yet | Preserve CLR identity/behavior; verify actual proposed types |
| Wasm host | Queued | No new worktree yet | Prove export integration and retain only necessary mechanical boundary |

Assessment and actual probe evidence: /private/tmp/nsharp-other-projects-assessment-20260909/ASSESSMENT.md.
Existing held config/query/signature work remains preserved until integrated or safely archived.
A finished lane is not completion of this whole objective.

## Compiler capability gaps for the Runtime conversion (2026-09-10)

Proven with the tip CLI (`nlc 0.1.0+dc7efda2f`) before any edit, then implemented as one integration
branch (`gap/integration`, 20 stream merges plus 3 root fixes) by Opus streams in persistent worktrees
under `/Users/spencer/repos/nsharp-worktrees/gap-*`; root planned, reviewed, merged, gated and pushed.
No Runtime `.cs` file was edited; the four acceptance sources are translated as executable native tests
that compare side by side with the real `NSharpLang.Runtime` types.

| Gap | Baseline | Now | Native evidence |
|---|---|---|---|
| Readonly structs | NL101 at `readonly struct` | all modifier orders, generic, `readonly ref/record struct`; NL326 mutable-instance-field rule; NL311 on non-structs; `IsReadOnlyAttribute` + `initonly` emission | `tests/native/readonly-structs` |
| Static members on generic types | NL323 at the declaration; `Box<int>.Create` parsed as a comparison | constructed generic receivers (`Name<T>.Member`, new AST node); static fields/properties/methods/operators/conversions on generic types with per-instantiation storage; generic methods on user types; `Result<int, string>.Ok(42)` | `generic-type-receivers`, `generic-static-members`, `user-generic-methods`, `runtime-acceptance` |
| Type identity by arity | NL306 for `Subscription` + `Subscription<T>`; generic user types emitted WITHOUT the `` `N `` CLR suffix | (name, arity) identity in every table; `` Name`N `` metadata names; qualified and unqualified references are one identity; abstract/virtual/override on source classes; faithful `NSharpEventSubscription` with zero deviations | `type-arity`, `class-inheritance`, `generic-member-types` |
| Constructed external generic members and constructors | `Vector<int>.Count` parse failure; `new Vector<int>(a, i)`, operators, indexer and `Vector.Sum` declined at emit | ordinary resolution for constructors, operators, indexers, generic static and instance methods (explicit and inferred type arguments), static members of constructed types; complete `SimdReductions` translation executing with parity against the C# helper | `external-generic-construction`, `external-generic-methods`, `simd-reductions`, `tuple-names` |

Adjacent gaps closed because the acceptance sources required them: external generics over the declaring
type's own parameters and over complete source types (`IEquatable<Self>` base lists with real dispatch,
`EqualityComparer<T>.Default`); `?.`, `default`, `base.Member` and `is` over any type in the columnar
backend; `[MethodImpl]` implementation flags (were silently dropped; NL930-NL932); `TupleElementNamesAttribute`
in both directions; namespace-qualified names in expression position; an explicit import now outranks
project-wide auto-discovery, and two imports supplying one name is NL209 (auto-discovery itself is kept:
`examples/12-multi-file-projects/AutoDiscovery` documents it); by-ref arguments in the semantic call planner;
user-defined conversions declared by external generic types; NL327 for `this`/`base` without a receiver.
Measured language limits that the translations spell around: `const` is not a field modifier (the
`MethodImplOptions` combination is written at each member), N# has no explicit interface implementation
(`IEnumerable<T>` on a source class does not load), and a generic method called directly on a call
result needs a local. Remaining documented limits are in `website/docs/types.md` "Current limits".

Evidence at the integrated tip: compiler-service estate 8,339/8,339; 66 native projects, every one
executing with zero failures; C# unit suite 399/399; format gate clean; ilverify clean over the new
assemblies. Three regressions were caught only by full sweeps or the product gate (a nullable-interface
typed local, `TryGetValue(key, out x)` on a static-field receiver, `base.Value` accepted in a constructor
initializer) plus a double-`box` IL defect from a merge collision — streams must run the FULL native
sweep, and a native project whose test build fails reports total 0, which a sweep must flag.
The A2 stream's three slices (abstract/virtual/override, generic-over-type-parameter member types,
exception property reads including the `ArgumentException::get_Message` override contract) are one
squashed commit whose message names only the first; this paragraph is the record for the other two.


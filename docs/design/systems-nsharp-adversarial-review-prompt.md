## GOLDEN RULE: ALWAYS use codex-review to adversarially debate your proposals!

You are reviewing a proposed "Systems N#" design for N#, a pragmatic .NET/CLR
language positioned as "Go for .NET."

Your job is adversarial product/language review. Do not be agreeable. Assume the
team may be fooling itself. The core question: can this credibly appeal to real
systems engineers while preserving N#'s purity and fitting the .NET ecosystem?

Review through three lenses:

1. N# purity: Does this preserve N# as a simple, pragmatic .NET language, or does
   it bolt on incoherent Rust/D/Zig concepts?
2. .NET ecosystem fit: Does this make sense on the CLR with GC, JIT, NativeAOT,
   Span<T>, unsafe, IDisposable, reflection-heavy frameworks, NuGet, and C#
   interop?
3. Systems engineering fit: Would people who write parsers, codecs, protocol
   stacks, game loops, trading/latency code, embedded-ish .NET, databases,
   runtimes, storage engines, networking stacks, and high-throughput services
   find this credible? What would they reject?

Important: write challenging pseudo-N# examples, not toy examples. They do not
need to compile. Pull scenarios from real systems code:

- packet parser
- binary codec
- ring buffer
- arena/bump allocator
- zero-copy protocol frame reader
- logging hot path
- JSON/UTF-8 parser
- order book update loop
- game ECS update
- native interop wrapper
- file IO boundary feeding hot parser
- ZLinq/value pipeline
- safe wrapper over unsafe memory copy
- NativeAOT-compatible CLI tool
- package boundary adapter

Spec to review:

Product lanes:

- Default N#: pragmatic .NET.
- Systems N#: whole-project profile.
- Default projects can still use `[hot]` locally.

Project config:

```yaml
language:
  profile: systems
  systems:
    mode: strict # audit | strict; systems defaults strict
    unknownExternalCalls: warn # allow | warn | error
```

Systems strict:

- Rejects all unmarked heap allocations.
- `new User()` errors if it heap-allocates.
- `alloc new User()` is allowed in ordinary systems code.
- `new SomeStruct()` does not require `alloc`.
- Audit-mode findings are separate systems findings, not normal warnings.
- Strict promotes policy violations to errors.
- Systems diagnostics use `NSYS###`.

`[hot]`:

- Available in any project.
- First-call inclusive.
- Implies no heap allocation, boxing, delegate allocation, closure allocation,
  runtime polymorphic dispatch, reflection, dynamic code, throwing, unknown
  external calls, or AOT blockers.
- `[hot]` does not imply memory safe.
- `[hot]` may contain explicit restricted `unsafe` if performance effects still
  pass.
- `[hot]` cannot throw; boundaries translate exceptions into explicit
  `Result<T,E>`.
- `[hot]` cannot create/open disposable resources in v1.
- `[hot]` allows read-only existing managed refs, strings, and arrays only for
  proven non-allocating operations.
- Unknown getters fail unless compiler-proven trivial, builtin, or tiny
  IL-proven.

Allocation:

```nsharp
x := alloc new User(...)
bytes := alloc new byte[4096]
msg := alloc $"id={id}"
items := alloc [1, 2, 3]
alloc {
    msg := $"id={id}"     // allowed selected obvious allocation sugar
}
```

- `alloc` marks selected construction forms, not arbitrary method calls.
- Delegate/closure allocation has no `alloc` marker in v1; it is boundary/allow
  only.
- `[hot]` rejects even `alloc new` unless inside `allow(alloc, reason: "...")`.

Allow/trust:

```nsharp
[allow(dispatch: interface, reason: "...")]
allow(alloc, reason: "...") { ... }
```

- Function-level and block-level only.
- Reason required.
- Trusted user package facts do not satisfy `[hot]`.
- External IL-proven facts can satisfy `[hot]` only for tiny whitelist shapes.

Boundary:

```nsharp
[boundary]
func LoadDotNet(...) { ... }
```

- Adapter contract, not "anything goes."
- Normal .NET patterns are allowed inside and reported.
- Boundary exported surface must not leak unsafe systems-hostile shapes.
- AOT blockers inside boundary require explicit allow.
- `nlc publish --aot` fails on reachable AOT blockers even if allowed for normal
  build.

Types/error model:

```nsharp
value union Result<T,E> {
    Ok { value: T }
    Err { error: E }
}
```

- Payload-carrying allocation-free unions require explicit `value union`.
- `value union` can carry references generally.
- `[hot]` applies stricter payload-safety rules.
- `Result<T,E>` should be a standard value union, not a weird intrinsic.

Effects/tooling:

- Call graph effect summaries.
- Internal summaries inferred.
- Public/package APIs need explicit or inferred summaries.
- Effect lockfile optional:
  - `.nlc/` generated facts by default.
  - `nsharp.effects.lock.json` via `nlc systems freeze-effects --write-lock`.
- `nlc check` enforces `[hot]` in default projects.
- In systems profile, `nlc check` includes systems diagnostics.
- `nlc systems check` gives deeper JSON reports.
- Canonical reports are versioned JSON for automation/LLMs.

External audit:

- Full dependency graph: NuGet, project refs, local DLLs, transitive deps.
- `nlc systems audit-package` works isolated or project-context.
- Facts: `compiler`, `builtin`, `ilProven`, `trustedUser`, `unknown`.
- Confidence: `proven`, `likely`, `unknown`, `trusted`.
- `[hot]` accepts only compiler/builtin/tiny IL-proven facts.

AOT:

- First real Systems milestone requires actual `nlc publish --aot` native binary
  support.
- Initial target: constrained systems CLI and library/package validation, not
  ASP.NET.
- Dedicated templates and flags:
  - `nlc new systems-cli`
  - `nlc new systems-lib`
  - `nlc new console --systems`
  - `nlc new lib --systems`

Lifetime/resources/unsafe:

- V1 includes CLR-native lifetime/ref safety, not Rust ownership.
- Span/ref struct escape rules inferred; `scoped` exists for advanced interop.
- Systems strict enforces obvious IDisposable disposal with existing `using`.
- No `defer` in v1.
- Restricted unsafe available anywhere with explicit `unsafe`.
- Memory safety is separate:

```nsharp
[memory(safe)]
[trusted(reason: "Bounds checked before pointer copy")]
```

- `[trusted]` may justify safe wrappers over unsafe code, but only for memory
  safety, not performance facts.

ZLinq/SIMD:

- ZLinq is blessed as first-class high-performance pipeline library.
- Builtin summaries for pinned supported ZLinq versions.
- System.Linq violations can get codefixes to ZLinq, never silent compiler
  rewrites.
- SIMD v1 is diagnostics/guidance only, no vector syntax.

Output required:

1. Short verdict: promising, confused, doomed, or needs major surgery.
2. Top 10 ways this spec could fail in the real systems world.
3. Top 10 ways it could fail in the .NET ecosystem.
4. Top 10 ways it could corrupt N# simplicity/purity.
5. At least 12 realistic pseudo-N# systems examples that stress the design.
6. For each example, say whether the spec handles it well, poorly, or
   ambiguously.
7. Identify features to cut from v1.
8. Identify missing features that real systems engineers would expect.
9. Propose a tighter v1 spec.
10. List unresolved questions the N# team must answer before implementation.

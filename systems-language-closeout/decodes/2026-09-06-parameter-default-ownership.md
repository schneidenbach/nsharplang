# Parameter metadata and constructor-default ownership

Selected from clean/pushed `7dc37d982`: the complete method/constructor parameter metadata and
constructor-default emission group. Move `DefineMethodParameterMetadata`,
`DefineConstructorParameterMetadata`, `HasParameterDefault`, `TrySetParameterDefault`,
`TryResolveStringEnumParameterDefault`, `TryResolveEnumParameterDefault`,
`CanUseConstructorDefaultAs`, and `TryEmitConstructorDefaultArgument`, including their shared
member-access default-kind constant. The two constructor-call methods consume the same enum-default
resolvers and belong with them. Every production caller routes directly to N#; no C# helper,
adapter, callback or fallback is added.

Preserve parameter ordinal/name/attribute order, missing array bounds, object type fallback,
partial metadata writes before failure, exact primitive/null/string behavior, and the distinct
null-string handling in metadata versus call emission. Keep source string-enum precedence, source
integer enum resolution, external enum eligibility and short/full-name repeated reflection reads.
Default eligibility, emitted IL and failure out slots remain N# decisions. Move necessary helpers
and state with callers; actual complete-source compilation must prove any SDK prerequisite.

Sol Max owns production and native canonical migration; Terra Max inventories canonical tests and
adds direct N# controls; Astra reviews, integrates, ratchets, verifies and pushes. Live C# assertions
must migrate and disappear; reuse native coverage and add only real gaps. Backend-only verification
uses focused dev/targeted checks, then a fresh non-VS-Code integration gate. Broader branch backlog
remains in `tasks/BRANCH-BACKLOG.md`.

Evidence root: `/private/tmp/nsharp-parameter-default-ownership-20260906`. Its baseline receipt
verifies the immutable compiler payloads against the previous accepted owner and records the fresh
447s gate: 590 unit, 7,860 canonical, 52 native projects, 12 throughput and 68 IL assemblies.
The previous accepted SDK seed remains installed. The selected area and compiler-wide goal stay open
until direct ownership, canonical assertions, required checks and push are complete.

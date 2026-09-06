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

Complete-source probes: r1/r2 first exposed reserved identifiers (`constructor` and output `type`);
renaming them to `constructorBuilder`/`resultType` preserves semantics and lets the full owner parse.
The r3 full build then proves the exact styled `Int32.TryParse` call is unmodeled. Original metadata
and both constructor-default methods require `NumberStyles.Integer`, invariant culture, and an
`out int`; substituting the two-argument call would change behavior. Sol is completing discovery
before grouping the necessary N# prerequisite; root preserves both feeds and the accepted seed
payloads and owns the fresh gate/setup/package probe.
Discovery-r4 compiles the entire owner with only the three styled-parse calls temporarily
substituted; the exact r3 source is restored byte-for-byte afterward. This proves the prerequisite
set is one exact Int32 static-call admission. No other builder/reflection/enum prerequisite is needed.
Temporary substitutions remain external evidence and are not product code.

Prerequisite seed accepted at `f95d8ad14`: fresh backend gate 449s, 590 unit / 7,861 canonical /
52 native projects / 12 throughput / 68 IL assemblies. Official setup and both feeds are verified;
all 10 Release tool payloads and all 12 SDK/cache payloads match. A normal minimal SDK project
compiled the exact committed native source plus an integer control and passed 2/2; emitted IL names
`Int32.TryParse(string, NumberStyles, IFormatProvider, int32&)`. Package SHA-256:
`2a0244f1ae94ee5c7e1f6256c7e9b8da46cc36d459e39dc5f139946d141adb7b`.
Receipt: `/private/tmp/nsharp-parameter-default-ownership-20260906/seed/acceptance.json`.
The complete owner and seven direct canonical controls now resume; the area remains open.

Exact full owner builds with the accepted seed (`full-owner-r6`). Root IL review confirms both
metadata loops preserve flags/name/ordinal and partial writes, exact boxed primitive constants,
all three invariant integer parser calls, source-before-runtime enum resolution, and separate
short/full-name runtime reflection reads. Constructor-call failure resets the output type before
work and assigns it only after emitted IL.

Seven new direct N# controls plus three existing selected controls pass 10/10 against one fresh
emitted assembly (`bss-controls-r7-partial-final.log`, `bss-controls-r8-all-no-build.log`). The fixture
uses DayOfWeek instead of an unsupported test-only enum spelling. Actual BCL observation corrected
two fixture expectations: Friday is 5; a parameter row whose constant was never set has Optional
(attribute 16), without HasDefault, while the untouched next row is unnamed and nonoptional. Both
method and constructor twins measured 4114/16/0. The assertions preserve these distinctions; temporary
observation code is removed. No production behavior change was required.

Integrated owner `05aa07853` (worker `e03bb1c9`) removes all eight C# definitions and their shared
constant. Thirteen production sites route directly into N#: eight method metadata declarations,
one constructor metadata declaration, two default-eligibility checks and two default IL emissions.
Surviving C# only supplies the existing builders/types/default columns, enum registry and IL stream
at these routes; its other compiler decisions remain separate debt. Existing canonical coverage
was already N#; no live C# parameter-default assertions remained to migrate.

Focused final owner controls pass 10/10 (seven new plus three existing). Unchanged native declaration
and constructor suites pass 121/121 and 7/7, matching verified baseline sources. Emitter shrinks
18,213→18,001 lines and 17,308→17,113 nonblank; all 380 other ratchet rows and epoch values unchanged.
New ratchet head `head-v1:52dd4405924e3517`. Final integration verification is pending.

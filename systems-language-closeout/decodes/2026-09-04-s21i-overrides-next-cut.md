# S2.1(i): method override declaration records

Read-only decode at `54faf94a`; implementation starts after S2.1(h) is integrated. Revalidate line
numbers at that tip. No i implementation or executed spelling result is claimed here.

There are fourteen actual `DefineMethodOverride` calls in `ColumnarIlEmitter.cs`: seven synchronous
iterator calls (3675 onward), four asynchronous iterator calls (3807 onward), and three ordinary
instance-method attachment families (4550–4559). The latter declaration envelope is 4495–4560;
that is not a prediction that all 66 lines can be deleted.

## Ordinary methods

Add source-ordinal override rows alongside `ColumnarMethodRows` and a per-method completion record.
N# owns the base-override request, two distinct deduplication sets, final method attributes, decline
payload and target application order. Ordinary and closed source-interface matches share one
`HashSet<MethodInfo>` equality domain; external matches use another. Preserve first occurrence and
duplicates across those domains.

Replace the host's attribute/list/set declarations with the N# pending record. Keep its existing
resolver loops, remove their `seen.Add` decisions, and feed successful handles into the record.
Completion calls the existing N# `ColumnarOverrideTargetResolver` only for a requested base override.
The existing-position validity check consumes its decline. `DefineMethod` reads final attributes;
shared parameter metadata stays next; one N# application call replaces all three host attachment
sites. Delete the unused C# `NSharpModifierOverride` constant. Add no C# branch, helper or replayer.

Resolution order is source interfaces, closed source interfaces, external interfaces, then the
explicit base target. Application order is base target first, then source, then external targets.
Literal attribute outcomes are ordinary **134**, interface implementation **486**, base override
**198**, and interface plus base override **230**: the last clears `NewSlot` and retains `Final`.

Preserve failure order: declaration/interface setup; return then parameter resolution; interface
matching then base-target failure; method creation; parameter/default metadata; attachments;
registration/body-job creation; whole-type interface completeness checks. Do not resolve targets
while building the initial plan or postpone attachments until every method exists.

`TryFindInterfaceMethod` (19249), `TryFindClosedInterfaceMethod` (19269),
`ExternalInterfaceMethodMatches` (19234), closed handles and exact signatures remain S2.2 debt.
The existing N# base resolver uses a public, nongeneric, virtual, nonfinal search; do not widen
protected-member or source-builder behavior in this ownership move.

## Iterators

`ColumnarIteratorPlanner` already publishes `MemberOverrides`, but production never reads those
strings. Tests alone do not establish ownership. Produce explicit records indexed by shape-member
ordinal, excluding constructors and async `MoveNextCore`.

Synchronous attachment order: `MoveNext`, generic `Current`, nongeneric `Current`, `Reset`, `Dispose`,
generic `GetEnumerator`, nongeneric `GetEnumerator`. Async order: `MoveNextAsync`, `Current`,
`DisposeAsync`, `GetAsyncEnumerator`.

Consume each record at the existing define → resolve → attach → emit-body point. Keep reflection
and closed-generic resolution at that point, with lookup names supplied by the record, and pass the
resolved handle into its N# executor. An eager target array changes lookup failure timing. Preserve
the declaration identity beside the handle for the later metadata writer; do not present runtime
handles as S2.2 completion.

## Verification

Before editing production, spell `DefineMethodOverride`, the `MethodBuilder` → `MethodInfo` argument,
and `HashSet<MethodInfo>` from N# under the pinned stage-0 SDK. The historical CLR capability probe
does not prove these spellings. Publish no SDK without a measured prerequisite.

Contract exact order, both deduplication domains, sparse/static exclusions, all four attribute
outcomes, invalid-base precedence, seven/four iterator identities, and constructor/core exclusion.
Emitted controls should cover inherited/diamond source interfaces, closed generic interfaces,
simultaneous base-plus-interface matching, nongeneric iterator dispatch, and malformed defaults
versus invalid override targets.

Existing witnesses: `tests/native/external-abstract-override` exercises `StringComparer` and
`Exception.ToString` through base types; its final `assert true` is not an invalid-target contract.
`interface-parameter-modifiers` exercises params/ref/out dispatch, `external-base-interface` covers
external and combined inheritance, and `iterators` covers synchronous/generic/instance/async paths.

Acceptance requires fourteen → zero C# attachment sites, measured host shrink, production use of
the rows, focused tests, observed ownership repin and fresh backend gate. Control-first whole-PE
parity must retain `MethodImpl` rows/order; body-only comparison is insufficient. h/i share the
plan constructor/build, tests, emitter constants and pass 0b, so implementation remains serialized.

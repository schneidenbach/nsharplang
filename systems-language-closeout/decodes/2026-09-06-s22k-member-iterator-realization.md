# S2.2(k): member iterator discovery and admission

`ColumnarIteratorRealization.EmitMember` now owns the complete type-member iterator decision path.
It receives the ten existing host inputs, derives the original builder/member label, rejects async and
generic instance cases at their established boundaries, discovers the first matching source input,
selects the readable field and callable method facts, analyzes the instance shape, and invokes the
accepted synchronous realization owner. The retained C# method has the same signature and only forwards
those inputs before recording the returned decline facts through the existing ambient trace.

The transfer preserves the observable order of the old driver. Static dispatch advances the supplied
ordinal before its additional `GetILGenerator` call. Instance discovery rejects a nonnull enclosing
generic map before reading program inputs, walks the live struct list to its first exact or ordinal
suffix match, and disposes that enumerator before the missing-input decision. Field selection retains
the short-circuit order of name length, PascalCase, exact handle lookup and late parallel canonical
lookup. Method selection retains five live `Name` reads, the non-static check, exact method lookup and
the overload-count check. Its enumerator is also disposed on a hit, miss or exception.

The accepted compiler cannot store an `IEnumerable<ColumnarStructInput>` local even though the exact
inherited interface conversion is valid. Two neutral acquisition helpers therefore accept the exact
`IEnumerable<T>` view and return its `IEnumerator<T>`; the decision loops stay in `EmitMember`. The
generated owner uses `IEnumerator<ColumnarStructInput>.Current` and
`IEnumerator<ColumnarFunctionInput>.Current`, with nongeneric movement and `IDisposable` cleanup inside
explicit `try`/`finally` regions. No collection is indexed, copied or materialized for discovery.

Shape analysis reads the original input facts and advances the ordinal at the old argument position.
A declined shape precedes the helper's `GetILGenerator` call. A supported instance reads the shared
empty type array before the enclosing builder and five fresh array snapshots, then calls `EmitSync`
with the established instance ordinal zero. The caller's earlier method-body `GetILGenerator` call is
unchanged; this ordering claim applies to the additional acquisition inside this driver.

The focused product build completed, and a forced test-enabled selection executed five existing
iterator realization and structural-identity controls with 5/5 passing. Compiled IL review verified
both exact generic `Current` slots, both cleanup handlers and first-hit leaves, the five method-name
reads, ordinal and generator timing, the ten-argument C# forward, and an unchanged accepted-j
realization suffix. The emitter changes by 6 additions and 57 deletions: a net reduction of 51 C# lines
and 3,115 bytes. Direct member-admission controls are integrated from the separately owned canonical
test slice; immutable parity, strict comparison and the full backend gate remain integration-owned.

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
The analyzer's closed runtime-generic relation now recognizes the corresponding exact
`IReadOnlyList<T>` to `IEnumerable<T>` inheritance while retaining its existing identity, arity and
variance checks. The nullable overload result uses an explicit default `NullReferenceException` trap
at the original `List<T>.Count` dereference phase, then reads the concrete list getter on the nonnull
path.

Shape analysis reads the original input facts and advances the ordinal at the old argument position.
A declined shape precedes the helper's `GetILGenerator` call. A supported instance reads the shared
empty type array before the enclosing builder and five fresh array snapshots, then calls `EmitSync`
with the established instance ordinal zero. The caller's earlier method-body `GetILGenerator` call is
unchanged; this ordering claim applies to the additional acquisition inside this driver.

Accepted at `137462ab1cf3898087304f6c4f524b4ea69bf478`: forced Sol selection 8/8 and the four
new member controls 4/4; compiled IL independently reviewed. The initial malformed-head test expectation
was localized and corrected at the classifier boundary; both value-variance negatives remain.
The emitter changes by 6 additions/57 deletions, a net reduction of 51 lines /51 nonblank /3,115 bytes.
The 94-image corpus and 2,184 native passes per arm match; current declarations 109/109 and image match j.
Strict old 260→candidate 258 removes only two intended NL202s while preserving 258 baseline findings.
The necessary analyzer prerequisite made this an IDE-affecting slice: a fresh VS Code-enabled gate
passed 593 unit /7,809 canonical /36 VS Code, and the rebuilt/reinstalled editor was visually verified.
The explicit null trap preserves default exception type/message and timing, not stack trace or
allocation-failure equivalence. [Acceptance proof](2026-09-06-s22k-parity-proof.md).

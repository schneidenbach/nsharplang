# S2.2(j): iterator realization ownership

Iterator declaration and realization now have one N# owner. `ColumnarIteratorRealization` owns the
synchronous and asynchronous state-machine declarations, iterator-specific canonical resolution,
member attachment, body-plan execution, factory construction and final publication. The two retained
C# methods preserve their established signatures and source scope; each forwards the original inputs
and immediately records an unsupported result through the existing decline path. They contain no
iterator declaration, canonical-resolution or IL-emission decisions.

The move preserves the old phase boundaries. Synchronous realization defines and registers its machine
before element resolution, while asynchronous realization resolves its element before defining the
machine. A direct machine generic-parameter lookup still wins before general admission, a failed later
admission retains its resolved out value, and the recursive guard still uses the dictionary's native
`ContainsValue` equality. Generic machines retain the real `GenericTypeParameterBuilder[]` result,
copy its elements into a fresh `Type[]` for construction, and separately retain the factory method's
MVAR owner and the actual rebound field's machine-VAR `FieldType`. The existing source `T[]` refusal is
unchanged. Both raw constructors and all eleven Apply/Build/GetIL/Execute attachment phases remain in
their prior order; a factory finishes before its machine is added to the synthesized-type list.

`ColumnarIteratorEmitContext` now carries the caller's structural type table unchanged. All fifteen
previous raw type-pool additions select their runtime companion at the original evaluation site and add
the selected key with that same table. Conditional boxing, cloning, captured-field and awaiter rows stay
conditional. Construction does not validate or replace a missing table, so an unused null table remains
accepted and the first reached keyed consumer preserves the failure boundary.

The focused contracts cover every consumed row and compare its table, interned key, emission identity,
runtime companion and validated runtime type. A heterogeneous captured `List<int>` field distinguishes
the factory argument from the machine element and state types. Dedicated controls exercise the async
`TaskAwaiter` row before baking, the reference-element no-box path, the no-capture/null-table path, and
a fresh companion corruption that is rejected before IL or local mutation. The fifteen existing context
fixtures now supply their actual table explicitly.

The final forced test-enabled BootstrapServices estate executed 7,801/7,801 tests. The final N# format
check and `git diff --check` were clean, and the integration strict preview retained the accepted 258
findings across 434 files with no new diagnostic in the N# owner. The emitter changed by 15 additions
and 305 deletions: a net reduction of 290 C# lines and 18,756 bytes. Full immutable parity and the product
gate remain integration-owned.

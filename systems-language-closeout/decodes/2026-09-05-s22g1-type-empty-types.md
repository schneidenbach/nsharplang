# S2.2(g1): `System.Type.EmptyTypes` external static-field binding

Implementation baseline: `f54385d5d6b32efb0cb47e5761931bb63af707f4`.

## Boundary

`ColumnarExternalBindingPlans.GetStaticMemberPlan` adds one exact field plan:
`Type.EmptyTypes` and `System.Type.EmptyTypes` map to the existing `Field` plan with declaring
identity `System.Type, System.Private.CoreLib` and value identity
`System.Type[], System.Private.CoreLib`. It uses the existing semantic-owner resolution and static
field planner unchanged. No generic `Array.Empty<T>()` call route, reflection fallback, private
singleton, collection admission, or source-owner bypass is added.

The canonical contracts pin both owner spellings, the exact field/value identities, rejection of
nearby members and owners, and semantic rollback when either a local parameter or source class
shadows `Type`. The planner contract verifies one `ldsfld` field row and no method row.

The durable native contract reads the field through short, qualified, inferred-local, and typed-local
out-parameter forms. It invokes the BCL `Array.Empty<Type>()` generic method only through a test-side
reflection oracle, then asserts every emitted field result is that exact object. The native IL records
`ldsfld class System.Type[] System.Type::EmptyTypes` in all four helpers; the out helper stores that
same value through its `Type[]&` parameter.

## Compatibility and focused evidence

The worker's frozen pre compiler was `70a84bc72`, retained at
`/private/tmp/nsharp-023-s22g-proof-20260905/cli/pre/Cli.dll`; its final fixture decline trace is
`/private/tmp/nsharp-s22g-controls-logs/type-empty-types/final/frozen-pre-native.stderr`. The original
worker decode mislabeled that compiler f543. Root independently rebuilt the actual accepted f543
compiler and replayed the exact final fixture: it also declines before any test runs at
`TypeEmptyTypesShortRead`'s return expression. The immutable f243 compiler passes1/1 on that same source.
The authoritative root commands, dependency hashes, streams and four-field-read IL are in
`/private/tmp/nsharp-023-s22g-seeded-proof-20260905/g1-capability/verdict.json`. These are measured
missing-binding declines, not executed-test failures.

The fresh compiler built from this source passes the full native `columnar-emit-facts` project,
**105 passed, 0 failed**, and the forced BootstrapServices estate, **7,759 passed, 0 failed**. The
canonical formatter and native formatter each report zero changed files; `git diff --check` passes.
The exact commands, source hashes, generating CLI dependency manifest, generated native-image hash,
and IL text are recorded in
`/private/tmp/nsharp-s22g-controls-logs/type-empty-types/final/receipt.json`.

The coordinator owns immutable pre/post corpus comparison, fixed-corpus parity, fresh gate, SDK
publication and the live SDK field probe. This cut does not change C# or add a general field-binding
capability.

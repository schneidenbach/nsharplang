# S2.2(l0): catalog reference array prerequisite

S2.2(l) is held at the existing-seed spelling boundary. The accepted source is
`31a0743d6f6f5f233c0e5e4c1def5eca1430540c`; its complete entry-point block remains unchanged.
The N# driver draft is preserved separately and has not replaced the production C# owner.

## Observed refusal

The exact parameter `Dictionary<string, Type>[]` in
`ColumnarEntryPointRealization.TryEmit` fails declaration emission with
`emit.declaration.method-param`. `./scripts/dev.sh EntryPoint` exited 1 and executed zero tests.
The four source files, argv, working directory, output and hashes are retained under
`/private/tmp/nsharp-s22l-executor-logs/stage0/attempt-01/`; receipt SHA-256
`a76bd28892b32472ca977bfa5baa1128436afd899be460edf5c921f172a25940`.

`ColumnarCanonicalTypeResolver` resolves the inner Dictionary type, but its array arm requires
`ColumnarTypeOfPlanner.IsSupportedElementType`. The final `IsSupportedType` array check repeats
that requirement. The element predicate admits selected primitives, reflection types and source
shapes, but omits ordinary closed catalog reference types. Qualification does not change this gate.
Changing the parameter to an interface would change array dispatch and failure behavior, so the
driver retains its exact array input.

## Connected N# correction

After the existing element cases and SZ-array recursion, admit a reference type only when
`!valueType.get_IsValueType() && IsSupportedCatalogType(valueType)`. The existing catalog predicate
requires the selected assembly to reproduce the exact type identity and excludes element shapes,
open generics and builder-bound closures. Preserve all existing source-builder and generic-parameter
allowances; this prerequisite does not revise them.

The rule intentionally admits SZ arrays of already supported catalog reference classes and
interfaces, including closed Dictionary, List and Queue types. Existing allocation, reference load,
reference store and array-loop lowerings already use the actual element type. Do not add a
Dictionary-specific name exception or broaden the ordinary value-type array surface. Runtime
pointer/byref, void, open-definition, rank-two and previously excluded value-type controls remain.
Identity controls must distinguish a forged catalog identity from a real foreign catalog type.

## Acceptance and order

1. Implement the element rule and canonical assertions in N#. Preserve the original refusal
   evidence and identify every existing limitation assertion intentionally changed by this feature.
2. Prove exact canonical array resolution and actual allocation, indexed read/write and iteration
   with genuine catalog reference elements. Retain exact identity, open-type and value-type boundaries.
3. Commit focused-green code, compare the fixed 94-image corpus and strict diagnostics, and run a
   fresh backend product gate. No analyzer/LSP behavior change is planned; re-evaluate the gate scope
   if implementation changes that assumption. C# and the ownership ratchet remain unchanged.
4. The coordinator publishes and verifies the SDK only after the prerequisite is committed and
   gated. Verify packaged/live-cache bytes and an actual SDK-built exact-array signature and runtime
   control. Existing legacy validation remains bootstrap debt.
5. Resume the complete [S2.2(l) entry-point cut](2026-09-06-s22l-entrypoint-next-cut.md) against that
   verified seed. A later body-spelling refusal is a separate measured fact, not proof that the array
   prerequisite failed or that the complete driver already works.

Tasks 015/021/022/023 and the full goal remain open. This prerequisite is required capability work;
it is not completion of entry-point ownership.

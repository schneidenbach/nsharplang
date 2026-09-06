# S2.2(l0): catalog reference array admission

The entry-point realization owner requires its existing host input as the exact CLR type
`Dictionary<string, Type>[]`. The accepted compiler resolved the closed dictionary but rejected it
as an SZ-array element, so declaration emission stopped at `emit.declaration.method-param` before a
test could execute. The retained failure source and launch receipt are under
`/private/tmp/nsharp-s22l-executor-logs/stage0/attempt-01/`.

`ColumnarTypeOfPlanner.IsSupportedElementType` now admits a non-value type through the existing
`IsSupportedCatalogType` identity gate after its established scalar, source-shape, nullable and
jagged-array cases. That gate requires the selected assembly to reproduce the exact closed type and
continues to reject element shapes, open generics and builder-bound closures. This is the shared
reference-element rule used by declaration, allocation, indexed access, iteration, params and Array
API planning; it is not an entry-point-only exception or a name-based collection allowance.

The existing element-surface contract now records `List<int>` and the catalog `Queue<int>` as valid
reference elements and retains an open `List<>` rejection. Value-type exclusions such as `decimal`
and `DateTime`, rank-two arrays, pointers, byrefs, generic parameters and source builders retain
their prior rules. Separately owned controls exercise exact canonical resolution and runtime array
operations with genuine catalog reference types as part of prerequisite acceptance.

The focused compiler build succeeded, and the forced test-enabled BootstrapServices estate passed
7,809/7,809 with no skips. The candidate compiler payload and its generating command are frozen at
`/private/tmp/nsharp-s22l0-executor-logs/candidate-payload-01/`. The coordinator owns fixed-corpus
parity, strict diagnostics, the fresh product gate and SDK publication before S2.2(l) resumes.

# S2.1(h): P/Invoke declaration records

Read-only plan at the S2.1(g) integration tree (`4f2a8e63`). No h implementation or test result is
claimed. `ColumnarIlEmitter.cs` has one `DefinePInvokeMethod` site (4435); its bodyless-native branch
is 4423–4450. The `NSharpModifierNativeImport` constant at 149 has no other use.

## N# ownership cut

Add a P/Invoke family to `ColumnarDeclarationPlan`, retaining the existing struct/method ordinals.
Use the existing `ColumnarMethodRows` result for base attributes. Selected rows carry validity and
decline data, method/library/entry-point names, method attributes, managed and unmanaged calling
conventions, charset, and the implementation-flag mask. Ordinary methods keep their ordinal slots
without being selected.

Move these remaining decisions out of C#:

- Native modifier bit 131072 is present; library/entry point are neither null nor empty; method type
  parameter count is zero; the method is not async. Reuse the existing N#
  `ColumnarStructMethodFlagIsNativeImport` / `ColumnarStructNativeImportModifierFlag` owner in
  `CompilerServices/ColumnarParserKernels.nl` instead of duplicating its bit value in a new owner.
- Preserve base method flags and OR `PinvokeImpl` 8192: ordinary static imports use 8342, operator
  names retain `SpecialName` and use 10390.
- Managed `Standard` is 1; unmanaged `Cdecl` is 2; `Ansi` is 2.
- Merge `PreserveSig` 128 into the current implementation flags in N#; do not overwrite other bits.
- Preserve `emit.declaration.native-import`, its exact message and its owner name.

Consume rows with the existing host branch and call; add no C# branch, helper or replayer. Remove the
now-unused native modifier constant. Build method rows once and share that result with the P/Invoke
planner rather than recomputing their policy.

Library/entry-point parsing is already N# owned by `ParseColumnarNativeImportInfoInto` in
`CompilerServices/ColumnarParserKernels.nl` (9576). The library is mandatory and nonempty; EntryPoint
defaults to the method name. There is no library-name fallback or extension synthesis to move.

## Ordering and boundaries

Record invalidity without throwing during planning. Consume the decline at the current branch,
after return and parameter resolution, preserving which error wins when more than one shape is
invalid. Preserve overload registration and omission of the managed-body job. Do not add a new
restriction on generic declaring types.

`DefineMethodParameterMetadata` remains shared declaration debt: one-based positions, out/optional
flags and null/bool/int/string/enum constants. Unsupported defaults currently fail after method
creation. Return/parameter resolution, including allowed byrefs, also precedes P/Invoke selection.
This slice must preserve those paths and must not claim their retirement.

The analyzer recognizes DllImport and LibraryImportAttribute, but this columnar parser requires the
exact LibraryImport token. Preserve that boundary in this ownership slice.

## Evidence to establish

Existing corpus witnesses are proof 26-native-device-handle (`c` library, explicit open/close entry
points, successful `/dev/null` execution) and proof 27-c-library-cli (default Hash64 entry point,
array/out parameters, expected missing fast_hash loader result). Recheck their emitted metadata and
actual outcomes; normalized whole-PE comparison retains the relevant tables and flags.

Add N# contracts for mixed/sparse ordinals, ordinary-method exclusion, each validity predicate,
null/empty/whitespace names, explicit/default entry points, literal metadata words, preservation of
unrelated implementation bits, and stable captured names. An emitted optional parameter and an
invalid-default control cover shared metadata behavior absent from the current native witnesses.
Run focused evidence, control-first corpus parity, observed ownership repin, and the fresh backend
integration gate at the checkpoint. No SDK publication is implied unless an actual spelling probe
establishes a new prerequisite.
